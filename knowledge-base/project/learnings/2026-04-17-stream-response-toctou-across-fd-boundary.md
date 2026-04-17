---
module: "KB binary response + hash gate"
date: 2026-04-17
problem_type: security_issue
component: nextjs_route
symptoms:
  - "Hash-then-serve refactor opened a rename/link TOCTOU window"
  - "Verdict cache keyed only on (mtimeMs, size) could be fooled by same-second same-size swaps"
  - "openBinaryStream errors mapped EVERY failure to 404 (incl. EMFILE)"
root_cause: buffer-to-stream_refactor_split_the_hash_and_serve_fds
severity: high
tags:
  - toctou
  - fd-lifetime
  - streaming
  - nextjs
  - inode-identity
  - code-review
synced_to: []
---

# Streaming refactor split the fd used for hashing from the fd used for serving — inode identity must be pinned across the gap

## Problem

PR #2477 converted `readBinaryFile` from a buffered read (`handle.readFile()` — bytes live in memory) to a metadata-only validator (`validateBinaryFile`) plus `openBinaryStream(filePath)` called fresh per response. This is the right perf fix (peak RSS drops from O(size) to O(64 KB)) but it split what had been a single-fd operation into **three separate `open()` calls** on the same path:

1. `validateBinaryFile` opens fd A, fstats, closes — to get `(ino, mtimeMs, size)` and content-type metadata.
2. `openBinaryStream(filePath)` opens fd B for the hash pass (cache miss), drains through SHA-256, closes.
3. `buildBinaryResponse` opens fd C for the response body stream.

The pre-refactor version used a single held fd for both the hash and the serve — bytes hashed and bytes served were bit-identical by fd identity. Post-refactor, an attacker with write access to the workspace can `rename(2)` a different regular file over the path between step 2 and step 3 and serve mismatched bytes that passed the hash gate.

`O_NOFOLLOW` does NOT protect against this — it only refuses symlinks at the terminal component. A rename of a regular file on top of a regular file is not a symlink operation and slips past.

Additionally: the verdict cache was initially keyed on `(token, mtimeMs, size)` only. On filesystems with coarse mtime resolution (NFS, overlayfs on older kernels, older tmpfs), a same-size file swap within the same mtime-second would hit the cache and serve the swapped bytes for up to 60 s without re-hashing.

## Investigation / How It Surfaced

Multi-agent review. `security-sentinel` F1 flagged the fd-split TOCTOU symbolically by reading the refactor's code path. `security-sentinel` F2 flagged the coarse-mtime cache-coherence edge case. `code-quality-analyst` P2-2 independently flagged that `openBinaryStream` errors mapped to 404 regardless of cause, swallowing fd-exhaustion (`EMFILE`/`ENFILE`) as "document no longer available" — which is a different failure mode of the same refactor (error classification drift when the I/O path grew an extra error source).

None of these were caught by vitest (tests used `fs.writeFileSync` + small real files; no attempt to simulate a rename during the request), `tsc --noEmit` (no type signal), or semgrep (no rule covers cross-fd inode drift). Full Next.js build passed clean. This is the same class as `2026-04-15-multi-agent-review-catches-bugs-tests-miss.md` — the review agents catch bugs that green CI does not.

## Solution

### 1. Pin inode identity across fds

```ts
// In validateBinaryFile, capture stat.ino along with size/mtimeMs:
return {
  ok: true,
  filePath: fullPath,
  ino: stat.ino,
  size: stat.size,
  mtimeMs: stat.mtimeMs,
  // ...
};

// In openBinaryStream, accept `expected` and fstat-verify:
export async function openBinaryStream(
  filePath: string,
  opts?: { start?: number; end?: number; expected?: { ino: number; size: number } },
): Promise<Readable> {
  const handle = await fs.promises.open(filePath, O_RDONLY | O_NOFOLLOW);
  if (opts?.expected) {
    const stat = await handle.stat();
    if (stat.ino !== opts.expected.ino || stat.size !== opts.expected.size) {
      await handle.close();
      throw new BinaryOpenError(404, "File changed between validation and read", "content-changed");
    }
  }
  return handle.createReadStream({ autoClose: true, start: opts?.start, end: opts?.end });
}
```

Callers that already have metadata (`validateBinaryFile` result) MUST pass `expected` on every subsequent `openBinaryStream` call. Missing the pass on any call silently reopens the TOCTOU window.

### 2. Add `ino` to the verdict cache tuple

