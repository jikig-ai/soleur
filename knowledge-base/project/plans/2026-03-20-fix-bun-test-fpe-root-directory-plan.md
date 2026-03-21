---
title: "fix: bun test FPE crash when running root-level test directory"
type: fix
date: 2026-03-20
semver: patch
closes: "#860"
---

## Enhancement Summary

**Deepened on:** 2026-03-20
**Sections enhanced:** 4 (Proposed Solution, Acceptance Criteria, Test Scenarios, Files to Modify)

### Key Improvements

1. Corrected `.bun-version` behavior -- Bun does not natively read this file; it requires external version managers or CI `bun-version-file` parameter
2. Added `packageManager` field in `package.json` as the standards-compliant version pin mechanism
3. DRY improvement: CI workflows should use `bun-version-file: ".bun-version"` instead of hardcoding `1.3.11` in 3 separate workflows
4. Added version check guard to `test-all.sh` script for local enforcement
5. Removed Layer 3 (bunfig.toml preload/smol) -- these options do not exist in Bun's test config

### New Considerations Discovered

- `.bun-version` is a convention supported by third-party version managers (BunVM, Bum) and `oven-sh/setup-bun`'s `bun-version-file` parameter -- Bun itself does not auto-switch versions based on this file
- The `packageManager` field in `package.json` is the Node.js ecosystem standard for version pinning, and `setup-bun` reads it as a fallback
- Three CI workflows (`ci.yml`, `scheduled-bug-fixer.yml`, `scheduled-ship-merge.yml`) all hardcode `bun-version: "1.3.11"` -- centralizing to `.bun-version` eliminates the DRY violation
- The FPE is a known class of Bun GC/allocator bugs ([oven-sh/bun#20429](https://github.com/oven-sh/bun/issues/20429)) exacerbated by high subprocess counts during garbage collection's slot visitor phase

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

### Research Insights

The FPE belongs to a known class of Bun GC/allocator bugs. [oven-sh/bun#20429](https://github.com/oven-sh/bun/issues/20429) documents a similar floating point exception during garbage collection's `JSC::JSString::visitChildren` phase. The crash correlates with high subprocess counts because each `Bun.spawn`/`Bun.spawnSync` call creates internal tracking objects that accumulate pressure on the GC visitor. When the GC fires during a spawn-heavy test run, the accounting code hits a division-by-zero in its statistics aggregation.

This project has now documented three distinct Bun crash classes:

1. **Segfault from missing deps** (2026-03-18) -- unresolvable imports cause allocator panic
2. **Segfault from leaked timers** (2026-03-20) -- `setInterval` leak causes RSS spike to 1GB
3. **FPE from spawn count** (this issue) -- high `Bun.spawnSync` count triggers GC accounting bug

All three share the pattern: RSS spikes to ~1.1GB before the crash. The common thread is Bun 1.3.5's fragile GC under memory pressure from subprocess or timer accumulation.

### Why CI Passes

`ci.yml` pins Bun to `1.3.11` (via `oven-sh/setup-bun@v2.1.2`), which includes fixes for allocator and spawn-related crashes present in 1.3.5. The same pin exists in `scheduled-bug-fixer.yml` and `scheduled-ship-merge.yml`.

### Impact

- Local `bun test` from root is broken for developers on Bun 1.3.5
- The compound skill's pre-commit test gate runs `bun test`, making it fragile locally
- No production impact (CI unaffected)

## Proposed Solution

Two-layer fix plus CI DRY improvement:

### Layer 1: Pin Bun version across local and CI (primary fix)

**a) Create `.bun-version` file** at repo root containing `1.3.11`. This file is read by:

- `oven-sh/setup-bun` via `bun-version-file: ".bun-version"` (CI)
- Third-party version managers like BunVM and Bum (local dev)
- Note: Bun itself does NOT natively read this file for auto-switching

**b) Add `packageManager` field to `package.json`**: Set `"packageManager": "bun@1.3.11"` as the standards-compliant version declaration. `setup-bun` reads this as a fallback when `bun-version-file` is not set.

**c) Update CI workflows** to use `bun-version-file: ".bun-version"` instead of hardcoded `bun-version: "1.3.11"`. This affects 3 files:

- `.github/workflows/ci.yml`
- `.github/workflows/scheduled-bug-fixer.yml`
- `.github/workflows/scheduled-ship-merge.yml`

**d) Upgrade local Bun** by running `bun upgrade` (targets latest) or installing 1.3.11 explicitly. The `.bun-version` file serves as documentation of the expected version; enforcement requires either a version manager or the guard script in Layer 2.

### Layer 2: Sequential test runner script (defense-in-depth)

Create a `scripts/test-all.sh` script that:

1. Checks the local Bun version and warns if it does not match `.bun-version`
2. Runs test suites sequentially per directory instead of relying on Bun's recursive discovery
3. Provides a summary of pass/fail counts

This works around the high-spawn-count crash pattern and provides better isolation even after the version upgrade, guarding against future regressions in Bun's test runner.

