#!/bin/bash
###############################################################################
# Omeka Classic 3.2 Auto Installer for Ubuntu 22.04 LTS
#
# DSpace install.sh 패턴 기반 — 단계별 자동 skip + 실패 복구
#
# 기능:
#   - Apache2 + MariaDB + PHP 7.4 + Omeka Classic 원스크립트 설치
#   - 각 단계별 자동 skip (이미 완료된 단계는 건너뜀)
#   - --step N 옵션으로 특정 단계부터 강제 시작 가능
#   - --korean 옵션으로 한글 패치 적용
#   - --env gcp|local 로 환경 선택
#   - 실패 시 실패 지점, 원인, 로그 위치를 안내
#   - 재실행 시 완료된 단계를 자동으로 건너뛰고 실패 지점부터 재개
#
# 사용법:
#   sudo bash install_omeka.sh --env gcp           # GCP (도메인 + SSL)
#   sudo bash install_omeka.sh --env local          # 교내 서버 (IP + HTTP)
#   sudo bash install_omeka.sh --env gcp --korean   # GCP + 한글 패치
#   sudo bash install_omeka.sh --step 4             # 4단계부터 강제 시작
#   sudo bash install_omeka.sh --step 0             # 처음부터 전체 재실행
#
# 단계 목록:
#    0. 시스템 업데이트 + Swap + 방화벽 + 기본 패키지
#    1. Apache2 설치
#    2. MariaDB 설치 + DB/유저 생성
#    3. PHP 7.4 + 확장 모듈 + ImageMagick + FFmpeg
#    4. Omeka Classic 다운로드 + 배포
#    5. DB 연결 (db.ini 자동 생성)
#    6. Apache 설정 (rewrite + VirtualHost)
#    7. 한글 패치 (--korean 옵션 시)
#    8. SSL + Nginx HTTPS (GCP만) / 포트 확인 (local)
#    9. 최종 점검 + 접속 정보 출력
#
###############################################################################

set -Eeuo pipefail

###############################################################################
# 설정값 (환경에 맞게 수정)
###############################################################################

# -- GCP 환경 설정 --
GCP_DOMAIN="omeka.example.com"       # GCP: 실제 도메인으로 변경

# -- 교내 서버 환경 설정 --
LOCAL_IP="00.00.000.00"              # 교내: 서버 IP로 변경
LOCAL_PORT="00000"                   # 교내: 포트 포워딩 포트

# -- 공통 설정 --
DB_NAME="omeka"
DB_USER="omeka"
DB_PASSWORD="omeka"      # 반드시 변경할 것
OMEKA_VERSION="3.2"
OMEKA_DIR="/var/www/omeka"
PHP_VERSION="7.4"
LOG_FILE="/var/log/omeka-install.log"
PROGRESS_FILE="/var/log/omeka-install-progress"

###############################################################################
# 인자 파싱
###############################################################################

START_STEP=-1
ENABLE_KOREAN=false
ENV_MODE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --step)
            START_STEP="$2"
            shift 2
            ;;
        --korean)
            ENABLE_KOREAN=true
            shift
            ;;
        --env)
            ENV_MODE="$2"
            shift 2
            ;;
        *)
            echo "알 수 없는 옵션: $1"
            echo "사용법: sudo bash install_omeka.sh --env [gcp|local] [--step N] [--korean]"
            exit 1
            ;;
    esac
done

###############################################################################
# 환경 모드 검증 + 변수 설정
###############################################################################

if [ -z "$ENV_MODE" ]; then
    echo "환경을 지정해주세요:"
    echo "  --env gcp    -> GCP 클라우드 (도메인 + SSL)"
    echo "  --env local  -> 교내 서버 (IP + HTTP)"
    echo ""
    echo "예: sudo bash install_omeka.sh --env gcp"
    exit 1
fi

