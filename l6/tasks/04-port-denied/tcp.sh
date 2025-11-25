#!/usr/bin/env bash
exec 3<>/dev/tcp/127.0.0.1/9999 || exit 1
echo ping >&3
cat <&3