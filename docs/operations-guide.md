# SecureKube Operations & Day-2 Guide

A practical operational guide for deploying, managing, inspecting, and troubleshooting the SecureKube platform.

---

## 1. Cluster Lifecycle Management

SecureKube orchestrates cluster deployment using Terraform and Make. All underlying operations run locally inside Docker via Kind.

### Essential Commands

| Command | Action | Expected Output |
|---|---|---|
| `make deploy` | End-to-end bootstrap (Cluster -> Policies -> Gatekeeper -> Falco -> Argo CD -> Test) | Fully configured 3-node cluster |
| `make status` | Health check across nodes, Calico, Gatekeeper, Falco, Argo CD, and test workloads | Status summary table |
| `make lint` | Runs static analysis (ShellCheck on scripts, Terraform fmt, YAML validation) | Zero lint errors |
| `make test-offline` | Runs Gatekeeper policy validation offline via `gator` CLI (no cluster required) | All constraints validated |
| `make test` | Runs positive & negative admission control tests via `scripts/test-policies.sh` | 8 rejected, 1 allowed |
| `make attack` | Runs 8-vector offensive security assault simulation | 100% defense score |
| `make harden FILE=...` | Automatically fixes insecure manifests to pass all security policies | 100% compliant manifest |
| `make generate-network-policy`| Auto-discovers pod connections and generates minimal NetworkPolicy | Least-privilege policy |
| `make vap` | Deploys native Kubernetes in-tree CEL ValidatingAdmissionPolicies | Sub-ms admission enforcement |
| `make secrets-eso` | Deploys External Secrets Operator & syncs secrets from remote vaults | Vault secrets materialized |
| `make cloud-eks` / `cloud-gke`| Provisions hardened AWS EKS or GCP GKE clusters via Terraform | Production cloud cluster |
| `make bench` | Runs CIS Kubernetes Benchmark via `kube-bench` in `kube-system` | CIS compliance report |
| `make destroy` | Tears down the Kind cluster and purges local state | Clean host state |

---

## 2. Accessing Web Dashboards & Credentials

SecureKube includes multiple web user interfaces for GitOps, runtime security, and cluster observability:

```
+------------------------------------------------------------------------------------+
|  Dashboard          | Port   | Command                  | Default Credentials      |
+------------------------------------------------------------------------------------+
|  Argo CD GitOps     | 8080   | make dashboard-argocd    | admin / (dynamic secret) |
|  Grafana Telemetry  | 3000   | make dashboard-grafana   | admin / (dynamic secret) |
|  Falco Sidekick UI  | 2802   | make dashboard           | Anonymous (local only)   |
|  Prometheus Server  | 9090   | make dashboard-prometheus| None (unauthenticated)   |
+------------------------------------------------------------------------------------+
```

### Retrieving Admin Credentials

```bash
# Argo CD Admin Password:
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo

# Grafana Admin Password:
kubectl -n monitoring get secret kube-prometheus-stack-grafana -o jsonpath='{.data.admin-password}' | base64 -d && echo
```

---

## 3. GitOps Workflows with Argo CD

All policies, controllers, and example workloads are declarative Argo CD Applications defined in `gitops/apps/`:

### Syncing Layers

```bash
make sync-all          # Trigger manual reconciliation for all 8 applications
make sync-policies     # Sync NetworkPolicies only
make sync-rbac         # Sync workload RBAC only
make sync-gatekeeper   # Sync Gatekeeper ConstraintTemplates and Constraints
```

### Checking Drift

When a developer or operator performs an ad-hoc `kubectl edit` or `kubectl apply` outside Git, Argo CD marks the application as `OutOfSync`. You can inspect the exact diff in the Argo CD web console at `http://localhost:8080` or via CLI:

```bash
argocd app diff network-policies-app --insecure
```

---

## 4. Authoring Compliant Workloads

To deploy an application successfully onto SecureKube, the pod manifest must adhere to **Pod Security Standards (`restricted`)** and all **9 OPA Gatekeeper constraints**:

