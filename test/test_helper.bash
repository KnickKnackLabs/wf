#!/usr/bin/env bash
# Shared fixtures for wf tests.

# Run through the real binary shim so tests exercise task resolution.
wf() {
  "$REPO_DIR/bin/wf" "$@"
}
export -f wf

wf_shell_quote() {
  printf '%q' "$1"
}

wait_for_file_contains() {
  local file="$1"
  local needle="$2"
  local attempts="${3:-20}"

  for _ in $(seq 1 "$attempts"); do
    if [ -f "$file" ] && grep -Fq "$needle" "$file"; then
      return 0
    fi
    sleep 0.1
  done

  return 1
}
