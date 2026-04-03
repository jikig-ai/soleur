---
module: WebPlatform
date: 2026-04-03
problem_type: security_issue
component: frontend_stimulus
symptoms:
  - "safeReturnTo allowed path traversal via ../ sequences"
  - "return_to param stored unsanitized in sessionStorage before validation"
  - "repoStatus typed as bare string instead of union type"
root_cause: missing_validation
resolution_type: code_fix
severity: high
tags: [open-redirect, path-traversal, sessionStorage, type-safety, settings]
synced_to: []
---

# Learning: Open Redirect Prevention with safeReturnTo

## Problem

When adding a `return_to` query param to survive GitHub OAuth redirects (settings -> connect-repo -> GitHub -> connect-repo -> settings), the initial `safeReturnTo` validation function blocked protocol-relative URLs (`//evil.com`) and backslash tricks but did not block path traversal (`/dashboard/../../logout`). A value like `/dashboard/../anything` passes the `startsWith("/dashboard")` check but resolves outside the dashboard path.

## Solution

Three fixes applied:

1. **Block `..` in safeReturnTo:** Added `param.includes("..")` check alongside existing `//` and `\\` checks
2. **Validate before storing:** Apply `safeReturnTo` before writing to `sessionStorage`, not just on read (defense-in-depth)
3. **Extract `consumeReturnTo` helper:** Deduplicated the sessionStorage read-and-clear pattern used in both `handleSkip` and `handleOpenDashboard`

```typescript
// Before (vulnerable)
if (!param.startsWith("/dashboard")) return FALLBACK;
if (param.includes("//") || param.includes("\\")) return FALLBACK;

// After (fixed)
if (!param.startsWith("/dashboard")) return FALLBACK;
if (param.includes("//") || param.includes("\\") || param.includes("..")) return FALLBACK;
```

## Key Insight

When building URL allowlists with prefix checks (`startsWith`), always also block path traversal sequences (`..`). The `startsWith` check only validates the beginning of the string — `../` segments can escape the allowed prefix after browser path normalization. This is a well-known OWASP open redirect pattern that prefix-only validation misses.

Also: validate untrusted input before storing, not just before using. Storing raw user input creates a fragile pattern where any future read site that forgets to validate inherits the vulnerability.

## Session Errors

1. **Dev server failed to start during QA** — `supabaseUrl is required` error from `session-sync.ts`. Recovery: Skipped browser QA, relied on unit tests (32 passing). Prevention: Fix the dev server Doppler config to include all required env vars for the custom server entrypoint.
2. **Initial safeReturnTo missed path traversal** — Security review caught `../` bypass. Recovery: Added `..` check and tests. Prevention: When writing URL validation functions, enumerate all OWASP open redirect vectors (protocol-relative, backslash, path traversal, encoded characters) in the initial implementation, not as review fixes.
3. **repoStatus typed as bare string** — Three review agents flagged the same issue. Recovery: Added `RepoStatus` union type. Prevention: When a component renders conditional branches based on string comparisons, define a union type from the start.

## Tags

category: security-issues
module: WebPlatform
