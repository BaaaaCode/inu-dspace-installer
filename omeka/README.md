# Omeka Classic 3.2 자동 설치 스크립트

---

## 1. 개요

이 스크립트(`install_omeka.sh`)는 **Ubuntu 22.04 LTS** 환경에서 Omeka Classic 3.2를 자동으로 설치합니다. Apache2, MariaDB, PHP 7.4 설정부터 Omeka 배포, 한글 패치까지 **한 파일로 완결**되며, 실패 시 실패 지점부터 자동으로 재개할 수 있도록 설계되어 있습니다.

**주요 특징:**

- 10단계(STEP 0~9)로 구성, 각 단계는 독립적으로 skip 가능
- 실패 시 실패 단계·위치·로그 경로를 안내하는 에러 핸들러 내장
- `--step N` 옵션으로 특정 단계부터 강제 시작 가능
- `--env gcp|local` 옵션으로 환경 선택 (GCP 도메인+SSL / 교내 서버 IP+HTTP)
- `--korean` 옵션으로 한글 패치 적용
- 설치 로그(`/var/log/omeka-install.log`)와 진행 기록(`/var/log/omeka-install-progress`) 자동 생성

---

## 2. 작동 구조

### 2.1 설치 단계

| STEP | 내용 | 예상 소요 |
|------|------|-----------|
| 0 | 시스템 업데이트, Swap(2GB), 방화벽(UFW), 기본 패키지 | 3~5분 |
| 1 | Apache2 설치 | < 1분 |
| 2 | MariaDB 설치, DB 생성, 전용 유저 생성 | 1~2분 |
| 3 | PHP 7.4 + 확장 모듈 + ImageMagick + FFmpeg | 2~3분 |
| 4 | Omeka Classic 3.2 다운로드 + 배포 | 1~2분 |
| 5 | DB 연결 (db.ini 자동 생성) | < 1분 |
| 6 | Apache 설정 (rewrite + VirtualHost) | < 1분 |
| 7 | 한글 패치 (--korean 옵션 시) | < 1분 |
| 8 | SSL + Nginx HTTPS (GCP) / 포트 확인 (local) | 1~2분 |
| 9 | Logrotate, 최종 상태 점검 | < 1분 |

**전체 소요: 약 10~15분** (네트워크 속도에 따라 상이)

### 2.2 서비스 구조

#### GCP 모드 (`--env gcp`)

```
[브라우저]
    │
    ▼ HTTPS (443)
[Nginx 리버스 프록시]
    │
    ▼ HTTP (8080)
[Apache2 + mod_php]
    │
    ├── DocumentRoot: /var/www/omeka  (Omeka Classic PHP)
    │
    └── [MariaDB :3306]  (omeka DB)
```

#### 교내 서버 모드 (`--env local`)

```
[브라우저]
    │
    ▼ SSH 터널 (localhost:PORT)
    │
[Apache2 + mod_php :PORT]
    │
    ├── DocumentRoot: /var/www/omeka  (Omeka Classic PHP)
    │
    └── [MariaDB :3306]  (omeka DB)
```

### 2.3 자동 Skip 로직

스크립트를 다시 실행하면 각 단계마다 **완료 여부를 자동 감지**합니다:

- `/var/log/omeka-install-progress` 파일에 완료된 단계가 기록됨
- 이미 기록된 단계는 자동으로 건너뜀
- `--step N` 옵션으로 특정 단계부터 강제 재시작 가능

---

## 3. 네트워크 구조 (교내 서버)

### 3.1 전체 구조

교내 서버 환경에서는 외부에서 VM으로 직접 웹 접속이 불가능합니다. SSH 터널링을 통해 접근합니다.

```
[외부 PC 브라우저]
    │
    ▼ SSH 터널 (MobaXterm / Xshell)
[open.inu.ac.kr:15000]  ← SSH 게이트웨이
    │
    ▼
[물리 서버 10.80.103.32]
    │ VirtualBox NAT
    ├── :20260 → IS20260 (관리 서버)
    ├── :20272 → IS20272
    ├── :20291 → IS20291 (Omeka 테스트)
    └── ...
```

