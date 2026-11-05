"""Renders architecture.png — the deployed Mod9 Secure CI/CD (ECS + SAST/SCA/Image/SBOM/Secret Scan) infra.

The `diagrams` library over Graphviz, with real AWS service icons.

    pip install diagrams          # needs Graphviz on PATH: apt install graphviz
    python architecture.py
"""

from diagrams import Cluster, Diagram, Edge
from diagrams.aws.compute import ECR, Fargate
from diagrams.aws.management import Cloudwatch
from diagrams.aws.network import ALB, InternetGateway
from diagrams.aws.security import IAM
from diagrams.aws.storage import S3
from diagrams.onprem.ci import Jenkins
from diagrams.onprem.client import User
from diagrams.onprem.monitoring import Prometheus
from diagrams.onprem.vcs import Github

graph_attr = {
    "fontsize": "22",
    "labelloc": "t",
    "pad": "0.75",
    "nodesep": "1.1",
    "ranksep": "1.7",
    "splines": "spline",
}
edge_attr = {"fontsize": "12"}

with Diagram(
    "Mod9 — Secure CI/CD Pipeline (ECS Fargate + SAST/SCA/Image/SBOM/Secret Scan)",
    filename="architecture",
    show=False,
    direction="TB",
    graph_attr=graph_attr,
    edge_attr=edge_attr,
):
    user = User("End User")
    gh = Github("GitHub\n(secure-cicd-ecs)")
    jenkins = Jenkins("Jenkins\nMultibranch + shared lib")

    with Cluster("AWS · eu-west-1 (sandbox)"):
        with Cluster("Managed / regional services"):
            ecr = ECR("ECR\n(immutable tags · scan on push · lifecycle)")
            cw = Cloudwatch("CloudWatch\n(log group · 6 alarms · dashboard · SNS)")
            iam = IAM("IAM\ntask + execution roles")

        with Cluster("VPC · public subnets"):
            igw = InternetGateway("Internet Gateway")
            alb = ALB("ALB\n(HTTP :80)")

            with Cluster("ECS cluster · Fargate"):
                app = Fargate("secure-cicd-app\n(2 tasks · non-root · port 8080)")

    # --- ingress -----------------------------------------------------------
    user >> Edge(label="HTTP") >> igw >> Edge(label="") >> alb
    alb >> Edge(label="/version /health /checkout") >> app

    # --- delivery pipeline -------------------------------------------------
    gh >> Edge(label="git push / webhook") >> jenkins
    jenkins >> Edge(label="scan (Gitleaks · SonarQube · Dep-Check · Trivy · Syft)") >> jenkins
    jenkins >> Edge(label="push image") >> ecr
    ecr >> Edge(style="dashed", label="image pull (digest)") >> app
    jenkins >> Edge(label="render + register task def · rolling update") >> app

    # --- supporting (dashed) -----------------------------------------------
    app >> Edge(style="dashed", label="JSON logs (trace_id)") >> cw
    iam >> Edge(style="dashed", label="grants permissions") >> app
    jenkins >> Edge(style="dashed", label="record deploy → env/dev") >> gh
