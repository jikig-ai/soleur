---
title: "fix: Complete Codex notice access and bounded retention"
type: fix
date: 2026-10-26
slug: fix-codex-notice-rights-and-retention
branch: feat-one-shot-codex-web-live-paths
lane: cross-domain
priority: p1
domain: legal
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
requires_clo_review: true
issue: 11170
related_pr: 9051
cpo_signoff: granted-2026-10-26
user_impact_review: concur-2026-10-26
gdpr_gate: advisory-run-art-5e-retention-finding
status: draft-policy-approved-pending-plan-review
clo_decision: knowledge-base/legal/audits/2026-10-26-codex-notice-rights-retention-decision.md
operator_policy_acceptance: approved-2026-10-26
---

# Complete Codex Notice Access and Bounded Retention

## Overview

Add a member-scoped Article 15 path for retained Codex history-transfer notice
metadata, without granting direct access to the private issuance table. Set and
enforce a CLO-approved maximum lifetime for a pending nonce issuance, and clean
up abandoned rows in bounded batches. Preserve the existing ownership,
generation, membership, delivery and one-use acknowledgment checks. An expired
or acknowledged notice must never send or resume a provider request by itself.

The October 26 internal CLO source assessment classifies
`codex_history_transfer_notice_issuances` as pseudonymous Customer Data in
TOM 4 shape (iv): RLS enabled, zero policies, no direct table grants, and a
narrow RPC surface. It withholds processing clearance pending purpose, rights
and retention controls. Both hosted App Server authentication modes remain
blocked, and customer-content processing remains blocked. This plan does not
change those dispositions.

## Premise Validation

Issue [#11170](https://github.com/jikig-ai/soleur/issues/11170) records the
subject-access omission and lack of server-side expiry. The authoritative
source assessment is
[`2026-10-26-codex-nonce-ledger-and-hosted-auth-recheck.md`](../../legal/audits/2026-10-26-codex-nonce-ledger-and-hosted-auth-recheck.md).
The audit and source were read from PR #9051's recovery worktree after its
migration rename; no live catalog or customer rows were read for this plan.
The existing acknowledgment export is not evidence that issuance and delivery
metadata are included. The 30-minute browser-held-turn cache is not a database
retention limit.

## Research Insights

### Premise Validation

The issue and the dated CLO source audit were read from the recovery worktree.
The audit confirms that the member-linked issuance metadata has no DSAR export
path and that the table has no server expiry or abandoned-row cleanup bound.
The source migration and DSAR worker confirm that acknowledgment export is a
separate table/path. The issue's “30-minute” browser cache is not a server
retention control. The table's direct grants remain revoked, including
`service_role`; no live catalog, customer row, or shared database was read.
These premises hold at the inspected source revision; current live schema
equivalence and writer coordination remain unverified.

### Property List

- A member's access bundle contains the CLO-approved metadata for that
  member's retained notice issuance and excludes nonce authenticators.
- An issuance cannot be delivered or consumed after a justified maximum
  server lifetime, and expired rows are removed in bounded monitored batches.
- Same-nonce retry and new-nonce replacement have distinct, deterministic
  issuance-clock behavior.
- Expiry, acknowledgment, and cleanup preserve the held message and never
  dispatch provider work without a later explicit member action.
- Ownership, generation, membership, erasure, and existing no-direct-grant
  boundaries remain effective across all relevant paths.
- Legal and processing records describe the implemented fields, purposes,
  roles, retention and deletion behavior without implying consent or provider
  authorization.

### Mechanism Comparison and Cut List

The issue requests a scoped metadata export, a maximum server lifetime,
bounded cleanup, retry/reissue semantics, lifecycle coverage, and preservation
of forward-only migration history. Existing acknowledgment export does not
provide issuance metadata; existing generation and foreign-key cleanup does
not bound an abandoned row while its parent records remain; the browser cache
does not enforce server retention. No existing mechanism found in the source
review satisfies those properties. The proposed projection RPC, expiry
predicate, bounded cleanup RPC, and current-nonce timestamp rules each address
one of those gaps. The existing direct-grant revokes and scheduled-job
monitoring patterns are constraints to preserve or reuse, not substitutes for
the missing properties.

| Cut | Property | Existing coverage |
|---|---|---|
| Direct `service_role` table `SELECT` for export | Member-scoped metadata access | Existing TOM 4 and migration grant revokes already enforce the narrower access boundary; use a definer projection instead. |
| Unbounded whole-table cleanup or a second scheduler | Bounded, monitored deletion | Neither is required: the cleanup RPC must use indexed batches, and the implementation must reuse one suitable monitored schedule if source inventory confirms one. |

No requirement is cut. Exact schedule selection remains contingent on the
Phase 2 inventory, and no live behavior is asserted from this source-only
research.

### Relevant Source and References

- `apps/web-platform/server/dsar-export.ts` and
  `apps/web-platform/server/dsar-export-allowlist.ts` — current subject export
  boundary and per-table query path.
- `apps/web-platform/supabase/migrations/175_codex_history_notice_issuance.sql`
  — current issuance table, RPCs, lifecycle cleanup and revoked direct grants.
- `apps/web-platform/server/ws-handler.ts` and
  `apps/web-platform/server/codex-held-turn-cache.ts` — acknowledgment and
  explicit held-message behavior.
- `knowledge-base/legal/audits/2026-10-26-codex-nonce-ledger-and-hosted-auth-recheck.md`
  — source classification and withheld processing clearance.
- `knowledge-base/project/learnings/best-practices/2026-04-15-plan-skill-reconcile-spec-vs-codebase.md`
  — reconcile source claims against implementation before qualification.
- Related tracking: issue #11170 (this correction), issue #11165 (source
  classification), and PR #9051 (draft rollout; independent holds remain).

