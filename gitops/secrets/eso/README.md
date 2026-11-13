# External Secrets Operator (ESO) in SecureKube

SecureKube integrates [External Secrets Operator (ESO)](https://external-secrets.io/) to bridge production secret stores (HashiCorp Vault, AWS Secrets Manager, GCP Secret Manager, Azure Key Vault) directly into native Kubernetes `Secret` objects.

---

## 🔑 Why External Secrets Operator?

1. **Zero Secret Handling on Laptops**: Developers never need to download or hold master Age/GPG keys on their workstations.
2. **Dynamic Rotation**: External Secrets Operator polls external vaults every `refreshInterval` (e.g., 1 hour) and updates Kubernetes Secrets automatically without restarting the application.
3. **Multi-Cloud Vault Compatibility**: Write one declarative `ExternalSecret` custom resource; the underlying cluster platform maps it to whichever vault engine the organization uses (AWS, GCP, Vault, Azure).

---

## 🚀 Quickstart

### 1. Inspect the Configured ClusterSecretStore
```bash
kubectl get clustersecretstores
```

### 2. View Synchronized ExternalSecrets
```bash
kubectl get externalsecrets -n default
```

Output:
```text
NAME                         STORETYPE            STORE                    STATUS         READY
database-credentials-vault   ClusterSecretStore   securekube-vault-store   SecretSynced   True
```

### 3. Deploy Workload Consuming Vault Secrets
```bash
kubectl apply -f examples/secure-app-with-vault-secret.yaml
kubectl logs -n default pod/secure-app-with-vault-secret
```

---

## 🏢 Connecting to Enterprise Vault Engines

### HashiCorp Vault (Kubernetes Auth)
Edit [`cluster-secret-store.yaml`](cluster-secret-store.yaml):
```yaml
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: securekube-hashicorp-vault
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
          serviceAccountRef:
            name: "external-secrets-sa"
            namespace: "external-secrets"
```

### AWS Secrets Manager (IRSA)
```yaml
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: securekube-aws-secrets-manager
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-east-1
      auth:
        jwt:
          serviceAccountRef:
            name: "external-secrets-sa"
            namespace: "external-secrets"
```

### GCP Secret Manager (Workload Identity)
```yaml
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: securekube-gcp-secret-manager
spec:
  provider:
    gcpsm:
      projectID: "my-gcp-project-12345"
      auth:
        workloadIdentity:
          clusterLocation: "us-central1"
          clusterName: "securekube-cluster"
          serviceAccountRef:
            name: "external-secrets-sa"
            namespace: "external-secrets"
```
