 
# Домашнее задание №4
В рамках данного задания требуется повысить производительность СУБД PostgreSQL на имеющемся оборудовании. Работа будет проводиться на виртуальной машине, созданной при выполнении третьего домашнего задания, так как подготовленная виртуальная машина подходит для экспериментов с типом хранилища (в моём случае примонтированный диск можно перенести на механический HDD для симуляции медленной дисковой системы).

---
## Подготовка
PostgreSQL установлен ранее из репозитория PGDG, версия - 15.7. Для корректности тестирования производительности, дополнительный накопитель, который был подключен к виртуальной машине и примонтирован в папку /mnt/pgdata, был перенесён на отдельный жёсткий диск, более нигде не используемый на хосте.
Тестирование производительности будет выполняться с хоста, на котором запущена виртуальная машина, чтобы минимизировать влияние сети на тест. Для этого на хост установлен клиент PostgreSQL и пакет postgresql-contrib, версия - 15.6 из основного APT-репозитория Debian Bookworm.

По умолчанию PostgreSQL, установленный на Ubuntu, принимает подключения только от localhost. Для включения возможности удалённого подключения к СУБД, выполнено локальное подключение к консоли при помощи `psql`, и выполнен SQL-запрос:
```
postgres=# ALTER SYSTEM SET listen_addresses TO '*';
```
После выполнения этого запроса СУБД перезапущена командой:
```
wr@bubuntu20042:~$ sudo systemctl restart postgresql
```
Для открытия возможности аутентификации удалённым пользователям, в файл /etc/postgresql/15/main/pg_hba.conf добавлена строка:
```
host    all             all             192.168.122.0/24        scram-sha-256
```
Эта эапись открывает всем пользователям в СУБД возможность аутентификации всем имеющимся БД из сети 192.168.122.0/24 (диапазон, по умолчанию выдаваемый гипервизором ВМ), в том числе IP хоста - 192.168.122.1.

Для тестирования производительности созданы пользователь и база данных:
```
postgres=# CREATE USER pgbench ENCRYPTED PASSWORD 'pgbemch';
CREATE ROLE
postgres=# CREATE DATABASE pgbench OWNER pgbench;
CREATE DATABASE
```
Выполнена инициализация БД для тестирования производительности, при помощи команды на хосте:
```
wr@main:~$ pgbench -i -F 100 -s 400 -h 192.168.122.188 -U pgbench pgbench
```
* `-F 100` - фактор заполнения, 100 - значение по умолчанию.
* `-s 400` - множитель фактора заполнения: в тестовых таблицах создаётся 100 * 400 = 40000 строк.
---
## Тестирование производительности с настройками СУБД по умолчанию
Тестирование запускается на хосте командой:
```
wr@main:~$ pgbench -c 50 -t 100 -j 4 -h 192.168.122.188 -U pgbench pgbench
```
* `-c 50` - количество эмулируемых клиентов;
* `-t 100` - количество запросов, выполняемых каждым клиентом;
* `-j 4` - количество потоков, в которое выполняется тестирование на хосте. В данном случае хост имеет процессор с 8 физическими ядрами (каждое работает в 2 потока), для минимизации влияния на виртуальную машину выделена только половина из них.

Тестирование выполнено три раза. Вывод команды со средним результатом:
```
wr@main:~$ pgbench -c 50 -t 100 -j 4 -h 192.168.122.188 -U pgbench pgbench
Password: 
pgbench (15.6 (Debian 15.6-0+deb12u1), server 15.7 (Ubuntu 15.7-1.pgdg20.04+1))
starting vacuum...end.
transaction type: <builtin: TPC-B (sort of)>
scaling factor: 400
query mode: simple
number of clients: 50
number of threads: 4
maximum number of tries: 1
number of transactions per client: 100
number of transactions actually processed: 5000/5000
number of failed transactions: 0 (0.000%)
latency average = 294.303 ms
initial connection time = 134.382 ms
tps = 169.893222 (without initial connection time)
```
При этом, при мониторинге нагрузки на виртуальную машину нет заметного роста нагрузки на ОЗУ, но при этом судя по выводу команды `top` значительно увеличивается значение `wa` - IOWAIT достигает 70%, что говорит о том что СУБД постоянно обращается к диску.

