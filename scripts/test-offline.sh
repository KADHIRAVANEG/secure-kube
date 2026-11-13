#!/usr/bin/env bash
# Runs Gatekeeper offline policy validation using the gator CLI.
# Tests both negative (insecure pods rejected) and positive (secure pod allowed)
# scenarios without requiring a running Kubernetes cluster.
set -euo pipefail

TEMPLATES_DIR="gatekeeper/constraint-templates"
CONSTRAINTS_DIR="gatekeeper/constraints"
INSECURE_MANIFEST="examples/insecure-apps.yaml"
SECURE_MANIFEST="examples/secure-app.yaml"

if ! command -v gator >/dev/null 2>&1; then
  if [ -x "${HOME}/.local/bin/gator" ]; then
    export PATH="${HOME}/.local/bin:${PATH}"
  else
    echo "ERROR: 'gator' CLI not found. Install from:"
    echo "  https://github.com/open-policy-agent/gatekeeper/releases"
    exit 1
  fi
fi

echo "== SecureKube Offline Policy Verification (gator) =="
echo "→ Using gator: $(gator --version | head -n 1)"
echo ""

echo "-- 1. Evaluating insecure workloads (each MUST produce violations) --"
INSECURE_OUT=$(mktemp)
trap 'rm -f "${INSECURE_OUT}"' EXIT

if gator test --filename="${TEMPLATES_DIR}" --filename="${CONSTRAINTS_DIR}" --filename="${INSECURE_MANIFEST}" > "${INSECURE_OUT}" 2>&1; then
  echo "FAIL: Expected violations but gator test exited with 0"
  cat "${INSECURE_OUT}"
  exit 1
else
  echo "✓ Insecure pods rejected by admission policies (as expected)"
fi

# Verify specific constraints triggered
CONSTRAINTS=(
  "block-privileged"
  "require-non-root"
  "require-readonly-rootfs"
  "block-hostpath"
  "block-host-namespaces"
  "require-resources"
  "allowed-repos"
  "capabilities-and-ports"
)

ALL_TRIGGERED=true
for c in "${CONSTRAINTS[@]}"; do
  if grep -q "${c}" "${INSECURE_OUT}"; then
    echo "  → ${c}... OK (violation caught)"
  else
    echo "  → ${c}... MISSING violation"
    ALL_TRIGGERED=false
  fi
done

if [ "${ALL_TRIGGERED}" = false ]; then
  echo "ERROR: One or more constraints failed to trigger violations."
  exit 1
fi

echo ""
echo "-- 2. Evaluating secure workload (MUST NOT produce deny violations) --"
if gator test --filename="${TEMPLATES_DIR}" --filename="${CONSTRAINTS_DIR}" --filename="${SECURE_MANIFEST}" >/dev/null 2>&1; then
  echo "✓ secure-app... OK (admitted without deny violations)"
else
  echo "FAIL: secure-app was unexpectedly rejected by gator test"
  exit 1
fi

echo ""
echo "All offline policy checks passed successfully!"
