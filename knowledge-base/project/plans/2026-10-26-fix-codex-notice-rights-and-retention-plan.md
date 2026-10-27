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
status: revised-pending-focused-plan-recheck
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
- Expiry, acknowledgment, cleanup and renewal never dispatch provider work
  alone; a still-cached held message is available only within its bounded
  tab-memory lifetime and requires fresh acknowledgment plus explicit resend.
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
review satisfies those properties. The atomic request-admission snapshot and
job-bound export, derived expiry, bounded database-owned cleanup and
current-nonce clock rules address those gaps. Existing direct-grant revokes and
`pg_cron` retention patterns are constraints to preserve or reuse; independent
expired-age monitoring remains required.

| Cut | Property | Existing coverage |
|---|---|---|
| Direct `service_role` table `SELECT` for export | Member-scoped metadata access | Existing TOM 4 and migration grant revokes already enforce the narrower boundary; snapshot at admission through one definer function instead. |
| Unbounded whole-table cleanup or a second cleanup scheduler | Bounded, monitored deletion | Use one indexed, bounded, database-owned `pg_cron` schedule; independent off-host status monitoring detects backlog and age. |

No requirement is cut. The CTO selected the database-owned `pg_cron` substrate;
Phase 2 verifies the exact role, privileges, monitor binding and measured
capacity. No live behavior is asserted from this source-only research.

### Relevant Source and References

- `apps/web-platform/server/dsar-export.ts` and
  `apps/web-platform/server/dsar-export-allowlist.ts` — current subject export
  boundary and per-table query path.
- `apps/web-platform/supabase/migrations/175_codex_history_notice_issuance.sql`
  — current issuance table, RPCs, lifecycle cleanup and revoked direct grants.
- `apps/web-platform/server/ws-handler.ts` and
  `apps/web-platform/lib/codex-held-turn-cache.ts` — acknowledgment and
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
| Contract subject eligibility | The issuance path verifies conversation ownership and workspace membership but does not establish the subject's contract or controller capacity. | New issuance and provider admission need a trusted, source-backed eligibility fence. Owner or team-member role alone is insufficient; ineligible roles remain blocked. |
| Mark delivered or repair | `persistCodexNoticeDelivery()` calls `mark_codex_history_transfer_notice_delivered` after socket send acceptance or authenticated reconnect repair. | The service RPC rechecks current conversation owner, generation and membership epoch and matches the nonce hash. |
| Remove unsent issuance | `discardCodexNoticeIssuance()` calls `delete_codex_history_transfer_notice_issuance` after failed or superseded sends. | The RPC deletes only the matching row while `delivered_at IS NULL`. |
| Acknowledge | WebSocket message `codex_history_transfer_acknowledge` uses the tenant JWT to call the three-argument acknowledgment RPC. That function consumes only a matching delivered issuance, then records an acknowledgment. | Possession hash is required. The client acknowledgement path emits a response; it does not itself dispatch a provider request. |
| Lifecycle cleanup | `175_codex_history_notice_issuance.sql` deletes pending rows when the auth-mode generation or membership epoch changes. Conversation, user and membership foreign keys cascade on deletion. | These are real lifecycle bounds but do not bound abandoned rows whose parents and generation remain. |
| Browser cache | `lib/codex-held-turn-cache.ts` keeps a bounded held message and raw notice nonce in tab memory for up to 30 minutes; it clears on auth-scope change, expiry or reload. | This is distinct from database retention. Never log, export or persist the raw nonce; do not promise recovery after cache expiry/reload. |
| Member access export | `DSAR_TABLE_ALLOWLIST` and `exportSqlTable()` include `codex_history_transfer_acknowledgments` by member. Issuance metadata appears in neither allowlist nor exclusions and has no export read path. | The worker uses a service client. The issuance table revokes direct table privileges from PUBLIC, `anon`, `authenticated` and `service_role`; that invariant must remain. |
| Current expiration | No database expiry column/check or abandoned-row sweep exists for the issuance table. | `issued_at` is not refreshed when a replacement nonce hash is stored, so it cannot currently express the current nonce's age. |

## Technical Approach

### 1. Request-time rights snapshot and job-bound export

The accepted CLO policy requires access to retained non-secret subject metadata
at the time the controller receives the request. A later worker read is too
late: acknowledgment, expiry, erasure or lifecycle cleanup may already have
deleted the issuance. Capture the eligible projection in the same database
transaction that admits a distinct DSAR request and creates/binds its job. The
worker exports that immutable job-bound snapshot by `job_id`; remove the
separate later live-issuance projection read. Do not expose a generic history
RPC or add permanent notice history.

