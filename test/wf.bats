#!/usr/bin/env bats

load test_helper

setup() {
  WF_TEST_STATE_HOME="$BATS_TEST_TMPDIR/wf-state"
  export WF_TEST_STATE_HOME
}

teardown() {
  local run_dir name

  [ -d "${WF_TEST_STATE_HOME:-}/runs" ] || return 0

  for run_dir in "$WF_TEST_STATE_HOME"/runs/*; do
    [ -d "$run_dir" ] || continue
    name="$(basename "$run_dir")"
    if ! env WF_STATE_HOME="$WF_TEST_STATE_HOME" "$REPO_DIR/bin/wf" run stop "$name" >/dev/null 2>&1; then
      :
    fi
  done
}

@test "binary shim resolves top-level tasks" {
  run wf tick --count 3 every 0s
  [ "$status" -eq 0 ]
  [ "$output" = $'1\n2\n3' ]
}

@test "task-specific help is routed without executing the task" {
  run wf help tick
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: wf tick"* ]]
}

@test "tick count zero emits no records" {
  run wf tick --count 0 every 0s
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "line primitives keep a final record without trailing newline" {
  run bash -c 'printf "a\nb" | "$REPO_DIR/bin/wf" text select "^[ab]$"'
  [ "$status" -eq 0 ]
  [ "$output" = $'a\nb' ]

  run bash -c 'printf "1\n2" | "$REPO_DIR/bin/wf" cond select "grep -q 2"'
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]

  run bash -c 'printf "{\"n\":1}\n{\"n\":2}" | "$REPO_DIR/bin/wf" json select ".n == 2"'
  [ "$status" -eq 0 ]
  [ "$output" = '{"n":2}' ]
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

@test "json predicates fail on invalid JSON records" {
  run bash -c 'printf "{bad}\n" | "$REPO_DIR/bin/wf" json select "."'
  [ "$status" -ne 0 ]
}

@test "json pipeline filters and maps JSONL records" {
  run bash -c '"$REPO_DIR/bin/wf" tick --count 3 --format json every 0s | "$REPO_DIR/bin/wf" json select ".n >= 2" | "$REPO_DIR/bin/wf" json map "{seen: .n}"'
  [ "$status" -eq 0 ]
  [ "$output" = $'{"seen":2}\n{"seen":3}' ]
}

@test "retry succeeds after transient command failures" {
  script="$BATS_TEST_TMPDIR/retry-eventual.sh"
  counter="$BATS_TEST_TMPDIR/retry-count"
  cat > "$script" <<'BASH'
#!/usr/bin/env bash
counter="$1"
n=0
if [ -f "$counter" ]; then
  n="$(< "$counter")"
fi
n=$((n + 1))
printf '%s\n' "$n" > "$counter"
if [ "$n" -lt 3 ]; then
  exit 1
fi
sed 's/^/ok:/'
BASH
  chmod +x "$script"
  command_string="$(wf_shell_quote "$script") $(wf_shell_quote "$counter")"

  run bash -c 'printf "job\n" | "$REPO_DIR/bin/wf" retry --times 3 --sleep 0s -- "$1"' _ "$command_string"
  [ "$status" -eq 0 ]
  [ "$output" = "ok:job" ]
  [ "$(< "$counter")" = "3" ]
}

@test "retry reports permanent failures" {
  run bash -c 'printf "job\n" | "$REPO_DIR/bin/wf" retry --times 2 --sleep 0s -- false'
  [ "$status" -ne 0 ]
  [[ "$output" == *"failed after 2 attempts"* ]]
}

@test "log append resolves relative files from the caller directory" {
  caller="$BATS_TEST_TMPDIR/caller"
  mkdir -p "$caller"

  run bash -c 'cd "$1" && printf "x\n" | "$2/bin/wf" log append logs/out' _ "$caller" "$REPO_DIR"
  [ "$status" -eq 0 ]
  [ "$output" = "x" ]
  [ "$(< "$caller/logs/out")" = "x" ]
}

@test "fanout tee broadcasts to branches while passing the original stream" {
  caller="$BATS_TEST_TMPDIR/fanout caller"
  mkdir -p "$caller"

  run bash -c 'cd "$1" && printf "%s\n" a b c | "$2/bin/wf" fanout tee --pass "wf log append branch-a --sink" "wf text select b | wf log append branch-b --sink"' _ "$caller" "$REPO_DIR"
  [ "$status" -eq 0 ]
  [ "$output" = $'a\nb\nc' ]
  [ "$(< "$caller/branch-a")" = $'a\nb\nc' ]
  [ "$(< "$caller/branch-b")" = "b" ]
}

@test "fanin merge combines multiple source commands" {
  run bash -c '"$REPO_DIR/bin/wf" fanin merge "printf \"right\\n\"" "printf \"left\\n\"" | sort'
  [ "$status" -eq 0 ]
  [ "$output" = $'left\nright' ]
}

@test "fanin merge fails when a source command fails" {
  run bash -c '"$REPO_DIR/bin/wf" fanin merge "printf \"ok\\n\"" false'
  [ "$status" -ne 0 ]
  [[ "$output" == *"ok"* ]]
}

@test "executable tasks include mise usage examples" {
  run bash -c 'cd "$REPO_DIR" && find .mise/tasks -type f -perm -u+x | while IFS= read -r task; do grep -q "^#USAGE example " "$task" || { echo "$task"; exit 1; }; done'
  [ "$status" -eq 0 ]
}

@test "tap propagates side-effect command failures" {
  run bash -c 'printf "x\n" | "$REPO_DIR/bin/wf" tap false'
  [ "$status" -ne 0 ]
  [[ "$output" == *"x"* ]]
}

@test "branch command failures fail the workflow node" {
  run bash -c 'printf "x\n" | "$REPO_DIR/bin/wf" text if "x" --then false'
  [ "$status" -ne 0 ]

  run bash -c 'printf "x\n" | "$REPO_DIR/bin/wf" fanout tee "cat >/dev/null" false'
  [ "$status" -ne 0 ]
}

@test "run lifecycle exposes status logs ps and stop" {
  state="$WF_TEST_STATE_HOME"

  run env WF_STATE_HOME="$state" "$REPO_DIR/bin/wf" run start lifecycle -- 'printf "ready\n"; sleep 30'
  [ "$status" -eq 0 ]
  wait_for_file_contains "$state/runs/lifecycle/stdout.log" "ready"

  run env WF_STATE_HOME="$state" "$REPO_DIR/bin/wf" run status lifecycle
  [ "$status" -eq 0 ]
  [[ "$output" == *"lifecycle running"* ]]

  run env WF_STATE_HOME="$state" "$REPO_DIR/bin/wf" run logs --stdout lifecycle
  [ "$status" -eq 0 ]
  [ "$output" = "ready" ]

  run env WF_STATE_HOME="$state" "$REPO_DIR/bin/wf" run ps
  [ "$status" -eq 0 ]
  [[ "$output" == *$'lifecycle\trunning'* ]]

  run env WF_STATE_HOME="$state" "$REPO_DIR/bin/wf" run stop lifecycle
  [ "$status" -eq 0 ]
  [[ "$output" == *"lifecycle stopped"* || "$output" == *"lifecycle killed"* ]]

  run env WF_STATE_HOME="$state" "$REPO_DIR/bin/wf" run status lifecycle
  [ "$status" -ne 0 ]
  [[ "$output" == *"lifecycle stopped"* ]]
}

@test "run start preserves caller directory with spaces" {
  state="$WF_TEST_STATE_HOME"
  caller="$BATS_TEST_TMPDIR/caller with space"
  mkdir -p "$caller"

  run bash -c 'cd "$1" && env WF_STATE_HOME="$3" "$2/bin/wf" run start pwd-check -- pwd' _ "$caller" "$REPO_DIR" "$state"
  [ "$status" -eq 0 ]
  wait_for_file_contains "$state/runs/pwd-check/stdout.log" "$caller"
  [ "$(< "$state/runs/pwd-check/stdout.log")" = "$caller" ]
}

@test "error contracts report invalid user input" {
  run wf nope
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown task: nope"* ]]

  run wf tick --count 1 bananas
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid duration: bananas"* ]]

  run wf run start 'bad/name' -- true
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid run name"* ]]
}

@test "run stop terminates workflow process trees" {
  state="$WF_TEST_STATE_HOME"

  run env WF_STATE_HOME="$state" "$REPO_DIR/bin/wf" run start bats-stop -- 'sleep 30'
  [ "$status" -eq 0 ]

  pid="$(< "$state/runs/bats-stop/pid")"
  child=""
  for _ in 1 2 3 4 5; do
    child="$(pgrep -P "$pid" 2>/dev/null | head -n 1)"
    [ -n "$child" ] && break
    sleep 0.1
  done
  [ -n "$child" ]

  run env WF_STATE_HOME="$state" "$REPO_DIR/bin/wf" run stop bats-stop
  [ "$status" -eq 0 ]

  stopped=false
  for _ in 1 2 3 4 5; do
    if ! kill -0 "$pid" 2>/dev/null && ! kill -0 "$child" 2>/dev/null; then
      stopped=true
      break
    fi
    sleep 0.1
  done
  $stopped
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
