# Research: Data Platform Infrastructure

**Feature**: `001-data-platform-infra` | **Date**: 2026-10-09 | **Plan input**: `prompt/003-infra-plan.md`

Each open technical choice is researched here before the user decides. A decision stays
**Pending** until the user chooses; then the entry records the choice, the rationale and who
chose it.

Prices are on-demand list prices in USD; a month is 730 hours. AWS prices are for `us-east-2`
(US East, Ohio) and come from the AWS Price List API.

## Decided by the user (from the plan input)

| Topic | Decision |
|---|---|
| Infrastructure as code / delivery | Terraform; Argo CD (GitOps); separate applies |
| Platform | Kubernetes |
| Cloud and region | AWS, `us-east-2` |
| Ingestion | Airbyte |
| Processing | Trino, with dbt as auxiliary |
| Orchestration | Airflow |
| Storage and table format | S3, Iceberg tables only |
| Iceberg catalog | Apache Polaris |
| Governance | OpenMetadata ≥ 1.12 with its Kubernetes native orchestrator |
| Platform observability | Prometheus/Grafana |
| Public access | In-cluster Gateway API controller behind one L4 load balancer |

## Step 0 decisions

| ID | Decision | Status |
|---|---|---|
| D-001 | Kubernetes on AWS and node scaling | Decided: C. EKS + Cluster Autoscaler |
| D-002 | Outbound internet access for private subnets | Decided: A. One zonal NAT gateway |
| D-003 | Number of Availability Zones | Decided: A. 2 AZs |
| D-004 | Cloud permissions per workload | Decided: C. Single node role |

---

## D-001 Kubernetes on AWS and node scaling

**Status**: Decided

### Context

- Spec FR-003: every functionality scales with demand, with cost tending to zero.
- Spec FR-011: data is updated daily, with no streaming (batch workloads).
- Spec FR-017: growth up to 1000x (about 1 TB per day) without redesign.
- Spec FR-002 and constitution VIII: interchangeable across AWS, Azure and GCP, minimal lock-in.
- Constitution II (scalability, cost tending to zero), III (simplicity), VI (GitOps), XIII
  (upstream Helm charts).
- Step 0.2 of the incremental delivery: the cluster must run "dry" before any functionality.

All options use Amazon EKS (managed control plane). The choice is **who creates and removes the
worker nodes** (the EC2 instances where pods run).

### Options

**A. EKS + Karpenter**
- What it is: an open source node provisioner (core project under Kubernetes SIG Autoscaling).
- How it works: watches pods that cannot be scheduled and launches, at that moment, the
  instance type that fits them (On-Demand or Spot); removes idle nodes and replaces underused
  ones by cheaper ones (consolidation).
- What you install: the Karpenter Helm chart (via Argo CD); an SQS queue and EventBridge rules
  for Spot interruption handling (Terraform); a small fixed node group or Fargate for the
  Karpenter controller, which must not run on nodes it manages; `NodePool` and `EC2NodeClass`
  objects.

**B. EKS Auto Mode**
- What it is: an EKS operating mode where AWS manages the nodes.
- How it works: a custom Karpenter run by AWS (not the open source one) provisions Bottlerocket
  nodes; nodes live at most 21 days; no SSH access. AWS also runs, as managed components, VPC
  CNI, kube-proxy, EBS CSI driver, CoreDNS and AWS Load Balancer Controller.
- What you install: nothing for nodes; you create Auto Mode objects (`NodeClass`
  `eks.amazonaws.com/v1`, StorageClass with provisioner `ebs.csi.eks.amazonaws.com`,
  `IngressClassParams`).
- Adds a management fee per instance on top of the EC2 price, not reduced by Spot, Savings
  Plans or Reserved Instances.

**C. EKS + Cluster Autoscaler**
- What it is: the Kubernetes project's open source autoscaler (`kubernetes/autoscaler`).
- How it works: increases or decreases the size of **node groups defined in advance**, when
  pods cannot be scheduled or nodes stay idle. Each node group has fixed instance types and one
  capacity type (On-Demand or Spot).
