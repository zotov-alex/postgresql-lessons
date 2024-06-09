 
# Домашнее задание №5
В рамках данного задания выполняется настройка резервного копирования postgresql при помощи pg_probackup.

---
## Подготовка
Задание будет выполняться на трёх локальных виртуальных машинах:
1. мастер;
2. реплика;
3. сервер резервного копирования.

Далее, в ходе работы сервера буду называть как в списке выше.

Перед продолжением стоит их подготовить, во избежание путаницы - переименовать хосты (особенно, если машины создавались из одного шаблона), при помощи команды:
```
wr@bubuntu20042:~$ sudo hostnamectl set-hostname master
```
Также, новое имя хоста требуется указать в /etc/hosts. Для упрощения будущей настройки стоит заодно добавить в /etc/hosts имена остальных виртуальных машин, если нет возможности внесения изменений в конфигурацию DNS-сервера. Пример добавленных строк на мастере:
```
127.0.0.1 master
192.168.122.188 replica
192.168.122.101 pgprobackup
```
После перезапуска сессии пользователя (например из-за переподключения к SSH) в терминале будет отображаться новое имя сервера.

На мастер и реплику PostgreSQL установлен ранее из репозитория PGDG, версия - 15.7.

### Репликация
Планируется попытка настройки резервного копирования с реплики БД, например - для снижения нагрузки на мастер. Для этого следует настроить репликацию. Предполагается постоянная работа реплики, поэтому при использовании слотов репликации проблем с утечкой занятого дискового пространства не будет.

На (предполагается что полностью настроенном и доступном) мастере создан пользователь с правом репликации, при помощи SQL-запроса:
```
CREATE USER replicator WITH REPLICATION ENCRYPTED PASSWORD 'secret';
```
Далее для разрешения подключения к postgresql с других машин для репликации, на мастере и реплике в /etc/postgresql/15/main/pg_hba.conf добавлена строка:
```
host    replication     replicator      192.168.122.0/24        scram-sha-256
```
Для упрощения указан диапазон IP, в продуктивных средах стоит добавлять несколько строк с индивидуальными IP только тех машин, с которых планируется подключаться (в том числе для репликации). После добавления строк при запущенной службе PostgreSQL следует перечитать конфигурацию, например, при помощи SQL-запроса:
```
SELECT pg_reload_conf();
```
Далее, на реплике следует остановить сервис PostgreSQL, если он был запущен, очистить каталог данных (по умолчанию - `/var/lib/postgresql/15/main/*`), и сделать полную копию данных мастера, например, при помощи команды:
```
sudo -u postgres pg_basebackup -h master -U replicator -p 5432 -D /var/lib/postgresql/15/main -Fp -Xs -P -R
```
В каталоге данных на реплике появился файл `standby.signal`, говорящий о том что сервер работает в режиме резерва (то есть, реплики). Также, в postgresql.auto.conf на реплике появился параметр primary_conninfo с данными для подключения к мастеру.
Так как решено использовать слот репликации, следует создать его на мастере, при помощи SQL-запроса:
```
SELECT pg_create_physical_replication_slot('standby_slot');
```
...и добавить информацию о нём в postgresql.conf (или postgresql.auto.conf) на реплике:
```
primary_slot_name = 'standby_slot'
```
После внесенных изменений можно запустить службу PostgreSQL на реплике, и проверить статус репликации на мастере:
```
postgres=# SELECT * FROM pg_stat_replication;
-[ RECORD 1 ]----+------------------------------
pid              | 4815
usesysid         | 16388
usename          | replicator
application_name | 15/main
client_addr      | 192.168.122.188
client_hostname  | 
client_port      | 33698
backend_start    | 2024-05-31 09:01:47.885823+05
backend_xmin     | 
state            | streaming
sent_lsn         | 0/3000148
write_lsn        | 0/3000148
flush_lsn        | 0/3000148
replay_lsn       | 0/3000148
write_lag        | 
flush_lag        | 
replay_lag       | 
sync_priority    | 0
sync_state       | async
reply_time       | 2024-05-31 09:02:48.034217+05

postgres=# SELECT * FROM pg_replication_slots;
-[ RECORD 1 ]-------+-------------
slot_name           | standby_slot
plugin              | 
slot_type           | physical
datoid              | 
database            | 
temporary           | f
active              | t
active_pid          | 4815
xmin                | 
catalog_xmin        | 
restart_lsn         | 0/3000148
confirmed_flush_lsn | 
wal_status          | reserved
safe_wal_size       | 
two_phase           | f
```
По выводу этих запросов видно что к мастеру подключена реплика, и активен созданный слот репликации. Заодно, можно создать некоторое количество тестовых данных:
```
postgres=# CREATE TABLE testtable (id serial, data text);
CREATE TABLE
postgres=# INSERT INTO testtable select nextval('testtable_id_seq'::regclass), md5(generate_series(1,1000000)::text);
INSERT 0 1000000
```
Созданные данные также будут присутствовать на реплике.