---
## Попытка оптимизации настроек СУБД
Для оптимизации настроек СУБД, требуется определить объём ресурсов сервера, имеющихся в распоряжении.
Количество доступных ядер (потоков) CPU можно определить командой:
```
wr@bubuntu20042:~$ lscpu | grep 'CPU(s)':
CPU(s):                             4
```
Объём доступной оперативной памяти проще всего определить по выводу команды 'free':
```
wr@bubuntu20042:~$ free -m
              total        used        free      shared  buff/cache   available
Mem:           7945         207        6526          16        1211        7425
Swap:          2047           0        2047
```
По столюцу `total` виден общий объём ОЗУ 7945 МБ (для упрощения будем считать его равным 8 ГБ).
В некоторых случаях также можно определить тип накопителя:
```
wr@bubuntu20042:~$ cat /sys/block/vdb/queue/rotational 
1
```
`vdb` - в данном случае именно на нём расположен раздел, примонтированный в `/mnt/pgdata`. `1` в выводе команды означает, что по данным ОС на виртуальной машине диск vdb вращается, то есть является механическим HDD. `0` означал бы, что накопитель является твердотельным (SSD). Но следует иметь в виду, что в некоторых случаях виртуальные машины не получают от гипервизора прямого доступа к оборудованию системы хранения данных: в моём случае единица отображается даже если накопитель виртуальной машины на самом деле расположен на NVME SSD. Более надёжный метод определения типа накопителя - знакомство с аппаратной конфигурацией сервера (или прямое указание типа накопителя при заказе виртуальной машины в облачном хостинге).

**Итог: 4 ядра CPU, 8 ГБ ОЗУ, механический HDD**.

Изменены параметры работы с ОЗУ, при помощи SQL-запросов:
```
postgres=# ALTER SYSTEM SET effective_cache_size TO '5GB';
ALTER SYSTEM
postgres=# ALTER SYSTEM SET shared_buffers TO '2GB';
ALTER SYSTEM
```
* `effective_cache_size` рекомендуется устанавливать примерно равным 2/3 общего объёма ОЗУ;
* `shared_buffers` рекомендуется делать равным 1/4 общего объёма ОЗУ; изменение требует перезапуска СУБД.

Несколько раз выполнено повторное тестирование производительности при помощи `pgbench` с идентичными опциями
```
wr@main:~$ pgbench -c 50 -t 100 -j 4 -h 192.168.122.188 -U pgbench pgbench
Password: 
pgbench (15.6 (Debian 15.6-0+deb12u1), server 15.7 (Ubuntu 15.7-1.pgdg20.04+1))
starting vacuum...end.
transaction type: <builtin: TPC-B (sort of)>
scaling factor: 400
query mode: simple
number of clients: 50
number of threads: 4
maximum number of tries: 1
number of transactions per client: 100
number of transactions actually processed: 5000/5000
number of failed transactions: 0 (0.000%)
latency average = 113.177 ms
initial connection time = 135.239 ms
tps = 441.786461 (without initial connection time)
```
Видно снижение среднего значения latency с 294 до 113 миллисекунд, и увеличение количества обработанных строк в секунду с 170 до 442 (округлённые значения).

---
## Дальнейшая оптимизация настроек

