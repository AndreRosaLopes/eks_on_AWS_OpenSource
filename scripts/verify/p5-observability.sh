#!/usr/bin/env bash
# Acceptance checks of P5 Observability (quickstart.md P5). Load .env first (set -a; source .env).
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/apps.sh"
require_tools kubectl

# From a short-lived curl pod: the Prometheus and Grafana images have no HTTP client, and the
# control plane cannot reach port 9090 for the API server proxy.
prometheus_api() {
  kubectl -n observability run "prometheus-query-$RANDOM" --rm -i --quiet --restart=Never \
    --image=curlimages/curl:8.22.0 -- -s "http://kps-prometheus:9090/api/v1/$1"
}

targets_answer() {
  prometheus_api 'query?query=up' | grep -q '"status":"success"'
}

airflow_rule_loaded() {
  prometheus_api rules | grep -q AirflowTaskFailed
}

alertmanager_running() {
  kubectl -n observability get pods -l app.kubernetes.io/name=alertmanager | grep -q Running
}

no_secret_in_logs() {
  local ns
  for ns in polaris airbyte trino airflow metabase; do
    if kubectl -n "$ns" logs --all-containers --tail=2000 --selector 'app.kubernetes.io/instance' 2>/dev/null |
      grep -q -F -e "$TF_VAR_trino_admin_password" -e "$TF_VAR_polaris_root_client_secret"; then
      return 1
    fi
  done
  return 0
}

check "observability Application Synced and Healthy" app_synced_healthy observability
check "opencost Application Synced and Healthy" app_synced_healthy opencost
check "Prometheus queries answer" targets_answer
check "alert rule for failed Airflow tasks loaded" airflow_rule_loaded
check "Alertmanager running" alertmanager_running
check "no platform secret in the logs" no_secret_in_logs
summary
