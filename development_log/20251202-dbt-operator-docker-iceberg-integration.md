# dbt-operator Docker 빌드 및 Iceberg 테이블 연동 문제 해결

**작업 일시:** 2025-12-02  
**작업자:** ed  
**목표:** dbt-operator Docker 이미지 빌드 및 MinIO Iceberg 테이블 읽기 성공

---

## 1. YAML 구문 오류 (profiles.yml)

### 이슈
```
Nested mappings are not allowed in compact mappings
  in "dbt/profiles.yml", line 34, column 13
```

**시작 시각:** 11:33

### 원인 분석
```yaml
dev_iceberg:
  type: duckdb
    path: ":memory:"  # 잘못된 들여쓰기 (8칸)
```

`path` 속성이 `type`보다 2칸 더 들여쓰기되어 중첩 매핑으로 인식됨

### 해결
```yaml
dev_iceberg:
  type: duckdb
  path: ":memory:"  # 올바른 들여쓰기 (6칸, type과 동일 레벨)
```

**검증 명령:**
```bash
python3 -c "import yaml; yaml.safe_load(open('dbt/profiles.yml'))" && echo "✓ YAML is valid"
```

**결과:** ✓ YAML 파싱 성공

---

## 2. Poetry 의존성 충돌

### 이슈
```
Because dbt-operator depends on dbt-core (1.10.15) which depends on Jinja2 (>=3.1.3,<4), 
jinja2 is required.
So, because dbt-operator depends on jinja2 (3.1.2), version solving failed.
```

**시작 시각:** 11:33

### 원인 분석
- `pyproject.toml`에 `jinja2 = "3.1.2"` 명시
- `dbt-core 1.10.15`는 `Jinja2 >=3.1.3` 요구
- 버전 충돌 발생

### 해결
```toml
# pyproject.toml
[tool.poetry.dependencies]
python = "^3.11"
dbt-core = "1.10.15"
dbt-duckdb = "1.10.0"
# jinja2 = "3.1.2"  # 제거 - dbt-core가 자동 관리
```

**실행 명령:**
```bash
poetry lock
docker build -t dbt-operator:test .
```

**결과:**
```
✓ Jinja2 3.1.6 자동 설치됨
✓ dbt-core 1.10.15 설치 성공
✓ dbt-duckdb 1.10.0 설치 성공
```

---

## 3. Docker 빌드 오류 - virtualenv 활성화

### 이슈
```
container_linux.go:380: starting container process caused: 
exec: "source": executable file not found in $PATH
```

**시작 시각:** 11:40

### 원인 분석
```dockerfile
RUN ["source", ".venv/bin/activate"]  # exec 형식에서 shell builtin 실행 불가
```

`source`는 shell의 내장 명령어로 exec 형식(`RUN ["command"]`)으로 실행 불가능

### 해결
```dockerfile
# Activate virtualenv by setting PATH
ENV PATH="/app/.venv/bin:$PATH"
```

환경 변수로 virtualenv를 PATH에 추가하여 자동 활성화

---

## 4. dbt 모델 파일 누락

### 이슈
```
11:33:46  Found 468 macros
11:33:46  The selection criterion 'staging.stg_raw_iceberg' does not match any enabled nodes
```

**시작 시각:** 11:33

### 원인 분석
```dockerfile
# COPY models/ models/  # 주석 처리되어 있음
```

Dockerfile에서 모델 디렉토리가 복사되지 않음

### 해결
```dockerfile
COPY models/ models/
COPY macros/ macros/
COPY tests/ tests/
COPY seeds/ seeds/
COPY snapshots/ snapshots/
```

**검증 명령:**
```bash
docker run --rm dbt-operator:test dbt ls --target dev_iceberg
```

**결과:**
```
✓ Found 1 model, 1 source, 843 macros
dbt_operator_project.staging.stg_raw_iceberg
source:dbt_operator_project.minio_data_lake.taxis
```

---

## 5. dbt 패키지 미설치

### 이슈
```
Compilation Error
dbt found 2 package(s) specified in packages.yml, but only 0 package(s) installed in dbt_packages.
Run "dbt deps" to install package dependencies.
```

**시작 시각:** 11:44

### 원인 분석
`packages.yml`에 정의된 패키지(dbt_utils, dbt_expectations)가 설치되지 않음

### 해결
```dockerfile
# Activate virtualenv by setting PATH (deps 실행 전에 위치)
ENV PATH="/app/.venv/bin:$PATH"

# Copy dbt project files
COPY dbt_project.yml .
COPY packages.yml packages.yml

# Create dbt profiles directory and copy profiles
RUN mkdir -p /root/.dbt
COPY profiles.yml /root/.dbt/profiles.yml

# Install dbt packages
RUN dbt deps --target dev_iceberg
```

