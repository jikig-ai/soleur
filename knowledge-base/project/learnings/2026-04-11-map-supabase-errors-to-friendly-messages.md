---
title: Map raw Supabase error strings to user-friendly messages on the login page
date: 2026-04-11
category: ui-bugs
tags: [supabase, auth, error-handling, ux, login]
issue: "1765"
---

# Learning: Map raw Supabase error strings to user-friendly messages

## Problem

The login page (`apps/web-platform/app/(auth)/login/page.tsx`) displayed raw Supabase
error strings directly to users. Two classes of errors were affected:

1. **Inline Supabase API errors** (from `signInWithOtp` / `verifyOtp`): `error.message`
   was set directly with `setError(error.message)`. Strings like
   `"email rate limit exceeded"` were shown verbatim.
2. **Callback redirect errors** (query param `?error=`): The `CALLBACK_ERRORS` map
   was missing `code_verifier_missing`, and `auth_failed` had a generic message
   with no context for the GitHub identity-linking flow.

## Solution

All changes in a single file (`apps/web-platform/app/(auth)/login/page.tsx`):

1. Added `code_verifier_missing` → `"Session expired. Please try signing in again."` to `CALLBACK_ERRORS`.
2. Improved `auth_failed` message to include context about GitHub account linking.
3. Added `SUPABASE_ERROR_PATTERNS: [RegExp, string][]` array for regex-based mapping
   of raw Supabase messages to friendly copy.
4. Added `mapSupabaseError(message)` helper that iterates patterns and falls back to
   a generic safe message.
5. Replaced both `setError(error.message)` calls with `setError(mapSupabaseError(error.message))`.

## Key Insight

Never pass `error.message` from third-party SDKs directly to UI state. Always
mediate through a mapping layer. Regex patterns (rather than exact string matches)
handle Supabase message variations across versions.

## Session Errors

1. **`worktree-manager.sh` exited 128** — script calls `git pull` which fails in a
   bare repo. Recovery: used `git worktree add` directly.
   **Prevention:** `fix-issue` skill should document `git worktree add` as the bare-repo
   fallback when worktree-manager fails.

2. **`bun test` crashed with Floating Point Exception** — Bun v1.3.6 segfaults before
   running any tests on this machine. No test baseline could be established.
   **Prevention:** File a tracking issue. The `fix-issue` skill should detect
   `panic:` in bun output and note it as a pre-existing runner crash, not a test failure.

3. **`Glob **/login*` returned no files** — Next.js route groups use `(auth)/login/`
   parenthesised directory names that glob patterns without explicit `(*)` don't match.
   **Prevention:** For Next.js apps, use `**/(*)/**/*login*` or list `app/` directly.

## Tags

category: ui-bugs
module: auth/login
