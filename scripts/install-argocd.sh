#!/usr/bin/env bash
# Installs Argo CD and registers all SecureKube Applications.
# Detects the GitHub remote URL from the local git config so you don't
# need to hardcode it anywhere — clone the repo, run make argocd, done.
set -euo pipefail

ARGOCD_NAMESPACE="argocd"
GITOPS_DIR="gitops/apps"

# ---------- 1. Detect repo URL from git remote ----------
REPO_URL=$(git remote get-url origin 2>/dev/null || echo "")
if [ -z "${REPO_URL}" ]; then
  echo "ERROR: could not detect git remote 'origin'. Set REPO_URL manually:"
  echo "  REPO_URL=https://github.com/youruser/securekube make argocd"
  exit 1
fi
# Normalise SSH remote (git@github.com:user/repo.git) to HTTPS
REPO_URL=$(echo "${REPO_URL}" | sed 's|git@github.com:|https://github.com/|' | sed 's|\.git$||')
echo "→ Repo URL: ${REPO_URL}"

# ---------- 2. Install Argo CD via Helm ----------
echo "→ Installing Argo CD..."
helm repo add argo https://argoproj.github.io/argo-helm --force-update
helm repo update
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
helm upgrade --install argocd argo/argo-cd \
  --namespace "${ARGOCD_NAMESPACE}" --create-namespace \
  --wait --timeout 300s \
  -f helm/argocd-values.yaml
echo "→ Argo CD installed"

# ---------- 3. Wait for Argo CD to be fully ready ----------
kubectl wait --for=condition=Available --timeout=120s \
  -n "${ARGOCD_NAMESPACE}" deployment/argocd-server
echo "→ Argo CD server ready"

# ---------- 4. Patch PLACEHOLDER with actual repo URL and apply ----------
echo "→ Registering SecureKube Applications..."
for f in "${GITOPS_DIR}"/*.yaml; do
  sed "s|https://github.com/PLACEHOLDER/securekube|${REPO_URL}|g" "${f}" \
    | kubectl apply -f -
done
echo "→ All Applications registered"

# ---------- 5. Print access info ----------
ARGOCD_PASSWORD=$(kubectl -n "${ARGOCD_NAMESPACE}" get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)
echo ""
echo "======================================================"
echo "  Argo CD is up. Access the UI:"
echo "  make dashboard-argocd"
echo "  URL:      http://localhost:8080"
echo "  Username: admin"
echo "  Password: ${ARGOCD_PASSWORD}"
echo ""
echo "  To sync a layer manually:"
echo "  make sync-policies      # network policies"
echo "  make sync-rbac          # RBAC"
echo "  make sync-gatekeeper    # Gatekeeper constraints"
echo "  make sync-helm-apps     # Helm releases (Gatekeeper, Falco, Argo CD)"
echo "  make sync-all           # everything"
echo "======================================================"
