# ADR-066: Operator email-triage inbox is workspace-grained (Owner-shared reads), not single-user

- **Status:** Accepted
- **Date:** 2026-06-18
- **Issue:** PR #5494 (feat-shared-workspace-email-triage-inbox)
- **Lineage:** ADR-038 (team workspaces / `workspace_members`), ADR-044 (workspace ownership), mig 102 (email_triage_items WORM ledger), mig 068 (attachments workspace-shared precedent), mig 109 (residual-personal-workspace backfill).

## Context

`email_triage_items` (the operator email-triage WORM ledger, mig 102) was
single-user-grained: no `workspace_id`, RLS `USING (user_id = auth.uid())`,
writes stamped `user_id = EMAIL_TRIAGE_OWNER_USER_ID`, and the
`set_email_triage_status` RPC pinned authorization on `auth.uid() = user_id`.

This produced a real founder-facing incident: the email-triage owner identity
(`EMAIL_TRIAGE_OWNER_USER_ID` → `ops@jikigai.com`) was a **different**
`auth.users` row than the account the operator logs into the dashboard with
(`jean.deruelle@jikigai.com`), even though both are **Owners of the same
workspace**. Clicking the gold "Open inbox item" button in a statutory-deadline
notification 404'd, because the `user_id`-scoped read returned no row for the
logged-in identity. A dead link on a running Art. 12 statutory clock is a
brand-survival event, not a cosmetic glitch.

The operator's chosen resolution was not to repoint or consolidate the single
owner, but to make the inbox a **shared workspace inbox**: every Owner of the
owning workspace can read and act on its items.

## Decision

`email_triage_items` is re-keyed from **user grain to workspace grain**:

1. Add `workspace_id uuid REFERENCES workspaces(id) ON DELETE RESTRICT`;
   backfill existing rows `workspace_id = user_id` (valid because the write
   path validates the residual-personal-workspace shape `workspace_id =
   user_id = owner`, ADR-038 N2 / mig 109). The write path stamps
   `workspace_id = ownerId` going forward. `workspace_id` is WORM hard-frozen
   (set-once at insert; backfill is the only sanctioned NULL→value UPDATE,
   gated by `app.email_triage_backfill_in_progress`).
2. **Read grain moves from `user_id = auth.uid()` to Owner membership** of the
   row's workspace, via the SECURITY DEFINER plpgsql helper
   `is_email_triage_workspace_owner(workspace_id, auth.uid())` (mig 068's
   inlining-defeating pattern, but `role = 'owner'`-scoped). All application
   read sites drop their `.eq("user_id", …)` filter (it would re-narrow below
   RLS and hide the shared inbox).
3. `set_email_triage_status` re-auths from the `user_id` pin to the same
   workspace-Owner predicate, preserving the no-existence-oracle posture.
4. **Notification recipient is UNCHANGED** — the single configured owner
   (`EMAIL_TRIAGE_OWNER_USER_ID`'s email) is still the only address paged.
   Only *read/act* access broadens. (Operator decision: "one address, shared
   reads".)
5. **Sharing scope is Owners only** (`role = 'owner'`), not all members.
6. **Art. 17 erasure is unchanged.** `anonymise_email_triage_items` still NULLs
   `user_id` + `sender` and leaves `workspace_id`. The residual
   `workspace_id == former-uid` value is a FK to `workspaces` (organizational
   metadata required for ongoing co-Owner access + Art. 5(1)(e) statutory
   retention), not a stored data-subject identifier; NULLing it would orphan
   the statutory record from all co-Owners. DSAR keeps `ownerField = user_id`
   (a shared ledger of third-party inbound mail is not a co-Owner's personal
   data). gdpr-gate ruled this disposition Suggestion-level / defensible-as-is.

### C4 impact

The C4 model (`diagrams/model.c4` + `views.c4`) was **missing the entire email
ingress** that this feature operates on — a pre-existing gap from the email-triage
introduction (#5125) that a first pass wrongly dismissed as "no C4 impact." This
ADR corrects it (all three reviewed: model / views / spec):

- **New external actor** `emailSender` ("Inbound Correspondent") — the vendors /
  regulators / counsel whose mail is the inbox's inbound source.
- **New external system** `resend` (Resend) — inbound email webhook + outbound
  triage notifications.
- **New relationships** (L1 + L2): `emailSender → resend`, `resend → webapp/api`
  (inbound svix-verified webhook), `webapp/api → resend` (notifications, labeled
  "single configured recipient; reads are Owner-shared per ADR-066"),
  `inngest → supabase` (email-on-received claim/finalize writes).
- **Actor correctness:** the `founder` actor description ("Solo founder") was
  factually stale post-ADR-038 and directly contradicted by this feature; updated
  to "Founder / Operator … workspaces may have MULTIPLE Owners; Owner-shared
  surfaces are readable by every Owner."
- **`emailSender` + `resend` added to the `context` (L1) and `containers` (L2)
  view include-lists** so they render. `spec.c4` needed no change (`actor`,
  `system`, `tag external` already defined). Validated: `c4-code-syntax` +
  `c4-render` tests green.

## Alternatives Considered

- **Repoint `EMAIL_TRIAGE_OWNER_USER_ID` to the operator's login uid.** Fixes
  the single operator but keeps the inbox single-owner; the moment a second
  Owner needs visibility it breaks again. Also risks silently stopping ALL
  triage emails if the new uid fails the solo-owner write-path predicate.
  Rejected — does not match the operator's "shared inbox" intent.
- **Consolidate the two `auth.users` accounts.** Heavier, touches auth data and
  every other `ops@`-owned row; orthogonal to inbox sharing. Rejected as
  out-of-scope.
- **Share with all workspace members (not just Owners).** Rejected — the
  operator scoped sharing to Owners; statutory items warrant the narrower grant.
- **Fan out notifications to every Owner.** Rejected — operator chose a single
  notification address with shared reads.
- **NULL `workspace_id` on anonymise for the residual shape.** Rejected — see
  Decision §6; it would orphan statutory evidence from remaining Owners.

## Consequences

- Any Owner of the owning workspace sees and can acknowledge/archive statutory
  items; the original 404 is resolved once a row carries `workspace_id` and the
  logged-in Owner satisfies the membership predicate (verified live: the
  operator is already `role='owner'` of the owning workspace).
- The RLS predicate MUST stay Owner-scoped — widening to `is_workspace_member`
  would expose a workspace's third-party-PII inbound ledger to non-Owner
  members. Enforced by the WORM integration test (case j: co-Owner reads;
  non-owner denied) and `verify/111`.
- The grain change is confined to reads + the status RPC; the write path and
  notification recipient are untouched, bounding blast radius.