case $ENV_MODE in
    gcp)
        DOMAIN="${GCP_DOMAIN}"
        ENABLE_SSL=true
        ACCESS_URL="https://${DOMAIN}"
        ADMIN_URL="https://${DOMAIN}/admin"
        echo "[환경] GCP 모드 -- 도메인: ${DOMAIN}, SSL: 활성화"
        ;;
    local)
        DOMAIN="${LOCAL_IP}"
        ENABLE_SSL=false
        ACCESS_URL="http://${LOCAL_IP}:${LOCAL_PORT}"
        ADMIN_URL="http://${LOCAL_IP}:${LOCAL_PORT}/admin"
        echo "[환경] 교내 서버 모드 -- IP: ${LOCAL_IP}, 포트: ${LOCAL_PORT}, SSL: 비활성화"
        ;;
    *)
        echo "알 수 없는 환경: ${ENV_MODE}"
        echo "사용 가능: gcp, local"
        exit 1
        ;;
esac

###############################################################################
# 로그 설정
###############################################################################

mkdir -p /var/log
exec > >(tee -a "$LOG_FILE") 2>&1

###############################################################################
# 에러 핸들러
###############################################################################

CURRENT_STEP=""
CURRENT_STEP_NAME=""

error_handler() {
    local line=$1
    echo ""
    echo "============================================================"
    echo "  설치 실패"
    echo "============================================================"
    echo "  실패 단계 : STEP ${CURRENT_STEP} -- ${CURRENT_STEP_NAME}"
    echo "  실패 위치 : install_omeka.sh line ${line}"
    echo "  로그 파일 : ${LOG_FILE}"
    echo "  진행 기록 : ${PROGRESS_FILE}"
    echo "------------------------------------------------------------"
    echo "  재시작 방법:"
    echo "    sudo bash install_omeka.sh --env ${ENV_MODE}"
    echo "      -> 완료된 단계는 자동 skip, 실패 지점부터 재개"
    echo "    sudo bash install_omeka.sh --env ${ENV_MODE} --step ${CURRENT_STEP}"
    echo "      -> ${CURRENT_STEP}단계부터 강제 재시작"
    echo "============================================================"
    exit 1
}

trap 'error_handler $LINENO' ERR

###############################################################################
# 헬퍼 함수
###############################################################################

section() {
    echo ""
    echo "=================================================="
    echo " $1"
    echo "=================================================="
}

mark_done() {
    echo "$1" >> "$PROGRESS_FILE"
}

is_done() {
    [ -f "$PROGRESS_FILE" ] && grep -qx "$1" "$PROGRESS_FILE"
}

should_skip_by_step() {
    local step_num=$1
    if [ "$START_STEP" -ge 0 ] && [ "$step_num" -lt "$START_STEP" ]; then
        return 0
    fi
    return 1
}

###############################################################################
# ROOT 권한 확인
###############################################################################

if [[ $EUID -ne 0 ]]; then
    echo "이 스크립트는 root 권한으로 실행해야 합니다 (sudo bash install_omeka.sh)"
    exit 1
fi

section "Omeka Classic ${OMEKA_VERSION} 설치 시작"
echo "환경 모드  : ${ENV_MODE}"
echo "접속 주소  : ${ACCESS_URL}"
echo "로그 파일  : ${LOG_FILE}"
echo "한글 패치  : ${ENABLE_KOREAN}"
echo "시작 시각  : $(date)"
if [ "$START_STEP" -ge 0 ]; then
    echo "시작 단계  : --step ${START_STEP}"
fi

###############################################################################
# STEP 0: 시스템 업데이트 + Swap + 방화벽 + 기본 패키지
###############################################################################

CURRENT_STEP=0; CURRENT_STEP_NAME="시스템 업데이트 + Swap + 방화벽 + 기본 패키지"

if should_skip_by_step 0; then
    echo "[STEP 0] --step 옵션으로 skip"
elif is_done "step0"; then
    echo "[STEP 0] 이미 완료됨. skip"
