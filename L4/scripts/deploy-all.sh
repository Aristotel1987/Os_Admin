#!/usr/bin/env bash

set -euo pipefail

SSH_USER="${SSH_USER:-root}"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PROXIES=(proxy01.dc.local proxy02.dc.local)
ZK_NODES=(zk01.dc.local zk02.dc.local zk03.dc.local)
CH_NODES=(
  ch-s1-r1.dc.local ch-s1-r2.dc.local ch-s1-r3.dc.local
  ch-s2-r1.dc.local ch-s2-r2.dc.local ch-s2-r3.dc.local
  ch-s3-r1.dc.local ch-s3-r2.dc.local ch-s3-r3.dc.local
)

log() {
  echo "[deploy] $*" >&2
}

run_ssh() {
  local host="$1"; shift
  log "SSH ${host}: $*"
  ssh -o BatchMode=yes "${SSH_USER}@${host}" "$@"
}

deploy_zookeeper() {

  for node in "${ZK_NODES[@]}"; do
    short="${node%%.*}"   # zk01 / zk02 / zk03
    log "-> ${node}"

    run_ssh "${node}" "mkdir -p /etc/zookeeper /var/lib/zookeeper && chown -R zookeeper:zookeeper /var/lib/zookeeper || true"

    scp "${REPO_DIR}/zookeeper/zoo.cfg" "${SSH_USER}@${node}:/etc/zookeeper/zoo.cfg"

    if [[ -f "${REPO_DIR}/zookeeper/myid.${short}" ]]; then
      scp "${REPO_DIR}/zookeeper/myid.${short}" "${SSH_USER}@${node}:/var/lib/zookeeper/myid"
      run_ssh "${node}" "chown zookeeper:zookeeper /var/lib/zookeeper/myid"
    fi

    if [[ -f "${REPO_DIR}/zookeeper/systemd/zookeeper-${short}.service" ]]; then
      scp "${REPO_DIR}/zookeeper/systemd/zookeeper-${short}.service" \
        "${SSH_USER}@${node}:/etc/systemd/system/zookeeper.service"
    elif [[ -f "${REPO_DIR}/zookeeper/systemd/zookeeper-zk01.service" ]]; then
      # fallback: один и тот же юнит везде
      scp "${REPO_DIR}/zookeeper/systemd/zookeeper-zk01.service" \
        "${SSH_USER}@${node}:/etc/systemd/system/zookeeper.service"
    fi

    run_ssh "${node}" "systemctl daemon-reload && systemctl enable --now zookeeper.service"
  done
}

deploy_clickhouse() {
  for node in "${CH_NODES[@]}"; do
    log "-> ${node}"

    run_ssh "${node}" "mkdir -p /etc/clickhouse-server/config.d /etc/clickhouse-server/users.d"

    # Zookeeper + cluster config
    scp "${REPO_DIR}/clickhouse/config.d/zookeeper.xml"      "${SSH_USER}@${node}:/etc/clickhouse-server/config.d/zookeeper.xml"
    scp "${REPO_DIR}/clickhouse/config.d/remote_servers.xml" "${SSH_USER}@${node}:/etc/clickhouse-server/config.d/remote_servers.xml"

    # users.d/*
    scp "${REPO_DIR}/clickhouse/users.d/"*.xml "${SSH_USER}@${node}:/etc/clickhouse-server/users.d/"

    # systemd-юнит (если нужен свой)
    if [[ -f "${REPO_DIR}/clickhouse/systemd/clickhouse-server.service" ]]; then
      scp "${REPO_DIR}/clickhouse/systemd/clickhouse-server.service" \
        "${SSH_USER}@${node}:/etc/systemd/system/clickhouse-server.service"
      run_ssh "${node}" "systemctl daemon-reload"
    fi

    run_ssh "${node}" "systemctl enable --now clickhouse-server"

    scp "${REPO_DIR}/clickhouse/create_tables.sql" "${SSH_USER}@${node}:/tmp/create_tables.sql"
    run_ssh "${node}" "clickhouse-client -n < /tmp/create_tables.sql || true"
  done
}

deploy_nginx_keepalived() {
  log "=== Развёртывание Nginx + keepalived на proxy01/proxy02 ==="

  for node in "${PROXIES[@]}"; do
    log "-> Nginx на ${node}"
    run_ssh "${node}" "mkdir -p /etc/nginx/conf.d"

    scp "${REPO_DIR}/nginx/upstream.conf" "${SSH_USER}@${node}:/etc/nginx/conf.d/upstream.conf"

    if [[ -f "${REPO_DIR}/nginx/mime.types" ]]; then
      scp "${REPO_DIR}/nginx/mime.types" "${SSH_USER}@${node}:/etc/nginx/mime.types"
    fi

    if [[ -f "${REPO_DIR}/nginx/systemd/nginx.service" ]]; then
      scp "${REPO_DIR}/nginx/systemd/nginx.service" \
        "${SSH_USER}@${node}:/etc/systemd/system/nginx.service"
      run_ssh "${node}" "systemctl daemon-reload"
    fi

    run_ssh "${node}" "systemctl enable --now nginx"
  done


  scp "${REPO_DIR}/keepalived/proxy01-keepalived.conf" \
      "${SSH_USER}@proxy01.dc.local:/etc/keepalived/keepalived.conf"
  run_ssh "proxy01.dc.local" "systemctl enable --now keepalived"

  log "-> keepalived proxy02 (BACKUP)"
  scp "${REPO_DIR}/keepalived/proxy02-keepalived.conf" \
      "${SSH_USER}@proxy02.dc.local:/etc/keepalived/keepalived.conf"
  run_ssh "proxy02.dc.local" "systemctl enable --now keepalived"
}

deploy_firewalls() {
  log "=== Применение iptables-правил ==="

  apply_fw() {
    local node="$1"
    local rules_file="$2"
    [[ -f "${rules_file}" ]] || { log "[WARN] нет ${rules_file}, пропуск ${node}"; return; }
    log "-> firewall для ${node} (${rules_file})"
    scp "${rules_file}" "${SSH_USER}@${node}:/tmp/firewall.rules"
    run_ssh "${node}" "iptables-restore < /tmp/firewall.rules"
  }

  apply_fw "proxy01.dc.local" "${REPO_DIR}/net/firewall/proxy01.rules"
  apply_fw "proxy02.dc.local" "${REPO_DIR}/net/firewall/proxy02.rules"

  apply_fw "zk01.dc.local" "${REPO_DIR}/net/firewall/zk01.rules"
  apply_fw "zk02.dc.local" "${REPO_DIR}/net/firewall/zk02.rules"
  apply_fw "zk03.dc.local" "${REPO_DIR}/net/firewall/zk03.rules"

  for node in "${CH_NODES[@]}"; do
    short="${node%%.*}"
    apply_fw "${node}" "${REPO_DIR}/net/firewall/${short}.rules"
  done
}

main() {
  log "Старт развёртывания. REPO_DIR=${REPO_DIR}, SSH_USER=${SSH_USER}"
  deploy_zookeeper
  deploy_clickhouse
  deploy_nginx_keepalived
  deploy_firewalls
  log "Развёртывание завершено."
}

main "$@"