The issue does not prescribe a duration, legal basis, Article 15 scope after
consumption, Article 20 disposition, or schedule substrate. The accepted CLO
decision below now supplies the legal policy; schedule selection and factual
clearance remain
decision gates, not research assumptions.

## User-Brand Impact

**Brand-survival threshold: single-user incident**

The worst credible result is one member's notice metadata omitted from access,
retained beyond its necessary use, or used to accept a stale acknowledgment.
The issue and audit do not establish actual customer exposure.

- **Authenticated conversation owner requesting a provider-mode change.**
  **Artifact:** their held `message.body`, `conversation.id`, and issuance
  `issued_at`/`delivered_at`. **Vector:** the DSAR allowlist omits issuance
  metadata, or replacement/expiry logic drops the held notice path or accepts
  an old nonce. **Coverage:** the approved Article 15 projection and per-row
  export tests, same-nonce versus replacement timestamp tests, expiry boundary
  tests, and held-message-preservation tests are acceptance criteria.
- **Authenticated DSAR requester who is a different workspace member.**
  **Artifact:** another member's `codex_history_transfer_notice_issuances`
  row and `conversation.id`. **Vector:** a subject-scope bug in the definer
  projection returns another member's row in the requester's archive.
  **Coverage:** the projection filters on the verified subject, the worker
  applies `assertReadScope`, and cross-member integration tests must fail the
  export before any partial archive is published.
- **Authenticated caller attempting acknowledgment without the notice.**
  **Artifact:** the owner's acknowledgment state and `nonce_hash`. **Vector:**
  exporting the hash or restoring the legacy two-argument RPC lets a caller
  acknowledge without possession of the delivered nonce. **Coverage:** the
  projection omits the hash, the exact overload/RPC-grant gate rejects the old
  path, and wrong-hash, undelivered and replay integration tests remain red.
- **Conversation owner whose notice reaches its expiry boundary.**
  **Artifact:** the held `message.body` and current issuance nonce. **Vector:**
  an expiry race either loses the held message or accepts a stale nonce; an
  expiry or acknowledgment handler could accidentally resume a provider turn.
  **Coverage:** before/at/after-boundary tests require fail-closed behavior,
  preserve the held message, and assert zero provider requests until a later
  explicit member action.
- **Member with an abandoned delivered issuance.** **Artifact:** their
  conversation/member-linked issuance row. **Vector:** a stalled or failing
  cleanup leaves it indefinitely, while an unbounded sweep can lock unrelated
  user rows. **Coverage:** CLO-approved maximum lifetime, indexed bounded
  batches, concurrency/retry tests and a Sentry cron monitor with a missed-run
  alert are acceptance criteria.
- **Member whose issuance is included in an access export.** **Artifact:**
  `conversation.id`, generation and issuance/delivery timestamps.
  **Vector:** the export reveals raw nonce/hash material or logs identifiers
  during a failed projection. **Coverage:** the output schema excludes nonce
  fields, tests inspect archive and error/log payloads, and failures prevent
  partial archive publication.