else
    section "STEP 0: ${CURRENT_STEP_NAME}"

    apt update && apt upgrade -y

    timedatectl set-timezone Asia/Seoul

    # Swap 2GB
    if ! swapon --show | grep -q "/swapfile"; then
        fallocate -l 2G /swapfile
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
        echo "2GB Swap 생성 완료"
    else
        echo "Swap 이미 존재. skip"
    fi

    # 방화벽
    apt install -y ufw
    ufw allow 22/tcp  || true
    ufw allow 80/tcp  || true
    ufw allow 443/tcp || true
    if [ "$ENV_MODE" = "local" ] && [ "${LOCAL_PORT}" != "80" ]; then
        ufw allow "${LOCAL_PORT}/tcp" || true
    fi
    ufw --force enable || true

    # Fail2ban + 자동 업데이트
    apt install -y fail2ban unattended-upgrades
    systemctl enable fail2ban
    systemctl start fail2ban
    dpkg-reconfigure -f noninteractive unattended-upgrades

    # 기본 패키지
    apt install -y \
        curl wget unzip vim git build-essential \
        software-properties-common ca-certificates gnupg \
        lsb-release logrotate openssl

    mark_done "step0"
fi

###############################################################################
# STEP 1: Apache2 설치
###############################################################################

CURRENT_STEP=1; CURRENT_STEP_NAME="Apache2 설치"

if should_skip_by_step 1; then
    echo "[STEP 1] --step 옵션으로 skip"
elif is_done "step1"; then
    echo "[STEP 1] 이미 완료됨. skip"
else
    section "STEP 1: ${CURRENT_STEP_NAME}"

    apt install -y apache2
    systemctl enable apache2
    systemctl start apache2
    apache2 -v
    echo "Apache2 설치 완료"

    mark_done "step1"
fi

###############################################################################
# STEP 2: MariaDB 설치 + DB/유저 생성
###############################################################################

CURRENT_STEP=2; CURRENT_STEP_NAME="MariaDB 설치 + DB/유저 생성"

if should_skip_by_step 2; then
    echo "[STEP 2] --step 옵션으로 skip"
elif is_done "step2"; then
    echo "[STEP 2] 이미 완료됨. skip"
else
    section "STEP 2: ${CURRENT_STEP_NAME}"

    apt install -y mariadb-server
    systemctl enable mariadb
    systemctl start mariadb

    mysql -u root <<EOSQL
CREATE DATABASE IF NOT EXISTS ${DB_NAME} DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOSQL

    echo "MariaDB + DB '${DB_NAME}' + 유저 '${DB_USER}' 생성 완료"

    mark_done "step2"
fi

###############################################################################
# STEP 3: PHP 7.4 + 확장 모듈 + ImageMagick + FFmpeg
###############################################################################

CURRENT_STEP=3; CURRENT_STEP_NAME="PHP ${PHP_VERSION} + 확장 모듈"

if should_skip_by_step 3; then
    echo "[STEP 3] --step 옵션으로 skip"
elif is_done "step3"; then
    echo "[STEP 3] 이미 완료됨. skip"
else
    section "STEP 3: ${CURRENT_STEP_NAME}"

    apt install -y software-properties-common
    add-apt-repository -y ppa:ondrej/php
    apt update

    apt install -y \
        php${PHP_VERSION} \
        php${PHP_VERSION}-mysql \
        php${PHP_VERSION}-xml \
        php${PHP_VERSION}-xsl \
        php${PHP_VERSION}-zip \
        php${PHP_VERSION}-cli \
        php${PHP_VERSION}-gd \
        php${PHP_VERSION}-intl \
        php${PHP_VERSION}-curl \
        php${PHP_VERSION}-opcache \
        php${PHP_VERSION}-readline \
        php${PHP_VERSION}-mbstring \
        php${PHP_VERSION}-dev \
        libapache2-mod-php${PHP_VERSION}

    apt install -y imagemagick
    apt install -y ffmpeg

    php -v
    echo "PHP ${PHP_VERSION} + 확장 모듈 + ImageMagick + FFmpeg 설치 완료"

    mark_done "step3"
fi

###############################################################################
# STEP 4: Omeka Classic 다운로드 + 배포
###############################################################################

CURRENT_STEP=4; CURRENT_STEP_NAME="Omeka Classic ${OMEKA_VERSION} 다운로드 + 배포"

if should_skip_by_step 4; then
    echo "[STEP 4] --step 옵션으로 skip"
elif is_done "step4"; then
    echo "[STEP 4] 이미 완료됨. skip"
