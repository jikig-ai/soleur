---
status: complete
priority: p2
issue_id: 945
tags: [code-review, security]
dependencies: []
---

# Checkout URLs derived from request.url

## Problem Statement

`app/api/checkout/route.ts` derives Stripe success/cancel URLs from `new URL(request.url).origin`. Behind a reverse proxy, `request.url` can reflect the `Host` header, which an attacker could manipulate to redirect users to a malicious domain after Stripe checkout.

## Findings

- **Source:** security-sentinel agent
- **Location:** `apps/web-platform/app/api/checkout/route.ts:19-20`
- **Evidence:** `success_url: \`${new URL(request.url).origin}/dashboard?checkout=success\``

## Proposed Solutions

### Option A: Use environment variable (Recommended)
Use `process.env.NEXT_PUBLIC_APP_URL ?? "https://app.soleur.ai"` for the origin.
- **Pros:** Simple, no dependency on request headers
- **Cons:** Requires env var to be set
- **Effort:** Small
- **Risk:** Low

### Option B: Use resolveOrigin utility
Import `resolveOrigin` from `lib/auth/resolve-origin.ts` which already validates against the allowlist.
- **Pros:** Reuses existing validation
- **Cons:** More complex, different function signature
- **Effort:** Small
- **Risk:** Low

## Recommended Action

Option A — replace `new URL(request.url).origin` with a hardcoded/env-based origin.

## Technical Details

- **Affected files:** `apps/web-platform/app/api/checkout/route.ts`

## Acceptance Criteria

- [ ] Checkout success/cancel URLs use a validated origin, not `request.url`
- [ ] Tests verify the URLs use the expected origin

## Work Log

| Date | Action | Notes |
|------|--------|-------|
| 2026-03-20 | Created | Found by security-sentinel during review |