- **Customer administrator or counsel signing the DPA.** **Artifact:** Schedule
  4 TOM 4 statements about issuance access, retention and member rights.
  **Vector:** changing the DPA before the CLO-approved maximum lifetime, legal
  basis and export scope match the implementation gives the signer an
  inaccurate processing commitment. **Coverage:** DPA changes are blocked
  until CLO approves exact wording; the final cross-document check must verify
  the contract against the implemented grants, projection, expiry and cleanup.

The CPO approved the `single-user incident` threshold and P1 planning priority
on 2026-10-26. The user-impact-reviewer concurred on 2026-10-26 after the
role-by-role artifact/vector review. These are impact-framing signoffs only.
The advisory GDPR gate identified the missing enforced server-retention bound.
The later CLO decision supplies the proposed policy, which the operator
accepted; implementation and final factual/legal qualification remain open. The existing
TOM 4 classification attestation does not substitute for them.

## Current Data-Flow Inventory

| Operation | Current path | Personal-data and access boundary |
| --- | --- | --- |
| Issue or replace | `dispatchCodexChatTurn()` calls `issue_codex_history_transfer_notice` using the service client before sending the notice. The RPC upserts the nonce hash and clears `delivered_at`; a replacement currently retains the old `issued_at`. | The row binds conversation, workspace, member, auth generation, membership epoch, nonce hash and timestamps. It contains no message body or raw nonce. |
| Mark delivered or repair | `persistCodexNoticeDelivery()` calls `mark_codex_history_transfer_notice_delivered` after socket send acceptance or authenticated reconnect repair. | The service RPC rechecks current conversation owner, generation and membership epoch and matches the nonce hash. |
| Remove unsent issuance | `discardCodexNoticeIssuance()` calls `delete_codex_history_transfer_notice_issuance` after failed or superseded sends. | The RPC deletes only the matching row while `delivered_at IS NULL`. |
| Acknowledge | WebSocket message `codex_history_transfer_acknowledge` uses the tenant JWT to call the three-argument acknowledgment RPC. That function consumes only a matching delivered issuance, then records an acknowledgment. | Possession hash is required. The client acknowledgement path emits a response; it does not itself dispatch a provider request. |
| Lifecycle cleanup | Migration 175 deletes pending rows when the auth-mode generation or membership epoch changes. Conversation, user and membership foreign keys cascade on deletion. | These are real lifecycle bounds but do not bound abandoned rows whose parents and generation remain. |
| Browser cache | `codex-held-turn-cache.ts` keeps a bounded held message and raw notice nonce in tab memory for up to 30 minutes; it clears on auth-scope change, expiry or reload. | This is distinct from database retention. Never log, export or persist the raw nonce. |
| Member access export | `DSAR_TABLE_ALLOWLIST` and `exportSqlTable()` include `codex_history_transfer_acknowledgments` by member. Issuance metadata appears in neither allowlist nor exclusions and has no export read path. | The worker uses a service client. The issuance table revokes direct table privileges from PUBLIC, `anon`, `authenticated` and `service_role`; that invariant must remain. |
| Current expiration | No database expiry column/check or abandoned-row sweep exists for the issuance table. | `issued_at` is not refreshed when a replacement nonce hash is stored, so it cannot currently express the current nonce's age. |

## Technical Approach

### 1. Member access projection

The October 26 CLO decision and operator acceptance approve Article 15 access
and conservative Article 20 inclusion for eligible service activity. This is
an independently assessed portability decision, conditional on the subject's
actual basis and controller capacity. The export worker must
read the metadata through one narrowly scoped `SECURITY DEFINER` projection RPC
with `search_path = public, pg_temp`, qualified relations, and a subject ID
argument supplied by the already-authenticated DSAR job. Grant execution only
to the server service role. Do not grant direct `SELECT` on the table to any
role.

Return every retained non-secret subject field or its faithful intelligible
equivalent: conversation, workspace and member references, generation,
membership timestamp, issuance and delivery-marker times, and expiry if stored.
Explain generation and membership context; do not include other members' data.
Do not return `nonce_hash` or raw nonce in the automatic bulk projection. The hash
is an authenticator: exposing it could let an authenticated caller satisfy the
hash-based acknowledgment protocol without possessing the notice nonce. The
RPC must select only rows owned by the requested member; `exportSqlTable()` must
apply `assertReadScope` to the response and fail the job if any returned member
does not match the verified subject.

