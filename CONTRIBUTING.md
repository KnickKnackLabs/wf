# Contributing

`wf` is a mise-task codebase for shell-native workflow primitives.

## Shape

```text
wf/
├── bin/wf                 # binary shim: wf cond if -> .mise/tasks/cond/if
├── .mise/tasks/           # task scripts; every executable file is a node
├── lib/wf.bash            # shared helpers for task scripts
├── test/                  # BATS tests through bin/wf
├── README.tsx             # generated README source
└── README.md              # generated output
```

## Local setup

```bash
mise trust
mise install
mise run test
mise run doctor
```

## Design principles

1. Core tasks should assume streams, not JSON.
2. Line records are the v0 framing contract unless a task documents otherwise.
3. Format-specific conveniences belong under namespaces like `wf text` and `wf json`.
4. Task stdout is pipeline data; task stderr is logs and diagnostics.
5. Inside tasks, use `$MISE_CONFIG_ROOT` for repo-relative paths.
6. When resolving caller-relative paths, use `$WF_CALLER_PWD`.

## Adding a primitive

1. Add an executable Bash script under `.mise/tasks/`.
2. Include a `#MISE description="..."` line so README/help discovery works.
3. Source `lib/wf.bash` only when shared helpers are needed.
4. Add a BATS test that calls `bin/wf`, not the task path directly.
5. Regenerate the README with `readme build`.

## README workflow

```bash
readme build
readme build --check
```

## Validation before merge

```bash
mise run test
codebase lint "$PWD"
readme build --check
git diff --check
```