else
    section "STEP 4: ${CURRENT_STEP_NAME}"

    cd /tmp

    if [ ! -f "omeka-${OMEKA_VERSION}.zip" ]; then
        wget -O "omeka-${OMEKA_VERSION}.zip" \
            "https://github.com/omeka/Omeka/releases/download/v${OMEKA_VERSION}/omeka-${OMEKA_VERSION}.zip"
    fi

    unzip -o "omeka-${OMEKA_VERSION}.zip"

    mkdir -p "${OMEKA_DIR}"
    cp -r "omeka-${OMEKA_VERSION}/." "${OMEKA_DIR}/"

    chown -R www-data:www-data "${OMEKA_DIR}"
    chmod 775 "${OMEKA_DIR}"

    find "${OMEKA_DIR}" -type d -exec chmod 775 {} \;
    find "${OMEKA_DIR}" -type f -exec chmod 664 {} \;

    if [ -d "${OMEKA_DIR}/files" ]; then
        find "${OMEKA_DIR}/files" -type d -exec chmod 777 {} \;
        find "${OMEKA_DIR}/files" -type f -exec chmod 666 {} \;
    fi

    echo "Omeka Classic ${OMEKA_VERSION} 배포 완료 -> ${OMEKA_DIR}"

    mark_done "step4"
fi

###############################################################################
# STEP 5: DB 연결 (db.ini 자동 생성)
###############################################################################

CURRENT_STEP=5; CURRENT_STEP_NAME="DB 연결 (db.ini 자동 생성)"

if should_skip_by_step 5; then
    echo "[STEP 5] --step 옵션으로 skip"
elif is_done "step5"; then
    echo "[STEP 5] 이미 완료됨. skip"
else
    section "STEP 5: ${CURRENT_STEP_NAME}"

    cat > "${OMEKA_DIR}/db.ini" <<EOINI
[database]
host     = "localhost"
username = "${DB_USER}"
password = "${DB_PASSWORD}"
dbname   = "${DB_NAME}"
prefix   = "omeka_"
charset  = "utf8"
;port     = ""
EOINI

    chown www-data:www-data "${OMEKA_DIR}/db.ini"
    chmod 640 "${OMEKA_DIR}/db.ini"

    echo "db.ini 생성 완료 (유저: ${DB_USER}, DB: ${DB_NAME})"

    mark_done "step5"
fi

###############################################################################
# STEP 6: Apache 설정 (rewrite + VirtualHost)
###############################################################################

CURRENT_STEP=6; CURRENT_STEP_NAME="Apache 설정 (rewrite + VirtualHost)"

if should_skip_by_step 6; then
    echo "[STEP 6] --step 옵션으로 skip"
elif is_done "step6"; then
    echo "[STEP 6] 이미 완료됨. skip"
else
    section "STEP 6: ${CURRENT_STEP_NAME}"

    a2enmod rewrite

    if [ "$ENV_MODE" = "local" ]; then
        # ports.conf: Apache Listen 포트를 LOCAL_PORT로 변경
        sed -i "s/^Listen 80$/Listen ${LOCAL_PORT}/" /etc/apache2/ports.conf
        if ! grep -q "^Listen ${LOCAL_PORT}" /etc/apache2/ports.conf; then
            echo "Listen ${LOCAL_PORT}" >> /etc/apache2/ports.conf
        fi

        cat > /etc/apache2/sites-available/omeka.conf <<EOVHOST
<VirtualHost *:${LOCAL_PORT}>
    DocumentRoot ${OMEKA_DIR}

    <Directory ${OMEKA_DIR}>
        Options Indexes FollowSymLinks MultiViews
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/omeka-error.log
    CustomLog \${APACHE_LOG_DIR}/omeka-access.log combined
</VirtualHost>
EOVHOST
    else
        cat > /etc/apache2/sites-available/omeka.conf <<EOVHOST
<VirtualHost *:80>
    ServerName ${DOMAIN}
    ServerAdmin webmaster@${DOMAIN}
    DocumentRoot ${OMEKA_DIR}

    <Directory ${OMEKA_DIR}>
        Options Indexes FollowSymLinks MultiViews
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/omeka-error.log
    CustomLog \${APACHE_LOG_DIR}/omeka-access.log combined
