---
title: "feat: Shared workspace email-triage inbox (all Owners can read/act)"
type: feat
date: 2026-06-17
branch: feat-one-shot-fix-notification-button-404
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
supersedes: 2026-06-17-fix-statutory-notification-inbox-button-404-plan.md
status: awaiting-operator-signoff
---

# ✨ feat: Shared workspace email-triage inbox

## Overview

The operator email-triage inbox (`email_triage_items`) is single-user-grained.
Re-key it to **workspace grain** so every **Owner** of the owning workspace can
read and act on statutory items — while the notification recipient stays the
single configured owner (operator decision: *one address, shared reads*).

**Root cause of the reported 404 (confirmed against code + live prod config +
the bug screenshots):** Not a broken URL or a missing route. The deep link
`https://app.soleur.ai/dashboard/inbox/email/<id>` and its route
(`app/(dashboard)/dashboard/inbox/email/[emailId]/page.tsx`, on `main` since
#5125) are both correct. The 404 is `notFound()` at `page.tsx:65` because the
row lookup `.eq("user_id", user.id)` returns nothing:

- `EMAIL_TRIAGE_OWNER_USER_ID = 754ee124-…0380` resolves (via
  `getUserById(ownerId).email`, `notifications.ts:200`) to **`ops@jikigai.com`**
  — where the email was delivered.
- Every row is written with `user_id = ownerId` (`server/inngest/functions/email-on-received.ts:310,381`).
- The operator opens the dashboard as **`jean.deruelle@jikigai.com`**, a
  different `auth.uid()` → the `user_id`-scoped read finds no row → 404.

The two Sentry codes in the emails are unrelated red herrings: `WEB-PLATFORM-3K`
(AbortError lock-steal, `lib/supabase/tenant.ts`) and `WEB-PLATFORM-3M`
(ambiguous-founder, `app/api/webhooks/github/route.ts`) — neither is in the
email-triage path. No change to either.

## Precondition status — MET (operator-confirmed, Phase 0 re-verifies)

**Team workspaces are enabled in prod via Flagsmith, and `jean.deruelle@` is
already a co-Owner of the relevant workspace** (operator-confirmed 2026-06-17).
So broadening reads to "all workspace Owners" **does** resolve the 404: once this
feature ships and a row carries `workspace_id`, `jean.deruelle@`'s Owner
membership satisfies the new SELECT predicate.

> Correction record: an earlier draft of this plan claimed "prod has solo
> workspaces only / sharing OFF," sourced from the **header comment of migration
> `068_attachments_workspace_shared.sql`** (a ~2026-05-25 point-in-time snapshot).
> That is NOT a source of truth for live runtime state — the flag lives in
> Flagsmith and membership lives in prod Supabase. Do not assert live
> flag/membership state from a migration-header snapshot.

**Phase 0 VERIFIED (prod, read-only, 2026-06-17 via service-role probe):**
- `EMAIL_TRIAGE_OWNER_USER_ID = 754ee124…0380` → `ops@jikigai.com`; all
  `email_triage_items` rows carry `user_id = 754ee124`.
- Workspace `754ee124` membership: `ops@` (**owner**), `jean.deruelle@`
  (`52af49c2…`, **owner**), `harry@soleur.ai` (member), `harry@jikigai.com`
  (member). `jean.deruelle@` `role='owner'` of `754ee124` = **TRUE**.
- **`workspace_id` of the owning workspace == the owner uid** (`754ee124`)
  — residual-personal-workspace shape (mig 109). So the AC1 backfill
  `workspace_id = user_id` stamps the correct workspace; NO design change, and
  the write path's `workspace_members WHERE workspace_id = ownerId AND user_id =
  ownerId AND role='owner'` validation still holds (ops@ owns `754ee124`).
- Owners-only RLS grants `jean.deruelle@` and excludes the two `harry@` members
  (operator-confirmed intent).

## Research Reconciliation — Spec vs. Codebase

| Claim | Codebase reality | Plan response |
|---|---|---|
| "button URL / route is broken" | URL + route correct; `notifications.test.ts:341` asserts the shape | No URL/route change |
| "repoint or consolidate the owner" | Operator chose shared workspace inbox instead | Re-key to workspace grain |
| email_triage_items is workspace-scoped | NO `workspace_id` column (mig 102); RLS `user_id = auth.uid()` | Add `workspace_id`; rewrite RLS |
| table is a normal CRUD table | WORM ledger: `no_mutate` trigger, owner-SELECT-only RLS, RPC-only status transitions | Migration must respect every WORM arm |
| reads gate in one place | 3 read sites + 1 status RPC all gate on `user_id` | Update all 4 (enumerated below) |
| prod can already share | Team workspaces ENABLED via Flagsmith; jean.deruelle@ already co-Owner (operator-confirmed) — mig 068 header was a stale May-25 snapshot | Precondition MET; Phase 0 re-confirms topology read-only |

## User-Brand Impact

**If this lands broken, the user experiences:** an Owner clicks the gold "Open
inbox item" in a statutory-deadline email and hits a dead 404 — or worse, a
shared statutory item silently disappears for a co-Owner — at the one moment a
regulatory response clock (Art. 12) is running. Missed-deadline hazard, not
cosmetic.

**If this leaks, the user's workflow is exposed via:** an RLS predicate that is
too wide would expose one workspace's inbound-email ledger (third-party PII:
senders, subjects) to a user who is not an Owner of that workspace. The new
SELECT predicate MUST be owner-membership-scoped, never `is_workspace_member`
(any member) and never unscoped. The detail-page diagnostic mirror carries ONLY
`emailId` — never sender/subject/summary (attacker-controlled inbound content),
never a foreign `user_id`.

**Brand-survival threshold:** single-user incident. `requires_cpo_signoff: true`.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 (migration — workspace_id + backfill):** new migration
  `111_email_triage_items_workspace_shared.sql` adds `workspace_id uuid NULL
  REFERENCES public.workspaces(id) ON DELETE RESTRICT`, backfills existing rows
  (`workspace_id = user_id` for the solo-workspace shape) under a GUC-bypass arm
  added to `email_triage_items_no_mutate` (the WORM trigger rejects a plain
  backfill UPDATE), then the write path sets it going forward. `workspace_id`
  is added to the trigger's **hard-frozen** column set (set-once at insert).
- [ ] **AC2 (RLS — owner-membership SELECT):** the `email_triage_items_owner_select`
  policy is replaced with a predicate readable by any **Owner** of the row's
  workspace, via a SECURITY DEFINER plpgsql helper
  `is_email_triage_workspace_owner(p_workspace_id, p_user_id)` (mig 068's
  `is_attachment_path_workspace_member` pattern, but `role = 'owner'`-scoped,
  NOT `is_workspace_member`). Helper pins `search_path = public, pg_temp`;
  REVOKE-from-all then GRANT to `authenticated`.
- [ ] **AC3 (status RPC re-auth):** `set_email_triage_status` authorization
  changes from `v_row.user_id <> auth.uid()` to "caller is an Owner of
  `v_row.workspace_id`" (reuse the AC2 helper). Same-error-for-missing-and-
  foreign-row (no existence oracle) preserved. One-way matrix unchanged.
- [ ] **AC4 (write path):** `email-on-received.ts` claim-insert sets
  `workspace_id` = the validated owner's solo workspace_id (already computed as
  `ownerId` in the N2 solo shape). No change to the notification recipient.
- [ ] **AC5 (read/act paths — COMPLETE inventory, deepen-verified):**
  `.eq("user_id", …)` is replaced with the workspace-Owner gate at every site:
  (a) `app/(dashboard)/dashboard/inbox/email/[emailId]/page.tsx` (detail read);
  (b) `app/api/inbox/emails/route.ts` (3 queries: list/new-count/archived);
  (c) `server/email-triage-tools.ts` (list + get + status-change tools);
  (d) `server/email-triage/email-triage-status-handler.ts` — the shared handler
  behind the `acknowledge`/`archive` routes (`makeEmailTriageStatusHandler`); if
  it pre-gates on `user_id` before calling the RPC, widen to the owner gate (the
  RPC's own re-auth, AC3, is the DB-level enforcement). The two route files
  (`app/api/inbox/emails/[id]/{acknowledge,archive}/route.ts`) are thin
  HTTP-only exports — no change needed there. `app/(dashboard)/dashboard/page.tsx`
  renders the inbox via `GET /api/inbox/emails` + `EmailTriageRow` (no direct
  email_triage_items query — covered by (b); its `.eq("user_id")` at :274 is the
  unrelated conversations cross-workspace hint). The RLS change makes
  owner-membership rows visible; the belt-and-suspenders `.eq` must widen
  consistently or be dropped — never leave a `user_id` filter that re-narrows
  below RLS.
- [ ] **AC6 (diagnostic hygiene — carryover):** the detail page captures `error`
  from the query and calls `reportSilentFallback(error, { feature:
  "email-triage", op: "inbox-detail-lookup-error", extra: { emailId } })` before
  `notFound()`. `extra` carries ONLY `emailId`. Genuine `{data:null,error:null}`
  → clean `notFound()`, no mirror.
- [ ] **AC7 (failing-test-first):** new test(s) assert: owner-of-workspace reads
  a row; non-owner-member and non-member do NOT; status RPC authorizes an Owner
  and rejects a non-owner with the no-oracle error; query-error path mirrors once
  with the error object. Tests FAIL before the code change.
  (`apps/web-platform/test/**/*.test.ts`, node project per `vitest.config.ts:44`.)
- [ ] **AC8 (GDPR — anonymise/DSAR unchanged-by-design, verified):** confirm the
  account-delete cascade (`account-delete.ts:915` → `anonymise_email_triage_items`)
  still NULLs `user_id`+`sender` WHERE `user_id = departing` and the row SURVIVES
  via `workspace_id` (statutory evidence preserved for co-Owners). Confirm
  `dsar-export-allowlist.ts:306` keeps `ownerField: "user_id"` (a shared ledger
  of third-party inbound mail is not a co-Owner's personal data). gdpr-gate signs
  off on the solo `workspace_id = user_id` pseudonym question (see GDPR section).
- [ ] **AC9 (typecheck + tests):** `cd apps/web-platform && ./node_modules/.bin/tsc
  --noEmit` clean; new + existing `notifications.test.ts` pass via
  `./node_modules/.bin/vitest run`.
- [ ] **AC10 (migration safety):** `ls supabase/migrations/ | tail` confirms 111
  is the next ordinal; migration body has NO top-level BEGIN/COMMIT (runner wraps
  `--single-transaction`); no `CREATE INDEX CONCURRENTLY` (txn-wrapped runner).

### Post-merge (operator)

- [ ] **AC11 (membership precondition — MET):** Phase 0 confirms `jean.deruelle@`
  holds `role='owner'` in the workspace owning the items (operator-confirmed; team
  workspaces enabled via Flagsmith). No membership change required. If Phase 0
  surprises (uid mismatch, wrong workspace), STOP and reconcile before shipping.

## Implementation Phases

### Phase 0 — Live topology verification (read-only, BEFORE code)
1. Supabase MCP read-only:
   - `SELECT id, email FROM auth.users WHERE email IN ('jean.deruelle@jikigai.com','ops@jikigai.com');`
   - `SELECT workspace_id, user_id, role FROM workspace_members WHERE user_id IN (<both uids>);`
     — establish whether a common workspace exists where both are `role='owner'`.
   - `SELECT id, user_id, workspace_id FROM email_triage_items ORDER BY received_at DESC LIMIT 5;`
     (workspace_id will be NULL pre-migration; confirms `user_id = ops@`).
2. Record the topology in the PR body. Branch AC11 on the result.

### Phase 1 — Failing tests (RED) — AC7
### Phase 2 — Migration 111 (workspace_id + backfill + RLS + status RPC) — AC1/2/3
### Phase 3 — Write path (stamp workspace_id) — AC4
### Phase 4 — Read paths (3 sites) + diagnostic mirror — AC5/AC6
### Phase 5 — GDPR verification (anonymise/DSAR) — AC8
### Phase 6 — Typecheck + tests + migration-safety — AC9/AC10

## Files to Edit
- `apps/web-platform/server/inngest/functions/email-on-received.ts` — stamp `workspace_id`.
- `apps/web-platform/app/(dashboard)/dashboard/inbox/email/[emailId]/page.tsx` — workspace gate + error mirror.
- `apps/web-platform/app/api/inbox/emails/route.ts` — 3 queries to workspace gate.
- `apps/web-platform/server/email-triage-tools.ts` — list/get/status tools to workspace gate.

## Files to Create
- `apps/web-platform/supabase/migrations/111_email_triage_items_workspace_shared.sql` (+ `.down.sql`)
  — workspace_id column, backfill (GUC-bypass), `is_email_triage_workspace_owner` helper,
  RLS rewrite, `set_email_triage_status` re-auth, WORM-trigger hard-frozen update.
- New test(s) under `apps/web-platform/test/`.

## GDPR / Compliance (gdpr-gate to run)
- **Anonymise:** unchanged shape works — `user_id`→NULL leaves the row (workspace_id
  preserves it for co-Owners; statutory rows retained). Verify the FK
  `workspace_id … ON DELETE RESTRICT` does not block account-delete (it can't:
  workspaces aren't deleted on user delete).
- **Solo pseudonym question (open for gdpr-gate):** for solo workspaces
  `workspace_id == user_id`, so after anonymise the row still carries the former
  owner's uid in `workspace_id`. gdpr-gate to rule whether anonymise must also
  NULL `workspace_id` for solo-shape rows, or whether the workspace identifier is
  out-of-scope (it identifies a workspace, not a data subject).
- **DSAR:** keep `ownerField: "user_id"` — the shared ledger is third-party
  inbound mail, not a co-Owner's personal data. Confirm with gdpr-gate.
- Article-30 register: PA entry for `email_triage_items` may need a §(c)/(d) note
  on workspace-shared visibility (mirror mig 068's PA-2 §(c) update).

## Architecture Decision (ADR/C4)
Re-keying a regulated WORM ledger from user grain to workspace grain is an
architectural decision. **Create an ADR** (next number) recording: email-triage
items move from user-owned to workspace-owned read grain, owner-membership RLS,
notification recipient unchanged. Align with **ADR-038** (team workspaces /
workspace_members) and **ADR-044** (workspace ownership). **C4:** Component view
— email-triage read edge moves from User to Workspace(Owner). Edit `.c4` model in
this feature's lifecycle (not deferred).

## Infrastructure (IaC)
**None.** No new infra surface: the notification recipient is unchanged, so
`EMAIL_TRIAGE_OWNER_USER_ID` is NOT modified (the obsolete config-fix plan's
Terraform `doppler_secret` is dropped — not needed under the shared-reads
decision). Pure migration + app-code change against provisioned surfaces.

## Observability
```yaml
liveness_signal:
  what: existing statutory-notify success/failure log (notifications.ts:387) — unchanged
  cadence: per inbound statutory email
  alert_target: Sentry (email-triage feature tag)
  configured_in: apps/web-platform/server/notifications.ts
error_reporting:
  destination: Sentry via reportSilentFallback (server/observability.ts)
  fail_loud: true — detail-page query errors mirrored (op "inbox-detail-lookup-error"), no longer a bare 404
failure_modes:
  - mode: detail-page query error (RLS misconfig, malformed uuid, DB timeout)
    detection: reportSilentFallback op "inbox-detail-lookup-error" (pg_code)
    alert_route: Sentry op:inbox-detail-lookup-error
  - mode: owner-membership predicate too wide (cross-workspace read)
    detection: AC7 RLS test (non-member/non-owner returns 0 rows)
    alert_route: pre-merge test gate
  - mode: membership precondition unmet (no co-Owner exists)
    detection: Phase 0 read-only topology check
    alert_route: PR body + AC11 operator decision
logs:
  where: pino structured logs + Sentry breadcrumbs
  retention: existing platform retention
discoverability_test:
  command: "doppler secrets get EMAIL_TRIAGE_OWNER_USER_ID -p soleur -c prd --plain  # NO ssh"
  expected_output: "owner uuid (unchanged); topology confirmed via Supabase MCP read-only"
```

## Out of Scope / Non-Goals
- Repointing or consolidating `EMAIL_TRIAGE_OWNER_USER_ID` (operator chose shared reads).
- Notification fan-out to multiple Owners (locked: single recipient).
- All-members (non-owner) visibility (locked: Owners only).
- The webhook founder resolver (3M) and auth-lock (3K) — documented red herrings.
- Enabling `TEAM_WORKSPACE_INVITE_ENABLED` / creating the team workspace — an
  operator decision surfaced in AC11, executed separately if chosen.

## Risks & Mitigations
- **RLS too wide → cross-workspace PII leak.** Owner-scoped helper (`role='owner'`),
  RLS test asserts non-owner returns 0 rows. Brand-survival gate.
- **WORM backfill rejected by no_mutate trigger.** Add a dedicated GUC-bypass arm
  (`app.email_triage_backfill_in_progress`) mirroring the existing purge/anonymise
  GUC pattern; backfill UPDATE runs under it; arm removed-from-effect after.
- **Status RPC left user_id-pinned.** AC3 explicitly re-auths it — a co-Owner
  could read but not acknowledge/archive otherwise (half-shared inbox).
- **Stale-state assertion (the mistake this plan already made).** Live flag +
  membership state was claimed from a migration-header snapshot; corrected to
  Flagsmith + Supabase as the sources of truth. Phase 0 re-verifies read-only.

## Sharp Edges
- `email_triage_items` is WORM — the migration touches a `no_mutate` trigger,
  owner-SELECT RLS, AND an `auth.uid()`-pinned RPC. All three must change together
  or the inbox is half-shared.
- Mirror `068_attachments_workspace_shared` for the SECURITY DEFINER helper shape
  (plpgsql not sql, to defeat planner inlining of the tenant boundary).
- `COMMENT ON POLICY` fails on Supabase prd (storage.objects ownership) — N/A here
  (public.email_triage_items is runner-owned) but keep policy prose in-body.
- Test path must match `vitest.config.ts:44` node glob (`test/**/*.test.ts`); typecheck
  is `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (no root workspaces).
- Migration body: no top-level BEGIN/COMMIT; no `CREATE INDEX CONCURRENTLY`.

## Deepen Pass (2026-06-17)

Deterministic gates: 4.6 User-Brand-Impact ✓ (threshold single-user incident),
4.7 Observability ✓ (5-field schema), 4.8 PAT-shaped ✓ none, no new scheduled
job (Inngest/cron gate N/A). 4.9 UI-wireframe: `page.tsx` matches the
`app/**/page.tsx` glob but the edit is a data-gate swap + server-side error
mirror with **no new screen/modal/layout** → `ui-surface-terms.md` "pure logic,
no structural change" exclusion; no `.pen` required.

### Precedent-diff — `068_attachments_workspace_shared.sql`
| Aspect | Mig 068 (precedent) | This migration (111) |
|---|---|---|
| helper | `is_attachment_path_workspace_member` — SECURITY DEFINER **plpgsql** (defeats planner inlining of tenant boundary), `is_workspace_member` (ANY member) | `is_email_triage_workspace_owner` — same SECURITY DEFINER plpgsql shape, but `role = 'owner'`-scoped (Owners-only decision) |
| RLS split | FOR ALL → widened SELECT + 3 narrow write policies (FOR ALL USING governs writes too) | email_triage_items has **no** authenticated write policies (writes are RPC/service-role); only the SELECT policy widens — no write-policy split needed |
| GRANT | REVOKE from all 4 roles, GRANT to authenticated | identical |
| GDPR cascade | nulls `messages.user_id` per-workspace | reuse existing `anonymise_email_triage_items` (unchanged) — row survives via `workspace_id` |

### Concrete migration mechanisms
- **WORM backfill (the load-bearing edge):** the existing `no_mutate` trigger
  rejects a plain backfill UPDATE. Add a GUC-bypass arm
  `app.email_triage_backfill_in_progress` (mirrors the existing
  purge/anonymise/status GUC idiom), wrap the one-time
  `UPDATE … SET workspace_id = user_id` in `SET LOCAL … = 'on'`, and add
  `workspace_id` to the trigger's **hard-frozen** column set (set-once at insert,
  immutable thereafter — same arm as `id`/`claim_key`).
