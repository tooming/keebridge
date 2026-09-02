.PHONY: help
help: ## Show this help
	@grep -hE '^[a-zA-Z0-9_-]+:.*##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*##"}; {printf "  \033[36m%-24s\033[0m %s\n", $$1, $$2}'

.PHONY: test
test: ## Run the KeeBridgeCore Swift package test suite (no signing needed)
	@cd KeeBridgeCore && swift test

.PHONY: build
build: ## Unsigned build of the app (embeds credential + card extensions) — CI-safe; signed builds need Xcode + the dev cert
	@xcodebuild -project KeeBridge.xcodeproj -scheme KeeBridge -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build

.PHONY: probe-build
probe-build: ## Unsigned build of VaultProbe (SPM executable, incl. its swift-argument-parser subcommands) — not otherwise gated
	@cd VaultProbe && swift build

.PHONY: routines-check
routines-check: ## Check routines/routines.yaml matches the last apply (catches edits not synced to the claude.ai trigger)
	@bash scripts/routines-check.sh

.PHONY: routines-mark-applied
routines-mark-applied: ## Refresh .routines-applied — run ONLY after applying routines.yaml via Claude Code RemoteTrigger
	@bash scripts/routines-mark-applied.sh

.PHONY: routines-author-check
routines-author-check: ## Fail if an executor-authored (auto/*) change edits routines.yaml — the executor can't apply it to the live trigger (drift detector)
	@bash scripts/routines-author-check.sh

.PHONY: ci
ci: ## Run every gate this repo has: test + unsigned build + VaultProbe build + routines drift checks
	@$(MAKE) test
	@$(MAKE) build
	@$(MAKE) probe-build
	@$(MAKE) routines-check
	@$(MAKE) routines-author-check
