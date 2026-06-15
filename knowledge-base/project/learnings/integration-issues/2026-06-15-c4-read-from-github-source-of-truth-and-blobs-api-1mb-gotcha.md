---
title: "C4 read path: serve from GitHub source-of-truth, and the Contents-API 1 MB content-drop gotcha"
date: 2026-06-15
category: integration-issues
module: apps/web-platform/app/api/kb/c4
tags: [github-api, c4, read-path, stale-clone, cache-coherence, blobs-api]
related_issues: [5221, 5304, 5309, 5220, 4976]
---

# Learning: C4 Code-tab Save did not survive a page refresh — read from GitHub, not the on-disk clone

## Problem

Editing a `.c4` in the KB Code panel, clicking Save, then **refreshing** showed the
OLD text + OLD diagram. The commit DID land on GitHub (200), but
`GET /api/kb/c4/project` read both `model.likec4.json` and the `.c4` sources
**exclusively from the on-disk workspace clone** (`kbRoot`). That clone is advanced
only by a best-effort `git pull --ff-only` whose self-heal ABORTS when the clone
holds un-pushed `session-sync` commits (`workspace-sync.ts:198-218`) — so a diverged
clone stays **permanently stale** and every refresh re-served pre-edit content.

## Solution

Read the `.c4` sources + `model.likec4.json` from the **GitHub source of truth** as
the PRIMARY path (PR #5304): resolve the active workspace's repo/installation via the
existing `resolveActiveWorkspaceRepoMeta` (ADR-044, membership-scoped), list the
diagrams dir once via the Contents API for per-file blob shas, then fetch each body
via the **Git Blobs API**. The on-disk clone is no longer read by this route. A
GitHub-read failure returns a distinct 503 + `reportSilentFallback` — never a silent
stale serve (the #4976 "a cache lag must not present as data loss" insight applied to
the read path).

## Key Insights

1. **The GitHub Contents API drops the base64 `content` field for files > 1 MB.**
   `model.likec4.json` is capped at 4 MB (`MAX_C4_BYTES`), so a 1–4 MB model read via
   `GET /contents/...` `.content` decodes to EMPTY and serves a broken dump WITHOUT
   tripping any size guard — silent corruption *worse* than the original bug. Read
   file BODIES via the **Git Blobs API** (`GET /repos/{o}/{r}/git/blobs/{sha}`, base64
   to 100 MB) using the sha from the Contents directory listing. A single Contents-dir
   listing returns every file's sha atomically, and blobs are content-addressed, so
   the source + dump are a consistent read-side snapshot without a separate HEAD pin.
   (Caveat: the WRITER commits the `.c4` and the re-rendered JSON in two separate
   commits, so a read landing between them can see new-source + old-dump — transient,
   self-correcting, covered by the Layer-1 honest-stale banner.)

2. **A same-titled prior PR may have fixed only a client slice.** #5220 shipped a
   client-side optimistic `useRef` that masks the revert *in-session* but resets on
   remount — so it does NOT survive a page refresh. The server root cause was
   explicitly deferred (tracking issue #5221, OPEN). Before treating a bug as "already
   fixed," verify which slice the prior PR closed; "the diagram reverts after refresh"
   was the deferred server slice, not stale.

3. **On a GitHub-primary route, drop the on-disk filesystem path guard.** The old
   route validated `dir` via `isPathInWorkspace(dirAbs, kbRoot)` — a filesystem check
   against the clone. On a route that no longer reads the clone, that check
   false-negative-400s a legitimately-shared dir absent from a stale/empty clone, and
   the RAW `dir` string (not the normalized one) was being concatenated into the
   GitHub path — letting `?ref=`/`#` inject GitHub query params. Replace it with a
   pure-string guard (reject `..`, NUL, `\`, leading `/`, `?`, `#`). (Caught by
   security-sentinel + user-impact-reviewer at review.)

4. **`GitHubApiError` exposes `.statusCode`, not `.status`** — mirror the existing
   `c4-writer.ts` check (`err instanceof GitHubApiError && err.statusCode === 404`).

## Session Errors

- **Plan file written to the bare-root synced mirror instead of the worktree**
  (despite an absolute path). Recovery: caught at the deepen-plan halt-gate; copied
  into the worktree + deleted the stray. Prevention: the plan skill's first-tool-call
  CWD-verification step already exists and fired — keep it; subagents must `cd
  <worktree> && pwd`-verify before any Write.
- **Bash CWD drift** — `cd apps/web-platform && …` then a later worktree-root `git
  add` failed because the Bash tool RETAINED CWD at `apps/web-platform`. Recovery:
  use absolute `cd <worktree-root> && <cmd>` in a single call. Prevention: already in
  work/SKILL.md ("chain `cd <abs> && cmd` in one Bash call; CWD is not guaranteed").

## Tags
category: integration-issues
module: c4-read-path
