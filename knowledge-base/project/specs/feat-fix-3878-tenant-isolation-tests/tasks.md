---
plan: knowledge-base/project/plans/2026-05-16-fix-tenant-isolation-tests-3878-plan.md
branch: feat-fix-3878-tenant-isolation-tests
issue: 3878
lane: single-domain
---

# Tasks — fix(tenant-isolation): unblock #3878

## Phase 1 — Setup

- [ ] 1.1 Verify worktree is `/home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-fix-3878-tenant-isolation-tests` and branch is `feat-fix-3878-tenant-isolation-tests`. Single Bash call: `cd <abs-worktree> && git branch --show-current && pwd`.
- [ ] 1.2 Confirm Doppler `soleur/dev` is reachable: `doppler secrets get SUPABASE_URL -p soleur -c dev --plain | head -c 30` returns a non-empty URL string (do NOT log the value).
- [ ] 1.3 Baseline the failing run to confirm the verification comment's reproduction:
      `cd <abs-worktree>/apps/web-platform && doppler run -p soleur -c dev -- env TENANT_INTEGRATION_TEST=1 ./node_modules/.bin/vitest run test/server/agent-runner.tenant-isolation.test.ts test/server/session-sync.tenant-isolation.test.ts --reporter=verbose`.
      Expected: `agent-runner` suite shows 10 skipped, `session-sync` shows 3 failed / 2 passed.

## Phase 2 — Core Implementation

### 2.1 agent-runner seed fix

- [ ] 2.1.1 Edit `apps/web-platform/test/server/agent-runner.tenant-isolation.test.ts:142` — replace the hyphen in `` `Synthetic-${user.id.slice(0, 8)}` `` with a space: `` `Synthetic ${user.id.slice(0, 8)}` ``. No other changes to this file.
- [ ] 2.1.2 Re-run JUST the agent-runner suite: `cd apps/web-platform && doppler run -p soleur -c dev -- env TENANT_INTEGRATION_TEST=1 ./node_modules/.bin/vitest run test/server/agent-runner.tenant-isolation.test.ts --reporter=verbose`. All 10 tests must report `passed`. If any still skip, the seed throws elsewhere — read the actual Postgres error before any further edit.

### 2.2 session-sync dual-shape

- [ ] 2.2.1 Edit `apps/web-platform/test/server/session-sync.tenant-isolation.test.ts` lines 178-194 (`:254 recordKbSyncHistory UPDATE`) — replace the rigid `expect(error).toBeNull(); expect(data).toEqual([])` pair with the dual-shape block from plan Phase 2. Keep the service-role re-read poison-check intact.
- [ ] 2.2.2 Edit lines 196-212 (`:270 updateLastSynced`) — same dual-shape pattern; the column is `repo_last_synced_at`, the re-read assertion stays `not.toBe(poison)`.
- [ ] 2.2.3 Edit lines 214-227 (symmetric) — three sub-fixes: (a) destructure `error` on the read side, (b) destructure `error` on the write side, (c) apply dual-shape to both sides. The pre-fix bug is that the write side destructures only `data: writeByB`, surfacing `expected null to deeply equal []` when Postgres returns `42501`.
- [ ] 2.2.4 Re-run just the session-sync suite: `cd apps/web-platform && doppler run -p soleur -c dev -- env TENANT_INTEGRATION_TEST=1 ./node_modules/.bin/vitest run test/server/session-sync.tenant-isolation.test.ts --reporter=verbose`. All 5 tests must report `passed`.

## Phase 3 — Verification

- [ ] 3.1 Full glob re-run (the verification command from #3878 issue body):
      `cd apps/web-platform && doppler run -p soleur -c dev -- env TENANT_INTEGRATION_TEST=1 ./node_modules/.bin/vitest run test/server/*.tenant-isolation.test.ts --reporter=verbose`. Expected: `Test Files 12 passed (12); Tests 55 passed (55)` and zero skipped, zero failed.
- [ ] 3.2 Capture the vitest summary line verbatim and the per-suite tally for the PR body. The plan's Verification section has the canonical table — paste it into the PR with the post-fix column populated.
- [ ] 3.3 AC sweep (run each in a single Bash chain):
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
