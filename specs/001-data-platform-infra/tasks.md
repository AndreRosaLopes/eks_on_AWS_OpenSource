---

description: "Task list for the data platform infrastructure"
---

# Tasks: Data Platform Infrastructure

**Input**: Design documents from `specs/001-data-platform-infra/`

**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md),
[quickstart.md](quickstart.md), [contracts/](contracts/)

**Tests**: no unit tests. Acceptance is checked by scripts in `scripts/verify/` (constitution XI),
one per checkpoint, following [quickstart.md](quickstart.md); they are listed as tasks.

**Organization**: Phase 1 (setup) and Phase 2 (step 0: network, cluster, GitOps, teardown) block
everything. Then one phase per user story, in the spec's priority order (US1 = P1 Ingestion …
US6 = P6 Governance).

**Rules for every task**:
- Pin every version (Terraform, providers, modules, charts, images) to the newest stable release,
  verified at the time of the task (constitution X, XII); every image must exist for arm64 (D-007).
- No secret in any versioned file (constitution IV): secrets come from `.env` as `TF_VAR_*` and
  become Kubernetes Secrets in the `bootstrap` apply (D-011).
- `terraform apply` and `terraform destroy` only with the user's explicit approval (constitution
  XI); before each apply: `terraform fmt`, `terraform validate`, reviewed `terraform plan`.
- Each component: one Argo CD Application in `infra/platform/argocd/<component>.yaml`; Helm values
  in `infra/platform/apps/<component>/values.yaml`; own resources as plain YAML in
  `infra/platform/apps/<component>/manifests/` (constitution XIII). Applications with a chart use
  multiple sources (the chart, plus this repository as `ref: values` for `valueFiles` and the
  `manifests/` path), `syncPolicy.automated` with `prune` and `selfHeal`,
  `CreateNamespace=true`, and the finalizer `resources-finalizer.argocd.argoproj.io` (D-029).
- Workloads that only run during batches (Trino workers, Airflow task pods, Airbyte job pods)
  tolerate the Spot group taint and select it; everything else runs on the On-Demand group.
- Items marked "to verify" in `research.md` are checked during the task that uses them.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel (different files, no dependency on an unfinished task)
- **[Story]**: user story of the task (US1 … US6)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: repository structure, local configuration and CI validation.

- [ ] T001 Create the folders of the plan's structure with a `.gitkeep` where empty: `infra/terraform/{state,data,foundation,bootstrap}/`, `infra/platform/argocd/`, `infra/platform/apps/`, `scripts/verify/`, `.github/workflows/`
- [ ] T002 [P] Create `.env.example` at the repository root listing every `TF_VAR_*` variable with an empty value and a one-line comment each (as `export TF_VAR_name=`): Polaris PostgreSQL password, Polaris root client secret, sample source PostgreSQL password, Trino admin user password, Trino Metabase service user password, Trino external system users (map of user name → password), Trino internal shared secret, Metabase PostgreSQL password, Airflow API server secret key, Airflow admin password, Grafana admin password, SMTP host/port/user/password and alert recipient address (D-024), OpenMetadata admin password; add how to load it in Git Bash (`set -a; source .env; set +a`)
- [ ] T003 [P] Create `.yamllint.yml` at the repository root extending `default`, with `line-length` max 120 and `document-start` disabled
- [ ] T004 [P] Create `.github/workflows/validate.yml` (D-031): on `pull_request` and `push` to `main`; job `terraform`: pinned `hashicorp/setup-terraform`, `terraform fmt -check -recursive infra/terraform`, then for each root module (`state`, `data`, `foundation`, `bootstrap`) `terraform init -backend=false` and `terraform validate`; job `yaml`: `yamllint .` and pinned `kubeconform -strict -summary -schema-location default -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'` on `infra/platform/argocd/` and every `infra/platform/apps/*/manifests/` (Helm `values.yaml` files are excluded); no cloud credential; skip root modules that do not exist yet
- [ ] T005 [P] Create `scripts/verify/lib.sh` with shared Bash helpers sourced by every verify script: `set -euo pipefail`, `AWS_REGION` default `us-east-2`, `CLUSTER_NAME` from the environment, `check "<description>" <command>` printing PASS/FAIL and counting failures, `require_tools aws kubectl terraform`, and a final summary that exits non-zero on any failure
- [ ] T006 Verify arm64 images for every component not yet confirmed in `research.md` (Airbyte, Apache Polaris, OpenMetadata and its ingestion image, OpenCost, AWS Load Balancer Controller, Cluster Autoscaler, the Trino driver for Metabase is a JAR and needs no image) and record the result in the arm64 section of D-007 in `specs/001-data-platform-infra/research.md`; report any gap to the user before Phase 2

