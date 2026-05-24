# 🏛️ DSpace 9.1 Automated Installer (GCP / On-Premise)

![DSpace](https://img.shields.io/badge/DSpace-9.1-blue)
![Ubuntu](https://img.shields.io/badge/Ubuntu-22.04_LTS-E95420?logo=ubuntu&logoColor=white)
![Solr](https://img.shields.io/badge/Solr-9.6.1-D9411E?logo=apachesolr&logoColor=white)
![Nginx](https://img.shields.io/badge/Nginx-Reverse_Proxy-009639?logo=nginx&logoColor=white)

Ubuntu 22.04 LTS 서버에서 **DSpace 9.1**을 원클릭으로 설치하는 자동화 스크립트입니다.
사전 준비(Java, Maven, PostgreSQL 등)부터 SSL 인증서, Nginx 리버스 프록시까지 **한 파일로 완결**됩니다.

## 🎯 프로젝트 목적 (Why?)

- **완전 자동화:** 15단계 설치 과정을 단일 스크립트로 통합. `sudo bash install.sh` 한 줄이면 끝.
- **실패 복구:** 실패 지점을 자동 감지하여 재실행 시 완료된 단계를 건너뛰고 이어서 진행.
- **환경 유연성:** GCP VM 테스트 환경과 학교 물리 서버(포트 기반 멀티 인스턴스) 모두 대응 가능.

---

## 📂 파일 구성

| 파일명 | 설명 |
|---|---|
| `install.sh` | DSpace 9.1 자동 설치 스크립트 (최종본) |
| `에러_해결_정리.md` | 개발 과정에서 발견·수정된 에러 6건의 상세 기록 |
| `README.md` | 상세 운영 매뉴얼 (오류 대처, 학교 서버 배포 가이드 포함) |
| `install_v4.sh` ~ `install_v9.sh` | 에러 수정 과정의 버전별 스크립트 (이력 보존용) |

---

## ⚙️ 작동 구조

### 서비스 아키텍처

```
[브라우저] ── HTTPS (443) ──▶ [Nginx]
                                 │
                     ┌───────────┴───────────┐
                     ▼                       ▼
              /server/                      /
         [Backend :8080]            [Frontend :4000]
         Spring Boot JAR            Angular SSR (PM2)
              │                          │
         ┌────┴────┐               SSR → Backend
         ▼         ▼               (서버사이드 렌더링)
   [PostgreSQL] [Solr :8983]
```

### 설치 단계 (15 STEP)

| STEP | 내용 | 소요 시간 |
|:----:|------|:---------:|
| 0 | 시스템 업데이트, Swap(4GB), 방화벽, 기본 패키지 | 3~5분 |
| 1 | DSpace 전용 유저 생성 | < 1분 |
| 2 | Java JDK 17 | 1~2분 |
| 3 | Maven 3.8.8 + Ant | 1~2분 |
| 4 | PostgreSQL + DB + pgcrypto + 튜닝 | 2~3분 |
| 5 | Node.js 20 + PM2 | 1~2분 |
| 6 | Apache Solr 9.6.1 | 2~3분 |
| 7 | Backend 다운로드 + Maven/Ant 빌드 | **10~15분** |
| 8 | Solr 코어 배포 + 로드 확인 | 1~2분 |
| 9 | DB 마이그레이션 + 인덱싱 | 2~3분 |
| 10 | Backend systemd 서비스 등록 | < 1분 |
| 11 | Frontend 다운로드 + Angular SSR 빌드 | **10~15분** |
| 12 | PM2 프로세스 등록 | < 1분 |
| 13 | SSL 인증서 + Nginx HTTPS | 1~2분 |
| 14 | Logrotate, 백업 cron, 최종 점검 | 1분 |

> 💡 **전체 소요: 약 30~40분** (네트워크 속도에 따라 상이)

---

## 🚀 빠른 시작 (Quick Start)

### 1단계: GCP VM 생성

| 항목 | 권장값 |
|------|--------|
| 머신 유형 | `e2-standard-2` (vCPU 2, RAM 8GB) |
| OS | Ubuntu 22.04 LTS |
| 디스크 | 30GB 이상 (SSD 권장) |
| 방화벽 | ✅ HTTP 허용 / ✅ HTTPS 허용 |

### 2단계: 스크립트 업로드 및 실행

```bash
# VM에 SSH 접속 후

# 1. install.sh 업로드 (브라우저 SSH → 파일 업로드)

# 2. 도메인 수정 (필요 시)
nano install.sh
# → 상단 DOMAIN="your-domain.ddns.net" 수정

# 3. 실행
sudo bash install.sh
```

### 3단계: 접속 확인

```
DSpace UI  : https://your-domain.ddns.net
REST API   : https://your-domain.ddns.net/server/api
```

> ⚠️ 자체서명 인증서 사용 시 브라우저에서 **"고급" → "안전하지 않음으로 계속"** 클릭이 필요합니다.

---

## 🔄 실패 시 재시작

설치 중 실패하면 아래와 같은 안내가 자동 출력됩니다:

```
╔══════════════════════════════════════════════════════════════╗
║                    설치 실패                                ║
╠══════════════════════════════════════════════════════════════╣
║  실패 단계 : STEP 7 — DSpace 백엔드 다운로드 + 빌드
║  실패 위치 : install.sh line 285
║  로그 파일 : /var/log/dspace-install.log
╠══════════════════════════════════════════════════════════════╣
║  재시작 방법:
║    sudo bash install.sh              ← 자동 재개
║    sudo bash install.sh --step 7     ← 7단계부터 강제
╚══════════════════════════════════════════════════════════════╝
```

```bash
# 방법 1: 자동 재개 (완료된 단계 skip)
sudo bash install.sh

# 방법 2: 특정 단계부터 강제 시작
sudo bash install.sh --step 7

# 방법 3: 처음부터 전체 재실행
sudo rm /var/log/dspace-install-progress
sudo bash install.sh --step 0
```

---

## 🛠️ 트러블슈팅

### 설치 중 오류

| 증상 | STEP | 대처 |
|------|:----:|------|
| Solr 설치 실패 | 6 | 네트워크 확인 후 재실행 |
| Maven 빌드 실패 | 7 | 재실행하면 자동 재개 |
| Frontend OOM (heap out of memory) | 11 | 아래 Swap 확대 참조 |
| SSL 인증서 실패 | 13 | 자체서명으로 자동 대체 (정상) |

**Frontend OOM 대처 (4GB VM):**

```bash
# Swap 8GB로 확대
sudo swapoff /swapfile
sudo fallocate -l 8G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# 빌드 단계부터 재시작
sudo bash install.sh --step 11
```

### 설치 후 접속 불가

```bash
# 1. 서비스 확인
systemctl status nginx dspace-backend
sudo -u dspace pm2 status

# 2. 포트 확인
ss -tlnp | grep -E '80|443|4000|8080'

# 3. 로컬 테스트
curl -k https://localhost/server/api    # JSON 응답 → 정상
curl -k https://localhost               # HTML 응답 → 정상
```

- **로컬 정상 + 외부 불가** → DNS 또는 GCP 방화벽 문제
- **로컬 API 정상 + 프론트 500** → PM2 로그 확인: `sudo -u dspace pm2 logs dspace-ui --lines 30`

### 500 Service unavailable (DSpace 로고는 보임)

```bash
# 자체서명 인증서 거부 문제 → PM2 재설정
sudo -u dspace pm2 delete dspace-ui
sudo -u dspace bash -c "cd /opt/dspace-angular && NODE_TLS_REJECT_UNAUTHORIZED=0 pm2 start 'npm run serve:ssr' --name dspace-ui"
sudo -u dspace pm2 save
```

---

## 🏫 학교 서버 배포 (On-Premise)

학교 물리 서버에 배포할 경우, 고정 IP + 학생별 포트 분리 구조를 사용합니다.

### 변경 개요

| 항목 | GCP (현재) | 학교 서버 |
|------|-----------|----------|
| 접속 방식 | `https://도메인` | `http://고정IP:포트` |
| SSL | Let's Encrypt / 자체서명 | 불필요 |
| Nginx | 리버스 프록시 | 불필요 |
| 인스턴스 | 1개 | 학생 수만큼 |

### 학생별 포트 할당 예시

| 학생 | Backend | Frontend | DB | 접속 URL |
|:----:|:-------:|:--------:|:--:|----------|
| 01 | 8001 | 4001 | dspace_01 | `http://IP:4001` |
| 02 | 8002 | 4002 | dspace_02 | `http://IP:4002` |
| 03 | 8003 | 4003 | dspace_03 | `http://IP:4003` |
| ... | ... | ... | ... | ... |

### 스크립트 분리 구조 (안)

```
install_base.sh        ← TA 1회 실행 (Java, Maven, PostgreSQL, Solr 등)
install_student.sh     ← 학생 각자 실행
```

```bash
# TA: 공용 서비스 설치
sudo bash install_base.sh

# 학생: 자기 인스턴스 설치
sudo bash install_student.sh --student 3
# → Backend:8003, Frontend:4003, DB:dspace_03
```

> 📖 학교 서버 배포의 상세 가이드(설정값 변경, Solr 코어 분리, 체크리스트 등)는 [README.md](./README.md) 7장을 참조하세요.

---

## 📁 주요 경로

| 항목 | 경로 |
|------|------|
| DSpace 설치 | `/dspace` |
| Backend 소스 | `/opt/dspace-source` |
| Frontend 소스 | `/opt/dspace-angular` |
| DSpace 설정 | `/dspace/config/local.cfg` |
| Frontend 설정 | `/opt/dspace-angular/config/config.prod.yml` |
| Nginx 설정 | `/etc/nginx/sites-available/dspace` |
| 설치 로그 | `/var/log/dspace-install.log` |
| 진행 기록 | `/var/log/dspace-install-progress` |

---

## 🐛 에러 수정 이력

이 스크립트는 교수님 제공 원본 `install.sh`를 GCP VM에서 실제 실행하며 발견된 6건의 에러를 수정한 결과물입니다.

| # | 에러 | 원인 | 수정 버전 |
|:-:|------|------|:---------:|
| 1 | Solr 설치 실패 | 파일명에서 버전 파싱 불가 | v4 |
| 2 | Solr 서비스 시작 실패 | 로그 디렉토리 권한 | v4 |
| 3 | Ant 빌드 실패 | pgcrypto 미설치 | v4 |
| 4 | Solr 코어 미인식 | Solr Home 경로 불일치 + core.properties | v7 |
| 5 | Frontend OOM | 메모리 부족 (8GB VM) | v9 |
| 6 | Frontend 500 에러 | 자체서명 SSL 인증서 거부 | v9 |

> 각 에러의 상세 분석은 [`에러_해결_정리.md`](./에러_해결_정리.md)를 참조하세요.

---

## 📝 License

This project is based on [DSpace](https://dspace.lyrasis.org/) — the world's leading open source repository platform.
