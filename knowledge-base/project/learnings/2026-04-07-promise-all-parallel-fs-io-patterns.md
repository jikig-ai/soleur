---
title: 'Promise.all parallel filesystem I/O patterns in Node.js'
date: 2026-04-07
category: performance
tags: [promise-all, parallel-io, filesystem, node-js, regex-concurrency, libuv-threadpool, kb-reader]
---

# Learning: Promise.all parallel filesystem I/O patterns in Node.js

## Problem

`kb-reader.ts` had three functions (`collectMdFiles`, `buildTree`, `searchKb`) that performed sequential `await` in loops over filesystem operations. Each iteration waited for the previous I/O to complete before starting the next, leaving the JavaScript event loop idle between calls.

## Solution

Converted sequential `await` loops to `Promise.all` in all three functions. Two distinct parallelism shapes emerged:

- **Tree-recursive parallelism** (`collectMdFiles`, `buildTree`) -- parallelize directory entries at each recursion level; concurrency is bounded by directory width per level.
- **Flat parallelism** (`searchKb`) -- `Promise.all` over all files at once; concurrency is bounded only by total file count.

## Key Insight: Per-callback RegExp is mandatory with `g` flag under concurrency

`RegExp` with the global (`g`) flag is stateful via `lastIndex`. In sequential code, `lastIndex` resets between loop iterations, so sharing one instance is safe. Under `Promise.all`, all callbacks execute in the same microtask batch -- a shared `g`-flag regex will have its `lastIndex` mutated by concurrent callbacks, producing wrong matches or infinite loops. Each concurrent callback MUST create its own `RegExp` instance.

## Secondary Insight: Promise.all vs Promise.allSettled selection

When individual error handling exists inside each promise callback (try/catch returning null on failure), `Promise.all` is correct. The inner catch prevents rejection propagation. `Promise.allSettled` would add unnecessary unwrapping of `{status, value}` objects with no behavioral benefit.

## Tertiary Insight: libuv threadpool serializes actual syscalls

Node.js defaults to 4 libuv threads. `Promise.all` with 200 concurrent `fs` calls does not mean 200 parallel disk reads -- it means 200 queued operations with 4 executing at a time. The performance win comes from eliminating idle JavaScript event loop time between sequential awaits, not from true parallel disk I/O. For extremely large knowledge bases, `searchKb`'s flat `Promise.all` will hit fd/memory limits before `collectMdFiles` or `buildTree` (which are bounded by directory width per level).

## Session Errors

1. **setup-ralph-loop.sh wrong path** -- Used `./plugins/soleur/skills/one-shot/scripts/setup-ralph-loop.sh` (incorrect); corrected to `./plugins/soleur/scripts/setup-ralph-loop.sh`. Prevention: the script lives at the plugin root `scripts/` level, not nested in skill directories. Verify paths by tracing each directory level before implementation.

2. **PreToolUse hook security false positive** -- `security_reminder_hook.py` warned about `child_process` usage on a file that does not use it. Prevention: known false positive; the hook scans broadly. Investigate the warning but do not block on confirmed false positives.

## Tags

category: performance
module: kb-reader
tags: promise-all, parallel-io, filesystem, node-js, regex-concurrency, libuv-threadpool
