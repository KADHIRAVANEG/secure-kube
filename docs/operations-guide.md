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
