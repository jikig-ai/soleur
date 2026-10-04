---
title: "feat: inbound email routing table for email triage (inbox-provider-neutral prep)"
date: 2026-10-03
slug: inbox-provider-neutral-email-routing
branch: feat-resend-inboxes-evaluation
issue: 9458
closes: 9458
type: feat
priority: p3
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
---

## Overview

Resolve an inbound email's recipient address to a validated workspace and owner through a new `email_inbox_routes` table, instead of relying only on the single env-pinned owner (`EMAIL_TRIAGE_OWNER_USER_ID`). This is the preparation chosen in the Resend Inboxes brainstorm (Approach A, `knowledge-base/project/brainstorms/archive/20261004-121033-2026-10-03-resend-inboxes-evaluation-brainstorm.md`), **trimmed after plan review** (operator decision, 2026-10-04): `agent_id`, `thread_key`, the `InboxProvider` interface and the WORM-trigger rewrite moved to #9459. Adopting Resend Inboxes itself stays deferred to #9459.

**Behavior after deploy is byte-identical for production traffic.** The routing table ships empty. An address that matches no route, or an event with no recipients, takes the existing env-owner path unchanged. The new code is dormant in prd until a route row exists, and **no route row may be created for a non-operator workspace until the hard preconditions in ADR-269 and #9459 are met** (claim-key scoping, no operator fallback once routes exist, multi-match fan-out).  *(Superseded — see `## Review Revisions` at the end of this plan.)*

## Plan-Review Revisions (2026-10-04)

Seven reviewers (DHH, Kieran, code-simplicity, architecture, spec-flow, CPO, CTO) reviewed the first draft.

- **Operator decision (User-Challenge, cut of requested scope):** trim to the routing table. Moved to #9459: `agent_id` (on routes and on `email_triage_items`), `thread_key` + header read, `InboxProvider`, WORM function replacement, migration 156.
- **Mechanical fixes applied:** resolve the route inside the `claim-insert` step and carry ids forward (Kieran P1, spec-flow P0, architecture P1); AC-2's "tests pass unmodified" was false and is rewritten; composite FK instead of two independent FKs (architecture, Kieran); one migration; allowlist path is repo-root-relative; normalizer lives in `events.ts` and the event stores normalized addresses only (Kieran); loose address CHECK to avoid JS/POSIX regex drift (Kieran); multi-match throws instead of silent first-wins (architecture P1); Phase 0 got a failure branch (spec-flow); status script gained `--resolve <addr>` (CTO); ADR-066 Decision 4 and the `api -> resend` C4 edge get amended (architecture).
- **Deferred as #9459 hard preconditions** (architecture P0s that only matter once a second tenant exists): workspace-scoped `claim_key` and adopt query, soft-delete/quarantine instead of operator fallback, multi-match fan-out, envelope-vs-header key.

## Research Insights

**Premise Validation (Phase 0.6).** #9458 is open and created this session; #9459 is the deferred adoption tracker. Cited artifacts all exist (`git grep`): `EMAIL_TRIAGE_OWNER_USER_ID` is read only at `email-on-received.ts:311` (plus `.env.example:126`); migrations 102/111 define `email_triage_items`; highest migration ordinal is 154; highest ADR is 268. An ADR-corpus grep for `plus-address|subaddress|InboxProvider|inbox provider|address.*routing` returned nothing, so the mechanism is not a previously rejected alternative. ADR-055 and ADR-066 are extended, not contradicted.

**Measured facts that bound the design:**

