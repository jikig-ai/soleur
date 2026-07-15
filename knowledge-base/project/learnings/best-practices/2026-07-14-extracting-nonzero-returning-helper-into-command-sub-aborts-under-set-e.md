---
title: "Extracting a nonzero-returning helper into a `$(…)` assignment aborts the whole script under `set -euo`"
date: 2026-07-14
category: best-practices
module: apps/web-platform/infra/ci-deploy.sh
issue: 6400
tags: [bash, set-e, command-substitution, refactor, tdd, ci-deploy]
---

# Extracting a nonzero-returning helper into a `$(…)` assignment aborts the whole script under `set -euo`

## Problem

`ci-deploy.sh` runs under `set -euo pipefail`. #6400 factored §1A's inline
GHCR re-fetch/relogin into a reusable helper `refetch_ghcr_and_relogin` that
**returns non-zero on a recovery miss** (echoes a stage string; returns 0 iff
`recovered`). Both callers captured the stage via a bare command-substitution
assignment:

```bash
prelude_stage="$(refetch_ghcr_and_relogin)"     # §1A prelude site
local stage; stage="$(refetch_ghcr_and_relogin)" # pull-site gate
```

A plain assignment `x="$(cmd)"` takes the exit status of the command
substitution. When the helper returned non-zero, the **assignment itself**
exited non-zero, and `set -e` aborted the entire deploy — right at the §1A
prelude path, *before* execution ever reached the pull site the fix targets.

Symptom: the AC14 RED test (relogin fails → assert the retry pull is NOT
attempted) reported `ghcr_pulls=0` — zero GHCR pulls, because the deploy died
during the prelude, not because the retry was correctly skipped. The vacuous
"0 pulls" would have passed a naive `!= 2` assertion; the exact-count
assertion (`== 1`) is what surfaced the abort.

The original inline §1A body did NOT have this bug: its failing commands lived
inside `if … then … else` conditionals, which are `set -e`-exempt. The
extraction into a command-sub assignment silently removed that exemption.

## Solution

Append `|| true` to every command-substitution assignment that captures a
helper's **string output** while the helper's non-zero return is
**expected/meaningful** (parsed as data, not treated as fatal):

```bash
prelude_stage="$(refetch_ghcr_and_relogin)" || true
local stage; stage="$(refetch_ghcr_and_relogin)" || true
```

The rc is discarded; the stage STRING is what the caller branches on. This is
correct here because a recovery miss is fail-open by contract (the terminal
`image_pull_failed` state is reached through a later `return 1`, not by
aborting mid-deploy).

## Key Insight

Under `set -euo pipefail`, four call shapes have DIFFERENT abort behavior for
a command that legitimately returns non-zero:

| Shape | Aborts on nonzero? |
|---|---|
| `cmd` as `if cmd; then …` condition | No (exempt) |
| `cmd && return 0` (cmd is left operand) | No (exempt) |
| `x="$(cmd)"` (bare assignment) | **YES** |
| `local x="$(cmd)"` (combined) | No — `local` masks the rc (a *different* footgun: it hides real failures) |

When you extract a function that returns non-zero as a signal (a stage code, a
"not found", a count) and call it in a `$(…)` **assignment**, you MUST guard
with `|| true` (or split `local x;  x="$(cmd)" || true`). Neither `bash -n`
nor a happy-path test catches it — only a test that drives the helper's
non-zero branch through the assignment does. TDD RED with an **exact-count**
assertion (not a `!=` threshold) is what forced the bug into the open.

## Session Errors

- **`set -e` command-sub landmine (this learning).** Recovery: `|| true` at
  both sites. Prevention: when a plan extracts an inline conditional body into
  a helper that returns non-zero as a signal, guard every `$(…)` assignment of
  its output with `|| true`; add a RED test that drives the non-zero branch and
  asserts an exact count/observable, not a threshold.
- **Test `grep -c … || echo 0` double-print.** `grep -c` prints `0` AND exits 1
  on a zero-match file, so `|| echo 0` appended a second `0` → `"0\n0"`
  arithmetic error. Recovery/Prevention: use `$(grep -c … || true)` — grep's
  `0` is already on stdout before the `||` fires; never `|| echo 0`.
- **Credential-hygiene grep too broad (AC6).** A negative `grep -qE 'docker
  login[^|]*\$(dt|du)'` flagged the `$du` *username* on argv as a secret.
  Prevention: forbid only the token var (`$dt`) on argv; the username is not a
  secret and legitimately appears as `-u "$du"`.
- **Concurrent review-agent worktree contamination (known sharp edge).** An
  agent running the test suite saw a transient 136/137 canary flake while a
  sibling agent copied/ran files in the shared worktree; another stalled.
  Recovery: `git diff HEAD` confirmed committed files intact + an isolated
  re-run was 137/137. Prevention: already documented — synthesize review
  against committed HEAD, re-run any suspicious suite in isolation.
