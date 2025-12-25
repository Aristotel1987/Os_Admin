#!/usr/bin/env bash
set -euo pipefail
echo "$(date -Is) MASTER $(hostname) vip=$(ip -4 addr show | grep -oE '10\.10\.0\.100/24' || true)" >> /var/log/keepalived-vip.log