- What you install: the Cluster Autoscaler Helm chart (via Argo CD) and the node groups
  (Terraform), e.g., one On-Demand group for the stable base and one Spot group for
  interruptible jobs.

### Cost per option (reference scenario)

Scenario for comparison only, not the project sizing: **2 general-purpose nodes (2 vCPU,
8 GiB) running all month (730 h)**, AWS `us-east-2`.

| Item | A. Karpenter | B. Auto Mode | C. Cluster Autoscaler |
|---|---|---|---|
| EKS control plane (US$ 0.10/h) | US$ 73.00 | US$ 73.00 | US$ 73.00 |
| 2 × m6i.large (US$ 0.096/h each) | US$ 140.16 | US$ 140.16 | US$ 140.16 |
| Fixed node for the Karpenter controller (t4g.small, US$ 0.0168/h) | US$ 12.26 | — | — |
| Auto Mode fee (m6i.large: US$ 0.01152/h per node) | — | US$ 16.82 | — |
| **Total per month** | **US$ 225.42** | **US$ 229.98** | **US$ 213.16** |
| **Each additional node** | + US$ 70.08 | + US$ 78.49 (+12%) | + US$ 70.08 |

- A: small fixed extra cost, then EC2 only; the most efficient packing and Spot use.
- B: about 12% on all compute, so the fee grows with the data volume (FR-017).
- C: the lowest fixed cost; node types are fixed per group, so packing is less efficient than
  A. For daily batch workloads (FR-011) the difference is small, and groups can scale to zero
  when idle.

### The same scenario in the other clouds (if the platform moves)

| Option | Equivalent | Control plane/month | 2 nodes (2 vCPU, 8 GiB)/month | Total/month |
|---|---|---|---|---|
| A | AKS Standard + Node Auto-Provisioning (Karpenter run by Azure) | US$ 73.00 | D2s_v5 US$ 0.096/h → US$ 140.16 | ≈ US$ 213 |
| A | GKE Standard + node auto-provisioning (no Karpenter provider maintained by Google) | US$ 73.00; the US$ 74.40 monthly credit covers a zonal cluster | n2-standard-2 US$ 0.097/h → US$ 141.80 (region not confirmed) | ≈ US$ 142 zonal / US$ 215 regional |
| B | AKS Automatic | US$ 0.16/h → US$ 116.80 | US$ 140.16 + "Automatic General Purpose" fee US$ 0.007841/h (unit per VM or per vCPU not clear) | ≈ US$ 268–280 |
| B | GKE Autopilot | Covered by the credit | Billed per pod requests, not nodes: 4 vCPU + 16 GiB → ≈ US$ 187 (us-west8 rates; us-east5 not confirmed) | ≈ US$ 187 |
| C | AKS Standard, cluster autoscaler built in | US$ 73.00 | US$ 140.16 | ≈ US$ 213 |
| C | GKE Standard, cluster autoscaler built in | US$ 73.00; the credit covers a zonal cluster | US$ 141.80 | ≈ US$ 142 zonal / US$ 215 regional |

Machines cost about the same in the three clouds (≈ US$ 0.096/h for 2 vCPU, 8 GiB); the
difference is the control plane fee and the fee of the "automatic" modes.

### What changes when moving to another cloud

| Item | A. Karpenter | B. Auto Mode | C. Cluster Autoscaler |
|---|---|---|---|
| Node configuration | `EC2NodeClass` → `AKSNodeClass` (Azure; `NodePool` unchanged); GCP: replace with the native autoscaler | `NodeClass` (`eks.amazonaws.com/v1`) → `AKSNodeClass` (AKS Automatic) or none (GKE Autopilot) | Node groups → AKS/GKE node pools with the built-in autoscaler |
| Storage (StorageClass) | EBS driver → Azure Disk / Persistent Disk | Auto Mode-only provisioner (`ebs.csi.eks.amazonaws.com`) → Azure Disk / Persistent Disk | Same as A |
| Public entry (L4 load balancer) | Service annotations | Auto Mode-specific annotations | Same as A |
| Core components (pod network, DNS, disk driver, LB controller) | Installed by you, in Git (Argo CD) | Run by AWS, outside Git and Argo CD | Installed by you, in Git (Argo CD) |
| Constraints on workloads in the target | None new | GKE Autopilot: vCPU:memory ratio 1:1 to 1:6.5, billing per pod request, restrictions on privileged pods | None new |
| Autoscaler in the target | Azure: managed Karpenter; GCP: different tool | Different "automatic" mode per cloud | The same tool, built into AKS and GKE |

