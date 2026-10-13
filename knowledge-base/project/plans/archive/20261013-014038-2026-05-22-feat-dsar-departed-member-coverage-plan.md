---
title: DSAR departed-workspace-member coverage
issue: 4230
umbrella: 4229
draft_pr: 4294
branch: feat-dsar-workspace-member-4230
spec: knowledge-base/project/specs/feat-dsar-workspace-member-4230/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-05-22-dsar-workspace-member-extension-brainstorm.md
status: planned
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
user_brand_critical: true
date: 2026-05-22
estimate_days: 3-4
follow_ups:
  - 4319 (author-only message redaction, split per legal-compliance-auditor + plan-review consensus)
---

# Plan — DSAR Departed-Workspace-Member Coverage (#4230)

## Overview

Add departed-member coverage to the DSAR export pipeline so members removed
from a workspace can still exercise GDPR Art. 15 / 17 / 20 over their
identifiable rows. The umbrella (#4229 / PR #4225) shipped multi-user team
workspaces but explicitly deferred this follow-up; landing it unblocks
`FLAG_TEAM_WORKSPACE_INVITE=1` (#4284) for the first non-jikigai workspace.

**Approach A + B**, per operator decision (re-confirmed post-plan-review):

- **A** — UNION current `workspace_members` with historical
  `workspace_member_attestations` to recover `workspaceIds` for departed
  members at `dsar-export.ts:609-630`. Symmetric `.or()` fix at `:678-697`
  so an ex-member's INVITER-side attestation rows export under their
  identifier (currently `.eq("invitee_user_id", …)` misses these). Paired
  with `assertReadScope` two-arm update at `:689-691` (Kieran P1-1).
- **B** — New `workspace_member_removals` WORM ledger captures
  `(removed_user_id, removed_by_user_id, removed_at, workspace_id)` for
  every `remove_workspace_member` invocation. Mirrors
  `058_workspace_member_attestations.sql` WORM-trigger + anonymise-RPC +
  retention-sweep patterns verbatim. Operator chose to capture removal
  lineage in this PR rather than spawn a follow-up.

**Scope-split (decided pre-/work):** Author-only message redaction is
filed as **#4319** per all 3 plan-reviewers + legal-compliance-auditor
convergence. Affects ALL DSARs (not just departed-member); Art. 15(4)
"rights of others" design decision; carries Art. 13(2)(b) disclosure that
must coordinate with PR #4289.

**Scope-cuts (operator confirmed post-plan-review):**

- No `MANIFEST_SCHEMA_VERSION` bump (no consumers; bump when #4319 lands).
- No `removed_by_email_at_time` snapshot column (live FK is sufficient;
  if remover later anonymises, bundle shows `null` — same semantic as
  existing `workspace_member_attestations.invitee_user_id` after anonymise).
- No inline copy fold in `membership-revoked-screen.tsx` (separate sibling PR
  per DHH; 5-line UI change should not gate a Postgres migration).
- No cross-PR `ready`-state gate on PR #4289 (cross-link only; redaction
  carrier dependency moves to #4319's PR).

**Legal text** lands in PR #4289 (open, draft) — DPD §2.3, privacy-policy,
gdpr-policy departed-member language. **PA-19 row** in
`article-30-register.md` + `compliance-posture.md` Active Item row +
accountless-ex-member runbook ride THIS PR (Art. 30(1) commencement).

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality (verified via grep at plan-write) | Plan response |
|---|---|---|
| "FR3 new `workspace_member_removals` table" | `058:72-141` provides canonical WORM pattern; `058:342-401` provides canonical anonymise-RPC shape. | Mirror 058. Migration file is `062_workspace_member_removals_and_remove_rpc_update.sql` (Kieran P1-2). |
| "FR4 modify `remove_workspace_member`" | `058:267-326` is SECURITY DEFINER plpgsql with AC-FLOW4 guards + `REVOKE/GRANT` matrix. | `CREATE OR REPLACE` in migration 062 MUST preserve `SECURITY DEFINER`, `SET search_path = public, pg_temp`, `REVOKE ALL ... FROM PUBLIC, anon, authenticated`, `GRANT EXECUTE TO authenticated` (Kieran P1-4). Add INSERT before line 320's DELETE. |
| "FR2 inviter-side attestation export" | `dsar-export.ts:672-697` comments "exporting both sides under one ownerField avoids the gap" — claim is WRONG. Code uses `.eq("invitee_user_id", X)`. | Replace with `.or("invitee_user_id.eq." + X + ",inviter_user_id.eq." + X)`. **Also** update `assertReadScope` at `:689-691` to two-arm (Kieran P1-1) — currently asserts single `ownerField: "invitee_user_id"` which will fire `CrossTenantViolation` on inviter-side rows. |
| "FR5 author-only redaction predicate" | Design change affects ALL DSARs, not departed-member-specific. | **Split to #4319**. Removed from this plan. |
| "FR1 workspaceIds UNION" | `dsar-export.ts:609-630` derives from current memberships only. | Add `service.from("workspace_member_attestations").select("workspace_id").eq("invitee_user_id", X)` query; merge into `workspaceIds` via `Set` union before line 639. |
| "DEP3 PR #4289 must land first" | PR #4289 OPEN, draft (updated today). | Cross-link both PRs in bodies. NO `ready`-state gate (redaction dependency moved to #4319 per plan-review). |
| Issue title "query by `workspace_member_id`" | Composite PK is `(workspace_id, user_id)`; no UUID surrogate. `dsar-reauth.ts` needs NO changes. | Title kept for traceability; mechanism reframed. |
| supabase-js `.or()` syntax | Confirmed in `node_modules/@supabase/postgrest-js/src/PostgrestFilterBuilder.ts:652-662` (v2.99.2). Plan-time grep shows ZERO existing usages in repo. | First-of-kind pattern. Integration test fixture in AC4 includes inviter-side-only row to lock the contract. |

## User-Brand Impact

**If this lands broken, the user experiences:** a departed member files a
GDPR Art. 15 request, signs in to their still-active Soleur account, and
receives an export bundle whose `workspaces/` and
`workspace_member_attestations/` sections silently omit any workspace
they have left — perceived to them as a denial of right-of-access for
the workspaces they care most about (post-employment, post-team-split,
post-fallout context).

**If this leaks, the user's data is exposed via:** the new
`workspace_member_removals` WORM ledger contains
`(removed_user_id, removed_by_user_id, removed_at)`. A buggy RLS
predicate or service-role leak would expose "person X removed person Y
on $date" to co-members. Severity: lower than message-content leakage
but still personal data.

**Brand-survival threshold:** `single-user incident`. A single ex-member
filing an Art. 15 request and receiving an incomplete export OR a
single incorrect cross-tenant exposure is brand-survival-relevant.

`user-impact-reviewer` will be invoked at PR review (mandatory per
`USER_BRAND_CRITICAL=true`).

## Domain Review

**Domains relevant:** Engineering, Product, Legal (brainstorm Phase 0.5
carry-forward + plan-time `legal-compliance-auditor` + `spec-flow-analyzer`).

### Engineering (CTO carry-forward)

**Status:** reviewed
**Assessment:** Approach A (zero schema, ~1-2 days) + Approach B (new
WORM table + RPC mod + anonymise + retention sweep, +ADR, ~3-5 days)
selected. Confirmed substrate exists; mirror 058 patterns verbatim.

### Product (CPO carry-forward)

**Status:** reviewed
**Assessment:** Target user at gate is operator's 10-person prospect.
Expected volume &lt;5 lifetime accountless ex-members. Authenticated-only
intake; runbook for accountless. Mixed-ownership redaction is split to
#4319.

### Legal (CLO carry-forward + plan-time legal-compliance-auditor)

**Status:** reviewed
**Assessment:** 3 GO/NO-GO gates for flag-flip per brainstorm. Gate 1
(`ON DELETE RESTRICT` blocks Art. 17) tracked as separate P1 #4299;
defense-in-depth cascade-order slice for the new table is in scope here.
Gate 2 (quoted-content predicate) → split to #4319. Gate 3 (unauth
inbound) → runbook only.

**Plan-time legal-compliance-auditor findings folded:**

- PA-19 row in `article-30-register.md` (next available; verified via
  `grep "^## Processing Activity" knowledge-base/legal/article-30-register.md`).
  36-mo retention rationale recorded in ADR-039.
- Accountless runbook with Art. 12(6) ID-verification template + 30-day
  SLA: new file `knowledge-base/legal/runbooks/dsar-accountless-ex-member.md`.
- `legal-doc-cross-document-gate.yml` fires on `knowledge-base/legal/**` —
  PA-19 + `compliance-posture.md` row + runbook all paired in this PR.
- Cross-PR coordination on PR #4289 collapses to body cross-link (no
  `ready`-state gate); the Art. 13(2)(b) disclosure dependency moved to
  #4319 with the redaction predicate.

### Product/UX Gate

**Tier:** none — no new user-facing pages or components in this PR.
The 5-line `membership-revoked-screen.tsx` discoverability fold filed
as separate sibling PR (DHH simplicity argument).

### Brainstorm-recommended specialists

- `architecture-strategist` — invoke via `/soleur:architecture create
  'DSAR departed-member coverage via removal-event ledger'` for ADR-039
  (Phase 0).
- `legal-document-generator` + `legal-compliance-auditor` — routed via
  PR #4289 (legal scaffolding WIP).
- `user-impact-reviewer` — invoked at PR review (auto-fires on
  `USER_BRAND_CRITICAL=true`).

### Skipped specialists

- `ux-design-lead` — no UI changes in scope.
- `copywriter` — no marketing copy; legal text is auditor-routed via #4289.

## Files to Edit

- `apps/web-platform/server/dsar-export.ts` — modify `workspaceIds`
  derivation at L609-630 (Approach A); modify attestation export at
  L678-697 (inviter-side symmetry) AND `assertReadScope` two-arm at
  L689-691 (Kieran P1-1); add `workspace_member_removals` block
  (Approach B); update the stale "avoids the gap" comment at L672-677.
- `apps/web-platform/server/dsar-export-allowlist.ts` — add
  `workspace_member_removals` entry.
- `apps/web-platform/server/account-delete.ts` — extend cascade order
  to call `anonymise_workspace_member_removals` BEFORE
  `auth.admin.deleteUser()`. (Verify path via `git ls-files | grep
  account-delete` at Phase 0.)
- `apps/web-platform/test/dsar-allowlist-completeness.test.ts` — auto-
  extends from the allowlist source-of-truth; no edit needed unless
  the migration discovery set diverges.
- `knowledge-base/legal/article-30-register.md` — add PA-19 row.
- `knowledge-base/legal/compliance-posture.md` — update DSAR coverage
  Active Item row.

## Files to Create

- `apps/web-platform/supabase/migrations/062_workspace_member_removals_and_remove_rpc_update.sql`
  + `.down.sql` — new table + WORM trigger + anonymise RPC + retention
  sweep + RLS (REVOKE INSERT FROM authenticated; no owner-insert
  policy per `cq-WORM-bypass`); `CREATE OR REPLACE FUNCTION
  public.remove_workspace_member` preserving all 058 clauses + adding
  INSERT before DELETE. Migration name carries `_and_remove_rpc_update`
  per Kieran P1-2 so `grep -l remove_workspace_member migrations/`
  surfaces both files honestly. Down-migration includes verbatim
  pre-change body of `remove_workspace_member` (load-bearing
  duplication of 058's RPC — AC1 covers parity check).
- `apps/web-platform/test/dsar-departed-member.integration.test.ts` —
  golden-fixture test per AC6.
- `knowledge-base/legal/runbooks/dsar-accountless-ex-member.md` —
  Art. 12(6) ID-verification template + 30-day SLA + audit-log
  template + CLO escalation clause.
- `knowledge-base/engineering/architecture/decisions/ADR-039-departed-member-removal-ledger.md`
  — created via `/soleur:architecture create` (Phase 0). Records:
  WORM-ledger invariant, 36-mo retention rationale (deviates from
  PA-PII 24-mo; Art. 82 limitation horizon), cascade-order requirement,
  RLS deviation note (departed members cannot read their own removal
  row via `is_workspace_member` — DSAR service-role read only; per
  Kieran observation).

## Open Code-Review Overlap

None. Verified via `gh issue list --label code-review --state open` + `jq
contains($path)` over `dsar-export.ts`, `dsar-export-allowlist.ts`,
`058_workspace_member_attestations.sql`, `041_dsar_export_jobs.sql`. Zero
matches against 75 open issues.

## Resolved Decisions (post-brainstorm + plan-review)

1. **Approach B kept** — operator confirmed post-plan-review (Kieran "ship
   with trims" branch). DHH+Simplicity argued for defer-B; operator
   weighed lineage-capture in same PR as worth the +2-3 day overhead.
2. **Author-only redaction split** — confirmed split to #4319 per
   all 3 reviewers + legal-compliance-auditor (CRITICAL).
3. **No snapshot column** — `removed_by_email_at_time` not added. Live
   FK is sufficient; bundle shows null for anonymised removers, same
   semantic as existing `workspace_member_attestations` post-anonymise.
4. **No manifest schema bump** — `MANIFEST_SCHEMA_VERSION` stays
   `"1.0.0"`. Additive `historical_workspaces` field can land without
   bump; bump when #4319 (which adds a `redactions` field) lands.
5. **No inline copy fold** — `membership-revoked-screen.tsx` discoverability
   filed as separate sibling PR (DHH simplicity).
6. **No cross-PR `ready`-state gate** — body cross-link only.
7. **#4299 fold-in scope** — cascade-order extension for the new table is
   added in `account-delete.ts` (one line); #4299's full sister-table
   resolution stays separate.

## Acceptance Criteria

### Pre-merge (PR)

- **AC1 (migration shape):** Migration `062_workspace_member_removals_and_remove_rpc_update.sql`
  creates the table with WORM trigger matching
  `workspace_member_attestations_no_mutate` shape (DELETE always
  rejected; UPDATE only allowed for `removed_user_id IS NULL` and
  `removed_by_user_id IS NULL` transitions; lineage columns `id`,
  `workspace_id`, `removed_at` immutable). `CREATE OR REPLACE
  FUNCTION public.remove_workspace_member` preserves all 058 clauses
  (SECURITY DEFINER, `SET search_path = public, pg_temp`, REVOKE
  matrix, GRANT EXECUTE TO authenticated) — verified by
  `grep -A2 'CREATE OR REPLACE FUNCTION public.remove_workspace_member'
  migrations/062_*.sql | grep -E 'SECURITY DEFINER|search_path|REVOKE|GRANT'`
  returns ≥4 matches. Down-migration drops cleanly and includes
  verbatim pre-change `remove_workspace_member` body; parity test asserts
  058's source RPC body matches the 062.down.sql copy.

- **AC2 (RPC failure propagation — Kieran P0-2 fix):** If the INSERT
  into `workspace_member_removals` raises (FK violation on
  `removed_user_id`, constraint violation), the surrounding
  `remove_workspace_member` RPC propagates the exception and the
  DELETE does NOT execute. Verified by integration test that forces
  an FK violation (e.g., passes a `removed_user_id` that violates
  RESTRICT). Post-test, the membership row is still present.

- **AC3 (workspaceIds UNION):** `dsar-export.ts:609-630` UNIONs
  current memberships with historical `workspace_member_attestations`
  on `invitee_user_id = X`. Departed-Harry integration test (AC6 (a))
  asserts the export contains workspace metadata for the workspace
  Harry left.

- **AC4 (symmetric attestation export + assertReadScope two-arm —
  Kieran P1-1):** `dsar-export.ts:678-697` uses
  `.or("invitee_user_id.eq." + X + ",inviter_user_id.eq." + X)` (or
  the equivalent supabase-js v2.99.2 string-filter syntax verified at
  Phase 0). `assertReadScope` at L689-691 updated to two-arm
  assertion: `row.invitee_user_id === expectedUserId OR
  row.inviter_user_id === expectedUserId`. Verified by integration
  test fixture containing an inviter-side-only row (departed Harry
  invited Bob before Harry left; Bob's attestation has
  `inviter_user_id = Harry`).

- **AC5 (allowlist):** `dsar-export-allowlist.ts` contains a
  `workspace_member_removals` entry with `ownerField:
  "removed_user_id"`, `article: "15"`.
  `dsar-allowlist-completeness.test.ts` passes.

- **AC6 (golden-fixture integration test):** Integration test
  `dsar-departed-member.integration.test.ts` passes against
  dev-Supabase. Asserts: (a) departed user's bundle contains
  workspace metadata for the workspace they left, (b) bundle contains
  a `workspace_member_removals` row recording the removal event,
  (c) bundle contains BOTH invitee-side AND inviter-side attestation
  rows where the user appears, (d) post-removal `dsar-reauth` and
  full export pipeline succeed for the removed user (spec-flow P1-4
  verification).

- **AC7 (ADR + legal docs):** ADR-039 exists at
  `knowledge-base/engineering/architecture/decisions/` recording:
  WORM-ledger invariant + 36-mo retention rationale + cascade-order
  requirement + RLS deviation note. PA-19 row in
  `knowledge-base/legal/article-30-register.md`: controller, Art.
  6(1)(c) lawful basis, 36-mo retention. `compliance-posture.md`
  DSAR Active Item row references this PR. Runbook
  `knowledge-base/legal/runbooks/dsar-accountless-ex-member.md`
  exists with Art. 12(6) template + 30-day SLA.

- **AC8 (review-time gates):** `user-impact-reviewer` agent passes
  (mandatory per `USER_BRAND_CRITICAL=true`); `/soleur:gdpr-gate`
  skill audit passes; `cq-pg-security-definer-search-path-pin-pg-temp`
  verified for both `remove_workspace_member` (preserved) and new
  `anonymise_workspace_member_removals`; `cq-WORM-bypass` verified
  by `grep "INSERT.*workspace_member_removals" apps/web-platform/server/`
  returning only the RPC call site (no TS-level inserts). PR body uses
  `Ref #4230` (not `Closes`; ops-remediation class). PR body cross-links
  #4289.

### Post-merge (automated)

- **AC9:** `web-platform-release.yml#migrate` applies migration 062 to
  prd-Supabase. Verification: `mcp__plugin_supabase_supabase__*` query
  for `workspace_member_removals` table + RLS policy count + RPC
  existence. Captured in ship-skill post-merge block.
- **AC10:** `gh issue close 4230` triggered after AC9 confirms.
  Follow-through #4284 (flag-flip) re-evaluated once AC9+AC10 + PR
  #4289 merge are all green.

## Implementation Phases

### Phase 0 — Preconditions

- **0.1** Read `058_workspace_member_attestations.sql` L41-141 + L267-401
  verbatim. Confirm WORM-trigger shape + anonymise RPCs + REVOKE matrix.
- **0.2** `git ls-files | grep account-delete` → locate cascade-order
  insertion point. Read the existing anonymise cascade.
- **0.3** Verify supabase-js `.or()` syntax against installed v2.99.2 at
  `node_modules/@supabase/postgrest-js/src/PostgrestFilterBuilder.ts`.
  Plan-time grep already confirmed; AC4 will exercise.
- **0.4** Invoke `/soleur:architecture create 'DSAR departed-member
  coverage via removal-event ledger'`. Confirm ADR-039 path.

### Phase 1 — Migration 062

- **1.1** `062_workspace_member_removals_and_remove_rpc_update.sql`:
  table DDL — `(id uuid PK, workspace_id uuid NOT NULL REFERENCES
  workspaces ON DELETE RESTRICT, removed_user_id uuid NULL REFERENCES
  users ON DELETE RESTRICT, removed_by_user_id uuid NULL REFERENCES
  users ON DELETE RESTRICT, removed_at timestamptz NOT NULL DEFAULT
  now())` + WORM trigger function mirroring 058:72-141 + REVOKE
  INSERT/UPDATE/DELETE FROM `PUBLIC, anon, authenticated` + SELECT-for-members
  RLS policy.
- **1.2** `anonymise_workspace_member_removals(p_user_id uuid)`
  SECURITY DEFINER RPC mirroring 058:342-362 (NULL out
  `removed_user_id` and `removed_by_user_id`, preserve `id`,
  `workspace_id`, `removed_at`).
- **1.3** `CREATE OR REPLACE FUNCTION public.remove_workspace_member`:
  paste 058:267-331 verbatim, then INSERT `workspace_member_removals`
  row capturing `(workspace_id = p_workspace_id, removed_user_id =
  p_user_id, removed_by_user_id = v_caller_user_id)` BEFORE the
  DELETE at line 320. **Preserve all existing AC-FLOW4 guards.
  Preserve `SECURITY DEFINER`, `SET search_path = public, pg_temp`,
  REVOKE matrix, GRANT EXECUTE — paste verbatim, do not paraphrase**
  (Kieran P1-4).
- **1.4** pg_cron retention sweep at 36-mo, GUC-bypass shape per
  `041:383-395`. Explicit GUC name: `app.workspace_member_removal_anonymise_in_progress`
  set to `'true'` inside the sweep RPC; WORM trigger checks
  `current_setting('app.workspace_member_removal_anonymise_in_progress', true) = 'true'
  AND current_user = 'service_role'` for bypass.
- **1.5** `.down.sql`: DROP trigger, DROP `anonymise_workspace_member_removals`,
  DROP table, DROP retention sweep, `CREATE OR REPLACE FUNCTION
  public.remove_workspace_member` reverting to pre-change body (verbatim
  copy from 058:267-326 — load-bearing duplication; AC1 covers parity test).

### Phase 2 — DSAR export pipeline

- **2.1** `dsar-export.ts` L609-630 `workspaceIds`: add the
  historical-attestations query (`.from("workspace_member_attestations").select("workspace_id").eq("invitee_user_id", X)`);
  merge results into `workspaceIds` via `Set` union before line 639;
  preserve `CrossTenantViolation` assertion.
- **2.2** `dsar-export.ts` L678-697: replace
  `.eq("invitee_user_id", X)` with the `.or(...)` filter. Update
  `assertReadScope` invocation at L689-691 — pass a two-arm validator
  predicate (Kieran P1-1). Update L672-677 comment to remove stale
  "avoids the gap" claim.
- **2.3** `dsar-export.ts`: add `workspace_member_removals` export
  block (analog to attestations at L672-697) keyed on
  `.eq("removed_user_id", X)`.
- **2.4** `dsar-export-allowlist.ts`: add `workspace_member_removals`
  entry with `ownerField: "removed_user_id"`, `article: "15"`. Update
  comment block following the existing style.

### Phase 3 — Integration test

- **3.1** `test/server/dsar-departed-member.integration.test.ts`:
  synthesize 2 users + workspace, invite-accept, exchange messages,
  remove member, run export, assert AC6 (a)/(b)/(c)/(d). Use
  `cq-test-fixtures-synthesized-only` pattern. Include an
  inviter-side-only attestation fixture for AC4's two-arm scope check.
- **3.2** Add FK-violation transaction-rollback test for AC2:
  invoke `remove_workspace_member` against a target user_id that
  violates FK RESTRICT (e.g., user_id from a soft-test-deleted row),
  assert RPC raises AND membership row remains intact.

### Phase 4 — Legal + cascade

- **4.1** Insert PA-19 row in `article-30-register.md`. Cross-doc-gate
  fires; AC7 pairs PA-19 + compliance-posture in this PR.
- **4.2** Update `compliance-posture.md` DSAR Active Item row to
  reference this PR + the cascade-order extension.
- **4.3** Create `knowledge-base/legal/runbooks/dsar-accountless-ex-member.md`
  (Art. 12(6) template + 30-day SLA + audit-log template + CLO escalation).
- **4.4** Extend `account-delete.ts` to call
  `anonymise_workspace_member_removals(p_user_id)` BEFORE
  `auth.admin.deleteUser()`, in the existing cascade order (after
  `anonymise_workspace_member_attestations`).

### Phase 5 — PR + ship gates

- **5.1** PR body authoring: `Ref #4230`, cross-link #4289 + #4319
  (redaction follow-up), legal-scaffolding handshake comment.
- **5.2** `/soleur:gdpr-gate` invocation on final diff (AC8).
- **5.3** `/soleur:preflight` Check 6 (USER_BRAND_CRITICAL gate).
- **5.4** Mark PR `ready` (no cross-PR gate; cross-link in body is
  sufficient per plan-review consensus).
- **5.5** `user-impact-reviewer` at PR review.

## Observability

Per `hr-observability-as-plan-quality-gate`:

```yaml
liveness_signal:
  what: "Successful DSAR export completion for a previously-removed workspace member returns a bundle containing workspace_member_removals row + workspace metadata for the workspace they left"
  cadence: per-DSAR-request (event-driven)
  alert_target: Sentry breadcrumb on dsar-export.ts:1314 (sendDsarExportReadyEmail) — existing tag `dsar_export.completed=true`; new tag `dsar_export.departed_workspace_count >= 0` added in Phase 2.
  configured_in: apps/web-platform/server/dsar-export.ts L1310-1320

error_reporting:
  destination: Sentry via existing `Sentry.captureException` at dsar-export.ts L1330-1340; new `extra.departed_workspace_count` tag.
  fail_loud: yes — existing alertable rule `dsar_export.failed`.

failure_modes:
  - mode: "workspace_member_removals INSERT fails inside remove_workspace_member RPC (FK violation, constraint)"
    detection: "RPC raises; TS wrapper `removeWorkspaceMember` reportSilentFallback catches; Sentry mirror under feature: workspace-membership, op: remove-rpc-failed"
    alert_route: Sentry P1 (existing `workspace-membership.*` routing)
  - mode: "historical-attestation UNION query returns malformed workspace_id (cross-tenant violation)"
    detection: "CrossTenantViolation thrown at dsar-export.ts existing L648-657; mirrorCrossTenantViolation Sentry hook fires"
    alert_route: Sentry P0 (existing CrossTenantViolation routing — single-user-incident threshold)
  - mode: "retention sweep DELETEs row outside intended 36-mo window"
    detection: "pg_cron sweep emits row count; daily Sentry breadcrumb tag `workspace_member_removals.swept_count` baseline-compared"
    alert_route: Sentry P2 (anomaly detection)

logs:
  where: existing dsar-export structured logger; new tags `dsar_export.departed_workspace_count`, `dsar_export.workspace_member_removals_count`
  retention: 30d (existing logger config)

discoverability_test:
  command: "psql $DEV_SUPABASE_URL -c 'SELECT COUNT(*) FROM public.workspace_member_removals; SELECT proname FROM pg_proc WHERE proname = ''anonymise_workspace_member_removals'';'"
  expected_output: "row count >= 0 (table exists); proname column returns 'anonymise_workspace_member_removals' (RPC exists)"
```

## Test Strategy

- **Unit:** new table's WORM trigger via SQL tests modeled on 058's
  trigger tests; verify path via `find test/server -name '*scope-grants*'`
  at Phase 0.
- **Integration:** `dsar-departed-member.integration.test.ts` —
  end-to-end against dev-Supabase (synthesized fixtures per
  `cq-test-fixtures-synthesized-only`).
- **FK-violation propagation (AC2):** integration test passes a
  removed_user_id violating FK RESTRICT; asserts exception propagates
  AND membership row intact.
- **Lint:** `dsar-allowlist-completeness.test.ts` validates new
  allowlist entry.
- **Down-migration parity:** lint asserts 062.down.sql's
  `remove_workspace_member` body equals 058's source (catches drift).
- Test runner: `vitest` (confirmed via `package.json scripts.test`).

## Risks & Assumptions

- **R1:** Modifying `remove_workspace_member` is a behavior change to a
  recently shipped RPC. Mitigation: keep DELETE semantics identical;
  only ADD the INSERT inside the same SECURITY DEFINER function body.
  Roll back via down-migration `CREATE OR REPLACE` reverting to
  pre-change body.
- **R2:** `workspace_member_removals.removed_user_id ON DELETE
  RESTRICT` intersects pre-existing #4299. Mitigation:
  `anonymise_workspace_member_removals` RPC called BEFORE
  `auth.admin.deleteUser()` in account-delete.ts cascade (Phase 4.4).
  #4299's full sister-table resolution remains separate scope.
- **R3:** `legal-doc-cross-document-gate.yml` fires on
  `knowledge-base/legal/**`. Failure to update `compliance-posture.md`
  alongside `article-30-register.md` blocks merge. AC7 pairs them.
- **R4:** `.or()` is first-of-kind in the repo. AC4's two-arm
  `assertReadScope` change is load-bearing — without it, AC3's
  golden-fixture test fires `CrossTenantViolation` on inviter-side
  rows. Kieran P1-1 catch.
- **A1:** Operator's prospect (10-person team) does not require
  accountless ex-member self-serve at gate. If false, runbook (AC7)
  is insufficient and `legal@jikigai.com` volume forces a public-form
  brainstorm (per #4302 trigger).
- **A2:** 36-mo retention for `workspace_member_removals` (deviating
  from 24-mo `dsar_export_audit_pii` precedent). Justification:
  Art. 82 limitation horizon. ADR-039 records.
- **A3:** `vitest` is the test runner. Confirmed via `package.json
  scripts.test`; no `bun test`.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail
  `deepen-plan` Phase 4.6 and `/soleur:preflight` Check 6. Populated
  above — do NOT replace during /work.
- WORM-table convention: do NOT add an owner-insert RLS policy on
  `workspace_member_removals`. Writes flow ONLY through the modified
  `remove_workspace_member` RPC. Verified by AC8.
- Cascade-order load-bearing: `anonymise_workspace_member_removals`
  MUST run BEFORE `auth.admin.deleteUser()` in `account-delete.ts`,
  same pattern as `anonymise_workspace_member_attestations` (058
  L342). Failure to thread this leaves Art. 17 erasure broken for any
  user who has ever been removed from a workspace.
- `CREATE OR REPLACE FUNCTION` does NOT preserve clauses from the
  prior body — every clause must be re-stated in the new
  definition. Phase 1.3 specifies paste-verbatim-then-modify;
  failing to preserve `SECURITY DEFINER + SET search_path = public,
  pg_temp + REVOKE/GRANT` is exactly the failure mode
  `cq-pg-security-definer-search-path-pin-pg-temp` exists to catch
  (Kieran P1-4).
- supabase-js `.or()` paired with `assertReadScope`: the existing
  scope helper asserts a single `ownerField`. The `.or()` change
  introduces two valid ownerFields per row class — `assertReadScope`
  must be two-arm-aware. AC4 covers (Kieran P1-1).
- Migration discipline (#4241 root cause): do NOT apply
  `062_workspace_member_removals_and_remove_rpc_update.sql` to
  dev-Supabase ahead of main. Let `web-platform-release.yml#migrate`
  apply on merge.
- PA numbering: PA-19 verified next available at plan-write time
  (PA-1..PA-18 exist; non-sequential ordering of PA-16/17/18 acceptable
  per existing register style).

## Out of Scope (deferred — tracking issues exist)

- **#4319** — Author-only message redaction (Art. 15(4) rights-of-others
  predicate; split per legal-compliance-auditor + 3-reviewer
  consensus; gated on PR #4289 ready-for-review).
- **#4299** — Pre-existing `ON DELETE RESTRICT` blocking Art. 17 cascade
  on sister tables. This PR's cascade-order extension for
  `workspace_member_removals` is defense-in-depth; full resolution
  stays at #4299.
- **#4301** — `runtime_cost_state` RLS-coverage audit.
- **#4302** — Public/email-proof DSAR intake form re-evaluation tracker.
- **`membership-revoked-screen.tsx` inline DSAR-link copy** —
  separate 5-line sibling PR (DHH simplicity).
- **Leave-email pipeline** — Resend template + transactional plumbing
  not in scope; track as follow-up at first accountless-DSAR signal.
- **Roadmap.md team-workspace-pivot update** — small CPO action,
  separately tracked.

## Cited References

- `058_workspace_member_attestations.sql:72-141` — WORM trigger function +
  triggers + REVOKE matrix (mirror target for migration 062).
- `058_workspace_member_attestations.sql:267-326` — `remove_workspace_member`
  RPC (paste-verbatim-then-modify target).
- `058_workspace_member_attestations.sql:342-401` — anonymise RPCs
  (mirror target for new `anonymise_workspace_member_removals`).
- `dsar-export.ts:609-630, 672-697, 689-691` — workspaceIds + attestation
  export + assertReadScope sites (modification targets).
- Learnings: `2026-05-21-worm-ledger-rls-owner-insert-policy-is-an-rpc-bypass.md`,
  `2026-05-21-dev-supabase-drift-from-unmerged-feature-branch-migrations.md`,
  `2026-05-15-worm-trigger-blocks-pg-cron-retention-sweep.md`.

## Resume Prompt

```text
/soleur:work knowledge-base/project/plans/2026-05-22-feat-dsar-departed-member-coverage-plan.md

Branch: feat-dsar-workspace-member-4230. Worktree: .worktrees/feat-dsar-workspace-member-4230/.
Issue: #4230. PR: #4294 (draft). Cross-PR: #4289 (legal scaffolding, body cross-link only).
Redaction split: #4319.

Plan-reviewed (DHH/Kieran/Simplicity). All converged trims applied.
Approach A+B kept per operator. ADR pending Phase 0.4 invocation.
```
