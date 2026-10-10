# Implementation Plan: Data Platform Infrastructure

**Branch**: `001-data-platform-infra` | **Date**: 2026-10-10 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/001-data-platform-infra/spec.md` (with the
clarifications of 2026-10-10); plan input `prompt/003-infra-plan.md`; decisions in
[research.md](research.md).

**Status**: Phase 0 and Phase 1 complete. Every technical choice is decided (D-001 to D-030).
D-016b and D-018 to D-026 were adopted from the recommendations without individual review and are
marked "to re-evaluate" in `research.md`. Facts marked "to verify" in `research.md` are confirmed
at implementation (constitution XII).

## Summary

Infrastructure for a data platform on Kubernetes in AWS (`us-east-2`), portable to Azure and GCP,
running 24/7 and brought up incrementally: step 0 (network, cluster, GitOps) "dry", then one step
per functionality (P1 Ingestion → P6 Governance). Cloud resources are created with Terraform; every
in-cluster component is delivered by Argo CD from this public repository using upstream Helm
charts with minimal values.

## Technical Context

**Language/Version**: Terraform (HCL) for cloud resources; YAML for Argo CD Applications, Helm
values and own Kubernetes resources; a GitHub Actions workflow builds the dbt image (D-021). Every
version is pinned at implementation to the newest stable release, verified per constitution XII.

**Primary Dependencies** (decision in parentheses):
- Platform: Amazon EKS 1.36 (D-009), Cluster Autoscaler (D-001), EBS CSI driver as EKS add-on
  (D-015), Argo CD.
- P1: Airbyte with S3 Data Lake destination (Iceberg), Apache Polaris with own PostgreSQL (D-012,
  D-014), sample PostgreSQL source (D-013).
- P2: Trino reading Iceberg through Polaris; self-signed TLS on Trino from the Terraform `tls`
  provider (D-017, D-028); password file authentication and file-based access control (D-026).
- P3: Airflow with KubernetesExecutor and remote logging to S3 (D-020); DAGs by git-sync; dbt as
  one pod per run (`KubernetesPodOperator`, `dbt build`) from a dbt-trino image built by GitHub
  Actions into GitHub Container Registry (D-021); Airflow scales Trino workers around the batch
  (D-022).
- P4: Envoy Gateway (D-016) behind one NLB created by the AWS Load Balancer Controller (D-016b);
  Metabase open source with own PostgreSQL and the Trino driver from an init container (D-018);
  external systems use Trino directly, one Trino user each (D-019).
- P5: Prometheus/Grafana with Alertmanager → email (D-024); Airflow metrics in Prometheus;
  OpenCost plus AWS cost allocation tags (D-023).
- P6: OpenMetadata ≥ 1.12 with its bundled database (D-010) and OpenSearch 3.x (D-025).

**Storage**:
- S3 for platform data, Iceberg tables only, catalog in Polaris; kept with no time limit (FR-008).
  The data bucket is in its own persistent root module `data/`, never destroyed by the teardown
  (D-030).
- S3 for Airflow task logs (D-020) and Airbyte storage, in `foundation`, deleted with the
  environment (D-030); Terraform state in S3 with native lock file (D-005).
- In-cluster PostgreSQL on EBS gp3: bundled in each chart (D-010), own plain YAML for Polaris
  (D-014) and Metabase (D-018), the sample source (D-013). No backup of any tool database (D-027,
  FR-018): after a loss, tables are recreated by reloading from the sources.

**Testing**: `terraform fmt`, `terraform validate`, reviewed `terraform plan` (constitution XI);
acceptance checks per checkpoint in `scripts/verify/`, described in [quickstart.md](quickstart.md).

**Apply and teardown order**: `state/` (once) → `data/` (once) → `foundation` → `bootstrap`. The
teardown is `scripts/teardown.sh` (D-029): Argo CD Applications deleted with cascade in order (the
`Gateway` and its NLB first, then the workloads and their EBS volumes, then the controllers),
`terraform destroy` in `bootstrap` and `foundation` (interactive), and a final check for orphan
cloud resources. `data/` and `state/` are never destroyed.

**Target Platform**: Amazon EKS 1.36, `us-east-2`, 2 Availability Zones (D-003); m7g.large
(Graviton, arm64) in an On-Demand base group and a Spot group (D-001, D-007); one zonal NAT gateway
(D-002); public API endpoint with IAM + RBAC (D-006); every image published for arm64.

**Project Type**: Infrastructure as code and GitOps delivery (no application code in this
feature; DAGs and the dbt project belong to the data scope).

**Performance Goals**: previous day's data available by 08:00 Brasília time (FR-011, SC-002);
growth from 1 GB/day up to about 1 TB/day without redesign (FR-017); up to 10 BI users (FR-012).

**Constraints**: single `dev` environment; platform on 24/7; BI required on weekdays 08:00–18:00
Brasília time and kept on 24/7 (D-022); cost tends to zero when idle for what scales; portability
across AWS, Azure and GCP; encryption only where it adds no cost (TLS only on Trino); no secrets in
Git (`.env`, D-011).

**Scale/Scope**: six functionalities (P1–P6), delivered after a step 0 foundation.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design (2026-10-10).*

| Principle | Status | Notes |
|---|---|---|
| I. Single Environment | ✅ Pass | Only `dev` |
| II. Scalability with Cost Tending to Zero | ⚠️ Justified | Platform on 24/7 (clarification 2026-10-10): the always-on base has a fixed cost; after the teardown (D-029) only S3 remains billed (data and state, D-030). What scales goes towards zero: nodes (Cluster Autoscaler, Spot), Trino workers (Airflow), task, sync and dbt pods. "State" read as platform data in S3; tool databases in the cluster without backup (D-010, D-027, user's choices). See Complexity Tracking |
| III. Simplicity First | ✅ Pass | No KEDA, no cert-manager, no backup tool, no custom Airflow image |
| IV. No Secrets in Git | ✅ Pass | `.env` → Terraform variables → Kubernetes Secrets (D-011); Trino key from the `tls` provider, also only in state (D-028) |
| V. Infrastructure as Code | ✅ Pass | All cloud resources in Terraform; NLB, volumes and nodes created by controllers (exception) |
| VI. GitOps for the Cluster | ⚠️ Justified | EKS core add-ons by Terraform (D-015); Trino worker replicas changed by Airflow at run time and ignored by Argo CD (D-022). See Complexity Tracking |
| VII. Separate Applies | ✅ Pass | `foundation` and `bootstrap` root modules, separate state keys; plus `state/` and the persistent `data/` module (D-030) |
| VIII. Cloud Portability | ⚠️ Justified | AWS Load Balancer Controller is an AWS-only in-cluster component (D-016b); cloud-specific values in Cluster Autoscaler and OpenCost. See Complexity Tracking |
| IX. Node-Level Cloud Permissions | ✅ Pass | Single node role, extended with S3 (data, Airflow logs) and the AWS Load Balancer Controller policy |
| X. Pinned Versions | ✅ Pass | Kubernetes 1.36; charts, images and providers pinned at implementation |
| XI. Verified Changes | ✅ Pass | `fmt`/`validate`/`plan`; `scripts/verify/`; apply and destroy only with approval; `scripts/teardown.sh` asks for confirmation and runs `terraform destroy` interactively (D-029) |
| XII. Verified Decisions | ✅ Pass | Sources per decision in `research.md`; items marked "to verify" confirmed at implementation |
| XIII. Simple Kubernetes Delivery | ✅ Pass | Upstream charts with minimal values; Metabase has no maintained upstream chart, so it is plain YAML; own resources plain YAML |

## Incremental Delivery

| Step | Content | Validation |
|---|---|---|
| 0.1 Network | Persistent `data/` module with the S3 data bucket (D-030); VPC in 2 AZs, public and private subnets (public tagged `kubernetes.io/role/elb`), internet gateway, one zonal NAT gateway, S3 gateway endpoint | [quickstart.md](quickstart.md) 0.1 |
| 0.2 Cluster | EKS 1.36, public + private endpoint, access entries, single node role, core add-ons (VPC CNI, CoreDNS, kube-proxy, EBS CSI), On-Demand base group, Spot group (min 0), Cluster Autoscaler, gp3 StorageClass; `default_tags` for cost allocation (D-023) | quickstart 0.2 |
| 0.3 GitOps | `bootstrap` apply installs Argo CD; root Application reads `infra/platform/argocd/`; every Application carries the cascade deletion finalizer (D-029); `scripts/teardown.sh` validated on the empty platform | quickstart 0.3 |
| P1 Ingestion | Uses the S3 data bucket from `data/` (D-030); Airbyte storage bucket; Polaris + own PostgreSQL; Airbyte (bundled database, S3 storage, S3 Data Lake destination as Iceberg); sample source PostgreSQL; Secrets from `.env` | quickstart P1 |
| P2 Processing | Trino (coordinator always on, workers 0 by default) with the Iceberg catalog on Polaris; self-signed TLS (Terraform `tls`, D-028); password file and group file; file-based access control (D-026); dbt-trino image workflow in GitHub Actions → GHCR (D-021) | quickstart P2 |
| P3 Orchestration | Airflow (KubernetesExecutor, reduced control components per N-001, git-sync, remote logging to an S3 bucket); daily DAG pattern: scale Trino workers up → Airbyte sync → dbt pod → scale workers to zero, finished before 08:00 Brasília time | quickstart P3 |
| P4 BI and external systems | AWS Load Balancer Controller; Envoy Gateway with one `Gateway` (one NLB): HTTP listener for Metabase, TCP/TLS passthrough listener for Trino; Metabase + own PostgreSQL; Trino users for BI (one service user) and per external system; contracts in [contracts/](contracts/) | quickstart P4 |
| P5 Observability | Prometheus, Grafana, Alertmanager (email receiver, SMTP credential from `.env`); Airflow metrics; OpenCost; cost allocation tags activated | quickstart P5 |
| P6 Governance | OpenSearch 3.x single node; OpenMetadata ≥ 1.12 (bundled database, Kubernetes native orchestrator); connectors to Trino, Airflow, Airbyte; classification of sensitive data mapped by hand to the Trino rules | quickstart P6 |

Cross-cutting services are added with the first functionality that needs them: the public entry
(Gateway, load balancer controller) in P4, platform observability in P5. Each step is an
independent set of Argo CD Applications (and Terraform resources where needed) and can be removed
without affecting the previous ones.

### Monthly cost estimate (`us-east-2`, On-Demand list prices, 24/7; to be confirmed by measurement)

Memory is converted at ≈ US$ 7.4 per GiB-month (m7g.large: US$ 0.0816/h for 8 GiB); actual cost
depends on how pods pack into whole nodes. Component memory figures are starting estimates.

| Step | Items | Month (730 h) |
|---|---|---|
| 0 | EKS control plane US$ 73.00; NAT US$ 32.85 + public IPv4 US$ 3.65; 1 × m7g.large US$ 59.57 (Argo CD, Cluster Autoscaler, system pods) | ≈ US$ 169 |
| P1 | ≈ 1 more m7g.large (Airbyte, Polaris and databases); gp3 ≈ 30 GB (US$ 0.08/GB-month); S3 | ≈ US$ 62 |
| P2 | Trino coordinator ≈ 2 GiB; workers only during the batch (e.g., 4 GiB × 1 h/day ≈ US$ 1.2) | ≈ US$ 16 |
| P3 | Airflow reduced control components ≈ 3–4 GiB + database; task and dbt pods on demand; S3 logs | ≈ US$ 25–30 |
| P4 | NLB US$ 16.43 + 2 public IPv4 US$ 7.30 + LCU; Envoy Gateway and AWS Load Balancer Controller ≈ 0.5 GiB; Metabase ≈ 1–2 GiB + PostgreSQL | ≈ US$ 37–45 + data transfer out (US$ 0.09/GB) |
| P5 | Prometheus ≈ 1–2 GiB, Grafana, Alertmanager, exporters, OpenCost; Prometheus volume ≈ 20 GB | ≈ US$ 13–21 |
| P6 | OpenMetadata ≈ 2 GiB, OpenSearch ≈ 2 GiB, database; volumes ≈ 20 GB | ≈ US$ 32–35 |
| **Total** | | **≈ US$ 355–380** |

Not included: data processed by the NAT (US$ 0.045/GB), node root volumes, S3 requests, Spot
savings. S3 storage grows with retention without limit (FR-008): ≈ US$ 0.70 more per month for
each month at 1 GB/day; ≈ US$ 700 more per month for each month at 1 TB/day.

After the teardown (D-029), only the data bucket (US$ 0.023/GB-month, S3 Standard) and the state
bucket (cents) remain billed.

## Project Structure

### Documentation (this feature)

```text
specs/001-data-platform-infra/
├── spec.md
├── plan.md              # This file
├── research.md          # Decisions D-001 to D-030 (Phase 0)
├── quickstart.md        # Validation per checkpoint (Phase 1)
├── contracts/           # BI access and external systems interface (Phase 1)
├── checklists/
└── tasks.md             # Phase 2 output (/speckit-tasks)
```

`data-model.md` is not created: this feature has no data model (data modeling belongs to the data
scope); the inventory of infrastructure resources is the structure below.

### Source Code (repository root)

```text
infra/
├── terraform/
│   ├── modules/              # network, eks, node-groups, s3 (cloud-specific layer)
│   ├── state/                # one-time creation of the state bucket (local state)
│   ├── data/                 # persistent: S3 data bucket, never destroyed (D-030)
│   ├── foundation/           # apply 1: VPC, EKS, node groups, core add-ons, node role, tool S3 buckets
│   └── bootstrap/            # apply 2: Argo CD, root Application, Secrets from .env, Trino TLS
└── platform/
    ├── argocd/               # one Application per component
    └── apps/
        ├── cluster-autoscaler/        # values.yaml
        ├── storage/                   # gp3 StorageClass (plain YAML)
        ├── polaris/                   # values.yaml + own PostgreSQL + bootstrap Job
        ├── airbyte/                   # values.yaml
        ├── sample-source/             # PostgreSQL + MovieLens SQL scripts (plain YAML)
        ├── trino/                     # values.yaml + access rules and group file (plain YAML)
        ├── airflow/                   # values.yaml
        ├── aws-load-balancer-controller/  # values.yaml
        ├── envoy-gateway/             # values.yaml + Gateway, routes (plain YAML)
        ├── metabase/                  # Deployment + own PostgreSQL (plain YAML)
        ├── observability/             # Prometheus/Grafana/Alertmanager values.yaml
        ├── opencost/                  # values.yaml
        ├── opensearch/                # values.yaml
        └── openmetadata/              # values.yaml
