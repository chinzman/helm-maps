# =============================================================================
# Input Variables
# =============================================================================

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
