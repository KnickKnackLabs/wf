<div align="center">

# wf

**Shell-native workflow primitives built from mise tasks.**

Route, branch, fan out, log, and supervise Unix pipelines without forcing a data format.

![shape: mise tasks + Bash](https://img.shields.io/badge/shape-mise%20tasks%20%2B%20Bash-4EAA25?style=flat&logo=gnubash&logoColor=white)
[![tests: 23](https://img.shields.io/badge/tests-23-brightgreen?style=flat)](test/)
[![tasks: 31](https://img.shields.io/badge/tasks-31-blue?style=flat)](.mise/tasks/)
![README: TSX](https://img.shields.io/badge/README-TSX-f472b6?style=flat)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue?style=flat)](LICENSE)

</div>

<br />

## What this is

`wf` is an experiment in n8n-like workflow composition using ordinary shell pieces. The public interface is a tiny binary shim, `bin/wf`, that maps commands like `wf cond if` to mise task scripts like `.mise/tasks/cond/if`.

The core does **not** require JSON, CSV, or any other data format. It treats stdin/stdout as streams, and the first practical record framing is line-oriented. Format-specific helpers live under namespaces such as `wf text` and `wf json`.

## Core model

- **Transport:** stdin/stdout/stderr, normal Unix pipes, and background processes.
- **Framing:** v0 primitives operate on line records unless a task says otherwise, including a final record without a trailing newline.
- **Encoding:** unrestricted by default; text and JSON helpers are optional layers.
- **Commands:** command arguments are explicit shell snippets run by Bash, so quote them like any other shell code.
- **State:** background runs live under `$WF_STATE_HOME` when set, otherwise `$XDG_STATE_HOME/wf` or `~/.local/state/wf`.
- **Tasks:** every node is a Bash script under `.mise/tasks`.

## Workflow graph patterns

Some nodes are **sources** and do not consume stdin. For example, `wf emit alpha beta gamma | wf tick` prints ticks forever by default; the emitted words are not part of the downstream flow. For large or short-lived combinations, piping into a source can block or trip SIGPIPE because nothing drains the pipe.

Fan-out sends one stream to multiple branches; fan-in merges multiple source commands into one stream. Concurrent fan-in has intentionally nondeterministic ordering, so tests should sort or otherwise normalize when order is not part of the contract.

```bash
wf fanin merge \
  'wf tick --count 3 every 0s | sed "s/^/tick:/"' \
  'wf emit alpha beta | sed "s/^/word:/"' \
  | wf fanout tee --pass \
      'wf log append all.log --sink' \
  | wf text select '^tick:'
```

For larger workflows, prefer a small Bash script with named command strings/functions over a single unreadable one-liner.

## Tooling dependencies

`mise install` installs the project tools, including `jq` for `wf json` helpers. Core text, condition, flow, fanout, logging, and run primitives stay Bash/Unix-stream oriented.

## Quick start

```bash
mise trust
mise install

./bin/wf help
./bin/wf help tick
./bin/wf tick --count 5 every 0s
```

## Examples

Route plain text numbers without assuming JSON:

```bash
wf tick --count 5 every 0s \
  | wf text if '^[02468]$' \
      --then 'sed "s/^/even: /"' \
      --else 'sed "s/^/odd: /"'
```

Use a generic predicate command when regex is not enough:

```bash
wf emit 1 2 3 4 \
  | wf cond select 'awk "{ exit !(\$1 > 2) }"'
```

Opt into JSONL only when structured predicates are useful:

```bash
wf tick --count 3 --format json every 0s \
  | wf json select '.n >= 2'
```

Start, inspect, log, and stop a named background workflow:

```bash
wf run start demo -- 'wf tick every 5s | wf log pretty'
wf run status demo
wf run logs -f demo
wf run stop demo
```

## Repository layout

| Path           | Purpose                                                     |
| -------------- | ----------------------------------------------------------- |
| `bin/wf`       | binary shim that resolves space-separated task names        |
| `.mise/tasks/` | workflow primitives; nested paths become nested wf commands |
| `lib/wf.bash`  | shared Bash helpers for task scripts                        |
| `test/`        | BATS tests that exercise the shim                           |
| `README.tsx`   | generated README source                                     |
| `mise.toml`    | tools, settings, and convention lint config                 |

## Tasks

| Command            | Description                                                              |
| ------------------ | ------------------------------------------------------------------------ |
| `wf alert print`   | Print alerts using an optional {} line template                          |
| `wf check disk`    | Check disk usage for a mount and emit text, kv, or JSON records          |
| `wf cond if`       | Route line records through then/else commands using a predicate command  |
| `wf cond reject`   | Drop line records whose predicate command exits successfully             |
| `wf cond select`   | Keep line records whose predicate command exits successfully             |
| `wf doctor`        | Check local development setup                                            |
| `wf emit`          | Emit arguments as line records, or pass stdin through                    |
| `wf fanin merge`   | Merge stdout from multiple source commands                               |
| `wf fanout tee`    | Broadcast line records to multiple branch commands                       |
| `wf flow delay`    | Sleep before forwarding each line record                                 |
| `wf flow drop`     | Drop the first N line records                                            |
| `wf flow take`     | Take the first N line records                                            |
| `wf flow throttle` | Forward line records at most once per duration                           |
| `wf json if`       | Route JSONL records through then/else commands using a jq predicate      |
| `wf json map`      | Transform JSONL records with jq -c                                       |
| `wf json reject`   | Drop JSONL records matching a jq predicate                               |
| `wf json select`   | Keep JSONL records matching a jq predicate                               |
| `wf log append`    | Append line records to a file and pass them through                      |
| `wf log pretty`    | Print line records with timestamps for humans                            |
| `wf retry`         | Retry a line-oriented command for each input record                      |
| `wf run logs`      | Print logs for a named background workflow                               |
| `wf run ps`        | List named background workflows                                          |
| `wf run start`     | Start a named workflow in the background                                 |
| `wf run status`    | Show status for a named background workflow                              |
| `wf run stop`      | Stop a named background workflow                                         |
| `wf tap`           | Run a side-effect command on a copy of stdin while passing stdin through |
| `wf test`          | Run BATS tests                                                           |
| `wf text if`       | Route text lines through then/else commands using a regex                |
| `wf text reject`   | Drop text lines matching a Bash regular expression                       |
| `wf text select`   | Keep text lines matching a Bash regular expression                       |
| `wf tick`          | Emit periodic tick records                                               |

## Development notes

1. Keep core primitives format-agnostic unless the namespace says otherwise.
2. Prefer line-oriented tasks first; add stronger framing only when a real workflow needs it.
3. Use `$MISE_CONFIG_ROOT` for repo-relative paths inside tasks.
4. Use `$WF_CALLER_PWD` when a task needs the directory where the user invoked `wf`; resolve user-facing relative file paths from there.
5. Write tests through `bin/wf`, not by invoking task scripts directly.

<details>
<summary><b>Current convention checks</b></summary>

`wf` currently asks [codebase](https://github.com/KnickKnackLabs/codebase) to run these lint rules:

```
mise-settings
bats-test-helper
bats-test-task
mcr-scope
or-true
shellcheck
gum-table
caller-pwd-contract
github-actions
```

</details>

## Validation

```bash
mise run test
codebase lint "$PWD"
readme build --check
git diff --check
```

The suite currently has **23 tests**, **31 executable tasks**, and CI runs on **ubuntu-latest + macos-latest**.

<div align="center">

---

<sub>
This README was generated from `README.tsx` with [KnickKnackLabs/readme](https://github.com/KnickKnackLabs/readme).<br />Streams first, structure when useful.
</sub></div>
