---
title: "perf: parallelize filesystem I/O in kb-reader tree and search"
type: feat
date: 2026-04-07
---

# perf: parallelize filesystem I/O in kb-reader tree and search

Ref #1728

## Enhancement Summary

**Deepened on:** 2026-04-07
**Sections enhanced:** 4 (Context, Implementation, Test Scenarios, Alternative Approaches)
**Research sources:** Node.js fs docs, graceful-fs patterns, symlink security learning, kb-viewer learning, performance-oracle agent analysis

### Key Improvements

1. Added fd limit analysis confirming `Promise.all` is safe without concurrency limiting (system limit 524,288 vs ~200 files)
2. Added `readdir({ recursive: true })` consideration and why it does not apply here
3. Strengthened regex statefulness warning with concrete race condition scenario
4. Added symlink security invariant from institutional learning (2026-04-07-symlink-escape-recursive-directory-traversal)
5. Added edge case for `readdir` races with concurrent directory mutation

## Context

The `buildTree()`, `collectMdFiles()`, and `searchKb()` functions in `apps/web-platform/server/kb-reader.ts` use sequential `await` inside `for...of` loops for filesystem operations. Each directory read and file stat is awaited one at a time. For a knowledge base with 200 files across 30 directories, this means ~230 sequential syscalls per tree load and ~230+ per search query.

The tree endpoint (`/api/kb/tree`) has no caching and is called on every page load. Search (`/api/kb/search`) is called on every debounced keystroke. Both scale linearly with file count.

### Current sequential pattern

In `buildTree`, each recursive call and each `stat` call blocks the loop:

```typescript
for (const entry of entries) {
  if (entry.isDirectory()) {
    const child = await buildTree(fullPath, effectiveTopRoot); // blocks
  } else if (entry.isFile()) {
    const stat = await fs.promises.stat(fullPath); // blocks
  }
}
```

In `collectMdFiles`, each recursive directory call blocks:

```typescript
for (const entry of entries) {
  if (entry.isDirectory()) {
    const nested = await collectMdFiles(fullPath, relativeTo); // blocks
  }
}
```

In `searchKb`, each file stat+read blocks:

```typescript
for (const relativePath of mdFiles) {
  const stat = await fs.promises.stat(fullPath); // blocks
  raw = await fs.promises.readFile(fullPath, "utf-8"); // blocks
}
```

### Research Insights

**File descriptor safety:** The system fd limit is 524,288 (`ulimit -n`). A 200-file KB produces ~230 concurrent operations at peak -- well within safe bounds. No concurrency limiter (`p-limit`, `graceful-fs`) is needed at this scale. If the KB grows to 10,000+ files, the `EMFILE` risk would warrant adding `graceful-fs` as a drop-in replacement for `fs` (it queues operations on EMFILE and retries when fds free up).

**Why not `readdir({ recursive: true })`:** Node.js 18.17+ supports `fs.promises.readdir(dir, { recursive: true })`, but it returns flat paths without `Dirent` type information needed to distinguish files from directories and check `isSymbolicLink()`. The manual recursive approach with `{ withFileTypes: true }` remains necessary for this use case.

**Concurrency is not parallelism:** These `Promise.all` calls achieve concurrency (overlapping I/O waits), not true CPU parallelism. The OS disk scheduler and filesystem cache handle the actual I/O ordering. The performance gain comes from eliminating idle event loop time between sequential syscalls, not from parallel disk reads.

## Acceptance Criteria

- [ ] Parallelize directory reads in `collectMdFiles` using `Promise.all` over directory entries
- [ ] Parallelize recursive calls and `stat` calls in `buildTree` using `Promise.all` over directory entries
- [ ] Parallelize file stat+read operations in `searchKb` using `Promise.all`
- [ ] All 17 existing tests in `apps/web-platform/test/kb-reader.test.ts` pass unchanged
- [ ] All 4 existing tests in `apps/web-platform/test/kb-security.test.ts` pass unchanged
- [ ] No behavioral change: same output, same error handling, same sort order

## Test Scenarios

- Given an empty knowledge base directory, when `buildTree` is called, then it returns an empty tree (existing test)
- Given a nested directory structure with .md files, when `buildTree` is called, then directories sort first alphabetically then files alphabetically (existing test)
- Given 101 files each containing the search term, when `searchKb` is called, then results are capped at 100 with total=101 (existing test)
- Given a file that fails `stat`, when `buildTree` processes it, then the file is included without `modifiedAt` (existing behavior preserved)
- Given a file that fails `stat` or `readFile` during search, when `searchKb` processes it, then the file is silently skipped (existing behavior preserved)

### Research Insights -- Test Considerations

**Existing test coverage is sufficient.** The 17 `kb-reader.test.ts` tests cover all public API behaviors (empty tree, nested structure, sort order, modifiedAt, error handling, search caps, regex escaping, frontmatter parsing). Since the parallelization is a pure refactor (same inputs, same outputs, same error behavior), no new test cases are needed. The existing tests serve as a regression guard.

**Deterministic sort order.** The sort happens after `Promise.all` resolves, so result ordering is deterministic regardless of which promises resolve first. The existing sort-order test (`sorts directories first, then files, alphabetically`) validates this.

