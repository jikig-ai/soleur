# Tasks — Harden RLS/authz-fuzz harness (#6307)

Derived from `knowledge-base/project/plans/2026-07-11-chore-rls-fuzz-harden-deepen-excluded-plan.md`.
lane: single-domain · brand_survival_threshold: single-user incident · depends_on: PR #6255.

> ⛔ **BLOCKED until PR #6255 merges.** The harness files exist only on
> `feat-t3mp3st-security-eval`, not on `main`, so nothing in this list is editable yet.
> Task 0.1 is a hard gate.

> **Global guardrail (applies to every new attack case):** ship a paired POSITIVE
> CONTROL (legitimate owner/member succeeds on the exact fixture row) — AC12.

## Phase 0 — Preconditions (hard gates)

- [ ] 0.1 `gh pr view 6255 --json state -q .state` == `MERGED` (else STOP).
- [ ] 0.2 `git rebase origin/main`; confirm `apps/web-platform/test/rls-fuzz/targets.ts` in-tree.
- [ ] 0.3 Resolve the harness ADR real filename/ordinal (`ls …/decisions | grep -i rls-fuzz`).
- [ ] 0.4 Local stack up (`supabase start` → `bash scripts/run-migrations.sh`); read-only confirm:
      anon EXECUTE on the 4 #6306 fns; **pre-scope the FULL anon-EXECUTE definer-fn set + caller-param
      count** (`securityDefinerAnonFns`); `routine_runs`/`routine_run_progress` columns + SELECT policy;
      each WORM trigger's SQLSTATE (expect P0001) + the REVOKE-INSERT grant-42501; whether
      `pg_get_function_identity_arguments` returns names or types-only; confirm no `proname` in the set is overloaded.
- [ ] 0.4b Shape assertion: `verdict.ts` exports (`classifyRpcOutcome`/`classifyMutationOutcome` → `{kind}`) +
      `RpcCtx` field set match #6255 HEAD (reds Phase 0 on a silent rework).
- [ ] 0.5 Baseline `bun run test:rls-fuzz` green (KNOWN_EXPOSURES `test.fails` red-as-designed).
- [ ] 0.6 Re-run the open code-review overlap query against the final file list.

## Phase 1 — Shared `harness-fixture.ts` (union superset) [item 8]

- [ ] 1.1 Create `harness-fixture.ts` (non-`*.test.ts`): `connect` (`max:1,prepare:false`),
      `seedTwoTenant`, `seedEmailTriageItem`, poisoned-flag seeding.
- [ ] 1.2 Export all three txn helpers as distinct shapes: `attackAs` (sets role+claims),
      `rolledBackRaw` (no role set; supports `reset role` mid-txn), `asTenant` (by `sub`);
      preserve per-sentinel rethrow.
- [ ] 1.3 Fixture self-check: `wsA!==wsB`, `orgA` present, userC ∈ wsA, `debug_mode` reads back `true`.
- [ ] 1.4 Migrate all three integration files to it — ZERO behavioral change (all existing ACs +
      `test.fails` unchanged). Design interface as the target superset so Phases 3–7 only ADD seeds.

## Phase 2 — RPC coverage re-key + anon enumerator [item 4 structural]

- [ ] 2.1 Re-key `ATTACK_SQL`/`EXCLUDED`/`KNOWN_EXPOSURES` + the AC8 gate to a **catalog-sourced**
      `proname(args)` composite (`pg_get_function_identity_arguments`) — atomic; not hand-typed.
- [ ] 2.2 Add `securityDefinerAnonFns()` to `catalog.ts` (`has_function_privilege('anon',…)`) +
      a parallel anon coverage gate; fail loud on unresolvable, never skip.

## Phase 3 — User-isolation dimension (CO-MEMBER attacker) [item 5]

- [ ] 3.1 Add `userIsolationTables()` to `catalog.ts` as a **SQL set-difference** ({auth.uid()+user_id}
      MINUS is_workspace_member set) so it is disjoint from `isolationSet` by construction; add
      `USER_ISOLATION_TARGETS`/`USER_EXCLUDED` to `targets.ts`.
- [ ] 3.2 Seed userA-owned rows for `api_keys`, `user_session_state` only (attacker **userC**
      co-member): SELECT=0, INSERT-forge=42501, UPDATE/DELETE=0-rows. **`tc_acceptances` → `USER_EXCLUDED`**
      (zero RLS policies; owner positive control impossible; not enumerated).