### 3.2 SSH 터널링 접속 원리

물리 서버의 각 포트는 VirtualBox NAT를 통해 VM의 SSH(22)로 포워딩됩니다. 웹 서비스에 접근하려면 **Apache의 Listen 포트를 배정받은 포트 번호와 일치**시키고, SSH 터널을 통해 해당 포트에 접근합니다.

```
직접 접근 (안 됨):
  브라우저 → 10.80.103.32:20291 → SSH 서비스가 받음 → ❌

SSH 터널 (됨):
  브라우저 → localhost:PORT → SSH 터널 → VM 내부 localhost:PORT → Apache → ✅
```

### 3.3 핵심 규칙

**터널링 Destination 포트 = Apache Listen 포트** — 이 두 값이 일치해야 Omeka의 주소창 리다이렉션이 정상 작동합니다. `install_omeka.sh`의 `LOCAL_PORT` 변수가 이 값을 자동으로 Apache 설정에 반영합니다.

---

## 4. TA 사전 준비사항

### 4.1 VM 확인

| 항목 | 값 |
|------|-----|
| OS | Ubuntu 22.04 LTS |
| 물리 서버 IP | 10.80.103.32 |
| SSH 게이트웨이 | open.inu.ac.kr:15000 |
| TA 테스트 포트 | 20291 (IS20291) |

### 4.2 터널링 프로그램 설정 (MobaXterm 기준)

| 항목 | 값 |
|------|-----|
| Type | Local |
| Local port | `20291` |
| Destination | `10.80.103.32:20291` |
| SSH server | `sbyang@open.inu.ac.kr:15000` |

### 4.3 install_omeka.sh 설정값 수정

스크립트 상단의 설정값을 환경에 맞게 수정합니다:

```bash
# install_omeka.sh 상단 — 환경에 맞게 수정
LOCAL_IP="10.80.103.32"          # 교내 서버 IP
LOCAL_PORT="20291"               # 배정받은 포트 번호
DB_PASSWORD="omeka"              # DB 비밀번호 (필요 시 변경)
```

### 4.4 테스트 실행

```bash
# IS20291 VM에 SSH 접속 후 실행
sudo bash install_omeka.sh --env local --korean
```

설치 완료 후 브라우저에서 `http://localhost:20291/` 접속하여 Omeka 설치 페이지가 뜨는지 확인합니다.

---

## 5. 학생 실행 가이드

### 5.1 사전 준비

1. TA로부터 **포트 번호**를 배정받습니다 (예: `20265`)
2. 터널링 프로그램(MobaXterm/Xshell)에서 포트 포워딩 규칙을 추가합니다

| 항목 | 값 (예시: 포트 20265) |
|------|----------------------|
| Type | Local |
| Local port | `20265` |
| Destination | `10.80.103.32:20265` |
| SSH server | `본인계정@open.inu.ac.kr:15000` |

### 5.2 실행 방법

VM에 SSH 접속 후:

```bash
# 1. install_omeka.sh 업로드 (SCP 또는 파일 전송)

# 2. 스크립트 상단에서 포트 번호 수정
LOCAL_PORT="20265"    # 각자 배정받은 포트 번호 입력

# 3. 실행
sudo bash install_omeka.sh --env local --korean
```

설치는 약 10~15분 소요됩니다.

### 5.3 설치 완료 확인

스크립트 마지막에 아래와 같은 메시지가 출력됩니다:

```
==================================================
 Omeka Classic 3.2 설치 완료!
==================================================

  환경 모드     : local
  공개용 접속   : http://10.80.103.32:20265
  관리자 페이지 : http://10.80.103.32:20265/admin
```

터널링 프로그램을 켠 상태에서 브라우저에 아래 주소를 입력합니다:

