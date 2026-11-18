# Writer-holder evidence preparation — 2026-10-27

## Disposition

Preparation only. This proposes a bounded, names-and-metadata-only inventory
for a future independent review. No collection command below was run; this
document does not authorize collection, credentials access, workflow changes,
database operations, writer clearance, or restoration. The October 27 catalog
capture approval is consumed and cannot be reused. A new exact-action review
and approval is required before any live collection.

The current capture reports 14 sessions and 43 locks at
`2026-10-27T10:27:19.021Z`, but does not retain enough identity, effective
privilege, or consumer evidence to identify all writers. It excludes column
ACLs, role inheritance and effective table/column privileges. The snapshot is
not a census of cached credentials or future connections. See
[the capture record](recovery-capture-2026-10-27.md) and
[the writer-window preparation](writer-window-preparation-2026-10-27.md).

## Questions this evidence must answer

For every path capable of changing the shared development ledger, migration
state, or application data, identify the principal or service, its effective
write capability, where it obtains authority, whether it is active, and the
enforced action that stops it. Classify uncertainty as `unknown`; absence from
one provider's roster is not proof that a path is absent.

The inventory covers:

1. GitHub workflow admission, every nonterminal run on every ref, and
   repository/environment administration that can dispatch or re-enable the
   three identified mutators.
2. GitHub App identities and repositories/secrets access paths that can run
   `tenant-integration.yml`, `scheduled-integration-suites.yml`, or
   `dev-ledger-reconcile.yml`.
3. Supabase organization/project members, database roles and inherited grants,
   `PUBLIC` grants, service-role API access, active sessions, and connection
   pools or workers that can reconnect.
4. Doppler project/config readers and service tokens, identifying token
   metadata, scopes and owners without reading token values or database
   secrets.
5. Deployed development services, scheduled jobs, seed tools, local/agent
   execution principals and administrative bypasses. Include the
   `bot-fixture.ts seed` consumer and any service holding a Supabase service
   key.

The workflow pause proposal covers only new admission to three GitHub Actions
workflows. It does not itself revoke a running job's credentials, prevent a
direct database/API writer, stop an independently deployed consumer, or
prevent a sufficiently privileged administrator from reversing the pause.

## Proposed collection contract — not authorized

Before asking for a new exact-command approval, prepare an executable
collector whose immutable source identity, provider/API endpoints, requested
fields, output schema, byte/row/time limits, and command are reviewed together.
Use GitHub App authentication for GitHub writes; this proposal requests only
provider read scopes. Obtain database connectivity only through an existing
approved read-only principal. Never print or persist secret values, SQL query
text from sessions, application rows, chat/history, emails, or raw tokens.

The collector should make separate, independently status-checked sections so
one unavailable provider cannot make another provider's empty result look
complete:

| Source | Minimum metadata | Must remain unknown when unavailable |
|---|---|---|
| GitHub Actions | Workflow numeric ID/path/state; every page of run ID, ref, event, status and conclusion for all target workflows; initiating actor identity; relevant App/repository/environment access metadata | Empty run census, complete run history, admission state, or effective ability of an unobserved admin/App |
| Database roles | Role name, `rolcanlogin`, superuser/bypass attributes, memberships and grant options, ownership, role/database/schema/table/column grants including `PUBLIC`; effective `has_table_privilege`/`has_column_privilege` results for the mutation targets | Effective privileges, inherited access, or complete role coverage if any catalog arm fails or is omitted |
| Database sessions | Session count and minimized role, application-name class, state, transaction age, and whether the session can write a target | No active writers from a zero/failed/partial query; future reconnect exclusion |
| Supabase and secret manager | Member/principal identifiers, roles, service-token metadata/scope/config association, key-rotation/version metadata and audit evidence of access where available | Who copied or cached a service key; which process still holds a value; key revocation effect unless measured |
| Deployed consumers | Service/workload identity, environment, deployment/config reference, enabled/scheduled state, secret reference name (never value), reachable write path and verified fence | No persistent consumer from a missing inventory or stale deployment record |
| Local/agent access | Authorized principal and session/token metadata available from identity providers; local process inventory limited to the controlled execution host | Other operators' machines, unreported exports, copied credentials or offline agents |

