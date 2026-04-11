---
title: "fix: validateSiteId rejects single-label domains (require dot)"
type: fix
date: 2026-04-11
deepened: 2026-04-11
---

## Enhancement Summary

**Deepened on:** 2026-04-11
**Sections enhanced:** 3 (Acceptance Criteria, Test Scenarios, MVP)
**Research agents used:** repo-research-analyst, learnings-researcher

### Key Improvements

1. Fixed incorrect test assertions -- callers wrap `validateSiteId` errors into generic messages, so tests cannot assert `toContain("dot")`. Plan now passes through the specific error from `validateSiteId` to preserve diagnostic value.
2. Added edge case coverage for dots-only domains (`"..."`) as explicit non-goal.
3. Documented that the shell script (`provision-plausible-goals.sh`) has the same gap but is out of scope (env-var-driven, not agent-input).

### New Considerations Discovered

- All three callers (`plausibleCreateSite`, `plausibleAddGoal`, `plausibleGetStats`) discard the specific `validateSiteId()` error and replace it with a generic string. The original plan's test assertions would have failed at runtime.
- The shell script `provision-plausible-goals.sh:51` has the same `SAFE_ID_RE` without a dot check but is out of scope (reads from env vars set in CI, not agent input).

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
- [ ] Callers pass through the specific `validateSiteId` error (not a generic wrapper)

### Research Insights

**Error message passthrough (critical fix from deepen-plan):** All three callers currently discard the specific `validateSiteId()` error and replace it with generic messages:

- `plausibleCreateSite` (line 78): returns hardcoded `"Invalid domain format"`
- `plausibleAddGoal` (line 93): returns hardcoded `"Invalid site ID format"`
- `plausibleGetStats` (line 118): returns hardcoded `"Invalid site ID format"`

The new "Domain must contain at least one dot" message would be invisible to consumers. Fix: change callers to pass through `idError` directly. This preserves diagnostic value and makes tests assertable.

**Non-goals (explicit):**

- Dots-only domains (`"..."`, `"."`) pass both regex and dot check. This is acceptable -- the dot check is a minimum bar, not an RFC 1035 validator. Plausible's own API will reject nonsense domains.
- The shell script `provision-plausible-goals.sh:51` has the same `SAFE_ID_RE` without a dot check. Out of scope -- that script reads from CI environment variables, not agent input.

## Test Scenarios

- Given a valid multi-label domain like `example.com`, when `validateSiteId` is called, then it returns `null`
- Given a single-label hostname like `localhost`, when `validateSiteId` is called, then it returns an error message containing "dot"
- Given a path traversal attempt like `../admin`, when `validateSiteId` is called, then it returns the existing "Invalid site ID format" error (regex check fires first)
- Given a domain with leading/trailing dots like `.example.com` or `example.`, when `validateSiteId` is called, then it passes (the dot check is a minimum bar, not a full RFC validator)
- Given `plausibleCreateSite` called with `"localhost"`, when validation runs, then it returns `{ success: false, error: "Domain must contain at least one dot" }` and fetch is NOT called
- Given `plausibleAddGoal` called with site_id `"internal"`, when validation runs, then it returns `{ success: false, error: "Domain must contain at least one dot" }` and fetch is NOT called
- Given `plausibleGetStats` called with site_id `"test"`, when validation runs, then it returns `{ success: false, error: "Domain must contain at least one dot" }` and fetch is NOT called

### Research Insights

**Test assertion correctness:** After the caller fix (passing through `idError`), test assertions can correctly check `toContain("dot")`. Without the caller fix, all three `plausibleCreateSite`/`plausibleAddGoal`/`plausibleGetStats` tests would fail because the generic wrapper messages do not contain "dot".

## Context

The `SAFE_ID_RE` regex was introduced in PR #1921 (service automation) following the hardening pattern from the Plausible goals provisioning script. The regex correctly prevents path traversal but was not designed to enforce domain structure. This fix adds a minimal structural check without attempting full RFC 1035 validation.

### Research Insights

**Plausible site ID semantics:** In this codebase, Plausible site IDs are always real domains (e.g., `soleur.ai`). The CI workflows and shell scripts consistently document site_id as "typically the domain" (see `scheduled-weekly-analytics.yml:10`, `provision-plausible-goals.sh:9`). Single-label names have no legitimate use case.

## MVP

### apps/web-platform/server/service-tools.ts

**Change 1:** Add dot check to `validateSiteId()` (line 18):

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

**Change 2:** Pass through specific error in `plausibleCreateSite` (line 78):

```typescript
// BEFORE:
if (idError) return { success: false, error: `Invalid domain format` };

// AFTER:
if (idError) return { success: false, error: idError };
```

**Change 3:** Pass through specific error in `plausibleAddGoal` (line 93):

```typescript
// BEFORE:
if (idError) return { success: false, error: "Invalid site ID format" };

// AFTER:
if (idError) return { success: false, error: idError };
```

**Change 4:** Pass through specific error in `plausibleGetStats` (line 118):

```typescript
// BEFORE:
if (idError) return { success: false, error: "Invalid site ID format" };

// AFTER:
if (idError) return { success: false, error: idError };
```

### apps/web-platform/test/service-tools.test.ts

**Existing test adjustment:** The existing test "rejects invalid domain format" (line 91) asserts `toContain("Invalid domain")`. After the caller change, this test should now assert `toContain("Invalid site ID format")` since the regex error is "Invalid site ID format". Verify by running the test after the change.

**New test cases** -- add one in each `describe` block:

```typescript
// In describe("plausibleCreateSite"), after existing "rejects invalid domain format" test
test("rejects single-label domain (no dot)", async () => {
  globalThis.fetch = mockFetchResponse(200, {});
  const result = await plausibleCreateSite("test-api-key", "localhost");
  expect(result.success).toBe(false);
  expect(result.error).toContain("dot");
  expect(globalThis.fetch).not.toHaveBeenCalled();
});

// In describe("plausibleAddGoal"), after existing "rejects site_id with path traversal" test
test("rejects single-label site_id (no dot)", async () => {
  const result = await plausibleAddGoal("test-api-key", "internal", "event", "Signup");
  expect(result.success).toBe(false);
  expect(result.error).toContain("dot");
});

// In describe("plausibleGetStats"), after existing "rejects site_id with path traversal" test
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
- Learning: `knowledge-base/project/learnings/integration-issues/service-tool-registration-scope-guard-20260410.md`
