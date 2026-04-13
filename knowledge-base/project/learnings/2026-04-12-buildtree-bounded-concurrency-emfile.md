---
title: 'buildTree bounded concurrency to prevent EMFILE'
date: 2026-04-12
category: performance
tags: [concurrency, emfile, filesystem, kb-reader, promise-all, fd-exhaustion]
---

# Learning: buildTree bounded concurrency to prevent EMFILE

## Problem

`buildTree` in `server/kb-reader.ts` fired an unbounded number of parallel
`fs.promises.stat` calls via `Promise.all`. A knowledge base with 1,000+ files
in a single directory would issue 1,000+ concurrent stat syscalls, risking
EMFILE (file descriptor exhaustion) at default ulimit (1024). This was
identified in PR #2002 code review and tracked as issue #2011.

## Solution

Added a `mapWithConcurrency` helper (inline, no external dependency) that uses a
worker-pool pattern: spawn `min(concurrency, items.length)` async workers that
pull from a shared index. Each worker awaits one item at a time, so at most
`MAX_CONCURRENT_STAT` (50) stat calls are in-flight simultaneously.

The `filePromises` array was replaced with a `fileEntries` collection step
followed by a single `mapWithConcurrency` call, keeping the same functional
behavior (collect entries, stat them, build TreeNode objects) while bounding
parallelism.

## Key Insight

When you cannot add an external dependency (`p-limit`), the worker-pool pattern
is a clean zero-dependency alternative. The key is a shared mutable index
counter (`nextIndex++`) -- safe in single-threaded JavaScript because the
increment and capture happen synchronously before the next `await` yields.

## Related

- `knowledge-base/project/learnings/2026-04-07-promise-all-parallel-fs-io-patterns.md`
  documents the original parallelization that created this risk.

## Tags

category: performance
module: kb-reader
tags: concurrency, emfile, filesystem, fd-exhaustion, worker-pool
