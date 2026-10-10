# EKS on AWS

## Contents

1. [Objective](#1-objective)
2. [Repository structure](#2-repository-structure)
3. [Setup](#3-setup)

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
│   │   ├── foundation/         # apply 1: AWS resources (VPC, EKS, IAM, S3)
│   │   └── bootstrap/          # apply 2: installs Argo CD in the cluster
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
    └── verify/                 # acceptance checks against the real environment
```

## 3. Setup

See [docs/setup.md](docs/setup.md) to set up the AI tooling: Claude Code, AWS, Terraform and Spec Kit.
