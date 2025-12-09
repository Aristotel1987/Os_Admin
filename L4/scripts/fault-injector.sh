#!/usr/bin/env bash


set -euo pipefail

SSH_USER="${SSH_USER:-root}"

log() {
  echo "[fault] $*" >&2
}

run_ssh() {
  local host="$1"; shift
  log "SSH ${host}: $*"
  ssh -o BatchMode=yes "${SSH_USER}@${host}" "$@"
}

usage() {
  cat <<EOF
Использование: $0 <команда> [аргументы]
  vip-failover         – остановить keepalived на proxy01 (VIP должен уйти на proxy02)
  vip-restore          – запустить keepalived на proxy01 и proxy02
  ch-down <host>       – остановить ClickHouse на указанной ноде (ch-sX-rY.dc.local)
  ch-up   <host>       – запустить ClickHouse на указанной ноде
  zk-quorum            – остановить zk03 и zk02 (оставив только zk01) – потеря кворума
  zk-restore           – запустить zk02 и zk03 обратно
Примеры:
  $0 vip-failover
  $0 ch-down ch-s1-r1.dc.local
  $0 zk-quorum
EOF
}

cmd_vip_failover() {
  log "Имитация отказа master-прокси: stop keepalived на proxy01"
  run_ssh proxy01.dc.local "systemctl stop keepalived"
  log "Теперь VIP должен перейти на proxy02 (проверь ip a на proxy01/proxy02)."
}

cmd_vip_restore() {
  log "Восстановление keepalived на proxy01/proxy02"
  run_ssh proxy01.dc.local "systemctl start keepalived"
  run_ssh proxy02.dc.local "systemctl start keepalived"
}

cmd_ch_down() {
  local host="$1"
  log "Остановка ClickHouse на ${host}"
  run_ssh "${host}" "systemctl stop clickhouse-server"
}

cmd_ch_up() {
  local host="$1"
  log "Запуск ClickHouse на ${host}"
  run_ssh "${host}" "systemctl start clickhouse-server"
}

cmd_zk_quorum() {
  log "Имитация потери кворума ZooKeeper: гасим zk03 и zk02 (остаётся только zk01)"
  run_ssh zk03.dc.local "systemctl stop zookeeper.service || systemctl stop zookeeper-zk03.service || true"
  run_ssh zk02.dc.local "systemctl stop zookeeper.service || systemctl stop zookeeper-zk02.service || true"
  log "Теперь у кластера 1/3 ZK; ClickHouse должен перейти в read-only на DDL/INSERT."
}

cmd_zk_restore() {
  log "Восстановление кворума ZooKeeper: поднимаем zk02 и zk03"
  run_ssh zk02.dc.local "systemctl start zookeeper.service || systemctl start zookeeper-zk02.service || true"
  run_ssh zk03.dc.local "systemctl start zookeeper.service || systemctl start zookeeper-zk03.service || true"
}

main() {
  local cmd="${1:-}"
  case "${cmd}" in
    vip-failover)
      cmd_vip_failover
      ;;
    vip-restore)
      cmd_vip_restore
      ;;
    ch-down)
      [[ $# -ge 2 ]] || { echo "Нужен host (ch-sX-rY.dc.local)"; usage; exit 1; }
      cmd_ch_down "$2"
      ;;
    ch-up)
      [[ $# -ge 2 ]] || { echo "Нужен host (ch-sX-rY.dc.local)"; usage; exit 1; }
      cmd_ch_up "$2"
      ;;
    zk-quorum)
      cmd_zk_quorum
      ;;
    zk-restore)
      cmd_zk_restore
      ;;
    ""|-h|--help)
      usage
      ;;
    *)
      echo "Неизвестная команда: ${cmd}"
      usage
      exit 1
      ;;
  esac
}

main "$@"
