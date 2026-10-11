# Self-signed certificate of Trino (D-028). External clients verify only the certificate
# authority (SSLVerification=CA) because the NLB name changes when the cluster is recreated.
resource "tls_private_key" "trino" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "trino" {
  private_key_pem = tls_private_key.trino.private_key_pem

  subject {
    common_name  = "trino"
    organization = "data-platform-dev"
  }

  dns_names = [
    "trino",
    "trino.trino.svc",
    "trino.trino.svc.cluster.local",
    "localhost",
  ]

  validity_period_hours = 8760
  early_renewal_hours   = 720
  is_ca_certificate     = true

  allowed_uses = [
    "digital_signature",
    "key_encipherment",
    "server_auth",
    "cert_signing",
  ]
}

resource "kubernetes_secret_v1" "trino_tls" {
  metadata {
    name      = "trino-tls"
    namespace = kubernetes_namespace_v1.platform["trino"].metadata[0].name
  }

  data = {
    "trino.pem" = "${tls_private_key.trino.private_key_pem_pkcs8}${tls_self_signed_cert.trino.cert_pem}"
  }
}

output "trino_ca_certificate" {
  description = "Certificate that Trino clients trust (not secret)."
  value       = tls_self_signed_cert.trino.cert_pem
}