The current worker lint requires a literal `.from(table).select().eq(owner)`
chain for every allowlisted table. Extend that lint with one explicit,
mutation-tested RPC projection case for this table. Keep the regular direct
table rule for every other allowlisted table. Update
`dsar-allowlist-completeness.test.ts`, worker per-row tests, archive manifest and
cross-tenant integration tests. A raw table name in an allowlist must not
silently authorize a direct service-role query.

Successful acknowledgment may delete the issuance without permanent history.
Preserve eligible non-secret metadata existing when the controller receives an
access request, before asynchronous export can lose it to acknowledgment,
expiry, erasure or lifecycle cleanup. Bind preservation to request admission
with an atomic or equivalently proven procedure, including the email channel.
Data genuinely deleted before receipt need not be recreated. The separate
acknowledgment is not a complete notice history. The rights-response copy has
its own necessary fulfillment purpose and lifecycle; prove its actual archive,
failure and deletion behavior before final CLO clearance. Download-link expiry
alone is not deletion evidence. Never preserve replay authenticators.

### 2. Expiry and bounded cleanup

Do not edit or replay migration 175. After rechecking the live main migration
ordinal and branch ownership, add a forward migration (expected next ordinal
176; reallocate if main has advanced) that adds a current-nonce expiry value,
an index supporting bounded cleanup, and the required narrow RPC changes. Do
not rename or rewrite existing migration bytes. The migration must preserve the
zero-policy and no-direct-table-grant posture.

Use these timestamp semantics:

- `issued_at` denotes the current nonce hash's issuance time.
- An exact same-nonce retry or delivery-marker repair does not extend the
  lifetime.
- A new nonce hash is a new notice issuance: reset `issued_at`, calculate its
  expiry, and clear `delivered_at` in the same upsert.
- `mark_codex_history_transfer_notice_delivered` and the three-argument
  acknowledgment RPC reject at or after expiry. The issuance RPC may replace
  an expired row only when it is creating and sending a new notice through the
  existing explicit notice flow.

The accepted proposed policy is **30 minutes of nonce usability**, followed by
at most **five further minutes for primary-table deletion**: a 35-minute ordinary
abandoned-row residence ceiling. This is a controller policy, not a statutory
duration or current enforcement. Include scheduler, queue, batch, lock and retry
delay in the erasure bound; prove capacity and alert early enough to intervene.
Block new issuance when required cleanup health is unavailable. Same-nonce
retries never renew lifetime. Managed backups/PITR and rights-response copies
remain distinct factual/lifecycle clearance conditions in the CLO decision.

Use the existing scheduled-retention patterns only after confirming their
monitoring and ownership properties. Prefer a monitored Inngest scheduled
function that invokes a narrow cleanup RPC if it provides an existing Sentry
heartbeat and an acceptable interval. The RPC deletes expired rows in bounded
indexed batches using a concurrency-safe lock strategy, returns a count only,
and never returns subject IDs, conversation IDs or hashes. It must not clear a
held message, deliver a notice, acknowledge a transfer or dispatch provider
work. If a suitable existing monitored schedule already covers this class,
extend it; do not install a second scheduler.

Keep the retention RPC's only execution grant narrow. The cleanup service
reaches rows through the definer function, never direct table privileges.
Preserve account, conversation, membership and generation deletion behavior.
Update the DPA template and dated PA-2/compliance processing record to describe
the actual mutable receipt and expiry/cleanup path; do not call it WORM or an
immutable accountability ledger.

### 3. Expiry behavior at the WebSocket boundary

An expired acknowledgment fails closed with a stable, content-free error code
that asks the member to review a newly issued notice. Keep the held message
available for explicit resend under the existing bounded cache; do not silently
drop it or replay it to a provider. A fresh notice requires a new nonce and a
new explicit member action. Tests must prove both that expiration alone and
acknowledgment alone cause zero provider requests.

Reuse the current notice surface if its served behavior can present renewal
without a new component or flow. If the implementation needs a changed UI
surface, stop before UI coding until a `.pen` wireframe is committed, then test
the served view with screenshots. Update client-facing copy to describe an
expired notice and review action; never describe nonce possession as proof of
reading or consent.

## Legal and Operator Decisions

1. **Accepted internal policy:** the source-based [CLO decision](../../legal/audits/2026-10-26-codex-notice-rights-retention-decision.md)
   supplies the proposed 30-minute validity/five-minute deletion limits, narrow
   service purpose, faithful non-secret Article 15 projection, request-receipt-
   time preservation, ordinary post-ack deletion and independently assessed
   Article 20 inclusion for eligible service activity. The operator explicitly
   approved this legal-risk policy for implementation and isolated testing.