### Подготовка pg-probackup
Резервное копирование будет выполняться с помощью `pg-probackup`, поэтому требуется установить эту утилиту на все три сервера по [документации](https://postgrespro.github.io/pg_probackup/#pbk-install).

На сервере резервного копирования требуется создать пользователя ОС, от имени которого будет выполняться резервное копирование.
```
sudo useradd -m -d /home/backup_user -s /bin/bash backup_user
```
После установки PostgreSQL на мастер и реплику и создания пользователя на сервере резервного копирования, необходимо создать возможность аутентификации без пароля для пользователей backup_user и postgres на соответствующих машинах - обменяться SSH-ключами любым удобным способом.

На сервере резервного копирования также требуется создать директорию для хранения резервных копий (например, `/opt/backup_db`), сделать пользователя `backup_user` её владельцем, и добавить переменную окружения, указывающую на эту директорию:
```
echo "BACKUP_PATH=/opt/backup_db">>~/.bash_profile
echo "export BACKUP_PATH">>~/.bash_profile
```

Созданную на сервере резервного копирования директорию теперь требуется инициализировать при помощи команды:
```
pg_probackup-15 init
```
Информация о пути к месту хранения резервных копий взята из переменной окружения BACKUP_PATH, если эту переменную окружения не назначать - потребуется добавить опцию `--backup-path` и указать путь в ней. При выполнении в `/opt/backup_db` должны появиться папки `backups` и `wal`.

### Подготовка СУБД к резервному копированию.

Для резервного копирования можно использовать уже готового суперпользователя `postgres` и системную БД `postgres`, но этот вариант нельзя считать безопасным, лучше создать отдельную БД и пользователя в PostgreSQL. SQL-запросы для создания пользователя и БД на мастере:
```
CREATE DATABASE backupdb;

\c backupdb
BEGIN;
CREATE ROLE backup WITH LOGIN;
GRANT USAGE ON SCHEMA pg_catalog TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.current_setting(text) TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.set_config(text, text, boolean) TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.pg_is_in_recovery() TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.pg_backup_start(text, boolean) TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.pg_backup_stop(boolean) TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.pg_create_restore_point(text) TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.pg_switch_wal() TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.pg_last_wal_replay_lsn() TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.txid_current() TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.txid_current_snapshot() TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.txid_snapshot_xmax(txid_snapshot) TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.pg_control_checkpoint() TO backup;
COMMIT;
```
Примечание:
По странному стечению обстоятельств функции `pg_catalog.pg_backup_start` и `pg_catalog.pg_backup_stop` так называются только начиная с верии PostgreSQL 15. Для PostgreSQL 14 и старее их название - соответственно `pg_catalog.pg_start_backup` и `pg_catalog.pg_stop_backup`.

Требуется разрешить возможность подключения сервера резервного копирования к СУБД. Для этого в /etc/postgresql/15/main/pg_hba.conf добавлены строки:
```
# pg_probackup entries
host    backupdb        backup          192.168.122.0/24        scram-sha-256
host    replication     backup          192.168.122.0/24        scram-sha-256
```

При настройках по умолчанию, реплика PostgreSQL не может архивировать WAL-логи. Для включения возможности отправки WAL-логов с реплики, требуется выполнить некоторые дополнительные настройки при помощи SQL-запросов, и заодно установить корректную команду архивирования логов для отправки их на сервер резервных копий:
```
ALTER SYSTEM SET archive_mode TO 'always';
ALTER SYSTEM SET hot_standby TO 'on';
ALTER SYSTEM SET wal_level TO 'replica';
ALTER SYSTEM SET archive_timeout TO '180';
ALTER SYSTEM SET archive_command TO 'pg_probackup-15 archive-push -B /opt/backup_db --instance=db1-replica --wal-file-path=%p --wal-file-name=%f --remote-host=192.168.122.101 --remote-user=backup_user --compress';
```
archive_mode = always - даёт возможность архивирования логов на standby-нодах;
archive_timeout = 180 - (в секундах) таймаут сохранения незаполненных WAL-логов, обязательно должен быть меньше значения archive-timeout инстанса pg_probackup (по умолчанию 5 минут).  

После установки этих параметров, требуется перезапустить СУБД на реплике.

---
## Резервное копирование и восстановление

Создание первой резервной копии, при помощи команды на сервере резервного копирования, выполняется от имени пользователя backup_user:
```
pg_probackup-15 backup --instance=db1-replica -j2 --progress -b FULL --compress --stream --delete-expired
```

Эта команда создаст полную копию СУБД с реплики. Посмотреть список созданных резервных копий можно при помощи команды:
```
backup_user@pgprobackup:~$ pg_probackup-15 show --instance=db1-replica
=======================================================================================================================================
 Instance     Version  ID      Recovery Time           Mode  WAL Mode  TLI    Time  Data    WAL  Zratio  Start LSN  Stop LSN    Status 
=======================================================================================================================================
 db1-replica  15       SETBQR  2024-06-09 17:23:05+05  FULL  STREAM    1/0  2m:43s   39MB  16MB    2.45  0/2E000028  0/2E00BE60  OK 
```
В списке видно одну резервную копию, созданную в режиме Full.

Для проверки инкрементного резервного копирования добавим некоторое количество данных в БД, при помощи запроса к мастеру:

```
CREATE TABLE testtable2 (id serial, data text);
INSERT INTO testtable2 select nextval('testtable_id_seq'::regclass), md5(generate_series(1,100000)::text);
```
После этого запроса в БД появится новая таблица с набором тестовых данных. Попробуем выполнить бекап в режиме PAGE (только изменения):

```
pg_probackup-15 backup --instance=db1-replica -j 2 --progress -b PAGE --compress
```
После чего в списке резервных копий появится ещё одна резервная копия, созданная из WAL-логов:
```
backup_user@pgprobackup:~$ pg_probackup-15 show --instance=db1-replica
=======================================================================================================================================
 Instance     Version  ID      Recovery Time           Mode  WAL Mode  TLI   Time   Data   WAL  Zratio  Start LSN   Stop LSN    Status 
=======================================================================================================================================
 db1-replica  15       SETBY8  2024-06-09 17:27:35+05  PAGE  ARCHIVE   1/1  2m:52s  198kB  16MB   34.58  0/2E000028  0/2F014ED8  OK     
 db1-replica  15       SETBQR  2024-06-09 17:23:05+05  FULL  STREAM    1/0  2m:43s   39MB  16MB    2.45  0/2E000028  0/2E00BE60  OK 
```

**Сымитируем аварию, при помощи SQL-запроса на мастере:**
```
DROP TABLE testtable;
```
Либо, вместо штатной имитации нештатного внесения изменения в данные, можно каким-либо образом повредить файлы в директории данных мастера, или вообще удалить (пересоздать) виртуальную машину, в таком случае дополнительно может потребоваться только подготовка новой виртуальной машины с аналогичной версией PostgreSQL. В рамках выполнения задания достаточно удалить таблицу на мастере СУБД.

Для восстановления резервной копии, созданной с реплики, на мастер (подразумевая что сервер исправен, доступен, на него установлена СУБД, но нет требуемых данных), требуется:  
1. остановить реплику (если она ещё доступна);
2. очистить каталог данных на мастере (если он ещё не очищен);
3. выполнить восстановление из резервной копии при помощи команды на сервере резервного копирования, с указанием требуемой точки восстановления (в нашем случае - `SETBY8`, которая отображалась после создания последней страничной резервной копии):

```
time pg_probackup-15 restore --instance=db1-replica -D /var/lib/postgresql/15/main -i SETBY8 -j 2 --recovery-target='immediate' --progress --remote-proto=ssh --remote-host=192.168.122.236  --archive-host=192.168.122.101 --archive-user=backup_user --log-level-console=log --log-level-file=verbose --log-filename=restore_imm.log
```
После восстановления, можно запустить СУБД на мастере. Если СУБД запустилась, проверим, присутствует ли на месте "случайно" удалённая таблица `testtable`:
```
postgres=# \dt
             Список отношений
 Схема  |    Имя     |   Тип   | Владелец 
--------+------------+---------+----------
 public | testtable  | таблица | postgres
 public | testtable2 | таблица | postgres
(2 строки)
```
Данные на месте, следовательно - можно вводить СУБД в работу, при помощи запроса:
```
SELECT pg_wal_replay_resume();
```
После этого, требуется повторно подключить реплику, как уже было описано выше, и удостовериться в том что создание новых резервных копий работает корректно. Также, после этого на мастере стоит устранить настройки, которые производились ранее только на реплике (отключить `archive_mode` т.к. реплика работала на физическом слоте, и т.п.), и убрать следы восстановления из резервной копии из postgresql.auto.conf.

При использовании pg_probackup в работе, создание резервных копий есть смысл автоматизировать при помощи cron, таймеров systemd, или другими способами, с требуемой регулярностью.