# Flink Docker Multi-Stage Build & PyFlink 환경 구성

**작성일**: 2025-11-03  
**작업 범위**: Flink Docker 이미지 빌드 환경 구성 및 PyFlink 패키지 설치 문제 해결

---

## 목차
1. [작업 개요](#작업-개요)
2. [시간순 작업 내역](#시간순-작업-내역)
3. [기술 개념 정리](#기술-개념-정리)

---

## 작업 개요

Flink 2.1.0 기반 Docker 이미지에 PyFlink 및 관련 Python 패키지를 설치하고, multi-stage build를 통해 경량화된 최종 이미지를 생성하는 작업을 수행했습니다.

**주요 목표**:
- uv를 사용한 빠른 패키지 설치
- pemja (Python-Java 브리지) 빌드 성공
- multi-stage build를 통한 이미지 경량화
- 최종 이미지에서 Python 실행 환경 정상 동작

---

## 시간순 작업 내역

### 1. requirements.txt 형식 수정

#### 이슈
- requirements.txt가 pip 형식이 아닌 잘못된 형식으로 작성됨
- 따옴표와 괄호로 감싸진 버전 지정자

```text
"kafka-python (>=2.2.15,<3.0.0)",
"psycopg2-binary (>=2.9.10,<3.0.0)",
...
```

#### 해결
- pip 표준 형식으로 변환

```bash
# 수정 후
kafka-python>=2.2.15,<3.0.0
psycopg2-binary>=2.9.10,<3.0.0
confluent-kafka>=2.3.0,<3.0.0
googleapis-common-protos>=1.70.0,<2.0.0
apache-flink==2.1.0
apache-flink-libraries==2.1.0
```

---

### 2. uv 실행 파일 경로 문제

#### 이슈
Docker 빌드 시 다음 에러 발생:
```
=> ERROR [8/8] RUN /opt/flink/venv/bin/uv pip install -r requirements.txt
```

#### 추론 가설
- `uv venv` 명령으로 가상환경 생성 시, venv 내부에 uv가 자동으로 설치되지 않음
- 시스템에 설치된 uv를 사용해야 함

#### 시도 1: 시스템 uv 사용
```dockerfile
RUN uv pip install --python /opt/flink/venv/bin/python -r requirements.txt
```

**결과**: 여전히 실패 (PATH 문제)

#### 시도 2: 절대 경로 지정
```dockerfile
RUN /usr/local/bin/uv pip install --python /opt/flink/venv/bin/python -r requirements.txt
```

**결과**: 성공 (다음 단계로 진행)

---

### 3. PyFlink 버전 불일치

#### 이슈
Docker 빌드 실패:
```
apache-flink==1.20.2  # requirements.txt
```
vs
```
FROM flink:2.1.0-scala_2.12-java21  # Dockerfile
```

#### 해결
requirements.txt의 PyFlink 버전을 Flink 이미지 버전과 일치시킴:

```text
apache-flink==2.1.0
apache-flink-libraries==2.1.0
```

---

### 4. pemja 빌드 실패 - JDK 헤더 파일 누락

#### 이슈
빌드 로그:
```
#12 20.11   × Failed to build `pemja==0.5.3`
#12 20.11       [stderr]
#12 20.11       Include folder should be at '/opt/java/openjdk/include' but doesn't
#12 20.11       exist. Please check you've installed the JDK properly.
```

#### 추론 가설
- Flink 이미지에는 JRE만 포함되어 있고 JDK가 없음
- pemja는 Python-Java 브리지로 네이티브 확장을 빌드하기 위해 JDK 헤더 파일(`jni.h` 등)이 필요

#### 해결
openjdk-21-jdk 패키지 설치:

```dockerfile
RUN apt-get update && \
    apt-get install -y python3-pip build-essential openjdk-21-jdk && \
    rm -rf /var/lib/apt/lists/*
```

---

### 5. JAVA_HOME 경로 문제

#### 이슈
JDK 설치 후에도 빌드 실패:
```
#12 16.22       [stderr]
#12 16.22       Path /usr/lib/jvm/java-21-openjdk-amd64 indicated by JAVA_HOME does
#12 16.22       not exist.
```

#### 추론 가설
- 아키텍처에 따라 JDK 경로가 다름 (amd64, arm64 등)
- 정적으로 경로를 지정하면 특정 아키텍처에서만 동작

#### 시도 과정

**시도 1**: 정적 경로
```dockerfile
ENV JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
```
**결과**: 실패 (경로가 존재하지 않음)

**시도 2**: 동적 경로 탐색 + 심볼릭 링크
```dockerfile
RUN JAVA_DIR=$(ls -d /usr/lib/jvm/java-21-openjdk-* 2>/dev/null | head -n 1) && \
    ln -sf $JAVA_DIR /usr/lib/jvm/default-java

ENV JAVA_HOME=/usr/lib/jvm/default-java
```
**결과**: 성공

#### 확인 방법
```bash
# 컨테이너 내부에서 JAVA_HOME 확인
docker run --rm <image_id> ls -la $JAVA_HOME
```

---

### 6. Multi-Stage Build로 전환

#### 목적
- 빌드 도구(JDK, build-essential)가 최종 이미지에 포함되지 않도록 함
- 이미지 크기 최적화 및 보안 향상

#### 구조

**Stage 1: Builder**
- JDK와 빌드 도구 설치
- uv를 사용하여 Python 패키지 빌드
- pemja 등 네이티브 확장 컴파일
- 완성된 venv 생성

**Stage 2: Final**
- 깨끗한 Flink 이미지로 시작
- builder에서 빌드된 venv만 복사
- JDK와 빌드 도구는 포함되지 않음

#### Dockerfile 구조
```dockerfile
# ========== STAGE 1: Builder ==========
FROM flink:2.1.0-scala_2.12-java21 AS builder

USER root
RUN apt-get update && \
    apt-get install -y openjdk-21-jdk build-essential python3-pip && \
    rm -rf /var/lib/apt/lists/*

# JAVA_HOME 설정
RUN JAVA_DIR=$(ls -d /usr/lib/jvm/java-21-openjdk-* 2>/dev/null | head -n 1) && \
    ln -sf $JAVA_DIR /usr/lib/jvm/default-java
ENV JAVA_HOME=/usr/lib/jvm/default-java

# uv 설치 및 패키지 빌드
RUN pip3 install uv
WORKDIR /opt/flink
RUN uv venv /opt/flink/venv && \
    chown -R flink:flink /opt/flink/venv

USER flink
COPY --chown=flink:flink requirements.txt .
RUN /usr/local/bin/uv pip install --python /opt/flink/venv/bin/python -r requirements.txt

# ========== STAGE 2: Final ==========
FROM flink:2.1.0-scala_2.12-java21

USER root
RUN echo "python.execution.environment.path: /opt/flink/venv" >> /opt/flink/conf/flink-conf.yaml

USER flink
WORKDIR /opt/flink

# 빌드된 venv만 복사
COPY --from=builder --chown=flink:flink /opt/flink/venv /opt/flink/venv

ENV PATH="/opt/flink/venv/bin:$PATH"
```

---

### 7. 빌드 테스트 및 이미지 삭제

#### 이미지 확인
```bash
$ docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.CreatedAt}}\t{{.Size}}"

REPOSITORY    TAG      IMAGE ID       CREATED AT                      SIZE
<none>        <none>   67e25e8c52b8   2025-11-03 14:38:40 +0900 KST   3.7GB
```

#### 이미지 삭제
```bash
$ docker rmi 67e25e8c52b8
Deleted: sha256:67e25e8c52b870544254c587ec07b288627253a55c62c6ae306bd80a34e15e85
```

---

### 8. Final Stage Python 런타임 누락 문제

#### 이슈
컨테이너 실행 시 Python을 찾을 수 없음:
```bash
$ docker run --rm a3531a7cc4cc /opt/flink/venv/bin/python
/docker-entrypoint.sh: line 190: /opt/flink/venv/bin/python: No such file or directory
```

#### 디버깅 과정

**Step 1**: venv/bin 디렉토리 확인
```bash
$ docker run --rm a3531a7cc4cc ls -la /opt/flink/venv/bin/

lrwxrwxrwx 1 flink flink   16 Nov  3 05:48 python -> /usr/bin/python3
lrwxrwxrwx 1 flink flink    6 Nov  3 05:48 python3 -> python
lrwxrwxrwx 1 flink flink    6 Nov  3 05:48 python3.10 -> python
```

**발견**: python이 심볼릭 링크로 `/usr/bin/python3`를 가리킴

**Step 2**: Python3 존재 여부 확인
```bash
$ docker run --rm a3531a7cc4cc which python3
# (출력 없음 - exit code 1)
```

**발견**: Final stage에 Python3가 설치되어 있지 않음

#### 추론 가설
- `uv venv`는 `--copies` 옵션 없이 심볼릭 링크 방식으로 venv 생성
- Builder stage에 있던 Python3가 final stage에는 없음
- venv만 복사해서는 실행 불가

#### 해결
Final stage에 Python3 런타임 설치:

```dockerfile
# STAGE 2: Final Image
FROM flink:2.1.0-scala_2.12-java21

USER root

# Python3 런타임 설치 (venv 실행에 필요, JDK와 빌드 도구는 불필요)
RUN apt-get update && \
    apt-get install -y python3 python3-distutils && \
    rm -rf /var/lib/apt/lists/*

# ... rest of the Dockerfile
```

#### 검증 방법
```bash
# 빌드 후 Python 실행 확인
$ docker run --rm <new_image_id> /opt/flink/venv/bin/python --version
Python 3.10.x

# PyFlink 임포트 테스트
$ docker run --rm <new_image_id> /opt/flink/venv/bin/python -c "import pyflink; print(pyflink.__version__)"
```

---

## 기술 개념 정리

### 1. uv (Python Package Installer)

**개념**:
- Rust로 작성된 초고속 Python 패키지 설치 도구
- pip의 대안으로, 10-100배 빠른 설치 속도
- 기본적으로 캐시를 사용하지 않음 (`--no-cache-dir` 기본값)

**주요 명령어**:
```bash
# 가상환경 생성
uv venv /path/to/venv

# 특정 Python으로 패키지 설치
uv pip install --python /path/to/python -r requirements.txt

# venv 내부의 pip 사용 (만약 venv에 uv가 있다면)
/path/to/venv/bin/uv pip install package
```

**주의사항**:
- `uv venv`로 생성한 가상환경에는 uv가 자동 설치되지 않음
- 시스템에 설치된 uv를 절대 경로로 사용하거나 `--python` 옵션 활용

---

### 2. pemja (Python Embedded in Java)

**개념**:
- Python과 Java 간 양방향 통신을 가능하게 하는 브리지 라이브러리
- PyFlink에서 Python UDF를 Java 프로세스에서 실행하기 위해 사용
- JNI (Java Native Interface) 기반으로 구현

**빌드 요구사항**:
1. **JDK** (JRE가 아님):
   - `jni.h`, `jni_md.h` 등의 헤더 파일 필요
   - 위치: `$JAVA_HOME/include/`

2. **C/C++ 컴파일러**:
   - gcc, g++ 등
   - Debian/Ubuntu: `build-essential` 패키지

3. **JAVA_HOME 환경 변수**:
   - pemja setup.py가 JDK 경로를 찾기 위해 참조

**일반적인 빌드 에러**:
```
Include folder should be at '/opt/java/openjdk/include' but doesn't exist.
```
→ JDK가 설치되지 않았거나 JAVA_HOME이 잘못 설정됨

---

### 3. Docker Multi-Stage Build

**개념**:
- 하나의 Dockerfile에서 여러 FROM 문을 사용하여 단계별로 이미지 빌드
- 이전 단계(stage)의 산출물만 선택적으로 복사 가능
- 빌드 도구와 런타임 환경을 분리하여 최종 이미지 경량화

**장점**:
1. **이미지 크기 감소**: 빌드 도구가 최종 이미지에 포함되지 않음
2. **보안 강화**: 불필요한 개발 도구 제거로 공격 표면 축소
3. **레이어 최적화**: 필요한 파일만 복사하여 레이어 수 감소

**구조**:
```dockerfile
# Stage 1: 빌드 환경
FROM base-image AS builder
RUN install build-tools
RUN compile application
# 많은 빌드 도구와 임시 파일 생성

# Stage 2: 런타임 환경
FROM base-image
COPY --from=builder /output/artifact /app/
# 빌드 산출물만 복사, 빌드 도구는 포함 안 됨
```

**COPY --from 문법**:
```dockerfile
COPY --from=<stage_name> <src_path> <dest_path>
COPY --from=builder /opt/flink/venv /opt/flink/venv
```

---

### 4. Python Virtual Environment (venv)

**가상환경 생성 방식**:

**1. 심볼릭 링크 방식 (기본값)**:
```bash
python3 -m venv /path/to/venv
uv venv /path/to/venv
```

구조:
```
venv/
├── bin/
│   ├── python -> /usr/bin/python3  # 심볼릭 링크
│   └── python3 -> python
└── lib/
    └── python3.x/site-packages/
```

**특징**:
- 디스크 공간 절약
- 시스템 Python에 의존
- **Multi-stage build에서 문제 발생 가능**

**2. 복사 방식**:
```bash
python3 -m venv --copies /path/to/venv
uv venv --copies /path/to/venv
```

구조:
```
venv/
├── bin/
│   ├── python  # 실제 바이너리 복사본
│   └── python3 -> python
```

**특징**:
- 독립적인 Python 실행 파일
- 시스템 Python 없이도 실행 가능
- **Multi-stage build에 적합**

---

### 5. JAVA_HOME 설정 방법

**동적 경로 탐색**:

아키텍처별 JDK 경로 차이:
- x86_64 (amd64): `/usr/lib/jvm/java-21-openjdk-amd64`
- aarch64 (arm64): `/usr/lib/jvm/java-21-openjdk-arm64`

**해결 방법 1**: 와일드카드 패턴
```dockerfile
RUN JAVA_DIR=$(ls -d /usr/lib/jvm/java-21-openjdk-* 2>/dev/null | head -n 1) && \
    ln -sf $JAVA_DIR /usr/lib/jvm/default-java

ENV JAVA_HOME=/usr/lib/jvm/default-java
```

**해결 방법 2**: update-alternatives 사용
```dockerfile
RUN JAVA_PATH=$(update-alternatives --query java | grep Value | awk '{print $2}') && \
    export JAVA_HOME=$(dirname $(dirname $JAVA_PATH))

# Java 경로 예시:
# Value: /usr/lib/jvm/java-21-openjdk-amd64/bin/java
# JAVA_HOME: /usr/lib/jvm/java-21-openjdk-amd64
```

**해결 방법 3**: dpkg 사용
```dockerfile
ENV JAVA_HOME=/usr/lib/jvm/java-21-openjdk-$(dpkg --print-architecture)
```

---

### 6. Flink Python 실행 환경 설정

**flink-conf.yaml 설정**:
```yaml
python.execution.environment.path: /opt/flink/venv
```

**의미**:
- Flink가 Python UDF 실행 시 사용할 가상환경 경로 지정
- 설정하지 않으면 시스템 Python 사용
- PyFlink 작업 실행 시 자동으로 해당 venv 활성화

**설정 방법** (Dockerfile):
```dockerfile
RUN echo "python.execution.environment.path: /opt/flink/venv" >> \
    /opt/flink/conf/flink-conf.yaml
```

---

### 7. Docker 이미지 크기 최적화 기법

**1. apt-get 캐시 정리**:
```dockerfile
RUN apt-get update && \
    apt-get install -y package1 package2 && \
    rm -rf /var/lib/apt/lists/*  # 캐시 삭제
```

**2. 단일 RUN 명령으로 레이어 통합**:
```dockerfile
# Bad - 여러 레이어 생성
RUN apt-get update
RUN apt-get install -y package1
RUN rm -rf /var/lib/apt/lists/*

# Good - 하나의 레이어
RUN apt-get update && \
    apt-get install -y package1 && \
    rm -rf /var/lib/apt/lists/*
```

**3. Multi-stage build**:
- 빌드 도구는 builder stage에만 설치
- 최종 이미지는 런타임만 포함

**4. 최소한의 런타임 패키지**:
```dockerfile
# JDK 전체 대신 JRE만 설치 (가능한 경우)
# python3-dev 대신 python3만 설치 (빌드 불필요 시)
```

**효과 예시**:
- Single-stage (JDK 포함): ~4-5GB
- Multi-stage (런타임만): ~2-3GB
- 약 40-50% 크기 감소

---

## 결론

### 최종 솔루션 요약

1. **Multi-stage build** 도입으로 이미지 크기 최적화
2. **Builder stage**에서 JDK와 빌드 도구로 pemja 컴파일
3. **Final stage**에서 Python3 런타임과 빌드된 venv만 포함
4. **uv**를 활용한 빠른 패키지 설치
5. **동적 JAVA_HOME 설정**으로 다양한 아키텍처 지원

### 주의사항

- venv는 심볼릭 링크 방식으로 생성되므로, final stage에도 Python3 필요
- PyFlink 버전과 Flink 이미지 버전은 반드시 일치시켜야 함
- pemja 빌드를 위해 JDK (JRE 아님) 필수

### 향후 개선 가능 사항

1. `uv venv --copies` 옵션 사용으로 Python 런타임 의존성 제거
2. Python3 패키지 최소화 (필요한 모듈만 설치)
3. 빌드 캐시 최적화 (requirements.txt 변경 시만 재빌드)
4. Health check 추가
5. 보안 스캔 및 취약점 점검



# 기술 개념 정리 - Docker, Python, Flink 통합 환경

**작성일**: 2025-11-03  
**관련 작업**: Flink Docker Multi-Stage Build & PyFlink 환경 구성

---

## 목차

1. [uv - 차세대 Python 패키지 매니저](#1-uv---차세대-python-패키지-매니저)
2. [pemja - Python-Java 브리지](#2-pemja---python-java-브리지)
3. [Docker Multi-Stage Build](#3-docker-multi-stage-build)
4. [Python Virtual Environment 심화](#4-python-virtual-environment-심화)
5. [JAVA_HOME과 JDK/JRE 차이](#5-java_home과-jdkjre-차이)
6. [PyFlink 아키텍처](#6-pyflink-아키텍처)
7. [Docker 이미지 최적화 전략](#7-docker-이미지-최적화-전략)

---

## 1. uv - 차세대 Python 패키지 매니저

### 개요

**uv**는 Rust로 작성된 Python 패키지 설치 및 관리 도구로, Astral에서 개발했습니다.

### 주요 특징

| 특징 | pip | uv |
|------|-----|-----|
| 언어 | Python | Rust |
| 속도 | 기준 | 10-100배 빠름 |
| 캐시 기본값 | 사용 | 미사용 (최적화됨) |
| 의존성 해결 | 순차적 | 병렬 처리 |
| 메모리 사용 | 높음 | 낮음 |

### 설치

```bash
# pip를 통한 설치
pip install uv

# curl을 통한 설치 (권장)
curl -LsSf https://astral.sh/uv/install.sh | sh

# 설치 확인
uv --version
```

### 주요 명령어

#### 1. 가상환경 생성

```bash
# 기본 (심볼릭 링크 방식)
uv venv /path/to/venv

# 복사 방식 (multi-stage build에 적합)
uv venv --copies /path/to/venv

# 특정 Python 버전 사용
uv venv --python 3.11 /path/to/venv
```

#### 2. 패키지 설치

```bash
# requirements.txt에서 설치
uv pip install -r requirements.txt

# 특정 Python 인터프리터 지정
uv pip install --python /path/to/python -r requirements.txt

# 단일 패키지 설치
uv pip install numpy pandas
```

#### 3. 패키지 관리

```bash
# 패키지 목록
uv pip list

# 패키지 삭제
uv pip uninstall package-name

# 패키지 동결 (현재 설치된 버전)
uv pip freeze > requirements.txt
```

### Dockerfile에서 uv 사용

```dockerfile
# uv 설치
RUN pip3 install uv

# venv 생성
RUN uv venv /opt/app/venv

# 패키지 설치
COPY requirements.txt .
RUN uv pip install --python /opt/app/venv/bin/python -r requirements.txt

# 또는 시스템 uv를 절대 경로로 사용
RUN /usr/local/bin/uv pip install --python /opt/app/venv/bin/python -r requirements.txt
```

### 주의사항

1. **venv 내부에 uv 미포함**:
   - `uv venv`로 생성한 가상환경에는 uv가 설치되지 않음
   - 시스템 uv를 사용하거나 `--python` 옵션 활용

2. **PATH 설정**:
   - uv가 PATH에 없으면 절대 경로 사용: `/usr/local/bin/uv`

3. **호환성**:
   - pip와 완전히 호환되지만, 일부 edge case에서 차이 있을 수 있음

---

## 2. pemja - Python-Java 브리지

### 개요

**pemja**(Python Embedded in Java)는 Python과 Java를 양방향으로 연결하는 브리지 라이브러리입니다.

### 아키텍처

```
┌─────────────┐
│   Java      │
│  Process    │
│             │
│  ┌────────┐ │
│  │  JNI   │ │  ← C/C++ Native Interface
│  └────────┘ │
└──────┬──────┘
       │
       ↓
┌──────────────┐
│   pemja      │  ← Native Extension (C/C++)
│  (CPython)   │
└──────────────┘
       │
       ↓
┌──────────────┐
│   Python     │
│ Interpreter  │
└──────────────┘
```

### PyFlink에서의 역할

1. **Python UDF 실행**:
   - Java로 작성된 Flink에서 Python 함수 호출
   - TaskManager JVM 프로세스 내에서 CPython 인터프리터 실행

2. **데이터 교환**:
   - Java 객체 ↔ Python 객체 변환
   - Arrow 포맷을 통한 효율적인 데이터 전송

3. **성능 최적화**:
   - 프로세스 간 통신 없이 in-memory 데이터 교환
   - 직렬화/역직렬화 오버헤드 최소화

### 빌드 요구사항

#### 1. JDK (Java Development Kit)

**필요한 이유**:
- JNI (Java Native Interface) 헤더 파일 필요
- `jni.h`, `jni_md.h` 등

**설치**:
```bash
# Ubuntu/Debian
apt-get install openjdk-11-jdk

# 확인
ls $JAVA_HOME/include/
# 출력: jni.h  jni_md.h  linux/
```

**JRE만으로는 불충분**:
```
JRE (Java Runtime Environment):
├── bin/java          ✓ 실행만 가능
└── lib/              ✓ 런타임 라이브러리

JDK (Java Development Kit):
├── bin/java          ✓
├── bin/javac         ✓ 컴파일러
├── include/          ✓ JNI 헤더 파일 (pemja 빌드에 필수)
│   ├── jni.h
│   └── jni_md.h
└── lib/              ✓
```

#### 2. C/C++ 컴파일러

```bash
# Ubuntu/Debian
apt-get install build-essential

# 포함 내용:
# - gcc (C 컴파일러)
# - g++ (C++ 컴파일러)
# - make (빌드 도구)
# - libc-dev (C 라이브러리 개발 파일)
```

#### 3. JAVA_HOME 환경 변수

**설정 방법**:
```dockerfile
# 정적 경로 (특정 아키텍처)
ENV JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64

# 동적 경로 (아키텍처 독립적)
RUN JAVA_DIR=$(ls -d /usr/lib/jvm/java-11-openjdk-* | head -n 1) && \
    ln -sf $JAVA_DIR /usr/lib/jvm/default-java
ENV JAVA_HOME=/usr/lib/jvm/default-java
```

### 일반적인 빌드 에러와 해결

#### 에러 1: JDK 헤더 파일 누락

```
Include folder should be at '/opt/java/openjdk/include' but doesn't exist.
Please check you've installed the JDK properly.
```

**원인**: JRE만 설치되었거나 JDK가 없음

**해결**:
```dockerfile
RUN apt-get install -y openjdk-11-jdk  # JRE 아님!
```

#### 에러 2: JAVA_HOME 미설정 또는 잘못된 경로

```
JAVA_HOME is not set or points to invalid directory
```

**해결**:
```bash
# 올바른 경로 확인
update-alternatives --config java

# 환경 변수 설정
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
```

#### 에러 3: 빌드 도구 누락

```
error: command 'gcc' failed: No such file or directory
```

**해결**:
```bash
apt-get install build-essential
```

### pemja 설치 확인

```python
# Python에서 확인
import pemja
print(pemja.__version__)

# PyFlink에서 암묵적으로 사용됨
from pyflink.datastream import StreamExecutionEnvironment
env = StreamExecutionEnvironment.get_execution_environment()
```

---

## 3. Docker Multi-Stage Build

### 개념

하나의 Dockerfile에서 여러 개의 `FROM` 문을 사용하여 단계적으로 이미지를 빌드하고, 이전 단계의 산출물만 선택적으로 복사하는 기법입니다.

### 기본 구조

```dockerfile
# ========== Stage 1: Builder ==========
FROM base-image:latest AS builder

# 빌드 도구 설치
RUN install-build-tools

# 소스 코드 복사 및 컴파일
COPY . /app
WORKDIR /app
RUN build-application

# ========== Stage 2: Runtime ==========
FROM base-image:latest

# 빌드된 산출물만 복사
COPY --from=builder /app/output /app

# 빌드 도구는 포함되지 않음!
CMD ["/app/binary"]
```

### 장점

#### 1. 이미지 크기 감소

**Single-stage 예시**:
```dockerfile
FROM ubuntu:22.04
RUN apt-get update && apt-get install -y \
    gcc g++ make cmake \
    python3-dev \
    openjdk-11-jdk  # ~500MB

# 빌드 후 모든 도구가 이미지에 남음
# 최종 이미지: ~2GB
```

**Multi-stage 예시**:
```dockerfile
# Builder
FROM ubuntu:22.04 AS builder
RUN apt-get update && apt-get install -y \
    gcc g++ make cmake python3-dev openjdk-11-jdk
RUN build-app

# Runtime
FROM ubuntu:22.04
RUN apt-get update && apt-get install -y python3  # ~50MB
COPY --from=builder /app/output /app

# 최종 이미지: ~500MB (75% 감소!)
```

#### 2. 보안 강화

- 빌드 도구와 소스 코드가 프로덕션 이미지에 포함되지 않음
- 공격 표면 (attack surface) 감소
- 취약점 스캔 대상 감소

#### 3. 레이어 최적화

- 불필요한 중간 레이어 제거
- 최종 이미지의 레이어 수 감소

### 고급 패턴

#### 1. 여러 빌더 스테이지

```dockerfile
# Backend builder
FROM golang:1.21 AS backend-builder
WORKDIR /app
COPY backend/ .
RUN go build -o server

# Frontend builder
FROM node:20 AS frontend-builder
WORKDIR /app
COPY frontend/ .
RUN npm install && npm run build

# Final image
FROM alpine:3.18
COPY --from=backend-builder /app/server /app/
COPY --from=frontend-builder /app/dist /app/static/
CMD ["/app/server"]
```

#### 2. 외부 이미지에서 복사

```dockerfile
# 다른 이미지에서 바이너리 복사
FROM alpine:3.18
COPY --from=nginx:alpine /usr/sbin/nginx /usr/sbin/
COPY --from=redis:alpine /usr/local/bin/redis-server /usr/bin/
```

#### 3. 빌드 캐시 최적화

```dockerfile
FROM python:3.11 AS builder

# 의존성 파일만 먼저 복사 (변경 빈도 낮음)
COPY requirements.txt .
RUN pip install -r requirements.txt  # ← 캐시됨

# 소스 코드 복사 (변경 빈도 높음)
COPY . /app  # ← 자주 변경되어도 위 레이어는 캐시 유지
```

### PyFlink 빌드 예시

```dockerfile
# ========== Builder: JDK + Build Tools ==========
FROM flink:2.1.0 AS builder

USER root

# JDK와 빌드 도구 설치 (약 1GB)
RUN apt-get update && \
    apt-get install -y \
        openjdk-21-jdk \
        build-essential \
        python3-pip && \
    rm -rf /var/lib/apt/lists/*

# JAVA_HOME 설정
ENV JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64

# uv 설치 및 Python 패키지 빌드
RUN pip3 install uv
WORKDIR /opt/flink
RUN uv venv /opt/flink/venv

USER flink
COPY requirements.txt .
RUN uv pip install --python /opt/flink/venv/bin/python -r requirements.txt

# ========== Runtime: 깨끗한 Flink + venv ==========
FROM flink:2.1.0

USER root

# Python 런타임만 설치 (약 50MB)
# JDK와 빌드 도구는 설치 안 함!
RUN apt-get update && \
    apt-get install -y python3 python3-distutils && \
    rm -rf /var/lib/apt/lists/*

# Flink 설정
RUN echo "python.execution.environment.path: /opt/flink/venv" >> \
    /opt/flink/conf/flink-conf.yaml

USER flink
WORKDIR /opt/flink

# 빌드된 venv만 복사 (펴mjа 포함)
COPY --from=builder --chown=flink:flink /opt/flink/venv /opt/flink/venv

ENV PATH="/opt/flink/venv/bin:$PATH"

# 최종 이미지:
# - Builder의 JDK와 빌드 도구: 제외
# - 컴파일된 pemja: 포함
# - Python 런타임: 포함
# - 크기: 약 2-3GB (single-stage 대비 40-50% 감소)
```

### 빌드 명령어

```bash
# 빌드 (자동으로 모든 stage 실행)
docker build -t my-flink:latest .

# 특정 stage만 빌드 (디버깅용)
docker build --target builder -t my-flink:builder .

# 빌드 아규먼트 전달
docker build --build-arg PYTHON_VERSION=3.11 -t my-flink:latest .
```

---

## 4. Python Virtual Environment 심화

### 가상환경 생성 방식

Python 가상환경은 두 가지 방식으로 생성할 수 있습니다.

#### 1. 심볼릭 링크 방식 (기본값)

**명령어**:
```bash
python3 -m venv /path/to/venv
uv venv /path/to/venv
```

**구조**:
```
venv/
├── bin/
│   ├── python -> /usr/bin/python3  # 심볼릭 링크
│   ├── python3 -> python            # 심볼릭 링크
│   ├── pip                          # 실제 스크립트
│   └── activate                     # 활성화 스크립트
├── lib/
│   └── python3.10/
│       └── site-packages/           # 설치된 패키지
└── pyvenv.cfg                       # 설정 파일
```

**특징**:
- ✓ 디스크 공간 절약 (Python 바이너리 미복사)
- ✓ 시스템 Python 업데이트 시 자동 반영
- ✗ 시스템 Python 삭제 시 venv 작동 불가
- ✗ **Multi-stage build에서 문제 발생**

**Multi-stage build 문제**:
```dockerfile
# Stage 1: Builder
FROM python:3.11 AS builder
RUN python -m venv /app/venv  # 심볼릭 링크 생성
RUN /app/venv/bin/pip install requests

# Stage 2: Runtime
FROM alpine:3.18
COPY --from=builder /app/venv /app/venv

# 문제: /app/venv/bin/python -> /usr/bin/python3
# Alpine에는 Python이 없음!
RUN /app/venv/bin/python --version  # ← 에러!
```

#### 2. 복사 방식

**명령어**:
```bash
python3 -m venv --copies /path/to/venv
uv venv --copies /path/to/venv
```

**구조**:
```
venv/
├── bin/
│   ├── python        # 실제 Python 바이너리 복사본
│   ├── python3 -> python
│   ├── pip
│   └── activate
├── lib/
│   └── python3.10/
│       └── site-packages/
└── pyvenv.cfg
```

**특징**:
- ✓ 독립적인 Python 실행 파일
- ✓ 시스템 Python 없이도 실행 가능
- ✓ **Multi-stage build에 적합**
- ✗ 디스크 공간 추가 소요 (~50-100MB)

**Multi-stage build 해결**:
```dockerfile
# Stage 1: Builder
FROM python:3.11 AS builder
RUN python -m venv --copies /app/venv  # 복사 방식
RUN /app/venv/bin/pip install requests

# Stage 2: Runtime
FROM alpine:3.18
# Python 설치 불필요!
COPY --from=builder /app/venv /app/venv

# 정상 작동
RUN /app/venv/bin/python --version  # ✓
```

### 가상환경 비교

| 특성 | 심볼릭 링크 | 복사 방식 | 시스템 Python |
|------|------------|-----------|---------------|
| 디스크 사용 | 최소 | 중간 | 공유 |
| 독립성 | 낮음 | 높음 | 없음 |
| 이식성 | 낮음 | 높음 | 중간 |
| Multi-stage | ✗ | ✓ | ✗ |
| 권장 용도 | 로컬 개발 | 컨테이너 | 단순 스크립트 |

### PyFlink 환경 설정

#### 방법 1: 심볼릭 링크 + Python 런타임 설치 (현재 구현)

```dockerfile
# Builder
FROM flink:2.1.0 AS builder
RUN uv venv /opt/flink/venv  # 심볼릭 링크
RUN uv pip install --python /opt/flink/venv/bin/python -r requirements.txt

# Runtime
FROM flink:2.1.0
RUN apt-get install -y python3  # Python 런타임 필요!
COPY --from=builder /opt/flink/venv /opt/flink/venv
```

**장점**:
- 디스크 공간 절약

**단점**:
- Final stage에 Python 설치 필요
- Python 버전 불일치 가능성

#### 방법 2: 복사 방식 (개선안)

```dockerfile
# Builder
FROM flink:2.1.0 AS builder
RUN uv venv --copies /opt/flink/venv  # 복사 방식
RUN uv pip install --python /opt/flink/venv/bin/python -r requirements.txt

# Runtime
FROM flink:2.1.0
# Python 설치 불필요!
COPY --from=builder /opt/flink/venv /opt/flink/venv
```

**장점**:
- Final stage에 Python 불필요
- 완전한 독립성
- 버전 불일치 없음

**단점**:
- 이미지 크기 약간 증가 (~50-100MB)

---

## 5. JAVA_HOME과 JDK/JRE 차이

### JDK vs JRE

#### JRE (Java Runtime Environment)

**포함 내용**:
```
jre/
├── bin/
│   └── java           # Java 실행 파일
├── lib/
│   ├── rt.jar         # 런타임 라이브러리
│   └── jce.jar
└── ...
```

**용도**: Java 애플리케이션 실행만 가능

#### JDK (Java Development Kit)

**포함 내용**:
```
jdk/
├── bin/
│   ├── java           # 실행 파일
│   ├── javac          # 컴파일러
│   └── jar            # JAR 도구
├── include/           # ★ JNI 헤더 파일 (pemja 빌드에 필수)
│   ├── jni.h
│   ├── jni_md.h
│   └── linux/
│       └── jni_md.h
├── lib/
│   └── tools.jar
└── jre/               # JRE 포함
    └── ...
```

**용도**: Java 애플리케이션 개발 및 실행

### JAVA_HOME 환경 변수

**정의**: JDK 또는 JRE 설치 경로를 가리키는 환경 변수

**필요한 이유**:
1. Java 도구들이 JDK 경로를 찾기 위해 사용
2. 빌드 도구(Maven, Gradle)가 참조
3. 네이티브 확장(pemja 등)이 JNI 헤더 파일 경로를 찾기 위해 사용

### 아키텍처별 경로 차이

| 아키텍처 | Debian/Ubuntu 경로 |
|----------|-------------------|
| x86_64 (amd64) | `/usr/lib/jvm/java-11-openjdk-amd64` |
| aarch64 (arm64) | `/usr/lib/jvm/java-11-openjdk-arm64` |
| ppc64el | `/usr/lib/jvm/java-11-openjdk-ppc64el` |

### 동적 JAVA_HOME 설정 방법

#### 방법 1: 와일드카드 패턴 (권장)

```dockerfile
RUN JAVA_DIR=$(ls -d /usr/lib/jvm/java-11-openjdk-* 2>/dev/null | head -n 1) && \
    ln -sf $JAVA_DIR /usr/lib/jvm/default-java

ENV JAVA_HOME=/usr/lib/jvm/default-java
```

**장점**:
- 모든 아키텍처에서 작동
- 간단한 구현

#### 방법 2: update-alternatives

```dockerfile
RUN JAVA_PATH=$(update-alternatives --query java | grep Value | awk '{print $2}') && \
    export JAVA_HOME=$(dirname $(dirname $JAVA_PATH))

# 예시 경로:
# JAVA_PATH=/usr/lib/jvm/java-11-openjdk-amd64/bin/java
# JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
```

**장점**:
- 시스템 기본 Java 사용
- 여러 JDK 버전 관리 용이

#### 방법 3: dpkg 사용

```dockerfile
ENV JAVA_HOME=/usr/lib/jvm/java-11-openjdk-$(dpkg --print-architecture)
```

**단점**:
- Dockerfile의 ENV에서 셸 명령 실행 불가
- 정적 경로와 유사한 문제

### JAVA_HOME 검증

```bash
# 1. 환경 변수 확인
echo $JAVA_HOME

# 2. Java 실행 파일 확인
$JAVA_HOME/bin/java -version

# 3. JNI 헤더 파일 확인 (pemja 빌드에 필수)
ls $JAVA_HOME/include/jni.h

# 4. Dockerfile에서 검증
RUN test -f $JAVA_HOME/include/jni.h || (echo "JNI headers not found" && exit 1)
```

---

## 6. PyFlink 아키텍처

### 전체 아키텍처

```
┌──────────────────────────────────────────┐
│         Flink Cluster (Java)             │
│                                          │
│  ┌────────────┐      ┌────────────┐    │
│  │ JobManager │      │ TaskManager│    │
│  │   (JVM)    │      │   (JVM)    │    │
│  └────────────┘      └─────┬──────┘    │
│                             │           │
│                             ↓           │
│                      ┌─────────────┐   │
│                      │   pemja     │   │  ← Python-Java 브리지
│                      │   (JNI)     │   │
│                      └──────┬──────┘   │
│                             │           │
└─────────────────────────────┼───────────┘
                              │
                              ↓
                     ┌────────────────┐
                     │    CPython     │     ← Python 인터프리터
                     │  Interpreter   │
                     └────────────────┘
                              │
                              ↓
                     ┌────────────────┐
                     │  Python UDF    │     ← 사용자 Python 코드
                     │  (user code)   │
                     └────────────────┘
```

### 데이터 흐름

```python
# Python UDF 정의
from pyflink.datastream import StreamExecutionEnvironment
from pyflink.table import StreamTableEnvironment

env = StreamExecutionEnvironment.get_execution_environment()
t_env = StreamTableEnvironment.create(env)

# Python UDF 등록
@udf(result_type=DataTypes.STRING())
def upper_case(s):
    return s.upper()

t_env.create_temporary_function("upper", upper_case)
```

**실행 흐름**:
1. Python 코드가 Flink Java API 호출 (Py4J)
2. JobManager가 작업 배포
3. TaskManager에서 pemja 로딩
4. CPython 인터프리터 시작
5. Python UDF 실행
6. 결과를 Java로 반환 (pemja)

### 환경 설정

#### flink-conf.yaml

```yaml
# Python 가상환경 경로
python.execution.environment.path: /opt/flink/venv

# Python 인터프리터 경로 (선택사항)
python.client.executable: /opt/flink/venv/bin/python

# Python 워커 메모리
python.fn-execution.memory.managed: 512m

# Python 워커 프로세스 수
python.fn-execution.bundle.size: 100
```

#### Dockerfile 설정

```dockerfile
# Python 가상환경 경로 설정
RUN echo "python.execution.environment.path: /opt/flink/venv" >> \
    /opt/flink/conf/flink-conf.yaml

# PATH 설정
ENV PATH="/opt/flink/venv/bin:$PATH"
```

### 의존성 패키지

PyFlink 필수 패키지:

```text
apache-flink==2.1.0          # PyFlink 코어
apache-flink-libraries==2.1.0 # 추가 라이브러리
pemja==0.5.3                  # Python-Java 브리지 (의존성으로 자동 설치)
py4j==0.10.9.7                # Python-Java 게이트웨이
cloudpickle>=2.0.0            # 객체 직렬화
numpy>=1.21.0                 # 수치 연산
pandas>=1.3.0                 # 데이터 프레임
pyarrow>=5.0.0                # Arrow 포맷 (데이터 교환)
```

---

## 7. Docker 이미지 최적화 전략

### 레이어 캐시 활용

#### Before (비효율)

```dockerfile
FROM python:3.11

# 소스 코드 복사 (자주 변경됨)
COPY . /app

# 의존성 설치 (가끔 변경됨)
COPY requirements.txt /app/
RUN pip install -r /app/requirements.txt

# 소스 코드가 변경될 때마다 의존성 재설치!
```

#### After (효율)

```dockerfile
FROM python:3.11

# 의존성 파일만 먼저 복사 (변경 빈도 낮음)
COPY requirements.txt /app/
RUN pip install -r /app/requirements.txt  # ← 캐시됨

# 소스 코드 복사 (변경 빈도 높음)
COPY . /app  # ← 소스만 변경 시 위 레이어는 캐시 사용
```

### apt-get 캐시 정리

```dockerfile
# Bad - 캐시가 레이어에 남음
RUN apt-get update
RUN apt-get install -y package1 package2
# /var/lib/apt/lists/ 에 수백 MB 캐시

# Good - 같은 RUN에서 정리
RUN apt-get update && \
    apt-get install -y package1 package2 && \
    rm -rf /var/lib/apt/lists/*  # 캐시 삭제
```

### 불필요한 파일 제외

#### .dockerignore 파일

```
# .dockerignore
*.pyc
__pycache__/
*.pyo
*.pyd
.Python
*.so
*.egg
*.egg-info
dist/
build/
.git/
.gitignore
.vscode/
.idea/
*.log
*.md
tests/
docs/
.env
.env.local
node_modules/
```

### 멀티 스테이지 최적화

```dockerfile
# ========== Stage 1: Dependencies ==========
FROM python:3.11-slim AS deps
WORKDIR /app
COPY requirements.txt .
RUN pip install --user -r requirements.txt

# ========== Stage 2: Builder ==========
FROM python:3.11-slim AS builder
COPY --from=deps /root/.local /root/.local
COPY . /app
WORKDIR /app
RUN python -m compileall .

# ========== Stage 3: Runtime ==========
FROM python:3.11-slim
COPY --from=deps /root/.local /root/.local
COPY --from=builder /app /app
ENV PATH=/root/.local/bin:$PATH
WORKDIR /app
CMD ["python", "app.py"]
```

### 베이스 이미지 선택

| 이미지 | 크기 | 용도 |
|--------|------|------|
| `python:3.11` | ~900MB | 개발, 모든 도구 포함 |
| `python:3.11-slim` | ~120MB | 프로덕션, 최소 도구 |
| `python:3.11-alpine` | ~50MB | 최소 크기, 호환성 주의 |
| `distroless/python3` | ~50MB | 보안, 셸 없음 |

**Flink 이미지**:
- `flink:2.1.0`: ~800MB (JRE 포함)
- `flink:2.1.0-scala_2.12-java21`: ~850MB

### 이미지 크기 비교 (PyFlink 예시)

| 구성 | 크기 | 설명 |
|------|------|------|
| Single-stage (JDK) | ~4-5GB | JDK + 빌드 도구 포함 |
| Multi-stage (Python 런타임) | ~2-3GB | Python3 + 런타임만 |
| Multi-stage (--copies) | ~2.5-3.5GB | 독립 Python 복사본 |
| 최적화 후 | ~2GB | 불필요한 파일 제거 |

### 최적화 체크리스트

- [ ] Multi-stage build 사용
- [ ] 최소 베이스 이미지 선택
- [ ] .dockerignore 설정
- [ ] apt-get 캐시 정리
- [ ] 단일 RUN으로 레이어 통합
- [ ] 의존성 파일 먼저 복사 (캐시 활용)
- [ ] 불필요한 개발 도구 제외
- [ ] 압축 가능한 파일 압축
- [ ] 이미지 스캔 (보안 취약점)

---

## 참고 자료

### 공식 문서
