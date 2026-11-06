---
title: A read-only readiness scanner trusted its own inputs, and its tests could not fail
date: 2026-11-02
category: security-issues
module: plugins/soleur/skills/launch-check
tags: [launch-check, redaction, false-clean, test-vacuity, review-panel, bash]
---

# Learning: a read-only scanner trusted its own inputs, and its tests could not fail

## Problem

PR #11867 added `launch-check`, a read-only skill that scans a customer repo and writes one committed report. It passed seven suites (146 assertions), shellcheck and a self-test on this repo. A 12-seat review then found ~60 defects, ~20 of them P1, all in the guards rather than the feature:

- SEC-01 (secrets) could read "none found" after scanning nothing: `git archive … || true` swallowed extraction failures, `export-ignore` dropped files, the target's own `.gitleaks.toml` could allowlist everything, and the never-read prune removed `.sql`/`fixtures/` before gitleaks saw them.
- The never-read list was case-sensitive and narrower than SEC-02's own credential list (`id_rsa`, `.npmrc`, `*.p12`, `.aws/credentials` reached the model-review step).
- `render` trusted any non-empty facts file, any previous report (CRLF reset every acceptance; a partial judged file closed accepted items) and live env overrides (`LAUNCH_CHECK_GITLEAKS=true` bypassed the redaction gate).
- 15 "denied:" assertions ran `bash -c '! lc_safe_path "$1"'` in a child shell that lacked the function: exit 127, `!` turned it into a pass. They could not fail.
- The gate's EXIT trap referenced function-locals, so every success printed `scratch: parameter null or not set` and leaked `/tmp/lc-gate.*`.

## Solution

Treat every input as untrusted at the boundary where it enters: validate facts against the catalog and an evidence grammar, parse the previous report strictly (CRLF-tolerant, duplicates, unknown lines surfaced), close a finding only on positive evidence, honour env seams only under `LAUNCH_CHECK_TEST=1`, snapshot HEAD through a throwaway index and abort on any extraction failure. Call shell functions in-process in tests. 28 regression cases were added and each fix was mutated back out in a sandbox to confirm the matching test reddens.

## Key Insight

For a tool whose job is to say "nothing found", the dangerous bug is the path that reads clean without having looked. Ask of every verdict: what input makes this green while the check did not run? The panel's convergence was the signal: five seats independently reached the never-read list and the false-clean SEC-01, which is one structural gap (untrusted input, positive evidence not required), not twenty.

## Session Errors

1. **Tracking issue refused by the issue-filing gate (earlier in the session)** — Recovery: the draft PR is the tracker; learning already recorded — Prevention: none new.
2. **Stop hook fired on closing sentences that named a future action** — Recovery: ended with a `Paused:` line naming the in-flight wait — Prevention: close with the label form when waiting on a background agent.
3. **Local affected gate ran for hours and failed one suite under contention from sibling worktrees' own full runs** — Recovery: stopped my two runs with `kill_mine`, re-ran the failing suite alone (232/232), relied on CI per the operator — Prevention: do not start a full local gate while other worktrees run theirs; the bounded gate plus CI is the check.
4. **Safety hooks blocked two Bash calls (`rm -rf` through a variable in a mutation harness; `git commit` with an unresolvable `$D` path)** — Recovery: per-mutation directories, no deletion in the harness; a script file instead of an inline commit — Prevention: build mutation sandboxes as fresh subdirectories, never reuse-and-delete.
5. **My first mutation sandbox omitted a sibling skill the SUT reads (`incident/`), so the unmutated control was red and every row was void** — Recovery: copied the whole dependency skill, re-ran — Prevention: run the unmutated control in the sandbox first and require it green (already a review-skill rule; I violated it).
6. **Shell cwd drifted into `plugins/soleur/skills/launch-check/...` after a compound `cd`** — Recovery: absolute paths — Prevention: never `cd` inside a compound command; use absolute paths.
7. **My own tests had the vacuity class the review skill documents** (a child shell lacking the function; floors below the real count; a source-text grep for the write path) — Recovery: fixed in-process, floors set to exact counts — Prevention: run the pristine-control and "name a mutation that satisfies this" checks before the panel, not after.
