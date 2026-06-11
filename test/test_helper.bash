#!/usr/bin/env bash
# Shared fixtures for wf tests.

# Run through the real binary shim so tests exercise task resolution.
wf() {
  "$REPO_DIR/bin/wf" "$@"
}
export -f wf
