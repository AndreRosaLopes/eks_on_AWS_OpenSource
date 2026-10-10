#!/usr/bin/env bash
# Ordered teardown of the platform without orphan cloud resources (D-029).
#
# 1. Ask for typed confirmation.
# 2. Delete the root Argo CD Application without cascade (stops the recreation of the others).
# 3. Delete the envoy-gateway Application with cascade and wait for its load balancer to go away.
# 4. Delete the workload Applications with cascade, then the remaining PVCs, and wait for their
#    EBS volumes to go away.
# 5. Delete the controller Applications (load balancer controller, Cluster Autoscaler, storage).
# 6. terraform destroy in infra/terraform/bootstrap (interactive).
# 7. terraform destroy in infra/terraform/foundation (interactive).
# 8. Check for orphan resources and exit non-zero if any is found.
#
# The data bucket (infra/terraform/data) and the state bucket (infra/terraform/state) are never
# touched. The script can be run again after a partial teardown.
#
# Usage (Git Bash, from the repository root): scripts/teardown.sh
set -euo pipefail

export AWS_REGION="${AWS_REGION:-us-east-2}"
export AWS_DEFAULT_REGION="$AWS_REGION"
NAME="${CLUSTER_NAME:-data-platform-dev}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-900}"
CONTROLLER_APPS="aws-load-balancer-controller cluster-autoscaler storage"

log() { echo "==> $*"; }

for tool in aws kubectl terraform; do
  command -v "$tool" >/dev/null 2>&1 || { echo "Missing tool: $tool" >&2; exit 2; }
done

# Secrets are required as variables by the bootstrap root module, also on destroy (D-011).
if [ -f "$REPO_ROOT/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  source "$REPO_ROOT/.env"
  set +a
fi

# wait_until "description" command args...: retries the command every 15 s until it succeeds.
wait_until() {
  local description="$1"
  shift
  local waited=0
  until "$@"; do
    if [ "$waited" -ge "$TIMEOUT_SECONDS" ]; then
      echo "Timeout waiting for: $description" >&2
      exit 1
    fi
    sleep 15
    waited=$((waited + 15))
  done
}

# ---- 1. Confirmation -------------------------------------------------------------------------
account="$(aws sts get-caller-identity --query Account --output text)"
vpc_id="$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=$NAME" --query 'Vpcs[0].VpcId' --output text)"
[ "$vpc_id" = "None" ] && vpc_id=""
echo "Account: $account  Region: $AWS_REGION  Cluster: $NAME  VPC: ${vpc_id:-none}"
echo "This deletes every Argo CD Application, the cluster and the network. Data and state buckets are kept."
read -r -p "Type the cluster name to confirm: " answer
if [ "$answer" != "$NAME" ]; then
  echo "Cancelled."
  exit 1
fi

cluster_exists=false
if aws eks describe-cluster --name "$NAME" >/dev/null 2>&1; then
  cluster_exists=true
  aws eks update-kubeconfig --name "$NAME" >/dev/null
fi

app_exists() { kubectl -n argocd get application "$1" >/dev/null 2>&1; }

# delete_app NAME: deletes an Application with cascade (Argo CD prunes its resources first).
delete_app() {
  local app="$1"
  app_exists "$app" || return 0
  log "Deleting Application $app with cascade"
  kubectl -n argocd patch application "$app" --type merge \
    -p '{"metadata":{"finalizers":["resources-finalizer.argocd.argoproj.io"]}}' >/dev/null
  kubectl -n argocd delete application "$app" --wait=true --timeout="${TIMEOUT_SECONDS}s"
}

no_load_balancers() {
  [ -z "$vpc_id" ] && return 0
  local count
  count="$(aws elbv2 describe-load-balancers --query "length(LoadBalancers[?VpcId=='$vpc_id'])" --output text)"
  [ "$count" = "0" ]
}

dynamic_volumes() {
  aws ec2 describe-volumes \
    --filters "Name=tag:Project,Values=$NAME" "Name=tag-key,Values=CSIVolumeName" \
    --query 'Volumes[].VolumeId' --output text
}

no_dynamic_volumes() { [ -z "$(dynamic_volumes)" ]; }

