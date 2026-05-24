# DSpace 9.1 Install 에러 해결 정리

---

## (1) Solr 스크립트 파일명에서 버전 확인 불가

* **에러 위치**: install.sh line 341

* **오류 메시지**:
```
Extracting solr.tgz to /opt
ERROR: Expected directory /opt/solr not found after extracting solr.tgz ... script fails.
Failed to enable unit: Unit file solr.service does not exist.
ERROR: Installation failed at line 354
```

* **원인**: `wget -O solr.tgz`로 파일명을 변경했는데, `install_solr_service.sh`는 파일명에서 버전 정보를 파싱하여 추출 디렉토리(`/opt/solr-9.6.1`)를 결정함. `solr.tgz`에서는 버전을 읽을 수 없어 `/opt/solr`을 찾으려다 실패.

* **수정사항**: 파일명에 버전 포함 
```bash
# 변경 전
wget -O solr.tgz \
    https://archive.apache.org/dist/solr/solr/${SOLR_VERSION}/solr-${SOLR_VERSION}.tgz
tar xzf solr.tgz solr-${SOLR_VERSION}/bin/install_solr_service.sh --strip-components=2
bash ./install_solr_service.sh solr.tgz -f || true

# 변경 후
wget -O solr-${SOLR_VERSION}.tgz \
    http://air.inu.ac.kr/~jdpark/ftp/solr-${SOLR_VERSION}.tgz
tar xzf solr-${SOLR_VERSION}.tgz solr-${SOLR_VERSION}/bin/install_solr_service.sh --strip-components=2
bash ./install_solr_service.sh solr-${SOLR_VERSION}.tgz -f
```

---

## (2) Solr 서비스 시작 실패 — 로그 디렉토리 권한 문제

* **에러 위치**: install.sh line 354 (`systemctl restart solr`)

* **오류 메시지**:
```
Java 17 detected. Enabled workaround for SOLR-16463
ERROR: Logs directory /opt/solr-9.6.1/server/logs could not be created. Exiting
```

* **원인**: Solr가 root 권한으로 추출되어 `/opt/solr-9.6.1` 소유자가 root. solr 유저로 서비스 실행 시 logs 폴더를 생성할 수 없음.

* **수정사항**: `install_solr_service.sh` 실행 직후, 서비스 시작 전에 권한 수정 추가
```bash
# 추가
mkdir -p /opt/solr-${SOLR_VERSION}/server/logs
chown -R solr:solr /opt/solr-${SOLR_VERSION}
chown -R solr:solr /var/solr
```

---

## (3) Ant 빌드 실패 — pgcrypto 확장 미설치

* **에러 위치**: install2 line 106 (`ant fresh_install`)

* **오류 메시지**:
```
[java] WARNING: Required PostgreSQL 'pgcrypto' extension is NOT INSTALLED on this database.
[java] ** DSpace REQUIRES PostgreSQL >= 9.4 AND pgcrypto extension >= 1.1 **
BUILD FAILED
/opt/dspace-source/dspace/target/dspace-installer/build.xml:783: Java returned: 1
```

* **원인**: install.sh 292줄에서 pgcrypto 설치 코드가 있으나, heredoc 내 `\c ${DB_NAME}` DB 전환이 정상 동작하지 않아 실제로는 설치되지 않음.

* **수정사항**: Maven 빌드 전에 pgcrypto 설치를 별도 명령으로 명시적 실행
```bash
# 추가 (Ant 실행 전)
sudo -u postgres psql -d ${DB_NAME} -c "CREATE EXTENSION IF NOT EXISTS pgcrypto;"
```

---

## (4) 인덱싱 실패 — Solr 코어 미인식 (core.properties 비어있음)

* **에러 위치**: install_v4.sh line 126 (`dspace index-discovery -b`)

* **오류 메시지**:
```
org.apache.solr.client.solrj.impl.HttpSolrClient$RemoteSolrException:
Error from server at http://localhost:8983/solr/search:
Expected mime type application/octet-stream but got text/html.
<p>Searching for Solr?<br/>You must type the correct path.<br/>Solr will respond.</p>
```

