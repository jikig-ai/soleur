---
title: "js/file-system-race fixes beyond open-once: /proc/self/fd re-opens for multi-consumer reads, held O_RDWR handle for FIFO check+unblock"
date: 2026-11-03
issue: 10925
pr: 12035
category: best-practices
module: apps/web-platform/test/bwrap-shim.test.ts, apps/web-platform/test/server/inngest/cron-community-monitor-collector-status.test.ts, plugins/soleur/scripts/install-opencode-adapter.ts
tags: [codeql, toctou, file-system-race, node-fs, proc-fd, fifo]
---

# Learning: two file-system-race shapes the open-once idiom does not directly cover

## Problem

The repo's standard `js/file-system-race` remediation (open each path once,
`fstat`/`read` on the descriptor — precedent `1b60715d80`, `7a3f264e0e`) fails
two real shapes:

1. **Two consumers must each read the same payload from offset 0.** Node has no
   `lseek`, so one descriptor cannot serve two `spawnSync` children — and a
   second `openSync(path)` is exactly the check→use pair the alert flags.
2. **A stat-check and a later open serve DIFFERENT purposes on a FIFO.**
   `statSync(fifo)` was a non-vacuity assertion; `open(fifo, "r+")` deep in a
   `Promise.race` failure path was the unblock for a parked reader. Merging them
   naively breaks the unblock.

## Solution

- **Multi-consumer:** create the path once (`openSync(path, "w+")` +
  `writeFileSync(fd)`), then mint each consumer's read descriptor via
  `openSync(`/proc/self/fd/${fd}`, "r")`. The procfs re-open yields a fresh
  file description at offset 0 **on the same inode** — no second path access,
  no window for a swap. Verified on Linux; gate to Linux-only suites
  (`skipIf(!BWRAP_OK)` already was).
- **FIFO:** `await open(fifo, "r+")` once and HOLD it across the race window.
  `fstat()` on the handle covers the non-vacuity `isFIFO()` check; the held
  O_RDWR writer end is itself what a parked reader's `open()` waits on, and
  closing it EOFs a reader parked in `read()` — the same unblock the second
  open provided, with the inode pinned the whole time. A defective reader that
  `open()`s gets past the call immediately (writer exists) and then blocks in
  `read()` — still caught by the same timeout arm.

## Prevention

Before writing a second path-based access of a file already opened once, ask
whether `/proc/self/fd/N` or a held descriptor covers the need — both keep the
"one path, one inode" invariant the CodeQL rule checks.

## Session Errors

One: a chained `export VAR && git add && git commit` call tripped the
precommit guard ("commit's own staging cannot be simulated safely") — stage
and commit as separate calls. Already hook-enforced; one-off.
