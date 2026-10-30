# Tasks — fix-codeql-fs-race-digest-write

Plan: `knowledge-base/project/plans/2026-10-27-fix-codeql-fs-race-digest-write-plan.md`

## Phase 1 — Failing tests first

- [x] 1.1 In `apps/web-platform/test/server/inngest/cron-community-publication.test.ts`, extend the `writeDigestFileContained` describe block (`:1031`):
  - [x] 1.1.1 `spawnCwd` itself a symlink → throws (containment refusal), writes nothing.
  - [x] 1.1.2 Linux-only dentry-pin regression (`it.skipIf(process.platform !== "linux")`): open the leaf's parent dir via the internal dir-handle seam, `rename` the real ancestor away + `symlink` a decoy outside dir into its place, write the leaf through the pinned fd → bytes land inside the renamed dir, decoy target untouched.
  - [x] 1.1.3 Leaf racing-recreate fails closed: an `O_EXCL`-violating leaf state (or injected seam) → throw, no overwrite.
- [x] 1.2 Run `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-community-publication.test.ts` — new cases RED.

## Phase 2 — Implementation

- [x] 2.1 In `apps/web-platform/server/inngest/functions/_cron-community-publication.ts`, rewrite `writeDigestFileContained` (`:639-700`):
  - [x] 2.1.1 Keep `relPath` lexical validation verbatim (`clean relative path` message).
  - [x] 2.1.2 `open(spawnCwd, O_RDONLY|O_DIRECTORY|O_NOFOLLOW)` → root dirfd (lazy `await import("node:fs/promises")` + `node:fs` constants).
  - [x] 2.1.3 Per ancestor segment: `open(`${FD_BASE}/${dirFh.fd}/${seg}`, O_RDONLY|O_DIRECTORY|O_NOFOLLOW)`; ENOENT → `mkdir` beneath pinned fd (tolerate EEXIST, re-open); ELOOP/ENOTDIR → `ancestor is not a plain directory`. `FD_BASE` = `/proc/self/fd` on Linux, else `join(current, seg)` fallback (comment: pin is Linux-only; non-Linux residual is dev-only).
  - [x] 2.1.4 Leaf: `unlink(`${FD_BASE}/${dirFh.fd}/${leaf}`)` tolerant-ENOENT; EISDIR/EPERM → `target is a directory`; then `open(leaf, O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW, 0o644)` → `fh.writeFile(text)` → `fh.close()`; EEXIST → throw fail-closed.
  - [x] 2.1.5 All FileHandles closed in `finally` with `.catch(() => {})`; internals split into `openContainedDir` + `createContainedFile` for the test seam; docstring updated to describe fd pinning.
- [x] 2.2 Re-run the vitest file — all cases GREEN (6 existing + 3 new).
- [x] 2.3 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` — clean.
- [x] 2.4 Verify zero stat-family calls remain in the function body (`grep -nE '(lstat|stat|access|existsSync)\('` inside `writeDigestFileContained` → none).

## Phase 3 — Ship checks

- [ ] 3.1 PR body carries ten `Closes #N` lines (one per own body line): #10368, #10839, #11318, #11190, #11062, #10985, #10910, #10800, #10687, #10756 — `ship` owns the body; assert they land there.
- [ ] 3.2 Post-merge (ship's verify pass): `gh api repos/jikig-ai/soleur/code-scanning/alerts/248 --jq .state` → `fixed` on the next CodeQL scan.