</VirtualHost>
EOVHOST
    fi

    a2ensite omeka.conf
    a2dissite 000-default.conf || true

    apache2ctl configtest
    systemctl restart apache2

    echo "Apache VirtualHost 설정 완료 (DocumentRoot: ${OMEKA_DIR})"

    mark_done "step6"
fi

###############################################################################
# STEP 7: 한글 패치 (--korean 옵션 시)
###############################################################################

CURRENT_STEP=7; CURRENT_STEP_NAME="한글 패치"

if should_skip_by_step 7; then
    echo "[STEP 7] --step 옵션으로 skip"
elif is_done "step7"; then
    echo "[STEP 7] 이미 완료됨. skip"
else
    section "STEP 7: ${CURRENT_STEP_NAME}"

    if [ "$ENABLE_KOREAN" = true ]; then
        CONFIG_INI="${OMEKA_DIR}/application/config/config.ini"

        if [ -f "$CONFIG_INI" ]; then
            sed -i 's/^locale\.name\s*=\s*""/locale.name = "ko_KR"/' "$CONFIG_INI"
            echo "한글 패치 적용 완료 (locale.name = ko_KR)"
        else
            echo "WARNING: config.ini 파일을 찾을 수 없음 (${CONFIG_INI})"
            echo "Omeka 웹 설치 완료 후 수동으로 한글 설정이 필요합니다."
        fi
    else
        echo "한글 패치 비활성화 (--korean 옵션 미사용). skip"
    fi

    mark_done "step7"
fi

###############################################################################
# STEP 8: SSL + Nginx HTTPS (GCP) / Apache 포트 확인 (local)
###############################################################################

CURRENT_STEP=8; CURRENT_STEP_NAME="네트워크 설정 (SSL/포트)"

if should_skip_by_step 8; then
    echo "[STEP 8] --step 옵션으로 skip"
elif is_done "step8"; then
    echo "[STEP 8] 이미 완료됨. skip"
else
    section "STEP 8: ${CURRENT_STEP_NAME}"

    if [ "$ENV_MODE" = "local" ]; then
        echo "교내 서버 모드 -- SSL 건너뜀, Apache HTTP만 사용"
        systemctl restart apache2
        echo "Apache 재시작 완료"
        echo ""
        echo "접속 주소: ${ACCESS_URL}"
        echo "관리자   : ${ADMIN_URL}"
        echo ""
        echo "* SSH 터널링으로 접근하세요:"
        echo "  터널 Destination: ${LOCAL_IP}:${LOCAL_PORT}"
        echo "  브라우저 접속: http://localhost:${LOCAL_PORT}/"

    else
        apt install -y nginx certbot python3-certbot-nginx

        sed -i 's/Listen 80$/Listen 8080/' /etc/apache2/ports.conf
        sed -i 's/<VirtualHost \*:80>/<VirtualHost *:8080>/' /etc/apache2/sites-available/omeka.conf
        systemctl restart apache2

        cat > /etc/nginx/sites-available/omeka <<EONGINX
server {
    listen 80;
    server_name ${DOMAIN};
    client_max_body_size 512M;
    location /.well-known/acme-challenge/ { root /var/www/html; }
    location / {
        proxy_pass         http://localhost:8080;
        proxy_set_header   Host              \$host;
        proxy_set_header   X-Real-IP         \$remote_addr;
        proxy_set_header   X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto \$scheme;
    }
}
EONGINX

        ln -sf /etc/nginx/sites-available/omeka /etc/nginx/sites-enabled/omeka
        rm -f /etc/nginx/sites-enabled/default || true
        systemctl restart nginx

        mkdir -p "/etc/letsencrypt/live/${DOMAIN}"
        CERT_ACQUIRED=false

        if certbot certonly --webroot -w /var/www/html -d "${DOMAIN}" \
            --non-interactive --agree-tos --email "webmaster@${DOMAIN}"; then
            echo "Let's Encrypt SSL 인증서 발급 성공!"
            CERT_ACQUIRED=true
        else
            echo "SSL 실패 -- 자체 서명 인증서 생성"
            openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
                -keyout "/etc/letsencrypt/live/${DOMAIN}/privkey.pem" \
                -out "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" \
                -subj "/CN=${DOMAIN}"
        fi

        cat > /etc/nginx/sites-available/omeka <<EONGINX
