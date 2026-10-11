# P4 BI secrets from .env (D-011) and the Trino certificate for Metabase (D-028).
variable "metabase_db_password" {
  type      = string
  sensitive = true
}

resource "kubernetes_secret_v1" "metabase_db" {
  metadata {
    name      = "metabase-db"
    namespace = kubernetes_namespace_v1.platform["metabase"].metadata[0].name
  }

  data = {
    password = var.metabase_db_password
  }
}

resource "kubernetes_secret_v1" "metabase_trino_ca" {
  metadata {
    name      = "trino-ca"
    namespace = kubernetes_namespace_v1.platform["metabase"].metadata[0].name
  }

  data = {
    "trino-ca.pem" = tls_self_signed_cert.trino.cert_pem
  }
}
