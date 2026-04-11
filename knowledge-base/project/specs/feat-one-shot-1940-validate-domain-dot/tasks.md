# Tasks: fix validateSiteId require dot

## Phase 1: Setup

- [x] 1.1 Rebase onto latest main to get `service-tools.ts` from PR #1921

## Phase 2: Core Implementation (TDD)

- [ ] 2.1 RED: Add failing tests for single-label domain rejection
  - [ ] 2.1.1 Add test in `plausibleCreateSite` block: rejects `"localhost"` (no dot)
  - [ ] 2.1.2 Add test in `plausibleAddGoal` block: rejects `"internal"` (no dot)
  - [ ] 2.1.3 Add test in `plausibleGetStats` block: rejects `"testhost"` (no dot)
  - [ ] 2.1.4 Run tests, confirm 3 new tests fail
- [ ] 2.2 GREEN: Implementation
  - [ ] 2.2.1 Add `if (!siteId.includes(".")) return "Domain must contain at least one dot"` after regex check in `validateSiteId()`
  - [ ] 2.2.2 Pass through `idError` in `plausibleCreateSite` (line 78: replace `"Invalid domain format"` with `idError`)
  - [ ] 2.2.3 Pass through `idError` in `plausibleAddGoal` (line 93: replace `"Invalid site ID format"` with `idError`)
  - [ ] 2.2.4 Pass through `idError` in `plausibleGetStats` (line 118: replace `"Invalid site ID format"` with `idError`)
  - [ ] 2.2.5 Update existing test "rejects invalid domain format" assertion if needed (was `toContain("Invalid domain")`, verify it still matches after passthrough change)
  - [ ] 2.2.6 Run tests, confirm all pass (new + existing)
- [ ] 2.3 REFACTOR: Verify no cleanup needed

## Phase 3: Verification

- [ ] 3.1 Run full test suite for `apps/web-platform`
- [ ] 3.2 Verify existing tests still pass (path traversal, timeout, etc.)
- [ ] 3.3 TypeScript type-check passes