**Checkpoint**: CI validates the empty structure; `.env` can be filled from `.env.example`.

---

## Phase 2: Foundational (Step 0: network, cluster, GitOps, teardown)

**Purpose**: the "dry" platform of plan step 0. ⚠️ No user story can start before this phase is
complete.

### 0.0 State and data buckets (applied once, never destroyed)

- [ ] T007 Create `infra/terraform/state/` (`versions.tf`, `main.tf`, `variables.tf`, `outputs.tf`) with local state: one S3 bucket for Terraform state, versioning enabled, SSE-S3 encryption, public access block, `prevent_destroy`; output the bucket name (D-005)
- [ ] T008 Create `infra/terraform/data/` (`versions.tf` with S3 backend key `data/terraform.tfstate` and `use_lockfile = true`, `main.tf`, `variables.tf`, `outputs.tf`): the data bucket as plain resources with SSE-S3, public access block, no lifecycle expiration (FR-008), no `force_destroy`, `lifecycle { prevent_destroy = true }`; provider `default_tags` (`Project`, `Environment = dev`, `Step = 0`); output bucket name and ARN (D-030)
- [ ] T009 Apply `state/` then `data/` after the user's approval; record the state bucket name in the backend configuration of `data/`, `foundation/` and `bootstrap/` (bucket name is not a secret)

### 0.1 Network (`foundation`)

- [ ] T010 Create `infra/terraform/foundation/versions.tf` (pinned Terraform, `aws` provider ≥ 6, S3 backend key `foundation/terraform.tfstate`, `use_lockfile = true`) and `providers.tf` with `default_tags` (`Project`, `Environment = dev`, `Step`) for cost allocation (D-023)
- [ ] T011 Create `infra/terraform/foundation/variables.tf`: `name` (default `data-platform-dev`), `region` (default `us-east-2`), `vpc_cidr`, `kubernetes_version` (default `1.36`), `instance_type` (default `m7g.large`), `data_bucket_name` (output of `data/`), `admin_principal_arns` (IAM principals of the technical team for the access entries)
- [ ] T012 Create `infra/terraform/foundation/network.tf` calling `terraform-aws-modules/vpc/aws` at a pinned version (D-032): 2 AZs (D-003), public and private subnets, public subnets tagged `kubernetes.io/role/elb = 1`, private subnets tagged `kubernetes.io/role/internal-elb = 1`, internet gateway, `single_nat_gateway = true` (D-002), S3 gateway endpoint on the private route tables
- [ ] T013 [P] Create `scripts/verify/0.1-network.sh` implementing the checks of quickstart 0.1 with `scripts/verify/lib.sh` (subnets per AZ, single NAT route, S3 endpoint route, `terraform plan` without changes)

### 0.2 Cluster (`foundation`)

