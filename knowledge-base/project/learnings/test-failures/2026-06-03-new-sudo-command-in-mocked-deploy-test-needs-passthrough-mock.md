---
title: "A new `sudo <cmd>` in a mock-harnessed deploy script needs a pass-through command mock"
date: 2026-06-03
category: test-failures
module: apps/web-platform/infra/ci-deploy
tags: [shell-mock, ci-deploy, sudo, set-e, test-harness, mkdir]
related_pr: 4886
related_issues: [4882]
---

# A new `sudo <cmd>` in a mock-harnessed deploy script needs a pass-through command mock

## Problem

Adding `sudo mkdir -p /mnt/data/workspaces/.cron && sudo chown 1001:1001 …` to
`apps/web-platform/infra/ci-deploy.sh` (to create the isolated cron-clone subdir,
#4882) turned `ci-deploy.test.sh` from **79/79 → 46/79** — 33 failures spanning
*every* assertion that depends on a successful deploy run (`no DOCKER_RUN_ARGS
lines found`, `deploy succeeds expected exit 0 got 1`, etc.), not just the line
I changed.

The failure looked environmental ("no DOCKER_RUN_ARGS lines found" also hit the
untouched apparmor/tmpfs assertions), but running the **unmodified** origin/main
files in an isolated `/tmp` dir passed 79/79 — proving my change was the cause.

## Root cause

`ci-deploy.test.sh` runs the real script under a mocked PATH. Its mock `sudo`
**strips the `sudo` prefix and `exec`s the real command** (resolving absolute
paths via PATH so other mocks shadow them). The harness mocks `chown` (no-op)
but had **no `mkdir` mock** — the script never called `mkdir` via `sudo` before.
So `sudo mkdir -p /mnt/data/workspaces/.cron` ran the **real** `mkdir` against the
nonexistent host `/mnt/data`, which failed, and under `set -e` aborted the entire
deploy function → every downstream assertion failed.

A naive fix (blanket no-op `mkdir` mock) then broke the **legitimate** non-`sudo`
`mkdir` calls at `ci-deploy.sh:416` (`mkdir -p "$PLUGIN_MOUNT_DIR"`) and `:711`
(`mkdir -m 0700 -p "$INNGEST_EXTRACT_DIR"`) — the script writes into those dirs
immediately after, so no-op'ing them produced a different set of failures.

## Solution

A **pass-through** mock: no-op only for the unwritable host `/mnt/*` paths, run
the real coreutils `mkdir` for every other target (the writable temp dirs).

```bash
create_mock_mkdir() {
  cat > "$1/mkdir" << 'MOCK'
#!/bin/bash
for arg in "$@"; do
  case "$arg" in /mnt/*) exit 0 ;; esac   # host volume path — no-op
done
# Resolve real coreutils mkdir, skipping THIS mock dir; fail LOUD if none found.
self_dir=$(cd "$(dirname "$0")" && pwd)
for real in /usr/bin/mkdir /bin/mkdir; do [[ -x "$real" ]] && exec "$real" "$@"; done
IFS=':' read -ra _paths <<< "$PATH"
for dir in "${_paths[@]}"; do
  [[ -z "$dir" || "$dir" == "$self_dir" ]] && continue
  [[ -x "$dir/mkdir" ]] && exec "$dir/mkdir" "$@"
done
echo "mock mkdir: no real coreutils mkdir found (PATH=$PATH)" >&2
exit 1
MOCK
  chmod +x "$1/mkdir"
}
```

Register it in `create_base_mocks`. Result: 79/79.

## Key Insight

**When you add a new `sudo <command>` (or any command) to a deploy/provision
script that is exercised by a mock-PATH shell test, the harness needs a mock for
that command — and the mock must be a *pass-through* that only intervenes for the
specific host-side effect it cannot reproduce (here: `/mnt/*` volume paths),
delegating every other invocation to the real binary.** A blanket no-op silently
breaks any sibling call to the same command whose result the script depends on.
Cheapest detection: after adding a `sudo <cmd>` line, grep the test for
`create_mock_<cmd>` / `create_base_mocks`; if absent, add a pass-through mock.

Corollary: a mock that resolves the real binary should **fail loud** (`exit 1` +
stderr) when it can't find one, never `exit 0` — a silent success masks a missing
dir on a non-standard host (Nix/busybox) and turns a real failure green.

## Diagnosis tip

When a script change makes MANY unrelated assertions in a mock-harness test fail
at once (not just the one you touched), suspect a `set -e` abort from a single
new command, not an environmental flake. Confirm by running the **unmodified**
origin/main files in an isolated dir — same-harness, baseline-input — before
assuming the environment is broken.

## Session Errors

1. **`ci-deploy.sh` isolation edit broke the mocked deploy test (33 failures).**
   Recovery: added a pass-through `mkdir` mock to `ci-deploy.test.sh`.
   **Prevention:** when adding `sudo <cmd>` to a mock-harnessed deploy script,
   check `create_base_mocks` for a `<cmd>` mock; add a pass-through one if absent.
2. **First mkdir-mock attempt (blanket no-op) broke `PLUGIN_MOUNT_DIR` /
   `INNGEST_EXTRACT_DIR` creation.** Recovery: pass-through-except-`/mnt`.
   **Prevention:** mock a command by intervening ONLY for the host effect it
   can't reproduce; delegate all other invocations to the real binary.
3. **Plan cited a nonexistent guard test `cron-substrate-imports.test.ts`.**
   Harmless (the relative `./_cron-shared` import convention held anyway).
   **Prevention:** treat plan-cited test/guard names as hypotheses — `ls` the
   file before treating it as a gate to satisfy.
4. **Plan/tasks under-specified the Sentry tf-monitor + apply-target.** The
   `function-registry-count.test.ts` (c)/(f) guards require a `cron-monitors.tf`
   resource + `apply-sentry-infra.yml` `-target=` for any new
   `SENTRY_MONITOR_SLUG`; tasks.md listed neither. Caught at precondition-read.
   **Prevention:** a new in-process cron with its own monitor slug has **five**
   registration sites — route.ts, EXPECTED_CRON_FUNCTIONS, cron-monitors.tf,
   apply-sentry-infra.yml `-target=`, and the registry-count literal — enumerate
   all five before implementing.
