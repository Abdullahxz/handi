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

STAGING        ?= ghcr.io/abdullahxz/handi
STAGE_ALPINE   := $(STAGING)/alpine
STAGE_NETSHOOT := $(STAGING)/netshoot
STAGE_PSQL     := $(STAGING)/psql
DIGESTS        := dist/digests.env
DIGEST_OF      := docker buildx imagetools inspect --format '{{.Manifest.Digest}}'

TRIVY_IMAGE      ?= aquasec/trivy:latest
HADOLINT_IMAGE   ?= hadolint/hadolint:latest-alpine
SHELLCHECK_IMAGE ?= koalaman/shellcheck:stable

COMMON_ARGS := --build-arg VCS_REF=$(VCS_REF) --build-arg BUILD_DATE=$(BUILD_DATE)
LOAD_BUILDER ?= $(or $(shell docker context show 2>/dev/null),default)
BUILD_LOAD  := docker buildx build --builder $(LOAD_BUILDER) --load $(COMMON_ARGS)
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

.PHONY: stage
stage: verify ## Build and push attested images to the staging registry
	@mkdir -p dist
	$(BUILD_PUSH) --build-arg ALPINE_VERSION=$(ALPINE_VERSION) -t $(STAGE_ALPINE):$(TAG) alpine
	@base="$(STAGE_ALPINE)@$$($(DIGEST_OF) $(STAGE_ALPINE):$(TAG))"; \
	echo ">> staged base $$base"; \
	$(BUILD_PUSH) --build-arg BASE_IMAGE="$$base" --build-arg PG_MAJOR=$(PG_MAJOR) \
		-t $(STAGE_PSQL):$(PG_MAJOR)-$(TAG) psql; \
	$(BUILD_PUSH) --build-arg BASE_IMAGE="$$base" --target core \
		-t $(STAGE_NETSHOOT):$(TAG) netshoot; \
	$(BUILD_PUSH) --build-arg BASE_IMAGE="$$base" --target full \
		-t $(STAGE_NETSHOOT):$(TAG)-full netshoot; \
	{ echo "STAGED_ALPINE=$$base"; \
	  echo "STAGED_PSQL=$(STAGE_PSQL)@$$($(DIGEST_OF) $(STAGE_PSQL):$(PG_MAJOR)-$(TAG))"; \
	  echo "STAGED_NETSHOOT=$(STAGE_NETSHOOT)@$$($(DIGEST_OF) $(STAGE_NETSHOOT):$(TAG))"; \
	  echo "STAGED_NETSHOOT_FULL=$(STAGE_NETSHOOT)@$$($(DIGEST_OF) $(STAGE_NETSHOOT):$(TAG)-full)"; \
	} > $(DIGESTS)
	@cat $(DIGESTS)

.PHONY: scan-staged
scan-staged: ## Scan the staged digests; fixable HIGH/CRITICAL fails the build
	@set -a; . ./$(DIGESTS); set +a; \
	for ref in "$$STAGED_ALPINE" "$$STAGED_PSQL" "$$STAGED_NETSHOOT" "$$STAGED_NETSHOOT_FULL"; do \
		echo "== trivy $$ref"; \
		docker run --rm -e TRIVY_USERNAME -e TRIVY_PASSWORD \
			-v "$$HOME/.docker:/root/.docker:ro" $(TRIVY_IMAGE) \
			image --scanners vuln --ignore-unfixed --exit-code 1 \
			--severity HIGH,CRITICAL "$$ref"; \
	done

.PHONY: promote
promote: ## Copy staged digests to the public registry, asserting bytes unchanged
	@set -a; . ./$(DIGESTS); set +a; \
	promote_one() { \
		src="$$1"; dst="$$2"; want="$${src##*@}"; \
		docker buildx imagetools create --tag "$$dst" "$$src"; \
		got="$$($(DIGEST_OF) $$dst)"; \
		if [ "$$got" != "$$want" ]; then \
			echo "!! $$dst published as $$got but $$want was scanned" >&2; \
			exit 1; \
		fi; \
		echo ">> $$dst == $$want"; \
	}; \
	promote_one "$$STAGED_ALPINE" "$(ALPINE_IMAGE)"; \
	promote_one "$$STAGED_PSQL" "$(PSQL_IMAGE)"; \
	promote_one "$$STAGED_NETSHOOT" "$(NETSHOOT_IMAGE)"; \
	promote_one "$$STAGED_NETSHOOT_FULL" "$(NETSHOOT_IMAGE)-full"

.PHONY: clean
clean: ## Remove build artefacts
	rm -rf dist
