 
# Домашнее задание №12
В рамках данного задания выполняется запуск высокодоступных кластеров СУБД PostgreSQL

---
## Вариант 1 - запуск высокодоступного кластера в kubernetes
Запуск будет выполнен в minikube, c использованием уже существующего Helm-чарта от Bitnami.

Перед началом работ выполнена установка утилит Helm и jq (вторая - потребуется для чтения секретов в kubernetes).

Для большего порядка установка кластера будет выполнена в отдельном пространстве имён. Оно создаётся командой:
```
kubectl create namespace otus
```
После, требуется добавить репозиторий bitnami и установить helm-чарт:
```
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
helm -n otus install otus-study bitnami/postgresql-ha
```
Через некоторое время после установки тестовый кластер запущен:
```
wr@main:~$ kubectl -n otus get pods
NAME                                               READY   STATUS    RESTARTS   AGE
otus-study-postgresql-ha-pgpool-667b797f9d-77mdb   1/1     Running   0          63s
otus-study-postgresql-ha-postgresql-0              1/1     Running   0          63s
otus-study-postgresql-ha-postgresql-1              1/1     Running   0          63s
otus-study-postgresql-ha-postgresql-2              1/1     Running   0          63s
```
Можно подключиться к кластеру. Так как при установке чарта не менялись никакие настройки, требуется узнать пароль суперпользователя. Вывод списка секретов:
```
wr@main:~$ kubectl -n otus get secrets 
NAME                                  TYPE                 DATA   AGE
otus-study-postgresql-ha-pgpool       Opaque               1      2m19s
otus-study-postgresql-ha-postgresql   Opaque               2      2m19s
sh.helm.release.v1.otus-study.v1      helm.sh/release.v1   1      2m19s
```
Можно вывести полное содержимое секрета в формате json при помощи команды:
```
kubectl -n otus get secrets otus-study-postgresql-ha-postgresql -o json
```
А можно вывести только пароль и сразу декодировать его:
```
kubectl -n otus get secrets otus-study-postgresql-ha-postgresql -o json | jq -r ".data.password" | base64 -d
```
На данном этапе СУБД доступна только изнутри kubernetes. Для того чтобы появилась возможность подключения снаружи в целях выполнения задания, требуется настроить проброс порта. Чтобы узнать на какой сервис его пробрасывать, требуется вывести список сервисов:
```
wr@main:~$ kubectl -n otus get services
NAME                                           TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)    AGE
otus-study-postgresql-ha-pgpool                ClusterIP   10.105.184.145   <none>        5432/TCP   6m12s
otus-study-postgresql-ha-postgresql            ClusterIP   10.96.179.26     <none>        5432/TCP   6m12s
otus-study-postgresql-ha-postgresql-headless   ClusterIP   None 
```
В данном случае требуется попасть на сервис `otus-study-postgresql-ha-pgpool`. Включение проброса порта:
```
kubectl -n otus port-forward svc/otus-study-postgresql-ha-pgpool 15432:5432
```
Сейчас можно пробовать подключаться к localhost по порту 15432:
```
wr@main:~$ psql -h localhost -p 15432 -U postgres
Пароль пользователя postgres: 
psql (16.4 (Debian 16.4-1.pgdg120+1), сервер 16.3)
Введите "help", чтобы получить справку.

postgres=# 
```
Чтобы посмотреть состав отказоустойчивого кластера, требуется выполнить запрос:
```
show pool_nodes;
```
Пример вывода:
```
 node_id |                                      hostname                                      | port | status | pg_status | lb_weight |  role   | pg_role | select_cnt | load_balance_node | replication_delay | replication_state | replication_sync_state | last_status_change  
---------+------------------------------------------------------------------------------------+------+--------+-----------+-----------+---------+---------+------------+-------------------+-------------------+-------------------+------------------------+---------------------
 0       | otus-study-postgresql-ha-postgresql-0.otus-study-postgresql-ha-postgresql-headless | 5432 | up     | up        | 0.333333  | primary | primary | 72         | false             | 0                 |                   |                        | 2024-08-12 03:08:11
 1       | otus-study-postgresql-ha-postgresql-1.otus-study-postgresql-ha-postgresql-headless | 5432 | up     | up        | 0.333333  | standby | standby | 78         | false             | 0                 |                   |                        | 2024-08-12 03:08:46
 2       | otus-study-postgresql-ha-postgresql-2.otus-study-postgresql-ha-postgresql-headless | 5432 | up     | up        | 0.333333  | standby | standby | 64         | true              | 0                 |                   |                        | 2024-08-12 03:08:46
(3 строки)
```
Видно что нода с именем `otus-study-postgresql-ha-postgresql-0` является мастером. Можно сразу проверить *высокую доступность* и удалить её под:
```
kubectl -n otus delete pod otus-study-postgresql-ha-postgresql-0 --force --grace-period=0
```
Если после этого просмотреть список подов, видно что он автоматически создался снова (возраст - 11 секунд):
```
wr@main:~$ kubectl -n otus get pods
NAME                                               READY   STATUS    RESTARTS   AGE
otus-study-postgresql-ha-pgpool-667b797f9d-77mdb   1/1     Running   0          20m
otus-study-postgresql-ha-postgresql-0              1/1     Running   0          11s
otus-study-postgresql-ha-postgresql-1              1/1     Running   0          20m
otus-study-postgresql-ha-postgresql-2              1/1     Running   0          20m
```
Утилита psql в соседнем окне при этом один раз выдаст ошибку подключения к СУБД, но со второго раза можно ещё раз посмотреть список нод кластера:
```
 node_id |                                      hostname                                      | port | status | pg_status | lb_weight |  role   | pg_role | select_cnt | load_balance_node | replication_delay | replication_state | replication_sync_state | last_status_change  
---------+------------------------------------------------------------------------------------+------+--------+-----------+-----------+---------+---------+------------+-------------------+-------------------+-------------------+------------------------+---------------------
 0       | otus-study-postgresql-ha-postgresql-0.otus-study-postgresql-ha-postgresql-headless | 5432 | down   | down      | 0.333333  | standby | unknown | 82         | false             | 0                 |                   |                        | 2024-08-12 03:27:38
 1       | otus-study-postgresql-ha-postgresql-1.otus-study-postgresql-ha-postgresql-headless | 5432 | up     | up        | 0.333333  | primary | primary | 92         | true              | 0                 |                   |                        | 2024-08-12 03:27:38
 2       | otus-study-postgresql-ha-postgresql-2.otus-study-postgresql-ha-postgresql-headless | 5432 | up     | up        | 0.333333  | standby | standby | 74         | false             | 4600              |                   |                        | 2024-08-12 03:08:46
(3 строки)
```
После удаления пода мастером стала СУБД на поде `otus-study-postgresql-ha-postgresql-1`.

