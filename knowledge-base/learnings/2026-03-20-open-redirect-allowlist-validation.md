# Learning: Open Redirect Prevention via Set-Based Origin Allowlist

## Problem

The auth callback route at `apps/web-platform/app/(auth)/callback/route.ts` constructed redirect URLs by concatenating attacker-controlled `x-forwarded-host` and `x-forwarded-proto` headers without any validation. An attacker could set `x-forwarded-host: evil.com` and redirect authenticated users to a malicious domain after login, stealing session tokens or phishing credentials.

## Solution

Extracted origin resolution into a pure function `resolveOrigin()` in `apps/web-platform/lib/auth/resolve-origin.ts`. The function computes the origin from forwarded headers, normalizes to lowercase (RFC 4343 hostname case-insensitivity), then validates against a hardcoded `Set<string>` allowlist. Rejected origins fall back to the production default (`https://app.soleur.ai`) and emit a warning log with control characters stripped to prevent log injection. `localhost:3000` is only added to the allowlist when `NODE_ENV=development`.

Key design choices:
- **`Set.has()` exact-match** -- zero bypass surface. No regex patterns to escape, no URL parsing to confuse, no substring matching to exploit. Subdomain spoofing (`app.soleur.ai.evil.com`), userinfo abuse (`app.soleur.ai@evil.com`), port variants, and URL encoding all fail because they never produce an exact match.
- **Pure function with no framework dependencies** -- testable with vitest directly, no Next.js runtime or path alias resolution needed.
- **Fail-closed** -- any origin not in the set returns the production default, never the attacker-controlled value.

## Key Insight

For redirect URL validation, `Set.has()` exact-match against a hardcoded allowlist is strictly superior to regex, URL parsing, or substring checks. Every alternative introduces bypass surface (regex anchoring errors, URL parser quirks, subdomain prefix matching). The allowlist approach has exactly one failure mode: forgetting to add a legitimate origin to the set -- which fails safe (redirects to production).

When testing Next.js route handlers, extract security-critical logic into standalone lib files without framework dependencies (`@/` path aliases, `next/server` imports, etc.). Vitest cannot resolve Next.js path aliases without additional configuration, and decoupling the logic from the framework makes the security boundary easier to test and audit.

## Session Errors

1. **Stale vitest cache with native binding mismatch** -- Running `npx vitest` before `npm install` caused a crash because the cached rolldown native binding was stale. Fix: always run `npm install` in the app directory before first test run in a new worktree.
2. **Path alias resolution failure** -- Initial tests imported the route handler directly (`app/(auth)/callback/route.ts`), which uses `@/` path aliases that vitest couldn't resolve. Fix: extracted `resolveOrigin()` into `lib/auth/resolve-origin.ts` with no `@/` imports, then tested the pure function. This also improved the design by separating concerns.
3. **Case-sensitivity gap caught by review agents** -- The initial implementation did not lowercase the computed origin before allowlist comparison, meaning `APP.SOLEUR.AI` would be rejected despite being a valid hostname per RFC 4343. Four parallel review agents caught this; added `.toLowerCase()` normalization.

## Tags

category: security
module: apps/web-platform
