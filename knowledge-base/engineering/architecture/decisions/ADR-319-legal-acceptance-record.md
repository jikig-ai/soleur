---
title: Legal acceptances are recorded in a separate write-once table from the founder's authenticated session
status: adopting
date: 2026-11-04
supersedes: none
issue: 12011
related: [12011, 12012, 12020, 12021, 12022, 12023, 12031, 4672]
related_adrs: [ADR-060, ADR-289, ADR-309]
tags: [security, legal, approval, rls, write-once, gdpr]
brand_survival_threshold: single-user incident
---

# ADR-319: Legal acceptances are recorded in a separate write-once table from the founder's authenticated session

## Context

A founder is asked to accept a legal text, such as a terms update or a data-processing amendment, before an agent may take a legal or irreversible step.
ADR-289 adopts an admin-authored issue comment as the Standing Delegation and records, as a residual, that the comment is posted from the same gh identity the agent
uses, so a GitHub comment is an audit trail and not a prevention. ADR-309 built a durable approval row for gated tool calls, but that row is a poor home for a legal
acceptance: its action text is scrubbed after 30 days, erasure nulls or deletes its user columns, and its subject is a tool call, not a document.

What the product must be able to say afterwards is narrow: **this founder, from their authenticated web session, decided this key on this exact text,
and for a Yes confirmed it with a fresh email code.** It must not say who the person is in law, that the text is enforceable, or that the record cannot
be altered by someone with production credentials.

Forces:

- The agent must not be able to create, change or delete a decision (property 3 below).
- The text the founder saw and the text that is hashed must be the same bytes; the browser never supplies either.
- A reflex click must not become a Yes: a Yes needs a code that arrives in the founder's inbox.
- The record must outlive the account (the founder is a data subject; see the legal basis below), so no erasure path may reach it.
- The database does not know the text registry (the texts are committed files), so the only party able to say which `(key, text hash)` pairs are real is the server.
- Customers are later. The first user is the operator, and nothing reads the table to enforce anything until PR-D.

## Considered Options

- **Option A: a separate write-once decision table plus a server-issued intent table (chosen).** `legal_acceptance` (unique on founder id, key, text hash), a guard trigger that
  admits only the RPC's insert and only against a consumed intent, a database-computed row checksum, no foreign key; `legal_reauth_event` for the intent and, for a Yes, the single-use email-code challenge.
- **Option B: reuse `approval_request` rows.** Rejected. The 30-day action-text scrub, the erasure scrub and the tool-call subject all fight the retention a legal
  record needs.
- **Option C: a GitHub comment as the authority.** Rejected. Same identity as the agent (ADR-289 records this as a residual).
- **Option D: a freshness claim in the JWT.** Rejected. `mintFounderJwt` mints the same claims for any caller that holds the signing secret, so a claim proves nothing the
  secret holder cannot forge.
- **Option E: a signed file in the repository.** Rejected. The key would be reachable by the process the record exists to constrain.
- **Option F: an unkeyed hash chain now.** Rejected. A service-role holder can recompute an unkeyed chain end to end. A per-row checksum is kept; a chain and an external
  anchor are deferred (tracked in #12080; this record and the plan are where the positions are documented).
- **Option G: a request table the agent fills (`request_legal_acceptance`).** Rejected by the CTO ruling of 2026-11-03: a text can only be requested from a committed
  registry file, so there is no request row to forge.
- **Option H: let any signed-in founder token record Decline or Request changes with no server step.** Rejected by the CTO ruling of 2026-11-04 (review of this PR): the
  database cannot tell a real `(key, text hash)` pair from an invented one, so any signed-up user could leave undeletable rows, and a stolen session could pre-empt the founder's Yes.
  Every choice therefore needs an intent that only the server can issue.

## Decision

Adopt Option A, shipped dark (no screen and no enforcement in this PR).

**Record.** `legal_acceptance` holds one row per (founder uuid, key, text sha256). Columns: founder id (a plain uuid, no foreign key), key, text hash, version (taken from the intent),
choice (`accept`, `decline`, `request_changes`), the optional requested edit (at most 1,000 characters, only for `request_changes`), the fixed method `web-session`, the
re-authentication method and time (Yes only), the web session id, the id of the intent that was consumed (no foreign key), the surface, the checksum and the creation time.
A new version of a text is a new row. A decision is terminal for its text hash: a Decline is undone only by publishing a new version of the text.

**Text registry.** A request for a text can only be created from a committed file `apps/web-platform/server/legal-acceptance/texts/<key>.md`. The hash is the sha256 of
the file's raw bytes with LF line endings; `sha256sum` gives the same value, which the shell-side check in PR-D will compare. Shared fixtures (ASCII with a pipe, a quote and
a trailing newline; and a multibyte one) are asserted in TypeScript and by `sha256sum`. The texts directory is not in the production image yet (PR-C precondition below).

