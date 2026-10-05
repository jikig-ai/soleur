---
title: Inbound email routing table as the tenancy key for email-triage ingress
status: accepted
date: 2026-10-04
amends: ADR-066
supersedes: none
issue: 9458
related: [9456, 9459, 5103]
related_adrs: [ADR-038, ADR-055, ADR-066, ADR-126]
tags: [email-triage, tenancy, ingress, resend-inbound]
brand_survival_threshold: single-user incident
---

# ADR-269: Inbound email routing table as the tenancy key for email-triage ingress

## Status

**Accepted — 2026-10-04 (#9458).** The routing table ships empty and every
event is claimed under the env-pinned operator until a route exists. The
resolver enforces this: it refuses any route that is not the operator pair, so
a non-operator route is inert until the hard preconditions below are met.

## Context

ADR-055 made Resend Inbound the third multi-source ingress and pinned its
tenancy to one value: `EMAIL_TRIAGE_OWNER_USER_ID`. ADR-066 made reads
workspace-grained but left the *write* tenancy (which workspace a mail is
claimed under) and the notification recipient on that single env value. The
Resend Inboxes evaluation (2026-10-03) concluded that neither a per-user inbox
nor per-agent inboxes should be built on a private-beta vendor product yet, but
that the vendor-neutral gap — no way to map an inbound address to a tenant —
blocks both paths regardless of vendor.

Measured facts: the Resend `email.received` payload carries `to`, `cc`, `bcc`
and `received_for`; for Proton-Sieve-forwarded `ops@` mail the receiving API
reports `to: ["triage@inbound.soleur.ai"]` (the forwarding target). The
webhook route previously read none of these.

## Decision

1. **`email_inbox_routes` is the ingress tenancy key.** One row maps a
   normalized recipient address to `(workspace_id, owner_user_id)`; the owner
   must be a member of the workspace (composite FK to `workspace_members`), and
   the application checks `role = 'owner'`. The table is service-role only
   (RLS on, no policies, privileges revoked from `anon`/`authenticated`).
2. **The webhook route emits normalized `recipients`** (`data.to` +
   `data.received_for`, envelope field first; display names stripped,
   lowercased, deduped, sorted, capped at 20 valid addresses) on the
   `email/inbound.received` event. The event store therefore holds normalized
   addresses only. The field is optional; absent or empty means "no routing".
3. **Resolution happens inside `claim-insert` and its ids are carried forward.**
   Inngest re-runs the handler body on every replay, so a DB-derived owner
   resolved outside a step could differ between attempts. The step returns
   `{ownerId}`; later steps read it from the claim; the 23505 adopt path takes
   it from the adopted row; a claim memoized before the deploy (no `ownerId`)
   falls back to the env owner.
4. **`EMAIL_TRIAGE_OWNER_USER_ID` is the operator, and the only owner.**
   Real production mail always carries recipients (Sieve-forwarded `ops@` mail
   arrives as `to: triage@inbound.soleur.ai`), so every inbound mail runs one
   indexed routes query; only an event with empty `recipients` skips it. A
   route resolves to its own pair only when it is the operator pair
   (workspace = owner = the env owner); any other route is refused and the mail
   is claimed under the operator. The env owner is validated in every case.
5. **A routing anomaly degrades to the operator; it never loses mail.** A
   routes-query error (a PostgREST schema-cache miss after migrate, a blip, a
   rollback) and a refused non-operator route both claim the mail under the
   operator and report to Sentry (`op: route-degraded`, tag `degraded`, pg code
   only). Failing closed would drop the operator's statutory mail on a
   `retries: 1` function whose webhook already returned 200. Two aliases of the
   operator are not ambiguous. Fail-closed semantics return with the first
   non-operator route (#9459), where falling back would misdeliver a tenant's
   mail instead.
6. **Vendor-swap seams are named, not abstracted.** The vendor boundary is
   three existing modules: the svix verify in
   `app/api/webhooks/resend-inbound/route.ts`, `fetch-received-email.ts` (its
   own mocked module), and the `sendCompliantOutbound` chokepoint in
   `outbound.ts`. A one-implementation `InboxProvider` interface was rejected
   until a second implementation exists (#9459).
7. **ADR-066 Decision 4 is amended.** The notification recipient is the claimed
   row's `user_id` — the route owner when a route matched, otherwise the
   configured owner. Reads remain Owner-shared via
   `is_email_triage_workspace_owner`.

### Hard preconditions before any non-operator route exists

Tracked in #9459. The resolver refuses non-operator routes today, so these are
the conditions for removing that refusal, not for creating rows.

- **Workspace-scoped `claim_key` and adopt query.** `claim_key` is
  `${sender}|${messageId}`, globally unique and sender-controlled, and the
  23505 adopt select is not workspace-filtered: with two routable tenants a
  Message-ID collision silently drops the second tenant's mail and can let one
  tenant's run adopt another's stub.
- **No operator fallback after a route is deleted or disabled.** The route FK
  is `ON DELETE CASCADE` (gdpr-gate `GDPR-Art-17`: configuration must not block
  account deletion), so deleting a route re-routes that address to the operator
  inbox. Replace the fallback with quarantine/tombstone semantics first.
- **Multi-route mail:** fan-out or quarantine (today: throws).
- **Key choice:** `to` is the sender-written header (misses Bcc, lists and
  aliases, and is attacker-controlled: a sender can put a routed address in
  `To` on mail that arrived for `ops@`, steering it, or co-address a route and
  `ops@` so the operator's copy is never claimed). Decide `received_for`
  (envelope) vs `to` and confirm the webhook `to` equals the receiving API's
  `to` on the first routed event. Today `received_for` is listed first so the
  cap never prefers the header.
- **Owner-validation memo:** the 1h memo means a demoted or removed owner keeps
  receiving routed mail for up to an hour; shorten or drop it for table routes.
- **Ambiguity:** two routes to different tenants must fan out or quarantine,
  and must not throw to exhaustion (an attacker can address two tenants' routes
  to force a lost mail).
- **Rollback order:** roll back the code before dropping the table
  (`155_email_inbox_routes.down.sql`); until then lookups fail and degrade.
- **Per-owner limits multiply per route:** the daily LLM ceiling and the
  statutory notification coalescing are keyed on `user_id`.
- **Probe:** extend `cron-email-ingress-probe` with a direct-to-route canary so
  it asserts the routed artifact (ADR-126); add a Sentry signal for an address
  that matches no route once any route exists.
- **Compliance:** a full DPIA (CLO screening triggers 1 and 2 from the
  2026-06-11 operator-inbox screening) and a Resend DPA before any per-user
  custody.

## Alternatives Considered

| Alternative | Verdict |
|---|---|
| Plus-addressing on one mailbox | Rejected: the Proton Sieve forward collapses the address to one inbound target, so the sub-address never reaches the webhook. |
| Per-tenant subdomain wildcard (`<tenant>.inbound.soleur.ai`) | Deferred: adds a DNS/Terraform surface with no demand signal; the table is subdomain-compatible. |
| Adopt Resend Inboxes now | Rejected in the 2026-10-03 brainstorm: vendor custody of full mail inverts ADR-055's parse-and-discard, private-beta API instability, and no published region/retention/pricing. |
| One webhook endpoint per tenant | Rejected: webhook sprawl; one verified ingress with a lookup is simpler and keeps the ADR-055 ordering. |
| `agent_id`, `thread_key`, WORM-trigger rewrite, `InboxProvider` | Deferred to #9459 at plan review: no reader exists, and the trigger rewrite sits on a statutory-evidence table. |

## Consequences

- One new service-role-only table and a small resolver; no new vendor and no
  body or header data stored (ADR-055 parse-and-discard unchanged).
- Third-party recipient addresses (normalized) now appear in the Inngest event
  payload and so in the run store, under the existing ADR-033 retention; noted
  against PA-27.
- Not dormant: every inbound mail with recipients now issues one indexed
  routes query and the event payload carries `recipients`. The behavior change
  is bounded because the outcome is the operator in every branch, and a lookup
  failure is reported rather than fatal. Migrate runs before deploy
  (`web-platform-release.yml`), so the table exists before the code that reads it.
- Route inspection is operator-only by design (`email-route-status.sh`, a
  read-only psql session); the table is service-role only and no agent tool
  reads it. An agent-facing route surface arrives with agent inboxes (#9459).
- The daily probe proves the fallback path only; routed-path coverage arrives
  with the first real route (#9459).

## Addendum 2026-10-05 — Resend Inboxes ruled out for EU-resident inboxes

The "Adopt Resend Inboxes now" row above rested on missing information. Resend answered in writing on
2026-10-05 (`knowledge-base/project/questionnaires/2026-10-05-email-vendor-inboxes-eu-residency.md`): Inboxes stores
all data in the United States (bodies, headers, attachments, metadata, logs and backups), cannot commit in the DPA to
EU-only storage or processing, and its founder advises against building on it for an EU-residency requirement. The
transfer basis is the Standard Contractual Clauses plus the EU-U.S. Data Privacy Framework. This matches the
existing Resend Inbound posture recorded in ADR-055 (US custody), so it is not a new transfer for the current
pipeline, but it removes Inboxes as a candidate for any inbox that must be EU-resident. The routing table stays
vendor-neutral; a per-user or per-agent inbox needs a different provider or a self-hosted receiver, tracked in #9459.

