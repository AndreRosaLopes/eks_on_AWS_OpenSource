# Quickstart: Validation per Checkpoint

Validation scenarios that prove each step works. Commands are run from the operator's
workstation with AWS credentials and `kubectl` configured; the automated versions go to
`scripts/verify/`. Decisions referenced are in [research.md](research.md).

## Prerequisites

- AWS credentials for the account (`aws sts get-caller-identity` succeeds).
- Terraform, `kubectl` and the AWS CLI installed and usable from Git Bash (see `docs/setup.md`).
- Local `.env` with the passwords (D-011), loaded in the shell before `terraform apply`.
- Terraform state bucket (D-005) and the persistent data bucket (`data/`, D-030) created once.
- For P4 and later: the Trino CA certificate (output of the `bootstrap` apply) and the SMTP
  credential for alerts in `.env` (D-024).

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

## P2 Processing

| Check | Expected outcome |
|---|---|
| Argo CD Application for Trino | Synced and Healthy; coordinator running, 0 workers |
| Trino over its port-forward with HTTPS and a valid user | Query succeeds; plain HTTP and wrong passwords are rejected |
| `SHOW TABLES` on the Iceberg catalog | Tables written by P1 are listed |
| Query with the BI service user on a sensitive column | Value masked or column hidden (D-026) |
| Query with the BI service user on bronze or silver | Access denied |
| dbt image workflow run on GitHub Actions | Image for arm64 published to GHCR with a pinned tag |
| dbt pod (`dbt build`) started by hand against Trino | Medallion layers and star schema tables created |

## P3 Orchestration

| Check | Expected outcome |
|---|---|
| Argo CD Application for Airflow | Synced and Healthy; no idle worker pods |
| A DAG committed to the repository | Appears in Airflow through git-sync without an image build |
| Daily DAG on schedule | Trino workers scale up, Airbyte sync and dbt pod run, workers return to 0; finished before 08:00 Brasília time |
| Same DAG triggered on demand | Runs |
| DAG run for one tumbling window | Processes exactly that window |
| Task logs after the task pod is gone | Readable in Airflow (remote logging in S3) |
| Argo CD after the run | Application still Synced (worker replicas ignored) |

## P4 BI and external systems

| Check | Expected outcome |
|---|---|
| AWS Load Balancer Controller and Envoy Gateway Applications | Synced and Healthy; one NLB created in the public subnets |
| BI port on the NLB address, without login | Login page only ([contracts/bi-access.md](contracts/bi-access.md)) |
| Business user login | Dashboards show processed data; sensitive columns masked or hidden |
| External system with its Trino user over the Trino port (`SSLVerification=CA`) | Query on the gold layer succeeds ([contracts/external-systems.md](contracts/external-systems.md)) |
| External system with a wrong password, or plain HTTP | Rejected |
| Admin interfaces (Airflow, Grafana, OpenMetadata, Argo CD) on the NLB | Not reachable; only through `kubectl port-forward` |

## P5 Observability

| Check | Expected outcome |
|---|---|
| Grafana through port-forward | Executions, failures and resource usage per workload visible |
| A DAG that fails on purpose | Alert email received by the technical team |
| A pod in crash loop | Alert email received |
| OpenCost | Cost per namespace/workload shown |
| AWS Cost Explorer filtered by the cost allocation tags (next day) | Cost per step visible, including NAT and NLB |
| Search of logs and metrics for the sample sensitive values | No occurrence (FR-006) |

## P6 Governance

| Check | Expected outcome |
|---|---|
| OpenSearch and OpenMetadata Applications | Synced and Healthy |
| OpenMetadata ingestion from Trino, Airflow and Airbyte | Processed datasets in the catalog |
| Lineage of a gold table | Source and each step visible |
| Sensitive column classified in OpenMetadata | The same column is masked or hidden by the Trino rules |

## Teardown

| Check | Expected outcome |
|---|---|
| `scripts/teardown.sh` without confirmation | Stops before deleting anything |
| `scripts/teardown.sh` with confirmation | Applications deleted in order; NLB and EBS volumes gone before `terraform destroy`; both destroys complete (D-029) |
| Final check of the script | No load balancer, target group, volume, network interface, security group, Elastic IP or EKS log group left for the cluster |
| Data bucket after the teardown | Still exists with its objects (D-030, FR-018) |
| `scripts/teardown.sh` run again after a partial teardown | Skips what no longer exists and completes |
