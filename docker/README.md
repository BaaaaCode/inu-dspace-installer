# 🏛️ DSpace 9.x Lab Environment (Offline/Local Deployment Kit)

![DSpace](https://img.shields.io/badge/DSpace-9.x-blue)
![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white)
![Python](https://img.shields.io/badge/Python-http.server-yellow?logo=python&logoColor=white)

이 저장소는 **DSpace 9.x** 실습 환경을 인터넷 연결이 제한적이거나 대역폭이 낮은 강의실(Local Lab) 환경에서 **빠르고 안정적으로 배포**하기 위해 구성되었습니다.

## 🎯 프로젝트 목적 (Why?)
- **대규모 동시 접속 해결:** 40명 이상의 학생이 동시에 Docker Image(약 3GB)를 다운로드할 때 발생하는 외부 네트워크 병목 현상 방지.
- **설치 시간 단축:** 로컬 네트워크(LAN)를 활용하여 초고속 전송(100MB/s+) 구현.
- **버전 일관성:** 모든 실습생이 동일한 환경(Image hash)에서 학습할 수 있도록 보장.

---

## 📂 파일 구성
| 파일명 | 설명 |
|---|---|
| `docker-compose.yml` | DSpace 9.x (Frontend, Backend, DB) 실행을 위한 오케스트레이션 파일 |
| `image.tar` | 사전 빌드된 Docker 이미지 패키지 (Backend, Frontend, DB 포함) |
| `docker.exe` | Docker Desktop 설치 파일 (Windows용) |

---

## 👨💻 TA 가이드: 배포 서버 구축 (Server Side)
*강의 시작 전, TA PC(Server)에서 수행하는 단계입니다.*

### 1. 사전 준비 (이미지 패키징)
인터넷이 원활한 환경에서 미리 이미지를 다운로드하고 패키징합니다.
```bash
# 1. 이미지 Pull (필요한 경우)
docker compose pull

# 2. 이미지 패키징 (tar 변환)
# 현재 디렉토리의 image.tar 파일로 저장되어 있습니다.
# 만약 새로 생성한다면 아래 명령어를 사용하세요:
# docker save -o image.tar dspace/dspace:dspace-9_x dspace/dspace-angular:dspace-9_x dspace/dspace-postgres-pgcrypto:dspace-9_x
```

### 2. 로컬 배포 서버 가동

파일들이 있는 폴더에서 웹 서버를 실행하여 학생들에게 파일을 제공합니다.
*(Python 또는 Docker Nginx 중 택 1)*

**Option A: Python 사용 (간편함)**

```bash
# 8000번 포트로 서버 개방
python -m http.server 8000
```

**Option B: Docker Nginx 사용 (대규모 트래픽 권장)**

```bash
docker run --rm -p 8000:80 -v "${PWD}:/usr/share/nginx/html" nginx
```

### 3. 방화벽 설정

* **방법 1 (권장):** Windows 방화벽 인바운드 규칙에서 `8000`번 포트(TCP) 개방. 
* **방법 2 (임시):** 배포 시간 동안만 방화벽 잠시 해제 (`방화벽 및 네트워크 보호` > `개인/공용 네트워크` > `끔`).

---

## 👩🎓 학생 가이드: 설치 및 실행 (Client Side)

*실습실 PC에서 아래 순서대로 천천히 진행해주세요.*

### 1단계: 실습 파일 다운로드 (준비)

1. **크롬 브라우저**를 켭니다.
2. 칠판에 적힌 **TA IP 주소**를 주소창에 입력하고 엔터를 칩니다.
   > 예시: `http://[IP_ADDRESS]` # 수업 중 제공 예정
3. 화면에 보이는 파일 3개를 모두 다운로드 받습니다.
   - `docker.exe` (도커 설치 파일)
   - `image.tar` (이미지 팩)
   - `docker-compose.yml` (실행 파일)

### 2단계: Docker 설치 및 실행

1. 다운로드 받은 `docker.exe`를 더블클릭해서 설치합니다. (계속 `Ok` 누르시면 됩니다)
2. **설치가 끝나면 꼭 재부팅(컴퓨터 껐다 켜기)을 해주세요!** 🔄

> **⚠️ 재부팅 후 "WSL 2 Installation is incomplete(window용 linux 하위 시스템 설치)" 창 발생 시**
> 1. 허용 버튼 클릭
> 2. 터미널 내 아무 글자 입력 
> 3. 절차에 따라 설치 진행
> 4. 위 절차 순서대로 진행을 못 한 경우 `http://[IP_ADDRESS]/wsl.msi`를 주소창에 입력 후 파일 다운로드 
> 5. 다운로드 된 파일 실행 후 재부팅
> 6. 다시 **Docker Desktop**을 켜면 잘 됩니다!

3. 재부팅 후, 바탕화면이나 시작 메뉴에서 **Docker Desktop**을 실행합니다.
4. 화면 오른쪽 아래 시간 옆에 **작은 고래 아이콘(🐳)**이 생겼다면 성공입니다!

### 3단계: 명령어 입력 (터미널)

1. 폴더 창 주소줄(위쪽)에 `powershell`이라고 치고 엔터를 누르세요.
   > **팁:** `Cmd`나 다른 터미널도 되지만, 파일이 있는 폴더에서 여는 것이 중요합니다!
2. 파란 화면(터미널)이 나오면 아래 명령어를 **한 줄씩 복사**해서 붙여넣으세요.

**첫 번째 명령어** (이미지 불러오기 - 약 1~2분 걸림)
```powershell
docker load -i image.tar
```
> *입력 후 엔터를 치세요. "Loaded image..." 메시지가 나오면 성공!*

**두 번째 명령어** (서버 켜기)
```powershell
docker compose -f docker-compose.yml up -d
```
> *뭔가 주르륵 뜨고 "Started"라고 뜨면 성공입니다.*

### 4단계: 접속 확인 (완료!)

이제 인터넷 주소창에 아래 주소를 입력해서 화면이 나오는지 확인해 보세요!

1. **사용자 화면:** http://localhost:4000
2. **관리자 화면:** http://localhost:8080/server

> **"500 Service Unavailable" 에러가 발생한 경우(사용자 화면)**
> **지극히 정상입니다!** 백엔드(서버)가 켜지는 데 **약 3~5분** 정도 걸립니다.
> 컴퓨터 사양에 따라 시간이 조금 걸리니, 500 에러 화면이 떠도 당황하지 말고 **3분 뒤에 새로고침(F5)** 키를 눌러보세요.

*🎉 축하합니다! DSpace 실습 환경 구축이 끝났습니다.*

---

## 🛠️ 자주 묻는 질문 (FAQ)

**Q. "Error response from daemon: Docker Desktop is unable to start..." 오류가 떠요!**
> -> **Docker가 아직 안 켜져서 그렇습니다.**
> -> 바탕화면에 있는 **Docker Desktop**을 실행하고, 오른쪽 아래 **고래 아이콘(🐳)**이 움직임을 멈출 때까지 기다려 주세요.
> -> 고래가 멈추면 다시 명령어를 입력하세요.(State: Docker Desktop is running)

**Q. 첫 번째 명령어(`docker load`)를 쳤는데 에러가 나요!**
> "open ...: no such file or directory" 라는 말이 나오나요?
> -> **터미널이 열린 위치**가 잘못되어서 그렇습니다.
> -> 터미널을 끄고, **파일이 있는 폴더(보통 '다운로드' 폴더)**로 가서 다시 `Shift` + `우클릭` -> `PowerShell 열기`를 해보세요.

**Q. 사이트(localhost:4000) 접속이 안 돼요.**
> -> **서버가 켜지는 데 시간이 조금 걸립니다.** (약 2~3분)
> -> 3분 정도 기다렸다가 인터넷 창에서 **새로고침(F5)** 키를 눌러보세요.

**Q. TA 서버 IP로 접속이 안 돼요.**
> -> 와이파이가 **강의실 와이파이**인지 확인해주세요. (다른 와이파이면 접속이 안 됩니다!)

**Q. localhost:4000 접속했더니 "500 Service Unavailable" 빨간 에러가 떠요!**
> -> **서버가 아직 부팅 중입니다.** (고장 난 게 아닙니다!)
> -> DSpace는 덩치가 커서 켜지는 데 시간이 좀 걸립니다.
> -> 약 **3~5분 정도** 기다렸다가 페이지를 **새로고침(F5)** 하면 정상적으로 화면이 뜹니다.

---

## 📝 License

This project is based on [DSpace](https://dspace.lyrasis.org/).
