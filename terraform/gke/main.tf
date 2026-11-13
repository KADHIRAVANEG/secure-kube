# SecureKube Google Kubernetes Engine (GKE) Hardening Module
# Implements CIS GKE Benchmark, Datapath V2 (Cilium eBPF), Shielded Nodes, and Workload Identity.

provider "google" {
  project = var.project_id
  region  = var.region
}

# ── 1. GKE Hardened Private Cluster ──────────────────────────────────
resource "google_container_cluster" "securekube" {
  name     = var.cluster_name
  location = var.region

  # Separate node pool for immutable hardening lifecycle
  remove_default_node_pool = true
  initial_node_count       = 1

  network    = var.network
  subnetwork = var.subnetwork

  # CIS GKE Control: Datapath V2 (Cilium eBPF networking & NetworkPolicy enforcement)
  datapath_provider = "ADVANCED_DATAPATH"

  # CIS GKE Control: Private cluster configuration
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  # CIS GKE Control: Workload Identity Federation
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # CIS GKE Control: Binary Authorization
  binary_authorization {
    evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"
  }

  # Control Plane Logging
  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "APISERVER", "CONTROLLER_MANAGER", "SCHEDULER"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS", "APISERVER", "CONTROLLER_MANAGER", "SCHEDULER"]
    managed_prometheus {
      enabled = true
    }
  }

  # Release Channel
  release_channel {
    channel = "REGULAR"
  }

  ip_allocation_policy {}
}

# ── 2. Dedicated IAM Service Account for GKE Nodes ───────────────────
resource "google_service_account" "gke_node_sa" {
  account_id   = "${var.cluster_name}-node-sa"
  display_name = "SecureKube GKE Hardened Node Service Account"
}

resource "google_project_iam_member" "node_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.gke_node_sa.email}"
}

resource "google_project_iam_member" "node_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.gke_node_sa.email}"
}

resource "google_project_iam_member" "node_monitoring_viewer" {
  project = var.project_id
  role    = "roles/monitoring.viewer"
  member  = "serviceAccount:${google_service_account.gke_node_sa.email}"
}

# ── 3. Hardened Shielded Node Pool ───────────────────────────────────
resource "google_container_node_pool" "hardened_nodes" {
  name       = "${var.cluster_name}-node-pool"
  location   = var.region
  cluster    = google_container_cluster.securekube.name
  node_count = var.node_count

  node_config {
    machine_type    = var.machine_type
    service_account = google_service_account.gke_node_sa.email

    # CIS GKE Control: Shielded GKE Nodes
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    # Restrict metadata access (Blocks SSRF container metadata attacks)
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    labels = {
      environment = "production"
      managed_by  = "securekube"
    }
  }
}

# ── 4. Apply SecureKube Zero-Trust Baseline ───────────────────────────
resource "null_resource" "apply_securekube_baseline" {
  triggers = {
    cluster_endpoint = google_container_cluster.securekube.endpoint
  }

  provisioner "local-exec" {
    command = <<-EOT
      gcloud container clusters get-credentials ${var.cluster_name} --region ${var.region} --project ${var.project_id}
      kubectl apply -k ../../kustomize/base
      kubectl apply -k ../../kustomize/base/vap
    EOT
  }

  depends_on = [google_container_node_pool.hardened_nodes]
}
