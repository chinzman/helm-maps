# =============================================================================
# IaC — Terraform: Deploy ml-api-chart to EKS via helm_release
# =============================================================================
# This is a representative root module showing how the Helm chart is consumed
# in a real EKS deployment pipeline.
#
# Assumed pre-existing infrastructure:
#   - AWS EKS cluster, VPC, node groups
#   - GHCR credentials stored in AWS Secrets Manager
#   - IAM roles for Service Accounts (IRSA)
# =============================================================================

# ---------------------------------------------------------------------------
# Data sources — look up the existing EKS cluster
# ---------------------------------------------------------------------------

data "aws_eks_cluster" "cluster" {
  name = var.eks_cluster_name
}

data "aws_eks_cluster_auth" "cluster" {
  name = var.eks_cluster_name
}

# ---------------------------------------------------------------------------
# Namespace
# ---------------------------------------------------------------------------

resource "kubernetes_namespace" "ml_api" {
  metadata {
    name = "ml-${var.environment}"
    labels = {
      environment = var.environment
      managed-by  = "terraform"
    }
  }
}

# ---------------------------------------------------------------------------
# Helm Release — deploys the chart from the OCI registry
# ---------------------------------------------------------------------------

locals {
  # Map environment name to the corresponding values file path
  values_file_map = {
    dev     = "${path.module}/../values/values-dev.yaml"
    staging = "${path.module}/../values/values-staging.yaml"
    prod    = "${path.module}/../values/values-prod.yaml"
  }
}

resource "helm_release" "ml_api" {
  name       = "ml-api-${var.environment}"
  repository = "oci://ghcr.io/your-org/helm-charts"
  chart      = "ml-api-chart"
  version    = var.chart_version
  namespace  = kubernetes_namespace.ml_api.metadata[0].name

  # Use the pre-authored environment values file
  values = [
    file(local.values_file_map[var.environment])
  ]

  # Override just the image tag — chart version and image version are independent
  set {
    name  = "image.tag"
    value = var.image_tag
  }

  # Atomic install: rolls back automatically on failure
  atomic          = true
  cleanup_on_fail = true

  # Give large models time to pull
  timeout = 300

  depends_on = [kubernetes_namespace.ml_api]

  lifecycle {
    # Note: Terraform requires prevent_destroy to be a static literal boolean (no dynamic expressions).
    # In production root modules/workspaces, set prevent_destroy = true to guard against accidental deletion.
    prevent_destroy = false
  }
}