All options change the node, storage and load balancer settings when moving. B also moves
components that AWS ran outside Git into Git, uses Auto Mode-only APIs, and lands on
"automatic" modes that behave differently (GKE Autopilot has no nodes). C keeps the same
autoscaler in the three clouds.

### Trade-offs

| | A. Karpenter | B. Auto Mode | C. Cluster Autoscaler |
|---|---|---|---|
| Scale speed and fit | Fast; picks the instance per workload | Same engine as A | Slower; limited to the types of each group |
| Spot | Native, chooses among many types | Native | One Spot group (or more) defined in advance |
| Fixed cost | + small controller node | + ≈ 12% fee on all compute | Lowest |
| Components to install | Karpenter, SQS, EventBridge, controller node, `NodePool`, `EC2NodeClass` | None for nodes; Auto Mode objects | Cluster Autoscaler and the node groups |
| Portability | Node layer changes; no maintained provider on GCP | Highest effort: managed components and Auto Mode APIs | Lowest effort: same tool in the three clouds |
| Delivery through Argo CD | Upstream Helm chart (XIII) | Core components outside Argo CD | Upstream Helm chart (XIII) |

### Principle fit

| Principle | A | B | C |
|---|---|---|---|
| II. Scalability, cost tending to zero | ✅ most efficient at large, varied scale | ⚠️ fee on all compute | ✅ enough for daily batch; groups scale to zero |
| III. Simplicity | ⚠️ more components | ✅ least to operate on AWS | ✅ fewest components to install |
| VIII. Portability | ⚠️ no maintained provider on GCP | ⚠️ highest migration effort | ✅ same tool in the three clouds |
| XIII. Simple Kubernetes delivery | ✅ | n/a (managed by AWS) | ✅ |

### Risks

- A: a broken Karpenter upgrade stops node provisioning; more components to keep.
- B: the fee grows with the 1000x growth; highest effort to move to another cloud.
- C: node types are fixed per group, so a new workload with different needs (e.g., larger
  Trino workers) requires a new or changed node group in Terraform; slower scale-up (minutes),
  acceptable for daily batch workloads.

### Recommendation

**C. EKS + Cluster Autoscaler.** Same or lower base cost than A and B, the fewest components to
install, and the same autoscaler in the three clouds (built into AKS and GKE). The efficiency
advantages of A matter with many varied workloads, heavy Spot use or second-level scale-up,
which the spec does not require (daily batch, FR-011). Revisit A if those needs appear; only the
node layer would change.

### Decision

- **Decision**: C. EKS + Cluster Autoscaler.
- **Rationale**: same base cost as A and B, fewer components to install, and the same mechanism
  in the three clouds (built into AKS and GKE), which keeps portability simple.
- **Chosen by**: the user, 2026-10-09.

### Sources