- The Resend `email.received` webhook payload includes `to`, `cc`, `bcc` and `received_for` (SDK type `ReceivedEmailEventData` in `apps/web-platform/node_modules/resend/dist/index.d.mts`; Resend's published example payload). The route's local `ResendInboundBody` type (`app/api/webhooks/resend-inbound/route.ts:68`) simply does not declare them. A research agent reported the opposite; that claim is refuted by both sources and not used.
- Live receiving API (`GET /emails/receiving?limit=5`, read-only, address fields only): all five most recent rows have `to: ["triage@inbound.soleur.ai"]`, empty `cc`/`bcc`, and no `received_for`. For Proton-Sieve-forwarded `ops@` mail, `to` carries the forwarding target address, which is the natural routing key. Whether the webhook's `to` equals the list API's `to` is gated by Phase 0.
- Inngest handlers re-run their body on every step replay; `ownerId` is currently a static env read at `email-on-received.ts:311` and is used outside steps at lines 459, 508, 534 and 688. A DB-derived owner must therefore be resolved inside a step and carried in the step's return, or a retry can notify a different owner than the row's `user_id`.
- `workspace_members` has `PRIMARY KEY (workspace_id, user_id)` with `role IN ('owner','member')` (migration 053), so a composite FK from routes to `(workspace_id, owner_user_id)` is valid; the owner-role check stays in application code.
- `claim_key` is `${sender}|${messageId}`, globally unique and sender-controlled (`email-on-received.ts:374-377`); the 23505 adopt query (`:410-414`) is not workspace-scoped. Safe today (single tenant); a hard #9459 precondition once a second tenant is routable.
- Verify SQL files run in the release pipeline: `apps/web-platform/scripts/run-verify.sh` is invoked from `.github/workflows/web-platform-release.yml`.
- No open code-review issue mentions `email-on-received`, `resend-inbound` or `email_triage` (research agent, `gh issue list --label code-review --limit 200`, bodies filtered).

**Property List (Phase 0.6b).** P1 — an inbound address resolves to a validated workspace + owner without the env-pinned owner. (P2 agent attribution, P3 conversation key and P4 vendor-swap seam were in the first draft and are deferred; see Cut List.)

**Cut List (Phase 0.6b).**

| Mechanism | Property | Already covered by | Decision |
|---|---|---|---|
| `agent_id` on routes and `email_triage_items` | P2 | none | Deferred to #9459 (no reader; forces a WORM function rewrite on a statutory table). |
| `thread_key`, `deriveThreadKey`, header read in the fused step | P3 | `message_id` already identifies a single mail | Deferred to #9459 (no reader; touches the parse-and-discard surface). |
| `InboxProvider` interface | P4 | `fetch-received-email.ts` (mocked seam), `outbound.ts` (`sendCompliantOutbound` chokepoint), svix verify in one route | Deferred; the ADR names the three seams instead of abstracting them. |
| Resolver RPC / SECURITY DEFINER function | P1 | plain service-role select suffices (no authenticated surface) | Cut. |
| Self-serve route creation API/UI | P1 | none — no user surface this phase | Cut. |
| Route fan-out, soft-delete/quarantine, workspace-scoped claim key | P1 at multi-tenant | none | Deferred as #9459 hard preconditions. |
| Separate `normalize-address.ts` | P1 | the normalizer is one function | Cut as a file; lives in `events.ts`. |

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality | Plan response |
|---|---|---|
| FR1 "routing table maps an inbound address to a workspace (and optionally an agent)" | Rows also need an owner user: `email_triage_items.user_id` is the notification recipient and DSAR owner, today the validated env owner (workspace_id = user_id = owner). | Route row carries `owner_user_id`; the existing two-query owner validation is generalized to `(workspace_id, owner_user_id)`. Agent attribution deferred. |
| FR2 `agent_id` + `thread_key` columns | No reader exists; `thread_key` needs header data only available inside the body-fetch step. | Deferred to #9459 (operator decision). |
| FR3 `InboxProvider` | The three seams already exist. | Deferred; documented in the ADR. |
| Brainstorm gap "no address→workspace routing" | Confirmed. | This plan. |

## User-Brand Impact

**If this lands broken, the user experiences:** an inbound email that lands in the wrong workspace's inbox (a founder sees another tenant's correspondence), or is silently dropped because a route lookup failed, so a DSAR or breach notice never reaches the person who owes a statutory reply.

**If this leaks, the user's data is exposed via:** a mis-keyed or over-broad route row (one address resolving to another tenant's workspace), a route table readable by `authenticated`, or a deleted route re-routing a tenant's mail to the operator inbox.

**Brand-survival threshold:** single-user incident

Carried forward from the brainstorm's `## User-Brand Impact`. This plan implements only the routing substrate, and ships it dormant; the sharpest vectors (cross-tenant misrouting, silent loss) are bounded by the hard preconditions on creating any non-operator route. `requires_cpo_signoff: true` — CPO reviewed the brainstorm and again at plan review and recommends this trimmed scope. `soleur:engineering:review:user-impact-reviewer` runs at review time.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "compare if this would be a viable solution with pros and cons" | Done in the brainstorm doc (this plan is its follow-through) | mapped |
| 2 | "provide Soleur Users with an email inbox and potentially email inboxes for key agents" | Phase 1 routing table (the substrate both need) | mapped |
| 3 | "A: Prepare, wait" and "Trim to routing table (Recommended)" (operator choices, 2026-10-03/04) | Whole plan; no Resend Inboxes adoption; agent/thread/provider work deferred | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Routing table + resolver (Phase 1) | "Stack-neutral prep (routing table, agent_id, thread_key, InboxProvider)" and "Trim to routing table" | asked |
| Route-status script (Phase 2) | — | inferred — required by the Observability gate (a new table needs a way to read its state without remote shell access) |
| DSAR exclusion entry for the new table (Phase 1) | — | inferred — a repo gate requires every table to be allowlisted or excluded |
| ADR-269, ADR-066 amendment, C4 edges, PA-27 note (Phase 3) | — | inferred — architecture-decision and Article 30 gates require them |

