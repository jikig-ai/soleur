---
title: BYOK delegation consent gate (gate-in-SQL) + the in-flight billing boundary on consent withdrawal
status: accepted
date: 2026-05-29
related: [4625, 4232, 4508, 4290]
related_adrs: [ADR-040, ADR-026]
related_plans:
  - knowledge-base/project/plans/2026-05-29-feat-byok-delegation-consent-enforcement-plan.md
brand_survival_threshold: single-user incident
---

# ADR-045: BYOK delegation consent gate + in-flight billing boundary

## Status

**Accepted** (2026-05-29, PR #4627; #4625). Sibling to [ADR-040](./ADR-040-byok-delegations-resolver-and-grace.md)
(resolver + WORM ledger + atomic cap RPC) and the dual-end-semantics it
established. Lands before `FLAG_BYOK_DELEGATIONS` flips ON in prd (the flip
is CLO-sign-off-gated — AC10/AC11).

## Context

ADR-040 shipped the delegation resolver `resolve_byok_key_owner` and the
atomic cap RPC `check_and_record_byok_delegation_use`. PR-B (#4508) shipped
the consent **capture** layer (`byok_delegation_acceptances`, mig 074). The
gap closed here: the resolver activated a delegation on `revoked_at IS NULL
AND expires_at > clock_timestamp()` **without checking acceptance**, so a
grantee's prompts could be processed under the grantor's key — with the
grantor seeing itemized cost telemetry — **before the grantee consented**.
That is a GDPR Art. 26 joint-controllership / processing-without-consent
exposure at the single-user-incident threshold (ADR-040's stated brand
threshold: an unauthorized invoice).

Two decisions needed recording: (1) **where** the consent gate lives, and
(2) **what the billing boundary is** when a grantee withdraws consent
mid-run.

## Decision

### 1. Gate in SQL, not TS (consent + withdrawal both at the resolver)

The acceptance check is an `AND EXISTS(current-version acceptance)` clause
added **inside** `resolve_byok_key_owner` (mig 083), and the withdrawal
check is a second `AND NOT EXISTS(withdrawal newer than the latest
acceptance)` clause (mig 084). Rationale:

- Preserves the atomic-MVCC TOCTOU guarantee (ADR-040 Decision #8) — the
  gate evaluates in the same query that selects the delegation.
- **Zero TS lease call-site changes** — the gate is at the single SQL
  chokepoint, so call-site count (2 today) is irrelevant to correctness.
- Automatically scoped to the delegation path only: the own-key
  short-circuit runs first, so solo BYOK users are unaffected.

The canonical version is **server-owned**: a SQL function-literal
`current_byok_side_letter_version()` (the single SQL source of truth) plus a
TS constant `BYOK_SIDE_LETTER_VERSION`, pinned in lockstep by a CI parity
gate. A version bump fail-closes every stale acceptance at the gate. A
function-literal (not a `byok_side_letter_versions` table) was chosen so the
legal-version pin is a reviewed-migration artifact, not runtime-mutable data.

### 2. Withdrawal is gate-side, non-terminal; in-flight billing stops within one turn and debits the grantee

A withdrawal writes **only** a `byok_delegation_withdrawals` WORM row. It
does **not** set `byok_delegations.revoked_at` — the mig 064 WORM trigger
requires the 3-field revoke flip to fire together and the `revocation_reason`
CHECK enum has no `consent_withdrawn` value, so a `revoked_at`-only write
aborts. Gate-side withdrawal is also **non-terminal** (re-accepting
reactivates — Art. 7(3) "as easy to withdraw as to give"). This is distinct
from the grantor-revoke path (60s grace, billing-kill), which remains.

**The in-flight billing boundary (the load-bearing decision):** the resolver
clause alone only blocks *new* leases — it leaves an in-flight run billing
the grantor until the run ends. We therefore add a **per-turn consent
re-gate** to `check_and_record_byok_delegation_use` (the cap RPC already
locks the delegation row `FOR UPDATE` each turn): if a withdrawal post-dates
the latest acceptance, the turn raises and the audit row is written with
`founder_id = grantee` (a new `consent_withdrawn` attribution_shift_reason).
So:

- **Boundary = one turn.** A withdrawal stops grantor billing at the next
  per-turn cap check, not at run end. The window of grantor-billed
  post-withdrawal usage is at most one turn's tokens.
- **The grantee, not the grantor, is billed** for that final partial turn —
  symmetric with the existing `revoked_post_grace` / `expired` attribution
  shift (cost follows the party who continued past the boundary).

The withdrawal predicate is **version-agnostic** (`COALESCE(max(accepted_at),
withdrawn_at)` + `>=`): a version bump that nulls `max(current-version
accepted_at)` must not make `withdrawn_at > NULL` fail OPEN, and an
equal-timestamp tie must block. The withdrawals table carries **no
`UNIQUE(user_id, delegation_id)`** — it is an append-only event log
(withdraw→re-accept→withdraw) and a UNIQUE would break Art. 17 anonymise
(two rows collapsing to `(NULL, delegation_id)` collide). `user_id` is
NULLABLE for the anonymise-to-NULL path.

## Consequences

- **Accepted:** a version bump deactivates new leases but does NOT abort an
  in-flight run (only the next turn's re-gate sees the stale version). Version
  bumps are rare/deliberate; the next run re-consents. The maximum
  grantor-billed post-withdrawal exposure is one turn — judged acceptable vs.
  the complexity of mid-turn interruption.
- **Rejected:** setting `revoked_at` on withdrawal (would require widening the
  064 WORM enum + trigger and conflate consent-withdrawal with grantor-revoke
  billing-kill semantics); a versions table (runtime-mutable legal pin).
- **Erasure:** `anonymise_byok_delegation_withdrawals` runs before
  `auth.admin.deleteUser` (account-delete step 5.12); the ledger joins the
  DSAR Art. 15+20 export.

## References

- Plan: `knowledge-base/project/plans/2026-05-29-feat-byok-delegation-consent-enforcement-plan.md`
- ADR-040 (resolver + grace + dual-end semantics), ADR-026 (gate token budget)
- Migrations 083 (consent gate), 084 (withdrawal + per-turn re-gate)