if [ "$cluster_exists" = true ] && kubectl get namespace argocd >/dev/null 2>&1; then
  # ---- 2. Root Application without cascade ---------------------------------------------------
  if app_exists root; then
    log "Deleting the root Application without cascade"
    kubectl -n argocd patch application root --type merge -p '{"metadata":{"finalizers":null}}' >/dev/null
    kubectl -n argocd delete application root --wait=true --timeout=120s
  fi
  # Without automated sync, Argo CD no longer recreates what this script deletes.
  for app in $(kubectl -n argocd get applications -o jsonpath='{.items[*].metadata.name}'); do
    kubectl -n argocd patch application "$app" --type json \
      -p '[{"op":"remove","path":"/spec/syncPolicy/automated"}]' >/dev/null 2>&1 || true
  done

  # ---- 3. Gateway and its load balancer ------------------------------------------------------
  # The Gateway is deleted first, while Envoy Gateway and the load balancer controller still run,
  # so the controller deletes the NLB of the Envoy Service.
  if kubectl get crd gateways.gateway.networking.k8s.io >/dev/null 2>&1; then
    log "Deleting the Gateways"
    kubectl delete gateways.gateway.networking.k8s.io --all --all-namespaces --wait=true --timeout="${TIMEOUT_SECONDS}s"
  fi
  log "Deleting the remaining Services of type LoadBalancer"
  kubectl get services --all-namespaces \
    -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.namespace} {.metadata.name}{"\n"}{end}' |
    while read -r ns svc; do
      [ -n "$ns" ] && kubectl -n "$ns" delete service "$svc" --wait=true --timeout="${TIMEOUT_SECONDS}s"
    done
  log "Waiting until no load balancer remains in the VPC"
  wait_until "load balancers deleted" no_load_balancers
  delete_app envoy-gateway

  # ---- 4. Workloads, PVCs and EBS volumes ----------------------------------------------------
  for app in $(kubectl -n argocd get applications -o jsonpath='{.items[*].metadata.name}'); do
    case " $CONTROLLER_APPS " in
      *" $app "*) ;;
      *) delete_app "$app" ;;
    esac
  done
  log "Deleting the remaining PersistentVolumeClaims"
  kubectl delete pvc --all --all-namespaces --wait=true --timeout="${TIMEOUT_SECONDS}s"
  log "Waiting until the EBS volumes of the PVCs are deleted"
  wait_until "EBS volumes deleted" no_dynamic_volumes

  # ---- 5. Controllers ------------------------------------------------------------------------
  for app in $CONTROLLER_APPS; do
    delete_app "$app"
  done
else
  log "Cluster or Argo CD not found: skipping the Kubernetes steps"
fi

# ---- 6 and 7. Terraform destroy (interactive) -------------------------------------------------
if [ "$cluster_exists" = true ]; then
  log "terraform destroy in infra/terraform/bootstrap"
  terraform -chdir="$REPO_ROOT/infra/terraform/bootstrap" init -input=false >/dev/null
  terraform -chdir="$REPO_ROOT/infra/terraform/bootstrap" destroy
fi

log "terraform destroy in infra/terraform/foundation"
terraform -chdir="$REPO_ROOT/infra/terraform/foundation" init -input=false >/dev/null
terraform -chdir="$REPO_ROOT/infra/terraform/foundation" destroy

# ---- 8. Orphan check -------------------------------------------------------------------------
log "Checking for orphan resources"
orphans=0
report() {
  local what="$1" value="$2"
  if [ -n "$value" ] && [ "$value" != "None" ] && [ "$value" != "0" ]; then
    echo "ORPHAN $what: $value"
    orphans=$((orphans + 1))
  else
    echo "ok     $what"
  fi
}

if [ -n "$vpc_id" ]; then
  report "VPC" "$(aws ec2 describe-vpcs --filters "Name=vpc-id,Values=$vpc_id" --query 'Vpcs[].VpcId' --output text)"
  report "load balancers" "$(aws elbv2 describe-load-balancers --query "LoadBalancers[?VpcId=='$vpc_id'].LoadBalancerName" --output text)"
  report "target groups" "$(aws elbv2 describe-target-groups --query "TargetGroups[?VpcId=='$vpc_id'].TargetGroupName" --output text)"
  report "network interfaces" "$(aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=$vpc_id" --query 'NetworkInterfaces[].NetworkInterfaceId' --output text)"
  report "security groups" "$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$vpc_id" --query 'SecurityGroups[].GroupId' --output text)"
fi
report "EBS volumes" "$(aws ec2 describe-volumes --filters "Name=tag:Project,Values=$NAME" --query 'Volumes[].VolumeId' --output text)"
report "Elastic IPs" "$(aws ec2 describe-addresses --filters "Name=tag:Project,Values=$NAME" --query 'Addresses[].PublicIp' --output text)"
report "EKS log group" "$(aws logs describe-log-groups --log-group-name-prefix "/aws/eks/$NAME/" --query 'logGroups[].logGroupName' --output text)"

if [ "$orphans" -gt 0 ]; then
  echo "Teardown finished with $orphans orphan resource type(s); delete them before they are billed." >&2
  exit 1
fi
log "Teardown complete: only the data and state buckets remain."
