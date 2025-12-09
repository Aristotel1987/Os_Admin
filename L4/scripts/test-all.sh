#!/usr/bin/env bash
set -euo pipefail

SSH_USER="${SSH_USER:-root}"
VIP="${VIP:-10.10.0.100}"

PROXIES=(proxy01.dc.local proxy02.dc.local)
ZK_NODES=(zk01.dc.local zk02.dc.local zk03.dc.local)
CH_SAMPLE="ch-s1-r1.dc.local"   

log() {
  echo "[test] $*" >&2
}

run_ssh() {
  local host="$1"; shift
  log "SSH ${host}: $*"
  ssh -o BatchMode=yes "${SSH_USER}@${host}" "$@"
}

confirm() {
  local msg="$1"
  read -r -p "${msg} [y/N]: " ans
  case "${ans}" in
    y|Y|yes|YES) return 0 ;;
    *)           return 1 ;;
  esac
}

section() {
  echo
  echo "============================================================"
  echo ">>> $*"
  echo "============================================================"
}

test_vip_failover() {
  section "1) VIP failover (VRRP)"

  log "Исходное состояние VIP:"
  run_ssh "${PROXIES[0]}" "ip a | grep -A2 '10.10.0'"
  run_ssh "${PROXIES[1]}" "ip a | grep -A2 '10.10.0'"

  if confirm "Остановить keepalived на proxy01 для проверки failover?"; then
    run_ssh "${PROXIES[0]}" "systemctl stop keepalived"
    log "Ждём 5 секунд..."
    sleep 5
    log "Смотрим VIP после остановки keepalived на proxy01:"
    run_ssh "${PROXIES[0]}" "ip a | grep -A2 '10.10.0' || true"
    run_ssh "${PROXIES[1]}" "ip a | grep -A2 '10.10.0' || true"

    if confirm "Вернуть keepalived на proxy01 (start)?"; then
      run_ssh "${PROXIES[0]}" "systemctl start keepalived"
      sleep 5
      log "Состояние VIP после восстановления:"
      run_ssh "${PROXIES[0]}" "ip a | grep -A2 '10.10.0' || true"
      run_ssh "${PROXIES[1]}" "ip a | grep -A2 '10.10.0' || true"
    fi
  else
    log "Шаг с остановкой keepalived пропущен по запросу пользователя."
  fi
}

test_proxy_lb() {
  section "2) Балансировка на Nginx (round-robin)"

  log "Делаем 20 запросов к VIP через curl"
  for i in $(seq 1 20); do
    resp="$(curl -s "http://${VIP}/?query=SELECT%201" || echo "ERR")"
    printf "%2d: %s\n" "$i" "$resp"
  done

  log "Вывод последних строк access_clickhouse.json на proxy01:"
  run_ssh "${PROXIES[0]}" "tail -n 20 /var/log/nginx/access_clickhouse.json || echo 'нет файла access_clickhouse.json'"
}

test_ch_fail_node() {
  section "3) Выпадение одной ClickHouse-ноды"

  local victim="ch-s1-r1.dc.local"

  if confirm "Остановить clickhouse-server на ${victim}?"; then
    run_ssh "${victim}" "systemctl stop clickhouse-server"
    log "Ждём пару секунд..."
    sleep 3

    log "10 запросов к VIP после выключения ${victim}:"
    for i in $(seq 1 10); do
      resp="$(curl -s "http://${VIP}/?query=SELECT%201" || echo "ERR")"
      printf "%2d: %s\n" "$i" "$resp"
    done

    log "Последние строки access_clickhouse.json (proxy01):"
    run_ssh "${PROXIES[0]}" "tail -n 30 /var/log/nginx/access_clickhouse.json || echo 'нет файла access_clickhouse.json'"

    if confirm "Запустить clickhouse-server на ${victim} обратно?"; then
      run_ssh "${victim}" "systemctl start clickhouse-server"
      sleep 5
      log "Ещё 10 запросов к VIP после восстановления ${victim}:"
      for i in $(seq 1 10); do
        resp="$(curl -s "http://${VIP}/?query=SELECT%201" || echo "ERR")"
        printf "%2d: %s\n" "$i" "$resp"
      done
    fi
  else
    log "Шаг с остановкой ClickHouse-ноды пропущен."
  fi
}