- [ ] T014 Create `infra/terraform/foundation/eks.tf` calling `terraform-aws-modules/eks/aws` at a pinned version (D-032): Kubernetes `var.kubernetes_version` (D-009), public and private endpoint (D-006), `authentication_mode = "API"` with an access entry per `admin_principal_arns` bound to `AmazonEKSClusterAdminPolicy`; add-ons `vpc-cni`, `coredns`, `kube-proxy`, `aws-ebs-csi-driver` (D-015); managed node groups in the private subnets, arm64 AMI, `var.instance_type`: `base` On-Demand (min 1, desired 1, max 3) and `spot` Spot (min 0, desired 0, max 6) with taint `capacity=spot:NoSchedule` and label `capacity=spot`; IMDSv2 with hop limit 2 so pods use the node role (D-004)
- [ ] T015 Create `infra/terraform/foundation/iam.tf` attaching to the single node role (D-004): S3 read/write on the data bucket (`var.data_bucket_name`) and on the tool buckets, the Cluster Autoscaler permissions (Auto Scaling and `eks:DescribeNodegroup`), and the AWS Load Balancer Controller IAM policy (official JSON at a pinned controller version, stored as `infra/terraform/foundation/policies/aws-load-balancer-controller.json`) (D-016b)
- [ ] T016 Create `infra/terraform/foundation/buckets.tf` with the tool buckets as plain resources, SSE-S3, public access block, `force_destroy = true`: Airflow logs (D-020) and Airbyte storage (D-030); outputs for their names
- [ ] T017 Create `infra/terraform/foundation/outputs.tf`: cluster name, endpoint, OIDC issuer, node role ARN, VPC ID, tool bucket names, and the `aws eks update-kubeconfig` command
- [ ] T018 Apply `foundation` after the user's approval and configure `kubectl` with `aws eks update-kubeconfig --name <cluster> --region us-east-2`
- [ ] T019 [P] Create `scripts/verify/0.2-cluster.sh` implementing the checks of quickstart 0.2 (nodes Ready arm64 without public IP, server 1.36, add-ons ACTIVE, PVC on gp3, Cluster Autoscaler adds and removes a node, S3 read with the node role)

### 0.3 GitOps (`bootstrap`) and teardown

- [ ] T020 Create `infra/terraform/bootstrap/versions.tf` (pinned `aws`, `helm`, `kubernetes`, `tls` providers; S3 backend key `bootstrap/terraform.tfstate`, `use_lockfile = true`) and `providers.tf` configuring `helm` and `kubernetes` from `data "aws_eks_cluster"` and `data "aws_eks_cluster_auth"` by cluster name
- [ ] T021 Create `infra/terraform/bootstrap/argocd.tf`: `helm_release` of the `argo-cd` chart (pinned) in namespace `argocd` with reduced resources per N-001 (Dex, notifications and ApplicationSet controllers disabled, one replica each, server without public Service); `helm_release` of the `argocd-apps` chart creating the root Application that syncs `infra/platform/argocd/` from `https://github.com/AndreRosaLopes/eks_on_AWS_OpenSource` branch `main` anonymously (D-008), with automated sync
- [ ] T022 Create `infra/terraform/bootstrap/variables.tf` with every secret variable of `.env.example` marked `sensitive = true`, and `infra/terraform/bootstrap/namespaces.tf` creating the namespaces that receive Secrets before Argo CD syncs (`polaris`, `airbyte`, `sample-source`, `trino`, `airflow`, `metabase`, `observability`, `openmetadata`)
- [ ] T023 [P] Create `infra/platform/argocd/storage.yaml` and `infra/platform/apps/storage/manifests/storageclass-gp3.yaml`: default StorageClass `gp3` (provisioner `ebs.csi.aws.com`, `type: gp3`, `reclaimPolicy: Delete`, `volumeBindingMode: WaitForFirstConsumer`, `tagSpecification_1: "Project=..."` for cost allocation)
- [ ] T024 [P] Create `infra/platform/argocd/cluster-autoscaler.yaml` and `infra/platform/apps/cluster-autoscaler/values.yaml`: upstream chart, `autoDiscovery.clusterName`, `awsRegion: us-east-2`, `expander: least-waste`, scale-down of empty nodes, runs on the base group, image tag matching Kubernetes 1.36 (D-001)
- [ ] T025 Apply `bootstrap` after the user's approval; open Argo CD with `kubectl -n argocd port-forward svc/argocd-server 8080:443` and confirm `storage` and `cluster-autoscaler` are Synced and Healthy
- [ ] T026 Create `scripts/teardown.sh` (D-029), Bash for Git Bash, `set -euo pipefail`, idempotent: (1) show account, Region and cluster and ask for typed confirmation; (2) delete the root Application without cascade; (3) delete the `envoy-gateway` Application with cascade if it exists and wait until no load balancer tagged for the cluster remains; (4) delete every other Application except `aws-load-balancer-controller`, `cluster-autoscaler`, `storage`, with cascade, then the remaining PVCs, and wait until no EBS volume of the cluster remains; (5) delete the remaining Applications; (6) `terraform -chdir=infra/terraform/bootstrap destroy` (interactive); (7) `terraform -chdir=infra/terraform/foundation destroy` (interactive); (8) list load balancers, target groups, volumes, network interfaces, security groups, Elastic IPs and the `/aws/eks/<cluster>` log group left for the cluster and exit non-zero if any; never touches `data/` or `state/`
- [ ] T027 [P] Create `scripts/verify/0.3-gitops.sh` implementing the checks of quickstart 0.3 (bootstrap plan without changes, Argo CD reachable only by port-forward, test Application synced, manual change reverted)
- [ ] T028 Run `scripts/teardown.sh` on the empty platform and re-apply `foundation` and `bootstrap`, after the user's approval, to validate the teardown and the recreation (quickstart Teardown)