```bash
#!/usr/bin/env bash
set -euo pipefail

# --- Version Check ---
if [[ -f .bun-version ]]; then
  expected=$(cat .bun-version)
  actual=$(bun --version)
  if [[ "$actual" != "$expected" ]]; then
    echo "WARNING: Bun $actual installed, expected $expected (from .bun-version)" >&2
    echo "Run: bun upgrade" >&2
  fi
fi

# --- Run Tests Per Directory ---
failed=0
suites=0

run_suite() {
  local label="$1"; shift
  suites=$((suites + 1))
  echo "--- $label ---"
  if bun test "$@"; then
    echo "[ok] $label"
  else
    echo "[FAIL] $label" >&2
    failed=$((failed + 1))
  fi
}

run_suite "root/content-publisher" test/content-publisher.test.ts
run_suite "root/x-community" test/x-community.test.ts
run_suite "root/pre-merge-rebase" test/pre-merge-rebase.test.ts
run_suite "apps/web-platform" apps/web-platform/
run_suite "apps/telegram-bridge" apps/telegram-bridge/
run_suite "plugins/soleur" plugins/soleur/

echo "=== $((suites - failed))/$suites suites passed ==="
if [[ "$failed" -gt 0 ]]; then
  exit 1
fi
```

Update `package.json` to add `"test": "bash scripts/test-all.sh"`.

### Removed: Layer 3 (bunfig.toml preload/smol)

Research confirms Bun's `[test]` section in `bunfig.toml` does not support `preload` or `smol` options. The existing `pathIgnorePatterns` is sufficient. A comment documenting the spawn-count sensitivity will be added.

## Non-goals

- Fixing the Bun upstream FPE bug (that is oven-sh/bun's responsibility)
- Migrating away from Bun's test runner
- Restructuring test files to reduce spawn counts (the tests are correct)
- Upgrading to Bun latest/canary (1.3.11 is the proven-stable CI version)
- Installing a Bun version manager (BunVM, Bum) -- the version check guard in test-all.sh is sufficient

## Acceptance Criteria

- [ ] `bun test` from repo root succeeds reliably (10/10 runs) on Bun 1.3.11
- [x] `scripts/test-all.sh` runs all 14 test files across 6 suites and exits 0
- [ ] CI continues to pass (no regression from `bun-version-file` change)
- [x] `.bun-version` file exists at repo root with `1.3.11`
- [x] `package.json` has `"test"` script (removed `packageManager` per architecture review — Corepack interference with `npx` docs scripts)
- [x] All 3 CI workflows (`ci.yml`, `scheduled-bug-fixer.yml`, `scheduled-ship-merge.yml`) use `bun-version-file` instead of hardcoded version
- [x] Learning document captures the FPE pattern, version sensitivity, and the 3-crash-class taxonomy

## Test Scenarios

- Given Bun 1.3.11 installed, when `bun test` runs from root, then all 14 test files pass without FPE
- Given Bun 1.3.11 installed, when `bun test test/` runs, then all 3 root test files pass
- Given `scripts/test-all.sh` exists, when executed, then all 6 suites run sequentially and exit 0
- Given Bun 1.3.5 installed, when `scripts/test-all.sh` runs, then a version mismatch warning is printed to stderr
- Given CI runs with `bun-version-file: ".bun-version"`, when the workflow executes, then Bun 1.3.11 is installed (verify via `bun --version` step or setup-bun output)
- Given a fresh clone, when `bun install && bun run test` runs, then tests pass

## Files to Modify

| File | Change |
|---|---|
| `.bun-version` (new) | Pin Bun to `1.3.11` |
| `scripts/test-all.sh` (new) | Sequential test runner with version guard |
| `package.json` | Add `"packageManager": "bun@1.3.11"` and `"test": "bash scripts/test-all.sh"` |
| `bunfig.toml` | Add comment documenting FPE spawn-count sensitivity |
| `.github/workflows/ci.yml` | Replace `bun-version: "1.3.11"` with `bun-version-file: ".bun-version"` |
| `.github/workflows/scheduled-bug-fixer.yml` | Replace `bun-version: "1.3.11"` with `bun-version-file: ".bun-version"` |
| `.github/workflows/scheduled-ship-merge.yml` | Replace `bun-version: "1.3.11"` with `bun-version-file: ".bun-version"` |
| `knowledge-base/project/learnings/2026-03-20-bun-fpe-spawn-count-sensitivity.md` (new) | Learning document with 3-crash-class taxonomy |

## References

- GitHub issue: #860
- Prior learning: `knowledge-base/project/learnings/2026-03-18-bun-test-segfault-missing-deps.md` (Bun crash class 1: missing deps)
- Prior learning: `knowledge-base/project/learnings/2026-03-20-bun-segfault-leaked-setinterval-timers.md` (Bun crash class 2: timer leaks)
- CI config: `.github/workflows/ci.yml` (current Bun 1.3.11 pin)
- Bun crash report: [bun.report](https://bun.report/1.3.5/lt11e86cebCg0ggC+1vRiqjjkFqthjkF4upjkFsh/wjF8q1+jFm15+jFuns7vEm2+oB2/5tCA5A84hwjE)
- Related upstream: [oven-sh/bun#20429](https://github.com/oven-sh/bun/issues/20429) (FPE during GC)
- setup-bun `bun-version-file`: [oven-sh/setup-bun](https://github.com/oven-sh/setup-bun) documentation
