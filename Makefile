# Makefile for the development clusters

GIT_BRANCH := $(shell git rev-parse --abbrev-ref HEAD)
LAST_TAG ?= $(shell git tag --sort=-version:refname | head -n 2 | tail -n 1)
REVISION := $(shell git rev-parse --abbrev-ref HEAD)

.PHONY: help
help: ## Display this help menu
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-30s %s\n", $$1, $$2}'

standalone: ## Provision a standalone cluster locally
	@echo "--> Provisioning Standalone Cluster (dev)"
	@scripts/make-dev.sh \
		--cluster-type standalone \
	  --cluster dev \
		--use-revision ${REVISION}

standalone-aws: ## Provision a standalone cluster in AWS
	@echo "--> Provisioning Standalone Cluster (dev) in AWS"
	@cd terraform && make init
	@cd terraform && ENVIRONMENT=dev make environment

destroy-standalone-aws: ## Destroy the standalone AWS cluster
	@echo "--> Destroying Standalone Cluster (dev) in AWS"
	@cd terraform && make init
	@cd terraform && ENVIRONMENT=dev make destroy-environment

eks-list: ## List EKS clusters (requires ENVIRONMENT variable)
	@$(MAKE) -C terraform eks-list ENVIRONMENT="$(ENVIRONMENT)"

eks-login: ## Login to EKS cluster (requires CLUSTER_NAME variable)
	@$(MAKE) -C terraform eks-login CLUSTER_NAME="$(CLUSTER_NAME)"

hub: ## Provision a hub cluster locally
	@echo "--> Provisioning Hub Cluster (hub)"
	@scripts/make-dev.sh \
		--cluster-type hub \
		--cluster hub

hub-aws: ## Provision a hub cluster in AWS
	@echo "--> Provisioning Hub Cluster (hub) in AWS"
	@cd terraform && make init
	@cd terraform && make hub

destroy-hub-aws: ## Destroy the hub AWS cluster
	@echo "--> Destroying Hub Cluster (hub) in AWS"
	@cd terraform && make init
	@cd terraform && make destroy-hub

spoke: ## Provision a spoke cluster locally
	@echo "Provisioning Spoke Cluster (spoke)"
	@scripts/make-spoke.sh --cluster spoke

spoke-aws: ## Provision a spoke cluster in AWS
	@echo "--> Provisioning Spoke Cluster (spoke) in AWS"
	@cd terraform && make init
	@cd terraform && make spoke

destroy-spoke-aws: ## Destroy the spoke AWS cluster
	@echo "--> Destroying Spoke Cluster (spoke) in AWS"
	@cd terraform && make init
	@cd terraform && make destroy-spoke

serve-docs: ## Serve documentation locally
	@echo "--> Serving the documentation..."
	@cd docs && npm start

clean: ## Delete all local development clusters
	@echo "Deleting development clusters..."
	@kind delete cluster --name dev 2>/dev/null || true
	@kind delete cluster --name hub 2>/dev/null || true
	@kind delete cluster --name spoke 2>/dev/null || true
	@rm -f .skip

changelog: ## Generate changelog from git tags
	@echo "--> Generating the changelog..."
	@git-cliff --config .cliff/cliff.toml $(LAST_TAG)..HEAD

test: ## Run all tests and validations
	@echo "--> Testing the configuration..."
	@$(MAKE) validate
	@$(MAKE) lint
	@$(MAKE) validate-templates

validate-templates: generate-template-fixtures ## Test ApplicationSet templatePatch rendering
	@echo "--> Testing ApplicationSet templatePatch rendering (Ginkgo)..."
	@cd tests/templates && go test ./... -count=1

generate-template-fixtures: ## Regenerate embedded template patches
	@echo "--> Regenerating embedded template patches..."
	@cd $(CURDIR) && python3 scripts/generate-template-fixtures.py

e2e: ## Run end-to-end tests
	@echo "--> Running the e2e tests..."
	@$(MAKE) standalone
	@tests/check-suite.sh

trigger-e2e: ## Trigger e2e tests via GitHub Actions
	echo "--> Triggering the e2e tests..."
	@gh workflow run e2e.yml --ref ${GIT_BRANCH}

validate: ## Run all validations
	@echo "--> Validating the configuration..."
	@$(MAKE) validate-actions
	@$(MAKE) validate-cluster-definitions
	@$(MAKE) validate-helm-addons
	@$(MAKE) validate-kustomize-addons
	@$(MAKE) validate-kustomize
	@$(MAKE) validate-helm-charts
	@$(MAKE) validate-kyverno
	@$(MAKE) validate-schema

validate-cluster-definitions: ## Validate cluster definitions
	@echo "--> Validating the cluster definitions..."
	@scripts/validate-cluster-definitions.sh

validate-actions: ## Validate GitHub Actions
	@echo "--> Validating Github Actions..."
	@actionlint

validate-helm-addons: ## Validate Helm addons
	@echo "--> Validating the helm addons..."
	@scripts/validate-addon-schemas.sh --helm

validate-kustomize-addons: ## Validate Kustomize addons
	@echo "--> Validating the kustomize addons..."
	@scripts/validate-addon-schemas.sh --kustomize

generate-addons-docs: ## Generate addons catalog documentation
	@echo "--> Generating addons catalog documentation..."
	@scripts/generate-addons.sh

validate-kyverno: ## Validate Kyverno policies
	@echo "--> Validating the Kyverno policies..."
	@scripts/validate-kyverno.sh

validate-kustomize: ## Validate Kustomize configuration
	@echo "--> Validating the kustomize configuration..."
	@scripts/validate-kustomize.sh

validate-helm-charts: ## Validate Helm Charts
	@echo "--> Validating Helm Charts..."
	@scripts/validate-helm-charts.sh

validate-schema: ## Validate cluster and workload schemas
	@echo "--> Validating cluster and workload schemas..."
	@scripts/validate-schema.sh

validate-docs: ## Validate documentation
	@echo "--> Validating the documentation..."
	@$(MAKE) validate-docs-spelling

validate-docs-spelling: ## Spell check documentation
	@echo "--> Spell Checking Docs"
	@misspell docs

lint-yaml: ## Lint YAML files
	@echo "--> Linting YAML files..."
	@yamllint .

lint: ## Run all linting checks
	@echo "--> Linting the tenant cluster..."
	@$(MAKE) lint-yaml
	@$(MAKE) lint-platform-applications

lint-platform-applications: ## Lint platform applications
	@echo "--> Linting the platform applications..."
	@kubeconform -ignore-missing-schemas apps

check-docs-updates: ## Check for documentation dependency updates
	@echo "--> Checking for documentation dependency updates..."
	@cd docs && npm outdated

update-docs: ## Update documentation dependencies
	@echo "--> Updating documentation dependencies..."
	@cd docs && npm update

