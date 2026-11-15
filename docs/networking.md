# Zero-Trust Networking & Microsegmentation

SecureKube implements a strict **zero-trust network model** powered by [Project Calico CNI](https://www.tigera.io/project-calico/). By default, all network traffic is dropped unless an explicit, least-privilege `NetworkPolicy` allows it.

---

## 🔒 Default-Deny Architecture

The cluster ships with a cluster-wide default-deny policy in `kustomize/base/network-policies/default-deny.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
```

### What Default-Deny Blocks
Without an explicit allow policy:
- ❌ Pods **cannot** perform DNS queries to CoreDNS.
- ❌ Pods **cannot** communicate with other workloads in the same or other namespaces.
- ❌ Pods **cannot** initiate outbound egress to external APIs or the internet.
- ❌ Lateral pivoting after a container breakout is rendered impossible at the packet layer.

To enable essential cluster functionality, SecureKube provisions an isolated DNS egress policy:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns-egress
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
```

---

## 🤖 Automated NetworkPolicy Discovery Tool

One of the greatest developer pain points is figuring out exact egress ports and IP ranges required by a microservice.

SecureKube solves this with `scripts/generate-network-policy.sh`:

```bash
make generate-network-policy TARGET=my-app-pod NS=default
```

### How It Works
1. Analyzes live socket connections and `/proc/net` tables of the running target pod.
2. Identifies all remote endpoints and destination ports.
3. Classifies endpoints into:
   - **Internal Cluster Services**: Translates Service ClusterIPs to Kubernetes Service selectors.
   - **External Public Endpoints**: Translates external CIDRs into scoped IPBlocks.
4. Auto-generates a ready-to-apply, least-privilege YAML manifest:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: my-app-discovered-egress
  namespace: default
spec:
  podSelector:
    matchLabels:
      app: my-app
  policyTypes:
    - Egress
  egress:
    # Discovered DNS dependency
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
      ports:
        - protocol: UDP
          port: 53
    # Discovered PostgreSQL dependency
    - to:
        - podSelector:
            matchLabels:
              app: postgresql
      ports:
        - protocol: TCP
          port: 5432
```

---

## 📦 Production Policy Catalog

SecureKube provides pre-tested templates in `network-policies/egress-templates/`:

| Template File | Allowed Traffic | Primary Use Case |
|---|---|---|
| `allow-dns.yaml` | UDP/TCP 53 to `kube-system` | Essential DNS resolution |
| `allow-same-namespace.yaml` | Intranamespace traffic | Microservices in a shared namespace |
| `allow-to-namespace.yaml` | Cross-namespace egress | Tier segregation (frontend → backend) |
| `allow-external-https.yaml` | TCP 443 outbound (excl. RFC1918) | Third-party REST APIs and payment gateways |
| `allow-database-egress.yaml` | TCP 5432 / 3306 / 6379 | Scoped database connectivity |
| `allow-monitoring.yaml` | TCP metrics port | Prometheus scraper ingress |
