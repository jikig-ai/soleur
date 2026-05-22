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
estimate_days: 4-6
---

# Plan — DSAR Departed-Workspace-Member Coverage (#4230)

## Overview

Add departed-member coverage to the DSAR export pipeline so members removed
from a workspace can still exercise GDPR Art. 15 / 17 / 20 over their
identifiable rows. The umbrella (#4229 / PR #4225) shipped multi-user team
workspaces but explicitly deferred this follow-up; landing it unblocks
`FLAG_TEAM_WORKSPACE_INVITE=1` (#4284) for the first non-jikigai workspace.

**Approach A + B combined**, per operator decision at brainstorm:

- **A** — UNION current `workspace_members` with historical
  `workspace_member_attestations` to recover `workspaceIds` for departed
  members at `dsar-export.ts:609-630`. Symmetric fix at `:678-697` so an
  ex-member's INVITER-side attestation rows export under their identifier
  (currently `.eq("invitee_user_id", …)` misses these).
- **B** — New `workspace_member_removals` WORM ledger captures
  `(removed_user_id, removed_by_user_id, removed_at, workspace_id)` for
  every `remove_workspace_member` invocation. Closes the Art. 15 lineage
  gap ("removed on $date by $whom"). Mirrors `058_workspace_member_attestations.sql`
  WORM-trigger + anonymise-RPC + WORM-bypass-GUC patterns line-by-line.

**Author-only message redaction** (CPO/CLO brainstorm consensus) is
**proposed as scope-split** per legal-compliance-auditor finding: the
predicate change affects ALL DSARs (not just departed members) and is a
distinct Art. 15(4) "rights of others" design decision that warrants its
own PR + privacy-policy disclosure coordinated with #4289. Surfaced for
plan-review reconciliation in §Open Decisions.

**Legal text** lands in PR #4289 (open, draft, updated today) — DPD §2.3,
privacy-policy, gdpr-policy departed-member language. PA-19 row addition to
`article-30-register.md` rides THIS PR per legal-compliance-auditor
(Art. 30(1) requires register at activity commencement).

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality (verified via grep at plan-write) | Plan response |
|---|---|---|
| "FR3 new `workspace_member_removals` table" | `058:72-141` provides the canonical WORM pattern (`workspace_member_attestations_no_mutate` + DROP-IF-EXISTS triggers + REVOKE matrix); `058:342-401` provides the canonical anonymise-RPC shape (NULL-out PII via UPDATE for retainable rows, DELETE for linkage-only rows). | Mirror 058 verbatim. New migration file is `062_workspace_member_removals.sql`. |
| "FR4 modify `remove_workspace_member` to INSERT removal row in same txn" | `058:267-326` is a SECURITY DEFINER plpgsql RPC; AC-FLOW4 short-circuits on `caller==target`. Adding an INSERT before the DELETE is one line; same txn semantics inherited. | New migration `062_*.sql` does `CREATE OR REPLACE FUNCTION` on the same name. |
| "FR2 inviter-side attestation export" | `dsar-export.ts:672-697` already comments "exporting both sides under one ownerField avoids the gap" — claim is WRONG. Code uses `.eq("invitee_user_id", X)` only. INVITER-side rows orphan. | Replace the `.eq()` with `.or(invitee_user_id.eq.X,inviter_user_id.eq.X)`. Update the comment to remove the stale claim. |
| "FR5 author-only redaction predicate" | `dsar-export-allowlist.ts:60-67` exports `messages` via joinVia `conversations.user_id`; current behavior returns ALL messages in user-owned conversations (multi-author leakage in team workspaces). | **Scope-split candidate per legal-compliance-auditor.** Hold pending §Open Decisions. |
| "FR1 workspaceIds UNION" | `dsar-export.ts:609-630` derives `workspaceIds` from `workspace_members.user_id` only; code at 606-608 comments "Phase 7.4 anonymises" but Phase 7.4 was the deferred #4230 work. | Add a second `service.from("workspace_member_attestations").select("workspace_id").eq("invitee_user_id", X)` query; merge into `workspaceIds` via `Set` union before line 639. |
| "DEP3 PR #4289 must land first" | PR #4289 OPEN, draft, last updated 2026-05-22T07:01Z (today). | Gate THIS PR's `ready` on PR #4289 entering ready-for-review per legal-compliance-auditor CRITICAL #3. |
| Issue title "query by `workspace_member_id`" | Composite PK is `(workspace_id, user_id)`; no UUID surrogate exists. `dsar-reauth.ts` needs NO changes. | Issue title kept for traceability; spec/plan reframed to actual mechanism. |

## User-Brand Impact

**If this lands broken, the user experiences:** a departed member files a
GDPR Art. 15 request, signs in to their still-active Soleur account, and
receives an export bundle whose `workspaces/` and `workspace_member_attestations/`
sections silently omit any workspace they have left — perceived to them as
a denial of right-of-access for the workspaces they care most about
(post-employment, post-team-split, post-fallout context).

**If this leaks, the user's data is exposed via:** the new
`workspace_member_removals` WORM ledger contains `(removed_user_id,
removed_by_user_id, removed_at)`. A buggy RLS predicate or service-role
leak would expose "person X removed person Y on $date" to co-members.
Severity: lower than message-content leakage but still personal data.

**Brand-survival threshold:** `single-user incident`. A single ex-member
filing an Art. 15 request and receiving an incomplete export OR a single
incorrect cross-tenant exposure is brand-survival-relevant.

`user-impact-reviewer` will be invoked at PR review (mandatory per
`USER_BRAND_CRITICAL=true`).

## Domain Review

**Domains relevant:** Engineering, Product, Legal (carry-forward from
brainstorm Phase 0.5 + plan-time `legal-compliance-auditor`).

### Engineering (CTO carry-forward)

**Status:** reviewed
**Assessment:** Approach A (zero schema, ~1-2 days) + Approach B (new
WORM table + RPC mod + anonymise + retention sweep, +ADR, ~3-5 days)
selected. Confirmed substrate exists; mirror 058 patterns verbatim.

### Product (CPO carry-forward)

**Status:** reviewed
**Assessment:** Target user at gate is operator's 10-person prospect.
Expected volume &lt;5 lifetime accountless ex-members. Authenticated-only
intake; runbook for accountless. Mixed-ownership redaction was CPO/CLO
consensus, now surfaced as scope-split candidate (see §Open Decisions).

### Legal (CLO carry-forward + plan-time legal-compliance-auditor)

**Status:** reviewed
**Assessment from brainstorm:** 3 GO/NO-GO gates for flag-flip. Gate 1
(`ON DELETE RESTRICT` blocks Art. 17) tracked as separate P1 #4299. Gate 2
(quoted-content predicate) → scope-split. Gate 3 (unauth inbound) → defer
to runbook.

**Plan-time legal-compliance-auditor findings:**

- **CRITICAL:** Author-only predicate is a separate Art. 15(4) "rights of
  others" design change affecting ALL DSARs. Recommend split to follow-up
  PR gated on #4289 (Art. 13(2)(b) transparency requires disclosure-at-
  collection). § Open Decisions item 1.
- **CRITICAL:** Cross-document sequencing — gate THIS PR's `ready` on
  PR #4289 entering ready-for-review. Otherwise new code lacks Art. 13
  transparency disclosure.
- **HIGH:** PA-19 (next available) added to `article-30-register.md` in
  THIS PR. 36-mo retention for removal rows (CLO-aligned, deviates from
  PA-PII 24-mo; document rationale).
- **HIGH:** Accountless runbook needs Art. 12(6) ID-verification template
  + 30-day SLA. New file: `knowledge-base/legal/runbooks/dsar-accountless-ex-member.md`.
- **HIGH:** Verify #4299 (`ON DELETE RESTRICT`) does not intersect — the
  new `workspace_member_removals.removed_user_id` FK to `users` IS itself
  `ON DELETE RESTRICT` (mirroring 058's convention). Anonymise RPC must
  run before `auth.admin.deleteUser()` per existing cascade order. Same
  pattern as attestations; contained within this PR.
- **MEDIUM:** `legal-doc-cross-document-gate.yml` fires on
  `knowledge-base/legal/**` changes. Cross-doc set: PA-19 in
  article-30-register, `compliance-posture.md` DSAR row update, runbook
  add. PR #4289 covers privacy-policy / DPD / gdpr-policy.

### Product/UX Gate

**Tier:** none — no new user-facing pages or components.
Discoverability surface (privacy-policy mention) routes via PR #4289;
in-app discoverability deferred (see Sharp Edges).

### Brainstorm-recommended specialists

- `architecture-strategist` — invoke via `/soleur:architecture create
  'DSAR departed-member coverage via removal-event ledger'` for the ADR
  (Phase 0).
- `legal-document-generator` + `legal-compliance-auditor` — routed via
  PR #4289 (legal scaffolding WIP).
- `user-impact-reviewer` — invoked at PR review (auto-fires on
  `USER_BRAND_CRITICAL=true`).

### Skipped specialists

- `ux-design-lead` — no UI changes in scope.
- `copywriter` — no marketing copy; legal text is auditor-routed.

## Open Decisions

These surfaced post-brainstorm via plan-time research. Plan-review
reviewers (DHH / Kieran / Simplicity) will weigh in.

**1. Author-only message redaction scope-split (CRITICAL).**

- **Brainstorm decision:** bundle in this PR (Approach A+B+redaction).
- **Plan-time finding:** legal-compliance-auditor + spec-flow flag that
  the predicate change is a separate Art. 15(4) "rights of others"
  decision affecting ALL DSARs (not just departed-member). Art. 13(2)(b)
  disclosure must coordinate with PR #4289.
- **Recommendation:** SPLIT to follow-up PR gated on #4289. Reasons:
  (a) reduces blast radius of this PR; (b) avoids privacy-policy drift
  if THIS PR merges first; (c) the departed-member core
  (workspaceIds UNION + removals ledger + symmetric attestation) is the
  brand-survival-load-bearing surface; (d) redaction can ride PR #4289
  side-by-side with the disclosure copy.
- **Decision needed before /work begins.** If operator confirms split,
  delete FR5/AC4 below and file follow-up issue with re-eval criteria.

**2. Discoverability — inline copy in MEMBERSHIP_REVOKED screen (P0 per spec-flow P0-1a).**

- `apps/web-platform/components/dashboard/membership-revoked-screen.tsx:42-57`
  is the terminal screen shown when a member is removed mid-session. Today
  it makes no mention of data retention or DSAR rights — Art. 13(2)(b)
  "at the time" notification gap.
- **Recommendation: FOLD IN THIS PR** (5-line UI copy change adding a
  link to `/dashboard/settings/privacy` + retention notice). Fires only
  for case (a) departed members who are connected at removal moment;
  case (b) accountless and case (a)-with-stale-session miss this surface.
- **Removal email** via Resend (Art. 13(2)(b) at-removal notification
  for users not currently connected) — DEFER as separate follow-up
  issue: requires Resend template + transactional plumbing not in scope.

**4. Manifest schema bump to 1.1.0 (P1 per spec-flow P1-3).**

- `MANIFEST_SCHEMA_VERSION = "1.0.0"` in `dsar-export.ts` has no field
  describing redaction events, removal-event ledger, or historical-
  workspace UNION. User opens `workspace_member_removals.json` with no
  context. Art. 15 "transparent information" duty.
- **Recommendation: FOLD IN THIS PR.** Bump to `1.1.0`; add
  `redactions: [{path, reason, count}]` (gated on Open Decision 1
  outcome) + `historical_workspaces: [workspace_id...]` to
  `ManifestRoot`. ~30 lines.

**5. Accountless ex-member public surface (P1 per spec-flow P1-5) →
PR #4289.**

- No `/legal/*` public route exists today (verified by spec-flow
  via repo grep). Accountless ex-members cannot discover
  `legal@jikigai.com` without a published surface.
- **Recommendation:** add explicit requirement to PR #4289 body —
  `legal-document-generator` agent must scaffold `/legal/data-rights`
  page with mailto + Art. 12 timeline alongside the existing privacy-
  policy edits. THIS PR's AC18 cross-link gate verifies the public
  surface ships.

**6. Snapshotted remover identity in bundle (P2 per spec-flow P2-6).**

- `workspace_member_removals.removed_by_user_id` is a live FK. When
  surfaced in bundle, this discloses another user's CURRENT identity
  (which may differ from time-of-removal). Within-workspace expected,
  but lower-coupling-with-time is better.
- **Recommendation:** snapshot `removed_by_email_at_time text NULL`
  alongside the FK (capture from `users.email` at INSERT inside the
  RPC). Bundle exports the snapshot, not the live join. Plan-time
  schema clarification; ADR-039 documents.

**3. Pre-existing #4299 fold-in vs. separate (HIGH).**

- New `workspace_member_removals.removed_user_id` is `ON DELETE
  RESTRICT` — same blocking pattern as #4299. Adding to the cascade
  order in `account-delete.ts` is one line.
- **Recommendation:** fold the cascade-order update for the new table
  into THIS PR; keep #4299's full resolution (sister tables' RESTRICT
  fix) as separate scope.

## Files to Edit

- `apps/web-platform/server/dsar-export.ts` — modify `workspaceIds`
  derivation at L609-630 (Approach A); modify attestation export at
  L678-697 (inviter-side symmetry); add `workspace_member_removals`
  block (Approach B); update the stale "avoids the gap" comment at
  L672-677.
- `apps/web-platform/server/dsar-export-allowlist.ts` — add
  `workspace_member_removals` entry (Approach B); IF author-only
  redaction stays in scope per Open Decision 1, modify `messages`
  entry to add a redaction predicate hook.
- `apps/web-platform/server/account-delete.ts` — extend cascade order
  to call `anonymise_workspace_member_removals` BEFORE
  `auth.admin.deleteUser()`. (Verify path via
  `git ls-files | grep account-delete` at /work Phase 0.)
- `apps/web-platform/components/dashboard/membership-revoked-screen.tsx` —
  add DSAR link + retention notice copy per Open Decision 2
  (spec-flow P0-1a). ~5-line diff.
- `apps/web-platform/server/dsar-export.ts` `MANIFEST_SCHEMA_VERSION` —
  bump `1.0.0` → `1.1.0`; extend `ManifestRoot` type with
  `historical_workspaces` (always) and `redactions` (gated on Open
  Decision 1). Per spec-flow P1-3.
- `apps/web-platform/server/workspace-membership.ts:147-207` — pass
  `removed_by_email_at_time` snapshot to the modified RPC per Open
  Decision 6 (spec-flow P2-6). Snapshot captured server-side from
  `users.email` join inside the SECURITY DEFINER RPC, not the TS wrapper.
- `apps/web-platform/test/dsar-allowlist-completeness.test.ts` — auto-
  extends from the allowlist source-of-truth; no edit needed unless
  the migration discovery set diverges.
- `knowledge-base/legal/article-30-register.md` — add PA-19 row.
- `knowledge-base/legal/compliance-posture.md` — update DSAR coverage
  Active Item row.

## Files to Create

- `apps/web-platform/supabase/migrations/062_workspace_member_removals.sql`
  + `.down.sql` — new table + WORM trigger + anonymise RPC + retention
  sweep + RLS (select-only for workspace co-members, mirroring 058
  L64-66); modify `remove_workspace_member` RPC at the end of the file
  (CREATE OR REPLACE with the new INSERT before DELETE).
- `apps/web-platform/test/dsar-departed-member.integration.test.ts` —
  golden-fixture test per TR3.
- `knowledge-base/legal/runbooks/dsar-accountless-ex-member.md` — Art.
  12(6) ID-verification template + 30-day SLA per legal-compliance-auditor.
- `knowledge-base/engineering/architecture/decisions/ADR-039-departed-member-removal-ledger.md`
  — per TR1. Created by `/soleur:architecture create` invocation.

## Open Code-Review Overlap

None. Verified via:

```bash
gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/open-review-issues.json
for path in apps/web-platform/server/dsar-export.ts apps/web-platform/server/dsar-export-allowlist.ts \
  apps/web-platform/supabase/migrations/058_workspace_member_attestations.sql \
  apps/web-platform/supabase/migrations/041_dsar_export_jobs.sql; do
  jq -r --arg path "$path" '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"' \
    /tmp/open-review-issues.json
done
```

Zero matches against 75 open code-review issues.

## Acceptance Criteria

### Pre-merge (PR)

- **AC1:** Migration `062_workspace_member_removals.sql` creates the
  table with WORM trigger matching `workspace_member_attestations_no_mutate`
  shape (DELETE always rejected; UPDATE only allowed for `removed_user_id
  IS NULL` transitions; lineage columns `id`, `workspace_id`,
  `removed_at` immutable). Down-migration drops cleanly.
- **AC2:** `remove_workspace_member` RPC INSERTs a removal row BEFORE
  the DELETE inside the same transaction. Transaction-rollback
  integration test asserts: aborting the transaction leaves neither row
  written nor delete applied.
- **AC3:** `dsar-export.ts:609-630` `workspaceIds` derivation UNIONs
  current memberships with historical attestations. Verified via
  golden-fixture integration test: synthesize two users in a workspace,
  remove one, run DSAR export for the removed user, assert the export
  contains workspace metadata for the former workspace.
- **AC4:** `dsar-export.ts:678-697` attestation export uses
  `.or("invitee_user_id.eq." + X + ",inviter_user_id.eq." + X)` (or
  the equivalent supabase-js syntax — verify against the installed
  package at /work Phase 0 per Sharp Edges #PostgREST-syntax).
- **AC5:** `dsar-export-allowlist.ts` contains a
  `workspace_member_removals` entry with `ownerField: "removed_user_id"`,
  `article: "15"`. `dsar-allowlist-completeness.test.ts` passes.
- **AC6:** Integration test `dsar-departed-member.integration.test.ts`
  passes against dev-Supabase: (a) departed user's bundle contains
  their messages and workspace metadata for the workspace they left,
  (b) bundle contains a `workspace_member_removals` row for the removal
  event, (c) bundle attests both invitee-side AND inviter-side
  attestation rows where the user appears.
- **AC7:** ADR-039 file exists at
  `knowledge-base/engineering/architecture/decisions/`. ADR records
  the WORM-ledger invariant + the 36-mo retention rationale + the
  cascade-order requirement.
- **AC8:** PA-19 row exists in `knowledge-base/legal/article-30-register.md`
  with: controller, Art. 6(1)(c) lawful basis, 36-mo retention,
  cross-doc references to PR #4289.
- **AC9:** `knowledge-base/legal/compliance-posture.md` DSAR Active
  Item row references this PR.
- **AC10:** `knowledge-base/legal/runbooks/dsar-accountless-ex-member.md`
  exists with: Art. 12(6) ID-verification template, 30-day SLA, audit-row
  log template, escalation-to-CLO clause.
- **AC11:** `cq-pg-security-definer-search-path-pin-pg-temp` — both the
  modified `remove_workspace_member` and the new
  `anonymise_workspace_member_removals` RPCs include
  `SECURITY DEFINER + SET search_path = public, pg_temp`. Verified by
  grep.
- **AC12:** `cq-WORM-bypass`: new table has NO owner-insert RLS policy
  (REVOKE INSERT FROM `PUBLIC, anon, authenticated`); writes flow
  ONLY through `remove_workspace_member` RPC. Verified by
  `grep "INSERT.*workspace_member_removals" apps/web-platform/server/`
  returning only the RPC call site.
- **AC13:** Migration applies cleanly to dev-Supabase via
  `web-platform-release.yml#migrate`. Tenant-isolation integration
  tests pass post-apply.
- **AC14:** `user-impact-reviewer` agent passes at PR review (failure
  modes enumerated against this diff).
- **AC15:** `/soleur:gdpr-gate` skill audit passes the diff (regulated-
  data surface).
- **AC16:** PR body uses `Ref #4230` (not `Closes #4230`) until the
  follow-through #4284 confirms flag-flip prerequisites met. AC closes
  via post-merge step.
- **AC17:** PR body cross-links #4289 with comment "departed-member
  legal text in scaffolding PR; code in #4294". PR #4289 body cross-
  links back.
- **AC18:** This PR is marked `ready` ONLY AFTER PR #4289 enters
  ready-for-review (legal-compliance-auditor CRITICAL #3). PR #4289
  body must include a requirement bullet for a `/legal/data-rights`
  public surface (spec-flow P1-5).
- **AC18a:** `membership-revoked-screen.tsx` displays a DSAR link to
  `/dashboard/settings/privacy` + 1-line retention notice (spec-flow
  P0-1a). Verified by component test.
- **AC18b:** `MANIFEST_SCHEMA_VERSION = "1.1.0"`; ManifestRoot
  type includes `historical_workspaces: string[]` AND (if Open
  Decision 1 keeps redaction) `redactions: {path, reason, count}[]`.
  Verified by grep + type test (spec-flow P1-3).
- **AC18c:** `workspace_member_removals.removed_by_email_at_time text NULL`
  column snapshots remover's email at INSERT time inside the RPC.
  Bundle export uses the snapshot, not a live join (spec-flow P2-6).
- **AC18d:** Integration test asserts a user removed inside the test
  transaction can still trigger `dsar-reauth` and receive an export
  (spec-flow P1-4 verification).

### Post-merge (operator + automated)

- **AC19 (automated, post-merge):** `web-platform-release.yml#migrate`
  applies `062_workspace_member_removals.sql` to prd-Supabase.
  Verification: `mcp__plugin_supabase_supabase__*` query for table
  existence + RLS-policy count. Captured in ship-skill post-merge
  block.
- **AC20 (automated, post-merge):** `gh issue close 4230` triggered
  after AC19 confirms.
- **AC21 (post-merge follow-through):** #4284 (flag-flip) re-evaluated
  once AC19+AC20 + PR #4289 merge are all green.

## Implementation Phases

Phase 0 — Preconditions (CLI verification + ADR scaffolding).

- **0.1** Read 058 lines 41-141 verbatim; confirm WORM-trigger function
  shape matches what I'll mirror.
- **0.2** Read `account-delete.ts` cascade order; locate the insertion
  point for `anonymise_workspace_member_removals` before
  `auth.admin.deleteUser()`.
- **0.3** Run `npm view @supabase/supabase-js` for the installed
  version; confirm `.or()` PostgREST syntax for AC4. Cite installed
  version in plan-review comment.
- **0.4** Invoke `/soleur:architecture create 'DSAR departed-member
  coverage via removal-event ledger'`. Confirm ADR-039 path. (Phase
  0.4 outputs into AC7 satisfaction.)
- **0.5** Decision gate for Open Decision #1 (author-only redaction
  split). If split: delete FR5/AC4-redaction, file follow-up issue.
  If keep: continue with redaction predicate in scope.

Phase 1 — Migration 062.

- **1.1** `062_workspace_member_removals.sql`: table DDL + WORM
  trigger + REVOKE matrix + SELECT-for-members RLS.
- **1.2** `anonymise_workspace_member_removals(p_user_id uuid)`
  SECURITY DEFINER RPC mirroring 058:342-362.
- **1.3** `CREATE OR REPLACE FUNCTION public.remove_workspace_member`:
  add the INSERT before the DELETE inside the SECURITY DEFINER
  function body. Preserve all existing AC-FLOW4 guards.
- **1.4** pg_cron retention sweep at 36-mo, GUC-bypass shape per 041
  L383-395.
- **1.5** `.down.sql`: DROP triggers, DROP function, DROP table,
  DROP retention sweep, REVERT `remove_workspace_member` to pre-change
  body.

Phase 2 — DSAR export pipeline (Approach A + symmetric attestation fix).

- **2.1** `dsar-export.ts` `workspaceIds` derivation at L609-630:
  add the historical-attestations query; merge via Set; preserve
  CrossTenantViolation assertion.
- **2.2** `dsar-export.ts` attestation export at L678-697: replace
  `.eq("invitee_user_id", X)` with `.or(...)`. Update L672-677
  comment to remove stale "avoids the gap" claim.
- **2.3** Add `workspace_member_removals` export block (analog to
  attestations at L672-697) keyed on `.eq("removed_user_id", X)`.
- **2.4** `dsar-export-allowlist.ts`: add `workspace_member_removals`
  entry. Update lint-test assertion if needed.

Phase 3 — IF Open Decision 1 = "keep redaction in scope".

- **3.1** Design + implement author-only redaction predicate in
  allowlist. Land sibling privacy-policy text in same PR (or block
  on PR #4289 merging first).
- **3.2** Integration test: mixed-ownership conversation export
  asserts redacted content.

Phase 4 — Integration test.

- **4.1** `dsar-departed-member.integration.test.ts`: synthesize 2
  users + workspace, invite-accept, exchange messages, remove member,
  run export, assert AC6 (a)/(b)/(c).
- **4.2** Add transaction-rollback test for AC2.

Phase 4.5 — UI + manifest folds-in (per spec-flow).

- **4.5.1** `membership-revoked-screen.tsx`: add DSAR link + retention
  notice copy (~5 lines). Update existing component test.
- **4.5.2** `dsar-export.ts`: bump `MANIFEST_SCHEMA_VERSION` to
  `"1.1.0"`; extend `ManifestRoot` type; populate
  `historical_workspaces` from the new UNION-derived workspaceIds
  set computed at Phase 2.1.
- **4.5.3** RPC modification at Phase 1.3 also captures
  `removed_by_email_at_time` snapshot via inline `SELECT email FROM
  public.users WHERE id = v_caller_user_id INTO v_email_snapshot;`.

Phase 5 — Legal docs + runbook (THIS PR slice).

- **5.1** Insert PA-19 row in `article-30-register.md`.
- **5.2** Update `compliance-posture.md` DSAR Active Item row.
- **5.3** Create `knowledge-base/legal/runbooks/dsar-accountless-ex-member.md`.

Phase 6 — Account-delete cascade + PR cross-link.

- **6.1** Extend `account-delete.ts` to call
  `anonymise_workspace_member_removals(p_user_id)` BEFORE
  `auth.admin.deleteUser()`.
- **6.2** PR-body authoring with `Ref #4230`, cross-link #4289,
  legal-scaffolding handshake comment.

Phase 7 — Pre-merge gates.

- **7.1** `/soleur:gdpr-gate` invocation on the final diff.
- **7.2** `user-impact-reviewer` agent at PR review.
- **7.3** PR #4289 ready-for-review confirmation before flipping this
  PR to `ready`.
- **7.4** `/soleur:preflight` Check 6 (USER_BRAND_CRITICAL gate).
- **7.5** Merge sequencing: wait for #4289 merge OR coordinate paired
  merge if reviewers prefer.

## Observability

Per `hr-observability-as-plan-quality-gate`, code-class file edits
(`apps/web-platform/server/dsar-export.ts`,
`apps/web-platform/supabase/migrations/062_*.sql`) require the
5-field schema:

```yaml
liveness_signal:
  what: "Successful DSAR export completion for a previously-removed workspace member returns a bundle containing workspace_member_removals row + workspace metadata for the workspace they left"
  cadence: per-DSAR-request (event-driven; no cron probe)
  alert_target: Sentry breadcrumb on dsar-export.ts:1314 (sendDsarExportReadyEmail) — existing tag `dsar_export.completed=true`; new tag `dsar_export.departed_workspace_count >= 0` added in Phase 2.
  configured_in: apps/web-platform/server/dsar-export.ts L1310-1320 (alongside existing send-email instrumentation)

error_reporting:
  destination: Sentry via existing `Sentry.captureException` at dsar-export.ts L1330-1340 (failed export path); new `extra.departed_workspace_count` tag carries departed-coverage signal.
  fail_loud: yes — DSAR failure mirrors to Sentry P0; existing alertable rule `dsar_export.failed`.

failure_modes:
  - mode: "workspace_member_removals INSERT fails inside remove_workspace_member RPC (constraint violation, FK miss)"
    detection: "RPC raises; TS wrapper `removeWorkspaceMember` reportSilentFallback catches; Sentry mirror under feature: workspace-membership, op: remove-rpc-failed"
    alert_route: Sentry P1 (existing Soleur alert routing for `workspace-membership.*` ops)
  - mode: "historical-attestation UNION query returns malformed workspace_id (cross-tenant violation)"
    detection: "CrossTenantViolation thrown at dsar-export.ts existing L648-657; mirrorCrossTenantViolation Sentry hook fires"
    alert_route: Sentry P0 (existing CrossTenantViolation routing — single-user-incident threshold)
  - mode: "retention sweep DELETEs row outside intended 36-mo window"
    detection: "pg_cron sweep emits row count; daily Sentry breadcrumb tag `workspace_member_removals.swept_count` compared against baseline"
    alert_route: Sentry P2 (anomaly detection — non-blocking, weekly review)

logs:
  where: existing dsar-export structured logger; new tags `dsar_export.departed_workspace_count`, `dsar_export.workspace_member_removals_count`
  retention: 30d (per existing logger config — no change)

discoverability_test:
  command: "psql $DEV_SUPABASE_URL -c 'SELECT COUNT(*) FROM public.workspace_member_removals; SELECT proname FROM pg_proc WHERE proname = ''anonymise_workspace_member_removals'';'"
  expected_output: "row count >= 0 (table exists); proname column returns 'anonymise_workspace_member_removals' (RPC exists)"
```

NO `ssh` in `discoverability_test.command` — query is `psql` against the
dev-Supabase URL (read-only).

## Test Strategy

- **Unit:** new table's WORM trigger via SQL tests modeled on `058`'s
  trigger tests (look for `test/server/scope-grants/lifecycle.test.ts`
  pattern; verify path at /work Phase 0).
- **Integration:** `dsar-departed-member.integration.test.ts` — full
  end-to-end against dev-Supabase (synthesized fixtures per
  `cq-test-fixtures-synthesized-only`).
- **Transaction-rollback test (AC2):** invoke `remove_workspace_member`
  inside a `BEGIN; ... ROLLBACK;` block; assert neither row written nor
  delete applied.
- **Lint:** `dsar-allowlist-completeness.test.ts` validates new
  allowlist entry.
- **Schema-drift guard:** existing migration-applied CI ensures
  062 lands cleanly post-merge.
- Test runner: `vitest` (confirmed via `package.json scripts.test` per
  Sharp Edges #bunfig-bun-test-discovery).

## Risks & Assumptions

- **R1:** Modifying `remove_workspace_member` is a behavior change to a
  recently shipped RPC (058). Mitigation: keep DELETE semantics
  identical; only ADD the INSERT inside the same SECURITY DEFINER
  function body. Roll back via down-migration `CREATE OR REPLACE`
  reverting to pre-change body.
- **R2:** If Open Decision 1 lands "keep redaction in scope", the
  predicate change affects ALL DSARs (active users too). Pre-existing
  Art. 15 export semantics for solo-workspace users (vast majority
  today) is unaffected — solo conversations have no other authors.
  Team-workspace users see a tighter export. Risk: Art. 13 disclosure
  drift if PR #4289 lands after this PR. Mitigation: AC18 gate.
- **R3:** `workspace_member_removals.removed_user_id ON DELETE RESTRICT`
  intersects with pre-existing #4299. Mitigation: anonymise_workspace_
  member_removals RPC is called BEFORE `auth.admin.deleteUser()` in
  account-delete.ts cascade (Phase 6.1). #4299's full resolution
  (sister tables) remains separate scope.
- **R4:** `legal-doc-cross-document-gate.yml` fires on
  `knowledge-base/legal/**`. Failure to update `compliance-posture.md`
  alongside `article-30-register.md` blocks merge. Mitigation: AC9 +
  AC8 paired.
- **A1:** Operator's prospect (10-person team) does not require
  accountless ex-member self-serve at gate. If false, the runbook
  (AC10) is insufficient and `legal@jikigai.com` volume forces a
  public-form brainstorm ahead of plan (per #4302 trigger).
- **A2:** Existing 24-mo `dsar_export_audit_pii` retention envelope is
  the precedent for membership-PII; 36-mo for `workspace_member_removals`
  is a deliberate deviation justified by Art. 82 limitation horizon.
  ADR-039 documents the rationale.
- **A3:** `vitest` is the test runner. Confirmed via package.json scripts
  precedent; no `bun test`.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail
  `deepen-plan` Phase 4.6 and `/soleur:preflight` Check 6. This plan's
  section is populated above — do NOT replace with TBD during /work.
- WORM-table convention: do NOT add an owner-insert RLS policy on
  `workspace_member_removals`. Writes flow ONLY through
  `remove_workspace_member` RPC. Verified by AC12.
- Cascade-order load-bearing: `anonymise_workspace_member_removals`
  MUST run BEFORE `auth.admin.deleteUser()` in `account-delete.ts`,
  same pattern as `anonymise_workspace_member_attestations` (058
  L342). Failure to thread this leaves Art. 17 erasure broken for
  any user who was ever in a workspace.
- supabase-js `.or()` syntax: verify against installed `@supabase/
  supabase-js` version at Phase 0.3 — PostgREST embedded-resource
  syntax is more limited than expected (per Sharp Edges in plan
  skill).
- Migration discipline (`#4241` learning): do NOT apply
  `062_workspace_member_removals.sql` to dev-Supabase ahead of main.
  Let `web-platform-release.yml#migrate` apply on merge.
- PA numbering: PA-19 is next available (verified via grep of
  `^## Processing Activity` in article-30-register.md). PA-16 / PA-17
  / PA-18 already taken — non-sequential numbering is acceptable per
  prior register precedent (PA-16/PA-17 ordering is reversed in source).
- PR cross-link sequencing: this PR's `ready` flag depends on PR #4289
  entering ready-for-review. Do NOT mark ready before that gate.

## Out of Scope (deferred — tracking issues exist)

- **#4299** — Pre-existing `ON DELETE RESTRICT` blocking Art. 17 cascade
  on sister tables (`workspace_member_attestations`,
  `workspace_members`). This PR's cascade-order extension for
  `workspace_member_removals` is a defense-in-depth slice; full
  resolution stays at #4299.
- **#4301** — `runtime_cost_state` RLS-coverage audit (separate concern).
- **#4302** — Public/email-proof DSAR intake form re-evaluation tracker.
- **Roadmap.md team-workspace-pivot update** — small CPO action,
  separately tracked.
- **Leave-email pipeline** — discoverability gap per §Open Decisions 2;
  defer to first-accountless-DSAR signal.
- **Author-only message redaction** — IF Open Decision 1 lands "split",
  filed as new follow-up issue gated on PR #4289 merging first.

## Cited References

- `058_workspace_member_attestations.sql:72-141` — WORM trigger
  function + DROP-IF-EXISTS triggers + REVOKE matrix (mirror target).
- `058_workspace_member_attestations.sql:267-326` — `remove_workspace_member`
  RPC (modification target).
- `058_workspace_member_attestations.sql:342-401` — anonymise RPCs
  (mirror target for new `anonymise_workspace_member_removals`).
- `053_organizations_and_workspace_members.sql:51,82-83` — ON DELETE
  RESTRICT pattern + composite PK.
- `041_dsar_export_jobs.sql:383-395` — pg_cron retention sweep shape
  (mirror target).
- `dsar-export.ts:609-630, 672-697` — workspaceIds + attestation
  export sites (modification targets).
- `dsar-export-allowlist.ts:48-182` — DSAR_TABLE_ALLOWLIST structure
  + existing workspace-member entries.
- `workspace-membership.ts:147-207` — `removeWorkspaceMember` TS
  wrapper (call-site for new RPC behavior).
- `knowledge-base/legal/article-30-register.md` PA-16/17/18 — number
  precedent for PA-19.
- `.github/workflows/legal-doc-cross-document-gate.yml` — cross-doc
  gate trigger surface.
- Learnings:
  - `2026-05-21-worm-ledger-rls-owner-insert-policy-is-an-rpc-bypass.md`
    (WORM-bypass convention)
  - `2026-05-21-dev-supabase-drift-from-unmerged-feature-branch-migrations.md`
    (#4241 root cause; migration discipline)
  - `2026-05-15-worm-trigger-blocks-pg-cron-retention-sweep.md` (GUC
    bypass for retention sweeps)
  - `2026-05-12-region-replacement-acs-must-enumerate-trailing-paragraphs.md`
    (legal doc edit precision)

## Resume Prompt

```text
/soleur:work knowledge-base/project/plans/2026-05-22-feat-dsar-departed-member-coverage-plan.md

Branch: feat-dsar-workspace-member-4230. Worktree: .worktrees/feat-dsar-workspace-member-4230/.
Issue: #4230. PR: #4294 (draft). Cross-PR: #4289 (legal scaffolding, must
ready-for-review before this PR flips ready).

Plan reviewed; ADR pending Phase 0.4 invocation. Decision needed at
Phase 0.5 on author-only redaction scope-split (legal-compliance-auditor
CRITICAL — see plan §Open Decisions 1).
```