For PostgreSQL, independently query `pg_roles`, `pg_auth_members`, ownership
and ACL catalogs, then compute effective table and column privileges using the
server privilege functions over the complete target relation/column set.
Include inherited memberships and `PUBLIC`; do not infer effective access from
direct grants alone. Enumerate active connections without selecting
`pg_stat_activity.query`; omit client addresses and backend PIDs from the
reviewer-facing projection. A catalog query failure, unsupported permission,
unavailable extension/view, or truncation means `unknown`, never zero.

Provider-side membership and token metadata do not reveal all copies of an
already-issued credential. Reconcile those rosters with service deployment
references, audit/access logs and the key's actual authorization boundary.
If a credential's holders cannot be established, treat it as an unaccounted
writer path. Do not rotate or revoke it as part of evidence collection.

## Collector implementation checkpoints

These checkpoints refine the preparation; they are not a collector or a
collection authorization.

1. Bind the executable, query text, endpoints, target identifiers, limits and
   field projections in one immutable manifest. A preview must verify those
   bindings without reading credentials, contacting providers or creating
   receipts. Any changed binding requires another review and approval.
2. Give each source and each database catalog arm its own result state:
   `complete`, `partial`, `failed` or `unsupported`. Include start and end
   times, counts, pagination termination and limit reasons. A complete page
   traversal is an interval observation, not a consistent snapshot or fence.
   A denied permission, unknown response shape, cap or timeout cannot become
   an empty complete result.
3. Project an explicit allowlist before writing any bytes to disk or logs;
   validate types and lengths and replace arbitrary provider error bodies with
   fixed error categories. Treat application names as untrusted input and map
   them to reviewed classes, with all unmatched values grouped as `unknown`.
   A failure to parse or classify must not persist the original value.
4. Before collection, establish an independently scheduled deletion mechanism
   that survives collector and host interruption, covers every receipt copy,
   runs by the capture-based 24-hour deadline, and emits a verifiable result.
   A process exit handler, local timer on an unverified host, or a promise to
   delete later does not establish that guarantee. If it cannot be proven,
   collection stays blocked. A deletion failure must remain visible as a
   failure; deleting a pathname alone does not prove backup copies were removed.
5. Exercise synthetic provider responses and a disposable database only: test
   multi-page and changing inventories, partial or denied arms, hidden sessions,
   inherited and `PUBLIC` privileges, role switching and function execution,
   arbitrary sensitive fields, size/time limits, interrupted execution,
   deletion failure and independent cleanup after process loss. Mutation-test
   the completeness and redaction assertions. Record which cases cannot be
   reproduced and keep their corresponding live coverage `unknown`.

The proposed output must separately identify potential privileges, observable
usable routes, and unobservable holders. No overall `complete` flag may imply
that cached credentials, future connections or unobserved administrators have
been excluded. A complete inventory is not writer clearance.

## Data minimization and retention

Collect metadata only. Filter each response through a reviewed field allowlist
before any persistence, including errors and arbitrary application names; raw
provider responses can contain excluded information. Store filtered receipts
in a private directory with mode `0700`; files `0600`. Do not commit receipts
or include credentials, application rows, SQL text, client addresses, emails,
or unrelated personnel data. Prevent copies in logs and backups. Keep a
separate minimized report containing source/command identity, capture time,
result counts, completeness markers, and unresolved holder categories. Delete
filtered receipts no later than 24 hours after capture, even if review has not
occurred; verify deletion and record its result. Interrupted collection and
cleanup failure must be reported, not treated as deletion. Any broader field
or retention request requires a revised privacy review and exact-action approval.

This material concerns identity and access metadata and remains a regulated
processing surface. The preparation does not establish a new lawful basis,
retention period, or final CLO processing clearance. `soleur:gdpr-gate` and
`soleur:legal:clo` review are required before live collection is proposed.

## Decision and clearance criteria

The CTO ruling for this preparation is to inventory every provider and direct
write path, preserving `unknown` where credential copies, principals, or
persistent consumers cannot be bounded. Do not activate a writer window from
the workflow roster or database snapshot alone.

