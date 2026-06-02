---
title: "fix: repair stale conversation-archive-release-slot integration suite (post-mig-059 schema drift)"
type: fix
date: 2026-06-02
branch: feat-one-shot-4798-stale-slot-integration-suite
lane: single-domain
status: planned
brand_survival_threshold: none
related_issues: [4798]
related_prs: [4791]
sentry_issue: 52442f7a9b77462b9927b1f055204cce
---

# fix: repair stale `conversation-archive-release-slot` integration suite (post-mig-059 schema drift)

## Enhancement Summary

**Deepened on:** 2026-06-02
**Sections enhanced:** Research Reconciliation, Acceptance Criteria, Risks (all live-verified rather than re-authored — the plan was already grounded at write time).
**Research method:** direct codebase verification (no external research warranted — this is a single-file test-fixture repair fully patterned on a merged sibling test). Halt gates 4.6/4.7/4.8 + precedent-diff 4.4 + verify-the-negative 4.45 + citation quality-checks all run inline.

### Verifications performed (all pass)

1. **Citations.** `#4798` confirmed OPEN with the exact title; `#4791` (the 23502 fix / sibling test) confirmed merged — commit `d53be565` is an ancestor of `origin/main`. Cited rule IDs `hr-dev-prd-distinct-supabase-projects`, `cq-test-fixtures-synthesized-only`, `hr-weigh-every-decision-against-target-user-impact` are all active in `AGENTS.md`. The cited learning path resolves.
2. **Verify-the-negative.** "No `title` column on `conversations`" — `git grep` across all migrations returns zero conversation-`title` hits; prod `createConversation` insert (`ws-handler.ts:816-826`) carries no `title`. CONFIRMED.
3. **Vitest collection (load-bearing for AC5/AC6).** `vitest.config.ts:44` includes `test/**/*.test.ts`; `*.integration.test.ts` matches that glob and is NOT in the `exclude` list (`e2e/**`, `node_modules/**`). The file is therefore compiled/collected and gated only by `describe.skipIf` — a compile error here breaks the whole web-platform vitest run. AC5/AC6 + Sharp Edges capture this.
4. **Precedent-diff (Phase 4.4).** The teardown sequence prescribed (anonymise RPCs → workspace → org → `deleteUser`) is a verbatim match for the merged sibling at `concurrency-acquire-slot-workspace-id.integration.test.ts:143-153`. No novel pattern; established convention adopted exactly.
5. **Gates.** 4.6 (User-Brand Impact present, threshold `none`, file is not a sensitive path → no scope-out bullet required), 4.7 (Observability section present; file is under `test/` not `server`/`src`/`infra`, so the production-code trigger does not strictly fire, but the section is present and correctly marks N/A), 4.8 (no PAT-shaped variables) — all pass.

### Scope note

No multi-agent review fan-out was run: scope is one opt-in, CI-skipped test file at brand-survival threshold `none`, with every substantive risk (schema drift, WORM-FK teardown, vitest collection) directly verified against the codebase. Plan-review (DHH/Kieran/Simplicity) at `/work` time remains available if desired.

## 🐛 Summary

The opt-in trigger integration suite
`apps/web-platform/test/conversation-archive-release-slot.integration.test.ts`
(gated by `SLOT_TRIGGER_INTEGRATION_TEST=1`) is **stale against the current dev
Supabase schema** and errors before reaching any of its 6 assertions. It does
not run in CI (`describe.skipIf(!INTEGRATION_ENABLED)`), so it has silently
rotted while the schema moved under it.

Three independent breaks, all confirmed live against dev in #4798:

1. **`title` column does not exist on `conversations`.** `insertConversation`
   (file lines 118–125) inserts `title: "slot-trigger integration"`. The
   `conversations` table never had a `title` column in the current schema (no
   `CREATE TABLE … title` and no `ADD COLUMN title` anywhere under
   `apps/web-platform/supabase/migrations/`). PostgREST rejects with `PGRST204`
   ("Could not find the 'title' column").
2. **Missing NOT NULL `workspace_id`.** Migration
   `059_workspace_keyed_rls_sweep.sql:62` runs
   `ALTER TABLE public.conversations ALTER COLUMN workspace_id SET NOT NULL`.
   `insertConversation` omits `workspace_id`, so even after the `title` fix the
   INSERT would 23502 (`not_null_violation`).
