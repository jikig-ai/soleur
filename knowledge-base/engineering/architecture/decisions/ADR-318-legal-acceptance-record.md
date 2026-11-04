---
title: Legal acceptances are recorded in a separate write-once table from the founder's authenticated session
status: adopting
date: 2026-11-04
supersedes: none
issue: 12011
related: [12011, 12012, 12020, 12021, 12022, 12023, 12031, 4672]
related_adrs: [ADR-060, ADR-289, ADR-309]
tags: [security, legal, approval, rls, write-once, flag-gated, gdpr]
brand_survival_threshold: single-user incident
---

# ADR-318: Legal acceptances are recorded in a separate write-once table from the founder's authenticated session

## Context

A founder is asked to accept a legal text, such as a terms update or a data-processing amendment, before an agent may take a legal or irreversible step.
ADR-289 fixed the rule that an approval comment on GitHub is not the authority: it carries the same identity the agent already holds. ADR-309 built a
durable approval row for gated tool calls, but that row is a poor home for a legal acceptance: its action text is scrubbed after 30 days, erasure
nulls or deletes its user columns, and its subject is a tool call, not a document.

What the product must be able to say afterwards is narrow: **this founder, from their authenticated web session, decided this key on this exact text,
and for a Yes confirmed it with a fresh email code.** It must not say who the person is in law, that the text is enforceable, or that the record cannot
be altered by someone with production credentials.

Forces:

- The agent must not be able to create, change or delete a decision (property 3 below).
- The text the founder saw and the text that is hashed must be the same bytes; the browser never supplies either.
- A reflex click must not become a Yes: a Yes needs a code that arrives in the founder's inbox.
- The record must outlive the account (the founder is a data subject; see the legal basis below), so no erasure path may reach it.
- Customers are later. The first user is the operator, and nothing reads the table to enforce anything until PR-D.

## Considered Options

- **Option A: a separate write-once decision table plus a challenge table (chosen).** `legal_acceptance` (unique on founder id, key, text hash), a guard trigger that
  admits only the RPC's insert, a database-computed row checksum, no foreign key; `legal_reauth_event` for the single-use email-code challenge.
- **Option B: reuse `approval_request` rows.** Rejected. The 30-day action-text scrub, the erasure scrub and the tool-call subject all fight the retention a legal
  record needs.
- **Option C: a GitHub comment as the authority.** Rejected. Same identity as the agent (ADR-289).
- **Option D: a freshness claim in the JWT.** Rejected. `mintFounderJwt` mints the same claims for any caller that holds the signing secret, so a claim proves nothing the
  secret holder cannot forge.
- **Option E: a signed file in the repository.** Rejected. The key would be reachable by the process the record exists to constrain.
- **Option F: an unkeyed hash chain now.** Rejected. A service-role holder can recompute an unkeyed chain end to end. A per-row checksum is kept; a chain and an external
  anchor are deferred (see below).
- **Option G: a request table the agent fills (`request_legal_acceptance`).** Rejected by the CTO ruling of 2026-11-03: a text can only be requested from a committed
  registry file, so there is no request row to forge.

## Decision

Adopt Option A, shipped dark (no screen and no enforcement in this PR).

**Record.** `legal_acceptance` holds one row per (founder uuid, key, text sha256). Columns: founder id (a plain uuid, no foreign key), key, text hash, version, choice
(`accept`, `decline`, `request_changes`), the optional requested edit (at most 1,000 characters, only for `request_changes`), the fixed method `web-session`, the
re-authentication method and time, the web session id, the surface, the checksum and the creation time. A new version of a text is a new row.

**Text registry.** A request for a text can only be created from a committed file `apps/web-platform/server/legal-acceptance/texts/<key>.md`. The hash is the sha256 of
the file's raw bytes with LF line endings; `sha256sum` gives the same value, which the shell-side check in PR-D will compare. A shared fixture containing a pipe, a quote and
a trailing newline is asserted in TypeScript and by `sha256sum`.

