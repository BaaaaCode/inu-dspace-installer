#!/bin/bash
set -Eeuo pipefail

DOMAIN="dspace-isd.ddns.net"
DB_NAME="dspace"
DB_USER="dspace"
DB_PASSWORD="dspace"
DSPACE_VERSION="9.1"
SOLR_VERSION="9.6.1"
DSPACE_USER="dspace"
JAVA_HEAP_MIN="1g"
JAVA_HEAP_MAX="2g"
INSTALL_DIR="/opt"
DSPACE_DIR="/dspace"
BACKEND_PORT="8080"
FRONTEND_PORT="4000"
LOG_FILE="/var/log/dspace-install.log"

exec > >(tee -a "$LOG_FILE") 2>&1
trap 'echo "ERROR at line $LINENO"; exit 1' ERR

section() { echo ""; echo "==== $1 ===="; }

###############################################################################
# 0. SOLR 설치 (install.sh에서 실패한 부분 — 파일명 버그 + 권한 버그 수정)
###############################################################################
section "SOLR ${SOLR_VERSION} INSTALLATION"

if systemctl is-active --quiet solr 2>/dev/null; then
    echo "Solr already running. Skipping installation."
else
    cd /tmp

    # 기존에 남아있는 파일 정리
    rm -f solr.tgz solr-${SOLR_VERSION}.tgz install_solr_service.sh

    # 다운로드 (교수님 서버에서)
    wget -O solr-${SOLR_VERSION}.tgz \
        https://archive.apache.org/dist/solr/solr/${SOLR_VERSION}/solr-${SOLR_VERSION}.tgz

    # 설치 스크립트 추출
    tar xzf solr-${SOLR_VERSION}.tgz \
        solr-${SOLR_VERSION}/bin/install_solr_service.sh \
        --strip-components=2

    # Solr 설치 (올바른 파일명으로 전달)
    bash ./install_solr_service.sh solr-${SOLR_VERSION}.tgz -f

    # 디렉토리 권한 수정 (logs 폴더 생성 실패 방지)
    mkdir -p /opt/solr-${SOLR_VERSION}/server/logs
    chown -R solr:solr /opt/solr-${SOLR_VERSION}
    chown -R solr:solr /var/solr

    # 메모리 및 설정
    echo 'SOLR_OPTS="$SOLR_OPTS -Dsolr.config.lib.enabled=true -Xms512m -Xmx1024m"' \
        >> /etc/default/solr.in.sh

    systemctl enable solr
    systemctl restart solr

    echo "Solr ${SOLR_VERSION} installation complete."
fi

# Solr 상태 확인
systemctl is-active --quiet solr && echo "Solr: ONLINE (OK)" || { echo "Solr: FAILED"; exit 1; }

###############################################################################
# 1. DSpace 디렉토리
###############################################################################
section "DSPACE DIRECTORIES"
mkdir -p ${DSPACE_DIR}
chown -R ${DSPACE_USER}:${DSPACE_USER} ${DSPACE_DIR}

# 2. Backend 다운로드
section "BACKEND DOWNLOAD"
cd ${INSTALL_DIR}
wget -O dspace-backend.tar.gz \
    https://github.com/DSpace/DSpace/archive/refs/tags/dspace-${DSPACE_VERSION}.tar.gz
rm -rf dspace-source
tar -zxf dspace-backend.tar.gz
mv DSpace-dspace-${DSPACE_VERSION} dspace-source
chown -R ${DSPACE_USER}:${DSPACE_USER} dspace-source

# 3. local.cfg
section "LOCAL.CFG"
cat > /opt/dspace-source/dspace/config/local.cfg <<EOF
dspace.dir = ${DSPACE_DIR}
dspace.ui.url = https://${DOMAIN}
dspace.server.url = https://${DOMAIN}/server
dspace.name = DSpace at ${DOMAIN}
db.url = jdbc:postgresql://localhost:5432/${DB_NAME}
db.driver = org.postgresql.Driver
db.username = ${DB_USER}
db.password = ${DB_PASSWORD}
solr.server = http://localhost:8983/solr
EOF
chown ${DSPACE_USER}:${DSPACE_USER} /opt/dspace-source/dspace/config/local.cfg

# 4. pgcrypto 확장 설치 (Ant 빌드 전 필수)
section "PGCRYPTO EXTENSION"
sudo -u postgres psql -d ${DB_NAME} -c "CREATE EXTENSION IF NOT EXISTS pgcrypto;"

# 5. Maven + Ant 빌드
section "MAVEN BUILD (10~15분 소요)"
cd /opt/dspace-source
sudo -u ${DSPACE_USER} bash -c "source /etc/profile.d/maven.sh && mvn package -DskipTests"

section "ANT INSTALL"
cd dspace/target/dspace-installer
sudo -u ${DSPACE_USER} ant fresh_install

