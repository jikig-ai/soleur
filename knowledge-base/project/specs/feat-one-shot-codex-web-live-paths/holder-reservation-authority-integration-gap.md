# Reservation authority integration gap

Status: **blocked; no live authorization**. This records the specific integration
work needed by the selected [creation-reservation contract](holder-vault-deletion-recovery-contract.md)
and [authority ledger ruling](holder-authority-ledger-integration.md). It does not
approve a protocol, a provider write, collection, or deletion.

The local receipt store writes a durable pending marker, then calls injected
`reserve`, `bind` and `verify` functions with canonical bytes and expects exact
byte echoes. Those echoes are assertions: they do not authenticate a service,
establish an independent epoch or clock, prove a committed record, or fence an
in-flight operation. Its local marker refuses retries after an ambiguous reserve;
there is no implemented independent reconciliation path. The HTTP handler and
Firestore v2 adapter accept prepared lifecycle intents, but do not expose a
reservation command or authenticate the receipt store's callback peer. The
Firestore transport's POST hard-disable remains in force.

## Concrete schema mismatch

`prepareIntent` fixes its action set to lifecycle transitions and its closed
intent schema to operation, vault, owner, generation, manifest/controller hashes,
state/revision, command ID, principal digest and asserted time. It contains no
reservation nonce, authority epoch, fixed entry name, vault directory device and
inode, or receipt device and inode. Its existing conditional-store validator
regenerates that closed schema and rejects extra fields. Consequently, hashing a
reservation outside that intent and storing it in a callback does not make the
ledger receipt bind the actual inode. The v2 document also caps retained
transition receipts and reserves its final slots for revocation and cleanup;
blindly treating reserve/bind as lifecycle transitions would consume those slots
and violate the ruling.

Python's current pending marker uses sorted-key JSON and JSON numbers; the
JavaScript intent uses a different ordered serialization. Filesystem device and
inode values can exceed JavaScript's exact integer range. A shared cryptographic
binding therefore needs a versioned cross-runtime encoding with strict decimal
integer strings or another exact representation, closed fields, size bounds and
published byte-for-byte Python/JavaScript test vectors. An unkeyed digest is an
integrity identifier, not a signature or proof that an authorized service
committed it. The new schema must minimize metadata and receive GDPR/CLO review.

## Required protocol and integration decisions

1. Select and independently review a versioned, canonical reservation envelope
   for `reserve` and `bind`. It must bind an opaque command/reservation ID,
   operation, generation, epoch, fixed entry and nonce, vault and filesystem
   identity, immutable deadline and approved manifest/controller; `bind` must
   additionally bind the exact receipt device/inode to that same reservation.
   The authenticated caller and intended authority audience must be bound too.
   Use a stable command ID and exact canonical digest for replay; a changed
   intent under the same ID refuses.
2. Define where those two immutable receipts live. A separately versioned,
   bounded conditional record or revised ledger schema must preserve the
   existing lifecycle receipt and reserved-slot rules, retain both exact
   receipts and pin the operation/document identity. Specify atomic creation,
   revision preconditions, conflict behavior and full-history validation before
   connecting the existing transport. A success or timeout is not sufficient:
   reconcile against an exact independently authenticated strong read, and keep
   an absent receipt `unknown` while the original request may still commit.
3. Replace callback echoes with an authenticated authority client whose server
   independently verifies the caller, request binding and roles. Pin issuer,
   audience, key provenance/rotation and service identity; prove the direct
   Firestore write path is denied to the vault and collector. The existing
   Google verifier's injected JWKS and subject map are explicitly untrusted.
4. Specify independent epoch and time sources and the operation fence. The
   current epoch reader labels its input and result unverified, and the signed
   time primitive yields evidence only at a sampled instant. Neither proves
   independent operation, clock error, fresh non-rollback state or that a
   revocation/epoch advance cannot race a filesystem mutation. A read of an AWS
   epoch and a Firestore CAS are not one atomic transaction. The authority and
   vault need a reviewed in-flight fencing/lease protocol with measurable
   revocation latency and explicit outage/restore behavior; if it cannot fence
   mutation, refuse rather than treating a fresh read as a fence.