```
postgres=# ALTER SYSTEM SET work_mem TO '10MB';
ALTER SYSTEM
postgres=# ALTER SYSTEM SET maintenance_work_mem TO '512MB';
ALTER SYSTEM
postgres=# ALTER SYSTEM SET checkpoint_completion_target TO '0.9';
ALTER SYSTEM
postgres=# ALTER SYSTEM SET effective_io_concurrency TO '1';
ALTER SYSTEM
postgres=# ALTER SYSTEM SET random_page_cost TO '4';
ALTER SYSTEM
postgres=# ALTER SYSTEM SET max_worker_processes TO '4';
ALTER SYSTEM
postgres=# ALTER SYSTEM SET max_parallel_workers_per_gather TO '2';
ALTER SYSTEM
postgres=# ALTER SYSTEM SET max_parallel_workers TO '4';
ALTER SYSTEM
postgres=# ALTER SYSTEM SET max_parallel_maintenance_workers TO '2';
ALTER SYSTEM
```
* `work_mem` - объём памяти для операций сортировки и хеширования; так как это значение задаётся для каждой операции (которых может быть много даже в рамках одного сеанса) устанавливать его слишком большим не рекомендуется;
* `maintenance_work_mem` - объём памяти для операций обслуживания БД, таких как vacuum, который обычно не выполняются одновременно. Увеличение ускоряет выполнение указанных операций;
* `checkpoint_completion_target` - wелевое время для завершения процедуры контрольной точки, влияет на равномерность нагрузки на систему ввода-вывода;
* `effective_io_concurrency` - количество параллельных операций ввода-вывода, в текущей ситуации равен единице т.к. СУБД работает на одном HDD;
* `random_page_cost` - стоимость чтения одной произвольной страницы с диска, устанавливается в соответствии примерной кратности снижения производительности при случайном чтении относительно последовательного (4 означает что случайное чтение в 40 раз медленнее последовательного, что примерно соответствует среднему HDD), значение подбирается в соответствии дисковой системе сервера;
* `max_worker_processes` - максимальное число фоновых процессов, равно количеству ядер (потоков) процессора сервера;
* `max_parallel_workers_per_gather` - максимальное число рабочих процессов, которые могут запускаться одним узлом Gather или Gather Merge;
* `max_parallel_workers` - максимальное число рабочих процессов, которое система сможет поддерживать для параллельных запросов, значение не должно превышать `max_worker_processes`;
* `max_parallel_maintenance_workers` - максимальное число рабочих процессов для операций обслуживания.

Изменение некоторых параметров из перечисленных выше требует перезапуска СУБД.

После выполнения указанных настроек ещё несколько раз выполнено тестирование производительности. Средний результат:
```
wr@main:~$ pgbench -c 50 -t 100 -j 4 -h 192.168.122.188 -U pgbench pgbench
Password: 
pgbench (15.6 (Debian 15.6-0+deb12u1), server 15.7 (Ubuntu 15.7-1.pgdg20.04+1))
starting vacuum...end.
transaction type: <builtin: TPC-B (sort of)>
scaling factor: 400
query mode: simple
number of clients: 50
number of threads: 4
maximum number of tries: 1
number of transactions per client: 100
number of transactions actually processed: 5000/5000
number of failed transactions: 0 (0.000%)
latency average = 105.222 ms
initial connection time = 117.328 ms
tps = 475.184804 (without initial connection time)
```
По результату виден дополнительный рост значения tps.

---
## Производительность в ущерб надёжности
* `synchronous_commit` - параметр, определяющий, после завершения какого уровня обработки WAL сервер будет сообщать об успешном выполнении операции. Значение по умолчанию - `on`, возможные значения перечислены в [документации](https://postgrespro.ru/docs/postgrespro/9.6/runtime-config-wal#synchronous-commit-matrix), изменение настроек допускается как через установку опций postgresql.conf, так и для отдельных (например, некритичных) транзакций;
* `fsync` - параметр, включение которого требует от сервера PostgreSQL добиваться, чтобы изменения были записаны на диск физически, выполняя системные вызовы fsync() или другими подобными методами, значение по умолчанию - `on`, изменение настройки требует перезапуска кластера СУБД.

Отключение перечисленных параметров может привести к некоторому росту производительности при тестировании, но допускает повреждение данных СУБД при сбоях ОС или аппаратного обеспечения. На время теста отключим эти параметры:

```
postgres=# ALTER SYSTEM SET synchronous_commit TO 'off';
ALTER SYSTEM
postgres=# ALTER SYSTEM SET fsync TO 'off';
ALTER SYSTEM
```
После установки этих параметров и перезапуска СУБД, ещё несколько раз повторен тест производительности. Средний результат:
```
wr@main:~$ pgbench -c 50 -t 100 -j 4 -h 192.168.122.188 -U pgbench pgbench
Password: 
pgbench (15.6 (Debian 15.6-0+deb12u1), server 15.7 (Ubuntu 15.7-1.pgdg20.04+1))
starting vacuum...end.
transaction type: <builtin: TPC-B (sort of)>
scaling factor: 400
query mode: simple
number of clients: 50
number of threads: 4
maximum number of tries: 1
number of transactions per client: 100
number of transactions actually processed: 5000/5000
number of failed transactions: 0 (0.000%)
latency average = 38.095 ms
initial connection time = 123.509 ms
tps = 1312.516472 (without initial connection time)
```
Виден заметный рост значения `tps`, но из-за возможных сбоев такой режим работы подходит только для тестирования задач, не подразумевающих никаких требований к сохранности данных.