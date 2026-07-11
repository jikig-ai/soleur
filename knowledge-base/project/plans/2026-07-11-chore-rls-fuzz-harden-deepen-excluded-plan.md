---
title: "Harden RLS/authz-fuzz harness — deepen excluded surfaces, anon + user-isolation dimensions, row-hijack UPDATE, shared fixture"
issue: 6307
branch: feat-one-shot-6307-rls-fuzz-harden
lane: single-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
depends_on_pr: 6255
status: draft
date: 2026-07-11
---

# Chore: Harden the RLS/authz-fuzz harness (post-#6255 review deepening)

## Enhancement Summary

**Deepened on:** 2026-07-11 · **Threshold:** single-user incident (triad review, not style panel).
**Review agents:** spec-flow-analyzer, learnings-researcher, data-integrity-guardian,
security-sentinel, architecture-strategist.

**Load-bearing corrections folded in (each a would-be false-green the harness exists to forbid):**

1. **Fact: the ADR is already `ADR-111`** on #6255's branch (not 103) — corrected throughout.
2. **P0 (security): anon write-attacks false-green.** The anon `acquire`/`release`/`touch`
   observation must `reset role`/re-read as service_role — under `auth.uid()=NULL` the member
   SELECT policy hides the row → `count=0` regardless → `test.fails` green forever + un-baseline
   never fires. (Phase 6, AC13)
3. **P1 (data-integrity): row-hijack is vacuous on SELECT/INSERT-only tables** (no UPDATE policy
   for anyone → 0-rows-by-default, and the positive control is impossible). Scoped to the four
   UPDATE-policy tables. **`kb_files` is a REAL latent exposure** the hijack surfaces (user_id-only
   UPDATE WITH CHECK permits owner re-home to wsB) — baseline/carve-out, don't green. (Phase 5, AC6)
4. **P1 (data-integrity): `email_triage_items` is workspace-OWNER-gated (mig 111), not user-keyed** —
   reclassified to AC1b, off the AC3 dimension. **`tc_acceptances` has zero RLS policies** — its
   owner positive control is schema-impossible → moved to `USER_EXCLUDED`. **`action_sends` keeps
   its INSERT-forge** (real RLS WITH CHECK). (Phase 3/4, AC3/AC4/AC5)
5. **P2 (data-integrity): WORM triggers raise P0001, not 42501** — the real bare-42501 risk is the
   table-level `REVOKE INSERT`; no message-text discriminator needed (dropped). (Phase 4, AC5)
6. **P1 (architecture): make the two catalog enumerators disjoint IN SQL** (`userIsolationSet :=
   {auth.uid()+user_id} MINUS is_workspace_member set`) so AC1/AC3 mutual-exhaustiveness is proven,
   not asserted. Compose the three txn helpers around one primitive/sentinel. (Phase 1/3)
7. **P1 (security): the anon coverage gate is enumeration-only** — reused authenticated
   classifications don't prove anon isolation (`auth.uid()=NULL` changes fn semantics); pre-scope
   the anon blast radius at Phase 0. (Phase 0/2, AC7/AC13)

## Overview

Issue #6307 tracks the MEDIUM/LOW deepening work deferred from the PR #6255 multi-agent
review of the runtime RLS/authz-fuzz harness (`apps/web-platform/test/rls-fuzz/`,
harness ADR, #6256). The HIGH-severity false-greens (RPC SQLSTATE classification,
getter poison-seed + positive control, real-A-owned-row attacks, the AC1b
workspace-tenancy coverage gate) already shipped in #6255. This plan closes the
eight remaining hardening items.

The harness is **dev/CI-only test tooling**: gated behind `RLS_FUZZ_LOCAL=1`, runs
`bun run test:rls-fuzz` (`vitest run test/rls-fuzz`) against a **local disposable
Postgres** (fail-closed DSN allowlist, `local-dsn-guard.ts`), every attack runs in a
rolled-back transaction, all fixtures are synthesized (`cq-test-fixtures-synthesized-only`).
No product source, no migration, no infrastructure. Its *purpose*, however, is a
single-user-incident-class invariant: **a false-green isolation test is worse than
none** (harness ADR framing). So the deepening work itself inherits that threshold —
each new attack must have a positive control / self-test proving it can go RED.

