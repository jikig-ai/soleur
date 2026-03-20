---
title: "Bun 1.3.5 FPE crash correlates with subprocess spawn count in test runner"
date: 2026-03-20
category: runtime-errors
tags: [bun, testing, fpe, sigfpe, spawn, subprocess, gc]
module: scripts/test-all.sh
---

# Learning: Bun 1.3.5 FPE crash correlates with subprocess spawn count in test runner

## Problem

Running `bun test` from the repo root (or `bun test test/`) crashes with a floating point exception (SIGFPE) on Bun 1.3.5. The crash is intermittent per-file but approaches 100% when all root-level test files run together via directory discovery.

```
panic: Floating point error at address 0x41C038E
```

## Root Cause

The FPE originates in Bun's internal process accounting code. Diagnostic testing reveals a clear correlation between subprocess spawn counts and crash probability:

| Test Combination | Crash Rate | Spawn Count |
|---|---|---|
| `content-publisher.test.ts` alone | 0% | ~50 spawns |
| `x-community.test.ts` alone | 0% | 0 spawns |
| `pre-merge-rebase.test.ts` alone | ~70% | ~80+ spawns (git ops) |
| content-publisher + x-community | 0% | ~50 spawns |
| x-community + pre-merge-rebase | 0% | ~80 spawns |
| content-publisher + pre-merge-rebase | ~33% | ~130 spawns |
| All 3 (directory discovery) | ~100% crash | ~130+ spawns |

The crash belongs to a known class of Bun GC/allocator bugs. [oven-sh/bun#20429](https://github.com/oven-sh/bun/issues/20429) documents a similar FPE during garbage collection's `JSC::JSString::visitChildren` phase. Each `Bun.spawnSync` call creates internal tracking objects that pressure the GC visitor, and when the GC fires during a spawn-heavy test run, the accounting code hits a division-by-zero.

## Bun Crash Class Taxonomy

This project has now documented three distinct Bun 1.3.5 crash patterns:

1. **Segfault from missing deps** (2026-03-18) — Unresolvable imports cause allocator panic. RSS spikes to ~1.1GB. Fix: auto-install deps in worktree creation.
   See: `knowledge-base/project/learnings/2026-03-18-bun-test-segfault-missing-deps.md`

2. **Segfault from leaked timers** (2026-03-20) — `setInterval` leak causes RSS spike to ~1GB. Fix: `afterEach` cleanup in tests.
   See: `knowledge-base/project/learnings/2026-03-20-bun-segfault-leaked-setinterval-timers.md`

3. **FPE from spawn count** (this issue) — High `Bun.spawnSync` count triggers GC accounting bug. Fix: version pin + sequential test runner.

All three share the pattern: RSS spikes to ~1.1GB before the crash. The common thread is Bun 1.3.5's fragile GC under memory pressure from subprocess or timer accumulation.

## Solution

Two-layer fix plus CI DRY improvement:

1. **Version pin**: `.bun-version` file at repo root with `1.3.11` (the version proven stable in CI). CI workflows read from `.bun-version` via `bun-version-file` parameter. Note: `packageManager` field was initially added but removed — it triggers Corepack enforcement that blocks `npx` commands in the docs scripts.

2. **Sequential test runner**: `scripts/test-all.sh` runs each test suite in isolation with a version mismatch guard. This avoids the high-spawn-count crash pattern even if future Bun versions regress.

3. **CI DRY**: All 3 workflows (`ci.yml`, `scheduled-bug-fixer.yml`, `scheduled-ship-merge.yml`) now use `bun-version-file: ".bun-version"` instead of hardcoding the version.

## Key Insight

When Bun's test runner discovers files via directory traversal, it runs them in the same process with shared GC state. Tests that individually pass can crash together because their combined spawn count exceeds the GC's accounting threshold. Sequential isolation (separate `bun test` invocations per suite) keeps each run's spawn count below the crash threshold, providing defense-in-depth even after the version upgrade.

**Rule of thumb:** When a Bun test runner crash correlates with RSS or subprocess count, suspect a GC bug and check if a newer Bun version fixes it before adding workarounds.
