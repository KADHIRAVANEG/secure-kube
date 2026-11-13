output "cluster_name" {
  description = "GKE Cluster Name"
  value       = google_container_cluster.securekube.name
}

output "cluster_endpoint" {
  description = "GKE API Server Endpoint"
  value       = google_container_cluster.securekube.endpoint
}

output "workload_identity_pool" {
  description = "GCP Workload Identity Pool"
  value       = "${var.project_id}.svc.id.goog"
}