**Checkpoint**: step 0 complete; quickstart 0.1–0.3 pass; the teardown leaves only the S3 buckets.

---

## Phase 3: User Story 1 - Ingestion (Priority: P1) 🎯 MVP

**Goal**: the technical team extracts data from APIs, databases and files into the data bucket as
Iceberg tables cataloged by Polaris (FR-007, FR-008).

**Independent Test**: quickstart P1; one sync from the sample PostgreSQL and one from an external
API and a file land as Iceberg tables listed by Polaris; access only through `kubectl
port-forward` (FR-004).

- [ ] T029 [US1] Create `infra/terraform/bootstrap/secrets-p1.tf`: Kubernetes Secrets for the Polaris PostgreSQL password and root client credentials (namespace `polaris`), the sample source PostgreSQL password (`sample-source`), from the sensitive variables (D-011)
- [ ] T030 [P] [US1] Create the Polaris PostgreSQL in `infra/platform/apps/polaris/manifests/postgres.yaml`: StatefulSet (official `postgres` image pinned, arm64) with one gp3 PVC, Service, password from the Secret (D-014)
- [ ] T031 [P] [US1] Create `infra/platform/apps/polaris/values.yaml` for the Apache Polaris chart: relational JDBC persistence on the PostgreSQL of T030, realm and root credentials from the Secret, no public Service; and `infra/platform/apps/polaris/manifests/bootstrap-job.yaml` running the Polaris admin tool bootstrap for the realm (Argo CD hook `PostSync`, idempotent) (D-012, D-014)
- [ ] T032 [US1] Create `infra/platform/apps/polaris/manifests/catalog-job.yaml`: Job (Argo CD `PostSync`) that creates, through the Polaris management API, the catalog pointing at `s3://<data bucket>/` with S3 access through the node role (credential vending behaviour: to verify), and the namespaces `bronze`, `silver`, `gold`; then `infra/platform/argocd/polaris.yaml`
- [ ] T033 [P] [US1] Create the sample source in `infra/platform/apps/sample-source/manifests/`: PostgreSQL StatefulSet with a gp3 PVC, Service, and a ConfigMap with the MovieLens schema and data SQL scripts from the reference project loaded at first start (D-013); then `infra/platform/argocd/sample-source.yaml`
- [ ] T034 [US1] Create `infra/platform/apps/airbyte/values.yaml`: Airbyte chart with its bundled database (D-010), S3 storage on the Airbyte storage bucket using the node role (instance profile; to verify), job pods on the Spot group, no public Service; then `infra/platform/argocd/airbyte.yaml`
- [ ] T035 [US1] Commit and push T029–T034, apply `bootstrap` after the user's approval, and confirm the Polaris, sample source and Airbyte Applications are Synced and Healthy
- [ ] T036 [US1] Through the Airbyte UI (`kubectl port-forward`), configure the S3 Data Lake destination with the Polaris REST catalog and run syncs from: the sample PostgreSQL (internal database), one public HTTP API (external API) and one file over HTTPS (external file); record in `quickstart.md` P1 which sources were used (SC-001)
- [ ] T037 [P] [US1] Create `scripts/verify/p1-ingestion.sh` implementing the checks of quickstart P1 (Applications healthy, bootstrap Job completed, tables listed by Polaris in the data bucket, Secrets present and `git grep` finds no password, no Service of type LoadBalancer in the P1 namespaces)

