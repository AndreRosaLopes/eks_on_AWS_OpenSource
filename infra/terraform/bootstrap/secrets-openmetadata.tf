# P6 Governance secret from .env (D-011): MySQL bundled with OpenMetadata (D-010).
variable "openmetadata_db_password" {
  type      = string
  sensitive = true
}

resource "kubernetes_secret_v1" "openmetadata_mysql" {
  metadata {
    name      = "openmetadata-mysql"
    namespace = kubernetes_namespace_v1.platform["openmetadata"].metadata[0].name
  }

  data = {
    mysql-root-password = var.openmetadata_db_password
    mysql-password      = var.openmetadata_db_password
  }
}
