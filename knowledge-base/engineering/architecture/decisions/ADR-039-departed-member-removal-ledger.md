---
title: workspace_member_removals WORM ledger for DSAR departed-member coverage
status: accepted
date: 2026-05-22
related: [4230, 4229, 4225, 4319, 4299]
related_adrs: [ADR-038, ADR-026, ADR-023]
related_plans:
  - knowledge-base/project/plans/2026-05-22-feat-dsar-departed-member-coverage-plan.md
brand_survival_threshold: single-user incident
---

# ADR-039: workspace_member_removals WORM ledger for DSAR departed-member coverage

## Status

**Accepted** (2026-05-22, PR #4294).

Lands as part of migration 062 in the same PR per `requires_adr: true` in the plan frontmatter.

## Context

ADR-038 (#4225) shipped `organizations` + `workspace_members` and decoupled `workspaces.id` from `owner_user_id`. The umbrella issue #4229 explicitly deferred DSAR departed-member coverage to a follow-up: once `remove_workspace_member` DELETEs a `workspace_members` row, the ex-member's identity-to-workspace linkage is gone and the DSAR export pipeline at `apps/web-platform/server/dsar-export.ts:609-630` (which derives `workspaceIds` from current memberships) silently omits any workspace the user has left.

GDPR Art. 15 (right of access) is a single-user-incident-threshold concern: one ex-member filing a request and receiving a bundle that omits the workspace they care about most (post-employment, post-team-split, post-fallout context) is brand-survival-relevant. The follow-up #4230 was triaged P2-medium pre-flag-flip but blocking for `FLAG_TEAM_WORKSPACE_INVITE=1` rollout (#4284).

Approach A (UNION current memberships with historical `workspace_member_attestations` to recover `workspaceIds`) is zero-schema and ~1-2 days. It exploits the fact that attestation rows survive removal (they're WORM per migration 058) — a departed member still has an attestation row recording the join-time event.

Approach A is necessary but not sufficient:

1. **Removal lineage is unrecoverable from attestations alone.** Attestations record the join event; nothing in the current schema records "Jean removed Harry on 2026-05-21." GDPR Art. 15(1)(g) requires controllers to provide "the source of the personal data" and Art. 30(1)(g) requires processing-activity records to cover the lifecycle. Attestation-only DSAR coverage exports who joined but not who left.
2. **Audit lineage for litigation discovery.** A departed member alleging wrongful removal needs the removal event in their bundle to evidence it. Without a ledger, the only record is the absence of a `workspace_members` row — non-evidentiary.
3. **Operator dogfood signal.** Jikigai itself runs as a two-member workspace; the first time the operator removes a contractor, the absence of an audit trail is a self-inflicted compliance gap.

A reflexive shape — "just keep the deleted `workspace_members` rows as soft-delete via a `removed_at` column" — is naive on two axes:

1. **WORM substrate already exists.** Migration 058's `workspace_member_attestations` is the canonical WORM-ledger pattern in this codebase. The trigger function (058:72-141), the REVOKE matrix (058:59-61), the anonymise RPC (058:342-362), and the AC-FLOW4 guards (058:267-326) are all reusable. Adding a soft-delete column to `workspace_members` would fork the audit substrate.
2. **WORM trigger blocks pg_cron retention.** Per learning `2026-05-15-worm-trigger-blocks-pg-cron-retention-sweep.md`, a naive append-only trigger rejects the time-based DELETE needed for retention. The GUC-bypass-with-role-gate pattern (Phase 1.4) is the precedent.

Brand-survival threshold: **single-user incident.** If the new ledger's RLS predicate over-returns TRUE, one row of "Jean removed Harry on $date" is visible to a co-member who has no need-to-know — that is personal-data leakage. The user-impact-reviewer agent at PR review is the load-bearing gate.

## Decision

**Introduce a `workspace_member_removals` WORM ledger mirroring `workspace_member_attestations`'s structural shape verbatim. Migration 062 (a) creates the table, WORM trigger, RLS policy, and indexes; (b) adds an `anonymise_workspace_member_removals(p_user_id uuid)` SECURITY DEFINER RPC for Art. 17 cascade; (c) `CREATE OR REPLACE`s `remove_workspace_member` to INSERT a removal row BEFORE the DELETE inside the same SECURITY DEFINER body (atomic; FK violation rolls back DELETE); (d) schedules a pg_cron retention sweep at 36 months with a GUC + role-gate WORM bypass. The DSAR export pipeline gains a UNION of `workspace_member_attestations` for `workspaceIds` derivation (Approach A) plus an export block for `workspace_member_removals` (Approach B). The cascade-order extension in `account-delete.ts` calls `anonymise_workspace_member_removals` BEFORE `auth.admin.deleteUser()` to break the new ON DELETE RESTRICT FKs.**

### Schema (migration 062)

```text
workspace_member_removals
  id                 uuid         PRIMARY KEY DEFAULT gen_random_uuid()
  -- NULL-able + SET NULL on workspace delete — orphan-org carve-out;
  -- see §Invariants.1 for rationale. Pre-existing
  -- workspace_member_attestations.workspace_id (058:43) is RESTRICT
  -- and remains unchanged (sister-table tracked separately).
  workspace_id       uuid         NULL    REFERENCES workspaces(id) ON DELETE SET NULL
  -- PII columns — NULL after Art. 17 anonymise.
  removed_user_id    uuid         NULL    REFERENCES users(id)      ON DELETE RESTRICT
  removed_by_user_id uuid         NULL    REFERENCES users(id)      ON DELETE RESTRICT
  -- Audit lineage — id + removed_at strictly immutable.
  removed_at         timestamptz  NOT NULL DEFAULT now()

INDEX workspace_member_removals_workspace_idx
  ON (workspace_id, removed_at DESC)

POLICY removals_select_for_members
  FOR SELECT TO authenticated USING (is_workspace_member(workspace_id, auth.uid()))

REVOKE INSERT, UPDATE, DELETE FROM PUBLIC, anon, authenticated
```

### Invariants

1. **WORM (write-once, anonymise-only).** Structural-shape pattern derived from `workspace_member_attestations_no_mutate` (058:72-141), extended with a **workspace_id carve-out** added at review-time (PR #4294 code-simplicity-reviewer DISSENT on initial RESTRICT FK shape). DELETE is always rejected for non-retention rows (use anonymise RPC); UPDATE is allowed only for NULL transitions on `removed_user_id`, `removed_by_user_id`, **and `workspace_id`**; strict-immutable lineage columns are `id` and `removed_at` only. Pattern reference: structural-shape recognition over GUC + role gate per learning `2026-05-18-worm-trigger-bypass-role-check-fails-under-postgrest-routing.md`. **The workspace_id carve-out** (`ON DELETE SET NULL` + WORM trigger permits NOT NULL → NULL) lets `anonymise_organization_membership` (058:419-468) DELETE orphaned workspaces without being blocked by removal-event rows pointing at them. After the workspace is gone there are zero co-members left to read the row via RLS, so workspace_id has no remaining semantic value — surviving identifiers (id, removed_user_id, removed_by_user_id, removed_at) still serve DSAR Art. 15 export under the requester's userId scope. Pre-existing parallel: `workspace_member_attestations.workspace_id` (058:43) keeps its `ON DELETE RESTRICT` FK shape; that's the sister-table defect tracked as a separate pre-existing-unrelated finding against `main`.
2. **All inserts route through `remove_workspace_member` RPC.** Per `cq-WORM-bypass` and the WORM-ledger contract: no TS-level inserts. The RPC's INSERT happens inside the same SECURITY DEFINER function body as the DELETE — atomic; if the INSERT raises (FK violation), the DELETE rolls back (AC2 verifies).
3. **Cascade-order load-bearing.** `anonymise_workspace_member_removals(p_user_id)` runs in `account-delete.ts` AFTER `anonymise_workspace_member_attestations` and BEFORE `auth.admin.deleteUser()`. Failure to thread this leaves Art. 17 erasure broken for any user who has ever been removed from a workspace (the ON DELETE RESTRICT FK on `removed_user_id` blocks the auth-delete cascade).
4. **RLS deviation from `workspace_member_attestations`.** The SELECT policy uses `is_workspace_member(workspace_id, auth.uid())` — meaning a departed member CANNOT read their own removal row via the policy. They access it through the DSAR export pipeline (service-role read). This is intentional: the removal row is co-member audit metadata, not the departed user's own profile data. The DSAR export is the gated surface for the departed user to see their row; co-members see all removal events for workspaces they currently belong to.

### Retention (36 months, deviating from 24-mo PA-PII envelope)

`workspace_member_removals` retains for **36 months** rather than the 24-month PA-PII envelope tracked at `compliance-posture.md` for `dsar_export_audit_pii`. Rationale: GDPR Art. 82(2) ("any person who has suffered material or non-material damage as a result of an infringement of this Regulation shall have the right to receive compensation from the controller") and Recital 146 do not stipulate a limitation horizon at the EU level; member-state implementations vary from 3 to 10 years. French Code Civil Art. 2224 sets the general civil-action limitation at 5 years; German BGB §195 sets it at 3 years; UK Limitation Act 1980 §11A sets data-protection at 6 years. **3 years is the floor across the operator's likely jurisdictions (FR/DE/UK/US).**

A removal event 30 months post-fact is still actionable; a removal event 36 months post-fact is past the shortest-jurisdiction floor. Retention beyond 36 months has diminishing audit value AND increasing storage-PII surface — choose 36 to balance.

After 36 months, the pg_cron sweep runs a service-role-gated GUC-bypass DELETE. The WORM trigger checks `current_setting('app.workspace_member_removal_anonymise_in_progress', true) = 'true' AND current_user = 'service_role'` for bypass per the plan's Phase 1.4 spec. The bypass is narrow: only the sweep RPC sets the GUC, and only `service_role` runs pg_cron.

### Cascade-order extension (Phase 4.4)

```text
account-delete.ts step ordering (post-#4230):
  3.90 anonymise_workspace_member_attestations  (existing, 058 cascade)
  3.905 anonymise_workspace_member_removals     (NEW, 062 cascade)
  3.91 anonymise_workspace_members              (existing)
  3.92 anonymise_organization_membership        (existing)
  4.   auth.admin.deleteUser()                  (existing, FK-cascade trigger)
```

The new step runs AFTER attestations (062's removed_user_id and removed_by_user_id FK columns may reference users who appear in attestation rows; ordering preserves the existing attestation-first invariant) and BEFORE workspace_members (membership deletion is unrelated to the new table's FKs but matches the 058 pattern).

### DSAR export pipeline (Phase 2)

Two changes to `apps/web-platform/server/dsar-export.ts`:

1. **`workspaceIds` UNION (L609-630, Approach A).** Add a `service.from("workspace_member_attestations").select("workspace_id").eq("invitee_user_id", expectedUserId)` query; merge into `workspaceIds` via `Set` union before the L639 length check. Preserves the `CrossTenantViolation` assertion.
2. **Symmetric attestation export + new removals block (L678-697 + new block, Approach A+B).** Replace `.eq("invitee_user_id", X)` with `.or("invitee_user_id.eq." + X + ",inviter_user_id.eq." + X)` to recover INVITER-side attestation rows for ex-members. Update `assertReadScope` at L689-691 to two-arm validator (Kieran P1-1). Add an export block for `workspace_member_removals` keyed on `.eq("removed_user_id", expectedUserId)`.

### Allowlist entry (Phase 2.4)

`apps/web-platform/server/dsar-export-allowlist.ts` gains `workspace_member_removals: { ownerField: "removed_user_id", article: "15" }`. The completeness lint at `dsar-allowlist-completeness.test.ts` auto-extends from the allowlist source-of-truth.

## Consequences

### Positive

- DSAR Art. 15 coverage closes for the first non-jikigai workspace; `FLAG_TEAM_WORKSPACE_INVITE=1` rollout (#4284) is unblocked on this axis (other gates: PR #4289 legal scaffolding ready; #4299 sister-table ON DELETE RESTRICT resolution).
- Removal-event audit trail satisfies Art. 30(1)(g) (PA-19) and creates discovery-evidentiary value for any wrongful-removal allegation.
- Mirror-058 implementation amortises substrate cost: WORM trigger, REVOKE matrix, RLS predicate, and anonymise-RPC shapes all reuse existing patterns.

### Negative

- 36-month retention deviates from 24-month PA-PII envelope; the deviation is documented here but operator must remember the dual policy when answering "how long do we keep what."
- Cascade-order chain in `account-delete.ts` gains a fifth anonymise step (3.905); each new ON DELETE RESTRICT FK adds operational complexity. Mitigated by the fact that the 058 cascade is already canonical.
- `.or()` is first-of-kind in the repo (verified via grep at plan-write). The two-arm `assertReadScope` change is load-bearing — without it, the golden-fixture test fires `CrossTenantViolation` on inviter-side rows.

### Neutral

- The redaction predicate (Art. 15(4) rights-of-others scoping for message content where multiple authors appear) is OUT OF SCOPE here and split to #4319. That work coordinates with PR #4289's Art. 13(2)(b) disclosure addition.
- Inline copy fold for `membership-revoked-screen.tsx` discoverability is OUT OF SCOPE here per DHH simplicity (5-line UI change should not gate a Postgres migration).

## Alternatives considered

### Alt 1 — Approach A only (UNION attestations; no removal ledger)

**Rejected.** Captures join-event lineage but not removal-event lineage. Cannot satisfy Art. 30(1)(g) lifecycle coverage; cannot evidence wrongful-removal allegations. Operator explicitly chose to capture removal lineage in this PR per plan §"Approach A + B".

### Alt 2 — Soft-delete column on `workspace_members`

**Rejected.** Would fork the WORM substrate established by migration 058 (single canonical pattern → two canonical patterns). Soft-delete also breaks the `is_workspace_member()` helper's simplicity (membership becomes "row exists AND removed_at IS NULL") and forces audit-policy duplication. Cleaner to keep `workspace_members` as a live-membership table and route audit through a separate WORM ledger.

### Alt 3 — Move the INSERT to a TS-level wrapper in `apps/web-platform/server/`

**Rejected.** Violates `cq-WORM-bypass` (TS-level inserts route around the SECURITY DEFINER RPC; service-role bypass is a known attack surface). Also breaks atomicity: the INSERT and DELETE must roll back together on FK violation (AC2). The plan's choice to embed the INSERT inside the existing `remove_workspace_member` RPC body is the only shape that preserves both invariants.

### Alt 4 — 24-month retention (PA-PII envelope)

**Rejected.** Below the shortest-jurisdiction limitation floor (DE 3 years). Operator's exposure window for civil-action discovery would close before the limitation horizon — same defect class as deleting access logs before the breach-notification window expires.

## Compliance posture

- **GDPR Art. 5(2) accountability.** Removal events are retained 36 months for audit/litigation availability.
- **GDPR Art. 6(1)(c) lawful basis.** Processing is legal obligation: controllers must maintain records of processing activities affecting data subjects (Art. 30).
- **GDPR Art. 15 (right of access).** DSAR bundle includes `workspace_member_removals` rows where `removed_user_id` matches the requesting user.
- **GDPR Art. 17 (right to erasure).** `anonymise_workspace_member_removals(p_user_id)` NULLs `removed_user_id` and `removed_by_user_id` for matching rows in the account-delete cascade; lineage (id, workspace_id, removed_at) preserved.
- **GDPR Art. 25(1) data minimisation.** No snapshot columns (`removed_by_email_at_time` etc.); live FK is sufficient.
- **GDPR Art. 30(1) records of processing activities.** PA-19 row added to `knowledge-base/legal/article-30-register.md` in this PR.
- **GDPR Art. 82(2) compensation/limitation horizon.** 36-month retention rationale documented above.

## References

- `apps/web-platform/supabase/migrations/058_workspace_member_attestations.sql:41-141, 267-401` — canonical WORM-ledger + RPC pattern.
- `apps/web-platform/supabase/migrations/041_dsar_export_jobs.sql:383-395` — canonical pg_cron retention sweep shape.
- `apps/web-platform/server/dsar-export.ts:609-630, 672-697, 689-691` — export-pipeline modification sites.
- `apps/web-platform/server/account-delete.ts:368-412` — cascade-order insertion point.
- ADR-038 — team-workspace substrate this builds on.
- ADR-026 — gdpr-gate skill that audits this PR's diff.
- Learnings: `2026-05-21-worm-ledger-rls-owner-insert-policy-is-an-rpc-bypass.md`, `2026-05-15-worm-trigger-blocks-pg-cron-retention-sweep.md`, `2026-05-18-worm-trigger-bypass-role-check-fails-under-postgrest-routing.md`, `2026-05-21-postgrest-schema-cache-and-stale-plan-quoted-apply-state.md`.
- Plan: `knowledge-base/project/plans/2026-05-22-feat-dsar-departed-member-coverage-plan.md`.
- Issue #4230 (this work), umbrella #4229, parent ADR-038/PR #4225, follow-up #4319 (redaction split), related #4299 (sister-table ON DELETE RESTRICT).
