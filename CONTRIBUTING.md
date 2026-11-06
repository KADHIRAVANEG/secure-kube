# Contributing to SecureKube

Thank you for your interest in contributing. This document explains how to get started, what we're looking for, and how the review process works.

---

## Table of contents

- [Code of conduct](#code-of-conduct)
- [What we're looking for](#what-were-looking-for)
- [Getting started](#getting-started)
- [Development workflow](#development-workflow)
- [Commit message format](#commit-message-format)
- [Pull request process](#pull-request-process)
- [Testing requirements](#testing-requirements)
- [Reporting bugs](#reporting-bugs)
- [Suggesting features](#suggesting-features)

---

## Code of conduct

Be respectful, constructive, and patient. We're all here to learn and build something useful. Harassment of any kind is not tolerated.

---

## What we're looking for

Good contributions include:

- **Bug fixes** — especially around cluster provisioning, policy enforcement, or CI reliability
- **New Gatekeeper constraints** — additional security controls with corresponding tests
- **Cloud modules** — EKS, GKE, or AKS Terraform modules following the same pattern as `terraform/kind/`
- **Documentation improvements** — clarifying the architecture, adding examples, fixing inaccuracies
- **Test coverage** — more negative/positive test cases in `scripts/test-policies.sh`
- **Tooling improvements** — better observability, dashboards, or developer experience

We are NOT currently looking for:

- Changes that weaken the default security posture without a strong justification
- Additions that require a paid cloud account to test
- Large rewrites without prior discussion in an issue

---

## Getting started

### Prerequisites

```bash
terraform >= 1.5.0
kubectl >= 1.28
helm >= 3.12
kind >= 0.22
docker (with your user in the docker group)
```

Or use the container image — no local installs needed:

```bash
docker run --rm -it \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v $(pwd):/workspace -w /workspace \
  ghcr.io/joker-53/secure-kube:latest bash
```

### Fork and clone

```bash
git clone https://github.com/<your-username>/secure-kube
cd secure-kube
git remote add upstream https://github.com/KADHIRAVANEG/secure-kube
```

### Deploy locally

```bash
make deploy     # full stack
make test       # verify policies
make destroy    # tear down when done
```

---

## Development workflow

```bash
# Create a feature branch
git checkout -b feat/your-feature-name

# Make changes, test locally
make deploy
make test

# Commit (follow the format below)
git add .
git commit -m "feat: add XYZ constraint"

# Push and open a PR
git push origin feat/your-feature-name
```

---

## Commit message format

We follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>: <short description>

[optional body]
[optional footer]
```

Types: `feat`, `fix`, `docs`, `refactor`, `test`, `ci`, `chore`

Examples:
```
feat: add seccomp profile enforcement constraint
fix: add argocd to Gatekeeper excludedNamespaces
docs: clarify anonymous-auth trade-off in architecture.md
ci: add Trivy vulnerability scan to release workflow
```

---

## Pull request process

1. Open an issue first for anything non-trivial — discuss the approach before writing code
2. Keep PRs focused — one concern per PR
3. Make sure `make test` passes locally before opening a PR
4. Fill in the PR template completely
5. PRs require at least one approving review before merge
6. Squash commits on merge

---

## Testing requirements

Every PR that changes a policy, constraint, or security control must:

- Add a corresponding test case in `scripts/test-policies.sh` OR explain why one isn't needed
- Pass `make test` (all 9 policy checks green)
- Pass CI (GitHub Actions runs automatically on every PR)

For new Gatekeeper constraints specifically:
- Add the `ConstraintTemplate` in `gatekeeper/constraint-templates/`
- Add the `Constraint` in `gatekeeper/constraints/` with `argocd`, `gatekeeper-system`, `falco`, `kube-system`, `calico-system` in `excludedNamespaces`
- Add a negative test pod in `examples/insecure-apps.yaml`
- Add the pod name to the `EXPECTED_REJECTED` list in `scripts/test-policies.sh`

---

## Reporting bugs

Use the **Bug report** issue template. Include:

- OS and kernel version
- Docker version (`docker info | grep "Server Version"`)
- The full output of the failing command
- Steps to reproduce

---

## Suggesting features

Use the **Feature request** issue template. Describe:

- What problem it solves
- How it fits the project's security-focused scope
- Whether you're willing to implement it yourself

For cloud module proposals (EKS, GKE, AKS), include which cloud you can test against.
