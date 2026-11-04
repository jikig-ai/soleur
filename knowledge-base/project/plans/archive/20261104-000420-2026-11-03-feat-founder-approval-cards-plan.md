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

Give a non-technical founder a plain-words way to answer owner-only gates, with one shared record format used by the command line and the web app. The first increment covers the operator's own gates: a command-line card for the existing standing-delegation question, and a web screen that records legal acceptances from the founder's own signed-in session with an in-place email-code check. The PR for this plan references #12011 and does not close it, because deferred follow-ups remain (#12020 to #12023 and #12031 for the password and provider checks).

Source documents: brainstorm `knowledge-base/project/brainstorms/2026-11-03-founder-approval-cards-brainstorm.md`, spec `knowledge-base/project/specs/feat-founder-approval-cards/spec.md`, approved wireframes `knowledge-base/product/design/approvals/founder-approval-cards.pen` (screenshots 10 to 18). Plan review (2026-11-03) cut and reshaped parts of the first draft; rulings are recorded in `## Plan Review Rulings`.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality (verified) | Plan response |
|---|---|---|
| Reuse the `approval_request` pattern, not its rows | `180_approval_request.sql` has the RPC, guard-trigger, RLS and grant shapes; it nulls `canonical_action` after 30 days and `anonymise_approval_request` deletes personal-workspace rows | New table `legal_acceptance`; copy the shapes; leave it out of the erasure scrub |
| "Fresh re-auth" can reuse the existing re-auth code | `server/dsar-reauth.ts` stores events in a process-local `Map`; `useOtpFlow.ts` starts a session; `EmailOtpType` has no reauthentication value | Single-use challenge stored in a table (`legal_reauth_event`), code verified server-side on a throwaway client; Phase A0 spike proves it on the dev project first |
| Migration number follows 182 | Latest on `origin/main` is 182; 183 is claimed by an unmerged sibling worktree | Use 184, re-checked at PR time |
| New ADR ordinal | Highest on `origin/main` is ADR-317 | Provisional ADR-318, re-verified at ship |
| TR1 hash chain across rows | An unkeyed chain is recomputable by a service-role holder, and the external anchor is undecided | Per-row `row_hash` now; chain deferred with the anchor decision (#12021) |
| TR4 `web-session` author arm | No flow produces such a comment; a `Method:` line the author controls must never pick a lighter check | Deferred; `Method:` stays a label (`tty-ack`) |
| FR2 pending-cards listing | `go.md` already files and dedupes the `Standing-delegation epic: #N` issue; the web page lists web acceptances | No new script; reuse `go.md`; AC3 rewritten |
| CLI has no equivalent surface | `operator-stage-approval.sh` and `operator-script.sh` give a typed-yes `tty-ack`; Cursor has no question-tool mapping | Reuse the `tty-ack` label; the card degrades to plain chat questions where no question tool exists |
| `hold-gate-eval.sh` can check a web record | Supports `pr-merged` and `no-inflight-run`; unknown kinds stay on hold; plan mode exits 3 without a `Delegation:` line | Add `web-acceptance` kind and state explicitly that web-acceptance holds run on the plan path outside delegation |

## Research Insights

**Premise validation.** #12011 and #12020 to #12023 are open; PR #11289 merged 2026-10-30 and is dark behind `approval-queue`; `grep legal_acceptance|legal_reauth` on `origin/main` returns nothing. The collision pre-check reported other worktrees' test runs and no open PR naming #12011.

**Property list.**

1. A founder answers the delegation question in plain words with Yes, No or Request changes, and Enter alone never answers.
2. A legal acceptance is recorded only from the founder's own authenticated browser session, after an in-place check made just before for that exact text, with the exact text kept.
3. A script can check, by key and text hash through a read-only endpoint, that a click was recorded from the founder's authenticated session. It does not protect against a holder of production credentials (the service-role key or prd Doppler), who can mint a founder session.
4. At a browser-only gate the CLI keeps working on unrelated work and the hold stands.
5. Every record says honestly how the answer was given.

**Cut list.**

| Mechanism | Property | What covers it / why cut |
|---|---|---|
| Reuse `approval_request` rows | 2 | Its 30-day text nulling and erasure scrub destroy the record |
| GitHub pointer comment as authority | 3 | Forgeable by the same identity (ADR-289) |
| Service-role read from scripts | 3 | Agent-reachable; replaced by a read-only endpoint token |
| Sign-out / sign-in again | 2 | Rejected at wireframe review; in-place email code |
| TOTP, passkey, SMS | 2 | New enrolment surface; deferred |
| Password and provider confirmation | 2 | No backend, provider redirect loses state; deferred to #12031 |
| `web-session` author arm, D3 | 3 | Nothing produces such a comment; downgrade risk; CTO ruling |
| `prev_hash` chain, `chain_break` alert, advisory lock | 3 | Unkeyed chain proves nothing against a service-role holder; deferred with the anchor (#12021) |
| `request_legal_acceptance` RPC and a request table | 2 | Text lives in a committed registry; pending means no row; no agent-creatable request |
| `pending-cards.sh`, its test, loader edit | 4 | `go.md` already re-surfaces the standing-delegation issue |
| `cron-approval-expiry.ts` edit | 2 | Consume-time five-minute check already enforces the window |
| `ops.ts`, `verify.ts`, `legal-acceptance-state.ts` as separate files | n/a | Use the existing Sentry helper and `approval-card-state.ts`; verify logic lives beside the route |
| Peer review, notifications, history, customer channel, RF0 amendment | n/a | #12021, #12022, #12020, #12023 |

**Key file facts** (verified by the implementation research):

- `apps/web-platform/supabase/migrations/180_approval_request.sql`: no top-level transaction (the runner wraps), precondition `DO` block, `REVOKE ALL ... FROM PUBLIC, anon, authenticated, service_role` then `GRANT SELECT ... TO authenticated`, RESTRICTIVE jti-deny policy, `SECURITY DEFINER` guard with `SET search_path = public, pg_temp` gated on a GUC, and `decide_approval` as the actor-from-`auth.uid()` pattern that also calls `is_jti_denied_from_jwt()` inside its body.
- `182_git_data_erasure_pending.down.sql:4-10`: a down file that refuses while rows exist.
- `apps/web-platform/supabase/verify/*.sql`: catalog sentinels run on deploy by `scripts/run-verify.sh`.
- `server/dsar-reauth.ts`: burn-first single-use consume, user binding; the semantics move into a table.
- `lib/supabase/tenant.ts` `mintFounderJwt` (l.271): the server mints founder sessions with the same claims as a human login; `decodeJwtPayloadUnsafe` does not verify signatures, so use `getUser()`. The runtime-audience check must live in SQL, not only in the route.
- `lib/internal-auth.ts:15` hard-codes the Inngest secret name; parameterise the name and reuse only `bearerMatches`.
- `plugins/soleur/scripts/delegation-verify.sh` (author checks l.491-497, `fail_invalid`/`fail_unv` l.62-64) and `plugins/soleur/skills/ship/scripts/hold-gate-eval.sh` (`known_kind` l.111, `eval_gate` l.152-163).
- Tests: bash suites are globbed by `scripts/test-all.sh`; the web app uses vitest.
- `lib/approval-copy.ts:128`: copy under a CLO sign-off gate (`PROVISIONAL: true`, test-enforced).

**Institutional learnings applied:** ADR-289, ADR-309, ADR-249, and `2026-11-03-brainstorm-verify-who-can-use-the-mechanism-before-briefing-design.md`.

**Functional overlap check.** Registries reachable; community artifacts cover gating and audit trails for developers; none is a plain-words founder card or checks standing delegation. Nothing to adopt.

**Phase A0 spike, API-surface half (2026-11-03).** Installed `@supabase/auth-js` and `@supabase/supabase-js` are both 2.99.2. Read from `node_modules/@supabase/auth-js/dist/main/lib/types.d.ts`: `signInWithOtp` options carry `shouldCreateUser` (lines 525 and 540); `EmailOtpType` includes `'email'` (line 684) so `verifyOtp({type:'email'})` is a valid call; the client options carry `persistSession` and `autoRefreshToken`, so a throwaway client with both off, cookies unwired, can be built. Not yet proven: the live round trip (an email code actually arriving at a dev user's inbox and verifying on the throwaway client without touching another session). That step needs a mailbox only the founder can read (an email one-time code is a human gate), so it stays open as a PR-B precondition: task 0.1 in `tasks.md` is not ticked.

**Phase A0 spike, live half (2026-11-04, dev project, raw GoTrue REST — same calls `supabase-js` makes).** Verify half proven; email delivery half not provable on dev.
- Send: `POST /auth/v1/otp {email, create_user:false}` for an existing user returns HTTP 200 with body `{}`; the server records `recovery_sent_at`. For an unknown address the same call returns HTTP 422 `otp_disabled` ("Signups not allowed for otp"). The two are NOT identical, so Supabase is an account-enumeration oracle: the reauth route must catch the 422 and return the same response to the caller as on success.
- Verify: `POST /auth/v1/verify {type:'email', email, token}` on a throwaway anon client (no persistence, no cookies): right code returns HTTP 200 with a session for that user, which the route must discard; a wrong code returns HTTP 403 `Token has expired or is invalid`; reusing a consumed code returns the same 403. Code source was `admin/generate_link` (`email_otp`), not an inbox.
- Delivery: the live email never arrived. Dev uses Supabase's default mailer (no custom SMTP, `rate_limit_email_sent = 2`) with a link-only magic-link template (no `{{ .Token }}`) and `mailer_otp_length = 8`. Prod uses Resend SMTP, a code template and `mailer_otp_length = 6`, `mailer_otp_exp = 600`. Prod delivery of codes is already exercised by the existing login flow; PR-C must not assume 6 digits on dev.
- Result: pass for the throwaway-client mechanism; the live-inbox step is replaced by prod parity evidence above. Task 0.1 ticked.

## Plan Review Rulings

Ruled by CTO agent, 2026-11-03 (binding): defer the `web-session` author arm (additive-only if ever added, with an operator-recorded login-to-founder mapping first); per-row `row_hash` only, database-computed from length-prefixed columns; no `request_legal_acceptance` and no request table, with texts in a committed registry `apps/web-platform/server/legal-acceptance/texts/<key>.md` bundled into the build and `text_hash` = sha256 of the raw file bytes (LF enforced); one write-once decision table, unique on `(founder_id, key, text_hash)`, founder id a plain uuid with no foreign key, SELECT policy `founder_id = auth.uid()` plus the RESTRICTIVE jti-deny policy; reauth required for Yes only; reauth event binds `user_id`, `key`, `text_hash`, `session_id`, attempt cap 5, resend supersedes the prior event (3 per 15 minutes), two `service_role`-only RPCs `issue_legal_reauth` and `mark_legal_reauth_verified`; verify endpoint returns only `{status, text_hash, decided_at, row_ok}` and compares against a server-configured founder id; `decide` emits a Sentry op event for every accepted row so a row with no event stands out; cut `pending-cards.sh`; hold-gate input validation (slug key, 64-hex hash, hard-coded https base, no redirects, token via header file, curl and jq in `need_tools`, timeout).

Ruled by CLO agent (draft, not legal advice), 2026-11-03: the founder is a data subject; keep the row after erasure with the founder id as a plain uuid and no foreign key (pseudonymous, never called anonymised); basis Art. 17(3)(e) and Art. 6(1)(f) with a standalone LIA, not 17(3)(b); recommended retention life of the instrument plus 5 years, cap 10 years, counsel to confirm; erasure reply must say what is kept, why, the period, restricted access, and Art. 21 and CNIL rights; any external anchor publishes only chain head, sequence number and date, never founder id or row content, ideally a signed git tag; a new numbered Art. 30 activity (not a PA-38 amendment) can ship dark in PR-B marked drafted and not counsel-reviewed, added to `DSAR_TABLE_EXCLUSIONS`; the attestation record in `knowledge-base/legal/audits/` and the LIA must exist before the first real row; the Request changes note is a new data category (cap its length, show a "no personal data" notice).

Operator decision, 2026-11-03: the in-place check ships email code only; password and provider confirmation are deferred. Request changes notes show on the web card; the agent sees only the status `changes_requested`.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "A founder-facing approval card (web app and CLI): plain-words summary of what is being approved and the consequence, the exact text that will be recorded, and Yes / No / Request changes." [issue #12011] | PR-A (CLI card), PR-C (web screen) | mapped |
| 2 | "The record keeps the text shown, identity, timestamp, choice and requested edit, and links the CLO/CTO reasoning in plain language." [issue #12011] | PR-B (`legal_acceptance` record) | mapped |
| 3 | "Which acts may ever be delegated, by class: reserved to the founder by default for legal, irreversible and money-moving acts" [issue #12011] | Phase A1 (reserved classes and `method` vocabulary in the card contract) | mapped |
| 4 | "Independent peer review of delegated production acts" [issue #12011] | — | descoped — justification: the CTO ruled a same-model reviewer is advisory only and the operator chose a first increment without it; tracked in #12021 |
| 5 | "One approval contract, two renderings." [issue #12011] | PR-A, PR-B, PR-C share the contract in `approval-card.md` | mapped |
| 6 | "how identity is established for a CLI answer" [issue #12011] | PR-A (`tty-ack` label, honest strength) and PR-D (verify endpoint for web answers) | mapped |
| 7 | "behaviour in headless and cloud sessions where no person can answer (the hold stands, and the same card is queued for the next attached session or the web app)" [issue #12011] | Phase A3 (existing `go.md` headless issue) and the web page listing | mapped |
| 8 | "the card in the Command Center, notification when a card is waiting, and the founder's history of approvals." [issue #12011] | Card in PR-C; notification and history descoped | descoped — justification: notifications and history are #12022 |
| 9 | "UX tested with a non-technical, non-legal founder on both surfaces, including the CLI." [issue #12011] | AC22 | mapped |
| 10 | "Interaction with `hr-technical-fork-is-not-an-operator-question`, `hr-menu-option-ack-not-prod-write-auth` and the existing delegation verifier." [issue #12011] | Phase A1, A2 | mapped |
| 11 | "Add legal acceptances via the web app" [operator, first-slice choice 2026-11-03] | PR-B, PR-C, PR-D | mapped |
| 12 | "Operator first, customers later" [operator, approach choice 2026-11-03] | Non-goal; #12020 | mapped |
| 13 | "Instead of asking to sign in again, can we ask them to enter their password again or enter a code in a popup" [operator, wireframe review 2026-11-03] | PR-C `legal-reauth-dialog` (email code) and `legal_reauth_event`; password and provider deferred | mapped |
| 14 | "Email code only" [operator, check-scope choice 2026-11-03] | PR-C scope; deferral issue for password and provider | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| CLI approval card wording contract (PR-A) | asks 1, 5 | asked |
| `Method:` label in `delegation-verify.sh` (PR-A) | asks 6, 10 | asked |
| Text registry and `legal_acceptance` table (PR-B) | asks 2, 11 | asked |
| `legal_reauth_event` table, RPCs and reauth route (PR-C) | asks 13, 14 | asked |
| Web legal-acceptance screen and states (PR-C) | asks 1, 11 | asked |
| Verify endpoint and read-only token (PR-D) | asks 6 | asked |
| `Gate: web-acceptance` kind (PR-D) | asks 6, 10 | asked |
| ADR-318 and C4 edit | — | inferred — justification: the decision adds a store and a trust boundary, so `wg-architecture-decision-is-a-plan-deliverable` requires the record |
| Art. 30 entry, LIA, attestation, privacy-document updates | — | inferred — justification: the CLO ruling requires a new processing-activity entry and legal basis before the first real row |
| Per-row `row_hash` | — | inferred — justification: the verifier needs an integrity checksum to detect accidental edit; stated honestly as a checksum |
| Terraform `doppler_secret` for the verify token and founder id | — | inferred — justification: `hr-all-infrastructure-provisioning-servers` forbids hand-set secrets |

### Split Assessment

- Subsystems touched: 4 — `apps/web-platform`, `plugins/soleur`, `knowledge-base`, `.claude`-free scripts
- Planned files: about 30 | Estimated changed lines: about 2000
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: split — four PRs at these seams: PR-A CLI card and `Method:` label (plugin and knowledge-base only); PR-B database record, text registry, ADR and C4, legal documents (dark); PR-C web screens and in-place check (behind `approval-queue`); PR-D verify endpoint, gate kind, Terraform secrets. This branch and draft PR #12012 carry PR-A; PR-B to PR-D open as follow-ups from `main` once the previous one merges. PR-B is gated on the Phase A0 spike result. PR-D can slip without blocking PR-A to PR-C.

## Open Code-Review Overlap

None. Seven planned edit paths were searched against open `code-review` issues; no body names any of them.

## Architecture Decision (ADR/C4)

### ADR

Create ADR-318 (provisional ordinal; re-verify against `origin/main` at ship): "Legal acceptances are recorded in a separate write-once table from the founder's authenticated session and checked by key and text hash through a read-only endpoint." It records: the property-3 sentence above, the per-row checksum (and that an unkeyed chain was rejected), the text registry as the only way to create a request, the email-code step-up as a separate single-use challenge, retention and erasure (pseudonymous uuid, no foreign key), and the external-anchor location as undecided with a signed git tag as the CLO-preferred option. `## Alternatives Considered`: reuse `approval_request` rows (rejected: 30-day text nulling, erasure scrub), GitHub comment as authority (rejected: same identity, ADR-289), JWT-claim freshness (rejected: `mintFounderJwt` mints the same claims), signed file (rejected: key custody the agent can reach), unkeyed hash chain now (rejected: recomputable by a service-role holder). Amend ADR-309 `## Decision` with a one-line pointer to ADR-318 for the legal class. Status `adopting` until PR-D ships and the first real acceptance has run.

### C4 views

All three model files (`model.c4`, `views.c4`, `spec.c4`) are read in Phase B4 before the edit. Already modeled: `approvalStore` (lines 329-331, ADR-309), whose description stays accurate because it covers agent tool calls only. Changes: add `legalAcceptanceStore = database "Legal Acceptances"` (Supabase, `legal_acceptance` and `legal_reauth_event`); web app container to that store; web app to Supabase Auth for the email one-time code; the verify endpoint as a relationship from the CLI-side hold evaluator (add a component or describe it on the existing plugin container if none models the evaluator); the verify token and founder id as a secret edge from Doppler; the founder-to-approval-screen relationship; the `view ... include` line in `views.c4` so it renders; fix any description the change falsifies. Validate with `apps/web-platform/test/c4-code-syntax.test.ts`, `c4-render.test.ts`, and `plugins/soleur/test/c4-count-parity.test.sh`.

### Sequencing

ADR and C4 ship in PR-B with the table they describe, in the same PR.

## Infrastructure (IaC)

### Terraform changes

Two new secrets in `apps/web-platform/infra/legal-acceptance-secrets.tf`: the read-only verify-endpoint token (`random_password` plus `doppler_secret` `LEGAL_ACCEPTANCE_VERIFY_TOKEN`) and the server-configured founder id (`LEGAL_ACCEPTANCE_FOUNDER_ID`), both in the `prd` config following `anthropic-ci-key.tf:21`; document both in `apps/web-platform/.env.example` as Doppler-only values. No new server, unit, DNS record or vendor account.

### Apply path

Not a host change. The existing Terraform pipeline applies the `doppler_secret` values; the web app reads them at its next deploy. No downtime.

### Host fan-out

Not applicable: no `terraform_data` SSH provisioner is added or edited.

### Distinctness / drift safeguards

`dev` and `prd` use separate generated tokens (one `random_password` per config). The values land in Terraform state; the state backend is encrypted.

### Vendor-tier reality check

Supabase email OTP uses the project's existing auth email path; `otp_expiry` is 3600 seconds in `supabase/config.toml`, so the five-minute lifetime is enforced by `legal_reauth_event` timestamps, not by the vendor.

## Observability

```yaml
liveness_signal:
  what: "Sentry feature tag legal-acceptance op events, including one op=accepted event per accepted row"
  cadence: "per request"
  alert_target: "Sentry issue alert routed to the existing approval alert recipients"
  configured_in: "apps/web-platform/infra/sentry (alert rule added in PR-C) and the existing reportApprovalOp helper"

error_reporting:
  destination: "Sentry web-platform via SENTRY_DSN, feature=legal-acceptance"
  fail_loud: "verify endpoint returns 503 when the token is unset and 401 on a wrong token; the hold evaluator keeps the hold and prints SOLEUR_HOLD_UNEVALUABLE with the reason"

failure_modes:
  - mode: "decide RPC rejected (stale hash, expired or already-used challenge, wrong user, superseded text)"
    detection: "op=decide_rejected with a reason tag"
    alert_route: "Sentry issue alert, feature:legal-acceptance"
  - mode: "email code send or verify fails"
    detection: "op=reauth_failed with provider error class"
    alert_route: "Sentry issue alert, feature:legal-acceptance"
  - mode: "a legal_acceptance row exists with no matching op=accepted event"
    detection: "reconciliation query run by the verify function and reported as op=row_without_event"
    alert_route: "Sentry issue alert, severity page"
  - mode: "hold evaluator cannot reach the verify endpoint"
    detection: "hold-gate-eval.sh prints SOLEUR_HOLD_UNEVALUABLE reason=verify-unreachable and keeps the hold"
    alert_route: "visible in the session and PR body; no silent discharge"

logs:
  where: "Sentry events and Better Stack SOLEUR_* markers mirrored from stdout"
  retention: "Sentry default 90 days; legal_acceptance rows are retained per the Art. 30 entry"

discoverability_test:
  command: "grep -o web-acceptance plugins/soleur/skills/ship/scripts/hold-gate-eval.sh"
  expected_output: "web-acceptance"
```

## Encryption Posture

```yaml
at_rest:
  - store: "Supabase Postgres, tables legal_acceptance and legal_reauth_event (prd project)"
    mechanism: "provider-managed:supabase-postgres-aes256"
    evidence: "scripts/encryption-posture-ledger.json, Supabase store entries (mechanism string provider-managed:supabase-postgres-aes256)"
    defends_against: "theft of a storage volume or backup without database credentials"
    does_not_defend: "a holder of the service-role key, a database role with SELECT, or an injection through application code; the verbatim text is plaintext to the database"
    disclosed_as: "Art. 30 entry added in PR-B and the Data Protection Disclosure"
    live_verification: "lint-encryption-posture.py in CI resolves the ledger entry"
in_transit:
  - connection: "browser to web app, web app to Supabase, hold evaluator script to the verify endpoint"
    tls: "TLS 1.2+ on all three"
    cert_verification: on
    does_not_defend: "a compromised client machine or an agent that already holds the founder's browser session"
    disclosed_as: "Data Protection Disclosure transport section"
```

## User-Brand Impact

- **If this lands broken, the founder experiences:** a Yes recorded in `legal_acceptance.choice` for a text they did not read or that changed while the page was open (the recorded `text_hash` differs from the text shown), or a Yes they gave that is not recorded so a legal or production step stalls without a visible reason. Covered by AC9 to AC13 and Guard 3.
- **If this leaks, the founder's workflow is exposed via:** a forged or replayed acceptance row (a reused or cross-card `legal_reauth_event`, or a minted founder session) that lets an agent act as the founder, or the verbatim legal text and founder uuid read by a service-role holder. Covered by AC10, AC11, AC14 and the disclosed residual in property 3.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** one forged or mis-recorded legal acceptance ends trust in "the founder decides", so the tier is the highest rather than an aggregate pattern.

CPO sign-off is required before `soleur:work` begins (carried from the brainstorm). `soleur:engineering:review:user-impact-reviewer` runs at review time.

## Domain Review

**Domains relevant:** Product, Engineering, Legal

### Product (CPO)

**Status:** reviewed
**Assessment:** The web card and durable record are shipped but dark; the genuinely new parts are the CLI card, Request changes, legal-acceptance class and peer review. Build the record contract first, then the CLI rendering. Roadmap row CP2 is stale ("Not started") and #12011 has no row; correct CP2 and place #12011 (founder's call). Reflex-clicking is the main UX risk: consequence first, no default.

### Engineering (CTO)

**Status:** reviewed
**Assessment:** See `## Plan Review Rulings`. Residual stated in property 3: a holder of production credentials can mint a founder session.

### Legal (CLO)

**Status:** reviewed
**Assessment:** See `## Plan Review Rulings`. Counsel review is needed before any customer-facing use and before the first real row; retention period unconfirmed.

### Product/UX Gate

**Tier:** blocking
**Decision:** reviewed
**Agents invoked:** soleur:product:cpo, soleur:product:design:ux-design-lead, soleur:product:spec-flow-analyzer
**Skipped specialists:** none
**Pencil available:** yes

#### Findings

Wireframes were produced at brainstorm time and approved by the operator on 2026-11-03: `knowledge-base/product/design/approvals/founder-approval-cards.pen`, screenshots 10 to 18. Variances from the approved frames, to be reconciled in PR-C: frames D (password) and E (provider) are marked "later"; "Taken back by your team" is dropped (superseded covers it); card states are derived: pending (no row for the current text), accepted, declined, changes requested, replaced (a newer registry version exists for the same key), expired (the registry entry carries `valid_until` and it passed with no row); frame 18 item 5 shows delegation items only in PR-A. The spec-flow analysis (11 findings) is folded into the acceptance criteria below.

## Implementation Phases

### PR-A — CLI approval card and `Method:` label (this branch, PR #12012)

**Phase A0 — Spike (gates PR-B and PR-C).** Prove on the dev Supabase project that an email code can be sent and verified for an existing user on a throwaway client (separate client with persistSession, autoRefresh and cookies off; discard and locally sign out the returned session) without touching the user's session: `signInWithOtp` with `shouldCreateUser: false`, then `verifyOtp({type:'email'})`. Confirm the response to the caller is identical for send success and failure. Record the call shape and result in this plan's Research Insights. If it fails, stop for a CTO ruling before PR-B.

**Phase A1 — Card wording contract.** Create `plugins/soleur/skills/brainstorm-techniques/references/approval-card.md`: plain-words structure (what will happen in business terms, then the three choices typed in words), the consequence block before the choices, no default on Enter, `y` refused, the three messages from wireframe frame 18 (delegation question, browser hold, no approver set up) with a decision table (TTY with account, headless with account, no account), the reserved classes (legal, irreversible, money are never answered at `tty-ack`), the `method` vocabulary (`tty-ack` only in this PR; `web-session` is a record value written by the database, never a comment label), and the assurance wording ban list. Link it from `standing-delegation.md` in the epic-start section.

**Phase A2 — `Method:` label in the delegation record.** Extend `delegation-verify.sh render` with an optional `--method tty-ack` argument that writes a `Method:` line, and make `verify` accept (never require) it, rejecting any other value (including `web-session`) as invalid. The line is a label only: `verify` returns the same verdict with or without it. Keep every existing fixture valid.

**Phase A3 — Headless queue.** No new script. Confirm `go.md`'s existing headless path (filing or reusing the `Standing-delegation epic: #N` issue) satisfies ask 7, and add a short line to `approval-card.md` pointing the CLI at it.

### PR-B — Database record, text registry, ADR, C4, legal documents (dark; gated on the A0 spike)

**Phase B1 — Migration.** `184_legal_acceptance.sql` and `.down.sql` (refuses while rows exist), plus `verify/184_legal_acceptance.sql`. Tables: `legal_acceptance` (id, founder_id uuid with no foreign key, key, text_hash, version, choice, requested_edit capped length, method fixed to `web-session`, reauth_method, reauth_at, session_id, surface, row_hash, created_at; unique on `(founder_id, key, text_hash)`) and `legal_reauth_event` (user_id, key, text_hash, session_id, attempts, verified_at, consumed_at, superseded_at, created_at). RPCs: `record_legal_acceptance` (`authenticated`; actor from `auth.uid()`; checks `is_jti_denied_from_jwt()` and the runtime-audience marker in SQL; takes key, `p_text_hash` and choice; locks the event row and recomputes the hash against the stored registry hash; consumes the event atomically for Yes only), `issue_legal_reauth` and `mark_legal_reauth_verified` (`service_role` only, taking `p_user_id`), and a read-only `verify_legal_acceptance`. `row_hash` is computed in SQL from length-prefixed (uint32 big-endian) columns. Guard trigger GUC-gated, write-once, no `ON DELETE SET NULL`, not part of `anonymise_approval_request`. SELECT policy `founder_id = auth.uid()` plus the RESTRICTIVE jti-deny policy. Precondition `DO` block; `search_path = public, pg_temp` on every `SECURITY DEFINER` function.

**Phase B2 — Text registry.** `apps/web-platform/server/legal-acceptance/texts/<key>.md` committed files with optional `valid_until` front matter, `canonical.ts` computing `text_hash` as sha256 of raw file bytes (LF enforced), and a shared fixture containing `|`, `"` and a trailing newline asserted in both bash and vitest.

**Phase B3 — Migration and guard tests.** `apps/web-platform/test/legal-acceptance/migration-184-legal-acceptance.test.ts` (static shape, mirrors the 180 test) plus a behavioural test that drives every Guard 3 mutation row.

**Phase B4 — Legal documents.** New numbered Art. 30 activity marked drafted and not counsel-reviewed, added to `DSAR_TABLE_EXCLUSIONS`; standalone LIA; the attestation record in `knowledge-base/legal/audits/`; Privacy Policy / Data Protection Disclosure / GDPR Policy updates if the data-subject class extends beyond the founder; `compliance-posture.md` row; retention and erasure wording; "no personal data" notice text for the note field. Gate: `soleur:gdpr-gate` against the migration.

**Phase B5 — ADR and C4.** ADR-318, the ADR-309 pointer, the `.c4` edits after reading all three files, validation tests.

### PR-C — Web screens and in-place check (behind `approval-queue`)

**Phase C1 — Service layer and routes.** `apps/web-platform/server/legal-acceptance/` (service, reauth, canonical); reauth route `app/api/legal-acceptance/[key]/reauth/route.ts` (send code and verify code on a throwaway client; email from `getUser()` only; identical response on send success and failure; attempt cap 5; resend limit 3 per 15 minutes; `validateOrigin` failing closed on an absent Origin; JSON content type required) and decide route `app/api/legal-acceptance/[key]/decide/route.ts` (takes key, choice, the shown `text_hash` and, for Request changes, the note; never client text). Reuse the existing Sentry helper for op events and emit `op=accepted` per accepted row.

**Phase C2 — UI.** `app/(dashboard)/dashboard/approvals/legal/[key]/page.tsx` (lists registry keys and states for the founder), `components/approvals/legal-acceptance-card.tsx`, `legal-reauth-dialog.tsx` (email code only), state derivation added to `lib/approval-card-state.ts`, and `lib/legal-acceptance-copy.ts` under the same CLO sign-off gate as `approval-copy.ts`. Use the Button primitives. Frames 10 to 17 with the variances listed under Findings.

**Phase C3 — Alert.** Sentry issue alert in `apps/web-platform/infra/sentry` for the failure modes above.

### PR-D — Verify endpoint and gate kind

**Phase D1 — Endpoint.** `app/api/internal/legal-acceptance/[key]/route.ts` using `bearerMatches` with a parameterised secret name (503 when unset, 401 on a wrong token, token checked before any lookup), returning only `{status, text_hash, decided_at, row_ok}` and comparing against the server-configured founder id. Terraform secrets as above.

**Phase D2 — Gate kind.** `hold-gate-eval.sh`: add `web-acceptance <key> <text-hash>` to `known_kind` and `eval_gate`, evaluated on the plan path outside delegation (plan mode today exits 3 without a `Delegation:` line; the change states and tests that web-acceptance holds still run). Validate key as a slug and hash as 64 hex; hard-coded https base with no env or plan override; `--proto =https`, no redirects, bounded timeouts; token read from a header file, never argv; require `status == "accepted"`, equal hash and `row_ok` through `jq -e`; add curl and jq to `need_tools`. Unknown kind, unreachable endpoint, mismatched hash, `declined`, `changes_requested` or an unreadable response all keep the hold and print the reason.

## Guard Contract

### Guard 1 — web-acceptance hold gate (`hold-gate-eval.sh`)

**Property.** A hold backed by a web acceptance is discharged only when the endpoint confirms an `accepted` answer for exactly the text hash named in the plan, from the configured founder; every other state keeps the hold.

**Assembly.** The gate quantifies over `known_kind`, `eval_gate`, the grammar comment, the plan parser for `Gate:` lines, input validation, the HTTP client call, and the three outcomes of every hold (`discharged`, `held`, `unevaluable`). All flow through one function that returns `held` on any non-success; the `Operator-reserved:` path is a second chokepoint and stays untouched.

**Mutation matrix.**

| # | Mutation | Must go RED because |
|---|----------|---------------------|
| 1 | Treat HTTP 5xx or a timeout as discharged | unreadable must hold |
| 2 | Accept `changes_requested` or `declined` as discharged | only `accepted` discharges |
| 3 | Skip the text-hash comparison | a revised text must not inherit an old acceptance |
| 4 | Accept a second matching `Gate:` line after a failing first one | every line must hold, not the first |
| 5 | Make `known_kind` list `web-acceptance` but leave `eval_gate` without the case | a gate that evaluates 0 and exits 0 is vacuous |
| 6 | Accept a key or hash that fails validation (path characters in the key) | input must be validated before any request |
| 7 | Follow a redirect or read the base URL from the environment | the base is hard-coded and redirects are refused |

**Harness rows.** Remove the stub-endpoint server from the suite so every case sees "unreachable" — the suite must fail rather than pass on all-held. Must-PASS inputs other than the canonical: a registry text containing `|`, `"` and a trailing newline, and a plan with two holds where only the second is a web acceptance.

**Anchor.** The independent anchor is the reviewed in-repo text and its committed hash; changing the plan hash alone does not match a recorded row. A service-role holder is out of scope and disclosed in ADR-318.

### Guard 2 — `Method:` label (`delegation-verify.sh`)

**Property.** A `Method:` line never changes the strength of the check: the verdict is identical with and without it, and any value other than `tty-ack` is invalid.

**Assembly.** `render`, `verify`, the parser for the `Method:` line, and the existing author checks (User type, no app, admin permission) all feed one `fail_invalid`/`fail_unv` exit path.

**Mutation matrix.**

| # | Mutation | Must go RED because |
|---|----------|---------------------|
| 1 | Accept `Method: web-session` | only `tty-ack` is a valid label here |
| 2 | Accept an unknown `Method:` value | unknown values are invalid |
| 3 | Skip the admin-permission check when a `Method:` line is present | the label must not select a lighter check |
| 4 | Let a bot or App author pass when `Method:` is present | existing rejection must hold |
| 5 | Remove the `Method:` parser call | a label that is never parsed lets bad values through |

**Harness rows.** Remove the `gh-stub.sh` response for the admin-permission call — the suite must fail. Must-PASS input differing from canonical: a delegation with no `Method:` line (legacy).

**Anchor.** The delegation comment is re-verified immediately before every delegated act (ADR-289).

### Guard 3 — write-once record (`legal_acceptance`)

**Property.** Once a decision row exists no column of it can change and no row can be deleted, a Yes row exists only with a consumed, matching, unexpired reauth event for the same user, key and text hash, and `row_hash` is database-computed from the row.

**Assembly.** The guard trigger (`BEFORE INSERT OR UPDATE OR DELETE`), every RPC that sets the GUC, `record_legal_acceptance`, `anonymise_approval_request` (must not touch the table), the founder-erasure path, and the unique constraint.

**Mutation matrix.**

| # | Mutation | Must go RED because |
|---|----------|---------------------|
| 1 | Remove `DELETE` from the trigger events | deletion must be blocked |
| 2 | Set the GUC in the verify function | the read RPC must not open the write door |
| 3 | Add the table to the erasure scrub | erasure must not destroy the record |
| 4 | Compute `row_hash` without `text_hash` | a changed text must change the hash |
| 5 | Skip the reauth-event consumption for Yes | Yes needs a consumed event |
| 6 | Accept an event bound to another key, user or text hash | the event is bound to one acceptance |
| 7 | Drop the `auth.uid()` check or the runtime-audience check | actor must come from the verified session |

**Harness rows.** The static shape test fails if the trigger statement is removed from the SQL. Must-PASS input: a second row for a new text version of the same key.

**Anchor.** None beyond the row checksum; the external anchor and chain are deferred (#12021) and stated as such in ADR-318.

## Files to Create

- `apps/web-platform/supabase/migrations/184_legal_acceptance.sql`
- `apps/web-platform/supabase/migrations/184_legal_acceptance.down.sql`
- `apps/web-platform/supabase/verify/184_legal_acceptance.sql`
- `apps/web-platform/server/legal-acceptance/service.ts`
- `apps/web-platform/server/legal-acceptance/reauth.ts`
- `apps/web-platform/server/legal-acceptance/canonical.ts`
- `apps/web-platform/server/legal-acceptance/texts/` (one committed file per key)
- `apps/web-platform/app/api/legal-acceptance/[key]/reauth/route.ts`
- `apps/web-platform/app/api/legal-acceptance/[key]/decide/route.ts`
- `apps/web-platform/app/api/internal/legal-acceptance/[key]/route.ts`
- `apps/web-platform/app/(dashboard)/dashboard/approvals/legal/[key]/page.tsx`
- `apps/web-platform/components/approvals/legal-acceptance-card.tsx`
- `apps/web-platform/components/approvals/legal-reauth-dialog.tsx`
- `apps/web-platform/lib/legal-acceptance-copy.ts`
- `apps/web-platform/test/legal-acceptance/migration-184-legal-acceptance.test.ts`
- `apps/web-platform/test/legal-acceptance/service.test.ts`
- `apps/web-platform/test/legal-acceptance/routes.test.ts`
- `apps/web-platform/test/legal-acceptance/card.test.tsx`
- `apps/web-platform/infra/legal-acceptance-secrets.tf`
- `plugins/soleur/skills/brainstorm-techniques/references/approval-card.md`
- `plugins/soleur/test/fixtures/standing-delegation/delegation-method-tty-ack.md`
- `plugins/soleur/test/fixtures/standing-delegation/delegation-method-unknown.md`
- `knowledge-base/engineering/architecture/decisions/ADR-318-legal-acceptance-record.md`
- `knowledge-base/legal/legitimate-interest-assessments/2026-11-founder-legal-acceptance-lia.md`
- `knowledge-base/legal/audits/2026-11-founder-legal-acceptance-attestation.md`

## Files to Edit

- `plugins/soleur/scripts/delegation-verify.sh`
- `plugins/soleur/scripts/delegation-verify.test.sh`
- `plugins/soleur/skills/ship/scripts/hold-gate-eval.sh`
- `plugins/soleur/test/hold-gate-eval.test.sh`
- `plugins/soleur/skills/brainstorm-techniques/references/standing-delegation.md`
- `apps/web-platform/lib/approval-card-state.ts`
- `apps/web-platform/components/approvals/approval-landing.tsx`
- `apps/web-platform/lib/internal-auth.ts` (parameterise the secret name)
- `apps/web-platform/.env.example`
- `knowledge-base/engineering/architecture/diagrams/model.c4`
- `knowledge-base/engineering/architecture/diagrams/views.c4`
- `knowledge-base/engineering/architecture/decisions/ADR-309-durable-action-bound-approval-requests.md`
- `knowledge-base/legal/article-30-register.md`
- `knowledge-base/legal/compliance-posture.md`
- `knowledge-base/product/roadmap.md` (CP2 status and #12011 row, founder's call on placement)

## Acceptance Criteria

### Pre-merge (per PR)

- [ ] AC1 (PR-A): the CLI card follows `approval-card.md`: consequence block before the choices, `Enter` alone never answers, `y` is refused, and a browser-only item refuses a typed answer.
- [ ] AC2 (PR-A): `delegation-verify.sh render --method tty-ack` writes a `Method:` line; `verify` returns the same verdict with and without it; any other value, including `web-session`, is invalid; existing fixtures still pass.
- [ ] AC3 (PR-A): `approval-card.md` documents the headless path through the existing `go.md` standing-delegation issue, and a test asserts the three-way decision table (TTY with account, headless with account, no account) selects the right frame-18 message.
- [ ] AC4 (PR-B): the migration applies on the dev project; the down file refuses while rows exist; `verify/184` reports `bad = 0`.
- [ ] AC5 (PR-B): the guard rejects UPDATE and DELETE; `anonymise_approval_request` leaves the table untouched; the founder-erasure path completes and the legal rows survive.
- [ ] AC6 (PR-B): `record_legal_acceptance` rejects a client-supplied text, a stale `p_text_hash`, a runtime-audience token and a jti-denied token; a superseded text returns a typed "replaced" error that does not consume the code.
- [ ] AC7 (PR-B): ADR-318 exists with `## Alternatives Considered`; the `.c4` edits render and the three C4 tests pass.
- [ ] AC8 (PR-B): the Art. 30 entry, LIA, attestation record and compliance-posture row are in the same PR with `soleur:gdpr-gate` output attached; the Request changes field has a length cap and a "no personal data" notice.
- [ ] AC9 (PR-C): Yes is disabled until the text is confirmed (text shorter than the viewport unlocks immediately; the lock state is announced to assistive technology); none of the three choices is pre-selected; Request changes requires text.
- [ ] AC10 (PR-C): the email code is single-use, valid for at most 5 minutes, capped at 5 attempts, bound to user, key, text hash and session, voided by a resend, and consumed atomically by `record_legal_acceptance`; a code issued for one card is rejected on another.
- [ ] AC11 (PR-C): reload mid-check returns to the start with nothing recorded; two tabs recording the same card produce one row and the second tab shows "accepted"; a failed decide call shows an error, never success.
- [ ] AC12 (PR-C): the card shows "Confirmed with an email code, <UTC time>" and a test greps all copy surfaces (`legal-acceptance-copy.ts`, `approval-card.md`, hold messages, LIA) for "verified", "reviewed", "legally binding", "audit-ready" and "compliant".
- [ ] AC13 (PR-C): creation and the Yes path are gated by `approval-queue`; with the flag off the page still renders existing rows; the rendered card text hashes to the stored `text_hash`.
- [ ] AC14 (PR-C): every card state (pending, accepted, declined, changes requested, replaced, expired) renders from a row or registry entry; an unreachable email send shows "nothing was recorded, try again shortly" with a way to get help.
- [ ] AC15 (PR-D): the endpoint returns 503 when the token is unset, 401 on a wrong token (checked before lookup) and only `{status, text_hash, decided_at, row_ok}` on a right one.
- [ ] AC16 (PR-D): every mutation row of Guards 1 to 3 is driven RED by a test (Guard 3 tests land in PR-B, Guard 2 in PR-A), and the harness rows fail the suite when the stub is removed.
- [ ] AC17 (PR-D): `LEGAL_ACCEPTANCE_VERIFY_TOKEN` and `LEGAL_ACCEPTANCE_FOUNDER_ID` are created by Terraform, differ between `dev` and `prd`, and are documented in `.env.example`.
- [ ] AC18 (PR-D): a held gate prints its reason (`declined`, `changes requested`, `unreachable`, `hash mismatch`).
- [ ] AC19: wireframe copy and implemented copy match frames 10 to 18 except the variances listed in the Product/UX Gate findings.

### Post-merge (follow-through)

- [ ] AC20: ADR-318 status moves from `adopting` to `accepted` after the first real acceptance has run end to end.
- [ ] AC21: the CLO enabling gate is cleared and counsel has reviewed the customer-facing wording and the retention period before `approval-queue` is turned on beyond the canary and before the first real row.
- [ ] AC22: a non-technical, non-legal founder completes one card on the CLI and one on the web without help (recorded as a comment on #12011).
- [ ] AC23: roadmap CP2 status corrected and #12011 placed.

## Test Scenarios

1. CLI card: typed `yes` records `Method: tty-ack`; bare Enter and `y` do nothing; `changes` collects text and records nothing granting.
2. Web, happy path: confirm text, Yes, send code, enter code, row `accepted` with `reauth_method=email_code`.
3. Web, wrong code (cap reached), expired code, resend voiding the old code: no row; a good code is not consumed by a wrong attempt.
4. Web, Request changes: row `changes_requested`; the card shows "waiting for revision"; the gate holds with that reason; a revised text creates a new key version and the old card shows "replaced".
5. Replay: the same challenge used twice; a challenge from another user; a challenge for another card; a challenge older than 5 minutes; a code for text A recorded against text B — all rejected.
6. Hold gate: accepted with matching hash discharges; declined, changes_requested, hash mismatch, endpoint down, redirect, malformed response and a path-character key all keep the hold.
7. Founder erasure: account deletion completes and the legal rows survive with a plain uuid.
8. Text TOCTOU: the registry text changes while the page is open; the decide call returns "replaced" and records nothing.
9. No web account (CLI-only user): the CLI prints the "no approver set up" message and does nothing.
10. Headless session: the hold stands and the existing standing-delegation issue is filed or reused.
11. Short text and keyboard-only use of the card on desktop and mobile widths.

## Dependencies & Risks

- **Supabase code route.** The A0 spike must show a throwaway-client email code works before PR-B starts; fallback needs a CTO ruling, not an operator question.
- **Service-role key and prd Doppler.** A holder can mint a founder session; ADR-318 and property 3 say so and do not claim to defend it.
- **Copy gate.** `approval-copy.ts` carries a CLO sign-off gate; PR-C copy ships `PROVISIONAL` until signed.
- **Retention period.** The recommended period (instrument life plus 5 years, cap 10) is unconfirmed by counsel.
- **Migration number.** 184 is re-checked at PR time; a sibling can claim it first.
- **Four PRs.** PR-B to PR-D open from `main` after the previous merge; this branch carries PR-A only.
- **Not in scope:** #12020 to #12023 and the password and provider follow-up; the cutover run sheet and #8211 gates stay as written.

## References

- Issue #12011; deferred #12020, #12021, #12022, #12023; related #10361
- ADR-289, ADR-309, ADR-249; `plugins/soleur/skills/brainstorm-techniques/references/standing-delegation.md`
- Brainstorm, spec and wireframes listed in the Overview
