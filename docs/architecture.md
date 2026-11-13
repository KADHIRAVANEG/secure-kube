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

## Why the Gatekeeper layer has 8 constraints, not 3

The first pass only blocked root/privileged/writable-rootfs — a real attacker doesn't need any of those if `hostPath` mounting `/` is left open, or if a pod can set `hostNetwork: true` and see every other pod's traffic on the node. The current set closes the highest-value gaps beyond what PSA's "restricted" profile alone covers:

| Constraint | What it stops |
|---|---|
| `no-root` / `no-privileged` / `readonly-rootfs` | container escape via root or writable host-equivalent access |
| `no-hostpath` | reading/writing the node filesystem directly |
| `no-host-namespaces` | seeing/signaling every process on the node, or sniffing node network traffic |
| `require-resources` | noisy-neighbor DoS from unbounded pods |
| `allowed-repos` | pulling arbitrary/untrusted images |
| `capabilities-and-ports` | capability creep and binding privileged ports like a root process |

This still isn't exhaustive — seccomp/AppArmor profile enforcement, image signature verification (Cosign), and NetworkPolicy egress allow-lists per-workload are reasonable next additions, not yet implemented.

## Why `kube-bench` runs in `kube-system`, not `default`

The first version of this Makefile applied `kube-bench`'s job manifest without specifying a namespace, so it landed in `default` — which has `pod-security.kubernetes.io/enforce: restricted` from `kustomize/base/pod-security/psa-labels.yaml`. `kube-bench` needs `hostPID: true` and several `hostPath` volume mounts (it inspects node-level config files like `/etc/kubernetes`, `/var/lib/kubelet`, `/var/lib/etcd`) to do its job at all — every one of those is exactly what the `restricted` profile blocks. The result: the `Job` object gets created fine (Jobs aren't subject to Pod Security Admission, only the Pods they spawn are), but every Pod the Job tries to create gets silently rejected, so the Job never has a running Pod and `kubectl wait --for=condition=complete` times out waiting for something that can never happen. Our own hardening was — correctly — blocking the tool whose entire purpose is to check that hardening.

Fix: run `kube-bench` in `kube-system` instead, which we deliberately left unlabeled (no PSA, and already excluded from every Gatekeeper constraint's `excludedNamespaces`) precisely because cluster-level system tooling legitimately needs broader access than application workloads. This is the same reasoning that already applies to Calico and Gatekeeper's own pods — `kube-bench` just needed the same treatment and we'd missed it.

## Audit logging scope

`terraform/kind/audit-policy.yaml` logs full request/response bodies only for `secrets`, `configmaps`, and RBAC objects — the resources where a full body matters for a security investigation — and only request metadata for everything else, to keep log volume manageable while still satisfying CIS 3.2.x.

## Smaller lessons worth keeping

- **`helm/falco-values.yaml` uses `driver.kind: modern_ebpf`, not `ebpf`.** Falco's chart renamed this value; the old name now fails install outright with a clear error, so this is a one-line fix if you ever see it again on a chart upgrade.
- **If a YAML file ever fails `kubectl apply` with a generic, low-information error** (`invalid object to validate`, `json: cannot unmarshal string into Go value of type unstructured.detector`) even though the same content parses fine with a YAML linter, suspect file corruption from copy/paste or a transfer step, not a real schema issue — rewriting the file cleanly is often faster than debugging the parser.
- **`kubectl`'s local schema cache (`~/.kube/cache`) can go stale** right after installing a new CRD (e.g. Gatekeeper's `ConstraintTemplate`). If `kubectl apply` rejects a resource that looks structurally correct, `rm -rf ~/.kube/cache` before assuming the YAML itself is wrong.