```ts
shareHashVerdictCache.get(token, ino, mtimeMs, size)  // was: (token, mtimeMs, size)
shareHashVerdictCache.set(token, ino, mtimeMs, size)
```

`ino` is the defense-in-depth against coarse-mtime swap attacks. Even on a filesystem that truncates mtime to 1-second resolution, inode reuse within a 60 s window is extremely unlikely in practice and would require an orchestrated `rm` + `creat` cycle timed against the cache TTL.

### 3. Classify `openBinaryStream` errors

Introduce `BinaryOpenError` with a status field; map Node error codes:

- `ENOENT` → 404
- `ELOOP`, `EMLINK`, `EACCES`, `EPERM` → 403
- `EMFILE`, `ENFILE` → 503 (server-side fd exhaustion, not client error)
- anything else → 500

The route handler catches `BinaryOpenError`, passes through `.status`, and logs `.code` for observability. The `"content-changed"` code is the sentinel thrown on inode/size drift so routes can map it to 410 without reading the error message string.

### 4. Rename `readBinaryFile` → `validateBinaryFile`

The old name is a lie post-refactor — it doesn't read the file. Keep a transitional `export const readBinaryFile = validateBinaryFile` alias so the rename lands in one commit without a big-bang callsite migration.

## Key Insights

- **Any refactor that splits a single-fd operation into multiple fds opens a TOCTOU window.** The pre-refactor safety was implicit in fd identity. Post-refactor, identity must become explicit via `ino` + fstat-verify on every subsequent open. Don't assume `O_NOFOLLOW` covers this — it doesn't.
- **Verdict caches that key on filesystem-derived tuples should include `ino`.** `mtimeMs + size` is enough on a correctness-strict ext4, but wrong on NFS, tmpfs (older kernels), overlayfs, and anything behind a 1-second mtime rounding layer. `ino` is free (the fstat that produces mtime also produces ino) and closes an ugly edge case.
- **When an error classifier exists in one helper (validateBinaryFile), it must also exist in every sibling helper that does the same I/O.** `openBinaryStream` initially swallowed all errors as 404; the fix introduces a shared `BinaryOpenError` with proper status mapping so the classification is load-bearing in both places.

## Session Errors

**Error 1 — Initial implementation shipped the 3-fd split without the `expected` tuple guard.** The plan document explicitly called out the TOCTOU window and documented acceptance of it, and I followed the plan verbatim without pushing back. On second-pass review, security-sentinel flagged it as P2 and the fix was small (~30 LOC across 3 files). **Prevention:** When a plan document says "accepted trade-off" for a TOCTOU or security-boundary change, treat that as a flag for extra scrutiny during implementation, not a rubber stamp. Ask: is there a cheap way to close the window even if the plan accepts leaving it open? In this case, threading `ino` through metadata was ~30 LOC — the plan's "acceptance" was premature.

**Error 2 — Cache-key expansion required a coordinated signature change across module, singleton exports, tests, and route call sites.** Four files, one breaking signature. **Prevention:** Already covered by rule `cq-nextjs-route-files-http-only-exports` (cache in its own module) and the usual TDD-first gate. Adding `ino` to a cache key is cheap; omitting `ino` from one call site in a future edit would silently downgrade the security story. A test that asserts the exact cached tuple (ino included) guards against regression — now added at `test/shared-token-verdict-cache.test.ts`.

## Prevention

- In review checklists for any buffer → stream refactor on hot security paths, explicitly ask: "Does the refactor split what was a single fd into multiple fds? If so, is inode identity preserved across the gap?"
- In verdict-cache design: prefer `(ino, mtimeMs, size)` over `(mtimeMs, size)`. The extra field is free from fstat and closes a real edge case.
- Error classification: if a helper can throw, define a typed error (class with status+code) and let callers discriminate. Don't let callers map-all-errors-to-one-status because "it probably means X."

## Related

- `2026-04-17-migration-not-null-without-backfill-and-partial-unique-index-pattern.md` — earlier in this session, also a multi-agent-review P2 catch on a pattern that passed all local checks.
- `2026-04-15-multi-agent-review-catches-bugs-tests-miss.md` — pattern catalogue.
- PR #2463 — introduced the content-hash gate this PR had to preserve.
- PR #2477 — this PR (streaming + verdict cache + TOCTOU fix).
- Scope-outs filed: #2483 (serveBinaryWithHashGate helper, contested-design).
