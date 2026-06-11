#!/usr/bin/env bash
# Shared helpers for wf task scripts.

wf_die() {
  printf 'wf: %s\n' "$*" >&2
  exit 1
}

wf_require_command() {
  local command_name="$1"
  command -v "$command_name" >/dev/null 2>&1 || wf_die "required command not found: $command_name"
}

wf_now_utc() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

wf_json_escape() {
  local value="$1"
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//$'\t'/\\t}
  value=${value//$'\r'/\\r}
  value=${value//$'\n'/\\n}
  printf '%s' "$value"
}

wf_parse_duration() {
  local raw="$*"
  raw="${raw#every }"
  raw="${raw#Every }"
  raw="${raw#EVERY }"

  # Trim leading/trailing whitespace.
  raw="${raw#"${raw%%[![:space:]]*}"}"
  raw="${raw%"${raw##*[![:space:]]}"}"

  [ -n "$raw" ] || raw="1s"

  local number unit
  if [[ "$raw" =~ ^([0-9]+([.][0-9]+)?)[[:space:]]*([a-zA-Z]+)?$ ]]; then
    number="${BASH_REMATCH[1]}"
    unit="${BASH_REMATCH[3]:-s}"
  else
    wf_die "invalid duration: $raw"
  fi

  case "$unit" in
    ms|millisecond|milliseconds)
      awk -v n="$number" 'BEGIN { printf "%.3f", n / 1000 }'
      ;;
    s|sec|secs|second|seconds)
      printf '%s' "$number"
      ;;
    m|min|mins|minute|minutes)
      awk -v n="$number" 'BEGIN { printf "%.3f", n * 60 }'
      ;;
    h|hr|hrs|hour|hours)
      awk -v n="$number" 'BEGIN { printf "%.3f", n * 3600 }'
      ;;
    *)
      wf_die "unsupported duration unit: $unit"
      ;;
  esac
}

wf_caller_path() {
  local path="$1"

  case "$path" in
    /*)
      printf '%s' "$path"
      ;;
    *)
      printf '%s/%s' "${WF_CALLER_PWD:-$PWD}" "$path"
      ;;
  esac
}

wf_run_line_command() {
  local command_string="$1"
  local record="$2"

  WF_RECORD="$record" bash -lc "$command_string" <<< "$record"
}

wf_test_line_command() {
  local command_string="$1"
  local record="$2"

  WF_RECORD="$record" bash -lc "$command_string" >/dev/null <<< "$record"
}

wf_jq_predicate() {
  local filter="$1"
  local json="$2"
  local status

  if ! jq -c . >/dev/null <<< "$json"; then
    wf_die "invalid JSON record"
  fi

  if jq -e "$filter" >/dev/null <<< "$json"; then
    return 0
  else
    status="$?"
  fi
  case "$status" in
    1|4)
      return 1
      ;;
    *)
      wf_die "jq predicate failed with status $status: $filter"
      ;;
  esac
}

wf_state_home() {
  if [ -n "${WF_STATE_HOME:-}" ]; then
    printf '%s' "$WF_STATE_HOME"
  else
    printf '%s/wf' "${XDG_STATE_HOME:-$HOME/.local/state}"
  fi
}

wf_run_home() {
  printf '%s/runs' "$(wf_state_home)"
}

wf_validate_run_name() {
  local name="$1"
  [[ "$name" =~ ^[A-Za-z0-9_.-]+$ ]] || wf_die "invalid run name '$name'; use letters, numbers, dot, dash, or underscore"
}

wf_is_pid_running() {
  local pid="$1"
  [ -n "$pid" ] || return 1
  kill -0 "$pid" >/dev/null 2>&1
}

wf_descendant_pids() {
  local root="$1"

  ps -eo pid=,ppid= | awk -v root="$root" '
    { pid[NR] = $1; ppid[NR] = $2 }
    END {
      found[root] = 1
      changed = 1
      while (changed) {
        changed = 0
        for (i = 1; i <= NR; i++) {
          if (found[ppid[i]] && !found[pid[i]]) {
            found[pid[i]] = 1
            order[++n] = pid[i]
            changed = 1
          }
        }
      }
      for (i = n; i >= 1; i--) print order[i]
    }
  '
}

wf_kill_process_tree() {
  local root="$1"
  local signal="${2:-TERM}"
  local child

  while IFS= read -r child; do
    [ -n "$child" ] || continue
    if ! kill "-$signal" "$child" >/dev/null 2>&1; then
      continue
    fi
  done < <(wf_descendant_pids "$root")

  if ! kill "-$signal" "$root" >/dev/null 2>&1; then
    return 0
  fi
}
