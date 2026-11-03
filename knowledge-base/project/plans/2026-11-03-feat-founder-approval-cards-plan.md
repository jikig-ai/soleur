---
title: "feat: founder approval cards (CLI and web app) and peer-reviewed CTO delegation for owner-only gates"
date: 2026-11-03
slug: founder-approval-cards
branch: feat-founder-approval-cards
issue: 12011
type: feat
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

## Overview

Give a non-technical founder a plain-words way to answer owner-only gates, with one shared record format used by the command line and the web app. The first increment covers the operator's own gates: a command-line card for the existing standing-delegation question, and a web screen that records legal acceptances from the founder's own signed-in session with an in-place email-code check. The PR for this plan references #12011 and does not close it, because four deferred follow-ups (#12020 to #12023) remain.

Source documents: brainstorm `knowledge-base/project/brainstorms/2026-11-03-founder-approval-cards-brainstorm.md`, spec `knowledge-base/project/specs/feat-founder-approval-cards/spec.md`, approved wireframes `knowledge-base/product/design/approvals/founder-approval-cards.pen` (screenshots 10 to 18).

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality (verified) | Plan response |
|---|---|---|
| Reuse the `approval_request` pattern, not its rows | `180_approval_request.sql` has the RPC, guard-trigger, RLS and grant shapes; it nulls `canonical_action` after 30 days and `anonymise_approval_request` deletes personal-workspace rows | New table `legal_acceptance`; copy the shapes; do not add it to the erasure scrub |
| "Fresh re-auth" can reuse the existing re-auth code | `server/dsar-reauth.ts` stores events in a process-local `Map`; `useOtpFlow.ts` starts a session; `EmailOtpType` has no reauthentication value and `verifyOtp` cannot consume a reauthenticate nonce | Single-use challenge stored in a table (`legal_reauth_event`), code verified server-side on a throwaway client; Phase 0 spike proves it on the dev project before any code is committed |
| Migration number follows 182 | Latest on `origin/main` is 182; 183 is claimed by an unmerged sibling worktree | Use 184, re-checked at PR time against `origin/main` |
| New ADR ordinal | Highest on `origin/main` is ADR-317 | Provisional ADR-318, re-verified by the ship ordinal gate |
| CLI has no equivalent surface | `plugins/soleur/hooks/operator-stage-approval.sh` and `scripts/lib/operator-script.sh` give a typed-yes `tty-ack`; Cursor has no question-tool mapping | Reuse the `tty-ack` label; the card degrades to plain chat questions where no question tool exists |
| `hold-gate-eval.sh` can check a web record | It supports `pr-merged` and `no-inflight-run`; unknown kinds stay on hold | Add `web-acceptance` kind; unknown or unreadable stays a hold |

## Research Insights

**Premise validation (Phase 0.6).** #12011 and #12020 to #12023 are open; PR #11289 (the web approval system) merged 2026-10-30 and is dark behind `approval-queue`; `grep legal_acceptance|legal_reauth` on `origin/main` returns nothing. The collision pre-check reported other worktrees' test runs and no open PR naming #12011.

**Property list (Phase 0.6b).**

1. A founder answers the delegation question in plain words with Yes, No or Request changes, and Enter alone never answers.
2. A legal acceptance is recorded only from the founder's own authenticated browser session, after an in-place check made just before, with the exact text kept.
3. A script can check the recorded answer by id without any channel an agent can forge.
4. At a browser-only gate the CLI keeps working on unrelated work, the hold stands, and pending cards are listed at the next session start.
5. Every record says honestly how the answer was given.

**Cut list.**

| Mechanism | Property | What covers it / why cut |
|---|---|---|
| Reuse `approval_request` rows for legal acceptances | 2 | Its 30-day text nulling and erasure scrub destroy the record; separate table |
| GitHub pointer comment as authority | 3 | Cosmetic only; a same-identity author can forge it (ADR-289) |
| Service-role read from scripts | 3 | Agent-reachable; replaced by a read-only verify endpoint token |
| Sign-out / sign-in again | 2 | Operator rejected at wireframe review; in-place email code instead |
| TOTP, passkey, SMS | 2 | New enrolment surface and plan cost; deferred |
| Peer review, notifications, history, customer channel, RF0 amendment | n/a | Deferred to #12021, #12022, #12020, #12023 |

**Key file facts** (paths verified by the implementation research):

