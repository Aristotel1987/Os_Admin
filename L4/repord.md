# # Отчёт

## Самостоятельная работа: «Отказоустойчивый HTTP-прокси для кластера ClickHouse (3×3) за VRRP-VIP + ZooKeeper (3 ноды)»
**Студент:** Выдумкин Илья Александрович
**Группа:** p4250
**Дисциплина:** Системное администрирование
**Работа:** «Отказоустойчивый HTTP-прокси для кластера ClickHouse с VRRP-VIP»
**Дата выполнения:** 7.12.2025

---

# ## 1. Цель работы

Цель работы — развернуть во внутренней («серой») сети изолированный стенд, включающий:

* два входных reverse-proxy-сервера на базе **Nginx + Keepalived (VRRP)**;
* отказоустойчивый кластер **ZooKeeper (3 ноды)**;
* распределённый кластер **ClickHouse (3 шарда × 3 реплики = 9 нод)** с репликацией;
* балансировку HTTP-запросов от VIP-адреса к живым ClickHouse-нодам;
* автоматическое исключение "упавших" нод из upstream (passive health-check);
* проверку работы отказоустойчивости (отказы CH-нод, отказы ZK-нод, VRRP-переключение VIP);
* построение воспроизводимой структуры репозитория с конфигурациями, юнитами, правилами firewall и текстовыми логами проверок.

---

# ## 2. Топология и базовая подготовка

### 2.1. Схема стенда

Внутренняя сеть: **10.10.0.0/24**

| Узел     | Назначение                   | DNS              | IP          |
| -------- | ---------------------------- | ---------------- | ----------- |
| proxy01  | MASTER VRRP + Nginx          | proxy01.dc.local | 10.10.0.11  |
| proxy02  | BACKUP VRRP + Nginx          | proxy02.dc.local | 10.10.0.12  |
| vip      | VRRP виртуальный IP          | vip.dc.local     | 10.10.0.100 |
| zk01     | ZooKeeper node 1             | zk01.dc.local    | 10.10.0.21  |
| zk02     | ZooKeeper node 2             | zk02.dc.local    | 10.10.0.22  |
| zk03     | ZooKeeper node 3             | zk03.dc.local    | 10.10.0.23  |
| ch-s1-r1 | ClickHouse Shard 1 Replica 1 | …                | 10.10.0.31  |
| ch-s1-r2 | Replica 2                    | …                | 10.10.0.32  |
| ch-s1-r3 | Replica 3                    | …                | 10.10.0.33  |
| ch-s2-r1 | Shard 2 Replica 1            | …                | 10.10.0.41  |
| …        | …                            | …                | …           |
| ch-s3-r3 | Shard 3 Replica 3            | …                | 10.10.0.53  |

### 2.2. Настройка имен и hosts

На каждом узле выполнено:

```bash
sudo hostnamectl set-hostname <имя-узла>
```

В файл `/etc/hosts` добавлены все узлы:

```
10.10.0.11  proxy01.dc.local proxy01
10.10.0.12  proxy02.dc.local proxy02
10.10.0.100 vip.dc.local     vip

10.10.0.21  zk01.dc.local zk01
10.10.0.22  zk02.dc.local zk02
10.10.0.23  zk03.dc.local zk03

# ClickHouse 3×3
10.10.0.31 ch-s1-r1.dc.local ch-s1-r1
...
10.10.0.53 ch-s3-r3.dc.local ch-s3-r3
```

Проверка:

```bash
host zk01.dc.local
host ch-s2-r3.dc.local
```

Логи команд сохранены в `checks/dns.txt`.

---

# ## 3. Развертывание ZooKeeper (3 ноды)

### 3.1. Установка

На **zk01/zk02/zk03**:

```bash
sudo apt update
sudo apt install zookeeper zookeeperd -y
```

### 3.2. Конфигурация zoo.cfg

Файл `/etc/zookeeper/zoo.cfg` заменён содержимым из репозитория:

```
tickTime=2000
initLimit=10
syncLimit=5
dataDir=/var/lib/zookeeper
clientPort=2181

server.1=zk01.dc.local:2888:3888
server.2=zk02.dc.local:2888:3888
server.3=zk03.dc.local:3888:2888
```

### 3.3. Файл myid

На `zk01`:

```
echo 1 | sudo tee /var/lib/zookeeper/myid
```

На `zk02`:

```
echo 2 | sudo tee /var/lib/zookeeper/myid
```

На `zk03`:

```
echo 3 | sudo tee /var/lib/zookeeper/myid
```

### 3.4. Проверка работы ZK

Проверка RPC:

```bash
echo ruok | nc zk01 2181
```

Ожидаемый ответ: `imok`.

Результаты сохранены в `checks/zk-quorum.txt`.

---

# ## 4. Развертывание ClickHouse кластера 3×3

### 4.1. Установка

На всех 9 нодах:

