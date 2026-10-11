#!/usr/bin/env bash
# Acceptance checks of P2 Processing (quickstart.md P2). Load .env first (set -a; source .env).
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/apps.sh"
require_tools kubectl

https_valid_user() {
  trino_query admin "$TF_VAR_trino_admin_password" "SELECT 1" | grep -q 1
}

wrong_password_rejected() {
  ! trino_query admin wrong-password "SELECT 1"
}

http_rejected() {
  ! trino_cli http://localhost:8080 admin "$TF_VAR_trino_admin_password" "SELECT 1"
}

iceberg_schemas() {
  trino_query admin "$TF_VAR_trino_admin_password" "SHOW SCHEMAS FROM iceberg" | grep -q gold
}

bi_denied_bronze() {
  ! trino_query metabase "$TF_VAR_trino_metabase_password" "SHOW TABLES FROM iceberg.bronze"
}

bi_lists_gold() {
  trino_query metabase "$TF_VAR_trino_metabase_password" "SHOW TABLES FROM iceberg.gold"
}

workers_scale() {
  kubectl -n trino scale deployment trino-worker --replicas=1 &&
    kubectl -n trino rollout status deployment trino-worker --timeout=900s &&
    kubectl -n trino scale deployment trino-worker --replicas=0
}

check "trino Application Synced and Healthy" app_synced_healthy trino
check "query over HTTPS with a valid user" https_valid_user
check "wrong password rejected" wrong_password_rejected
check "password over plain HTTP rejected" http_rejected
check "Iceberg catalog lists the medallion schemas" iceberg_schemas
check "BI user denied on bronze" bi_denied_bronze
check "BI user can list gold" bi_lists_gold
check "workers scale 0 -> 1 -> 0 on the Spot group" workers_scale
summary
