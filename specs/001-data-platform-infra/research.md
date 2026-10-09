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
| D-005 | Terraform state storage | Decided: A. S3 with native lock file |
| D-006 | Access to the cluster API (kubectl) | Decided: B. Open public endpoint + private endpoint |
| D-007 | Instance family of the nodes | Decided: C. m7g.large for all node groups |
| D-008 | Argo CD access to the Git repository | Decided: A. Public repository |
| D-009 | Kubernetes version | Decided: B. 1.36 |

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

## D-005 Terraform state storage

**Status**: Decided

### Context

- Constitution V (infrastructure as code), VII (separate applies: `foundation` and `bootstrap`,
  each with its own state), IV (no secrets in Git), and the reproducibility principle.
- The state records every resource Terraform manages and may contain sensitive values (e.g., a
  repository credential passed to the bootstrap, D-008); it must not be stored in Git.
- The state storage itself must exist before the first `terraform init`: it is created once by a
  small root module with local state (or by hand once and then imported), a known
  "chicken-and-egg" step.

### Options

**A. S3 with native lock file** — state in an S3 bucket (versioned, encrypted); locking through a
lock file in the same bucket (`use_lockfile = true`).
**B. S3 with DynamoDB locking** — state in S3; locking through a DynamoDB table. HashiCorp marks
DynamoDB-based locking as deprecated, to be removed in a future minor version.
**C. HCP Terraform** — HashiCorp's SaaS stores state and runs plans; pricing not verified here.
**D. Local state** — state file on the workstation.

### Cost

| Option | Cost |
|---|---|
| A | S3 storage and requests for a few small files: cents per month |
| B | Same as A + DynamoDB on-demand for a few lock operations: cents per month |
| C | SaaS subscription (not verified) |
| D | None |

### Equivalents in the other clouds

| Cloud | Backend | Locking |
|---|---|---|
| AWS | `s3` | Lock file (A) or DynamoDB (B) |
| Azure | `azurerm` (Blob Storage) | Native blob lease |
| GCP | `gcs` (Cloud Storage) | Native |

### Trade-offs

| | A. S3 + lock file | B. S3 + DynamoDB | C. HCP Terraform | D. Local |
|---|---|---|---|---|
| Resources to create | One bucket | Bucket + table | Account and workspaces | None |
| Locking | ✅ | ✅ (deprecated) | ✅ | ❌ |
| Shared across workstations | ✅ | ✅ | ✅ | ❌ |
| Recovery of a previous state | ✅ bucket versioning | ✅ | ✅ | ❌ |
| Future-proof | ✅ | ❌ deprecated | ✅ | — |
| Data outside the cloud account | No | No | Yes (SaaS) | Workstation |

### Principle fit

| Principle | A | B | C | D |
|---|---|---|---|---|
| III. Simplicity | ✅ | ⚠️ | ⚠️ | ✅ |
| IV / reproducibility | ✅ | ✅ | ✅ | ❌ |
| VIII. Portability | ✅ same pattern (`azurerm`, `gcs`) | ⚠️ | ✅ | — |

### Recommendation

**A. S3 with native lock file**: one bucket, versioned and encrypted, with a separate state key
for `foundation` and `bootstrap` (VII); the same pattern exists in Azure and GCP.

### Decision

- **Decision**: A. S3 with native lock file.
- **Rationale**: the user chose S3; option A is the S3 variant that is not deprecated
  (option B, DynamoDB locking, is deprecated by HashiCorp).
- **Chosen by**: the user, 2026-10-09.

### Sources

