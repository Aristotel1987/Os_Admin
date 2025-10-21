# Nginx-прокси во внутренней сети с двумя бэкендами
## Топология
3 узла во «серой» сети 
Хост
Роль
Имя (DNS)
IP
proxy01 
reverse-proxy (nginx)
proxy01.dc.local 
10.100.0.1 
app01 
backend#1 (HTTP :8080)
app01.dc.local 
10.100.0.2	
app02 
backend#2 (HTTP :8080)
app02.dc.local
10.100.0.3	

# На всех узлах синхронизируй время и хостнеймы; настрой /etc/hosts или DNS.
# Далее — по узлам:

# === app01 и app02 ===
sudo apt -y update && sudo apt -y install python3 # /etc/systemd/system
# Скопируй из repo: app/app.py и app/systemd/simple-backend@.service
sudo cp app/app.py /opt/simple-backend/app.py
sudo cp app/systemd/simple-backend@.service /etc/systemd/system/simple-backend@.service
sudo usermod -a -G www-data $USER || true
sudo systemctl daemon-reload
sudo systemctl enable --now simple-backend@app01   # на app01
sudo systemctl enable --now simple-backend@app02   # на app02

# === proxy01 ===
sudo apt -y update && sudo apt -y install nginx
sudo mkdir -p /etc/nginx/conf.d
# Скопируй из repo: proxy/nginx.conf.d/app.conf
sudo cp proxy/nginx.conf.d/app.conf /etc/nginx/conf.d/app.conf
sudo nginx -t && sudo systemctl enable --now nginx
 DNS: положи в dns/ зону dc.local (bind9/dnsmasq) с тремя A-записями proxy01, app01, app02.
10.100.0.1 	proxy01.dc.local
10.100.0.2	app01.dc.local
10.100.0.3	app02.dc.local
2) Мини-бэкенды (app01, app02)
Python:
from http.server import BaseHTTPRequestHandler, HTTPServer
import os, socket, datetime
NAME = os.environ.get("APP_NAME", socket.gethostname())

class H(BaseHTTPRequestHandler):
    def do_GET(self):
        body = f"backend={NAME} host={socket.gethostname()} time={datetime.datetime.utcnow().isoformat()}Z\n"
        self.send_response(200); self.send_header("Content-Type","text/plain"); self.end_headers()
        self.wfile.write(body.encode())
    def log_message(self, fmt, *args): return

HTTPServer(("0.0.0.0", int(os.environ.get("PORT","8080"))), H).serve_forever()
systemd-юнит app/systemd/simple-backend@.service:
ini

[Service]
Environment=APP_NAME=%i PORT=8080
ExecStart=/usr/bin/python3 /opt/simple-backend/app.py
Restart=always
User=www-data
Group=www-data

[Install]
WantedBy=multi-user.target
Установка (на каждом из app01/app02):

sudo install -d -o root -g root /opt/simple-backend
sudo cp app/app.py /opt/simple-backend/app.py
sudo cp app/systemd/simple-backend@.service /etc/systemd/system/simple-backend@.service
sudo systemctl daemon-reload
# На app01:
sudo systemctl enable --now simple-backend@app01
# На app02:
sudo systemctl enable --now simple-backend@app02
Проверка локально:
curl -s http://localhost:8080/
Сетевая безопасность (файрвол)
ufw 
На app01 и app02:
sudo apt -y install ufw
sudo ufw default deny incoming
sudo ufw default allow outgoing
# Разрешить 8080 только от proxy01
sudo ufw allow from 10.10.0.10 to any port 8080 proto tcp
sudo ufw enable
sudo ufw status verbose
На proxy01 ограничить входящие):

sudo ufw default deny incoming
sudo ufw allow 80/tcp
sudo ufw enable

#!/usr/bin/env bash
set -euo pipefail

echo "# DNS" > checks/dns.txt
{
  host app01.dc.local
  host app02.dc.local
  host proxy01.dc.local
} >> checks/dns.txt 2>&1 || true

echo "# Backends from proxy01" > checks/backend.txt
{
  curl -s http://app01.dc.local:8080/
  curl -s http://app02.dc.local:8080/
} >> checks/backend.txt

echo "# Round-robin via proxy01" > checks/proxy-roundrobin.txt
for i in {1..10}; do curl -s http://proxy01.dc.local/; done >> checks/proxy-roundrobin.txt

echo "# Access log sample (first 10 lines)" > checks/access-sample.json
sudo head -n 10 /var/log/nginx/access.json >> checks/access-sample.json || true

# Failover
echo "# Failover test" > checks/failover.txt
echo "Stopping app02..." | tee -a checks/failover.txt
sudo systemctl stop simple-backend@app02
for i in {1..5}; do
  out="$(curl -s http://proxy01.dc.local/)"
  echo "$out" | tee -a checks/failover.txt
  sleep 0.3
done
echo "--- last 10 access log lines during failover ---" >> checks/failover.txt
sudo tail -n 10 /var/log/nginx/access.json >> checks/failover.txt || true

echo "Starting app02..." | tee -a checks/failover.txt
sudo systemctl start simple-backend@app02
sleep 2
for i in {1..6}; do
  curl -s http://proxy01.dc.local/ | tee -a checks/failover.txt
  sleep 0.3
done
echo "--- last 10 access log lines after recovery ---" >> checks/failover.txt
sudo tail -n 10 /var/log/nginx/access.json >> checks/failover.txt || true

echo "Done. See checks/ directory."
Сделай исполняемым:

chmod +x checks/run_all.sh

# Диагностика :
• 
sudo journalctl -u simple-backend@app01 -f,
• 
sudo tail -f /var/log/nginx/access.json,
• 
curl -v http://proxy01.dc.local/ и curl -v http://app01.dc.local:8080/ с --resolve, если надо. 
