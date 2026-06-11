#!/usr/bin/env bats

load test_helper

@test "binary shim resolves top-level tasks" {
  run wf tick --count 3 every 0s
  [ "$status" -eq 0 ]
  [ "$output" = $'1\n2\n3' ]
}

@test "text if routes records without assuming JSON" {
  run bash -c 'printf "%s\n" 1 2 3 4 | "$REPO_DIR/bin/wf" text if "^[02468]$" --then "sed s/^/even:/" --else "sed s/^/odd:/"'
  [ "$status" -eq 0 ]
  [ "$output" = $'odd:1\neven:2\nodd:3\neven:4' ]
}

@test "generic cond select uses predicate exit status" {
  run bash -c 'printf "%s\n" 1 2 3 4 | "$REPO_DIR/bin/wf" cond select "grep -q \"^[34]$\""'
  [ "$status" -eq 0 ]
  [ "$output" = $'3\n4' ]
}

@test "README.md is generated from README.tsx" {
  run bash -c 'cd "$REPO_DIR" && readme build --check'
  [ "$status" -eq 0 ]
}

@test "doctor reports optional pre-commit hook state" {
  run bash -c 'cd "$REPO_DIR" && mise run -q doctor'
  [ "$status" -eq 0 ]
  [[ "$output" == *"pre-commit"* ]]
}
