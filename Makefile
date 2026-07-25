#   make all                       build everything locally
#   make lint scan                 the gates CI enforces
#   make push TAG=$(git rev-parse --short HEAD)

SHELL := /usr/bin/env bash
.SHELLFLAGS := -euo pipefail -c
.DEFAULT_GOAL := help

REGISTRY       ?= abdullahxz
ALPINE_VERSION ?= 3.24.1
PG_MAJOR       ?= 17
TAG            ?= dev

# Add linux/arm64 after: scripts/fetch-rootfs.sh <version> aarch64
PLATFORMS      ?= linux/amd64

VCS_REF        := $(shell git rev-parse --short HEAD 2>/dev/null || echo unknown)
BUILD_DATE     := $(shell date -u +%Y-%m-%dT%H:%M:%SZ)

ALPINE_IMAGE   := $(REGISTRY)/alpine:$(ALPINE_VERSION)
NETSHOOT_IMAGE := $(REGISTRY)/netshoot:$(TAG)
PSQL_IMAGE     := $(REGISTRY)/psql:$(PG_MAJOR)-$(TAG)

BASE_IMAGE     ?= $(ALPINE_IMAGE)

TRIVY_IMAGE      ?= aquasec/trivy:latest
HADOLINT_IMAGE   ?= hadolint/hadolint:latest-alpine
SHELLCHECK_IMAGE ?= koalaman/shellcheck:stable

COMMON_ARGS := --build-arg VCS_REF=$(VCS_REF) --build-arg BUILD_DATE=$(BUILD_DATE)
BUILD_LOAD  := docker buildx build --load $(COMMON_ARGS)
BUILD_PUSH  := docker buildx build --push --platform $(PLATFORMS) \
	--sbom=true --provenance=mode=max $(COMMON_ARGS)

.PHONY: help
help: ## Show this help
	@awk 'BEGIN{FS=":.*##"} /^[a-zA-Z0-9_%-]+:.*##/ {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

.PHONY: verify
verify: ## Verify the vendored Alpine rootfs against SHA256SUMS
	@cd alpine && if command -v sha256sum >/dev/null 2>&1; then \
		sha256sum -c SHA256SUMS; \
	else \
		shasum -a 256 -c SHA256SUMS; \
	fi

.PHONY: lint
lint: ## Lint Dockerfiles and shell scripts
	@rc=0; \
	for f in alpine/Dockerfile netshoot/Dockerfile psql/Dockerfile; do \
		echo "== hadolint $$f"; \
		docker run --rm -i -v "$$PWD/.hadolint.yaml:/.hadolint.yaml:ro" \
			$(HADOLINT_IMAGE) hadolint --config /.hadolint.yaml - < "$$f" || rc=1; \
	done; \
	echo "== shellcheck"; \
	docker run --rm -v "$$PWD:/src:ro" -w /src $(SHELLCHECK_IMAGE) \
		scripts/fetch-rootfs.sh netshoot/harden.sh || rc=1; \
	exit $$rc

.PHONY: alpine
alpine: verify ## Build the base image
	$(BUILD_LOAD) --build-arg ALPINE_VERSION=$(ALPINE_VERSION) -t $(ALPINE_IMAGE) alpine

.PHONY: netshoot
netshoot: ## Build netshoot, core toolset (default target)
	$(BUILD_LOAD) --build-arg BASE_IMAGE=$(BASE_IMAGE) --target core \
		-t $(NETSHOOT_IMAGE) netshoot

.PHONY: netshoot-full
netshoot-full: ## Build netshoot, full toolset
	$(BUILD_LOAD) --build-arg BASE_IMAGE=$(BASE_IMAGE) --target full \
		-t $(NETSHOOT_IMAGE)-full netshoot

.PHONY: psql
psql: ## Build the PostgreSQL client image
	$(BUILD_LOAD) --build-arg BASE_IMAGE=$(BASE_IMAGE) --build-arg PG_MAJOR=$(PG_MAJOR) \
		-t $(PSQL_IMAGE) psql

.PHONY: all
all: alpine netshoot netshoot-full psql ## Build every image locally

.PHONY: scan
scan: ## Fail on fixable HIGH/CRITICAL CVEs
	@for img in $(ALPINE_IMAGE) $(NETSHOOT_IMAGE) $(NETSHOOT_IMAGE)-full $(PSQL_IMAGE); do \
		echo "== trivy $$img"; \
		docker run --rm -v /var/run/docker.sock:/var/run/docker.sock $(TRIVY_IMAGE) \
			image --scanners vuln --ignore-unfixed --exit-code 1 \
			--severity HIGH,CRITICAL "$$img"; \
	done

.PHONY: sizes
sizes: ## Show the size cost of each variant
	@docker images --format '{{.Repository}}:{{.Tag}}\t{{.Size}}' \
		| grep -E '$(REGISTRY)/(alpine|netshoot|psql)' | sort

.PHONY: sbom
sbom: ## Write CycloneDX SBOMs to dist/
	@mkdir -p dist
	@for img in $(ALPINE_IMAGE) $(NETSHOOT_IMAGE) $(NETSHOOT_IMAGE)-full $(PSQL_IMAGE); do \
		out="dist/$$(echo "$$img" | tr '/:' '__').cdx.json"; \
		echo "== sbom $$img -> $$out"; \
		docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
			-v "$$PWD/dist:/dist" $(TRIVY_IMAGE) image --format cyclonedx \
			--output "/dist/$$(basename "$$out")" "$$img"; \
	done

.PHONY: push
push: verify ## Build and push everything, children pinned to the base digest
	$(BUILD_PUSH) --build-arg ALPINE_VERSION=$(ALPINE_VERSION) -t $(ALPINE_IMAGE) alpine
	@digest=$$(docker buildx imagetools inspect $(ALPINE_IMAGE) --format '{{.Manifest.Digest}}'); \
	echo ">> base digest $$digest"; \
	$(MAKE) push-children BASE_IMAGE=$(REGISTRY)/alpine@$$digest

.PHONY: push-children
push-children: ## Push the derived images (requires BASE_IMAGE)
	$(BUILD_PUSH) --build-arg BASE_IMAGE=$(BASE_IMAGE) --build-arg PG_MAJOR=$(PG_MAJOR) \
		-t $(PSQL_IMAGE) psql
	$(BUILD_PUSH) --build-arg BASE_IMAGE=$(BASE_IMAGE) --target core \
		-t $(NETSHOOT_IMAGE) netshoot
	$(BUILD_PUSH) --build-arg BASE_IMAGE=$(BASE_IMAGE) --target full \
		-t $(NETSHOOT_IMAGE)-full netshoot

.PHONY: clean
clean: ## Remove build artefacts
	rm -rf dist