5. Define an authenticated recovery protocol for pending local markers, lost
   reserve/bind acknowledgements, an empty unbound entry and an already bound
   partial entry. Reuse neither the name nor inode alone after restart. A
   changed or restored generation, unresolved in-flight request, missing
   authority, changed entry or inability to account for readers and copies
   remains `unknown`. No automatic adoption or deletion follows from an echo.

## Evidence needed before enabling a real boundary

Synthetic tests must compare exact cross-language bytes and signatures; cover
all changed-field and changed-ID replays, concurrent reserve/bind CAS, receipt
slot exhaustion, malformed/truncated history, delayed commits, ambiguous reads,
unknown epoch/time, revocation and clock crossings. Interrupt every local and
remote durable step and confirm no byte is written before an exact bound
reservation is independently confirmed. Include integer overflow and inode
reuse tests. The selected substrate must then be separately authorized and
rehearsed for isolated identities, actual atomic persistence, role denial,
namespace exclusivity, host-loss restoration, independent epoch/time and
revocation latency. Synthetic success alone is not that evidence.

## Integration decision — strict admission and drain

The implementation must use a separate bounded reservation record, rather than
using lifecycle transition slots. The record is scoped to one operation and
generation and has exactly one immutable reserve receipt and at most one bind
receipt. An absent-document precondition creates the reservation; binding uses
an update-time precondition on that same record. Both receipts retain the exact
versioned canonical request bytes and their digest. A repeat is historical only
after authentication and an exact receipt comparison. A conflicting request,
unresolved write, unverified history or absent read after an ambiguous write is
`unknown`; it cannot authorize a new inode or a write. This is a local technical
decision, not an independent review or evidence that Firestore meets it.

Use one specified canonical encoding across the Python vault and JavaScript
authority. Encode filesystem identifiers and epochs as bounded canonical
decimal strings, reject leading zeroes except for zero itself, and pin the
encoding version, request purpose, caller identity and audience. Reserve binds
the operation, generation, nonce, fixed entry, vault identity, deadline and
approved source/controller identities; bind also includes the reserve digest
and exact receipt device and inode. Schema, numeric bounds, maximum encoded
length and byte-for-byte cross-language vectors must be reviewed before wiring
either implementation. An unkeyed digest identifies bytes; it does not
authenticate the caller or establish a durable authority decision.

Epoch reads on one service and conditional writes on another are not atomic.
Therefore a fresh epoch check alone is insufficient to revoke an in-flight
write. The activation protocol must serialize mutation admission with a
durable revocation barrier, prevent further admission before acknowledging
revocation, and establish that all admitted mutations have completed or have
been forcibly stopped before reporting the operation drained. A timeout or
unreachable vault leaves drain unknown. A process death is not proof that
other handles, copies or remote operations stopped. Before implementation can
claim this property it must specify and test the actual serialization point,
durable acknowledgment, bounded lease and clock assumptions, restart recovery,
and worst-case revocation latency on the selected substrate. Until then both
capture and cleanup stay refused; this decision grants no live authorization.

## Candidate executor barrier — preliminary technical assessment

The candidate serialization point is the sole vault mutation executor, not a
Firestore CAS paired with a separate epoch read. The authority first records a
generation-bound revocation as pending and refuses new capture capabilities.
The candidate queues a barrier and refuses later admission while it waits for
the exclusive mutation gate. An already admitted mutation holds that gate
through filesystem operations, completion sync and release of controlled
handles. Only after it releases the gate can the barrier acquire it and persist
the sealed generation. The queue's ordering, closure and crash behavior still
need an actual implementation and proof. Only an authenticated acknowledgment bound to operation,
generation, epoch and barrier command can support reporting a drain. Until
the acknowledgment and its prerequisites are established, the result is
`unknown`. A drained executor does not prove the safety or absence of prior
side effects, nor does it prove deletion.

The actual runtime must enforce sole-executor and namespace exclusivity; a
cooperative lock or a lease assertion does not establish either. A restart
starts closed and requires reconciliation against a non-rollback external
epoch and evidence that no previous instance or in-flight operation can still
mutate the namespace. If a filesystem operation can hang, no finite revocation
latency follows without a verified means to stop it and prove it stopped.
Writes can cross the deadline; a later clock check cannot undo their bytes.

