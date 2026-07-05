---
title: "Bounded fresh-boot retry in the off-host verify + fail-loud guards must neutralize the detection command's nonzero exit"
date: 2026-07-05
category: best-practices
module: apps/web-platform/infra
issues: ["#6051", "#6040"]
tags: [bash, set-e, pipefail, fail-loud, infra, ci, retry, off-host-verify, review]
---

# Learning: bounded fresh-boot degraded-retry + fail-loud guard exit-status neutralization

## Problem

Two coupled infra fixes (#6051 timing bug, #6040 dedup) to the ADR-068 off-host web-2
acceptance verify (`deploy-status-fanout-verify.sh`):

1. **#6051** — the verify aborted RED on the FIRST `ok_peer_fanout_degraded`, but a fresh
   `terraform apply -replace` boot of web-2 takes ~10 min to bind `:9000`, so the single
   fan-out always degraded → false RED even though web-2 booted fine.
2. **#6040** — the shared verify script (extracted by #6030) was never adopted by the
   pre-existing `warm_standby` job, which carried a ~94-line divergent inline copy.

## Solution

**Bounded fresh-boot degraded-retry (the durable fix):** on the FIRST degraded completion,
passively wait until `elapsed-since-verify-start ≥ FRESH_BOOT_WINDOW_S` (600s), then re-POST
the fan-out **exactly once** (`DEGRADED_RETRY_MAX=1`). Migrate `warm_standby` onto the same
script (`OP_CONTEXT` selects recovery wording; script emits `deployed_tag` to `$GITHUB_OUTPUT`).

Three correctness invariants that are easy to get wrong (all caught by plan-review / code-review):

- **P0 — mark the "already retried" set ONLY when the retry actually fires**, after the
  `elapsed ≥ window` check — never on first sight of a degraded completion. A real unbound
  host emits the SAME `start_ts` every poll; marking-on-first-sight makes the single retry
  unreachable and the fix silently survives (RED-on-timeout, not GREEN). Recompute `elapsed`
  every poll.
- **Reassign the outer `DEPLOY_TAG` across the retrigger** so a tag advancing during the
  ≥600s wait doesn't leave a healthy web-2 stuck on a permanent `TAG != DEPLOY_TAG` mismatch.
- **Never advance the staleness baseline** (`PRE_START_TS`) on re-trigger — a late-arriving
  `ok` from an earlier in-flight cycle must still be accepted.

## Key Insight

**A fail-loud bash guard must neutralize the exit status of its DETECTION command, or
`set -e`+`pipefail` aborts BEFORE the tailored `::error::` prints — a silent failure that is
invisible to happy-path tests and shellcheck.** Two instances the code-quality reviewer caught
(one pre-existing, carried through the extraction):

- **F1:** `ROSTER_COUNT=$(… | grep -cE '…')` — `grep -c` exits **1** when the count is 0, so a
  garbage roster aborted the assignment (silent `rc=1`, no message) before the single-peer
  guard. Fix: append `|| true` so `ROSTER_COUNT=0` reaches the fail-loud branch.
- **F2:** `_post_fanout`'s POST `curl` lacked the `|| echo "000"` guard that the sibling GET
  (`_get_status`) has, so a transport failure aborted before the non-202 recovery message.
  Fix: mirror the guard so the failure surfaces as a non-202 through the loud handler.

The general rule (companion to [[2026-04-29-canary-layer3-mount-and-pipefail-traps]] and
[[2026-03-03-set-euo-pipefail-upgrade-pitfalls]]): in a `set -euo pipefail` script, any command
whose **nonzero exit is a valid data outcome** (`grep -c`=0-count, `diff`/`comm` non-empty,
`curl` transport-fail) used inside a `VAR=$(…)` assignment or a pipeline that feeds a
subsequent guard MUST be `|| true` / `|| echo <sentinel>`-neutralized. Test the count=0 /
transport-fail path explicitly — the happy path and shellcheck both pass green over the bug.

## How to test (network-free)

Inject three seams the script honors only in test (unset → real curl/POST/clock):
`DEPLOY_STATUS_SOURCE_CMD` (a stateful fixture popper that clamps to the last body — modeling
a static host re-emitting the same deploy-status), `DEPLOY_POST_SINK` (records POSTs, one line
per POST → `POSTS==2` proves exactly one retry), `DEPLOY_POST_CODE_CMD` (scripted per-POST HTTP
codes for the non-202 terminal case). Prove non-vacuity by MUTATION: revert the retry branch to
terminal-exit-1 and confirm the retry-dependent assertions flip to FAIL (they did — 8 of them);
the `POSTS==2` assertion, not `rc==1`, is what catches the P0 mark-on-first-sight regression.

## Session Errors

1. **`ci-deploy.sh` Read failed 3× with the wrong path** (`infra/scripts/ci-deploy.sh` — the
   file is at `infra/ci-deploy.sh`; only the SHARED verify script lives in `scripts/`).
   Recovery: `git ls-files | grep`. **Prevention:** when a plan cites a bare `<file>:<line>`,
   resolve the full path via `git ls-files | grep <basename>` before Read — sibling files in a
   subsystem can live in different subdirs.
2. **Test-harness double-newline desync (AC3e false-fail on first run).** `run_verify` appended
   `echo >> seqf` after each already-newline-terminated fixture → blank lines interleaved →
   the retry's tag-reread landed on a blank line so `DEPLOY_TAG` never advanced. Recovery:
   drop the extra `echo`. **Prevention:** when composing a line-per-record fixture from files,
   check whether the source already ends in `\n` before adding a separator.
3. **`./node_modules/.bin/bun` not found** — bun is the global runtime (`~/.bun/bin/bun`), not
   a node_modules-pinned binary (unlike `vitest`/`tsc`). Recovery: use global `bun`.
   **Prevention:** the pinned-binary rule applies to test runners inside a package, not to the
   bun/node runtime itself.
4. **Overly-broad "no ssh" verification grep returned a false rc=1** — `grep -in 'ssh'` matched
   the documentation words "NO SSH"/"(no SSH)" in comments/echo, not an `ssh` command.
   **Prevention:** for "no real X usage" checks, anchor on the command shape (`ssh -`/`ssh <host>`),
   not the bare token that also appears in prose.
5. **[forwarded] observability-coverage-reviewer agent did not return during planning**
   (mitigated via cross-agent coverage + a self-audit of the Observability section). One-off.
6. **[forwarded] a `.done` sentinel wait-convention the planning subagent tried does not exist
   in this harness** (completions arrive as task-notifications). No impact. One-off.

All session errors were one-offs except the F1/F2 fail-loud class (recurring), which was
fixed inline in the review commit and is captured as the Key Insight above.
