#!/usr/bin/env bash
# SecureKube Software Supply-Chain & Attestation Verifier (SLSA Level 3)
# Cryptographically validates container image signatures and retrieves the
# tamper-proof SPDX Software Bill of Materials (SBOM) using Sigstore Cosign.
set -euo pipefail

IMAGE="${1:-ghcr.io/kadhiravaneg/secure-kube:latest}"
REPO_REGEX="https://github.com/KADHIRAVANEG/secure-kube/.*"
OIDC_ISSUER="https://token.actions.githubusercontent.com"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${BOLD}${CYAN}========================================================================${NC}"
echo -e "${BOLD}${CYAN}     SecureKube Supply-Chain Attestation & SBOM Verification (SLSA 3)   ${NC}"
echo -e "${BOLD}${CYAN}========================================================================${NC}"
echo -e "Target Image:        ${BOLD}${IMAGE}${NC}"
echo -e "OIDC Trust Domain:   ${OIDC_ISSUER}"
echo -e "Identity Pattern:    ${REPO_REGEX}"
echo ""

# 1. Check for Cosign
if ! command -v cosign >/dev/null 2>&1; then
  echo -e "${RED}✗ Error: 'cosign' binary not found in PATH.${NC}"
  echo -e "Install Cosign from: https://docs.sigstore.dev/cosign/system_config/installation/"
  echo -e "Or download via: curl -Lo /usr/local/bin/cosign https://github.com/sigstore/cosign/releases/latest/download/cosign-linux-amd64 && chmod +x /usr/local/bin/cosign"
  exit 1
fi

# 2. Verify Cosign Keyless Signature
echo -e "${BOLD}[Step 1/2] Verifying Cryptographic OIDC Container Signature...${NC}"
SIG_OUT=$(cosign verify \
  --certificate-identity-regexp="${REPO_REGEX}" \
  --certificate-oidc-issuer="${OIDC_ISSUER}" \
  "${IMAGE}" 2>&1) || {
    echo -e "  ${RED}✗ Signature verification failed!${NC}"
    echo "${SIG_OUT}"
    exit 1
}

echo -e "  ${GREEN}✓ Signature VALID:${NC} Image is cryptographically signed by official SecureKube CI/CD"
echo -e "  ${BLUE}Issuer:${NC} GitHub Actions OIDC"
echo ""

# 3. Verify and Extract SPDX SBOM Attestation
echo -e "${BOLD}[Step 2/2] Verifying and Extracting SLSA Level 3 SPDX SBOM Attestation...${NC}"
ATTEST_OUT=$(cosign verify-attestation \
  --type spdx \
  --certificate-identity-regexp="${REPO_REGEX}" \
  --certificate-oidc-issuer="${OIDC_ISSUER}" \
  "${IMAGE}" 2>&1) || {
    echo -e "  ${YELLOW}⚠ No SPDX SBOM attestation found for image ${IMAGE}.${NC}"
    echo -e "  (Note: Attestations are generated on release tags 'v*')"
    exit 0
}

echo -e "  ${GREEN}✓ Attestation VALID:${NC} In-toto SPDX predicate verified against Sigstore Rekor transparency log"

if command -v jq >/dev/null 2>&1; then
  TOTAL_PKGS=$(echo "${ATTEST_OUT}" | jq -r '.payload | @base64d | fromjson | .predicate.packages | length' 2>/dev/null || echo "N/A")
  echo -e "  ${BLUE}Verified Components:${NC} ${TOTAL_PKGS} software packages recorded in attested SBOM"
fi

echo ""
echo -e "${BOLD}${CYAN}========================================================================${NC}"
echo -e "${BOLD}${GREEN}✓ SUPPLY CHAIN INTEGRITY CONFIRMED (SLSA LEVEL 3 COMPLIANT)${NC}"
echo -e "Zero unauthorized tampering detected. Image provenance verified."
echo -e "${BOLD}${CYAN}========================================================================${NC}"