3. **`deleteUser` teardown blocked by the WORM membership-audit FK.** The
   new-user trigger auto-creates a solo organization, a solo workspace
   (`workspaces.id = user.id`, ADR-038 N2), an owner `workspace_members` row,
   and a `workspace_member_actions` audit row whose `{target,actor}_user_id`
   are **RESTRICT** FKs to `public.users`. The bare
   `service.auth.admin.deleteUser(user.id)` in `afterAll` (file lines 97–113)
   fails on that RESTRICT FK.

The canonical, already-merged repair pattern lives in the **sibling** test
`apps/web-platform/test/concurrency-acquire-slot-workspace-id.integration.test.ts`
(PR #4791, the 23502 fix). It demonstrates every piece of the fix:
- reads the trigger-created solo workspace's `organization_id`
  (`.from("workspaces").select("organization_id").eq("id", user.id)`),
- supplies `workspace_id` on writes,
- tears down with `anonymise_workspace_members` +
  `anonymise_workspace_member_actions` (WORM-bypass) **before** `deleteUser`.

This plan rewrites the stale suite's fixtures/teardown to that pattern and
removes the in-file `#4798` staleness note (file lines 138–142) once the
staleness is gone.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing user-facing — this is
an opt-in, CI-skipped developer integration test. The only "user" is a
developer running `SLOT_TRIGGER_INTEGRATION_TEST=1` locally against dev; a
broken repair means the suite still errors in `beforeAll`/`insertConversation`
exactly as it does today, with no regression to production behavior.

**If this leaks, the user's data / workflow / money is exposed via:** N/A — the
suite only creates and deletes **synthetic** `slot-trigger-*@soleur.test`
accounts against the **dev** Supabase project (never prod, per
`hr-dev-prd-distinct-supabase-projects`), gated by an `assertSynthetic` email
allowlist. No real user data is touched.

**Brand-survival threshold:** none — test-only change against dev, no production
code path, no schema change, no new data surface. (Sensitive-path note: the
plan touches no file under the preflight Check 6 sensitive-path regex — it edits
one `*.integration.test.ts` file only — so no `threshold: none, reason:` scope-out
bullet is required.)

## Research Reconciliation — Spec vs. Codebase

No external spec exists for this branch. The #4798 issue body's three claims
were each verified against the live codebase at plan time:

| #4798 claim | Codebase reality (verified) | Plan response |
| --- | --- | --- |
| `title` column removed from `conversations` | `git grep` for `title` across `supabase/migrations/` returns **zero** conversation-`title` hits; canonical prod insert `createConversation` (`ws-handler.ts:816-826`) inserts **no** `title`. | Drop `title` from `insertConversation`. |
| `conversations.workspace_id` is NOT NULL (mig 059) | Confirmed: `059_workspace_keyed_rls_sweep.sql:62` `ALTER COLUMN workspace_id SET NOT NULL`. | Add `workspace_id` to `insertConversation` (solo workspace = `user.id`, ADR-038 N2). |
| Bare `deleteUser` teardown blocked by WORM `workspace_member_actions` RESTRICT FK | Confirmed: `anonymise_workspace_members` (`063:545`) + `anonymise_workspace_member_actions` (`063:304`) both exist, `service_role`-granted, WORM-bypass via `session_replication_role='replica'`. Sibling test uses exactly this sequence (`concurrency-acquire-slot-workspace-id.integration.test.ts:143-153`). | Replace bare `deleteUser` with the anonymise-RPC sequence + workspace/org cleanup, mirroring the sibling. |

## Approach

Rewrite the suite to mirror the sibling test's fixture/teardown contract. The
test's **assertions and scenarios stay identical** — only the fixture plumbing
changes. This is a pure schema-alignment repair; no test intent changes.

### What changes

1. **`insertConversation` (file lines 115–128):**
   - Remove `title: "slot-trigger integration"`.
   - Add `workspace_id: user.id`. For this solo synthetic user the active
     workspace IS the solo workspace, whose id equals `user.id` (ADR-038 N2,
     matching the existing `acquireSlot` helper's `p_workspace_id: user.id` at
     file line 147). This keeps `slot.workspace_id == conversation.workspace_id`
     — the equality `find_stuck_active_conversations` and the RLS member-select
     both assume.
   - Optionally add `last_active: new Date().toISOString()` to mirror
     `createConversation` exactly (the column is nullable, so not strictly
     required; include for fidelity if it does not complicate the diff).

2. **`afterAll` teardown (file lines 97–113):** replace the bare
   `deleteUser` with the sibling's FK-dependency-ordered sequence:
   ```ts
   await service.from("user_concurrency_slots").delete().eq("user_id", user.id);
   await service.from("conversations").delete().eq("user_id", user.id);
   await service.rpc("anonymise_workspace_members", { p_user_id: user.id });
   await service.rpc("anonymise_workspace_member_actions", { p_user_id: user.id });
   await service.from("workspaces").delete().eq("id", user.id);
   await service.from("organizations").delete().eq("owner_user_id", user.id);
   // then the existing assertSynthetic + getUserById email re-check, then deleteUser
   ```
   Keep the existing `assertSynthetic(user.email)` guard and the
   `getUserById` email re-check before `deleteUser` (defense-in-depth that the
   sibling test also retains). Downgrade the post-`deleteUser` `throw` to a
   `console.warn` per the sibling's rationale (a future trigger-added RESTRICT
   FK should warn, not fail a teardown-only cascade gap) — OR keep the `throw`
   if we want the suite to fail loud on teardown regressions. **Decision: keep
   the `throw`** — this suite is about asserting trigger correctness; a teardown
   failure that leaves synthetic dev rows behind should surface, and the
   anonymise sequence makes the documented FK path succeed. (Note in PR body.)

