---
title: "fix(tenant-isolation): unblock #3878 — accept grant-deny shape + fix team_names seed"
date: 2026-05-16
type: bug-fix
lane: single-domain
status: ready-for-work
issue: 3878
related_pr: 3854
classification: test-fix-only
risk: low
requires_cpo_signoff: false
---

# fix(tenant-isolation): unblock #3878 — accept grant-deny shape + fix team_names seed

## Overview

Issue #3878 is the post-merge follow-through gate that PR-C (#3854 — `feat(runtime): PR-C sibling-query tenant migration`) needs cleared before prod promotion. The
2026-05-16 verification run (comment 4466926265) executed the full
`apps/web-platform/test/server/*.tenant-isolation.test.ts` glob against dev
Supabase under `TENANT_INTEGRATION_TEST=1` and produced a **NOT READY** verdict:

```
Test Files  2 failed | 10 passed (12)
     Tests  3 failed | 42 passed | 10 skipped (55)
```

Two test files account for all 4 visible failures and the 10 silently-skipped
tests. Neither failure indicates a real isolation regression — both are
test-methodology defects of the exact two classes documented in the most
recent tenant-isolation learnings:

1. **`agent-runner.tenant-isolation.test.ts`** (PR-B legacy suite, 10 tests
   silently `skipped`) — `beforeAll` seed inserts a `team_names` row whose
   `custom_name` contains a hyphen, violating the load-bearing migration
   constraint `team_names_custom_name_check1` (`custom_name ~ '^[a-zA-Z0-9 ]+$'`,
   no hyphen). The seed throws `23514`, vitest marks every test in the suite
   `skipped`. This is the **vitest-blind trap** described in
   `2026-05-06-tenant-jwt-rpc-grant-mismatch-vitest-blind.md` and which the
   `TENANT_INTEGRATION_TEST=1` gate itself was built to surface — the issue's
   `follow-through` script ran exactly to catch this class.

