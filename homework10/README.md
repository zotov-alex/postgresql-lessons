 
# Домашнее задание №10
В рамках данного задания выполняется сравнение быстродействия PostgreSQL с другой СУБД при работе с большим объёмом данных.

---
## Подготовка
Для сравнения производительности с PostgreSQL при работе с большим объёмом данных выбрана СУБД clickhouse. Подготовлены одинаковые виртуальные машины (4 ядра CPU, 8 ГБ RAM, 100 ГБ диск NVME SSD, Ubuntu 20.04 с актуальными на момент выполнения обновлениями), работающие локально с использованием libvirt (virt-manager). Тесты проведены поочередно, для исключения влияния работы виртуальных машин друг на друга.  

PostgreSQL 16 установлен в соответствии [документации](https://www.postgresql.org/download/linux/ubuntu/) разработчика. Clickhouse также установлен по [документации](https://clickhouse.com/docs/ru/getting-started/install). Настройки всех СУБД, влияющие на производительность, не изменялись. Тесты выполнены при помощи запросов в штатной консоли СУБД - соответственно утилиты psql и clickhouse-client.

Перед выполнением запросов в обе СУБД был загружен датасет, в его качестве использованы данные о поездках такси в Нью-Йорке за 2019-2020 годы ([ссылка](https://www.kaggle.com/datasets/microize/newyork-yellow-taxi-trip-data-2020-2019) на датасет), после загрузки которого были получены БД размером примерно 13 гигабайт в случае обеих СУБД. Датасеты загружались из CSV.

---
## Измерения PostgreSQL

Перед загрузкой данных в postgresql, создание таблицы при помощи запроса:
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
Загрузка данных из файла на виртуальной машине:
```
COPY persons(
	"VendorID",
	tpep_pickup_datetime,
	tpep_dropoff_datetime,
	passenger_count,
	trip_distance,
	"RatecodeID",
	store_and_fwd_flag,
	"PULocationID",
	"DOLocationID",
	payment_type,
	fare_amount,
	extra,
	mta_tax,
	tip_amount,
	tolls_amount,
	improvement_surcharge,
	total_amount,
	congestion_surcharge
	)
FROM '/tmp/yellow_tripdata_merged.csv'
DELIMITER ','
CSV HEADER;
```
Для отображения времени выполнения запросов в консоли утилиты psql следует выполнить команду:
```
\timing on
```
Запрос для подсчёта записей о поездках с количеством пассажиров, равным 6, и время его выполнения:
```
test=# select count(*) from yellow_tripdata where passenger_count = 6;
  count  
---------
 2377311
(1 строка)

Время: 45384,013 мс (00:45,384)
```
Время выполнения запроса - чуть более 45 секунд.

Запрос для вывода информации о поездках за первые 10 минут 2020 года, и информация о времени его выполнения (сами данные также были выведены, но из-за большого объёма они в отчёте не указаны):
```
test=# select * from yellow_tripdata where tpep_pickup_datetime like '%2020-01-01 00:00%';
Время: 165727,263 мс (02:45,727)
```
Время выполнения - около 2 минут 46 секунд, было выведено 45 строк.

---
## Измерения Clickhouse
Запрос для создания таблицы в Clickhouse:
```
CREATE TABLE INFORMATION_SCHEMA.yellow_tripdata (
	VendorID INTEGER,
	tpep_pickup_datetime VARCHAR(50),
	tpep_dropoff_datetime VARCHAR(50),
	passenger_count INTEGER,
	trip_distance REAL,
	RatecodeID INTEGER,
	store_and_fwd_flag VARCHAR(50),
	PULocationID INTEGER,
	DOLocationID INTEGER,
	payment_type INTEGER,
	fare_amount REAL,
	extra INTEGER,
	mta_tax REAL,
	tip_amount INTEGER,
	tolls_amount INTEGER,
	improvement_surcharge REAL,
	total_amount REAL,
	congestion_surcharge REAL
) ENGINE = Log;
```
Запрос для загрузки данных из файла:
```
INSERT INTO default.yellow_tripdata
FROM INFILE '/tmp/yellow_tripdata_merged.csv'
FORMAT CSV
```
Консольный клиента Clickhouse по умолчанию выводит время выполнения запросов. Для оценки производительности были выполнены эквивалентные запросы, первый - для подсчёта записей о поездках с количеством пассажиров, равным 6 (выполнился за 0.082 секунды, нашлось такое же кол-во строк как и при запросе к PostgreSQL):
```
bubuntu20042 :) select count() from default.yellow_tripdata where passenger_count = 6;

SELECT count()
FROM default.yellow_tripdata
WHERE passenger_count = 6

Query id: fb59c3ef-3703-45fb-bfd8-5e1ece4e0b5c

   ┌─count()─┐
1. │ 2377311 │ -- 2.38 million
   └─────────┘

1 row in set. Elapsed: 0.082 sec. Processed 101.25 million rows, 404.99 MB (1.24 billion rows/s., 4.94 GB/s.)
Peak memory usage: 293.59 KiB.
```
Второй - для вывода информации о поездках за первые 10 минут 2020 года (содержимое таблицы сокращено для компактности отчёта), выполнен за немного более чем 6 секунд, выведено 45 строк, также как и при выполнении запроса к PostgreSQL:
```
bubuntu20042 :) select * from default.yellow_tripdata where tpep_pickup_datetime like '%2019-01-01 00:00%';

SELECT *
FROM default.yellow_tripdata
WHERE tpep_pickup_datetime LIKE '%2019-01-01 00:00%'

Query id: 30580d23-b25b-435c-b407-6e372b52552f

    ┌─VendorID─┬─tpep_pickup_datetime─┬─tpep_dropoff_datetime─┬─passenger_count─┬─trip_distance─┬─RatecodeID─┬─store_and_fwd_flag─┬─PULocationID─┬─DOLocationID─┬─payment_type─┬─fare_amount─┬─extra─┬─mta_tax─┬─tip_amount─┬─tolls_amount─┬─improvement_surcharge─┬─total_amount─┬─congestion_surcharge─┐
 1. │        2 │ 2019-01-01 00:00:00  │ 2019-01-01 01:03:12   │               2 │          7.37 │          1 │ N                  │          237 │          264 │            2 │          23 │   0.5 │     0.5 │          0 │            0 │                   0.3 │         24.8 │                      │
 2. │        1 │ 2019-01-01 00:00:19  │ 2019-01-01 00:09:54   │               1 │           1.8 │          1 │ N                  │          249 │            4 │            2 │           8 │   0.5 │     0.5 │          0 │            0 │                   0.3 │          9.8 │                      │
<...><...><...><...><...><...><...><...><...><...><...><...><...><...><...><...><...><...><...><...><...><...><...><...><...><...><...><...><...><...><...><...><...><...><...><...><...><...><...><...><...><...><...><...><...><...><...><...><...><...><...><...><...><...><...><...><...><...><...><...>
45. │        2 │ 2019-01-01 00:00:37  │ 2019-01-01 00:10:58   │               1 │          1.51 │          1 │ N                  │           79 │          249 │            1 │           8 │   0.5 │     0.5 │       2.45 │            0 │                   0.3 │        12.25 │                      │
    └──────────┴──────────────────────┴───────────────────────┴─────────────────┴───────────────┴────────────┴────────────────────┴──────────────┴──────────────┴──────────────┴─────────────┴───────┴─────────┴────────────┴──────────────┴───────────────────────┴──────────────┴──────────────────────┘

45 rows in set. Elapsed: 6.288 sec. Processed 101.25 million rows, 13.53 GB (16.10 million rows/s., 2.15 GB/s.)
Peak memory usage: 91.59 MiB.
```

---
## Итог
Время выполнения аналитических запросов к БД большого размера в СУБД PostgreSQL значительно превышает время выполнения эквивалентных запросов к отдельной аналитической СУБД.