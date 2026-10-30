---
title: "fix: messages owner draft UPDATE policy, column-narrowed grant, and #11572 hygiene"
type: fix
date: 2026-10-30
slug: fix-messages-update-policy-and-harness-hygiene
branch: feat-one-shot-11569-11572-messages-update-policy
issue: 11569
closes: [11569, 11572]
priority: p1-high
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
---

# fix: messages owner draft UPDATE policy, column-narrowed grant, and #11572 hygiene

## Enhancement Summary

**Deepened on:** 2026-10-30
**Sections enhanced:** Scope Check (Split Assessment recommendation), Observability (single-file probe), Product/UX Gate (wireframe baseline and exemption), Phase 3 step 6 (test location), Research Insights (deepen verification).
**Research used:** the 5-seat plan-review panel (DHH, Kieran, code-simplicity, architecture-strategist, spec-flow), CTO and CPO rulings, GDPR gate, live read-only prd/dev catalog and Sentry/Better Stack reads, and the deepen-plan halt gates below.

### Key Improvements
1. Kieran's P0: `verify/174_api_data_grants_snapshot.sql` asserts table-level UPDATE on `messages` and would have failed `verify-migrations` on prd, gating the deploy; it is now an edit in this PR.
2. The fuzz targets would have gone vacuous after the column narrowing (denials from the column privilege, not the policy); `targets.ts` and the hijack helper are now in scope, and the tenant test separates the two layers by error message.
3. Spec-flow corrected the premise: the prod backlog is 1898 github + 45 kb-drift drafts (no Stripe drafts), and draft cards are author-only end to end; the Today fetch needs `cache: "no-store"` and Discard/Edit/Dismiss need an "already handled" 403 line.
4. The "re-authorize" promise in the 403 and Settings copy is false in the current gate; the strings now promise nothing and the gap is #11630.

### New Considerations Discovered
- Ordinal 181 vs the unmerged 179 (#11593): a dev-ledger drift risk; sequencing is a Phase 2 step.
- ADR-303 needs a one-bullet amendment (Phase 2.10 test).

## Overview

One PR closes #11569 and #11572 (the PR body carries `Closes #11569` and `Closes #11572` on separate lines).

**#11569 (P1).** Production `public.messages` has no permissive UPDATE policy, so the cookie-client UPDATEs in the
Discard, Edit and send-archive routes match zero rows (1943 draft rows, 0 archived, measured 2026-10-30; by source they
are 1898 `github` and 45 `kb-drift`, no Stripe drafts, so what the fix unblocks in prod today is the send-route archive
and the kb-drift digest Dismiss, while the Discard and Edit buttons exist on the Stripe card only). Migration
`181` adds a PERMISSIVE UPDATE policy for `authenticated` keyed on `is_workspace_member(workspace_id, (SELECT auth.uid()))`
plus the `user_id` filter the routes already apply, scoped to draft rows (CTO D1), and in the same transaction narrows
the table-level UPDATE grant to `status` and `draft_preview` (CTO D2) so the new write path cannot be used to rewrite
authorization-relevant columns. The dev and prod policy sets were compared read-only first and are identical.

**#11572.** Items 7 and 12 (card copy, now that the policy exists) and 13 (stdin hang) are code changes; items 8, 9
and 11 harden the shared mutation harness (`scripts/lib/mutation-harness.sh`); items 3, 5 and 10 were resolved by
measurement or ruling and become header comments; items 4 and 6 move to the new tracking issue #11628. Draft cards are
author-only end to end (the Today list already filters `user_id`), so whether other Owners of a team workspace should
see and act on them is a product question tracked as #11629; the missing recovery path after a template authorization is
revoked, expires or is exhausted is #11630.

## Research Insights

### Premise Validation (Phase 0.6)

- #11569 and #11572 are both OPEN; no merged PR closes either (`gh issue view`). The only open PR naming them is this
  PR's own draft (#11622); the other `collision-precheck.sh` hits are unrelated `test-all.sh` runs in sibling worktrees.
- #11566 (merged 2026-10-30) is the cited predecessor: it shipped the shared harness lib, the scorer controls and the
  card copy, and it deliberately removed "or Discard it" from the Edit-409 string. Confirmed on `origin/main`:
  `scripts/lib/mutation-harness.sh` (107 lines), `today-card.tsx` Edit-409 branch, `DENY_REASON_COPY` at lines 107 to 118.
- #11569 premise MEASURED today (read-only, `PGOPTIONS=-c default_transaction_read_only=on`, DSN never printed,
  `doppler run -p soleur -c dev|prd`): the `pg_policies` set for `public.messages` is IDENTICAL on dev and prd (three
  policies: `messages_jti_not_denied` ALL RESTRICTIVE, `messages_workspace_member_insert`, `messages_workspace_member_select`;
  no UPDATE or ALL permissive policy). RLS on, not forced. `authenticated` holds table-level UPDATE on all 21 columns
  (mig 174 snapshot of Supabase defaults). No triggers. Prod: 2483 rows, 1943 `draft`, 0 `archived` (no archive has ever
  succeeded). The issue's table is confirmed; its "dev and prd differ" worry did not materialize for this table.
- The ADR corpus has no ADR that rejects an owner UPDATE policy on `messages`; ADR-303 (explicit data-API grants,
  two-tier table-grant guard) governs the column-grant question and mig 178 is the precedent for column narrowing.
- Migration ordinal: origin/main tops out at `180_approval_request`; `179_*` is held by open PR #11593 and `164` to `175`
  by other open PRs. This plan uses `181` provisionally; `soleur:ship` re-verifies against `origin/main`.

### Property List and Cut List (Phase 0.6b)

Properties (observable outcomes):

1. A signed-in workspace member can Discard, Edit and have the send route archive their own draft cards, and a draft
   they do not own, or one in another workspace, stays untouched.
2. The new write path is no wider than the three routes need (no client rewrite of chat history, no row reassignment).
3. Dev and prod converge on the same policy set without copying a policy name from one project into a migration for the other.
4. The Edit-409 and 403 copy names only actions that exist on the surface the founder is looking at and that work.
5. A probe suite cannot credit a mutant for the wrong row, and a hung stdin cannot stall `test-argv-bearer-sweep.sh`.

Cut List (mechanism, property it would buy, what already covers it):

- A SECURITY DEFINER RPC for discard/edit/archive -> property 1 -> the three routes already use the cookie client with
  `user_id` and `status` filters; a policy is one statement and matches the existing INSERT/SELECT shape. Cut.
- A Sentry alert on `messages-archive-no-row` -> property 1 -> the op already mirrors to Sentry (send route
  `archiveDraft`); after the policy it should stay at zero. Re-measure only (see Post-merge). Cut.
- A new follow-through probe for the soak -> property 1 -> a one-shot post-merge SQL read of the `archived` count is
  enough; no multi-day signal is gated on it. Cut.
- Adding an `environment:production` filter to the 11211 probe -> none (see D4 ruling) -> measured evidence below.

### Live measurements taken at plan time (read-only)

| Item | Measurement | Consequence |
|---|---|---|
| #11569 policy set | dev == prd (3 policies, no permissive UPDATE) | one migration, no dev/prd branch needed; still `IF`-guarded for drift |
| #11569 grants | `authenticated` UPDATE on all 21 columns, `anon` also holds UPDATE (no policy) | a row-only policy would let a member rewrite `content`/`role`/`workspace_id` of own rows via PostgREST; see D1/D2 |
| #11569 stuck drafts by source | prd `status = 'draft'`: 1898 `github` + 45 `kb-drift` (all `external_low_stakes`), 0 Stripe; 1740 are older than 7 days | Discard/Edit buttons (Stripe card only) have no prod drafts to act on; the backlog clears via Send (github) and Dismiss (kb-drift digest). Do not word the PR as "1943 drafts now discardable" |
| #11572 item 3 | `betterstack-query.sh --since 60d --grep <marker> --limit 5000` = 4 s (30d 5 s, 7d 2 s, 41 rows) vs `--max-time 60` | 15x headroom; exit 3 on timeout is the probe's honest CANNOT ESTABLISH; no behavior change |
| #11572 item 5 | Sentry org jikigai-eu, 30 d: `has:op` events environment=production 1564, null 17783; every `web-platform@x.y.z` release event is production; null-env events are host-side emitters; zero non-production environments exist | the premise "preview builds also report production" cannot occur today; a filter adds only false-zero risk |

### Institutional learnings applied

- `2026-05-21-rls-restrictive-policy-plus-column-grant-blocks-tenant-writes` and `2026-03-20-supabase-column-level-grant-override`:
  a table-level UPDATE grant makes column REVOKEs no-ops; narrow with `REVOKE UPDATE ON TABLE` first, then `GRANT UPDATE (cols)`; verify with `has_column_privilege`.
- `2026-07-18-rls-initplan-wrap-breaks-verify-sentinels-and-dev-prod-policy-divergence`: wrap `auth.uid()` as
  `(SELECT auth.uid())`, guard every policy statement with a `pg_policies` existence check, and write the verify sentinel
  against the DEPARSED form (`( SELECT auth.uid() AS uid)`).
