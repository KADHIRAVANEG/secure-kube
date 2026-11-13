# Architecture notes

## Why `anonymous-auth` is NOT disabled on the API server

CIS control 1.2.1 recommends `--anonymous-auth=false`. We tried exactly that, and it breaks cluster bootstrap entirely: `kubeadm join`'s default discovery mechanism reads the `cluster-info` ConfigMap in `kube-public` **unauthenticated** — by design, since a joining node has no credentials yet. Disabling anonymous auth makes that read return `401 Unauthorized`, and every worker join hangs indefinitely retrying against a wall the cluster itself put up.

This is a genuine, known tension between that CIS control and kubeadm's token-based bootstrap flow, not a misconfiguration on our end. The realistic fixes are: (a) leave anonymous-auth enabled, as we do here, and rely on RBAC + NodeRestriction to constrain what an anonymous/unauthenticated request can actually see or do; or (b) switch to **file-based discovery** (baking a static bootstrap kubeconfig into worker nodes ahead of time) instead of token discovery, which doesn't need the anonymous ConfigMap read at all. We chose (a) for this project since it keeps `make deploy` a true one-command flow — (b) would need per-node kubeconfig provisioning as an extra step. If you need `anonymous-auth=false` for a compliance requirement, implement (b) and update this doc.

## Why the Terraform layer shells out to the `kind` CLI instead of using the `tehcyx/kind` provider

We started with the `tehcyx/kind` Terraform provider's native `kind_config` resource block. In practice it repeatedly failed to complete multi-node worker joins when combined with custom `kubeadm_config_patches` — the underlying `kind create cluster` process would run, but visibility into *why* it stalled was opaque (Terraform just shows "Still creating..." with no intermediate output). Switching `main.tf` to a `null_resource` + `local-exec` that calls `kind create cluster --config kind-config.yaml` directly gives the exact same real-time output you'd get running `kind` by hand — which is what let us find the `anonymous-auth` issue above in the first place. The trade-off is losing Terraform's native resource semantics (typed attributes, `terraform plan` diffing on cluster properties); for a project whose value is the security config layered on top, not the provisioning mechanism itself, that trade-off was worth it.

## Why default-deny + Calico on kind

