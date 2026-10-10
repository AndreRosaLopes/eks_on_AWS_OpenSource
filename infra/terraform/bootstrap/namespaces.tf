# Namespaces that receive Secrets from this apply before Argo CD syncs the components (D-011).
resource "kubernetes_namespace_v1" "platform" {
  for_each = toset([
    "polaris",
    "airbyte",
    "sample-source",
    "trino",
    "airflow",
    "metabase",
    "observability",
    "openmetadata",
  ])

  metadata {
    name = each.value
  }
}
