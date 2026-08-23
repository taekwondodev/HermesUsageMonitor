# HermesUsageMonitor build & tooling entry point.
#
# This Makefile is a THIN WRAPPER only: every target delegates to an existing
# script under ./scripts (the single source of truth for app build logic) or to
# a standard SwiftPM command. It must never duplicate build/app-assembly logic
# and must never introduce a parallel path to the scripts.
#
# The scripts resolve the project root themselves via $BASH_SOURCE, so they work
# from any cwd; SwiftPM commands need the package root as working directory.

ROOT := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

# Bare `make` (no target) must never trigger build/install implicitly.
.DEFAULT_GOAL := help

.PHONY: build verify check test clean help push-and-watch

# Build, assemble, sign, install and launch ~/Applications/HermesUsageMonitor.app.
build:
	"$(ROOT)scripts/build-app.sh"

# Verify an installed app bundle is complete and correctly signed, then launch it.
verify:
	"$(ROOT)scripts/verify-installed-app.sh"

# Check the Hermes update-to-app compatibility path without mutating Hermes state.
check:
	"$(ROOT)scripts/verify-hermes-compatibility.py"

# Run the SwiftUI package test suite (quick iteration).
test:
	cd "$(ROOT)" && swift test

# Clean SwiftPM build artifacts only — never touches ~/Applications/HermesUsageMonitor.app.
clean:
	cd "$(ROOT)" && swift package clean

# Push main and block until the GitGuardian CI run for that push finishes (exit status propagates).
push-and-watch:
	"$(ROOT)scripts/push-and-watch.sh"

# List available targets.
help:
	@echo "HermesUsageMonitor targets (thin wrapper over ./scripts + SwiftPM):"
	@echo "  build          assemble, sign, install and launch the app (build-app.sh)"
	@echo "  verify         check an installed app bundle, then launch it"
	@echo "  check          verify Hermes update-to-app compatibility"
	@echo "  test           run the SwiftPM test suite"
	@echo "  clean          remove SwiftPM build artifacts (.build only)"
	@echo "  push-and-watch push main and wait for the GitGuardian CI run"
	@echo "  help           this list"