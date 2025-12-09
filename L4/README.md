# Отказоустойчивый HTTP-прокси для кластера ClickHouse (3×3) за VRRP-VIP + ZooKeeper (3 ноды)

## 1. Карта стенда

Сегмент «серой» сети: `10.10.0.0/24`

- VIP (VRRP): `10.10.0.100/24` → `vip.dc.local`
- Прокси:
  - `proxy01.dc.local` — `10.10.0.11` — Nginx + keepalived (MASTER)
  - `proxy02.dc.local` — `10.10.0.12` — Nginx + keepalived (BACKUP)
- ZooKeeper:
  - `zk01.dc.local` — `10.10.0.21`
  - `zk02.dc.local` — `10.10.0.22`
  - `zk03.dc.local` — `10.10.0.23`
- ClickHouse (3 шарда × 3 реплики):
  - Шард 1: `ch-s1-r1.dc.local (10.10.0.31)`, `ch-s1-r2 (10.10.0.32)`, `ch-s1-r3 (10.10.0.33)`
  - Шард 2: `ch-s2-r1.dc.local (10.10.0.41)`, `ch-s2-r2 (10.10.0.42)`, `ch-s2-r3 (10.10.0.43)`
  - Шард 3: `ch-s3-r1.dc.local (10.10.0.51)`, `ch-s3-r2 (10.10.0.52)`, `ch-s3-r3 (10.10.0.53)`

Сеть изолирована, доступ только внутри `10.10.0.0/24`.

---

## 2. Порядок развёртывания

1. **Сеть и DNS**
   - Настроить IP-адреса на узлах.
   - Заполнить `/etc/hosts` или зону DNS по образцу `net/hosts.dc.local`.

2. **ZooKeeper (3 ноды)**
   - Установить ZooKeeper на `zk01/zk02/zk03`.
   - Скопировать `zookeeper/zoo.cfg` в `/etc/zookeeper/zoo.cfg`.
   - На `zk01/02/03` положить `zookeeper/myid.zk0X` в `/var/lib/zookeeper/myid`.
   - Скопировать `zookeeper/systemd/zookeeper-zk0X.service` либо использовать как шаблон.
   - Запустить и проверить: `echo ruok | nc zk01 2181`.

3. **ClickHouse 3×3**
   - Установить ClickHouse Server на все `ch-sX-rY`.
   - Скопировать:
     - `clickhouse/config.d/zookeeper.xml` → `/etc/clickhouse-server/config.d/`
     - `clickhouse/config.d/remote_servers.xml` → `/etc/clickhouse-server/config.d/`
     - `clickhouse/users.d/*.xml` → `/etc/clickhouse-server/users.d/`
   - Запустить ClickHouse на всех нодах.
   - На каждой ноде выполнить `clickhouse-client -n -f clickhouse/create_tables.sql`.
   - Проверить: `SELECT hostName(), cluster() FROM system.clusters` и `system.replicas`.

4. **Nginx (reverse-proxy)**
   - Установить Nginx на `proxy01/02`.
   - Скопировать `nginx/upstream.conf` в `/etc/nginx/conf.d/upstream.conf`.
   - При необходимости заменить `nginx/mime.types` системным или использовать наш.

5. **keepalived (VRRP)**
   - Установить keepalived на `proxy01/02`.
   - Скопировать конфиги:
     - `keepalived/proxy01-keepalived.conf` → `/etc/keepalived/keepalived.conf` на proxy01
     - `keepalived/proxy02-keepalived.conf` → `/etc/keepalived/keepalived.conf` на proxy02
   - Убедиться, что интерфейс в конфиге (`ens18`) совпадает с реальным.
   - Запустить keepalived и проверить, что VIP `10.10.0.100` висит на одной из проксей.

6. **Файрволы**
   - На всех узлах применить правила из `net/firewall/*.rules` как iptables-restore:
     - `iptables-restore < proxy01.rules` и т. п.
   - Проверить, что открыты только нужные порты.

---

## 3. Как проверять (checks/*)

Каждый файл в `checks/` содержит шаблон команд, которые нужно выполнить, и места, куда вставить вывод:

- `checks/vip-failover.txt` — переключение VIP между proxy01/02.
- `checks/proxy-lb.txt` — round-robin балансировка на ClickHouse.
- `checks/proxy-fail-node.txt` — выпадение одной CH-ноды из upstream и возврат.
- `checks/zk-quorum.txt` — поведение при потере 1 и 2 нод ZooKeeper.
- `checks/ch-health.txt` — базовые SELECT, system.clusters, system.replicas.
- `checks/routes-ports.txt` — ss/iptables-save для сетевой гигиены.

---

## 4. Сценарии отказов

- Отказ **proxy01**:
  - Остановить keepalived: `systemctl stop keepalived`.
  - VIP `10.10.0.100` должен перейти на `proxy02` ≤ 3–5 секунд.
- Отказ **одной ClickHouse-ноды**:
  - Остановить сервис на одной ноде.
  - Запросы через VIP не должны возвращать 502/504, upstream-адреса — только живые ноды.
- Отказ **ZooKeeper**:
  - При падении 1 ноды: кластер читает и пишет.
  - При падении 2 нод: ClickHouse переходит в read-only по DDL/записям.

---

## 5. Почему пассивный health в Nginx

В OSS-версии Nginx нет активных health-checks upstream'ов.  
Используем:

- `max_fails` и `fail_timeout` в `upstream` — временно помечают сервер как down после нескольких ошибок.
- `proxy_next_upstream error timeout http_502 http_503 http_504` — при ошибке запрос перекидывается на следующий живой сервер.

Это даёт приемлемый отказоустойчивый режим без платных модулей.

---

## 6. Makefile и скрипты

- `Makefile` даёт цели `deploy-*` и `test-*`, которые просто вызывают скрипты из `scripts/`.
- `scripts/deploy-all.sh` — развёртывание конфигов по узлам (через ssh/rsync).
- `scripts/test-all.sh` — запуск всех проверок из `checks/`.
- `scripts/fault-injector.sh` — автоматизация сценариев отказов (стоп/старт сервисов).
