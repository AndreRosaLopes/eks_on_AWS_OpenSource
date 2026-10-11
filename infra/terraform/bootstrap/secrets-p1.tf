# P1 Ingestion secrets from .env (D-011).
variable "polaris_db_password" {
  type      = string
  sensitive = true
}

variable "polaris_root_client_secret" {
  type      = string
  sensitive = true
}

variable "sample_source_db_password" {
  type      = string
  sensitive = true
}

resource "kubernetes_secret_v1" "polaris_db" {
  metadata {
    name      = "polaris-db"
    namespace = kubernetes_namespace_v1.platform["polaris"].metadata[0].name
  }

  data = {
    username = "polaris"
    password = var.polaris_db_password
    jdbcUrl  = "jdbc:postgresql://polaris-postgres.polaris.svc:5432/polaris?currentSchema=polaris_schema"
  }
}

resource "kubernetes_secret_v1" "polaris_root" {
  metadata {
    name      = "polaris-root"
    namespace = kubernetes_namespace_v1.platform["polaris"].metadata[0].name
  }

  data = {
    clientId     = "root"
    clientSecret = var.polaris_root_client_secret
  }
}

resource "kubernetes_secret_v1" "sample_source_db" {
  metadata {
    name      = "sample-source-db"
    namespace = kubernetes_namespace_v1.platform["sample-source"].metadata[0].name
  }

  data = {
    password = var.sample_source_db_password
  }
}