- AWS Price List API (`AmazonEKS`, `AmazonEC2`, `us-east-2`), queried through the AWS MCP Server.
- [Karpenter best practices (Amazon EKS)](https://docs.aws.amazon.com/eks/latest/best-practices/karpenter.html)
- [Karpenter disruption and interruption](https://karpenter.sh/docs/concepts/disruption/)
- [EKS Auto Mode cost](https://aws.amazon.com/blogs/containers/maximizing-value-with-amazon-eks-auto-mode-strategies-for-visibility-control-and-optimization/)
- [EKS Auto Mode components](https://aws.amazon.com/blogs/containers/better-together-amazon-eks-auto-mode-and-istio-ambient-mesh/)
- [EKS Auto Mode node lifetime](https://docs.aws.amazon.com/whitepapers/latest/security-overview-amazon-eks-auto-mode/benefits.html)
- [Azure Retail Prices API (AKS)](https://prices.azure.com/api/retail/prices)
- [AKS Node Auto-Provisioning](https://learn.microsoft.com/en-us/azure/aks/node-auto-provisioning)
- [GKE pricing](https://cloud.google.com/kubernetes-engine/pricing)
- [Karpenter FAQ (providers)](https://karpenter.sh/docs/faq/)
- [EKS Auto Mode storage class](https://docs.aws.amazon.com/eks/latest/userguide/sample-storage-workload.html)
- [Getting started with EKS Auto Mode](https://aws.amazon.com/blogs/containers/getting-started-with-amazon-eks-auto-mode/)
- [Azure Retail Prices API (D2s_v5, eastus2)](https://prices.azure.com/api/retail/prices)
- [Autopilot resource requests](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/autopilot-resource-requests)
- [General Purpose VM pricing (GCP)](https://cloud.google.com/products/compute/pricing/general-purpose)

---

## D-002 Outbound internet access for private subnets

**Status**: Decided

### Context

- Nodes live in private subnets; they need outbound access to pull images and Helm charts, to
  reach the Git repository (Argo CD) and to extract data from external sources (spec FR-007).
- Spec FR-017: inbound data may grow to about 1 TB per day; data returning through a NAT is
  billed per GB.
- Constitution II (cost), III (simplicity), VIII (portability).
- Independent of this choice: an S3 gateway endpoint (no charge) keeps S3 traffic off the NAT.
  This is a separate design element and will be listed as its own item in the plan.

### Options

**A. One zonal NAT gateway** shared by the private subnets of all AZs.
**B. One zonal NAT gateway per AZ**, each AZ routing to its own.
**C. One regional NAT gateway** (launched November 2025): a single gateway that expands to
the AZs where workloads exist; no public subnet is needed to host it; up to 32 IP addresses
per AZ; may take up to 60 minutes to expand to a new AZ.
**D. NAT instance** (e.g., the open source fck-nat image on a t4g.nano): an EC2 instance you
run as the NAT.

### Cost (AWS `us-east-2`)

| | Fixed per month | Per GB processed |
|---|---|---|
| A | US$ 0.045/h ≈ US$ 32.85 + public IPv4 US$ 0.005/h ≈ US$ 3.65 = **≈ US$ 36.50** | US$ 0.045 |
| B (2 AZs) | **≈ US$ 73.00** | US$ 0.045 |
| C | Listed at US$ 0.045/h; the sources read do not state whether the hourly charge applies per active AZ; plus US$ 0.005/h per public IPv4 | US$ 0.045 |
| D | t4g.nano ≈ US$ 0.0042/h ≈ US$ 3.07 + disk ≈ US$ 0.64 + public IPv4 ≈ US$ 3.65 = **≈ US$ 7.40** (project figures) | US$ 0 (no processing fee) |

Effect of the data volume on the per-GB charge (A, B, C), for data from external sources:

| Volume | GB/month | Processing charge/month |
|---|---|---|
| Today (1 GB/day) | ≈ 30 | ≈ US$ 1.35 |
| 1000x (≈ 1 TB/day) | ≈ 30,000 | ≈ US$ 1,350 |

Standard data transfer charges apply in every option; traffic between AZs costs
US$ 0.01/GB in each direction.

### Equivalents in the other clouds

| Cloud | Managed NAT | Fixed | Per GB |
|---|---|---|---|
| Azure | NAT Gateway StandardV2 (zone-redundant by default; same price as Standard) | ≈ US$ 0.045/h (2023 rate; not confirmed on the current pricing page) | ≈ US$ 0.045 |
| GCP | Cloud NAT (regional, distributed) | US$ 0.0014/h per VM, up to 32 VMs, + US$ 0.005/h per IP | US$ 0.045/GiB |

Azure and GCP use one regional, highly available gateway: option C is the AWS design closest
to them.

### Trade-offs

| | A. Zonal, single | B. Zonal per AZ | C. Regional | D. NAT instance |
|---|---|---|---|---|
| Fixed cost | Low | 2x A | Uncertain | Lowest |
| Cost at 1000x growth | High per-GB | High per-GB | High per-GB | No per-GB fee; limited to 5 Gbps per instance |
| Availability | Lost for every AZ if its AZ fails | Each AZ independent | Automatic multi-AZ | Single instance; HA mode is not fully immune to outages |
| Operation | Managed | Managed, routes per AZ | Managed, one route | You patch and monitor the instance |
| Maturity | Established | Established | New (Nov 2025) | Community project |
| Same design as Azure/GCP | No | No | Yes | No |

### Principle fit

| Principle | A | B | C | D |
|---|---|---|---|---|
| II. Cost | ✅ today; ⚠️ at growth | ❌ | ⚠️ unknown | ✅ |
| III. Simplicity | ✅ | ⚠️ | ✅ | ❌ one more machine to run |
| VIII. Portability | ⚠️ | ⚠️ | ✅ | ⚠️ |

### Risks

- A: a failure of its AZ removes outbound access for the whole cluster until it recovers.
- C: cost not fully documented in the sources read; new service.
- D: self-managed single point of failure; bandwidth ceiling.
- A, B, C: per-GB charge becomes the largest network cost if external ingestion reaches 1 TB/day.

### Recommendation

**A. One zonal NAT gateway** for step 0: lowest known managed cost and simplest for a single
`dev` environment; the AZ risk is accepted. Revisit when the external ingestion volume grows
(per-GB charge) or when the regional NAT billing is confirmed.

### Decision

- **Decision**: A. One zonal NAT gateway, shared by the private subnets of all AZs.
- **Rationale**: not stated by the user; matches the research recommendation (lowest known
  managed cost and simplest for a single `dev` environment; AZ risk accepted).
- **Chosen by**: the user, 2026-10-09.

### Sources

- AWS Price List API (`AmazonEC2`, NAT Gateway, `us-east-2`), queried through the AWS MCP Server.
- [Amazon VPC pricing](https://aws.amazon.com/vpc/pricing/)
- [Regional NAT gateways](https://docs.aws.amazon.com/vpc/latest/userguide/nat-gateways-regional.html)
- [NAT gateway pricing strategies](https://docs.aws.amazon.com/vpc/latest/userguide/nat-gateway-pricing.html)
- [Cross-AZ data transfer](https://docs.aws.amazon.com/prescriptive-guidance/latest/eks-cost-optimization/network-cost-reduction.html)
- [fck-nat project](https://github.com/AndrewGuenther/fck-nat)
- [Azure NAT Gateway SKUs](https://learn.microsoft.com/en-us/azure/nat-gateway/nat-sku)
- [Azure NAT Gateway charges (Q&A, 2023)](https://learn.microsoft.com/en-us/answers/questions/1190165/azure-nat-gateway-charges)
- [Cloud NAT pricing](https://cloud.google.com/nat/pricing)

---

## D-003 Number of Availability Zones

**Status**: Decided

### Context

- Amazon EKS requires subnets in at least two Availability Zones.
- Constitution I (single `dev` environment), II (cost), III (simplicity), VIII (portability).

### Options

**A. 2 AZs** — one public and one private subnet per AZ.
**B. 3 AZs** — one public and one private subnet per AZ.

### Cost

| Item | 2 AZs | 3 AZs |
|---|---|---|
| Subnets, route tables | No charge | No charge |
| Traffic between AZs | US$ 0.01/GB each direction | Same rate; more traffic crosses AZs as pods spread |
| NAT per AZ (only if D-002 = B) | 2 gateways ≈ US$ 73/month | 3 gateways ≈ US$ 109.50/month |

### Equivalents in the other clouds

| Cloud | Where zones are set |
|---|---|
| AWS | Subnets are zonal: one subnet per AZ |
| Azure | Subnets are regional; zones are a node pool setting |
| GCP | Subnets are regional; zones are a node pool setting |

### Trade-offs

| | A. 2 AZs | B. 3 AZs |
|---|---|---|
| Resilience | Survives the loss of one AZ | More headroom |
| Spot capacity | Fewer capacity pools | More pools, fewer interruptions |
| Cost | Lower | Higher with NAT per AZ; more cross-AZ traffic |
| Network design | Fewer subnets | More subnets |

### Principle fit

| Principle | A | B |
|---|---|---|
| II. Cost | ✅ | ⚠️ |
| III. Simplicity | ✅ | ⚠️ |
| VIII. Portability | ✅ neutral | ✅ neutral |

### Recommendation

**A. 2 AZs**: the EKS minimum, simplest and cheapest; neutral for portability.

### Decision

- **Decision**: A. 2 AZs.
- **Rationale**: not stated by the user; matches the research recommendation (EKS minimum,
  simplest and cheapest; neutral for portability).
- **Chosen by**: the user, 2026-10-09.

### Sources

- [Cross-AZ data transfer](https://docs.aws.amazon.com/prescriptive-guidance/latest/eks-cost-optimization/network-cost-reduction.html)
- [Data transfer charges](https://docs.aws.amazon.com/cur/latest/userguide/cur-data-transfers-charges.html)

---

## D-004 Cloud permissions per workload

**Status**: Decided

### Context

- Constitution IX (as amended by this decision): cloud permissions through a single node role
  shared by every workload; access by users and groups (including LGPD) is controlled at the
  data layer.
- Constitution VIII: interchangeable across AWS, Azure and GCP.
- Workloads that need AWS permissions: Airbyte, Trino, Polaris and others that read or write
  S3; Karpenter (EC2); and future components.

### Options

**A. EKS Pod Identity**
- An IAM role is associated with a Kubernetes service account through the EKS API; an agent
  (`eks-pod-identity-agent` add-on) delivers the credentials.
- No OIDC provider per cluster; the role trusts the service principal
  `pods.eks.amazonaws.com` once; supports role session tags (one role reused with different
  effective permissions).
- One IAM role per service account. Requires recent AWS SDKs in the applications.
- Not available on EKS Fargate, Windows nodes or self-managed Kubernetes on EC2.

**B. IAM Roles for Service Accounts (IRSA)**
- The cluster's OIDC issuer is registered as an IAM OIDC provider; the service account is
  annotated with the role; the role's trust policy names the cluster's OIDC provider and the
  service account.
- One OIDC provider per cluster (default limit of 100 per account); trust policies have a size
  limit (typically four to eight relationships per policy).
- Works on EKS (including Fargate), EKS Anywhere and self-managed clusters.

**C. Single node role**
- Every node gets the same IAM role (instance profile); every pod on any node uses it through
  the instance metadata service.
- No per-workload roles, no OIDC provider, no agent, no service account annotations.
- Every workload, including Argo CD, can reach every resource the node role allows (e.g., the
  data buckets).
- Pods must be allowed to reach the instance metadata service (IMDSv2 hop limit of 2); to be
  checked in the plan.

### Cost

No charge in any of the three clouds, for all options.

### Equivalents in the other clouds

| Cloud | Mechanism | Model |
|---|---|---|
| AWS | IRSA | Service account token federated through OIDC |
| AWS | EKS Pod Identity | AWS agent; no OIDC federation |
| Azure | Microsoft Entra Workload ID | Service account token federated through OIDC (same model as IRSA) |
| GCP | Workload Identity Federation for GKE | Service account token exchanged through STS (federated, same model as IRSA) |
| AWS | Node role (option C) | Instance profile of the node |
| Azure | Node (kubelet) managed identity | Identity of the VM scale set |
| GCP | Node service account | Service account of the node VMs |

### Trade-offs

| | A. Pod Identity | B. IRSA | C. Single node role |
|---|---|---|---|
| Setup | Simpler: association through the EKS API | OIDC provider and trust policy per cluster | Simplest: one role for all nodes |
| Scale of roles | No trust-policy size limit | Trust-policy size limit | One role |
| Same model as Azure/GCP | No | Yes | Yes (node identity exists in the three clouds) |
| Who reaches the data buckets | Only workloads whose role allows it | Only workloads whose role allows it | Every workload, including Argo CD |
| Application impact | Needs recent AWS SDKs | Supported by AWS SDKs for many years | None: default AWS SDK credential chain |

### Principle fit

| Principle | A | B | C |
|---|---|---|---|
| III. Simplicity | ✅ | ⚠️ | ✅ simplest |
| VIII. Portability | ❌ AWS-only model | ✅ same model in the three clouds | ✅ node identity in the three clouds |
| IX. Least privilege (original text) | ✅ | ✅ | ❌ requires amending principle IX |

### Recommendation

**B. IRSA** (research recommendation before the decision): per-workload permissions under the
original principle IX, with the same federated model as Azure and GCP.

### Decision

- **Decision**: C. Single node role, shared by every workload.
- **Rationale**: simplicity; workloads being able to reach the data products is accepted for now
  and will be revisited later. Access to data by users and groups (including LGPD) is
  controlled at the data layer. Requires amending constitution principle IX.
- **Chosen by**: the user, 2026-10-09.

### Sources

- [EKS Pod Identity vs IRSA](https://aws.amazon.com/blogs/containers/amazon-eks-pod-identity-a-new-way-for-applications-on-eks-to-obtain-iam-credentials/)
- [EKS Pod Identity restrictions](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html)
- [Microsoft Entra Workload ID on AKS](https://learn.microsoft.com/en-us/azure/aks/workload-identity-deploy-cluster)
- [Workload Identity Federation for GKE](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/workload-identity)

---

## N-001 Memory and cost reduction for Argo CD and Airflow

**Status**: Noted by the user as important for cost; to apply in the plan and implementation.

The upstream Helm charts of Argo CD and Airflow set no resource requests by default. The values
below are starting points from third-party sources; requests MUST be adjusted to the usage
measured with Prometheus/Grafana. Resource usage does not depend on D-001 (the node scaler).

### Starting estimates

| Component | Memory request | CPU request | Source |
|---|---|---|---|
| Argo CD (small install, up to ~100 apps): application-controller 512 MiB, repo-server 256 MiB, server 128–256 MiB, redis 128 MiB, dex 64 MiB | ≈ 1.1–1.2 GiB | ≈ 0.5 vCPU | Third-party sizing guides |
| Airflow 3 production profile: scheduler 1,920 MiB, API server 3,840 MiB, DAG processor 3,840 MiB, triggerer 1,920 MiB | ≈ 11.25 GiB | 3 vCPU | Astronomer |

The Airflow metadata database (PostgreSQL) is not included.

### Reduction measures

**Argo CD**
- Disable Dex when there is no SSO login (access is through `kubectl port-forward`).
- Disable the notifications controller when deploy notifications are not used.
- Do not use the ApplicationSet controller while Applications are written one per component.
- Keep one replica per component (no high availability; chart default).
- Exclude from the cache the resource kinds Argo CD does not need to watch
  (`resource.exclusions`), reducing the application-controller memory.
- Consider the "core" installation (no UI, API server or Dex) if the web interface is not needed.

**Airflow 3**
- Disable the triggerer when no task uses deferrable operators.
- Reduce the API server worker processes to 1–2.
- Reduce the DAG processor parsing processes to 1 and increase the file re-parse interval.
- Use an executor that creates one pod per task (e.g., KubernetesExecutor): no idle workers, and
  task memory exists only while tasks run, on Spot capacity.
- Keep DAGs few and light (no heavy code at module level).
- Set requests from measured usage, not from production profiles.

Exact configuration names vary across Airflow and chart versions and MUST be checked against the
chosen versions.

### Expected effect

With these measures the On-Demand base (Argo CD + Airflow control components) is expected to fit
in 1–2 nodes of 2 vCPU / 8 GiB (≈ US$ 70–140/month with m6i.large at US$ 0.096/h), instead of
about 3 nodes with the production profile; to be confirmed by measurement in step 0.

### Sources

- [Airflow Helm chart: setting resources](https://airflow.apache.org/docs/helm-chart/stable/setting-resources-for-containers.html)
- [Astronomer: scale Airflow resources](https://www.astronomer.io/docs/astro-private-cloud/v-2-x/scale-airflow-resources.md)
- [Argo CD Operator: resource management](https://argocd-operator.readthedocs.io/en/latest/usage/resource_management/)
- [OneUptime: optimize Argo CD resources](https://oneuptime.com/blog/post/2026-02-26-argocd-optimize-resource-consumption/view)
- [OneUptime: install Argo CD](https://oneuptime.com/blog/post/2026-01-25-install-argocd-kubernetes/view)