### Workload Checklist:
- [x] Run as a non-root user (`runAsNonRoot: true`, `runAsUser: 10001`)
- [x] Disallow privilege escalation (`allowPrivilegeEscalation: false`)
- [x] Drop all capabilities except explicitly permitted (`drop: ["ALL"]`)
- [x] Mount root filesystem read-only (`readOnlyRootFilesystem: true`)
- [x] Set explicit CPU and Memory requests and limits
- [x] Use seccomp profile `RuntimeDefault`
- [x] Pull images only from approved registries (`docker.io/library/`, `ghcr.io/`, `gcr.io/`, `registry.k8s.io/`)
- [x] Never use `hostPath`, `hostNetwork`, `hostPID`, or `hostIPC`
- [x] Bind only to non-privileged ports (> 1024)

### Reference Compliant Pod

See [`examples/secure-app.yaml`](../examples/secure-app.yaml) for a fully annotated production-grade template:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-secure-app
  namespace: default
  labels:
    app: my-secure-app
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 10001
    runAsGroup: 10001
    fsGroup: 10001
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: app
      image: docker.io/library/nginx:alpine
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities:
          drop: ["ALL"]
      resources:
        limits:
          cpu: "200m"
          memory: "128Mi"
        requests:
          cpu: "50m"
          memory: "64Mi"
```

---

## 5. Runtime Security & Falco Threat Hunting

Falco observes kernel events across all nodes using the modern eBPF driver.

### Live Threat Monitoring

Tail live alerts stream:
```bash
make logs
```

### Simulating a Runtime Security Violation

To test that Falco accurately detects unauthorized behavior in a container:

```bash
# 1. Spawn a compliant test container
kubectl run test-sec --image=busybox:1.36 --restart=Never --command -- sleep 3600

# 2. Exec a terminal shell inside the container (Falco rule: "Terminal shell in container")
kubectl exec -it test-sec -- sh -c "cat /etc/shadow"

# 3. Check Falco alerts:
make logs | grep "Terminal shell"
```

The event will immediately reflect on the **Falco Sidekick UI** at `http://localhost:2802` categorized as `Notice` or `Warning`.

---

## 6. Common Troubleshooting Runbooks

### 1. PVCs Stuck in `Pending`
- **Symptom**: `kubectl get pvc -A` shows PVCs in `Pending` state.
- **Cause**: Kind's `local-path-provisioner` helper pod was rejected by admission webhooks.
- **Remediation**: Ensure `local-path-storage` is present in `excludedNamespaces` in all files in `gatekeeper/constraints/`.

### 2. Node in `NotReady` State
- **Symptom**: Nodes remain in `NotReady` after `make cluster`.
- **Cause**: SecureKube disables default `kindnet` to enforce Calico. The node remains `NotReady` until a CNI provides network routing.
- **Remediation**: Run `make policies` or `kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml`.

### 3. Webhook Connection Reset on Local Port-Forward
- **Symptom**: `kubectl port-forward` exits with `connection reset by peer`.
- **Cause**: Argo CD runs HTTP on port 8080 (`--insecure`), but service port 443 routes to the same container port.
- **Remediation**: Forward port 80 to 8080 or pod port 8080 directly:
  ```bash
  kubectl -n argocd port-forward svc/argocd-server 8080:80 --address 127.0.0.1
  ```

---

## 7. GitOps Secrets Management (SOPS + Age)

Storing raw secrets in Git repositories is a critical vulnerability. SecureKube implements zero-trust GitOps secrets management using **Mozilla SOPS** and modern **Age asymmetric encryption**.

### How It Works

1. **Local Key Generation**: A private/public Age keypair is generated locally (`~/.config/sops/age/keys.txt`).
2. **Public Key Configuration**: The public recipient is committed to [`.sops.yaml`](../.sops.yaml) targeting `.*\.enc\.ya?ml$`.
3. **Encrypted in Git**: Kubernetes Secret manifests (e.g., [`gitops/secrets/database-credentials.enc.yaml`](../gitops/secrets/database-credentials.enc.yaml)) are committed fully encrypted. Only keys and metadata remain plaintext; sensitive payload values are AES-256-GCM encrypted.
4. **On-the-Fly Application**: Manifests are decrypted in-memory during application without writing plaintext to disk.

### Secrets Lifecycle Operations

```bash
# 1. Initialize Age keypair & configure .sops.yaml
make secrets-init

# 2. Encrypt an existing plaintext Secret manifest
make secrets-encrypt FILE=my-secret.yaml DEST=gitops/secrets/my-secret.enc.yaml

# 3. Decrypt and apply encrypted secrets directly to the live cluster
make secrets-apply

# 4. Sync Age private key to Argo CD namespace (for GitOps KSOPS plugin)
./scripts/secrets-tool.sh sync-key
```