- [Terraform S3 backend](https://developer.hashicorp.com/terraform/language/backend/s3)

---

## D-006 Access to the cluster API (kubectl)

**Status**: Decided

### Context

- The operator runs `kubectl`, `kubectl port-forward` (admin interfaces) and Terraform from the
  workstation; nodes in private subnets must also reach the API.
- By default the EKS API endpoint is public; every request is still authenticated (IAM) and
  authorized (Kubernetes RBAC).
- Constitution II (cost), III (simplicity), VIII (portability).
- Operator permissions use EKS access entries (authentication mode `API`), the means AWS now
  prefers over the `aws-auth` ConfigMap.

### Options

**A. Public endpoint restricted to the operator's IP + private endpoint** — the public endpoint
accepts only listed CIDRs (e.g., the operator's public IP); nodes reach the API through the
private endpoint inside the VPC.
**B. Public endpoint open to the internet + private endpoint** — authentication and RBAC are the
only protection.
**C. Private endpoint only** — the API is reachable only from inside the VPC; the operator needs
a VPN, a bastion or another path into the VPC.

### Cost

| Option | Cost |
|---|---|
| A | No charge |
| B | No charge |
| C | Extra: a VPN endpoint or a bastion instance (not estimated here) |

### Equivalents in the other clouds

| Cloud | Restricted public | Private only |
|---|---|---|
| AWS | `publicAccessCidrs` | Private endpoint |
| Azure | AKS API server authorized IP ranges | AKS private cluster |
| GCP | GKE authorized networks | GKE private endpoint |

### Trade-offs

| | A. Restricted public | B. Open public | C. Private only |
|---|---|---|---|
| Exposure | Only listed IPs | Internet (authenticated) | None |
| Operator access | Direct; the CIDR must be updated if the operator's IP changes | Direct | Through VPN/bastion |
| Cost | None | None | VPN or bastion |
| Simplicity | ✅ | ✅ | ❌ |

### Principle fit

| Principle | A | B | C |
|---|---|---|---|
| II. Cost | ✅ | ✅ | ⚠️ |
| III. Simplicity | ✅ | ✅ | ❌ |
| VIII. Portability | ✅ | ✅ | ✅ |

### Risks

- A: a changing home IP blocks access until the CIDR variable is updated and applied.
- B: any leaked credential can reach the API from anywhere.
- C: extra component and cost.

### Recommendation

**A. Public endpoint restricted to the operator's IP, plus the private endpoint for nodes**: no
cost, simple, and the API is not open to the internet; the allowed CIDR is a Terraform variable.

### Decision

- **Decision**: B. Public endpoint open to the internet, plus the private endpoint for nodes.
- **Rationale**: the simplest option; security relies on IAM authentication and Kubernetes RBAC.
  Same setup as the reference project, where GitHub Actions runners (changing IPs) also reach
  the cluster.
- **Chosen by**: the user, 2026-10-09.

### Sources

- [EKS best practices: cluster endpoint](https://docs.aws.amazon.com/eks/latest/best-practices/identity-and-access-management.html)
- [Restricting access to the public endpoint](https://docs.aws.amazon.com/eks/latest/eksctl/vpc-cluster-access.html)
- [Cluster networking for worker nodes](https://aws.amazon.com/blogs/containers/de-mystifying-cluster-networking-for-amazon-eks-worker-nodes/)
- [EKS access entries](https://aws.amazon.com/blogs/containers/a-deep-dive-into-simplified-amazon-eks-access-management-controls/)

---

## D-007 Instance family of the nodes

**Status**: Decided

### Context

- D-001: two node groups, an On-Demand base (Argo CD, Airflow control components, catalogs,
  databases) and a Spot group for interruptible jobs.
- The base components are mostly idle (N-001); the jobs use CPU in bursts.
- Constitution II (cost), VIII (portability).

### Options (2 vCPU, 8 GiB, On-Demand, `us-east-2`)

| Option | Instance | Architecture | vCPU (physical cores) | Sustained CPU | Network (up to) | Price/hour |
|---|---|---|---|---|---|---|
| A. Intel | m6i.large | x86 | 2 (1 core, 2 threads) | 100% | 12.5 Gbps | US$ 0.0960 |
| B. AMD | m6a.large | x86 | 2 (1 core, 2 threads) | 100% | 12.5 Gbps | US$ 0.0864 |
| C. Graviton | m7g.large | arm64 | 2 (2 cores) | 100% | 12.5 Gbps | US$ 0.0816 |
| D1. Burstable Intel | t3.large | x86 | 2 (1 core, 2 threads) | 30% baseline + credits | 5 Gbps | US$ 0.0832 |
| D2. Burstable Graviton | t4g.large | arm64 | 2 (2 cores) | 30% baseline + credits | 5 Gbps | US$ 0.0672 |

Burstable (D) instances deliver a baseline CPU of 30% and burst above it with credits. They
launch in `unlimited` mode by default: if the average CPU over 24 hours, or over the instance
lifetime when shorter, exceeds the baseline, the extra is billed per vCPU-hour (US$ 0.05 for T3,
US$ 0.04 for T4g); surplus credits are charged at the latest when the instance stops. AWS
recommends `standard` mode for short-lived Spot instances to avoid surplus charges.

### Effective price per hour by average CPU (same compute: 2 vCPU, 8 GiB)

Burstable: fixed price + surplus above the 30% baseline. Non-burstable: the same price at any
usage. US$ per hour, per node.

| Average CPU | D1. t3.large | A. m6i.large | B. m6a.large | D2. t4g.large | C. m7g.large |
|---|---|---|---|---|---|
| 10% | 0.0832 | 0.0960 | 0.0864 | **0.0672** | 0.0816 |
| 30% (baseline) | 0.0832 | 0.0960 | 0.0864 | **0.0672** | 0.0816 |
| 40% | 0.0932 | 0.0960 | 0.0864 | **0.0752** | 0.0816 |
| 50% | 0.1032 | 0.0960 | 0.0864 | 0.0832 | **0.0816** |
| 75% | 0.1282 | 0.0960 | 0.0864 | 0.1032 | **0.0816** |
| 100% | 0.1532 | 0.0960 | 0.0864 | 0.1232 | **0.0816** |

### Break-even: average CPU above which the burstable costs more

| Burstable | vs. A. m6i.large | vs. B. m6a.large | vs. C. m7g.large |
|---|---|---|---|
| D1. t3.large | ≈ 43% | ≈ 33% | Never cheaper (US$ 0.0832 > US$ 0.0816 even at baseline) |
| D2. t4g.large | ≈ 66% | ≈ 54% | ≈ 48% |

The fairest comparisons stay within the same architecture: t3 vs. m6i/m6a (x86) and t4g vs.
m7g (arm64). The break-even treats every vCPU as equal; m7g has two physical cores while t3,
m6i and m6a have one core with two threads, so m7g tends to deliver more per vCPU.

Smaller sizes (micro, small, medium) were also compared: the price per GiB is the same within a
family, but smaller nodes lose a larger share of memory to Kubernetes reservations and system
pods (≈ 29% on micro, ≈ 11% on medium, ≈ 8% on large) and accept fewer pods (4 on micro, 17 on
medium, 29–35 on large); m6i and m6a have no size below large.

### arm64 availability (for C and D2)

Multi-architecture images (amd64 and arm64) were verified for: Airflow (`apache/airflow`), Trino
(`trinodb/trino`), Polaris (`apache/polaris`), OpenMetadata (`openmetadata/server`), Airbyte
(`airbyte/server` and `airbyte/workload-launcher` 2.4.0; connector `airbyte/source-postgres`),
Grafana, Prometheus and Argo CD (`quay.io/argoproj/argocd`, multi-architecture manifest). Each
Airbyte connector and every image built by the project must also be checked.

### Equivalents in the other clouds

| Cloud | x86 general purpose | arm64 general purpose | Burstable |
|---|---|---|---|
| AWS | m6i, m6a | m7g (Graviton) | t3, t4g |
| Azure | Dsv5, Dasv5 | Dpsv5/Dpsv6 (Ampere/Cobalt) | B-series |
| GCP | n2, n2d | t2a, c4a (Axion) | e2 shared-core |

### Trade-offs

| | A. Intel | B. AMD | C. Graviton | D. Burstable |
|---|---|---|---|---|
| Price | Highest | −10% | −15% | −13% (t3) / −30% (t4g) |
| Image compatibility | All | All | Needs arm64 images | t3 all; t4g needs arm64 |
| Sustained CPU | Full | Full | Full | Baseline + credits; surplus billed |
| Fit for the idle base | ✅ | ✅ | ✅ | ✅ best |
| Fit for Spot jobs | ✅ | ✅ | ✅ | ⚠️ surplus charges in `unlimited` mode |

### Principle fit

| Principle | A | B | C | D |
|---|---|---|---|---|
| II. Cost | ⚠️ | ✅ | ✅ | ✅ base / ⚠️ jobs |
| III. Simplicity | ✅ | ✅ | ⚠️ arm64 check per image | ⚠️ credit monitoring |
| VIII. Portability | ✅ | ✅ | ✅ arm64 exists in the three clouds | ✅ |

### Recommendation

**Base group: D2 (t4g.large, burstable Graviton)**, cheapest for mostly idle components; **Spot
group: C (Graviton, non-burstable, e.g., m7g)** for CPU-heavy jobs. Fallback to x86 (B) for any
image without arm64.

### Decision

- **Decision**: C. m7g.large (Graviton, arm64) for all node groups (On-Demand base and Spot).
- **Rationale**: simplicity, one instance type everywhere. CPU usage of the base group (Argo CD,
  Airflow scheduler and other control components) will be measured; if it stays low, the base
  group may move to burstable (D2. t4g.large).
- **Chosen by**: the user, 2026-10-09.

### Sources

- AWS Price List API (`AmazonEC2`, `us-east-2`), queried through the AWS MCP Server.
- Amazon EC2 `DescribeInstanceTypes` (`us-east-2`), queried through the AWS MCP Server.
- [EC2 On-Demand pricing: T4g/T3 Unlimited Mode](https://aws.amazon.com/ec2/pricing/on-demand/)
- [Unlimited mode for burstable instances](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/burstable-performance-instances-unlimited-mode.html)
- [Unlimited mode concepts (t3.large baseline)](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/burstable-performance-instances-unlimited-mode-concepts.html)
- [Amazon EC2 T3 instances](https://aws.amazon.com/ec2/instance-types/t3/)
- Docker Hub and Quay registry APIs (image architectures), queried on 2026-10-09.

---

## D-008 Argo CD access to the Git repository

**Status**: Decided

### Context

- Argo CD reads this repository (`github.com/AndreRosaLopes/eks_on_AWS_OpenSource`). An
  unauthenticated request to the GitHub API for it returns "not found", so the repository is
  private (or not reachable anonymously).
- Constitution IV: no credential in Git. A credential for a private repository must be given to
  the cluster by the bootstrap from outside the repository.
- Constitution III (simplicity).

### Options

**A. Make the repository public** — Argo CD reads it anonymously; no credential at all.
**B. Deploy key** — a read-only SSH key bound to this repository; its private part is given to
Argo CD by the bootstrap.
**C. GitHub App** — an app installed on the repository; Argo CD uses its private key to obtain
short-lived tokens.
**D. Fine-grained personal access token** — a token of the user's account, read-only on this
repository, with an expiration date.

### Cost

No charge for any option.

### Equivalents in the other clouds

Not cloud-dependent: the same options apply with Argo CD on AKS or GKE.

### Trade-offs

| | A. Public | B. Deploy key | C. GitHub App | D. Fine-grained token |
|---|---|---|---|---|
| Credential to keep | None | One SSH key | App private key | Token |
| Scope | — | One repository, read-only | Repositories where installed | Chosen repositories |
| Expiration | — | None | Short-lived tokens | Expires; must be renewed |
| Tied to a person | — | No | No | Yes |
| Setup | None | Low | Medium | Low |
| Code visibility | Everyone | Private | Private | Private |

### Principle fit

| Principle | A | B | C | D |
|---|---|---|---|---|
| III. Simplicity | ✅ | ✅ | ⚠️ | ✅ |
| IV. No secrets in Git | ✅ nothing to protect | ✅ if kept outside Git | ✅ if kept outside Git | ✅ if kept outside Git |

### Risks

- A: everything in the repository becomes public; safe only while no secret is ever committed (IV).
- B, C, D: the credential must be stored outside Git and reach the bootstrap; if passed to
  Terraform it is also stored in the state (encrypted bucket, D-005).
- D: expiration breaks delivery until renewed.

### Recommendation

The repository's visibility is the user's choice. If it can be public, **A** is the simplest.
If it must stay private, **B. Deploy key**: read-only, one repository, no expiration and not
tied to a person.

### Decision

- **Decision**: A. Make the repository public; Argo CD reads it anonymously, with no credential.
- **Rationale**: the simplest option; constitution IV already keeps secrets out of Git. Before
  the change, the Git history (14 commits) was scanned for credentials, keys and tokens, with no
  findings. The repository was made public on 2026-10-09 and an anonymous request to the GitHub
  API now returns it.
- **Chosen by**: the user, 2026-10-09.

### Sources

- GitHub REST API (`GET /repos/AndreRosaLopes/eks_on_AWS_OpenSource`, unauthenticated: 404),
  queried on 2026-10-09.

---

## D-009 Kubernetes version

**Status**: Decided

### Context

- Constitution X (pinned versions).
- Cost: EKS standard support costs US$ 0.10/h per cluster; after the end of standard support the
  cluster moves to extended support at US$ 0.60/h, so the cluster must be upgraded before that
  date.
- The Cluster Autoscaler (D-001) releases one version per Kubernetes minor version.

### Options (EKS versions in standard support, `us-east-2`, on 2026-10-09)

| Option | Version | Released | End of standard support | EKS default |
|---|---|---|---|---|
| A | 1.37 | 2026-10-01 | 2027-12-01 | No |
| B | 1.36 | 2026-06-02 | 2027-08-02 | Yes |
| C | 1.35 | 2026-01-27 | 2027-03-27 | No |

Latest Cluster Autoscaler releases: 1.36.1, 1.35.2, 1.34.5 (2026-07-23); **no 1.37 release
yet**.

### Equivalents in the other clouds

AKS and GKE publish their own supported versions and calendars; the Kubernetes minor version is
the same concept in the three clouds.

### Trade-offs

| | A. 1.37 | B. 1.36 | C. 1.35 |
|---|---|---|---|
| Standard support left | ≈ 14 months | ≈ 10 months | ≈ 5.5 months |
| Matching Cluster Autoscaler | ❌ not released | ✅ 1.36.1 | ✅ 1.35.2 |
| Helm chart and add-on compatibility | Newest; may lag | Established | Established |

### Principle fit

| Principle | A | B | C |
|---|---|---|---|
| II. Cost (avoid extended support) | ✅ | ✅ | ⚠️ earlier upgrade |
| X. Pinned versions | ✅ | ✅ | ✅ |

### Recommendation

**B. 1.36**: EKS default, a matching Cluster Autoscaler release exists, and about 10 months of
standard support; plan the upgrade to 1.37 once its autoscaler is released.

### Decision

- **Decision**: B. Kubernetes 1.36.
- **Rationale**: the user's rule is to always use the newest stable version possible; 1.36 is the
  newest version with a matching Cluster Autoscaler release.
- **Chosen by**: the user, 2026-10-09.

### Sources

- Amazon EKS `DescribeClusterVersions` (`us-east-2`), queried through the AWS MCP Server on 2026-10-09.
- [Cluster Autoscaler releases](https://github.com/kubernetes/autoscaler/releases), queried on 2026-10-09.

---

## P1 Ingestion decisions

| ID | Decision | Status |
|---|---|---|
| D-010 | PostgreSQL for the platform metadata | Decided: A. Bundled database of each Helm chart |
| D-011 | Secrets outside Git | Decided: `.env` → Terraform variables → Kubernetes Secrets |
| D-012 | Writing the bronze layer as Iceberg | Decided: A. Polaris in P1 |
| D-013 | Location of the internal sources | Decided: same as the reference project (sample PostgreSQL in the cluster) |
| D-014 | PostgreSQL for Polaris | Decided: A. Own PostgreSQL as plain YAML |
| D-015 | Block storage driver for persistent volumes | Decided: A. EKS managed add-on in Terraform |

What P1 needs, from the official documentation:
- **Airbyte** (Helm chart V2; Airbyte 2.1+ supports only chart V2) needs a PostgreSQL database
  (bundled or external, version 13 or later) and object storage for state and logs (bundled
  MinIO or S3; S3 supports authentication by instance profile, which matches D-004).
- **Iceberg on S3** (user decision: Iceberg tables only) is written by Airbyte's *S3 Data Lake*
  destination, which supports the REST, AWS Glue, Nessie and **Polaris** catalogs.
- **Polaris** keeps its catalog in memory by default (lost on restart, not for production); the
  documented production setup is PostgreSQL (`relational-jdbc`).

---

## D-010 PostgreSQL for the platform metadata

**Status**: Decided

### Context

- Airbyte (P1) and Polaris (P1, see D-012) need PostgreSQL; Airflow (P3), OpenMetadata (P6) and,
  possibly, the BI tool (P4) will also need a database.
- Constitution II: "State MUST be always on and managed"; capacity scales with demand and cost
  tends to zero when idle. Constitution III (simplicity), VIII (portability).
- Encryption only where it adds no cost (spec FR-005).

### Options

**A. Bundled database of each Helm chart** — each component runs its own PostgreSQL pod with a
persistent volume (Polaris has no bundled database, so it would need another one).
**B. One shared in-cluster PostgreSQL managed by an operator (e.g., CloudNativePG)** — one
PostgreSQL cluster in Kubernetes, one database per component, on a persistent volume.
**C. Amazon RDS for PostgreSQL, one shared instance** — managed by AWS; one database per
component.
**D. Aurora PostgreSQL Serverless v2 with scale to zero** — managed; pauses after a period
without connections (minimum 5 minutes) and resumes in up to about 15 seconds.

### Cost (`us-east-2`)

| Option | Compute | Storage | Example: 20 GB, all month |
|---|---|---|---|
| A | Node memory and CPU (one pod per component) | EBS gp3 US$ 0.08/GB-month per volume | ≈ US$ 1.60 per volume + node capacity |
| B | Node memory and CPU (one cluster) | EBS gp3 US$ 0.08/GB-month | ≈ US$ 1.60 + node capacity |
| C | db.t4g.micro US$ 0.016/h (≈ US$ 11.68/month); db.t4g.small US$ 0.032/h (≈ US$ 23.36/month) | gp3 US$ 0.115/GB-month | ≈ US$ 13.98 (micro) / US$ 25.66 (small) |
| D | US$ 0.12 per ACU-hour while active; no compute charge while paused | Aurora storage (price not queried) | Depends on active hours |

An RDS instance can be stopped when the platform is off (it restarts automatically after seven
days). Encryption at rest with the AWS managed key has no extra charge.

### Equivalents in the other clouds

| Option | Azure | GCP |
|---|---|---|
| A, B | Same (in-cluster) | Same (in-cluster) |
| C | Azure Database for PostgreSQL – Flexible Server | Cloud SQL for PostgreSQL |
| D | No direct scale-to-zero equivalent verified | No direct scale-to-zero equivalent verified |

All options use the standard PostgreSQL protocol; components only see a host, a port and a
database.

### Trade-offs

| | A. Bundled per chart | B. Shared in-cluster | C. RDS | D. Aurora Serverless v2 |
|---|---|---|---|---|
| "State always on and managed" (II) | ❌ self-managed | ❌ self-managed (operator) | ✅ | ✅ |
| Backups and upgrades | You | Operator + you | AWS | AWS |
| Extra components in the cluster | One database per chart | Operator + database | None | None |
| Persistent volumes in the cluster | Yes (block storage driver needed) | Yes | No | No |
| Idle cost | Node capacity | Node capacity | Instance hour (can be stopped) | Storage only while paused |
| Portability | ✅ | ✅ | ✅ managed equivalents | ⚠️ scale to zero is AWS-specific |
| Simplicity | ⚠️ many databases | ⚠️ operator to learn | ✅ | ⚠️ resume delay; fewer equivalents |

### Recommendation

**C. One shared Amazon RDS for PostgreSQL instance (db.t4g.micro to start)**, one database per
component: meets "state always on and managed" (II), no persistent volumes or database
operations in the cluster, low fixed cost, and managed PostgreSQL exists in the three clouds.
Resize if measurements show the need.

### In the reference project (`20261005_eks_ws`)

One PostgreSQL per component, self-managed in the cluster: a `postgres:15-alpine` Deployment with
a 10 GiB gp3 persistent volume each (`charts/postgres-eks/`: Airbyte, Airflow, Hive Metastore,
OpenMetadata, OpenMetadata's Airflow, and the sample source). The volumes use the EBS CSI
driver, installed as an EKS managed add-on with its own IAM role
(`specs/SPEC-014-terraform-eks.md`, `infra/terraform/modules/iam-irsa`). The Hive Metastore database
also holds `iceberg_catalog`, the Trino JDBC catalog. Closest to option A (one database per
component, in-cluster), but with the project's own manifests instead of the charts' bundled
databases.

### Decision

- **Decision**: A. Bundled database of each Helm chart.
- **Rationale**: not stated by the user. The user does not read constitution II ("State MUST be
  always on and managed") as covering the databases of the tools, so the "self-managed" mark
  against A in the trade-offs does not apply under that reading.
- **Open points**: Polaris has no bundled database (a PostgreSQL must still be provided for it);
  in-cluster databases need persistent volumes, so the cluster needs a block storage driver
  (e.g., EBS CSI).
- **Chosen by**: the user, 2026-10-09.

### Sources

- AWS Price List API (`AmazonRDS`, `AmazonEC2` gp3, `us-east-2`), queried through the AWS MCP Server.
- [Aurora Serverless v2 auto-pause](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-serverless-v2-auto-pause.html)
- [Scaling to 0 with Aurora Serverless v2](https://aws.amazon.com/blogs/database/introducing-scaling-to-0-capacity-with-amazon-aurora-serverless-v2/)
- [Airbyte external database](https://docs.airbyte.com/platform/1.8/deploying-airbyte/integrations/database)
- [Polaris persistence (Helm chart)](https://polaris.apache.org/releases/1.4.0/helm-chart/persistence/)

---

## D-011 Secrets outside Git

**Status**: Decided

### Context

- Constitution IV: no secrets in Git; VI: in-cluster workloads delivered by Argo CD.
- Secrets in P1: database passwords (D-010), Polaris client credentials used by Airbyte, and the
  credentials of each data source.
- Airbyte stores connector credentials in its database by default; it can also use AWS Secrets
  Manager as its secrets store.

### Options

**A. Terraform bootstrap creates the Kubernetes Secrets** — passwords generated by Terraform
(e.g., random passwords) and written both to the database and to Kubernetes Secrets; values are
kept in the Terraform state (encrypted S3 bucket, D-005), never in Git. Source credentials are
entered in the Airbyte UI and stored by Airbyte.
**B. External Secrets Operator + a cloud secret store** — secrets live in AWS SSM Parameter
Store or Secrets Manager; the operator (delivered by Argo CD) copies them into Kubernetes
Secrets.
**C. Sealed Secrets** — secrets are encrypted with a key held by a controller in the cluster;
the encrypted form is committed to Git.
**D. SOPS** — secrets encrypted with a key (e.g., KMS or age) and committed to Git; Argo CD needs
a plugin to decrypt them.

### Cost

| Option | Cost |
|---|---|
| A | None |
| B | SSM Parameter Store standard: no charge; Secrets Manager: US$ 0.40 per secret per month + US$ 0.05 per 10,000 requests |
| C | None (controller runs in the cluster) |
| D | KMS key (if used) |

### Equivalents in the other clouds

| Option | Azure / GCP |
|---|---|
| A | Same (Terraform Kubernetes provider) |
| B | The operator supports Azure Key Vault and GCP Secret Manager |
| C | Same (cloud-independent) |
| D | Azure Key Vault / GCP KMS keys, or age |

### Trade-offs

| | A. Terraform bootstrap | B. External Secrets | C. Sealed Secrets | D. SOPS |
|---|---|---|---|---|
| Extra components | None | Operator + secret store | Controller | Argo CD plugin |
| Where secrets live | Terraform state (encrypted) | Cloud secret store | Git (encrypted) | Git (encrypted) |
| Rotation | Terraform apply | In the store; synced automatically | Re-seal and commit | Re-encrypt and commit |
| Delivered by Argo CD | No (bootstrap) | Yes | Yes | Yes (with plugin) |
| Simplicity | ✅ | ⚠️ | ⚠️ | ❌ |
| Risk | Anyone with state access reads secrets | Store permissions (node role, D-004) | Losing the controller key loses the secrets | Key management |

### Recommendation

**A. Terraform bootstrap creates the Kubernetes Secrets**: no extra component or cost, nothing
in Git, and the state is already encrypted and private (D-005). Source credentials stay in
Airbyte. Revisit B if secrets need rotation or sharing outside the cluster.

### In the reference project (`20261005_eks_ws`)

Secrets are committed to Git in plain text: database passwords in versioned manifests (e.g.,
`airbyte123` in `charts/postgres-eks/airbyte-postgres.yaml`) and object storage keys in a
Kustomize `secretGenerator` (`charts/airbyte-eks/kustomization.yaml`); files named `*secret*.yaml`
are ignored by Git. None of the options above; this pattern violates constitution IV.

### Decision

- **Decision**: Passwords defined by the user in the local `.env` file (not versioned), passed
  to Terraform as `TF_VAR_*` variables marked `sensitive`; the Terraform bootstrap creates the
  Kubernetes Secrets from them. Source credentials stay in Airbyte.
- **Rationale**: the user keeps control of the values. The values are also stored in the
  Terraform state (encrypted, private bucket, D-005). Keeping them out of the state (ephemeral
  variables and write-only arguments, Terraform 1.10/1.11+) was presented and not chosen.
- **Chosen by**: the user, 2026-10-09.

### Sources

- AWS Price List API (`AWSSecretsManager`, `us-east-2`), queried through the AWS MCP Server.
- [Airbyte secret management](https://docs.airbyte.com/platform/deploying-airbyte/integrations/secrets)
- [Terraform S3 backend](https://developer.hashicorp.com/terraform/language/backend/s3)

---

## D-012 Writing the bronze layer as Iceberg

**Status**: Decided

### Context

- User decisions: Iceberg tables only; Apache Polaris as the Iceberg catalog; Airbyte for
  ingestion.
- Spec P1 (ingestion) comes before P2 (processing); the plan adds each component with the first
  functionality that needs it.

### Options

**A. Polaris in P1; Airbyte writes Iceberg directly** — Airbyte's S3 Data Lake destination writes
Iceberg tables to S3 and registers them in Polaris.
**B. Airbyte writes plain files (e.g., Parquet) in P1; conversion to Iceberg in P2** — Polaris
arrives with processing.
**C. AWS Glue as the bronze catalog** — Airbyte writes Iceberg registered in Glue.

### Trade-offs

| | A. Polaris in P1 | B. Files, convert later | C. Glue |
|---|---|---|---|
| "Iceberg tables only" | ✅ | ❌ bronze is not Iceberg | ✅ |
| Polaris decision | ✅ | ✅ (later) | ❌ second catalog |
| Portability (VIII) | ✅ | ✅ | ❌ AWS-only catalog |
| P1 scope | Larger: Polaris + its database | Smaller | Medium |
| Extra processing step | None | Conversion job | None |

### Recommendation

**A. Polaris in P1**: the only option that keeps Iceberg everywhere with the chosen catalog;
P1 then includes Airbyte, Polaris, the PostgreSQL databases (D-010) and the S3 storage.

### In the reference project (`20261005_eks_ws`)

Airbyte's S3 destination writes **Parquet files** (not Iceberg) to the `bronze` bucket of an
in-cluster MinIO, not S3 (`s3://bronze/movielens/<table>/`; `docs/runbooks/airbyte-eks-setup.md`);
Airbyte's own state and logs also go to MinIO (`apps/eks/airbyte-app.yaml`). Iceberg appears only
in later layers, through Trino's JDBC catalog stored in PostgreSQL; Polaris is not used and a Hive
Metastore is deployed. Closest to option B (files in bronze, Iceberg later), with a different
catalog.

### Decision

- **Decision**: A. Polaris in P1; Airbyte writes Iceberg directly through the S3 Data Lake
  destination.
- **Rationale**: not stated by the user; matches the research recommendation (the only option
  that keeps Iceberg tables only with the chosen catalog).
- **Chosen by**: the user, 2026-10-09.

### Sources

- [Airbyte S3 Data Lake destination](https://docs.airbyte.com/integrations/destinations/s3-data-lake)
- [Polaris persistence (Helm chart)](https://polaris.apache.org/releases/1.4.0/helm-chart/persistence/)

---

## D-013 Location of the internal sources

**Status**: Decided

### Context

- Spec FR-007: sources are external and internal (APIs, databases and files). External sources
  are reached through the outbound gateway (D-002).
- How the platform reaches an **internal** source depends on where it is; the security
  requirement is defined first, and the connection follows from it.

### In the reference project (`20261005_eks_ws`)

The only source is a sample PostgreSQL database (MovieLens) running **inside the cluster**:
- Defined as plain YAML (`charts/postgres-eks/sample-source-postgres.yaml`), loaded by SQL scripts
  in `charts/postgres-eks/sample-data/` (`01-movielens-schema.sql`, `02-movielens-data.sql`).
- Airbyte reaches it by the cluster DNS name
  `sample-source-postgres.ingestion.svc.cluster.local:5432`, with SSL disabled
  (`docs/runbooks/airbyte-eks-setup.md`); Trino also reads it through a PostgreSQL connector
  (`apps/eks/trino-app.yaml`).
- There are no external sources and no sources in other networks; no VPN, peering or other
  private connection exists (`specs/SPEC-014-terraform-eks.md` sets the EKS endpoint public "for
  kubectl access without VPN").

In the reference project the "internal source" is therefore a database in the same cluster and
VPC, created only to simulate a company system.

### Question

Where are the internal sources?

| Answer | What the infrastructure needs |
|---|---|
| In this AWS account and VPC | Nothing extra (security groups) |
| In another AWS account or VPC | A private connection between networks (e.g., peering or Transit Gateway) |
| In the company's own network (on-premises) | A private connection to that network (e.g., site-to-site VPN or Direct Connect) |
| Reachable over the internet | Nothing extra; same path as external sources |
| Not known yet | Treat as external for now; revisit later |

### Decision

- **Decision**: Same as the reference project: the internal source is a sample PostgreSQL
  database (MovieLens) running inside the cluster, defined as plain YAML and loaded by SQL
  scripts; Airbyte reaches it by its cluster DNS name. No private connection to other networks.
- **Rationale**: chosen by the user to follow the reference project. Its password follows D-011
  (`.env`), not the plain-text password committed in the reference project (constitution IV).
- **Chosen by**: the user, 2026-10-09.

---

## D-014 PostgreSQL for Polaris

**Status**: Decided

### Context

- D-010: each component uses the database bundled in its Helm chart; the Polaris chart has no
  bundled database (its default persistence is in memory, lost on restart).
- D-012: Polaris is part of P1.
- Polaris production setup: `persistence.type: relational-jdbc` with PostgreSQL; a Kubernetes
  Secret with `username`, `password` and `jdbcUrl`; the schema must exist beforehand and the
  realm is created by the Polaris admin tool (bootstrap job).
- Constitution III (simplicity), XIII (upstream charts; own resources as plain YAML), D-011
  (password from `.env`).

### Options

**A. Own PostgreSQL as plain YAML** — a PostgreSQL Deployment (official `postgres` image) with a
persistent volume, in `infra/platform/apps/polaris/`, delivered by Argo CD with the Polaris
Application.
**B. Reuse another chart's bundled database** — e.g., create a `polaris` database inside the
PostgreSQL bundled with the Airbyte chart.
**C. A PostgreSQL Helm chart** — a third-party chart deployed only for Polaris (chart and image
licensing to be verified in the plan).
**D. A PostgreSQL operator (e.g., CloudNativePG)** — the operator plus one PostgreSQL cluster for
Polaris.

### Cost

All options run in the cluster: node capacity plus a gp3 volume (US$ 0.08/GB-month; e.g.,
10 GB ≈ US$ 0.80/month). D also runs the operator.

### Equivalents in the other clouds

All options are in-cluster and work the same on AKS and GKE; only the StorageClass changes
(D-015).

### Trade-offs

| | A. Own YAML | B. Reuse Airbyte's database | C. PostgreSQL chart | D. Operator |
|---|---|---|---|---|
| Extra components | One Deployment + volume | None | One chart | Operator + cluster |
| Independence of the increments | ✅ Polaris owns its database | ❌ Polaris depends on Airbyte's chart | ✅ | ✅ |
| Fits XIII | ✅ own resources as plain YAML | ✅ | ⚠️ chart not maintained by the PostgreSQL project | ⚠️ |
| Backups and upgrades | You | You, tied to Airbyte's upgrades | You | Operator + you |
| Simplicity | ✅ | ⚠️ hidden coupling | ⚠️ | ❌ |

### In the reference project (`20261005_eks_ws`)

There is no Polaris. The Iceberg catalog is Trino's JDBC catalog, stored in an `iceberg_catalog`
database created inside the Hive Metastore PostgreSQL, which is a plain-YAML Deployment
(`charts/postgres-eks/hive-metastore-postgres.yaml`); an Argo CD PostSync Job creates the
database and tables (`charts/postgres-eks/iceberg-catalog-init-job.yaml`). Closest to option A
(own YAML), with a shared database.

### Recommendation

**A. Own PostgreSQL as plain YAML**, owned by Polaris: simplest, keeps P1 increments
independent, follows XIII and the reference project; the password comes from `.env` (D-011);
a bootstrap Job creates the schema and the Polaris realm.

### Decision

- **Decision**: A. Own PostgreSQL as plain YAML, owned by Polaris; password from `.env` (D-011);
  a bootstrap Job creates the schema and the Polaris realm.
- **Rationale**: the user followed the research recommendation (simplest, keeps P1 increments
  independent, follows XIII and the reference project).
- **Chosen by**: the user, 2026-10-09.

### Sources

- [Polaris persistence (Helm chart)](https://polaris.apache.org/releases/1.4.0/helm-chart/persistence/)
- [Polaris production configuration](https://polaris.apache.org/releases/1.5.0/helm-chart/production/)

---

## D-015 Block storage driver for persistent volumes

**Status**: Decided

### Context

- D-010 and D-014: PostgreSQL databases run in the cluster and need persistent volumes (EBS).
- On EKS, persistent volumes on EBS need the EBS CSI driver and a StorageClass (e.g., gp3).
- D-004: AWS permissions come from the node role; the driver needs EBS permissions there.
- Constitution V (cloud resources through Terraform), VI (in-cluster workloads through Argo CD),
  X (pinned versions), XIII (upstream Helm charts).

### Options

**A. EKS managed add-on (`aws-ebs-csi-driver`), declared in Terraform** — AWS packages and
updates the driver; the version is pinned in Terraform.
**B. Upstream Helm chart, delivered by Argo CD** — the driver's open source chart, like the
other in-cluster components.

Both need the EBS permissions on the node role (D-004) and a gp3 StorageClass (plain YAML).

### Cost

No charge for the driver in either option; volumes cost US$ 0.08/GB-month (gp3).

### Equivalents in the other clouds

| Cloud | Block storage driver |
|---|---|
| AWS | EBS CSI driver (add-on or chart) |
| Azure | Azure Disk CSI driver, built into AKS |
| GCP | Persistent Disk CSI driver, built into GKE |

AKS and GKE ship the driver as part of the managed cluster, closer to option A.

### Trade-offs

| | A. EKS managed add-on | B. Helm chart via Argo CD |
|---|---|---|
| Who packages and tests it | AWS, for the EKS version | The driver project |
| Where it is declared | Terraform (cluster, step 0.2) | Git, Argo CD Application |
| Available before Argo CD | ✅ (with the cluster) | ❌ (after step 0.3) |
| Fits VI (in-cluster via Argo CD) | ⚠️ installed by AWS through Terraform, like the other core add-ons | ✅ |
| Portability | ✅ same model as AKS/GKE built-in drivers | ⚠️ AWS-specific chart |
| Simplicity | ✅ | ⚠️ one more Application |

### In the reference project (`20261005_eks_ws`)

Option A: `aws-ebs-csi-driver` is an EKS managed add-on, with its own IAM role
(`specs/SPEC-014-terraform-eks.md`, `infra/terraform/modules/iam-irsa`), and the volumes use a
`gp3` StorageClass.

### Recommendation

**A. EKS managed add-on in Terraform**, together with the other core add-ons of the cluster (VPC
CNI, CoreDNS, kube-proxy): available as soon as the cluster exists, same model as AKS and GKE,
and follows the reference project. Its relation to principle VI (core add-ons installed by
Terraform rather than Argo CD) should be stated in the plan's Constitution Check.

### Decision

- **Decision**: A. EKS managed add-on (`aws-ebs-csi-driver`) declared in Terraform, with the
  other core add-ons; a gp3 StorageClass as plain YAML.
- **Rationale**: the user followed the research recommendation (available with the cluster, same
  model as AKS and GKE, follows the reference project). Its relation to principle VI is stated
  in the plan's Constitution Check.
- **Chosen by**: the user, 2026-10-09.

### Sources

- AWS Price List API (`AmazonEC2` gp3, `us-east-2`), queried through the AWS MCP Server.
- Facts on the EBS CSI add-on permissions and the default StorageClass to be verified in the plan
  (constitution XII).

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
