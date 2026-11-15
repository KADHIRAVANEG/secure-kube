# AWS EKS CIS-Hardened Deployment

SecureKube provides production Terraform scaffolding in `terraform/eks` to provision an enterprise-grade, CIS-compliant Amazon EKS cluster that enforces the exact same security policies applied in local Kind development.

---

## 🛡️ Security Features

1. **CIS Control Plane Logging**: Automatically streams `api`, `audit`, `authenticator`, `controllerManager`, and `scheduler` logs to AWS CloudWatch with configurable retention.
2. **KMS Envelope Encryption**: All Kubernetes Secrets are encrypted at rest with a dedicated customer-managed AWS KMS key (`aws_kms_key.eks`).
3. **IMDSv2 Enforced**: Worker EC2 nodes require token-based metadata access (`http_tokens = "required"`, `http_put_response_hop_limit = 1`), defeating SSRF container metadata escape attacks.
4. **IAM Roles for Service Accounts (IRSA)**: Pre-configured OpenID Connect (OIDC) provider allows least-privilege pod IAM roles without static AWS credentials.
5. **Private API Endpoint**: Configurable public/private endpoint access with CIDR block whitelisting.
6. **Automated Baseline Application**: Applies the exact same SecureKube NetworkPolicies, least-privilege RBAC, and in-tree CEL admission policies upon cluster completion.

---

## 📋 Input Variables

| Variable | Description | Type | Default | Required |
|---|---|---|---|---|
| `cluster_name` | Name of the EKS cluster | `string` | `"securekube-eks"` | no |
| `cluster_version` | Kubernetes version | `string` | `"1.31"` | no |
| `vpc_id` | AWS VPC ID where cluster is provisioned | `string` | — | yes |
| `subnet_ids` | List of subnet IDs for control plane and nodes | `list(string)` | — | yes |
| `node_instance_types` | EC2 instance types for managed node group | `list(string)` | `["t3.large"]` | no |
| `min_nodes` | Minimum worker node count | `number` | `2` | no |
| `max_nodes` | Maximum worker node count | `number` | `5` | no |
| `desired_nodes` | Initial desired worker node count | `number` | `3` | no |

---

## 🚀 Deployment Steps

```bash
cd terraform/eks
terraform init

# Validate configuration
make cloud-eks

# Plan and apply
terraform plan -var="vpc_id=vpc-0123456789abcdef0" -var='subnet_ids=["subnet-a", "subnet-b", "subnet-c"]'
terraform apply -var="vpc_id=vpc-0123456789abcdef0" -var='subnet_ids=["subnet-a", "subnet-b", "subnet-c"]'
```
