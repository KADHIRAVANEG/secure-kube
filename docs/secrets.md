# Enterprise Secret Management

SecureKube provides a dual-layer secret management architecture designed for both local GitOps workflows and multi-cloud enterprise production deployments.

---

## 🔀 Two Operational Models

| Capability | Local GitOps (SOPS + Age) | Enterprise Vaults (ESO) |
|---|---|---|
| **Primary Tool** | Mozilla SOPS + Age CLI | External Secrets Operator (ESO) |
| **Best For** | Offline development, local Kind clusters, pure GitOps repos | Production clouds (AWS, GCP, Vault, Azure) |
| **Key Location** | Developer workstation (`~/.config/sops/age/keys.txt`) | Managed Cloud KMS / IAM Role / Vault AppRole |
| **Rotation** | Manual re-encryption on commit | Fully automated polling (`refreshInterval: 1h`) |
| **Developer Overhead** | Low (single CLI command) | Zero (developers never touch raw keys) |

---

## 🔒 Layer A: Local GitOps via Mozilla SOPS + Age

For developer laptops and self-contained repositories, SecureKube integrates SOPS with modern, lightweight Age asymmetric encryption.

### 1. Initialize Age Keypair
```bash
make secrets-init
```
Generates a 256-bit Age keypair at `~/.config/sops/age/keys.txt` and automatically generates the `.sops.yaml` encryption rule binding your repository to the generated public key.

### 2. Encrypt a Kubernetes Secret
```bash
make secrets-encrypt FILE=gitops/secrets/examples/app-secret.yaml
```
Outputs an encrypted manifest with envelope integrity signatures (`.enc.yaml`). The ciphertext is completely safe to commit into public Git repositories.

### 3. Decrypt and Apply On-The-Fly
```bash
make secrets-apply
```
Decrypts the encrypted manifest in-memory and pipes it directly into `kubectl apply` without writing unencrypted secrets to disk.

---

## 🏢 Layer B: Enterprise Secret Synchronization (ESO)

For production enterprise environments, SecureKube deploys the [External Secrets Operator](https://external-secrets.io/). Workloads declare an `ExternalSecret` custom resource, and the operator synchronizes credentials directly into native Kubernetes `Secret` objects.

### 1. Install External Secrets Operator
```bash
make secrets-eso
```

### 2. The ExternalSecret Custom Resource

Developers declare what secrets they need without handling credentials:

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: database-credentials
  namespace: default
spec:
  refreshInterval: "1h"
  secretStoreRef:
    name: securekube-vault-store
    kind: ClusterSecretStore
  target:
    name: database-credentials-k8s
    creationPolicy: Owner
  data:
    - secretKey: DB_USER
      remoteRef:
        key: production/database
        property: username
    - secretKey: DB_PASS
      remoteRef:
        key: production/database
        property: password
```

### 3. Multi-Cloud Provider Backends

#### HashiCorp Vault (Kubernetes Auth)
```yaml
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: vault-backend
spec:
  provider:
    vault:
      server: "https://vault.internal.corp:8200"
      path: "secret"
      version: "v2"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "securekube-workload-role"
```

#### AWS Secrets Manager (IRSA)
```yaml
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: aws-secrets-manager
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-east-1
      auth:
        jwt:
          serviceAccountRef:
            name: eso-irsa-sa
            namespace: external-secrets
```

#### GCP Secret Manager (Workload Identity)
```yaml
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: gcp-secret-manager
spec:
  provider:
    gcpsm:
      projectID: my-hardened-gcp-project
      auth:
        workloadIdentity:
          clusterLocation: us-central1
          clusterName: securekube-gke
          serviceAccountRef:
            name: eso-wi-sa
            namespace: external-secrets
```
