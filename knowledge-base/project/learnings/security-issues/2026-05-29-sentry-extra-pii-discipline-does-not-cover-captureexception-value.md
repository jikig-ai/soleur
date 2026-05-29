---
title: "extra-level PII discipline gives false confidence — captureException still ships error.message"
date: 2026-05-29
category: security-issues
module: apps/web-platform/auth
tags: [sentry, pii, observability, supabase-auth, otp, error-mapping]
related:
  - "PR #4633 — fix OTP verify generic error + code/status mapping"
  - "lib/client-observability.ts stripPiiKeys / ClientExtra branding"
  - "sentry.client.config.ts beforeSend scrub chain"
  - "2026-05-18-supabase-custom-access-token-hook-discriminator.md"
---

# Learning: Sentry `extra` PII discipline does not cover the `captureException` exception value

## Problem

The dashboard OTP verify screen rendered a dead-end `Something went wrong. Please
try again.` for `ops@jikigai.com` after a long wait. Root cause: the client error
mapper (`lib/auth/error-messages.ts`) matched only four freetext message regexes
and fell through to the generic message for every structured GoTrue failure —
`over_request_rate_limit` (429), `otp_expired`, server 5xx (a raising Custom
Access Token Hook), and transport throws. The operationally-likely failures all
dead-ended.

A secondary, subtler finding surfaced in multi-agent review: the codebase had a
careful `extra`-level PII discipline (forward only enum `code` / int `status` to
Sentry, never `error.message`, because the message embeds the email and Sentry is
a shared cross-tenant project). But `reportSilentFallback(err, ...)` forwards the
**raw error object** as the first arg to `Sentry.captureException(err, ...)`, so
`error.message` (e.g. `"rate limited for ops@jikigai.com"`) still shipped to
Sentry as `event.exception.values[].value`. The `extra` bag was clean; the
exception value was not. The unit test even asserted "never forwards
error.message" while only inspecting `extra` — papering over the real leak.

## Solution

1. **Map on structured fields first.** `mapSupabaseAuthError(error)` inspects
   `error.code` then `error.status` (version-stable, no PII), then falls back to
   the preserved freetext regex table. Mirrors the in-repo precedent at
   `lib/supabase/tenant.ts` (code-first discrimination on `over_request_rate_limit`).
   Wrap `verifyOtp`/`signInWithOtp`/`signInWithOAuth` in try/catch so a transport
   reject routes through the same layer instead of throwing unhandled.
2. **Scrub PII at the `beforeSend` layer, not just at the call site.** Added an
   `EMAIL_PATTERN` scrub to `sentry.client.config.ts` `beforeSend` (mirrors the
   existing JWT scrub loop over `event.message` + `event.exception.values[].value`).
   Over-redacting an email in error telemetry is the safe direction.

## Key Insight

**Call-site `extra` hygiene is necessary but not sufficient.** Any helper that
forwards a raw `Error` to `Sentry.captureException` ships `error.message` as the
exception value regardless of how disciplined the structured `extra` payload is.
The load-bearing scrub for message-borne PII lives in the global `beforeSend`
chain (which already iterates `exception.values[].value` for JWTs) — not at the
N call sites. When you see a test named "never forwards `error.message`" that only
asserts on `extra`, treat it as a false-confidence signal: check whether the raw
error itself reaches `captureException`.

Generalizable: **a redaction filter applied to one serialization surface (the
structured bag) does not cover sibling surfaces (the exception value, the
breadcrumb message, the span description).** Enumerate every surface the sensitive
string can ride before declaring the leak closed.

## Session Errors

1. **Bash CWD confusion** — `cd apps/web-platform && vitest` failed with "No such
   directory" because the Bash tool's CWD had already persisted into that dir from
   a prior call. Recovery: dropped the redundant `cd`. **Prevention:** use one
   absolute-path `cd /abs/path && cmd` per Bash call; do not assume CWD either
   persists or resets between calls — anchor every command to an absolute path.
2. **Duplicate `import Link`** introduced while replacing an inserted type block
   that had displaced an adjacent import line. Recovery: grep + remove the dupe.
   **Prevention:** after replacing a block that was earlier inserted *between* two
   existing lines, grep for the displaced symbol to confirm no duplicate remains.
3. **Plan-file Edit "modified since read"** — a linter touched the file between
   Read and Edit. Recovery: re-read then edit. Expected; no workflow change.

## Tags
category: security-issues
module: apps/web-platform/auth