**Write path.** One authenticated RPC, `record_legal_acceptance`. The actor is `auth.uid()`; a denied token and a runtime-audience token are refused in SQL. A Yes
needs a verified, unexpired challenge bound to the same user, key, text hash and web session, and consumes it in the same transaction as the insert; a challenge bound to
another text returns a typed `replaced` outcome and consumes nothing. Decline and Request changes need no code.

**Email-code step-up.** `legal_reauth_event` is a separate single-use challenge: five minutes, five attempts counted before the auth service is asked, a resend voids the
earlier code, three challenges per user and key per 15 minutes. The code is checked by the auth service on a throwaway client and is never stored here. Password and
provider confirmation are deferred (#12031). Spike result (2026-11-04): an unknown address answers 422 `otp_disabled` where a known one answers 200, so the web route
in PR-C must return the same response for both.

**Guard.** A trigger refuses UPDATE, DELETE and TRUNCATE for every role, including the table owner, and admits INSERT only inside the RPC (a transaction-local setting the
read-only check function never sets). The trigger overwrites the checksum, so a caller cannot choose it.

**Checksum.** `row_hash` is sha256 over a fixed list of columns, each as a four-byte big-endian length then its UTF-8 bytes (a null is length -1). It makes a changed
row detectable by anyone who recomputes it. It is not an external anchor.

**Read path.** `verify_legal_acceptance` (service role, read-only) returns the status of one decision and whether the stored row still matches its checksum. PR-D exposes it
to the hold evaluator through an internal endpoint that returns only the status, the text hash, the decision time and the checksum result.

**Retention and erasure.** The founder is a data subject. The row is kept after erasure with the founder id as a pseudonymous uuid and no foreign key (never called
anonymised), on Art. 17(3)(e) and Art. 6(1)(f) with a standalone legitimate-interest assessment. The proposed period is the life of the instrument plus five years, capped
at ten, **unconfirmed by counsel**. No erasure scrub touches the table; `anonymise_approval_request` does not know it. The tables are excluded from the data-subject export
with a stated reason; access is answered through the legal contact.

**External anchor: undecided.** A chain and an external anchor are deferred (#12021). If one is added it publishes only the chain head, a sequence number and a date,
never a founder id or row content; a signed git tag is the counsel-preferred location.

### Residual risk (stated, not mitigated)

- A holder of production credentials can mint a founder session, or write a row and its checksum as the database owner. The checksum detects an ordinary change; it does not
  stop that holder. This is why property 3 is stated as *recorded from an authenticated web session*, not *cannot be forged*.
- The verbatim text is plaintext to the database operator; only its hash is stored in the row, and the text lives in the repository.
- Email delivery is a single factor held by the founder's mailbox provider.

### Properties

1. A decision row cannot change or disappear (guard, tested for every role).
2. A Yes exists only with a consumed, matching challenge (tested for another user, key, session and text).
3. A decision is recorded from the founder's authenticated web session (the actor is the verified session, not a parameter).

## Consequences

- One more pair of tables and six functions, all dark. The record gives the product a way to hold a legal or irreversible step until the founder has decided, once PR-C and
  PR-D land; until then it changes nothing for any user.
- Counsel review of the wording and the retention period is a gate before the flag is enabled beyond the canary and before the first real row.
- Status is `adopting` until the first real acceptance has run through the screens and the check endpoint; nothing here is a measured production claim.

## Ordinal history

Drafted as ADR-318 (provisional) in the plan of 2026-11-03; ordinal re-verified against `origin/main` on 2026-11-04 (highest present was ADR-317).

## Cost Impacts

None for vendors. Two small tables; row volume is the number of legal texts a founder is asked about.

## NFR Impacts

None. No NFR register row changes tier.

## Principle Alignment

- AP-020 (Untrusted input at the agent boundary): Aligned. The agent has no write path; the text and its hash come from the server's registry, never from a request body.
- AP-021 (Diagnostic honesty): Aligned. The record says *confirmed with an email code from a web session*. It does not claim the person's legal identity, the text's effect, or
  tamper-proofness against a credential holder.

## Diagram

C4: `platform.infra.legalAcceptanceStore` ("Legal Acceptances") with `webapp -> legalAcceptanceStore`, included in the `containers` view. There is deliberately no edge from
the engine.
