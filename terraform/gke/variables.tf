variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP region for GKE cluster"
  type        = string
  default     = "us-central1"
}

variable "cluster_name" {
  description = "Name of the SecureKube GKE cluster"
  type        = string
  default     = "securekube-gke"
}

variable "network" {
  description = "VPC Network name"
  type        = string
  default     = "default"
}

variable "subnetwork" {
  description = "VPC Subnetwork name"
  type        = string
  default     = "default"
}

variable "node_count" {
  description = "Initial worker node count per zone"
  type        = number
  default     = 1
}

variable "machine_type" {
  description = "Compute Engine machine type for hardened nodes"
  type        = string
  default     = "e2-standard-4"
}