2. **Remaining basis/capacity facts:** Article 6(1)(b) applies only to a verified
   contracting subject where objectively necessary. Team/noncontracting roles
   remain blocked pending the actual controller basis/instructions. No separate
   security/accountability purpose or Article 6(1)(f) fallback is approved.
3. **Remaining lifecycle facts:** establish actual backup/PITR handling and the
   rights-response copy/archive failure, restore and deletion lifecycle before
   final processing clearance. The bulk authenticator exclusion does not waive
   case-specific handling of an explicit full-access request.
4. **CLO processing-record decision:** define the exact dated PA-2/compliance
   amendment, retention wording and role split. Update the processor register
   only if the actual processing activity warrants it. No provider permission
   follows from these local controls.
5. **Approval boundary:** operator policy acceptance does not authorize a new
   shared-database read/write, provider request, customer processing, readiness,
   merge or deployment. Follow the exact recovery-evidence approval boundary.

The accepted policy comes from the CLO and operator; it is not a CTO ruling or
professional counsel opinion. The CTO technical design recommendation is the
projection RPC, current-nonce timestamps, fail-closed expiry checks and bounded
cleanup described above.

## Data Safety and Rollback

- Keep all prior migration SQL bytes unchanged. Run the new migration only in
  disposable PostgreSQL until the transaction, grants, FK cascades, schedule,
  backfill, expiry boundary and cleanup are verified.
- Do not connect the test harness to a configured dev/prod URL, use provider
  credentials, include customer content, or dispatch Docker/Supabase work
  implicitly. Use synthesized users, conversations and hashes only.
- If a deployed schema correction needs rollback, disable the cleanup schedule
  and roll application code forward to a safe state. Do not drop the expiry
  column, purge function or table while pending records exist. Deletion of
  expired rows is the intended retention action and cannot be undone by a
  schema rollback; preserve a metadata-only run receipt without member IDs or
  hashes for operational verification.
- Verify the account-deletion, conversation-deletion and membership-removal
  paths remain effective. Test the cleanup's bounded row count and index use;
  no full unbounded table delete is acceptable.
- Do not perform shared reconciliation, new shared catalog capture, migration
  application, provider request, account login or production change under this
  plan. Each later shared operation requires its own exact approval and all
  legal and technical gates.

## Test Scenarios

- Given a synthetic member with one retained issuance, when their DSAR job runs,
  then the bundle contains only the approved metadata fields and marks the
  record as Article 15 unless CLO separately approves portability.
- Given a different member's issuance, when the subject export runs, then the
  row is absent; a mismatched RPC result fails the job and no partial archive is
  published.
- Given the issuance table, when a source/test mutant grants direct service
  `SELECT`, adds an RLS policy/client grant, broadens the projection RPC, or
  includes `nonce_hash`, then the respective gate turns red.
- Given an issuance before expiry, at the exact boundary and after expiry,
  when delivery repair or acknowledgment runs, then only the pre-expiry case
  can proceed.
- Given a same-nonce retry, when its marker is repaired, then `issued_at` and
  expiry do not move. Given a newly generated nonce, when the issue RPC replaces
  the hash, then the current nonce gets a new issuance time/expiry and the
  delivered marker clears.
- Given expired rows and concurrent users of the RPC, when one cleanup batch
  runs, then it deletes no more than the configured batch bound, skips rows
  already locked, returns only an aggregate count, and remains safe on retry.
- Given an expired held notice, when its acknowledgment arrives, then the server
  returns the renewal code, preserves the held message, sends no provider
  request and does not mark the conversation acknowledged. Only a later
  explicit member action can resend.
- Given auth-generation change, membership-epoch replacement, account deletion,
  conversation deletion or membership removal, then existing lifecycle cleanup
  remains correct and is not delayed by the retention sweep.
- Given a cleanup failure, then Sentry receives a bounded failure event without
  subject identifiers or nonce material; the following scheduled run can retry.

## Work Phases and Gates

1. **Confirm scope and sign-offs:** CPO and user-impact-reviewer signoffs are
   recorded for the single-user impact threshold. The CLO decision and operator
   acceptance supply the legal policy for implementation and isolated testing.
   The advisory `soleur:gdpr-gate` recorded the missing enforcement finding.
   Final factual/legal processing clearance remains withheld.