The authenticated request boundary supplies the verified subject, workspace,
reauthentication event and a stable request id. The admission RPC verifies the
subject/workspace scope, creates the DSAR job and snapshots only that subject's
retained notice metadata atomically. A retry with the same request id returns
the same job and snapshot. A genuinely new request has a new request id, job
and admission-time snapshot; `enqueueExport()` must not silently reuse an old
completed archive for that new request. Worker retries and restarts remain
bound to the admitted `job_id`. The email channel must use the same admission
and snapshot boundary after its own identity verification.

Return every retained non-secret field or a faithful intelligible equivalent:
conversation, workspace and member references, generation, membership
timestamp, issuance and delivery-marker times, and the derived expiry. Explain
generation and membership context; do not include another subject's data. Do
not snapshot `nonce_hash` or raw nonce: the hash can satisfy the acknowledgment
predicate without notice possession. Data genuinely deleted before the
request-receipt point is not recreated. Article 15 remains available for
retained subject data independently of eligibility for new notice processing
or Article 20 portability.

Keep the snapshot request-bound and short-lived under the actual DSAR job
lifecycle; do not infer deletion from the seven-day download-link TTL. Before
final CLO clearance, prove archive creation/failure behavior, encryption at
rest, first-download deletion, expiry deletion, account erasure, restore/PITR
handling and cleanup of the job-bound snapshot. A later request must not reuse
an earlier archive. The acknowledgment record remains separate and is not a
complete notice history.

Keep direct issuance-table grants revoked. Use one narrowly scoped admission
`SECURITY DEFINER` function with `search_path = public, pg_temp`, qualified
relations and execution granted only to the server service role. `assertReadScope`
must bind the returned job snapshot to the verified requester before archive
publication. Extend the worker-lint with a mutation-tested job-snapshot path;
the existing literal direct-table rule stays in place for other allowlisted
tables. Update allowlist completeness, per-row scope, archive-manifest and
cross-tenant tests without adding a permanent history table.

Successful acknowledgment may delete the issuance without permanent history.

### 2. Expiry and bounded cleanup

Do not edit or replay `175_codex_history_notice_issuance.sql`. Remeasure
migration ownership and ordinals
before each forward-only migration in dependent companion PRs stacked on #9051's
feature branch; any correction migration must follow #9051's prerequisite on
the stack and must be numbered after current `origin/main`'s maximum ordinal
178. If main remains unchanged and the correction is ready after #9051 merges,
the next two ordinals are 179 and 180; remeasure again before creating them.
Derive expiry from
`issued_at + interval '30 minutes'`; do not add a second stored expiry clock
without evidence that variable policy is required. Add an index supporting
bounded cleanup and narrow RPC changes. Do not rename or rewrite existing
migration bytes. Preserve the zero-policy and no-direct-table-grant posture.

Use these timestamp semantics:

- `issued_at` denotes the current nonce hash's issuance time.
- An exact same-nonce retry or delivery-marker repair does not extend the
  lifetime.
- A new nonce hash is a new notice issuance: reset `issued_at` and clear
  `delivered_at` in the same upsert.
- Delivery repair and the three-argument acknowledgment reject at or after
  expiry. Evaluate the cutoff with `clock_timestamp()` only after acquiring
  the existing run/conversation, membership and issuance locks, immediately
  before the protected write. `now()` is transaction-start time and can be
  stale after a lock wait.
- The issue RPC may replace an expired row only through the explicit fresh
  notice flow after subject eligibility and cleanup health are checked.

The accepted controller policy is **30 minutes of nonce usability**, followed
by at most **five further minutes for ordinary primary-table deletion**. This
is not a statutory period or current enforcement. Use one database-owned
`pg_cron` sweep at one-minute cadence, consistent with ADR-098 and existing
retention migrations. Delete in indexed batches with a lock-safe `SKIP LOCKED`
strategy. Set the batch bound from measured row rate and lock/deadline tests;
verify the scheduled role's ownership and privileges before choosing direct
delete versus a narrow definer function.

