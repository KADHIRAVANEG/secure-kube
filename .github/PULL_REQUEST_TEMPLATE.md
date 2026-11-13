## What does this PR do?

<!-- Short description of the change -->

## Type of change

- [ ] Bug fix
- [ ] New feature / constraint
- [ ] Cloud module (EKS / GKE / AKS)
- [ ] Documentation
- [ ] CI/CD improvement
- [ ] Refactor

## Related issue

Closes #<!-- issue number -->

## Testing

- [ ] `make lint` passes (ShellCheck, Terraform fmt, YAML validator)
- [ ] `make test-offline` passes (`gator test` v3.18.0)
- [ ] `make test` passes (all live policy checks green)
- [ ] `make attack` passes (100% defense resilience score)
- [ ] New constraint has a corresponding negative test in `examples/insecure-apps.yaml`
- [ ] CI passes on this PR

## Checklist

- [ ] Commit messages follow the Conventional Commits format
- [ ] New constraints include `argocd`, `gatekeeper-system`, `falco`, `kube-system`, `calico-system`, `monitoring`, `local-path-storage`, `external-secrets` in `excludedNamespaces`
- [ ] If applicable, in-tree CEL `ValidatingAdmissionPolicy` added to `kustomize/base/vap/`
- [ ] Documentation updated if behaviour changed
- [ ] `docs/architecture.md` updated if a trade-off was made

## Screenshots / output (if relevant)

<!-- paste `make test` output or any relevant terminal output -->
