# =============================================================================
# Outputs
# =============================================================================

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