After a separately approved collection, independent reviewers must reconcile
each holder path to a reviewed, enforceable fence and a tested restoration
owner. The restoration controller must be rehearsed for partial workflow
disable, lost API responses, authentication loss, host/process interruption,
and concurrent administrative changes. Only after those checks can a new
exact-command pause proposal be prepared. Workflow pause, drain observations,
direct-holder fencing, and restoration remain separate approvals. Any later
ledger action retains its own mutex acquisition, transactional lock, fresh
schema/tuple verification, compare-and-swap, and exact-action authorization.

## Observability

- **Signal:** per-source completeness and error markers, row counts, run IDs,
  effective-privilege classifications, reviewer disposition and filtered-receipt
  deletion receipt.
- **Owner:** executing agent for collection; independent reviewer for coverage
  and privacy; named controller owner for any later fence/restoration.
- **Failure modes:** unavailable provider, pagination truncation, privilege
  query error, unmapped credential, stale deployment, output cap, and
  interruption all mark the affected path `unknown` and block clearance.
- **Discoverability test command:**
  `cat knowledge-base/project/specs/feat-one-shot-codex-web-live-paths/holder-evidence-preparation-2026-10-27.md`
  reads this local proposal without SSH; it does not test live writer state or
  prove that the file is committed.
- **Retention:** private filtered metadata receipts for no more than 24 hours
  after capture; retain only minimized completeness results and digest.

## Evidence and validation boundary

Repository inspection confirms the previous collector is absent from this
worktree's tracked files and `.soleur` contains only the private catalog and
receipt. The existing capture declares `writer_clearance:false`; no holder
inventory, fence, or restoration controller is evidenced here. The proposal
was written offline; its provider commands, SQL, completeness, and retention
deletion were not executed or independently validated. No shared state was
changed.

## Independent preparation review — 2026-10-27

The read-only review found the proposal is not ready for collection approval.
Before proposing an exact command, the collector must bind its source digest,
endpoints, SQL, field allowlists, per-source limits and receipt schema; record
unsupported, partial and failed sources separately; and pass synthetic tests
for pagination, partial responses, limits, interruption, cleanup, sensitive
fields and permission failures. Pagination needs a capture interval and final
page checks; a changing run list is not a fence.

Database coverage must include executable privileged functions and RPCs,
ownership, superuser and role switching, schema creation, triggers, RLS and
service-key paths as well as table and column privileges. Separate potential
privilege from a usable route. Test session visibility, including pooled
identities, and mark unobservable sessions and future reconnects unknown.
Even a complete provider roster cannot establish that cached credentials have
been eliminated. This review grants no collection or writer clearance.

## Addendum — local page projection prototype

The earlier statement that the previous collector is absent from tracked
files is incorrect: `apps/web-platform/scripts/capture-codex-dev-catalog.mjs`
is tracked. It is the previously approved catalog collector, not a complete
holder collector, and its earlier approval does not authorize another run.

An offline-only page projection prototype and synthesized tests now exist in
`apps/web-platform/scripts/holder-evidence-core.mjs` and its adjacent test.
They accept supplied objects only; they do not fetch, authenticate, write
receipts or establish source identity. Their `complete` state describes only
the supplied page walk and always carries `writer_clearance: false`. They do
not establish pagination stability or provider coverage. A bound live collector,
database/provider coverage, durable deletion, independent review and legal
review are still required before a collection command can be proposed.

## Addendum — preliminary source-specific CLO assessment, 2026-10-28

The independent CLO's provisional assessment identifies the Article 30
register's PA-8 (operational telemetry and breach-detection logs) as the
closest existing purpose, not as authorization for this operation. Its
documented subjects and logging destinations do not establish coverage for a
deliberate roster of personnel and credential holders or a new evidence vault.
PA-12, PA-33 and PA-35 concern other activities and do not establish this
operation's scope or basis. The earlier nonce decision does not authorize a
new holder capture.

Before a collection proposal, assess whether to amend PA-8 or document a
distinct activity, and complete an operation-specific necessity and balancing
assessment. For GitHub, identify actor categories, repository and environment
scope, ref-digest linkability and any outside contributors. For database and
Supabase arms, document principal and project scope, potentially identifying
role/session metadata, affected member categories and visibility limits. For
Doppler, verify the metadata endpoint, suppression of key-bearing fields and
the applicable contractual instrument; the CLO found DPA verification and
register mapping remain open in the compliance posture. For local and
deployed consumers, define the host and jurisdiction boundaries and exclude
unsupported claims about other machines.

