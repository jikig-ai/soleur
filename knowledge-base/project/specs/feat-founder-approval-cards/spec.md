---
feature: founder-approval-cards
issue: 12011
pr: 12012
branch: feat-founder-approval-cards
lane: cross-domain
brand_survival_threshold: single-user incident
brainstorm: knowledge-base/project/brainstorms/2026-11-03-founder-approval-cards-brainstorm.md
---

# Spec: Founder approval cards (CLI and web app)

## Problem Statement

Soleur stops at owner-only gates (legal acceptances, production authorizations) and describes them in engineering language. A non-technical, non-legal founder cannot tell what they are approving, cannot answer in one step, and the only recorded answer that counts today is a hand-typed GitHub comment (run sheet RF0: an agent comment posted through the founder's login never counts). The web app has a dark approval-request system for agent tool calls, but it only offers approve/deny, a closed list of 8 tools, workspace scoping, and nulls the shown text 30 days after a terminal state. The CLI has no equivalent.

## Goals

- G1. A plain-words CLI approval card (Yes / No / Request changes) for the existing Standing Delegation question.
- G2. A web legal-acceptance screen whose answer is recorded under the founder's own authenticated session, with the exact text shown.
- G3. One shared record contract rendered by both surfaces, with an honest `method` (`tty-ack` | `web-session`).
- G4. Scripts (`hold-gate-eval.sh`, `delegation-verify.sh`) can check a web acceptance by id.

## Non-Goals

- CLI-only customer channel (GitHub environment reviewer, record in customer's repo): later increment, needs counsel.
- Peer review of delegated production acts, kill-switch wording, different-model reviewer.
- Notifications, approval history UI.
- Amending run sheet RF0 or #8211 gates (follow-up after this ships).
- Jikigai-hosted records for CLI-only customers.

## Functional Requirements

- FR1. CLI card shows what will happen in business terms, then Yes / No / Request changes typed in words; no default on Enter; no jargon, paths or issue numbers in the question.
- FR2. At a browser-only gate the CLI prints one plain message with the app link, continues work that does not depend on the answer, stops at the point that needs it, and lists pending cards at the next session start. Headless/cloud sessions: the hold stands and one `action-required` issue is the queued card.
- FR3. Web screen: plain-words summary and consequence first; exact verbatim text with version label; three equal choices, none pre-selected; fresh re-login before Yes is recorded; Request changes requires free text.
- FR4. States: pending, accepted, declined, changes_requested ("waiting for revision"), superseded, expired; each shows how the answer was given, without the words "verified", "reviewed", "legally binding", "audit-ready", "compliant".
- FR5. A revision is a new row with a new text hash and `supersedes_id`; withdrawal is a later row, never an update.
- FR6. A user with no approver set up gets: "This needs approval from you in a browser and no approver is set up. Nothing was done."
- FR7. New gate kind `Gate: web-acceptance <id> <text-hash>`; any hold whose predicate cannot be evaluated stands (fail closed).

## Technical Requirements

- TR1. New table `legal_acceptance` (not `approval_request`): `authenticated`-only RPC, `auth.uid()` as actor, guard trigger rejecting null/mismatched founder id, write-once, hash chain across rows, JWT session id and fresh re-auth marker stored; verbatim text retained beyond 30 days; no ON DELETE SET NULL on founder id; exempt from `anonymise_approval_request` scrubbing (Art. 17 basis is the CLO's call).
- TR2. Read-only verify endpoint (id in; text hash, choice, founder id, method, timestamp, chain head out) behind a new read-only token; verifiers recompute the hash from the in-repo text. A pointer GitHub comment is cosmetic only.
- TR3. Reuse the `approval_request` pattern (RPC, GUC-gated guard trigger, forward-only status), not its rows. `SECURITY DEFINER` functions pin `search_path` including `pg_temp`.
- TR4. Web-session records need their own author arm in `delegation-verify.sh` (ADR-289 decision 1 rejects App-authored comments).
- TR5. Record carries: text shown, text hash/version, founder id, method, session id, timestamp, choice, requested edit, surface, links to CTO/CLO reasoning anchored on content.
- TR6. Ships dark behind the existing `approval-queue` flag (creation gated; `[id]/page.tsx` renders existing rows regardless). The CLO enabling gate blocks any non-canary flip, real acceptance rows, and public wording.
- TR7. Legal deliverables in the same PRs: new Art. 30 entry or PA-38 amendment, standalone LIA, Privacy Policy / DPD / GDPR Policy updates if new data is collected, copy sign-off.
- TR9. In-place step-up, never a sign-out (Ruled by CTO agent, 2026-11-03): default is an email one-time code; password re-entry only for accounts that have a password; OAuth re-login (redirect back to the same card) as last fallback; no TOTP, passkey or SMS now. The marker is a separate single-use challenge stored in a new `legal_reauth_event` table (`user_id`, `method`, `verified_at`, `consumed_at`, `challenge_hash`), verified by a dedicated server route that takes the email from `getUser()`, never the client. `record_legal_acceptance` consumes it atomically (same `user_id`, unconsumed, at most 5 minutes old) and copies `reauth_method` and `reauth_at` onto the row. Route and RPC reject a runtime-audience JWT. JWT-claim freshness is rejected because `mintFounderJwt` (`apps/web-platform/lib/supabase/tenant.ts`) mints founder sessions server-side. Residual: anyone holding the service-role key can still mint a session. Labels: "Confirmed with an email code, <UTC time>", "Confirmed with your password, <UTC time>", "Confirmed by signing in again with <provider>, <UTC time>"; the CLO approves the three method values and labels. The existing `settings/privacy/reauth` route is not reusable as-is (in-process Map store).
- TR8. Unresolved residual: the agent must not hold a secret able to mint a `web-session` (CTO, unverified); external anchor for the chain head (CLO to choose).

## PR Sequence (CTO ruling)

1. Dark: table, RPC, guard, chain, verify function, Art. 30 draft.
2. Web card and page with step-up re-auth, creation gated by `approval-queue`.
3. Verify endpoint, `Gate: web-acceptance`, CLI delegation card (independent; may ship first).
4. RF0 and runbook amendment.

## Visual Design

Wireframes approved by the operator 2026-11-03: `knowledge-base/product/design/approvals/founder-approval-cards.pen`, screenshots 10 to 18 in `knowledge-base/product/design/approvals/screenshots/`.

- FR3 web screen: frames 10, 11 (desktop), 13, 14 (mobile).
- TR9 in-place email-code check (states: start, enter code, wrong/expired code, password, provider): frames 12 (desktop) and 15 (mobile).
- FR4 result states: frame 16. Waiting-for-you list (FR2): frame 17. CLI plain-words prompts (FR1, FR2, FR6): frame 18.
- Approved scope of the code check: Yes only; No and Request changes record straight away with "Signed in with your account".
- Open wording items for planning: replace the made-up CLI delegation example with the real Standing Delegation wording; confirm the CLI honesty line ("Typed in this terminal on your computer. It was not re-checked against your account."); code lifetime is "a few minutes" until a number is chosen.

## Amendments from plan review (2026-11-03)

The plan at `knowledge-base/project/plans/2026-11-03-feat-founder-approval-cards-plan.md` supersedes these spec lines (rulings recorded there under `## Plan Review Rulings`):

- TR1: per-row database-computed `row_hash` from length-prefixed columns; no `prev_hash` hash chain and no `chain_break` alert (deferred with the external anchor, #12021); founder id is a plain uuid with no foreign key; one write-once decision table, unique on `(founder_id, key, text_hash)`; texts come from a committed registry, so there is no request table and no `request_legal_acceptance` RPC.
- TR2: the verify endpoint returns only `{status, text_hash, decided_at, row_ok}` and compares against a server-configured founder id.
- TR4: the `web-session` author arm is deferred; `Method:` is a label only and `tty-ack` is its only valid value in this increment.
- TR9: the in-place check ships email code only; password and provider confirmation are deferred to #12031. The reauth challenge binds user, key, text hash and session, with an attempt cap of 5.
- FR2: no pending-cards script; the CLI reuses the existing `go.md` standing-delegation issue, and the web page lists web acceptances.
- Retention and erasure: the row survives founder erasure with a plain uuid (CLO draft: instrument life plus 5 years, cap 10 years, counsel to confirm).
