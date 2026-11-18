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

### 0. Bounded holder-evidence worker (precondition for any collection command)

The current in-process callback prototype is not a bounded collector: its
adapter can retain the database connection in a closure, its event-loop timer
cannot interrupt synchronous work, and its verifier only checks an
adapter-reported object. Do not prepare or run exact collection commands from
that prototype.

Replace it with an opt-in, dedicated `hcloud_server.holder_collector` in the
existing `apps/web-platform/infra` Terraform root. Keep the resource disabled
by default and separate it from the web and Inngest hosts. The coordinator
must never receive a database client or socket. A per-operation systemd
`Type=oneshot` child creates and exclusively owns its database connection under
an operation-scoped read-only principal. Pin a minimum systemd version and
unified cgroup-v2 mode. `RuntimeMaxSec` is ineffective for `Type=oneshot`; use a
finite `TimeoutStartSec` with `TimeoutStartFailureMode=terminate`, short
`TimeoutStopSec`, `KillMode=control-group`, and final SIGKILL so PID 1 bounds
synchronous loops and descendants. This is a hard process-tree fallback, not
proof that database authority was revoked ([systemd service unit
documentation](https://freedesktop.org/software/systemd/man/latest/systemd.service.html)). The child
returns only a bounded, sanitized result; receipt bodies, credential material,
subject identifiers and raw provider responses never enter logs.

An off-host durable authority owns each operation's generation and deadline,
persists the deadline event before arming work, and survives coordinator and
worker failure. At deadline it atomically revokes the generation and database
credential, waits for authoritative revocation acknowledgment, and only then
asks the host supervisor over a narrow authenticated control API to kill the
unit's full cgroup. A database-enforced operation-credential lease must also
expire server-side; a process timer or host timeout cannot bound backend
authority during an authority or network outage. A separately authenticated
narrow database observer then verifies that no sessions, transactions or locks
remain for that operation principal.
Current source and CTO review establish no existing mechanism that gives the
hosted database an absolute per-operation authority deadline. A candidate is a
durable database deadline record plus a narrowly owned `pg_cron` expiry job
that disables a unique operation role and calls `pg_terminate_backend` for all
of its sessions, followed by the independent observer. This is only a design
candidate: managed-role grants, scheduler maximum lag/availability, queueing,
restart recovery, and fail-closed admission must be demonstrated on the exact
PostgreSQL/Supabase versions before it can be called a bound. PostgreSQL
`VALID UNTIL` only expires password authentication; role GUC defaults alone do
not prevent session overrides or terminate existing sessions. PG17 statement,
transaction and idle timeouts are defense-in-depth, not an operation lease.
If the candidate cannot prove an accepted maximum stop time for active sessions
and transactions under scheduler or network failure, reject this collector
substrate and keep collection blocked; select and review another substrate
before implementation. Current ADR values are `operation_deadline: UNSET / NO-GO`,
`maximum_backend_stop: NOT PROVEN`, and `scheduler_maximum_lag: NOT PROVEN`.
The existing 24-hour receipt-retention ceiling does not justify a 24-hour
operation. Before setting a runtime value, cap each included source's connect
time, full-response time, pages, rows, bytes and retries; verify its pagination
contract; and measure worst-case throttling and stop lag. No retry may extend
the absolute operation deadline. Require zero incomplete source arms: any
timeout, cap, denial, malformed/unknown response, missing/changing page or
unverified pagination makes the operation partial/failed/unsupported, never
complete. See [PostgreSQL 17 client runtime configuration](https://www.postgresql.org/docs/17/runtime-config-client.html),
[role creation](https://www.postgresql.org/docs/17/sql-createrole.html) and
[backend termination](https://www.postgresql.org/docs/17/functions-admin.html).
Child exit, connection identity, a database name, or the callback prototype's
shape-only `verify()` is not stop evidence. Keep the fence and resources held
when lease expiry, revocation, supervisor status, observation or authority
availability is unknown. The worker, revocation authority, verifier and vault
custodian use separate identities and credentials. The worker may write only
the operation's encrypted vault object; it cannot list, restore, erase or
release objects. The authority may seal or tombstone an operation but cannot
read contents. A separate vault custodian can restore or erase only through
audited, operation-scoped requests; it cannot authorize collection or release
the worker fence. Durable tombstones, retention enforcement and tested restore
and erasure behavior are required.
One vault candidate for review is an EU GCS bucket with client-side envelope
encryption and a unique imported-only Cloud KMS key per operation in a separate
key project/IAM domain. The worker encrypts but cannot decrypt; the restore
custodian can decrypt but cannot collect; the erasure authority can destroy but
cannot decrypt or restore. Keep raw imported key material out of all backups,
Terraform state, logs and the receipt store, and prove no re-import path remains
after erasure. This candidate is not approved: Cloud KMS documents a zero
destruction delay for imported-only keys but key material may remain in Google
active/backup systems for up to 45 days. If CLO requires physical provider-side
removal within 24 hours, reject this candidate; if customer-inaccessible
crypto-erasure is sufficient, obtain explicit CLO and contract approval and
prove it with disposable-project restore/erasure tests. See [key states](https://docs.cloud.google.com/kms/docs/key-states),
[destroy and restore](https://docs.cloud.google.com/kms/docs/destroy-restore),
and [key import](https://docs.cloud.google.com/kms/docs/importing-a-key).

Use a new private network and subnet containing only the collector and its
dedicated egress gateway; do not join `soleur-private`, which is shared with
production web, git-data, registry and Inngest hosts. The collector has no
public NIC. Route its only outbound path through the dual-homed gateway's
private proxy address. Install host nftables on both machines: the collector
may reach only the proxy, and the proxy accepts only the collector's private
address. The gateway has no public ingress and an explicit Hetzner outbound
firewall allowing DNS only to the pinned resolver, TCP 443 for Firestore/STS,
and the exact database port from the reviewed Supabase endpoint manifest;
stateful replies only. An
authenticated CONNECT/TCP proxy enforces exact FQDN/port ACLs for
`firestore.googleapis.com:443`, `sts.mtls.googleapis.com:443`, and the approved
Supabase endpoint. This is a candidate source set, not a complete allowlist:
`holder-provider-coverage-design.md` also describes GitHub surfaces. Before
network implementation, explicitly mark every source included or excluded;
each included source requires its own purpose/contract review and exact
destination in the manifest and egress ACL. No source inherits authorization
from another path. If GitHub is included, pin `api.github.com:443` and the
reviewed API paths/scopes; include exact Doppler and Supabase Management
destinations only when their sources are in scope. Otherwise record each as
unsupported/excluded and limit every completeness statement accordingly. The
checked-in repo does not identify the primary app
project's pooler endpoint; do not reuse the documented endpoint for the
separate Inngest project. Add a reviewed nonsecret endpoint-and-port manifest
as the single source for worker settings and proxy ACLs; credentials remain in
the vault. Select and review the vault storage and key-management provider,
service/account, region, replication and backup locations as part of this same
vendor/transfer inventory. Give each operation a short-lived proxy credential delivered via
systemd credentials or mTLS. The proxy resolves names itself through a dedicated
validating resolver, rejects private, link-local and special-use addresses,
client-supplied IPs and stale DNS, and fails closed on resolver errors. The
collector's only route is through the gateway; its nftables permits loopback,
resolver access and the proxy only. Gateway nftables permits collector-private
ingress to the proxy/resolver and only resolver DNS plus proxy-originated
connections to approved destinations and ports. Specify these controls before
code. Hetzner Cloud Firewalls do not
filter private-network L2 traffic, so their rules cannot replace host-level
controls ([Firewall FAQ](https://docs.hetzner.com/cloud/firewalls/faq/),
[Networks FAQ](https://docs.hetzner.com/networking/networks/faq/)).

Before enabling or applying either host, choose an EU location and server type,
recheck current orderable stock and monthly cost, and
<!-- lint-infra-ignore start: records the gated production Terraform apply and command-specific operator authorization required before provisioning; issue #11170 -->
obtain exact operator authorization for the Terraform apply.
<!-- lint-infra-ignore end -->
The hosts must be reproducible through
Terraform from empty state and immutable replacement; no SSH key or in-host
command is a primary status or debug path. Offline qualification uses the
exact systemd/cgroup, route, nftables and proxy configuration with a disposable
cgroup-v2 VM and PostgreSQL. Test busy loops, synchronous blocks, stubborn
descendants, pending transactions, authority restart, revocation-before-kill
ordering, active sessions, long-running and prepared-transaction denial,
repeated short transactions, worker/network loss, scheduler restart/queue/outage,
measured deadline-job maximum lag, stale-generation reconnect, server-side
credential-lease expiry and observer/control outage. Refuse new operations
whenever deadline execution is unhealthy. Run `systemd-analyze verify`; prove
the cgroup empties, expired credentials cannot reconnect, and observer outage
retains the fence. Before qualification, verify on the exact hosted project
that `max_prepared_transactions=0`; if it is nonzero or unverifiable, prohibit
`PREPARE TRANSACTION` and prove a database-owned recovery path removes every
operation-owned prepared transaction before stop evidence can pass. Session
termination cannot remove a prepared transaction.
Passing these local tests
does not establish production authority, Firestore IAM, provider coverage or
permission to collect.

#### Holder-evidence processing gate

The accepted Codex notice policy and its Article 6(1)(b) analysis do not
authorize holder-evidence collection. Before exact collection commands may be
prepared, independently review the operation-specific purpose, necessity and
balancing; subject categories; controller/processor roles; source-backed legal
basis; Article 14 notice or exception; DPIA screening; and the applicable
`soleur:gdpr-gate` and CLO reviews. Verify the exact Firestore project/account,
Google service and region; the Supabase development project and its separation
from production; and the Hetzner, Doppler, Vector and Sentry resources, regions,
recipients, support access, processor terms and transfer safeguards. Confirm
the source-specific DPAs and data-flow records. Network ACLs and TLS do not
establish contractual or transfer authorization. Update the relevant processing
record (including an explicit decision whether to amend PA-8 or create a
separate processing activity) and Privacy Policy, Data Protection Disclosure
and GDPR Policy (including published mirrors when applicable) before
collection if CLO confirms this is a new processing activity.

Use distinct reviewed allowlists for provider receipts, durable authority
records and telemetry. Start from the source projections in
`holder-provider-coverage-design.md`; enumerate exact fields, types, per-field
limits and total response bounds, and reject unknown or unbounded fields before
persistence. Treat principal IDs/digests, operation IDs, timestamps and
tombstones as potentially linkable. The control ledger never contains receipt
bodies or raw provider responses. Preserve the existing 24-hour maximum for
filtered receipt copies from capture; any longer or broader retention needs a
new privacy review. No receipt-bearing copy may rely on a tombstone alone to
meet the 24-hour deletion limit: either exclude it from backups/snapshots or
use per-operation envelope encryption with keys outside every ciphertext
backup/replica domain and prove crypto-erasure by 24 hours. A restore must
consult an independently retained tombstone and reject deleted generations.
Set separate necessity, access, retention and deletion
rules for minimized reports, authority/revocation records, tombstones, deletion
receipts and telemetry before collection. Keep operation IDs and principal
digests out of Sentry; send only an approved aggregate projection there, with a
CLO-approved retention bound for Sentry and each other control/report/tombstone/
deletion record. Define rights and notice handling for people represented
in the holder inventory; the Codex request-time DSAR snapshot is a distinct
data store and does not satisfy those rights.

The holder-rights flow must provide a published request channel, verify the
requester's identity and scope against the minimum necessary source mapping,
search each approved copy, and return a status and response by the applicable
deadline. It must include records retained in reports, authority metadata,
tombstones, telemetry, backups and restored copies without exposing another
person's records. If a request cannot be matched or a copy cannot be reached,
record an unresolved state and escalate under the CLO-approved procedure;
never report erasure complete based only on live-store deletion.

Exact operation commands are generated from the reviewed schema and endpoint
manifest, pinned to the source revision and tool versions, and include a no-op
render/hash plus destination and retention summary. An independent technical,
GDPR and CLO review records the exact command bytes and target. The operator's
explicit authorization then covers only that collection command. After a
verified collection result, generate and independently review the distinct
writer-window commands against the observed evidence and exact migration
hashes; obtain a second, separate authorization before any writer window. One
authorization never covers both actions. If collection is partial, timed out,
revoked or unknown, keep all fences held; preserve operation ID/generation,
bounded result and deletion state; do not retry into the same generation or
reconcile/write. A retry requires a new generation and independently reviewed
command. Release only after authority revocation, credential expiry, empty
cgroup, zero observed backend sessions/transactions/locks, and receipt
retention/deletion evidence are all independently verified.

Restore/erasure qualification covers Firestore history, database PITR, host and
volume snapshots, temporary files, crash dumps, logs and restored copies. An
external tombstone or equivalent must prevent restored data from becoming live
again, with verified re-deletion evidence where applicable. Keep holder receipts
and Codex rights-response archives in separate stores and lifecycles. Existing
intent preparation and Firestore ledger contracts do not establish authenticated
authority; Firestore writes remain hard-disabled. Exact-intent conformance,
verified IAM, and separate exact-action authorization are required before any
authority claim. No code or offline proof changes those holds.

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
the stack and must be numbered after current `origin/main`'s maximum ordinal.
On 2026-11-18, `origin/main` reached ordinal 186; if main remains unchanged
and the correction is ready after #9051 merges, the next two ordinals are 187
and 188. Remeasure before creating either migration.
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

- Given a holder-evidence worker that enters a synchronous busy loop or forks a
  descendant, when the operation deadline expires, then the systemd/cgroup
  supervisor terminates the full operation tree within the configured bound.
- Given a worker with a pending PostgreSQL transaction, when timeout revokes
  its operation generation and credentials, then a separate verifier observes
  zero sessions, transactions and locks for that operation principal before
  the fence or resource is released.
- Given a worker that repeatedly completes short transactions or loses its
  network while its database session remains open, when the operation deadline
  fires, then the qualified database-side deadline mechanism terminates that
  session within its measured maximum lag. Scheduler restart, queueing or
  outage must preserve the bound or refuse new operations and keep every fence
  held; `VALID UNTIL` and role defaults alone do not pass.
- Given stale-generation reconnect, unavailable authority, worker crash,
  supervisor failure or observer outage, then the operation stays fenced and
  stop remains unknown; no new credentials or work are admitted.
- Given a vault seal, tombstone, deletion or restore failure, then no receipt
  body is returned to the coordinator and the retention state fails closed.
- Given partial, timed-out, revoked or unknown collection, then the operation
  remains fenced with its generation and bounded outcome recorded; no same-
  generation retry, reconciliation, writer window or deletion-complete claim is
  permitted. A retry uses a new generation and reviewed command.
- Given a rights request from a person represented in the holder inventory,
  then the reviewed request flow scopes the request across each approved live
  copy, report, authority record, tombstone, telemetry store, backup and
  restored copy, returns a tracked status by the approved deadline, and records
  unresolved copies without claiming complete erasure.
- Given an unapproved network destination, when the isolated worker attempts
  egress, then the host policy refuses it and emits only bounded operational
  telemetry without subject or credential material.
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
- Given expired, denied, offline, rate-limited or socket-dropped renewal, then
  the interface exposes an accessible retryable or unresolved state, preserves
  the held draft within its documented cache bounds, and never dispatches a
  provider request. Keyboard and screen-reader announcements cover expiry,
  pending, success, failure and resend; narrow-screen behavior passes the
  served-build visual gate.
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
   independent monitoring and all privacy-document mirrors. Inventory the
   dedicated holder-worker network and egress boundary, systemd/cgroup runtime,
   worker and observer identities, durable revocation authority, vault operator,
   restore path and off-host telemetry. Recheck migration
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
   The estimate is at least 35 files across six subsystem roots and exceeds
   the split threshold.
3. **Holder-evidence privacy and service review:** establish the separate
   purpose, basis, subject categories, roles, Article 14 assessment, DPIA
   screening, source-specific contracts/transfers, exact service/project/region
   inventory, three allowlisted schemas, per-copy retention and rights rules,
   and restore/erasure coverage defined above. Run the GDPR gate and obtain
   independent CLO review. Do not prepare exact collection commands until this
   review clears; accepted Codex notice policy is not collection authority.
4. **Bounded holder-worker foundation:** record the selected trust boundaries
   and failure semantics in a new architecture decision after rechecking the
   decision ordinal. Add a reviewed nonsecret primary-app
   Supabase endpoint-and-port manifest first; then update and review the
   dedicated-host Terraform, systemd/cgroup worker, network and egress policy, operation-scoped
   read-only DB identity, off-host durable deadline/revocation authority,
   server-enforced expiring database credential, separate verifier and vault
   fencing, restoration and no-SSH observability before code. Keep host creation
   disabled by default. Before any apply, recheck EU stock and cost, record the
   chosen server type and location, and obtain the exact command's explicit
   operator authorization. Test busy loops, pending transactions, synchronous
   blocks, stubborn descendants, revocation ordering, active sessions, repeated
   short transactions, scheduler restart/queue/outage, measured deadline-job
   maximum lag, server-side credential lease expiry, stale-generation reconnect,
   vault restore/deletion and verifier outage using only disposable
   infrastructure. Verify `max_prepared_transactions=0` on the exact hosted
   project; if this cannot be proven, the ADR must choose a tested prepared-
   transaction cleanup or no-go. Independent review
   must confirm supervisor and backend absence evidence before this phase
   clears. Do not
   prepare exact collection commands while any item remains open.
5. **Collection command gate:** only after Phases 3–4 clear, prepare the exact
   source, target, operation, scope, schema, version-pinned collection command
   and a no-op render/hash. Obtain independent technical, GDPR and CLO review
   of the exact command bytes. Request the separate explicit collection
   authorization only after that review; execute only the authorized bytes.
   Record operation ID/generation, start/stop, bounded result and deletion
   evidence. Partial, timed-out, revoked or unknown outcomes stay fenced and
   stop before reconciliation.
6. **Writer-window command gate:** only after collection has a complete,
   independently verified result, prepare the exact writer-window commands
   against the observed evidence, target and migration hashes. Obtain a new
   independent review and a separate explicit writer-window authorization.
   Never reuse collection authorization. If either review or authorization is
   absent, no writer window or reconciliation proceeds.
7. **Reconciliation, schema equivalence and rehearsal:** reconcile only after
   both preceding gates clear; verify exact source/schema equivalence and run
   the approved rehearsal, keeping writes disabled until the writer-window
   authorization is active. Preserve evidence of before/after state and stop on
   any mismatch.
8. **RLS parity and Slice A — request-time rights snapshot:** first prove the
   disposable-database table/column grant registry matches effective grants
   for all three API roles. Then add RED tests for atomic
   admission-time capture, same-request retry versus new request, completed-job
   non-reuse, job-bound worker reads, email admission, tenant scope, snapshot
   deletion/restore and no nonce/hash. Implement and QA this slice in a
   companion PR stacked on the held #9051 feature branch.
9. **Slice B — lifetime, cleanup and renewal:** add RED tests for contract-role
   refusal before issuance/provider admission, post-lock clock boundary,
   same-nonce and replacement timestamp, one-minute bounded `pg_cron`, backlog
   health, issuance refusal, rollback erasure coverage, renewal protocol/UI,
   cache expiry and exactly-one explicit resend. Commit the `.pen` before UI
   coding. Implement this dependent slice on Slice A; keep all six asks in one
   completion gate across the stack.
10. **Offline integration and QA:** use only disposable PostgreSQL and
   synthesized fixtures, with no ambient shared DB/provider credentials. Run
   focused migration/DSAR/handler/client/UI suites, RLS fuzz, typecheck,
   screenshots, TOM4/legal cross-document checks and repository static gates.
   Verify archive and logs never contain raw nonce/hash. Run `soleur:gdpr-gate`,
   CLO review, exact-head code review, QA and preflight on both slices and the
   final integrated head.
11. **Records and qualification:** append dated migration-conditioned
   PA-2/compliance records and update the DPA, privacy and GDPR artifacts and
   their mirrors only after final CLO verification. Later runtime qualification
   still requires fresh exact-head recovery, provider permission for the exact
   route, current served-build renewal tests, fresh approved shared evidence,
   verified no-writer activity outside the authorized window, and all recovery
   gates. Keep customer content blocked until
   that separate clearance exists.

## Observability

```yaml
liveness_signal:
  what: "Planned bounded worker heartbeat and exit; generation revocation; verifier-confirmed active sessions, transactions and locks; cleanup freshness, expired backlog and oldest expired-row age"
  cadence: "After implementation, each operation is bounded by systemd/cgroup deadlines; an independent off-host monitor checks worker and verifier freshness and must detect missed cleanup before the five-minute deletion allowance"
  alert_target: "Web Platform engineering on-call"
  configured_in: "Planned dedicated collector host and egress gateway in the existing Terraform root; systemd Type=oneshot under cgroup v2; host nftables and authenticated proxy; Vector journald and host_metrics to Sentry; independent database verifier and Sentry monitor. Verify the exact off-host signal and alert delay in Phase 2"
error_reporting:
  destination: "Sentry web-platform through Vector journald/host_metrics and the existing Sentry monitor inventory, correlated to the deployed release SHA; events contain aggregate state only, never subject IDs, receipt bodies, credentials or provider payloads"
  fail_loud: "The durable authority attempts generation/credential revocation before requesting cgroup termination; systemd may independently kill the cgroup on its hard timeout even if revocation is unavailable. That kill is not revocation or stop evidence. Report stop only after the independent verifier confirms zero operation sessions/transactions/locks and revocation/credential expiry is proven; unknown authority, supervisor, verifier or scheduler state keeps the fence held and refuses new credentials/work. Expiry rejects stale delivery/acknowledgment; unhealthy cleanup blocks issuance; a failed DSAR snapshot prevents archive publication"
failure_modes:
  - mode: "Collector busy-loops, blocks synchronously, forks descendants or exceeds its systemd start deadline"
    detection: "Layer 3 Vector journald ships systemd/cgroup timeout and forced-kill status; Layer 4 Vector host_metrics shows a worker still consuming resources"
    alert_route: "Web Platform engineering on-call; collector status command reports the bounded operation state"
  - mode: "Deadline/revocation authority, server-side credential lease, or independent verifier fails"
    detection: "Layer 3 Vector journald records bounded transition codes; Sentry receives only an approved aggregate health projection, never operation IDs or principal digests; detailed authority acknowledgment and independently observed sessions/transactions/locks stay in the access-controlled control record"
    alert_route: "Web Platform engineering on-call; keep the operation fence held"
  - mode: "Collector or gateway attempts an unapproved destination, or resolver returns a private/special-use address"
    detection: "Layer 3 Vector journald ships host nftables/proxy refusal codes; Layer 4 Vector host_metrics exposes unexpected egress volume"
    alert_route: "Web Platform engineering on-call; operation is refused"
  - mode: "Delivery repair or acknowledgment reaches the expiry boundary"
    detection: "Layer 2 Pino-to-Sentry mirror records a bounded expiry code; Layer 5 release context binds it to the served SHA"
    alert_route: "Web Platform engineering on-call"
  - mode: "Cleanup is late, errors, skips locked rows or exceeds measured backlog capacity"
    detection: "Sentry monitor reads independent cleanup freshness, backlog count and oldest expired age; Vector journald (Layer 3) carries bounded host status, and release context (Layer 5) binds remediation to the deployed SHA. Alert before the five-minute allowance expires"
    alert_route: "Web Platform engineering on-call"
  - mode: "DSAR admission snapshot fails or a worker reads another job/subject's snapshot"
    detection: "Layer 2 Pino-to-Sentry mirror and job's persisted failed status; no partial archive is published"
    alert_route: "Web Platform engineering on-call and the DSAR request status"
  - mode: "Database outage prevents cleanup"
    detection: "Sentry monitor reports stale cron completion and rising oldest-expired age; Layer 5 release context binds remediation to the deployed source"
    alert_route: "Web Platform engineering on-call"
logs:
  where: "Sentry receives only approved aggregate counts/ages and transition categories; Vector ships redacted systemd/nftables/proxy status; detailed verifier and pg_cron evidence stays in access-controlled records"
  retention: "CLO-approved numeric retention bounds for each Sentry, database, authority, report, tombstone and deletion record must be set before collection; existing defaults are not evidence of approval"
discoverability_test:
  command: "(planned) bash apps/web-platform/scripts/holder-collector-status.sh prd && bash apps/web-platform/scripts/codex-notice-retention-status.sh prd"
  expected_output: "collector_health=healthy; active_sessions=0; verifier_fresh=true; notice_retention_health=healthy; expired_backlog=0; oldest_expired_age_seconds<300"
  credentials_required: "Doppler read-only status and separately authenticated observer credentials; no database URL or secret in process arguments, logs or output; neither command exists yet"
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
| 6 [issue #11170] | "Obtain source CPO/user-impact, GDPR and CLO reviews; retain all independent hosted-auth/provider, runtime and shipping holds." | User-Brand Impact; Legal and Operator Decisions; Phases 1, 3, 10 and 11; final acceptance criteria | mapped |
| 7 [PR #9051 continuation] | "Complete the bound collector, independent authority, vault, workers, fencing, restoration, technical and GDPR/CLO reviews." | Bounded holder-evidence worker prerequisite; systemd/cgroup, authority revocation, independent verifier, separate vault, isolated network and offline fault suite | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|----------------------------------|---------|
| Atomic request-time snapshot, job binding, request/retry identity, nonce/hash omission and DSAR completeness tests | asks 1 and 3 | asked |
| Forward migrations, derived expiry, post-lock clock checks, retry/reissue rules and bounded database cleanup | asks 2 and 5 | asked |
| Reachable renewal action, held-cache disclosure and explicit resend tests with committed `.pen` | ask 4 | asked |
| Ownership/generation/membership/erasure checks and lifecycle integration coverage | ask 3 | asked |
| Independent cleanup freshness/backlog/oldest-expired-age monitoring and no-SSH discoverability probe | "Cover all issuance/delivery/consume paths, expiry boundaries, ownership/generation/membership fences, erasure and failure observability." — issue asks 3 | asked |
| Dedicated bounded holder-evidence worker, operation-scoped DB principal, off-host durable deadline/revocation, server-side credential lease, independent session verifier, separate vault roles, network/egress gateway and restore tests | "Complete the bound collector, independent authority, vault, workers, fencing, restoration, technical and GDPR/CLO reviews." — PR #9051 continuation | asked |
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
| Reviewed nonsecret primary-app Supabase endpoint-and-port manifest; `apps/web-platform/infra/holder-collector.tf`, dedicated private network/subnet, egress gateway, firewall/route resources, cloud-init, worker/gateway systemd, nftables and proxy templates, and `infra/tests/holder-collector-*` | PR #9051 continuation | asked; use the existing Terraform root and keep both servers disabled by default |
| `apps/web-platform/scripts/holder-collector-status.sh`, offline process/cgroup/PostgreSQL fault tests, Vector/Sentry bindings and independent verifier checks | PR #9051 continuation and ask 3 | asked |
| DSAR allowlist completeness and worker per-row tests | ask 1 | asked |
| Focused DSAR, handler, migration, RLS and RPC-grant tests | asks 1–5 | asked |
| TOM 4 checker and mutation suite | asks 1, 2 and 5 | asked |
| `knowledge-base/legal/data-processing-agreement-template.md` | — | inferred — legal wording must match implementation; requires prior CLO approval |
| `knowledge-base/legal/article-30-register.md`, `compliance-posture.md`, and applicable privacy artifacts | ask 6 | asked |

### Split Assessment

- Minimum inventory: at least 35 files across six subsystem roots —
  `apps/web-platform`, `scripts`, `knowledge-base`, `docs`, `plugins`, and the
  separate infrastructure root `apps/web-platform/infra`. It includes two forward
  migrations, DSAR admission and worker, email intake, WebSocket handler and
  protocol types/schemas, client/cache and chat surface, committed `.pen`,
  isolated collector and egress-gateway Terraform, systemd/cgroup worker,
  independent database verifier, vault restore path, off-host health monitoring,
  process/SQL/DSAR/client/UI tests, TOM4 gates, DPA/register/
  compliance text, and six canonical/mirrored privacy documents with legal SHA
  pins. The earlier 23-file/700-line estimate is obsolete.
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines.
- Recommendation: three dependent slices, all held behind one completion gate
  and stacked on #9051's draft branch. The bounded collector foundation lands
  before any exact collection command; Slice A implements atomic rights
  admission/snapshot and job-bound export; Slice B implements expiry, bounded
  cleanup/health and the
  renewal UI/protocol. Integrate both before reconsidering #9051 readiness. One
  completion gate spans all six asks. Do not target `main` with either
  correction migration until prerequisite
  `175_codex_history_notice_issuance.sql` from #9051 is present
  there. On 2026-11-18, fetched main reached ordinal 186, so remeasure before
  choosing correction ordinals. Preserve the draft hold.

## Acceptance Criteria

- [ ] No exact holder-evidence collection command is prepared until an opt-in
      dedicated worker has an externally enforced systemd/cgroup deadline,
      operation-scoped read-only DB identity, database-enforced credential
      lease, durable revocation fence, independently authenticated
      backend-session verifier, and separately identified encrypted vault with
      tested all-copy restore and erasure. The separate purpose, basis, subjects,
      roles, Article 14 assessment, DPIA screening, service/transfer review,
      allowlists, per-copy retention and rights handling must pass independent
      technical, GDPR and CLO review first.
- [ ] A reviewed ADR chooses a numeric operation deadline and maximum backend
      stop lag, plus the exact database-side enforcement and failure tolerance,
      or records a no-go for this collector substrate. No placeholder or
      unmeasured scheduler cadence qualifies as a bound.
- [ ] The source manifest explicitly includes or excludes every provider
      surface in the coverage design. Each included source has separate purpose,
      contract and destination review; its exact FQDN/port feeds the worker,
      proxy ACL and Hetzner outbound firewall. No broad wildcard is allowed.
- [ ] The vault provider, service/account, region, replication, backup and key
      management are identified and reviewed. Receipt-bearing backups are
      excluded or per-operation encryption keys are held outside every copy
      domain and crypto-erased within 24 hours; restore tests reject tombstoned
      generations. Sentry receives only approved aggregate counts/ages and
      transition categories without operation IDs or principal digests, and
      CLO-approved retention bounds exist for every record class.
- [ ] Database stop evidence proves zero sessions, transactions, prepared
      transactions and locks. Verify the exact hosted project's
      `max_prepared_transactions=0`, or qualify an operation-scoped cleanup for
      prepared transactions; `pg_terminate_backend` alone is insufficient.
- [ ] Exact collection commands are pinned, dry-rendered and independently
      reviewed against the target and source revision before requesting a
      separate explicit authorization for collection. After collection, exact
      writer-window commands receive a new independent review and separate
      explicit authorization. Neither authorization covers the other action.
      Partial/timed-out/revoked/unknown outcomes remain fenced and cannot enter
      reconciliation or a writer window.
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
- [ ] Holder-evidence receipt, authority, report, tombstone, deletion-receipt
      and telemetry schemas each have approved allowlists, necessity, access,
      retention, deletion, rights and restore behavior. Filtered receipts expire
      within 24 hours of capture across Firestore history, database, host/volume
      snapshots, temporary files, dumps, logs and restored copies by verified
      deletion or crypto-erasure; an external tombstone prevents resurrection
      and re-deletion is verified.
- [ ] A CLO-approved rights process covers people represented in holder
      evidence across receipts, reports, authority records, tombstones,
      telemetry, backups and restored copies; it records identity/scope checks,
      response status, applicable deadline and unresolved copies separately
      from the Codex request-time export lifecycle.
- [ ] Expiry is enforced by the database at delivery and acknowledgment; same
      nonce retries cannot renew lifetime, new notices follow the approved
      timestamp rule, and cleanup is indexed, bounded and monitored.
- [ ] Expiry, acknowledgment, cleanup, renewal and recovery never dispatch
      provider work by themselves. A committed `.pen` precedes UI code, and the
      client requires a fresh notice, fresh acknowledgment and separate explicit
      resend while accurately describing its 30-minute tab-cache limit. Expired,
      denied, offline, rate-limited and socket-dropped states are retryable or
      explicitly unresolved without losing the held draft inside its cache
      bounds. Keyboard, screen-reader and narrow-screen checks cover expiry,
      pending, success, failure and resend.
- [ ] Contract-subject eligibility is checked before notice issuance and
      provider admission; team or owner role alone never qualifies.
- [ ] Migration/DSAR/handler tests pass with synthesized fixtures in an
      isolated database; TypeScript, RLS/TOM4, legal cross-document and exact
      source gates pass. No provider or shared database contact occurs during
      offline QA.
- [ ] The PA-2/compliance and DPA records accurately describe the final
      processing, access, expiry, roles and deletion behavior, conditioned on
      the reviewed migration. CLO verifies the final wording.
- [ ] Before holder-evidence collection, source-specific services/projects,
      regions, recipients, support access, DPAs, processor roles, data location
      and transfer safeguards are verified. Any required processing records
      and privacy disclosures are updated and published after CLO approval.
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
- Reviewed nonsecret primary-app Supabase pooler endpoint-and-port manifest as the sole input to worker configuration and proxy ACLs; never reuse the endpoint for the separate Inngest project.
- `apps/web-platform/infra/holder-collector.tf`, dedicated private network/subnet,
  egress gateway, firewall/route resources, cloud-init, systemd units, nftables
  and authenticated proxy templates; all new hosts disabled by default.
- `apps/web-platform/scripts/holder-collector-status.sh`, independent observer
  adapter, Vector/Sentry monitoring bindings and offline process/cgroup/
  PostgreSQL supervisor fault tests. These are planned artifacts, not present
  capabilities.
- `knowledge-base/engineering/architecture/decisions/ADR-<rechecked-ordinal>-bounded-holder-evidence-worker.md` — choose a qualified database-side deadline/termination substrate with measured maximum lag, or a no-go/different substrate; record service boundaries, vault roles, egress, recovery and fail-closed held states. Recheck ordinal before creation.
- `knowledge-base/project/specs/feat-one-shot-codex-web-live-paths/holder-provider-coverage-design.md` source projections, source-specific service/contract/data-flow assessment, receipt/authority/log schemas, rights and retention matrix, and all-copy restore/erasure evidence; legal disclosures only after CLO approval.
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
4. What reviewed nonsecret source will pin the primary app project's Supabase
   pooler FQDN and port for both worker configuration and proxy ACLs? The repo
   has no such endpoint today; do not infer it from the separate Inngest
   project's pooler. Add and validate the manifest before egress implementation.
5. Which source set from `holder-provider-coverage-design.md` is in scope, and
   what vault provider/region/key-management and backup topology satisfies
   separate custody and 24-hour crypto-erasure? Resolve these in the technical
   ADR and source-specific CLO review before infrastructure implementation.
