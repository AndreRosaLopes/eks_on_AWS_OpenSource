#!/usr/bin/env bash
# Acceptance checks of step 0.3 GitOps (quickstart.md 0.3).
source "$(dirname "$0")/lib.sh"
require_tools kubectl terraform

app_synced_healthy() {
  local app="$1" status
  status="$(kubectl -n argocd get application "$app" -o jsonpath='{.status.sync.status}/{.status.health.status}')"
  [ "$status" = "Synced/Healthy" ]
}

argocd_not_public() {
  [ "$(kubectl -n argocd get svc argocd-server -o jsonpath='{.spec.type}')" = "ClusterIP" ]
}

self_heal() {
  # A manual change to a managed resource is reverted by Argo CD.
  kubectl annotate storageclass gp3 storageclass.kubernetes.io/is-default-class=false --overwrite
  local i
  for i in $(seq 1 20); do
    sleep 15
    [ "$(kubectl get storageclass gp3 -o jsonpath='{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}')" = "true" ] && return 0
  done
  return 1
}

no_changes() {
  terraform -chdir="$REPO_ROOT/infra/terraform/bootstrap" plan -detailed-exitcode -input=false -lock=false
}

check "terraform plan in bootstrap has no changes" no_changes
check "Argo CD server is not exposed (ClusterIP)" argocd_not_public
check "root Application Synced and Healthy" app_synced_healthy root
check "storage Application Synced and Healthy" app_synced_healthy storage
check "cluster-autoscaler Application Synced and Healthy" app_synced_healthy cluster-autoscaler
check "manual change reverted by Argo CD" self_heal
summary
