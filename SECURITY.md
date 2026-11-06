# Security Policy

## Supported versions

| Version | Supported |
|---------|-----------|
| latest (main) | ✅ |
| v1.0.x | ✅ |
| older | ❌ |

## Reporting a vulnerability

**Do not open a public GitHub issue for security vulnerabilities.**

Report privately via GitHub's built-in security advisory:
1. Go to `https://github.com/KADHIRAVANEG/secure-kube/security/advisories`
2. Click **New draft security advisory**
3. Fill in the details and submit

We will respond within 72 hours and aim to release a fix within 14 days for confirmed vulnerabilities.

## Scope

This project is a **local development / reference implementation**. Please report:

- Vulnerabilities in the container image (`ghcr.io/joker-53/secure-kube`)
- Gatekeeper constraints that can be bypassed in ways not already documented
- CI/CD workflow vulnerabilities (secret exposure, injection attacks)
- Incorrect security documentation that could mislead users into unsafe configurations

Out of scope:

- CIS benchmark failures on `kind` that are documented in `docs/architecture.md`
- The fail-open Gatekeeper webhook (documented trade-off)
- Anonymous auth being enabled (documented trade-off)
- Vulnerabilities in upstream tools (report to Terraform, Gatekeeper, Falco, etc. directly)

## Known security trade-offs

These are intentional, documented decisions — not vulnerabilities:

| Trade-off | Reason | Reference |
|---|---|---|
| Gatekeeper webhook is fail-open | Calico IPAM deadlock with fail-closed | `docs/architecture.md` |
| `anonymous-auth` enabled | kubeadm join bootstrap token requires it | `docs/architecture.md` |
| CIS benchmark partially fails | kind cannot satisfy node-level controls | `README.md` |
| Permissive allowed-repos list | Bundled examples need public registries | `gatekeeper/constraints/allowed-repos-constraint.yaml` |
