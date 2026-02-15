.PHONY: build release-all release-linux-amd64 release-linux-arm64 clean test

# Configuration
BINARY_NAME := autobot-server
VERSION     := $(shell grep '^version:' shard.yml | cut -d' ' -f2)
BUILD_DIR   := build
BIN_DIR     := bin

# Crystal compiler flags
CRYSTAL       := crystal
SHARDS        := shards
RELEASE_FLAGS := --release --no-debug --progress
STATIC_FLAGS  := $(RELEASE_FLAGS) --static
DEBUG_FLAGS   := --debug --error-trace --progress

.DEFAULT_GOAL := build

## —— Building ————————————————————————————————————————

build: ## Build debug binary
	@echo "Building $(BINARY_NAME)..."
	@mkdir -p $(BIN_DIR)
	$(CRYSTAL) build src/main.cr -o $(BIN_DIR)/$(BINARY_NAME) $(DEBUG_FLAGS)

## —— Testing —————————————————————————————————————————

test: ## Run all tests
	$(CRYSTAL) spec --progress

## —— Multi-platform Releases ————————————————————————

release-all: release-linux-amd64 release-linux-arm64 ## Build for all platforms
	@echo "All release binaries built in $(BUILD_DIR)/"

release-linux-amd64: ## Build static binary for Linux x86_64 (via Docker)
	@mkdir -p $(BUILD_DIR)
	docker run --rm -v $(PWD):/src -w /src crystallang/crystal:latest-alpine \
		sh -c "shards install && crystal build src/main.cr -o $(BUILD_DIR)/$(BINARY_NAME)-linux-amd64 $(STATIC_FLAGS)"
	@echo "Built $(BUILD_DIR)/$(BINARY_NAME)-linux-amd64"

release-linux-arm64: ## Build static binary for Linux arm64 (via Docker)
	@mkdir -p $(BUILD_DIR)
	docker run --rm --platform linux/arm64 -v $(PWD):/src -w /src crystallang/crystal:latest-alpine \
		sh -c "shards install && crystal build src/main.cr -o $(BUILD_DIR)/$(BINARY_NAME)-linux-arm64 $(STATIC_FLAGS)"
	@echo "Built $(BUILD_DIR)/$(BINARY_NAME)-linux-arm64"

## —— Cleanup —————————————————————————————————————————

clean: ## Remove build artifacts
	rm -rf $(BIN_DIR) $(BUILD_DIR) lib .shards .crystal
	@echo "Clean."
