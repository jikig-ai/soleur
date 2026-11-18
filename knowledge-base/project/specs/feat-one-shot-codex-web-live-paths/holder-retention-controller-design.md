# Holder evidence retention controller — offline design

## Disposition

This is a design and two local synthetic experiments, not an implemented or
deployed deletion service. No provider was contacted and no live receipt was
created or deleted. The current holder collector remains **blocked**: there is
no demonstrated independently scheduled deletion service, no proven inventory
of every possible receipt copy, and no processing or retention clearance.

The 24-hour ceiling in [holder evidence preparation](holder-evidence-preparation-2026-10-27.md)
is measured from capture, not from the end of a review or an operator's later
action. An availability outage can prevent timely deletion; no design below
claims an unconditional guarantee under an unreachable store or simultaneous
controller failures. The executor must refuse collection unless the whole
admission proof below is satisfied. A later failure is a retention incident,
not permission to retain the receipt longer or a successful cleanup.

## Concrete candidate and isolation boundary

Use a dedicated, separately provisioned private receipt vault in a failure
domain independent of the collecting process and host. The vault owns a
private POSIX directory (`0700`) and fixed receipt files (`0600`); a collector
streams only already-projected, allowlisted metadata over an authenticated,
encrypted channel to a bounded vault API. It must not write a local receipt,
raw response, temporary copy or log. The vault and its controller are separate
from the collector. Their storage, identities, scheduling, monitoring and
network policy must be declared through Terraform, reviewed and authorized
before provisioning; this document does not authorize provisioning or a live
collection. This is a candidate architecture, not a claim that the repository
already provides a suitable vault or scheduler.

Before capture, prove all of the following with a bounded, synthetic
end-to-end probe on the actual proposed substrate:

1. The vault's dedicated filesystem and account are isolated; generated
   operation identifiers are random and are never derived from provider data.
   The allowed filenames are fixed in the collector manifest. The vault uses
   descriptor-relative operations beneath an already-open directory, rejects
   symlinks and hard links, checks file type, owner, device and link count, and
   never follows a provider-supplied path. Any unexpected entry or identity
   change is `unknown`; it must not broaden deletion to a containing directory.
2. The durable control ledger records only an opaque operation identifier,
   vault object identity, capture-start timestamp, absolute deadline,
   approved controller/source identity and state. It contains no receipt body,
   secret, application name, provider error body or personal-data-bearing path.
   Clock synchronization and skew bounds are measured from an independent time
   source; clock uncertainty blocks admission. The capture start is recorded
   before the first byte can reach the vault.
3. At least two independently scheduled cleanup workers in distinct failure
   domains can reach the same vault without the collector host. A durable job
   is registered and read back by both workers before any receipt byte is
   accepted. Each worker has narrowly scoped authority over the specific owned
   operation. Schedule the first attempt substantially before the deadline
   (candidate: 12 hours after capture start), with bounded retries and alerts;
   the exact timings and scheduling implementation require review and a
   substrate-specific rehearsal. A shared scheduler, shared credential, or
   shared network dependency is a correlated failure and must be identified;
   two processes on the same host are not independent failure domains.
4. The vault refuses writes at the absolute deadline and never extends it.
   It seals the operation before deletion, prevents new opens and writes, and
   closes all controlled readers/writers. Deletion is scoped to the recorded
   operation and fixed entries only. A pathname disappearing is insufficient:
   an open descriptor can retain the content, and hidden copies may survive in
   snapshots, backups, swap, crash dumps, provider access logs or telemetry.
   Prove each of those surfaces is disabled, excluded or subject to the same
   verified deadline. If any copy or open reader cannot be accounted for,
   the result is `unknown`. Encryption-key destruction is not a substitute
   for the requested receipt deletion and copy verification.
5. On a timeout or lost delete response, the worker checks the original vault
   identity and independently reads back absence; it does not infer success
   from a CLI exit or HTTP response. A trusted absence check includes a healthy
   control read so authentication failure, an unreachable service, stale
   routing or an incorrect vault cannot masquerade as an empty directory.
   A changed inode, generation, owner or operation identity is an ownership
   conflict: stop and alert, without deleting the replacement.
