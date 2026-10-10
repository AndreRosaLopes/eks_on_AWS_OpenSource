# Quickstart: Validation per Checkpoint

Validation scenarios that prove each step works. Commands are run from the operator's
workstation with AWS credentials and `kubectl` configured; the automated versions go to
`scripts/verify/`. Decisions referenced are in [research.md](research.md).

## Prerequisites

- AWS credentials for the account (`aws sts get-caller-identity` succeeds).
- Terraform, `kubectl` and the AWS CLI installed (see `docs/setup.md`).
- Local `.env` with the passwords (D-011), loaded in the shell before `terraform apply`.
- Terraform state bucket created once (D-005).

## 0.1 Network

| Check | Expected outcome |
|---|---|
| `terraform plan` in `foundation` after apply | No changes |
| The VPC has 2 public and 2 private subnets in 2 AZs | 4 subnets, 2 per AZ |
| The private route table sends `0.0.0.0/0` to the single NAT gateway | One NAT gateway route |
| The private route table has the S3 gateway endpoint route | S3 prefix list route present |
| A test instance in a private subnet reaches the internet and has no public IP | Outbound succeeds; no inbound path |

## 0.2 Cluster

| Check | Expected outcome |
|---|---|
| `aws eks update-kubeconfig --name <cluster> --region us-east-2` then `kubectl get nodes` | Base node(s) `Ready`, arm64, no public IP |
| `kubectl version` | Server version 1.36 |
| EKS add-ons (VPC CNI, CoreDNS, kube-proxy, EBS CSI) | All `ACTIVE` |
| A test pod with a PersistentVolumeClaim on the gp3 StorageClass | Volume bound; data kept after pod restart |
| A test Deployment that does not fit the current nodes | Cluster Autoscaler adds a node; the node is removed after the Deployment is deleted |
| A test pod reads an allowed S3 bucket using the node role | Read succeeds (D-004) |

## 0.3 GitOps

| Check | Expected outcome |
|---|---|
| `terraform plan` in `bootstrap` after apply | No changes |
| `kubectl -n argocd port-forward svc/argocd-server 8080:443` | Argo CD UI reachable only through the port-forward |
| A test Application committed under `infra/platform/argocd/` | Synced and Healthy without manual commands |
| A manual change to the test Application's resources | Reverted by Argo CD |

## P1 Ingestion

| Check | Expected outcome |
|---|---|
| Argo CD Applications for Polaris, its PostgreSQL, Airbyte and the sample source | Synced and Healthy |
| Polaris bootstrap Job | Completed; realm and catalog exist |
| Airbyte UI through `kubectl port-forward` | Reachable |
| Airbyte connection: sample PostgreSQL → S3 Data Lake destination (Polaris catalog) | Sync succeeds |
| Polaris lists the namespace and tables created by the sync | Tables present, stored as Iceberg in S3 |
| `kubectl get secrets` contains the database passwords; `git grep` finds none of them | Secrets only in the cluster and in the Terraform state (D-011) |