2. **`session-sync.tenant-isolation.test.ts`** (3 tests, all `users` UPDATEs) —
   The assertion shape is the canonical RLS-deny shape (`error === null && data === []`),
   but dev Supabase returns `42501 permission denied for table users` because
   the `authenticated` role lacks `GRANT UPDATE ON public.users` (a deliberately
   tighter grant than RLS-only deny — Postgres's hint literally proposes the
   grant: `GRANT UPDATE ON public.users TO authenticated;`). Both are
   load-bearing safe; the test under-specifies "deny" as RLS-deny only. The
   third failure is the same class compounded with a destructure bug — the
   symmetric test at `:214` destructures `data` without `error`, so when
   Postgres returns `42501` `data` is `null` and the assertion fails with
   `expected null to deeply equal []` — a misleading message that hides the
   real reason. This is the methodology gap documented in
   `2026-05-16-rls-deny-tests-payload-must-type-validate-or-they-pass-for-wrong-reason.md`
   ("a deny-test must send a payload that would have SUCCEEDED if the gate
   under test were removed" — generalized to "must accept any deny shape that
   the live grant + policy stack can produce, and rely on the service-role
   re-read for the actual safety property").

This plan ships test-file edits ONLY. **No migration changes. No runtime code
changes. No GRANT changes. No CI workflow changes.** The dev/prod grant model
is preserved exactly; the migration's check constraint stays load-bearing on
the prod schema.

## User-Brand Impact

**If this lands broken, the user experiences:** No direct user-facing impact —
this is a test fix. The transitive impact is that PR-C (#3854, already merged
to `main`) cannot be promoted to prod traffic until #3878 is cleared, so any
prod-runtime change downstream of the sibling-query tenant migration stays
gated.

**If this leaks, the user's data is exposed via:** N/A. This PR adds no new
data flow, no new endpoint, no new auth path. The tests it edits cover an
isolation property; the grant-deny accommodation does not relax any deny —
it adds a SECOND accepted deny shape (the stricter one) on top of the
existing RLS-deny shape. The service-role re-read poison-check (`expect(stillThere?.<col>).not.toEqual(poison)`)
remains the load-bearing safety assertion.

**Brand-survival threshold:** `none`.

**Reason for `none`:** This PR edits only `*.test.ts` files. Sensitive-path
preflight (see `plugins/soleur/skills/preflight/SKILL.md` Check 6) will scope
this PR out automatically (test-only diff, no `server/**` or `lib/**` runtime
touch, no schema change, no GRANT change). The actual tenant-isolation
property is owned by PR-C (#3854) and the migrations/RLS policies it consumes
— not by this PR.

## Research Reconciliation — Spec vs. Codebase

The issue body + the verification comment present a complete and correct
diagnosis. Two facts were re-verified at plan time:

| Claim | Reality (verified at plan time) | Plan response |
|---|---|---|
| Migration `018_team_names.sql:11` declares `check (custom_name ~ '^[a-zA-Z0-9 ]+$')` (alphanumeric + spaces, no hyphen) | Confirmed by reading the file. Lines 10-12 are: `custom_name text not null check (char_length(custom_name) between 1 and 30) check (custom_name ~ '^[a-zA-Z0-9 ]+$'),`. | Replace the seed's hyphen with a space — no migration touch. |
| Seed at `agent-runner.tenant-isolation.test.ts:~142` is `custom_name: \`Synthetic-${user.id.slice(0, 8)}\`` | Confirmed at line 142 — exact text matches. The surrounding seed loop iterates over both `userA` and `userB` so the value is per-tenant by construction; replacing `-` with ` ` keeps uniqueness. | Edit line 142 only. The unique constraint is `(user_id, leader_id)` not `custom_name`, so collision is impossible regardless. |
| `session-sync.tenant-isolation.test.ts` has 3 failing UPDATE tests at `:178`, `:196`, `:214` | Confirmed by reading the file: line 178 = `:254 recordKbSyncHistory UPDATE`, line 196 = `:270 updateLastSynced`, line 214 = symmetric write-side. The symmetric test destructures only `data: writeByB` (line 221) without `error` — the latent bug the verification comment flagged. | Edit all three tests to accept either deny shape + add `error` to the symmetric test's destructure. |
| Symmetric test `:214` read side `expect(readByB).toEqual([])` may also fail under grant-deny semantics | SELECT on `users` does NOT require `GRANT SELECT ON public.users TO authenticated` to be revoked — RLS-deny on SELECT returns `error=null, data=[]` because the `authenticated` role has the `SELECT` grant; only the row-filter denies. The verification comment did not list the read side as failing. | Conservative dual-shape on the read side too (cheap, matches the methodology rule). |
| PR-C (#3854) is merged | Confirmed: `gh pr view 3854` → `state: MERGED`. The fix lands against `main`. | Targets `main`. Branch `feat-fix-3878-tenant-isolation-tests`. |
| Referenced learnings exist | Confirmed: `knowledge-base/project/learnings/2026-05-06-tenant-jwt-rpc-grant-mismatch-vitest-blind.md` (97 LoC) and `knowledge-base/project/learnings/2026-05-16-rls-deny-tests-payload-must-type-validate-or-they-pass-for-wrong-reason.md` (103 LoC). | Plan body and PR body cite both. |
| Verification command from issue body | Confirmed verbatim from #3878 issue body + verification comment 4466926265: `doppler run -p soleur -c dev -- env TENANT_INTEGRATION_TEST=1 ./node_modules/.bin/vitest run test/server/*.tenant-isolation.test.ts --reporter=verbose` from `apps/web-platform/`. | Plan uses this command verbatim. |
| Issue #3869 item 6 (CI workflow) | Confirmed open: "review: PR-C (#3244 §2) deferrals — helper consolidation, CI tenant-integration job, mock dedup, sentinel sweep, ADR". Item 6 explicitly deferred. | Plan does NOT touch CI workflows. Explicitly listed in Out of Scope. |

No spec drift. No paraphrase-without-verification issues.

## Files to Edit

1. `apps/web-platform/test/server/agent-runner.tenant-isolation.test.ts`
   - **Line 142** only. Replace `` `Synthetic-${user.id.slice(0, 8)}` `` with
     `` `Synthetic ${user.id.slice(0, 8)}` `` (hyphen → space). No other
     changes. The fixture remains unique-per-tenant (the user.id slice differs
     per-user), human-readable, and constraint-compliant.

2. `apps/web-platform/test/server/session-sync.tenant-isolation.test.ts`
   - **Lines 178-194** (`:254 recordKbSyncHistory UPDATE`): destructure `error`
     alongside `data` (already done), and replace the rigid
     `expect(error).toBeNull(); expect(data).toEqual([])` pair with a
     dual-shape accept block. Keep the service-role re-read poison-check
     intact — that is the real safety assertion.
   - **Lines 196-212** (`:270 updateLastSynced`): same dual-shape pattern.
     Keep the service-role re-read poison-check.
   - **Lines 214-227** (symmetric): three sub-fixes.
     (a) Destructure `error` alongside `data` for both the read and write
         sides (the write side currently destructures `data: writeByB`
         only — this is the latent bug that produces `expected null to deeply
         equal []` when Postgres returns `42501`).
     (b) Apply the dual-shape pattern on the write side.
     (c) Apply the dual-shape pattern on the read side as well (defensive —
         the read side currently passes per the verification comment, but
         the methodology rule says the test should not over-specify the deny
         shape; the cost is 4 lines).

## Files to Create

None.

## Implementation

### Phase 1 — agent-runner seed fix

Edit `apps/web-platform/test/server/agent-runner.tenant-isolation.test.ts:142`:

```diff
- custom_name: `Synthetic-${user.id.slice(0, 8)}`,
+ custom_name: `Synthetic ${user.id.slice(0, 8)}`,
```

Rationale:
- The migration's check `custom_name ~ '^[a-zA-Z0-9 ]+$'` is load-bearing on
  prod schema (it constrains what founders can enter into the team-naming UI,
  validated at the SQL boundary). Widening it would silently accept hyphens
  in production user-facing data. **Do not touch the migration.**
- A space is the minimum-perturbation fix: the value is still 9 chars
  (`"Synthetic " + 8 hex chars`), within the 1-30 range, unique per tenant
  by virtue of the differing user.id slice, and human-readable in test logs.
- The unique constraint on `team_names` is `(user_id, leader_id)`. The
  `custom_name` value is not in any unique index. Collision is impossible.

### Phase 2 — session-sync dual-shape accommodation

Edit `apps/web-platform/test/server/session-sync.tenant-isolation.test.ts`.

For the two single-direction UPDATE tests (`:254` at file line 178 and `:270`
at file line 196), replace the rigid deny-shape assertion with the canonical
dual-shape pattern documented in
`knowledge-base/project/learnings/2026-05-16-rls-deny-tests-payload-must-type-validate-or-they-pass-for-wrong-reason.md`:

```ts
// Lines 178-194 — `:254 recordKbSyncHistory UPDATE`
test("`:254` recordKbSyncHistory UPDATE — A cannot UPDATE B's kb_sync_history", async () => {
  const poison = [{ date: "1999-01-01", count: 9999 }];
  const { data, error } = await aClient
    .from("users")
    .update({ kb_sync_history: poison })
    .eq("id", userB.id)
    .select("id");

  // Accept either RLS-deny (error=null, data=[]) or grant-deny (42501) —
  // both are load-bearing safe. See learning
  // 2026-05-16-rls-deny-tests-payload-must-type-validate-or-they-pass-for-wrong-reason.
  if (error) {
    expect(error.code).toBe("42501");
    expect(data).toBeNull();
  } else {
    expect(data).toEqual([]);
  }

  // Safety property — service-role re-read confirms B's row is unchanged.
  // This is the actual assertion; the deny-shape block above only asserts
  // that the DENY MECHANISM fired, not the policy outcome.
  const { data: stillThere } = await service
    .from("users")
    .select("kb_sync_history")
    .eq("id", userB.id)
    .maybeSingle();
  expect(stillThere?.kb_sync_history).not.toEqual(poison);
});
```

The `:270` test at file line 196 follows the same shape — only the column
under poison (`repo_last_synced_at`) and the poison value
(`"1999-01-01T00:00:00.000Z"`) differ. The re-read assertion stays
`expect(stillThere?.repo_last_synced_at).not.toBe(poison)` (already correct).

For the symmetric test at file line 214, apply the dual-shape pattern AND
destructure `error` on both sides:

```ts
test("symmetric: B cannot read or write A's users row either", async () => {
  // Read side — SELECT does not require a UPDATE grant; RLS-deny is the
  // expected path. Still accept either shape for methodology hygiene.
  const { data: readByB, error: readErr } = await bClient
    .from("users")
    .select("github_installation_id, kb_sync_history, repo_last_synced_at")
    .eq("id", userA.id);
  if (readErr) {
    expect(readErr.code).toBe("42501");
    expect(readByB).toBeNull();
  } else {
    expect(readByB).toEqual([]);
  }

  // Write side — same dual-shape; this is the path that currently fails
  // because Postgres returns 42501 from the missing UPDATE grant, and the
  // pre-fix test destructured only data, surfacing the misleading
  // "expected null to deeply equal []" message.
  const { data: writeByB, error: writeErr } = await bClient
    .from("users")
    .update({ repo_last_synced_at: "1999-01-01T00:00:00.000Z" })
    .eq("id", userA.id)
    .select("id");
  if (writeErr) {
    expect(writeErr.code).toBe("42501");
    expect(writeByB).toBeNull();
  } else {
    expect(writeByB).toEqual([]);
  }
});
```

### Why dual-shape, not single-shape rewrite

The 2026-05-16 learning emits two rules:

1. **Methodology rule:** a deny-test must accept ANY deny shape that the live
   grant + policy stack can produce. Single-shape assertions over-specify the
   policy and turn an alternate-deny (grant-level) into a false fail.
2. **Safety rule:** the load-bearing assertion is the service-role re-read —
   "the row didn't change" — NOT the request-side shape. Single-shape can
   still mask the safety property if it gets the shape wrong.

A unilateral switch to "expect 42501 always" would invert the failure mode:
the test would silently false-pass against any future grant alignment
(e.g., dev/prod grants reconciled to GRANT-UPDATE-then-RLS-deny). Dual-shape
survives both grant configurations + the future grant alignment work
without further edit.

## Verification (MUST run before opening PR)

Run from the worktree root in a single Bash call so CWD is per-call-absolute:

```bash
cd /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-fix-3878-tenant-isolation-tests/apps/web-platform && \
  doppler run -p soleur -c dev -- env TENANT_INTEGRATION_TEST=1 \
  ./node_modules/.bin/vitest run test/server/*.tenant-isolation.test.ts --reporter=verbose
```

This is the exact command from issue #3878's body and the 2026-05-16
verification comment, anchored to the worktree path per
`hr-when-in-a-worktree-never-read-from-bare`.

### Pass criteria — must hold ALL of these

1. **All 12 `.tenant-isolation.test.ts` suites must report `passed`.** Not
   `skipped`, not `failed`. The 11 PR-C suites AND the legacy
   `agent-runner.tenant-isolation.test.ts` after the seed fix.

2. **Vitest summary line shows `Test Files 0 failed | 12 passed (12)` and
   `Tests 0 failed | 0 skipped`** for the tenant-isolation glob. The pre-fix
   summary was `Test Files 2 failed | 10 passed (12); Tests 3 failed | 42 passed | 10 skipped (55)`.
   Post-fix expected: `Test Files 12 passed (12); Tests 55 passed (55)`
   (the 10 previously-skipped agent-runner tests join the passing count;
   the 3 previously-failed session-sync tests flip to passed).

3. **Per-suite re-run tally (paste into PR body) — all green:**

   | # | Suite | Pre-fix | Post-fix expected |
   |---|---|---|---|
   | 1 | `agent-runner.tenant-isolation.test.ts` | skipped (10 tests) | passed (10/10) |
   | 2 | `api-messages.tenant-isolation.test.ts` | passed (4/4) | passed (4/4) |
   | 3 | `api-usage.tenant-isolation.test.ts` | passed (4/4) | passed (4/4) |
   | 4 | `cc-dispatcher.tenant-isolation.test.ts` | passed (3/3) | passed (3/3) |
   | 5 | `conversation-writer.tenant-isolation.test.ts` | passed (4/4) | passed (4/4) |
   | 6 | `conversations-tools.tenant-isolation.test.ts` | passed (6/6) | passed (6/6) |
   | 7 | `current-repo-url.tenant-isolation.test.ts` | passed (2/2) | passed (2/2) |
   | 8 | `kb-document-resolver.tenant-isolation.test.ts` | passed (2/2) | passed (2/2) |
   | 9 | `kb-route-helpers.tenant-isolation.test.ts` | passed (3/3) | passed (3/3) |
   | 10 | `lookup-conversation-for-path.tenant-isolation.test.ts` | passed (3/3) | passed (3/3) |
   | 11 | `session-sync.tenant-isolation.test.ts` | 3 failed / 2 passed | passed (5/5) |
   | 12 | `ws-handler.tenant-isolation.test.ts` | passed (6/6) | passed (6/6) |

### Failure-mode rules (do not paper over)

The two learnings are explicit about the failure modes the fix must NOT
silently introduce:

- **If any suite still skips:** the seed fix is wrong. Re-read the actual
  Postgres error (`select pg_get_constraintdef(oid) from pg_constraint where conname = 'team_names_custom_name_check1'`)
  before editing. Do not chase the symptom; do not delete the check from the
  migration; do not delete the seed step.

- **If any test still fails:** the deny-shape fix is wrong. Re-read the
  actual error object Postgres returned (`console.log(error)` once
  temporarily, do not commit the log). Do not switch to `try/catch`,
  do not loosen `not.toEqual(poison)`, do not change the service-role
  re-read query.

- **If the `:178`, `:196`, or `:214` test passes for a wrong reason:**
  This is the 2026-05-16 trap. Verify by temporarily commenting out the
  re-read assertion and confirming the deny-shape block alone does not
  pass — the safety property must remain the load-bearing assertion.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1: `apps/web-platform/test/server/agent-runner.tenant-isolation.test.ts:142`
      contains `` `Synthetic ${user.id.slice(0, 8)}` `` (space, not hyphen).
      Verify via: `grep -n "custom_name: \`Synthetic " apps/web-platform/test/server/agent-runner.tenant-isolation.test.ts`
      returns exactly 1 line at line 142.
- [ ] AC2: `apps/web-platform/test/server/session-sync.tenant-isolation.test.ts`
      contains exactly 3 `expect(error.code).toBe("42501")` assertions —
      one in each of the 3 fixed tests. Verify via:
      `grep -cE 'expect\(\w+(\.code|Err\.code)\)\.toBe\("42501"\)' apps/web-platform/test/server/session-sync.tenant-isolation.test.ts`
      returns `3`.
- [ ] AC3: The symmetric test at line 214 destructures both `data` AND `error`
      on both the read and write sides. Verify via:
      `grep -cE '(error: (readErr|writeErr))' apps/web-platform/test/server/session-sync.tenant-isolation.test.ts`
      returns `2`.
- [ ] AC4: Migration `apps/web-platform/supabase/migrations/018_team_names.sql`
      is **unchanged** by this PR. Verify via:
      `git diff main -- apps/web-platform/supabase/migrations/` is empty.
- [ ] AC5: No `GRANT` statement is added or removed in any migration by this PR.
      Verify via:
      `git diff main -- apps/web-platform/supabase/migrations/ | grep -iE "^\+.*GRANT|^-.*GRANT"` is empty.
- [ ] AC6: No CI workflow file is touched by this PR (deferred to #3869 item 6).
      Verify via: `git diff main --name-only -- .github/` is empty.
- [ ] AC7: No file under `apps/web-platform/server/` or `apps/web-platform/lib/`
      is touched (test-only change). Verify via:
      `git diff main --name-only | grep -E "apps/web-platform/(server|lib)/"` is empty.
- [ ] AC8: Vitest run produces `Test Files 12 passed (12); Tests 55 passed (55)`
      for the tenant-isolation glob (or, if vitest reports a different total
      from added afterEach context, the summary must still show `0 failed | 0 skipped`
      and 12 passing files). Paste the literal vitest summary line into the
      PR body.
- [ ] AC9: PR body includes the per-suite re-run tally table from the
      Verification section with all 12 rows marked passed.
- [ ] AC10: PR body uses `Closes #3878` (NOT `Ref #3878`) — this is a test-fix
      PR whose merge alone resolves the follow-through gate; no post-merge
      operator action is needed. Per `wg-use-closes-n-in-pr-body-not-title-to`.

### Post-merge (operator) — none

This PR's merge is the resolution. No post-merge `gh issue close`, no
terraform apply, no migration verify, no Doppler config touch. The
`follow-through` daily monitor will pick up the closed state on its next
sweep.

## Domain Review

**Domains relevant:** Engineering (test methodology only).

No cross-domain implications. No product surface touched, no legal/compliance
surface, no infra, no schema, no GRANT. CTO-style review covered by the
plan-review pass below.

## Open Code-Review Overlap

Ran the check against open `code-review`-labeled issues for the two file
paths in `## Files to Edit`. No matches:

```bash
gh issue list --label code-review --state open \
  --json number,title,body --limit 200 > /tmp/open-review-issues.json
for path in \
  apps/web-platform/test/server/agent-runner.tenant-isolation.test.ts \
  apps/web-platform/test/server/session-sync.tenant-isolation.test.ts ; do
  jq -r --arg path "$path" '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"' /tmp/open-review-issues.json
done
```

Returns empty. No fold-in/acknowledge/defer decision needed.

## Out of Scope

These are explicitly NOT touched by this PR:

1. **CI workflow to run tenant-isolation in automation** — issue #3869 item 6.
   Deferred; needs Doppler dev-Supabase secrets injection into CI. Filed,
   tracked, owned by a separate cycle. This PR's verification stays
   operator-local against dev Supabase, exactly as #3878 prescribes.

2. **Aligning dev/prod grants on `public.users`** — deliberately not touched.
   The current state (dev returns `42501` because `GRANT UPDATE` is absent;
   prod presumably the same) is LOAD-BEARING SAFE. A grant alignment that
   relaxed dev to "RLS only" would expand the attack surface; an alignment
   that tightened prod to match dev would be a separate migration with its
   own RLS-policy implications. Either direction is a CTO/CPO-owned decision,
   not a test-fix concern.

3. **Any other tenant-isolation suite changes** — the 9 PR-C suites that
   passed remain untouched. The mock-dedup work and helper consolidation
   from PR-C are also tracked in #3869 (items 1, 3, 4, 5) and are out of
   scope here.

4. **`agent-runner.tenant-isolation.test.ts` modernization** — the PR-B
   legacy suite uses an older fixture shape than the PR-C suites. Migrating
   it to share PR-C's helpers is a separate refactor (already partially
   tracked in #3869 item 1). This PR fixes only the one seed bug.

5. **The migration's check constraint** — the `^[a-zA-Z0-9 ]+$` regex is
   load-bearing on prod (it constrains user-facing team-name input). Widening
   it to accept hyphens is a product decision, not a test-fix decision.

## Risks & Sharp Edges

- **Risk:** dev/prod grant divergence on `public.users`. The fix accepts
  either deny shape, but if prod has `GRANT UPDATE TO authenticated` while
  dev does not, the test will exercise the RLS-deny branch in prod and the
  grant-deny branch in dev. **Mitigation:** the service-role re-read
  poison-check is the load-bearing safety assertion in both branches —
  whichever branch fires, the safety property holds. Acceptable.

- **Risk:** future `team_names` constraint widening (e.g., to allow hyphens
  in user-facing names) silently re-enables the original `Synthetic-…`
  shape but does not break it — the seed value stays valid because the
  space is in `[a-zA-Z0-9 ]`. Acceptable.

- **Sharp edge:** the symmetric test's destructure bug at line 221 is what
  produced the *misleading* error message
  (`expected null to deeply equal []`) in the verification run. After the
  fix, future failures will surface with the actual Postgres error object,
  which is the right signal. Anyone diagnosing a future failure of this
  test should expect a `42501` shape (or whichever deny shape the
  then-current grants produce), not `data === null` confusion.

- **Sharp edge:** the dual-shape pattern is now the canonical RLS-deny
  assertion in this codebase. New tenant-isolation tests added after this
  PR should use the same pattern. The 2026-05-16 learning is the source of
  truth; this PR's edits exemplify it. (Promotion of the pattern into a
  helper is tracked in #3869 item 1 — out of scope here.)

## Related

- **Issue:** #3878 (follow-through gate; closed by this PR's merge)
- **Source PR:** #3854 (`feat(runtime): PR-C sibling-query tenant migration`,
  already merged to `main`) — this PR unblocks its prod promotion
- **Deferrals tracker:** #3869 (item 6 = CI workflow for tenant-isolation;
  items 1/3/4/5 = mock dedup, helper consolidation, sentinel sweep, ADR)
- **Learnings:**
  - `knowledge-base/project/learnings/2026-05-06-tenant-jwt-rpc-grant-mismatch-vitest-blind.md`
    — `beforeAll` crash → `skipped` is the vitest-blind class
  - `knowledge-base/project/learnings/2026-05-16-rls-deny-tests-payload-must-type-validate-or-they-pass-for-wrong-reason.md`
    — deny-test methodology + dual-shape pattern
