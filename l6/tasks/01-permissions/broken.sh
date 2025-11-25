#!/usr/bin/env bash
set -euo pipefail
mkdir -p /tmp/secret-dir
chmod 0555 /tmp/secret-dir
exec 3> /tmp/secret-dir/data.txt
echo hello >&3