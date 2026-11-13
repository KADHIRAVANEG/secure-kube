# Changelog

All notable changes to SecureKube are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Versioning follows [Semantic Versioning](https://semver.org/).

---

## [1.5.0] - 2026-11-13

### Added
- **Automated Security Assault & Defense Simulator**: Added [`scripts/simulate-attacks.sh`](scripts/simulate-attacks.sh) and `make attack` command simulating 8 distinct cyber attack vectors (privilege escalation, host escapes, hostNetwork MITM, untrusted registry supply chain, privileged port hijacking, memory exhaustion DoS, Calico cross-namespace pivoting, Falco eBPF runtime exploitation) with 100% defense resilience scoring.
- **GitOps Secrets Management (SOPS + Age)**: Added zero-trust encrypted secrets management pipeline using Mozilla SOPS and modern Age asymmetric cryptography. Includes [`.sops.yaml`](.sops.yaml) creation rules, [`scripts/secrets-tool.sh`](scripts/secrets-tool.sh) key management and sync utility, encrypted database credentials at [`gitops/secrets/database-credentials.enc.yaml`](gitops/secrets/database-credentials.enc.yaml), and compliant reference pod at [`examples/secure-app-with-secret.yaml`](examples/secure-app-with-secret.yaml).
- **Secrets & Attack Make Targets**: Added `make attack`, `make secrets-init`, `make secrets-encrypt`, and `make secrets-apply` commands.
- **GitOps Observability Integration**: Brought `kube-prometheus-stack` Helm release and custom observability resources under declarative GitOps management via `gitops/apps/monitoring-helm-app.yaml` and `gitops/apps/observability-app.yaml` (#18).
- **Offline Policy Testing**: Added Gatekeeper offline policy testing via `gator test` CLI in [`scripts/test-offline.sh`](scripts/test-offline.sh) and `make test-offline` target (#19).
- **Pre-Commit Linting**: Added `make lint` running ShellCheck static analysis on scripts, Terraform recursive format verification, and YAML manifest validation (#19).
- **CI Linting & Offline Validation**: Integrated `make lint` and `make test-offline` into GitHub Actions CI workflow prior to cluster deployment (#19).
- **Visual Showcase & Screenshots**: High-resolution UI captures of live running Kind cluster (`docs/screenshots/`):
  - Argo CD GitOps Dashboard (`argocd-dashboard.png`) managing all 8 core apps
  - Grafana Unified Security & Cluster Overview (`grafana-dashboard.png`)
  - Falco Sidekick Runtime Telemetry UI (`falco-sidekick-ui.png`)
  - Admission control verification terminal run (`terminal-policy-tests.png`)
  - Multi-node cluster health overview (`terminal-cluster-status.png`)
- **Operations Runbook**: Added comprehensive day-2 guide [`docs/operations-guide.md`](docs/operations-guide.md) covering dashboard authentication, compliant workload authoring, live threat simulation, and troubleshooting runbooks.
- **Reference Multi-Tier Architecture**: Consolidated full-stack reference deployment at [`examples/three-tier-app.yaml`](examples/three-tier-app.yaml) demonstrating ingress, cross-tier egress, and database isolation under default-deny.
- **Cosign Supply-Chain Enforcement**: Added 9th Gatekeeper constraint template and constraint for cryptographic image signature verification (`require-signed-images`).
- **Dashboard Make Targets**: Added `make dashboard-argocd`, `make dashboard-grafana`, and `make dashboard-prometheus` targets for one-command browser access.

### Changed
- **Network Policies**: Flattened nested `network-policies/` directory into `network-policies/egress-templates/` and updated [`network-policies/README.md`](network-policies/README.md).
- **Sub-Kustomizations**: Added independent `kustomization.yaml` manifests for `network-policies`, `pod-security`, and `rbac` to support clean decoupled GitOps management.
- **Architecture Documentation**: Consolidated root `ARCHITECTURE.md` into [`docs/architecture.md`](docs/architecture.md) and expanded on Kind local storage provisioner trade-offs, fail-open webhook rationale, and telemetry design.

### Fixed
- **Makefile Test Target**: Restored and decoupled `make test` target from Prometheus dashboard setup.
- **GitOps Application Conflict**: Resolved duplicate directory ownership between `network-policies-app` and `egress-policies-app` in `gitops/apps/`.
- **Kind Storage Provisioning**: Added `local-path-storage` to Gatekeeper `excludedNamespaces` across all 9 constraints, unblocking Kind local storage provisioner helper pods and resolving PVC `Pending` status.
- **Configuration Synchronization**: Synchronized `config.env` cluster variables with Terraform `kind-config.yaml` and Makefile parameters.
- **Scripts Cleanup**: Removed deprecated `scripts/verify-policies.sh`.

---

## [1.2.0] - 2026-07-12

### Added
- GitOps layer via Argo CD — 5 Applications managing all policy layers (NetworkPolicy, RBAC, PSA, Gatekeeper constraints) with manual sync mode
- Argo CD AppProject scoping source repo and destination cluster with least-privilege allow-lists
- `make argocd`, `make dashboard-argocd`, `make sync-all`, `make sync-policies`, `make sync-rbac`, `make sync-gatekeeper` targets
- `scripts/install-argocd.sh` — auto-detects GitHub remote URL, patches Application manifests, prints admin credentials
- CONTRIBUTING.md — contribution guide covering constraint authoring, test requirements, commit format, PR process
- SECURITY.md — vulnerability reporting path and documented known trade-offs
- GitHub issue templates — bug report and feature request
- GitHub PR template — checklist for constraint PRs
- Trivy vulnerability scanning in CI (filesystem scan) and release workflow (container image scan)
- Trivy SARIF results uploaded to GitHub Security tab
- Container image published to ghcr.io and Docker Hub on every release
- Per-workload egress NetworkPolicy template library (8 templates):
  - `allow-dns.yaml` — required for every workload
  - `allow-same-namespace.yaml` — east-west within a namespace
  - `allow-to-namespace.yaml` — cross-namespace traffic
  - `allow-external-https.yaml` — any external HTTPS
  - `allow-external-cidr.yaml` — specific IP range
  - `allow-database-egress.yaml` — app to specific DB pod + port
  - `allow-monitoring.yaml` — Prometheus scraping
  - `allow-api-gateway.yaml` — ingress only from gateway namespace

### Fixed
- Added `argocd` to Gatekeeper `excludedNamespaces` on all constraints
- Lowercase repo owner in Trivy image ref (GHCR compatibility)
- `security-events: write` permission added to release workflow for SARIF upload
- `install-argocd.sh` pre-creates `argocd` namespace before Helm install

---

## [1.1.0] - 2026-07-07

### Added
- CONTRIBUTING.md, SECURITY.md, GitHub issue templates, PR template
- Trivy vulnerability scanning in CI and release workflow
- Container image published to ghcr.io and Docker Hub on every release

### Fixed
- Lowercase repo owner in Trivy image ref
- `security-events: write` permission for SARIF upload

---

## [1.0.0] - 2026-07-07

### Added
- CIS-aligned Kubernetes cluster provisioning via `kind` + Terraform
- Zero-trust networking: Calico CNI + default-deny NetworkPolicy across all namespaces
- OPA Gatekeeper with 8 constraints: no-root, no-privileged, readonly-rootfs, no-hostpath, no-host-namespaces, require-resources, allowed-repos, capabilities-and-ports
- Pod Security Admission (`restricted` profile) enforced on all workload namespaces
- Least-privilege RBAC — no wildcard verbs, no cluster-admin for workloads
- Falco runtime threat detection (modern eBPF driver) + Falco Sidekick UI
- Audit logging via hardened API server flags (CIS 3.2.x)
- One-command deploy: `make deploy` (kind, fully local, zero cloud cost)
- Policy test suite: 8 negative tests (insecure patterns rejected) + 1 positive test (secure workload allowed)
- CIS Benchmark scoring via kube-bench (`make bench`)
- GitHub Actions CI: deploy → test → bench → teardown on every push
- Container image published to ghcr.io and Docker Hub on every release
