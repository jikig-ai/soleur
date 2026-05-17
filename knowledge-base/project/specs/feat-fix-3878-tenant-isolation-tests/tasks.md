---
plan: knowledge-base/project/plans/2026-05-16-fix-tenant-isolation-tests-3878-plan.md
branch: feat-fix-3878-tenant-isolation-tests
issue: 3878
lane: single-domain
---

# Tasks — fix(tenant-isolation): unblock #3878

## Phase 1 — Setup

- [x] 1.1 Worktree + branch verified.
- [x] 1.2 Doppler `soleur/dev` reachable (SUPABASE_URL fetched, non-empty).
- [x] 1.3 Baseline confirmed via the pre-fix verification run (issue #3878 comment 4466926265).

## Phase 2 — Core Implementation

### 2.1 agent-runner seed fix

- [x] 2.1.1 Edited line 142: hyphen → space.
- [x] 2.1.2 agent-runner re-run: all 10 tests `passed` (now included in full glob below).

### 2.2 session-sync dual-shape

- [x] 2.2.1 Edited `:254` test — dual-shape applied.
- [x] 2.2.2 Edited `:270` test — dual-shape applied.
- [x] 2.2.3 Edited symmetric test — dual-shape + error destructure on both sides.
- [x] 2.2.4 session-sync re-run: all 5 tests `passed` (included in full glob below).

## Phase 3 — Verification

- [x] 3.1 Full glob re-run: `Test Files 12 passed (12); Tests 55 passed (55)` — 0 failed, 0 skipped.
- [x] 3.2 Vitest summary + per-suite tally captured for PR body.
- [x] 3.3 AC sweep (all passed):
      - AC1: `grep -n "custom_name: \`Synthetic " apps/web-platform/test/server/agent-runner.tenant-isolation.test.ts | wc -l` returns `1`.
      - AC2: `grep -cE 'expect\(\w+(\.code|Err\.code)\)\.toBe\("42501"\)' apps/web-platform/test/server/session-sync.tenant-isolation.test.ts` returns `3`.
      - AC3: `grep -cE 'error: (readErr|writeErr)' apps/web-platform/test/server/session-sync.tenant-isolation.test.ts` returns `2`.
      - AC4: `git diff main -- apps/web-platform/supabase/migrations/` is empty.
      - AC5: `git diff main -- apps/web-platform/supabase/migrations/ | grep -iE "^\+.*GRANT|^-.*GRANT"` is empty.
      - AC6: `git diff main --name-only -- .github/` is empty.
      - AC7: `git diff main --name-only | grep -E "apps/web-platform/(server|lib)/"` is empty.

## Phase 4 — Lifecycle

- [ ] 4.1 Run `skill: soleur:compound` to capture any new session learnings (the dual-shape pattern's first cited use; the agent-runner seed-vs-migration trap if not already covered by 2026-05-06 vitest-blind).
- [ ] 4.2 Commit with a Conventional Commit message matching the PR title (`fix(tenant-isolation): unblock #3878 — accept grant-deny shape + fix team_names seed`).
- [ ] 4.3 Push + open PR via `skill: commit-commands:commit-push-pr`. PR body must include the per-suite tally, `Closes #3878`, reference to PR-C (#3854) and the verification comment URL, and links to both learnings.
- [ ] 4.4 After PR opens, request review and run `skill: soleur:ship`.