```
http://localhost:20265/
```

> SSH 터널링을 통해 포워딩된 것이므로, `10.80.103.32`가 아닌 **`localhost`**로 접근해야 합니다.

첫 접속 시 Omeka 초기 설정 페이지가 표시되며, 관리자 계정을 생성해야 합니다.

### 5.4 설치 중 실패한 경우

실패 시 아래와 같은 안내가 출력됩니다:

```
============================================================
  설치 실패
============================================================
  실패 단계 : STEP 3 -- PHP 7.4 + 확장 모듈
  실패 위치 : install_omeka.sh line 325
  로그 파일 : /var/log/omeka-install.log
  진행 기록 : /var/log/omeka-install-progress
------------------------------------------------------------
  재시작 방법:
    sudo bash install_omeka.sh --env local
      -> 완료된 단계는 자동 skip, 실패 지점부터 재개
    sudo bash install_omeka.sh --env local --step 3
      -> 3단계부터 강제 재시작
============================================================
```

1. **로그 확인**: `cat /var/log/omeka-install.log | tail -50`
2. **그대로 재실행**: `sudo bash install_omeka.sh --env local` — 완료된 단계는 자동 skip됨
3. 같은 에러가 반복되면 로그와 스크린샷을 TA에게 전달

---

## 6. 오류 발생 시 대처 방안

### 6.1 설치 중 오류

| 증상 | 원인 | 대처 |
|------|------|------|
| STEP 2에서 `Access denied for user 'root'@'localhost'` | MariaDB root 비밀번호가 이미 설정됨 | `sudo mysql`로 접속하여 수동으로 DB/유저 생성 후 `--step 3`으로 재시작 |
| STEP 3에서 PPA 추가 실패 | 네트워크 접근 불가 또는 PPA 서버 문제 | 네트워크 확인 후 재실행 |
| STEP 4에서 다운로드 실패 | GitHub 접근 불가 | 네트워크 확인 후 재실행 (이미 다운받은 파일은 재사용됨) |
| STEP 5에서 db.ini syntax error | 스마트 따옴표(`""`) 사용 | 스크립트가 자동으로 일반 따옴표 사용하므로 발생하지 않음. 수동 편집 시 주의 |
| STEP 6에서 Apache configtest 실패 | 설정 파일 문법 오류 | `/etc/apache2/sites-available/omeka.conf` 확인 |
| STEP 8에서 SSL 실패 (GCP) | DNS 미설정 또는 전파 지연 | 자체서명 인증서로 자동 대체됨 (정상) |

### 6.2 설치 완료 후 접속 불가

아래 체크리스트를 **순서대로** 확인합니다:

| 순서 | 확인 항목 | 명령어 | 정상 기준 |
|------|-----------|--------|-----------|
| 1 | Apache 서비스 상태 | `systemctl status apache2` | active (running) |
| 2 | MariaDB 서비스 상태 | `systemctl status mariadb` | active (running) |
| 3 | Apache 포트 리스닝 | `ss -tlnp \| grep apache` | `LOCAL_PORT`에서 LISTEN |
| 4 | Omeka 응답 확인 | `curl -I http://localhost:PORT` | 200 또는 302 응답 |
| 5 | 터널링 프로그램 상태 | MobaXterm/Xshell에서 터널 활성화 확인 | Running |
| 6 | 브라우저 접속 | `http://localhost:PORT/` | Omeka 페이지 표시 |

**판단 기준:**

- 1~2 실패 → 서비스 문제. `sudo systemctl restart apache2 mariadb` 실행
- 3 실패 → Apache가 잘못된 포트에서 대기 중. `/etc/apache2/ports.conf`에서 `Listen PORT` 확인
- 4 실패, 1~3 정상 → Omeka 설정 문제. `/var/log/apache2/omeka-error.log` 확인
- 4 정상, 6 실패 → 터널링 설정 문제. Destination 포트가 Apache Listen 포트와 일치하는지 확인
- `ERR_INVALID_HTTP_RESPONSE` → 터널이 SSH 서비스에 연결됨. 터널 Destination 포트 확인