test_zk_quorum() {
  section "4) ZooKeeper кворум и read-only ClickHouse"

  log "Проверяем состояние ZK (ruok на 3 нодах):"
  for node in "${ZK_NODES[@]}"; do
    run_ssh "${node}" "echo ruok | nc 127.0.0.1 2181 || echo 'ruok failed'"
  done

  log "Пробуем INSERT на ${CH_SAMPLE} до отказов:"
  run_ssh "${CH_SAMPLE}" "clickhouse-client -q \"INSERT INTO lab.t_demo (id, value) VALUES (rand(), 'before_fail')\" || true"

  if confirm "Остановить zk03 для потери 1 ноды (2/3 кворума)?"; then
    run_ssh zk03.dc.local "systemctl stop zookeeper.service || systemctl stop zookeeper-zk03.service || true"
    sleep 3
    log "INSERT после остановки zk03 (2/3 кворума):"
    run_ssh "${CH_SAMPLE}" "clickhouse-client -q \"INSERT INTO lab.t_demo (id, value) VALUES (rand(), 'after_1_fail')\" || true"
  else
    log "Шаг с остановкой zk03 пропущен."
  fi

  if confirm "Остановить zk02 (останется только zk01, потеря кворума)?"; then
    run_ssh zk02.dc.local "systemctl stop zookeeper.service || systemctl stop zookeeper-zk02.service || true"
    sleep 3
    log "INSERT при потере кворума (ожидаем ошибку / read-only):"
    run_ssh "${CH_SAMPLE}" "clickhouse-client -q \"INSERT INTO lab.t_demo (id, value) VALUES (rand(), 'no_quorum')\" || true"
    log "SELECT (должен работать):"
    run_ssh "${CH_SAMPLE}" "clickhouse-client -q \"SELECT count() FROM lab.t_demo\" || true"
  else
    log "Шаг с остановкой zk02 пропущен."
  fi

  if confirm "Восстановить zk02 и zk03?"; then
    run_ssh zk02.dc.local "systemctl start zookeeper.service || systemctl start zookeeper-zk02.service || true"
    run_ssh zk03.dc.local "systemctl start zookeeper.service || systemctl start zookeeper-zk03.service || true"
    sleep 5
    log "INSERT после восстановления кворума:"
    run_ssh "${CH_SAMPLE}" "clickhouse-client -q \"INSERT INTO lab.t_demo (id, value) VALUES (rand(), 'recovered')\" || true"
  fi
}

test_ch_health() {
  section "5) Состояние кластера ClickHouse"

  log "SELECT hostName(), cluster() через VIP:"
  curl -s "http://${VIP}/?query=SELECT%20hostName(),%20cluster()%20FORMAT%20TabSeparated" || echo "curl error"

  log "system.clusters на ${CH_SAMPLE}:"
  run_ssh "${CH_SAMPLE}" "clickhouse-client -q \"SELECT cluster, shard_num, replica_num, host_name, host_address, port FROM system.clusters WHERE cluster='cluster_3x3' ORDER BY shard_num, replica_num FORMAT PrettyCompact\" || true"

  log "system.replicas по lab.t_demo на ${CH_SAMPLE}:"
  run_ssh "${CH_SAMPLE}" "clickhouse-client -q \"SELECT database, table, is_readonly, is_session_expired, future_parts, queue_size, total_replicas, active_replicas FROM system.replicas WHERE database='lab' AND table='t_demo' FORMAT PrettyCompact\" || true"
}

test_routes_ports() {
  section "6) Порты и маршруты"

  log "proxy01: порты и маршруты:"
  run_ssh proxy01.dc.local "ss -ltnp | grep -E ':(80|8123|9000|2181|2888|3888)\\b' || true"
  run_ssh proxy01.dc.local "ip a"
  run_ssh proxy01.dc.local "ip r"

  log "ch-s1-r1: порты и маршруты:"
  run_ssh ch-s1-r1.dc.local "ss -ltnp | grep -E ':(80|8123|9000|2181|2888|3888)\\b' || true"
  run_ssh ch-s1-r1.dc.local "ip a"
  run_ssh ch-s1-r1.dc.local "ip r"

  log "zk01: порты и маршруты:"
  run_ssh zk01.dc.local "ss -ltnp | grep -E ':(80|8123|9000|2181|2888|3888)\\b' || true"
  run_ssh zk01.dc.local "ip a"
  run_ssh zk01.dc.local "ip r"
}

main() {
  section "Сводный тест стенда"
  echo "SSH_USER=${SSH_USER}, VIP=${VIP}"
  echo "Хосты:"
  echo "  Прокси:    ${PROXIES[*]}"
  echo "  ZooKeeper: ${ZK_NODES[*]}"
  echo "  CH sample: ${CH_SAMPLE}"
  echo

  test_vip_failover
  test_proxy_lb
  test_ch_fail_node
  test_zk_quorum
  test_ch_health
  test_routes_ports

  echo
  echo "Тестирование завершено."
}

main "$@"