3. **`beforeAll` (file lines 63–82):** no change required. The new-user trigger
   already creates the solo workspace; the test does not need a second
   (team) workspace because every scenario operates on the solo workspace
   (`workspace_id = user.id`). Do **not** add the sibling's `teamWorkspaceId`
   fixture — it is unused here (YAGNI).

4. **`afterEach` (file lines 84–95):** no change. It already deletes
   `user_concurrency_slots` then `conversations` by `user_id`, which is correct
   and order-safe. (The slot FK is on `users`, not `conversations`, as the
   in-file comment notes — still accurate.)

5. **In-file staleness note (file lines 138–142, inside `acquireSlot`):**
   remove the `NOTE:` paragraph and the `#4798` reference now that the suite is
   no longer stale. Keep the mig-093 4-arg contract comment (lines 134–137,
   148) — that is still accurate and load-bearing.

### What does NOT change

- The 6 test bodies (lines 167–356) and their assertions.
- The `acquireSlot` helper's 4-arg RPC call (already correct post-#4791).
- The `slotCount`, `backdateSlotHeartbeat` helpers.
- `SYNTHETIC_EMAIL_PATTERN`, `syntheticEmail`, `assertSynthetic`, `requireEnv`.

## Files to Edit

- `apps/web-platform/test/conversation-archive-release-slot.integration.test.ts`
  — the only file. Changes: `insertConversation` (drop `title`, add
  `workspace_id`), `afterAll` (anonymise-RPC teardown sequence + workspace/org
  cleanup), remove in-file `#4798` staleness `NOTE`. Header docstring: update
  the "Plan:" line to cite this plan and drop any stale-schema caveat.

## Files to Create

- None. (No new component files, no `app/**/page.tsx`, no `app/**/layout.tsx` —
  Product/UX mechanical-escalation does not fire.)

## Open Code-Review Overlap

