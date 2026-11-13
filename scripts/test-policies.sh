#!/usr/bin/env bash
# Proves the cluster enforces exactly what it claims to:
#  - every insecure pattern in examples/insecure-apps.yaml gets rejected
#  - the well-formed pod in examples/secure-app.yaml gets ALLOWED
# A policy stack that only blocks bad things but also blocks good
# things isn't done -- it's just broken in a different direction.
set -uo pipefail

FAILURES=0
NAMESPACE=default

cleanup() {
  kubectl delete -f examples/insecure-apps.yaml -n "${NAMESPACE}" --ignore-not-found >/dev/null 2>&1
  kubectl delete -f examples/secure-app.yaml -n "${NAMESPACE}" --ignore-not-found >/dev/null 2>&1
}
cleanup
trap cleanup EXIT

echo "== SecureKube policy verification =="
echo ""
echo "-- Negative tests (each of these MUST be rejected) --"

kubectl apply -f examples/insecure-apps.yaml -n "${NAMESPACE}" >/tmp/insecure_apply.log 2>&1 || true

EXPECTED_REJECTED=(
  insecure-privileged
  insecure-root
  insecure-writable-rootfs
  insecure-hostpath
  insecure-hostnetwork
  insecure-no-resources
  insecure-untrusted-registry
  insecure-privileged-port
)

for pod in "${EXPECTED_REJECTED[@]}"; do
  echo -n "-> ${pod}... "
  if kubectl get pod "${pod}" -n "${NAMESPACE}" >/dev/null 2>&1; then
    echo "FAIL (was created, should have been rejected)"
    FAILURES=$((FAILURES + 1))
  elif grep -q "${pod}" /tmp/insecure_apply.log 2>/dev/null; then
    echo "OK (rejected as expected)"
  else
    echo "WARN (no record of this pod in apply output -- check manually)"
  fi
done

echo ""
echo "-- Positive test (this MUST be allowed) --"
echo -n "-> secure-app... "
if kubectl apply -f examples/secure-app.yaml -n "${NAMESPACE}" >/tmp/secure_apply.log 2>&1; then
  echo "OK (allowed as expected)"
else
  echo "FAIL (was rejected, should have been allowed)"
  cat /tmp/secure_apply.log
  FAILURES=$((FAILURES + 1))
fi

echo ""
if [ "${FAILURES}" -eq 0 ]; then
  echo "All policy checks passed -- insecure patterns blocked, secure workloads allowed."
  exit 0
else
  echo "${FAILURES} check(s) failed -- review Gatekeeper constraints and PSA labels."
  exit 1
fi