# 5. Solr 코어 복사
section "SOLR CORES"
cp -r ${DSPACE_DIR}/solr/* /var/solr/data/
chown -R solr:solr /var/solr/data/*
systemctl restart solr
sleep 5

# 6. DB 마이그레이션
section "DB MIGRATION"
sudo -u ${DSPACE_USER} ${DSPACE_DIR}/bin/dspace database migrate
sudo -u ${DSPACE_USER} ${DSPACE_DIR}/bin/dspace database info

# 7. 인덱싱
section "INDEXING"
sudo -u ${DSPACE_USER} ${DSPACE_DIR}/bin/dspace index-discovery -b

# 8. Backend 서비스
section "BACKEND SERVICE"
cat > /etc/systemd/system/dspace-backend.service <<EOF
[Unit]
Description=DSpace Backend
After=network.target postgresql.service solr.service

[Service]
Type=simple
User=${DSPACE_USER}
WorkingDirectory=${DSPACE_DIR}
Environment="JAVA_OPTS=-Xms${JAVA_HEAP_MIN} -Xmx${JAVA_HEAP_MAX}"
ExecStart=/usr/bin/java \$JAVA_OPTS -jar ${DSPACE_DIR}/webapps/server-boot.jar
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable dspace-backend
systemctl restart dspace-backend

# 9. Frontend 다운로드 + 빌드
section "FRONTEND DOWNLOAD"
cd ${INSTALL_DIR}
wget -O dspace-frontend.tar.gz \
    https://github.com/DSpace/dspace-angular/archive/refs/tags/dspace-${DSPACE_VERSION}.tar.gz
rm -rf dspace-angular
tar -zxf dspace-frontend.tar.gz
mv dspace-angular-dspace-${DSPACE_VERSION} dspace-angular
chown -R ${DSPACE_USER}:${DSPACE_USER} dspace-angular

mkdir -p /opt/dspace-angular/config
cat > /opt/dspace-angular/config/config.prod.yml <<EOF
ui:
  ssl: false
  host: localhost
  port: ${FRONTEND_PORT}
  nameSpace: /
  baseUrl: https://${DOMAIN}
rest:
  ssl: true
  host: ${DOMAIN}
  port: 443
  nameSpace: /server
EOF
chown -R ${DSPACE_USER}:${DSPACE_USER} /opt/dspace-angular

section "FRONTEND BUILD (10~15분 소요)"
cd /opt/dspace-angular
sudo -u ${DSPACE_USER} npm install
sudo -u ${DSPACE_USER} npm run build:prod

# 10. PM2
section "PM2 SETUP"
sudo -u ${DSPACE_USER} pm2 delete dspace-ui || true
sudo -u ${DSPACE_USER} bash -c "cd /opt/dspace-angular && pm2 start 'npm run serve:ssr' --name dspace-ui"
sudo -u ${DSPACE_USER} pm2 save
PM2_STARTUP_CMD=$(sudo -u ${DSPACE_USER} pm2 startup systemd -u ${DSPACE_USER} --hp /home/${DSPACE_USER} | grep "sudo env" || true)
if [ -n "$PM2_STARTUP_CMD" ]; then eval "$PM2_STARTUP_CMD"; fi

# 11. SSL + Nginx
section "SSL & NGINX"
apt install -y certbot python3-certbot-nginx

cat > /etc/nginx/sites-available/dspace <<EOF
server {
    listen 80;
    server_name ${DOMAIN};
    client_max_body_size 2G;
    location /.well-known/acme-challenge/ { root /var/www/html; }
    location /server/ {
        proxy_pass http://localhost:${BACKEND_PORT}/server/;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    location / {
        proxy_pass http://localhost:${FRONTEND_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
ln -sf /etc/nginx/sites-available/dspace /etc/nginx/sites-enabled/dspace
rm -f /etc/nginx/sites-enabled/default || true
systemctl restart nginx

mkdir -p /etc/letsencrypt/live/${DOMAIN}
if certbot certonly --webroot -w /var/www/html -d ${DOMAIN} --non-interactive --agree-tos --email webmaster@${DOMAIN}; then
    echo "SSL 인증서 발급 성공!"
else
    echo "SSL 실패 - 자체 서명 인증서 생성"
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/letsencrypt/live/${DOMAIN}/privkey.pem \
        -out /etc/letsencrypt/live/${DOMAIN}/fullchain.pem \
        -subj "/CN=${DOMAIN}"
fi

# HTTPS Nginx 설정
cat > /etc/nginx/sites-available/dspace <<EOF
server {
    listen 80;
    server_name ${DOMAIN};
    location /.well-known/acme-challenge/ { root /var/www/html; }
    location / { return 301 https://\$host\$request_uri; }
}
server {
    listen 443 ssl;
    server_name ${DOMAIN};
    client_max_body_size 2G;
    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    location /server/ {
        proxy_pass http://localhost:${BACKEND_PORT}/server/;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-Proto https;
    }
    location / {
        proxy_pass http://localhost:${FRONTEND_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-Proto https;
    }
}
EOF
nginx -t
systemctl restart nginx

section "설치 완료!"
echo "DSpace: https://${DOMAIN}"
echo "REST API: https://${DOMAIN}/server"
