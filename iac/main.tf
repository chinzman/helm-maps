# =============================================================================
# IaC — Terraform: Deploy ml-api-chart to EKS via helm_release
# =============================================================================
# This is a representative snippet, NOT a complete Terraform root module.
# It shows how the Helm chart would be consumed via IaC in a real deployment.
#
# Assumed pre-existing resources (managed elsewhere):
#   - AWS EKS cluster
#   - VPC and node groups
#   - GHCR credentials stored in AWS Secrets Manager
#   - IAM role for IRSA
# =============================================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.13"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# ---------------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------------

variable "environment" {
  description = "Deployment environment (dev / staging / prod)"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod"
  }
}

variable "chart_version" {
  description = "Version of the ml-api Helm chart to deploy"
  type        = string
}

variable "image_tag" {
  description = "Docker image tag for the ML API"
  type        = string
}

variable "eks_cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "ghcr_username" {
  description = "GitHub username or service account for pulling OCI charts"
  type        = string
  default     = ""
}

variable "ghcr_token" {
  description = "GitHub personal access token or CI secret for GHCR"
  type        = string
  sensitive   = true
  default     = ""
}

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
# Providers — connect to the EKS cluster
# ---------------------------------------------------------------------------

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.cluster.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }

  # Authenticate to GHCR to pull the chart
  registry {
    url      = "oci://ghcr.io"
    username = var.ghcr_username
    password = var.ghcr_token  # Passed via tfvars or CI secret; never hardcoded
  }
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

# ---------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------

output "release_name" {
  description = "Helm release name"
  value       = helm_release.ml_api.name
}

output "release_namespace" {
  description = "Kubernetes namespace"
  value       = helm_release.ml_api.namespace
}

output "chart_version_deployed" {
  description = "Chart version that was deployed"
  value       = helm_release.ml_api.version
}
