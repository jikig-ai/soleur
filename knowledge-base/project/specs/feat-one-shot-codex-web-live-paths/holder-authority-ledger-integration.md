# Holder authority and ledger integration — offline assessment

The current intent preparer cannot safely be wired to the existing Firestore
ledger as its authorization or replay boundary. Both accept asserted inputs,
neither establishes an authenticated authority, and the ledger's restricted
transport refuses every POST before credential acquisition. Keep that guard in
place. This assessment authorizes no provider access, storage, capture, cleanup,
or writer action.

## Concrete contract differences

- The prepared intent hashes a versioned JSON object including action,
  principal digest, predecessor and target revisions, clock decision, and the
  full operation base. The ledger computes a different `holder-ledger-intent-v1`
  hash over an array of base values plus command ID, states, target revision,
  time interval and late flag. A ledger receipt therefore cannot attest to the
  prepared intent or its principal/action. A matching command ID and edge is
  not enough to establish exact-intent replay.
- `create()` accepts only the base and creates an unarmed revision-zero record;
  it stores no prepare command ID or principal receipt. A lost creation response
  cannot be reconciled to a unique prepare intent by the present record.
- The ledger permits only `unarmed` to `armed`; its record validator recognizes
  four edges but has no `deleting` self-edge, `verified_deleted`, or `revoked`
  edge. The preparer describes those future actions, including repeated attempts.
  Its reachability check is only a proposed shape constraint, not evidence
  that the existing ledger supports those actions or that a state is current.
  The preparer now reserves its eighth proposed receipt slot against further
  repeated attempts. This does not settle whether one terminal slot suffices:
  revocation, later verification, incidents and an exhausted history may all
  need durable evidence. The ledger does not implement these future edges.
- The ledger obtains its own injected clock sample and arming readback; the
  preparer accepts an asserted interval and classifies it. A precomputed digest
  cannot replace an independently sourced fresh interval or the post-commit
  check, and a later sample changes exact intent. A retry needs the original
  immutable intent to distinguish replay from a different request.
- Both components accept caller-provided bindings; neither verifies identity,
  approved operation, isolated credentials, job readiness, vault ownership,
  revocation or rollback epoch. Unkeyed principal digests remain linkable and
  require privacy review. The existing POST refusal prevents the supplied
  transport from performing real commits, but an injected mock or separate raw
  credential is not constrained by that transport.

## Testable integration path

1. Define and independently review one versioned canonical intent and ledger
   receipt schema, including prepare identity and every authorization-relevant
   binding. Specify state, revision, receipt-cap, late and replay behavior for
   each command; explicitly resolve exhaustion, terminal and post-revocation
   evidence, and choose how existing version-one records are refused or migrated.
   Keep prepare creation at revision zero only if an atomic creation receipt
   can be represented without violating the chosen history invariant.
2. In a disposable mock only, persist the canonical intent or a verifiable
   exact-intent digest atomically with each conditional state update. Reconcile
   an ambiguous outcome only against the exact immutable receipt and generation;
   missing evidence is unknown because the original request can still commit.
   Never perform vault side effects inside a retryable database callback.
3. Exercise changed identity, action, clock, generation and base under a reused
   command ID; simultaneous contenders; lost responses and delayed commits;
   creation replay; stale restored state; malformed or full history; exact
   update-time preconditions; and unauthorized attempted transitions. Mutate
   away both the exact-intent check and the conditional precondition and show
   that their tests fail. Include a conformance test proving the bytes and digest
   passed to conditional persistence are exactly those independently prepared;
   the two current hashes differ, so equality cannot presently be claimed. These
   tests establish only the mock contract.
4. Integrate a separately authenticated authority and independent readiness,
   clock, epoch, revocation and vault checks; demonstrate credential isolation
   and denial of direct writes on a disposable real substrate. Review the whole
   identity, data, retention and transfer flow, and complete the specified
   security and CLO gates. Only then consider a separately reviewed transport
   change. No existing prototype test is proof of those controls.

## Candidate common receipt contract — not implemented

For a new closed schema version, use one canonical intent encoding and digest
implementation, shared by preparation and persistence. Store the exact
canonical intent bytes and their recomputed digest in each receipt; verify the
entire bounded history, state chain, base, and unique command IDs before any
conditional write. Store a separate prepare receipt atomically with the initial
unarmed revision-zero record, rather than pretending that creation incremented
the transition revision. The prepare receipt and subsequent transition receipts
share the command-ID uniqueness scope. The whole record must fit independently
reviewed byte and history bounds.

Create uses an absent-document precondition. A lost create or update response
is `unknown` unless a strong read finds the exact canonical receipt against the
bound operation and generation. A same-ID different-intent receipt is a conflict;
absence after a timeout is still `unknown` while the original may be in flight.
Repeat requests must reauthenticate the same principal and submit the original
immutable intent; a new current clock sample must independently gate any later
side effect. A receipt demonstrates a ledger transition only. Its clock interval
does not prove freshness and does not itself authorize a vault mutation.

Refuse version-one records at a version-two boundary unless a separately
reviewed conversion has exact source and rollback semantics. The existing
version-one code and tests retain their current behavior. The new contract must
specify what durable evidence survives receipt exhaustion and whether revocation
and later deletion verification each need their own record. The current one-slot
reservation cannot answer that; nor does it define the separate incident channel.
An append-only side record would need its own conditional-write and retention
proof, so no storage layout is selected here. The data flow and retention of
the principal digest and receipt history also require CLO review.

The offline conformance test `apps/web-platform/scripts/holder-authority-ledger-conformance.test.mjs`
demonstrates the present mismatch using the real preparer and version-one ledger
with an injected mock. It is a mismatch regression, not a shared-contract test.
The proposed version-two implementation remains blocked on the exhaustion,
post-revocation, independent-clock and privacy semantics above; implementing a
mock that invents those guarantees would not establish the real integration.

## Technical ruling — 2026-10-29

Ruled by CTO agent: use a separate atomic prepare receipt and eight bounded
transition receipts. Reserve three transition slots for revocation, a
separately authorized post-revocation cleanup attempt and independent
verification; after each of those actions retain the remaining reserved slots.
Ordinary operations must not consume them. This retains the evidence sequence
even when retries exhaust ordinary capacity. Revocation prevents new capture
authority but does not prove an outstanding lease stopped. Cleanup still
requires independently established capture stop, current authority, epoch and
ownership. A separate independently monitored durable incident channel must
report exhaustion or unavailable controls; delivery remains unknown without
readback. Dissent: none.

Reauthenticate a replay and compare the complete original canonical intent
byte-for-byte; return only the historical receipt. Every later side effect needs
a new independent clock and authority check. Missing receipt after a timeout is
unknown. Verification is timely only with healthy independent copy and handle
checks and a trusted upper time bound strictly before the deadline; later proof
is late. Refuse v1 records at the v2 boundary absent a separately reviewed
conversion. The incident, clock, epoch, provider identity and real substrate
remain unverified; their absence blocks activation. CLO owns processing,
retention and transfer clearance. This ruling authorizes no live action.