**Intent.** `issue_legal_reauth` (service role; the server knows the registry) opens an intent for one (user, key, text hash, version, web session). It lives 30 minutes,
calling it again with the same inputs returns the live intent (reopening a card burns nothing) unless that intent's confirmed code is older than five minutes, in which case a new intent is opened so the founder
can confirm again, an explicit resend voids the earlier intent of that session and inserts
a new one, and at most three new intents per user and key are created in 15 minutes. It is the only source of valid pairs.

**Write path.** One authenticated RPC, `record_legal_acceptance`. The actor is `auth.uid()`; only a token whose audience is exactly `authenticated` may call it (a runtime
token, any other audience and a denied jti are refused in SQL), and the token must carry a web session id. **Every** choice needs the live intent for that user, key, text hash and
session, consumed in the same transaction as the insert; without one the call raises, a hash bound to another text returns a typed `replaced` outcome, a lapsed intent returns
`expired`, and nothing is consumed in those cases. A Yes additionally needs the email code confirmed in the last five minutes (`code_expired` otherwise). Two tabs on the same
decision are serialised by an advisory lock and the second reads `already_recorded`.

**Email-code step-up.** For a Yes the same row is the single-use challenge: five attempts counted by `claim_legal_reauth_attempt` BEFORE the auth service is asked (so a locked
challenge never reaches it), and `mark_legal_reauth_verified` bound to the event id that claim returned (so a resend between the two cannot move the confirmation). The code
is checked by the auth service on a throwaway client and is never stored here. Password and provider confirmation are deferred (#12031). Spike result (2026-11-04): an unknown
address answers 422 `otp_disabled` where a known one answers 200, so the web route in PR-C must return the same response for both.

**Guard.** A trigger (ENABLE ALWAYS, so it also fires in replica mode) refuses UPDATE, DELETE and TRUNCATE for every role while it is enabled, and admits INSERT only inside the RPC (a
transaction-local setting the read-only check function never sets) AND only against a consumed intent for the same user, key, text hash, session and event (for a Yes, a confirmed
code at the stamped time), so the setting is not the only gate. The trigger overwrites the checksum, so a caller cannot choose it.

**Checksum.** `row_hash` is sha256 over a fixed list of columns, each as a four-byte big-endian length then its UTF-8 bytes (a null is length -1). It makes a changed
row detectable by anyone who recomputes it. It is not an external anchor, and a column added later is outside it until the list is extended (a static test pins the list against the column set).

**Read path.** `verify_legal_acceptance` (service role, read-only, fails closed: a row whose checksum no longer matches reads status `invalid`) returns the status of one decision and
the checksum result. PR-D exposes it to the hold evaluator through an internal endpoint that returns only the status, the text hash, the decision time and the checksum result,
and that derives the founder id from its own configuration, never from the request.

**Reads by the founder.** The founder reads their own rows through RLS, and only through a token whose audience is exactly `authenticated`; a runtime token or a token with no audience reads nothing.

**Retention and erasure.** The founder is a data subject. The row is kept after erasure with the founder id as a pseudonymous uuid and no foreign key (never called
anonymised), on Art. 17(3)(e) and Art. 6(1)(f) with a standalone legitimate-interest assessment. The proposed period is the life of the instrument plus five years, capped
at ten, **unconfirmed by counsel**. No erasure scrub touches the table; `anonymise_approval_request` does not know it. Intent rows older than 30 days are deleted whenever a
challenge is requested. The tables are excluded from the data-subject export with a stated reason; access is answered through the legal contact. A deletion or redaction path for
a retained row, in particular for the free-text note, is not built and is a counsel and engineering follow-up (PA-40, counsel item 17).

**External anchor: undecided.** A chain and an external anchor are deferred. If one is added it publishes only the chain head, a sequence number and a date,
never a founder id or row content; a signed git tag is the counsel-preferred location.

### Residual risk (stated, not mitigated)

- A holder of production credentials can mint a founder web session, or write a row and its checksum as the database owner, or run `ALTER TABLE ... DISABLE TRIGGER` / `DROP TABLE`.
  The checksum detects an ordinary change; it does not stop that holder. This is why property 3 is stated as *recorded from an authenticated web session*, not *cannot be forged*.
- `mark_legal_reauth_verified` trusts its caller: a holder of the service key can stamp an intent as confirmed without any mailbox access (and then needs a web-session token to record).
- The agent process runs in-process with a service client (see ADR-309); the audience checks stop a runtime token, not code that holds the service key.
- A founder web session that is stolen can open the card through the legitimate server path and record a Decline. A Decline never signs anything and a new text version restores the
  founder's choice, so the CTO accepted it; PR-C must require a web session and never mint an intent for a runtime token.
- The verbatim text is plaintext to the database operator; only its hash is stored in the row, and the text lives in the repository.
- Email delivery is a single factor held by the founder's mailbox provider.
- The email-code attempt budget is per intent (five), three intents per user and key per 15 minutes; a per-user ceiling across keys is a PR-C item.

### Properties

1. While the guard trigger is enabled, a decision row cannot change or disappear (tested for every role; the owner can disable the trigger, see Residual risk).
2. A decision exists only with a consumed, matching intent, and a Yes only with a code confirmed in the last five minutes (tested for another user, key, session and text, and for a direct insert with the write door open).
3. A decision is recorded from the founder's authenticated web session (the actor is the verified session, not a parameter; a non-web audience and a runtime token are refused).

## Consequences

- One more pair of tables and seven functions (five RPCs plus the guard and the checksum), all dark. The record gives the product a way to hold a legal or irreversible step until the founder
  has decided, once PR-C and PR-D land; until then it changes nothing for any user.
- PR-C preconditions carried from this PR's review: embed or COPY the texts into the production image and test the deployed path; require a web session and never mint an intent for a runtime
  token; return the same response for a known and an unknown address on the email-code send; a per-user attempt ceiling across keys; a way to recover from a mistaken Decline (new text version).
- Counsel review of the wording and the retention period is a gate before the flag is enabled beyond the canary and before the first real row.
- Status is `adopting` until the first real acceptance has run through the screens and the check endpoint; nothing here is a measured production claim.

## Ordinal history

Drafted as ADR-318 (provisional) in the plan of 2026-11-03. Open PR #12002 had already claimed ADR-318 (`apply-delivery-gap-follower-may-redrive`), so this record was renumbered to ADR-319 on 2026-11-04
during review and every citation in the branch was swept. Re-verify against open PR heads again at ship.

## Cost Impacts

None for vendors. Two small tables; row volume is the number of legal texts a founder is asked about.

## NFR Impacts

None. No NFR register row changes tier.

## Principle Alignment

- AP-020 (Untrusted input at the agent boundary): Aligned. The agent has no write path; the text and its hash come from the server's registry, never from a request body, and the database only
  accepts a pair the server issued.
- AP-021 (Diagnostic honesty): Aligned. The record says *confirmed with an email code from a web session*. It does not claim the person's legal identity, the text's effect, or
  tamper-proofness against a credential holder.

## Diagram

C4: `platform.infra.legalAcceptanceStore` ("Legal Acceptances") with `webapp -> legalAcceptanceStore`, included in the `containers` view. There is deliberately no edge from
the engine.

## Amendment 2026-11-05 (PR-C)

PR-C ships the web card and the in-place email-code check behind the `approval-queue` flag. The decisions above are unchanged; this amendment records what PR-C decided on top of them, how each
precondition carried from PR-B's review (the "PR-C preconditions" bullet under Consequences, numbered 6.5 to 6.10 in the PR-C task list) was closed, and what stays open. Status stays
`adopting`: nothing here is a measured production claim and no real row has been recorded.

### Decisions

- **Every choice needs a server-issued intent.** `record_legal_acceptance` refuses any choice without a live intent for the same user, key, text hash and web session. The intent is opened in one of two places: the decide route calls
  `issue_legal_reauth` (30 minutes) at decision time for Decline and Request changes, while a Yes relies on the intent the email-code send step already opened. The choice is sent with the text hash the founder was shown. A refusal with no live
  intent (SQLSTATE 42501) is answered as HTTP 403 with the body `{ "error": "reverify" }`; it is not a member of the typed `LegalDecideOutcome`, and the dialog maps it to a step that sends the founder back to ask for a new code.
- **Yes needs an email code confirmed within five minutes.** The founder asks for the code on the card; the server verifies it on a throwaway client whose session is discarded, so the founder's own session (and its id) is unchanged, and then calls
  `mark_legal_reauth_verified` bound to the event id that `claim_legal_reauth_attempt` returned. Password and provider confirmation are not built (#12031).
- **Web session id, derived exactly as the SQL reads it.** The server takes the `session_id` claim of the founder's access token, else `ses_id`, and treats an empty value as absent, the same order `record_legal_acceptance` uses. A request with no web
  session id never opens an intent, and a runtime token is refused before any RPC is called.
- **The send step has no address-enumeration surface.** The address comes from the authenticated session only, never from the request, so a caller cannot ask about an address that is not their own. The response is `sent` on success and for the one
  exact auth-service code that means "unknown user or email codes disabled"; every real failure is `unavailable`, and an auth-service 429 is `rate_limited`. A reused live intent skips the email, so a repeated request does not send a second mail, but only when the earlier send is not known to have failed: after a failed or rate-limited send the next request mails again (the dialog sends a resend, and the server remembers the failure for the intent window), because a live intent is not proof that a code went out.
- **A per-user ceiling on verify attempts**, in addition to the five per challenge. It is in-process, per web host, and resets on restart (two web hosts exist), so it is a soft brake, not a bound. The hard bounds are the database ones.
- **The card says an answer is final.** It states that changing an answer means a new text version sent by the team. There is no undo button.
- **The two notices are shown on the card** (the card-level notice and the notice for the free-text note), word for word as drafted. The retention period inside the card-level notice is still marked "to be confirmed by counsel", so the card is
  PROVISIONAL and ships behind the flag until counsel decides.
- **Failure signals.** The card emits Sentry events tagged `feature=legal-acceptance` with `op` in `accepted` (one per accepted row, liveness, never paged), `decide_rejected` (reason tag), `reauth_failed` (provider error class),
  `page_read_failed` (the founder page could not read its rows; not paged) and `row_without_event` (a row with no matching `accepted` event). Two issue alerts in `apps/web-platform/infra/sentry` route them to the existing approval recipients:
  a burst rule that matches `decide_rejected` and `reauth_failed` (not `accepted`, not `page_read_failed`) and a per-event rule for `row_without_event`. Nothing emits `row_without_event` until the PR-D verify endpoint exists, so that page-severity
  rule is inert until then.

### Carry-over items from PR-B's review, and how each was closed

| Item | How it was closed |
| --- | --- |
| 6.4 Alerting for the card's failure modes | Two Sentry issue alerts (`legal-acceptance-failure-burst`, `legal-acceptance-row-without-event`) with a contract test that derives the op set from the server source and pins the committed alert reference. The burst threshold is provisional. |
| 6.5 Web session required, never an intent for a runtime token; session id as the SQL reads it | Closed in the service layer: the session id is derived by the SQL's own rule (`session_id`, else `ses_id`, empty meaning absent); no session id or a runtime token means no intent. |
| 6.6 Same response for a known and an unknown address | Closed by construction in the reauth route: the address comes only from the session, never the request, so there is nothing to enumerate. Success and the exact unknown-user code return `sent`; real failures return `unavailable`; a 429 returns `rate_limited`. |
| 6.7 Texts reach the production image | The registry reads `<cwd>/server/legal-acceptance/texts`; the runtime image carries that directory (the choice and its test are documented in `apps/web-platform/server/legal-acceptance/README.md`). The deployed-path test covers the esbuild bundle layout; the Next-compiled routes and pages rely on the same cwd convention (`WORKDIR /app`, `node dist/server/index.cjs`). A post-deploy smoke that loads a key from inside the container is a PR-D or ship follow-up. |
| 6.8 A per-user attempt ceiling across keys | Mitigated: the per-user ceiling is in-process, per host, and resets on restart (two web hosts exist); the 5-per-challenge database bound and the 3-challenges-per-15-minutes issue limit are the hard bounds. |
| 6.9 Typed outcomes for the RPC results | The service maps `recorded`, `already_recorded`, `replaced`, `expired` and `code_expired` to typed results that the route returns and the card renders as one of six states; an unexpected outcome fails closed and is reported to Sentry. A no-live-intent refusal is the exception: it is HTTP 403 `{ "error": "reverify" }`, outside `LegalDecideOutcome`. |
| 6.10 A way to recover from a mistaken answer | By design there is no undo button. The card tells the founder an answer is final and that changing it means a new text version sent by their team (a new text hash is a new row, as in the Decision section). |

The numbering follows the PR-C task list in `knowledge-base/project/specs/archive/20261105-131233-feat-founder-approval-cards-pr-c/tasks.md`; each item is also identified here by what it requires, so it does not depend on the number.

### Flag scope

`approval-queue` is read with `workspaceId: null`, which keys on role only, so the flag is effectively global: it is not per user and not per workspace. Enabling the card means enabling `approval-queue` for every workspace. With no real text committed,
an unknown key answers 404 for everyone. The card is therefore not "per-user behind the flag".

### Enabling conditions

All of these hold before the flag goes on for any founder:

- The "Request changes" note has no delivery path to the team until PR-D, although the card copy says it is saved with the decision.
- Counsel's retention decision is made and the `(c-2)` notice placeholder is replaced.
- The three published privacy documents are updated together.
- The Supabase "single session per user" setting is confirmed off; otherwise the throwaway `verifyOtp` would end the founder's web session.

### Verification state

`verify_legal_acceptance` (PR-B) returns `invalid` when a row's checksum does not match. The founder page has no card state for it: it shows the row as recorded while the agent-facing status reads `invalid`. PR-D must not collapse `invalid` into `none`.

### Still open

- **Retention and redaction.** The retention period (life of the instrument plus five years, capped at ten) remains unconfirmed by counsel (counsel item 17), and the deletion or redaction path for a retained row, in particular the free-text note,
  is not built (#12080). The card ships PROVISIONAL behind the flag for this reason; the first real row waits for counsel.
- **Password and provider confirmation** as further strength checks: #12031.
- **Counsel review** of the card wording and both notices. Nothing in this amendment says counsel has reviewed anything.
- **PR-D:** the check endpoint and the hold evaluator that read the record.

## Amendment 2026-11-05 (PR-D)

PR-D ships the read path: a check endpoint, an acknowledgement table that gives the `row_without_event` alert an emitter, a `web-acceptance` kind in the ship hold evaluator, and a pull-only way for the operator to read a Request changes note. The
decisions above are unchanged; this amendment records what PR-D decided on top of them. Status stays `adopting`: no real row has been recorded and the endpoint has not run against one. The code merges dark: the endpoint answers 503 until both
configuration values exist (see Hard limits).

### Decisions

- **Read path as built.** `GET /api/internal/legal-acceptance/[key]?hash=<64 hex>`. Check order: 503 (token or founder id unset or malformed, or the registry cannot be read), 401 (wrong token), 400 (malformed key or hash), 404 (key not in the
  registry), then the lookup. The 200 body has exactly four keys: `status`, `text_hash`, `decided_at`, `row_ok`. The founder id comes from the endpoint's own configuration, never from the request. The hash is answered from the database for the
  exact hash asked; whether that hash equals the committed text is the gate's job. The token is its own secret, `LEGAL_ACCEPTANCE_VERIFY_TOKEN`, separate from the Inngest one; `lib/internal-auth.ts` takes the secret name as a closed-union argument
  defaulting to the Inngest secret, so its existing callers are unchanged.
- **The acknowledgement table and what `row_without_event` proves.** Migration 185 adds `legal_acceptance_ack(acceptance_id, acked_at)`: service-role only, no founder id, no foreign key, no note and no decision field. The decide route writes the
  acknowledgement (`ack_legal_acceptance`) after the `accepted` event is emitted and `Sentry.flush` resolved true, off the request path, so the founder's response never waits on it. The verify endpoint reads `legal_acceptance_ack_state` for the one row it
  found and emits `row_without_event` when there is no acknowledgement and the row is older than 120 s. This proves "the web route did not acknowledge this row", not "Sentry received the event". It is alert-only: the response body and the gate are
  unchanged by it.
- **Note delivery: pull-only.** The note stays in `legal_acceptance.requested_edit`. No email, no Inngest function, no GitHub issue and no other push: that would create a second copy outside the retention and redaction decisions (#12080) and the agent holds
  the GitHub identity. The operator reads it personally with an owner-level query in their own Supabase login, following `knowledge-base/engineering/operations/runbooks/legal-acceptance-note-read.md`. No `service_role` function returns the note, the card
  copy is not changed, and the endpoint never returns it. The PR-C enabling condition "no delivery path to the team until PR-D" is restated as: pull-only delivery, no push.
- **The `invalid` rule.** A row whose checksum no longer matches is `invalid`. The endpoint passes it through as `invalid` with `row_ok: false` and emits `record_invalid` (error); the gate treats it as unevaluable (exit 2, "the record failed its check"). It
  is never collapsed into `none` at any layer PR-D touches. **Standing gap:** the founder page still shows such a row as recorded, because the card has six states and none is `invalid`. Adding one needs a wireframe and counsel-gated copy, so it is
  deferred to #12193; it is an enabling condition before the `approval-queue` flag is on for anyone beyond the operator-run dev exercise.
- **Hold-gate semantics.** `web-acceptance <key> <hash>` discharges a hold only when the endpoint answers `accepted` with `row_ok` true, the echoed hash equals the gate's hash, and that hash equals the sha256 of the committed text. A declined or
  changes-requested answer is terminal for that hash (a revised text with a new hash is needed). Every other answer, and every inability to ask, keeps the hold with a printed reason. A plan that carries a `web-acceptance` gate and no `Delegation:` line is
  evaluated rather than handed to the prose path; mixed with another kind and no delegation it is unevaluable (exit 2); a no-delegation plan without such a gate keeps exit 3; `Operator-reserved:` holds always stand.
- **A recorded Yes authorizes no production act.** A `web-acceptance` gate backs only a hold on that legal acceptance itself, for a text written for that hold. It is not a licence for any other action.
- **The flag is still effectively global.** `approval-queue` is read with `workspaceId: null`; the endpoint does not read the flag at all. The statement in the PR-C amendment stands.
- **Hard limits on the endpoint.** The 48-character bearer token, the read-only RPC, and the single configured founder id. A wrong token is answered 401 with no throttle, which the token length makes acceptable. A Tier-A reader (a branch workflow) can read the
  token from Terraform state and query one founder's status; that is bounded to four fields about one founder, and it is the consequence of choosing Terraform over a Doppler-only token (see the ADR-320 ruling below).
- **The alert is pull-driven.** `row_without_event` fires when a row is verified; a row nobody verifies stays silent. A sweep over unacknowledged rows is a follow-up (#12194) that must exist before the flag is on for a non-operator founder.
  `already_recorded` never acknowledges: a second tab proves nothing about a first tab that died, and a heal there would hide a row written through the RPC directly. A row whose acknowledgement was lost is reconciled by the operator through the runbook
  after confirming with the founder.
- **ADR-320 review of the verify token.** Outside ADR-320 decision 1: read-only status token, reviewed under decision 4 on 2026-11-05. Rotating it does not repair a leak, and it would move out of Terraform if it ever gains write reach. The founder uuid is not a secret:
  the operator enters it into the Doppler dev and prd configs outside Terraform and it is checked by a read, never passed as a Terraform variable. ADR-320 carries a one-line scope note pointing here.
- **Terraform is plan-only here.** No `.tf` file ships in this PR: the infra workflow applies on the push that merges one, so the secrets are carried by a separate change after the operator approves the plan (#12196).

### Added signals

Two ops join the existing set under `feature=legal-acceptance`: `record_invalid` and `store_failed` (tag `stage` in `verify`, `ack_state`, `ack`). `row_without_event` now has its emitter. `record_invalid` and `store_failed` have no paging rule in this PR; the
draft rules are tracked in #12195 and are an enabling condition before the flag is on. No payload carries the note.

### Still open after PR-D

- The founder-page state for `invalid` (#12193), the sweep (#12194), paging for the two new ops (#12195), the Terraform secrets and the founder uuid (#12196).
- The first real acceptance verified end to end by the gate, the post-deploy registry smoke (no text is committed, so every key answers 404) and the roadmap wording (#12197). Status moves to `accepted` only after the first.
- Before any non-operator founder: a named reader role for the note with a response expectation, a count-only "note waiting" signal, a visible acknowledgement for the founder, counsel-approved card copy that matches the real delivery behaviour, and the UX test with a
  non-technical founder.

### Diagram

The C4 model gains three edges: the ship component to the web application (read-only HTTPS bearer to the check endpoint), the ship component to Doppler (read of the one token), and the founder to the legal-acceptance store (the operator's owner-level read of the
note; operator-only and not reachable by an agent). The statement that no edge reaches the store from the agent side is replaced: the agent can read four fields about one decision through the endpoint and can never read the note.
