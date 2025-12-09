CREATE DATABASE IF NOT EXISTS lab;

USE lab;

CREATE TABLE IF NOT EXISTS t_demo
(
    dt DateTime DEFAULT now(),
    id UInt64,
    value String
)
ENGINE = ReplicatedMergeTree(
    '/clickhouse/tables/{shard}/t_demo',
    '{replica}'
)
ORDER BY (dt, id);

CREATE TABLE IF NOT EXISTS t_demo_dist
(
    dt DateTime,
    id UInt64,
    value String
)
ENGINE = Distributed(cluster_3x3, lab, t_demo, rand());
