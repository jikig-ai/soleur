---
title: "Bun FPE crash version range extends to 1.3.6, not just <=1.3.5"
date: 2026-04-05
category: runtime-errors
tags: [bun, testing, fpe, verification, version-range]
issue: "#1511"
related:
  - 2026-03-20-bun-fpe-spawn-count-sensitivity.md
  - 2026-03-18-bun-test-segfault-missing-deps.md
  - 2026-03-20-bun-segfault-leaked-setinterval-timers.md
---

# Learning: Bun FPE crash version range extends to 1.3.6, not just <=1.3.5

## Context

Issue #1511 reported that `bun test` crashes with SIGFPE (Floating Point Error) in Bun v1.3.6. The original fix documentation (`2026-03-20-bun-fpe-spawn-count-sensitivity.md`) described the affected range as "Bun <=1.3.5". The crash report URL in #1511 proved that 1.3.6 is also affected, extending the known-bad range by one minor version.

## What Was Already Fixed

Investigation confirmed the crash was already resolved by three prior PRs forming a defense-in-depth stack:

1. **PR #860** -- Bun version pin to 1.3.11 via `.bun-version` file + sequential test runner (`scripts/test-all.sh`)
2. **PR #1517** -- Dual-runner exclusion: web-platform tests excluded from `bun test` (run by Vitest instead)
3. **PR #1518** -- Connect-repo god component split (reduced test complexity)

## What This Session Changed

1. **Version range correction**: Updated `bunfig.toml` comment from "Bun <=1.3.5" to "Bun <=1.3.6" to reflect the crash report evidence
2. **Learning file update**: Updated `2026-03-20-bun-fpe-spawn-count-sensitivity.md` title and references from "<=1.3.5" to "<=1.3.6"
3. **Stability verification**: Ran `bun test` 5 consecutive times (1199 tests each, 0 failures, no crashes) to confirm the existing three-layer fix holds

## Verification Methodology

The verification approach for confirming a crash is fixed:

1. Run the exact command that crashed (`bun test`) multiple times (5x minimum) to account for intermittent crashes
2. Confirm test count is consistent across runs (1199 tests each run = deterministic discovery)
3. Confirm zero failures and zero crashes across all runs
4. Document the PR chain that constitutes the fix, not just the most recent PR

## Key Insight

When a bug report arrives for a crash that existing defenses already prevent, the correct response is: (1) verify the defenses hold via repeated execution, (2) correct any stale version references in documentation/comments, (3) close with a resolution comment linking the specific PRs that form the fix. Do not re-implement fixes that already exist.

## Session Errors

### 1. Ralph Loop script not found

`./plugins/soleur/skills/one-shot/scripts/setup-ralph-loop.sh` does not exist. The script was referenced during session setup but the file is missing from the repository.

**Prevention:** Before invoking a script, verify it exists with `test -f <path>`. Session-start scripts should degrade gracefully (skip with a warning) when optional components are absent.

### 2. Stale version reference in own plan file

The planning subagent wrote "Bun <= 1.3.5" on line 33 of the new plan file, contradicting the plan's own conclusion that the range extends to 1.3.6. The error was caught during review and corrected.

**Prevention:** When a subagent produces a plan that corrects a factual claim (e.g., version range), grep the plan output for the old incorrect value before accepting it. Subagents can echo stale data from their initial context even when their analysis concludes otherwise.