.github/
└── workflows/                # dbt-trino image build → GHCR (D-021)
scripts/
├── teardown.sh               # ordered teardown without orphan resources (D-029)
└── verify/                   # acceptance checks per checkpoint
```

**Structure Decision**: the layout follows the README's planned structure and the plan input's
Kubernetes delivery structure (`infra/platform/argocd/`, `infra/platform/apps/<component>/`). The
location of the DAGs and the dbt project is set by the data scope; the infrastructure only points
git-sync and the image workflow to it.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|---|---|---|
| VI: EKS core add-ons installed by Terraform, not Argo CD | They must exist before Argo CD can run (pod network, DNS) and the EBS CSI driver is packaged by AWS for the EKS version (D-015) | Installing them through Argo CD is impossible for the network and DNS add-ons |
| VI: Trino worker replicas changed by Airflow at run time | Workers exist only during the batch (D-022, constitution II) | Fixed workers cost ≈ US$ 30/month idle; KEDA rejected by the user (simplicity) |
| VIII: AWS Load Balancer Controller (AWS-only in-cluster component) | Recommended by AWS; the legacy controller only receives critical fixes (D-016b) | The legacy controller avoids the component but is legacy; switching clouds removes the chart and the annotations only |
| II: always-on base cost (platform on 24/7) | Daily update runs unattended (clarification 2026-10-10) | Turning the platform off between sessions was rejected by the user |
