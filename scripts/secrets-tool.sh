#!/usr/bin/env bash
# SecureKube SOPS & Age Secrets Management Utility
# Handles key generation, secret encryption, decryption, and cluster synchronization.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOPS_CONFIG="${REPO_ROOT}/.sops.yaml"
AGE_KEY_DIR="${HOME}/.config/sops/age"
AGE_KEY_FILE="${AGE_KEY_DIR}/keys.txt"

usage() {
  cat << EOF
SecureKube Secrets Management Tool (SOPS + Age)

Usage:
  ./scripts/secrets-tool.sh init                   # Generate Age keypair and configure .sops.yaml
  ./scripts/secrets-tool.sh encrypt <file.yaml>    # Encrypt a secret into <file.enc.yaml>
  ./scripts/secrets-tool.sh decrypt <file.enc.yaml> # Decrypt and print secret to stdout
  ./scripts/secrets-tool.sh apply <file.enc.yaml>  # Decrypt and apply secret directly to cluster
  ./scripts/secrets-tool.sh sync-key               # Sync Age private key to Argo CD namespace

EOF
  exit 1
}

check_deps() {
  if ! command -v sops >/dev/null 2>&1; then
    echo "ERROR: 'sops' binary not found. Please install SOPS: https://github.com/getsops/sops"
    exit 1
  fi
  if ! command -v age-keygen >/dev/null 2>&1; then
    echo "ERROR: 'age-keygen' not found. Please install Age: https://github.com/FiloSottile/age"
    exit 1
  fi
}

cmd_init() {
  check_deps
  mkdir -p "${AGE_KEY_DIR}"
  if [ ! -f "${AGE_KEY_FILE}" ]; then
    echo "→ Generating new Age key pair at ${AGE_KEY_FILE}..."
    age-keygen -o "${AGE_KEY_FILE}"
    chmod 600 "${AGE_KEY_FILE}"
  else
    echo "→ Found existing Age key pair at ${AGE_KEY_FILE}"
  fi

  PUBKEY=$(grep "public key:" "${AGE_KEY_FILE}" | awk '{print $NF}')
  echo "→ Age Public Key: ${PUBKEY}"

  echo "→ Generating ${SOPS_CONFIG}..."
  cat << EOF > "${SOPS_CONFIG}"
creation_rules:
  - path_regex: .*\.enc\.ya?ml$
    age: "${PUBKEY}"
EOF
  echo "✓ SOPS configured successfully with Age public key."
}

cmd_encrypt() {
  check_deps
  local src="${1:-}"
  if [ -z "${src}" ] || [ ! -f "${src}" ]; then
    echo "ERROR: Please specify a valid plaintext YAML secret file to encrypt."
    exit 1
  fi

  local dest="${src%.yaml}.enc.yaml"
  dest="${dest%.yml}.enc.yaml"

  echo "→ Encrypting ${src} -> ${dest}..."
  local tmp_dest="${dest}.tmp"
  sops --filename-override "${dest}" -e "${src}" > "${tmp_dest}"
  mv "${tmp_dest}" "${dest}"
  echo "✓ Encrypted successfully. Output written to ${dest}"
}

cmd_decrypt() {
  check_deps
  local src="${1:-}"
  if [ -z "${src}" ] || [ ! -f "${src}" ]; then
    echo "ERROR: Please specify an encrypted .enc.yaml file."
    exit 1
  fi

  export SOPS_AGE_KEY_FILE="${AGE_KEY_FILE}"
  sops -d "${src}"
}

cmd_apply() {
  check_deps
  local src="${1:-}"
  export SOPS_AGE_KEY_FILE="${AGE_KEY_FILE}"

  if [ -n "${src}" ]; then
    if [ ! -f "${src}" ]; then
      echo "ERROR: File '${src}' not found."
      exit 1
    fi
    echo "→ Decrypting and applying ${src} to cluster..."
    sops -d "${src}" | kubectl apply -f -
    echo "✓ Applied successfully."
    return 0
  fi

  local found=0
  for f in "${REPO_ROOT}/gitops/secrets"/*.enc.yaml; do
    if [ -f "${f}" ]; then
      found=1
      echo "→ Decrypting and applying ${f} to cluster..."
      sops -d "${f}" | kubectl apply -f -
    fi
  done

  if [ "${found}" -eq 0 ]; then
    echo "ERROR: No encrypted files found in gitops/secrets/. Specify a file explicitly."
    exit 1
  fi
  echo "✓ All encrypted secrets applied successfully."
}

cmd_sync_key() {
  if [ ! -f "${AGE_KEY_FILE}" ]; then
    echo "ERROR: Key file ${AGE_KEY_FILE} not found. Run 'init' first."
    exit 1
  fi

  echo "→ Syncing Age secret key to argocd namespace..."
  kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
  kubectl create secret generic sops-age-key \
    --namespace argocd \
    --from-file=keys.txt="${AGE_KEY_FILE}" \
    --dry-run=client -o yaml | kubectl apply -f -
  echo "✓ Secret 'sops-age-key' created in 'argocd' namespace."
}

ACTION="${1:-}"
case "${ACTION}" in
  init)
    cmd_init
    ;;
  encrypt)
    shift
    cmd_encrypt "${@}"
    ;;
  decrypt)
    shift
    cmd_decrypt "${@}"
    ;;
  apply)
    shift
    cmd_apply "${@}"
    ;;
  sync-key)
    cmd_sync_key
    ;;
  *)
    usage
    ;;
esac
