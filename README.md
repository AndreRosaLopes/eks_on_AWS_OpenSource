# EKS on AWS

## Contents

1. [Objective](#1-objective)
2. [Repository structure](#2-repository-structure)
3. [Setup](#3-setup)
4. [Deploy and teardown](#4-deploy-and-teardown)

## 1. Objective

Build a data platform on Amazon EKS, preferably with open source tools, organized as a monorepo with two main areas:

- **Infrastructure:** provisioning of AWS services (VPC, EKS and related resources) with Terraform, and of the components that run inside the cluster with Argo CD.
- **Data:** data engineering (Airflow DAGs, Python and SQL) and analytics.

The project has a single environment: `dev`.

## 2. Repository structure

```
.
├── AGENTS.md                   # instructions for AI agents
├── README.md
├── .env.example                # names of the secrets; copy to .env (not versioned)
├── .github/workflows/          # validation of every change (Terraform and YAML)
├── .mcp.json                   # project MCP servers (Terraform); created by the setup
├── .specify/                   # Spec Kit constitution, templates and scripts; created by the setup
├── .claude/skills/             # Spec Kit skills for Claude Code; created by the setup
├── docs/
│   ├── setup.md                # AI tooling setup
│   └── architecture/           # current state of the system
├── specs/                      # Spec Kit: one folder per feature
│   └── NNN-<feature>/
│       ├── spec.md             # what and why: requirements and acceptance criteria
│       ├── plan.md             # how: technical decisions
│       ├── tasks.md            # ordered, verifiable tasks
│       └── prompts/            # implementation prompts, one per task
├── infra/
│   ├── terraform/
│   │   ├── state/              # once: bucket of the Terraform state (local state)
│   │   ├── data/               # once: bucket of the platform data, never destroyed
│   │   ├── foundation/         # apply 1: AWS resources (VPC, EKS, IAM, tool buckets)
│   │   └── bootstrap/          # apply 2: Argo CD, root Application, Secrets from .env
│   └── platform/               # workloads running inside EKS, synced by Argo CD
│       ├── argocd/             # Argo CD Applications, one per component
│       └── apps/
│           └── <component>/    # Helm values for each component (e.g., airflow)
├── data-engineering/
│   ├── dags/                   # Airflow DAGs
│   ├── src/                    # Python code (ingestion, utilities)
│   │   └── spark/              # Spark jobs
│   ├── sql/                    # SQL scripts
│   └── tests/
│       └── unit/               # unit tests (pytest), run locally without AWS
├── analytics/                  # to be defined
└── scripts/
    ├── teardown.sh             # ordered teardown without orphan cloud resources
    └── verify/                 # acceptance checks against the real environment
```

## 3. Setup

See [docs/setup.md](docs/setup.md) to set up the AI tooling: Claude Code, AWS, Terraform and Spec Kit.

## 4. Deploy and teardown

Commands run in Git Bash from the repository root, with AWS credentials for the account.

```bash
cp .env.example .env                  # fill in the passwords (never commit .env)
set -a; source .env; set +a

terraform -chdir=infra/terraform/state init && terraform -chdir=infra/terraform/state apply   # once
terraform -chdir=infra/terraform/data init && terraform -chdir=infra/terraform/data apply     # once
terraform -chdir=infra/terraform/foundation init && terraform -chdir=infra/terraform/foundation apply
aws eks update-kubeconfig --name data-platform-dev --region us-east-2
terraform -chdir=infra/terraform/bootstrap init && terraform -chdir=infra/terraform/bootstrap apply
```

Argo CD then syncs every component in `infra/platform/argocd/` from the `main` branch. Its UI is
reached with `kubectl -n argocd port-forward svc/argocd-server 8080:443`.

Acceptance checks: `scripts/verify/<step>.sh` (see `specs/001-data-platform-infra/quickstart.md`).

Teardown (keeps the data and state buckets): `scripts/teardown.sh`.