server {
    listen 80;
    server_name ${DOMAIN};
    location /.well-known/acme-challenge/ { root /var/www/html; }
    location / { return 301 https://\$host\$request_uri; }
}
server {
    listen 443 ssl;
    server_name ${DOMAIN};
    client_max_body_size 512M;
    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    location / {
        proxy_pass         http://localhost:8080;
        proxy_set_header   Host              \$host;
        proxy_set_header   X-Real-IP         \$remote_addr;
        proxy_set_header   X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto https;
    }
}
EONGINX

        nginx -t
        systemctl restart nginx
        echo "Nginx HTTPS 리버스 프록시 설정 완료"
    fi

    mark_done "step8"
fi

###############################################################################
# STEP 9: 최종 점검 + 접속 정보 출력
###############################################################################

CURRENT_STEP=9; CURRENT_STEP_NAME="최종 점검 + 접속 정보"

if should_skip_by_step 9; then
    echo "[STEP 9] --step 옵션으로 skip"
elif is_done "step9"; then
    echo "[STEP 9] 이미 완료됨. skip"
else
    section "STEP 9: ${CURRENT_STEP_NAME}"

    cat > /etc/logrotate.d/omeka <<EOLOGROTATE
/var/log/omeka-install.log {
    weekly
    rotate 12
    compress
    missingok
    notifempty
}
EOLOGROTATE

    section "최종 상태 점검"
    echo "서비스 상태:"
    systemctl is-active --quiet apache2  && echo "  Apache2  : OK" || echo "  Apache2  : FAILED"
    systemctl is-active --quiet mariadb  && echo "  MariaDB  : OK" || echo "  MariaDB  : FAILED"

    if [ "$ENV_MODE" = "gcp" ]; then
        systemctl is-active --quiet nginx && echo "  Nginx    : OK" || echo "  Nginx    : FAILED"
    fi

    if [ "$ENV_MODE" = "gcp" ]; then
        LOCAL_TEST_PORT=8080
    elif [ "$ENV_MODE" = "local" ]; then
        LOCAL_TEST_PORT="${LOCAL_PORT}"
    else
        LOCAL_TEST_PORT=80
    fi

    curl -sf "http://localhost:${LOCAL_TEST_PORT}" > /dev/null \
        && echo "  Omeka    : OK (응답 확인)" \
        || echo "  Omeka    : 아직 초기 설정 대기 중 (정상)"

    mark_done "step9"
fi

###############################################################################
# 설치 완료
###############################################################################

section "Omeka Classic ${OMEKA_VERSION} 설치 완료!"
echo ""
echo "  환경 모드     : ${ENV_MODE}"
echo "  공개용 접속   : ${ACCESS_URL}"
echo "  관리자 페이지 : ${ADMIN_URL}"
echo "  로그 파일     : ${LOG_FILE}"
echo "  진행 기록     : ${PROGRESS_FILE}"
echo ""
if [ "$ENV_MODE" = "gcp" ] && [ "${CERT_ACQUIRED:-false}" = false ]; then
    echo "  [참고] 자체서명 인증서 사용 중입니다."
    echo "  DNS가 이 VM IP를 가리킨 후 아래 명령으로 정식 인증서를 발급하세요:"
    echo "    sudo certbot --nginx -d ${DOMAIN} --agree-tos --email webmaster@${DOMAIN} --redirect"
    echo ""
fi
if [ "$ENV_MODE" = "local" ]; then
    echo "  [참고] 교내 서버 모드 -- SSH 터널링으로 접속합니다."
    echo "  터널 Destination: ${LOCAL_IP}:${LOCAL_PORT}"
    echo "  브라우저 접속: http://localhost:${LOCAL_PORT}/"
    echo ""
fi
echo "  * 첫 접속 시 웹 브라우저에서 관리자 계정을 생성해야 합니다."
echo "  완료 시각: $(date)"
echo ""
