# Tasks: fix validateSiteId require dot

## Phase 1: Setup

- [x] 1.1 Rebase onto latest main to get `service-tools.ts` from PR #1921

## Phase 2: Core Implementation (TDD)

- [x] 2.1 RED: Add failing tests for single-label domain rejection
  - [x] 2.1.1 Add test in `plausibleCreateSite` block: rejects `"localhost"` (no dot)
  - [x] 2.1.2 Add test in `plausibleAddGoal` block: rejects `"internal"` (no dot)
  - [x] 2.1.3 Add test in `plausibleGetStats` block: rejects `"testhost"` (no dot)
  - [x] 2.1.4 Run tests, confirm 3 new tests fail
- [x] 2.2 GREEN: Implementation
  - [x] 2.2.1 Add `if (!siteId.includes(".")) return "Domain must contain at least one dot"` after regex check in `validateSiteId()`
  - [x] 2.2.2 Pass through `idError` in `plausibleCreateSite` (line 78: replace `"Invalid domain format"` with `idError`)
  - [x] 2.2.3 Pass through `idError` in `plausibleAddGoal` (line 93: replace `"Invalid site ID format"` with `idError`)
  - [x] 2.2.4 Pass through `idError` in `plausibleGetStats` (line 118: replace `"Invalid site ID format"` with `idError`)
  - [x] 2.2.5 Update existing test "rejects invalid domain format" assertion if needed (was `toContain("Invalid domain")`, verify it still matches after passthrough change)
  - [x] 2.2.6 Run tests, confirm all pass (new + existing)
- [x] 2.3 REFACTOR: Verify no cleanup needed

## Phase 3: Verification

- [x] 3.1 Run full test suite for `apps/web-platform`
- [x] 3.2 Verify existing tests still pass (path traversal, timeout, etc.)
- [x] 3.3 TypeScript type-check passes (N/A -- no tsconfig in web-platform)