2. **Inventory schedulers and schema:** inspect existing DSAR grant/query
   assertions, `pg_cron` retention patterns, Inngest cron monitors and cleanup
   callers. Recheck migration ordinal, affected user-FK tables and existing
   server flags. Select exactly one monitored cleanup substrate and calculate
   the bounded sweep cadence from the approved maximum.
3. **RED tests first:** add failing tests for the projection RPC, allowlist and
   per-row lint exception, field minimization, Article 15 manifest, tenant
   isolation, direct-grant rejection, expiry boundary, same-hash retry,
   replacement timestamp, scheduled batch bound, cleanup retry, deletion
   cascades and zero-provider dispatch. Verify the mutants fail the intended
   assertions.
4. **GREEN implementation:** add the forward migration after source ordinal
   remeasurement; implement the read projection and retention RPCs; update the
   worker, allowlist and reviewed static lints; add expiry response handling and
   the single monitored cleanup job. Keep existing table privileges at zero.
5. **Offline integration and QA:** execute tests only in disposable PostgreSQL
   with synthetic fixtures and no ambient DB/provider credentials. Run focused
   migration/DSAR/handler suites, RLS fuzz, typecheck, DPA/TOM4 and repository
   static checks. Verify archive contents and that raw nonce/hash never enters
   output, logs or errors. Run `soleur:gdpr-gate`, CLO review, code review and
   QA on the exact source head.
6. **Records and qualification:** append a dated, merge-and-migration-
   conditioned PA-2/compliance record and update the DPA representation only
   after CLO approval. Re-run legal cross-document gates. Later runtime
   qualification requires fresh exact-head recovery and provider permission for
   the actual route, a current served-build notice/renewal test, and all data and
   writer-coordination gates. Keep customer content blocked until that separate
   clearance exists.

## Observability

```yaml
liveness_signal:
  what: "Most recent scheduled expiry-cleanup completion and aggregate rows deleted"
  cadence: "One check-in per scheduled invocation; cadence must keep worst-case cleanup delay inside the CLO-approved retention maximum"
  alert_target: "Web Platform engineering on-call"
  configured_in: "Registered Inngest scheduled cleanup function, Sentry cron monitor, and the existing cron-monitor Terraform inventory"
error_reporting:
  destination: "Sentry web-platform with Inngest function/run correlation and release SHA"
  fail_loud: "Expiry checks reject stale delivery/acknowledgment; cleanup failure raises the monitored run; DSAR projection failure fails the export job before an archive is published"
failure_modes:
  - mode: "Delivery repair or acknowledgment reaches the expiry boundary"
    detection: "Layer 2 Pino to Sentry mirror records a bounded expiry code; Layer 5 Sentry release context binds it to the served SHA"
    alert_route: "Web Platform engineering on-call"
  - mode: "Scheduled cleanup is late, errors, or returns an invalid batch count"
    detection: "Layer 1 Inngest Sentry-correlation middleware plus the Sentry cron monitor; monitor must alert before the approved maximum expires"
    alert_route: "Web Platform engineering on-call"
  - mode: "DSAR projection fails or violates subject scope"
    detection: "Layer 2 Pino to Sentry mirror and the DSAR job's persisted failed status; no partial archive is published"
    alert_route: "Web Platform engineering on-call and the DSAR request status"
  - mode: "Cleanup repeatedly fails while the process remains otherwise live"
    detection: "Layer 1 Inngest Sentry-correlation middleware and the Sentry cron monitor's missed-check-in alert"
    alert_route: "Web Platform engineering on-call"
logs:
  where: "Sentry events and Inngest run metadata; aggregate deleted-row count only"
  retention: "Existing Sentry and Inngest retention; CLO must confirm the applicable retention before qualification"
discoverability_test:
  command: "bash apps/web-platform/scripts/codex-notice-retention-status.sh prd"
  expected_output: "job_status=ok"
  credentials_required: "Doppler soleur/prd read-only database credential; the last cleanup result is private database state and has no unauthenticated public probe"
```

