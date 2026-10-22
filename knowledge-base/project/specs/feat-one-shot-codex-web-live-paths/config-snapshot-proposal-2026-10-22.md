---
title: Separate inert Mailpit Config snapshot proposal
date: 2026-10-22
pr: 9051
reviewed_source: 52c4fc8a03a5e7b0d05bd5848f9561cb15c880c8
status: source-contract-accepted-implementation-pending
---

# Decision and purpose

Ruled by CTO agent, 2026-10-22: implement a separately versioned, dormant
Mailpit Config-snapshot stage after acceptance of this retention contract.
Retain exact validated Config bytes privately for bounded inert field-value
inspection. Do not produce executable profiles or operational admission.
Dissent: registry integrity and inspection do not establish publisher provenance,
daemon configuration, safe execution or permitted hosted authentication.

This document is a proposal for source implementation and synthesized tests.
It creates no operational artifact and clears no execution gate. The operator's
standing approval covers remaining non-production engineering work; technical
source, actual-manifest, exact-command and separate evidence reviews still apply
without another routine permission prompt. Destructive shared-production acts
and genuine legal/provider requirements retain their own boundaries.

The preceding Config-only action has separately accepted integrity/schema
evidence. It deliberately discarded the bytes and cannot provide field values.
See [the existing acquisition contract](config-acquisition-proposal-2026-10-20.md#config-validation-and-non-admission)
and `scripts/codex-qualification/config_acquisition.py` › `ConfigAcquisition.collect()`.
Keep that non-retaining protocol, its source history and every old manifest,
marker and receipt unchanged. This proposal requires a new acquisition; it
does not reconstruct, replay or retroactively retain the consumed action.

The worst target-user failure would be fabricated profile clearance admitting
unreviewed commands or the wrong resources during recovery. Therefore this stage
has no profile admission, Docker write, payload execution or customer-data path.
No production database writes or WAL are introduced. UI design is inapplicable:
this is backend data handling and a local CLI, with no changed product UI.

# Fixed scope and reusable boundary

Only `docker.io/axllent/mailpit`, `linux/amd64`, is eligible. Bind the retained
864-byte platform manifest with SHA-256
`168f762c218e167ba88ae7e48194126eb5ba5e99ef652063e3f14f9c4f0ee70f`.
The sole payload descriptor is `application/vnd.oci.image.config.v1+json`,
2646 bytes, digest
`sha256:3f56e44ddc1a5655b8f288a2aa812db567b2f5f0b8bc18ef3da63b94a95608d5`.
Its layer count is three. No other descriptor, tag, image or platform is accepted.

Reuse the existing bounded HTTPS implementation, pinned CA, strict schema
validator and resolver containment. Preserve the exact three-GET order and
200/307/200 contract: anonymous token, fixed registry Config endpoint, fresh
in-memory Location at exact `production.cloudfront.docker.com:443`. Preserve
the existing origin/address/peer/TLS/framing predicates, token confinement,
60-second absolute action deadline, ten-second shrinking per-request limits,
90-second outer timeout and five-second kill grace. No retry, redirect expansion,
fallback address, HEAD, layer request, daemon contact, package install or execution
of acquired content is added. Recheck the previously accepted primary exact-host
evidence during actual-manifest review; changed evidence stops preparation.

Use a distinct dormant coordinator and output protocol. Shared transport or
validation refactoring must preserve the old coordinator's behavior and tests.
Do not enable retention by adding an ambient switch to its existing command.
Every new source/test dependency enters the operational census and manifest
closure before review. No signing/provenance property is inferred from a
self-hash, local UID or matching supplied JSON.

# Fresh manifest and private artifacts

Use schema `config-snapshot-manifest-v1` and a fresh attempt. Preparation remains
file-only: it exclusively creates a new owner-controlled `0700` directory and
`0600` manifest; no marker, payload, receipt, DNS or network operation occurs.
The manifest pins:

- Clean full source HEAD and complete executing dependency hashes, interpreter
  identity, source pairing, operational/input/retained-manifest/platform/schema
  references and CA bytes, with the existing attestation limitations.
- Exact request plan, descriptor, all budgets and expected output directory
  device/inode/UID; no URL capability is persisted.
- Fixed leaves `snapshot-manifest.json`, `snapshot-marker.json`,
  `config.bin`, `snapshot-receipt.json`, `snapshot-review.json`, optional `field-report.json` and
  `snapshot-cleanup-receipt.json` reserved for the later cleanup entry point.
  Unknown leaves cause refusal and prevent directory removal.
- Integer UTC `prepared_at` and `expires_at`, with
  `prepared_at < expires_at <= min(prepared_at + 259200, browser_contract_expiry)`.
  Thus retention is at most 72 hours and never outlives the bound qualification
  window. A trusted coordinator clock is an explicit assumption, not attested time.

All private artifact access walks absolute paths descriptor-relatively with
`O_NOFOLLOW`, verifies the bound owner and directory identity, and rejects
group/world permissions. Regular payload/report/receipt files require mode
`0600`, expected owner, link count one and a stable descriptor/name identity.
Opening an existing artifact for review is read-only. No payload is executable,
added to Git, printed, passed through argv/environment, sourced or uploaded.

The fresh mode-0700 action directory is exclusively controlled by this stage.
Every cooperating acquisition, inspection, recovery and cleanup entry point
obtains a nonblocking exclusive advisory lock on the pinned directory descriptor
before inspecting or modifying artifacts, retains it through final verification/
fsync, and refuses contention or unavailable locking. Independent review holds
the same lock while reading. No lock-file leaf is introduced.

Mode 0700 and advisory locking do not defend against an uncooperative same-UID
process, root, or modification of the executing program. Such concurrent mutation
is outside this protocol's threat model. Ownership/inode checks followed by
unlink are not an atomic conditional deletion. The protocol makes no guarantee
against substitution between those operations by an excluded writer. Within
the exclusivity assumption, detected substitutions and ambiguous ownership
refuse modification; tests must not claim resistance to the excluded race.

# Acquisition and joint publication

1. Check every local binding, expiry, output identity and unused directory before
   marker consumption. Require exactly the manifest leaf. Disable core dumps
   and use the existing replaced environment without account/provider secrets.
2. Exclusively write and durably close the new marker before the first request.
   Consumption is final on every later outcome, including interruption. The
   marker contains only the manifest canonical hash; it is never deleted as a
   means of retrying. Preserve all historical directories unchanged.
3. Acquire the same bounded payload as inert bytes in memory. Require exact
   framed count, untouched-byte digest and strict existing schema validation
   before creating `config.bin`. No invalid/partial network payload is retained.
4. Recheck output identity and bindings, then create `config.bin` with
   `O_CREAT|O_EXCL|O_NOFOLLOW`, mode `0600`, through the bound directory descriptor.
   Write all 2646 bytes with progress checks; fsync; verify owner/mode/link count,
   size and raw-byte digest through the descriptor; recheck the named inode;
   close and fsync the directory. Short write, close/fsync error, substitution or
   deadline/expiry failure prevents completion. Never overwrite an existing leaf.
5. Only after durable payload verification create the fixed sanitized receipt
   with `O_EXCL|O_NOFOLLOW`. Write, fsync, close, fsync the directory and recheck
   both receipt and payload identities/contents. The receipt is the publication
   commit record; two-file creation itself is not atomic. A payload without a
   valid complete receipt is an orphan, never accepted evidence.
6. Report success only after output, socket/helper and installed signal-handler
   cleanup is verified. The caller separately records the actual process exit
   and sanitized tool result. Receipt presence alone cannot establish successful
   execution or cleanup. A nonzero/unknown exit requires separate failure review.

Token, Location and request objects are discarded on every path. Memory handling
cannot promise physical zeroization or defeat privileged process inspection.
No derived data may extend raw payload retention by changing its filename.

# Closed receipt and evidence acceptance

`config-snapshot-receipt-v1` is a new closed schema, never accepted by the old
receipt checker. Reuse the old receipt's fixed status/peer/TLS/check fields and
binding hashes, adding only the following constant-shaped metadata:

- `schema = config-snapshot-receipt-v1`, `review = pending` and the fixed expected
  descriptor; request count/status/check requirements remain unchanged.
- Manifest-bound `prepared_at`, `expires_at`, and a source-bound observer kind
  `local-unattested`; an observation timestamp with the clock limitation explicit.
- `snapshot`, either null on failure or an exact object with fixed leaf
  `config.bin`, raw SHA-256, size 2646, device/inode/UID, mode `0600`, link count one
  and `durably_verified = true`. Values must match the verified private file.
- A canonical receipt self-hash, an integrity checksum rather than authentication.
- Authority fields `destination_ownership`, `publisher_verified`,
  `issuer_verified`, `profile_admitted`, `runtime_authorized`,
  `recovery_authorized`, `hosted_auth_cleared` and `qualified`, all constant false.

No Config keys, values, presence maps, extension counts, paths inside the Config,
observed wrong digest, URL/address/header, bearer or exception text enters this
receipt. Existing fixed acquisition failures remain; add fixed local failures
`expiry`, `payload_output`, `receipt_output` and `cleanup`. An invalid receipt
is never published intentionally. Unwritable/partial receipt output is reported
only by a fixed CLI outcome plus the marker/actual artifact census.

Separate evidence review must jointly verify: the reviewed manifest and exact
command; source/input/CA/platform/schema/output bindings; spent marker;
actual bounded execution exit; correct three request outcomes; complete receipt
self-hash and all false authority flags; and the **actual private payload** using
the descriptor-relative checks above. Require payload hash/size/identity to agree
with both descriptor and receipt, valid schema on those same bytes and an
unexpired retention window. Do not print its contents during that verification.
Record review in a separate sanitized artifact; never rewrite the receipt.

The fixed private `snapshot-review.json` has a closed
`config-snapshot-review-v1` schema. It contains only an
`accepted-for-inert-inspection` state; exact manifest/expanded-command/marker/
receipt hashes and payload descriptor/identity/digest; the original execution
exit code (required zero) and hash of the separately copied tool-result record;
engineering/security consistency verdicts (both required pass); prepared,
reviewed and expiry timestamps; `observer_kind = local-unattested`; the same
constant-false authority map; and its canonical self-hash. Its execution-record
hash must match a supplied bounded private closed tool-result record containing
the exact command hash, observed exit, fixed stdout/stderr hashes and tool-result
reference. Missing, unknown, nonzero, contradictory, mismatched or stale inputs
refuse inspection even when the receipt/payload pair is complete.

Only the coordinating agent writes this exclusive mode-0600 review input, after
observing the original result and obtaining both independent evidence passes;
acquisition never derives it from its own receipt. Validation proves supplied
local consistency, not authenticity of the tool result, reviewer identity or
independence. A forged self-consistent local input remains possible under the
unattested model and grants no profile or operational authority. The pure parser
may be tested on synthesized bytes without this gate; the artifact inspection
entry point requires the gate.

Independent reviewers may verify consistency, but must distinguish that from
witnessing the original execution. A receipt/payload pair fabricated from supplied
JSON is not a network observation. Acceptance establishes a bounded retained
Config observation only, with publisher and observer provenance still unverified.

# Failure, interruption and rollback

Before marker consumption, failures mean zero authorized requests and a fixed
preconsume stage. After consumption, failures mean a spent attempt; no retry or
automatic follow-on. Preserve the marker even if every other output is absent.

For ordinary failures after payload creation, close all owned descriptors and
attempt to remove only newly created payload/report/partial receipt leaves whose
recorded device/inode still match and whose link count is one, under the stated
exclusive-writer assumption. Detected replacements or foreign leaves are
preserved with refusal. Preserve any already valid complete receipt as
historical evidence; if removing its failed payload, record an incomplete pair
in separate failure review, never claim success. Fixed `cleanup` failure and
the observed remaining leaf census distinguish uncertain cleanup from absence.

Signal handling attempts the same bounded owned cleanup and reaps helpers before
reporting failure. SIGKILL/power loss can leave payloads or partial receipts;
this cannot be prevented by a finally block. The next invocation first performs
read-only recovery classification and refuses acquisition/reuse. A separate
bounded cleanup path removes positively identified owned artifacts; it never
resumes the action or clears its marker. Do not automatically accept an apparently
complete pair after an unknown process outcome.

Rollback covers local outputs only: no remote write was made by the GET action.
Ambiguous ownership, substituted path, hard link, unexpected leaf or failed
fsync/unlink causes refusal and a durable sanitized failure record where safely
writable. Preserve evidence for investigation; do not broaden deletion.

# Private field inspection and expiry cleanup

Acquisition and joint evidence review require the original fresh source, CA and
input checks. Subsequent inert inspection verifies the accepted historical
manifest/marker/receipt/payload bindings, unexpired retention and manifest-bound
inspector implementation; it does not require ambient CA or repository HEAD to
remain unchanged solely because an evidence/docs commit occurred. Verify the
historical committed closure and executing inspector bytes; a changed inspector
requires separate source and command review. No historical check permits a new
acquisition or profile use.

After joint acceptance, the inspection entry point obtains the directory lock,
reopens the exact payload read-only and revalidates its historical bindings,
review input, expiry and schema. A pure inspection function
then parses those supplied bytes under the same strict bounds, without I/O or
callbacks. The entry point records its complete decoded structure in private `field-report.json`,
preserving unknown fields as data and distinguishing absent versus present-null
versus observed typed values. The report binds its source payload digest and
manifest, uses the same expiry/owner/private-file rules, and has no executable
profile, callback, network, daemon or subprocess entry point. Bound its serialized
size to 32768 bytes; exceeding that limit refuses reporting, never truncates data.
Report digest/size and fixed review outcomes alone may enter committed evidence.

Review inherited execution/health/environment/user/directory/volume/port fields
as untrusted data. Missing fields stay missing. A successful inspection does
not supply the complete daemon Config required by `controller_inputs.py` ›
`profile_spec()` or `image_observations.py` › `ImageObservationCollector.collect()`.
Do not normalize an OCI Config into a guessed Docker inspect response or equate
its digest to a daemon image ID. Later executable profile review requires the
actual owned-store identity, complete inherited Config, independent exact
reobservation and separately reviewed effective create/host/exec recipes.

Provide a bounded `cleanup` entry point with manifest and expected artifact
identities. It deletes only verified owned `config.bin` and `field-report.json`,
fsyncs the directory, verifies their absence and writes a separate closed
`config-snapshot-cleanup-v1` receipt with binding hashes, fixed outcomes and no
payload values. Keep manifest, marker, acquisition receipt and sanitized reviews.
Use exclusive leaf `snapshot-cleanup-receipt.json`; an existing receipt is
read-only recovery evidence, never overwritten. Record any further recovery
attempt in a new separate private review directory, not an unlisted new leaf.
Unknown/substituted/hard-linked leaves cause refusal, never recursive removal.

Cleanup uses its own currently reviewed implementation and pinned historical
manifest/artifact identities. Expiry, ambient CA rotation or changed repository
HEAD alone must not prevent deletion of positively identified retained data.
Cleanup exceptions grant no acquisition, payload-use or profile authority.
Inspection has a five-second monotonic work budget; cleanup has ten seconds.
Each uses a 15-second outer timeout with five-second forced termination, bounded
regular-file reads and at most the fixed seven artifact leaves. Refuse an eighth
leaf without an unbounded directory census. Tests verify these numeric bounds.

The coordinator invokes cleanup once the retention purpose finishes, before
ending the workflow, or when expiry is reached, whichever comes first. Every
inspection/use checks expiry and refuses expired data. No detached timer or
unavailable scheduling capability is claimed: abrupt host/session loss may delay
physical cleanup until recovery; expiry guards then deny use and recovery owns
the cleanup. If cleanup cannot be verified, record that precise remaining
retention condition and stop further payload use. Secure erasure is not claimed.

# TDD and review sequence

Planned coordinator and test paths are
`scripts/codex-qualification/config_snapshot.py` and
`scripts/codex-qualification/test_config_snapshot.py`. Any shared collector seam
must be explicit, retain the existing command's non-retaining default, and be
reviewed with all existing acquisition regressions. It cannot be an environment
switch or a second generic downloader.

Write synthesized failing tests before implementation, covering:

- Byte-for-byte success and independent re-read; exact descriptor and schema;
  missing/null/value distinctions; unknown extensions retained inertly; no
  semantic normalization, executable profile or operational callbacks.
- Wrong length/digest/platform/schema; duplicate keys, invalid UTF-8, depth,
  invalid types and malformed numeric values; no invalid payload publication.
- New/old protocol separation; no old receipt/manifest acceptance; fresh-source
  dependency closure and changed-source/CA/platform/runtime refusal.
- Historical inert inspection after a docs commit with unchanged bound inspector;
  changed-inspector refusal; cleanup after expiry, source drift and CA rotation.
- Lock contention/unavailable locking and lock release after failure; substitution
  before final verification. No race against an excluded writer is claimed safe.
- Directory replacement, symlink at every component, hard links, wrong UID/mode,
  special files, unexpected leaves, pre-existing output and named-inode races.
- Partial/zero writes, ENOSPC, fsync/close failure, receipt failure after durable
  payload, output substitution, gate failure, helper/socket cleanup failure,
  handled interruption and a killed-worker orphan recovered without replay.
- Joint receipt/payload corruption, contradictory success, absent/partial output,
  unknown/nonzero execution result and expiry at each publication/review boundary.
- Otherwise valid complete pairs with absent, unknown/nonzero, contradictory,
  mismatched, stale or unaccepted separate review/tool-result inputs; valid gate
  control; no self-issued acceptance or claimed review provenance.
- Cleanup exact-identity refusal, successful absence verification, partial cleanup
  and restart classification; cleanup never removes a marker or foreign artifact.
- Secret canaries in all failure paths; no raw Config, query, token or exceptions
  in stdout, receipt or committed fixtures. Derived reports share expiry.
- All old acquisition regressions plus synthetic end-to-end new coordinator
  publication/inspection/cleanup. No actual DNS, Docker or provider operation.

Any test that mutates a signaling helper must automatically run its passing
control and mutant through the canonical bounded PID-namespace runner, including
default discovery; unsupported isolation is unverified, never host fallback.
Run focused tests, complete offline qualification suite, lint, secret scan and
independent engineering/security/test-design review on pushed frozen source.
Correct findings before preparing a fresh actual manifest and exact bounded
command. Review actual resulting evidence separately before private inspection.
No source test or proposal approval establishes real acquisition success.

## Observability

- Layer: bounded local CLI, private closed receipts and separate evidence review.
- Signal: source/binding hashes, fixed stage/failure, request/check results,
  payload identity/hash, execution outcome, retention expiry and cleanup result.
- Failure coverage: preconsume refusal, spent failure, orphan/partial outputs,
  unknown execution outcome and uncertain cleanup are distinct incomplete states.
- Owner: coordinating agent owns actual-command/evidence review and cleanup;
  independent reviewers own source and evidence consistency findings.
- `discoverability_test.command`: from `scripts/codex-qualification/`, run the
  planned `/usr/bin/python3.14 -E -B -W error -m unittest test_config_snapshot`.
  It must cover synthetic actual-coordinator success, publication fault,
  interrupted-worker recovery and exact-owned cleanup under bounded timeouts;
  exact commands/results must be recorded by the implementation review.

## Retained acceptance chain

The eleven operational roles, current-source owned image store/build, complete
filesystem and retained-state inventories, namespace/session/recovery execution
and authenticated local renderer/browser QA remain required. This Mailpit-only
stage supplies none of the other roles. Docker pull/import or payload execution
requires a fresh concrete containment proposal and technical review.

Preserve the full original feature and qualification scope. Both hosted App
Server authentication routes remain blocked and the alternative API-funded route
pending under [the October 21 CLO audit](../../../legal/audits/2026-10-21-codex-web-hosted-auth-recheck.md).
User consent cannot supply provider permission. Only `soleur:legal:clo` owns the
mode-specific legal disposition. No default-off shipping clearance is inferred.
Keep PR draft/disarmed, flags off and customer content blocked until the retained
technical, permitted Web/CLO, full review, QA, GDPR/preflight and shipping gates
actually pass. This proposal removes no original phase or acceptance criterion.

## Independent contract acceptance — 2026-10-22

Engineering, security and test-design accepted this corrected contract at
`ae4a0777d98bc6226b6eee1ea88fcc1646297e25`. The earlier Medium cleanup-guarantee
finding and unspecified joint-review gate are resolved by the explicit exclusive
directory threat model, advisory locking, historical binding lifecycle and closed
review/tool-result inputs above. No proposal findings remain. Ruled by CTO agent:
proceed with RED-first source implementation and synthesized tests. This design
acceptance supplies no implementation, actual-manifest, execution or evidence
clearance, and preserves every original qualification/legal phase.
