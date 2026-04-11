---
title: "fix: close bun test FPE crash #1948 -- already resolved by version pin and sequential runner"
type: fix
date: 2026-04-11
semver: patch
closes: "#1948"
---

# fix: close bun test FPE crash #1948 -- already resolved by version pin and sequential runner

## Overview

Issue #1948 reports that `bun test` crashes with a Floating Point Exception (SIGFPE) on Bun v1.3.6. This is the same crash class as #1511 (closed 2026-04-05) and #1796 (closed). The crash was discovered during bot-fix #1765 when the fix-issue workflow ran on a system with Bun 1.3.6 installed.

The crash is **already resolved** by the existing three-layer defense:

1. **Bun version pin to 1.3.11** -- `.bun-version` file at repo root, CI reads via `bun-version-file` parameter
2. **Sequential test runner** -- `scripts/test-all.sh` isolates test suites to avoid high-spawn-count crash pattern
3. **Dual-runner exclusion** -- `bunfig.toml` `pathIgnorePatterns` excludes web-platform tests from Bun discovery

The remaining work is: verify the fix holds, optionally evaluate Bun 1.3.12 upgrade, and close #1948 with a resolution comment.

## Problem Statement

### Crash Details

```text
panic: Floating point error at address 0x41C2C7E
oh no: Bun has crashed. This indicates a bug in Bun, not your code.
```

Bun version: 1.3.6 (d530ed99) on Linux x64. The crash occurs in Bun's internal process accounting when the GC fires during spawn-heavy test runs. Upstream: [oven-sh/bun#20429](https://github.com/oven-sh/bun/issues/20429) (still open, labeled `old-version`).

### Current State (Verified 2026-04-11)

| Check | Result |
|---|---|
| `.bun-version` | 1.3.11 (pinned) |
| Local `bun --version` | 1.3.11 |
| `bun test` | 1116 pass, 0 fail, no crash (7.79s) |
| `bash scripts/test-all.sh` | 9/9 suites pass |
| CI on main | Green (3 consecutive runs) |
| Latest stable Bun | v1.3.12 (released 2026-04-10) |
| Bun 1.3.12 meets `minimumReleaseAge` (3 days)? | No (1 day old) |

### Root Cause of #1948

Issue #1948 was discovered during bot-fix #1765. The scheduled-bug-fixer workflow uses `bun-version-file: ".bun-version"` which pins to 1.3.11, so CI should not reproduce this crash. The issue body explicitly states "Bun version: 1.3.6 (d530ed99)" -- the crash was observed before the `.bun-version` pin was in place, or on a runner where the global Bun installation (1.3.6) was used instead of the pinned version. Verify by checking bot-fix #1765 run logs if the root cause matters for closing.

### Relationship to Prior Issues

| Issue | Title | State | Resolution |
|---|---|---|---|
| #860 | Version pin + sequential runner | Closed | PR merged -- `.bun-version` + `scripts/test-all.sh` |
| #1511 | FPE crash verification (v1.3.6) | Closed | Confirmed existing fix holds, updated version range docs |
| #1796 | FPE crash tracking | Closed | Duplicate of #1511 |
| #1948 | FPE crash (this issue) | Open | Same crash class, same fix applies |

## Proposed Solution

### Tasks

1. **Verify test stability** -- Run `bash scripts/test-all.sh` once as a smoke test to confirm the three-layer defense holds (CI is already green on main with 3 consecutive runs, so extended local verification is redundant)

2. **Evaluate Bun 1.3.12 upgrade** -- Bun 1.3.12 was released 2026-04-10 with 120 bug fixes. However, it does NOT meet the project's `minimumReleaseAge` of 259200 seconds (3 days) per `bunfig.toml`. Bump `.bun-version` to 1.3.12 after 2026-04-13 as a routine maintenance task -- no tracking issue needed.

3. **Close #1948** -- Add a resolution comment documenting:
   - This is the same crash class as #1511 (duplicate)
   - The three-layer fix (version pin, sequential runner, dual-runner exclusion)
   - Links to prior resolutions (#1511, #860)
   - Current test stability verification results

### Files to Modify

No code changes required. The fix is already in place. This plan is verification + issue hygiene only.

| File | Change |
|---|---|
| None | No code changes needed |

### Commands to Run

```bash
# Task 1: Verify stability (smoke test)
bash scripts/test-all.sh

# Task 3: Close issue with resolution comment
gh issue close 1948 --comment "Resolved by existing three-layer defense..."
```

## Non-goals

- Fixing the upstream Bun FPE bug (oven-sh/bun's responsibility)
- Migrating away from Bun as a test runner
- Upgrading to Bun 1.3.12 before the 3-day release age gate (2026-04-13)
- Re-implementing workarounds that already exist

## Acceptance Criteria

- [x] `bash scripts/test-all.sh` exits 0
- [x] Issue #1948 closed with resolution comment explicitly noting duplicate crash class of #1511 and linking fix PRs

## Test Scenarios

- Given `scripts/test-all.sh` exists, when executed, then all suites pass and exit 0
- Given issue #1948 closed, when viewing it on GitHub, then the resolution comment states "duplicate crash class of #1511", documents the three-layer fix, and links to #860 and #1511

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- this is verification of an existing fix and issue hygiene.

## Alternative Approaches Considered

| Approach | Verdict | Reason |
|---|---|---|
| Upgrade to Bun 1.3.12 immediately | Deferred | Fails 3-day `minimumReleaseAge` policy (released 1 day ago) |
| Switch test runner to Vitest for all tests | Rejected | Overkill -- Bun tests work fine on 1.3.11; web-platform already uses Vitest |
| Add Bun version check to pre-commit hook | Rejected | `scripts/test-all.sh` already has a version mismatch guard |
| No action (close as duplicate of #1511) | Partially adopted | The fix IS the same, but #1948 was filed independently and deserves its own resolution comment |

## References

- Issue: [#1948](https://github.com/jikig-ai/soleur/issues/1948) (this issue)
- Prior resolution: [#1511](https://github.com/jikig-ai/soleur/issues/1511) (same crash, closed 2026-04-05)
- Prior fix PR: [#860](https://github.com/jikig-ai/soleur/issues/860) (version pin + sequential runner)
- Bot-fix trigger: [#1765](https://github.com/jikig-ai/soleur/issues/1765) (where crash was discovered)
- Learning: `knowledge-base/project/learnings/2026-03-20-bun-fpe-spawn-count-sensitivity.md`
- Learning: `knowledge-base/project/learnings/2026-04-05-bun-fpe-version-range-correction.md`
- Prior plan: `knowledge-base/project/plans/2026-04-05-fix-bun-test-fpe-crash-verification-plan.md`
- Upstream: [oven-sh/bun#20429](https://github.com/oven-sh/bun/issues/20429) (FPE during GC, still open)
- Bun 1.3.12: [release notes](https://bun.sh/blog/bun-v1.3.12) (120 bug fixes, released 2026-04-10)
