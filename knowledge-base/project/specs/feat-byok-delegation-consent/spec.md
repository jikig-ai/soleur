---
feature: byok-delegation-consent-enforcement
issue: 4625
parent: 4232
status: draft
lane: cross-domain
brand_survival_threshold: single-user incident
created: 2026-05-29
brainstorm: knowledge-base/project/brainstorms/2026-05-29-byok-delegation-consent-enforcement-brainstorm.md
---

# Spec — BYOK Delegation Consent Enforcement

## Problem Statement

BYOK delegations let a workspace owner (grantor) fund a member's (grantee's) Anthropic
runs on the owner's BYOK key. PR-B (#4508) shipped a consent *capture* layer — the
`byok_delegation_acceptances` WORM table (mig 074), a `POST /api/workspace/delegations/accept`
route, and a UI resolver that displays acceptance status. **But the key-lease backend
ignores it.** `resolve_byok_key_owner` (mig 064:583) activates a delegation on
`revoked_at IS NULL AND expires_at > clock_timestamp()` alone, so the grantor's key is
leased the instant the delegation is created — before the grantee accepts. The grantee's
itemized usage telemetry is therefore visible to the grantor without recorded consent
(GDPR Art. 26 / unauthorized-processing exposure). Additionally `side_letter_version` is
caller-supplied (`accept/route.ts:65`), there is no withdrawal path, and the prd flag flip
is still gated on a paper-signature consent document.

## Goals

- Make recorded in-app consent the source of truth that gates the key lease.
- Add a withdrawal path that terminates the lease.
- Make the consent text/version trustworthy and Art. 26-sufficient.
- Replace the paper-signature precondition with the recorded in-app consent and enable
  `FLAG_BYOK_DELEGATIONS` to be flipped programmatically through existing flag tooling
  (unblocks #4232).

## Non-Goals

- Re-consent re-prompt UX (the version-specific gate already fail-closes on a text bump).
- Multi-grantee / multi-grantor fan-out.
- Consent audit-export UI (DSAR runbook extraction suffices).
- A new grace mechanism for withdrawal (reuse the existing 60s revoke grace).
- Per-action consent scoping.

## Functional Requirements

- **FR1 — Consent gate.** `resolve_byok_key_owner` returns a grantor key owner only when a
  current-version, unwithdrawn acceptance row exists for (grantee, delegation). Otherwise it
  returns empty → `MissingByokKeyError` (fail-closed). [Decisions #2, #3]
- **FR2 — Withdrawal.** A grantee can withdraw consent; a new `byok_delegation_withdrawals`
  WORM row is recorded. The resolver treats a delegation as inactive when a withdrawal exists
  newer than the latest acceptance. Withdrawal reuses the 60s revoke grace; post-grace tokens
  debit the grantee. [Decisions #4, #5]
- **FR3 — Server-owned canonical version.** The accept route validates the submitted
  `side_letter_version` against a server-owned canonical version and rejects mismatches; the
  resolver compares the stored version against the canonical one. [Decisions #6, #7]
- **FR4 — Pending-consent UX.** Grantor sees an explicit not-live state (no spend/cap banner
  pre-acceptance); grantee sees a review-and-accept prompt with an inline telemetry-visibility
  acknowledgment. [Decision #11]
- **FR5 — Art. 26 consent text.** The versioned consent text embodies the joint-controllership
  responsibility allocation and states the Art. 6 basis; grantor is bound to the same version.
  mig 074's lawful-basis header is corrected. [Decisions #8, #9]
- **FR6 — Flag flip.** Once FR1–FR5 land and CLO confirms the text, flip the flag through
  existing flag tooling (Flagsmith + Doppler) programmatically — no signing ceremony, no
  human gate. [Decision #12]

## Technical Requirements

- **TR1** — Gate implemented as an `AND EXISTS(...)` clause inside `resolve_byok_key_owner`
  (`CREATE OR REPLACE`, mig 075), preserving the atomic-MVCC TOCTOU guarantee (064 Decision #8);
  re-assert REVOKE/GRANT and run a `pg_default_acl` / default-privileges audit. [Decision #13]
- **TR2** — `byok_delegation_withdrawals` WORM table with its own no-UPDATE trigger + Art. 17
  anonymise RPC, mirroring 044/074; pin `search_path = public, pg_temp` on all DEFINER fns. [Decision #13]
- **TR3** — The 5 lease call sites (agent-runner.ts:882/2401, cc-dispatcher.ts:890,
  cfo-on-payment-failed.ts:199, github-on-event.ts:208) require no change; add a sentinel-sweep
  assertion. [Decision #2, hr-write-boundary-sentinel-sweep-all-write-sites]
- **TR4** — Tests: no-consent → `MissingByokKeyError` (distinct from `ByokDelegationRevokedError`);
  stale-version acceptance fail-closes; withdrawal terminates lease after grace; cross-tenant
  isolation preserved.
- **TR5** — ADR via `/soleur:architecture create` (withdrawal-as-separate-WORM-ledger + canonical
  version ownership) before the gate PR merges. [Decision #15]
- **TR6** — Route the spec through `/soleur:gdpr-gate` before merge. [Decision #14]

## Open Questions

See brainstorm `## Open Questions` (canonical-version storage shape, exact unwithdrawn SQL clause,
gdpr-gate findings, #4364 independence, member-departure/DSAR carry-forward).

## Acceptance Criteria

- A delegation with no current-version acceptance does not lease the grantor's key (verified test).
- Withdrawal terminates the lease within the 60s grace semantics.
- Caller-supplied version cannot satisfy the gate (server-owned canonical version enforced).
- CLO confirms the consent text satisfies Art. 26; the paper-signature precondition is replaced.
- `FLAG_BYOK_DELEGATIONS` flippable programmatically through existing flag tooling.