The final data flow must identify the vault operator, recipients, contractual
roles, storage and transfer safeguards, all copies and verified deletion, and
separately justify the retention of any minimized report and deletion receipt.
Assess Article 14 notice and how rights requests are handled during capture
and retention. If the final flow is a new processing activity, the CLO skill
requires updates to the Privacy Policy, Data Protection Disclosure and GDPR
Policy, with corresponding published mirrors where applicable. Identifiers,
digests and aggregates must not be assumed anonymous. This is preliminary
assessment, not final legal clearance or permission to collect.

## Addendum — preliminary Firestore assessment

An independent CLO review found that the existing Google entry in the
compliance posture covers a different service and does not establish the
processor terms, access routes, transfers or purpose of a Firestore ledger.
The actual Google service and account, as well as the proposed Hetzner,
Cloudflare, AWS and Doppler arrangements, require source-specific contractual
and data-flow verification. PA-8 remains a possible register amendment, not
an established basis for this roster or vault.

Keep receipt bodies and raw provider responses out of the control ledger.
Opaque operation identifiers, timestamps and transition markers can still be
linkable and require their own necessity, access, retention and rights
assessment. Firestore's documented historical-version window and any backups
are separate copies; logical deletion and asynchronous TTL do not establish
the capture-based receipt deletion deadline. Before activation, assess
Article 14 notice for the actual sources and recipients, including the
applicable timing and exceptions, and test rights handling across all copies.
The final flow also needs DPIA screening, the relevant register and disclosure
updates, and verified processor and transfer safeguards. This remains a
preliminary assessment, not legal clearance.

## Addendum — preliminary v2 control-record assessment, 2026-10-29

Independent CLO review keeps live processing blocked. The proposed canonical
intents, principal digests, timestamps and incident records can be linkable;
an unkeyed digest is not anonymity. The holder-receipt 24-hour ceiling does
not itself establish a retention period for control records, Firestore history,
backups, restored copies, logs or the incident channel. Each needs an identified
purpose, recipient, access boundary, retention and deletion rule, and tested
rights and notice handling. The source-specific contractual, transfer, Article
30, balancing and DPIA requirements above remain open for the actual flow.
This is preliminary assessment, not final clearance or collection authority.

## Addendum — CTO collector-boundary ruling, 2026-11-18

The in-process injected-adapter lifecycle is not a bounded collector. The
adapter can retain the raw connection in shared closure state and perform
untracked work alongside a settled tracker handle. Its `Promise.race` deadline
also cannot preempt synchronous adapter or inspection callbacks. The current
verifier validates only an adapter-reported object; it does not independently
observe backend session, transaction, or lock state. No production lifecycle
caller is wired.

The selected replacement boundary is a per-operation Linux worker managed by
an OS-level systemd/cgroup supervisor. The coordinator must never receive the
database client or socket. The worker creates and exclusively owns a
connection using an operation-specific read-only principal, and returns only
a bounded sanitized projection. On timeout, durable authority revokes the
operation generation and credentials before the supervisor kills the entire
cgroup. A separately authenticated narrow database observer must then verify
that no sessions, transactions, or locks remain for that operation before
stop can be reported or resources released. Worker exit alone is not proof.

Before exact collection-command preparation, the branch needs a Terraform-
managed Linux supervisor with tested cgroup-v2 kill semantics; the scoped
database principal and independent observer with effective grants verified;
durable authenticated authority CAS/revocation and worker STS issuance; a
separately identified encrypted vault with durable tombstones and restore/
erasure proof; and an offline fault suite covering busy loops, descendants,
pending transactions, stale-generation reconnect and observer outage. Local
PostgreSQL mechanics do not establish Firestore/provider IAM or production
authority. Collection and writer authorization remain held.

The independent CLO review also remains blocked for processing clearance,
readiness, and shipment. Contract-subject/controller-capacity facts, measured
cleanup and monitoring, backup/PITR and restore deletion, rights-copy lifecycle,
final notice/client flow, and exact-head schema/legal/QA evidence are not
established. This review is internal and does not provide external counsel
advice or collection authority.