- `apps/web-platform/supabase/migrations/180_approval_request.sql`: no top-level transaction (runner wraps), precondition `DO` block, `REVOKE ALL ... FROM PUBLIC, anon, authenticated, service_role` then `GRANT SELECT ... TO authenticated`, RESTRICTIVE jti-deny policy, `SECURITY DEFINER` guard with `SET search_path = public, pg_temp` gated on a GUC, `decide_approval` as the actor-from-`auth.uid()` pattern.
- `182_git_data_erasure_pending.down.sql:4-10`: a down file that refuses while rows exist; copy for the legal table.
- `apps/web-platform/supabase/verify/*.sql`: catalog sentinels run on deploy by `scripts/run-verify.sh`; fail on any `bad > 0`.
- `apps/web-platform/server/dsar-reauth.ts`: burn-first single-use consume, 5-minute TTL, user binding; the semantics move into a table.
- `apps/web-platform/lib/supabase/tenant.ts` `mintFounderJwt` (l.271): the server can mint a founder session with the same claims as a human login, so JWT-claim freshness is not evidence; reject the `soleur-runtime` audience.
- `apps/web-platform/lib/internal-auth.ts` and `app/api/internal/cohort/route.ts`: fail-closed bearer with `timingSafeEqual`; the model for the verify endpoint. Do not reuse `INNGEST_MANUAL_TRIGGER_SECRET` (it dispatches cron).
- `plugins/soleur/scripts/delegation-verify.sh` (author checks l.491-497, `fail_invalid`/`fail_unv` l.62-64) and `plugins/soleur/skills/ship/scripts/hold-gate-eval.sh` (`known_kind` l.111, `eval_gate` l.152-163).
- Tests: bash suites are globbed by `scripts/test-all.sh` (`plugins/soleur/test/*.test.sh`, `plugins/soleur/scripts/*.test.sh`); web app uses vitest (`apps/web-platform/test/approval/*`).
- `apps/web-platform/lib/approval-copy.ts:128`: copy under a CLO sign-off gate (`PROVISIONAL: true`, test-enforced).

**Institutional learnings applied:** ADR-289 (delegation is not separation of duties), ADR-309 (bind approvals to a hash of the full snapshot), ADR-249 (typed-yes needs a TTY), `2026-11-03-brainstorm-verify-who-can-use-the-mechanism-before-briefing-design.md` (verify who can use a mechanism).

