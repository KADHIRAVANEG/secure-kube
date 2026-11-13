# SecureKube AWS EKS Terraform Module

Provisions a production-grade, CIS-hardened Amazon EKS cluster with full policy enforcement and zero-trust defaults.

---

## 🛡️ Security Features

1. **CIS Control Plane Logging**: Automatically streams `api`, `audit`, `authenticator`, `controllerManager`, and `scheduler` logs to AWS CloudWatch.
2. **KMS Envelope Encryption**: All Kubernetes Secrets are encrypted at rest with a dedicated customer-managed AWS KMS key.
3. **IMDSv2 Enforced**: Worker EC2 nodes require token-based metadata access (`http_tokens = "required"`, `http_put_response_hop_limit = 1`), defeating SSRF container metadata escape attacks.
4. **IAM Roles for Service Accounts (IRSA)**: Pre-configured OpenID Connect (OIDC) provider allows least-privilege pod IAM roles without AWS access keys.
5. **Automated Baseline Application**: Applies the exact same SecureKube NetworkPolicies, least-privilege RBAC, and in-tree CEL admission policies upon cluster completion.

---

## 🚀 Usage

```bash
cd terraform/eks
terraform init
terraform plan -var="subnet_ids=[\"subnet-xxx\",\"subnet-yyy\"]"
terraform apply -auto-approve
```
