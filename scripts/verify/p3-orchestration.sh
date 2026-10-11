#!/usr/bin/env bash
# Acceptance checks of P3 Orchestration (quickstart.md P3). DAG checks belong to the data scope.
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/apps.sh"
require_tools kubectl

AIRFLOW_SA=system:serviceaccount:airflow:airflow-worker

no_idle_workers() {
  [ -z "$(kubectl -n airflow get pods -l component=worker -o name)" ]
}

git_sync_running() {
  kubectl -n airflow get pods -l component=dag-processor \
    -o jsonpath='{.items[0].spec.containers[*].name}' | grep -q git-sync
}

can_scale_trino() {
  kubectl auth can-i patch deployments/trino-worker -n trino --subresource=scale --as="$AIRFLOW_SA" | grep -q yes
}

scale_keeps_synced() {
  kubectl -n trino scale deployment trino-worker --replicas=0 --as="$AIRFLOW_SA" && sleep 30 &&
    app_synced_healthy trino
}

remote_logging() {
  kubectl -n airflow get configmap airflow-config -o jsonpath='{.data.airflow\.cfg}' |
    grep -q 'remote_base_log_folder = s3://'
}

check "airflow Application Synced and Healthy" app_synced_healthy airflow
check "no idle worker pods" no_idle_workers
check "git-sync running" git_sync_running
check "Airflow service account can scale the Trino workers" can_scale_trino
check "scale by Airflow keeps the trino Application Synced" scale_keeps_synced
check "remote logging to S3 configured" remote_logging
summary
