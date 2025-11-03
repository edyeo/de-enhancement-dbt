# =====================================================================
# STAGE 1: Builder - JDK와 빌드 도구를 임시로 설치하여 Python 패키지 빌드
# =====================================================================
FROM flink:2.1.0-scala_2.12-java21 AS builder

USER root

# JDK와 C/C++ 빌드 도구, uv 설치 도구(pip) 설치
# openjdk-21-jdk: pemja 빌드를 위한 JDK 헤더 파일 포함
RUN apt-get update && \
    apt-get install -y openjdk-21-jdk build-essential python3-pip && \
    rm -rf /var/lib/apt/lists/*

# JAVA_HOME 환경 변수 설정 (pemja 빌드를 위해 필요)
# 실제로 설치된 java-21-openjdk 디렉토리를 찾아서 설정
RUN JAVA_DIR=$(ls -d /usr/lib/jvm/java-21-openjdk-* 2>/dev/null | head -n 1) && \
    ln -sf $JAVA_DIR /usr/lib/jvm/default-java

ENV JAVA_HOME=/usr/lib/jvm/default-java

# uv 설치 (빠른 패키지 설치를 위해)
RUN pip3 install uv

WORKDIR /opt/flink

# venv 생성 (uv 사용) 및 소유권 변경
RUN uv venv /opt/flink/venv && \
    chown -R flink:flink /opt/flink/venv

USER flink

# requirements.txt 복사
COPY --chown=flink:flink requirements.txt .

# [핵심] builder 스테이지에서는 JDK가 있으므로 
# pemja가 소스에서 빌드되어도 성공합니다.
RUN /usr/local/bin/uv pip install --python /opt/flink/venv/bin/python -r requirements.txt


# =====================================================================
# STAGE 2: Final Image - 깨끗한 Flink 이미지 + 빌드된 venv만 복사
# =====================================================================
FROM flink:2.1.0-scala_2.12-java21

USER root

# Python3 런타임 설치 (venv 실행에 필요, JDK와 빌드 도구는 불필요)
RUN apt-get update && \
    apt-get install -y python3 python3-distutils && \
    rm -rf /var/lib/apt/lists/*

# Flink 설정 파일에 Python venv 경로 지정
RUN echo "python.execution.environment.path: /opt/flink/venv" >> /opt/flink/conf/flink-conf.yaml

USER flink

WORKDIR /opt/flink

# [핵심] 'builder' 스테이지에서 '빌드가 완료된' venv만 그대로 복사
# JDK와 빌드 도구들은 이 이미지에 포함되지 않아 이미지 크기가 대폭 감소
COPY --from=builder --chown=flink:flink /opt/flink/venv /opt/flink/venv

# (선택 사항) PyFlink 스크립트 등 애플리케이션 코드 복사
# COPY --chown=flink:flink . .

# 디버깅 등을 위한 PATH 설정
ENV PATH="/opt/flink/venv/bin:$PATH"
