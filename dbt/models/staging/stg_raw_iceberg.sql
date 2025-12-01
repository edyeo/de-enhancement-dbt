-- models/staging/stg_raw_iceberg.sql
{{ config(materialized='view', schema='staging') }}

-- 1. sources.yml의 메타데이터에서 Iceberg 테이블 경로를 가져옵니다.
{% set source_node = graph.sources.values() | selectattr("source_name", "equalto", "minio_data_lake") | selectattr("name", "equalto", "taxis") | first %}
{% set iceberg_path = source_node.meta.iceberg_location %}

SELECT
    *
FROM 
    -- [핵심] DuckDB의 iceberg_scan 함수를 사용해 S3 경로의 Iceberg 파일을 직접 읽습니다.
    -- 테이블 루트 경로를 전달하면 DuckDB가 자동으로 최신 메타데이터를 찾습니다
    iceberg_scan('{{ iceberg_path }}')