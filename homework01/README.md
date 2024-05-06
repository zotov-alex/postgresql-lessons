 
# Домашнее задание №1
В процессе выполнения первого домашнего задания требуется создать инстанс виртуальной машины, воспользовавшись услугами одного из облачных провайдеров (например, Yandex Cloud). В рамках именно первого урока работа будет проводиться только на одной виртуальной машине, и специфичных для геораспределённости задач в данном случае не стоит, работа выполнена на локальной виртуальной машине. *Некоторый опыт работы с облачным хостингом уже имеется.*

![Образец интерфейса Yandex Cloud](./yc-screenshot.png?raw=true)

---
## Начало работы
Виртуальная машина создана средствами virt-manager (qemu/kvm), путём клонирования ранее созданной ВМ, ОС - Ubuntu 20.04. ОС на хосте (он же рабочее место) - Debian 12.

Для удобства подключения к командной оболочке виртуальной машины на неё добавлен открытый ключ SSH:

```
azotov@main:~$ ssh-copy-id -i .ssh/id_rsa.pub user@192.168.122.236
/usr/bin/ssh-copy-id: INFO: Source of key(s) to be installed: ".ssh/id_rsa.pub"
/usr/bin/ssh-copy-id: INFO: attempting to log in with the new key(s), to filter out any that are already installed
/usr/bin/ssh-copy-id: INFO: 1 key(s) remain to be installed -- if you are prompted now it is to install the new keys
user@192.168.122.236's password: 

Number of key(s) added: 1

Now try logging into the machine, with:   "ssh 'user@192.168.122.236'"
and check to make sure that only the key(s) you wanted were added.
```

После добавления ключа, при подключении к виртуальной машине не будет запрашиваться пароль пользователя.

Все дальнейшие команды выполнены на виртуальной машине.
APT-репозиторий PGDG настроен по документации с сайта [postgresql.org](https://www.postgresql.org/download/linux/ubuntu/). Использоваться будет версия 15, поэтому СУБД установлена командой:

`user@ubuntu20042:~$ sudo apt install postgresql-15`

При установке на Ubuntu (равно как и на других Debian-based дистрибутивах) кластер PostgreSQL инициализируется и запускается автоматически после установки пакета. При необходимости можно проверить статус службы PostgreSQL:
```
user@ubuntu20042:~$ systemctl status postgresql@15-main.service 
● postgresql@15-main.service - PostgreSQL Cluster 15-main
     Loaded: loaded (/lib/systemd/system/postgresql@.service; enabled-runtime; vendor preset: enabled)
     Active: active (running) since Sun 2024-05-05 22:30:47 +05; 4min 6s ago
    Process: 5556 ExecStart=/usr/bin/pg_ctlcluster --skip-systemctl-redirect 15-main start (code=exited, stat>
   Main PID: 5574 (postgres)
      Tasks: 6 (limit: 2256)
     Memory: 20.1M
     CGroup: /system.slice/system-postgresql.slice/postgresql@15-main.service
             ├─5574 /usr/lib/postgresql/15/bin/postgres -D /var/lib/postgresql/15/main -c config_file=/etc/po>
             ├─5575 postgres: 15/main: checkpointer
             ├─5576 postgres: 15/main: background writer
             ├─5578 postgres: 15/main: walwriter
             ├─5579 postgres: 15/main: autovacuum launcher
             └─5580 postgres: 15/main: logical replication launcher
```
---
## Изоляция транзакций
Для изучения работы с изоляцией транзакций требуется в двух окнах терминала подключиться к PostgreSQL при помощи консольного клиента psql с логином postgres. Пока не задан пароль пользователя и не произведены настройки для разрешения удалённого подключения - можно подключиться с самой виртуальной машины, от имени одноименного пользователя в ОС:
```
user@ubuntu20042:~$ sudo -u postgres psql
```
PostgreSQL не имеет штатной возможности отключения автофиксации на уровне сервера, но можно инициировать изолированные транзакции средствами клиента СУБД. Для отключения автофиксации изменений для одной транзакции в одном из открытых окон с командной строкой PostgreSQL выполнена команда:
```
postgres=# BEGIN;
```
В рамках начатой транзакции создана и наполнена таблица persons при помощи SQL-запроса:
```
CREATE TABLE persons(id serial, first_name text, second_name text);
INSERT INTO persons(first_name, second_name) values('ivan', 'ivanov');
INSERT INTO persons(first_name, second_name) values('petr', 'petrov');
```
Изменения зафиксированы командой:
```
postgres=*# COMMIT;
```
Проверен текущий уровень изоляции транзакций:
```
postgres=# SHOW TRANSACTION ISOLATION LEVEL;
 transaction_isolation 
-----------------------
 read committed
(1 строка)
```

При помощи команды `BEGIN;` в двух окнах с запущенным клиентом psql начаты новые транзакции. В первом окне таблица persons дополнена данными и **не выполнена** фиксация:
```
INSERT INTO persons(first_name, second_name) values('sergey', 'sergeev');
```
При этом при попытке прочитать содержимое таблицы во втором окне новой строки не видно:
```
postgres=*# SELECT * FROM persons;
 id | first_name | second_name 
----+------------+-------------
  1 | ivan       | ivanov
  2 | petr       | petrov
(2 строки)
```
При помощи команды COMMIT; зафиксированы изменения в первом окне. После этого в транзакции, запущенной во втором окне, уже видны изменения:
```
postgres=*# SELECT * FROM persons;
 id | first_name | second_name 
----+------------+-------------
  1 | ivan       | ivanov
  2 | petr       | petrov
  3 | sergey     | sergeev
(3 строки)
```
Новые данные видны так как установлен уровень изоляции транзакций по умолчанию - READ COMMITED, при котором простой запрос SELECT видит данные, которые были зафиксированы в других транзакциях до начала самого запроса.
После проверки содержимого таблицы транзакция во втором окне также зафиксирована командой `COMMIT;`.

---
Другой, более высокий уровень изоляции транзакций в PostgreSQL - REPEATABLE READ. Для начала таких транзакций в двух окнах клиента psql выполнены команды:
```
postgres=# BEGIN;
BEGIN
postgres=*# SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
SET

```
Далее, в первой сессии создана ещё одна строка в таблице, **изменения не зафиксированы**:
```
INSERT INTO persons(first_name, second_name) values('sveta', 'svetova');
```
После этого при чтении содержимого таблицы во втором окне новая строка не видна:
```
postgres=*# SELECT * FROM persons;
 id | first_name | second_name 
----+------------+-------------
  1 | ivan       | ivanov
  2 | petr       | petrov
  3 | sergey     | sergeev
(3 строки)
```
При помощи команды `COMMIT;` завершена транзакция в первом окне. После этого при выполнении селекта во втором окне изменения также не видны:
```
postgres=*# SELECT * FROM persons;
 id | first_name | second_name 
----+------------+-------------
  1 | ivan       | ivanov
  2 | petr       | petrov
  3 | sergey     | sergeev
(3 строки)
```
Изменения не видны, потому что при уровне изоляции REPEATABLE READ при выполнении SQL-запроса в рамках транзакции видны только те изменения, которые были зафиксированы до начала транзакции.

Далее, после завершения транзакции при помощи команды `COMMIT;` во втором окне, изменения уже видны:
```
postgres=*# COMMIT;
COMMIT
postgres=# SELECT * FROM persons;
 id | first_name | second_name 
----+------------+-------------
  1 | ivan       | ivanov
  2 | petr       | petrov
  3 | sergey     | sergeev
  4 | sveta      | svetova
(4 строки)
```
