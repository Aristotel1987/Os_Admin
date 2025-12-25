\
ANSIBLE=ansible-playbook -i inventories/lab/hosts.ini

bootstrap:
	$(ANSIBLE) playbooks/01_common.yml --tags common -e 'bootstrap=true'

deploy:
	$(ANSIBLE) playbooks/site.yml

deploy-core:
	$(ANSIBLE) playbooks/01_common.yml playbooks/02_dns.yml playbooks/03_firewall.yml

deploy-backend:
	$(ANSIBLE) playbooks/04_zookeeper.yml playbooks/05_clickhouse.yml

deploy-proxy:
	$(ANSIBLE) playbooks/06_nginx.yml playbooks/07_keepalived.yml

test:
	$(ANSIBLE) playbooks/99_checks.yml --tags checks

fault-ch:
	$(ANSIBLE) playbooks/fault_inject.yml --tags ch

fault-zk:
	$(ANSIBLE) playbooks/fault_inject.yml --tags zk

destroy:
	$(ANSIBLE) playbooks/destroy.yml