### Reference Pod Consuming Decrypted Secret

See [`examples/secure-app-with-secret.yaml`](../examples/secure-app-with-secret.yaml) for a hardened, admitted workload consuming database credentials via environment variables:

```bash
kubectl apply -f examples/secure-app-with-secret.yaml
kubectl logs -n default pod/secure-app-with-secret
```

---

## 8. Automated Security Assault & Defense Simulator (`make attack`)

SecureKube provides an integrated offensive attack simulation suite ([`scripts/simulate-attacks.sh`](../scripts/simulate-attacks.sh)) to empirically verify that every defense layer actively repels real-world cyber threats.

### Running the Assault Suite

```bash
make attack
```

### Attack Vectors & Mitigating Defense Layers

| # | Attack Vector | Technique / Payload | Mitigating Layer | Outcome |
|---|---|---|---|---|
| **1** | **Privilege Escalation** | Pod with `privileged: true`, `CAP_SYS_ADMIN` | Kubernetes PSA (`restricted`) | **BLOCKED AT ADMISSION** |
| **2** | **Host Escape** | Pod mounting `/` via `hostPath` | Kubernetes PSA (`restricted`) | **BLOCKED AT ADMISSION** |
| **3** | **Network Sniffing** | Pod with `hostNetwork: true` eavesdropping on node | Kubernetes PSA (`restricted`) | **BLOCKED AT ADMISSION** |
| **4** | **Supply Chain Poisoning** | Image pulled from untrusted external rogue registry | OPA Gatekeeper (`[allowed-repos]`) | **BLOCKED AT ADMISSION** |
| **5** | **Privileged Port Hijack** | Non-root container attempting to bind port `80` | OPA Gatekeeper (`[capabilities-and-ports]`) | **BLOCKED AT ADMISSION** |
| **6** | **Denial of Service** | Unbounded memory pod without requests or limits | OPA Gatekeeper (`[require-resources]`) | **BLOCKED AT ADMISSION** |
| **7** | **Lateral Pivoting** | Cross-namespace TCP probing to unauthorized internal DB | Calico CNI + Default-Deny NetworkPolicy | **DROPPED BY NETWORK POLICY** |
| **8** | **Runtime Exploitation** | Spawning interactive terminal shells inside container | Falco modern eBPF driver | **DETECTED IN KERNEL TELEMETRY** |

The assault suite outputs a definitive defense score (100% resilience) and is suitable for CI/CD gates and red/blue team validation.

---

## 9. Automated Workload Hardening (`make harden`)

Developers often struggle with the 12+ required securityContext and resource fields required by Gatekeeper and Pod Security Standards. SecureKube includes [`scripts/harden-manifest.py`](../scripts/harden-manifest.py), an automated AST-based manifest transformer:

### Usage

```bash
# Preview hardened manifest in stdout
make harden FILE=my-insecure-pod.yaml

# Overwrite in-place
make harden FILE=my-insecure-pod.yaml IN_PLACE=true

# Output to a specific file
make harden FILE=my-insecure-pod.yaml OUTPUT=my-hardened-pod.yaml
```

### What It Remediates Automatically
- Injects Pod-level `runAsNonRoot: true`, `runAsUser: 10001`, `runAsGroup: 10001`, `fsGroup: 10001`, and `seccompProfile.type: RuntimeDefault`.
- Injects Container-level `allowPrivilegeEscalation: false`, `readOnlyRootFilesystem: true`, and `capabilities.drop: ["ALL"]`.
- Injects sensible default resource limits and requests (`cpu: 200m/50m`, `memory: 128Mi/64Mi`).
- Rewrites privileged container ports (e.g. `80` -> `8080`, `443` -> `8443`) to prevent host port hijacking.
- Adds an `emptyDir` scratch volume (`/tmp`) for read-only root filesystems requiring temp write space.

---

## 10. Native In-Tree CEL Admission Policies (`ValidatingAdmissionPolicy`)

Starting in Kubernetes 1.30, admission control can be executed in-process inside `kube-apiserver` using Common Expression Language (CEL), bypassing webhook latencies (50–200ms) and avoiding webhook failure deadlocks.