**Checkpoint**: US1 complete and testable alone (MVP).

---

## Phase 4: User Story 2 - Processing (Priority: P2)

**Goal**: Trino reads and writes the Iceberg tables through Polaris, with workers that exist only
during batches, TLS and access rules (FR-009, FR-006, FR-003).

**Independent Test**: quickstart P2: query over HTTPS with a valid user, masks for the BI user,
workers scaled 0 → 1 → 0 with nodes added and removed.

- [ ] T038 [US2] Create `infra/terraform/bootstrap/trino-tls.tf` (D-028): `tls_private_key` and `tls_self_signed_cert` (validity 1 year, DNS names `trino`, `trino.trino.svc`, `trino.trino.svc.cluster.local`, `localhost`), a Secret in `trino` with the PEM (certificate + key) for Trino, and an output `trino_ca_certificate` (public certificate, not sensitive) for clients
- [ ] T039 [US2] Create `infra/terraform/bootstrap/secrets-trino.tf`: Secret with the password file (bcrypt hashes of the admin, Metabase service and external system users; stable hashes without a diff on every plan: to verify) and the internal shared secret (D-026)
- [ ] T040 [P] [US2] Create `infra/platform/apps/trino/manifests/access-control.yaml`: ConfigMap with the file-based access control rules (`rules.json`): technical team group full access; Metabase service user and external system users read-only on schema `gold` only; column masks and hidden columns for sensitive data (FR-006); and the group file (`group:user1,user2`) (D-026)
- [ ] T041 [US2] Create `infra/platform/apps/trino/values.yaml`: Trino chart, coordinator on the base group, workers 0 on the Spot group with graceful shutdown, HTTPS on the coordinator with the PEM Secret, `http-server.process-forwarded=true` only if routing is HTTP (D-028 impact 4), password file authentication, file-based access control and group provider from T040, Iceberg catalog `iceberg` of type REST pointing at Polaris with OAuth2 client credentials, S3 through the node role; then `infra/platform/argocd/trino.yaml` with `ignoreDifferences` on the worker Deployment `spec.replicas` (D-022)
- [ ] T042 [US2] Commit and push T038–T041, apply `bootstrap` after the user's approval, and confirm the Trino Application is Synced and Healthy with 0 workers
- [ ] T043 [P] [US2] Create `scripts/verify/p2-processing.sh` implementing the checks of quickstart P2 (HTTPS query with a valid user, rejection of HTTP and wrong passwords, Iceberg tables listed, masks and denied schemas for the BI user, workers 0 → 1 → 0 and nodes removed)

**Checkpoint**: US2 complete; dbt runs belong to the data scope (D-021).

---

