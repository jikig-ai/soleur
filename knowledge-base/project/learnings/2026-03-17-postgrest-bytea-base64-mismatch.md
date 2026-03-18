# Learning: PostgREST bytea column returns hex, not base64

## Problem

BYOK key decryption failed with "Unsupported state or unable to authenticate data" (AES-256-GCM). The `encrypted_key` column was declared as `bytea` in PostgreSQL, but the app wrote base64 strings and read expecting base64 strings. PostgREST returns `bytea` columns in PostgreSQL hex format (`\x4142...`), not the original value. `Buffer.from(hexString, "base64")` produced garbage bytes, causing GCM auth tag verification to fail.

## Solution

Changed `encrypted_key` column from `bytea` to `text` via migration, aligning it with `iv` and `auth_tag` (already `text`). Used `convert_from(encrypted_key, 'UTF8')` in the `USING` clause — NOT `encode(encrypted_key, 'base64')` which would double-encode (the stored bytes are ASCII of the base64 string, not raw ciphertext).

## Key Insight

When PostgREST writes a string to a `bytea` column, it stores the ASCII bytes of the string. When it reads the column back, it returns the hex-escaped format (`\x...`). This creates a silent data round-trip corruption that only surfaces when the consumer tries to use the data (e.g., decryption fails). If your app stores and reads string-encoded binary data (base64), use `text` columns — not `bytea` — unless you specifically handle PostgREST's bytea serialization format.

Migration gotcha: `encode(bytea, 'base64')` re-encodes, producing base64-of-ASCII-of-base64. Use `convert_from(bytea, 'UTF8')` to extract the original text that was stored as bytes.

## Session Errors

1. **Worktree script failed from bare repo** — `worktree-manager.sh feature` requires a work tree, not a bare repo. Used `git worktree add` directly as fallback.
2. **Wrong GitHub label name** — Used `type/enhancement` but correct label is `enhancement`. Check labels with `gh label list` before creating issues.
3. **Fix branch based on wrong parent** — Created `feat-byok-decryption-fix` from `main`, but `apps/web-platform/` only exists on unmerged `feat/web-platform-ux`. Had to close PR #677, remove worktree, and work on the existing feature branch instead. When fixing bugs in unmerged feature code, branch from the feature branch, not main.

## Tags

category: database-issues
module: apps/web-platform
