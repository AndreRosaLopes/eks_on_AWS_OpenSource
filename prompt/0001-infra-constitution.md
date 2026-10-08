Create the project constitution. This run covers the **Infrastructure** scope only.
Structure the document so a **Data** scope section can be added later by a separate amendment
without rewriting the infrastructure principles.

Context: monorepo for a low-cost data platform on Amazon EKS for a small company with
little data per day. Infrastructure covers AWS resources (VPC, EKS, IAM, S3) provisioned
with Terraform and the components running inside the cluster, delivered by Argo CD.

Write each principle as a testable rule (MUST / SHOULD) followed by a one-line rationale,
so `/speckit-plan` can check it as a gate.

## Shared principles (apply to every scope)

1. **Single environment.** There is only one environment, `dev`. No per-environment
   abstractions.
2. **Scale to zero.** State is always on and managed; compute scales to zero when idle.
3. **Simplicity first.** Simplest solution for the current need; nothing for hypothetical
   needs.
4. **No secrets in Git.** Passwords, keys and tokens never go into the repository.

## Infrastructure principles

5. **Infrastructure as code.** Every AWS resource is created and changed through Terraform;
   no manual changes in the console.
6. **GitOps for the cluster.** Every in-cluster workload is delivered by Argo CD from this
   repository; no manual `kubectl apply` or `helm install` for workloads.
7. **Separate applies.** AWS resources (`infra/terraform/foundation`) and the cluster
   bootstrap (`infra/terraform/bootstrap`, which installs Argo CD) are separate Terraform
   root modules with separate state and applies.
8. **Cloud portability.** Prefer Kubernetes-native, cloud-neutral components; cloud-specific
   code is confined to Terraform modules and resource annotations.
9. **Least privilege.** IAM permissions are scoped per workload (no shared node-role
   permissions for application access).
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

## Governance

- The constitution overrides other practices; a plan that breaks a principle must justify
  it in its Complexity Tracking section.
- Amendments use semantic versioning (MAJOR: principle removed or redefined; MINOR:
  principle or section added; PATCH: wording).
- Agent working rules (answering, Git workflow) live in `AGENTS.md` and are out of scope.
