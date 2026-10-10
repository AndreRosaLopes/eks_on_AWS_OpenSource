#!/usr/bin/env bash
# Acceptance checks of step 0.2 Cluster (quickstart.md 0.2). Creates and deletes test pods in the
# namespace verify-0-2.
source "$(dirname "$0")/lib.sh"
require_tools aws kubectl

NS=verify-0-2

nodes_ready_arm64() {
  local not_ready
  not_ready="$(kubectl get nodes -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Ready")].status} {.status.nodeInfo.architecture}{"\n"}{end}' \
    | grep -v -c '^True arm64$' || true)"
  [ "$not_ready" = "0" ] && [ "$(kubectl get nodes --no-headers | wc -l)" -ge 1 ]
}

nodes_without_public_ip() {
  ! kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="ExternalIP")].address}' | grep -q .
}

server_version() {
  kubectl version -o json | grep -q '"minor": "36'
}

addons_active() {
  local addon status
  for addon in vpc-cni coredns kube-proxy aws-ebs-csi-driver; do
    status="$(aws eks describe-addon --cluster-name "$CLUSTER_NAME" --addon-name "$addon" --query 'addon.status' --output text)"
    [ "$status" = "ACTIVE" ] || return 1
  done
}

pvc_on_gp3() {
  kubectl -n "$NS" apply -f - <<'YAML'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: pvc-test
spec:
  containers:
    - name: test
      image: public.ecr.aws/docker/library/busybox:1.37
      command: [sh, -c, "echo ok > /data/test && sleep 3600"]
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: test
YAML
  kubectl -n "$NS" wait --for=condition=Ready pod/pvc-test --timeout=300s
  [ "$(kubectl -n "$NS" get pvc test -o jsonpath='{.spec.storageClassName}')" = "gp3" ]
}

autoscaler_adds_node() {
  local before
  before="$(kubectl get nodes --no-headers | wc -l)"
  kubectl -n "$NS" create deployment big --image=public.ecr.aws/docker/library/busybox:1.37 \
    --replicas=3 -- sleep 3600
  kubectl -n "$NS" set resources deployment big --requests=cpu=1,memory=2Gi
  kubectl -n "$NS" wait --for=condition=Available deployment/big --timeout=600s
  [ "$(kubectl get nodes --no-headers | wc -l)" -gt "$before" ]
}

s3_with_node_role() {
  kubectl -n "$NS" run s3-test --image=public.ecr.aws/aws-cli/aws-cli:2.37.9 --restart=Never \
    --command -- aws s3 ls "s3://data-platform-dev-data-$(aws sts get-caller-identity --query Account --output text)"
  kubectl -n "$NS" wait --for=jsonpath='{.status.phase}'=Succeeded pod/s3-test --timeout=300s
}

kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
check "nodes Ready and arm64" nodes_ready_arm64
check "nodes without public IP" nodes_without_public_ip
check "server version 1.36" server_version
check "EKS add-ons ACTIVE" addons_active
check "PVC bound on gp3 and pod running" pvc_on_gp3
check "S3 read with the node role" s3_with_node_role
check "Cluster Autoscaler adds a node" autoscaler_adds_node
kubectl delete namespace "$NS" --wait=true >/dev/null
echo "Note: the extra node is removed by the Cluster Autoscaler after about 10 minutes."
summary