### 6.3 Connection Timeout이 반복되는 경우

교내 서버에서 가장 흔한 문제입니다. 원인은 거의 항상 **터널링 Destination 포트 ≠ Apache Listen 포트** 불일치입니다.

확인 방법:
```bash
# VM 내부에서 Apache가 어떤 포트에서 대기 중인지 확인
sudo ss -tlnp | grep apache

# ports.conf 확인
cat /etc/apache2/ports.conf | grep Listen

# omeka.conf 확인
cat /etc/apache2/sites-available/omeka.conf | grep VirtualHost
```

세 값이 모두 배정받은 포트 번호와 일치해야 합니다.

### 6.4 Omeka "has encountered an error" 페이지

Omeka 접속은 되지만 에러 페이지가 뜨는 경우:

```bash
# Omeka 에러 로그 확인
cat /var/log/apache2/omeka-error.log | tail -20

# db.ini 설정 확인
cat /var/www/omeka/db.ini
```

흔한 원인:

| 증상 | 원인 | 대처 |
|------|------|------|
| DB 연결 실패 | db.ini의 username/password 오류 | db.ini 수정 후 Apache 재시작 |
| db.ini syntax error (line N) | `//` 주석 사용 (ini는 `;`만 지원) | `//` 주석을 `;`로 변경하거나 제거 |
| db.ini syntax error (smart quotes) | PDF에서 복붙 시 스마트 따옴표 혼입 | `sed -i "s/[\x{201c}\x{201d}]/\"/g" /var/www/omeka/db.ini` |

---

## 7. 참고사항

### 7.1 주요 파일 경로

| 항목 | 경로 |
|------|------|
| Omeka 설치 디렉토리 | `/var/www/omeka` |
| Omeka 설정 | `/var/www/omeka/application/config/config.ini` |
| DB 연결 설정 | `/var/www/omeka/db.ini` |
| 업로드 파일 | `/var/www/omeka/files` |
| Apache VirtualHost | `/etc/apache2/sites-available/omeka.conf` |
| Apache 포트 설정 | `/etc/apache2/ports.conf` |
| 설치 로그 | `/var/log/omeka-install.log` |
| 진행 기록 | `/var/log/omeka-install-progress` |
| Apache 에러 로그 | `/var/log/apache2/omeka-error.log` |
| Apache 접근 로그 | `/var/log/apache2/omeka-access.log` |

### 7.2 주요 서비스 관리 명령어

```bash
# Apache 시작/중지/재시작
sudo systemctl start|stop|restart apache2

# MariaDB 시작/중지/재시작
sudo systemctl start|stop|restart mariadb

# Apache 설정 문법 검사
sudo apache2ctl configtest

# Omeka 파일 권한 재설정
sudo chown -R www-data:www-data /var/www/omeka
sudo find /var/www/omeka/files -type d -exec chmod 777 {} \;
sudo find /var/www/omeka/files -type f -exec chmod 666 {} \;
```

### 7.3 설치 초기화 (완전 재설치)

```bash
# 1. Omeka 파일 삭제
sudo rm -rf /var/www/omeka

# 2. DB 삭제
sudo mysql -e "DROP DATABASE IF EXISTS omeka; DROP USER IF EXISTS 'omeka'@'localhost'; FLUSH PRIVILEGES;"

# 3. 진행 기록 삭제
sudo rm -f /var/log/omeka-install-progress

# 4. 처음부터 재실행
sudo bash install_omeka.sh --env local --korean --step 0
```

### 7.4 Omeka Classic vs Omeka S 비교