- [ ] 3.3 Positive control (owner userA reads own row) + negative (co-member userC denied) per target.
- [ ] 3.4 New `rls-user-isolation.integration.test.ts` (or a base-file `describe`).

## Phase 4 — Deepen the 6 EXCLUDED_ISOLATION tables [item 1]

- [ ] 4.1 Workspace-keyed: `inbox_item`, `workspace_member_actions`, `message_attachments` — target
      or tightened exclusion.
- [ ] 4.2 User-keyed `dsar_export_jobs`/`action_sends` → co-member attacker model; **`email_triage_items`
      is workspace-OWNER-gated (mig 111) → AC1b target/exclusion, NOT AC3**. Build `seedEmailTriageItem`
      in Phase 1 fixture (shared with Phase 7).
- [ ] 4.3 WORM handling: triggers raise **P0001** (already `test-error`); drop INSERT-forge ONLY where
      REVOKE INSERT / no-INSERT-policy intercepts (`email_triage_items`,`inbox_item`,`workspace_member_actions`);
      **KEEP `action_sends` INSERT-forge** (real RLS WITH CHECK). SELECT-visibility is the WORM proof; SELECT
      positive control. **No `verdict.ts` message-text discriminator.**
- [ ] 4.4 Remove each deepened table from `EXCLUDED_ISOLATION` (keep AC1b partition exact).

## Phase 5 — Row-hijack WITH-CHECK variant (OWNER attacker) [item 3]

- [ ] 5.1 **Scope to UPDATE-policy-bearing targets ONLY** (`conversations`, `kb_share_links`,
      `push_subscriptions`, `kb_files` — catalog-derived); under A's own claims:
      `UPDATE … SET workspace_id=wsB … RETURNING id`; denied ⇔ 0 rows OR 42501; any returned `wsB` row = leaked.
- [ ] 5.2 Positive control: A updates a non-tenancy column on its own row + assert `is_workspace_member(wsB,userA)=false`.
      **`kb_files` expected `leaked`** (user_id-only UPDATE WITH CHECK) → baseline `test.fails`+issue OR carve-out. Skip WORM.

## Phase 6 — Anon attacks on the 4 #6306 fns [item 4 attack]

- [ ] 6.1 Drive the 4 fns under `anon` (`rolledBackRaw` + `set local role anon`) with their OWN
      `test.fails` entries keyed #6306. **Write-attacks (`acquire`/`release`/`touch`) MUST `reset role`/
      re-read as service_role before the poison re-read** (else `auth.uid()=NULL` hides the row → permanent green).
- [ ] 6.2 Anon positive control: assert `auth.uid() IS NULL` under the anon txn. Anon gate is enumeration-only.

## Phase 7 — Faithful RPC attacks for the 2 EXCLUDED fns [item 2]

- [ ] 7.1 `set_email_triage_status`: seed a REAL userA triage item (no P0002-vacuous); EXCLUDED→ATTACK;
      owner positive control.
- [ ] 7.2 `authorize_template`: seed a REAL userA `scope_grant`; drive as userB with A's `p_grant_id`;
      bespoke assert "no template_authorization row references A's grant"; owner positive control.

## Phase 8 — RPC mutation self-test [item 7]

- [ ] 8.1 Strip a guard in a rolled-back txn on a fn reading a POISONED non-sentinel value (prefer a
      scratch definer fn); assert `classifyRpcOutcome` == `{kind:"leaked"}`.
- [ ] 8.2 Post-rollback verify RLS re-enabled (AC5) + scratch fn absent / real fn unchanged (AC14).

## Phase 9 — routine_runs / routine_run_progress (ENFORCE) [item 6]

- [ ] 9.1 Schema-pin assertion: columns ⊆ allowlisted non-PII set AND no `workspace_id`/`user_id`;
      reconcile with AC1b. File a finding issue if a tenant-identifying column is present.

## Phase 10 — ADR amendment + docs

- [ ] 10.1 Amend the harness ADR (real ordinal): user-isolation dimension, anon dimension,
      `proname(args)` key, deepened excluded coverage. Add to Decision + Consequences.
- [ ] 10.2 Confirm `## C4 impact: None` against all three `.c4` files.

## Exit gate

- [ ] E.1 `bun run test:rls-fuzz` green; KNOWN_EXPOSURES `test.fails` (authenticated + anon) red-as-designed; vitest `skipped==0`.
- [ ] E.2 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean.
- [ ] E.3 All AC1–AC15 satisfied (incl. AC13 anon reset-role + enumeration-only, AC14 DDL post-rollback verify, AC15 shape assertion).