**Symlink exclusion.** The existing `!entry.isSymbolicLink()` checks in both `buildTree` and `collectMdFiles` (added per learning 2026-04-07-symlink-escape-recursive-directory-traversal) must be preserved in the parallelized code. The `kb-security.test.ts` tests verify these checks remain in place.

## Implementation

### File: `apps/web-platform/server/kb-reader.ts`

**1. `collectMdFiles` -- parallelize recursive directory calls**

Split entries into directories and files. For directories, use `Promise.all` to recurse in parallel. Files are collected synchronously (no I/O needed beyond the already-completed `readdir`).

- Collect file paths from entries immediately (no I/O)
- Collect directory promises into an array
- Await all directory promises with `Promise.all`
- Concatenate results

**2. `buildTree` -- parallelize recursive calls and stat calls**

Process all entries in parallel using `Promise.all`. Each entry maps to a promise that either recursively builds a subtree (directory) or stats the file (file).

- Separate directory and file processing into two promise arrays
- Directory promises: recursive `buildTree` call, then filter empty dirs (return `null` for empty)
- File promises: `stat` call with catch handler that omits `modifiedAt` on failure
- `Promise.all` both arrays concurrently
- Filter `null` directories, sort both arrays, merge

**3. `searchKb` -- parallelize file stat+read**

After collecting all `.md` file paths via `collectMdFiles`, process them in parallel.

- Map each file path to a promise that stats, reads, and regex-matches
- Each callback creates its own `RegExp` instance (critical: `RegExp` with `g` flag is stateful via `lastIndex` -- sharing across concurrent callbacks would cause race conditions)
- Return `null` for files that fail or have no matches
- Filter nulls, sort by match count

**Sharp edge -- regex statefulness:** The current sequential code reuses a single `RegExp` instance because `lastIndex` is reset between iterations. After parallelization, each concurrent callback MUST create its own `RegExp` to avoid `lastIndex` contention. Concrete scenario: if two callbacks share a regex, callback A sets `lastIndex=15` after finding a match, then callback B's `exec()` starts searching at position 15 instead of 0, missing earlier matches.

**Sharp edge -- symlink security invariant:** The `!entry.isSymbolicLink()` guard on both `isDirectory()` and `isFile()` branches is a security requirement (see learning: 2026-04-07-symlink-escape-recursive-directory-traversal). When refactoring the loop body into `Promise.all` map callbacks, preserve these checks in every callback. A symlink to `/etc/` would otherwise be traversed and its files exposed through the tree and search endpoints.

**Sharp edge -- readdir race with concurrent mutation:** If a file is deleted between `readdir` returning its entry and the `stat`/`readFile` call, the operation throws `ENOENT`. The existing try/catch handlers already cover this (omit `modifiedAt` in `buildTree`, skip file in `searchKb`). The parallelized code preserves these handlers inside each promise callback.

## Alternative Approaches Considered

| Approach | Verdict | Reason |
|----------|---------|--------|
| `p-limit` concurrency limiter | Deferred | Adds a dependency; Node.js handles hundreds of concurrent `stat`/`readFile` calls fine for KB-sized workloads (~200 files). Revisit if users report fd exhaustion on very large KBs. |
| Short TTL in-memory cache for tree endpoint | Deferred | Good idea (issue #1728 mentions it), but orthogonal to I/O parallelization. Can be added independently. |
| `Promise.allSettled` instead of `Promise.all` | Not needed | Individual error handling via `.then(onFulfilled, onRejected)` and try/catch inside map callbacks already handles failures gracefully without rejecting the outer Promise. |
| Stream-based search with `readline` | Rejected | Adds complexity without significant benefit for files under 1MB (already capped by `MAX_FILE_SIZE`). |
| `readdir({ recursive: true })` | Not applicable | Available in Node.js 18.17+ but returns flat paths without `Dirent` type info needed for symlink checks and tree building. |
| `graceful-fs` drop-in replacement | Deferred | Queues fs operations on EMFILE and retries. Not needed at current scale (system fd limit 524,288 vs ~200 concurrent ops). Worth adding if KB grows to 10,000+ files. |

### Research Insights -- Alternative Approaches

**Why `Promise.all` over `Promise.allSettled`:** `Promise.allSettled` would be appropriate if we needed to collect partial results when some promises reject. However, in all three functions, individual errors are already caught inside the promise callbacks (try/catch or `.then(onFulfilled, onRejected)`). No callback ever throws an unhandled rejection, so `Promise.all` never short-circuits. Using `Promise.allSettled` would add unnecessary unwrapping of `{status, value}` objects.

**Batched `Promise.all` pattern:** For very large directories (1,000+ entries), a batched approach (`for (let i = 0; i < entries.length; i += BATCH_SIZE)`) could limit peak fd usage. Not needed here -- the KB is bounded by practical file counts -- but the pattern exists if needed.

**References:**

- [Node.js fs documentation](https://nodejs.org/api/fs.html)
- [graceful-fs -- EMFILE handling](https://github.com/isaacs/node-graceful-fs)
- [Institutional learning: symlink escape in recursive directory traversal](../learnings/2026-04-07-symlink-escape-recursive-directory-traversal.md)

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- internal performance optimization of existing infrastructure code.