kindnet (kind's default CNI) does not enforce `NetworkPolicy` — it provides pod networking only. Without swapping in a policy-aware CNI, the `default-deny-all` NetworkPolicy in `kustomize/base/network-policies/` would be silently ignored and the cluster would *look* zero-trust without *being* zero-trust. `terraform/kind/main.tf` disables the default CNI and installs Calico for this reason.

## Why two enforcement layers (PSA + Gatekeeper)

- **Pod Security Admission (PSA)**, applied via namespace labels, is built into Kubernetes core, has zero extra moving parts, and enforces the standard "restricted" profile.
- **OPA Gatekeeper** adds enforcement Kubernetes' native PSA can't express as precisely (e.g. exact rego conditions, custom messages, audit trail of violations over time, extensibility for future org-specific rules).

Together: PSA is the floor that can never regress even if Gatekeeper is ever uninstalled; Gatekeeper is the layer that gives auditable, extensible policy-as-code.

## Why RBAC ships a `workload-runtime` Role instead of relying only on defaults

Kubernetes ships no default namespaced role suitable for application workloads — teams either bind `cluster-admin` (too broad) or write nothing (pods run with only their ServiceAccount's implicit, minimal permissions, which usually breaks introspection features). `workload-runtime` is the least-privilege middle ground: read-only access to configmaps and pod listing, explicitly *no* secrets access. Secrets access is intentionally left to a separate, per-secret scoped role so it's an explicit decision, not a default.

## Why the webhook is fail-open (`Ignore`), not fail-closed (`Fail`) — corrected

We initially set `validatingWebhookFailurePolicy: Fail` (see the now-outdated reasoning below) but hit a real, reproducible deadlock on kind+Calico: Calico's IP address management uses **cluster-scoped** CRDs (`IPAMBlock`, `BlockAffinity`) that have no namespace at all. Gatekeeper's own `gatekeeper-system` exclusion works by namespace label/name — which simply cannot apply to a resource that has no namespace. The result: every pod's IP allocation, in every namespace, calls Gatekeeper's webhook regardless of the exclusion. If that webhook is ever unreachable — including during Gatekeeper's *own* first install, before its pods have networking yet — no pod anywhere can start, which means Gatekeeper's own pods can never come up to start serving the webhook again. A genuine, unrecoverable deadlock, not a timing fluke.

Switching to `Ignore` breaks that deadlock: if the webhook is down, requests proceed unvalidated rather than hanging forever. The real cost is a brief enforcement gap any time the webhook pod restarts (e.g. after a node reboot, before Kubernetes reschedules it) — worth knowing if you're relying on this for a real security boundary, not just a demo/portfolio cluster. If you need genuinely fail-closed behavior, the correct fix is upstream: exclude Gatekeeper's own namespace from Calico's admission-relevant object creation entirely (a Calico/Gatekeeper compatibility concern, not something this project's config can fully solve on its own).

## Compensating Control: Native In-Tree CEL Admission Policies (`ValidatingAdmissionPolicy`)

To eliminate the brief enforcement gap caused by Gatekeeper's fail-open webhook and eliminate external webhook latency (50–200ms per admission request), SecureKube introduces **Kubernetes 1.30+ in-tree CEL ValidatingAdmissionPolicies** in `kustomize/base/vap/`.

### The In-Tree vs. Webhook Architecture

```
Incoming Request -> [ kube-apiserver ]
                         |
                         +---> 1. In-Tree CEL Evaluation (Sub-millisecond, In-Process)
                         |        [vap-no-privileged, vap-no-root, vap-readonly-rootfs, etc.]
                         |        (Rejects immediately if non-compliant; ZERO network roundtrips)
                         |
                         +---> 2. External Webhook Evaluation (Out-of-Process over HTTPS)
                                  [Gatekeeper Webhook Service]
                                  (Deep Rego inspection, Cosign signatures, violation auditing)
```

### Key Architectural Advantages:
1. **Zero External Network Hops**: Evaluated in-memory inside `kube-apiserver`, slashing admission latency from >100ms down to microseconds.
2. **Zero Webhook Deadlock Risk**: Because CEL policies execute in-process, they never deadlock against CNI IPAM CRDs or webhook pod cold-starts.
3. **Dual-Layer Defense**: CEL acts as an instantaneous in-tree filter for core security constraints, while Gatekeeper provides extensible Rego policies, comprehensive audit logging (`gatekeeper_violations`), and Cosign signature verification.

---

## Why the Gatekeeper layer has 9 constraints, not 3

The first pass only blocked root/privileged/writable-rootfs — a real attacker doesn't need any of those if `hostPath` mounting `/` is left open, or if a pod can set `hostNetwork: true` and see every other pod's traffic on the node. The current set closes the highest-value gaps beyond what PSA's "restricted" profile alone covers:

| Constraint | What it stops |
|---|---|
| `no-root` / `no-privileged` / `readonly-rootfs` | container escape via root or writable host-equivalent access |
| `no-hostpath` | reading/writing the node filesystem directly |
| `no-host-namespaces` | seeing/signaling every process on the node, or sniffing node network traffic |
| `require-resources` | noisy-neighbor DoS from unbounded pods |
| `allowed-repos` | pulling arbitrary/untrusted images |
| `capabilities-and-ports` | capability creep and binding privileged ports like a root process |
| `require-signed-images` | untrusted supply-chain deployments lacking Cosign cryptographic signatures |

This provides comprehensive admission hardening — combined with per-workload egress NetworkPolicies and Falco eBPF runtime observability.

## Why `kube-bench` runs in `kube-system`, not `default`

The first version of this Makefile applied `kube-bench`'s job manifest without specifying a namespace, so it landed in `default` — which has `pod-security.kubernetes.io/enforce: restricted` from `kustomize/base/pod-security/psa-labels.yaml`. `kube-bench` needs `hostPID: true` and several `hostPath` volume mounts (it inspects node-level config files like `/etc/kubernetes`, `/var/lib/kubelet`, `/var/lib/etcd`) to do its job at all — every one of those is exactly what the `restricted` profile blocks. The result: the `Job` object gets created fine (Jobs aren't subject to Pod Security Admission, only the Pods they spawn are), but every Pod the Job tries to create gets silently rejected, so the Job never has a running Pod and `kubectl wait --for=condition=complete` times out waiting for something that can never happen. Our own hardening was — correctly — blocking the tool whose entire purpose is to check that hardening.

