# EKS on AWS

## 1. Objective

Build a data platform on Amazon EKS, preferably with open source tools, organized as a monorepo with two main areas:

- **Infrastructure:** provisioning of AWS services (VPC, EKS and related resources) with Terraform, and of the components that run inside the cluster with Argo CD.
- **Data:** data engineering (Airflow DAGs, Python and SQL) and analytics.

The project has a single environment: `dev`.

## 2. Repository structure

```
.
├── AGENTS.md                   # instructions for AI agents
├── infra/
│   ├── terraform/
│   │   ├── modules/            # reusable modules: vpc, eks, iam, s3...
│   │   ├── foundation/         # apply 1: AWS resources (VPC, EKS, IAM, S3)
│   │   └── bootstrap/          # apply 2: installs Argo CD in the cluster
│   └── platform/               # workloads running inside EKS, synced by Argo CD
│       ├── argocd/             # Argo CD Applications, one per component
│       └── apps/
│           └── <component>/    # Helm values for each component (e.g., airflow)
├── data-engineering/
│   ├── dags/                   # Airflow DAGs
│   ├── src/                    # Python code (ingestion, utilities)
│   ├── sql/                    # SQL scripts
│   └── tests/
└── analytics/                  # to be defined
```

