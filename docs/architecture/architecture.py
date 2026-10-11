"""Architecture diagram of the data platform (EKS on AWS).

Render from this directory (requires Graphviz on PATH):
    uv run --with diagrams==0.25.1 python architecture.py
Output: architecture.png
"""

from diagrams import Cluster, Diagram, Edge
from diagrams.aws.compute import EC2AutoScaling, EC2SpotInstance, EKS
from diagrams.aws.general import Users
from diagrams.aws.network import NATGateway, NLB, Endpoint, InternetGateway
from diagrams.aws.security import IAMRole
from diagrams.aws.storage import EBS, S3
from diagrams.k8s.compute import Pod
from diagrams.onprem.analytics import Metabase, Trino
from diagrams.onprem.database import PostgreSQL
from diagrams.onprem.gitops import ArgoCD
from diagrams.onprem.monitoring import Grafana, Prometheus
from diagrams.onprem.network import Envoy
from diagrams.onprem.vcs import Github
from diagrams.onprem.workflow import Airflow

graph_attr = {"fontsize": "20", "pad": "0.5", "splines": "spline", "nodesep": "0.6", "ranksep": "0.9"}

with Diagram(
    "Data platform on Amazon EKS",
    filename="architecture",
    outformat="png",
    show=False,
    direction="LR",
    graph_attr=graph_attr,
):
    users = Users("Analysts / BI users")
    repo = Github("GitHub repo\n(GitOps source)")

    with Cluster("AWS account - us-east-2"):
        with Cluster("Amazon S3"):
            data_bucket = S3("data\n(bronze/silver/gold)")
            tool_buckets = S3("airflow-logs\nairbyte")

        node_role = IAMRole("Node role\n(S3, autoscaler, LBC)")
        ebs = EBS("EBS gp3\n(PVCs)")

        with Cluster("VPC (2 AZs)"):
            igw = InternetGateway("Internet gateway")
            s3_endpoint = Endpoint("S3 gateway\nendpoint")

            with Cluster("Public subnets"):
                nlb = NLB("NLB\n:80 BI, :8443 Trino")
                nat = NATGateway("NAT gateway\n(single)")

            with Cluster("Private subnets"):
                eks = EKS("EKS 1.36")

                with Cluster("Managed node groups (m7g.large, arm64)"):
                    base = EC2AutoScaling("base\nOn-Demand 1-3")
                    spot = EC2SpotInstance("spot\n0-6")

                with Cluster("Platform"):
                    argocd = ArgoCD("Argo CD")
                    envoy = Envoy("Envoy Gateway")
                    lbc = Pod("AWS LB\nController")
                    autoscaler = Pod("Cluster\nAutoscaler")

                with Cluster("Ingestion"):
                    source = PostgreSQL("Sample source")
                    airbyte = Pod("Airbyte")

                with Cluster("Catalog and processing"):
                    polaris = Pod("Polaris\n(Iceberg REST)")
                    trino = Trino("Trino")

                orchestration = Airflow("Airflow")

                with Cluster("BI"):
                    metabase = Metabase("Metabase")

                with Cluster("Observability"):
                    prometheus = Prometheus("Prometheus\nAlertmanager")
                    grafana = Grafana("Grafana")
                    opencost = Pod("OpenCost")

                with Cluster("Governance"):
                    openmetadata = Pod("OpenMetadata")
                    opensearch = Pod("OpenSearch")

    # Delivery
    repo >> Edge(label="sync", style="dashed") >> argocd
    argocd >> Edge(style="dashed") >> eks

    # Access
    users >> igw >> nlb >> envoy
    envoy >> Edge(label="HTTP") >> metabase
    envoy >> Edge(label="TLS 8443") >> trino
    lbc >> Edge(style="dotted") >> nlb

    # Data flow
    source >> airbyte >> data_bucket
    airbyte >> polaris
    metabase >> trino
    trino >> polaris
    trino >> data_bucket
    orchestration >> Edge(label="queries / scale workers") >> trino
    orchestration >> tool_buckets

    # Governance and observability
    openmetadata >> Edge(label="metadata") >> trino
    openmetadata >> opensearch
    prometheus >> grafana
    opencost >> prometheus

    # Infrastructure
    eks >> [base, spot]
    autoscaler >> Edge(style="dotted") >> [base, spot]
    base >> Edge(style="dotted") >> ebs
    base >> Edge(style="dotted") >> node_role
    base >> nat >> igw
    data_bucket << Edge(label="S3 traffic") << s3_endpoint