## Phase 5: User Story 3 - Orchestration (Priority: P3)

**Goal**: Airflow ready to run DAGs from this repository on Spot capacity and to scale the Trino
workers (FR-010, D-020, D-022).

**Independent Test**: quickstart P3: Airflow healthy without idle workers, git-sync running, the
Airflow service account can scale the Trino workers, remote logging configured.

- [ ] T044 [US3] Create `infra/terraform/bootstrap/secrets-airflow.tf`: Secrets for the Airflow API server secret key and admin password (namespace `airflow`)
- [ ] T045 [US3] Create `infra/platform/apps/airflow/values.yaml`: official Airflow chart, `KubernetesExecutor` with task pods on the Spot group, bundled PostgreSQL (D-010), reduced control components per N-001 (triggerer disabled, API server workers 1–2, one DAG processor process), git-sync from this repository branch `main`, path of the DAG folder set by the data scope (default `data-engineering/dags`, README), remote logging to the Airflow logs bucket through the node role, no public Service; then `infra/platform/argocd/airflow.yaml`
- [ ] T046 [P] [US3] Create `infra/platform/apps/airflow/manifests/trino-scaler-rbac.yaml`: Role in namespace `trino` allowing `get`, `patch` and `update` on `deployments/scale` and `deployments` of the Trino workers, and a RoleBinding to the Airflow task pod service account (D-022)
- [ ] T047 [US3] Commit and push T044–T046, apply `bootstrap` after the user's approval, and confirm the Airflow Application is Synced and Healthy
- [ ] T048 [P] [US3] Create `scripts/verify/p3-orchestration.sh` implementing the checks of quickstart P3 (no idle workers, git-sync running, `kubectl auth can-i` as the Airflow service account, scale with that account keeps the Trino Application Synced, remote logging configuration)

**Checkpoint**: US3 infrastructure complete; DAG checks belong to the data scope.

---

## Phase 6: User Story 4 - BI and external systems (Priority: P4)

**Goal**: business users reach Metabase and external systems reach Trino over the internet through
one NLB (FR-012, FR-013; [contracts/](contracts/)).

**Independent Test**: quickstart P4: login page only without login, masked data for business
users, external system query over HTTPS with `SSLVerification=CA`, admin tools not on the NLB.

- [ ] T049 [US4] Create `infra/platform/apps/aws-load-balancer-controller/values.yaml` (`clusterName`, `region`, `vpcId`, runs on the base group, permissions from the node role) and `infra/platform/argocd/aws-load-balancer-controller.yaml` (D-016b)
- [ ] T050 [US4] Create `infra/platform/apps/envoy-gateway/values.yaml` (Envoy Gateway chart with the Gateway API CRDs including the route kind used for Trino; to verify) and `infra/platform/argocd/envoy-gateway.yaml` (D-016)
- [ ] T051 [US4] Create `infra/platform/apps/envoy-gateway/manifests/gateway.yaml`: `EnvoyProxy` with Service annotations for an internet-facing NLB with IP targets created by the AWS Load Balancer Controller and cost allocation tags (`aws-load-balancer-additional-resource-tags`); `GatewayClass`; one `Gateway` with an HTTP listener on the BI port and a TCP (or TLS passthrough) listener on the Trino port; `HTTPRoute` to Metabase and the Trino route to the coordinator HTTPS port (TLS not terminated, D-028)
- [ ] T052 [US4] Create `infra/terraform/bootstrap/secrets-metabase.tf`: Secret for the Metabase PostgreSQL password and a Secret with the Trino CA certificate for Metabase (namespace `metabase`)
- [ ] T053 [P] [US4] Create `infra/platform/apps/metabase/manifests/postgres.yaml`: PostgreSQL StatefulSet with a gp3 PVC and Service for Metabase (D-018)
- [ ] T054 [US4] Create `infra/platform/apps/metabase/manifests/metabase.yaml`: Deployment (official `metabase/metabase` image pinned, arm64, fixed 1 replica, base group), init container downloading the pinned Starburst Trino driver JAR into an `emptyDir` mounted at `/plugins`, database settings from the Secret, Trino CA certificate mounted for the connection; Service; then `infra/platform/argocd/metabase.yaml` (D-018, D-022)
- [ ] T055 [US4] Commit and push T049–T054, apply `bootstrap` after the user's approval; in Metabase create the admin account, the Trino connection with the Metabase service user (`SSL=true`, `SSLVerification=CA`, CA from the Secret) and the business user accounts (FR-012); fill in the BI and Trino port numbers in `contracts/bi-access.md` and `contracts/external-systems.md`
- [ ] T056 [P] [US4] Create `scripts/verify/p4-bi.sh` implementing the checks of quickstart P4 against the NLB DNS name (login page without login, Trino over HTTPS with an external user and `SSLVerification=CA`, rejection of wrong passwords and plain HTTP, no admin interface reachable on the NLB)