---
## Вариант 2 - pg_auto_failover
Кластер будет развернут на трёх виртуальных машинах под управлением Ubuntu 24.04.
* autofailover1 - 192.168.122.119
* autofailover2 - 192.168.122.84
* autofailover3 - 192.168.122.77

В Ubuntu кластер PostgreSQL инициализируется автоматически, чтобы этого избежать требуется до установки создать файл `/etc/postgresql-common/createcluster.conf` с содержимым:
```
create_main_cluster = false
```
Установка PostgreSQL выполнена по [инструкции](https://www.postgresql.org/download/linux/ubuntu/) с сайта PostgreSQL, при помощи apt. Заодно установлен пакет `postgresql-16-auto-failover`.
```
sudo apt install postgresql-16 postgresql-16-auto-failover
```
Сервис PostgreSQL будет управляться средствами управляющего монитора, поэтому требуется его останоить и отключить автозапуск средствами systemd:
```
sudo systemctl disable --now postgresql
```
Далее, создана новая директория данных `/var/lib/postgresql/16/test`, и этот путь указан в переменной окружения PGDATA для пользователя postgres:
```
export PGDATA="/var/lib/postgresql/16/test"
```
Эта же команда добавлена в файл .profile, созданный в домашней директории пользователя postgres.

### Настройка управляющей ноды (монитора)
После создания директории данных управляющей ноды, можно её инициализировать:
```
pg_autoctl create monitor --auth trust --no-ssl --pgport 5432 --hostname autofailover1
```
...и попробовать запустить:
```
pg_autoctl run
```
Нода запустилась, проверить это можно путём выполнения в соседнем окне терминала команд `psql` или
```
postgres@autofailover1:~$ pg_autoctl show state
Name |  Node |  Host:Port |  TLI: LSN |   Connection |      Reported State |      Assigned State
-----+-------+------------+-----------+--------------+---------------------+--------------------
```
По второй команде видно что в данный момент к управляющей ноде ничто не подключено.

В данный момент управляющая нода запущена в интерактивном режиме, остановим её при помощи Ctrl+C и настроим запуск в виде сервиса:
```
pg_autoctl -q show systemd --pgdata "/var/lib/postgresql/16/test" | sudo tee /etc/systemd/system/pgautofailover.service
sudo systemctl daemon-reload
sudo systemctl enable --now pgautofailover.service
sudo systemctl status pgautofailover.service
```
Перед подключением к управляющей ноде ведомых, требуется разрешить это путём добавления в pg_hba строки
```
host    pg_auto_failover        autoctl_node    192.168.122.0/24        trust
```
... и перечитать конфигурацию командой:
```
pg_autoctl reload
```

### Настройка ведомых нод
Настройка показана на примере autofailover2, autofailover3 настроен идентично.

Инициализация СУБД выполнена командой:
```
pg_autoctl create postgres --name autofailover2 --pgport 5432 --dbname test --monitor postgres://autoctl_node@192.168.122.119:5432/pg_auto_failover --auth trust --no-ssl
```

Далее сразу выполнена настройка для запуска СУБД в виде сервиса, аналогично монитору.

После запуска сервиса pg_autofailover на одной из нод, на мониторе можно проверить его состояние:
```
postgres@autofailover1:~$ pg_autoctl show state
         Name |  Node |          Host:Port |       TLI: LSN |   Connection |      Reported State |      Assigned State
--------------+-------+--------------------+----------------+--------------+---------------------+--------------------
autofailover2 |     1 | autofailover2:5432 |   1: 0/1937420 | read-write ! |              single |              single
```

После запуска pg_autofailover на последней ноде, уже виден полностью собранный кластер:
```
postgres@autofailover1:~$ pg_autoctl show state
         Name |  Node |          Host:Port |       TLI: LSN |   Connection |      Reported State |      Assigned State
--------------+-------+--------------------+----------------+--------------+---------------------+--------------------
autofailover2 |     1 | autofailover2:5432 |   1: 0/3000148 |   read-write |             primary |             primary
autofailover3 |    14 | autofailover3:5432 |   1: 0/3000148 |    read-only |           secondary |           secondary
```

Для открытия возможности подключения клиентов, в pg_hba на autofailover2 и autofailover3 добавлена строка:
```
host    all             all             192.168.122.0/24        scram-sha-256
```
После чего можно настроить haproxy, keepalived и другие сервисы для обеспечения высокой доступности, по аналогии выполненному заданию о настройке Patroni.