---
title: A plan-prescribed probe must be portable to every host it ships to
date: 2026-09-18
category: workflow-patterns
module: plan
tags: [plan, portability, macos, timeout, gitleaks, plan-review]
issue: 8231
---

# Learning: a plan-prescribed probe must be portable to every host it ships to

## Problem

The #8231 green-baseline plan fixed a class in which a GNU-only tool, missing on a developer host,
is read as a verdict: #8250's `/usr/bin/time` and #8266's `bc`. Its own first draft then
prescribed a runnability probe `timeout 10 gitleaks version` for `code-to-prd.sh` (distributed
to plugin users) and the commit secret-scan hook. Stock macOS has no GNU `timeout`, so on macOS
the probe exits 127 and a *working* gitleaks would read as unrunnable. The plugin skill would exit 2
for every macOS user, and every macOS commit would bypass the local secret scan. Four independent
plan reviewers caught it. The repo had already hit this in hooks
(`.claude/hooks/supabase-loopback-warn.sh`, `memory-backstop.sh`), and its guard pattern
(`command -v timeout && TO=(timeout N)`) sat unused.

## Solution

The probe uses `timeout`, falls back to `gtimeout`, and runs bare when neither exists. An
acceptance criterion runs the probe with `timeout` removed from a PATH built from symlinks, and
asserts that a working tool still scans.

## Key Insight

The defect class a plan is fixing is the class its own new mechanism is most likely to
reintroduce. The author is thinking about the *subject's* tool (gitleaks), not the *probe's*
tools (`timeout`). For any command a plan prescribes that will run on user or developer hosts,
list every external binary it invokes and check each against the non-GNU hosts it reaches:
`timeout`, `/usr/bin/time`, `bc`, `sed -i`, `date -d`, `readlink -f`, `stat -c`.

Two further findings from the same review:

- **A user's git config can blind a secret scanner.** `gitleaks git --pre-commit --staged`
  returns rc 0 with 0 findings on a staged AWS key under `color.ui=always` or
  `color.diff=always`. Any tool that runs `git` itself inherits the user's config. Pin
  `color.*=never` via `GIT_CONFIG_*` on that invocation.
- **`--src-prefix=a/ --dst-prefix=b/` is the only portable pin** for patch parsers that match
  on `b/`. `-c diff.mnemonicprefix=false` does not undo `diff.noprefix=true`, and
  `--default-prefix` needs git ≥ 2.41.

## Session Errors

1. **The plan draft prescribed an unguarded `timeout` probe.** Recovery: four plan reviewers
   flagged it; the probe now uses timeout→gtimeout→bare plus a no-`timeout` acceptance
   criterion. **Prevention:** plan skill Sharp Edge routed from this learning (portability of
   prescribed probe commands).
2. **The plan draft told /work to "add" flags `guardrails.sh` already carries.** Recovery:
   architecture review. **Prevention:** before prescribing a flag addition, quote the current
   invocation from the file.
3. **The plan draft edited `ship-runbook-ssh-gate.sh` on a line baselined in
   `scripts/lint-shell-capture-exit.baseline.txt`, which would have reddened the required `test`
   check.** Recovery: the file was dropped, and the plan now requires a baseline grep before
   each defensive edit. **Prevention:** that Sharp Edge in the plan.
4. **The plan draft's census regex missed 3 of its own 7 named files, and its `resolve()`
   partitioner had four defects.** Recovery: both cut when the simplification and correctness
   panels fired on the same scope. **Prevention:** existing plan-review guidance ("prefer delete
   over fix").
5. **Two reviewers asserted `brand-hex-commit-gate.sh` is not a patch parser, having read only
   its `--name-only` line; it parses `git diff -U0` ~150 lines later.** Recovery: one grep.
   **Prevention:** treat a reviewer's negative claim as a claim to re-derive (existing brainstorm
   guidance on subagent claims).
6. **A learnings-researcher summary inverted a learning's rule** ("tests should fail loud, not
   skip"). The source says "FAIL in CI, SKIP only locally". Recovery: grepped the cited file.
   **Prevention:** existing guidance to grep any quoted string before relying on it.
7. **The stop hook fired twice when turns ended while background agents were still running.**
   Recovery: explicit `<stop>BLOCKED: …</stop>` tags. **Prevention:** none needed. This is harness
   behaviour working as designed.

## Tags

category: workflow-patterns
module: plan
