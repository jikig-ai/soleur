---
date: 2026-05-04
category: integration-issues
module: apps/web-platform/lib/auth
tags: [supabase, error-mapping, ux, account-enumeration, referrer-policy]
issues: ["#1765", "PR #3180"]
related:
  - 2026-03-20-supabase-signinwithotp-creates-users.md
---

# Learning: A `shouldCreateUser: false`-class flag creates a NEW error surface the mapper must handle in lockstep

## Problem

The login page called `supabase.auth.signInWithOtp({ email, options: { shouldCreateUser: false } })`. When the email had no Soleur account (e.g. `harry@jikigai.com`), Supabase returned an `AuthApiError` with `code: "otp_disabled"` / `message: "Signups not allowed for otp"`. The `mapSupabaseError` mapper at `apps/web-platform/lib/auth/error-messages.ts` had patterns for `email rate limit exceeded`, `invalid otp`, and `token...expired` — but **nothing** for `otp_disabled`. Result: every no-account login submission fell through to the generic `DEFAULT_ERROR_MESSAGE = "Something went wrong. Please try again."` — a confused, blame-shifted, dead-end UX. The original "fix" (issue #1765) had added three friendly strings but missed `otp_disabled` because the error class didn't exist *at the time* — it only became reachable when `shouldCreateUser: false` was added later (PR #1344, the magic-link → OTP split).

## Solution

Two-part fix, plus a defense-in-depth mapper entry:

1. **Detect the no-account condition with a typed-code-first check.** Add `isNoAccountError(error)` in `lib/auth/error-messages.ts` that checks `error.code === "otp_disabled"` first (typed contract from `@supabase/auth-js`'s `ErrorCode` union) and falls back to a regex on `error.message` (`/signups? not allowed for otp/i`) for SDK versions or transports that drop the code field.

2. **Redirect, don't display.** On the login page, when `isNoAccountError` matches, call `router.replace("/signup?email=<encoded>&reason=no_account")` — `replace` (not `push`) keeps the email out of browser history. The signup page reads the query params, prefills the email, and shows a derived banner ("No Soleur account found for X. Create one below.") — no `useState`, no dismiss-site, banner auto-hides when the user edits the email (`email !== initialEmail`).

3. **Mapper defense-in-depth.** Add `NO_ACCOUNT_PATTERN` to `SUPABASE_ERROR_PATTERNS` mapping to a sensible string. Both the mapper entry and `isNoAccountError` reference the same const — single source of truth for the regex.

4. **Auth-segment Referrer-Policy.** Adding `?email=` to the redirect URL means the user's email lands in the `Referer` header on cross-origin OAuth click. Add `app/(auth)/layout.tsx` exporting `metadata.referrer = "strict-origin-when-cross-origin"`.

## Key Insight

When you toggle a boolean feature flag on an upstream API (here `shouldCreateUser: false`), **the error surface is new — not a subset of the default surface.** Every downstream consumer of that error — mapper functions, UI handlers, observability tags, telemetry — must be reviewed in lockstep. The flag flip is mechanical; the error-mapping work is not.

Forcing functions:

- When adding `shouldCreateUser: false` (or any equivalent gate flag), grep all `mapSupabaseError` / error-display call sites in the same PR and verify each new error code from the upstream docs has a friendly string OR an explicit "redirect on detection" branch. The same pattern applies to `email_signup_disabled`, `phone_signup_disabled`, `over_email_send_rate_limit`, etc.
- Detection should prefer **typed error codes** (Supabase `ErrorCode` union, etc.) over regex on prose. Regex is defense-in-depth; codes are the contract.
- When the right UX response to an error is **navigation, not error-text**, use `router.replace` not `router.push` so the URL (which may carry the user's email or other PII) doesn't enter browser history. Add a `Referrer-Policy` to the affected route segment so the URL doesn't leak via `Referer` on outbound clicks.

## Patterns to Apply

```ts
// lib/auth/error-messages.ts — single source of truth for both mapper and detector
export const NO_ACCOUNT_PATTERN = /signups? not allowed for otp/i;
export const SIGNUP_REASON_NO_ACCOUNT = "no_account";

const SUPABASE_ERROR_PATTERNS: [RegExp, string][] = [
  [NO_ACCOUNT_PATTERN, "No Soleur account found for this email. Sign up instead."],
  // ...
];

export function isNoAccountError(error: { code?: string; message: string }): boolean {
  if (error.code === "otp_disabled") return true;
  return NO_ACCOUNT_PATTERN.test(error.message);
}
```

```tsx
// signup/page.tsx — derived banner state, no useState
const showNoAccountBanner =
  reason === SIGNUP_REASON_NO_ACCOUNT &&
  initialEmail.length > 0 &&
  email === initialEmail; // auto-hides on first edit
```

```tsx
// app/(auth)/layout.tsx — pin referrer for the entire auth segment
export const metadata: Metadata = {
  referrer: "strict-origin-when-cross-origin",
};
```

## Session Errors

- **`bun run lint` is interactive in Next.js 16** — `next lint` is deprecated and prompts for ESLint setup, blocking automated quality gates. Recovery: skipped lint, relied on `bunx tsc --noEmit` + the test suite. Prevention: route the lint setup migration (`@next/codemod next-lint-to-eslint-cli .`) onto the next-touched apps/web-platform task; skill instruction in `work` Phase 3 to detect the deprecation prompt and fall back gracefully without blocking.
- **Playwright MCP `browser_navigate` failed twice with "Target page... has been closed"** — required `browser_close` then re-navigate. Recovery: explicit `browser_close` cleared stale context; next navigate succeeded. Prevention: skill instruction in `qa` (or a Sharp Edge note in `review-e2e-testing.md`) — when `browser_navigate` errors with "Target page/context/browser has been closed", don't retry the same navigate; call `browser_close` first to recycle the context, then re-navigate.

## Related

- `2026-03-20-supabase-signinwithotp-creates-users.md` — the prior learning that drove the `shouldCreateUser: false` flag flip; this learning is its direct follow-on (the flag created the error class this learning teaches the consumer to handle).
- `2026-04-15-multi-agent-review-catches-bugs-tests-miss.md` — multi-agent review caught the regex-duplication drift risk that single-reviewer review would have missed; pattern-recognition + architecture + code-quality all converged on the same finding independently.
- Issue #1765 — the precursor "improve error messages on login page" fix that addressed three patterns but missed `otp_disabled` because the error didn't yet exist on the login path.
- PR #3180 — this PR (squash-merge target).
