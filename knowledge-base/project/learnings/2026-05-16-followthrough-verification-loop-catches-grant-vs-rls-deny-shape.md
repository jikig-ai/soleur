---
title: Follow-through verification loop catches grant-vs-RLS deny-shape mismatch — dual-shape pattern is now canonical for table-deny tests
date: 2026-05-16
category: test-failures
tags:
  - tenant-isolation
  - rls
  - postgres
  - supabase
  - vitest-blind-class
  - 42501
  - pr-3244
  - follow-through
related:
  - "#3878 (this verification gate)"
  - "#3854 (PR-C — PR-C sibling-query tenant migration)"
  - "#3869 (PR-C deferrals tracker, items 1 + 6)"
  - 2026-05-06-tenant-jwt-rpc-grant-mismatch-vitest-blind
  - 2026-05-16-rls-deny-tests-payload-must-type-validate-or-they-pass-for-wrong-reason
---

# Context

Issue #3878 was the `follow-through` gate guarding prod promotion of PR-C (#3854 — `feat(runtime): PR-C sibling-query tenant migration`). The follow-through monitor required an operator to run the 11 PR-C tenant-isolation suites against dev Supabase with `TENANT_INTEGRATION_TEST=1` and report all green. The verification run produced a NOT-READY verdict:

```
Test Files  2 failed | 10 passed (12)
     Tests  3 failed | 42 passed | 10 skipped (55)
```

The 4 visible failures + 10 silently-skipped tests broke down into exactly two methodology classes documented in prior learnings — both prevented by the dual-shape pattern + service-role re-read poison-check architecture.

# Why this learning is worth writing

This isn't a new defect class — it's confirmation that the prior two learnings worked exactly as designed:

- The `TENANT_INTEGRATION_TEST=1` gate + per-suite breakdown surfaced the vitest-blind `skipped` trap from `2026-05-06-tenant-jwt-rpc-grant-mismatch-vitest-blind.md` (agent-runner's seed crashed on a check constraint, vitest reported all 10 tests as `skipped`).
- The grant-deny vs RLS-deny shape mismatch from `2026-05-16-rls-deny-tests-payload-must-type-validate-or-they-pass-for-wrong-reason.md` fired across three session-sync tests (dev returns `42501 permission denied for table users` because migration `006_restrict_tc_accepted_at_update.sql` deliberately revokes table-level UPDATE; tests asserted only canonical RLS-deny shape).

The fix matched both prior-learning prescriptions exactly:
- Seed value `Synthetic-${hex8}` → `Synthetic ${hex8}` (hyphen→space) satisfies migration 018's `custom_name ~ '^[a-zA-Z0-9 ]+$'` check.
- Three single-direction UPDATE tests + the symmetric test get a dual-shape accept block:
  ```ts
  if (error) { expect(error.code).toBe("42501"); expect(data).toBeNull(); }
  else       { expect(data).toEqual([]); }
  ```
- The service-role re-read poison-check (`expect(stillThere?.<col>).not.toEqual(poison)`) is unchanged on all three single-direction tests AND newly added to the symmetric test (which previously had no re-read on the write side).

The dual-shape pattern is now in **4 call sites within one file** plus the precedent at `cc-dispatcher.tenant-isolation.test.ts:151-155` (looser) and `api-usage` + `agent-runner` RPC-deny sites (substring-fallback form). Three coexisting forms encode different policy properties — pattern-recognition-specialist and code-quality-analyst both independently named helper extraction as the right consolidation path, deferred to #3869 item 1 (helper consolidation) where it spans multiple files.

# Mechanism summary

`public.users` has had table-level `UPDATE` revoked since migration 006 (re-granted only on `email`). Migrations 016 + 017 add RESTRICTIVE `WITH CHECK (col IS NOT DISTINCT FROM ...)` policies as defense-in-depth.

| State of grants | Postgres result on cross-tenant UPDATE | Wire shape |
|---|---|---|
| `GRANT UPDATE` revoked (current dev/prod) | `42501 permission denied for table users` | `{ error: { code: "42501", … }, data: null }` |
| `GRANT UPDATE` re-granted + RESTRICTIVE policy denies row | RLS-deny silent zero-rows | `{ error: null, data: [] }` |

**Both outcomes preserve "B's row unchanged"** — the deny mechanism differs but the load-bearing invariant is the service-role re-read on the poisoned column. The dual-shape `if (error) ... else ...` pattern makes the path-of-deny visible at the test runner: a failure log shows which branch fired, simplifying diagnosis of future regressions if grants ever shift.

# Validated existing prevention work

- `cq-test-fixtures-synthesized-only` — both edited tests still use synthetic emails matching the canonical `tenant-isolation-[a-f0-9]{16}@soleur.test` pattern. No real-user data introduced.
- The `TENANT_INTEGRATION_TEST=1` describe.skipIf gate fired correctly: tests that depend on dev Supabase secrets do not run in CI (item 6 in #3869 — gating CI workflow is deferred).
- `2026-05-06-tenant-jwt-rpc-grant-mismatch-vitest-blind` — the seed crash → vitest `skipped` trap is exactly the trap this follow-through monitor exists to catch. Caught 10 silent skips here.
- `2026-05-16-rls-deny-tests-payload-must-type-validate-or-they-pass-for-wrong-reason` — predicted the grant-vs-RLS shape mismatch and prescribed the dual-shape repair. Applied verbatim in this PR.

The post-merge follow-through gate (#3878) closes the validation loop. Without it, PR-C would have promoted to prod with a test methodology defect that would have masked any future RLS-policy regression on those columns.

# Session Errors

- **Misplaced verification worktree at `apps/web-platform/.worktrees/`.** First `git worktree add .worktrees/verify-3878-...` was created from a drifted CWD (earlier `cd apps/web-platform`). The Bash tool persists CWD across calls, but absolute paths do not. Recovery: `git worktree remove` + recreate at the absolute worktrees path. **Prevention:** always pass an absolute path to `git worktree add` — `git worktree add /abs/.worktrees/<name> ...`. Already covered by general CWD-drift learnings; restated for the worktree-creation surface specifically.

- **Stale local `main` in bare repo.** `git worktree add .worktrees/verify-... main` checked out commit `6617337d` (PR #3853) instead of `abcb3765` (PR-C merge). Cause: bare repo's local `main` ref was behind `origin/main` despite a successful `git fetch origin main` minutes earlier. Recovery: `git pull --ff-only origin main` inside the worktree. **Prevention:** when adding a verification worktree in a bare repo, prefer `git worktree add <abs-path> origin/main` (use the remote-tracking ref directly) over the local `main` shorthand. Same class as `hr-when-in-a-worktree-never-read-from-bare` but for the worktree-creation side.

- **`doppler secrets get --no-check` returned empty for all 4 valid secrets.** The `--no-check` flag combined with `--plain` produced empty output for SUPABASE_URL / NEXT_PUBLIC_SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY / SUPABASE_JWT_SECRET — even though `doppler secrets --only-names` listed all four. Re-running without `--no-check` resolved cleanly. Recovery: dropped the flag. **Prevention:** the canonical Doppler-presence probe is `doppler secrets get NAME -p PROJ -c CONFIG --plain` with no extra flags; verify list-existence with `doppler secrets --only-names | grep NAME` first if the `get` returns empty.

- **Issue body claimed "11 suites" but full glob finds 12.** PR-C added 11 new `*.tenant-isolation.test.ts` files; the legacy PR-B `agent-runner.tenant-isolation.test.ts` was already present and shares the `*.tenant-isolation.test.ts` glob. The discrepancy didn't cause real harm — both PR-B's 10 silently-skipped tests AND PR-C's 3 failed tests needed the methodology repair — but the issue body's scope-count and the glob's actual scope differed. **Prevention:** when verification commands use a glob, the verification report should enumerate the actual file count produced by the glob, not the count from the source PR's description. Re-count at verification time, not plan time.

# Out-of-scope confirmation

This PR deliberately did NOT:
- Add a positive UPDATE control on `users` RLS (per 2026-05-16 learning rule §4). Tracked in #3869 item 1; filed as `test.todo` in the same describe block so the gap is visible at runtime.
- Touch dev/prod grants on `public.users`. The current revoke-then-RESTRICTIVE-policy stack is intentional defense-in-depth (per migration 006 prose).
- Extract a helper for the dual-shape block. 4 call sites in one file is below the cross-file-helper threshold; #3869 item 1 lands the helper alongside the positive control.
- Touch the CI workflow that would automate this verification. Tracked in #3869 item 6.

# Workflow proposal

No new AGENTS.md rules needed. The two prior learnings (2026-05-06 + 2026-05-16) already encode the prevention surface; this PR is their execution loop firing as designed.

One narrow advisory worth surfacing: **when a follow-through monitor reports per-suite tally as "passed / skipped / failed", treat any `skipped` count > 0 as a P1 trap by default** — the 2026-05-06 vitest-blind class makes `skipped` look like "harmless gating" but is usually a `beforeAll` crash. Add to the follow-through monitor's report template: if `Tests N passed | M failed | K skipped` and K > 0, the report MUST enumerate WHICH suites skipped and inspect each one's `beforeAll`.