An unwired ordered in-memory experiment exercises part of this candidate: it
assumes queue closure and allows one active mutation, refusing a modeled seal
until that mutation and its handles finish. Its input values and modeled seal
are assertions. It neither implements a shared
gate nor establishes durability, executor exclusivity, authenticated identity,
real time, restart reconciliation, deletion or any authority to capture. The
proposal and actual implementation still require independent review and
substrate-specific tests before any live boundary is enabled.

## Candidate durable reservation guard — review required before integration

The current injected adapter's unresolved latch is per process and cannot
coordinate another instance or survive restart. A candidate durable protocol
uses one deterministically named guard per operation, generation and purpose,
independent of caller-chosen command IDs. A pending guard retains the exact
canonical request, digest and attempt identity. The effect commit must
atomically change that exact guard from pending to committed and create or bind
the separately scoped reservation under its own precondition. A recovery fence
must change that same pending guard to a different state with a unique barrier
ID under the identical observed guard update-time precondition. The two writes
race: if the effect wins, reconcile its exact committed receipt; if a later
strong read confirms the state-changing fence won, the old effect cannot commit
under that same revision. A no-op or verify-only write is not a fence.

This reasoning depends on [Firestore's atomic ordered commit](https://docs.cloud.google.com/firestore/docs/reference/rest/v1/projects.databases.documents/commit)
and [conditional update](https://docs.cloud.google.com/firestore/docs/reference/rest/v1/Precondition)
semantics, an exclusive authorized writer, a stable guard identity and no
rollback. It does not prove any of those properties for this account. An
independent review found that an ambiguous initial guard creation cannot be
resolved by an absent read: the original create may still commit. Initial
guard provisioning, competing creation, lost claims, repeated commands and
restart must therefore have a separately reviewed protocol; no ordinary path
may delete, recreate, TTL-expire or silently reset the guard. A restored old
guard or reservation requires global quiescence and verified epoch/namespace
reconciliation before admission. An external epoch read alone cannot fence a
Firestore write already in flight.

The independent review also requires exact guard history and identity checks,
bind preconditions on the immutable reserve and reservation revision, and
proof that all authority instances use the guard in the same atomic commit.
An ambiguous fence, conflicting history, direct privileged writer, failed
readback or uncertain restoration remains `unknown`. A fence proves no vault
side effect and does not replace the vault admission/drain barrier. The current
adapter has no durable guard and must not be used as one.

An independent review of the unwired commit-body builder found a further
boundary: an update-time precondition pins a revision, not the caller-supplied
payload. Passing fabricated `ready` bytes alongside a `fenced` document's
actual revision can generate a structurally valid overwrite; a fabricated prior
reservation paired with the real revision has the same problem. The authority
must itself obtain authenticated, exact document-name/payload/revision
snapshots and bind its transition to those snapshots. The byte builder's
`prepared_unverified` result never supplies that authentication or permission
to execute a commit. Integration tests must exercise these substitutions.

### Bootstrap and delayed-claim refinement — conditional design review

A further candidate pre-establishes an immutable `ready` guard for each purpose
before any claim or reservation effect. Every claim changes `ready` to
`pending` using its exact update time. Recovery that sees `ready` first races
a real, terminal `ready`-to-`fenced` change against every delayed claim from
that revision. If fencing wins and an exact strong read confirms it, those
claims cannot subsequently commit; that purpose remains closed for the
generation. If a claim wins, a conflicting request stays refused while the
exact pending operation is resolved or fenced. An ambiguous response stays
unknown. There is no reset of a fenced guard within that generation.

The `ready` record is initialized and exactly read back before any claimant is
permitted to act. Absence after ambiguous initialization is not proof that its
creation failed; no claim may follow from that absence. A missing guard after a
claim could have been issued may signal restore or unauthorized deletion and
must not be recreated automatically. This candidate still depends on exclusive
write enforcement, atomic conditional operations, verified bootstrap provenance
and non-rollback recovery; it establishes no provider or vault guarantee.

Independent security review found that this race closes the delayed-claim gap
only when every claimant uses the one fixed guard and revision, its identity
and history are closed and authenticated, and revisions cannot roll back or be
reused. A losing recoverer must reconcile the winning exact state; a generic
fenced response is not its own receipt. Reserve and bind use separate guards,
so bind must additionally pin the exact committed reserve and reservation
revision in the same atomic effect. A new generation requires independently
verified lifecycle and epoch admission; a fence alone cannot authorize it.
