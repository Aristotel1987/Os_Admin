# ЛР: HA Nginx (VIP/VRRP) + ClickHouse 3×3 + ZooKeeper 3 ноды в «серой» сети (Debian 12) — полностью офлайн

Это **готовый к сдаче репозиторий** под лабораторную работу:
- 2 узла `proxy` (Nginx) с VRRP VIP через `keepalived` (VIP мигрирует при отказе)
- 3 узла `zookeeper`
- 9 узлов `clickhouse` (3 шарда × 3 реплики)
- DNS без интернета: `dnsmasq` (только DNS, DHCP off) **или** управление `/etc/hosts`
- firewall: `nftables`, политика `drop` + точечные allow
- проверки (`role_checks`) сохраняют артефакты в `ansible/checks/*.txt`
- **внешний интернет НЕ требуется** — ClickHouse ставится из локальных `.deb` в репозитории

> Окружение: Debian 12 на всех узлах. Репозиторий запускается с управляющей машины (control node), где есть Ansible.

---

## 0) Сетевая модель (как в задании)

Подсеть: `10.10.0.0/24`

VIP: `10.10.0.100`

| Роль | Хост | IP |
|---|---|---|
| proxy | proxy01 | 10.10.0.11 |
| proxy | proxy02 | 10.10.0.12 |
| zookeeper | zk01 | 10.10.0.21 |
| zookeeper | zk02 | 10.10.0.22 |
| zookeeper | zk03 | 10.10.0.23 |
| clickhouse shard1 | ch-s1-r1 | 10.10.0.31 |
| clickhouse shard1 | ch-s1-r2 | 10.10.0.32 |
| clickhouse shard1 | ch-s1-r3 | 10.10.0.33 |
| clickhouse shard2 | ch-s2-r1 | 10.10.0.41 |
| clickhouse shard2 | ch-s2-r2 | 10.10.0.42 |
| clickhouse shard2 | ch-s2-r3 | 10.10.0.43 |
| clickhouse shard3 | ch-s3-r1 | 10.10.0.51 |
| clickhouse shard3 | ch-s3-r2 | 10.10.0.52 |
| clickhouse shard3 | ch-s3-r3 | 10.10.0.53 |

FQDN: `*.dc.local` (пример: `proxy01.dc.local`, `ch-s3-r2.dc.local`).

---

## 1) Что нужно на управляющей машине (control node)

Минимум:
- `python3`, `ssh`, `make`
- `ansible` (core)

Рекомендуется:
- `ansible-lint`, `yamllint`

---

## 2) Подготовка SSH (важно для автодеплоя)

В инвентаре (`ansible/inventories/lab/hosts.ini`) задан:
- `ansible_user=admin`

Требования:
- на узлах есть пользователь `admin`
- `admin` входит в группу `admin` (или имеет sudo)
- SSH по ключу (без пароля)

Проверка:
```bash
cd ansible
ansible all -m ping
```

---

## 3) ClickHouse офлайн (самое важное)

### 3.1. Положи .deb пакеты в репозиторий

Скопируй `.deb` ClickHouse в папку:
```
ansible/artifacts/clickhouse/deb/
```

Обычно нужны:
- `clickhouse-common-static_*.deb`
- `clickhouse-server_*.deb`
- `clickhouse-client_*.deb`

Роль `role_clickhouse`:
- копирует `.deb` на хост в `/tmp/clickhouse-deb/`
- ставит их через `apt` локально
- раскладывает конфиги кластера и users
- создаёт демо-таблицы ReplicatedMergeTree + Distributed

---

## 4) Запуск (Makefile)

### 4.1. Bootstrap (общая подготовка узлов)
```bash
cd ansible
make bootstrap
```

Ставит базовые пакеты, настраивает sshd hardening и т.д.

### 4.2. Полный деплой
```bash
make deploy
```

Порядок:
`common → dns → fw → zk → ch → nginx → keepalived`

### 4.3. Проверки (acceptance)
```bash
make test
```

Артефакты:
- `ansible/checks/vip-failover.txt`
- `ansible/checks/proxy-lb.txt`
- `ansible/checks/proxy-fail-node.txt`
- `ansible/checks/zk-quorum.txt`
- `ansible/checks/ch-health.txt`
- `ansible/checks/routes-ports.txt`

---

## 5) Отказы (fault injection)

### ClickHouse нода down/up (демо)
```bash
make fault-ch
make test
```

### ZooKeeper нода down (демо)
```bash
make fault-zk
make test
```

---

## 6) Уничтожение стенда (best-effort)
```bash
make destroy
```

Останавливает сервисы и удаляет конфиги (пакеты удаляет best-effort).

---

## 7) Где что настраивается

- Инвентарь: `ansible/inventories/lab/hosts.ini`
- Общие переменные: `ansible/inventories/lab/group_vars/all.yml`
- Переменные групп: `proxy.yml`, `zookeeper.yml`, `clickhouse.yml`
- Роли: `ansible/roles/*`
- Оркестрация: `ansible/playbooks/*`
- Логи Nginx JSON: `/var/log/nginx/access.json` на proxy нодах
- Лог смены VIP: `/var/log/keepalived-vip.log` на proxy нодах

---

## 8) Требования из задания — чем покрыто

- Идемпотентность: роли используют template/copy/service и безопасные проверки
- DNS: `dnsmasq` без upstream
- VRRP VIP: keepalived + notify scripts + GARP
- Nginx LB: upstream 9 нод, JSON access.log, /healthz
- ZK quorum: 3 ноды, `ruok` checks
- ClickHouse 3×3: cluster remote_servers.xml + zookeeper.xml + ReplicatedMergeTree + Distributed
- Firewall: drop + allow only required ports
- Checks: сохраняются как текстовые артефакты

---

## 9) Быстрый “чек-лист сдачи”

1) В `ansible/artifacts/clickhouse/deb/` лежат `.deb`.
2) `ansible -i inventories/lab/hosts.ini all -m ping` — OK.
3) `make deploy` — без падений.
4) `make test` — создал файлы в `ansible/checks/`.
5) VIP failover выполнен и отражён в `vip-failover.txt`.