- `2026-07-11-rls-migration-verify-savepoint-and-signature-scope`: a verify guard that raises aborts the transaction;
  assert the literal `user_id = ( SELECT auth.uid()` (a bare `%auth.uid()%` match is tautological because
  `is_workspace_member(..., auth.uid())` contains it).
- `2026-05-06-rls-zero-policies-anon-delete-204-semantic` and `2026-05-16-rls-deny-tests-payload-must-type-validate-or-they-pass-for-wrong-reason`:
  an RLS-hidden UPDATE returns zero rows, not an error; deny tests need a positive control, valid UUID payloads and a service-role re-read.
- `2026-09-18-my-mutation-harness-counted-a-crash-as-a-kill-and-the-fixture-stacked-x-on-x`: a non-zero exit with no FAIL line is UNRESOLVED, not KILLED; re-drive the whole battery on the commit candidate.
- `2026-09-24-editing-an-already-applied-migration-during-review-breaks-the-dev-ledger`: once the migration is applied to dev (tenant-integration does it on push) it is byte-immutable for the life of the PR, comments included; get the SQL right before the first push.

### Deepen-plan verification (2026-10-30)

| Gate | Result |
|---|---|
| 4.6 User-Brand Impact | present, threshold `single-user incident`, concrete artifact and vector |
| 4.7 Observability | five fields present; command starts with `bash`, no ssh, single verify file (well inside the 15 s cap); `expected_output` is the literal `messages_policy_single_permissive_update|0`; `credentials_required` declared with a justification (Check 10 reports SKIP-DECLARED) |
| 4.8 PAT-shaped variable | clean (grep empty) |
| 4.9 UI wireframe | UI glob hit on `today-card.tsx` and `dashboard/page.tsx`; copy-only exemption with committed baseline `.pen` files named in the Product/UX Gate and the AC6 diff invariant |
| 4.10 Encryption posture | skipped with reason (no new store or connection), matching the accepted precedent in `2026-10-06-fix-sandbox-canary-bridge-spawn-placeholder-plan.md` |
| 4.11 Guard Contract | `python3 scripts/lint-guard-contract.py` green, 3 entries, assemblies name chokepoints (catalog/ACL/`pg_policies`, `mutate_run`, the single `exec`) not member lists |
| 4.12 Scope Check | section present once (unfenced), Ask Mapping / Provenance / Split Assessment with a `Recommendation:` line, no `unmapped` rows |
| 4.13 Task design | no new autonomous-task surface (no workflow, Inngest function, cron) |
| Cited issues / PRs | all 12 numbers resolved live with `gh issue view` (#11193 CLOSED, #11486/#11520 CLOSED, #11566 MERGED, #11569/#11572/#11593/#11622/#11628/#11629/#11630/#3220 OPEN) |
| Cited rule IDs | `cq-write-failing-tests-before`, `wg-when-deferring-a-capability-create-a` exist in AGENTS.md |
| Cited paths | every ratchet script, test file, ADR and registry path in the plan exists in `git ls-files` |
| Attribution | `a48479b3a7` (#11253) touched `verify/174` (confirmed); ADR-303 line 70 defers narrowing to #11193 (confirmed) |
| Labels | `type/bug`, `type/feature`, `type/chore`, `domain/product`, `domain/engineering`, `priority/p2-medium`, `priority/p3-low`, `deferred-scope-out` exist; #11628, #11629, #11630 were created with them |
| tasks.md | propagated: verify/174 edit, targets.ts, ADR-303, 403 copy, no-store fetch, extended census |

### Related code (anchors, not line numbers)

- Routes: `apps/web-platform/app/api/dashboard/today/[id]/{discard,edit,send}/route.ts` (the send route comment on
  `archiveDraft` says "RLS owner-update"; that policy never existed).
- Policy precedent: `apps/web-platform/supabase/migrations/059_workspace_keyed_rls_sweep.sql` (messages select/insert),
  `134_rls_initplan_hotspots.sql` (`conversations_owner_update`, `kb_files_owner_update`), `178_api_data_grants_narrowing.sql` (column grants).
- Test layers that will see the change: `apps/web-platform/test/rls-fuzz/` (`targets.ts` has a `messages` target with
  `updateCol: "workspace_id"`; `table-grants.ts` OVERRIDES has no `messages` entry), `test/server/*.tenant-isolation.test.ts`
  pattern (`approval-request.tenant-isolation.test.ts`), `supabase/verify/NNN_*.sql` run by `scripts/run-verify.sh` against prd.

### Research Reconciliation: issue text vs codebase

| Issue claim | Reality | Plan response |
|---|---|---|
| #11569: "keyed on is_workspace_member plus the user_id filter" | Right, but `authenticated` also holds UPDATE on every column | Add D1/D2: scope rows to draft cards and (per ruling) columns to `status`, `draft_preview` |
| #11572 item 10: "docker-run-tuple.test.sh carries a third instrument_selftest not migrated to the lib" | It sources a different lib, `apps/web-platform/infra/lib/mutation-scorer.sh`, with a different protocol; the followthrough lib is not its shape | See D6 ruling |
| #11572 item 4: seams named `INNGEST_ZOT_BOOT_QUERY_BIN`, `DESTROY_ASK_QUERY_SCRIPT`, `IMAGE_CVE_QUERY_SCRIPT` | Located at `inngest-zot-boot-7462.sh`, `hosted-destroy-ask-window-9776.sh`, `image-cve-scan-window-9826.sh`; each has its own suite | See D5 ruling |
| #11572 item 13: "stub docker waits on inherited stdin" | Confirmed: the suite's S6 stub `docker` runs `pw="$(cat)"` unconditionally and `s6_run_step` has no stdin redirect | `exec < /dev/null` at the head of the suite |
| send route comment: "RLS owner-update" | No such policy existed | Comment becomes true; no edit needed beyond a pointer to the migration |

## Open Code-Review Overlap

One open code-review issue names a path this plan touches: #3220 ("ci: postmerge verification of trigger-bearing
migrations in prd"). **Acknowledge.** Migration 181 creates a policy and changes a column grant and carries no trigger, so
#3220's subject (trigger-bearing migrations) does not apply; it stays open. No other open `code-review` issue names any
file in Files to Edit / Files to Create (checked per path with `jq --arg`).

## Scope Check

### Ask Mapping

| Ask (task brief) | Plan item |
|---|---|
| Add the owner-scoped PERMISSIVE UPDATE policy for `authenticated`, keyed on `is_workspace_member(workspace_id, (SELECT auth.uid()))` plus the `user_id` filter | Phase 2 (migration 181, policy `messages_owner_draft_update`) |
| Compare the dev and prod policy sets read-only first; never copy policy names from prod into a dev migration | Research Insights (measured, identical); migration names its own policy and guards with `DROP POLICY IF EXISTS` |
| Production apply through the normal migration path with its gates; do not paper over with copy | Phase 6 + Acceptance (dev rehearsal, tenant-integration, migrate job, verify-migrations); copy changes follow the policy, they do not replace it |
| #11572 items 3 to 13, triaged by the issue's revisit criteria | Phase 3 to Phase 5, decision table `decision-challenges.md` D3 to D9 |
| File or keep tracked anything needing a live Better Stack or Sentry read, with a re-evaluation criterion | Items 3 and 5 were read live at plan time (no remaining read); items 4, 6, 10 tracked in #11628 |
| `Closes #11569` and `Closes #11572` on separate lines | Phase 7 (PR body) |

### Plan-Item Provenance

| Item | Provenance |
|---|---|
| Column-level narrowing (`REVOKE UPDATE` then `GRANT UPDATE (status, draft_preview)`) | `inferred`, justified: with a table-level UPDATE grant on all 21 columns, the requested policy alone would let a browser client rewrite `trust_tier`, `action_class`, `template_id` and `workspace_id` of its own rows, which is a regression from today's inert state; CTO D2. |
| `status = 'draft'` in the policy | `inferred`, justified: keeps chat rows immutable from the client; every route already filters on it; CTO D1. |
| Discard-route unit test | `inferred`, justified: the route has no test (edit and send do); the migration's whole purpose is to change the Discard result. |
| Trust-tier-copy `REVOCATION_REASON_COPY` edit | `inferred`, justified: the same "Click Send again" defect as item 7 on a surface with no Send button; CTO D8(c). |
| `mh_selftest_caught` (item 8), `mh_floor`/`assert_fixture_dir` rows (item 9), `mh_frag_unique` (item 11), `exec < /dev/null` (item 13) | `asked` (issue #11572 items 8, 9, 11, 13) |
| Tracking issues #11628, #11629 | `asked` by the brief ("file or keep tracked ... with a re-evaluation criterion") and by `wg-when-deferring-a-capability-create-a` |

### Split Assessment

Counts derived from `## Files to Edit` (about 20 files) and `## Files to Create` (6 files): the policy half touches 3 SQL
files, 4 test files and 2 registry/verify edits; the harness half touches 1 lib, 2 suites, 3 header-only comments and 1
suite head; the copy half touches 2 source files, 1 page fetcher and their tests.

- Recommendation: keep as ONE PR (operator instruction; the copy half depends on the policy half and the harness half is
  independent but small). Split the harness half off only if its CI stalls.

The two issues share one PR by operator instruction. They are independent in code (SQL and copy versus shell harness) but
the copy half of #11572 (items 7 and 12) is only truthful once the policy exists, which is why #11572 was written to wait
on #11569. The harness half touches no file of the policy half; if CI on the harness half stalls, it can be split off
without re-planning, because Phases 3 to 5 do not depend on Phase 2 (only Phase 3's copy assertions do).

## Proposed Solution

### A. #11569 — migration 181 (policy plus column narrowing)

`apps/web-platform/supabase/migrations/181_messages_owner_draft_update.sql` (sketch; the final text is written in Phase 2):

```sql
-- precondition block: to_regclass('public.messages') and public.is_workspace_member(uuid, uuid) exist, else RAISE
DROP POLICY IF EXISTS messages_owner_draft_update ON public.messages;
CREATE POLICY messages_owner_draft_update ON public.messages
  AS PERMISSIVE FOR UPDATE TO authenticated
  USING (user_id = (SELECT auth.uid())
         AND status = 'draft'
         AND public.is_workspace_member(workspace_id, (SELECT auth.uid())))
  WITH CHECK (user_id = (SELECT auth.uid())
              AND status IN ('draft', 'archived')
              AND public.is_workspace_member(workspace_id, (SELECT auth.uid())));

REVOKE UPDATE ON TABLE public.messages FROM PUBLIC, anon, authenticated;   -- must precede the column GRANT (mig 178 ordering)
GRANT UPDATE (status, draft_preview) ON TABLE public.messages TO authenticated;
```

Why each part (CTO D1, D2):

- PERMISSIVE and `TO authenticated`: the existing RESTRICTIVE `messages_jti_not_denied` (ALL) ANDs on top, so a revoked-JTI session still cannot update.
- `user_id` equality plus workspace membership: the issue's keyed predicate; the routes keep their own `user_id` filter as belt-and-suspenders.
- `status = 'draft'` in USING and `IN ('draft','archived')` in WITH CHECK: the three routes only ever move draft -> archived or edit a draft; `complete`/`aborted` chat rows stay immutable from the client, and a draft cannot be flipped to `complete`.
- `(SELECT auth.uid())` wrap: the InitPlan form mig 134 standardised; the verify sentinel asserts the deparsed literal `user_id = ( SELECT auth.uid()`.
- Column narrowing: `authenticated` and `anon` hold table-level UPDATE on all 21 columns (mig 174 snapshot of Supabase defaults); a table-level grant makes a column-level REVOKE a no-op, so the table-level UPDATE is revoked first and only the two columns the routes write are re-granted. `anon` is revoked as hygiene (inert today, no policy). Remaining table-level verbs (DELETE, TRUNCATE, ...) are NOT narrowed here (CTO D2; follow-up belongs to the ADR-303 narrowing line, not this P1).
- No data movement: the 1943 stuck drafts are not bulk-archived (CTO D2); founders discard them with the working button.
- The down file (`181_..._.down.sql`) drops the policy, revokes the two column grants and re-grants table-level UPDATE to `anon, authenticated` (restores the 174 snapshot, defects included, matching the 176 down convention).

Companion artifacts: `supabase/verify/174_api_data_grants_snapshot.sql` must be edited in the same PR (Kieran P0): its `grants_messages_anon` and `grants_messages_authenticated` rows assert table-level UPDATE and would go red on prd in `verify-migrations`, gating the deploy; remove `UPDATE` from those two verb lists exactly as mig 178 did for the relations it narrowed, and pin the edit in the shape test. `supabase/verify/181_messages_owner_draft_update.sql` (runs against prd in `verify-migrations`), the
`table-grants.ts` OVERRIDES entry so the RLS-fuzz grant census expects the new posture, a real-DB tenant-isolation
test, and a static migration-shape test for the always-on lane.

### B. #11572 triage (decision table in `decision-challenges.md`)

| Item | Disposition | Where |
|---|---|---|
| 3 (60-day read timeout) | Resolved by measurement: 4 s against a 60 s budget; no behaviour change; measurement recorded in the 11265 probe header (comment-only edit) | Phase 4 |
| 4 (sibling reader seams) | Tracked: #11628 item A (next edit to those probes) | Phase 7 |
| 5 (11211 Sentry `environment:` filter) | Resolved by measurement: leave unfiltered; evidence recorded in the 11211 probe header (comment-only edit) | Phase 4 |
| 6 (structure suite edges and variant) | Tracked: #11628 item B | Phase 7 |
| 7 (three DENY_REASON_COPY 403 strings) | Done: button-neutral and truthful; the re-authorize promise is dropped because it is false (#11630) | Phase 3 |
| 8 (`mutate_helper` inline scorer) | Done as `mh_selftest_caught` with controls (capped at 40 changed lines in the lib, else moved to #11628) | Phase 5 |
| 9 (`mh_floor`, `assert_fixture_dir` refusal rows) | Done: inner-run rows in both probe suites | Phase 5 |
| 10 (docker-run-tuple third selftest) | Ruled: do not migrate; header comment in `docker-run-tuple.test.sh` pointing at #11628 item B | Phase 4 |
| 11 (sibling-row prefix collisions) | Done: `mh_frag_unique` plus exact-mode in `mh_caught` | Phase 5 |
| 12 (restore "or Discard it", recheck "Refresh" promises) | Done: Edit-409 string restored; `not_a_draft`/`approval_expired` need no change (verified; `future_clicked_at` deliberately keeps "Try again shortly") | Phase 3 |
| 13 (argv-bearer sweep stdin hang) | Done: `exec < /dev/null` at the head of the suite plus one pinning row | Phase 5 |

Copy (CTO D8, final strings):

- Edit-409 (`today-card.tsx`, `draft_already_approved` branch): `You already approved this draft, so it can't be edited. Send it to go ahead or Discard it.` The comment "Discard is not offered here until the messages UPDATE policy exists (#11569)" is deleted.
- `DENY_REASON_COPY` (planner correction of CTO D8(b), see decision D12): the "re-authorize" promise is false in the current gate (a second click returns the same 403: `isTemplateAuthorized` denies on the latest revoked row and `first_send` is returned only when no row exists; pinned by `is-template-authorized.test.ts` case (c); filed as #11630), so the strings state what happened and promise nothing: `template_revoked` "This template was revoked, so this draft can't be sent."; `template_expired` "This template's 90-day authorization expired, so this draft can't be sent."; `template_quota_exhausted` "You've sent 100 messages with this template, so this draft can't be sent." They name no button, so they read right from the card and from the typed-confirm modal.
- `lib/messages/trust-tier-copy.ts` `REVOCATION_REASON_COPY` (same defect): `quota_exhausted` "Reached the 100-send limit for this template."; `expired` "The 90-day authorization window closed." (the "Click Send again to re-authorize" tails are dropped).

Harness mechanisms (`scripts/lib/mutation-harness.sh`):

- `mh_frag_unique <frag> <ledger> <fix_n>`: pure; scans the first `fix_n` ledger lines (`ok|bad<TAB>label`) with `awk -F'\t'`, literal `index()` and `ENVIRON`, on the label field only. It PRINTS one token and keeps the return code binary (Kieran: an overloaded rc 3 would make an `if ! mh_frag_unique` caller refuse valid fragments): `unique` (zero or exactly one distinct label starts with the fragment), `exact` (the fragment equals one label exactly AND two or more labels share the prefix, the only case needing exact mode, so the ~50 existing rows keep prefix semantics), `ambiguous` (more than one distinct label starts with it and none equals it), `empty`. rc 0 for `unique`/`exact`, rc 1 otherwise. `mutate_run` refuses with `bad "mutation <name>: fragment [..] is ambiguous (instrument)"` on `ambiguous`/`empty`. Read optional arguments as `${3:-}` (the lib runs under `set -u`).
- Planner refinement of D7 (mechanical, same intent): on `exact` `mutate_run` passes `exact` to `mh_caught <frag> <log> [exact]`, which then requires the FAIL line to equal `  FAIL: <frag>` exactly, so a longer sibling row (`...: exit 5 (30 days or older)`) cannot credit a mutant claimed against the shorter row. Without this the D7 tie-break would still let the sibling collision through.
- `mh_selftest_caught <rc> <log>` (item 8): 0 only when rc is 4 and a line STARTS with `INSTRUMENT SELF-TEST FAILED`; `mutate_helper` calls it instead of the inline test.
- Both probe suites gain capture-only controls for each new function plus the item 9 refusal rows (`mh_floor` exits 1 on a short fixture count and on a short battery count, passes on a sufficient count and under `FT_INNER`; `assert_fixture_dir` exits 2 on empty, relative, `..`, synthetic-fs and root inputs and passes on an absolute temp path). Both functions `exit`, so each row runs as `( ... ); rc=$?` in the parent shell and `check`s the rc and the printed `FLOOR:`/`FATAL:` line; place every new control after `FIX_N` is taken so it counts toward `MIN_BATTERY`; leave the existing literal "8 negative controls" teeth rows untouched. `MIN_BATTERY` rises by the exact ledger-label diff (currently 50 in 11211 and 55 in 11265).

## Implementation Phases

Order follows `cq-write-failing-tests-before`: each phase writes its RED test first. Phases 3 to 5 do not depend on Phase 2 except Phase 3's copy assertions (written together with the copy).

### Phase 0 — Baseline (read-only)

1. Re-run the dev and prd `pg_policies` + `has_column_privilege` reads (Research Insights query) and paste the result into the PR body, so a later drift is visible. Include the `status = 'draft'` count by `source` (1898 `github`, 45 `kb-drift`, 0 Stripe on 2026-10-30) so the PR body states what the fix actually unblocks.
2. Capture the pristine ledger-label lists of both probe suites (`bash <suite> | grep -E '^  (PASS|FAIL):'`) and the `argv-bearer-sweep` row count (`EXPECTED_TESTS=824`), for the label-diff ACs.
3. Confirm the next free migration ordinal against `origin/main` (provisionally 181; 179 is held by open PR #11593).

### Phase 1 — Tests first for #11569 (RED)

1. `apps/web-platform/test/server/messages-owner-draft-update.tenant-isolation.test.ts` (real DB, DEV only, refuses the prd ref, every scenario ROLLED BACK; model: `approval-request.tenant-isolation.test.ts`). Scenarios (each preceded by a positive control so a deny cannot pass for the wrong reason, with valid UUID payloads and a service-role re-read of the row after every denial):
   - author discards a draft (`status` draft -> archived, 1 row) and edits `draft_preview` (1 row);
   - a second member of the same workspace (not the author) updates 0 rows;
   - a member of another workspace updates 0 rows;
   - an already archived draft updates 0 rows (USING);
   - author sets `status = 'complete'` on a draft: error 42501 whose message matches `/new row violates row-level security policy/` (WITH CHECK);
   - author updates `content`, `role`, `user_id`, `workspace_id`, `trust_tier`, `action_class`, `template_id`: error 42501 whose message matches `/permission denied for table messages/` (column privilege), row unchanged. Both shapes raise 42501, so the message is what tells the two layers apart (Kieran P1); assert it per case;
   - a `complete` chat row owned by the caller: status update 0 rows, content update 42501;
   - `anon` UPDATE: 42501;
   - catalog: `has_table_privilege('authenticated','public.messages','UPDATE')` is false; `has_column_privilege` true for `status`, `draft_preview` only.
   RED before the migration is applied: the author cases update 0 rows (the production bug).
2. `apps/web-platform/test/supabase-migrations/181-messages-owner-draft-update.test.ts` (static shape test, the always-on lane signal; model: 178), deliberately thin (plan-review: the real-DB test and `verify/181` already own the policy semantics): `REVOKE UPDATE` strictly before `GRANT UPDATE (status, draft_preview)` (only a text test can see ordering), no bare `auth.uid()` in the up file (only `(SELECT auth.uid())`), the GRANT names exactly those two columns, the down file exists and mirrors, and the verify file carries the `check_name`/`bad` contract. One anti-vacuity self-test that the parser extracted the statements it asserts on.
3. `apps/web-platform/test/api/dashboard/today/discard-route.test.ts` (mocked Supabase, like edit/send): 200 with `{id,status:"archived"}`; zero rows -> 403 `forbidden`; DB error -> 500 and a `messages-archive` Sentry mirror; unauthenticated -> 401; update chain carries `.eq("user_id")` and `.eq("status","draft")`.
4. `apps/web-platform/test/rls-fuzz/`: the `AC6` gate in `rls-row-hijack.integration.test.ts` asserts the hijack registry equals `rowHijackTables` (catalog: PERMISSIVE UPDATE/ALL policies on tables with `workspace_id`), so adding the policy REQUIRES a `messages` entry in `HIJACK_TARGETS` (not optional): seed a draft-card row for `userA` in `wsA`; positive control = owner sets `status='archived'`; hijack attempts = `workspace_id = wsB` and `status = 'complete'`, both denied (the first is denied by the column privilege, 42501, before WITH CHECK runs; the tenant-isolation test is what exercises the WITH CHECK status clause). ALSO fix the `messages` target in `test/rls-fuzz/targets.ts` (architecture review P1): it uses `updateCol: "workspace_id"` and a chat-shape seed with the default status, so after 181 the base matrix's cross-tenant and co-member UPDATE checks (`rls-authz-fuzz`, `rls-user-isolation`: `update messages set <col> = <col>`) would be denied by the column privilege and pass without ever exercising `messages_owner_draft_update`. Switch it to `updateCol: "draft_preview"` with a draft-card seed (`status='draft'`, `user_id = userA`, `source`, `owning_domain`, `draft_preview`, tier external) so the author could update it and a denial for B/C comes from the policy. Then add the `messages` entry to `HIJACK_TARGETS` and the `messages` entry to `OVERRIDES` in `table-grants.ts` (table-level `anon`/`authenticated` verbs minus UPDATE, `service_role` full, `columns: { authenticated: { status: ["UPDATE"], draft_preview: ["UPDATE"] } }`, provenance citing mig 181). Re-derive the exact verb lists from the 174 snapshot parse, do not hand-type them.

### Phase 2 — Migration, verify, dev rehearsal

0. Re-check `origin/main` and the open PRs for migration ordinals immediately before the first dev apply; the ordinal is final from that moment (byte-frozen once applied). #11593 holds `179_*` and is not merged: `run-migrations.sh --verify` flags any on-disk file below the ledger high-watermark that is absent from `_schema_migrations`, so if 179 lands after 181 the dev ledger reports drift. Sequence note (corrected after review): the migrate loop looks files up in `_schema_migrations` by filename, not ordinal, and nothing in the release path runs `run-migrations.sh --verify`, so a later-merging 179 is simply applied by the next `migrate`; only a manual `--verify` between the two events would report drift. Two unmerged branches hold a 179 (#11593 and a local codex branch); neither touches `messages`.
0b. Extend the writer census beyond the three `.update(` sites before writing SQL (spec-flow and architecture review): `git grep -n "ON CONFLICT" -- apps/web-platform/supabase/migrations | grep -i messages`, any non-SECURITY DEFINER function that UPDATEs `messages`, `.upsert(` on `messages`, and any `tenant`-JWT client that writes `messages` (a column revoke breaks all of these). The 2026-10-30 census found none; record the greps' empty output in the PR body.
1. Write `181_messages_owner_draft_update.sql` and `.down.sql` (shape in Proposed Solution A; header explains the dev/prd comparison, the column narrowing, and that the 1943 drafts are not backfilled). The rollback note in the PR body pairs the down file with the reverse `table-grants.ts` edit (the registry would otherwise expect the narrowed posture).
2. Write `supabase/verify/181_messages_owner_draft_update.sql` (`check_name`, `bad` rows; deparse-aware; the existing `verify/178` complement sweep names a fixed relation list that excludes `messages`, so 181 carries its own): exactly one PERMISSIVE UPDATE/ALL policy on `messages` and it is `messages_owner_draft_update` (a legitimate future second UPDATE policy, for example the co-owner decision in #11629, must update this row in the same PR; say so in a comment); `roles = {authenticated}`; `qual`/`with_check` each contain the literal `user_id = ( SELECT auth.uid()`, `is_workspace_member(`, and (qual) `status = 'draft'::text` / (with_check) `status = ANY (ARRAY['draft'::text, 'archived'::text])`; `messages_jti_not_denied` still present and RESTRICTIVE; `has_table_privilege` false for UPDATE on `anon` and `authenticated`; `has_column_privilege` true for `authenticated` on `status`, `draft_preview` and false on every other column (derive the column list from `pg_attribute`, not a hand list, so a future column is covered); `anon` holds no UPDATE column privilege; and an `attacl`/`relacl` sweep in the registered-or-covered form of the fuzz gate (`has_column_privilege(role, col, 'UPDATE') AND NOT has_table_privilege(role, 'UPDATE')`, for `anon` and `authenticated`, excluding the two granted columns for `authenticated`; `service_role` keeps its table-level grants and is exempt through `NOT has_table_privilege`), plus an `aclexplode` check that no ACL entry with grantee `0` (PUBLIC) carries UPDATE on the table or any column (`has_*_privilege` cannot see PUBLIC as a role).
3. Dry-run first, apply second: `BEGIN; \i 181...sql; <verify queries>; ROLLBACK;` against dev with `PGOPTIONS=-c default_transaction_read_only=off` only inside the explicit transaction (psql, DSN from `doppler run -c dev`, never printed), then `doppler run -p soleur -c dev -- bash scripts/run-migrations.sh` per the runbook §0, then `psql -f` the verify file against dev. The file is byte-frozen once applied to dev (runbook), so no edit after this step except via `dev-ledger-reconcile.yml`.
4. Run Phase 1 test 1 against dev: RED -> GREEN; rerun test 3 and test 2.

### Phase 3 — Copy (#11572 items 7 and 12)

1. Tests first: update `test/components/today-card.click.test.tsx` (the Edit-409 expectation at the `draft_already_approved` row) to the restored string, and add rows pinning the three `DENY_REASON_COPY` strings by rendering a 403 `template_revoked` / `template_expired` / `template_quota_exhausted` response (no test pins them today); update the `trust-tier-copy` tests if any assert the two strings (CTO found none; grep first).
2. Edit `today-card.tsx` and `lib/messages/trust-tier-copy.ts` to the strings above.
3. Invariant (AC): copy only, no structural change (the #11566 wireframe-exemption invariant, AC6 below).
3b. Truthfulness proof for the dropped "re-authorize" promise (CPO asked for it to be verified, not assumed): already done at plan time by reading the gate and the existing `is-template-authorized.test.ts` case (c) (a revoked latest row is denied; `first_send` is reached only with no row). No new test (plan-review: it would re-prove existing behaviour); the evidence is cited in the PR body and #11630.
4. `not_a_draft` check (CTO D8(d) asked for confirmation): done at plan time (a non-draft row answers 409 `not_a_draft`; `GET /api/dashboard/today` selects `status = draft`, so a refresh drops the card). No new test; cited in the PR body.
5. New 403 copy for Discard, Edit and the kb-drift Dismiss (spec-flow P1, CPO note "the `forbidden` copy must not invite a retry"): after the fix a second Discard (another tab, a double click) or an Edit/Discard by a non-author matches zero rows and answers 403, which the card shows as `Discard failed (403)` / `Edit failed (403)` / `Dismiss failed (403)`. Add one 403 branch to each of the three handlers in `today-card.tsx` with a single constant: `This draft was already handled, or it isn't yours to change. Refresh to update this card.` (same register as the existing `not_a_draft` line; names no button). Tests first in `today-card.click.test.tsx` (one row per handler) and keep the generic `... failed (NNN)` fallback for every other status.
6. Stale list after a successful Discard (spec-flow P1): `app/(dashboard)/dashboard/page.tsx` fetches the Today list through SWR with a plain `fetch("/api/dashboard/today")`, and the route answers `Cache-Control: private, max-age=60`, so a revalidation inside 60 s can serve the browser-cached list and bring a discarded card back (the next Discard then 403s). Pass `{ cache: "no-store" }` on that client fetch only (the server header and its Art. 14 rationale are unchanged). Test: the fetcher is called with `cache: "no-store"`; no existing test references `/api/dashboard/today` for the page (grep of `apps/web-platform/test/`), so add one row to `apps/web-platform/test/dashboard-mount-fetch-dedup.test.tsx` (it already mounts the page and counts its fetches) or a new small test beside it. SWR (ADR-067) serves the cached list instantly and revalidates on mount and focus; the `no-store` option is what stops the browser HTTP cache answering that revalidation.

### Phase 4 — Header-only edits (items 3, 5, 10)

Comment-only edits (AC: every changed line starts with `#`): `inngest-luks-keeper-dark-11265.sh` header records the 60-day read measurement and the re-evaluation trigger (timeout-class exit 3, or the archive arm growing past about 10x); `dispatch-recovery-sweeper-11211.sh` header records the Sentry environment split and its triggers (a preview or staging environment appears; the first real `feature:dashboard-send` event confirms `environment:production`); `docker-run-tuple.test.sh` header says why it does not use `scripts/lib/mutation-harness.sh` and points at #11628. These touch `AFFECTED_*_PATHS` members, so both probe suites rerun.

### Phase 5 — Harness hygiene (items 8, 9, 11, 13)

1. Tests first in both probe suites' scorer-control block: controls for `mh_frag_unique` (unique, ambiguous, exact tie-break, empty), exact-mode `mh_caught`, `mh_selftest_caught`, and the item 9 refusal rows (capture-only, run in the parent shell, synthetic logs committed in the suite). RED while the lib lacks the functions.
2. Implement the functions in `scripts/lib/mutation-harness.sh`; wire `mutate_run` (ambiguity refusal, `exact` pass-through) and `mutate_helper` (`mh_selftest_caught`). Run each suite: any pre-existing ambiguous fragment surfaces as a `bad ... ambiguous (instrument)` row; fix by choosing the row's exact label, or a longer leading-words fragment that is unique.
3. Raise `MIN_BATTERY` by the exact ledger-label diff in each suite; keep `MIN_FIXTURE` unchanged.
4. `tests/scripts/test-argv-bearer-sweep.sh`: add `exec < /dev/null` (with a comment naming the S6 stub `docker`'s unconditional `pw="$(cat)"`) right after `set -uo pipefail`; add one row asserting the line exists before the first fixture write and is not inside a function; raise `EXPECTED_TESTS` by 1 and append the dated history line the file keeps. Check no `read` in the suite consumes the inherited stdin (the `while read` loops at the file read from here-strings/pipes; confirm each). `exec < /dev/null` turns the S6 stub `docker`'s `pw="$(cat)"` from "blocks" into "empty": run the suite before and after with stdin closed and diff the per-row results; every S6 row must keep its outcome. `EXPECTED_TESTS` is a lower bound in this file (its own comment says so), so set it to the measured count after the row is added.
5. Pre-push ratchets (the #11566 list): `bash scripts/lint-supabase-deprecated-endpoints.sh`, `bash scripts/lint-betterstack-emitter-read.sh`, `bash scripts/test-affected-kb-consumers.test.sh`, `bash .claude/hooks/grep-q-pipe-guard.test.sh`, `bash scripts/followthrough-exec-bit.test.sh`, `bash tests/scripts/test-argv-bearer-sweep.sh`, `bash scripts/lint-orphan-test-suites.sh`, `bash apps/web-platform/scripts/lint-migration-api-grants.sh <the two 181 migration files>` (it takes file arguments or `--from-pr-diff`; a bare run checks nothing), `bash plugins/soleur/test/c4-count-parity.test.sh`, `python3 scripts/lint-guard-contract.py` on this plan; then the two probe suites and the touched vitest files (with `tsc --noEmit` in the same command).

### Phase 6 — Ship and prod verification (normal gates, no extra approval step; decision D11)

1. PR body carries `Closes #11569` and `Closes #11572` on separate lines, the Phase 0 catalog reads, the rollback SQL (the down file), and links #11628, #11629.
2. Rollback (amended after review): apply the down file to prd, `DELETE FROM public._schema_migrations WHERE filename='181_messages_owner_draft_update.sql'`, and land a revert PR in the SAME change that deletes `verify/181`, the `table-grants.ts` `messages` entry, the 181 shape and tenant tests (and restores UPDATE in the two `verify/174` rows); `verify-migrations` runs every verify file on every release and `deploy` needs it green, so applying the down file alone blocks all later releases. Run the down file on dev too (181 is applied there).
3. After merge the existing pipeline applies the migration (`migrate` job) and runs `verify-migrations` against prd (this executes `verify/181`). Post-merge read-only checks are in Acceptance Criteria.

### Phase 7 — Tracking

#11628 and #11629 already exist (filed at plan time). Add a comment to #11572 listing the disposition of each item and the closing PR; confirm `Closes` lines in the PR body.

## Files to Edit

- `apps/web-platform/components/dashboard/today-card.tsx` (Edit-409 string, comment, three DENY strings, one 403 line for Discard, Edit and Dismiss)
- `apps/web-platform/lib/messages/trust-tier-copy.ts` (two strings)
- `apps/web-platform/test/components/today-card.click.test.tsx` (Edit-409 string, DENY rows)
- `apps/web-platform/test/rls-fuzz/table-grants.ts` (OVERRIDES: `messages`)
- `apps/web-platform/test/rls-fuzz/rls-row-hijack.integration.test.ts` (HIJACK_TARGETS: `messages`; give `HijackTarget` optional `hijackCol`/`hijackValue` so the `messages` entry can attempt `status = 'complete'` instead of the hard-coded `workspace_id`, or state in the entry that WITH CHECK is covered only by the tenant-isolation test)
- `apps/web-platform/test/rls-fuzz/targets.ts` (`messages` target: `updateCol: "draft_preview"`, draft-card seed with `user_id = userA`)
- `apps/web-platform/supabase/verify/174_api_data_grants_snapshot.sql` (remove UPDATE from the `grants_messages_anon` / `grants_messages_authenticated` verb lists)
- `apps/web-platform/app/(dashboard)/dashboard/page.tsx` (Today fetcher: `cache: "no-store"`) and `apps/web-platform/test/dashboard-mount-fetch-dedup.test.tsx` (one row)
- `knowledge-base/engineering/architecture/decisions/ADR-303-explicit-data-api-grants-and-two-tier-table-grant-guard.md` (one Consequences bullet, see Architecture Decision)
- `scripts/lib/mutation-harness.sh` (`mh_frag_unique`, exact mode in `mh_caught`, `mh_selftest_caught`, `mutate_run`, `mutate_helper`)
- `scripts/followthroughs/inngest-luks-keeper-dark-11265.test.sh`, `scripts/followthroughs/dispatch-recovery-sweeper-11211.test.sh` (controls, refusal rows, `MIN_BATTERY`)
- `scripts/followthroughs/inngest-luks-keeper-dark-11265.sh`, `scripts/followthroughs/dispatch-recovery-sweeper-11211.sh` (header comments only)
- `apps/web-platform/infra/docker-run-tuple.test.sh` (header comment only)
- `tests/scripts/test-argv-bearer-sweep.sh` (`exec < /dev/null`, one row, `EXPECTED_TESTS`)

Sibling-query sweep (the tenant-scope rule): every `.from("messages").update(` site was enumerated (three cookie-client
sites, all in the three routes; no service-client UPDATE on `messages` in TypeScript; SQL UPDATEs are migration backfills
and SECURITY DEFINER bodies, which bypass the grant). No other route needs an edit.

## Files to Create

- `apps/web-platform/supabase/migrations/181_messages_owner_draft_update.sql`
- `apps/web-platform/supabase/migrations/181_messages_owner_draft_update.down.sql`
- `apps/web-platform/supabase/verify/181_messages_owner_draft_update.sql`
- `apps/web-platform/test/server/messages-owner-draft-update.tenant-isolation.test.ts`
- `apps/web-platform/test/supabase-migrations/181-messages-owner-draft-update.test.ts`
- `apps/web-platform/test/api/dashboard/today/discard-route.test.ts`

(Globs checked: `test/server/*.tenant-isolation.test.ts` is collected by `tenant-integration.yml`; `test/supabase-migrations/`
and `test/api/dashboard/today/` exist with sibling tests; `supabase/verify/` is read by `scripts/run-verify.sh`.)

## Acceptance Criteria

### Pre-merge (PR)

- AC1. `181_messages_owner_draft_update.sql` and `.down.sql` exist; the up file contains exactly one `CREATE POLICY messages_owner_draft_update`, `AS PERMISSIVE FOR UPDATE TO authenticated`, no bare `auth.uid()` (only `(SELECT auth.uid())`), and `REVOKE UPDATE ON TABLE public.messages` precedes `GRANT UPDATE (status, draft_preview)`. The static shape test pins each.
- AC2. Migration applied to DEV via the normal path before merge; `psql -f supabase/verify/181_...sql` against dev prints every row with `bad = 0`.
- AC3. The tenant-isolation test passes against dev with every case in Phase 1 test 1, and the same test run BEFORE the migration shows the author cases RED (zero rows), recorded in the PR body.
- AC3b. `supabase/verify/174_api_data_grants_snapshot.sql` no longer asserts table-level UPDATE for `anon`/`authenticated` on `messages`; `psql -f` of both verify files against dev prints every row with `bad = 0` (the 174 rows would be RED without the edit).
- AC4. `RLS_FUZZ_LOCAL=1` rls-grants and row-hijack suites are green with the `messages` OVERRIDES / HIJACK_TARGETS entries (or, if no local stack is available, the CI `rls-authz-fuzz` job on this PR is green).
- AC5. `discard-route.test.ts`, the updated `today-card.click.test.tsx` (including one 403 row each for Discard, Edit and Dismiss, and the `cache: "no-store"` row for the dashboard fetcher) and the trust-tier-copy tests pass; `tsc --noEmit` clean.
- AC5b. In the `rls-authz-fuzz` and `rls-user-isolation` runs the `messages` cross-tenant and co-member UPDATE denials come from the policy, not the column privilege: the target updates `draft_preview` of a seeded author-owned draft (the positive control, owner updating it, succeeds).
- AC6. Copy-only invariant: `git diff -U0 origin/main -- apps/web-platform/components apps/web-platform/hooks | grep -E '^[+-][[:space:]]*(<[A-Za-z]|.*(className|role=|aria-|data-))'` prints nothing, and no new file exists under `components/`.
- AC7. The Edit-409 string and the three DENY strings and the two trust-tier strings match the Proposed Solution B list exactly: `grep -c 'Click Send again' apps/web-platform/components/dashboard/today-card.tsx apps/web-platform/lib/messages/trust-tier-copy.ts` prints `:0` for both files, and `grep -c 'Send it to go ahead or Discard it' apps/web-platform/components/dashboard/today-card.tsx` prints `1`.
- AC8. Both probe suites are green on a pristine run; `MIN_BATTERY` rose by exactly the ledger-label diff; no pre-existing fragment is ambiguous (or each was disambiguated and the diff is in the PR body).
- AC9. Header-only edits: for the two probes and `docker-run-tuple.test.sh`, `git diff -U0 origin/main -- <file> | grep -E '^[+-][^+-]' | grep -vE '^[+-][[:space:]]*#'` prints nothing.
- AC10. `tests/scripts/test-argv-bearer-sweep.sh` completes with an open stdin: `tail -f /dev/null | timeout <T> bash tests/scripts/test-argv-bearer-sweep.sh; echo ${PIPESTATUS[1]}` prints `0` (not `124`), where `<T>` is a concrete number of seconds chosen in Phase 5 as 3x the measured closed-stdin duration and written into the PR body; the before/after per-row results with stdin closed are identical; `EXPECTED_TESTS` is set to the measured count.
- AC11. `python3 scripts/lint-guard-contract.py` passes on this plan; the pre-push ratchets listed in Phase 5 step 5 pass.
- AC12. PR body contains `Closes #11569` and `Closes #11572` on separate lines; #11628, #11629 and #11630 are linked; the PR body says the fix unblocks the github send-archive and the kb-drift Dismiss (not a Stripe Discard backlog) and that draft cards are author-only.
- AC13. ADR-303 carries the new Consequences bullet for migration 181 (`grep -n "181" knowledge-base/engineering/architecture/decisions/ADR-303-explicit-data-api-grants-and-two-tier-table-grant-guard.md` prints it); `bash plugins/soleur/test/c4-count-parity.test.sh` passes.

### Post-merge (agent-runnable, read-only)

- PM1. The release workflow's `migrate` and `verify-migrations` jobs are green for the merge SHA, which executes `verify/181` against prd. Find the run with `bash plugins/soleur/scripts/deploy-arm.sh find <full-sha>` (the `workflow_run` arm carries `migrate`/`verify-migrations`/`deploy`; `gh run list --commit <sha>` returns the push arm, whose `head_sha` is the merge SHA but which skips `migrate` and `verify-migrations`), then `gh run view <ARM> --json jobs`. (Amended after review: the earlier command could not find the arm.)
- PM2. Read-only prd catalog check (same method as Phase 0, including the draft count by `source`): `messages_owner_draft_update` present; `has_column_privilege('authenticated','public.messages','status','UPDATE')` and `'draft_preview'` true; `'content'`, `'workspace_id'`, `'trust_tier'`, `'action_class'`, `'template_id'`, `'user_id'` false; `messages_jti_not_denied` still RESTRICTIVE.
- PM3 (amended after review). The gate is the DB count `SELECT source, count(*) FILTER (WHERE status='archived') FROM public.messages GROUP BY 1` (record it by source on #11569); Sentry is corroboration only, because only the send route reports a zero-row archive and a Discard/Dismiss zero-row answers a bare 403, so zero Sentry events is meaningful only when the archived count is above zero. Original text: Sentry (read-only, `SENTRY_ISSUE_RO_TOKEN`): `op:messages-archive-no-row` has 0 events for the 7 days after the deploy, and `feature:dashboard-discard op:messages-archive` / `feature:dashboard-edit op:messages-update` have 0 error events; the count of `status = 'archived'` prd rows is no longer 0 once a github send has archived a draft or a kb-drift digest has been dismissed (record the reading, by `source`, on #11569 before it closes; do not require a Stripe Discard, there are no Stripe drafts).

## Guard Contract

### Guard 1 — messages UPDATE reachability (policy + grant + verify)

**Property.** An `authenticated` caller can UPDATE `status` and `draft_preview` of exactly the draft rows it authored in a workspace it belongs to, and nothing else on `public.messages`.

**Assembly.** The write surface is the product of (a) every PERMISSIVE and RESTRICTIVE policy on `messages` for UPDATE/ALL (`pg_policies`, not the migration text: the jti RESTRICTIVE ALL policy and any out-of-band drift policy count), (b) the table-level and column-level UPDATE privileges of `anon`, `authenticated` and `PUBLIC` (`pg_attribute` x `has_column_privilege`, derived from the catalog so a column added later is covered), and (c) every UPDATE call site (the three routes; SECURITY DEFINER functions bypass both layers by design). Chokepoints: the catalog `verify/181` row set, and the tenant-isolation test's catalog scenario.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Policy USING drops `AND status = 'draft'` | tenant-isolation "archived draft updates 0 rows" and "complete chat row" cases RED; verify `qual` literal row RED |
| 2 | WITH CHECK widens to `status IN ('draft','archived','complete')` or drops the status clause | tenant-isolation "sets status complete" case RED; verify `with_check` row RED |
| 3 | Migration omits the `REVOKE UPDATE ON TABLE` (policy only) | tenant-isolation column-privilege cases RED (`content`, `workspace_id`, `trust_tier` updates succeed); verify column-privilege row RED (derived over `pg_attribute`) |
| 4 | Migration grants one extra column after a compliant first (`GRANT UPDATE (status, draft_preview, content)`) | verify "no other column" row RED (second-member case); shape test RED |
| 5 | A second permissive policy is added out-of-band (`FOR UPDATE ... USING (true)`) | verify "exactly one permissive UPDATE/ALL policy" row RED (the guard's own dispatch: it counts `pg_policies`, and the shape test asserts the count query returns a row) |
| 6 | `GRANT` placed before `REVOKE` in the file | shape test ordering row RED (a later REVOKE would strip the column grant; also tenant-isolation positive control RED) |
| 7 | Policy applied to `TO public` instead of `TO authenticated` | verify `roles` row RED |

**Harness rows.** Suite edit that must go RED: the tenant-isolation positive control updated to expect 0 rows (a vacuous suite that never UPDATEs would stay green) must fail the first case; the shape test's self-test that its parser extracted the policy block is removed -> RED. Must-PASS input that is not the canonical: a draft authored by a second user in the same workspace updated by that user (differs in author, workspace and row id) must succeed, so a policy hard-coded to one fixture user fails.

**Anchor.** The verify file and the policy move in one diff, so a diff-only check proves consistency, not integrity. The outside anchors are (a) the Phase 0 pre-change catalog reads of dev and prd pasted in the PR body (a weakening cannot also edit them), (b) the prd `verify-migrations` run, which reads the live catalog after the real apply, and (c) the `table-grants.ts` registry compared to the live grants by the RLS-fuzz grant gate (held == registered), which a policy-only edit cannot satisfy.

### Guard 2 — fragment uniqueness (`mh_frag_unique` and exact-mode `mh_caught`)

**Property.** A mutant is credited as caught only by the one fixture row its claimed fragment names; a fragment that is the leading words of two rows is refused, and a fragment equal to one full label cannot be credited by a longer sibling row.

**Assembly.** One decision point: `mutate_run` in `scripts/lib/mutation-harness.sh` (reached by `mutate_sub`, and by the suites' direct `mutate_run` rows). Members: every mutation row in `inngest-luks-keeper-dark-11265.test.sh` and `dispatch-recovery-sweeper-11211.test.sh`. `mutate_helper` has its own scorer (`mh_selftest_caught`, item 8). The structure suite and `docker-run-tuple.test.sh` keep separate scorers (#11628 item B).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | `mh_frag_unique` always returns 0 | ambiguous-fragment control RED in both suites |
| 2 | `mh_frag_unique` counts only the first matching label (stops at the first member) | ambiguous-fragment control RED (a third sibling row after a compliant first is in the fixture ledger) |
| 3 | `mutate_run` stops calling `mh_frag_unique` | the control that drives `mutate_run` with an ambiguous fragment (a synthetic ledger and fragment, inner run stubbed) RED; AC grep pins the call |
| 4 | `mh_caught` ignores the `exact` argument | exact-mode control RED (longer sibling FAIL line must NOT credit) |
| 5 | `mh_frag_unique` treats an exact-label match as ambiguous (or prints `exact` for every unique fragment, switching ~50 rows to exact mode) | exact tie-break control RED; a unique-prefix control RED |
| 6 | `mh_frag_unique` returns rc 0 for the empty fragment | empty-fragment control RED |

**Harness rows.** Suite edit that must go RED: deleting the control rows from the SECOND suite after a compliant first, leaving `MIN_BATTERY` raised -> that suite's battery floor RED. Must-PASS non-canonical input: a fragment equal to one label that is also the prefix of another (the issue's `...: exit 5` vs `...: exit 5 (30 days or older)`), plus a fragment matching zero fixture labels (a battery-row name), both valid.

**Anchor.** The ledger-label list captured BEFORE the change (Phase 0) is the outside reference for the `MIN_BATTERY` bump (exact label diff, not a number read off a run).

### Guard 3 — argv-bearer suite closes its stdin

**Property.** No inherited stdin can block `tests/scripts/test-argv-bearer-sweep.sh`.

**Assembly.** The suite's own process stdin, reached by every child that inherits it (the S6 stub `docker`'s `cat`, any `read` without a redirect). One chokepoint: the single `exec < /dev/null` before the first fixture write.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the `exec < /dev/null` line | the pinning row RED; the open-stdin run (AC10) times out |
| 2 | Move it below the first stub invocation | the pinning row RED (ordering assertion) |
| 3 | Wrap it in a function that is never called | the pinning row RED (top-level assertion) |

**Harness rows.** Edit to the suite: mutation 1 applied to a scratch copy and the pinning row run against it (RED). Must-PASS non-canonical input: the suite run with stdin attached to an open pipe (AC10) passes.

**Anchor.** The `EXPECTED_TESTS` floor moves with the row (exact +1), recorded with a dated history line in the file.

## User-Brand Impact

- **If this lands broken, the user experiences:** (a) the policy too narrow or the column grant too tight: Discard, Edit or the send archive keep answering 403 / no-op exactly as today (no regression); (b) the column revoke catching a write path I missed: a Concierge draft card action fails with a 500 where it previously 403'd; (c) the policy too wide: one member of a workspace rewriting another member's draft body or a draft being moved between workspaces.
- **If this leaks, the user's [data / workflow] is exposed via:** a cross-tenant or cross-author UPDATE on `public.messages` (chat and draft content, `trust_tier`, `action_class`, `template_id`, which gate what an agent may send in the founder's name) if the USING/WITH CHECK predicates or the column grant are weaker than specified. Mitigations: author-and-membership predicate, draft-only rows, two-column grant, the RESTRICTIVE jti policy unchanged, and the real-DB cross-tenant cases in AC3.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision:** this changes write authorization on a tenant table that holds founder correspondence and the fields that authorize outbound sends; one wrong predicate is a single-tenant integrity incident. CPO sign-off at plan time is required (`requires_cpo_signoff: true`); `soleur:engineering:review:user-impact-reviewer` runs at review time.

## Observability

```yaml
liveness_signal:
  what:            Sentry op messages-archive-no-row stays at zero after the deploy, and prd public.messages gains status = 'archived' rows once founders use Discard
  cadence:         per send and per Discard click
  alert_target:    Sentry issue stream for the web-platform project (existing mirror in the send route archiveDraft; no new alert)
  configured_in:   apps/web-platform/app/api/dashboard/today/[id]/send/route.ts (archiveDraft), discard/route.ts (messages-archive), edit/route.ts (messages-update)
error_reporting:
  destination:     Sentry via reportSilentFallback (SENTRY_DSN server env); verify-migrations job log for the catalog
  fail_loud:       a zero-row archive reports op messages-archive-no-row; a zero-row Discard/Edit answers 403 forbidden; verify/181 fails the release workflow's verify-migrations job with the check name
failure_modes:
  - mode:          the policy or the column grant is missing or weaker on prd (drift, partial apply)
    detection:     verify/181 row set run by verify-migrations against prd after every release; Phase 0 and PM2 catalog reads
    alert_route:   release workflow failure (deploy gated) and the PR/issue thread
  - mode:          a write path was missed and now fails on the column revoke (permission denied, 42501)
    detection:     reportSilentFallback in the three routes returns 500 internal_error and mirrors to Sentry with the route's op tag; census in Files to Edit shows none
    alert_route:   Sentry issue stream
  - mode:          archive still matches zero rows (concurrent state change or RLS)
    detection:     op messages-archive-no-row
    alert_route:   Sentry issue stream
logs:
  where:           Sentry (route events); release workflow logs (verify-migrations)
  retention:       Sentry project retention; GitHub Actions log retention
discoverability_test:
  command:         bash -c 'psql "$DATABASE_URL_POOLER" --no-psqlrc -tAF "|" -f apps/web-platform/supabase/verify/181_messages_owner_draft_update.sql'
  expected_output: messages_policy_single_permissive_update|0
  credentials_required: Doppler prd DATABASE_URL_POOLER (read-only catalog queries) - pg_policies and column privileges are not reachable without a database credential, so no unauthenticated probe verifies the same property
```

## Domain Review

**Domains relevant:** Engineering, Product, Legal (advisory)

### Engineering

**Status:** reviewed
**Assessment:** CTO rulings D1 to D9 in `decision-challenges.md` (policy shape, column narrowing in the same migration, no code change for items 3 and 5, tracking for 4 and 6, no migration of docker-run-tuple, `mh_frag_unique` with the exact tie-break, final copy, items 8/9/13 in scope).

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** soleur:engineering:cto, soleur:product:cpo
**Skipped specialists:** soleur:product:design:ux-design-lead (copy-only, no structural change; the #11566 exemption with the AC6 diff invariant), soleur:marketing:copywriter (six short strings; CPO voice check)
**Pencil available:** not applicable (no UI surface change: copy-only exemption)
**Wireframe baseline and exemption (`wg-ui-feature-requires-pen-wireframe`, deepen-plan Phase 4.9):** `today-card.tsx` and `dashboard/page.tsx` match the UI-surface glob, but the change is copy plus one `fetch` option, no element, layout, class or new file under `components/` (the "Pure copy or style tweaks" exclusion of `ui-surface-terms.md`). The unchanged design baseline is the committed card wireframes `knowledge-base/product/design/dashboard/action-feedback-variant-a-forge-restraint.pen`, `knowledge-base/product/design/dashboard/action-feedback-variant-b-instrumented-spec.pen` and `knowledge-base/product/design/dashboard/action-feedback-variant-c-ember-glow.pen`. The exemption is backed by the mechanical diff invariant in AC6 and lapses on any added element, button, modal, toast, layout or class change (the work phase then stops to design).

#### Findings

CPO sign-off: YES (2026-10-30). The `single-user incident` threshold and the policy scope (author-only drafts, grant limited to `status` and `draft_preview`) are right from a founder-trust view; the column narrowing is what keeps the fix from being worse than today's inert state. Copy: the six strings were judged truthful and surface-neutral as proposed, with one condition the CPO asked to be verified, that the 403 copy's promise of a fresh authorization on retry actually holds. Verified by the planner against the gate: it does not (a revoked latest row is final and `first_send` is only reached with no row), so the three DENY strings and the two Settings strings were reworded to state the outcome without a promise and the gap was filed as #11630 (decision D12). CPO notes carried into the PR: say in the PR body that the fix works for authors only so the team-workspace 403 is not read as a regression (#11629, which now has a concrete trigger: the first Sentry `forbidden` on discard/edit from a non-author in a multi-member workspace); check that the `forbidden` copy for a non-author does not invite a retry; no bulk-archive of the 1943 stuck drafts, with a bulk-clear question parked on #11629.

### Legal / GDPR (advisory)

**Status:** reviewed (`soleur:gdpr-gate`, plan Phase 2.7, advisory, 2026-10-30)
**Assessment:** no `Critical` or `Important` finding. Checks `GDPR-Art-6`, `Art-5e`, `Art-17` / `Art-17-caller`, `Chapter-V` and `Art-9` do not fire: migration 181 adds no column, table, FK, vendor or retention change and processes no new category of data. Two `Suggestion` notes: (1) the column-narrowed UPDATE grant is an Art. 32(1)(b) / Art. 25 least-privilege improvement, keep the `pg_attribute`-derived verify row; (2) SELECT stays workspace-wide while UPDATE is author-only, a conservative asymmetry that widens no existing access (co-owner question tracked as #11629). `compliance-posture.md` is not modified; no `compliance/critical` issue is required. Not legal review; `soleur:legal:clo` consulted only if a reviewer escalates.

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-303 (not a new ADR) in this plan, as an in-scope task: add one Consequences bullet stating that migration 181
narrows `public.messages` UPDATE from the default-era table-level grant to `(status, draft_preview)` for `authenticated`
(and revokes it from `anon`), paired with the owner-draft policy `messages_owner_draft_update`, and that the
`table-grants.ts` column-split entry is how the grant guard sees it. Reason (architecture review P1): ADR-303's
Consequences defer per-relation narrowing to #11193 and never mention 178 or 181, so a reader would conclude `messages`
still carries the default UPDATE. No new decision is made (ADR-303's mechanism, mig 178's ordering precedent).

### C4 views

No C4 impact. Checked against all three model files (`model.c4`, `views.c4`, `spec.c4`): external human actor `founder`
(workspace Owner, model.c4 `founder = actor`; unchanged, still the only actor writing drafts); external systems: none
added, no vendor, webhook or store; container/data store: `platform.infra.supabase` (the "Supabase PostgreSQL" database,
already in the platform views at views.c4) and `platform.webapp.dashboard` / `platform.webapp.api`, all unchanged; the
actor-to-surface relationship `founder -> webapp` and `webapp -> supabase` ("Auth and data") already model an
authenticated browser session reading and writing data, and no derived count embedded in an edge description moves
(verified by running `plugins/soleur/test/c4-count-parity.test.sh`, an AC below).

### Sequencing

The ADR amendment lands in the same PR as the migration; nothing is deferred.

## Encryption Posture

Skipped: no new persistent store and no new cross-component connection. Migration 181 changes who may UPDATE two columns
of the existing `public.messages` table; the table's storage and transport are unchanged.

## Test Scenarios

1. Author discards a draft (dev DB, real rows): 1 row, status archived. Author edits `draft_preview`: 1 row.
2. Second workspace member, other-workspace member, `anon`: 0 rows / 42501, row unchanged on service-role re-read.
3. Author sets status `complete`, rewrites `content`, `workspace_id`, `trust_tier`: denied, row unchanged.
4. Founder dismisses a kb-drift digest or discards a Stripe draft on dev after the migration: the route returns 200, the card disappears, and navigating away and back within 60 s does not bring it back (no-store fetch); a second Discard from another tab shows the "already handled" line, not a bare 403.
5. Founder clicks Send with a replayable approval older than 23 h: 409 `approval_expired`, card cleared on refresh (archive now works).
6. Edit after Send-approve: 409 `draft_already_approved`, copy offers Send or Discard; Discard works.
7. A 403 `template_revoked` / `template_expired` / `template_quota_exhausted` response shows the new button-neutral line in the card and in the typed-confirm modal path, and a second Send on the same hash returns the same 403 without calling `authorize_template` (the reason the copy promises nothing; #11630).
8. Harness: an ambiguous fragment is refused; an exact-label fragment is credited only by its own row; `test-argv-bearer-sweep.sh` finishes with an open stdin.

## Risks and Sharp Edges

- **A migration applied to dev is byte-frozen** for the life of the PR (runbook §0). Dry-run in a rolled-back transaction first; do not "fix a comment" after the dev apply.
- **Do not copy policy names between dev and prd.** The migration creates its own name and `DROP POLICY IF EXISTS`; the verify file counts permissive UPDATE/ALL policies so an out-of-band policy on either project is caught, not inherited.
- **`REVOKE ... FROM PUBLIC, anon, authenticated` before the column `GRANT`.** The reverse order strips the new grant. Learning 2026-03-20 and mig 178.
- **Deparse-aware sentinels.** `pg_policies` renders `(SELECT auth.uid())` as `( SELECT auth.uid() AS uid)` and `IN (...)` as `= ANY (ARRAY[...])`; assert the literal `user_id = ( SELECT auth.uid()` and do not match a bare `auth.uid()` (tautological: `is_workspace_member(..., auth.uid())` contains it).
- **A deny test can pass for the wrong reason.** Every denial case has a positive control and a service-role re-read; payloads are type-valid UUIDs.
- **Column-level 42501 vs RLS zero rows.** Updating `content` fails with `permission denied` (grant), updating another author's draft returns zero rows (RLS), setting `status='complete'` fails WITH CHECK (42501). The tests assert the right shape per case, not "any error".
- **Team workspaces.** Draft cards are author-only end to end: the Today list filters `user_id`, so a co-owner never sees a teammate's card and reaches a 403 only through a stale tab or a direct API call (spec-flow corrected the first draft of this plan, and #11629 was rewritten to match). 1898 of the 1943 prod drafts sit in multi-member workspaces. A draft whose author later left the workspace is invisible and cannot be discarded by the new policy (`is_workspace_member` in USING); nothing lists it either.
- **Deploy order and skew.** The release pipeline runs `migrate`, `verify-migrations`, then `deploy`, so the normal window is new DB with the old app, which is safe (the routes write only `status` and `draft_preview`; the old Edit-409 copy is merely stale). The reverse window (new copy, old DB) exists only if migrate is skipped or `skip_deploy` is used: the copy would then offer Discard while it 403s. Deploy is gated on migrate success; do not hand-deploy this app build ahead of 181.
- **Stale Today list after Discard.** Fixed by the `cache: "no-store"` fetch (Phase 3 step 6); without it a revalidation inside the 60 s `max-age` can resurrect a discarded card.
- **Dead end on a template 403.** The new button-neutral 403 strings promise nothing and, on the GitHub and kb-drift cards (no Discard), leave the card stuck until #11630 lands (taste; decision D14).
- **Edit/Discard on an approved draft.** Discard of a draft that already has an `action_sends` approval row archives the message and leaves the approval row; the approval cannot send an archived draft (`not_a_draft`). This is the behaviour before #11566 removed the copy; confirmed by the Edit-409 path being pre-update. Only the Stripe card renders Discard and Edit, and prd has no Stripe drafts, so this path is reachable in prod only after Stripe drafts appear.
- **The send route comment "RLS owner-update"** becomes true; no edit.
- A plan whose `## User-Brand Impact` is empty fails `deepen-plan` Phase 4.6; this one is filled.

## Non-Goals

- Narrowing DELETE/TRUNCATE/other table-level verbs on `messages` (ADR-303 follow-up; not part of this P1).
- Bulk-archiving the 1943 stuck prod drafts.
- Co-owner access to teammates' drafts (#11629).
- Seam removal in sibling probes, the structure suite, unifying scorer protocols (#11628).
- Any Better Stack alert or Sentry alert change.
- Fixing the missing recovery path after a template authorization is revoked, expires or is exhausted (#11630); this PR only stops the copy from promising it.

## References

- Issues: #11569, #11572, #11486 (origin), #11520, #11566 (predecessor PR), #11628, #11629, #11630, #3220 (overlap, acknowledged).
- ADR-303 (explicit data-API grants, two-tier guard); ADR-111 (RLS fuzz harness); ADR-073 (N co-owners).
- Migrations: 059, 068, 134, 174, 176, 178, 180. Runbook: `knowledge-base/engineering/operations/runbooks/supabase-migrations.md`.
- Prior plan (copy exemption and harness extraction): `knowledge-base/project/plans/archive/20261030-094556-2026-10-29-chore-todaycard-send-copy-and-mutation-harness-plan.md`.
