# P5 Observability secrets from .env (D-011, D-024). Without an SMTP host, alerts go to a null
# receiver until the SMTP settings are filled in .env.
variable "grafana_admin_password" {
  type      = string
  sensitive = true
}

variable "smtp_host" {
  type    = string
  default = ""
}

variable "smtp_port" {
  type    = number
  default = 587
}

variable "smtp_username" {
  type    = string
  default = ""
}

variable "smtp_password" {
  type      = string
  default   = ""
  sensitive = true
}

variable "alert_email_from" {
  type    = string
  default = ""
}

variable "alert_email_to" {
  type    = string
  default = ""
}

locals {
  email_enabled = var.smtp_host != "" && var.alert_email_to != ""

  # Alerts that only check the alerting pipeline are dropped.
  alertmanager_routes = [
    { receiver = "null", matchers = ["alertname = Watchdog"] },
    { receiver = "null", matchers = ["alertname = InfoInhibitor"] },
  ]

  alertmanager_config_email = yamlencode({
    global = {
      smtp_smarthost     = "${var.smtp_host}:${var.smtp_port}"
      smtp_from          = var.alert_email_from
      smtp_auth_username = var.smtp_username
      smtp_auth_password = var.smtp_password
      smtp_require_tls   = true
    }
    route = {
      receiver        = "technical-team"
      group_by        = ["alertname", "namespace"]
      group_wait      = "30s"
      group_interval  = "5m"
      repeat_interval = "4h"
      routes          = local.alertmanager_routes
    }
    receivers = [
      { name = "null" },
      {
        name          = "technical-team"
        email_configs = [{ to = var.alert_email_to, send_resolved = true }]
      },
    ]
  })

  alertmanager_config_null = yamlencode({
    route = {
      receiver = "null"
      routes   = local.alertmanager_routes
    }
    receivers = [{ name = "null" }]
  })
}

resource "kubernetes_secret_v1" "grafana_admin" {
  metadata {
    name      = "grafana-admin"
    namespace = kubernetes_namespace_v1.platform["observability"].metadata[0].name
  }

  data = {
    admin-user     = "admin"
    admin-password = var.grafana_admin_password
  }
}

resource "kubernetes_secret_v1" "alertmanager_config" {
  metadata {
    name      = "alertmanager-config"
    namespace = kubernetes_namespace_v1.platform["observability"].metadata[0].name
  }

  data = {
    "alertmanager.yaml" = local.email_enabled ? local.alertmanager_config_email : local.alertmanager_config_null
  }
}
