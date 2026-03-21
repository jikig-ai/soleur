---
title: CSRF Prevention via Structural Enforcement (Negative-Space Tests)
date: 2026-03-20
category: security
tags: [csrf, testing, negative-space, structural-enforcement, defense-in-depth, api-routes]
symptoms: New POST handlers added without Origin validation; cookie security flags drifting during refactors
synced_to: null
---

# CSRF Prevention via Structural Enforcement (Negative-Space Tests)

## Key Insight: The Generalizable Lesson

The most effective CSRF prevention is **structural**: enforce it via automated tests rather than relying on code review or documentation. A negative-space test scans the entire codebase, enumerates the attack surface, and **fails the build** when new POST handlers are added without protection. This is more reliable than:

- Documentation ("add validateOrigin to all POST routes")
- Code review checklists ("verify CSRF protection")
- Linting rules (tools don't understand security domains)

A negative-space test makes CSRF protection a **compile-time requirement**, not a post-hoc audit.

### How It Works

```typescript
// csrf-coverage.test.ts: Negative-space enumeration
const EXEMPT_ROUTES = new Set([
  "app/api/webhooks/stripe/route.ts",  // Justified: signature-based auth
]);

describe("CSRF coverage", () => {
  it("every POST route either uses validateOrigin or is explicitly exempt", () => {
    // 1. Find ALL route.ts files in app/api/
    // 2. For each file with a POST handler:
    //    - If in EXEMPT_ROUTES, skip
    //    - If !content.includes("validateOrigin"), fail
    //    - Else pass
    // 3. Fail the test with unprotected routes listed
  });
});
```

**Why negative-space matters:** Instead of checking "is this code present?", the test checks "is this code missing?" Negative-space tests enumerate what you *thought* should exist, then fail when it doesn't. This catches omissions that positive assertions miss.

---

## Prevention Strategies by Category

### 1. Adding New Routes (Checklist for Developers)

**When you add a new route handler in `app/api/`:**

#### Pre-Coding Checklist

- [ ] Does this route mutate state (POST, PUT, DELETE)? If no, skip to "Code Complete."
- [ ] Is this route unauthenticated (e.g., webhook signature-based)? If yes, document in `EXEMPT_ROUTES` with justification; skip to "Code Complete."
- [ ] Does this route rely on Supabase auth (cookie-based)? If yes, proceed.

#### During Coding

- [ ] Import `validateOrigin` and `rejectCsrf` from `@/lib/auth/validate-origin`
- [ ] Call at the **top** of your handler, before any auth check:

  ```typescript
  export async function POST(request: Request) {
    const { valid, origin } = validateOrigin(request);
    if (!valid) return rejectCsrf("api/your-route", origin);
    // ... rest of handler
  }
  ```

- [ ] Never add your route to `EXEMPT_ROUTES` unless it is truly exempt (non-cookie auth, explicit signature verification, etc.)

#### Post-Coding

- [ ] Run the test suite: `npm test -- csrf-coverage.test.ts`
- [ ] If the test fails, add the route to `EXEMPT_ROUTES` **only** with a justification comment explaining why it bypasses Origin validation
- [ ] Include the failing test failure in your PR description so reviewers understand what changed

**Automation enforces this:** You cannot merge a PR that adds a POST handler without Origin validation. The test will fail CI.

---

### 2. CSRF Token Reconsideration Triggers

The current solution uses **Origin validation + SameSite=Lax cookies**. CSRF tokens are **not** implemented because:

- All mutations use `fetch()` from same-origin React components (not `<form>` submissions)
- Origin validation catches the cross-origin POST attack vector
- SameSite=Lax prevents the browser from sending cookies on cross-site requests

**Reconsider CSRF tokens if any of these occur:**

1. **Adding `<form>` POST submissions** -- Forms are sent by the browser regardless of Origin header. A CSRF token becomes necessary.
   - Trigger: PR that includes `<form ... method="post">` in auth, checkout, or workspace routes
   - Action: File GitHub issue "Add CSRF token protection for form submissions" before merging
   - Implementation: Use Next.js built-in Server Actions (which do CSRF token validation internally) or add a token generation/verification step

2. **Adopting Server Actions** -- Next.js Server Actions use their own CSRF token mechanism internally.
   - Trigger: Adding files with `"use server"` directive in mutation paths
   - Action: Ensure `serverActions.allowedOrigins` is set in `next.config.ts` (already done for defense-in-depth)
   - Implementation: Next.js handles CSRF tokens automatically; no custom code needed

3. **Removing Origin header validation** -- If Origin validation is disabled or removed:
   - Trigger: Diff showing removal of `validateOrigin` calls or changes to `allowed-origins.ts`
   - Action: This is a security regression. Require explicit justification in PR description.
   - Implementation: Do not remove without adding an equivalent protection layer (e.g., CSRF tokens)

4. **Supporting non-browser clients** -- If mobile apps or third-party integrations access the API:
   - Trigger: Adding API documentation or SDKs for external clients
   - Action: Evaluate if Origin validation is still sufficient (it may not be for cross-origin requests from legitimate clients)
   - Implementation: CSRF tokens or API key-based auth become necessary

---

### 3. Cookie Configuration Review Triggers

Cookie security drifts when:

- Upgrading `@supabase/ssr` (defaults may change)
- Refactoring auth flow (e.g., adding custom session management)
- Changing deployment infrastructure (e.g., from Cloudflare to AWS CloudFront)

**Trigger Protocol:**

1. **After upgrading `@supabase/ssr`:**
   - Run: `npm audit` to check for `@supabase/ssr` updates
   - Review: Check the Supabase changelog for cookie option changes
   - Verify: Run `git diff middleware.ts lib/supabase/server.ts` to ensure cookie options are still present
   - Action: If options are missing, re-add with `SECURITY:` comments

2. **When refactoring auth flow:**
   - Trigger: Any PR that touches middleware or `lib/supabase/server.ts`
   - Checklist:
     - [ ] `cookieOptions` block present with all three options: `sameSite`, `secure`, `path`
     - [ ] Each option has a `// SECURITY:` comment explaining its purpose
     - [ ] `secure: process.env.NODE_ENV === "production"` (production-only HTTPS enforcement)
     - [ ] `sameSite: "lax"` (not "strict", which breaks legitimate navigation)
     - [ ] Cookie options applied consistently in both locations: middleware.ts and lib/supabase/server.ts

3. **When changing deployment:**
   - If HTTPS termination moves (e.g., from Cloudflare to direct origin):
     - Verify `secure: true` in production still appropriate
     - Check if `httpOnly` flag becomes necessary (only if Supabase client no longer needs JS access to tokens)
     - Test cookie transmission with browser DevTools (Network tab, Cookies section)

4. **Adjacent-config-audit pattern:**
   - When touching cookie options, **do not remove adjacent configuration**
   - Example of drift: A refactor touches `sameSite` but accidentally removes `secure` (both are in the `cookieOptions` block)
   - Prevention: Use `git diff --staged` before committing to verify the entire `cookieOptions` block is intact

---

### 4. Structural Enforcement: The Key Generalization

**Pattern:** When a security property should be "always present," enforce it via a test, not documentation.

#### Examples from This Fix

| Property | Where | Test |
|----------|-------|------|
| Origin validation | Every POST handler | `csrf-coverage.test.ts` scans all `route.ts` files |
| SameSite cookie | middleware.ts, lib/supabase/server.ts | Could add: snapshot test verifying both blocks contain `sameSite` |
| Secure cookie flag | Both locations | Could add: test verifying `secure: true` in production builds |

#### How to Write a Negative-Space Test

1. **Define the attack surface:** What should always be true?
   - "Every POST handler validates Origin"
   - "Every cookie-setting Supabase client has sameSite=lax"
   - "Every sensitive API route has rate-limiting"

2. **Write the invariant:** What code pattern indicates compliance?
   - Contains the string `validateOrigin`
   - Contains `cookieOptions: { sameSite: "lax"`
   - Calls `rateLimiter.check()`

3. **Enumerate exceptions:** What's intentionally exempt?
   - Stripe webhook (signature-based, not cookie-based)
   - Public routes (no auth needed)
   - Unauthenticated endpoints

4. **Fail the build:** Make it a test assertion
   - Vitest, Jest, or Cypress can all run filesystem scanning
   - Use `expect(unprotected).toEqual([])` -- fail if any routes missing protection

#### Benefits Over Alternatives

| Approach | Cost | Reliability | Scope |
|----------|------|-------------|-------|
| Documentation + code review | Zero upfront; high ongoing (human review) | Low (humans miss things) | Single PR only |
| Linting rule | High (tooling setup) | Medium (static analysis limited) | All files matching pattern |
| **Negative-space test** | **Low (30 lines of code)** | **High (always runs, always fails)** | **All POST handlers in app/api/** |

---

## Implementation Checklist for New Security Domains

Use this template when defending a new attack surface:

### Phase 1: Identify the Boundary

- [ ] What code paths can be exploited? (enumerate fully, not just the reported case)
- [ ] Which code paths are intentionally excluded? (document with justification)
- [ ] What's the minimal check that catches 100% of violations?

### Phase 2: Implement the Check

- [ ] Write a reusable utility function (e.g., `validateOrigin`, `checkRateLimit`)
- [ ] Add inline `SECURITY:` comments on security-critical config options
- [ ] Create a negative-space test that scans the entire codebase

### Phase 3: Enforce at Merge Time

- [ ] Add the test to CI (runs on every PR)
- [ ] Document exemptions in code with justification
- [ ] Train the team on the checklist (this document)

### Phase 4: Monitor & Iterate

- [ ] Track if new routes are added and caught by the test (prove it's working)
- [ ] If exemptions grow beyond 2-3 routes, revisit the design (exemptions are a code smell)
- [ ] After 1-2 quarters, review for false positives (overly broad test) or false negatives (bypassed checks)

---

## Real-World Attack Scenarios Prevented

### Scenario 1: Refactor Without Thinking

A developer refactors `api/keys/route.ts` to use a new Supabase helper function. Accidentally, they remove the call to `validateOrigin` while reorganizing the code.

**Without negative-space test:** Merged and deployed. The route is now vulnerable to CSRF.

**With negative-space test:** CI fails. The test reports "api/keys/route.ts POST handler missing validateOrigin". Developer adds it back before merge.

### Scenario 2: Copy-Paste Mistake

A developer copies `api/checkout/route.ts` to `api/webhooks/invoice/route.ts`. They forget to update it from webhook to authenticated route. They don't realize the Origin validation code is incorrect for a webhook.

**Without negative-space test:** Merged. The route is now vulnerable or rejects legitimate webhooks.

**With negative-space test:** Test fails. The new route must either have `validateOrigin` or be explicitly added to `EXEMPT_ROUTES` with justification. The developer realizes the route is a webhook and adds the justification, or fixes the code if it was supposed to be authenticated.

### Scenario 3: Cookie Config Drift During Upgrade

A developer upgrades `@supabase/ssr`. The new version introduces a different default for `secure`. The developer merges without checking if cookie options are still set.

**Without negative-space test:** The `secure` flag silently defaults to the new value, potentially breaking or weakening security.

**With negative-space test:** Could extend the test to snapshot cookie options and fail if they change unexpectedly.

---

## FAQ

### Q: Why not just use linting rules?

**A:** Linting is pattern-based. It can verify syntax (e.g., "this function exists in the file") but not semantics (e.g., "this function is called at the right time for the right reason"). A negative-space test understands your business logic and can fail with a message like "api/keys/route.ts POST handler missing validateOrigin — add protection or add to EXEMPT_ROUTES with justification."

### Q: What if a route legitimately doesn't need CSRF protection?

**A:** Add it to `EXEMPT_ROUTES` with a comment explaining why. The test still passes. The exemption is now documented and visible to future developers. If someone accidentally adds a new exempt route, they have to explicitly edit the list, which draws attention during code review.

### Q: How does this scale to multiple attack surfaces?

**A:** Create one test per attack surface. For example:

- `csrf-coverage.test.ts` — Origin validation
- `rate-limit-coverage.test.ts` — Rate limiting on expensive endpoints
- `authentication-coverage.test.ts` — All routes check auth before mutations

---

## See Also

- **Plan:** `/knowledge-base/project/plans/2026-03-20-fix-csrf-protection-state-mutating-api-routes-plan.md` — Full implementation details
- **Implementation:** `apps/web-platform/lib/auth/csrf-coverage.test.ts` — Actual test code
- **Learning:** `2026-03-20-security-fix-attack-surface-enumeration.md` — How to enumerate the full attack surface
- **Learning:** `2026-03-20-security-refactor-adjacent-config-audit.md` — How to prevent config drift via inline comments
