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

Created a shared error mapping utility at `apps/web-platform/lib/auth/error-messages.ts`:

1. `CALLBACK_ERRORS` map for query-param redirect errors (`auth_failed`, `code_verifier_missing`, `provider_disabled`).
2. `SUPABASE_ERROR_PATTERNS: [RegExp, string][]` array for regex-based mapping of raw Supabase messages to friendly copy.
3. `mapSupabaseError(message)` helper that iterates patterns and falls back to `DEFAULT_ERROR_MESSAGE`.
4. Applied to all auth surfaces: `login/page.tsx`, `signup/page.tsx`, and `oauth-buttons.tsx`.
5. Added `console.error` before mapping so raw errors are available in dev tools for debugging.

## Key Insight

Never pass `error.message` from third-party SDKs directly to UI state. Always
mediate through a mapping layer. Regex patterns (rather than exact string matches)
handle Supabase message variations across versions.

## Tags

category: ui-bugs
module: auth/login