Independently monitor cleanup freshness, backlog and age of the oldest
remaining expired row. Refuse new issuance when the cleanup job is absent,
stale, failing or behind its measured capacity. Invocation success or aggregate
deleted count alone does not prove the five-minute bound. Include schedule,
backlog, lock contention and retry delay in the limit and alert before it is
exhausted. A database outage can prevent deletion; report that as a retention
failure and do not claim cron registration guarantees the bound during an
outage. Do not disable the only erasure path during rollback while expired
rows remain. Roll application code forward while preserving database cleanup.

Same-nonce retries never renew lifetime. Managed backups/PITR and rights-response
snapshots have distinct retention and restore lifecycles; they remain conditions
for final CLO clearance. Cleanup returns aggregate health only, never subject
IDs, conversation IDs or hashes; it never clears a held message, delivers a
notice, acknowledges transfer or dispatches provider work.

Record the estimated database write work as roughly `4C + 3A + 2S` row changes
per day for `C` completed notices, `A` abandoned deliveries and `S` DSAR
snapshots, before retries/replacements and existing DSAR writes. The minute
cron adds 1,440 executions/day; avoid per-tick health writes and measure WAL
and cleanup capacity before qualification.

Update the DPA template and dated PA-2/compliance processing record to describe
the actual mutable receipt and expiry/cleanup path; do not call it WORM or an
immutable accountability ledger.

### 3. Reachable metadata-only renewal and explicit resend

The expiry response fails closed with a stable content-free code and a
reachable metadata-only **Request a new notice** action. Commit a `.pen`
wireframe for expired notice, fresh notice and recovery states before UI
implementation. Update WebSocket types/schemas, `ws-client.ts` state, the
server handler and chat surface together. Reconnect never resends the old
unacknowledged nonce; the existing retry action must not submit it after expiry.

The member action requests a fresh nonce; the server rechecks exact verified
contract-subject eligibility before issuance. The client presents the new
notice and requires a new acknowledgment tied to that nonce and generation.
Only after that acknowledgment may a separate explicit member action call
`resendMessage()`. Expiry, reconnect, renewal, fresh notice and acknowledgment
each cause zero provider requests by themselves. Reject stale responses from a
prior generation/turn and prevent repeat clicks from duplicating renewal or
resend.

The held user message exists only in the existing bounded tab-memory cache
(30 minutes, count/byte caps, cleared on reload or auth-scope change). Do not
promise persistence past that bound. Show the member when the cached draft is
unavailable; reconstruction is an explicit new user action. Tests cover
mount/remount before and after cache TTL, reload, scope invalidation, repeated
clicks, reconnect, stale response generations, fresh acknowledgment and exactly
one explicit resend. Model resend as one stable logical turn with three
outcomes: definitely not dispatched, durably accepted, or unresolved.
`WebSocket.send()` returning successfully means only pending; keep the held
copy until a correlated authoritative acceptance/result. A definite
pre-admission failure keeps the same message, attachments and original turn ID
retryable by a new explicit member action. Repeated clicks while pending submit
once. A disconnect, timeout or lost response is unresolved: disable resend and
reconcile authenticated status scoped to subject, conversation and generation,
without provider work. A durable accepted claim suppresses duplicates across
sockets and restarts; a positive authoritative not-dispatched disposition may
permit explicit retry of that same claim only with atomic fencing. Generic
failure, duplicate-key errors, unavailable status or missing responses never
prove non-dispatch and never permit a replacement ID or automatic retry.
Wrong-scope replies and altered payloads on a reused ID cannot clear or dispatch
the draft. Cache expiry/auth invalidation retains bounded-memory behavior and
makes no persistence promise. This contract prevents duplicate dispatch; it
does not promise exactly-once provider completion. No expiry path may silently
drop a still-cached message or replay it to a provider. Copy must not equate
nonce possession with reading or consent.

## Legal and Operator Decisions

1. **Accepted internal policy:** the source-based [CLO decision](../../legal/audits/2026-10-26-codex-notice-rights-retention-decision.md)
   supplies the proposed 30-minute validity/five-minute deletion limits, narrow
   service purpose, faithful non-secret Article 15 projection, request-receipt-
   time preservation, ordinary post-ack deletion and independently assessed
   Article 20 inclusion for eligible service activity. The operator explicitly
   approved this legal-risk policy for implementation and isolated testing.
