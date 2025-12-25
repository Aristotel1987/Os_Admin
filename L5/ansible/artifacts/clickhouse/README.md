# ClickHouse офлайн-пакеты

Положи `.deb` пакеты ClickHouse в:
- `ansible/artifacts/clickhouse/deb/*.deb`

Роль `role_clickhouse` установит **все** `.deb` из этой папки локально.

Пример проверки на узле:
- `clickhouse-client --query "SELECT version()"`
