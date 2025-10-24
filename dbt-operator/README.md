# dbt Operator Docker Image

Airflow Kubernetes Pod Operator에서 사용할 수 있는 dbt 실행용 Docker 이미지입니다.

## 구조

```
dbt-operator/
├── Dockerfile              # Docker 이미지 정의
├── Makefile               # 빌드 자동화 스크립트
├── pyproject.toml         # Poetry 프로젝트 설정 및 의존성
├── poetry.lock            # Poetry 잠금 파일 (자동 생성)
├── .venv/                 # Poetry 가상환경 (자동 생성)
├── .dockerignore          # Docker 빌드 최적화
├── dbt_project.yml        # dbt 프로젝트 설정
├── profiles.yml           # dbt 프로파일 설정
├── packages.yml           # dbt 패키지 의존성
├── entrypoint.sh          # 컨테이너 진입점 스크립트
├── models/                # dbt 모델 (사용자가 추가)
├── macros/                # dbt 매크로
├── tests/                 # dbt 테스트
├── seeds/                 # dbt 시드 데이터
├── snapshots/             # dbt 스냅샷
└── analysis/              # dbt 분석
```

## 사용법

### Poetry 환경 설정 (로컬 개발)

```bash
# Poetry 설치 (macOS)
brew install poetry

# Poetry 설치 (Linux/Windows)
curl -sSL https://install.python-poetry.org | python3 -

# 의존성 설치
make poetry-install

# 가상환경 활성화
make poetry-shell

# 의존성 업데이트
make poetry-update

# Poetry 설정 확인
make poetry-check
```

### Docker 이미지 빌드

```bash
# 기본 빌드
make build

# 캐시 없이 빌드
make build-no-cache

# 커스텀 이미지명과 태그로 빌드
make build IMAGE_NAME=my-dbt-operator IMAGE_TAG=v1.0.0

# 레지스트리 포함 빌드
make build REGISTRY=your-registry.com IMAGE_NAME=dbt-operator IMAGE_TAG=latest
```

### 이미지 테스트

```bash
# 기본 테스트
make test

# 컨테이너에서 쉘 실행
make shell

# dbt 명령어 실행
make run-deps
make run-test
make run-compile
```

### 이미지 관리

```bash
# 이미지 크기 확인
make size

# 이미지 상세 정보 확인
make inspect

# 이미지 삭제
make clean

# 모든 dbt-operator 이미지 삭제
make clean-all
```

### 레지스트리 작업

```bash
# 이미지 푸시
make push REGISTRY=your-registry.com

# 이미지 풀
make pull REGISTRY=your-registry.com
```

## Airflow Kubernetes Pod Operator 사용법

### 기본 dbt 실행 태스크

```python
from airflow.providers.cncf.kubernetes.operators.kubernetes_pod import KubernetesPodOperator

dbt_run_task = KubernetesPodOperator(
    task_id='dbt_run',
    name='dbt-run',
    image='dbt-operator:latest',
    cmds=['dbt'],
    arguments=['run'],
    namespace='default',
    is_delete_operator_pod=True,
    get_logs=True,
)
```

### 환경 변수를 사용한 dbt 테스트 태스크

```python
dbt_test_task = KubernetesPodOperator(
    task_id='dbt_test',
    name='dbt-test',
    image='dbt-operator:latest',
    cmds=['dbt'],
    arguments=['test'],
    namespace='default',
    env_vars={
        'DBT_HOST': 'your-db-host',
        'DBT_USER': 'your-db-user',
        'DBT_PASSWORD': 'your-db-password',
        'DBT_DATABASE': 'your-database',
        'DBT_SCHEMA': 'your-schema'
    },
    is_delete_operator_pod=True,
    get_logs=True,
)
```

### dbt 시드 데이터 로드 태스크

```python
dbt_seed_task = KubernetesPodOperator(
    task_id='dbt_seed',
    name='dbt-seed',
    image='dbt-operator:latest',
    cmds=['dbt'],
    arguments=['seed'],
    namespace='default',
    env_vars={
        'DBT_HOST': 'your-db-host',
        'DBT_USER': 'your-db-user',
        'DBT_PASSWORD': 'your-db-password',
        'DBT_DATABASE': 'your-database',
        'DBT_SCHEMA': 'your-schema'
    },
    is_delete_operator_pod=True,
    get_logs=True,
)
```

## 환경 변수

다음 환경 변수들을 사용하여 데이터베이스 연결을 설정할 수 있습니다:

- `DBT_HOST`: 데이터베이스 호스트
- `DBT_USER`: 데이터베이스 사용자명
- `DBT_PASSWORD`: 데이터베이스 비밀번호
- `DBT_PORT`: 데이터베이스 포트 (기본값: 5432)
- `DBT_DATABASE`: 데이터베이스명
- `DBT_SCHEMA`: 스키마명 (기본값: public)

## 지원하는 데이터베이스

현재 PostgreSQL을 기본으로 설정되어 있습니다. 다른 데이터베이스를 사용하려면 `requirements.txt`에서 해당 어댑터를 활성화하고 `profiles.yml`을 수정하세요.

지원되는 어댑터:
- PostgreSQL (`dbt-postgres`)
- Snowflake (`dbt-snowflake`)
- BigQuery (`dbt-bigquery`)
- Redshift (`dbt-redshift`)
- Databricks (`dbt-databricks`)
- Spark (`dbt-spark`)

## 개발 모드

로컬에서 개발할 때는 볼륨 마운트를 사용할 수 있습니다:

```bash
make dev
```

또는 직접 Docker 명령어 사용:

```bash
docker run --rm -it -v $(pwd):/app dbt-operator:latest /bin/bash
```

## 도움말

사용 가능한 모든 Makefile 타겟을 보려면:

```bash
make help
```
