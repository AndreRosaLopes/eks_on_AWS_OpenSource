Technical context for the plan of `specs/001-data-platform-infra`.

Decided (source):
- Infrastructure as code with Terraform; in-cluster components delivered by Argo CD (GitOps);
  cloud resources and cluster bootstrap in separate applies (constitution V–VII).
- Kubernetes as the platform.
- Cloud: AWS, region `us-east-2` (user decision).
- Portability across AWS, Azure and GCP with minimal lock-in (constitution VIII, spec FR-002).
- Single `dev` environment (constitution I).
- Ingestion: Airbyte (user decision).
- Processing: Trino, with dbt as auxiliary (user decision).
- Orchestration: Airflow (user decision).
- Storage: S3, with Iceberg tables only (user decision).
- Iceberg catalog: Apache Polaris (user decision).
- Governance: OpenMetadata ≥ 1.12 with its Kubernetes native orchestrator (user decision).
- Platform observability: Prometheus/Grafana (user decision).
- Public access for BI and external systems: in-cluster Gateway API controller exposed by one
  L4 load balancer (user decision); admin interfaces via `kubectl port-forward`.

Open technical choices (not decided by the user):
- Every other tool or service the plan needs.

For each open technical choice: research the options, present them to the user with their
trade-offs, and wait for the user's choice before recording the decision. Verify every technical
choice per constitution XII (official documentation, MCP servers, skills).

Record each decision in `research.md` with:
- Decision: what was chosen.
- Options considered.
- Trade-offs: advantages and disadvantages of each option.
- Rationale: why this option was chosen.
- Chosen by: the user, with the date.
- Sources.

Incremental delivery:
- Step 0 (foundation, no data functionality): bring up the infrastructure "dry", in three
  checkpoints, each validated with a test workload before the next:
  0.1 network; 0.2 Kubernetes cluster; 0.3 GitOps delivery.
- Then one step per functionality, in the spec's priority order (P1 Ingestion → P6 Governance).
- Each cross-cutting service (e.g., public entry point, platform scaling, platform
  observability) is added with the first functionality that needs it, not in step 0.
- Each step can be deployed and removed without affecting the previous ones.
- Estimate the monthly cost of step 0 and of each following step.

Kubernetes delivery structure:
- One Argo CD Application per component, in `infra/platform/argocd/`.
- Values file and own resources of each component in `infra/platform/apps/<component>/`.
- The same structure for every component.