| 구분 | Classic | S |
|------|---------|---|
| 운영 목적 | 단일 프로젝트, 단일 테마 전시 | 기관 단위, 다중 사이트 운영 |
| 리소스 풀 | 사이트별 개별 데이터 관리 | 통합 데이터 풀을 여러 사이트에서 공유 |
| 메타데이터 | Dublin Core 기반 | LOD 기반, 확장 가능한 온톨로지 |
| 대상 사용자 | 개인 연구자, 소규모 프로젝트 | 대학, 박물관, 기록관 |

### 7.5 GCP 배포 시 추가 사항

GCP 환경에서는 도메인 + SSL 구성을 사용합니다:

```bash
# install_omeka.sh 상단 수정
GCP_DOMAIN="omeka.example.com"    # 실제 도메인으로 변경

# 실행
sudo bash install_omeka.sh --env gcp --korean
```

- No-IP 또는 별도 도메인 서비스에서 호스트네임 생성 후 VM 외부 IP로 설정
- SSL 인증서는 Let's Encrypt로 자동 발급, 실패 시 자체서명 인증서로 대체
- 자체서명 인증서 사용 중일 때 브라우저에서 보안 경고가 뜨면 "고급 → 안전하지 않음으로 계속" 클릭

---

## 8. 학생 배포 가이드라인 (TA 매뉴얼)

### 8.1 포트 할당 계획

각 학생에게 고유 포트를 배정합니다. 포트 번호가 곧 VM 접속 포트이자 Apache Listen 포트입니다.

| 학생 | VM | 포트 | 접속 주소 (터널링 후) |
|------|-----|------|---------------------|
| TA (테스트) | IS20291 | 20291 | `http://localhost:20291/` |
| 학생 A | IS20265 | 20265 | `http://localhost:20265/` |
| 학생 B | IS20266 | 20266 | `http://localhost:20266/` |

### 8.2 학생별 설정

학생은 `install_omeka.sh` 상단에서 **`LOCAL_PORT`만 수정**하면 됩니다:

```bash
LOCAL_PORT="20265"    # 각자 배정받은 포트 번호 입력
```

스크립트가 자동으로 처리하는 항목:
- `/etc/apache2/ports.conf` → `Listen ${LOCAL_PORT}`
- `/etc/apache2/sites-available/omeka.conf` → `<VirtualHost *:${LOCAL_PORT}>`
- UFW 방화벽 포트 오픈

### 8.3 학생 안내 체크리스트

- [ ] 포트 번호 배정 및 공지
- [ ] 터널링 프로그램 설정 방법 안내 (5.1절 참조)
- [ ] `install_omeka.sh` 파일 배포
- [ ] `LOCAL_PORT` 수정 방법 안내
- [ ] 실행 명령어 안내: `sudo bash install_omeka.sh --env local --korean`
- [ ] 접속 주소 안내: `http://localhost:본인포트/`
- [ ] 실패 시 대처 방법 안내 (5.4절 참조)

---

## 9. 에러 해결 이력

이 스크립트 개발 과정에서 발견·수정된 에러 목록입니다.

| 문제 | 원인 | 해결 |
|------|------|------|
| Ansible `host.ini` 파싱 실패 | 파일명 오타 (`host.ini` → `hosts.ini`) | 파일명 수정 |
| Omeka "has encountered an error" | `db.ini`에 `//` 주석 사용 (ini는 `;`만 지원) | 주석 제거 |
| db.ini syntax error (line 20) | PDF에서 복붙한 스마트 따옴표 (`"` → `"`) | `sed`로 정상 따옴표로 교체 |
| `Access denied for user 'root'@'localhost'` | 이전 수동 설치에서 root 비밀번호 설정됨 | 전용 DB 유저(`omeka`) 사용으로 해결 |
| Connection Timeout (외부 접속 불가) | 터널링 Destination 포트 ≠ Apache Listen 포트 | 두 포트를 `LOCAL_PORT`로 일치시켜 해결 |
| `ERR_INVALID_HTTP_RESPONSE` | 터널이 SSH 서비스(22)에 연결됨 | 터널 Destination을 Apache 포트로 수정 |