**The eight items (issue #6307):**

1. Deepen the 6 `EXCLUDED_ISOLATION` tables into real base-table targets.
2. Faithful RPC attacks for the 2 `EXCLUDED` definer fns (`set_email_triage_status`, `authorize_template`).
3. Row-hijack UPDATE variant (F4): tenant-key reassignment `SET workspace_id = wsB` asserting WITH CHECK.
4. Anon dimension (F7): drive the 4 #6306 fns under `anon`; key the AC8 gate on `proname + args`.
5. Model the user-isolation dimension (`user_id = auth.uid()` tables).
6. Verify `routine_runs` / `routine_run_progress` global-read is intentional, not a leak.
7. RPC mutation self-test: mirror base-matrix AC5 for the RPC dimension.
8. Extract a shared `harness-fixture.ts` (consolidate `seedContext`/rollback/`connect`).

## ⛔ Blocking Dependency — PR #6255 is UNMERGED

**This is the load-bearing premise of the whole plan.** Every file this plan edits
(`targets.ts`, `rpc-cases.ts`, `catalog.ts`, `verdict.ts`, the three
`*.integration.test.ts`, `claim.ts`) lives **only on the `feat-t3mp3st-security-eval`
branch (PR #6255, state = OPEN, mergeable)**. None of them exist on `origin/main`, and
therefore **none exist in this worktree** (branch `feat-one-shot-6307-rls-fuzz-harden`
is cut from `main` @ `25846d2d`).

Consequences the pipeline MUST honor:

- **`/work` cannot begin until PR #6255 merges to `main`.** There is nothing to edit
  until then. The Phase 0 gate below hard-blocks on `gh pr view 6255 --json state` ≠ `MERGED`.
- **After #6255 merges, rebase this branch onto the new `main`** (`git rebase origin/main`)
  so the harness files are present, then proceed. Do NOT stack this PR on
  `feat-t3mp3st-security-eval` and do NOT cherry-pick #6255's diff into this branch —
  that would balloon the #6307 diff to include all of #6255.
- If #6255 is abandoned or substantially reworked, this plan must be re-derived against
  the merged harness shape (the file contents quoted here are #6255's current HEAD).

## Premise Validation

Checked at plan time (2026-07-11):

- **#6256** (harness umbrella) — OPEN. **#6255** (harness PR) — OPEN, MERGEABLE, branch
  `feat-t3mp3st-security-eval`, 25 files. → the hard blocking dependency above.
- **#6306** (the KNOWN_EXPOSURES tracking issue) — OPEN, title confirms
  "find_stuck_active_conversations executable by anon/authenticated — cross-tenant
  disclosure". The four fns are asserted under `test.fails` in `rpc-cases.ts`. Item 4's
  "granted to anon too" claim is consistent with the harness ADR's first-run findings
  and the migration comment (mig 063 L77) but MUST be re-confirmed against the live
  catalog at /work (Phase 0).
- **ADR ordinal collision (carried, not owned by us):** the harness ADR is authored on
  #6255's branch, where it has **already been renumbered to
  `ADR-111-runtime-authz-rls-fuzz-harness.md`** (deepen-plan architecture review confirmed
  the branch file + the `catalog.ts`/`targets.ts`/`rpc-cases.ts` citations already say
  "ADR-111"). `main`'s highest ordinal is **ADR-110**, so ADR-111 is free and expected to
  survive #6255's ship. **This plan refers to it as "the harness ADR (ADR-111)"; the
  ADR-amendment deliverable in Phase 10 re-confirms the real filename at /work from the
  merged tree in case a sibling PR claims 111 first.** (ADR-111's own header rationale is
  itself stale — it says "highest existing is ADR-102" — a pre-existing #6255 nit, not ours.)
- All 6 excluded tables + the user-isolation tables + `routine_runs`/`routine_run_progress`
  schemas were confirmed present on `main` (`apps/web-platform/supabase/migrations/`), so
  once #6255 merges the schemas are readable in-tree for faithful seeds.

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Codebase reality (verified) | Plan response |
|---|---|---|
| "Deepen the 6 EXCLUDED_ISOLATION tables" as one homogeneous item | Mixed predicates (verified against migrations incl. **mig 111**): `inbox_item`/`workspace_member_actions` workspace-keyed; `message_attachments` EXISTS-join via `messages`; `dsar_export_jobs`/`action_sends` **user-keyed** (`user_id=auth.uid()`); **`email_triage_items` workspace-OWNER-gated** (`is_email_triage_workspace_owner`, mig 111 dropped the old user_id policy). | Item 1 **split by predicate**: workspace-keyed → non-member `userB`; user-keyed → AC3 co-member `userC` (Phase 3/4); `email_triage_items` → AC1b owner-gated, NOT AC3 (deepen data-integrity review). |
| Excluded tables just "need seeds + attacks" | The four WORM triggers raise **P0001** (not 42501) `BEFORE UPDATE/DELETE` (mig 102/122/063/051); `verdict.ts` already scores P0001 as `test-error`. The real bare-**42501** risk is the table-level `REVOKE INSERT FROM authenticated` on `email_triage_items`/`inbox_item` (grant denial, not RLS). `action_sends` keeps a real INSERT WITH CHECK. | Phase 4: drop INSERT-forge only where REVOKE/no-INSERT-policy intercepts; **keep `action_sends` INSERT-forge**; SELECT-visibility is the load-bearing WORM proof; **no message-text discriminator** (deepen review). |
| "Key AC8 gate on proname + args" (item 4) | `securityDefinerAuthenticatedFns()` already returns `{proname, args}`, but the AC8 test and the `ATTACK_SQL`/`EXCLUDED`/`KNOWN_EXPOSURES` maps are keyed by **bare `proname` string**. | Migrating the key to a **catalog-sourced** `proname(args)` is a structural refactor of `rpc-cases.ts` + the AC8 gate — **Phase 2** owns it, before the anon work. Assert no `proname` in the set is overloaded (deepen review). |
| "Drive the 4 fns under anon" (item 4) | Catalog enumerator filters `authenticated` only; no `anon` enumerator; `claim.ts` has `buildAnonClaims()`. Supabase default-privileges grant anon EXECUTE broadly → the anon set ≈ authenticated set. | **Phase 2** adds `securityDefinerAnonFns`; **Phase 6** drives anon attacks. The anon coverage gate is **enumeration-only** (reused authenticated classifications don't prove anon isolation under `auth.uid()=NULL`) + the anon write-observation must `reset role` (deepen security review). |
| Harness ADR is "ADR-103" | **Already renumbered to ADR-111 on #6255's branch** (deepen-plan review); main's highest is ADR-110, so 111 is free. | Reference it as ADR-111; re-confirm filename at /work Phase 0 + Phase 10. |

## Research Insights (institutional learnings)

Verified-on-disk learnings that directly govern the correctness of this work:

- `knowledge-base/project/learnings/2026-05-16-rls-deny-tests-payload-must-type-validate-or-they-pass-for-wrong-reason.md`
  — Postgres order is parse → type-cast → constraints → RLS `WITH CHECK` → execute. A
  deny payload that fails at cast/constraint (`22P02`, `23xxx`) passes the deny-test **for
  the wrong reason**. **Every new seed/forge must be a payload that would SUCCEED if the
  RLS gate were removed** (governs Phases 2–4 and the WORM-trigger decision — this is why
  a trigger-guard P0001 must not be blanket-scored denied).
- `knowledge-base/project/learnings/2026-05-06-rls-zero-policies-anon-delete-204-semantic.md`
  — RLS denies SELECT/UPDATE/DELETE by **hiding rows** (0-rows, no error) and denies INSERT
  by **raising 42501**. The oracle must re-read via service_role, not trust status/error
  shape (governs the row-hijack WITH-CHECK verdict in Phase 5 and the anon dimension in Phase 6).
- `knowledge-base/project/learnings/security-issues/2026-04-18-rls-for-all-using-applies-to-writes.md`
  — `FOR ALL USING (auth.uid()=user_id)` with no `WITH CHECK` governs writes too; a spoofed
  INSERT/UPDATE claiming another tenant's id is rejected by USING (underpins the
  user-isolation dimension (Phase 3) and the row-hijack WITH-CHECK variant (Phase 5)).
- `knowledge-base/project/learnings/security-issues/2026-06-01-caller-override-rpc-needs-service-role-only-grant.md`
  — a SECURITY DEFINER RPC with a forgeable caller-override param (`COALESCE(p_caller,auth.uid())`)
  must be service_role-only; the faithful attack forges `p_*_user_id = victim` under
  `authenticated`/`anon` and asserts denial (governs Phases 5–6 and the #6306 anon attacks).
- `knowledge-base/project/learnings/security-issues/2026-07-09-security-definer-rpc-bypasses-jti-rls-and-new-user-fk-table-trips-two-dsar-gates.md`
  — a definer fn granted to `authenticated` is an independent entry point that BYPASSES
  RLS; every boundary property must be re-asserted in the fn body (core rationale for the
  RPC dimension; also notes the touched-file loop ≠ full-suite exit gate for web-platform).
- `knowledge-base/project/learnings/best-practices/2026-06-19-sql-function-body-parser-must-anchor-to-create-not-bare-function.md`
  — catalog/enumeration must anchor to `CREATE [OR REPLACE]` and **fail loud on
  unresolvable**, never silently skip (governs the new `userIsolationTables`/
  `securityDefinerAnonFns` enumerators — an inert enumerator is a false-green).
- `knowledge-base/project/learnings/2026-05-04-vacuous-red-via-shared-fixture-and-toolchain-pinning.md`
  — a shared-fixture identity that trips an early-exit branch makes attacks pass vacuously;
  RED inputs must select identities only the branch-under-test handles. Run the pinned
  `./node_modules/.bin/vitest`, never `bunx/npx` (governs the Phase 1 fixture extraction).
- `knowledge-base/project/learnings/2026-05-16-followthrough-verification-loop-catches-grant-vs-rls-deny-shape.md`
  — dual deny-shape (`42501`+null vs empty-data) + a service_role poison re-read is the
  canonical assertion; multiple coexisting shapes are the signal to extract a shared helper
  (validates item 8).

Conventions to honor: `cq-test-fixtures-synthesized-only` (synthetic emails only; the
harness already uses `*@example.test`); treat any vitest `skipped > 0` as a `beforeAll`
crash trap; the authoritative web-platform gates are `./node_modules/.bin/tsc --noEmit`
and `./node_modules/.bin/vitest run` (not `next lint`).

## User-Brand Impact

**If this lands broken, the user experiences:** nothing *directly* — this is a
gated dev/CI test harness with no runtime surface. The real failure mode is
**indirect and severe**: a *vacuous or mis-classified* new attack case that reports
**green while a genuine cross-tenant path is open** would let a real tenant-isolation
leak ship undetected. That is the exact single-user-incident the harness exists to
catch.

**If this leaks, the user's data is exposed via:** the harness itself never touches
prod (fail-closed local-DSN allowlist, synthetic fixtures, rolled-back txns). The
exposure vector guarded here is *epistemic*: a false-green suite that certifies
isolation that does not hold.

**Brand-survival threshold:** single-user incident. Inherited from the harness ADR —
"a false-green isolation test is worse than none." Every new attack case in this plan
MUST ship with a positive control (tenant-A can do the thing) and/or a self-test
(disable the guard → verdict flips RED), so a green result is provably non-vacuous.

> CPO sign-off required at plan time before `/work` begins (frontmatter
> `requires_cpo_signoff: true`). `user-impact-reviewer` runs at review time.

## Implementation Phases

> **The single highest-value guardrail across every phase (spec-flow):** a
> **mandatory positive control per new attack case** — the legitimate owner/member
> succeeds on the *exact* fixture row/param. Without it, a `denied` verdict cannot be
> distinguished from "the row/param never existed" (`P0002 no_data_found`, `22P02`,
> `count=0`-by-emptiness) — the dominant false-green mode in this harness. Every new
> case below is required to ship its paired positive control.

### Phase 0 — Preconditions (hard gates; no edits)

- **G0.1 (blocking):** `gh pr view 6255 --json state -q .state` MUST equal `MERGED`.
  If not, STOP — `/work` cannot proceed. Re-run when #6255 merges.
- **G0.2:** `git rebase origin/main` so the harness files are in-tree. Confirm
  `apps/web-platform/test/rls-fuzz/targets.ts` exists.
- **G0.3:** Resolve the harness ADR's real filename/ordinal:
  `ls knowledge-base/engineering/architecture/decisions/ | grep -i rls-fuzz` (record it).
- **G0.4 (catalog facts against a local stack):** bring up the local stack per the
  workflow (`supabase start` → `bash scripts/run-migrations.sh`) and confirm, read-only:
  - the 4 #6306 fns carry `has_function_privilege('anon', oid, 'EXECUTE')` (item 4 premise);
  - **🟠 pre-scope the anon blast radius NOW (deepen security review):** run
    `securityDefinerAnonFns` (a read-only catalog query, same class as this step) and record
    the full anon-EXECUTE definer-fn count + which take a caller-override/`p_*_user_id` param.
    Discovering "N anon-EXECUTE fns, M caller-param" mid-`/work` under the AC11 "suite green"
    pressure invites a bulk-`EXCLUDED` shortcut with reused-authenticated rationales (the P1
    false-green). Sizing it here turns an unknown-size discovery into a scoped PR. Each anon
    exposure surfaced beyond the 4 gets its OWN `test.fails` keyed to a **filed** issue; a
    mass-EXCLUDE is a review-blocking event, never a green-the-gate move.
  - `routine_runs`/`routine_run_progress` SELECT policy is `auth.uid() IS NOT NULL` and
    enumerate their columns to judge per-tenant PII (item 6);
  - the trigger SQLSTATEs raised on a cross-tenant INSERT/UPDATE for each WORM table
    (`email_triage_items`, `inbox_item`, `workspace_member_actions`, `action_sends`) —
    record which raise 42501 vs P0001 (informs the Phase 4 WORM handling).
- **G0.4b (shape assertion — deepen security review):** assert the #6255 HEAD shapes this
  plan quotes are intact after the merge — `verdict.ts` exports (`classifyRpcOutcome`/
  `classifyMutationOutcome` return `{kind:…}`), the `RpcCtx` field set, and `driveDenied`'s
  `""`-void-return semantics — so a silent #6255 rework reds at Phase 0, not mid-implementation.
- **G0.5:** `bun run test:rls-fuzz` is green on the rebased tree before any change
  (baseline; the existing `test.fails` KNOWN_EXPOSURES stay red-as-designed).

### Phase 1 — Extract shared `harness-fixture.ts` as a UNION superset (item 8)

Extract first, but the module MUST be the **union superset** of the three current copies,
not a lossy intersection — spec-flow flagged three load-bearing behaviors a naive merge
would silently break, each a total false-green:

- **`max: 1` is load-bearing.** `set local role` / `set_config('request.jwt.claims', …)`
  apply **per connection**; a `connect()` that raises pool size lets a query run on a
  different connection than the one the role/claims were set on → attacks silently run as
  `service_role` or claim-less. Pin `max:1, prepare:false, onnotice:()=>{}`.
- **The three txn helpers are NOT interchangeable — but COMPOSE them around ONE primitive
  (deepen architecture review P2-3)** rather than three parallel copies with three sentinels:
  - `rolledBackRaw(sql, fn)` — the **primitive**: rolls back via the **single** rollback
    Symbol, does **NOT** set role (callers set it; the #6306 KNOWN_EXPOSURE tests `reset role`
    mid-txn to observe as superuser — a pre-set role would break that observation).
  - `attackAs(sql, claims, fn)` — wraps `rolledBackRaw`, setting role `authenticated` + claims as its first statements.
  - `asTenant(sql, sub, fn)` — wraps `attackAs(sql, buildAuthenticatedClaims({sub}), fn)`.
  One sentinel, three shapes — shrinks the sentinel-mismatch false-green surface.
- **`seedRpcCtx` flag-poisoning MUST be preserved** (`debug_mode=true`, `ack=now()`,
  `github_installation_id=424242`): a getter leak reads identically to a denial (null)
  unless A's flags are poisoned to non-sentinel values. Dropping the poison silently
  breaks every getter-leak detection AND the RPC positive control.
- Export `connect(dsn?)` (post-`assertLocalDsn`) and `seedTwoTenant(sql)` (the shared
  userA/userB/userC + membership + 2-conversation bootstrap).
- **Add a fixture self-check** asserting the seed is valid before any case trusts it:
  `wsA !== wsB`, `orgA` present, userC is a wsA member, and the poison landed
  (`debug_mode` reads back `true`). A silent seed failure is a `beforeAll` false-green
  (treat any vitest `skipped > 0` as a crash trap).
- Design the fixture **interface as the target superset up front** (carry userC
  co-member, hooks for userA-owned user-keyed rows, poisoned flags, an anon-role helper)
  so Phases 3–7 ADD seed entries against a stable interface rather than re-fork the
  helpers. Migrate all three integration files to it with **zero behavioral change** —
  every existing AC and the KNOWN_EXPOSURES `test.fails` pass/fail exactly as before
  (RED→GREEN refactor; the suite is its own regression test).

### Phase 2 — RPC coverage re-key (`proname+args`) + anon enumerator (item 4, structural half)

Do this **before** any new RPC case (Phase 6) so new keys are added in args-form, not bare.

- **`proname` → `proname(args)` key migration (atomic).** Re-key `ATTACK_SQL`/`EXCLUDED`/
  `KNOWN_EXPOSURES` and the AC8 gate simultaneously, using
  `pg_get_function_identity_arguments`. **Do NOT hand-type the arg strings** — spec-flow:
  hand keys must match the catalog byte-for-byte (`character varying` vs `varchar`,
  whitespace, arg-name presence) or every entry reads `stale`. Derive the composite key
  from the catalog row (`\`${proname}(${args})\``) and key the maps by that exact string,
  or add a normalization step. Migrate the gate and the maps in ONE edit — a maps-migrated
  / gate-on-bare split can *coincidentally* match and silently mis-cover (the reverse fails
  loud, which is safe). The ATTACK SQL *text* keeps calling the bare fn name (Postgres
  resolves overloads by arg types) — only the map KEY carries args.
- **Anon enumerator:** add `securityDefinerAnonFns(sql)` to `catalog.ts`
  (`has_function_privilege('anon', p.oid, 'EXECUTE')`) — a fn granted to `anon` but NOT
  `authenticated` escapes the current gate entirely. Anchor enumeration to catalog rows and
  **fail loud on unresolvable**, never skip.
- **🟠 P1 — enumeration-coverage ≠ attack-coverage (deepen security review).** Supabase
  default privileges grant EXECUTE to PUBLIC/anon on nearly every fn, so the anon-EXECUTE set
  ≈ the authenticated-EXECUTE set (dozens of fns). A "parallel anon gate (anon-EXECUTE ⊆
  `ATTACK`∪`EXCLUDED`∪`KNOWN`)" that **reuses the existing maps** passes as a near-tautology
  the moment every fn is classified for `authenticated` — while actual anon *attacks* run on
  only the 4 #6306 fns. But **`auth.uid()=NULL` changes fn semantics**: every `EXCLUDED`
  rationale is reasoned under `authenticated` (`authorize_template: "founder_id = auth.uid()"`,
  `set_current_organization_id: "…for auth.uid()"`, `crm_contact_upsert: "founder_id =
  auth.uid()"`) — each is safe *because* the caller's uid IS the founder; under anon that
  premise evaporates, and a caller-override param (`COALESCE(p_caller, auth.uid())`) becomes
  fully attacker-controlled (learning `2026-06-01-caller-override-rpc-needs-service-role-only-grant`).
  **Decision required in the plan (do not defer to /work):** AC7's anon gate is scoped as
  **enumeration-coverage ONLY** — a green anon gate MUST NOT be read as "anon isolation
  proven." A separate, explicitly-tracked follow-up drives the full `ATTACK_SQL` set under anon
  with re-reasoned `EXCLUDED` rationales. (If /work has budget, fold that in; otherwise file it
  as a #6306-sibling issue in the same PR.) The near-tautology gate is acceptable ONLY with
  this scoping stated in-code and in the AC.

### Phase 3 — Model the user-isolation dimension (item 5) — attacker is a CO-MEMBER

The base matrix models *workspace* isolation (attacker = a **non-member** of wsA). The
distinct dimension here is **within-workspace user isolation**: a co-member of wsA reading
*another member's* `user_id = auth.uid()`-keyed rows. **The attacker MUST be `userC` (a
co-member of wsA), not `userB`** — spec-flow: with `userB` (a cross-workspace non-member),
a policy that isolates only by `workspace_id` and is *missing* the `user_id` clause still
denies B → false-green; the actual leak path (co-member reads another member's `api_keys`)
stays invisible.

- Add `userIsolationTables(sql)` to `catalog.ts`: RLS-enabled `public` tables whose
  PERMISSIVE `TO authenticated` policy references `auth.uid()` AND a `user_id`/`founder_id`
  column. **🟠 P1 — make the two sets disjoint IN SQL, not by human judgment (deepen
  architecture review).** `conversations`/`kb_files`/`kb_share_links` are documented in
  `targets.ts` as "user-keyed rows … workspace visibility overlaid" — they satisfy BOTH the
  `is_workspace_member` predicate AND the `auth.uid()`+`user_id` predicate, so a naive
  `userIsolationTables` returns them too. "Classify by the load-bearing predicate" is a
  human call a `pg_policies` query cannot execute → if placement is manual, AC1/AC3 stop
  being self-tracking (a new dual-membership table can be mis-placed or escape both). Encode
  a **deterministic partition in SQL**: `userIsolationSet := {auth.uid()+user_id predicate}
  MINUS isolationSet{is_workspace_member}`. Then the sets are disjoint *by construction*,
  their union covers the surface, and AC1/AC3 mutual-exhaustiveness is a proven property, not
  an assertion. (Three-way: a user-keyed table that also carries `workspace_id` still lands
  in `workspaceTenancyTables()`/AC1b — Phase 9 reconciles that.)
- Add `USER_ISOLATION_TARGETS` + `USER_EXCLUDED` (rationale-gated) to `targets.ts`, same
  coverage-gate discipline (registry ⇔ catalog).
- Seed **userA-owned** rows for `api_keys`, `user_session_state`, `tc_acceptances` (+ the
  user-keyed excluded three, below). Attacker `userC` (co-member): SELECT count=0,
  INSERT-forge → 42501, UPDATE/DELETE → 0-rows. **Positive control: owner userA reads/owns
  its own row.** **Negative control: co-member userC is denied** (this is the new path — no
  existing test drives a co-member attacker).
- New `rls-user-isolation.integration.test.ts` (or a `describe` in the base file) on the
  shared fixture.

### Phase 4 — Deepen the 6 EXCLUDED_ISOLATION tables (item 1)

Split by dimension; each leaves `EXCLUDED_ISOLATION` only when its faithful target lands
(AC1b keeps the rest honest).

- **Workspace-keyed (non-member `userB` model):** `inbox_item`, `workspace_member_actions`
  (both WORM), and `message_attachments` (EXISTS-join through `messages`). Decide
  per-table: real base target vs. tightened, justified exclusion (`message_attachments`
  object isolation is already AC9 via `storage.objects` — a sharpened metadata-row
  rationale is acceptable).
- **Per-table classification corrected against mig 111 + policy shapes (deepen data-integrity
  review):**
  - `dsar_export_jobs` — user-keyed (`auth.uid() = user_id`). Phase 4 target under the Phase 3
    co-member attacker model (NOT re-parented into Phase 3's named trio).
  - `action_sends` — user-keyed (`user_id = auth.uid()` SELECT **and** a real INSERT WITH
    CHECK); its WORM triggers are `BEFORE UPDATE/DELETE` only. **KEEP its INSERT-forge** — a
    cross-tenant INSERT-forge hits the genuine RLS WITH CHECK → 42501, a faithful, non-trigger-
    masked write test. Do NOT drop it.
  - `email_triage_items` — **NOT user-keyed.** Mig 111 dropped `..._owner_select` and replaced
    it with `is_email_triage_workspace_owner(workspace_id, auth.uid())` → it is **workspace-
    owner-gated** (a third predicate family, like AC1b). It does not match `userIsolationTables`
    and cannot "land under the AC3 dimension." Treat it as an **AC1b target/exclusion** (owner-
    gated), with co-member userC denied *by owner-gating*, not user-isolation. Its
    `seedEmailTriageItem` (resend-ingest shape: NOT NULL `claim_key` UNIQUE, `resend_email_id`,
    `subject`, `received_at`, `received_at_source`) is still built once in Phase 1's shared
    fixture (additive export) and reused by the Phase 7 `set_email_triage_status` RPC attack.
- **WORM-table write handling (corrected against the migrations — deepen data-integrity
  review P2).** The motivating "trigger 42501 ↔ RLS 42501 collision" **does not exist today**:
  all four tables' WORM triggers raise **P0001** (mig 102/122/063/051), which `verdict.ts`
  already scores as `test-error` (fails the case). The REAL bare-42501 false-green source is
  the **table-level `REVOKE INSERT … FROM authenticated`** on `email_triage_items`/`inbox_item`
  (mig 102:101-103): an authenticated INSERT-forge raises `42501 "permission denied for table …"`
  — a **grant** denial, not RLS — which the write-verdict would mis-score as an RLS denial.
  Required handling:
  1. **Drop the INSERT-forge ONLY where a table-level REVOKE or a pre-RLS trigger intercepts**
     — `email_triage_items`, `inbox_item` (INSERT REVOKE'd), `workspace_member_actions` (no
     INSERT policy). **KEEP the `action_sends` INSERT-forge** (real RLS WITH CHECK, INSERT not
     revoked, triggers are UPDATE/DELETE-only).
  2. For the drop-INSERT tables, carry the RLS isolation proof **solely on SELECT-USING
     visibility** (owner/service_role sees 1, attacker sees 0). The UPDATE/DELETE 0-rows on
     these tables is **vacuous** (no UPDATE/DELETE policy for anyone → default-deny, would pass
     even with no tenant filtering) — do NOT count it as isolation evidence. The positive
     control MUST be a **SELECT** (owner sees the row), never an UPDATE.
  3. **Do NOT add an RLS-policy-message-text discriminator to `verdict.ts`** — coupling a
     verdict to Postgres wording (locale/version-sensitive) is the most brittle possible
     oracle, and (per P2) the collision it would guard doesn't exist. `verdict.ts` needs no
     new discriminator.

### Phase 5 — Row-hijack WITH-CHECK variant (item 3 / F4) — attacker is the OWNER

spec-flow correction: running the hijack as `userB` is **vacuous** — USING filters A's row
for B → 0 rows → **WITH CHECK is never evaluated** → always "denied", proving nothing. A
WITH-CHECK probe is only meaningful run by an actor who **passes USING but should fail WITH
CHECK**: **tenant-A itself (or a wsA member) reassigning its own row's tenancy key to wsB.**

**🔴 Scope to tables with a real permissive UPDATE/ALL policy ONLY (deepen data-integrity
review P1).** Most workspace-keyed targets (`workspace_activity`, `scope_grants`,
`audit_byok_use`, `audit_github_token_use`, `worktree_write_lease`, `messages`, the
attestation/removal/invitation tables) are **SELECT/INSERT-only — no UPDATE policy for anyone**
(writes are RPC/service-role). On those the hijack returns 0 rows *because no UPDATE policy
exists* → a **vacuous** "denied", AND AC6's positive control ("A updates a non-tenancy col on
its own row") is **impossible** (userA has no UPDATE policy either). So:

- **Run the hijack ONLY on targets with a permissive UPDATE/ALL policy `TO authenticated`** —
  `conversations`, `kb_share_links`, `push_subscriptions`, `kb_files`. Derive this set from the
  catalog at /work, do not hand-list.
- Under **A's own claims** (rolled back): `UPDATE "<t>" SET workspace_id = <wsB> WHERE <A row>
  RETURNING id`. Verdict: 0 rows or 42501 = denied; **any returned row now carrying `wsB` = leaked.**
- **Positive control:** A updates a non-tenancy column on its own row; **also assert
  `is_workspace_member(wsB, userA) = false`** before trusting a `denied` verdict (the oracle is
  sound only while userA is a non-member of wsB — a fixture invariant, currently held, unasserted).
- **🔴 `kb_files` is a REAL latent exposure the hijack WILL surface (deepen review P1):** its
  UPDATE WITH CHECK is `user_id = auth.uid()` **only** — no membership check on the NEW row
  (unlike its INSERT WITH CHECK) — so owner userA CAN `SET workspace_id = wsB`, re-homing the
  file into wsB where wsB's members can read it. The hijack correctly emits `leaked`.
  **Pre-decide (do NOT let /work loosen the oracle):** baseline as a `test.fails` + a filed
  tracking issue (the KNOWN_EXPOSURES precedent) if it is a real exposure, OR a documented
  per-table carve-out if user-keyed re-home is intended. Escalate to the security owner.
- **Skip WORM tables** — the BEFORE-UPDATE trigger intercepts before WITH CHECK.

### Phase 6 — Anon attacks on the 4 #6306 fns (item 4, attack half)

- Drive `find_stuck_active_conversations`, `acquire/release/touch_conversation_slot` under
  `anon` (role `anon`, `buildAnonClaims()`, no `sub`) — via `rolledBackRaw` + an explicit
  `set local role anon`.
- **🔴 P0 — the write-exposure observation MUST `reset role` mid-txn (deepen security review).**
  Three of the four #6306 fns are WRITES (`acquire`/`release`/`touch` slot). The existing
  *authenticated* `test.fails` re-read `user_concurrency_slots` after `reset role` to observe
  the mutation **as superuser** — load-bearing because `user_concurrency_slots` has a
  workspace-member SELECT policy. Under `anon` (`auth.uid()=NULL`, no membership) that SELECT
  policy **hides A's slot unconditionally** → the poison re-read returns `count=0` *regardless
  of whether the attack mutated it*. Without a `reset role` (or a service_role re-read) before
  the observation, the `stillPresent > 0` assertion is forced false → `test.fails` reports
  **green permanently**, AND when #6306 is fixed the slot survives but anon still sees `0` → the
  assertion never starts passing → **the un-baseline signal never fires**. The anon write-attack
  observation MUST mirror the authenticated variant's `reset role`/service_role re-read. Encode
  this explicitly here and in AC7 — do NOT leave it to "mirror the #6306 tests."
- **Anon positive control:** assert `auth.uid() IS NULL` under the anon txn — else a
  mis-set role (running as superuser) makes every anon "denial" vacuous.
- Give the anon variants their **own `test.fails` entries** keyed to #6306 — a grant fix
  could close the `authenticated` grant while leaving `anon` open, so one does not cover
  the other. Green while exposed, RED when the anon grant is fixed.

### Phase 7 — Faithful RPC attacks for the 2 EXCLUDED fns (item 2)

- **`set_email_triage_status`:** reuse `seedEmailTriageItem` to land a **real userA-owned**
  triage item, then attack under `sub = userB` (workspace-owner-gated) / co-member. The
  seed MUST be real — a faithless seed → `P0002 no_data_found` → scored `denied` = vacuous
  (the F2 trap). Move `EXCLUDED` → `ATTACK_SQL` (delete the EXCLUDED key or the `dupes`
  gate reds).
- **`authorize_template`:** founder-scoped; **`driveDenied`'s "non-null ⇒ leaked" is WRONG
  here** — B authorizing B's own template legally returns a non-null id. The attack must
  seed a **real userA-owned `scope_grant`**, drive `authorize_template` as `userB` passing
  **userA's `p_grant_id`**, and assert via a **bespoke check that no template_authorization
  row was written referencing A's grant** (distinguishes "accepted foreign grant" = leaked
  from "rejected" = denied). Do not rely on the generic scalar classifier.
- **Positive controls:** owner-A can `set_email_triage_status` / `authorize_template` on
  the same fixture row (proves the row exists and the guard is ownership, not not-found).

### Phase 8 — RPC mutation self-test (item 7)

Mirror base-matrix AC5 for the RPC dimension: prove the RPC harness can report RED.

- In a rolled-back txn, **strip a guard** and drive a fn cross-tenant, asserting
  `classifyRpcOutcome` yields `{kind:"leaked"}` specifically (not merely "verdict changed").
- **Strip the guard on a fn reading a POISONED non-sentinel A value** (e.g. a getter over
  `debug_mode=true` / `installation_id=424242`) — spec-flow: stripping a guard on a
  null-defaulting getter does NOT flip (still returns null → still "denied"), so the
  self-test would falsely fail as a harness bug. The leak must be observable.
- Prefer a **scratch `SECURITY DEFINER` fn** (trusts a caller param, granted to
  `authenticated`, dropped on rollback) over `CREATE OR REPLACE` of a real fn — a
  replacement that changes return shape flips the classifier for the wrong reason (shape
  artifact, not guard removal). Keep the replacement faithful if used.

### Phase 9 — Verify `routine_runs` / `routine_run_progress` (item 6) — ENFORCE, don't assert

The harness only expresses *denial* assertions; an intentional-global table has no
falsifiable guard, so "ops-global, no PII" in prose is **unfalsifiable** — a future
migration adding a PII/`workspace_id` column would leak with a green suite.

- Add a **schema-pinning assertion**: the live column set of `routine_runs` /
  `routine_run_progress` ⊆ an allowlisted non-PII column set, AND **no `workspace_id` /
  `user_id` column present**. If either grows a tenant-identifying column, the assertion
  reds — turning "intentional global" into an enforced invariant.
- Note: if these tables DO carry `workspace_id`, they already surface in
  `workspaceTenancyTables()` and MUST be targeted-or-excluded under AC1b — a silent
  exclusion there would defeat AC1b. Reconcile the two gates.
- Share this schema-pin pattern with any remaining `EXCLUDED_ISOLATION` rationale (Phase 4).

### Phase 10 — Harness ADR amendment + docs

- **Amend the harness ADR** (real ordinal resolved in Phase 0) to record the deepened
  scope: the user-isolation dimension, the anon dimension, the `proname+args` gate key,
  and the deepened excluded surfaces. This is an in-scope deliverable, not a deferred
  issue (`wg-architecture-decision-is-a-plan-deliverable`). Add the user-isolation
  dimension to the ADR's Decision + note it in Consequences.
- `## C4 impact`: **None** — same rationale as the harness ADR (dev/CI tooling outside
  the modeled boundary; no new external actor/system, no product data store, no prod
  access-relationship). Verified against `model.c4`/`views.c4`/`spec.c4` at /work.
- If routine_runs (Phase 9) surfaces a finding, cross-link the new issue.

## Files to Edit

- `apps/web-platform/test/rls-fuzz/targets.ts` — new `USER_ISOLATION_TARGETS`/`USER_EXCLUDED`; move 6 tables out of `EXCLUDED_ISOLATION`; row-hijack + WORM-trigger fields.
- `apps/web-platform/test/rls-fuzz/rpc-cases.ts` — `proname(args)` re-key; `set_email_triage_status` + `authorize_template` EXCLUDED→ATTACK; anon coverage; `RpcCtx` extension for email-triage seed.
- `apps/web-platform/test/rls-fuzz/catalog.ts` — `userIsolationTables()`, `securityDefinerAnonFns()`; AC8 gate consumes `{proname,args}`.
- `apps/web-platform/test/rls-fuzz/verdict.ts` — **likely NO change** (deepen review dropped the message-text discriminator; WORM tables carry no write-denial assertion, so the existing classifiers suffice). Touch only if the RPC self-test needs a `{kind:"leaked"}` helper.
- `apps/web-platform/test/rls-fuzz/rls-authz-fuzz.integration.test.ts` — migrate to shared fixture; owner-driven row-hijack WITH-CHECK variant; routine_runs schema-pin assertion.
- `apps/web-platform/test/rls-fuzz/rls-rpc.integration.test.ts` — migrate to shared fixture; anon attacks (+ `auth.uid() IS NULL` control); RPC self-test; `proname(args)` gate; new EXCLUDED→ATTACK cases.
- `apps/web-platform/test/rls-fuzz/rls-storage.integration.test.ts` — migrate to shared fixture (no behavioral change).
- `apps/web-platform/test/rls-fuzz/claim.ts` — only if the anon path needs a claim-shape tweak (likely none; `buildAnonClaims` exists).
- The harness ADR (real ordinal) — Phase 10 amendment.

## Files to Create

- `apps/web-platform/test/rls-fuzz/harness-fixture.ts` — union-superset shared module: `connect` (`max:1`), `seedTwoTenant`, `seedEmailTriageItem`, the three txn helpers (`attackAs`/`rolledBackRaw`/`asTenant`), poisoned-flag seeding, fixture self-check.
- `apps/web-platform/test/rls-fuzz/rls-user-isolation.integration.test.ts` — user-isolation dimension driver (or a `describe` block folded into the base file; decide at /work for fixture-reuse cost).

## Open Code-Review Overlap

None. (Verified at plan time — the harness files exist only on the unmerged #6255 branch,
so no `origin/main` open code-review issue can name them. Re-run
`gh issue list --label code-review --state open --json number,title,body` against the
final file list at /work Phase 0 after the #6255 rebase, since #6255's own review may
have filed scope-outs touching these paths.)

## Acceptance Criteria

### Pre-merge (PR)

- **AC1 (dependency):** PR #6255 is merged and this branch is rebased onto the post-merge
  `main`; `apps/web-platform/test/rls-fuzz/targets.ts` exists in-tree.
- **AC2 (fixture consolidation, union-superset):** `harness-fixture.ts` exists
  (non-`*.test.ts`); all three integration files import the shared `connect`/`seedTwoTenant`/
  txn helpers from it; **zero** in-file re-implementations of `seedContext`/`seedRpcCtx`/the
  rollback sentinels remain
  (`grep -c "async function seedContext\|async function seedRpcCtx" test/rls-fuzz/*.integration.test.ts` ⇒ 0).
  The module pins `max:1`; exports all three distinct txn helpers (`attackAs`/`rolledBackRaw`/
  `asTenant`); preserves the flag-poisoning; and runs a fixture self-check
  (`wsA!==wsB`, `orgA` present, userC is a wsA member, `debug_mode` reads back `true`).
- **AC3 (user-isolation dimension — CO-MEMBER attacker):** `userIsolationTables()` enumerates
  from the live catalog via the SQL set-difference partition (disjoint from AC1 by
  construction, so AC1/AC3 are provably mutually exhaustive). Named positive-control targets
  are **`api_keys` and `user_session_state`** — each with a **positive control (owner userA
  reads own row)** + a **co-member negative (userC denied)** + INSERT-forge=42501 +
  UPDATE/DELETE=0-rows. Attacker is `userC` (wsA co-member), NOT `userB`.
  **🟠 `tc_acceptances` is NOT an AC3 target (deepen data-integrity review):** it has RLS
  ENABLED with **ZERO policies** (service-role-only via `accept_terms`/anonymise RPCs, mig
  044:74) → owner userA reads 0 rows too → an owner positive control is schema-impossible, and
  `userIsolationTables` (reads `pg_policies`) never enumerates it. Place it in `USER_EXCLUDED`
  with that rationale (like `dsar_export_jobs`). Only tables the enumerator actually returns
  (a real `auth.uid()`-keyed permissive policy) can be AC3 targets — confirm each named
  target's policy shape at G0.4 before seeding.
- **AC4 (excluded deepened — per-table classification corrected):** `EXCLUDED_ISOLATION` no
  longer contains any table that now has a faithful target; each remaining exclusion carries a
  >20-char rationale (AC1b gate). Classification: `inbox_item`, `workspace_member_actions`,
  `message_attachments` → workspace-keyed (non-member `userB`) targets or tightened exclusions;
  `dsar_export_jobs`, `action_sends` → user-keyed, under the AC3 co-member attacker model;
  `email_triage_items` → **workspace-owner-gated (mig 111), an AC1b target/exclusion — NOT an
  AC3 user-isolation target** (its policy is `is_email_triage_workspace_owner(...)`, not
  `user_id=auth.uid()`).
- **AC5 (WORM-table write handling — corrected):** the INSERT-forge is dropped **only** where
  a table-level `REVOKE INSERT` or pre-RLS trigger intercepts (`email_triage_items`,
  `inbox_item`, `workspace_member_actions`); **`action_sends` KEEPS its INSERT-forge** (real
  RLS WITH CHECK → 42501). For the drop-INSERT tables the RLS proof is carried **solely on
  SELECT-USING visibility** with a **SELECT** positive control (owner sees the row) — the
  UPDATE/DELETE 0-rows is vacuous (default-deny, no policy) and is NOT counted as isolation
  evidence. **`verdict.ts` gains NO error-message-text discriminator** (the trigger-vs-RLS
  42501 collision does not exist — triggers raise P0001; the real bare-42501 risk is the grant
  REVOKE, handled by dropping those INSERT-forges).
- **AC6 (row-hijack WITH-CHECK — OWNER attacker, UPDATE-policy tables only):** the hijack runs
  **only on the catalog-derived set of targets that carry a permissive UPDATE/ALL policy**
  (`conversations`, `kb_share_links`, `push_subscriptions`, `kb_files`) — NOT the SELECT/INSERT-only
  targets (where it and its positive control are vacuous/impossible). Under A's own claims,
  `UPDATE … SET workspace_id = wsB … RETURNING id`; `denied` = 0 rows OR 42501, **any returned
  `wsB` row = leaked**; positive control = A updates a non-tenancy column on its own row AND
  `is_workspace_member(wsB, userA)=false` is asserted; `kb_files` is expected to emit `leaked`
  and is dispositioned (baseline `test.fails`+issue OR carve-out), not silently greened; WORM
  tables skipped.
- **AC7 (anon + proname+args):** the AC8 gate is keyed on a **catalog-derived** `proname(args)`
  composite (not hand-typed args); `securityDefinerAnonFns()` enumerator exists with a parallel
  anon coverage gate that reds on any unclassified anon-EXECUTE fn; the 4 #6306 fns are driven
  under `anon` via their **own** `test.fails` entries keyed #6306, with an `auth.uid() IS NULL`
  positive control confirming the anon role is actually set.
- **AC8 (RPC excluded→attack):** `set_email_triage_status` and `authorize_template` moved to
  `ATTACK_SQL` (keyed `proname(args)`; EXCLUDED keys deleted so `dupes` stays empty);
  `set_email_triage_status` seeds a REAL userA triage item (no P0002-vacuous pass);
  `authorize_template` seeds a REAL userA `scope_grant` and asserts via a bespoke "no
  template_authorization row references A's grant" check (not the generic non-null classifier);
  both have owner positive controls.
- **AC9 (RPC self-test):** an RPC verdict provably flips to `{kind:"leaked"}` when a guard is
  stripped in a rolled-back txn — on a fn reading a **poisoned non-sentinel** A value (so the
  leak is observable), preferably a scratch definer fn (no return-shape artifact).
- **AC10 (routine_runs — enforced, not asserted):** a schema-pinning assertion pins
  `routine_runs`/`routine_run_progress` columns ⊆ an allowlisted non-PII set AND asserts no
  `workspace_id`/`user_id` column, reconciled with AC1b; OR a finding issue is filed if a
  tenant-identifying column is present.
- **AC11 (suite green):** `bun run test:rls-fuzz` passes on the rebased tree; the KNOWN_EXPOSURES
  `test.fails` (authenticated + new anon) remain red-as-designed; vitest `skipped == 0`;
  `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` is clean.
- **AC12 (positive control per case — the dominant-false-green gate):** every new `denied`
  verdict added by this PR is paired with a positive control where the legitimate owner/member
  succeeds on the *exact* fixture row/param — so a `denied` cannot be reached via
  "the target never existed" (`P0002`/`22P02`/`count=0`-by-emptiness). No new case is exempt.
- **AC13 (anon P0 + enumeration-scope):** the anon write-attack observations (`acquire`/
  `release`/`touch` slot) `reset role`/re-read as service_role before the poison re-read (else
  `auth.uid()=NULL` hides the row → permanent green); the anon coverage gate is documented
  in-code + in this AC as **enumeration-coverage ONLY** (a green anon gate is NOT "anon
  isolation proven"), with a filed follow-up for full anon attack-coverage.
- **AC14 (DDL self-test post-rollback verification):** after the AC5 base-matrix RLS-disable
  and the Phase 8 RPC guard-strip self-tests, a post-txn read asserts RLS is re-enabled on the
  table AND the scratch definer fn is absent / the real fn definition is unchanged — so a DDL
  escape on the reused local DB cannot silently persist a guard-stripped `KNOWN_EXPOSURES` fn.
- **AC15 (Phase 0 shape assertion):** Phase 0 G0.4b confirms the #6255 HEAD `verdict.ts`
  exports + `RpcCtx` field set the later phases depend on, so a silent #6255 rework reds at
  Phase 0, not mid-implementation.

### Post-merge (operator)

- None. The harness runs in the `RLS authz fuzz` GitHub workflow on the paths it touches
  (`bun run test:rls-fuzz` + `rls:parity`); no operator step, no migration apply, no infra.
  (Automation: covered by CI.)

## Domain Review

**Domains relevant:** Engineering (security-testing) only.

Mechanical UI-surface override: no path in Files to Edit/Create matches the UI-surface
term list/globs — Product = **NONE**. No user-facing surface, no `.pen` wireframe required
(`wg-ui-feature-requires-pen-wireframe` N/A). No Finance/Legal/Sales/Marketing/Support/Ops
implications — this is dev/CI test tooling. The security-testing substance is reviewed at
deepen-plan by the data-integrity-guardian + security-sentinel + architecture-strategist
triad (single-user-incident threshold) — the appropriate lens for false-green detection,
not the CEO/design panel.

## Observability

The harness IS an observability instrument (it makes a latent isolation break loud). Its
own operational signal:

```yaml
liveness_signal:
  what: "the `RLS authz fuzz` GitHub Actions workflow result on PRs touching test/rls-fuzz/** or the migrations/policies it enumerates"
  cadence: "per-PR (path-filtered) + on merge to main"
  alert_target: "workflow failure = red check on the PR; CI Slack on main failure"
  configured_in: ".github/workflows/rls-authz-fuzz.yml"
error_reporting:
  destination: "vitest assertion output in the workflow log (a failed isolation/coverage AC fails the job)"
  fail_loud: "yes — a new false-green is caught by the coverage gates (AC1/AC1b/AC8) reding the suite; a real leak reds via a leaked verdict"
failure_modes:
  - mode: "a new isolated/user-keyed table or definer fn ships with no attack case"
    detection: "catalog⇔registry coverage gate (AC1/AC1b/AC3/AC8) fails in-suite"
    alert_route: "red workflow check on the introducing PR"
  - mode: "a KNOWN_EXPOSURE grant is fixed (good) but not un-baselined"
    detection: "the #6306 test.fails assertion starts passing → vitest reports the test.fails as failed"
    alert_route: "red workflow check, forcing un-baseline"
  - mode: "a real cross-tenant path opens on a fuzzed surface"
    detection: "a leaked verdict on the corresponding attack test"
    alert_route: "red workflow check"
logs:
  where: "GitHub Actions workflow run logs for `RLS authz fuzz`"
  retention: "GitHub default workflow-log retention"
discoverability_test:
  command: "gh run list --workflow 'RLS authz fuzz' --limit 5"
  expected_output: "recent runs with conclusion=success (and the intended test.fails staying green-as-designed)"
```

## Architecture Decision (ADR/C4)

### ADR

Amend **the harness ADR — `ADR-111-runtime-authz-rls-fuzz-harness.md`** (already renumbered
on #6255's branch; re-confirm filename at Phase 0). Record: the **user-isolation dimension**
(`user_id = auth.uid()`) as a first-class enumerated dimension alongside the workspace-isolation
and jti-deny dimensions; the **anon** attack dimension — which **promotes the DB _role_ to a
first-class attacker dimension** (ADR-111's Decision currently scopes "attacker dimension =
`sub`" under `SET LOCAL ROLE authenticated`; anon widens this to the role axis — call it out
explicitly, do not fold silently); the `proname(args)` coverage key; and the deepened
excluded-table coverage. No *new* ADR — this is an extension of the harness's existing
"enumerate from the live catalog / self-tracking" decision, not a reversal.

### C4 views

**No C4 impact.** Enumerated against all three model files at /work: no new external human
actor (attacker is a synthetic in-DB tenant, already conceptually within the test suite),
no new external system/vendor (all-local disposable Postgres), no new container/data-store
(reads existing migrated schema), no changed actor↔surface access relationship (dev/CI
tooling outside the modeled boundary). Same conclusion the harness ADR already recorded;
this plan does not widen the modeled system. Run `apps/web-platform/test/c4-code-syntax.test.ts`
+ `c4-render.test.ts` only if any `.c4` edit is made (none expected).

### Sequencing

The ADR amendment lands in this PR (Phase 9), describing the deepened target state.

## Test Scenarios

The plan's deliverable *is* tests. Cross-cutting scenarios beyond the per-item ACs:

- **Refactor safety (Phase 1):** after fixture extraction, the full pre-existing AC set
  passes byte-for-byte in behavior (RED→GREEN; the suite is its own regression test).
- **Non-vacuity:** every new attack has a positive control (owner can) OR a self-test
  (guard-off → RED). No new `denied` verdict may be reachable only via `count=0`/`null`
  without a paired positive control proving the value would differ under the owner.
- **Coverage-gate self-tracking:** adding a synthetic user-keyed RLS table with no target
  reds AC3; a new anon-EXECUTE definer fn reds AC7 — proving the enumerators, not a
  hand-list, drive coverage.
- **KNOWN_EXPOSURE lifecycle:** with #6306 unfixed, the 4 `test.fails` stay green; simulate
  a fix (grant revoke in a rolled-back txn) → the assertion passes → `test.fails` reports
  failure, forcing un-baseline.

## SpecFlow Analysis — false-green corrections (folded into the phases above)

Spec-flow (single-user-incident lens) surfaced six would-be false-greens, all now
encoded in the Implementation Phases + ACs. Summary map (referenced by concept, not a
second phase numbering):

1. **Positive control per new case** — the dominant false-green: `classifyMutationOutcome`
   and the RPC `P0002 = denial` rule turn *any* pre-auth failure (row never existed,
   `22P02`, `23xxx`) into green. → guardrail note atop Implementation Phases + **AC12**.
2. **WORM write handling** (superseded by deepen data-integrity review — see Enhancement
   Summary #5): the four WORM triggers raise **P0001** (already `test-error`), so no
   trigger-42501↔RLS-42501 collision exists; the real bare-42501 risk is the table-level
   `REVOKE INSERT`. → Phase 4 drops the INSERT-forge only where REVOKE/no-INSERT-policy
   intercepts (**keeps `action_sends`**), carries the proof on SELECT-visibility, and adds
   **no** `verdict.ts` message-text discriminator (AC5).
3. **Row-hijack attacker = the OWNER, not tenant-B** — run as B, USING filters A's row → WITH
   CHECK never evaluated → vacuous "denied". → Phase 5 runs `SET workspace_id=wsB` under A's
   own claims; a returned `wsB` row = leaked (AC6).
4. **User-isolation attacker = a co-member (userC), not cross-workspace userB** — userB is
   denied by workspace isolation even when the `user_id` clause is missing → the within-
   workspace user-leak stays invisible. → Phase 3 attacks with userC + owner positive +
   co-member negative (AC3).
5. **`authorize_template` returns non-null on the legitimate path** — the generic
   "non-null ⇒ leaked" classifier is wrong; the attack must seed a real A-owned grant and
   assert no template_authorization row references A's grant. → Phase 7 bespoke assertion (AC8).
6. **Catalog-sourced `proname(args)` key + anon** — hand-typed args drift from
   `pg_get_function_identity_arguments` (`character varying` vs `varchar`); the anon fns need
   their own `test.fails` + an `auth.uid() IS NULL` control; `routine_runs` exclusion needs a
   schema-pin (enforced, not prose); the RPC self-test must strip a guard on a *poisoned
   non-sentinel* value. → Phases 2/6/8/9 (AC7/AC9/AC10).

## Risks & Sharp Edges

- **Fixture-merge (Phase 1/8) — union superset, not lossy intersection.** The three rollback
  helpers are NOT interchangeable: `attackTxn` sets role+claims inside; the RPC `rolledBack`
  deliberately does NOT (callers set role; KNOWN_EXPOSURE tests `reset role` mid-txn to observe
  as superuser); `asTenant` sets by `sub`. The merged module must export all three, preserve
  per-sentinel rethrow, and NOT pre-set role universally. **`max:1` is load-bearing** —
  `set local role`/`set_config` are per-connection; a pool > 1 could run the attack on a
  different connection than the one claims were set on → total false-green. The flag-poisoning
  (`debug_mode=true`/`installation_id=424242`) MUST survive the merge.

- **WORM-trigger false-green (highest):** a table whose BEFORE-INSERT trigger raises P0001
  for a *non-authorization* reason must NOT have that P0001 scored as an RLS denial. Resolve
  per-table via Phase 0 G0.4 evidence; default to forge-omission. deepen-plan
  data-integrity-guardian should scrutinize each of the 4 WORM tables individually.
- **`proname`→`proname(args)` re-key churn:** every existing `ATTACK_SQL`/`EXCLUDED`/
  `KNOWN_EXPOSURES` key changes shape simultaneously with the AC8 gate; a partial migration
  reds the gate. Do the re-key as one atomic edit with the gate, before adding new cases.
- **User-iso vs workspace-iso double-membership:** a table may satisfy BOTH the
  `is_workspace_member` set and the `user_id = auth.uid()` set. Classify by the
  load-bearing predicate; a table appearing in both enumerators must not double-count or
  escape both registries. The AC1/AC3 gates must be mutually exhaustive, not overlapping-blind.
- **email_triage_items ingest fixture is shared** between the Phase 4 base-table (owner-gated)
  seed and the Phase 7 `set_email_triage_status` RPC attack — build it once in the shared fixture, not twice (the exact
  divergence item 8 exists to prevent).
- **`securityDefinerAnonFns` may enumerate MORE than the 4 #6306 fns** — Supabase default
  privileges grant EXECUTE to `anon` broadly. Any anon-EXECUTE definer fn that is not a
  known exposure must be classified or the anon gate reds; budget for triaging that list at
  /work (it may itself surface new findings — treat as #6306-class, track don't hide).
- **Test-discovery:** new `*.integration.test.ts` under `test/rls-fuzz/` match the vitest
  `unit` project glob `test/**/*.test.ts` and are run by `vitest run test/rls-fuzz`;
  `harness-fixture.ts` must NOT be named `*.test.ts` (it is a helper, not a suite).
- **ADR ordinal:** never pin the harness ADR by number in this plan's artifacts beyond
  "resolve at Phase 0"; the #6255 ship collision gate owns the real ordinal.

## Alternatives Considered

| Option | Verdict | Reason |
|---|---|---|
| Stack this PR on `feat-t3mp3st-security-eval` (base ≠ main) | Rejected | Complex stacked-PR flow; #6255 must merge first anyway. Rebase-after-merge is simpler and keeps the #6307 diff scoped to its own changes. |
| Deepen excluded tables without first modeling the user-isolation dimension | Rejected | 3 of the 6 excluded tables are user-keyed; attacking them with the non-member `sub=userB` model is unfaithful (a non-member of *no* workspace is not the isolation these tables enforce). Item 5 must precede the user-keyed slice of item 1. |
| Blanket "any P0001 = RPC/write denial" for WORM tables | Rejected | Masks a real leak on a table whose trigger raises P0001 for a non-auth reason; violates the harness's 42501-discipline (verdict.ts). Per-table evidence-based classification only. |
| Skip the fixture extraction (item 8) and add tests to the 3 forked copies | Rejected | The three copies have already begun to diverge (issue text); adding 3 more dimensions triples the divergence. Extraction first is the enabling refactor. |
| Hand-list the anon attack surface instead of a catalog enumerator | Rejected | Defeats the harness's self-tracking invariant; a future anon-granted definer fn would silently escape. Enumerate from `has_function_privilege('anon', …)`. |