SecureKube deploys 8 native CEL policies located in [`kustomize/base/vap/`](../kustomize/base/vap/):
1. `vap-no-privileged`: Prohibits `securityContext.privileged: true`.
2. `vap-no-root`: Enforces `runAsNonRoot: true` or non-zero `runAsUser`.
3. `vap-readonly-rootfs`: Enforces `readOnlyRootFilesystem: true`.
4. `vap-no-hostpath`: Prohibits `hostPath` volume mounts.
5. `vap-no-host-namespaces`: Prohibits `hostNetwork`, `hostPID`, and `hostIPC`.
6. `vap-require-resources`: Enforces CPU and memory requests/limits.
7. `vap-capabilities-and-ports`: Enforces `capabilities.drop: ["ALL"]` and port > 1024.
8. `vap-allowed-registries`: Restricts container image registries to approved sources.

### Deploying & Testing CEL Policies

```bash
# Deploy CEL policies and cluster-wide bindings
make vap

# Policies run in-tree alongside Gatekeeper and evaluate instantaneously
kubectl apply -f examples/insecure-apps.yaml
```

---

## 11. NetworkPolicy Auto-Discovery / Generator (`make generate-network-policy`)

Debugging silent packet drops in zero-trust environments can stall developer velocity. SecureKube includes [`scripts/generate-network-policy.sh`](../scripts/generate-network-policy.sh) to auto-generate minimal least-privilege egress and ingress rules.

### Usage

```bash
# Discover live ports and generate NetworkPolicy for a pod
make generate-network-policy POD=my-app NAMESPACE=default
```

### Generated Policy Properties
- Automatically extracts pod labels and container ports for ingress rules.
- Automatically includes mandatory egress to CoreDNS (`kube-dns` on UDP/TCP port 53).
- Implements strict default-deny for all unauthorized ingress and egress traffic.

---

## 12. External Secrets Operator (Local Fake Vault & Enterprise Sync)

For enterprise environments using HashiCorp Vault, AWS Secrets Manager, or GCP Secret Manager, SecureKube integrates the **External Secrets Operator (ESO)**:

### Architecture
- Runs with hardened non-root container specs (`helm/external-secrets-values.yaml`).
- Configures `ClusterSecretStore` ([`gitops/secrets/eso/cluster-secret-store.yaml`](../gitops/secrets/eso/cluster-secret-store.yaml)).
- Local environments use the built-in `fake` provider for zero-cost, zero-dependency testing.
- Includes pre-configured production blocks for Vault, AWS Secrets Manager, and GCP Secret Manager.

### Deployment & Verification

```bash
# Deploy ESO and synchronize secrets
make secrets-eso

# Verify materialized secret
kubectl get secret database-credentials-vault -n default -o yaml

# Run workload consuming ESO synchronized secret
kubectl apply -f examples/secure-app-with-vault-secret.yaml
kubectl logs -n default pod/secure-app-with-vault-secret
```

---

## 13. Production Cloud Provisioning (AWS EKS & GCP GKE)

SecureKube provides production-ready Terraform modules to deploy the identical zero-trust security baseline onto managed hyperscaler cloud environments:

### AWS EKS (`terraform/eks/`)
- Encrypted control plane secrets via AWS KMS.
- CIS control plane logging (api, audit, authenticator, controllerManager, scheduler).
- Private cluster endpoint with managed public CIDR allow-listing.
- Hardened managed node groups with IMDSv2 enforced (`http_tokens = "required"`, `http_put_response_hop_limit = 1`).
- IAM Roles for Service Accounts (IRSA) via OIDC provider.
- Automated SecureKube baseline bootstrapping via Helm provider.

```bash
cd terraform/eks
terraform init
terraform apply -var="cluster_name=prod-securekube"
```

### GCP GKE (`terraform/gke/`)
- Datapath V2 enabled (Cilium eBPF CNI native integration).
- Shielded GKE Nodes (Secure Boot & Integrity Monitoring).
- Workload Identity enabled for zero-secret GCP API authentication.
- Private cluster with authorized master networks.
- Cloud KMS envelope encryption for Kubernetes secrets.
- Automated SecureKube baseline bootstrapping via Helm provider.

```bash
cd terraform/gke
terraform init
terraform apply -var="cluster_name=prod-securekube"
```
