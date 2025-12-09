SSH_USER ?= student

all: help

help:
	@echo "Targets:"
	@echo "  deploy-all      - развернуть конфиги на всех узлах"
	@echo "  test-all        - выполнить все проверки и заполнить checks/"
	@echo "  deploy-zk       - развернуть ZooKeeper-конфиги"
	@echo "  deploy-ch       - развернуть ClickHouse-конфиги"
	@echo "  deploy-proxy    - развернуть Nginx и keepalived"
	@echo "  test-vip        - проверить VIP failover"
	@echo "  test-lb         - проверить балансировку Nginx"

deploy-all:
	bash scripts/deploy-all.sh

test-all:
	bash scripts/test-all.sh

deploy-zk:
	bash scripts/deploy-all.sh zk

deploy-ch:
	bash scripts/deploy-all.sh ch

deploy-proxy:
	bash scripts/deploy-all.sh proxy

test-vip:
	bash scripts/fault-injector.sh vip

test-lb:
	bash scripts/fault-injector.sh lb
