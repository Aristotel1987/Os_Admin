#!/usr/bin/env bash
set -euo pipefail
echo "$(date -Is) BACKUP $(hostname)" >> /var/log/keepalived-vip.log
