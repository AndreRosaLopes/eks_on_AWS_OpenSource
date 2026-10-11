# P3 Orchestration secrets from .env (D-011).
variable "airflow_api_secret_key" {
  type      = string
  sensitive = true
}

variable "airflow_admin_password" {
  type      = string
  sensitive = true
}

resource "kubernetes_secret_v1" "airflow_api_secret" {
  metadata {
    name      = "airflow-api-secret"
    namespace = kubernetes_namespace_v1.platform["airflow"].metadata[0].name
  }

  data = {
    "api-secret-key" = var.airflow_api_secret_key
  }
}

resource "kubernetes_secret_v1" "airflow_admin" {
  metadata {
    name      = "airflow-admin"
    namespace = kubernetes_namespace_v1.platform["airflow"].metadata[0].name
  }

  data = {
    password = var.airflow_admin_password
  }
}
