#!/usr/bin/env bash
# Shared checks sourced by the step scripts.

# app_synced_healthy NAME: the Argo CD Application is Synced and Healthy.
app_synced_healthy() {
  local status
  status="$(kubectl -n argocd get application "$1" -o jsonpath='{.status.sync.status}/{.status.health.status}')"
  [ "$status" = "Synced/Healthy" ]
}

# no_load_balancer_services NS...: no Service of type LoadBalancer in the namespaces (FR-004).
no_load_balancer_services() {
  local ns
  for ns in "$@"; do
    if kubectl -n "$ns" get services -o jsonpath='{.items[*].spec.type}' | grep -q LoadBalancer; then
      return 1
    fi
  done
  return 0
}

# trino_cli SERVER USER PASSWORD SQL: runs a statement with the Trino CLI of the coordinator pod.
trino_cli() {
  kubectl -n trino exec deploy/trino-coordinator -- env TRINO_PASSWORD="$3" \
    trino --server "$1" --insecure --user "$2" --password --output-format CSV --execute "$4"
}

# trino_query USER PASSWORD SQL: same, over HTTPS inside the cluster.
trino_query() {
  trino_cli https://localhost:8443 "$1" "$2" "$3"
}