The planned status command must query only the scheduled job's bounded status,
use TLS verification and avoid placing the database URL/password in process
arguments or logs. Its implementation and exact success output are acceptance
criteria; it must not be treated as available until added and tested.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 [issue #11170] | "Add a narrowly scoped member metadata export path and completeness tests; do not export the nonce or its hash, and document a specific security projection rationale." | Member access projection; Phase 3–5; DSAR worker/RPC/tests | mapped |
| 2 [issue #11170] | "Define and enforce a maximum server lifetime and actual bounded cleanup for abandoned issuances; specify reissue/retry clock behavior." | Expiry and bounded cleanup; Phase 2–5; forward migration/cleanup/status probe | mapped |
| 3 [issue #11170] | "Cover all issuance/delivery/consume paths, expiry boundaries, ownership/generation/membership fences, erasure and failure observability." | Data-flow inventory; expiry behavior; Phase 3–5; lifecycle and observability tests | mapped |
| 4 [issue #11170] | "Preserve unsent messages and explicit resend; expiry/acknowledgment must never dispatch a provider request." | Expiry behavior at WebSocket boundary; Phase 3–5; held-turn tests | mapped |
| 5 [issue #11170] | "Preserve all existing migration SQL bytes; use a reviewed forward correction if schema/functions must change." | Expiry and bounded cleanup; Data Safety and Rollback; forward migration only | mapped |
| 6 [issue #11170] | "Obtain source CPO/user-impact, GDPR and CLO reviews; retain all independent hosted-auth/provider, runtime and shipping holds." | User-Brand Impact; Legal and Operator Decisions; Phases 1, 5 and 6; final acceptance criteria | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|----------------------------------|---------|
| Member metadata projection, subject assertion, nonce/hash omission and DSAR completeness tests | asks 1 and 3 | asked |
| Forward migration, expiry fields/predicates, retry/reissue clock rules and bounded cleanup RPC | asks 2 and 5 | asked |
| WebSocket expiry response, held-message preservation and explicit resend tests | ask 4 | asked |
| Ownership/generation/membership/erasure checks and lifecycle integration coverage | ask 3 | asked |
| Sentry/Inngest monitoring, bounded failure events and no-SSH discoverability probe | "Cover all issuance/delivery/consume paths, expiry boundaries, ownership/generation/membership fences, erasure and failure observability." — issue asks 3 | asked |
| TOM 4/DPA and PA-2/compliance wording updates | — | inferred — required so the processing records match the reviewed implementation and do not make an inaccurate legal commitment; CLO approval remains a prerequisite. |
| Keep hosted-auth/provider, runtime, data and shipping holds; preserve PR #9051 draft/off state | "Obtain source CPO/user-impact, GDPR and CLO reviews; retain all independent hosted-auth/provider, runtime and shipping holds." — issue ask 6 | asked |
| Probe only the cleanup status through a credential-safe, no-SSH command | — | inferred — required by the production observability gate; its code and credentials remain unimplemented until approval and review. |

| Files-to-Edit entry | User words cited (verbatim quote) | Verdict |
|---------------------|----------------------------------|---------|
| `<rechecked-ordinal>_codex_notice_rights_retention.sql` | asks 2 and 5 | asked |
| `server/dsar-export-allowlist.ts` | ask 1 | asked |
| `server/dsar-export.ts` | asks 1 and 3 | asked |
| `server/ws-handler.ts` | asks 3 and 4 | asked |
| `server/inngest/functions/`, `server/inngest/cron-manifest.ts`, `infra/sentry/cron-monitors.tf` | asks 2 and 3 | asked; exact files depend on Phase 2 inventory |
| `scripts/codex-notice-retention-status.sh` | — | inferred — required by the no-SSH observability gate; see justification above |
| DSAR allowlist completeness and worker per-row tests | ask 1 | asked |
| Focused DSAR, handler, migration, RLS and RPC-grant tests | asks 1–5 | asked |
| TOM 4 checker and mutation suite | asks 1, 2 and 5 | asked |
| `knowledge-base/legal/data-processing-agreement-template.md` | — | inferred — legal wording must match implementation; requires prior CLO approval |
| `knowledge-base/legal/article-30-register.md`, `compliance-posture.md`, and applicable privacy artifacts | ask 6 | asked |

### Split Assessment

- Subsystems touched: 3 — `apps/web-platform`, `scripts`, `knowledge-base`
- Pre-decision estimate: approximately 23 files / 700 changed lines. Request-admission preservation and the complete privacy-document/mirror set require a new inventory and split ruling before implementation; the old estimate does not establish headroom.
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: pending the revised inventory and CTO plan review. Preserve all six asks; do not drop request-time rights completeness to fit a threshold. The correction remains separate from draft PR #9051.

## Acceptance Criteria

- [x] CPO and user-impact-reviewer sign off the single-user impact framing and
      priority; the advisory GDPR gate runs and records its retention finding.
- [x] CLO proposes purpose/basis, maximum lifetime, Article 15/20 and
      post-consumption policy; operator accepts it for implementation and isolated
      testing. Factual basis/capacity and final processing clearance remain held.
- [ ] A DSAR projection path returns the CLO-approved member metadata, omits
      nonce/hash and other members, and preserves zero direct table grants.
- [ ] Request admission preserves eligible metadata present at receipt despite
      later acknowledgment, expiry and erasure; tests cover the email procedure,
      failure and deletion lifecycle without creating permanent notice history.
- [ ] The allowlist completeness and per-row query checks recognize only the
      tested issuance RPC projection; existing direct-table checks still cover
      all other allowlisted tables.
- [ ] Expiry is enforced by the database at delivery and acknowledgment; same
      nonce retries cannot renew lifetime, new notices follow the approved
      timestamp rule, and cleanup is indexed, bounded and monitored.
- [ ] Expiry, acknowledgment, cleanup and recovery never dispatch provider work
      by themselves; the held user message survives until explicit resend.
- [ ] Migration/DSAR/handler tests pass with synthesized fixtures in an
      isolated database; TypeScript, RLS/TOM4, legal cross-document and exact
      source gates pass. No provider or shared database contact occurs during
      offline QA.
- [ ] The PA-2/compliance and DPA records accurately describe the final
      processing, access, expiry, roles and deletion behavior, conditioned on
      the reviewed migration. CLO verifies the final wording.
- [ ] Hosted App Server API-key and managed modes remain blocked, customer
      content remains blocked, PR #9051 stays draft and auto-merge stays off
      until the separate provider, runtime, data, recovery, review and shipping
      gates clear.

## Files to Edit

- `apps/web-platform/supabase/migrations/<rechecked-ordinal>_codex_notice_rights_retention.sql` — new projection/expiry/cleanup RPCs and scheduler binding; do not edit migration 175.
- `apps/web-platform/server/dsar-export-allowlist.ts` and `server/dsar-export.ts` — scoped metadata export through the reviewed RPC.
- `apps/web-platform/app/api/account/export/route.ts` and the request-admission RPC/rights snapshot tests — preserve the approved request-receipt-time projection before asynchronous processing; establish the equivalent email procedure.
- `apps/web-platform/server/ws-handler.ts` — stable expiry response while preserving held-turn and explicit resend behavior.
- `apps/web-platform/server/inngest/functions/`, `server/inngest/cron-manifest.ts`, and `apps/web-platform/infra/sentry/cron-monitors.tf` — only if no existing monitored schedule can safely host the cleanup.
- `apps/web-platform/scripts/codex-notice-retention-status.sh` — no-SSH status probe using the credential-safe read pattern.
- `apps/web-platform/test/dsar-allowlist-completeness.test.ts`, `test/dsar-worker-per-row-where.test.ts`, focused DSAR/handler/migration integration tests and RLS/RPC grant tests.
- `scripts/check-tom4-rls-posture.sh`, its mutation suite and `knowledge-base/legal/data-processing-agreement-template.md` — keep the table RPC-only and outside WORM; update the legal wording only after CLO review.
- `knowledge-base/legal/article-30-register.md`, `compliance-posture.md` and applicable cross-document privacy artifacts — append the dated, migration-conditioned purpose/retention/rights record after legal approval.

## Non-Goals

- Do not change the meaning or bytes of migration 175 or any earlier migration.
- Do not treat the issuance as an explicit transfer instruction, GDPR consent,
  evidence that the notice was read, or provider permission.
- Do not add direct table SELECT or expand the issuance projection to expose
  nonce/hash material.
- Do not enable customer-content processing, dispatch any provider request,
  reconcile the shared dev ledger or apply a shared migration under this plan.
- Do not resolve the hosted App Server restriction by renaming a dependency or
  SDK. The distinct API-funded candidate remains subject to exact route/account
  review.

## Open Questions

1. Which verified subject contract/controller capacity supports the narrow
   service purpose for qualification? Other roles remain blocked.
2. What are the proven backup/PITR and rights-response-copy deletion/restore
   lifecycles? Final CLO clearance depends on these facts.
3. Does the complete source plan, including request-admission preservation,
   remain within the single-PR split threshold after inventory and plan review?
