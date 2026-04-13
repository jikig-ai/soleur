# Learning: Foundation card completion requires file size, not just existence

## Problem

The Command Center dashboard showed a green checkmark (complete) for foundation
cards when the underlying file merely existed, even if it was a stub containing
only a title and a placeholder instruction (~100-200 bytes). This false-positive
completion gave users the impression their vision document was done when it had
no real content.

## Solution

Added `size` to the KB tree API response (already available from the existing
`fs.stat()` call in `buildTree`) and changed the dashboard completion check from
pure file-existence (`Set.has(path)`) to existence + minimum size
(`Map.get(path)?.size >= FOUNDATION_MIN_CONTENT_BYTES`).

Key decisions:

- Extracted the 500-byte threshold into `FOUNDATION_MIN_CONTENT_BYTES` in
  `lib/kb-constants.ts` to prevent drift between `vision-helpers.ts` and the
  dashboard
- Changed `flattenTree` from `Set<string>` to `Map<string, FileInfo>` to carry
  size metadata to the consumption site
- Kept `visionExists` as file-existence-only for the first-run gate (a stub
  means the user already submitted their idea)

## Key Insight

When a tree API already calls `stat()` on every file, piggybacking additional
metadata (size, permissions) costs zero additional I/O. The stat result was being
destructured to extract only `mtime` and the rest discarded. Capturing the full
result object and extracting multiple fields is both simpler and more useful.

Shared constants (`FOUNDATION_MIN_CONTENT_BYTES`) between server and client code
prevent threshold drift -- the 500-byte magic number existed in two places before
this fix.

## Session Errors

1. **E2e test `kbTree()` helper missing `size` field** — The plan's task list
   covered unit test updates but missed the e2e test file
   (`e2e/start-fresh-onboarding.e2e.ts`), which has its own `TreeNode` interface
   copy. Three review agents independently flagged this. Recovery: Fixed in a
   follow-up commit. Prevention: When adding a field to a shared interface,
   grep for all copies of the interface across the codebase (including test and
   e2e directories) before considering the task complete.

2. **Dev server startup failure during QA** — Supabase env vars missing from
   Doppler `dev` config prevented browser-based QA. Recovery: Skipped browser
   QA (unit tests covered all scenarios). Prevention: Pre-existing environment
   issue; tracked separately.

## Tags

category: ui-bugs
module: dashboard, kb-reader