### Split Assessment

- Subsystems touched: 3 — `apps/web-platform/supabase`, `apps/web-platform/server` + `app/api`, `knowledge-base/`
- Planned files: ~17 | Estimated changed lines: ~420
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Domain Review

**Domains relevant:** Engineering, Legal, Product (carried forward from the brainstorm's `## Domain Assessments`; no fresh sweep needed)

### Engineering (CTO)

**Status:** reviewed (brainstorm + plan review)
**Assessment:** Extend the current stack; keep Phases 0, 1 and the status script, defer the rest. Give the operator a way to run an address through the resolver before it matters (`--resolve`). No Amazon SNS exists in the repo.

### Legal (CLO)

**Status:** reviewed (brainstorm)
**Assessment:** Not adoptable for per-user inboxes as it stands (full DPIA, Art. 28 chain, Resend DPA not on file). This plan adds no new vendor custody: the routing table stores addresses and workspace/owner ids, and no body column is added.

### Product (CPO)

**Status:** reviewed (brainstorm + plan review)
**Assessment:** No founder demand signal; accept only invisible, behavior-neutral preparation. **Product/UX Gate:** Tier none — the Files to Create / Files to Edit lists below contain no `components/**`, `app/**/page.tsx` or `app/**/layout.tsx` path, so the mechanical UI-surface override does not fire.

### GDPR gate (plan Phase 2.7, advisory)

`GDPR-Art-6` Important — `LAWFUL_BASIS` annotation on the new table (applied); `GDPR-Art-5e` Important — retention comment (applied); `GDPR-Art-17` Important — a RESTRICT FK to `users` would block account deletion, so the route FK is `ON DELETE CASCADE` (applied; fallback-reroute hazard recorded as a #9459 hard precondition); `GDPR-Chapter-V` none — no new vendor or SDK; `GDPR-Art-9` none. Added at review: `recipients` (normalized third-party addresses) now appear in the Inngest event payload and so in the run store; recorded in the PA-27 note. A DPIA is required before the first non-operator route (CLO screening triggers 1 and 2), recorded in #9459.

**Brainstorm-recommended specialists:** none named.

## Architecture Decision (ADR/C4)

### ADR

Create **ADR-269 — Inbound email routing table as the tenancy key for email-triage ingress** (provisional ordinal: highest existing is ADR-268; `soleur:ship` re-verifies against `origin/main`). Decision: ingress tenancy is resolved from the inbound recipient address through `email_inbox_routes`, with `EMAIL_TRIAGE_OWNER_USER_ID` as the no-match fallback while the table is operator-only; lookup errors and ambiguous (multi-route) matches throw, never fall back; vendor swap is bounded by three named seams (route.ts svix verify, `fetch-received-email.ts`, `outbound.ts`). **Hard preconditions before any non-operator route exists** (also in #9459): workspace-scoped `claim_key` and a workspace filter on the 23505 adopt query; a tombstone/quarantine rule so a deleted or disabled route never falls back to the operator; fan-out or quarantine for multi-route mail; envelope (`received_for`) vs header (`to`) key choice; per-owner LLM ceiling and statutory notification coalescing are keyed on `user_id` and multiply per route. Alternatives Considered: (a) plus-addressing on one mailbox (rejected: the Sieve forward collapses it); (b) per-tenant subdomain wildcard (deferred: DNS/Terraform surface, no demand); (c) adopt Resend Inboxes now (rejected in the brainstorm); (d) one webhook endpoint per tenant (rejected: webhook sprawl). Amend **ADR-066 Decision 4** (notification recipient is the single configured owner) with a pointer to ADR-269, not only the Consequences section.

### C4 views

Enumeration checked against `knowledge-base/engineering/architecture/diagrams/model.c4`: (a) external human actor — `emailSender` "Inbound Correspondent" (line 36) already modeled; (b) external system — `resend` (line 363) already modeled, no new vendor; (c) data store — a new table inside the existing `supabase` database element (line 240), no new container; (d) access relationship — unchanged (routes are service-role-only; reads stay Owner-scoped via ADR-066). Edits required: the edge `api -> supabase "Email-triage claim/finalize writes …"` (line 668) mentions the route-table read, and the `api -> resend` notification edge (line 666, "single configured recipient") is reworded to "the resolved route owner (the configured owner while no routes exist)". The work phase reads all three of `model.c4`, `views.c4`, `spec.c4` before editing, then runs `apps/web-platform/test/c4-code-syntax.test.ts`, `c4-render.test.ts` and `plugins/soleur/test/c4-count-parity.test.sh`.

### Sequencing

ADR-269 describes the target state and ships in this PR (accepted; the code ships dormant but real). It is not a follow-up issue.

## Implementation Phases

### Phase 0 — Empirical gate (before any code)

Prove the routing key before building on it.

- 0.1 Send ONE direct-to-inbound canary (from a Resend-verified sender to `triage@inbound.soleur.ai`), rely on the existing `ops@` -> Sieve traffic, read both rows back through the receiving API (address fields only) and confirm `to` carries the `@inbound.soleur.ai` address in both cases. Confirm the webhook delivers the same `to` (and whether `received_for` is present) by reading the first routed event's `recipients` in the work-phase test environment.
- **Result (2026-10-04, work phase).** The forwarded (`ops@` -> Sieve) path is proven: the receiving API returns `to: ["triage@inbound.soleur.ai"]` for the five most recent rows (measured earlier). No production canary was sent: a direct send to the inbound address would create a real triage row, notification and LLM call in the operator's production inbox, and a direct send's `to` is trivially the address it was sent to, so it proves nothing the forwarded rows do not. The webhook-vs-API `to` equivalence rests on Resend's published `email.received` payload and the SDK type (both list `to`/`received_for`); it is confirmed on the first routed event and is a #9459 hard precondition before any non-operator route (ADR-269). With the table empty, `recipients` is inert in production.
- 0.2 Record the result in Research Insights. **Failure branch:** if neither `to` nor `received_for` carries the forwarding address for Sieve-forwarded mail, there is no routing key and the plan stops here: #9458 is re-scoped to "ADR-269 + Phase 0 evidence only" and the routing code moves to #9459.

### Phase 1 — Routing table + resolver

**Consumer:** `email-on-received.ts` claim step (every mail with recipients runs the resolver; the table path is covered by unit tests, the verify file and `--resolve`; prd runs the env-owner path).

- 1.1 Migration `155_email_inbox_routes.sql` (+ `.down.sql`), provisional ordinal (re-check at ship):

  ```sql
  -- LAWFUL_BASIS: legitimate interest (Art. 6(1)(f)), see article-30-register PA-27.
  -- Retention: a route lives while configured; no purge job — rows are removed by the
  -- workspace-member cascade.
  CREATE TABLE public.email_inbox_routes (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    address       text NOT NULL,
    workspace_id  uuid NOT NULL,
    owner_user_id uuid NOT NULL,
    created_at    timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT email_inbox_routes_owner_member_fk
      FOREIGN KEY (workspace_id, owner_user_id)
      REFERENCES public.workspace_members (workspace_id, user_id) ON DELETE CASCADE,
    CONSTRAINT email_inbox_routes_address_shape
      CHECK (address = lower(address) AND char_length(address) <= 320
             AND address LIKE '%_@_%' AND address NOT LIKE '%@%@%')
  );
  CREATE UNIQUE INDEX email_inbox_routes_address_key ON public.email_inbox_routes (address);
  ALTER TABLE public.email_inbox_routes ENABLE ROW LEVEL SECURITY;
  REVOKE ALL ON public.email_inbox_routes FROM anon, authenticated;
  ```

  No RLS policies (service-role only; table-level REVOKE, per the column-grant learning). The composite FK makes a route's owner a member of its workspace at write time (`role='owner'` stays an application check, because a FK cannot express it). `ON DELETE CASCADE` follows the gdpr-gate `GDPR-Art-17` finding (a route is configuration, not statutory evidence, so it must not block account or workspace deletion); the fallback-reroute consequence is a hard #9459 precondition. The CHECK is deliberately loose (shape only) so it cannot drift from the strict JS validator in `events.ts`.
- 1.2 `server/email-triage/events.ts` (client-free module): add `normalizeInboundAddress(raw: unknown): string | null` (accepts `addr` or `Name <addr>`, lowercases, trims, validates with one strict regex, returns null otherwise) and an optional `recipients?: string[]` field on `EmailInboundReceivedData` (version stays `"1"`; absent ⇒ no routing).
- 1.3 `app/api/webhooks/resend-inbound/route.ts`: declare `to?: unknown` and `received_for?: unknown` on `ResendInboundBody.data`; `recipients` = the first 50 entries across both fields that normalize successfully, deduped and sorted; the event carries **normalized addresses only** (no display names). No dedup/verify/ordering change.
- 1.4 `server/email-triage/resolve-inbound-route.ts` — `resolveInboundRoute(recipients, deps)` → `{ workspaceId, ownerId, source: "table" | "env-fallback" }`. Empty `recipients` → env path with **no query**. Otherwise one `select … from email_inbox_routes where address in (…)`; a query error **throws** (retriable, never falls back); two or more distinct matching routes **throw** (ambiguous — #9459 designs fan-out); one match returns the row; no match → env fallback (`workspaceId = ownerId = EMAIL_TRIAGE_OWNER_USER_ID`, throwing the existing "unset" error only here). Owner validation (`users` row exists + `workspace_members(workspace_id, user_id, role='owner')`) moves from the inline block at `email-on-received.ts:322-365` into this module, generalized to the pair, with a memo keyed on `${workspaceId}:${ownerId}` and the existing 1h TTL. `resetOwnerValidationMemo` stays exported from `email-on-received.ts` (re-export) so existing imports keep working.
- 1.5 `email-on-received.ts`: call the resolver **inside `claim-insert`** and return `{ shortCircuit, id, ownerId, workspaceId }` from the step; every later use of `ownerId` (ceiling at :534, notify at :459/:508/:688) reads `claim.ownerId`. On the 23505 adopt path, take owner and workspace from the adopted row, not from a fresh resolve. A memoized claim from before the deploy (`{shortCircuit, id}` without `ownerId`) falls back to the env owner. The insert writes `user_id: ownerId`, `workspace_id: workspaceId`.
- 1.6 `apps/web-platform/server/dsar-export-allowlist.ts`: add `email_inbox_routes` to the exclusions with the reason "service configuration (addresses + workspace/owner ids), no data-subject content; revisit if per-user local parts are derived from personal names".
- 1.7 `apps/web-platform/supabase/verify/155_email_inbox_routes.sql`: asserts RLS enabled, zero policies, `anon`/`authenticated` have no privileges (queried from the live catalog, not grep), address uniqueness, the shape CHECK, the composite FK (a non-member owner is rejected) and the cascade. Runs in the release pipeline via `run-verify.sh`.

### Phase 2 — Observability

- 2.1 `apps/web-platform/scripts/email-route-status.sh` — read-only, Supabase REST with a service key from Doppler: prints `routes=<n>`; `--resolve <addr>` prints which route (or `env-fallback`) the address would take, so the operator can exercise the table path before it matters.
- 2.2 Route lookup errors and ambiguous matches surface through the existing Inngest-exhaustion Sentry capture; a lookup error **never falls back**.
- 2.3 The daily `cron-email-ingress-probe` keeps traversing the full chain (ops@ → Sieve → `triage@inbound` → webhook → resolver → row). With an empty table it proves the fallback path. #9459 must extend it with a direct-to-route canary before the first real route (ADR-126).

### Phase 3 — Documentation, registers, tests

- 3.1 ADR-269 + ADR-066 Decision 4 pointer; C4 edge edits (see above).
- 3.2 `knowledge-base/legal/article-30-register.md` PA-27: note the routing table (addresses + workspace/owner ids, service-role-only, lookup errors do not fall back) and that normalized recipient addresses now appear in the Inngest event payload under the existing run-store retention. No column-list change (the items table is untouched). Run the PA-27 validation the register cites.
- 3.3 No `.service-role-allowlist` entry is needed: the resolver receives the Supabase client as a parameter and imports no service-client factory (the allowlist keys on that import). `scripts/check-tom4-rls-posture.sh` gains `email_inbox_routes` in `NOT_CUSTOMER_DATA`, and `BASELINE_DECLARED_PROBES` in `plugins/soleur/test/preflight-discoverability-test.test.ts` rises 42 -> 43 (both found by the affected-test gate).
- 3.4 Tests first (`cq-write-failing-tests-before`): see Test Scenarios.

## Files to Create

- `apps/web-platform/supabase/migrations/155_email_inbox_routes.sql` (+ `.down.sql`)
- `apps/web-platform/supabase/verify/155_email_inbox_routes.sql`
- `apps/web-platform/server/email-triage/resolve-inbound-route.ts`
- `apps/web-platform/scripts/email-route-status.sh`
- `apps/web-platform/test/server/email-triage-resolve-route.test.ts`
- `apps/web-platform/test/server/email-triage-normalize-address.test.ts`
- `knowledge-base/engineering/architecture/decisions/ADR-269-inbound-email-routing-table-as-ingress-tenancy-key.md`

## Files to Edit

- `apps/web-platform/app/api/webhooks/resend-inbound/route.ts` (declare `to`/`received_for`, build `recipients`)
- `apps/web-platform/server/email-triage/events.ts` (`recipients?`, `normalizeInboundAddress`)
- `apps/web-platform/server/inngest/functions/email-on-received.ts` (resolver in `claim-insert`, carry ids, adopt path, `resetOwnerValidationMemo` re-export)
- `apps/web-platform/server/dsar-export-allowlist.ts` (exclusion entry)
- `apps/web-platform/test/server/inngest/email-on-received.test.ts` (resolver stubbing in the supabase mock; the env-unset-before-any-step assertion at line ~369 moves into the step)
- `apps/web-platform/test/server/resend-inbound-route.test.ts` (new cases)
- `apps/web-platform/.env.example` (comment: `EMAIL_TRIAGE_OWNER_USER_ID` is the no-route fallback)
- `scripts/check-tom4-rls-posture.sh` (classify the new zero-policy table) and `plugins/soleur/test/preflight-discoverability-test.test.ts` (credentials baseline 42 -> 43)
- `knowledge-base/legal/article-30-register.md` (PA-27 note)
- `knowledge-base/engineering/architecture/diagrams/model.c4` (edges at lines 666 and 668)
- `knowledge-base/engineering/architecture/decisions/ADR-066-email-triage-inbox-workspace-grain.md` (Decision 4 pointer)

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open --limit 200` filtered on bodies containing `email-on-received`, `resend-inbound` or `email_triage` returned an empty set (research agent, 2026-10-03).

## Observability

```yaml
liveness_signal:
  what: Sentry cron monitor cron-email-ingress-probe (daily end-to-end probe through ops@ -> Sieve -> inbound -> webhook -> resolver -> mail_class='probe' row)
  cadence: daily 06:00 UTC, check-in margin 60 min
  alert_target: Sentry issue alert routed to the operator (email + native Slack per the existing monitor)
  configured_in: apps/web-platform/infra/sentry/cron-monitors.tf (resource cron_email_ingress_probe)
error_reporting:
  destination: Sentry web-platform via SENTRY_DSN (Inngest function-failed capture on exhaustion)
  fail_loud: a route lookup error or an ambiguous match throws inside claim-insert; Inngest retries once, then the function-failed capture fires; the probe monitor goes red if the chain stops landing rows
failure_modes:
  - mode: route lookup query errors (Supabase/PostgREST failure)
    detection: Inngest function failure capture + probe monitor status=error within the day
    alert_route: Sentry issue alert -> operator
  - mode: two routes match one mail (ambiguous)
    detection: the resolver throws; Inngest exhaustion capture
    alert_route: Sentry issue alert -> operator
  - mode: a route row is mis-keyed to the wrong workspace
    detection: the composite FK rejects a non-member owner at write time, UNIQUE(address) rejects duplicates, the resolver's owner-role validation throws for a non-owner, and email-route-status.sh --resolve shows the target before any traffic
    alert_route: validation failure throws -> Sentry
  - mode: a real address matches nothing and falls back to the owner once routes exist
    detection: not possible while the table is operator-only; ADR-269 makes the quarantine rule and a Sentry signal a #9459 hard precondition
    alert_route: Sentry (added by #9459)
logs:
  where: Sentry (events) and Inngest run history on the self-hosted instance; no body, subject or sender is logged (TR3); the event payload carries normalized recipient addresses only
  retention: Sentry plan retention; Inngest run store per ADR-033
discoverability_test:
  command: bash apps/web-platform/scripts/email-route-status.sh
  expected_output: routes=
  credentials_required: Doppler soleur/prd SUPABASE_SERVICE_ROLE_KEY read — email_inbox_routes is service-role-only with no policies, so no unauthenticated probe can read its state
```

## Encryption Posture

```yaml
at_rest:
  - store: supabase.prd public.email_inbox_routes (new)
    mechanism: provider-managed:Supabase Postgres storage encryption (AES-256 at rest), attestation retrieved from the Supabase security page
    evidence: knowledge-base/legal/compliance-posture.md (Supabase row) and the existing PA-27 TOMs line citing provider-managed encryption for email_triage_items
    defends_against: a stolen or RMA'd disk and a raw storage-layer snapshot of the managed Postgres volume
    does_not_defend: a leaked service-role key (this table is service-role-only, so that key reads every route), an RLS bypass, a SQL-injection read, or an operator with project access
    disclosed_as: docs/legal/gdpr-policy.md (Supabase processor section) — no per-table claim is made for the routing table, so the literal not-publicly-claimed
    live_verification: unavailable:Supabase does not expose per-table encryption state through any API
in_transit:
  - connection: web-platform server (Inngest function / webhook route) -> Supabase REST (PostgREST)
    enforced_at: apps/web-platform/lib/supabase/service.ts (createServiceClient, https:// project URL)
    tls: HTTPS, TLS 1.2+ as terminated by Supabase
    cert_verification: on
    does_not_defend: a compromised server process holding the service key
    disclosed_as: not-publicly-claimed
```

## Acceptance Criteria

- [x] AC-1 (Phase 0): the routing key is proven for the Sieve-forwarded `ops@` path (receiving API `to`); the result and the deliberate decision not to send a production canary are recorded under Phase 0. Webhook-vs-API `to` equivalence is confirmed on the first routed event (ADR-269 / #9459 precondition).
- [x] AC-2: with `email_inbox_routes` empty or `recipients` empty/absent, `email-on-received` behaves as before: same `user_id`/`workspace_id`, same notification recipient, and **no route query is issued**. Existing tests pass after the two documented mock/assertion edits (resolver stubbing; env-unset error now thrown inside the step).  *(Superseded — see `## Review Revisions` at the end of this plan.)*
- [x] AC-3: a recipient matching a route resolves to `route.workspace_id`/`route.owner_user_id`; the row is inserted under those values; the ceiling and notification use `claim.ownerId`.
- [x] AC-4: a route-lookup error throws (retriable) and never falls back; two distinct matching routes throw; an owner-validation failure throws.  *(Superseded — see `## Review Revisions` at the end of this plan.)*
- [x] AC-5: replay safety — a retry after the claim step reads ids from the memoized `claim` and never re-resolves; the 23505 adopt path takes owner/workspace from the adopted row; a pre-deploy memoized claim without `ownerId` uses the env owner (tests for each).
- [x] AC-6: `anon` and `authenticated` cannot select/insert/update/delete `email_inbox_routes`; a route whose owner is not a member of its workspace is rejected by the composite FK (verify SQL against the live catalog; the FK rejection and cascade were also exercised behaviorally on dev inside a rolled-back transaction).
- [x] AC-7: `normalizeInboundAddress` handles `Name <a@b>`, uppercase, whitespace, non-string input and malformed values; webhook route test: payload with `to`/`received_for` produces normalized, deduped, sorted `recipients` (cap 50); payload without them, or with non-string entries, yields no `recipients` and still returns 200 with unchanged verify/dedup ordering.
- [x] AC-8: no body column and no header data are added; the fused step's return shape is unchanged.
- [x] AC-9 (gdpr-gate): deleting a workspace member who owns a route removes the route; migration 155 carries the `LAWFUL_BASIS` and retention comments; `DSAR_TABLE_ALLOWLIST` gate and PA-27 validation pass.
- [ ] AC-10: ADR-269 exists with the hard preconditions and is correctly numbered against freshly fetched `origin/main` at ship time; migration ordinal 155 re-verified free at ship time; ADR-066 Decision 4 pointer added; C4 edge edits made and the C4 tests plus `c4-count-parity` pass; no `.service-role-allowlist` entry is needed (the resolver imports no service-client factory); TOM-4 posture and the credentials baseline are updated.
- [x] AC-11: `email-route-status.sh --resolve <addr>` prints the chosen route or `env-fallback`.
- [ ] AC-12: PR body carries `Closes #9458`; #9459's body lists the deferred items (`agent_id`, `thread_key`, `InboxProvider`, WORM rewrite) and the hard preconditions.

## Test Scenarios

- Given an inbound event with no `recipients`, then the env owner is used and no route query is issued.
- Given `recipients: ["triage@inbound.soleur.ai"]` and no route rows, then the env owner is used (fallback).
- Given a route `cro@inbound.soleur.ai → workspace W, owner U` and an event for that recipient, then the row has `workspace_id = W`, `user_id = U` and the notification goes to U.
- Given two routes matching one event, then the handler throws and inserts nothing.
- Given the route lookup throws, then the handler throws and inserts nothing; given a route whose owner is not a workspace owner, then it throws.
- Given a replay of the notify step after the claim step, then no second resolve occurs (spy asserts one query).
- Given an adopted unfinalized stub with a different owner than a fresh resolve would give, then the adopted row's owner is used.
- Given a pre-deploy memoized claim `{shortCircuit: false, id}`, then the env owner is used.
- Mutation rows (regression guards, not a new gate): replacing the resolver's lookup-error `throw` with a fallback must fail the AC-4 test; resolving the route outside `claim-insert` must fail the AC-5 replay test.

## Dependencies & Risks

- **Dormant until a route exists.** Mitigated by AC-2 (prd path unchanged, no query for empty recipients) and by unit/verify coverage of the table path.  *(Superseded — see `## Review Revisions` at the end of this plan.)*
- **Hard preconditions for any non-operator route** (ADR-269, #9459): workspace-scoped claim key and adopt query; quarantine instead of operator fallback after a route is deleted (the FK cascade re-routes a deleted tenant's address to the operator otherwise); multi-route fan-out; `received_for` vs `to` choice; per-owner ceiling and statutory coalescing multiply per route; a DPIA and a Resend DPA before per-user custody.
- **Header `to` is a weak tenancy key** (misses Bcc, lists, aliases): Phase 0 decides whether `received_for` is read; both fields feed `recipients`.
- **Migration ordinal collision.** 155 is provisional; re-check at ship time (`git ls-tree origin/main -- apps/web-platform/supabase/migrations/`).
- **Resend `to` semantics unproven for webhooks.** Gated by Phase 0; only the extraction line in Phase 1.3 changes if wrong.

## Sharp Edges

- Resolving the route outside `claim-insert` reintroduces the replay hazard (a retry can notify a different owner than the row's `user_id`); AC-5 guards it.
- The CHECK on `address` is intentionally loose; the strict validator is the JS function in `events.ts`, so a change to the address rules is a one-place edit.
- Any plan edit that empties `## User-Brand Impact` or removes the threshold fails `deepen-plan` Phase 4.6.

## Review Revisions (2026-10-04, 12-seat review of PR #9456)

Appended; the sections above record the plan as reviewed at plan time.

- **"Dormant / byte-identical in prod" was false.** Sieve-forwarded `ops@` mail
  carries `to: triage@inbound.soleur.ai`, so `recipients` is non-empty on every
  real event and every mail issues one routes query. Restated in ADR-269
  Decision 4 and Consequences. Only an event with empty `recipients` skips the
  query.
- **Fail-closed on a lookup error would drop the operator's statutory mail**
  (`retries: 1`, webhook already returned 200; a PostgREST schema-cache miss
  after migrate or a rollback hits every mail). Replaced: a lookup error
  degrades to the env owner and reports `op: route-degraded` (pg code only).
  AC-4's "never falls back" is superseded for the operator-only phase.
- **The operator-only invariant is now enforced in the resolver**, not just
  documented: every matched route must be the operator pair, else the mail is
  claimed under the operator and reported. Two aliases of the operator are not
  ambiguous. Fail-closed returns with the first non-operator route (#9459).
- **Routing key is sender-controlled** (`to` header). `received_for` is listed
  first and the cap is 20 valid addresses, so a long `to` cannot displace the
  envelope address. Route-plus-operator co-addressing, memo staleness and
  rollback order were added to the #9459 preconditions.
- **Cut:** `workspaceId` is no longer carried in the claim step return or the
  adopt select (nothing read it). The unset-env pre-check stays unconditional.
- **Hardening:** migration 155 gained the FK precondition guard (lint), the
  verify SQL asserts constraint/index definitions and a service-role positive
  control, `email-route-status.sh` re-execs once, refuses xtrace (exit 78) and
  opens a read-only session.
- **Tests added** for the nine mutants the test-design seat found surviving
  (pair-keyed memo and TTL, adopt select columns, `received_for` as a source,
  valid-vs-raw cap, per-source cap, cap constant, sort on early return).

