#!/usr/bin/env bash
# Acceptance checks of P4 BI and external systems (quickstart.md P4, contracts/).
# Load .env first (set -a; source .env); the first external system user is used.
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/apps.sh"
require_tools kubectl curl

nlb="$(kubectl -n envoy-gateway-system get gateway platform -o jsonpath='{.status.addresses[0].value}')"
external_user="$(printf '%s' "${TF_VAR_trino_external_users:-}" | sed -n 's/^{"\([^"]*\)":"\([^"]*\)".*/\1/p')"
external_password="$(printf '%s' "${TF_VAR_trino_external_users:-}" | sed -n 's/^{"\([^"]*\)":"\([^"]*\)".*/\2/p')"

nlb_exists() {
  [ -n "$nlb" ]
}

bi_requires_login() {
  curl -sf -m 10 "http://$nlb/api/health" >/dev/null && ! curl -sf -m 10 "http://$nlb/api/user/current"
}

trino_over_nlb() {
  trino_cli "https://$nlb:8443" "$external_user" "$external_password" "SHOW SCHEMAS FROM iceberg" | grep -q gold
}

trino_wrong_password() {
  ! trino_cli "https://$nlb:8443" "$external_user" wrong-password "SELECT 1"
}

only_public_ports() {
  local port
  for port in 3000 8080 8585 9090; do
    if curl -s -m 5 "http://$nlb:$port/" >/dev/null; then
      return 1
    fi
  done
  return 0
}

check "aws-load-balancer-controller Application Synced and Healthy" app_synced_healthy aws-load-balancer-controller
check "envoy-gateway Application Synced and Healthy" app_synced_healthy envoy-gateway
check "metabase Application Synced and Healthy" app_synced_healthy metabase
check "NLB address on the Gateway" nlb_exists
check "BI without login shows no data" bi_requires_login
check "external system queries Trino over HTTPS through the NLB" trino_over_nlb
check "wrong password rejected through the NLB" trino_wrong_password
check "admin ports not open on the NLB" only_public_ports
summary
