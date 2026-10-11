#!/usr/bin/env bash
# Acceptance checks of P1 Ingestion (quickstart.md P1). Load .env first (set -a; source .env).
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/apps.sh"
require_tools aws kubectl git

bootstrap_completed() {
  kubectl -n polaris get job polaris-bootstrap -o jsonpath='{.status.succeeded}' | grep -q 1
}

catalog_created() {
  kubectl -n polaris get job polaris-catalog -o jsonpath='{.status.succeeded}' | grep -q 1
}

iceberg_tables_in_bucket() {
  local account
  account="$(aws sts get-caller-identity --query Account --output text)"
  aws s3 ls "s3://data-platform-dev-data-$account/lakehouse/" --recursive | grep -q 'metadata.json'
}

secrets_present() {
  kubectl -n polaris get secret polaris-db polaris-root && kubectl -n sample-source get secret sample-source-db
}

no_password_in_git() {
  local value
  for value in "${TF_VAR_polaris_db_password:-}" "${TF_VAR_polaris_root_client_secret:-}" \
    "${TF_VAR_sample_source_db_password:-}"; do
    [ -n "$value" ] || return 1
    if git -C "$REPO_ROOT" grep -q -F "$value"; then
      return 1
    fi
  done
  return 0
}

check "polaris Application Synced and Healthy" app_synced_healthy polaris
check "sample-source Application Synced and Healthy" app_synced_healthy sample-source
check "airbyte Application Synced and Healthy" app_synced_healthy airbyte
check "Polaris bootstrap Job completed" bootstrap_completed
check "Polaris catalog and medallion namespaces Job completed" catalog_created
check "Iceberg tables written to the data bucket" iceberg_tables_in_bucket
check "P1 Secrets present in the cluster" secrets_present
check "no P1 password in Git" no_password_in_git
check "no LoadBalancer Service in the P1 namespaces" no_load_balancer_services polaris airbyte sample-source
summary