2. **Basis/capacity enforcement:** Article 6(1)(b) applies only to a verified
   contracting subject where objectively necessary. Before notice issuance,
   enforce an explicit allowlist of verified contracting-subject categories;
   owner, workspace-admin or team-member status is not contract evidence.
   Other roles remain blocked from new issuance and provider admission pending
   their actual controller basis/instructions. No separate
   security/accountability purpose or Article 6(1)(f) fallback is approved.
3. **Remaining lifecycle facts:** establish actual backup/PITR handling and the
   request-bound snapshot/archive encryption, failure, restore, download,
   account-erasure and deletion lifecycle before final processing clearance.
   Article 15 access to retained data is independent of Article 20 eligibility.
   The bulk authenticator exclusion does not waive case-specific handling of an
   explicit full-access request.
4. **CLO processing-record decision:** define the exact dated PA-2/compliance
   amendment, retention wording and role split. Update the processor register
   only if the actual processing activity warrants it. No provider permission
   follows from these local controls.
5. **Approval boundary:** operator policy acceptance does not authorize a new
   shared-database read/write, provider request, customer processing, readiness,
   merge or deployment. Follow the exact recovery-evidence approval boundary.

The accepted policy comes from the CLO and operator; it is not professional
counsel advice. CTO technical ruling (2026-10-26): use two dependent correction
slices stacked on #9051's held feature branch; capture rights metadata
atomically at request admission and export by job ID; use one database-owned
one-minute `pg_cron` cleanup schedule with independent expired-age monitoring;
never treat cron registration as proof of deletion during database outages.
CTO technical ruling (2026-10-27): resend uses a stable logical turn and
three-state dispatch outcome. Preserve the bounded held copy until correlated
authoritative acceptance/result; only a definite pre-admission failure or
positive authoritative not-dispatched disposition with same-claim fencing can
permit a new explicit retry. Ambiguous outcomes require authenticated,
scope-bound status reconciliation and never automatic retry or a new turn ID.
This promises duplicate prevention, not exactly-once provider completion. The
rulings preserve all six asks and keep #9051 draft with auto-merge off.

## Data Safety and Rollback

- Keep all prior migration SQL bytes unchanged. Run the new migration only in
  disposable PostgreSQL until the transaction, grants, FK cascades, schedule,
  backfill, expiry boundary and cleanup are verified.
- Do not connect the test harness to a configured dev/prod URL, use provider
  credentials, include customer content, or dispatch Docker/Supabase work
  implicitly. Use synthesized users, conversations and hashes only.
- If a deployed schema correction needs rollback, preserve the database-owned
  cleanup schedule while any issuance can be expired. Roll application code
  forward to a safe state; never disable the only erasure path or remove
  cleanup coverage while rows remain. Do not drop the expiry index, cleanup
  mechanism or snapshot lifecycle while pending records exist. Deletion of
  expired rows is the intended retention action and cannot be undone by a
  schema rollback; status telemetry contains no member IDs or hashes.
- Verify the account-deletion, conversation-deletion and membership-removal
  paths remain effective. Test the cleanup's bounded row count and index use;
  no full unbounded table delete is acceptable.
- Do not perform shared reconciliation, new shared catalog capture, migration
  application, provider request, account login or production change under this
  plan. Each later shared operation requires its own exact approval and all
  legal and technical gates.

## Test Scenarios

- Given a synthetic member with one retained issuance, when a DSAR request is
  admitted, then its job-bound snapshot contains only approved metadata; Article
  15 applies to retained rows, and Article 20 is added only for an eligible
  contracting subject.
- Given a second genuine request after a completed export, then admission creates
  a new job and fresh snapshot; retrying the original request returns only its
  original job/snapshot. No older archive satisfies the new request.
- Given acknowledgment, expiry, erasure or lifecycle deletion concurrent with
  request admission, then transaction ordering gives one explicit receipt-time
  result: rows present at the admission point are preserved; rows deleted before
  that point are not recreated.
- Given another member's issuance or a mismatched job snapshot, then admission
  omits it or the worker fails before publishing a partial archive.
- Given the issuance table, when a source/test mutant grants direct service
  `SELECT`, adds an RLS policy/client grant, broadens the admission snapshot or
  includes `nonce_hash`, then the respective gate turns red.