6. On verified completion, append a minimized deletion receipt with operation
   identifier, deadline, completion time, verification method and result. If
   deletion or verification is unavailable, partial, late or interrupted,
   record that exact state and alert. Keep it `unknown` or `late`, never
   `deleted`. The no-SSH monitoring path must discover missing jobs, missed
   heartbeats, overdue receipts and failed verification before admission and
   throughout the retention interval.

Ruled by CTO agent: independently operated storage, cleanup and verification
must be established before collection. Local RAM or tmpfs alone cannot supply
the required post-host-loss evidence and verified deletion. Admission must bind
the exact substrate, job readbacks, copy and ownership controls, clock bounds,
rehearsal and monitoring. The local next step is a fail-closed admission check
over synthetic evidence and a concrete Terraform/rehearsal proposal. Shared
infrastructure provisioning requires separate exact-action authorization;
legal processing and retention clearance belongs to the CLO. Dissent: none.

This candidate does not establish a lawful basis, permitted data transfer,
provider location, legal retention period, credential authority, or final CLO
approval. Provider-specific durability, expiry behavior, API semantics and
failure domains have not been investigated or measured here. A scheduled job,
object-store lifecycle rule, local `trap`, tmpfs mount or encryption by itself
does not prove the 24-hour deletion and verification contract.

## Ledger authority boundary — technical ruling

Ruled by CTO agent: a separately enforced ledger authority service must be the
only application principal with Firestore write permission. Collectors, cleanup
workers and the verifier use distinct authenticated identities and typed,
operation-scoped commands to that service; they do not receive its Firestore
credential. The service independently checks the approved operation and
generation, worker and verifier evidence, deadline, trusted clock and
compare-and-swap state before issuing a transition or a signed cleanup capsule.
The vault independently enforces generation, deadline, access and deletion
fences. A capsule must establish current authority, ownership and revocation
status before cleanup; an unreachable authority does not itself authorize
deletion. Unknown or late outcomes block admission and generate an incident.
These requirements remain unimplemented and need an independent security review
and substrate-specific failure rehearsal. Dissent: none.

