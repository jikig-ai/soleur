---
date: 2026-05-29
topic: resend-pending-invite
issue: 4636
branch: feat-resend-pending-invite
pr: 4645
lane: cross-domain
brand_survival_threshold: single-user incident
user_brand_critical: true
---

# Brainstorm: Resend / re-issue a pending workspace invite (#4636)

## What We're Building

An owner-side **"Resend"** action on each pending workspace invite. Resend mints a
**new** invite token, resets the 7-day expiry, invalidates the old link, and
re-sends the invite email. It complements the cancel-only slice shipped in #4632
(feat-cancel-pending-invite, closed #4634): cancel handles wrong-email and clearing
stale invites; resend handles "the right person never accepted in time."

Resend applies to **any non-terminal invite** — both expired and still-valid (a
pre-expiry nudge). It is owner-only and mirrors the existing invite auth chain.

## Why This Approach

The `workspace_invitations` table is **append-only by design**. The
`workspace_invitations_no_mutate()` trigger (migration `075:93`, re-issued in `085`)
makes `token_hash`, `expires_at`, PII, and audit-lineage columns **immutable** once a
row exists. The literal "edit the row to rotate the token + reset expiry" is therefore
rejected by the DB — confirmed by direct grep of 075/085, not just leader assertion.

**Chosen: revoke-old + insert-new (single RPC transaction).**
- In one `SECURITY DEFINER` transaction: `SELECT … FOR UPDATE` the old row → owner
  re-check on the old row's `workspace_id` (cross-tenant guard) → terminal-state guards
  → cooldown check → `UPDATE old SET revoked_at=now()` → `INSERT` a fresh row with the
  new `token_hash`, `now()+7d`, same email/role/inviter, and the **same
  `attestation_id`** carried forward.
- The old link dies for free: `lookup_invitation_by_token` and
  `accept_workspace_invitation` already reject rows where `revoked_at IS NOT NULL`.
- Atomic by construction; zero trigger change; reuses the proven model from #4632.
- The pending-invites list already filters `revoked_at IS NULL`, so the superseded row
  disappears and the new one surfaces with no consumer change.

**Rejected: relax the WORM trigger for in-place rotation.** Widens a security-relevant
immutability invariant that three migrations and the unique `token_hash` index depend
on; every guard becomes conditional. CTO rated HIGH risk.

## Key Decisions

| Decision | Choice | Source |
|----------|--------|--------|
| Token strategy | Mint new token, invalidate old | Operator |
| In-place vs revoke+insert | **Revoke-old + insert-new** (WORM forbids in-place) | Operator + CTO/CLO |
| Resend scope | Any non-terminal invite (expired **or** still-valid) | Operator |
| Cross-tenant control | Owner re-check **inside the RPC** on the old row's workspace_id (load-bearing; route check insufficient because RPC is `service_role`) | CTO |
| Email abuse / #4638 | Server-side cooldown (~60s) computed against the **most recent non-terminal row for (workspace_id, invitee_email)**, RPC-level so service-role can't bypass | CTO |
| Attestation | **Reuse** original `attestation_id` (same email, same role → attested fact unchanged); re-prompting is legal theater | CLO |
| Accountability | Resend re-processes PII (Art. 5(2)) → log who resent + when; the revoked-old-row + new-row pair is itself the rotation audit record | CLO |
| Confirm dialog | None — reversible, low-stakes, one click (parity with Cancel) | CPO |
| Success feedback | Inline, commit-on-server-ok: swap button to "Sent ✓" ~3s, refresh row expiry to "Expires in 7d" | CPO |
| Button affordance | Sibling of Cancel in a `flex gap-2` cluster. Primary/emphasized on **expired** rows; secondary nudge on still-valid rows | CPO |
| Error copy | Per-action message (current row error is hardcoded "Couldn't cancel" — would lie for resend) | CPO |
| Resend count / history UI | **Cut** (over-build; cooldown already guards spam) | CPO |
| Observability | Replace resend route's email `.catch(()=>{})` with `reportSilentFallback` — a swallowed failure on an explicit "send again" is a silent no-op on a user action | CTO |
| SECURITY DEFINER | New RPC must `SET search_path = public, pg_temp`; `REVOKE … FROM PUBLIC,anon,authenticated; GRANT EXECUTE … TO service_role` | CTO (cq-pg-security-definer-search-path-pin-pg-temp) |

## Open Questions

1. **Attestation FK sharing** — can two `workspace_invitations` rows reference the same
   `attestation_id`, or is there a 1:1 constraint? If 1:1, resend must either copy the
   attestation row or relax the constraint. Resolve at plan time against `058` +
   `076_invitation_invitee_identity_check.sql`.
2. **Cooldown column** — does the 60s cooldown need a persisted `last_sent_at`, or can
   it derive from the most-recent non-terminal row's `created_at`? Leaning derive-from-
   `created_at` (no new column, no new trigger arm). Confirm in plan.
3. **DSAR consumers** — `dsar-export.ts`, `dsar-export-allowlist.ts`, `account-delete.ts`
   read `workspace_invitations`. Revoke+insert adds rows but no new column/PII shape;
   confirm exports still behave (likely no-op, but verify).

## Domain Assessments

**Assessed:** Engineering, Product, Legal (Marketing, Operations, Sales, Finance, Support — not relevant)

### Engineering (CTO)

**Summary:** In-place rotation is blocked by the WORM trigger (HIGH-risk to relax);
revoke-old + insert-new in one RPC transaction is the architecturally aligned path,
atomic by construction, reusing the #4632 model. Load-bearing controls: RPC-level owner
re-check (cross-tenant), RPC-level cooldown (email abuse + keeps #4638's OTP fix intact),
search_path pinning, and replacing the swallowed email-failure catch with Sentry mirroring.

### Product (CPO)

**Summary:** Add Resend as a sibling of Cancel — primary on expired rows, secondary nudge
on valid rows; no confirm dialog; inline "Sent ✓" with refreshed expiry; 60s cooldown via
a disabled button; reuse the per-row `pendingIds`/`errorIds` Set pattern (add `sentIds`).
Cut resend-count/history as over-build. Fix the hardcoded "Couldn't cancel" error copy.

### Legal (CLO)

**Summary:** Reuse the original attestation (same email/role → attested fact unchanged;
re-prompting is theater). No new lawful basis (Art. 6(1)(a)/(c) unchanged), but resend is
a fresh PII-processing event — log who/when for Art. 5(2) accountability. No
Privacy/DPD/GDPR-register edit expected (no new processing activity); auditor to confirm.

## Capability Gaps

None. All required skills (Supabase migration, gdpr-gate, security-review, engineering)
are present in-domain. Confirmed via the three leader assessments + direct migration grep.