Checked open `code-review` issues for any that name
`conversation-archive-release-slot.integration.test.ts`. The only match is
**#4798 itself** (this issue). No other open scope-out touches this file.
**Disposition: Fold in / Closes #4798** — this PR fully resolves the staleness
#4798 tracks.

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1 — `title` removed.** `grep -n "title" apps/web-platform/test/conversation-archive-release-slot.integration.test.ts` returns **zero** lines inside the `insertConversation` insert object (the word may survive only in unrelated prose/test names — verify the INSERT payload specifically).
- [x] **AC2 — `workspace_id` supplied.** The `insertConversation` insert object contains `workspace_id: user.id`. Verify: `grep -nE "workspace_id:\s*user\.id" apps/web-platform/test/conversation-archive-release-slot.integration.test.ts` returns ≥1.
- [x] **AC3 — WORM-bypass teardown.** `afterAll` calls `anonymise_workspace_members` and `anonymise_workspace_member_actions` **before** `deleteUser`, plus `workspaces`/`organizations` cleanup. Verify: `grep -nE "anonymise_workspace_member" apps/web-platform/test/conversation-archive-release-slot.integration.test.ts` returns exactly 2 RPC calls, both lexically above the `deleteUser` line.
- [x] **AC4 — staleness note gone.** `grep -n "#4798\|independently stale\|does not run in CI" apps/web-platform/test/conversation-archive-release-slot.integration.test.ts` returns **zero** lines.
- [x] **AC5 — typecheck clean.** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` exits 0 (the file is collected by vitest's `test/**/*.test.ts` include glob — `vitest.config.ts:44` — so it must compile).
- [x] **AC6 — default (skipped) suite run stays green.** `cd apps/web-platform && ./node_modules/.bin/vitest run test/conversation-archive-release-slot.integration.test.ts` (no env flag) reports the describe block **skipped**, exit 0 — proving the edit did not break the skip-gate or compilation.
- [x] **AC7 — live dev run all-green (the actual repair proof).** With dev creds, the full opt-in suite passes all 6 tests:
  ```bash
  cd apps/web-platform && \
    doppler run -p soleur -c dev -- \
    env SLOT_TRIGGER_INTEGRATION_TEST=1 \
    ./node_modules/.bin/vitest run test/conversation-archive-release-slot.integration.test.ts
  ```
  Expected: `6 passed`, exit 0, and no synthetic `slot-trigger-*@soleur.test`
  rows left behind in dev (teardown verified). **Automation:** runnable in-session
  via the `doppler`/`vitest` CLIs (no SSH, no dashboard) — execute at /work time
  and paste the summary into the PR body. NOT an operator step.
- [x] **AC8 — synthetic-only invariant preserved.** `SYNTHETIC_EMAIL_PATTERN` and the `assertSynthetic` guards remain unchanged (`cq-test-fixtures-synthesized-only`, `hr-dev-prd-distinct-supabase-projects`).

### Post-merge (operator)

- None. No migration to apply, no infra to provision, no external state to set.
  The repaired suite remains opt-in/CI-skipped; merging is the whole deliverable.

## Test Scenarios

The 6 existing scenarios are the test surface and are unchanged in intent:
1. archiving a conversation releases its concurrency slot,
2. free-tier user can start a new conversation immediately after archiving,
3. regression guard: trigger MUST NOT release on unarchive,
4. regression guard: trigger MUST NOT release on `status='completed'`,
5. stale-heartbeat slot (200 s) reaped by lazy sweep on next acquire,
6. fresh-heartbeat slot (60 s) NOT reaped — genuine `cap_hit` fires.

The repair is validated by AC7 (all 6 turn green against live dev) — no new
test bodies are added.

## Observability

Not applicable as a 5-field runtime-observability schema: this plan edits a
single opt-in **test** file with no production code path, no new service, no
new infrastructure surface (Phase 2.8/2.9 skip conditions met — Files-to-Edit
is one `*.test.ts` under `apps/web-platform/test/`, not under `server/`,
`src/`, or `infra/`). The repair's own "is it healthy" signal is the AC7 live
dev run: a green 6/6 with clean teardown is the discoverability test, runnable
with no SSH via the `doppler run … vitest run` command in AC7.

## Domain Review

**Domains relevant:** none

No cross-domain implications — this is a developer-tooling / test-fixture
schema-alignment change against the dev database. No product surface, no
user-facing UI, no security primitive, no infrastructure, no marketing/growth
surface. Product/UX mechanical-escalation does not fire (no new component
files). GDPR Phase 2.7 skip: the file touches no schema/migration/auth/API-route
surface — it only exercises existing `service_role` RPCs against synthetic dev
data, and the triggers (a)–(d) do not fire (no new LLM processing, threshold is
`none`, no new cron, no new artifact-distribution surface).

## Risks & Mitigations

- **R1 — dev solo-workspace assumption (`workspace_id = user.id`).** If a future
  new-user trigger change stops setting `workspaces.id = user.id` for solo users
  (ADR-038 N2), the `workspace_id: user.id` fixture would FK-fail. *Mitigation:*
  this is the established invariant the sibling test (#4791) and the live
  `acquireSlot` helper both already depend on; a change to it would break both
  suites loudly. No new coupling introduced.
- **R2 — teardown anonymise RPC drift.** If `anonymise_workspace_members` /
  `anonymise_workspace_member_actions` signatures change, teardown breaks.
  *Mitigation:* both are `service_role`-granted, defined in mig 063, and used
  unchanged by the sibling suite; signature confirmed at plan time
  (`anonymise_workspace_members(uuid)`, `anonymise_workspace_member_actions(uuid)`).
- **R3 — leftover synthetic rows on a partial-failure run.** A test that throws
  mid-suite could leave dev rows. *Mitigation:* `afterEach` already cleans
  slots+conversations per test; `afterAll` cleans workspace/org/membership; the
  `assertSynthetic` guard bounds the blast radius to `slot-trigger-*@soleur.test`.
- **R4 — false-clean default run.** AC6 must confirm the suite still *skips*
  cleanly without the env flag (the edit must not accidentally un-gate it). The
  `describe.skipIf(!INTEGRATION_ENABLED)` wrapper is untouched.

## Alternative Approaches Considered

| Alternative | Why not |
| --- | --- |
| Delete the stale suite entirely | The 6 scenarios pin real trigger/SQL-predicate behavior (slot release on archive, lazy-sweep boundaries) that the migration-shape unit test cannot verify (vitest can't fire Postgres triggers). The suite has value; repair > delete. |
| Add a team-workspace fixture like the sibling | YAGNI — every scenario here operates on the solo workspace; a second workspace is unused. The sibling needed it to prove the slot tracks a *non-solo* `workspace_id`; this suite tests the archive trigger, not workspace-keying. |
| Move the file out of the `test/**/*.test.ts` glob (rename to `.integration.ts`) so it stops compiling under the suite | Out of scope and risky: the sibling test uses the same naming and the gate is `skipIf`, not glob-exclusion. Keeping it collected ensures it stays typecheck-protected (AC5). |
| Leave deferred (it's CI-skipped) | #4798's re-eval date is 2026-09-01, but this one-shot is explicitly tasked to repair it now; the fix is mechanical and fully patterned on #4791. |

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail
  `deepen-plan` Phase 4.6. This plan's section is filled (threshold: none).
- **`title` may also appear in test-name strings or prose** (e.g.
  `"slot-trigger integration"`); AC1's grep must target the `insertConversation`
  INSERT payload specifically, not every occurrence of the substring `title`.
- **The file IS collected by vitest** (`test/**/*.test.ts`, `vitest.config.ts:44`)
  despite being "opt-in" — opt-in means `describe.skipIf` skips the *bodies*, but
  the module is still imported and type-checked. A compile error here fails the
  whole web-platform vitest run, not just this suite. AC5/AC6 guard this.
- **AC7 requires live dev creds** (`doppler run -p soleur -c dev`). If creds are
  unavailable in-session, AC7 cannot be self-verified; in that case the PR body
  must state AC7 as "pending live dev run" rather than claim it passed — silence
  beats a fabricated green.

## Provenance

- Issue: #4798 (label `code-review`, `deferred-scope-out`; milestone Post-MVP / Later).
- Canonical repair pattern: `apps/web-platform/test/concurrency-acquire-slot-workspace-id.integration.test.ts` (PR #4791, the 23502 fix).
- Schema facts: `059_workspace_keyed_rls_sweep.sql:62` (conversations.workspace_id NOT NULL); `063_workspace_member_actions.sql:304,545` (anonymise RPCs); `029_plan_tier_and_concurrency_slots.sql` + `093_acquire_slot_workspace_id.sql` (slot RPC); `ws-handler.ts:816-826` (canonical conversation insert column set, no `title`).
- Related learning: `knowledge-base/project/learnings/2026-05-22-tenant-integration-runtime-failures-post-mig-059.md` (the NOT NULL ↔ RPC/fixture contract-break class).