Firestore server clients bypass Security Rules; IAM protects server and REST
access. Firestore also caches IAM permissions for up to five minutes, so an IAM
role change is not an immediate operation fence. See Google's [server access
guidance](https://docs.cloud.google.com/firestore/native/docs/security/insecure-rules)
and [IAM role-change latency](https://docs.cloud.google.com/firestore/native/docs/security/iam).
An unkeyed receipt hash or validation in a caller-controlled client cannot
establish authority. The offline transport currently refuses every POST before
obtaining credentials. It must remain disabled until the authority, credential
isolation, clock and revocation controls are implemented and independently
reviewed; none is established by the persistence prototype.

### Implementation candidate and acceptance tests

A pinned-image private Cloud Run service with its own Firestore-writing service
account is a candidate authority. Separate collector, administrator, verifier
and worker identities must have only their typed command permissions and no
direct Firestore write or authority-account impersonation. Map a verified
identity to a role, never a caller-supplied role or header. Google documents
[audience-bound service authentication and external federation](https://docs.cloud.google.com/run/docs/authenticating/service-to-service).
The exact Cloudflare worker identity issuer, federation and application-level
identity propagation are not verified; these are feasibility gates, not assumed
capabilities. Google, vault-network and epoch dependencies remain correlated.

#### Identity feasibility research — 2026-10-29

An independent public-documentation review did not establish an ambient OIDC
identity issuer for a scheduled Cloudflare Worker. Cloudflare Access service
tokens and request-context identity do not, by themselves, establish a
scheduled invocation's keyless identity. This is a research limitation, not a
claim that no such capability exists. Google documents [external OIDC
federation](https://docs.cloud.google.com/iam/docs/workload-identity-federation-with-other-providers)
and [Cloud Run service authentication](https://docs.cloud.google.com/run/docs/authenticating/service-to-service):
a candidate path requires an identified trusted issuer, worker-specific
assertion, token exchange, a distinct Google service account and an
audience-bound ID token. A shared service account would lose worker identity.
The application must verify the delivered identity rather than trust a role
header; Google's documented `X-Serverless-Authorization` behavior also needs
attention when choosing the header available for application verification.

Before choosing this path, demonstrate refreshable issuer assertions and the
full exchange in separately authorized disposable infrastructure, including
wrong-issuer, audience and worker denial, revocation and outage cases. Issuer
control, account permissions, network behavior, contractual terms, cost and
retention clearance remain open. No account was queried or provisioned in this
research.

The candidate commands are `prepare`, `arm`, `begin_capture`, `seal`,
`report_attempt`, `report_verified` and `revoke`, with closed bounded schemas
and operation, generation, manifest and request identity binding. The
authority independently verifies job and verifier readiness; a worker's
assertion cannot substitute for independent deletion verification. Mutations
compare revision and append the exact intent receipt atomically. Lost responses
remain unknown until exact-receipt or definitive quiescence evidence resolves
them. The vault separately serializes writes, sealing and deletion against
durable generation and tombstones. It verifies a scoped signed capability and
fresh independent epoch and revocation evidence; a restored state cannot act
until reconciled against a non-rolled-back authority. Cached leases have a
finite revocation latency and cannot claim instantaneous revocation.

An independently monitored time source and monotonic elapsed time must bound
clock uncertainty; stale samples, rollback or excessive skew block admission.
The vault rechecks time and generation at each mutation. An upper time bound
must be before the deadline for receipt writes; early cleanup requires a lower
bound at the permitted time or independently established capture stop. Late
cleanup still needs current authority and ownership and is always reported
late. The precise time and epoch substrate remains unselected.

Acceptance includes synthetic authenticated API tests for every wrong role,
issuer, audience and subject; changed-intent replay, ambiguous commit and
concurrent operations; clock crossings, premature seal, expired or revoked
capsules, rollback and tombstones; and vault replacement races and outages.
Disposable real-substrate tests must separately demonstrate direct Firestore
write denial for each caller, both independently fired jobs, host loss and
volume reattachment, and independently verified deletion and copy controls.
Terraform must declare isolated identities, remote state and serialized apply,
the vault and monitoring. No Terraform resources, provider identities or live
operations have been established by this candidate.

## Candidate object-store constraint

Cloudflare documents that R2 lifecycle deletion typically happens within
24 hours *after* the expiration time and can take longer. A one-day lifecycle
rule therefore cannot by itself meet this record's capture-based 24-hour
deadline. [Cloudflare object lifecycle behavior](https://developers.cloudflare.com/r2/buckets/object-lifecycles/)
is a backup control only; a reviewed, independently scheduled deletion and
healthy readback remain required. R2 documents strong consistency for deletion
and listing, but a successful readback does not by itself establish the absence
of backups, other copies or unobserved readers. [Cloudflare consistency model](https://developers.cloudflare.com/r2/reference/consistency/).
No account-specific R2 configuration or actual retention behavior was tested.

Read-only infrastructure investigation found that the existing CLA evidence
bucket's ten-year lock prevents this use. Workspace GC runs in the application
and covers its own workspace volume; the DSAR expiry sweep changes job state
and does not itself delete this receipt. A dedicated R2 bucket and independent
worker are only a candidate, not a demonstrated solution. The current
preparation contract specifies private directory and file modes; an object-only
design would change that storage contract and needs renewed privacy review.
Any collector-host copy must also be accounted for after host loss. Bucket
scope, version/multipart/backup behavior, jurisdiction, independent scheduling,
monitoring, and deletion and verification under outages remain unverified.

## Addendum — independent technical ruling, 2026-10-28

Ruled by CTO agent: develop a candidate with a dedicated Hetzner POSIX vault
and volume, Cloudflare and AWS scheduled cleanup workers, and a separate Google
Cloud verifier. This is an implementation target, not a proven service or
authorization to provision. Dissent: none. The vault and network remain shared
failure dependencies: independently scheduled workers cannot delete from an
unreachable vault. Host-loss recovery, volume reattachment, open handles and
all copies require a substrate-specific synthetic rehearsal before admission.

The provider says a [Hetzner volume](https://docs.hetzner.com/cloud/volumes/overview/)
attaches to one server at a time and stores replicated blocks. Its published
[technical measures](https://docs.hetzner.com/general/security-and-identify/technical-and-organizational-measures/)
allow up to 48 hours for final deletion of a cloud-server image; destroying a
host is therefore not evidence that the 24-hour requirement is met. Cloudflare
documents that [cron changes may take 15 minutes to propagate](https://developers.cloudflare.com/workers/configuration/cron-triggers/).
AWS documents [scheduler failures and dead-letter queues](https://docs.aws.amazon.com/scheduler/latest/UserGuide/configuring-schedule-dlq.html),
including invalid targets accepted when a schedule is created. Job creation
or readback is not execution proof. Account availability, cost, permissions,
regions, contractual roles and the verifier's independence remain unverified.

Hetzner's [volume overview](https://docs.hetzner.com/cloud/volumes/overview/)
specifies three physical block copies. The published material inspected does
not establish a deadline or verification mechanism for erasing stale blocks
from all replicas after an individual filesystem unlink. Filesystem readback,
directory sync, TRIM, volume reattachment and a successful synthetic rehearsal
therefore do not by themselves establish the existing all-copy 24-hour
requirement. Obtain provider-specific evidence and legal review before relying
on this substrate; a change to that requirement needs separate approval.

Before any receipt bytes, bind and review the exact infrastructure, code and
operation, independently register and exercise both cleanup paths, establish
the verifier and no-SSH monitoring, and rehearse host loss and recovery with
synthetic data. A failed or late deletion is an incident; it is not a verified
deletion. Legal processing and transfer clearance remains with the CLO.

## Operational state machine to implement and review

Ruled by CTO agent: use a dedicated Firestore Native-mode `eur3` database as
the **candidate** control ledger, separate in project and identity from the
Google verifier. One opaque operation record must use a transactional state and
generation comparison; it contains no receipt body or credentials. Google
documents [strong default reads](https://docs.cloud.google.com/firestore/native/docs/understand-reads-writes-scale),
[serializable transactions](https://docs.cloud.google.com/firestore/native/docs/transaction-data-contention)
and [eur3 replication](https://docs.cloud.google.com/firestore/native/docs/locations)
across Belgium and the Netherlands with a Finland witness. These properties do
not prove account access, availability, legal suitability or a deletion
deadline; ledger and verifier still share Google and network failure modes.

Before capture, both workers must durably hold and read back an authenticated,
narrowly scoped operation capsule binding vault, generation, fixed entries,
deadline and approved authority. During a ledger outage, workers may request
idempotent cleanup only for that capsule, provided an independently available
authority check establishes current authorization and revocation as well as
ownership and generation at the vault. If it cannot, the vault refuses and
alerts. No new capture is admitted; verification stays
unknown until healthy independent checks and ledger reconciliation. Receipt
writes stop at the immutable deadline, but cleanup continues after it and must
be reported late. Restore cannot authorize a capture or replacement deletion
without reconciliation against the current vault generation and both jobs.
Firestore [backups restore to a new database](https://docs.cloud.google.com/firestore/native/docs/backups),
can preserve stale state and may contain identifiable metadata; their copies
and retention require CLO review. Firestore also documents that historical
document versions remain readable for [one hour without point-in-time recovery,
or seven days with it enabled](https://docs.cloud.google.com/firestore/docs/reference/rest/v1/projects.databases).
The ledger must therefore never hold receipt bodies; retention of its
potentially identifying metadata and historical versions requires separate CLO
assessment. Out-of-Google alerting, verified time, capsule
revocation, account permissions, network isolation and host-loss recovery remain
unimplemented and must be rehearsed. Dissent: none.

Independent security review: a signature does not establish current authority.
The capsule protocol still needs purpose, audience, issuer/key version, worker
scope, unpredictable operation ID, capture start, earliest cleanup policy,
expected file ownership and current generation, plus authenticated vault
access. A replay must not prematurely seal an active capture. The vault needs
durable terminal tombstones and an exclusive mutation boundary; pathname
comparison followed by unlink is not atomic against a process able to replace
an entry. A restored volume or ledger can roll those records back, so stale
authority cannot delete until reconciled with an independent monotonic epoch.
If current authority or revocation cannot be established during a ledger
outage, cleanup is refused and alerted, not authorized by signature alone.
This may cause a missed deadline; record that outcome as unknown or late.
Clock uncertainty blocks capture and premature cleanup, while any conservative
late-cleanup path needs a separately reviewed ownership and time protocol.
Test restore rollback, stale and revoked capsules, early replay, concurrent
requests, issuer and network outages, time jumps and generation replacement.

The ledger adapter must also retain an immutable, bounded receipt for each
state transition, atomically with its state/generation comparison. A timeout
after a Firestore commit is ambiguous; a later state or a single overwritten
"last command" cannot prove whether that particular transition committed.
Strongly read the pinned ledger and its retained receipt to reconcile an
ambiguous result; if the evidence is missing or inaccessible, report unknown.
Never perform vault deletion or other side effects inside a Firestore
transaction callback, which may be retried. Preserve the exact Firestore
`updateTime` for conditional writes rather than rounding it through a
millisecond clock. These are requirements for the unimplemented adapter, not
claims about the local SQLite experiment. Firestore's
[precondition](https://docs.cloud.google.com/firestore/docs/reference/rest/v1/Precondition)
and [transaction behavior](https://docs.cloud.google.com/firestore/native/docs/manage-data/transactions)
describe the relevant API semantics. Its [TTL deletion](https://docs.cloud.google.com/firestore/native/docs/ttl)
is asynchronous and cannot establish this capture-based deadline.

The persistence prototype binds each receipt to a canonical intent, but the
independent authority must verify that intent and enforce its permissions before
the transport can be enabled. That intent must cover the complete canonical
intent: operation, vault, generation, owner, manifest and controller digests,
predecessor and target state/revision, deadline, clock decision and action.
Reusing a command ID with different intent must refuse; retained receipts must
be unique, bounded, contiguous and never silently truncated. An immediate
strong read that lacks a receipt after a timeout does not prove failure: the
original commit could still be in flight. Return unknown until a separately
defined quiescence or exact-receipt proof resolves it. A receipt proves only
the ledger transition, not a vault side effect. Validate the full pinned
database/document identity, closed schema and types, bounded integer values,
exact microsecond update time and entire state history; unknown fields or a
restored stale database block use pending explicit reconciliation.

Clock assertions from a caller do not establish trustworthy time. Admission
must bind a fresh, independently measured skew interval, and a pre-commit
sample cannot fence a write after a slow commit. The vault must check current
time and generation at every write, with no deadline extension. Late cleanup
remains possible under separately verified authority; a ledger transition alone
cannot mark deletion verified. Receipt exhaustion, competing updates, in-flight
commits after reads, replay with altered intent, clock crossing and restoration
rollback require tests before any live use. IAM and Google account access have
not been verified; privileged server principals cannot be assumed constrained
by client security rules.

The alternative of a vault-local ledger shares the original host-loss failure;
a ledger on either scheduler provider shares that provider's outage. Terraform
state needs an independent key and explicit apply serialization: the existing
web-platform R2 backend documents that it does not itself provide state
locking. None of these controls are established by the local SQLite experiment.

| State | Permitted transition | Evidence required |
|---|---|---|
| `unarmed` | `armed` | Both independent jobs persisted and read back, verified destination/copy controls and deadline |
| `armed` | `capturing` | Separate exact collection approval and immutable collector/vault/controller bindings |
| `capturing` | `sealed` | No new writes; capture stopped or independently fenced; expected ownership still matches |
| `sealed` | `deleting` | An owned, bounded deletion attempt before the deadline |
| `deleting` | `verified_deleted` | Healthy independent readback confirms all owned files, handles and registered copies absent before deadline |
| Any | `unknown` | Failed/unavailable readback, missing arm, conflicting owner, unaccounted copy or interrupted cleanup |
| Any | `late` | Deadline reached without verified deletion, including eventual deletion after the deadline |

Neither `unknown` nor `late` permits a new capture or writer clearance. An
`armed` ledger entry must survive collector process and host loss; it must not
be deleted just because the collector reports completion. The verification
receipt cannot contain the deleted metadata. A stale lease may be retried but
must never authorize a delete of a new owner at a reused path.

## Runnable synthetic experiments

The following runs an in-memory **decision model**, with no network, provider
or filesystem access. It checks failure classifications, not actual
scheduling, host failure, permissions, vault durability or deletion:

```bash
python3 - <<'PY'
def assess(*, armed=True, t=0, deadline=24, identity=True, healthy=True,
           delete_response='ok', absent=True, copies_accounted=True):
    if not armed:
        return 'refused'
    if not identity or not healthy or not copies_accounted:
        return 'unknown'
    if t >= deadline:
        return 'late'
    if delete_response not in ('ok', 'lost') or not absent:
        return 'unknown'
    return 'verified_deleted'

cases = [
    ({}, 'verified_deleted'),
    ({'armed': False}, 'refused'),
    ({'identity': False}, 'unknown'),
    ({'healthy': False, 'absent': True}, 'unknown'),
    ({'copies_accounted': False}, 'unknown'),
    ({'delete_response': 'lost', 'absent': True}, 'verified_deleted'),
    ({'delete_response': 'lost', 'absent': False}, 'unknown'),
    ({'delete_response': 'denied'}, 'unknown'),
    ({'t': 24, 'absent': True}, 'late'),
]
for values, expected in cases:
    assert assess(**values) == expected, (values, expected)
print(f'{len(cases)} synthetic decision cases passed')
PY
```

This separate local experiment creates only synthesized bytes in a new private
temporary directory. It demonstrates why unlinking a file is not sufficient
evidence that all readers have released it. It does not establish cleanup of
real receipts, backups, memory, swap, or remote replicas:

```bash
python3 - <<'PY'
import os
import tempfile

with tempfile.TemporaryDirectory(prefix='holder-retention-synthetic-') as root:
    os.chmod(root, 0o700)
    assert (os.stat(root).st_mode & 0o777) == 0o700
    path = os.path.join(root, 'synthetic-receipt')
    fd = os.open(path, os.O_CREAT | os.O_EXCL | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        os.write(fd, b'synthesized-only')
        assert (os.fstat(fd).st_mode & 0o777) == 0o600
        os.unlink(path)
        assert not os.path.exists(path)
        os.lseek(fd, 0, os.SEEK_SET)
        assert os.read(fd, 64) == b'synthesized-only'
    finally:
        os.close(fd)
print('synthetic unlinked-open-file behavior confirmed')
PY
```

Once a real controller is implemented, its synthetic integration suite must
also kill the collector **after the durable job is armed and after a synthetic
file is written**, wait for a separately running worker to delete and verify
it, and prove an unrelated sentinel survives. Exercise worker restart, host
loss in a representative disposable environment, unreachable vault, wrong
identity, stale lease, denied delete, lost response, multiple receipt copies,
open descriptors, clock skew, due-time boundary and independent observer
failure. A model or a same-host process-kill alone is not host-loss proof.

## Observability

- **Signal:** independent-job admission, heartbeat, vault ownership conflict,
  due/deletion/verification states, deletion lag, and fixed error categories.
  Do not emit receipt contents or provider response bodies.
- **Owner:** named vault/controller owner operates deletion; an independent
  reviewer verifies evidence and the legal owner approves processing.
- **Failure modes:** unavailable vault/controller, failed admission, clock drift,
  unaccounted copies, stale identity, open handles, missed or late cleanup,
  and unreachable verification all block clearance and generate alerts.
- **Discoverability test command:** a future no-SSH authenticated status probe
  must read the durable ledger and heartbeat, including last successful
  verification and overdue count. No such command is asserted to exist here.
- **Retention:** delete every filtered receipt and accounted copy by the
  capture-based 24-hour deadline; retain only the minimized deletion receipt
  under an independently approved policy.

## Candidate identity, epoch and clock ruling — 2026-10-30

Ruled by CTO agent: investigate Cloudflare Worker mTLS binding to Google X.509
workload identity federation, then a dedicated worker service-account ID token
for private Cloud Run. Use an AWS-region DynamoDB strongly consistent epoch and
independently monitored EC2 time-sync probe as candidate external epoch and
clock substrates. These are gated candidates, not established controls. The
AWS substrates share a failure domain with one proposed worker; Google, vault
and network dependencies remain correlated. Dissent: none.

The providers separately document [Worker mTLS bindings](https://developers.cloudflare.com/workers/runtime-apis/bindings/mtls/),
[Google X.509 federation](https://docs.cloud.google.com/iam/docs/workload-identity-federation-with-x509-certificates),
[DynamoDB strongly consistent reads](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/HowItWorks.ReadConsistency.html)
and [EC2 time synchronization](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/configure-ec2-ntp.html).
These documents do not prove that the proposed combination works, that a clock
interval is bounded, that restored epoch state cannot roll back, or that
revocation fences an in-flight vault mutation. Independent technical review,
actual account configuration, cost and legal/transfer assessment remain open.

Independent public-documentation review found Cloudflare's binding requires an
uploaded certificate and private key; this candidate is not ambient or keyless
identity. Google's STS expects the corresponding leaf and chain in its request,
then an additional ID-token exchange for Cloud Run. The reviewed Google guide
did not establish CRL/OCSP behavior or immediate revocation. Certificate issuance,
key custody, rotation, existing token lifetime and the actual combined path
remain unverified and must be included in the disposable test and review.
Google documents that [service-account ID tokens are valid for one hour and
cannot be revoked](https://docs.cloud.google.com/docs/authentication/token-types).
Token expiry or certificate changes therefore cannot stand in for a current
authority and vault-side revocation fence.

Read-only source inspection on 2026-10-30 found that Wrangler's
[mTLS upload implementation](https://github.com/cloudflare/workers-sdk/blob/a2d1338708fa36881bb265d277a579e64fe59eb7/packages/wrangler/src/api/mtls-certificate.ts)
uses the account `mtls_certificates` API with the certificate chain, private
key and `ca: false`. The inspected [Terraform provider schema](https://github.com/cloudflare/terraform-provider-cloudflare/blob/9b51a582458f5c5d46d8547ed2604fcba91fb861/internal/services/mtls_certificate/schema.go)
exposes corresponding attributes; `private_key` is sensitive, not declared
write-only in that revision. This supports an API-level candidate, not a
tested binding. Terraform sensitive values may persist in state and plans;
state isolation, access, retention, failure copies and destruction require
review before provisioning. A separate root also needs apply serialization:
the existing R2 backend does not provide a state lock.

Before live use, separately authorized disposable infrastructure must prove
worker certificate issuance and exchange, Cloud Run subject propagation and
cross-role denial, direct Firestore-write denial, epoch races and restore
refusal, clock freshness and skew, vault-exclusive mutation and revocation
latency. Use synthetic data. The Firestore POST guard and all capture and
cleanup authorization remain disabled until the entire admission proof and
separate collection approval are satisfied. A real late or failed deletion
remains an incident; this candidate does not guarantee availability.
