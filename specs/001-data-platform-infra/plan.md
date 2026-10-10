# Implementation Plan: Data Platform Infrastructure

**Branch**: `001-data-platform-infra` | **Date**: 2026-10-09 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/001-data-platform-infra/spec.md`; plan input
`prompt/003-infra-plan.md`; decisions in [research.md](research.md).

**Status**: In progress. Phase 0 is complete for step 0 and P1 (decisions D-001 to D-015); the
open technical choices of P2 to P6 are still `NEEDS CLARIFICATION`.

## Summary

Infrastructure for a data platform on Kubernetes in AWS (`us-east-2`), portable to Azure and GCP,
brought up incrementally: step 0 (network, cluster, GitOps) "dry", then one step per
functionality (P1 Ingestion → P6 Governance). Cloud resources are created with Terraform; every
in-cluster component is delivered by Argo CD from this public repository using upstream Helm
charts with minimal values.

## Technical Context

**Language/Version**: Terraform (HCL) for cloud resources; YAML for Argo CD Applications, Helm
values and own Kubernetes resources. Every version is pinned at implementation to the newest
stable release, verified per constitution XII.

**Primary Dependencies**:
- Decided (plan input): Terraform, Argo CD, Kubernetes, Airbyte, Trino, dbt, Airflow, Apache
  Polaris, OpenMetadata ≥ 1.12, Prometheus/Grafana, an in-cluster Gateway API controller behind
  one L4 load balancer.
- Decided (research): Amazon EKS 1.36 (D-009) with Cluster Autoscaler (D-001); EBS CSI driver as
  an EKS managed add-on (D-015).
- NEEDS CLARIFICATION (P2–P6): Gateway API controller implementation, TLS certificates and domain,
  BI tool, interface for external systems, Airflow executor, workload scale-to-zero mechanism,
  cost visibility, alert channel, and the other components the later steps need.

**Storage**:
- S3 for platform data, Iceberg tables only, catalog in Polaris (D-012); Terraform state in S3
  with native lock file (D-005).
- In-cluster PostgreSQL on EBS gp3 volumes: the database bundled in each Helm chart (D-010); an own
  plain-YAML PostgreSQL for Polaris (D-014); the sample source database (D-013).

**Testing**: `terraform fmt`, `terraform validate`, reviewed `terraform plan` (constitution XI);
acceptance checks per checkpoint in `scripts/verify/`, described in [quickstart.md](quickstart.md).

**Target Platform**: Amazon EKS 1.36, `us-east-2`, 2 Availability Zones (D-003); nodes m7g.large
(Graviton, arm64) in an On-Demand base group and a Spot group (D-001, D-007); one zonal NAT
gateway (D-002); public API endpoint with IAM + RBAC (D-006).

**Project Type**: Infrastructure as code and GitOps delivery (no application code in this
feature).

**Performance Goals**: daily batch updates, no streaming (FR-011); growth from 1 GB/day up to
about 1 TB/day without redesign (FR-017); up to 10 BI users (FR-012).

**Constraints**: single `dev` environment; capacity scales with demand and cost tends to zero
when idle; portability across AWS, Azure and GCP; encryption only where it adds no cost; no
secrets in Git (passwords from a local `.env`, D-011).

**Scale/Scope**: six functionalities (P1–P6), delivered after a step 0 foundation.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|---|---|---|
| I. Single Environment | ✅ Pass | Only `dev` |
| II. Scalability with Cost Tending to Zero | ✅ Pass | Cluster Autoscaler, Spot group (D-001). "State" read as platform data in S3; tool databases run in the cluster (D-010, user's reading) |
| III. Simplicity First | ✅ Pass | Simplest options chosen in D-001 to D-015 |
| IV. No Secrets in Git | ✅ Pass | `.env` → Terraform variables → Kubernetes Secrets (D-011); public repository scanned (D-008) |
| V. Infrastructure as Code | ✅ Pass | All cloud resources in Terraform; controller-created resources (volumes, load balancer, nodes) allowed by the exception |
| VI. GitOps for the Cluster | ⚠️ Justified | EKS core add-ons (VPC CNI, CoreDNS, kube-proxy, EBS CSI) are installed by Terraform, not Argo CD (D-015); see Complexity Tracking |
| VII. Separate Applies | ✅ Pass | `foundation` and `bootstrap` root modules, separate state keys (D-005) |
| VIII. Cloud Portability | ✅ Pass | AWS-specific parts confined to Terraform modules and annotations; S3 accessed through the cloud-specific layer |
| IX. Node-Level Cloud Permissions | ✅ Pass | Single node role (D-004) |
| X. Pinned Versions | ✅ Pass | Kubernetes 1.36; every other version pinned at implementation |
| XI. Verified Changes | ✅ Pass | `fmt`/`validate`/`plan`; `scripts/verify/`; apply and destroy only with approval |
| XII. Verified Decisions | ✅ Pass | Sources recorded per decision in `research.md` |
| XIII. Simple Kubernetes Delivery | ✅ Pass | Upstream charts with minimal values; own resources as plain YAML (Polaris PostgreSQL, sample source, StorageClass) |

## Incremental Delivery

| Step | Content | Validation |
|---|---|---|
| 0.1 Network | VPC in 2 AZs, public and private subnets, internet gateway, one zonal NAT gateway, S3 gateway endpoint | [quickstart.md](quickstart.md) 0.1 |
| 0.2 Cluster | EKS 1.36, public + private endpoint, access entries, single node role, core add-ons (VPC CNI, CoreDNS, kube-proxy, EBS CSI), On-Demand base group (m7g.large), Spot group (min 0), Cluster Autoscaler, gp3 StorageClass | quickstart 0.2 |
| 0.3 GitOps | `bootstrap` apply installs Argo CD; root Application reads `infra/platform/argocd/` from the public repository | quickstart 0.3 |
| P1 Ingestion | S3 buckets; Polaris + its PostgreSQL (D-012, D-014); Airbyte with its bundled PostgreSQL, S3 storage, S3 Data Lake destination (Iceberg); sample source PostgreSQL (D-013); Secrets from `.env` | quickstart P1 |
| P2–P6 | To be planned after their decisions | — |

Cross-cutting services (public entry point, platform observability) are added with the first
functionality that needs them. The Cluster Autoscaler is part of step 0.2, because the node groups
depend on it.

### Cost estimate (`us-east-2`, On-Demand list prices; to be confirmed by measurement)

| Step | Items | Per hour | 6-hour lab session | Month (730 h) |
|---|---|---|---|---|
| 0 | EKS control plane US$ 0.10/h; NAT US$ 0.045/h + public IPv4 US$ 0.005/h; 1 × m7g.large US$ 0.0816/h | ≈ US$ 0.23 | ≈ US$ 1.39 | ≈ US$ 169 |
| P1 (added) | 1 more m7g.large (estimate for Airbyte, Polaris and databases); gp3 volumes ≈ 30 GB (US$ 0.08/GB-month); S3 (small) | ≈ US$ 0.085 | ≈ US$ 0.51 | ≈ US$ 62 |

Data processed by the NAT (US$ 0.045/GB), node root volumes and S3 requests are not included.

## Project Structure

### Documentation (this feature)

```text
specs/001-data-platform-infra/
├── spec.md
├── plan.md              # This file
├── research.md          # Decisions D-001 to D-015 (Phase 0)
├── quickstart.md        # Validation per checkpoint (Phase 1)
├── contracts/           # Created at P4 (BI and external systems)
├── checklists/
└── tasks.md             # Phase 2 output (/speckit-tasks)
```

`data-model.md` is not created: this feature has no data model (data modeling belongs to the data
scope); the inventory of infrastructure resources is the structure below.

### Source Code (repository root)

```text
infra/
├── terraform/
│   ├── modules/              # network, eks, node-groups, s3, state (cloud-specific layer)
│   ├── state/                # one-time creation of the state bucket (local state)
│   ├── foundation/           # apply 1: VPC, EKS, node groups, core add-ons, node role, S3 buckets
│   └── bootstrap/            # apply 2: Argo CD, root Application, Kubernetes Secrets from .env
└── platform/
    ├── argocd/               # one Application per component
    └── apps/
        ├── cluster-autoscaler/   # values.yaml
        ├── storage/              # gp3 StorageClass (plain YAML)
        ├── airbyte/              # values.yaml
        ├── polaris/              # values.yaml + own PostgreSQL (plain YAML) + bootstrap Job
        └── sample-source/        # PostgreSQL + MovieLens SQL scripts (plain YAML)
scripts/
└── verify/                   # acceptance checks per checkpoint
```

**Structure Decision**: the layout follows the README's planned structure and the plan input's
Kubernetes delivery structure (`infra/platform/argocd/`, `infra/platform/apps/<component>/`).

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|---|---|---|
| VI: EKS core add-ons installed by Terraform, not Argo CD | They must exist before Argo CD can run (pod network, DNS) and the EBS CSI driver is packaged by AWS for the EKS version (D-015) | Installing them through Argo CD is impossible for the network and DNS add-ons, and adds one more Application for EBS CSI |
