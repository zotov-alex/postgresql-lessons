 
# Домашнее задание №14
В рамках данного задания выполняется запуск CocroachDB в качестве мультимастер-альтернативы PostgreSQL.

## CocroachDB

Установка выполняется на локальные виртуальные машины, вручную.

### Установка
Созданы три виртуальные машины на Ubuntu 24.04 (2 ядра ЦП, 8 ГБ ОЗУ, 40 ГБ SSD):

* cdb1 - 192.168.122.233
* cdb2 - 192.168.122.106
* cdb3 - 192.168.122.177

Для работы CocroachDB требуются пакеты glibc, libncurses, and tzdata. В Ubuntu 24.04 они установлены по умолчанию, в этом случае дополнительных действий не требуется. Но всё ещё требуется специально собранная версия библиотеки GEOS, которую потребуется также установить вручную.

Для начала - загрузка и распаковка дистрибутива:
```
cd /tmp
wget https://binaries.cockroachdb.com/cockroach-v24.1.4.linux-amd64.tgz
tar -xvf cockroach-v24.1.4.linux-amd64.tgz
```
Установка библиотек GEOS:
```
sudo mkdir /usr/local/lib/cocroach
sudo cp /tmp/cockroach-v24.1.4.linux-amd64/lib/libgeos{_c.so,.so} /usr/local/lib/cocroach/
```
Установка бинарного файла CocroachDB:
```
sudo cp /tmp/cockroach-v24.1.4.linux-amd64/cockroach /usr/local/bin
```
Создание пользователя, от имени которого будет запускаться CocroachDB:
```
sudo useradd -m -d /opt/cocroach -s /bin/bash cocroach
sudo -u cocroach mkdir -p /opt/cocroach/{certs,.cdb}
```
Для аутентификации нод кластера будут использоваться сертификаты. Их создание на одной из нод:
```
sudo su - cocroach
cockroach cert create-ca --certs-dir=certs --ca-key=.cdb/ca.key
cockroach cert create-node localhost cdb1 cdb2 cdb3 --certs-dir=certs --ca-key=.cdb/ca.key --overwrite
cockroach cert create-client root --certs-dir=certs --ca-key=.cdb/ca.key
cockroach cert list --certs-dir=certs
```
Директорию `certs` вместе со всем содержимым требуется скопировать на оставшиеся сервера в домашнюю директорию пользователя cocroach - `/opt/cocroach`. После копирования сертификатов можно запустить ноды. Пример команды запуска первой:
```
cockroach start --certs-dir=/opt/cocroach/certs --advertise-addr=cdb1 --join=cdb1,cdb2,cdb3 --cache=.25 --max-sql-memory=.25 --background
```
Сбор (инициализация кластера):
```
cockroach init --certs-dir=/opt/cocroach/certs --host=cdb1
```
После успешной инициализации можно просмотреть состав кластера:
```
cocroach@cdb1:~$ cockroach node status --certs-dir=certs
  id |  address   | sql_address |  build  |              started_at              |              updated_at              | locality | is_available | is_live
-----+------------+-------------+---------+--------------------------------------+--------------------------------------+----------+--------------+----------
   1 | cdb1:26257 | cdb1:26257  | v24.1.4 | 2024-09-10 06:48:43.247638 +0000 UTC | 2024-09-10 07:00:22.284226 +0000 UTC |          | true         | true
   2 | cdb3:26257 | cdb3:26257  | v24.1.4 | 2024-09-10 06:48:44.183661 +0000 UTC | 2024-09-10 07:00:23.221471 +0000 UTC |          | true         | true
   3 | cdb2:26257 | cdb2:26257  | v24.1.4 | 2024-09-10 06:48:45.181037 +0000 UTC | 2024-09-10 07:00:24.204526 +0000 UTC |          | true         | true
(3 rows)
```
Для удалённого подключения лучше создать отдельного пользователя и базу данных. Запросы для их создания аналогичны таковым в PostgreSQL:
```
CREATE USER test ENCRYPTED PASSWORD 'test';
CREATE DATABASE test OWNER test;
```
Для подключения к консоли можно использовать стандартный клиент psql, но лучше воспользоваться встроенным клиентом CocroachDB:
```
cockroach sql --certs-dir=certs
```
Для подключения с других машин можно использовать отдельный клиент cocroach-sql. Для этого на эту машину также требуется скопировать сертификаты, и удостовериться что имя сервера корректно разрешается DNS-сервером (или добавить запись в hosts). Команда для подключения:
```
cockroach-sql --url 'postgres://test@cdb1:26257/test' --certs-dir=/tmp/certs
```

### Тестирование
Тестирование производится при помощи датасета с данными такси Нью-Йорка, по аналогии с домашним заданием [homework15](../homework15). Запрос для создания таблицы:
```
CREATE TABLE public.yellow_tripdata (
        "VendorID" integer NULL,
        tpep_pickup_datetime varchar(50) NULL,
        tpep_dropoff_datetime varchar(50) NULL,
        passenger_count integer NULL,
        trip_distance real NULL,
        "RatecodeID" integer NULL,
        store_and_fwd_flag varchar(50) NULL,
        "PULocationID" integer NULL,
        "DOLocationID" integer NULL,
        payment_type integer NULL,
        fare_amount real NULL,
        extra integer NULL,
        mta_tax real NULL,
        tip_amount integer NULL,
        tolls_amount integer NULL,
        improvement_surcharge real NULL,
        total_amount real NULL,
        congestion_surcharge real NULL
);
```
Подсчёт поездок с шестью пассажирами:
```
test@cdb1:26257/test> select count(*) from yellow_tripdata where passenger_count = 6;                                     
   count
-----------
  2377311
(1 row)

Time: 27.545s total (execution 27.535s / network 0.010s)
```
Вывод информации о поездках за первые 10 минут 2020 года:
```
test@cdb1:26257/test> select * from yellow_tripdata where tpep_pickup_datetime like '%2020-01-01 00:00%';                 
  VendorID | tpep_pickup_datetime | tpep_dropoff_datetime | passenger_count | trip_distance | RatecodeID | store_and_fwd_flag | PULocationID | DOLocationID | payment_type | fare_amount | extra | mta_tax | tip_amount | tolls_amount | improvement_surcharge | total_amount | congestion_surcharge
-----------+----------------------+-----------------------+-----------------+---------------+------------+--------------------+--------------+--------------+--------------+-------------+-------+---------+------------+--------------+-----------------------+--------------+-----------------------
         2 | 2020-01-01 00:00:06  | 2020-01-01 00:18:13   |               1 |          4.51 |          1 | N                  |           75 |          162 |            2 |          16 |     0 |     0.5 |          0 |            0 |                   0.3 |         19.8 |                  2.5
<...>
         2 | 2020-01-01 00:00:00  | 2020-01-01 04:17:14   |               5 |          0.96 |          1 | N                  |           68 |           50 |            2 |         5.5 |     0 |     0.5 |          0 |            0 |                   0.3 |          9.3 |                  2.5
(49 rows)

Time: 29.531s total (execution 29.530s / network 0.001s)
```
Скорость выполнения запросов несколько ниже по сравнению с одиночной инсталляцией PostgreSQL по причине повышения накладных расходов из-за запуска виртуальных машин на одном физическом сервере и одном накопителе (хотя и скоростном NVMe). Результаты тестирования одиночной инсталляции PostgreSQL перечислены в [homework15](../homework15).