**Functional overlap check.** Registries reachable; the closest community artifacts (review-agent-governance, emilia-guard, human-gate) cover gating and audit trails for developers; none is a plain-words founder card or checks standing delegation. Nothing to adopt.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "A founder-facing approval card (web app and CLI): plain-words summary of what is being approved and the consequence, the exact text that will be recorded, and Yes / No / Request changes." [issue #12011] | PR-A (CLI card), PR-C (web screen) | mapped |
| 2 | "The record keeps the text shown, identity, timestamp, choice and requested edit, and links the CLO/CTO reasoning in plain language." [issue #12011] | PR-B (`legal_acceptance` record) | mapped |
| 3 | "Which acts may ever be delegated, by class: reserved to the founder by default for legal, irreversible and money-moving acts" [issue #12011] | Phase A2 (`method` label and reserved classes in the card contract) | mapped |
| 4 | "Independent peer review of delegated production acts" [issue #12011] | — | descoped — justification: the CTO ruled a same-model reviewer is advisory only and the operator chose a first increment without it; tracked in #12021 |
| 5 | "One approval contract, two renderings." [issue #12011] | PR-A, PR-B, PR-C share the record contract | mapped |
| 6 | "how identity is established for a CLI answer" [issue #12011] | PR-A (`method` label) and PR-D (verify endpoint) | mapped |
| 7 | "behaviour in headless and cloud sessions where no person can answer (the hold stands, and the same card is queued for the next attached session or the web app)" [issue #12011] | Phase A3 (pending-card listing) | mapped |
| 8 | "the card in the Command Center, notification when a card is waiting, and the founder's history of approvals." [issue #12011] | Card in PR-C; notification and history descoped | descoped — justification: notifications and history are #12022 |
| 9 | "UX tested with a non-technical, non-legal founder on both surfaces, including the CLI." [issue #12011] | Acceptance criterion AC20 | mapped |
| 10 | "Interaction with `hr-technical-fork-is-not-an-operator-question`, `hr-menu-option-ack-not-prod-write-auth` and the existing delegation verifier." [issue #12011] | Phase A2, D3 | mapped |
| 11 | "Add legal acceptances via the web app" [operator, first-slice choice 2026-11-03] | PR-B, PR-C, PR-D | mapped |
| 12 | "Operator first, customers later" [operator, approach choice 2026-11-03] | Non-goal; #12020 | mapped |
| 13 | "Instead of asking to sign in again, can we ask them to enter their password again or enter a code in a popup" [operator, wireframe review 2026-11-03] | PR-C `legal-reauth-dialog` and `legal_reauth_event` | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| CLI approval card wording contract (PR-A) | asks 1, 5 | asked |
| `pending-cards.sh` session-start listing (PR-A) | asks 7 | asked |
| `legal_acceptance` table, RPC, guard, chain (PR-B) | asks 2, 11 | asked |
| `legal_reauth_event` table and reauth route (PR-C) | asks 13 | asked |
| Web legal-acceptance screen and states (PR-C) | asks 1, 11 | asked |
| Verify endpoint and read-only token (PR-D) | asks 6 | asked |
| `Gate: web-acceptance` kind in `hold-gate-eval.sh` (PR-D) | asks 6, 10 | asked |
| `web-session` author arm in `delegation-verify.sh` (PR-D) | asks 10 | asked |
| ADR-318 and C4 edit | — | inferred — justification: the decision changes a tenancy-adjacent store and a trust boundary, so `wg-architecture-decision-is-a-plan-deliverable` requires the record |
| Art. 30 entry, LIA, privacy-document updates | — | inferred — justification: the CLO advisory says storing founder acceptances needs a new processing-activity entry and a legal basis before use outside a canary |
| Hash chain across rows | — | inferred — justification: the CLO requires tamper evidence for an accountability record |
| Terraform `doppler_secret` for the verify token | — | inferred — justification: `hr-all-infrastructure-provisioning-servers` forbids hand-set secrets |

### Split Assessment

- Subsystems touched: 5 — `apps/web-platform`, `plugins/soleur`, `knowledge-base`, `scripts`, `.github`-free infra under `apps/web-platform/infra`
- Planned files: about 38 | Estimated changed lines: about 2600
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: split — four PRs at these seams: PR-A CLI card and pending list (plugin only); PR-B database record, ADR and C4, legal docs (dark); PR-C web screens and in-place check (behind `approval-queue`); PR-D verify endpoint, gate kind, `web-session` author arm, Terraform secret. This branch and draft PR #12012 carry PR-A; PR-B to PR-D open as stacked follow-ups from `main` once the previous one merges.

## Open Code-Review Overlap

None. Seven planned edit paths were searched against open `code-review` issues; no body names any of them.

## Architecture Decision (ADR/C4)

### ADR

Create ADR-318 (provisional ordinal; re-verify against `origin/main` at ship): "Legal acceptances are recorded in a separate write-once table from the founder's authenticated session, checked by id through a read-only verify endpoint." It records the CTO rulings (separate table, hash chain, `method` label, in-place single-use challenge, verify endpoint) and `## Alternatives Considered`: reuse `approval_request` rows (rejected: 30-day text nulling and erasure scrub), GitHub comment as authority (rejected: forgeable by the same identity, ADR-289), JWT-claim freshness (rejected: `mintFounderJwt` mints the same claims), signed file (rejected: key custody the agent can reach). Amend ADR-309 `## Decision` with a one-line pointer to ADR-318 for the legal class. Status `adopting` until PR-D ships and the first real acceptance has run.

### C4 views

All three model files (`model.c4`, `views.c4`, `spec.c4`) are read in Phase B4 before the edit. Checked so far from `model.c4`: `approvalStore` exists (lines 329-331, ADR-309) but covers agent tool calls only. Changes: add `legalAcceptanceStore = database "Legal Acceptances"` (Supabase, `legal_acceptance` and `legal_reauth_event`); add the edge from the web app container to it; add an edge from the plugin's CLI hold-gate evaluator to the verify endpoint; add the verify endpoint as a relationship on the web app; add the founder-to-approval-screen relationship; add the `view ... include` line in `views.c4` so it renders; fix any description the change falsifies. Validate with `apps/web-platform/test/c4-code-syntax.test.ts`, `c4-render.test.ts`, and `plugins/soleur/test/c4-count-parity.test.sh`.

### Sequencing

ADR and C4 ship in PR-B with the table they describe, in the same PR, not a follow-up.

## Infrastructure (IaC)

### Terraform changes

One new secret: the read-only verify-endpoint token. Add `apps/web-platform/infra/legal-acceptance-verify-token.tf` with a `random_password` and a `doppler_secret` for `LEGAL_ACCEPTANCE_VERIFY_TOKEN` in the `prd` config, following `anthropic-ci-key.tf:21`; document it in `apps/web-platform/.env.example` as a Doppler-only value. No new server, unit, DNS record or vendor account.

### Apply path

Not a host change. The existing Terraform pipeline applies the `doppler_secret`; the web app reads it at its next deploy. No downtime.

### Host fan-out

Not applicable: no `terraform_data` SSH provisioner is added or edited.

### Distinctness / drift safeguards

`dev` and `prd` use distinct tokens (`hr-dev-prd-distinct-supabase-projects` analogue): the token is generated per config and a precondition asserts the two values differ. The value lands in Terraform state; the state backend is encrypted.

### Vendor-tier reality check

Supabase email OTP uses the project's existing auth email path; `otp_expiry` is 3600 seconds in `supabase/config.toml`, so the short code lifetime is enforced by `legal_reauth_event` timestamps, not by the vendor.

## Observability

```yaml
liveness_signal:
  what: "Sentry feature tag legal-acceptance op events (reported by reportLegalAcceptanceOp) plus the pending-cards self-check"
  cadence: "per request / per session start"
  alert_target: "Sentry issue alert routed to the existing approval alert recipients"
  configured_in: "apps/web-platform/server/legal-acceptance/ops.ts and apps/web-platform/infra/sentry (alert rule added in PR-C)"

error_reporting:
  destination: "Sentry web-platform via SENTRY_DSN, feature=legal-acceptance"
  fail_loud: "verify endpoint returns 503 when the token is unset and 401 on a wrong token; the hold evaluator keeps the hold and prints SOLEUR_HOLD_UNEVALUABLE"

failure_modes:
  - mode: "decide RPC rejected (stale hash, expired challenge, wrong user)"
    detection: "reportLegalAcceptanceOp emits op=decide_rejected with a reason tag"
    alert_route: "Sentry issue alert, feature:legal-acceptance"
  - mode: "email code send or verify fails"
    detection: "reportLegalAcceptanceOp emits op=reauth_failed with provider error class"
    alert_route: "Sentry issue alert, feature:legal-acceptance"
  - mode: "hash chain break (row's prev hash does not match)"
    detection: "verify function returns chain_ok=false and the endpoint reports op=chain_break"
    alert_route: "Sentry issue alert, severity page"
  - mode: "hold evaluator cannot reach the verify endpoint"
    detection: "hold-gate-eval.sh prints SOLEUR_HOLD_UNEVALUABLE reason=verify-unreachable and keeps the hold"
    alert_route: "visible in the session and PR body; no silent discharge"

logs:
  where: "Sentry events and Better Stack SOLEUR_* markers mirrored from stdout"
  retention: "Sentry default 90 days; legal_acceptance rows themselves are retained per the Art. 30 entry"

discoverability_test:
  command: "bash plugins/soleur/scripts/pending-cards.sh --self-check"
  expected_output: "pending-cards: ok"
```

## Encryption Posture

```yaml
at_rest:
  - store: "Supabase Postgres, tables legal_acceptance and legal_reauth_event (prd project)"
    mechanism: "provider-managed:supabase-postgres-aes256"
    evidence: "scripts/encryption-posture-ledger.json entry for the Supabase prd store (mechanism string provider-managed:supabase-postgres-aes256)"
    defends_against: "theft of a storage volume or backup without database credentials"
    does_not_defend: "a holder of the service-role key, a database role with SELECT, or an injection through application code; the verbatim text is plaintext to the database"
    disclosed_as: "Art. 30 entry added in PR-B and the Data Protection Disclosure"
    live_verification: "lint-encryption-posture.py run in CI resolves the ledger entry"
in_transit:
  - connection: "browser to web app, web app to Supabase, hold evaluator script to verify endpoint"
    tls: "TLS 1.2+ on all three"
    cert_verification: on
    does_not_defend: "a compromised client machine or an agent that already holds the founder's browser session"
    disclosed_as: "Data Protection Disclosure transport section"
```

## User-Brand Impact

- **If this lands broken, the user experiences:** a founder card that records a Yes they did not intend, or fails to record the Yes they gave so a legal or production step silently stalls.
- **If this leaks, the user's workflow is exposed via:** a forged or replayed acceptance row that lets an agent act as the founder, or the verbatim legal text and the founder's identity read by someone with service-role access.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** one forged or mis-recorded legal acceptance ends trust in "the founder decides", so the tier is the highest rather than an aggregate pattern.

CPO sign-off is required before `soleur:work` begins (carried from the brainstorm). `soleur:engineering:review:user-impact-reviewer` runs at review time.

## Domain Review

**Domains relevant:** Product, Engineering, Legal

### Product (CPO)

**Status:** reviewed
**Assessment:** The web card and durable record are shipped but dark; the genuinely new parts are the CLI card, Request changes, legal-acceptance class and peer review. Build the record contract first, then the CLI rendering. Roadmap row CP2 is stale ("Not started") and #12011 has no row; correct CP2 and place #12011 as a CP2 child or Phase 4 row (founder's call). Reflex-clicking is the main UX risk: consequence first, no default.

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Separate `legal_acceptance` table, verify endpoint, `method` label, single-use `legal_reauth_event` challenge with email code as default; same-model review advisory only; four-PR sequence. Residual: anyone holding the service-role key can still mint a session.

### Legal (CLO)

**Status:** reviewed
**Assessment:** A web click from the founder's authenticated session is acceptable evidence if it carries the minimum fields and integrity properties; CLI is not unless made outside the agent's reach. Needs its own retention, an Art. 30 entry or PA-38 amendment, a standalone LIA and erasure carve-out. Wording must avoid "verified", "reviewed", "legally binding", "audit-ready", "compliant". Not legal advice; counsel review before any customer-facing use.

### Product/UX Gate

**Tier:** blocking
**Decision:** reviewed
**Agents invoked:** soleur:product:cpo, soleur:product:design:ux-design-lead
**Skipped specialists:** none
**Pencil available:** yes

#### Findings

Wireframes were produced at brainstorm time and approved by the operator on 2026-11-03: `knowledge-base/product/design/approvals/founder-approval-cards.pen`, screenshots 10 to 18. The brainstorm carry-forward does not replace page design here because the wireframes are the page design. The spec-flow analysis is run in the plan-review step.

## Implementation Phases

### PR-A — CLI approval card and pending list (this branch, PR #12012)

**Phase A0 — Spike.** Prove on the dev Supabase project that an email code can be sent and verified for an existing user on a throwaway client without touching the user's session (`signInWithOtp` with `shouldCreateUser: false`, then `verifyOtp({type:'email'})` on a separate client). Record the call shape and the result in this plan's Research Insights. If it fails, fall back to the CTO's second option and stop for a ruling before PR-C.

**Phase A1 — Card wording contract.** Create `plugins/soleur/skills/brainstorm-techniques/references/approval-card.md`: plain-words structure (what will happen in business terms, then the three choices typed in words), no default on Enter, the three messages from wireframe frame 18 (delegation question, browser hold, no approver set up), and the `method` vocabulary (`tty-ack`, `web-session`). Link it from `standing-delegation.md` in the epic-start section.

**Phase A2 — Method label in the delegation record.** Extend `delegation-verify.sh render` with an optional `--method tty-ack` argument that writes a `Method:` line into the rendered comment, and make `verify` accept (never require) a valid `Method:` value, rejecting unknown values as invalid. Keep every existing fixture valid.

**Phase A3 — Pending-cards listing.** Create `plugins/soleur/scripts/pending-cards.sh`: lists open `action-required` issues carrying the machine marker `Standing-delegation epic: #N` and, once PR-D lands, pending legal acceptances; `--self-check` prints `pending-cards: ok` without network. Hook the listing into the `/go` Step 0 session-start output and `session-rules-loader.sh` context line.

### PR-B — Database record, ADR, C4, legal documents (dark)

**Phase B1 — Migration.** `184_legal_acceptance.sql` and `.down.sql` (refusing while rows exist), plus `verify/184_legal_acceptance.sql`. Tables: `legal_acceptance` (id, founder id, text, text_hash, version, choice, requested_edit, supersedes_id, method, reauth_method, reauth_at, session_id, surface, prev_hash, row_hash, created_at) and `legal_reauth_event`. RPCs: `request_legal_acceptance` (service_role), `record_legal_acceptance` (`authenticated`, actor from `auth.uid()`, rejects a runtime-audience token, consumes the reauth event atomically), `verify_legal_acceptance` (read-only). Guard trigger GUC-gated, write-once, forward-only status, no `ON DELETE SET NULL` on the founder id, not part of `anonymise_approval_request`. Precondition `DO` block and `search_path = public, pg_temp` on every `SECURITY DEFINER` function.

**Phase B2 — Migration tests.** `apps/web-platform/test/legal-acceptance/migration-184-legal-acceptance.test.ts` (static shape, mirrors the 180 test) and a behavioural tenant-isolation test.

**Phase B3 — Legal documents.** New Art. 30 entry (or PA-38 amendment), standalone LIA, Privacy Policy / Data Protection Disclosure / GDPR Policy updates if new data is collected, `compliance-posture.md` row, retention and erasure carve-out wording. Gate: `soleur:gdpr-gate` against the migration.

**Phase B4 — ADR and C4.** ADR-318, the ADR-309 pointer, the `.c4` edits (after reading all three files), validation tests.

### PR-C — Web screens and in-place check (behind `approval-queue`)

**Phase C1 — Service layer.** `apps/web-platform/server/legal-acceptance/` (service, reauth, canonical text and hashing, ops reporter); the reauth route `app/api/legal-acceptance/[id]/reauth/route.ts` (send code, verify code; email from `getUser()` only; 5-minute window; rate limit; origin/CSRF guards from the existing privacy reauth route) and decide route `app/api/legal-acceptance/[id]/decide/route.ts`.

**Phase C2 — UI.** `app/(dashboard)/dashboard/approvals/legal/[id]/page.tsx`, `components/approvals/legal-acceptance-card.tsx`, `legal-reauth-dialog.tsx`, `lib/legal-acceptance-state.ts`, `lib/legal-acceptance-copy.ts` under the same CLO sign-off gate as `approval-copy.ts`. Use the Button primitives. Frames 10 to 17.

**Phase C3 — Alert and expiry.** Sentry issue alert in `apps/web-platform/infra/sentry`; extend `cron-approval-expiry.ts` to expire stale `legal_reauth_event` rows (an edit to an existing function, not a new autonomous task).

### PR-D — Verify endpoint and gate kind

**Phase D1 — Endpoint.** `app/api/internal/legal-acceptance/[id]/route.ts` modelled on `lib/internal-auth.ts` (503 when the token is unset, length-guarded `timingSafeEqual`), returning text hash, choice, founder id, method, reauth method, timestamps, chain head; read-only token `LEGAL_ACCEPTANCE_VERIFY_TOKEN` via the Terraform `doppler_secret`.

**Phase D2 — Gate kind.** `hold-gate-eval.sh`: add `web-acceptance <id> <text-hash>` to `known_kind` and `eval_gate`; recompute the hash from the in-repo text; unknown kind, unreachable endpoint, mismatched hash, `declined`, `changes_requested` or an unreadable response all keep the hold.

**Phase D3 — Author arm.** `delegation-verify.sh`: a `web-session` author arm that checks the endpoint instead of GitHub comment authorship, preserving the existing rejection of bot and App authors.

## Guard Contract

### Guard 1 — web-acceptance hold gate (`hold-gate-eval.sh`)

**Property.** A hold backed by a web acceptance is discharged only when the endpoint confirms an `accepted` answer, by the recorded founder, for exactly the text hash named in the plan, inside its reauth window; every other state keeps the hold.

**Assembly.** The gate quantifies over `known_kind`, `eval_gate`, the grammar comment, the plan parser for `Gate:` lines, the HTTP client call, and the three outcomes of every hold (`discharged`, `held`, `unevaluable`). All must flow through one function that returns `held` on any non-success; the `Operator-reserved:` path is a second chokepoint and must remain untouched.

**Mutation matrix.**

| # | Mutation | Must go RED because |
|---|----------|---------------------|
| 1 | Treat HTTP 5xx or a timeout as discharged | unreadable must hold |
| 2 | Accept `changes_requested` or `declined` as discharged | only `accepted` discharges |
| 3 | Skip the text-hash comparison | a revised text must not inherit an old acceptance |
| 4 | Accept a second matching `Gate:` line after a failing first one | every line must hold, not the first |
| 5 | Make `known_kind` list `web-acceptance` but leave `eval_gate` without the case (dispatch emptied) | a gate that reports "0 evaluated" and exits 0 is vacuous |
| 6 | Move the hash recompute after the discharge decision (reorder) | order of verify before discharge |
| 7 | Convert an `Operator-reserved:` hold to a gate | reserved holds always stand |

**Harness rows.** Break the harness: delete the stub-endpoint server from the suite so every case sees "unreachable" — the suite must fail rather than pass on all-held. Must-PASS inputs other than the canonical: an acceptance whose text contains the characters `|`, `"` and a trailing newline, and a plan with two holds where only the second is a web acceptance.

**Anchor.** The stored text hash in the plan is compared with the endpoint; one diff could edit both the plan hash and the text. The independent anchor is the endpoint's hash chain head recorded in the PR body at ship time and checked by the ship hold evaluation, so changing both in one commit still requires the recorded founder row to exist for that hash.

### Guard 2 — `web-session` author arm and `Method:` line (`delegation-verify.sh`)

**Property.** A delegation counts as valid only when the author arm that applies proves the recorded person, and no rendered `Method:` value can raise the strength of a record above what its author arm proved.

**Assembly.** `render`, `verify`, the author checks (User type, no app, admin permission), the new `web-session` arm, and the `Method:` parser all feed one `fail_invalid`/`fail_unv` exit path.

**Mutation matrix.**

| # | Mutation | Must go RED because |
|---|----------|---------------------|
| 1 | Accept `Method: web-session` in a GitHub comment with no endpoint proof | the label alone proves nothing |
| 2 | Accept an unknown `Method:` value | unknown values are invalid |
| 3 | Let a bot or App author pass through the new arm | existing rejection must hold |
| 4 | Make the new arm return success on an empty endpoint response | empty is unverifiable |
| 5 | Remove the dispatch to the new arm (arm never called) | a guard that checks nothing exits 0 |

**Harness rows.** Remove the `gh-stub.sh` response for the admin-permission call — the suite must fail. Must-PASS input differing from canonical: a delegation with no `Method:` line at all (legacy).

**Anchor.** The delegation comment is re-verified immediately before every delegated act (ADR-289); the endpoint, not the comment, carries the web proof.

### Guard 3 — write-once record trigger (`legal_acceptance`)

**Property.** Once a decision row exists no column of it can change and no row can be deleted, and every row's `prev_hash` equals the previous row's `row_hash`.

**Assembly.** The guard trigger (`BEFORE INSERT OR UPDATE OR DELETE`), every RPC that sets the GUC, `anonymise_approval_request` (must not touch the table), and the founder-erasure path.

**Mutation matrix.**

| # | Mutation | Must go RED because |
|---|----------|---------------------|
| 1 | Remove `DELETE` from the trigger events | deletion must be blocked |
| 2 | Set the GUC in the verify function | read RPC must not open the write door |
| 3 | Add the table to the erasure scrub | erasure must not destroy the record |
| 4 | Compute `row_hash` without `text` | a changed text must change the hash |
| 5 | Insert a row with the wrong `prev_hash` | chain break must be rejected |

**Harness rows.** The static shape test fails if the trigger statement is removed from the SQL. Must-PASS input: a second row for a new text version with `supersedes_id` set.

**Anchor.** Chain head is anchored externally (CLO to choose where; recorded in ADR-318) so a database-level rewrite of every row is still detectable.

## Files to Create

- `apps/web-platform/supabase/migrations/184_legal_acceptance.sql`
- `apps/web-platform/supabase/migrations/184_legal_acceptance.down.sql`
- `apps/web-platform/supabase/verify/184_legal_acceptance.sql`
- `apps/web-platform/server/legal-acceptance/service.ts`
- `apps/web-platform/server/legal-acceptance/reauth.ts`
- `apps/web-platform/server/legal-acceptance/canonical.ts`
- `apps/web-platform/server/legal-acceptance/verify.ts`
- `apps/web-platform/server/legal-acceptance/ops.ts`
- `apps/web-platform/app/api/legal-acceptance/[id]/reauth/route.ts`
- `apps/web-platform/app/api/legal-acceptance/[id]/decide/route.ts`
- `apps/web-platform/app/api/internal/legal-acceptance/[id]/route.ts`
- `apps/web-platform/app/(dashboard)/dashboard/approvals/legal/[id]/page.tsx`
- `apps/web-platform/components/approvals/legal-acceptance-card.tsx`
- `apps/web-platform/components/approvals/legal-reauth-dialog.tsx`
- `apps/web-platform/lib/legal-acceptance-state.ts`
- `apps/web-platform/lib/legal-acceptance-copy.ts`
- `apps/web-platform/test/legal-acceptance/migration-184-legal-acceptance.test.ts`
- `apps/web-platform/test/legal-acceptance/service.test.ts`
- `apps/web-platform/test/legal-acceptance/routes.test.ts`
- `apps/web-platform/test/legal-acceptance/card.test.tsx`
- `apps/web-platform/infra/legal-acceptance-verify-token.tf`
- `plugins/soleur/scripts/pending-cards.sh`
- `plugins/soleur/scripts/pending-cards.test.sh`
- `plugins/soleur/skills/brainstorm-techniques/references/approval-card.md`
- `plugins/soleur/test/fixtures/standing-delegation/delegation-method-tty-ack.md`
- `plugins/soleur/test/fixtures/standing-delegation/delegation-method-unknown.md`
- `knowledge-base/engineering/architecture/decisions/ADR-318-legal-acceptance-record.md`
- `knowledge-base/legal/legitimate-interest-assessments/2026-11-founder-legal-acceptance-lia.md`

## Files to Edit

- `plugins/soleur/scripts/delegation-verify.sh`
- `plugins/soleur/scripts/delegation-verify.test.sh`
- `plugins/soleur/skills/ship/scripts/hold-gate-eval.sh`
- `plugins/soleur/test/hold-gate-eval.test.sh`
- `plugins/soleur/skills/brainstorm-techniques/references/standing-delegation.md`
- `plugins/soleur/commands/go.md` (Step 0 pending-cards line)
- `.claude/hooks/session-rules-loader.sh` (pending-cards context line)
- `apps/web-platform/server/inngest/functions/cron-approval-expiry.ts`
- `apps/web-platform/lib/approval-card-state.ts`
- `apps/web-platform/components/approvals/approval-landing.tsx`
- `apps/web-platform/.env.example`
- `knowledge-base/engineering/architecture/diagrams/model.c4`
- `knowledge-base/engineering/architecture/diagrams/views.c4`
- `knowledge-base/engineering/architecture/decisions/ADR-309-durable-action-bound-approval-requests.md`
- `knowledge-base/legal/article-30-register.md`
- `knowledge-base/legal/compliance-posture.md`
- `knowledge-base/product/roadmap.md` (CP2 status and #12011 row, founder's call on placement)

## Acceptance Criteria

### Pre-merge (per PR)

- [ ] AC1 (PR-A): the CLI card text follows `approval-card.md`; `Enter` alone never answers; `y` is refused.
- [ ] AC2 (PR-A): `delegation-verify.sh render --method tty-ack` writes a `Method:` line; `verify` accepts a record with and without it and rejects an unknown value; all existing fixtures still pass.
- [ ] AC3 (PR-A): `pending-cards.sh --self-check` prints `pending-cards: ok`; a headless run lists pending items without prompting.
- [ ] AC4 (PR-B): the migration applies cleanly on the dev project; the down file refuses while rows exist; `verify/184` reports `bad = 0`.
- [ ] AC5 (PR-B): the guard rejects UPDATE and DELETE; a wrong `prev_hash` insert is rejected; `anonymise_approval_request` leaves the table untouched.
- [ ] AC6 (PR-B): ADR-318 exists with `## Alternatives Considered`; the `.c4` edits render and the three C4 tests pass; `c4-count-parity` is green.
- [ ] AC7 (PR-B): the Art. 30 entry, LIA and compliance-posture row are in the same PR; `soleur:gdpr-gate` output is attached to the PR.
- [ ] AC8 (PR-C): Yes is disabled until the text is scrolled and confirmed; none of the three choices is pre-selected; Request changes requires text.
- [ ] AC9 (PR-C): the email code is single-use, valid for at most 5 minutes, bound to the user, and consumed atomically by `record_legal_acceptance`; a second use fails.
- [ ] AC10 (PR-C): a runtime-audience token is rejected by the reauth and decide routes.
- [ ] AC11 (PR-C): the card shows exactly one of the three "Confirmed with ..." labels and never "verified", "reviewed" or "legally binding" (a test greps the copy file).
- [ ] AC12 (PR-C): creation is gated by `approval-queue`; with the flag off the page still renders existing rows.
- [ ] AC13 (PR-D): the endpoint returns 503 when the token is unset, 401 on a wrong token, and the row facts on a right one.
- [ ] AC14 (PR-D): every mutation row of Guards 1 to 3 is driven RED by a test, and the harness rows fail the suite when the stub is removed.
- [ ] AC15 (PR-D): `LEGAL_ACCEPTANCE_VERIFY_TOKEN` is created by Terraform, differs between `dev` and `prd`, and is documented in `.env.example`.
- [ ] AC16: wireframe copy and implemented copy match frames 10 to 18 except the documented open wording items.

### Post-merge (follow-through)

- [ ] AC17: ADR-318 status moves from `adopting` to `accepted` after the first real acceptance has run end to end.
- [ ] AC18: the CLO enabling gate is cleared and counsel has reviewed the customer-facing wording before `approval-queue` is turned on beyond the canary.
- [ ] AC19: roadmap CP2 status corrected and #12011 placed.
- [ ] AC20: a non-technical, non-legal founder completes one card on the CLI and one on the web without help (recorded as a comment on #12011).

## Test Scenarios

1. CLI card: typed `yes` records `Method: tty-ack`; bare Enter and `y` do nothing; `changes` collects text and records nothing granting.
2. Web, happy path: scroll, tick, Yes, send code, enter code, row `accepted` with `reauth_method=email_code`.
3. Web, wrong code, then expired code: row stays `pending`, no consumption of a good code.
4. Web, Request changes: row `changes_requested`; the CLI shows "waiting for revision"; a revised text creates a new row with `supersedes_id`.
5. Replay: the same challenge used twice; a challenge from another user; a challenge older than 5 minutes — all rejected.
6. Hold gate: accepted + matching hash discharges; declined, changes_requested, hash mismatch, endpoint down and malformed response all keep the hold.
7. Founder erasure: the legal rows survive and the scrub leaves the table untouched.
8. Chain: tampering with one stored text breaks `chain_ok`; the endpoint reports it.
9. No web account (CLI-only user): the CLI prints the "no approver set up" message and does nothing.
10. Headless session: the hold stands and `pending-cards.sh` lists the item at the next attached start.

## Dependencies & Risks

- **Supabase reauth nonce.** `verifyOtp` may not accept a reauthenticate nonce; Phase A0 proves the throwaway-client route first. Fallback needs a CTO ruling, not an operator question.
- **Service-role key.** Anyone holding it can mint a founder session; the plan says so and does not claim to defend it. CLO and CTO own where the external chain anchor lives.
- **Copy gate.** `approval-copy.ts` carries a CLO sign-off gate; PR-C copy ships `PROVISIONAL` until signed.
- **Migration number.** 184 is re-checked at PR time; a sibling can claim it first.
- **Four PRs.** PR-B to PR-D open from `main` after the previous merge; this branch carries PR-A only.
- **Not in scope:** #12020, #12021, #12022, #12023; the cutover run sheet and #8211 gates stay as written.

## References

- Issue #12011; deferred #12020, #12021, #12022, #12023; related #10361
- ADR-289, ADR-309, ADR-249; `plugins/soleur/skills/brainstorm-techniques/references/standing-delegation.md`
- Brainstorm, spec and wireframes listed in the Overview
