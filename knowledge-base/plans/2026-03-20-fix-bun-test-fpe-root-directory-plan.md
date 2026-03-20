---
title: "fix: bun test FPE crash when running root-level test directory"
type: fix
date: 2026-03-20
semver: patch
closes: "#860"
---

# fix: bun test FPE crash when running root-level test directory

## Overview

Running `bun test` from the repo root (or `bun test test/`) crashes with a floating point exception (SIGFPE) on Bun 1.3.5. The crash is intermittent but frequent -- `pre-merge-rebase.test.ts` alone crashes ~70% of runs due to heavy `Bun.spawnSync` usage (dozens of git subprocess invocations). When all 3 root-level test files run together, the crash rate approaches 100%.

CI is unaffected because it uses Bun 1.3.11 (pinned in `ci.yml`).

## Problem Statement

### Root Cause Analysis

The FPE originates at address `0x41C038E` in Bun's internal process accounting code. Diagnostic testing reveals:

| Test Combination | Crash Rate | Spawn Count |
|---|---|---|
| `content-publisher.test.ts` alone | 0% (3/3 pass) | ~50 spawns |
| `x-community.test.ts` alone | 0% (3/3 pass) | 0 spawns |
| `pre-merge-rebase.test.ts` alone | ~70% (1/5 pass) | ~80+ spawns (git ops) |
| content-publisher + x-community | 0% (3/3 pass) | ~50 spawns |
| x-community + pre-merge-rebase | 0% (3/3 pass) | ~80 spawns |
| content-publisher + pre-merge-rebase | ~33% (2/3 pass) | ~130 spawns |
| All 3 (directory discovery) | ~100% crash | ~130+ spawns |

The crash report shows `spawn(127)` in the features line, confirming the high subprocess count. The FPE is a division-by-zero or NaN in Bun's internal stats/accounting when aggregating spawn metrics across concurrent test workers.

### Why CI Passes

`ci.yml` pins Bun to `1.3.11` (via `oven-sh/setup-bun@v2.1.2`), which includes fixes for allocator and spawn-related crashes present in 1.3.5.

### Impact

- Local `bun test` from root is broken for developers on Bun 1.3.5
- The compound skill's pre-commit test gate runs `bun test`, making it fragile locally
- No production impact (CI unaffected)

## Proposed Solution

Two-layer fix:

### Layer 1: Pin local Bun version (primary fix)

Add a `.bun-version` file to the repo root containing `1.3.11`. Bun respects this file and version managers (like `bun upgrade`) will target it. This ensures local and CI Bun versions are synchronized.

### Layer 2: Sequential test runner script (defense-in-depth)

Create a `scripts/test-all.sh` script that runs test suites sequentially per directory instead of relying on Bun's recursive discovery. This works around the high-spawn-count crash pattern and provides better isolation:

```bash
#!/usr/bin/env bash
set -euo pipefail
bun test test/content-publisher.test.ts
bun test test/x-community.test.ts
bun test test/pre-merge-rebase.test.ts
bun test apps/web-platform/
bun test apps/telegram-bridge/
bun test plugins/soleur/
```

Update `package.json` to add a `"test"` script pointing to this runner.

### Layer 3: Update bunfig.toml test configuration

Add `preload` or `smol` configuration hints if available in Bun 1.3.11 to reduce per-worker memory pressure. At minimum, document the spawn-count sensitivity in a comment.

## Non-goals

- Fixing the Bun upstream FPE bug (that is oven-sh/bun's responsibility)
- Migrating away from Bun's test runner
- Restructuring test files to reduce spawn counts (the tests are correct)
- Upgrading to Bun latest/canary (1.3.11 is the proven-stable CI version)

## Acceptance Criteria

- [ ] `bun test` from repo root succeeds reliably (10/10 runs)
- [ ] `scripts/test-all.sh` runs all 14 test files across all directories and exits 0
- [ ] CI continues to pass (no regression from version pin or script changes)
- [ ] `.bun-version` file exists at repo root with `1.3.11`
- [ ] `package.json` has a `"test"` script entry
- [ ] Learning document captures the FPE pattern and version sensitivity

## Test Scenarios

- Given Bun 1.3.11 installed, when `bun test` runs from root, then all 14 test files pass without FPE
- Given Bun 1.3.11 installed, when `bun test test/` runs, then all 3 root test files pass
- Given `scripts/test-all.sh` exists, when executed, then all test directories run sequentially and exit 0
- Given a fresh clone, when `bun install && bun test` runs, then tests pass (no stale version mismatch)

## Files to Modify

| File | Change |
|---|---|
| `.bun-version` (new) | Pin Bun to `1.3.11` |
| `scripts/test-all.sh` (new) | Sequential test runner script |
| `package.json` | Add `"test": "bash scripts/test-all.sh"` script |
| `bunfig.toml` | Add comment documenting spawn-count sensitivity |
| `knowledge-base/learnings/2026-03-20-bun-fpe-spawn-count-sensitivity.md` (new) | Learning document |

## References

- GitHub issue: #860
- Prior learning: `knowledge-base/learnings/2026-03-18-bun-test-segfault-missing-deps.md` (related Bun crash class)
- Prior learning: `knowledge-base/learnings/2026-03-20-bun-segfault-leaked-setinterval-timers.md` (related timer leak crash)
- CI config: `.github/workflows/ci.yml` (Bun 1.3.11 pin)
- Bun crash report: [bun.report](https://bun.report/1.3.5/lt11e86cebCg0ggC+1vRiqjjkFqthjkF4upjkFsh/wjF8q1+jFm15+jFuns7vEm2+oB2/5tCA5A84hwjE)
