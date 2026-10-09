Create the project constitution. This run covers the **Infrastructure** scope only.
Structure the document so a **Data** scope section can be added later by a separate amendment
without rewriting the infrastructure principles.

Context: monorepo for a low-cost data platform on Kubernetes for a small company with
little data per day, hosted on one of the three main clouds: AWS, Azure or GCP.
Infrastructure covers cloud resources (network, Kubernetes cluster, identity and access,
object storage) provisioned with Terraform and the components running inside the cluster,
delivered by Argo CD.

Write each principle as a testable rule (MUST / SHOULD) followed by a one-line rationale,
so `/speckit-plan` can check it as a gate.

## Shared principles (apply to every scope)

1. **Single environment.** There is only one environment, `dev`. No per-environment
   abstractions.
2. **Scalability with cost tending to zero.** State is always on and managed; capacity
   scales with demand and cost tends to zero when idle.
3. **Simplicity first.** Simplest solution for the current need; nothing for hypothetical
   needs.
4. **No secrets in Git.** Passwords, keys and tokens never go into the repository.

## Infrastructure principles

5. **Infrastructure as code.** Every cloud resource is created and changed through Terraform,
   except resources created dynamically by in-cluster controllers in response to Kubernetes
   objects declared in Git (e.g., load balancers, volumes, nodes); no manual changes in the
   console.
6. **GitOps for the cluster.** Every in-cluster workload is delivered by Argo CD from this
   repository; no manual `kubectl apply` or `helm install` for workloads.
7. **Separate applies.** Cloud resources (`infra/terraform/foundation`) and the cluster
   bootstrap (`infra/terraform/bootstrap`, which installs Argo CD) are separate Terraform
   root modules with separate state and applies.
8. **Cloud portability.** The solution MUST be interchangeable across at least AWS, Azure
   and GCP, with minimal cloud provider lock-in. Prefer Kubernetes-native, cloud-neutral
   components; cloud-specific code is confined to Terraform modules and resource annotations.
9. **Node-level cloud permissions.** Cloud permissions are granted through a single node role
   shared by every workload, for simplicity; to be revisited when finer-grained access is
   needed. Access to data by users and groups (including LGPD) is controlled at the data layer.
10. **Pinned versions.** Terraform, providers, modules, Helm charts and images use pinned
    versions.
11. **Verified changes.** Every change passes `terraform fmt`, `terraform validate` and a
    reviewed `terraform plan`; acceptance is checked by scripts in `scripts/verify/`.
    `terraform apply` and `destroy` run only with explicit approval.
12. **Verified decisions.** Every technical choice in a plan (service, feature, limit, price,
    region availability, provider/module/chart version, resource argument) cites its source
    and is checked against current official documentation through the AWS MCP Server
    (documentation, regional availability, pricing), the AWS skills and the Terraform MCP
    server (registry versions and resource schemas); official websites cover what these
    tools do not. Deployed resources are confirmed against the spec through the AWS MCP
    Server.
13. **Simple Kubernetes delivery.** Use the upstream Helm chart of each component, with a
    values file that overrides only what differs from the chart defaults; no custom or
    wrapper charts unless no maintained chart exists; Kustomize only when a chart cannot be
    configured through values; own resources as plain YAML.

## Governance

- The constitution overrides other practices; a plan that breaks a principle must justify
  it in its Complexity Tracking section.
- Amendments use semantic versioning (MAJOR: principle removed or redefined; MINOR:
  principle or section added; PATCH: wording).
- Agent working rules (answering, Git workflow) live in `AGENTS.md` and are out of scope.
