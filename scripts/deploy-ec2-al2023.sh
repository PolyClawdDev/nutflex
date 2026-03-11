#!/bin/bash
# Run this script ON the EC2 instance (as ec2-user or root) to install and run neTV.
# Amazon Linux 2023, us-east-1.

set -e

echo "==> Installing system packages..."
sudo dnf install -y git python3.11 python3.11-pip nginx

# FFmpeg: try EPEL/crb, else install static build
if ! sudo dnf install -y ffmpeg 2>/dev/null; then
  echo "==> FFmpeg not in repos, installing static build..."
  cd /tmp
  curl -sLO https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-linux64-gpl.tar.xz
  tar xf ffmpeg-master-latest-linux64-gpl.tar.xz
  sudo mv ffmpeg-master-latest-linux64-gpl/bin/ffmpeg ffmpeg-master-latest-linux64-gpl/bin/ffprobe /usr/local/bin/
  rm -rf ffmpeg-master-latest-linux64-gpl*
  cd - >/dev/null
fi
ffmpeg -version || { echo "FFmpeg install failed"; exit 1; }

echo "==> Cloning app..."
cd /home/ec2-user
if [ -d nutflex ]; then
  cd nutflex && git pull
else
  git clone https://github.com/PolyClawdDev/nutflex.git
  cd nutflex
fi

echo "==> Creating virtualenv and installing Python deps..."
python3.11 -m venv .venv
.venv/bin/pip install --upgrade pip
.venv/bin/pip install -r requirements.txt

echo "==> Default source env (.env)..."
if [ ! -f .env ] && [ -f .env.example ]; then
  cp .env.example .env
  echo "    Created .env from .env.example — edit with your IPTV URL/user/pass and run: sudo systemctl restart netv"
elif [ ! -f .env ]; then
  echo "    No .env found. Create one with NETV_DEFAULT_SOURCE_URL, USER, PASS (see .env.example) so the app starts with a default source."
fi

echo "==> Creating systemd service..."
sudo tee /etc/systemd/system/netv.service > /dev/null << 'SVC'
[Unit]
Description=neTV IPTV web app
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/home/ec2-user/nutflex
Environment="PATH=/home/ec2-user/nutflex/.venv/bin:/usr/local/bin:/usr/bin"
EnvironmentFile=-/home/ec2-user/nutflex/.env
ExecStart=/home/ec2-user/nutflex/.venv/bin/python -m uvicorn main:app --host 0.0.0.0 --port 8000
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SVC

sudo systemctl daemon-reload
sudo systemctl enable netv
sudo systemctl start netv

echo "==> Configuring nginx (reverse proxy to port 8000)..."
sudo tee /etc/nginx/conf.d/netv.conf > /dev/null << 'NGX'
server {
    listen 80;
    server_name _;
    client_max_body_size 50M;
    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }
}
NGX

sudo nginx -t && sudo systemctl enable nginx && sudo systemctl restart nginx

echo ""
echo "==> Done. neTV is running."
echo "    App:  http://127.0.0.1:8000"
echo "    Nginx: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)"
echo ""
echo "Next steps:"
echo "  1. In AWS Security Group, open inbound: 80 (HTTP), 443 (HTTPS)."
echo "  2. Point nutflexgang.xyz to this IP, then run: sudo dnf install -y certbot python3-certbot-nginx && sudo certbot --nginx -d www.nutflexgang.xyz -d nutflexgang.xyz"
echo "  3. To preload default IPTV source: edit /home/ec2-user/nutflex/.env (NETV_DEFAULT_SOURCE_*), then sudo systemctl restart netv."
echo "  4. First visit: create admin at /setup if needed; source from .env appears in Settings when no sources exist."
echo ""
