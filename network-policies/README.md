# Network Policy Templates & Zero-Trust Reference

Per-workload egress and ingress NetworkPolicy templates for SecureKube.

The cluster ships with a `default-deny-all` policy (`kustomize/base/network-policies/default-deny.yaml`) that blocks **ALL** ingress and egress across all managed namespaces. These templates allow you to explicitly declare least-privilege network paths for each microservice — the foundational principle of zero-trust Kubernetes networking.

---

## Architecture Overview

```
                      +-------------------+
                      |   Ingress Gateway |
                      +---------+---------+
                                | (TCP 8080)
                                v
                      +-------------------+
                      |   Frontend Tier   |
                      +---------+---------+
                                | (TCP 8080)
                                v
                      +-------------------+
                      |   Backend Tier    |
                      +---------+---------+
                                | (TCP 5432)
                                v
                      +-------------------+
                      |   Database Tier   |
                      +-------------------+
```

By default on Calico CNI, without explicit network policy rules:
- Pods cannot reach CoreDNS (`kube-dns` on UDP/TCP port 53).
- Pods cannot communicate with other pods in the same namespace or across namespaces.
- Pods cannot initiate egress connections to the internet or external cloud APIs.

---

## How to Use Templates

1. Copy the relevant template(s) from `network-policies/egress-templates/` into your workload's deployment folder or Kustomize base.
2. Update the `podSelector` (e.g. `matchLabels: { app: my-workload }`).
3. Apply directly or let Argo CD sync the manifests.

```bash
# Apply a single template directly
kubectl apply -f network-policies/egress-templates/allow-dns.yaml

# Or customize a template for your service
cp network-policies/egress-templates/allow-external-https.yaml \
   kustomize/base/network-policies/my-app-egress.yaml

# Apply via Kustomize
kubectl apply -k kustomize/base/network-policies/
```

---

## Template Index

| Template File | Protocol & Port | Allowed Traffic | Use Case |
|---|---|---|---|
| [`allow-dns.yaml`](egress-templates/allow-dns.yaml) | UDP & TCP 53 | CoreDNS in `kube-system` | **Mandatory** for almost all workloads requiring hostname resolution. |
| [`allow-same-namespace.yaml`](egress-templates/allow-same-namespace.yaml) | Any | Workloads within the same namespace | Microservices sharing a namespace that trust internal mesh traffic. |
| [`allow-to-namespace.yaml`](egress-templates/allow-to-namespace.yaml) | Targeted | Cross-namespace egress to specific pods | Microservice tier segregation (e.g., frontend in `web` to backend in `api`). |
| [`allow-external-https.yaml`](egress-templates/allow-external-https.yaml) | TCP 443 | Outbound to `0.0.0.0/0` (excluding RFC 1918 private IPs) | Calling public REST APIs, third-party payment gateways, or webhooks. |
| [`allow-external-cidr.yaml`](egress-templates/allow-external-cidr.yaml) | Custom IP/Port | Outbound to pinned CIDR block | Tightly scoped external egress (e.g., enterprise VPC gateway or static IP). |
| [`allow-database-egress.yaml`](egress-templates/allow-database-egress.yaml) | TCP 5432 / 3306 / 6379 | Egress to database pods by selector | Backend service connecting to PostgreSQL, MySQL, or Redis. |
| [`allow-monitoring.yaml`](egress-templates/allow-monitoring.yaml) | TCP metrics port | Ingress from Prometheus in `monitoring` | Microservices exposing `/metrics` endpoints for Prometheus scraping. |
| [`allow-api-gateway.yaml`](egress-templates/allow-api-gateway.yaml) | Target port | Ingress from API Gateway / Ingress Controller | Backend microservices that must reject all direct ingress except from gateway. |

---

## Reference Implementation: 3-Tier Application

A complete reference microservice architecture showcasing layered NetworkPolicies is provided in [`examples/three-tier-app.yaml`](../examples/three-tier-app.yaml).

It deploys:
- **Frontend** (`app: frontend`): Receives ingress from gateway, has egress only to DNS and Backend.
- **Backend** (`app: backend`): Receives ingress only from Frontend, has egress only to DNS and Database.
- **Database** (`app: database`): Receives ingress only from Backend on port 5432, zero external egress.

To deploy and test the 3-tier workload:
```bash
# Deploy the sample workload and network policies
kubectl apply -f examples/three-tier-app.yaml

# Verify frontend can reach backend
kubectl exec -n three-tier deploy/frontend -- nc -zv backend 8080

# Verify frontend CANNOT reach database directly (blocked by policy)
kubectl exec -n three-tier deploy/frontend -- nc -zv -w 3 database 5432
# Expected: Timeout / Connection refused by Calico NetworkPolicy

# Cleanup
kubectl delete -f examples/three-tier-app.yaml
```

---

## Verifying Network Isolation

```bash
# List all active policies in a namespace
kubectl get networkpolicies -n default

# Inspect policy rule details
kubectl describe networkpolicy default-deny-all -n default

# Live connection probe from a test pod
kubectl run test-probe --rm -it --image=busybox:1.36 --restart=Never -- nslookup kubernetes.default
```
