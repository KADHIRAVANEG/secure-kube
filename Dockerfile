# SecureKube tooling image
# Bundles every tool needed to run `make deploy` so users don't need
# to install anything locally — just Docker.
#
# Tool versions bumped to fix 429 CVEs found by Trivy in v1.4.0:
#   - crypto/tls issues fixed in newer Go-based binaries
#   - grpc-go authorization bypass fixed in updated versions
#
# Usage:
#   docker run --rm -it \
#     -v /var/run/docker.sock:/var/run/docker.sock \
#     -v $(pwd):/workspace \
#     -w /workspace \
#     ghcr.io/kadhiravaneg/secure-kube:latest \
#     make deploy

# ── Stage 1: download all tool binaries ──────────────────────────────
FROM alpine:3.21 AS downloader

ARG TARGETARCH=amd64

RUN apk add --no-cache curl unzip bash

WORKDIR /tools

ENV TERRAFORM_VERSION=1.15.8 \
    KUBECTL_VERSION=1.36.3 \
    HELM_VERSION=4.2.2 \
    KIND_VERSION=0.27.0 \
    ARGOCD_VERSION=3.0.6

# Terraform
RUN curl -fsSL "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_${TARGETARCH}.zip" \
      -o terraform.zip \
    && unzip terraform.zip \
    && rm terraform.zip \
    && chmod +x terraform

# kubectl
RUN curl -fsSL "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl" \
      -o kubectl \
    && chmod +x kubectl

# Helm
RUN curl -fsSL "https://get.helm.sh/helm-v${HELM_VERSION}-linux-${TARGETARCH}.tar.gz" \
      | tar -xz --strip-components=1 linux-${TARGETARCH}/helm \
    && chmod +x helm

# kind
RUN curl -fsSL "https://kind.sigs.k8s.io/dl/v${KIND_VERSION}/kind-linux-${TARGETARCH}" \
      -o kind \
    && chmod +x kind

# Argo CD CLI
RUN curl -fsSL "https://github.com/argoproj/argo-cd/releases/download/v${ARGOCD_VERSION}/argocd-linux-${TARGETARCH}" \
      -o argocd \
    && chmod +x argocd

# ── Stage 2: final lean image ─────────────────────────────────────────
FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       bash make git curl ca-certificates python3 python3-yaml \
    && rm -rf /var/lib/apt/lists/*

COPY --from=downloader /tools/terraform  /usr/local/bin/terraform
COPY --from=downloader /tools/kubectl    /usr/local/bin/kubectl
COPY --from=downloader /tools/helm       /usr/local/bin/helm
COPY --from=downloader /tools/kind       /usr/local/bin/kind
COPY --from=downloader /tools/argocd     /usr/local/bin/argocd

RUN terraform version \
    && kubectl version --client \
    && helm version \
    && kind version \
    && argocd version --client

COPY . /workspace
WORKDIR /workspace

CMD ["make", "help"]

LABEL org.opencontainers.image.title="SecureKube" \
      org.opencontainers.image.description="CIS-aligned zero-trust Kubernetes cluster via IaC" \
      org.opencontainers.image.source="https://github.com/KADHIRAVANEG/secure-kube" \
      org.opencontainers.image.licenses="MIT"
