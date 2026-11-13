include config.env
export

.PHONY: deploy deploy-light destroy cluster policies gatekeeper falco argocd observability verify test bench \
        status logs clean-logs dashboard dashboard-argocd dashboard-grafana dashboard-prometheus sync-policies sync-rbac \
        sync-gatekeeper sync-pod-security sync-helm-apps sync-all clean help

CLUSTER_NAME  ?= securekube
TF_VAR_cluster_name         = $(strip $(CLUSTER_NAME))
TF_VAR_enable_network_policy_cni = $(strip $(ENABLE_CALICO))
export TF_VAR_cluster_name TF_VAR_enable_network_policy_cni

help: ## Show this help
	@grep -h -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-22s\033[0m %s\n", $$1, $$2}'

deploy: cluster policies gatekeeper falco argocd observability test ## Full one-command deploy (kind, local)
	@echo ""
	@echo "✅ SecureKube is up. CIS-hardened, zero-trust, policy-enforced, GitOps-managed, fully observable."
	@echo "   Run 'make dashboard-grafana'    → Grafana at localhost:3000 (admin / securekube-admin)"
	@echo "   Run 'make dashboard-prometheus' → Prometheus at localhost:9090"
	@echo "   Run 'make dashboard-argocd'     → Argo CD at localhost:8080"
	@echo "   Run 'make dashboard'            → Falco Sidekick UI at localhost:2802"

deploy-light: ## Deploy with Falco disabled and 1 worker — for slower machines
	@$(MAKE) cluster
	@$(MAKE) policies
	@$(MAKE) gatekeeper
	@$(MAKE) test
	@echo "✅ SecureKube (light mode) is up — Falco skipped. Run 'make falco' later if you want runtime monitoring."

cluster: ## Step 1: Provision the kind cluster via Terraform
	cd terraform/kind && terraform init -input=false && terraform apply -auto-approve
	@echo "→ Cluster '$(CLUSTER_NAME)' provisioned ($(CONTROL_PLANE_COUNT) control-plane, $(WORKER_COUNT) worker)"

policies: ## Step 2-3: Apply NetworkPolicy, RBAC, Pod Security Standards
	kubectl apply -k kustomize/base
	@echo "→ Default-deny NetworkPolicy, least-privilege RBAC, and PSS labels applied"

gatekeeper: ## Step 4: Install OPA Gatekeeper + all constraint templates + constraints
	helm repo add gatekeeper https://open-policy-agent.github.io/gatekeeper/charts --force-update
	helm repo update
	helm upgrade --install gatekeeper gatekeeper/gatekeeper \
		--namespace gatekeeper-system --create-namespace \
		--wait --timeout 180s \
		-f helm/gatekeeper-values.yaml
	kubectl wait --for=condition=Available --timeout=120s -n gatekeeper-system deployment/gatekeeper-controller-manager
	kubectl apply -f gatekeeper/constraint-templates/
	@echo "→ Waiting for CRDs to register..."
	sleep 8
	kubectl apply -f gatekeeper/constraints/
	@echo "→ Gatekeeper installed — 9 constraints enforced: no-root, no-privileged, readonly-rootfs, no-hostpath, no-host-namespaces, require-resources, allowed-repos, capabilities-and-ports, require-signed-images"

falco: ## Step 5: Install Falco for runtime threat detection + audit logging
ifeq ($(strip $(ENABLE_FALCO)),true)
	helm repo add falcosecurity https://falcosecurity.github.io/charts --force-update
	helm repo update
	helm upgrade --install falco falcosecurity/falco \
		--namespace falco --create-namespace \
		-f helm/falco-values.yaml
	@echo "→ Falco runtime monitoring active. Run 'make dashboard' to view alerts."
else
	@echo "→ ENABLE_FALCO=false in config.env, skipping Falco install"
endif

argocd: ## Install Argo CD + register all SecureKube Applications (manual sync mode)
	./scripts/install-argocd.sh

dashboard-argocd: ## Port-forward the Argo CD UI to localhost:8080
	@echo "Opening Argo CD UI at http://localhost:8080 (Ctrl+C to stop)"
	@echo "Username: admin"
	@echo "Password: $$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"
	kubectl port-forward -n argocd svc/argocd-server 8080:80

sync-policies: ## Manually trigger Argo CD sync for network policies
	kubectl -n argocd patch application securekube-network-policies \
		--type merge -p '{"operation":{"initiatedBy":{"username":"makefile"},"sync":{"revision":"HEAD"}}}'

sync-rbac: ## Manually trigger Argo CD sync for RBAC
	kubectl -n argocd patch application securekube-rbac \
		--type merge -p '{"operation":{"initiatedBy":{"username":"makefile"},"sync":{"revision":"HEAD"}}}'

sync-pod-security: ## Manually trigger Argo CD sync for Pod Security Standards
	kubectl -n argocd patch application securekube-pod-security \
		--type merge -p '{"operation":{"initiatedBy":{"username":"makefile"},"sync":{"revision":"HEAD"}}}'

sync-gatekeeper: ## Manually trigger Argo CD sync for Gatekeeper constraints
	kubectl -n argocd patch application securekube-gatekeeper-templates \
		--type merge -p '{"operation":{"initiatedBy":{"username":"makefile"},"sync":{"revision":"HEAD"}}}'
	kubectl -n argocd patch application securekube-gatekeeper-constraints \
		--type merge -p '{"operation":{"initiatedBy":{"username":"makefile"},"sync":{"revision":"HEAD"}}}'

sync-helm-apps: ## Manually trigger Argo CD sync for Gatekeeper, Falco, Argo CD, and Monitoring Helm apps
	kubectl -n argocd patch application securekube-gatekeeper \
		--type merge -p '{"operation":{"initiatedBy":{"username":"makefile"},"sync":{"revision":"HEAD"}}}' || true
	kubectl -n argocd patch application securekube-falco \
		--type merge -p '{"operation":{"initiatedBy":{"username":"makefile"},"sync":{"revision":"HEAD"}}}' || true
	kubectl -n argocd patch application securekube-argocd \
		--type merge -p '{"operation":{"initiatedBy":{"username":"makefile"},"sync":{"revision":"HEAD"}}}' || true
	kubectl -n argocd patch application securekube-monitoring \
		--type merge -p '{"operation":{"initiatedBy":{"username":"makefile"},"sync":{"revision":"HEAD"}}}' || true

sync-observability: ## Manually trigger Argo CD sync for observability dashboards and alerts
	kubectl -n argocd patch application securekube-observability \
		--type merge -p '{"operation":{"initiatedBy":{"username":"makefile"},"sync":{"revision":"HEAD"}}}' || true

sync-all: sync-policies sync-rbac sync-pod-security sync-gatekeeper sync-helm-apps sync-observability ## Trigger Argo CD sync for all layers

observability: ## Install Prometheus + Grafana + Alertmanager + Falco alert rules
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update
	helm repo update
	helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
		--namespace monitoring --create-namespace \
		--wait --timeout 300s \
		-f helm/kube-prometheus-stack-values.yaml
	@echo "→ Prometheus + Grafana + Alertmanager installed"
	kubectl apply -f observability/falco-servicemonitor.yaml
	kubectl apply -f observability/dashboards/
	kubectl apply -f observability/alerts/
	helm upgrade --install falco falcosecurity/falco \
		--namespace falco \
		-f helm/falco-values.yaml
	@echo "→ Falco wired to Alertmanager, dashboards and alert rules loaded"
	@echo "→ Run 'make dashboard-grafana' to open Grafana (admin / securekube-admin)"

dashboard-grafana: ## Port-forward Grafana to localhost:3000
	@echo "Opening Grafana at http://localhost:3000 (Ctrl+C to stop)"
	@echo "Username: admin  Password: securekube-admin"
	kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

dashboard-prometheus: ## Port-forward Prometheus to localhost:9090
	@echo "Opening Prometheus at http://localhost:9090 (Ctrl+C to stop)"
	kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090

lint: ## Run static analysis (shellcheck, terraform fmt, YAML validation)
	@echo "→ Checking shell scripts with shellcheck..."
	shellcheck scripts/*.sh
	@echo "→ Checking Terraform formatting..."
	terraform -chdir=terraform/kind fmt -check -recursive
	@echo "→ Validating YAML manifests..."
	python3 -c "import yaml, glob; [list(yaml.safe_load_all(open(f))) for f in glob.glob('**/*.yaml', recursive=True) + glob.glob('**/*.yml', recursive=True)]"
	@echo "✓ All static linting checks passed!"

test-offline: ## Run offline Gatekeeper policy validation via gator
	./scripts/test-offline.sh

test: ## Step 6: Test policies (negative + positive)
	./scripts/test-policies.sh

verify: test ## Alias for 'test' (back-compat)

bench: ## Step 6: Run kube-bench and report the CIS score
	kubectl delete job kube-bench -n kube-system --ignore-not-found
	kubectl apply -n kube-system -f https://raw.githubusercontent.com/aquasecurity/kube-bench/main/job.yaml
	@echo "→ Waiting for kube-bench job to complete..."
	kubectl wait --for=condition=complete --timeout=120s job/kube-bench -n kube-system
	kubectl logs -n kube-system job/kube-bench
	@echo ""
	@echo "ℹ️  kube-bench runs in kube-system, not default: it needs hostPID/hostPath/"
	@echo "   privileged access to inspect node files, which our own restricted PSA on"
	@echo "   'default' correctly blocks. kube-system is intentionally left unlabeled"
	@echo "   for exactly this kind of system tooling — see docs/architecture.md."
	@echo ""
	@echo "ℹ️  kind runs a subset of a real control plane (no managed etcd/kubelet file perms"
	@echo "   the way a bare-metal install has). Expect PASS on API-server/RBAC/PSP-family"
	@echo "   controls and expected FAIL/WARN on node-file-permission controls — see docs/architecture.md."

status: ## Show health of every SecureKube component
	@echo "== Cluster =="
	@kubectl cluster-info --context kind-$(CLUSTER_NAME) 2>/dev/null || echo "  not running"
	@echo ""
	@echo "== Gatekeeper =="
	@kubectl get pods -n gatekeeper-system 2>/dev/null || echo "  not installed"
	@echo ""
	@echo "== Falco =="
	@kubectl get pods -n falco 2>/dev/null || echo "  not installed"
	@echo ""
	@echo "== Argo CD =="
	@kubectl get pods -n argocd 2>/dev/null || echo "  not installed"
	@echo ""
	@echo "== Argo CD Applications =="
	@kubectl get applications -n argocd 2>/dev/null || echo "  none registered"
	@echo ""
	@echo "== Observability =="
	@kubectl get pods -n monitoring 2>/dev/null || echo "  not installed"
	@echo ""
	@echo "== Constraints (active policies) =="
	@kubectl get constraints 2>/dev/null || echo "  none"
	@echo ""
	@echo "== Recent constraint violations =="
	@kubectl get events --field-selector reason=ConstraintViolation -A 2>/dev/null | tail -10 || echo "  none"

logs: ## Tail Falco alert logs
	kubectl logs -n falco -l app.kubernetes.io/name=falco -f --tail=50

clean-logs: ## Clear old kube-bench / test job leftovers
	kubectl delete job kube-bench -n kube-system --ignore-not-found
	kubectl delete pod -n default -l app=secure-app --ignore-not-found
	@echo "→ Stale jobs and test pods removed"

dashboard: ## Port-forward the Falco Sidekick UI to localhost:2802
	@echo "Opening Falco Sidekick UI at http://localhost:2802 (Ctrl+C to stop)"
	kubectl port-forward -n falco svc/falco-falcosidekick-ui 2802:2802

destroy: ## Tear down the cluster and all resources
	cd terraform/kind && terraform destroy -auto-approve
	@echo "→ Cluster destroyed"

clean: destroy ## Alias for destroy
