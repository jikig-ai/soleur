---
title: "perf: parallelize filesystem I/O in kb-reader tree and search"
type: feat
date: 2026-04-07
---

# perf: parallelize filesystem I/O in kb-reader tree and search

Ref #1728

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

**Sharp edge -- regex statefulness:** The current sequential code reuses a single `RegExp` instance because `lastIndex` is reset between iterations. After parallelization, each concurrent callback MUST create its own `RegExp` to avoid `lastIndex` contention.

## Alternative Approaches Considered

| Approach | Verdict | Reason |
|----------|---------|--------|
| `p-limit` concurrency limiter | Deferred | Adds a dependency; Node.js handles hundreds of concurrent `stat`/`readFile` calls fine for KB-sized workloads (~200 files). Revisit if users report fd exhaustion on very large KBs. |
| Short TTL in-memory cache for tree endpoint | Deferred | Good idea (issue #1728 mentions it), but orthogonal to I/O parallelization. Can be added independently. |
| `Promise.allSettled` instead of `Promise.all` | Not needed | Individual error handling via `.then(onFulfilled, onRejected)` and try/catch inside map callbacks already handles failures gracefully without rejecting the outer Promise. |
| Stream-based search with `readline` | Rejected | Adds complexity without significant benefit for files under 1MB (already capped by `MAX_FILE_SIZE`). |

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- internal performance optimization of existing infrastructure code.
