# SecureKube GCP GKE Terraform Module

Provisions a CIS-hardened Google Kubernetes Engine (GKE) cluster with Datapath V2 (Cilium eBPF), Shielded Nodes, Workload Identity, and Private Cluster architecture.

---

## 🛡️ Security Features

1. **Datapath V2 (Cilium eBPF)**: Native, high-performance in-kernel packet filtering with default NetworkPolicy enforcement without iptables overhead.
2. **Workload Identity Federation**: Binds Kubernetes ServiceAccounts directly to Google Cloud IAM roles, eliminating long-lived GCP service account keys.
3. **Shielded GKE Nodes**: Enforces Secure Boot and node firmware integrity monitoring.
4. **Metadata Concealment**: Configures `workload_metadata_config.mode = "GKE_METADATA"` to prevent container breakouts to Google Cloud Instance Metadata.
5. **Private Cluster**: Disables public worker node IPs and protects the control plane with master authorized network CIDRs.
6. **Automated Baseline Application**: Applies the exact same SecureKube NetworkPolicies and in-tree CEL admission policies upon cluster completion.

---

## 📋 Input Variables

| Variable | Description | Type | Default | Required |
|---|---|---|---|---|
| `project_id` | GCP Project ID | `string` | — | yes |
| `region` | GCP Compute Region | `string` | `"us-central1"` | no |
| `cluster_name` | Name of the GKE cluster | `string` | `"securekube-gke"` | no |
| `network` | VPC Network name | `string` | `"default"` | no |
| `subnetwork` | VPC Subnetwork name | `string` | `"default"` | no |
| `node_count` | Number of worker nodes per zone | `number` | `3` | no |
| `machine_type` | Compute Engine instance type | `string` | `"e2-standard-4"` | no |

---

## 📤 Outputs

| Output | Description |
|---|---|
| `cluster_name` | The GKE cluster identifier |
| `cluster_endpoint` | The IP address of the Kubernetes API server |
| `ca_certificate` | Base64-encoded public CA certificate of the cluster |
| `workload_identity_pool` | Workload Identity Pool for GCP IAM bindings |

---

## 🚀 Usage

```bash
cd terraform/gke
terraform init

# Plan with your GCP project
terraform plan -var="project_id=my-hardened-gcp-project"

terraform apply -auto-approve
```
