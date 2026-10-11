# Trino users, groups and internal secret from .env (D-011, D-026).
variable "trino_admin_password" {
  type      = string
  sensitive = true
}

variable "trino_metabase_password" {
  type      = string
  sensitive = true
}

variable "trino_external_users" {
  description = "Map of external system user name to password (FR-013)."
  type        = map(string)
  sensitive   = true
}

variable "trino_shared_secret" {
  type      = string
  sensitive = true
}

locals {
  trino_users = merge(
    {
      admin    = var.trino_admin_password
      metabase = var.trino_metabase_password
    },
    var.trino_external_users,
  )
}

# bcrypt() salts differently on every run: the file is rebuilt only when a password changes.
resource "terraform_data" "trino_passwords" {
  input = sha256(jsonencode(local.trino_users))
}

resource "kubernetes_secret_v1" "trino_password_file" {
  metadata {
    name      = "trino-password-file"
    namespace = kubernetes_namespace_v1.platform["trino"].metadata[0].name
  }

  data = {
    "password.db" = join("\n", [
      for user in sort(keys(local.trino_users)) :
      "${user}:${replace(bcrypt(local.trino_users[user], 10), "$2a$", "$2y$")}"
    ])
  }

  lifecycle {
    ignore_changes       = [data]
    replace_triggered_by = [terraform_data.trino_passwords]
  }
}

resource "kubernetes_secret_v1" "trino_groups" {
  metadata {
    name      = "trino-groups"
    namespace = kubernetes_namespace_v1.platform["trino"].metadata[0].name
  }

  data = {
    "group.db" = join("\n", [
      "technical_team:admin",
      "bi:metabase",
      "external:${join(",", sort(nonsensitive(keys(var.trino_external_users))))}",
    ])
  }
}

resource "kubernetes_secret_v1" "trino_shared_secret" {
  metadata {
    name      = "trino-shared-secret"
    namespace = kubernetes_namespace_v1.platform["trino"].metadata[0].name
  }

  data = {
    secret = var.trino_shared_secret
  }
}

# Polaris root credential used by the Trino Iceberg catalog.
resource "kubernetes_secret_v1" "trino_polaris" {
  metadata {
    name      = "trino-polaris"
    namespace = kubernetes_namespace_v1.platform["trino"].metadata[0].name
  }

  data = {
    clientSecret = var.polaris_root_client_secret
  }
}
