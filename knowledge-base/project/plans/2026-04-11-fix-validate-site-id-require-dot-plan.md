---
title: "fix: validateSiteId rejects single-label domains (require dot)"
type: fix
date: 2026-04-11
---

# fix: validateSiteId rejects single-label domains (require dot)

`plausibleCreateSite` validates domain format with `SAFE_ID_RE` (`/^[a-zA-Z0-9._-]+$/`) which accepts single-label hostnames like `localhost` or `internal-host`. While not a security vulnerability, an agent could be manipulated into provisioning nonsense Plausible sites against single-label names that will never receive real traffic.

**Location:** `apps/web-platform/server/service-tools.ts` -- `validateSiteId()` function (line 18)

**Root cause:** `SAFE_ID_RE` prevents path traversal but does not enforce domain structure. Any string matching `[a-zA-Z0-9._-]+` passes, including `localhost`, `test`, or `notadomain`.

## Acceptance Criteria

- [ ] `validateSiteId("example.com")` returns `null` (valid)
- [ ] `validateSiteId("sub.example.com")` returns `null` (valid)
- [ ] `validateSiteId("localhost")` returns error string containing "dot"
- [ ] `validateSiteId("notadomain")` returns error string containing "dot"
- [ ] `validateSiteId("../admin")` still returns error (existing path traversal check preserved)
- [ ] Existing tests continue to pass unchanged
- [ ] New tests cover single-label rejection for all three public functions (`plausibleCreateSite`, `plausibleAddGoal`, `plausibleGetStats`)

## Test Scenarios

- Given a valid multi-label domain like `example.com`, when `validateSiteId` is called, then it returns `null`
- Given a single-label hostname like `localhost`, when `validateSiteId` is called, then it returns an error message containing "dot"
- Given a path traversal attempt like `../admin`, when `validateSiteId` is called, then it returns the existing "Invalid site ID format" error (regex check fires first)
- Given a domain with leading/trailing dots like `.example.com` or `example.`, when `validateSiteId` is called, then it passes (the dot check is a minimum bar, not a full RFC validator)
- Given `plausibleCreateSite` called with `"localhost"`, when validation runs, then it returns `{ success: false, error: "..." }` and fetch is NOT called
- Given `plausibleAddGoal` called with site_id `"internal"`, when validation runs, then it returns `{ success: false, error: "..." }` and fetch is NOT called
- Given `plausibleGetStats` called with site_id `"test"`, when validation runs, then it returns `{ success: false, error: "..." }` and fetch is NOT called

## Context

The `SAFE_ID_RE` regex was introduced in PR #1921 (service automation) following the hardening pattern from the Plausible goals provisioning script. The regex correctly prevents path traversal but was not designed to enforce domain structure. This fix adds a minimal structural check without attempting full RFC 1035 validation.

## MVP

### apps/web-platform/server/service-tools.ts

Add one check after the existing regex validation in `validateSiteId()`:

```typescript
function validateSiteId(siteId: string): string | null {
  if (!SAFE_ID_RE.test(siteId)) {
    return "Invalid site ID format";
  }
  if (!siteId.includes(".")) {
    return "Domain must contain at least one dot";
  }
  return null;
}
```

### apps/web-platform/test/service-tools.test.ts

Add test cases for single-label rejection in each `describe` block:

```typescript
// In describe("plausibleCreateSite")
test("rejects single-label domain (no dot)", async () => {
  globalThis.fetch = mockFetchResponse(200, {});
  const result = await plausibleCreateSite("test-api-key", "localhost");
  expect(result.success).toBe(false);
  expect(result.error).toContain("dot");
  expect(globalThis.fetch).not.toHaveBeenCalled();
});

// In describe("plausibleAddGoal")
test("rejects single-label site_id (no dot)", async () => {
  const result = await plausibleAddGoal("test-api-key", "internal", "event", "Signup");
  expect(result.success).toBe(false);
  expect(result.error).toContain("dot");
});

// In describe("plausibleGetStats")
test("rejects single-label site_id (no dot)", async () => {
  const result = await plausibleGetStats("test-api-key", "testhost", "day");
  expect(result.success).toBe(false);
  expect(result.error).toContain("dot");
});
```

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- code-quality hardening of an internal validation function.

## References

- Issue: #1940
- PR #1921 (introduced `service-tools.ts`)
- Learning: `knowledge-base/project/learnings/2026-03-13-plausible-goals-api-provisioning-hardening.md`
- Learning: `knowledge-base/project/learnings/2026-04-02-plausible-api-response-validation-prevention.md`
