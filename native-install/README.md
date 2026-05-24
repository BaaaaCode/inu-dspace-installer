# DSpace 9.1 자동 설치 스크립트

---

## 1. 개요
이 스크립트(`install.sh`)는 **Ubuntu 22.04 LTS** 환경(GCP VM 기준)에서 DSpace 9.1을 자동으로 설치합니다. 사전 준비(Java, Maven, PostgreSQL 등)부터 SSL 인증서 발급, Nginx 리버스 프록시 설정까지 **한 파일로 완결**되며, 실패 시 실패 지점부터 자동으로 재개할 수 있도록 설계되어 있습니다.

**주요 특징:**

- 15단계(STEP 0~14)로 구성, 각 단계는 독립적으로 skip 가능
- 실패 시 실패 단계·위치·로그 경로를 안내하는 에러 핸들러 내장
- `--step N` 옵션으로 특정 단계부터 강제 시작 가능
- 설치 로그(`/var/log/dspace-install.log`)와 진행 기록(`/var/log/dspace-install-progress`) 자동 생성

---

## 2. 작동 구조

### 2.1 설치 단계

| STEP | 내용 | 예상 소요 |
|------|------|-----------|
| 0 | 시스템 업데이트, Swap(4GB), 방화벽(UFW), 기본 패키지 | 3~5분 |
| 1 | DSpace 전용 유저(`dspace`) 생성 | < 1분 |
| 2 | Java JDK 17 설치 | 1~2분 |
| 3 | Maven 3.8.8 + Ant 설치 | 1~2분 |
| 4 | PostgreSQL 설치, DB 생성, pgcrypto 확장, 튜닝 | 2~3분 |
| 5 | Node.js 20 + PM2 설치 | 1~2분 |
| 6 | Apache Solr 9.6.1 설치 | 2~3분 |
| 7 | DSpace 백엔드 다운로드 + local.cfg + Maven/Ant 빌드 | **10~15분** |
| 8 | Solr 코어 배포 + 로드 확인 | 1~2분 |
| 9 | DB 마이그레이션 + Discovery 인덱싱 | 2~3분 |
| 10 | Backend systemd 서비스 등록 | < 1분 |
| 11 | Frontend 다운로드 + Angular SSR 빌드 | **10~15분** |
| 12 | PM2 프로세스 등록 (Frontend SSR) | < 1분 |
| 13 | SSL 인증서(Let's Encrypt / 자체서명) + Nginx HTTPS | 1~2분 |
| 14 | Logrotate, 일일 백업 cron, 최종 상태 점검 | 1분 |

**전체 소요: 약 30~40분** (네트워크 속도에 따라 상이)

### 2.2 서비스 구조

```
[브라우저]
    │
    ▼ HTTPS (443)
[Nginx 리버스 프록시]
    │
    ├── /server/  →  [DSpace Backend :8080]  (Spring Boot JAR)
    │                       │
    │                       ▼
    │                [PostgreSQL :5432]  +  [Solr :8983]
    │
    └── /  →  [DSpace Frontend :4000]  (Angular SSR, PM2 관리)
                    │
                    ▼ (SSR에서 백엔드 API 호출)
                [Nginx :443 → Backend :8080]
```

### 2.3 자동 Skip 로직

스크립트를 다시 실행하면 각 단계마다 **완료 여부를 자동 감지**합니다:

- `/var/log/dspace-install-progress` 파일에 완료된 단계가 기록됨
- 이미 기록된 단계는 자동으로 건너뜀
- 추가로 Solr 실행 여부, `server-boot.jar` 존재 여부, `dist/` 폴더 존재 여부 등을 체크하여 이중 확인

---

## 3. TA 사전 준비사항

### 3.1 GCP VM 생성

1. **GCP Console** → Compute Engine → VM 인스턴스 → 인스턴스 만들기
2. 권장 스펙:

| 항목 | 권장값 | 비고 |
|------|--------|------|
| 머신 유형 | e2-standard-2 | vCPU 2개, 메모리 8GB |
| OS | Ubuntu 22.04 LTS | 반드시 22.04 |
| 부팅 디스크 | 30GB 이상 | SSD 권장 |
| 방화벽 | HTTP + HTTPS 허용 체크 | **반드시 체크** |

3. VM 생성 후 **외부 IP** 확인 (예: `34.50.20.167`)

### 3.2 도메인 설정 (No-IP)

1. [noip.com](https://www.noip.com) 에서 호스트네임 생성 (예: `dspace-isd.ddns.net`)
2. IP를 VM 외부 IP로 설정
3. VM을 삭제/재생성할 때마다 IP 업데이트 필요

### 3.3 install.sh 배포

1. `install.sh` 파일을 VM에 업로드
   - GCP 브라우저 SSH → 우측 상단 톱니바퀴 → **파일 업로드**
   - 또는 `scp install.sh username@VM_IP:/home/username/`
2. 스크립트 상단의 **설정값** 섹션에서 `DOMAIN` 등을 환경에 맞게 수정

```bash
# install.sh 상단 — 환경에 맞게 수정
DOMAIN="dspace-isd.ddns.net"    # ← 실제 도메인
DB_PASSWORD="dspace"             # ← 필요 시 변경
```

### 3.4 테스트 실행

```bash
sudo bash install.sh
```

설치 완료 후 `https://도메인` 접속하여 DSpace 9 화면이 뜨는지 확인합니다.

---

## 4. 학생 실행 가이드

### 4.1 실행 방법

VM에 SSH 접속 후:

```bash
# 1. install.sh 업로드 (브라우저 SSH의 파일 업로드 기능 사용)

# 2. 실행
sudo bash install.sh
```

설치는 약 30~40분 소요됩니다. 중간에 SSH 연결이 끊겨도 로그는 `/var/log/dspace-install.log`에 기록됩니다.

### 4.2 설치 완료 확인

스크립트 마지막에 아래와 같은 메시지가 출력됩니다:

```
==================================================
 DSpace 9.1 설치 완료!
==================================================

  DSpace 접속     : https://dspace-isd.ddns.net
  REST API        : https://dspace-isd.ddns.net/server
```

브라우저에서 접속 시 자체서명 인증서 경고가 뜨면 **"고급" → "안전하지 않음으로 계속"**을 클릭합니다.

### 4.3 설치 중 실패한 경우

실패 시 아래와 같은 안내가 출력됩니다:

```
╔══════════════════════════════════════════════════════════════╗
║                    설치 실패                                ║
╠══════════════════════════════════════════════════════════════╣
║  실패 단계 : STEP 7 — DSpace 백엔드 다운로드 + 빌드
║  실패 위치 : install.sh line 285
║  로그 파일 : /var/log/dspace-install.log
╠══════════════════════════════════════════════════════════════╣
║  재시작 방법:
║    sudo bash install.sh
║      → 완료된 단계는 자동 skip, 실패 지점부터 재개
║    sudo bash install.sh --step 7
║      → 7단계부터 강제 재시작
╚══════════════════════════════════════════════════════════════╝
```

이 메시지를 **스크린샷**으로 저장한 뒤, 아래 순서로 대처합니다:

1. **로그 확인**: `cat /var/log/dspace-install.log | tail -50`
2. **그대로 재실행**: `sudo bash install.sh` — 완료된 단계는 자동 skip됨
3. 같은 에러가 반복되면 로그와 스크린샷을 TA에게 전달

---

## 5. 오류 발생 시 대처 방안

### 5.1 설치 중 오류

| 증상 | 원인 | 대처 |
|------|------|------|
| STEP 6에서 Solr 설치 실패 | 다운로드 서버 접근 불가 | 네트워크 확인 후 `sudo bash install.sh` 재실행 |
| STEP 7에서 Maven 빌드 실패 | 메모리 부족 또는 네트워크 끊김 | 재실행하면 자동 재개 |
| STEP 8에서 Solr 코어 로드 실패 | Solr 서비스 비정상 | `sudo systemctl restart solr` 후 `sudo bash install.sh --step 8` |
| STEP 11에서 OOM (heap out of memory) | 메모리 부족 (4GB VM) | 아래 **5.2** 참조 |
| STEP 13에서 SSL 실패 | DNS 미설정 또는 전파 지연 | 자체서명 인증서로 자동 대체됨 (정상) |

### 5.2 Frontend 빌드 OOM (메모리 부족)

4GB VM에서 Frontend 빌드 시 메모리 부족으로 실패할 수 있습니다. 이 경우:

```bash
# Swap을 8GB로 확대
sudo swapoff /swapfile
sudo fallocate -l 8G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# 빌드 단계부터 재시작
sudo bash install.sh --step 11
```

### 5.3 설치 완료 후 접속 불가

아래 체크리스트를 **순서대로** 확인합니다:

| 순서 | 확인 항목 | 명령어 | 정상 기준 |
|------|-----------|--------|-----------|
| 1 | 서비스 상태 | `systemctl status nginx dspace-backend` | active (running) |
| 2 | PM2 상태 | `sudo -u dspace pm2 status` | online |
| 3 | 포트 리스닝 | `ss -tlnp \| grep -E '80\|443\|4000\|8080'` | 4개 모두 LISTEN |
| 4 | 백엔드 응답 | `curl -k https://localhost/server/api` | JSON 응답 |
| 5 | 프론트 응답 | `curl -k https://localhost` | HTML 응답 |
| 6 | DNS 일치 | `curl ifconfig.me` vs `nslookup 도메인` | IP 동일 |
| 7 | GCP 방화벽 | GCP Console → VM → HTTP/HTTPS 허용 체크 | 체크됨 |

**판단 기준:**

- 1~3 실패 → 서비스 설치 문제. 로그 확인 후 해당 STEP 재실행
- 4 실패, 1~3 정상 → Backend 기동 중 (Spring Boot 시작에 약 1분 소요). 잠시 후 재시도
- 5 실패, 4 정상 → Frontend SSR의 SSL 인증서 문제. `sudo -u dspace pm2 logs dspace-ui --lines 30`으로 확인
- 4~5 정상, 외부 접속 불가 → DNS 또는 GCP 방화벽 문제

### 5.4 500 Service unavailable 에러

브라우저에서 DSpace 로고는 보이지만 "500 Service unavailable"이 표시되는 경우:

```bash
# PM2 에러 로그 확인
sudo -u dspace pm2 logs dspace-ui --lines 30
```

`ERROR Error: undefined doesn't contain the link sites` 에러가 보이면 자체서명 인증서 문제입니다. 스크립트에 이미 대응이 포함되어 있으나, 수동으로 재설정이 필요한 경우:

```bash
sudo -u dspace pm2 delete dspace-ui
sudo -u dspace bash -c "cd /opt/dspace-angular && NODE_TLS_REJECT_UNAUTHORIZED=0 pm2 start 'npm run serve:ssr' --name dspace-ui"
sudo -u dspace pm2 save
```

---

## 6. 참고사항

### 6.1 주요 파일 경로

| 항목 | 경로 |
|------|------|
| DSpace 설치 디렉토리 | `/dspace` |
| Backend 소스 | `/opt/dspace-source` |
| Frontend 소스 | `/opt/dspace-angular` |
| Frontend 설정 | `/opt/dspace-angular/config/config.prod.yml` |
| DSpace 설정 | `/dspace/config/local.cfg` |
| Solr Home | `/opt/solr-9.6.1/server/solr` |
| Nginx 설정 | `/etc/nginx/sites-available/dspace` |
| 설치 로그 | `/var/log/dspace-install.log` |
| 진행 기록 | `/var/log/dspace-install-progress` |
| DB 백업 | `/backup/dspace_YYYYMMDD_HHMMSS.sql` |

### 6.2 주요 서비스 관리 명령어

```bash
# 서비스 시작/중지/재시작
sudo systemctl start|stop|restart nginx
sudo systemctl start|stop|restart dspace-backend
sudo systemctl start|stop|restart solr

# Frontend (PM2)
sudo -u dspace pm2 start|stop|restart dspace-ui
sudo -u dspace pm2 logs dspace-ui --lines 50

# DSpace CLI
sudo -u dspace /dspace/bin/dspace              # 명령어 목록
sudo -u dspace /dspace/bin/dspace index-discovery -b  # 재인덱싱
```

### 6.3 설치 초기화 (완전 재설치)

VM을 삭제하고 새로 생성하는 것이 가장 깔끔합니다. 기존 VM에서 초기화하려면:

```bash
# 진행 기록 삭제 (모든 단계를 다시 실행하게 됨)
sudo rm /var/log/dspace-install-progress

# 처음부터 재실행
sudo bash install.sh --step 0
```

### 6.4 SSL 정식 인증서 발급

자체서명 인증서 대신 정식 Let's Encrypt 인증서를 발급하려면, DNS가 VM IP를 가리키는 상태에서:

```bash
sudo certbot --nginx -d dspace-isd.ddns.net --agree-tos --email webmaster@dspace-isd.ddns.net --redirect
```

### 6.5 에러 해결 이력

이 스크립트 개발 과정에서 발견·수정된 에러 목록은 `error_report.md` 파일에 정리되어 있습니다. 새로운 환경에서 유사한 문제가 발생할 경우 참고하세요.

---

## 7. 학교 서버 배포 시 수정 가이드

현재 스크립트는 **GCP VM 1대 + 도메인 + SSL** 구성으로 작성되어 있습니다. 추후 학교 물리 서버에 배포할 경우, 아래와 같은 환경이 예상됩니다:

- 학교 서버 1대, 고정 IP
- 학생마다 **포트를 다르게 할당**하여 각자의 DSpace 인스턴스에 접속
- 도메인 없이 `http://고정IP:포트` 방식으로 접근
- SSL 불필요

이 경우 스크립트에서 수정해야 할 항목을 아래에 정리합니다.

### 7.1 설정값 변경

스크립트 상단의 설정값을 도메인 기반에서 IP+포트 기반으로 변경합니다.

```bash
# ── 현재 (GCP + 도메인) ──
DOMAIN="dspace-isd.ddns.net"
BACKEND_PORT="8080"
FRONTEND_PORT="4000"

# ── 변경 (학교 서버 + 포트 분리) ──
SERVER_IP="123.456.789.10"          # 학교 서버 고정 IP
STUDENT_ID="01"                     # 학생 번호
BACKEND_PORT="80${STUDENT_ID}"      # 학생01 → 8001, 학생02 → 8002 ...
FRONTEND_PORT="40${STUDENT_ID}"     # 학생01 → 4001, 학생02 → 4002 ...
```

### 7.2 local.cfg URL 변경

DSpace 설정에서 HTTPS 도메인 대신 HTTP IP+포트를 사용합니다.

```bash
# ── 현재 ──
dspace.ui.url = https://${DOMAIN}
dspace.server.url = https://${DOMAIN}/server

# ── 변경 ──
dspace.ui.url = http://${SERVER_IP}:${FRONTEND_PORT}
dspace.server.url = http://${SERVER_IP}:${BACKEND_PORT}/server
```

### 7.3 Frontend config.prod.yml 변경

프론트엔드가 백엔드에 연결하는 설정도 변경합니다.

```yaml
# ── 현재 ──
ui:
  ssl: false
  host: localhost
  port: 4000
  nameSpace: /
  baseUrl: https://dspace-isd.ddns.net
rest:
  ssl: true
  host: dspace-isd.ddns.net
  port: 443
  nameSpace: /server

# ── 변경 ──
ui:
  ssl: false
  host: 0.0.0.0                    # 외부 접속 허용
  port: 4001                       # 학생별 포트
  nameSpace: /
  baseUrl: http://123.456.789.10:4001
rest:
  ssl: false                       # SSL 없음
  host: 123.456.789.10
  port: 8001                       # 학생별 백엔드 포트
  nameSpace: /server
```

### 7.4 SSL / Nginx 단계 제거

포트 직접 접근 방식에서는 Nginx 리버스 프록시와 SSL 인증서가 불필요합니다.

- **STEP 13 (SSL + Nginx HTTPS)** 전체를 제거하거나 skip
- Backend가 직접 `0.0.0.0:${BACKEND_PORT}`에서 리스닝하도록 변경
- Frontend도 `0.0.0.0:${FRONTEND_PORT}`에서 직접 리스닝

Nginx를 사용하지 않으므로 `NODE_TLS_REJECT_UNAUTHORIZED=0` 설정도 불필요합니다 (HTTP 직접 통신이므로 SSL 인증서 검증 자체가 발생하지 않음).

### 7.5 학생별 격리

한 서버에 여러 학생이 설치하면 DB, 설치 경로, Solr 코어가 충돌합니다. 아래와 같이 학생별로 분리해야 합니다.

#### 분리가 필요한 항목

| 항목 | 현재 (단일) | 변경 (학생별) | 예시 (학생 01) |
|------|------------|--------------|---------------|
| OS 유저 | `dspace` | `student${ID}` | `student01` |
| DB 이름 | `dspace` | `dspace_${ID}` | `dspace_01` |
| DB 유저 | `dspace` | `dspace_${ID}` | `dspace_01` |
| 설치 경로 | `/dspace` | `/dspace/student${ID}` | `/dspace/student01` |
| Backend 소스 | `/opt/dspace-source` | `/opt/dspace-source-${ID}` | `/opt/dspace-source-01` |
| Frontend 소스 | `/opt/dspace-angular` | `/opt/dspace-angular-${ID}` | `/opt/dspace-angular-01` |
| Backend 포트 | 8080 | `80${ID}` | 8001 |
| Frontend 포트 | 4000 | `40${ID}` | 4001 |
| PM2 프로세스명 | `dspace-ui` | `dspace-ui-${ID}` | `dspace-ui-01` |
| systemd 서비스명 | `dspace-backend` | `dspace-backend-${ID}` | `dspace-backend-01` |
| 로그 파일 | `/var/log/dspace-install.log` | `/var/log/dspace-install-${ID}.log` | `/var/log/dspace-install-01.log` |
| 진행 기록 | `/var/log/dspace-install-progress` | `/var/log/dspace-install-progress-${ID}` | `/var/log/dspace-install-progress-01` |

#### 공유 가능한 항목 (TA가 한 번만 설치)

아래 서비스는 모든 학생이 공유하며, TA가 서버 세팅 시 한 번만 설치합니다:

| 항목 | 비고 |
|------|------|
| Java JDK 17 | 시스템 전역 설치 |
| Maven 3.8.8 | 시스템 전역 설치 |
| Ant | 시스템 전역 설치 |
| Node.js 20 | 시스템 전역 설치 |
| PM2 | 시스템 전역 설치 |
| PostgreSQL | 1개 인스턴스, DB만 학생별로 생성 |
| Solr | 1개 인스턴스, 코어를 학생별 prefix로 구분 (아래 참조) |

#### Solr 코어 분리

Solr는 1개 인스턴스를 공유하되, 코어 이름에 학생 번호를 prefix로 붙여 구분합니다.

```bash
# 현재 — 코어 이름
authority, oai, qaevent, search, statistics, suggestion

# 변경 — 학생별 prefix
s01_authority, s01_oai, s01_qaevent, s01_search, s01_statistics, s01_suggestion
s02_authority, s02_oai, s02_qaevent, s02_search, s02_statistics, s02_suggestion
```

`local.cfg`에서 Solr 코어 prefix를 지정합니다:

```properties
# local.cfg에 추가
solr.server = http://localhost:8983/solr
solr.multicorePrefix = s01_
```

> **참고**: DSpace 9.x에서 Solr 코어 prefix 지원 여부는 버전에 따라 다를 수 있습니다. 지원하지 않는 경우 학생별로 별도 Solr 포트를 할당하거나, Docker 기반 격리를 고려해야 합니다.

### 7.6 스크립트 실행 방식 변경 (안)

학생 번호를 인자로 받아 포트/경로/DB를 자동 계산하는 방식으로 변경할 수 있습니다.

```bash
# 학생 번호를 지정하여 실행
sudo bash install.sh --student 3

# 내부적으로 자동 계산:
#   STUDENT_ID=03
#   BACKEND_PORT=8003
#   FRONTEND_PORT=4003
#   DB_NAME=dspace_03
#   DSPACE_DIR=/dspace/student03
#   ...
```

### 7.7 스크립트 분리 구조 (안)

학교 서버 배포 시 스크립트를 2개로 분리하면 관리가 편합니다.

```
install_base.sh      ← TA가 1회 실행 (Java, Maven, PostgreSQL, Solr 등 공용 서비스)
install_student.sh   ← 학생이 각자 실행 (--student N, 자기 DSpace 인스턴스만 설치)
```

**install_base.sh** (TA 실행):
- STEP 0~6 해당 (시스템 업데이트, Java, Maven, PostgreSQL, Node.js, Solr)
- 한 번만 실행

**install_student.sh** (학생 실행):
- `--student N` 인자 필수
- STEP 7~12 해당 (백엔드 빌드, Solr 코어, DB 마이그레이션, Frontend 빌드, PM2)
- STEP 13 (Nginx/SSL) 제거, 포트 직접 접근
- 학생별 경로/DB/포트 자동 계산

### 7.8 접속 방식 변경

```
# ── 현재 (GCP + 도메인) ──
DSpace UI  : https://dspace-isd.ddns.net
REST API   : https://dspace-isd.ddns.net/server

# ── 변경 (학교 서버 + 포트) ──
학생 01:
  DSpace UI  : http://123.456.789.10:4001
  REST API   : http://123.456.789.10:8001/server

학생 02:
  DSpace UI  : http://123.456.789.10:4002
  REST API   : http://123.456.789.10:8002/server

학생 15:
  DSpace UI  : http://123.456.789.10:4015
  REST API   : http://123.456.789.10:8015/server
```

### 7.9 요약 체크리스트

학교 서버 배포 전 확인사항:

- [ ] 서버 IP 및 사용 가능 포트 범위 확인
- [ ] 학생 수 확인 → 포트 할당 계획 수립
- [ ] `install_base.sh` / `install_student.sh` 분리 여부 결정
- [ ] Solr 코어 격리 방식 결정 (prefix vs 별도 포트 vs Docker)
- [ ] 서버 메모리 확인 (학생 수 × 약 2~3GB 필요)
- [ ] 방화벽에서 할당 포트 범위 오픈
- [ ] 스크립트 상단 설정값 수정 (IP, 포트 규칙)
- [ ] 테스트 (학생 2~3명분 설치 후 동시 접속 확인)