```bash
sudo apt install clickhouse-server clickhouse-client -y
sudo systemctl enable --now clickhouse-server
```

### 4.2. Конфигурация Zookeeper для CH

Файл `/etc/clickhouse-server/config.d/zookeeper.xml`:

```xml
<zookeeper-servers>
  <node index="1"><host>zk01.dc.local</host><port>2181</port></node>
  <node index="2"><host>zk02.dc.local</host><port>2181</port></node>
  <node index="3"><host>zk03.dc.local</host><port>2181</port></node>
</zookeeper-servers>
```

### 4.3. Конфигурация remote_servers.xml

Формируется карта кластеров 3×3.

### 4.4. Создание таблиц ReplicatedMergeTree

На каждом ClickHouse-сервере:

```bash
clickhouse-client -n < clickhouse/create_tables.sql
```

### 4.5. Проверка состояния реплик

```bash
clickhouse-client --query="SELECT hostName(), is_leader, is_readonly FROM system.replicas"
```

Выводы сохранены в `checks/ch-health.txt`.

---

# ## 5. Настройка Nginx + VRRP (proxy01 и proxy02)

## 5.1. Установка Nginx

```bash
sudo apt install nginx -y
```

В `/etc/nginx/conf.d/upstream.conf` размещён upstream из 9 ClickHouse нод.

## 5.2. Установка keepalived

```bash
sudo apt install keepalived -y
```

### Конфигурация MASTER (proxy01):

```
state MASTER
interface ens18
virtual_router_id 51
priority 150
virtual_ipaddress {
   10.10.0.100/24
}
```

### Конфигурация BACKUP (proxy02):

```
state BACKUP
priority 100
same virtual_router_id and VIP
```

### 5.3. Проверка VRRP

Интерфейс `ens18` на proxy01:

```bash
ip a | grep 10.10.0.100
```

Затем:

```bash
sudo systemctl stop keepalived
```

Проверка на proxy02:

```bash
ip a | grep 10.10.0.100
```

Логи — в `checks/vip-failover.txt`.

---

# ## 6. Сетевая безопасность (firewall)

### 6.1. На ClickHouse-ноды

Разрешены:

* SSH 22
* HTTP 8123 (только из 10.10.0.0/24)
* Native CH TCP 9000 (только из 10.10.0.0/24)

### 6.2. На ZooKeeper-ноды

Разрешены только:

* 22 SSH
* 2181 client
* 2888 follower
* 3888 leader

Правила iptables оформлены в файлах:

```
net/firewall/ch-s1-r1.rules
...
net/firewall/zk03.rules
```

Применение:

```bash
sudo iptables-restore < net/firewall/ch-s1-r1.rules
```

---

# ## 7. Проверка отказоустойчивости

Все результаты записаны в:

```
checks/*.txt
```

### 7.1. Отказ proxy01 (VIP failover)

* останавливаем keepalived на proxy01;
* VIP появляется на proxy02;
* запросы через VIP продолжают идти.

### 7.2. Round-robin распределение нагрузки

Команда:

```bash
for i in {1..20}; do curl -s http://vip.dc.local/?query=SELECT%201; done
```

Половина запросов распределяется равномерно по 9 нодам (учитывая доступность).

### 7.3. Отказ CH-ноды

* остановили сервис CH на одной ноде;
* Nginx исключает ноду после `max_fails`;
* система продолжает работать.

### 7.4. Потеря ZooKeeper-ноды

1 нода ZK:

```
INSERT … → работает
```

2 ноды ZK:

```
INSERT … → ошибка (read-only)
SELECT … → работает
```

### Все выводы помещены в:

```
checks/zk-quorum.txt
checks/proxy-fail-node.txt
checks/ch-health.txt
checks/routes-ports.txt
```

---

# ## 8. Структура репозитория

Репозиторий приведён в reproducible-виде:

```
.
├── keepalived/
├── nginx/
├── clickhouse/
├── zookeeper/
├── net/firewall/
├── scripts/
└── checks/
```

Каждый каталог содержит только текстовые конфигурации, что полностью соответствует требованиям.

---

# ## 9. Вывод

В ходе выполнения лабораторной работы:

* Развернут полный кластер **ClickHouse 3×3** с репликацией;
* Настроена система метаданных **ZooKeeper 3-ноды**;
* Настроен **reverse-proxy Nginx** с балансировкой и пассивными health-check;
* Настроена **отказоустойчивость входной точки** через VRRP и keepalived;
* Реализована строгая **сетевая изоляция** посредством iptables;
* Проведены тесты отказоустойчивости: выпадение реплики CH, потеря кворума ZooKeeper и переключение VIP;
* Все результаты проверок оформлены в каталоге `checks/`.

Поставленная цель полностью выполнена. Стенд работает в соответствии с требованиями, демонстрирует устойчивость к отказам и корректную балансировку нагрузки.