- Given the frozen migrations 165 and 175, when their exact path+digest
  declarations are accepted by static lint, then the runtime registry still
  classifies only `agent_engine_attempts(id, run_id, status, created_at,
  updated_at, terminal_at, accepted_at)` and
  `agent_engine_recovery_checkpoints(run_id, updated_at)` as service-role
  SELECT; `attempt_key`, `checkpoint`, anon and authenticated remain denied.
  The `codex_history_transfer_notice_issuances` table stays INTERNAL with zero
  effective table- or column-level privileges for `anon`, `authenticated`, and
  `service_role`. Disposable catalog parity uses the RLS-fuzz registry's
  `API_ROLES` and `TABLE_VERBS`, and compares both table and per-column
  effective privileges (including `PUBLIC` and inherited grants through
  PostgreSQL's `has_*_privilege` functions) against `table-grants.ts`. No
  default-ACL prediction is implied; parity checks current effective catalog
  state. RPC/function execution remains covered by the existing RPC security
  tests, not this table-grant parity assertion. Any deviation fails
  qualification.
- Given an issuance before expiry, at the exact boundary and after expiry,
  when delivery repair or acknowledgment runs, then only the pre-expiry case
  can proceed.
- Given a request that starts before expiry but waits on a lifecycle lock until
  after expiry, when delivery or acknowledgment checks its boundary, then the
  post-lock `clock_timestamp()` rejects it. A same-nonce retry does not move
  `issued_at`; a different nonce resets `issued_at` and clears `delivered_at`.
- Given expired rows and concurrent users of the RPC, when one cleanup batch
  runs, then it deletes no more than the configured batch bound, skips rows
  already locked, returns only an aggregate count, and remains safe on retry.
- Given an expired notice, when the member requests renewal, then a fresh notice
  and nonce are issued only for an eligible subject; no provider request occurs
  until fresh acknowledgment and a separate explicit resend.
- Given a closed socket or definite prequeue send failure, then the exact held
  draft remains retryable and a later explicit retry uses its original turn ID.
- Given a correlated server rejection before admission, then the draft remains
  retryable and provider calls remain zero; repeated clicks while pending still
  produce one submission.
- Given accepted claim/provider invocation followed by lost response, reconnect
  and server restart, then authenticated status reconciliation finds the same
  attempt and duplicate submissions cause no second provider invocation.
- Given lost claim response, unavailable status, generic terminal failure,
  wrong subject/conversation/generation reply or altered payload with a reused
  ID, then the outcome stays unresolved and no retry, replacement ID, provider
  request or draft clearing occurs.
- Given reconnect, repeated renewal clicks, a stale server response, reload,
  auth-scope change and cache TTL expiry, then the client never uses an old
  nonce, never duplicates provider dispatch, and communicates whether the
  bounded tab-memory draft remains available.
- Given auth-generation change, membership-epoch replacement, account deletion,
  conversation deletion or membership removal, then existing lifecycle cleanup
  remains correct and is not delayed by the retention sweep.
- Given cleanup backlog, lock starvation, stale cron execution or database
  outage, then the status probe reports oldest expired-row age and cleanup
  freshness, new issuance fails closed at the defined health threshold, and no
  claim of a hard deletion guarantee is made during the outage.
- Given a cleanup failure, then the independent monitor detects it before the
  five-minute allowance expires without subject identifiers or nonce material;
  the next scheduled run can retry while the original erasure path stays active.

## Work Phases and Gates

1. **Confirm scope and sign-offs:** CPO and user-impact-reviewer signoffs are
   recorded for the single-user threshold. The CLO decision and operator
   acceptance approve policy for implementation and isolated testing. The
   advisory `soleur:gdpr-gate` recorded its Art. 5(e) retention finding. Final
   factual/legal processing clearance remains withheld.
2. **Source and architecture inventory:** confirm request admission channels,
   job/retry semantics, archive and snapshot lifecycle, exact contract-subject
   eligibility source, cron role/privileges, one-minute backlog capacity,
   independent monitoring and all privacy-document mirrors. Recheck migration
   ordinals before each slice. Keep frozen migrations 165 and 175 byte-for-byte.
   The exact-hash static declarations do not grant access or replace RLS-fuzz
   parity. In the stacked forward correction, grant the DSAR worker only
   `service_role` SELECT on `agent_engine_attempts(id, run_id, status,
   created_at, updated_at, terminal_at, accepted_at)` and
   `agent_engine_recovery_checkpoints(run_id, updated_at)`. Do not grant
   `attempt_key` or `checkpoint`. Classify those exact effective grants in
   `table-grants.ts`, and register the migration 175
   `codex_history_transfer_notice_issuances` table as INTERNAL with zero direct
   table or column privileges for all `API_ROLES` (`anon`, `authenticated`,
   `service_role`) across `TABLE_VERBS`. On a disposable database, verify
   registry parity against effective table and column privileges using the
   RLS-fuzz gate's `has_*_privilege` checks; these include inherited grants
   and `PUBLIC` effects on the three API roles. Default ACLs are outside this
   current-catalog assertion, and RPC/function execution stays with the RPC
   security tests. Verify unauthorized column denial before qualification.
   The estimate is at least 25 files
   across five roots and exceeds the split threshold.
3. **Slice A — request-time rights snapshot:** add RED tests for atomic
   admission-time capture, same-request retry versus new request, completed-job
   non-reuse, job-bound worker reads, email admission, tenant scope, snapshot
   deletion/restore and no nonce/hash. Implement and QA this slice in a
   companion PR stacked on the held #9051 feature branch.
4. **Slice B — lifetime, cleanup and renewal:** add RED tests for contract-role
   refusal before issuance/provider admission, post-lock clock boundary,
   same-nonce and replacement timestamp, one-minute bounded `pg_cron`, backlog
   health, issuance refusal, rollback erasure coverage, renewal protocol/UI,
   cache expiry and exactly-one explicit resend. Commit the `.pen` before UI
   coding. Implement this dependent slice on Slice A; keep all six asks in one
   completion gate across the stack.
5. **Offline integration and QA:** use only disposable PostgreSQL and
   synthesized fixtures, with no ambient shared DB/provider credentials. Run
   focused migration/DSAR/handler/client/UI suites, RLS fuzz, typecheck,
   screenshots, TOM4/legal cross-document checks and repository static gates.
   Verify archive and logs never contain raw nonce/hash. Run `soleur:gdpr-gate`,
   CLO review, exact-head code review, QA and preflight on both slices and the
   final integrated head.
6. **Records and qualification:** append dated migration-conditioned
   PA-2/compliance records and update the DPA, privacy and GDPR artifacts and
   their mirrors only after final CLO verification. Later runtime qualification
   still requires fresh exact-head recovery, provider permission for the exact
   route, current served-build renewal tests, fresh approved shared evidence,
   writer exclusion and all recovery gates. Keep customer content blocked until
   that separate clearance exists.

## Observability

```yaml
liveness_signal:
  what: "Cleanup freshness, expired backlog count, oldest expired-row age, and oldest locked/skipped row age"
  cadence: "pg_cron cleanup every minute; independent off-host status monitoring must detect a missed deadline before the five-minute deletion allowance"
  alert_target: "Web Platform engineering on-call"
  configured_in: "One database-owned pg_cron cleanup plus independent status monitoring wired to the existing Sentry cron-monitor inventory; verify the off-host polling substrate and alert delay in Phase 2"
error_reporting:
  destination: "Sentry web-platform with monitor correlation and release SHA; bounded pg_cron errors and backlog/age metrics contain no subject identifiers"
  fail_loud: "Expiry checks reject stale delivery/acknowledgment; unhealthy or stale cleanup blocks new notice issuance; job-bound DSAR snapshot failure fails export before archive publication"
failure_modes:
  - mode: "Delivery repair or acknowledgment reaches the expiry boundary"
    detection: "Layer 2 Pino-to-Sentry mirror records a bounded expiry code; Layer 5 release context binds it to the served SHA"
    alert_route: "Web Platform engineering on-call"
  - mode: "Cleanup is late, errors, skips locked rows or exceeds measured backlog capacity"
    detection: "Layer 1 independent off-host monitor plus Sentry cron monitor reads freshness, backlog count and oldest expired age; must alert before the five-minute allowance expires"
    alert_route: "Web Platform engineering on-call"
  - mode: "DSAR admission snapshot fails or a worker reads another job/subject's snapshot"
    detection: "Layer 2 Pino-to-Sentry mirror and job's persisted failed status; no partial archive is published"
    alert_route: "Web Platform engineering on-call and the DSAR request status"
  - mode: "Database outage prevents cleanup"
    detection: "Layer 1 independent off-host monitor reports stale cron completion and rising oldest-expired age; Layer 5 release context binds remediation to the deployed source"
    alert_route: "Web Platform engineering on-call"
logs:
  where: "Sentry monitor events and bounded pg_cron status; aggregate counts/ages only"
  retention: "Existing Sentry and database cron metadata retention; CLO must confirm the applicable retention before qualification"
discoverability_test:
  command: "bash apps/web-platform/scripts/codex-notice-retention-status.sh prd"
  expected_output: "job_status=ok"
  credentials_required: "Doppler soleur/prd read-only database credential; the last cleanup result is private database state and has no unauthenticated public probe"
```

The planned status command must query only bounded aggregate health, use TLS
verification and avoid placing the database URL/password in process arguments
or logs. Its implementation and exact success output are acceptance criteria;
it must not be treated as available until added and tested.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 [issue #11170] | "Add a narrowly scoped member metadata export path and completeness tests; do not export the nonce or its hash, and document a specific security projection rationale." | Request-time rights snapshot and job-bound export; Slice A; DSAR admission/worker/tests | mapped |
| 2 [issue #11170] | "Define and enforce a maximum server lifetime and actual bounded cleanup for abandoned issuances; specify reissue/retry clock behavior." | Expiry and bounded cleanup; Slice B; forward migration/pg_cron/health probe | mapped |
| 3 [issue #11170] | "Cover all issuance/delivery/consume paths, expiry boundaries, ownership/generation/membership fences, erasure and failure observability." | Data-flow inventory; both slices; lifecycle, backlog-age and failure tests | mapped |
| 4 [issue #11170] | "Preserve unsent messages and explicit resend; expiry/acknowledgment must never dispatch a provider request." | Reachable metadata-only renewal and explicit resend; Slice B; wireframe/client/server tests | mapped |
| 5 [issue #11170] | "Preserve all existing migration SQL bytes; use a reviewed forward correction if schema/functions must change." | Both forward migrations; stacked branch topology; Data Safety and Rollback | mapped |
| 6 [issue #11170] | "Obtain source CPO/user-impact, GDPR and CLO reviews; retain all independent hosted-auth/provider, runtime and shipping holds." | User-Brand Impact; Legal and Operator Decisions; Phases 1, 5 and 6; final acceptance criteria | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|----------------------------------|---------|
| Atomic request-time snapshot, job binding, request/retry identity, nonce/hash omission and DSAR completeness tests | asks 1 and 3 | asked |
| Forward migrations, derived expiry, post-lock clock checks, retry/reissue rules and bounded database cleanup | asks 2 and 5 | asked |
| Reachable renewal action, held-cache disclosure and explicit resend tests with committed `.pen` | ask 4 | asked |
| Ownership/generation/membership/erasure checks and lifecycle integration coverage | ask 3 | asked |
| Independent cleanup freshness/backlog/oldest-expired-age monitoring and no-SSH discoverability probe | "Cover all issuance/delivery/consume paths, expiry boundaries, ownership/generation/membership fences, erasure and failure observability." — issue asks 3 | asked |
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

- Minimum inventory: at least 25 files across five roots — `apps/web-platform`,
  `scripts`, `knowledge-base`, `docs` and `plugins`. It includes two forward
  migrations, DSAR admission and worker, email intake, WebSocket handler and
  protocol types/schemas, client/cache and chat surface, committed `.pen`,
  off-host health monitoring, SQL/DSAR/client/UI tests, TOM4 gates, DPA/register/
  compliance text, and six canonical/mirrored privacy documents with legal SHA
  pins. The earlier 23-file/700-line estimate is obsolete.
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines.
- Recommendation: two dependent companion PR slices, both stacked on #9051's
  held feature branch. Slice A implements atomic rights admission/snapshot and
  job-bound export; Slice B implements expiry, bounded cleanup/health and the
  renewal UI/protocol. Integrate both before reconsidering #9051 readiness. One
  completion gate spans all six asks. Do not target `main` with either
  correction migration until prerequisite
  `175_codex_history_notice_issuance.sql` from #9051 is present
  there. Current fetched main reaches ordinal 178, so remeasure before choosing
  correction ordinals. Preserve the draft hold.

## Acceptance Criteria

- [x] CPO and user-impact-reviewer sign off the single-user impact framing and
      priority; the advisory GDPR gate runs and records its retention finding.
- [x] CLO proposes purpose/basis, maximum lifetime, Article 15/20 and
      post-consumption policy; operator accepts it for implementation and isolated
      testing. Factual basis/capacity and final processing clearance remain held.
- [ ] One atomic request-admission path captures the CLO-approved non-secret
      metadata at receipt, binds it to a distinct job ID, supports same-request
      retries and gives a new request a fresh snapshot/job; email follows the
      same boundary and no permanent notice history is created.
- [ ] The worker exports only the verified job-bound snapshot, enforces subject
      scope, includes Article 15 for retained rows independently of Article 20
      eligibility, and never exposes nonce/hash or another member's data.
- [ ] Archive and snapshot encryption, failure, first-download/expiry deletion,
      account erasure and PITR/restore lifecycles are verified before final CLO
      clearance.
- [ ] Expiry is enforced by the database at delivery and acknowledgment; same
      nonce retries cannot renew lifetime, new notices follow the approved
      timestamp rule, and cleanup is indexed, bounded and monitored.
- [ ] Expiry, acknowledgment, cleanup, renewal and recovery never dispatch
      provider work by themselves. A committed `.pen` precedes UI code, and the
      client requires a fresh notice, fresh acknowledgment and separate explicit
      resend while accurately describing its 30-minute tab-cache limit.
- [ ] Contract-subject eligibility is checked before notice issuance and
      provider admission; team or owner role alone never qualifies.
- [ ] Migration/DSAR/handler tests pass with synthesized fixtures in an
      isolated database; TypeScript, RLS/TOM4, legal cross-document and exact
      source gates pass. No provider or shared database contact occurs during
      offline QA.
- [ ] The PA-2/compliance and DPA records accurately describe the final
      processing, access, expiry, roles and deletion behavior, conditioned on
      the reviewed migration. CLO verifies the final wording.
- [ ] A one-minute database-owned `pg_cron` sweep has measured batch capacity;
      independent monitoring detects backlog/oldest expired age before the
      five-minute allowance, new issuance refuses unhealthy retention, and
      rollback preserves cleanup coverage.
- [ ] Hosted App Server API-key and managed modes remain blocked, customer
      content remains blocked, PR #9051 stays draft and auto-merge stays off
      until the separate provider, runtime, data, recovery, review and shipping
      gates clear.

## Files to Edit

- `apps/web-platform/supabase/migrations/<rechecked-ordinal>_codex_dsar_snapshot.sql` and `<rechecked-ordinal>_codex_notice_retention.sql` — dependent forward migrations; do not edit `175_codex_history_notice_issuance.sql`.
- `apps/web-platform/server/dsar-export-allowlist.ts`, `server/dsar-export.ts`, account-export request admission and verified email intake — atomic request/job/snapshot binding and scoped export.
- DSAR snapshot/job lifecycle migrations and tests — fresh request versus retry, deletion, account erasure, encryption, PITR and restore behavior.
- `apps/web-platform/server/ws-handler.ts`, `lib/types.ts`, `lib/ws-zod-schemas.ts`, `lib/ws-client.ts`, and chat UI — fresh nonce renewal, acknowledgment and separate explicit resend.
- A committed Pencil `.pen` wireframe before any renewal UI implementation; served-build screenshot tests afterward.
- `apps/web-platform/scripts/codex-notice-retention-status.sh` and the existing off-host monitoring/Sentry cron-monitor binding — no-SSH aggregate status probe, oldest-expired-age signal and freshness check; do not add a second cleanup scheduler.
- `apps/web-platform/test/dsar-allowlist-completeness.test.ts`, `test/dsar-worker-per-row-where.test.ts`, focused DSAR/handler/client/UI/migration integration tests and RLS/RPC-grant tests.
- `scripts/check-tom4-rls-posture.sh`, its mutation suite and `knowledge-base/legal/data-processing-agreement-template.md` — keep the table RPC-only and outside WORM; update the legal wording only after CLO review.
- `knowledge-base/legal/article-30-register.md`, `compliance-posture.md`, Privacy Policy, GDPR Policy and Data Protection Disclosure, plus their `docs/legal/` and `plugins/soleur/docs/pages/legal/` mirrors and SHA pins — update the dated, migration-conditioned purpose/retention/rights record after legal approval.

## Non-Goals

- Do not change the meaning or bytes of `175_codex_history_notice_issuance.sql` or any earlier migration.
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

1. Which source-backed role categories and account facts prove a contracting
   subject and controller capacity before a new notice is issued? Other roles
   remain blocked.
2. What are the proven backup/PITR and request-snapshot/archive deletion and
   restore lifecycles? Final CLO clearance depends on these facts.
3. Which existing independent off-host monitor can read oldest-expired age and
   freshness inside the five-minute window, and what measured cleanup batch
   rate proves capacity under lock contention?
