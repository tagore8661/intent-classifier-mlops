#!/bin/bash
set -e

# 1. Setup Directory
export APP_DIR="/opt/intent-app"
mkdir -p $APP_DIR
cd $APP_DIR

# 2. Update System & Install Dependencies
apt-get update -y
apt-get install -y git python3 python3-venv python3-pip nginx

# 3. Clone Code
git clone -b virtual-machines https://github.com/tagore8661/intent-classifier-mlops.git .

# 4. Setup Virtual Env & Install Python Packages
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

# 5. Train Model (Generate .pkl)
python3 model/train.py

# 6. Configure Gunicorn as a Systemd Service
cat > /etc/systemd/system/gunicorn.service <<'EOF'
[Unit]
Description=Gunicorn instance to serve Intent Classifier
After=network.target

[Service]
User=ubuntu
Group=ubuntu
WorkingDirectory=/opt/intent-app
Environment="PATH=/usr/bin:/bin:/opt/intent-app/.venv/bin"
ExecStart=/opt/intent-app/.venv/bin/gunicorn --workers 3 --bind 127.0.0.1:6000 wsgi:app
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# 7. Configure Nginx as Reverse Proxy
cat > /etc/nginx/sites-available/default <<'EOF'
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:6000/predict;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout 60s;
        proxy_read_timeout 120s;
    }
}
EOF

# 8. Enable Nginx site
ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default


# 9. Start Services
systemctl daemon-reload
systemctl enable gunicorn
systemctl restart gunicorn
systemctl restart nginx