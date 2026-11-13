# SecureKube GCP GKE Terraform Module

Provisions a CIS-hardened Google Kubernetes Engine (GKE) cluster with Datapath V2, Shielded Nodes, and Workload Identity.

---

## 🛡️ Security Features

1. **Datapath V2 (Cilium eBPF)**: Native, high-performance in-kernel packet filtering with default NetworkPolicy enforcement without iptables overhead.
2. **Workload Identity Federation**: Binds Kubernetes ServiceAccounts directly to Google Cloud IAM roles, eliminating long-lived GCP service account keys.
3. **Shielded GKE Nodes**: Enforces Secure Boot and node firmware integrity monitoring.
4. **Metadata Concealment**: Configures `workload_metadata_config.mode = "GKE_METADATA"` to prevent container breakouts to Google Cloud Instance Metadata.
5. **Private Cluster**: Disables public worker node IPs and protects the control plane with master authorized network CIDRs.
6. **Automated Baseline Application**: Applies the exact same SecureKube NetworkPolicies and in-tree CEL admission policies upon cluster completion.

---

## 🚀 Usage

```bash
cd terraform/gke
terraform init
terraform plan -var="project_id=my-gcp-project"
terraform apply -auto-approve
```