**Checkpoint**: US4 complete; contracts verified.

---

## Phase 7: User Story 5 - Observability (Priority: P5)

**Goal**: the technical team sees executions, failures, resource usage and cost, and receives
alerts by email (FR-014, FR-015, D-023, D-024).

**Independent Test**: quickstart P5: Grafana dashboards, test alert email received, OpenCost and
Cost Explorer by tags, no sensitive values in logs or metrics.

- [ ] T057 [US5] Create `infra/terraform/bootstrap/secrets-observability.tf`: Secrets for the Grafana admin password and the Alertmanager SMTP configuration (namespace `observability`) (D-024)
- [ ] T058 [US5] Create `infra/platform/apps/observability/values.yaml`: Prometheus/Grafana/Alertmanager chart with small retention and a gp3 volume for Prometheus, Alertmanager with one email receiver from the Secret, alert rules for pods in crash loop, failed Jobs and failed Airflow tasks; Grafana without public Service; then `infra/platform/argocd/observability.yaml`
- [ ] T059 [US5] Update `infra/platform/apps/airflow/values.yaml` to export Airflow metrics to Prometheus (StatsD exporter and ServiceMonitor) (D-024)
- [ ] T060 [P] [US5] Create `infra/platform/apps/opencost/values.yaml` (OpenCost chart reading the Prometheus of T058, AWS pricing for `us-east-2`) and `infra/platform/argocd/opencost.yaml` (D-023)
- [ ] T061 [P] [US5] Create `infra/terraform/foundation/cost-tags.tf` activating the cost allocation tags `Project`, `Environment` and `Step` with `aws_ce_cost_allocation_tag` (D-023)
- [ ] T062 [US5] Commit and push T057–T061, apply `foundation` and `bootstrap` after the user's approval, and confirm the Applications are Synced and Healthy
- [ ] T063 [P] [US5] Create `scripts/verify/p5-observability.sh` implementing the checks of quickstart P5 (dashboards reachable by port-forward, test alert through Alertmanager, OpenCost cost per namespace, search of logs and metrics for the sample sensitive values returns nothing)

**Checkpoint**: US5 complete.

---

## Phase 8: User Story 6 - Governance (Priority: P6)

**Goal**: catalog, lineage and classification of sensitive data in OpenMetadata, mapped to the
Trino rules (FR-016).

**Independent Test**: quickstart P6: a processed dataset found in the catalog with lineage, its
sensitive column classified and masked by Trino.

