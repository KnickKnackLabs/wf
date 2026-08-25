#!/usr/bin/env bats

load test_helper

@test "test task selects Rush and preserves complete arguments" {
  mock_dir="$BATS_TEST_TMPDIR/mock-bin"
  export BATS_LOG="$BATS_TEST_TMPDIR/bats.log"
  mkdir -p "$mock_dir"

  cat > "$mock_dir/bats" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'parallel=%s\n' "${BATS_PARALLEL_BINARY_NAME:-}" > "$BATS_LOG"
for argument in "$@"; do
  printf 'arg=%s\n' "$argument" >> "$BATS_LOG"
done
SH
  chmod +x "$mock_dir/bats"

  BATS_COMMAND="$mock_dir/bats" \
    run wf test --jobs 4 --filter lifecycle wf

  [ "$status" -eq 0 ]
  grep -Fx "parallel=rush" "$BATS_LOG"
  grep -Fx "arg=--print-output-on-failure" "$BATS_LOG"
  grep -Fx "arg=--jobs" "$BATS_LOG"
  grep -Fx "arg=4" "$BATS_LOG"
  grep -Fx "arg=--filter" "$BATS_LOG"
  grep -Fx "arg=lifecycle" "$BATS_LOG"
  grep -Fx "arg=$REPO_DIR/test/wf.bats" "$BATS_LOG"
  if [[ "$REPO_DIR" =~ [[:space:]] ]]; then
    grep -Fx "arg=--no-parallelize-across-files" "$BATS_LOG"
  else
    ! grep -Fx "arg=--no-parallelize-across-files" "$BATS_LOG"
  fi

  BATS_COMMAND="$mock_dir/bats" \
    run wf test --jobs 4 --filter "lifecycle output" wf

  [ "$status" -eq 0 ]
  grep -Fx "arg=lifecycle output" "$BATS_LOG"
  grep -Fx "arg=--no-parallelize-across-files" "$BATS_LOG"
}

@test "serial test path preserves a target containing whitespace" {
  probe_dir="$BATS_TEST_TMPDIR/serial probe"
  mkdir -p "$probe_dir"
  test_keyword='@test'
  {
    printf '%s\n' '#!/usr/bin/env bats'
    printf '%s\n' "$test_keyword \"serial probe passes\" {"
    printf '%s\n' '  true' '}'
  } > "$probe_dir/passing test.bats"

  BATS_PARALLEL_BINARY_NAME=missing \
    run wf test --jobs 1 "$probe_dir/passing test.bats"

  [ "$status" -eq 0 ]
  [[ "$output" == *"1..1"* ]]
}

@test "whitespace fallback retains within-file concurrency" {
  probe_dir="$BATS_TEST_TMPDIR/within file probe"
  export PROBE_DIR="$BATS_TEST_TMPDIR/within-file-barrier"
  mkdir -p "$probe_dir" "$PROBE_DIR"

  test_keyword='@test'
  {
    printf '%s\n' '#!/usr/bin/env bats'
    printf '%s\n' "$test_keyword \"first test observes second test\" {"
    cat <<'BATS'
  touch "$PROBE_DIR/one"
  for _ in {1..50}; do
    [ ! -e "$PROBE_DIR/two" ] || return 0
    sleep 0.05
  done
  false
}
BATS
    printf '%s\n' "$test_keyword \"second test observes first test\" {"
    cat <<'BATS'
  touch "$PROBE_DIR/two"
  for _ in {1..50}; do
    [ ! -e "$PROBE_DIR/one" ] || return 0
    sleep 0.05
  done
  false
}
BATS
  } > "$probe_dir/within-file.bats"

  run wf test --jobs 4 "$probe_dir/within-file.bats"

  [ "$status" -eq 0 ]
  [[ "$output" == *"BATS parallelism: 4 jobs via rush"* ]]
}

@test "normal paths retain across-file concurrency" {
  probe_dir="$BATS_TEST_TMPDIR/across-file-probe"
  export PROBE_DIR="$BATS_TEST_TMPDIR/across-file-barrier"
  if [[ "$REPO_DIR" =~ [[:space:]] || "$probe_dir" =~ [[:space:]] ]]; then
    skip "bounded whitespace fallback intentionally disables across-file scheduling"
  fi
  mkdir -p "$probe_dir" "$PROBE_DIR"

  test_keyword='@test'
  for side in one two; do
    other=one
    [ "$side" = one ] && other=two
    {
      printf '%s\n' '#!/usr/bin/env bats'
      printf '%s\n' "$test_keyword \"$side observes $other\" {"
      printf '  touch "$PROBE_DIR/%s"\n' "$side"
      printf '%s\n' '  for _ in {1..50}; do'
      printf '    [ ! -e "$PROBE_DIR/%s" ] || return 0\n' "$other"
      printf '%s\n' '    sleep 0.05' '  done' '  false' '}'
    } > "$probe_dir/$side.bats"
  done

  run wf test --jobs 4 "$probe_dir/one.bats" "$probe_dir/two.bats"

  [ "$status" -eq 0 ]
}