**결과:**
```
✓ Installing dbt-labs/dbt_utils (1.1.1)
✓ Installing calogica/dbt_expectations (0.10.1)
✓ Installing calogica/dbt_date (0.10.1)
```

---

## 6. Source Meta 접근 오류

### 이슈
```
Compilation Error in model stg_raw_iceberg
'dbt.adapters.duckdb.relation.DuckDBRelation object' has no attribute 'meta'
```

**시작 시각:** 11:42

### 원인 분석
```sql
-- 잘못된 방법
{% set iceberg_path = source('minio_data_lake', 'taxis').meta.iceberg_location %}
```

`source()` 함수는 Relation 객체를 반환하며, `meta` 속성이 없음

### 해결
```sql
-- 올바른 방법: graph.sources를 통한 접근
{% set source_node = graph.sources.values() 
    | selectattr("source_name", "equalto", "minio_data_lake") 
    | selectattr("name", "equalto", "taxis") 
    | first %}
{% set iceberg_path = source_node.meta.iceberg_location %}
```

---

## 7. MinIO 연결 문제

### 이슈 (1차)
```
Runtime Error: Could not establish connection error for HTTP HEAD to 
'http://docker.host.internal:8181/warehouse/...'
```

**시작 시각:** 11:46

### 원인 분석
- 잘못된 호스트명: `host:8181` (유효하지 않은 호스트)
- 잘못된 포트: `8181` (실제 MinIO는 9000 포트)

**확인 명령:**
```bash
docker ps --filter "name=minio" --format "table {{.Names}}\t{{.Ports}}\t{{.Status}}"
```

**출력:**
```
NAMES    PORTS                              STATUS
minio    0.0.0.0:9000-9001->9000-9001/tcp   Up 49 minutes
```

### 해결
```yaml
# profiles.yml
settings:
  s3_endpoint: "host.docker.internal:9000"  # Mac/Windows용
  s3_access_key_id: "admin"
  s3_secret_access_key: "mypassword"
  s3_region: "ap-northeast-2"
  s3_use_ssl: false
  s3_url_style: "path"
```

**실행 명령:**
```bash
docker run --rm --add-host=host.docker.internal:host-gateway \
  dbt-operator:test dbt run --target dev_iceberg --select stg_raw_iceberg
```

### 이슈 (2차) - 파일 404
```
HTTP Error: Unable to connect to URL 
"http://host.docker.internal:9000/warehouse/nyc/taxis/metadata/v1.metadata.json": 
404 (Not Found)
```

**시작 시각:** 11:51

### 원인 분석
```yaml
# sources.yaml - 문제 있는 경로
meta:
  iceberg_location: "s3://warehouse/nyc/taxis/metadata/"
```

```sql
-- stg_raw_iceberg.sql - 하드코딩된 메타데이터 파일
{% set iceberg_path = source_node.meta.iceberg_location ~ 'v1.metadata.json' %}
```

하드코딩된 `v1.metadata.json`이 존재하지 않거나 버전이 다름

---

## 8. Iceberg 버전 추측 비활성화

### 이슈
```
Failed to read iceberg table. No version was provided and no version-hint could be found, 
globbing the filesystem to locate the latest version is disabled by default as this is 
considered unsafe and could result in reading uncommitted data. 
To enable this use 'SET unsafe_enable_version_guessing = true;'
```

**시작 시각:** 11:53

### 해결 (최종)

#### 1. 테이블 루트 경로 사용
```yaml
# sources.yaml
meta:
  iceberg_location: "s3://warehouse/nyc/taxis"  # 메타데이터 파일명 제거
```

#### 2. SQL 단순화
```sql
-- stg_raw_iceberg.sql
{% set source_node = graph.sources.values() 
    | selectattr("source_name", "equalto", "minio_data_lake") 
    | selectattr("name", "equalto", "taxis") 
    | first %}
{% set iceberg_path = source_node.meta.iceberg_location %}

SELECT *
FROM iceberg_scan('{{ iceberg_path }}')  -- DuckDB가 자동으로 최신 메타데이터 찾음
```

#### 3. DuckDB 설정 추가
```yaml
# profiles.yml
settings:
  s3_endpoint: "host.docker.internal:9000"
  s3_access_key_id: "admin"
  s3_secret_access_key: "mypassword"
  s3_region: "ap-northeast-2"
  s3_use_ssl: false
  s3_url_style: "path"
  unsafe_enable_version_guessing: true  # 버전 자동 감지 활성화
```

### 최종 검증
**실행 명령:**
```bash
docker run --rm --add-host=host.docker.internal:host-gateway \
  dbt-operator:test dbt run --target dev_iceberg --select stg_raw_iceberg
```

