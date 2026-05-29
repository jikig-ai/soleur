---
feature: byok-delegation-consent-enforcement
issue: 4625
parent: 4232
type: feature
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
created: 2026-05-29
brainstorm: knowledge-base/project/brainstorms/2026-05-29-byok-delegation-consent-enforcement-brainstorm.md
spec: knowledge-base/project/specs/feat-byok-delegation-consent/spec.md
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- Phase 2.8 reviewed: this plan introduces NO infrastructure (no server, service, cron,
     vendor account, DNS, cert, secret, or firewall rule). It is a Supabase-migration +
     app-code change against already-provisioned surfaces; the flag flip is automated through
     the existing /soleur:flag-set-role skill. The single Post-merge step (AC10) is a CLO legal
     determination that cannot be automated (human judgment). See ## Infrastructure (IaC). -->

# Plan — BYOK Delegation Consent Enforcement

## Overview

Make recorded in-app consent the source of truth that gates the BYOK key lease, add a
withdrawal path, make the consent version trustworthy and Art. 26-sufficient, and replace
the external paper-signature precondition so `FLAG_BYOK_DELEGATIONS` can be flipped
programmatically (unblocks #4232).

PR-B (#4508) already shipped the consent **capture** layer (table `byok_delegation_acceptances`
mig 074, `POST .../accept` route, UI resolver). The gap: the key-lease gate
`resolve_byok_key_owner` (mig 064:583) activates a delegation on `revoked_at IS NULL AND
expires_at > clock_timestamp()` **without checking acceptance**, and `side_letter_version`
is **client-supplied** (`accept/route.ts:65`).

Core design (validated against code):

- **Gate in SQL, not TS.** Add `AND EXISTS(current-version acceptance)` inside
  `resolve_byok_key_owner`. This keeps the atomic-MVCC TOCTOU guarantee (064 Decision #8),
  needs **zero change** to the TS lease call sites, and is **automatically scoped to the
  delegation path only** — direct `runWithByokLease` solo-key leases never hit the resolver,
  so own-key users are unaffected.
- **Withdrawal = gate-side, not revoke-side** (revised after plan-review P0). The withdraw RPC
  writes ONLY a `byok_delegation_withdrawals` WORM row; the resolver gains a second clause
  `AND NOT EXISTS(withdrawal newer than the latest current-version acceptance)`. It does NOT
  set `byok_delegations.revoked_at` — the mig 064 WORM trigger (064:312-354) requires
  `revoked_at` + `revoked_by_user_id` + `revocation_reason` to flip *together*, and the
  `revocation_reason` CHECK enum (064:95-99) has no `consent_withdrawn` value, so a revoked_at-only
  write aborts. Gate-side withdrawal is also **non-terminal** (re-accepting reactivates — Art. 7(3)
  "as easy as giving") and mirrors the acceptance-EXISTS pattern. Consequence: withdrawal blocks
  NEW leases immediately; in-flight runs complete (lawful pre-withdrawal processing, Art. 7(3));
  grantor-revoke (existing path, with 60s grace + debit-grantee) remains the distinct in-flight-kill
  + billing-control mechanism. The `byok_delegation_withdrawals` table is the Art. 7(3)/Art. 30
  consent-withdrawal evidence, distinct from grantor-revoke audit.
- **Server-owned canonical version.** The accept route stops trusting `body.sideLetterVersion`
  and stamps a server constant; the gate compares the stored version against the canonical one,
  so a version bump fail-closes stale acceptances (the version-specific gate; re-prompt UX
  deferred to #4628).

## Research Reconciliation — Spec vs. Codebase

| Spec/brainstorm claim | Reality (verified 2026-05-29) | Plan response |
|---|---|---|
| Gate migration is `075` | Highest migration is **082**; next free is **083/084** | Use mig **083** (gate) + **084** (withdrawals). Correct spec TR1/TR2. |
| "5 `runWithByokLease` call sites" wrap the resolver | Only **2** `resolveKeyOwnerThenLease` sites today (`agent-runner.ts:906, 2522`); other paths reach them indirectly | Non-load-bearing: gate lives in the SQL chokepoint, so call-site count is irrelevant to correctness. Sentinel sweep still enumerates (TR3). |
| `side_letter_version` capture exists | Exists but is **client-supplied** (`accept/route.ts:65` ← body; modal prop) | Server-owned canonical version is a **security prerequisite** (Phase 1), not a feature. |
| `byok_delegation_acceptances` to be built | Already shipped (mig 074, WORM, anonymise RPC) | Reuse as the gate's evidence source; mirror its WORM/anonymise shape for the new withdrawals table. |

## User-Brand Impact

**If this lands broken, the user experiences:** a grantee's prompts are processed under the
grantor's key with the grantor seeing itemized cost telemetry **before the grantee consented**
(processing-without-consent), or a grantee who withdrew keeps spending the grantor's budget.

**If this leaks, the user's data/money is exposed via:** joint-controllership of the grantee's
prompt content without a recorded Art. 26 arrangement, and the grantor's Anthropic billing for
unauthorized runs.

**Brand-survival threshold:** single-user incident. (`requires_cpo_signoff: true` — see Domain
Review; `user-impact-reviewer` runs at PR review.)

## Implementation Phases

TDD throughout (RED → GREEN). Migrations ship with `.down.sql` mirrors. Every `CREATE OR
REPLACE` of a SECURITY DEFINER function re-asserts `REVOKE ALL ... FROM PUBLIC, anon,
authenticated; GRANT EXECUTE ... TO service_role;` and the migration includes a `pg_default_acl`
/ default-privileges audit (per `2026-05-06-supabase-default-privileges-defeat-revoke-from-public`).

### Phase 1 — Server-owned canonical version (security prerequisite)
- Precondition greps (do first, no code): next migration number is 083 (`ls supabase/migrations
  | tail`); `resolve_byok_key_owner` body unchanged (mig 064:583); read the mig 064 WORM shapes
  (064:245-355) + `revocation_reason` enum (064:95-99) before authoring any RPC; no server
  `BYOK_SIDE_LETTER_VERSION` constant exists.
- **Create** TS const `BYOK_SIDE_LETTER_VERSION` in a shared server module (e.g.
  `apps/web-platform/server/byok-side-letter.ts`), value = current version string (e.g. `"1.0"`).
- **Create** SQL `current_byok_side_letter_version()` (`IMMUTABLE`, `SET search_path = public,
  pg_temp`) returning the same literal — the SECURITY DEFINER gate reads it via the
  schema-qualified `public.current_byok_side_letter_version()` call (a TS const is unreadable
  from SQL). The function is the single SQL source of truth; AC4 parity test (CI gate) prevents
  TS/SQL split-brain drift.
- **Edit** `accept/route.ts` + `delegation-acceptance-modal.tsx` + the request type: **drop the
  `sideLetterVersion` field entirely** (client no longer sends it; no validate-and-400 branch).
  The route stamps `BYOK_SIDE_LETTER_VERSION` server-side; the modal reads the current version
  from the UI resolver for display only.
- RED: test that the stored `side_letter_version` always equals the server constant regardless
  of request body.

### Phase 2 — Consent gate in resolver (mig 083)
- **Create** `083_byok_delegation_consent_gate.sql` + `.down.sql`: `CREATE OR REPLACE
  resolve_byok_key_owner` adding to the delegation `RETURN QUERY` (mig 064:614-623):
  ```sql
  AND EXISTS (
    SELECT 1 FROM public.byok_delegation_acceptances a
     WHERE a.delegation_id = bd.id
       AND a.user_id       = bd.grantee_user_id
       AND a.side_letter_version = public.current_byok_side_letter_version()
  )
  ```
  Re-assert REVOKE/GRANT; default-privileges audit.
- RED→GREEN: (a) delegation with no acceptance → resolver returns empty → `MissingByokKeyError`
  (assert distinct from `ByokDelegationRevokedError`); (b) stale-version acceptance → empty
  (fail-closed); (c) current-version acceptance → grantor key owner returned; (d) own-key user
  unaffected (resolver short-circuits before the delegation branch).

### Phase 3 — Withdrawal (mig 084 + resolver clause + route + UI)
- **Create** `084_byok_delegation_withdrawals.sql` + `.down.sql`: `byok_delegation_withdrawals`
  WORM table mirroring mig 074 (cols: `id, user_id REFERENCES users ON DELETE RESTRICT,
  delegation_id REFERENCES byok_delegations ON DELETE RESTRICT, withdrawn_at, side_letter_version,
  ip_hash, user_agent, retention_until 7y, UNIQUE(user_id, delegation_id)`), `no_update`/`no_delete`
  WORM triggers + `anonymise_byok_delegation_withdrawals(p_user_id)` Art. 17 RPC (copy 074 shape),
  RLS `user_id = auth.uid()` select/insert.
- **Create** SECURITY DEFINER `withdraw_byok_delegation_consent(p_delegation_id, p_user_id)`:
  verify caller is grantee, INSERT the withdrawal WORM row. Does **NOT** touch `byok_delegations`
  (no `revoked_at` write — that would require the 3-field WORM flip + a `consent_withdrawn` enum
  value that does not exist; see plan-review P0). Idempotent (no-op if already withdrawn).
- **Update** mig 084 also `CREATE OR REPLACE resolve_byok_key_owner` to add the second gate clause:
  ```sql
  AND NOT EXISTS (
    SELECT 1 FROM public.byok_delegation_withdrawals w
     WHERE w.delegation_id = bd.id
       AND w.user_id       = bd.grantee_user_id
       AND w.withdrawn_at > (
         SELECT max(a2.accepted_at) FROM public.byok_delegation_acceptances a2
          WHERE a2.delegation_id = bd.id AND a2.user_id = bd.grantee_user_id
            AND a2.side_letter_version = public.current_byok_side_letter_version()
       )
  )
  ```
  Re-assert REVOKE/GRANT; default-privileges audit. (Non-terminal: a later re-acceptance whose
  `accepted_at` post-dates the withdrawal reactivates the delegation.)
- **Create** `POST /api/workspace/delegations/withdraw` route (auth, CSRF, flag-gated, grantee-only).
- **Edit** account-delete cascade (`account-delete.ts`): add an explicit step calling
  `anonymise_byok_delegation_withdrawals` **before** `auth.admin.deleteUser` (the `ON DELETE
  RESTRICT` FK aborts `deleteUser` otherwise — mirror the existing mig-074 acceptances cascade step).
- **Edit** DSAR (`dsar-export.ts` + `dsar-export-allowlist.ts`): add `byok_delegation_withdrawals`
  mirroring the `byok_delegation_acceptances` allowlist entry (Art. 15).
- RED→GREEN: withdrawal blocks new leases (resolver empty); in-flight runs unaffected (grantor-revoke
  remains the kill path); re-acceptance after withdrawal reactivates; withdrawal row is WORM
  (UPDATE/DELETE rejected); cross-tenant withdraw rejected; account-delete succeeds with a withdrawal
  row present (FK-block regression).

### Phase 4 — Consent text + mig 074 header (legal)
- Invoke `legal-document-generator` to rewrite `delegation-consent-side-letter-template.md` as
  versioned in-app consent text that **embodies the Art. 26 responsibility allocation** (who
  answers DSARs, security, transparency) AND states the **Art. 6 basis**, with the grantor bound
  to the same version at delegation creation.
- **Edit** mig 074 header comment: correct "Art. 6(1)(b) contract — grantee consents" to state
  both bases coherently (do not conflate consent with contractual necessity).
- Retain DPD §2.3 addendum + AUP §5.6 (public disclosure half — different legal function).

### Phase 5 — Pending-consent UX (ADVISORY tier)
- Grantor view: explicit not-live state ("Invited — not funding until accepted"), NO spend/cap
  banner pre-acceptance. Grantee view: review-and-accept with an **inline telemetry-visibility
  acknowledgment** checkbox; add a withdraw affordance on the same surface. Modify existing
  `delegation-acceptance-modal.tsx` + settings delegation surface (no new pages).

### Phase 6 — Flag flip (CLO sign-off gate)
- After Phases 1-5 merge AND CLO confirms the consent text satisfies Art. 26, flip
  `FLAG_BYOK_DELEGATIONS` via `/soleur:flag-set-role` (Flagsmith API + Doppler mirror, automated —
  no signed document, no human checklist). Member-departure auto-revoke (from 2026-05-22 CLO list)
  confirmed already satisfied by mig 064/PR-B or added here.

## Files to Edit / Create

**Create:** `apps/web-platform/server/byok-side-letter.ts`;
`supabase/migrations/083_byok_delegation_consent_gate.sql`(+`.down.sql`);
`supabase/migrations/084_byok_delegation_withdrawals.sql`(+`.down.sql`);
`apps/web-platform/app/api/workspace/delegations/withdraw/route.ts`; test files per phase.

**Edit:** `app/api/workspace/delegations/accept/route.ts` (stamp server version);
`components/settings/delegation-acceptance-modal.tsx` (drop client version, add ack + withdraw);
`server/byok-delegation-ui-resolver.ts` (surface current version + withdrawn state);
`server/account-delete.ts` (anonymise withdrawals before deleteUser);
`server/dsar-export.ts` + `server/dsar-export-allowlist.ts` (withdrawal events);
`supabase/migrations/074_byok_delegation_acceptances.sql` (header comment only);
`knowledge-base/legal/delegation-consent-side-letter-template.md` (Art. 26 arrangement).

**Sentinel sweep (TR3):** resolver RPC `resolve_byok_key_owner` is the single chokepoint; its
only TS caller is `resolveKeyOwnerThenLease` (`agent-runner.ts:906, 2522`). Gate-in-SQL ⇒ no
call-site edits. Direct `runWithByokLease` (solo) callers MUST NOT be gated — verified the
resolver short-circuits before the delegation branch for own-key users.

## GDPR / Compliance

(Carried from CLO brainstorm assessment — VIABLE-WITH-CONDITIONS. `/soleur:gdpr-gate` to run at
deepen-plan/work per TR6; CLO leader already produced the Art-level findings below.)

- **Art. 26 (joint controllership):** in-app consent retires the signed Side Letter ONLY if the
  versioned text embodies the bilateral responsibility allocation and the grantor is bound to the
  same version (Phase 4). Unilateral click ≠ arrangement; the text content IS the arrangement.
- **Art. 6:** mig 074's "6(1)(b) — grantee consents" is self-contradictory (conflates basis with
  consent); text must state both coherently (Phase 4).
- **Art. 7(3) / Art. 17:** withdrawal path is a blocker (Phase 3); WORM withdrawal event +
  lease termination; anonymise RPC for erasure.
- **Art. 15 (DSAR):** withdrawal events join the DSAR export (Phase 3).
- **Disclosure half:** DPD §2.3 + AUP §5.6 retained.

## Observability

```yaml
liveness_signal:
  what: delegation lease-gate denials (no/stale-version consent → MissingByokKeyError)
  cadence: per agent run
  alert_target: Sentry (existing agent-runner error path)
  configured_in: apps/web-platform/server/agent-runner.ts (lease error catch)
error_reporting:
  destination: Sentry
  fail_loud: true (no silent fallback; resolver warn-path already mirrors per cq-silent-fallback-must-mirror-to-sentry)
failure_modes:
  - {mode: no-consent lease attempt, detection: MissingByokKeyError in agent-runner, alert_route: Sentry}
  - {mode: stale-version (post-bump) lease attempt, detection: resolver returns empty + structured log, alert_route: Sentry}
  - {mode: consent withdrawn, detection: withdraw RPC writes withdrawal row + revoked_at + structured log, alert_route: Sentry breadcrumb}
  - {mode: cross-tenant withdraw attempt, detection: grantee-check rejection, alert_route: Sentry (Art. 33 sibling #4364)}
logs:
  where: pino structured logs in accept/withdraw routes + byok-resolver warn path
  retention: existing platform log retention
discoverability_test:
  command: "supabase MCP query: SELECT count(*) FROM byok_delegation_acceptances WHERE side_letter_version = current_byok_side_letter_version(); plus Sentry search issue=MissingByokKeyError"
  expected_output: "acceptance count matches active delegations; zero unexpected MissingByokKeyError spikes"
```

## Infrastructure (IaC)

No new infrastructure (no server, service, cron, vendor account, DNS, cert, or firewall rule).
Pure Supabase-migration + app-code change against already-provisioned surfaces. The flag flip is
automated through the existing `/soleur:flag-set-role` skill (Flagsmith API + Doppler mirror).
Phase 2.8 gate: reviewed, no new infra surface (see `iac-routing-ack` at top of file).

## Domain Review

**Domains relevant:** Product, Engineering, Legal (carried forward from brainstorm `## Domain Assessments`).

### Engineering (CTO)
**Status:** reviewed. **Assessment:** gate-in-SQL preserves TOCTOU; withdrawal as separate WORM
table reusing the 60s grace; server-owned canonical version is a HIGH-risk prerequisite. ~2-3 PRs.

### Legal (CLO)
**Status:** reviewed. **Assessment:** VIABLE-WITH-CONDITIONS — gate fix + withdrawal path are the
load-bearing blockers; consent text must carry the Art. 26 arrangement; mig 074 header correction;
retain DPD/AUP.

### Product/UX Gate
**Tier:** advisory. **Decision:** reviewed (carry-forward). **Agents invoked:** cpo (brainstorm carry-forward).
**Skipped specialists:** ux-design-lead (small UI delta — modifies existing `delegation-acceptance-modal.tsx`
+ settings surface, no new pages; wireframes deferred per brainstorm). **Pencil available:** N/A.
**CPO sign-off:** required at plan time (single-user-incident threshold) before `/work` — CPO assessed
Product in brainstorm Phase 0.5 (carry-forward); confirm before `/work`.

#### Findings
CPO: enforcement is v1-now (closes a live joint-controllership exposure); withdrawal is a hard
prerequisite before the flag targets anyone beyond dogfood; pending-state must be visually distinct
from active; inline telemetry acknowledgment in the accept action.

## Open Code-Review Overlap

None. Checked open `code-review` issues against `byok-resolver`, `064_byok_delegations`,
`074_byok_delegation_acceptances`, `delegations/accept`, `byok-delegation-ui-resolver` — zero matches.

## Acceptance Criteria

### Pre-merge (PR)
- AC1: A delegation with no current-version acceptance does NOT lease the grantor's key — resolver
  returns empty, agent-runner raises `MissingByokKeyError` (test asserts distinct from `ByokDelegationRevokedError`).
- AC2: A stale-version acceptance (version ≠ canonical) fail-closes (resolver empty).
- AC3: The accept request carries no `sideLetterVersion` field; the route stamps `BYOK_SIDE_LETTER_VERSION`
  server-side; the stored `side_letter_version` always equals the server constant regardless of body (test).
- AC4: TS `BYOK_SIDE_LETTER_VERSION` === SQL `current_byok_side_letter_version()` — parity test wired as a
  CI gate (fails the build, not just the suite).
- AC5: Withdrawal writes a WORM row and blocks new leases (resolver returns empty); it does NOT set
  `revoked_at`; in-flight runs are unaffected (grantor-revoke remains the kill path); a re-acceptance whose
  `accepted_at` post-dates the withdrawal reactivates; withdrawal row is WORM (UPDATE/DELETE rejected);
  cross-tenant withdraw rejected.
- AC6: Own-key (solo) users are unaffected — resolver short-circuits before the delegation branch (test).
- AC7: account-delete anonymises `byok_delegation_withdrawals` **before** `deleteUser` and succeeds with a
  withdrawal row present (FK-block regression test); DSAR export includes withdrawal events.
- AC8: mig 083/084 re-assert REVOKE/GRANT; `pg_default_acl` audit returns no widened EXECUTE.
- AC9: mig 074 header states Art. 6 + Art. 26 coherently (no "6(1)(b) — grantee consents" conflation).

### Post-merge
- AC10: CLO confirms the consent text satisfies Art. 26 (sign-off recorded on the issue).
  Automation: not feasible — CLO legal determination requires human judgment.
- AC11: `FLAG_BYOK_DELEGATIONS` flipped via `/soleur:flag-set-role` (verify Flagsmith + Doppler mirror) — `Ref #4625`, then `gh issue close 4625`. Automation: feasible via flag tooling.

## Risks & Mitigations

- **Withdrawal design (resolved at plan-review):** gate-side `NOT EXISTS(withdrawal)` chosen over
  setting `revoked_at` — the latter is a P0 (WORM 3-field flip + missing `consent_withdrawn` enum value).
  Gate-side is non-terminal and avoids new grace logic. Consequence to confirm at deepen-plan: in-flight
  runs are NOT killed on withdrawal (only new leases blocked); the USD/day cap + grantor-revoke bound the
  in-flight billing exposure. Verify the `NOT EXISTS`/`max(accepted_at)` clause against the WORM/MVCC
  semantics (data-integrity-guardian).
- **Version bump mid-run** deactivates new leases but does not abort in-flight (grace keyed on
  revoked_at, not version). Acceptable — version bumps are rare/deliberate; run completes, next run re-consents.
- **Canonical version storage** (SQL function literal vs `byok_side_letter_versions` table) — leading
  with the function+parity-test (YAGNI); deepen-plan to confirm against precedent.

## Non-Goals
Re-consent re-prompt UX (#4628); multi-grantee fan-out; consent audit-export UI; new grace mechanism;
per-action consent scoping.

## Sharp Edges
- A plan whose `## User-Brand Impact` section is empty/placeholder fails deepen-plan Phase 4.6 — this
  one is filled.
- At single-user-incident threshold, deepen-plan (data-integrity-guardian + security-sentinel +
  architecture-strategist) is mandated and catches migration/RLS/atomicity P0s that plan-review (style)
  cannot — per `2026-05-22-plan-review-and-deepen-plan-catch-different-issue-classes.md` (same #4232 family).
