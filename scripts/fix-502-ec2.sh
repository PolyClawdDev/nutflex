#!/bin/bash
# Run this ON the EC2 (paste into SSH session) to fix 502. Or from your Mac: ssh -i ~/Desktop/IP.pem ec2-user@44.223.7.166 'bash -s' < scripts/fix-502-ec2.sh

set -e
cd /home/ec2-user/nutflex

echo "==> Stopping netv..."
sudo systemctl stop netv 2>/dev/null || true

echo "==> Checking app starts..."
export PATH="/home/ec2-user/nutflex/.venv/bin:$PATH"
cd /home/ec2-user/nutflex
if ! .venv/bin/python -c "
import sys
sys.path.insert(0, '/home/ec2-user/nutflex')
import main
print('App import OK')
" 2>&1; then
  echo "Import failed, trying uvicorn directly..."
  timeout 5 .venv/bin/python -m uvicorn main:app --host 127.0.0.1 --port 8000 2>&1 || true
fi

echo "==> Fixing systemd service..."
sudo tee /etc/systemd/system/netv.service > /dev/null << 'SVC'
[Unit]
Description=neTV IPTV web app
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/home/ec2-user/nutflex
Environment=PATH=/home/ec2-user/nutflex/.venv/bin:/usr/local/bin:/usr/bin
EnvironmentFile=-/home/ec2-user/nutflex/.env
ExecStart=/home/ec2-user/nutflex/.venv/bin/python -m uvicorn main:app --host 0.0.0.0 --port 8000
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SVC

sudo systemctl daemon-reload
sudo systemctl start netv
sleep 2
sudo systemctl status netv --no-pager || true

echo ""
echo "==> Testing port 8000..."
curl -s -o /dev/null -w "HTTP %{http_code}\n" http://127.0.0.1:8000/ || echo "Connection failed"
echo ""
echo "If you see HTTP 200/303 above, reload http://44.223.7.166 in your browser."
echo "If not, run: sudo journalctl -u netv -n 30 --no-pager"