#!/usr/bin/env bash
# Sign container images with Cosign keyless signing (Sigstore/Fulcio).
# This script is called from the GitHub Actions release workflow after
# images are pushed to GHCR and Docker Hub.
#
# Keyless signing uses GitHub Actions OIDC identity — no keys needed.
# Signatures are stored in the Sigstore transparency log (Rekor) and
# alongside the image in the OCI registry.
#
# Verify any image with:
#   cosign verify \
#     --certificate-identity-regexp="https://github.com/KADHIRAVANEG/secure-kube/.*" \
#     --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
#     ghcr.io/joker-53/secure-kube:v1.4.0
set -euo pipefail

OWNER_LC=$(echo "${GITHUB_REPOSITORY_OWNER}" | tr '[:upper:]' '[:lower:]')
VERSION="${1:-latest}"

GHCR_IMAGE="ghcr.io/${OWNER_LC}/secure-kube:${VERSION}"
DOCKERHUB_IMAGE="${DOCKERHUB_USERNAME}/secure-kube:${VERSION}"

echo "→ Signing ${GHCR_IMAGE} with Cosign keyless..."
cosign sign --yes "${GHCR_IMAGE}"

echo "→ Signing ${DOCKERHUB_IMAGE} with Cosign keyless..."
cosign sign --yes "${DOCKERHUB_IMAGE}"

echo "✅ Images signed. Verify with:"
echo "   cosign verify \\"
echo "     --certificate-identity-regexp='https://github.com/KADHIRAVANEG/secure-kube/.*' \\"
echo "     --certificate-oidc-issuer='https://token.actions.githubusercontent.com' \\"
echo "     ${GHCR_IMAGE}"
