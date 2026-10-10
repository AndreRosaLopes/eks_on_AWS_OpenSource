# Argo CD with reduced components (N-001); UI only through kubectl port-forward.
resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "10.10.2"

  values = [yamlencode({
    dex = {
      enabled = false
    }
    notifications = {
      enabled = false
    }
    applicationSet = {
      replicas = 0
    }
    controller = {
      resources = { requests = { cpu = "250m", memory = "512Mi" } }
    }
    repoServer = {
      resources = { requests = { cpu = "100m", memory = "256Mi" } }
    }
    server = {
      service   = { type = "ClusterIP" }
      resources = { requests = { cpu = "50m", memory = "128Mi" } }
    }
    redis = {
      resources = { requests = { cpu = "50m", memory = "128Mi" } }
    }
  })]
}

# Root Application: one Application per component in infra/platform/argocd/ (app of apps).
# No cascade finalizer: deleting it leaves the component Applications in place (D-029).
resource "helm_release" "root_app" {
  name       = "root"
  namespace  = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version    = "2.0.6"

  values = [yamlencode({
    applications = {
      root = {
        namespace = "argocd"
        project   = "default"
        source = {
          repoURL        = var.repo_url
          targetRevision = var.repo_revision
          path           = "infra/platform/argocd"
        }
        destination = {
          server    = "https://kubernetes.default.svc"
          namespace = "argocd"
        }
        syncPolicy = {
          automated = {
            prune    = true
            selfHeal = true
          }
        }
      }
    }
  })]

  depends_on = [helm_release.argocd]
}

# Helm OCI repository of the Envoy Gateway chart (public, no credential).
resource "kubernetes_secret_v1" "argocd_repo_envoyproxy" {
  metadata {
    name      = "repo-envoyproxy"
    namespace = "argocd"
    labels = {
      "argocd.argoproj.io/secret-type" = "repository"
    }
  }

  data = {
    name      = "envoyproxy"
    type      = "helm"
    url       = "docker.io/envoyproxy"
    enableOCI = "true"
  }

  depends_on = [helm_release.argocd]
}
