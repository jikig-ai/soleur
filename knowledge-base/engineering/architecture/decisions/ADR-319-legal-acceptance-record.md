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
  anchor are deferred (no issue tracks them yet; this record and the plan are the place they are deferred).
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
calling it again with the same inputs returns the live intent (reopening a card burns nothing), an explicit resend voids the earlier intent of that session and inserts
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

**Reads by the founder.** The founder reads their own rows through RLS; a runtime-audience token reads nothing.

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
