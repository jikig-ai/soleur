---
status: pending
priority: p2
issue_id: "045"
tags: [code-review, security, csp]
dependencies: []
---

# CSP appHost should validate against allowlist (defense-in-depth)

## Problem Statement

`request.nextUrl.host` flows unsanitized into the CSP `connect-src` directive via string interpolation in `buildCspHeader()`. While Cloudflare normalizes Host headers in production (making this unexploitable today), defense-in-depth says application-layer validation should not depend solely on infrastructure.

## Findings

- **Source:** security-sentinel review agent
- **Severity:** MEDIUM, mitigated to LOW by Cloudflare proxy (`proxied = true` in dns.tf)
- **Location:** `apps/web-platform/lib/csp.ts:33`, `apps/web-platform/middleware.ts:31`
- **Evidence:** An attacker-controlled Host header like `evil.com; script-src *` could restructure the CSP if Cloudflare proxy is removed
- **Existing pattern:** `validate-origin.ts` already uses `PRODUCTION_ORIGINS` / `DEV_ORIGINS` allowlists for origin validation

## Proposed Solutions

### Option A: Allowlist in buildCspHeader (Recommended)

Validate `appHost` against known-good hosts before interpolation.

```typescript
const ALLOWED_HOSTS = new Set(["app.soleur.ai", "localhost:3000"]);
const safeHost = ALLOWED_HOSTS.has(appHost) ? appHost : "app.soleur.ai";
```

- **Pros:** Simple, follows existing pattern from validate-origin.ts
- **Cons:** Requires updating allowlist for new deployment domains
- **Effort:** Small
- **Risk:** Low

### Option B: Sanitize CSP-breaking characters

Strip semicolons, spaces, and newlines from appHost before interpolation.

- **Pros:** No hardcoded allowlist to maintain
- **Cons:** May allow unexpected but syntactically-valid hosts in CSP
- **Effort:** Small
- **Risk:** Low

## Recommended Action

(To be filled during triage)

## Technical Details

**Affected files:**

- `apps/web-platform/lib/csp.ts` (primary)
- `apps/web-platform/test/csp.test.ts` (add adversarial input tests)

## Acceptance Criteria

- [ ] `appHost` is validated before interpolation into CSP
- [ ] Adversarial `appHost` values (spaces, semicolons, empty string) are tested
- [ ] Existing CSP tests continue to pass

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-28 | Created from security-sentinel review | Cloudflare mitigates today but defense-in-depth warranted |

## Resources

- PR #1234 (fix-command-center-server-error)
- MDN connect-src documentation
- Existing pattern: `apps/web-platform/lib/validate-origin.ts`