* **원인**: `cp -r ${DSPACE_DIR}/solr/* /var/solr/data/` 로 코어 디렉토리(conf 폴더 등)는 복사되었으나, 각 코어의 `core.properties` 파일이 비어있음. Solr는 `core.properties`에 `name=코어이름`이 명시되어야 해당 코어를 인식·로드함. DSpace 빌드가 빈 `core.properties`를 생성하는 것이 원인.

* **수정사항 (v5 — 불완전)**: `core.properties`에 이름 추가 → 효과 없음

* **근본 원인 재분석**: Solr Home이 `/opt/solr-9.6.1/server/solr/`인데, 스크립트는 `/var/solr/data/`에 코어를 복사하고 있었음. Solr가 보는 경로와 복사 대상 경로가 불일치.
  - Solr 로그에서 확인: `Solr Home: /opt/solr-9.6.1/server/solr (source: system property: solr.solr.home)`
  - `SOLR_HOME`이 `/etc/default/solr.in.sh`에 설정되지 않아 기본값 사용

* **추가 문제 (v6)**: `sleep 5` 후 코어 체크 → Solr 코어 로드 완료 전에 체크 실행되어 실패. 실제로는 코어가 정상 로드됨.

* **수정사항 (v7)**: 코어 복사 대상을 Solr Home 경로로 변경 + 코어 체크를 최대 30초 재시도 루프로 변경

---

## (5) Frontend 빌드 OOM — JavaScript heap out of memory

* **에러 위치**: install_v7.sh line 221 (`npm run build:prod`)

* **오류 메시지**:
```
FATAL ERROR: Ineffective mark-compacts near heap limit Allocation failed - JavaScript heap out of memory
Aborted (core dumped)
```

* **원인**: Angular SSR 프로덕션 빌드(`ng build --configuration production`)는 기본 Node.js 힙(~1.5GB)보다 많은 메모리를 필요로 함. 8GB VM에서 Solr(1GB) + PostgreSQL + DSpace Backend 서비스가 동시에 실행 중이라 가용 메모리 부족.

* **수정사항 (v8 — 2GB 힙, Backend만 중지)**: 여전히 OOM 발생. 2GB로는 부족.

* **수정사항 (v9 — 최종)**: 
  1. 빌드 전 Solr + Backend 모두 중지하여 최대한 메모리 확보
  2. Node.js 힙을 4GB로 확대 (`NODE_OPTIONS=--max-old-space-size=4096`)
```bash
# 빌드 전 메모리 확보 (Solr + Backend 모두 중지)
systemctl stop dspace-backend || true
systemctl stop solr || true

# Node.js 힙 4GB로 확대 후 빌드
sudo -u ${DSPACE_USER} bash -c "export NODE_OPTIONS='--max-old-space-size=4096' && cd /opt/dspace-angular && npm install && npm run build:prod"

# 빌드 후 서비스 재시작
systemctl restart solr
sleep 10
systemctl restart dspace-backend
```
```bash
# Solr Home 경로 자동 감지
SOLR_HOME=$(sudo -u solr /opt/solr/bin/solr status 2>/dev/null | grep -oP 'solr_home\s*:\s*\K\S+' || echo "/opt/solr-${SOLR_VERSION}/server/solr")

# 코어 복사 (Solr Home으로)
cp -r ${DSPACE_DIR}/solr/* ${SOLR_HOME}/

# core.properties 이름 명시
for CORE in authority oai qaevent search statistics suggestion; do
    echo "name=${CORE}" > ${SOLR_HOME}/${CORE}/core.properties
done

chown -R solr:solr ${SOLR_HOME}/
```

---

## (6) Frontend 500 에러 — 자체서명 SSL 인증서 거부

* **에러 위치**: PM2 dspace-ui 프로세스 (SSR 렌더링)

* **오류 메시지**:
```
ERROR Error: undefined doesn't contain the link sites
GET /home 500 268.413 ms - -
GET /home 500 753.973 ms - -
```

* **증상**: 브라우저에서 `https://dspace-isd.ddns.net` 접속 시 DSpace UI 틀(로고, 메뉴바)은 표시되지만 본문에 "500 Service unavailable" 에러 표시. REST API(`/server/api`)는 정상 응답.

### 원인 분석

DSpace Angular은 **SSR(Server-Side Rendering)** 방식으로 동작한다. 사용자가 페이지를 요청하면:

1. 브라우저 → Nginx(443) → PM2/Node.js(4000)로 요청 전달
2. Node.js(SSR)가 **서버 측에서** 백엔드 REST API를 호출하여 데이터를 가져옴
3. 데이터로 HTML을 렌더링한 뒤 브라우저에 응답

이때 2단계에서 문제가 발생한다. `config.prod.yml`의 REST 설정이:
```yaml
rest:
  ssl: true
  host: dspace-isd.ddns.net
  port: 443
  nameSpace: /server
```
이므로 Node.js SSR 프로세스는 `https://dspace-isd.ddns.net/server/api`로 백엔드를 호출한다.

Let's Encrypt 인증서 발급이 실패하여 자체서명(self-signed) 인증서를 사용하고 있는 상황에서, **Node.js는 기본적으로 신뢰할 수 없는 인증서를 거부**한다. 따라서 SSR 프로세스가 백엔드에서 데이터를 가져오지 못하고, REST API root 응답에서 `sites` 링크를 파싱하지 못해 500 에러가 발생한다.

### 요청 흐름 및 실패 지점

```
[브라우저]
    │
    ▼ HTTPS (443)
[Nginx] ─── /server/ ──→ [Backend :8080]  ✅ 정상 (직접 HTTP)
    │
    └── / ──→ [PM2/Node.js :4000]  (Frontend SSR)
                  │
                  ▼ HTTPS (443) ← ❌ 여기서 실패!
              [Nginx] → [Backend :8080]
              (자체서명 인증서 → Node.js가 거부)
```

- 브라우저 → Nginx → Backend(8080): Nginx가 내부적으로 HTTP로 proxy_pass하므로 인증서 문제 없음
- 브라우저 → Nginx → Frontend(4000): Nginx가 HTTP로 전달하므로 문제 없음
- **Frontend(SSR) → Nginx(443) → Backend**: SSR이 외부 HTTPS URL로 백엔드를 호출하므로 자체서명 인증서에서 실패

### 수정사항

PM2 시작 시 `NODE_TLS_REJECT_UNAUTHORIZED=0` 환경변수를 추가하여 Node.js가 자체서명 인증서를 허용하도록 설정:

```bash
# 변경 전
sudo -u ${DSPACE_USER} bash -c "cd /opt/dspace-angular && pm2 start 'npm run serve:ssr' --name dspace-ui"

# 변경 후
sudo -u ${DSPACE_USER} bash -c "cd /opt/dspace-angular && NODE_TLS_REJECT_UNAUTHORIZED=0 pm2 start 'npm run serve:ssr' --name dspace-ui"
```

### 참고: 외부 접속 불가 시 체크리스트

설치 완료 후 외부에서 접속이 안 될 때 아래 순서로 확인:

| 순서 | 확인 항목 | 명령어 | 정상 기준 |
|------|-----------|--------|-----------|
| 1 | 서비스 상태 | `systemctl status nginx dspace-backend` / `sudo -u dspace pm2 status` | 전부 active/online |
| 2 | 포트 리스닝 | `ss -tlnp \| grep -E '80\|443\|4000\|8080'` | 80, 443, 4000, 8080 모두 LISTEN |
| 3 | 로컬 백엔드 | `curl -k https://localhost/server/api` | JSON 응답 |
| 4 | 로컬 프론트 | `curl -k https://localhost` | HTML 응답 |
| 5 | DNS 일치 | `curl ifconfig.me` vs `nslookup dspace-isd.ddns.net` | IP 동일 |
| 6 | GCP 방화벽 | GCP Console → VM 인스턴스 → 수정 → HTTP/HTTPS 허용 체크 | ✅ 체크됨 |
| 7 | iptables | `sudo iptables -L -n \| grep -E '80\|443'` | ACCEPT 규칙 존재 |
| 8 | PM2 에러 로그 | `sudo -u dspace pm2 logs dspace-ui --lines 30` | 500 에러 없음 |

- 1~2 실패 → 서비스 설치/설정 문제
- 3 실패, 1~2 정상 → 백엔드 기동 중 (Spring Boot 시작에 약 1분 소요, 기다린 후 재시도)
- 4 실패, 3 정상 → **에러 (6)** — SSR의 자체서명 인증서 거부 문제
- 3~4 정상, 외부 접속 불가 → DNS 또는 GCP 방화벽 문제
