---
date: 2026-05-29
status: committed
decision: gate-plus-withdrawal-plus-flag-flip-defer-reconsent-ux
brand_survival_threshold: single-user incident
lane: cross-domain
supersedes: []
related:
  - knowledge-base/project/brainstorms/2026-05-22-byok-delegations-brainstorm.md
  - knowledge-base/legal/delegation-consent-side-letter-template.md
closes_issues:
  - 4625
---

# BYOK Delegation Consent Enforcement — In-Product Consent as Source of Truth

## What We're Building

The consent *capture* layer already shipped in PR-B (#4508): the
`byok_delegation_acceptances` WORM table (mig 074), a `POST /api/workspace/delegations/accept`
route, and a UI resolver that *displays* acceptance status. This feature wires that
captured consent into the actual key-lease path and makes it the legal source of truth,
so the out-of-band **signed** Delegation Consent Side Letter precondition for flipping
`FLAG_BYOK_DELEGATIONS` ON can be retired.

Three coupled pieces:

1. **Backend enforcement (the load-bearing fix).** `resolve_byok_key_owner` (mig 064:583)
   today returns the grantor as key owner whenever an active, unrevoked, unexpired
   delegation exists — it **never checks for an acceptance row**. Add an `AND EXISTS(...)`
   clause so a delegation is inactive until a current-version, unwithdrawn acceptance
   exists. No consent ⇒ no lease ⇒ `MissingByokKeyError` (fail-closed, identical to no-key).
2. **Withdrawal.** Currently unbuilt. Add a separate `byok_delegation_withdrawals` WORM
   table; the resolver clause becomes "accepted AND not withdrawn-since-latest-accept".
   Withdrawal reuses the existing 60s revoke-grace path (post-grace tokens debit the grantee).
3. **Legal retirement + flag flip.** Correct mig 074's lawful-basis header, make the
   versioned consent text embody the Art. 26 joint-controllership arrangement (not just
   unilateral assent), get CLO sign-off, then flip the flag with **zero out-of-band signed
   documents**.

## Why This Approach

The issue's stated outcome is "unblock #4232's flag flip with zero out-of-band
operator/legal steps." The CLO confirms that requires three load-bearing conditions:
the gate fix, a withdrawal path, and consent text that carries the Art. 26 arrangement.
The chosen scope delivers exactly those and flips the flag. Re-consent *re-prompt UX* is
the only deferrable piece because the consent text is stable during dogfood — but a cheap
**version-specific gate** (`side_letter_version = <current>`) is retained so any future
text bump auto-invalidates stale acceptances and fail-closes, satisfying CLO condition #4
without the deferred UX cost.

## Verified Premise (pre-spawn code findings)

| Claim | Status | Evidence |
|---|---|---|
| PR-A #4290, PR-B #4508 merged; #4232 OPEN; flag OFF | TRUE | `gh pr view` / `gh issue view` 2026-05-29 |
| `byok_delegation_acceptances` table + accept route + UI resolver exist | TRUE | mig 074; `app/api/workspace/delegations/accept/route.ts`; `byok-delegation-ui-resolver.ts:174` |
| Backend lease gate ignores consent | TRUE (the gap) | `resolve_byok_key_owner` mig 064:583-625 — selects on `revoked_at IS NULL AND expires_at > clock_timestamp()` only |
| `side_letter_version` is caller-supplied (no server canonical) | TRUE | `accept/route.ts:65` ← `body.sideLetterVersion` |
| Acceptances table has no withdrawal column/RPC | TRUE | mig 074 INSERT/SELECT only; `UNIQUE(user_id, delegation_id)` |
| 5 lease call sites wrap via the resolver | TRUE | agent-runner.ts:882/2401, cc-dispatcher.ts:890, cfo-on-payment-failed.ts:199, github-on-event.ts:208 |

## User-Brand Impact

`USER_BRAND_CRITICAL=true` — operator selected "All of them" in Phase 0.1 framing
(processing-without-consent, billing surprise, cross-tenant trust breach).

**Artifact at risk:** Harry's prompt content (joint-controlled by Jean via delegation),
Jean's Anthropic billing, the cross-tenant boundary on `byok_delegations`.

**Vectors:**
1. **Processing without consent (live today).** A delegation funds the grantee's runs the
   instant the grantor creates it — Harry's itemized telemetry is visible to Jean before
   Harry accepts. GDPR Art. 26 / unauthorized-processing exposure. Mitigation: the resolver
   gate refuses to activate without a current-version, unwithdrawn acceptance.
2. **Withdrawn-but-still-charging.** A grantee who withdrew keeps spending the grantor's
   budget. Mitigation: withdrawal terminates the lease, reusing the 60s grace then debiting
   the grantee.
3. **Stale-version acceptance.** A consent-text change leaves old acceptances satisfying the
   gate. Mitigation: version-specific gate fail-closes on mismatch.

**Threshold:** `single-user incident`.

## Key Decisions

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| 1 | Scope | Gate + withdrawal + legal retirement + flag flip. Defer re-consent re-prompt UX only. | Operator selection. Achieves the issue's "unblock the flip" goal; CLO blockers 1 & 3 met. |
| 2 | Gate placement | `AND EXISTS(...)` clause inside `resolve_byok_key_owner` (SQL), NOT the TS layer. | CTO: preserves the Decision #8 atomic-MVCC TOCTOU guarantee; one place vs 5 call sites; no extra RTT. |
| 3 | Fail-closed semantics | No current-version unwithdrawn acceptance ⇒ resolver returns empty ⇒ `MissingByokKeyError`. | CTO: converges with the existing no-key path. Add an explicit test distinguishing no-consent from `ByokDelegationRevokedError`. |
| 4 | Withdrawal data model | New **`byok_delegation_withdrawals` WORM table** (mirror 044/074 precedent), NOT a `withdrawn_at` column. | CTO: 074's `UNIQUE(user_id, delegation_id)` + no-UPDATE trigger block an in-place column. Resolver clause: accepted AND no withdrawal newer than latest accept. ADR required. |
| 5 | Withdrawal lease behavior | Reuse the existing 60s revoke-grace; post-grace in-flight tokens debit the grantee. | CPO + CTO: withdrawal is semantically a grantee-initiated revoke; do not invent a parallel grace. |
| 6 | Canonical consent version | Introduce a **server-owned canonical version source** the SECURITY DEFINER fn can read; accept route validates submitted version against it (reject mismatch). | CTO HIGH-risk prerequisite: today the client self-asserts `side_letter_version`. Security fix, not a feature. |
| 7 | Re-consent gate vs UX | Keep the **version-specific gate** (`side_letter_version = <current>`, fail-closed). Defer only the friendly re-prompt flow. | Satisfies CLO condition #4 cheaply; re-prompt UX unneeded while text is stable (dogfood). |
| 8 | Consent text content | Versioned text must embody the **Art. 26 responsibility allocation** + state the **Art. 6 basis**; grantor bound to the same version at delegation creation. | CLO: a unilateral click is assent to terms; the *arrangement* is the content of those terms. |
| 9 | mig 074 header | Correct the "Art. 6(1)(b) contract — grantee consents" header (conflates basis with consent). State both bases coherently. | CLO: the record is self-contradictory on its face today. |
| 10 | DPD §2.3 + AUP §5.6 | **Retain.** In-app consent is the bilateral/evidentiary layer; DPD/AUP are the public-facing Art. 13/14 transparency half. | CLO: different legal functions; do not drop. |
| 11 | Pending-consent UX | Grantor sees an explicit not-live state ("Invited Harry — not funding until he accepts"), NO spend/cap banner pre-acceptance. Grantee sees "Jean offered to fund your runs — review & accept" with an **inline telemetry-visibility acknowledgment**. | CPO least-surprise: grantor must never believe funding is live before acceptance. |
| 12 | Flag flip | Automated via existing flag tooling (`/soleur:flag-set-role` / Flagsmith+Doppler) once gate + withdrawal merge and CLO confirms the consent text. NO signed PDF, NO operator checklist. | Issue goal: zero out-of-band steps. Per `hr-never-defer-operator-actions`. |
| 13 | Migration numbers | Gate = mig **075** (`CREATE OR REPLACE` resolver + re-assert REVOKE/GRANT + `pg_default_acl` audit). Withdrawals table = mig **075/076** with its own WORM trigger + Art. 17 anonymise RPC. | CTO: 074 is latest; DEFINER-RPC default-privileges audit mandatory. |
| 14 | gdpr-gate | Route the spec through `/soleur:gdpr-gate` before merge (joint-controllership + telemetry-visibility = regulated surface). | CPO + `hr-gdpr-gate-on-regulated-data-surfaces`. |
| 15 | ADR | Required — withdrawal-as-separate-WORM-ledger + canonical-version ownership. `/soleur:architecture create` before the gate PR merges. | CTO: two new cross-cutting decisions. |

## Open Questions

1. **Canonical version storage shape.** Shared TS constant mirrored into a small
   `byok_side_letter_versions` table the SECURITY DEFINER fn reads, vs a hardcoded value in
   the migration. Plan-skill decision (TS-const + DB-readable table is the leading shape).
2. **"Unwithdrawn" clause form.** `EXISTS(accept of current version) AND NOT EXISTS(withdrawal
   with created_at > that accept)` — confirm the exact SQL against the 60s-grace timestamp
   semantics at plan time.
3. **gdpr-gate findings** may add conditions (DSAR extraction of withdrawal events, retention
   of withdrawal rows). Run before plan close.
4. **Sentry alert (#4364)** for `art_33_breach=true` is a sibling open item; confirm it does
   not gate this work (it does not — separate post-merge).
5. **Member-departure auto-revoke + DSAR runbook** (carried from 2026-05-22 CLO list) — confirm
   already satisfied by PR-A/PR-B or whether withdrawal events need to appear in the DSAR export.

## Domain Assessments

**Assessed:** Product (CPO), Engineering (CTO), Legal (CLO). Marketing/Sales/Ops/Support/Finance
not spawned (no public surface, no positioning/pricing change, internal-flag-gated dogfood).

### Product (CPO)

**Summary:** v1-now, ship in slices: enforcement first (closes a live joint-controllership
exposure that clears the single-user threshold), then withdrawal (a hard prerequisite — not
deferrable — before the prd flag targets anyone beyond dogfood, since "consent you cannot revoke
is not real consent"). Pending-consent state must be visually distinct from active; grantor must
never see a live spend banner pre-acceptance; telemetry-visibility acknowledgment must be inline
in the accept action. Defer re-consent re-prompt UX and multi-grantee fan-out.

### Engineering (CTO)

**Summary:** Sound, well-scoped gap closure. Gate belongs in `resolve_byok_key_owner` as an
`AND EXISTS(...)` clause (preserves the Decision #8 atomic-MVCC TOCTOU guarantee; 5 call sites
unchanged; fail-closed on empty return). Withdrawal: separate WORM table (074's UNIQUE + no-UPDATE
trigger block an in-place column), reuse the 60s grace. **Canonical `side_letter_version` does not
exist server-side — it's caller-supplied at `accept/route.ts:65`; introducing a server-owned source
is a HIGH-risk prerequisite.** New mig 075 with REVOKE/GRANT re-assert + `pg_default_acl` audit; ADR
for withdrawal model + version ownership. Build: ~2-3 PRs / 4-6 days.

### Legal (CLO)

**Summary:** VIABLE-WITH-CONDITIONS. In-app recorded consent can replace the signed Side Letter
ONLY if: (1) the resolver gate requires a current-version acceptance row (blocker — today it ignores
acceptance); (2) the versioned text embodies the Art. 26 responsibility allocation + states the Art. 6
basis, grantor bound to the same version; (3) a withdrawal path exists and terminates the lease
(blocker — Art. 7(3)/17); (4) the gate is version-specific; (5) mig 074's lawful-basis header is
corrected (it conflates 6(1)(b) with consent); (6) DPD §2.3 + AUP §5.6 are retained as the public
disclosure half. Conditions 1 and 3 are the genuine blockers. Member-departure auto-revoke + DSAR
runbook (from 2026-05-22) still required.

## Capability Gaps

None new. Existing agents cover plan-time needs:

- **`legal-document-generator`** — rewrite the Delegation Consent Side Letter as versioned in-app
  consent text embodying the Art. 26 arrangement (Decision #8); correct mig 074 header.
- **`data-integrity-guardian`** + **`security-sentinel`** — mig 075 review (resolver EXISTS clause,
  withdrawals WORM trigger, RLS, anonymise RPC, default-privileges audit).
- **`gdpr-gate`** skill — fires on the regulated surface (Decision #14).
- **`ux-design-lead`** — pending-consent grantor/grantee views + withdraw affordance (plan-time;
  Phase 3.55 wireframes deferred to plan given the small, well-described UI delta).

## Non-Goals

- **Re-consent re-prompt UX** (friendly "the terms changed, re-accept" flow). The version-specific
  gate already fail-closes on a bump; the polished re-prompt waits until the consent text actually
  changes.
- **Multi-grantee / multi-grantor fan-out** — dogfood is one grantor + one grantee.
- **Consent audit-export UI** — DSAR runbook extraction (CLI/runbook) is sufficient for v1.
- **New grace mechanism for withdrawal** — reuse the existing 60s revoke grace.
- **Per-action consent scoping** ("consent to research but not deploys") — defer.

## Session Errors

1. **Issue body under-described prior art.** #4625 framed the work as "build an in-product consent
   flow," but PR-B #4508 had already shipped the capture table + accept route + UI resolver. Pre-spawn
   code reads (resolver SQL, accept route, mig 074) reframed the scope to enforcement + withdrawal +
   legal retirement BEFORE leader spawn — leaders received accurate ground truth and did not waste
   cycles re-deriving. Fix already internalized: brainstorm read the cited resolver/migration symbols
   against the worktree before Phase 0.5.

## Productize Candidate

None. Consent-gating is an app-domain authorization primitive, not a reusable skill/agent shape.

## Lane

- Lane: cross-domain (user-brand-critical triad mandatory).
- Brand-survival threshold: single-user incident.
