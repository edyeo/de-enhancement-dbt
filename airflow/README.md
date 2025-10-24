# Airflow Scheduler Docker Image

Kubernetes 환경에서 Airflow 스케줄러로 사용할 수 있는 최적화된 Docker 이미지입니다.

## 🚀 주요 특징

- **KubernetesExecutor 지원**: Kubernetes 환경에 최적화된 실행자
- **멀티스테이지 빌드**: 최적화된 이미지 크기와 보안
- **Helm Chart 호환**: Kubernetes 배포에 최적화된 설정
- **자동화된 빌드**: CI/CD 파이프라인 통합
- **보안 강화**: 최소 권한 원칙 적용

## 📦 이미지 구성

### 기본 이미지
- `apache/airflow:3.1.0` (버전 변경 가능)

### 추가 패키지
- `apache-airflow-providers-cncf-kubernetes==4.0.0`
- 시스템 도구: `vim`, `curl`, `git`

### 환경 변수
```bash
AIRFLOW__CORE__EXECUTOR=KubernetesExecutor
AIRFLOW__KUBERNETES__NAMESPACE=default
AIRFLOW__KUBERNETES__WORKER_CONTAINER_REPOSITORY=apache/airflow
AIRFLOW__KUBERNETES__WORKER_CONTAINER_TAG=3.1.0
AIRFLOW__KUBERNETES__DELETE_WORKER_PODS=True
AIRFLOW__KUBERNETES__DELETE_WORKER_PODS_ON_FAILURE=True
```

## 🛠️ 사용법

### 로컬 빌드
```bash
# 기본 빌드
make build

# 커스텀 설정으로 빌드
make build IMAGE_NAME=airflow-scheduler IMAGE_TAG=v1.0.0 AIRFLOW_VERSION=3.1.0

# 레지스트리에 푸시
make push REGISTRY=your-registry.com
```

### 스크립트 사용
```bash
# 실행 권한 부여
chmod +x build.sh

# 빌드 실행
./build.sh airflow-scheduler v1.0.0 your-registry.com 3.1.0
```

### Docker 직접 사용
```bash
# 이미지 빌드
docker build --build-arg AIRFLOW_VERSION=3.1.0 -t airflow-scheduler:latest .

# 컨테이너 실행
docker run --rm airflow-scheduler:latest airflow scheduler
```

## ☸️ Kubernetes 배포

### Helm Chart 사용
```yaml
# values.yaml 예제
image:
  repository: your-registry.com/airflow-scheduler
  tag: latest
  pullPolicy: IfNotPresent

resources:
  requests:
    memory: "512Mi"
    cpu: "250m"
  limits:
    memory: "1Gi"
    cpu: "500m"

airflow:
  executor: KubernetesExecutor
  namespace: airflow
```

### 매니페스트 직접 사용
```bash
# 예제 매니페스트 적용
kubectl apply -f k8s-deployment-example.yaml
```

## 🔧 CI/CD 통합

### GitHub Actions
```yaml
# 워크플로우에서 사용
- name: Build Airflow Image
  run: |
    cd airflow
    make build IMAGE_NAME=airflow-scheduler IMAGE_TAG=${{ github.sha }} REGISTRY=${{ env.REGISTRY_URL }}
```

### 수동 트리거
GitHub Actions에서 다음 옵션으로 수동 빌드 가능:
- Operator: `airflow`
- Image Tag: `latest` (또는 커스텀 태그)
- Registry: `your-registry.com`
- Push to Registry: `true/false`

## 🧪 테스트

### 기본 테스트
```bash
# 이미지 테스트
make test

# 헬스 체크
make health-check

# 컨테이너 쉘 접근
make shell
```

### Kubernetes 테스트
```bash
# 스케줄러 프로세스 확인
kubectl exec -it airflow-scheduler-pod -- pgrep -f "airflow scheduler"

# 로그 확인
kubectl logs airflow-scheduler-pod
```

## 📊 모니터링

### 헬스 체크
- **Liveness Probe**: 스케줄러 프로세스 실행 상태 확인
- **Readiness Probe**: 스케줄러 준비 상태 확인
- **Health Check**: 컨테이너 내부 헬스 체크

### 로그 모니터링
```bash
# 실시간 로그 확인
kubectl logs -f deployment/airflow-scheduler

# 특정 시간대 로그
kubectl logs --since=1h deployment/airflow-scheduler
```

## 🔒 보안 고려사항

- **최소 권한**: `airflow` 사용자로 실행
- **이미지 스캔**: `make security-scan` 명령으로 보안 취약점 검사
- **시크릿 관리**: Kubernetes Secret을 통한 민감 정보 관리
- **네트워크 정책**: 필요한 포트만 노출

## 📈 성능 최적화

- **리소스 제한**: CPU/메모리 리소스 적절히 설정
- **이미지 크기**: 멀티스테이지 빌드로 최적화
- **캐시 활용**: Docker 레이어 캐싱 활용
- **병렬 처리**: KubernetesExecutor의 병렬 태스크 실행

## 🆘 문제 해결

### 일반적인 문제
1. **스케줄러 시작 실패**: 데이터베이스 연결 확인
2. **워커 팟 생성 실패**: RBAC 권한 및 이미지 풀 정책 확인
3. **태스크 실행 실패**: 리소스 제한 및 네트워크 정책 확인

### 디버깅 명령어
```bash
# 컨테이너 상태 확인
kubectl describe pod airflow-scheduler-pod

# 이벤트 확인
kubectl get events --sort-by=.metadata.creationTimestamp

# 리소스 사용량 확인
kubectl top pod airflow-scheduler-pod
```

## 📚 추가 자료

- [Apache Airflow 공식 문서](https://airflow.apache.org/docs/)
- [KubernetesExecutor 가이드](https://airflow.apache.org/docs/apache-airflow/stable/executor/kubernetes.html)
- [Helm Chart 가이드](https://helm.sh/docs/)