Fix: run `kube-bench` in `kube-system` instead, which we deliberately left unlabeled (no PSA, and already excluded from every Gatekeeper constraint's `excludedNamespaces`) precisely because cluster-level system tooling legitimately needs broader access than application workloads. This is the same reasoning that already applies to Calico and Gatekeeper's own pods — `kube-bench` just needed the same treatment and we'd missed it.

## Why `local-path-storage` is excluded in Gatekeeper constraints

Kind clusters rely on Rancher's `local-path-provisioner` to dynamically provision local PersistentVolumes. When a PVC is created (e.g. for Prometheus, Grafana, or Alertmanager), the provisioner spins up a transient `helper-pod` in the `local-path-storage` namespace. This helper pod mounts the node's `/var/local-path-provisioner` directory via `hostPath` to initialize storage paths, and runs as a minimal utility without explicit resource requests.

If `local-path-storage` is not explicitly added to `excludedNamespaces` on Gatekeeper constraints, `block-hostpath` and `require-resources` will reject the helper pod on admission. The PVC remains stuck in `Pending` indefinitely with event logs citing admission rejection. Adding `local-path-storage` ensures local volume provisioning functions smoothly while keeping all user and workload namespaces strictly enforced.

## GitOps Architecture: Multi-Application Decoupling

Argo CD manages each layer of SecureKube as a distinct `Application` object under an `AppProject` (`gitops/apps/project.yaml`):

1. **Infrastructure Controllers**: `calico-system-app`, `gatekeeper-system-app`, `falco-system-app`.
2. **Cluster Policies**: `gatekeeper-templates-app`, `gatekeeper-constraints-app`, `network-policies-app`, `pod-security-app`, `rbac-app`.
3. **Workload Reference**: `secure-app`.

To prevent resource ownership conflicts and duplicate drift calculations in Argo CD, each policy layer is maintained in its own self-contained directory with an independent `kustomization.yaml` (e.g., `kustomize/base/network-policies/`, `kustomize/base/pod-security/`, `kustomize/base/rbac/`). Pointing multiple Argo CD applications at the same directory is strictly avoided.

## Observability & Security Telemetry Integration

Security without observability creates an operational blind spot. SecureKube combines runtime kernel telemetry with admission audit metrics:

- **Falco eBPF Probes**: Inspect system calls (execve, open, connect) on worker and control-plane nodes. Alerts are emitted in JSON to standard out and forwarded over HTTP to `falco-sidekick` and Redis.
- **Falco Sidekick UI**: Visualizes runtime threat frequency, priority classifications (`Warning`, `Error`, `Critical`), and offending container metadata at `localhost:2802`.
- **Prometheus & Grafana (`kube-prometheus-stack`)**: Scrapes Gatekeeper metrics (`gatekeeper_violations`, `gatekeeper_constraints`), cAdvisor, and node-exporter metrics. Pre-provisioned dashboards in `observability/dashboards/` offer immediate situational awareness of cluster compliance and resource health.

## Audit logging scope

`terraform/kind/audit-policy.yaml` logs full request/response bodies only for `secrets`, `configmaps`, and RBAC objects — the resources where a full body matters for a security investigation — and only request metadata for everything else, to keep log volume manageable while still satisfying CIS 3.2.x.

## Enterprise Secret Management: SOPS+Age vs. External Secrets Operator (ESO)

SecureKube provides two complementary, production-grade secrets patterns tailored to different operational environments:

### 1. Developer Workstation & Local GitOps: Mozilla SOPS + Age
- **Use Case**: Local development, CI/CD pipelines, and standalone GitOps repositories without enterprise vault infrastructure.
- **Mechanism**: The repository contains `.sops.yaml` with public Age recipient keys. Secret manifests are encrypted client-side (`make secrets-encrypt`). Sensitive payload data is encrypted via AES-256-GCM while metadata remains intact for Git versioning. Decryption happens on-the-fly (`make secrets-apply`) or in-cluster via the KSOPS plugin.

### 2. Multi-Cloud & Enterprise Vault Sync: External Secrets Operator (ESO)
- **Use Case**: Enterprise production clusters where developers should never handle encryption keys or decrypt raw secrets on their laptops.
- **Mechanism**: ESO runs in-cluster (`helm/external-secrets-values.yaml`) with a hardened, non-root pod specification. A `ClusterSecretStore` connects directly to upstream secret providers:
  - **Local/CI**: `fake` provider with zero external dependencies and zero cloud billing.
  - **AWS**: AWS Secrets Manager authenticated via IAM Roles for Service Accounts (IRSA).
  - **GCP**: GCP Secret Manager authenticated via Workload Identity.
  - **On-Premise / Multi-Cloud**: HashiCorp Vault authenticated via Kubernetes ServiceAccount tokens.
- **Dynamic Rotation**: ESO polls upstream vaults at configured intervals (e.g., `refreshInterval: 1h`) and automatically synchronizes Kubernetes `Secret` objects, decoupling secret lifecycle from Git commits.

---

## NetworkPolicy Auto-Discovery: Overcoming the Zero-Trust Blackhole

Default-deny networking is the gold standard of zero-trust Kubernetes security, but it often frustrates developers: when a pod is blocked by a NetworkPolicy, packets drop silently without error messages. Applications fail with cryptic `i/o timeout` or `Connection refused` errors.

To solve this operational friction, SecureKube implements a two-fold solution:
1. **Calico Dropped Packet Observability**: Calico Felix Prometheus metrics are exported on port 9091, enabling real-time monitoring of dropped packet counters in Prometheus and Grafana.
2. **Automated Discovery & Generator (`scripts/generate-network-policy.sh`)**: Rather than guessing egress rules, developers run `make generate-network-policy POD=<name>`. The generator:
   - Queries live container specs and runtime ports.
   - Extracts existing pod labels for targeted `podSelector` matching.
   - Automatically injects mandatory CoreDNS egress (UDP/TCP port 53 to `kube-dns`).
   - Produces a minimal, least-privilege `NetworkPolicy` ready for immediate application or commit into GitOps.

---

## Automated Workload Hardening Architecture

Rather than rejecting non-compliant manifests at admission and forcing developers through frustrating trial-and-error cycles, SecureKube provides an automated manifest transformer (`scripts/harden-manifest.py`).

### Design Principles:
- **Preserve Developer Intent**: Uses PyYAML to load manifests as structured trees, mutating only the necessary fields while preserving custom labels, annotations, volume mounts, and container arguments.
- **Complete AST Injection**: Automatically injects all 12 required securityContext fields:
  - Pod: `runAsNonRoot: true`, `runAsUser: 10001`, `runAsGroup: 10001`, `fsGroup: 10001`, `seccompProfile: RuntimeDefault`.
  - Container: `allowPrivilegeEscalation: false`, `readOnlyRootFilesystem: true`, `capabilities.drop: ["ALL"]`.
  - Resources: sensible default requests (`cpu: 50m`, `memory: 64Mi`) and limits (`cpu: 200m`, `memory: 128Mi`).
- **Privileged Port Remapping**: Identifies reserved ports (< 1024) like 80 or 443 and remaps them to unprivileged equivalents (8080, 8443) to prevent `CAP_NET_BIND_SERVICE` privilege escalation.
- **Scratch Space Emulation**: Automatically attaches an in-memory `emptyDir` volume at `/tmp` so read-only root filesystems don't break applications requiring temporary write space.

---

## Multi-Cloud Parity Architecture: AWS EKS & GCP GKE

To ensure that security controls verified locally on Kind translate seamlessly to enterprise production environments, SecureKube provides production-hardened Terraform modules for AWS and GCP:

| Architectural Component | Local Kind Stack | AWS EKS (`terraform/eks/`) | GCP GKE (`terraform/gke/`) |
|---|---|---|---|
| **Cluster Provisioning** | Kind CLI via Terraform | AWS EKS Managed Cluster | GKE Private Cluster |
| **Control Plane Audit** | `audit-policy.yaml` mounted | CloudWatch CIS Control Plane Logs | Cloud Logging CIS Audit Export |
| **Secret Encryption** | Kind etcd / SOPS / ESO | AWS KMS Customer Managed Key | Cloud KMS Envelope Encryption |
| **Network Fabric** | Calico CNI + NetworkPolicy | AWS VPC CNI + NetworkPolicy | Datapath V2 (Cilium eBPF) |
| **Node Hardening** | Docker container node | IMDSv2 Enforced (`http_tokens`) | Shielded GKE Nodes (Secure Boot) |
| **Identity & IAM** | ServiceAccount Tokens | IAM Roles for Service Accounts (IRSA) | Workload Identity Federation |
| **Policy Enforcement** | Gatekeeper + In-Tree CEL | Gatekeeper + In-Tree CEL | Gatekeeper + In-Tree CEL |
| **Runtime Detection** | Falco modern eBPF | Falco modern eBPF | Falco modern eBPF |

---

## Smaller lessons worth keeping

- **`helm/falco-values.yaml` uses `driver.kind: modern_ebpf`, not `ebpf`.** Falco's chart renamed this value; the old name now fails install outright with a clear error, so this is a one-line fix if you ever see it again on a chart upgrade.
- **If a YAML file ever fails `kubectl apply` with a generic, low-information error** (`invalid object to validate`, `json: cannot unmarshal string into Go value of type unstructured.detector`) even though the same content parses fine with a YAML linter, suspect file corruption from copy/paste or a transfer step, not a real schema issue — rewriting the file cleanly is often faster than debugging the parser.
- **`kubectl`'s local schema cache (`~/.kube/cache`) can go stale** right after installing a new CRD (e.g. Gatekeeper's `ConstraintTemplate`). If `kubectl apply` rejects a resource that looks structurally correct, `rm -rf ~/.kube/cache` before assuming the YAML itself is wrong.