**출력:**
```
11:55:16  Found 1 model, 1 source, 843 macros
11:55:24  1 of 1 START sql view model main_staging.stg_raw_iceberg ....................... [RUN]
11:55:25  1 of 1 OK created sql view model main_staging.stg_raw_iceberg .................. [OK in 0.30s]
11:55:25  Completed successfully
11:55:25  Done. PASS=1 WARN=0 ERROR=0 SKIP=0 NO-OP=0 TOTAL=1
```

**결과:** ✅ **성공!**

---

## 주요 기술 개념 정리

### 1. dbt (data build tool)
- **정의:** SQL 기반 데이터 변환 도구
- **핵심 개념:**
  - **Models:** SQL SELECT 문으로 정의되는 데이터 변환 로직
  - **Sources:** 외부 데이터 소스 정의 (sources.yaml)
  - **Materialization:** 모델이 데이터베이스에 구현되는 방식 (view, table, incremental, ephemeral)
  - **Profiles:** 데이터베이스 연결 설정 (profiles.yml)
  - **Packages:** 재사용 가능한 매크로/모델 모음 (packages.yml)

### 2. Apache Iceberg
- **정의:** 대규모 분석용 오픈 테이블 포맷
- **특징:**
  - ACID 트랜잭션 지원
  - 스키마 진화 (Schema Evolution)
  - 파티션 진화 (Partition Evolution)
  - 타임 트래블 쿼리
  - 숨겨진 파티셔닝
- **메타데이터 구조:**
  - `metadata/` 디렉토리에 버전별 메타데이터 파일 저장
  - `v1.metadata.json`, `v2.metadata.json`, ... 형태로 증가
  - 최신 버전을 가리키는 version-hint 파일 존재

### 3. DuckDB
- **정의:** 임베디드 분석용 OLAP 데이터베이스
- **Iceberg 지원:**
  - `iceberg_scan()` 함수로 Iceberg 테이블 직접 읽기
  - S3/MinIO 등 오브젝트 스토리지 지원
  - `unsafe_enable_version_guessing`: 메타데이터 버전 자동 탐지 설정

### 4. Poetry
- **정의:** Python 의존성 관리 및 패키징 도구
- **주요 파일:**
  - `pyproject.toml`: 프로젝트 메타데이터 및 의존성 정의
  - `poetry.lock`: 정확한 의존성 버전 잠금
- **주요 명령:**
  - `poetry install`: 의존성 설치
  - `poetry lock`: lock 파일 업데이트
  - `poetry config virtualenvs.in-project true`: 프로젝트 내 venv 생성

### 5. Docker 네트워킹
- **host.docker.internal:**
  - Mac/Windows: Docker 컨테이너에서 호스트 머신을 가리키는 특수 DNS 이름
  - Linux: 기본 제공되지 않음, `--add-host=host.docker.internal:host-gateway` 필요
- **컨테이너 간 통신:**
  - 같은 네트워크: 컨테이너 이름으로 접근
  - 호스트 네트워크 모드: `--network host`로 호스트와 동일한 네트워크 사용

### 6. Jinja2 in dbt
- **용도:** dbt SQL 템플릿 엔진
- **주요 기능:**
  - 변수 설정: `{% set var = value %}`
  - 필터: `| selectattr()`, `| first`
  - 함수: `{{ config() }}`, `{{ ref() }}`, `{{ source() }}`
  - Graph 객체: `graph.sources`, `graph.nodes` - 프로젝트 메타데이터 접근

### 7. YAML 구문
- **들여쓰기 규칙:**
  - 같은 레벨의 키는 같은 들여쓰기
  - 자식 요소는 부모보다 2칸 들여쓰기 (관례)
  - 탭 사용 불가, 공백만 사용
- **매핑 (Mapping):**
  - `key: value` 형식
  - 중첩된 매핑은 들여쓰기로 표현

---

## 커밋 내역

```bash
git commit -m "Fix dbt-operator Docker build and add Iceberg table support

- Fix Jinja2 dependency conflict by removing version pin
- Add dbt deps installation step in Dockerfile
- Configure virtualenv PATH for dbt commands
- Add staging models for reading Iceberg tables from MinIO
- Update profiles.yml with MinIO S3 endpoint configuration
- Enable unsafe_enable_version_guessing for Iceberg version detection
- Successfully tested dbt run with Iceberg table on MinIO"

# Commit: 8b9d2b0
# Push: origin/main
```

---

## 결론

dbt-operator Docker 이미지가 성공적으로 빌드되었고, MinIO에 저장된 Iceberg 테이블을 읽어 dbt 모델을 실행할 수 있게 되었습니다. 주요 해결 포인트는:

1. 올바른 의존성 관리 (Poetry)
2. dbt의 graph 객체를 통한 메타데이터 접근
3. Iceberg 테이블 경로 및 DuckDB 설정
4. Docker 네트워킹 이해

이제 Airflow나 Kubernetes 환경에서 이 이미지를 활용하여 Iceberg 데이터 파이프라인을 구축할 수 있습니다.