- [ ] T064 [US6] Create `infra/platform/apps/opensearch/values.yaml` (OpenSearch 3.x chart, single node, reduced heap, gp3 volume, `vm.max_map_count` init container, internal access only; security plugin setting: to verify) and `infra/platform/argocd/opensearch.yaml` (D-025)
- [ ] T065 [US6] Create `infra/terraform/bootstrap/secrets-openmetadata.tf` (OpenMetadata admin password, namespace `openmetadata`) and `infra/platform/apps/openmetadata/values.yaml`: OpenMetadata ≥ 1.12 chart with its bundled database (D-010), search on the OpenSearch of T064, Kubernetes native ingestion orchestrator with pods on the Spot group, no public Service; then `infra/platform/argocd/openmetadata.yaml`
- [ ] T066 [US6] Commit and push T064–T065, apply `bootstrap` after the user's approval; in OpenMetadata configure the Trino, Airflow and Airbyte connectors and run ingestion and lineage
- [ ] T067 [US6] Classify one sensitive column in OpenMetadata and add the matching mask to `infra/platform/apps/trino/manifests/access-control.yaml` (FR-016, D-026 impact 1)
- [ ] T068 [P] [US6] Create `scripts/verify/p6-governance.sh` implementing the checks of quickstart P6 (Applications healthy, dataset in the catalog with lineage, classified column masked for the BI user)

**Checkpoint**: all user stories complete.

---

## Phase 9: Polish & Cross-Cutting Concerns

- [ ] T069 Update `scripts/teardown.sh` and run it on the full platform after the user's approval; confirm quickstart Teardown (no orphan resource, data bucket kept) and recreate the platform
- [ ] T070 [P] Update `README.md` (structure and setup: `.env`, apply order `state/` → `data/` → `foundation` → `bootstrap`, teardown) and `docs/setup.md` (Terraform, `kubectl`, AWS CLI in Git Bash)
- [ ] T071 [P] Measure memory and CPU of each component in Grafana, set the requests in each `values.yaml`, and update the cost estimate in `plan.md` with measured values (N-001, D-007)
- [ ] T072 Run every `scripts/verify/*.sh` against the full platform and report the results to the user

---

## Dependencies & Execution Order

### Phase dependencies

- **Phase 1 (Setup)**: no dependency.
- **Phase 2 (Step 0)**: depends on Phase 1; blocks every user story.
- **US1 Ingestion**: depends on Phase 2.
- **US2 Processing**: depends on US1 (Polaris catalog and tables).
- **US3 Orchestration**: depends on US2 (Trino workers to scale); Airbyte from US1.
- **US4 BI**: depends on US2 (Trino); independent of US3.
- **US5 Observability**: depends on Phase 2; T059 depends on US3 (Airflow).
- **US6 Governance**: depends on US1–US3 (connectors) and US2 (masks).
- **Phase 9**: depends on every story to deliver.

### Within each story

Secrets in `bootstrap` → plain YAML and values → Argo CD Application → commit, push and apply →
verify script.

### Parallel opportunities

- Phase 1: T002, T003, T004, T005 in parallel.
- Phase 2: verify scripts T013, T019, T027 in parallel with the Terraform work; T023 and T024 in
  parallel.
- US1: T030, T031, T033 in parallel; T037 in parallel with T036.
- US2: T040 in parallel with T038–T039.
- US4: T053 in parallel with T049–T052.
- US5: T060 and T061 in parallel.
- After US2: US4 and US5 can proceed in parallel; US3 can proceed in parallel with US4.

### Parallel example: User Story 1

```text
T030 Polaris PostgreSQL manifest      (infra/platform/apps/polaris/manifests/postgres.yaml)
T031 Polaris values and bootstrap Job (infra/platform/apps/polaris/values.yaml, manifests/bootstrap-job.yaml)
T033 Sample source manifests          (infra/platform/apps/sample-source/manifests/)
```

---

## Implementation Strategy

### MVP first

1. Phase 1 and Phase 2 (step 0, validated with the teardown).
2. US1 Ingestion.
3. Stop and validate with `scripts/verify/p1-ingestion.sh`.

### Incremental delivery

Each story adds its own Argo CD Applications and Secrets and is validated by its verify script
before the next one (plan "Incremental Delivery"). Each apply and each destroy waits for the user's
approval.