- **RLS predicate:** `USING (public.is_email_triage_workspace_owner(workspace_id, auth.uid()))`
  where the helper is `EXISTS(SELECT 1 FROM workspace_members WHERE workspace_id =
  p_workspace_id AND user_id = p_user_id AND role = 'owner')`. NULL workspace_id
  (anonymised rows) → helper returns false → not readable (correct: anonymised =
  erased).
- **Status RPC re-auth:** replace `v_row.user_id <> auth.uid()` with
  `NOT public.is_email_triage_workspace_owner(v_row.workspace_id, auth.uid())`;
  keep the same `42501` no-oracle error for missing+foreign rows.

### GDPR (carry to /review gdpr-gate)
- anonymise survival: `user_id`→NULL leaves `workspace_id` intact → co-Owners
  still see statutory evidence (Art. 5(1)(e) retention preserved). The
  `workspace_id … ON DELETE RESTRICT` FK can't block account-delete (workspaces
  aren't deleted on user delete).
- **Open for gdpr-gate:** for the residual-personal-workspace shape
  `workspace_id == user_id`, an anonymised row still carries the former owner's
  uid in `workspace_id`. gdpr-gate to rule whether anonymise must also NULL
  `workspace_id` for that shape (workspace identifier vs data-subject identifier).
- DSAR keeps `ownerField: "user_id"` (shared third-party inbound mail is not a
  co-Owner's personal data).

### Verify-the-negative (round-1)
"Never log sender/subject/summary in the mirror" — confirmed: detail page already
routes display fields through `sanitizeDisplayString`; the new mirror's `extra` is
restricted to `{ emailId }`. No contradiction.
