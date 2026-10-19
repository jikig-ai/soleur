---
title: Separate prebuild evidence acquisition from runtime qualification
date: 2026-10-16
pr: 9051
status: registry-metadata-implemented-focused-source-review-pending
---

# CTO ruling and scope

Ruled by CTO agent after the operator requested CTO consultation: acquisition
of actual image and executable provenance is agent-owned work. The operator
must not be asked to invent service profiles or supply a nonexistent current
renderer image. Separate prebuild evidence acquisition from the existing
complete eleven-role observation and profile gate.

At `bec74df32f1b318305a699a04292f3a77f831b02`, the exact-head candidate receipt
has `image_id=null` and `execute_authorized=false`. Retained October 11 build
and inspection records refer to source `2b826822c086d4348ada891e15fde2aa7b62eac3`;
they cannot qualify current source. The retained dependency manifest supplies
six repository/platform references, not observed local Docker identities.
Its byte hash is
`e48e6011aef57ddb47b0f575c6eb9ee86f0c73cf02a7544fef249fbff6b888f4`.
Its registry Config digests must never be substituted for observed local IDs.

## Source-only implementation

Add a dormant acquisition boundary with separate file-only `prepare` and
explicit `execute` modes. Preserve the existing eleven-role collector and
namespace Policy. Register synthetic tests and bind the new components in
the operational source census.

The finite acquisition manifest binds exact source/component bytes,
operational and pairing hashes, the six pinned dependency references, retained
manifest bytes, selected local executable hashes, explicit Unix endpoint,
endpoint filesystem identity, private output directory and a fixed replay
marker. Preparation opens no socket and invokes no Docker/buildx executable.

Execution requires a separately reviewed manifest and fresh approval of the
exact command through the harness. A manifest, digest, execute flag or marker
cannot establish human authorization. The exclusive, no-follow, mode-0600
marker is replay prevention only; consume and fsync it before the first socket
request and retain it on failure. No default execution, retry or fallback.

Acquire only `GET /version`, `GET /info`, and six exact percent-encoded
repository/platform image inspections. Bound the pass to 60 seconds and each
request to 10 seconds. A missing image or malformed/late response stops the
attempt and preserves only private partial evidence; it never triggers a pull.
No image/container enumeration, registry access, build, startup, SQL, provider,
browser, account, recovery, deployment or flag/cohort operation is included.

Project daemon metadata to version/identity/security/resource fields. Retain
complete image Configs only in private receipts; public output contains
hashes, counts and status. Check the requested platform reference against
returned RepoDigests and bind the independently returned immutable local Id.
Recheck the explicit endpoint filesystem identity around requests. These
checks do not authenticate the daemon administrator or establish ownership.
All execution/profile/authentication/ownership/quiescence authority stays
false and issuer verification/independent review stays pending.

## Acceptance and test scenarios

- Preparation performs filesystem/Git reads and exclusive private writes only;
  construction never contacts a transport or consumes a replay marker.
- The executed allowlist has exactly eight ordered bodyless GET requests;
  altered method/path/source/endpoint/digest/budget inputs refuse.
- Gate failure prevents every request; a successful gate is consumed before
  the first request, and success or failure cannot replay the same attempt.
- A single shrinking deadline bounds the pass and each request; timeout,
  malformed metadata, image mismatch, absent/non-dictionary/oversized Config or 404 stops without
  retry and without making later requests.
- Receipts retain projected daemon fields, exact source/reference/Config
  bindings and partial-failure state; all authority flags stay false.
- Symlinked/replaced output or manifest paths and persistently replaced
  endpoint paths fail closed. Synthetic tests exercise these boundaries
  without contacting a real daemon. Before/after endpoint fingerprints do
  not exclude replacement during a pathname connection followed by restore.
  The endpoint namespace must remain trusted; peer authentication and host
  administrator isolation remain unestablished. Local filesystem and Python
  processing have cooperative deadline checks rather than preemption.

## User impact and remaining gates

Worst target-user failure: false clearance for an unrelated image or resource
could lead to disclosure or modification outside the intended synthetic
fixture. Source consistency, self-reported daemon identity and filesystem
observations are not provenance authentication or runtime clearance.

After separately approved acquisition, review actual dependency Configs and
any absent payloads. Finish builder admission, dependency networking/resource
and context-writer isolation before requesting a separate current-source build
approval. Obtain the new renderer and remaining browser/TLS/resolver/migration
observations under separate exact actions, then close the complete eleven-role
profile gate before namespace creation or recovery.

Hosted authentication stays BLOCKED in both modes; an alternate API-funded
route stays PENDING. Build approval is consumed and the withdrawn October 11
command stays forbidden. Keep draft/disarmed/default-off/customer-blocked.
Recovery, authenticated screenshots, routine qualification, permitted Web/CLO
matrices, full review/QA/preflight and promotion remain pending.

## Observability

- Layer: local CLI status and private receipt files; no server-side sink.
- Signal: exact manifest/runner/source hashes, bounded request counts,
  completion/failure state and projected observation hashes.
- Failure: fixed sanitized diagnostics; partial private evidence and the
  retained replay marker distinguish failure from a never-started action.
- Owner: the coordinating agent reviews the receipt before any further action.
- Discoverability test: source-only synthetic acquisition tests, without SSH,
  daemon connections, provider calls or operational execution.

## Synthetic verification

The new test module first failed because `prebuild_acquisition` did not exist.
It now passes 18 cases, including the actual prepare/execute functions over
fake transports, persistent replay refusal across a forked process, copied
directory and mid-request path replacement, FIFO/symlink refusal, retained
byte binding, one shrinking deadline and contradictory daemon metadata.
The related operational/preparation/candidate tests pass 31 cases. Both runs
used `python3 -E -B -W error`; no real socket connection or acquisition ran.
Bash syntax and whitespace checks pass. The 18 acquisition cases also pass
under the explicit system Python 3.14 intended for the reviewed command.

Focused CTO and security review found the initial raw Config key requirement
rejected legitimate omitted optional keys. A synthesized omission case ran
RED before preserving and hashing the exact returned dictionary; absent,
non-dictionary and oversized Configs still refuse. No defaults or effective
profile admission are inferred. The security review also identified an
overstatement about endpoint replacement detection; the limitation above
now names the actual guarantee. Additional output-mode hardening ran RED
when a mode change allowed a second request, then GREEN after owner/mode/
identity rechecks around requests and before receipt creation. The CTO and
security reviewer independently reverified pushed
`663256a8947aec73065a7d3e09d2a2f21a835d73`: both findings are closed, with
no further concrete finding in that correction delta. They ran source reads
only. This evidence-record update changes no acquisition component bytes.
Actual file-only action preparation, review of its exact bindings, exact-head
refresh and fresh exact-command approval remain pending. This is not the full
PR panel or runtime clearance.

## Action freshness after main sync

The CTO independently reviewed the file-only manifest prepared at
`741ae4081ddc85f1d5e13c5ce3c5fc0d635daf9d`; its canonical digest was
`b0b6baec527c6717083fa4e61f6b36669f6bb72f61b5522e3177e9849657d207`.
No execution approval was requested or consumed, no marker exists and no
receipt was produced. This historical manifest must not be executed after
the October 18 source sync. Source-bound preparation and exact manifest
review must be refreshed before a new approval request. Acquisition components
are unchanged; this is an input/source freshness gate, not runtime clearance.

## Session corrections

### Consumed October 18 metadata attempt and diagnostic repair

The CTO reviewed a new manifest at source
`177b981cb6ee8e067c2db645e49a7d6f57c42fa0`, digest
`7a03a4ae685500e197d3cb1281d0c88335f345d6aefe95530901308e0dfea4eb`.
The operator approved the exact host-context timeout-wrapped command once.
That attempt consumed its fixed marker and stopped incomplete after three
requests were attempted. Its private receipt retains two daemon projections
and zero image Configs. Self checksum:
`459d2cf6a3641b134558b54628900ab4a8462191ee1b6b0e804d2c17460f86a3`;
file-byte digest:
`6cd5eae2d9edbf688f78e736b3aa5260b0bc29c039e30fbe37621f31c8c845f0`.
The receipt records no failure status/cause. It proves neither a 404 or absent
image nor a transport/validation mismatch. Do not rewrite it or infer a cause.
No retry or follow-on operation is authorized by the consumed approval.

Ruled by CTO agent: repair the observation gap inline before proposing any
later live action. In incomplete collector receipts add only fixed failure
phase/reason enums, a one-based approved action index, approved request-path
and selected-reference hashes, and an observed strict HTTP status or null.
Capture a returned status immediately after transport returns, before late
response/binding checks; it grants no response admission. An exception inside
transport has null status. Failures before action selection have null action/
reference fields; later binding failures identify the prospective action even
when no request was sent. Recompute the receipt checksum including diagnostic
fields. Preserve
the fixed CLI error and existing one-use/failure semantics.

Synthetic regressions must distinguish transport failure, malformed receipt,
returned 404, repository membership/platform/Config failures and a late 200
whose status is retained. Test gate order, no later request, no replay and
absence of sensitive sentinels. Retain no raw error body, response keys or
values, exception text or failed Config/Env. Keep output owner/mode/identity
checks around requests and before receipt creation. Revalidate source and
obtain focused review before preparing a new attempt and fresh exact approval.
The previous consumed manifest remains immutable and unavailable for retry.

The diagnostic tests first ran RED with four missing-failure-object errors.
They now pass 28 cases under explicit system Python 3.14, also with `-W error`.
The suite discriminates transport, malformed receipt, strict status/404,
identity/repository/platform/Config, gate and late/binding failures, checks the
receipt checksum and rejects sensitive sentinels. A late Config-processing
and role-projection schedule proves failed Configs are not retained. Large
projections are staged before final deadline/source/endpoint/output checks,
then published by small assignment. The CLI passes its output-binding check
explicitly into the collector so returned status is captured first; its
private write and pre/post owner/mode/identity checks remain enforced.
Focused CTO and security review of pushed
`6c9489d37ee7101df8133700bc5245ec46c4ef88` found no code blocker or
actionable security finding in the diagnostic implementation. Their shared
documentation correction distinguishes a selected action from a sent request
and is applied above. This record update changes no acquisition component.
A new source-bound file-only manifest, independent binding review and fresh
exact-action approval remain required. No live request was repeated to
develop or verify this source repair. This is not full PR/runtime/legal or
shipping clearance.

### Reviewed second metadata attempt: HTTP 404

Canonical sync resolved BEHIND at
`ff1e7aa9ee6f28f3df785763423d354d95059a86`, including main
`840dc667fce537b8e99a8d96047a7ceaa2fdfb95`. Acquisition components remain
identical to the focused reviewed diagnostic implementation. Runtime/plugin
inputs changed, so file-only preparation and export were refreshed: 5,155
inputs, 191 migrations, 53 components, 1,770 vendored inputs and 6,927 source
leaves plus three metadata leaves. Preview and export receipts match.
Pairing: `a41d550612fdc5c338d8b567f5d80d4d2e049a4e2c70f5fee31137ca7555dff9`;
operational: `116fc68441dd26f086b6bb71fde982e8ce45bc72950c7ddfa8f590406eb4b6ec`.

File-only v3 preparation refused changed local executable bytes before
creating an output directory. Fresh filesystem reads and independent CTO
verification rebound those bytes in v4; neither executable was invoked.
This binds current filesystem identity, not provenance or builder admission.
The CTO independently verified the actual v4 manifest, exact eight bodyless
GETs, source/retained/output bindings and unused marker/receipt. Manifest:
`daf5143a1e6ec02c5b93f3a9890d60f12e48a24190b1c23c440e4b4fc91788fe`;
runner: `d9c795968e949c1a24d450fc2335d08c6791f407589218d7e6750e55a19daadf`.

The operator freshly approved that exact host-context timeout-wrapped action.
It ran once and stopped incomplete after three requests, retaining two daemon
projections and zero image Configs. Its private mode-0600 receipt records
action 3, `response_validation`, `http_status`, status **404** for the approved
pinned Mailpit request. Request-path hash:
`b6f5efb2b149ef7b7164da5a6364d4a54145582a9cfb92d4a85050a4ce376167`;
reference hash:
`3b7d76f278ac28fc51e89cae5e1d0a02f967b2926e7bdc63a8a0b90f41e1be16`.
No failed response body or Config was retained. Receipt checksum:
`e0ff00ee3005bca0f26ff168305e55c10a6c1773e85b0b664927cc9d03dddb30`;
file-byte digest:
`702e937112281ba57651c2d4e3953b4105e2f638f7145fe35023dbe02c1e82e9`.
Checksum verified; marker spent; all authority remains false/pending. The
first attempt's receipt bytes remain unchanged and its cause remains unknown.

HTTP 404 alone does not distinguish absence from reference-resolution
ambiguity. CTO ruled that a separate Mailpit-only diagnostic must precede any
pull proposal; do not repeat the full six-image acquisition.
No retry, pull, build, startup, SQL, provider, browser/account, recovery or
follow-on operation is authorized. Preserve both consumed manifests and
receipts. All profile/runtime/legal/review/QA/preflight/promotion holds persist.

### Separate reference-resolution diagnostic

The dormant diagnostic must bind the same source/retained/component/file/
endpoint/private-output identities and require a separate fresh exact-action
approval. Enumerate exactly five bodyless GETs: version, info, the retained
Mailpit repository/platform reference with `docker.io/` removed, the retained
platform digest as a candidate, and the retained registry Config digest as a
candidate. Derive candidates from original retained bytes; digest-only
addresses are never asserted to be observed local image IDs. Do not query
tags, enumerate images, consult registry/account configuration or pull.

Read all pre-enumerated candidates even after a valid 200. A candidate 404
records its fixed status and advances only to the next approved candidate;
daemon metadata 404 or any other transport/binding/deadline/validation failure
terminates. Capture returned status before post-request checks. Keep successful
bounded raw Configs private, stage projections before final checks, publish no
failed Config and preserve fixed sanitized reasons without exception/error
bodies. The exclusive private replay marker remains spent on failure.
Collector budget stays 60 seconds overall and at most 10 per request.
Clean HEAD and executing component/retained/file bytes are checked before
execution. Per-request checks revalidate the in-memory manifest and endpoint/
output identities; they do not continuously monitor source files on disk.
Every authority remains false/pending; successful alternative lookups require
independent identity/reference review and cannot admit an image/profile.
All-404 outcome means only “none of the approved immutable lookup forms
resolved”; it does not prove layers absent. Existing acquisition behavior
remains unchanged. Synthetic RED/GREEN, focused independent source review,
new source-bound manifest review and fresh approval remain required.

The separate diagnostic first ran RED because its source module was absent,
then passed eight synthetic test methods, including real temporary filesystem
prepare/execute calls over a fake transport, persistent replay across a fork,
status preservation on late/binding failure, Config exclusion, retained/tool
byte refusal and private directory/receipt checks. No real diagnostic prepare
or execution ran. The new module binds its executing bytes and all reused
prebuild dependencies. Valid 200s may lack RepoDigests; absent/null/list states
are distinct, exact matches are observations, and membership verification is
pending for every candidate. All five requests remain pre-enumerated even
after a successful candidate response.

### Main's new lint gate and explicit cleanup outcomes

The newly merged shrink-only Ruff gate identified 18 findings in earlier
feature files, plus two findings in the new diagnostic. No baseline or waiver
was changed. Unused imports were removed; the candidate test now imports
Refused from its defining preparation module. Existing directory collisions
receive descriptor-relative no-follow directory checks before the existing
no-follow open. Adapter failure recording is separated from raising so
quiescence release still runs with the original primary failure. Race
snapshots verify that caught refusals recorded terminal failure. Failed
partial-receipt writes raise the same fixed sanitized refusal and retain
the spent marker.

Manifest cleanup consumes descriptors before each close, records fixed
cleanup outcomes, attempts remaining cleanup, and unlinks only its created
inode. A final parent-close failure after an otherwise successful write now
refuses rather than returning a success digest. A synthesized regression ran
RED before this correction. Proxy half-close accepts only established
ENOTCONN peer disconnection; unexpected errors receive a fixed refusal.
The EBADF discriminator likewise ran RED before correction. No exception
text is logged. Test peers record expected disconnection/TLS refusal apart
from unexpected errors; descriptor cleanup verifies EBADF explicitly.

The focused diagnostic/acquisition/operational/preparation/candidate/image/
adapter/session set passes 164 tests under system Python 3.14 with warnings
as errors. The upgraded-input/half-close suite passes three tests. Its initial
sandboxed run failed socket setup with EPERM; the exact approved host-context
rerun used temporary synthetic Unix peers only and passed. This is not a live
Docker operation or runtime qualification. Focused source review and fresh
source/action bindings are required after these cleanup component changes.
The separately affected controller-input, synthetic transport, TLS and proxy
barrier suites pass 57 additional unit tests; the ownership script passes
51 checks with zero Docker calls. Initial unittest discovery on that script
found zero tests and exited 5; its direct registered script invocation supplied
the actual result. Transport/TLS sandbox setup also required exact synthetic
peer approvals before successful host-context runs. No setup refusal or
empty discovery is counted as a test verdict.

### Reviewed diagnostic consumed; registry metadata boundary

Focused CTO and security review of pushed
`3f2b5979eb277ff7433b76f7b9cb13d6e56c0ce1` found no remaining blocker or
actionable security finding in the diagnostic/cleanup delta. Whole-tree Ruff
passes with 62 existing baseline findings and 110 files scanned; staged secret
and whitespace checks pass. The positive proxy script also passes seven
transport checks with zero Docker calls. These are focused source/fixture
results, not full PR, SAST, runtime, legal or shipping clearance.

File-only preview/export at that source match: 5,155 production/plugin inputs,
191 migrations, 55 components, 1,770 vendored inputs and 6,927 source leaves
plus three metadata leaves. Pairing:
`d99f7abf6efe6ad5954f36a9e7ff4fa3758ed09fdda59c39e07813fd79eb6199`;
operational:
`1337fb9492cb5b1b4a8ef9e09f4120d45d7678f43b14c7ffd690383f96d3a1f4`.
The CTO independently verified actual file-only diagnostic manifest
`157090b6fd705e99db260a47f049cc7b6b99c6ef8ed8df826c6b05323c1dae0a`,
runner `ada64abc37b4f0c4784bf356eef3e822988e7ae49693b7a99c21a2463a8ecef0`,
exact five GETs, retained candidates, host endpoint/private outputs and unused
marker/receipt. The operator freshly approved the exact timeout-wrapped action.

It executed once and completed statuses **200, 200, 404, 404, 404**. All three
approved immutable Mailpit lookup forms failed to resolve; no Config was
observed. This does not prove layer absence or shared-host ownership.
Private receipt checksum:
`9eb1b3e3df86f773291171002b48de52ada756efb7d22bc0d66cbe6d4ef4617f`;
file-byte digest:
`8800e359d9a343a40956b4bb901d44167c2b9d29235c82d0d5d00f04c1d03bf1`.
The checksum verifies, receipt is mode 0600, marker spent, and both earlier
receipt bytes unchanged. All authority remains false/pending. No follow-on
operation is authorized by this completed diagnostic.

Ruled by CTO agent: next prepare a Mailpit-only credential-free registry
metadata acquisition into a fresh private task directory, without a shared
Docker mutation. Exact proactive sequence: anonymous token GET for service
`registry.docker.io`, scope `repository:axllent/mailpit:pull`, at
`https://auth.docker.io/token`; then the retained platform manifest and Config
blob at `https://registry-1.docker.io/v2/axllent/mailpit/` digest routes.
Fixed initial URLs and headers belong in the reviewed source-bound manifest.
Only the exact registry host receives bearer authorization. Token aliases
must agree if both present; token material stays in memory and never appears
in output, errors, receipts or persisted request headers.

Pin the selected CA-bundle bytes, verify TLS hostname/chain, request identity
encoding and accept only fixed manifest/Config media types. This is a CA-bundle
hash binding, not a server-certificate or publisher pin. Disable redirects,
challenge processing, alternate hosts and retries. Any 401/3xx stops before
contacting its Location; a Config redirect may leave only a verified manifest.
Consume an exclusive private marker before token acquisition, retain it on
failure, and bound token/manifest/Config streams to 16 KiB/1 MiB/1 MiB under
one 60-second collector budget with at most 10 seconds requested per request.
Unpreempted DNS/Python/filesystem stages remain cooperative; require a separate
90-second outer timeout with five-second kill grace.

Hash raw manifest bytes before interpreting descriptors. Require the exact
retained Config digest
`sha256:3f56e44ddc1a5655b8f288a2aa812db567b2f5f0b8bc18ef3da63b94a95608d5`,
permitted descriptor media type and bounded size, then verify raw Config bytes
and linux/amd64 platform. Retain complete successful bytes privately and layer
descriptors/sizes as data only. No layer fetch, unpack, execution, shared cache
or image import is included. Content-addressed consistency establishes neither
publisher authenticity nor observed local Docker IDs, admission or ownership.
After actual metadata review, document an owned image-store/import boundary
before any separately approved layer acquisition or import proposal. Source
implementation, synthetic verification, independent source/actual-manifest
review and fresh exact-action approval are still required. No registry request
has been made during this preparation; all build/runtime/legal/ship holds persist.

The dormant registry module and tests are implemented. The initial test run
failed for the absent module; ten methods now pass under system Python 3.14
with warnings as errors. Cases use synthesized bytes, fake HTTPS/SSL adapters
and temporary files only. They distinguish token aliases and mismatches,
401/307 stopping without body/Location retention, exact digest-before-parse
ordering, strict Config descriptor/media/size/platform, duplicate JSON,
bounded streams and encoding refusal, late/binding failure, staged publication
cleanup, private modes, CA-byte refusal before the marker, persistent replay
across a fork and output replacement. The actual HTTPS adapter constructor
loads only supplied verified PEM bytes and opens no connection. The tests
create no real registry action and use no account credentials or network.
Two-file Ruff passes. Registration includes both new components and tests;
combined verification passes 77 tests across registry/reference/acquisition,
operational, preparation and candidate modules. Canonical whole-tree Ruff
passes with 62 existing baseline findings and 112 files scanned; staged secret,
Bash syntax and whitespace checks pass. Focused source review and all actual
action/approval gates remain pending.

Focused security review of pushed
`66320332529dbd63ef4e6f6a4b5031787c214157` identified a publication rollback
gap: the sink could finish, then the collector's final deadline/binding check
could reject the current metadata while its final private file remained.
Retain exact created-inode rollback ownership through the collector's final
acceptance. On rejection remove only the current owned artifact, preserve
foreign replacements and earlier accepted platform metadata, and report any
cleanup failure with a fixed reason. Discriminating tempfile schedules and
pushed correction/review are required before preparing any actual action.
No other actionable HTTPS/TLS/token/digest finding was identified in that
focused pass. File-only contract/preview preparation at `6632033252` is
historical after the correction; no action manifest or registry request exists.

The correction retains a publisher rollback callback bound to the pinned
output descriptor, fixed created names and exact inode through final collector
checks and metadata acceptance. Rejection rolls back only that current owned
artifact and removes its projection; earlier accepted platform metadata and
foreign replacement files remain. Cleanup failure uses a fixed sanitized
reason. On October 19, the parent verified all 11 registry test methods pass
and ran the new tempfile discriminator against the previous committed source:
six rejection schedules fail on the old source, while corrected tests pass.
The implementation agent hit its usage limit before handoff; the parent read
its diff and verified the actual bytes rather than treating that notification
as completion. Pushed correction and focused independent recheck remain pending.

The synthetic browser fixture expired October 19 at 00:00 UTC. Current-source
operational/export preparation therefore needs a reviewed source-only refresh;
no expiry bypass, fixture renewal, registry action preparation or live retry
has run. CTO technical disposition is pending. All exact-action holds persist.

CTO ruled a source-only renewal through the existing binding chain: attempt
`codex9051-oct19-local-auth-preparation-v1`, issued October 19 at 00:00 UTC,
expires October 26 at 00:00 UTC. The deterministic algorithm derives fresh
synthetic hostname/signing material/token; no hosted credential or account
operation is involved. Do not add a separate registry-only identity path or
bypass expiry. Valid synthetic observation clocks move inside that window;
negative tests derive the exact expiry boundary and its following second
rather than assuming a fixed calendar date remains expired. The first run
with the new valid observation clock correctly refused the expired old
fixture. That setup failure exposed implicit temporary-directory cleanup;
cleanup is now registered before contract preparation so refusal also cleans
the fixture. Fresh source bindings and independent review remain required.
Combined affected verification passes 78 methods; the latest focused rerun
passes 12 registry and 13 operational methods after adding cleanup-failure
coverage. If owned removal itself fails, the receipt excludes Config, retains
prior accepted platform evidence and reports fixed `publication_cleanup`;
the surviving private file is not admitted. Exact expiry-minus-one acceptance
and expiry/expiry-plus-one refusal pass. Ruff remains clean against the
existing 62-finding baseline, with 112 files scanned. No network action ran.

Canonical sync pushed `213826863942ca1cf5c194010b3c282d4695e65b`, including
main `65c0ad6fb9f38e01edbe4ff20d5e4615d12ef602`, and resolved BEHIND.
Qualification components, Dockerfile and migrations were unchanged by main;
runtime sandbox sources changed and require fresh production input bindings.
Both reviewers accepted the fixture refresh. Security closed the original
P1 publication timing gap but identified P2: device/inode numbers alone do not
prevent reuse after an unlinked created file is closed. The correction now
holds the created regular-file descriptor until final acceptance or rollback.
Both paths consume and close it exactly once; rollback compares names while
the inode is pinned. A deterministic test first failed with EBADF on both
paths, then all 13 registry methods passed. It checks the descriptor remains
open after unlink, a replacement cannot reuse that inode, foreign bytes
survive rollback, and acceptance/rollback each close once. A failed release
never retries its descriptor close or deletes a potentially reused inode.
Focused pushed recheck remains required. Current main's Ruff baseline has
44 existing findings; the 113-file scan passes without a baseline edit here.
No actual registry manifest, network request or authorization exists.

The initial evidence search used the retired rollout directory rather than
the live-paths directory. Discover current filenames before following older
slugs. GitHub CLI subprocesses in this worktree encountered a sandboxed mise
installation refusal; the canonical read-only checks succeeded under exact
tool approval. Check every producer exit and retain failed probes as errors,
never as a CI or qualification verdict.
An additional helper lookup guessed a filename; the canonical monitor's
actual helper reference identified the read-only attribution script. Follow
the resolved reference rather than deriving a helper name from its purpose.
A multi-file evidence patch used the wrong tasks path and was rejected
atomically; verified clean status before correcting the full path. Keep the
entire discovered feature-spec prefix when constructing patch targets.
Staging then hit a sandbox index-lock refusal; a trailing read hid its exit
status and the subsequent commit correctly refused unstaged files. Run each
Git mutation separately, inspect its status immediately, and use the required
filesystem approval for index writes before continuing.
This continuation guessed a CI job ID and received 404; discovery through
the current check URL supplied the actual ID. Raw-log output then required
the CLI's advertised escape-sequence flag; an unsupported output flag was
rejected before the successful sanitized read. Discover exact IDs and inspect
supported CLI flags before constructing log commands. The executed aggregate
log confirms DRAFT_LIGHT and its intentional full-battery-owed failure.
A source search guessed `test_prepare.py`, which does not exist; scoped file
discovery identified `test_preparation.py`. Use discovered test filenames.

### Registry setup refusal and CA projection correction — 2026-10-19

CTO and security independently closed the P1/P2 publication findings at
`8ff7ad82c2db45c14255d20edb4c3d77f5006bc4`. The CTO reviewed the actual
registry manifest `42d1b2dbba51d0daaf6ab4f7873f1d3646278bf9e1b6a1cb047f01013b4d99a7`,
and the exact bounded command received fresh approval and ran once. It
returned the fixed incomplete refusal during setup. Its marker, receipt,
platform manifest and Config files remain absent; do not manufacture an
action receipt or reuse that approval. The runner digest was
`59590c5331e1d45f8cce05d8776e0537f9106ba4afc609f1f55f979f7b832950`.

A separate file-only diagnostic reproduced `UnicodeDecodeError` at the
constructor's whole-bundle ASCII decode. The bound 185,311-byte public CA
bundle has 121 certificate blocks and eight non-ASCII bytes in a UTF-8
comment, with no non-ASCII certificate content. Source/dependency/manifest/
output checks passed before TLS construction; no request method, marker or
collector ran in this setup path. Its raw CA hash remains
`8c97794a899a32666593979dc7adfaec8bda2b420eb092ff0d987e44ad0bf6ea`.

Ruled by CTO agent: preserve the entire raw-byte hash and project every
certificate block in order, including duplicates. Outside blocks accept only
ASCII blank lines and valid UTF-8 `#` comments; reject other payload, malformed
or nested delimiters and non-ASCII certificate content. The explicit TLS
context loads only this ASCII PEM projection and still delegates certificate
encoding validation to SSL. No CAfile copy, ambient trust or trust-policy
change is introduced. The new synthetic discriminator first failed with
six failures and four errors on the original source. The corrected registry
suite passes all 14 methods, covering LF/CRLF, ordered duplicates, malformed
input, full raw-hash binding and absence of default-trust/connection calls.
A separate local construction check loads all 121 original certificates,
preserves every block and opens zero connections. Canonical Ruff passes with
44 baseline findings and 113 scanned files. Pushed focused review and new
source/export/action bindings are still required before fresh exact-action
approval. All operational and shipping holds persist.

The settled `8ff7ad82c2` CI additionally reports an `e2e` failure: 51 cases
failed after localhost:3100 refused connections; 48 passed and one skipped.
The root cause is not yet established, and it is not classified as intentional
or pre-existing. The separate aggregate `test` draft gate remains expected.
No workflow rerun or local browser/build was authorized. Read the existing
job log and inspect source; keep the failure open until attributed.
Log retrieval initially emitted a truncated result; capture large logs to a
private local file and print bounded matching excerpts. A guessed ratchet
shell filename failed; scoped discovery found `scripts/lint-ratchet.py`.
The log CLI required its advertised escape-sequence option, and sandboxed
mise refused a later invocation; the exact approved read-only retrieval
succeeded. A dependent search against the failed producer's empty file had
no evidentiary value. Inspect each producer status before reading its output.

### Registry transport refusal and framed-response correction — 2026-10-19

Canonical sync pushed `9d24f8f256a92075ab0917de6738d1676535fd34`, including
main `310eab957ff57a475e4a5a979f42af87b664edcc` (community digest only).
CTO and security cleared the CA correction. Exact-head file-only preview and
export match: 5,163 inputs, 191 migrations, 57 components, 1,773 vendored
inputs and 6,938 source leaves plus three metadata leaves. Pairing is
`6f6d5907b9cb80f8694b70dd29b5d76de241137ef57833df82c46d29d555d572`;
operational hash is
`eed995f99d777262a8654859ef7fa0466a0689713a027e5465ccbb5cad941e1e`.
Image ID remains null, authority false and exporter operation counts zero.
CTO independently reviewed replacement manifest
`f57a8892b64a512b7b4ad59d9c13d74c66c63ba1a08252c28aac3d7cf7eba92c`,
runner `d546eda51e1081538984d5dcf0a63ce08ffb0e5553a71a21a491fee948464336`,
all source/helper/CA/retained/private-output bindings and three fixed routes.
Separate file-only preflight passed and loaded 121 CAs without connections.

The exact command was freshly approved and executed once. It stopped
incomplete after two requests: anonymous token observed HTTP 200; platform
request observed HTTP 200 then transport `unexpected_failure`; Config was
not attempted. No platform or Config bytes were accepted or retained. Marker
is spent. Receipt checksum is
`49bedd650a8ddda6fff8484f844a780f9c99425d1e8dc0733fe7e4dcb0a801d0`;
receipt file SHA-256 is
`d3cdbd7fb5bcd1bc7f42635b168aa1426fa7e121ca93d84846227d6c43e2df19`.
Both verify; every admission/ownership/authentication field stays false or
pending. Keep this receipt unchanged. No exception text or failed body was
retained, so the actual transport cause remains unknown. No retry follows.

CTO and security independently identified a concrete source defect from local
Python 3.14 implementation: `HTTPResponse.read1()` closes its file when the
remaining Content-Length reaches zero, while returning final nonempty bytes.
For `Connection: close`, `HTTPConnection.getresponse()` has already released
the connection's socket ownership. The next adapter iteration can therefore
call `settimeout()` on a released socket. This is consistent with the receipt
but does not prove that attempt's cause.

Ruled by CTO agent: once a validated Content-Length's exact count is reached,
stop before another socket access. Keep post-read deadline checks, bounds and
final exact-length validation; chunked/close-delimited bodies remain EOF-driven.
An in-memory fake socket/file with actual stdlib HTTPResponse parsing first
reproduced `unexpected_failure` on a valid fragmented closing response. The
minimal loop correction passes all 15 registry methods, including seven
framing schedules: fragmented complete length, zero length, truncation,
chunked, close-delimited, oversize and late response. Cleanup runs once and
negative cases preserve sanitized reason/status. No real socket, TLS request,
Docker or runtime operation is used by this regression. Ruff passes with
44 baseline findings/113 files. Pushed focused review and new source/action
bindings remain required before fresh approval.

The earlier E2E artifact (12174025076, exact `8ff7ad82`) was downloaded for
bounded JSON trace inspection only. The first failed case's retry has four
refused network resources/status -1 and no console or process explanation.
No browser or images were opened. CTO rules listener loss with unattributed
cause. Live check found historical Ref #8785 CLOSED, describing a different
font-resolution failure; do not substitute it as current tracking. E2E passes
on `9d24f8f256`'s automatic CI, which settles at 83 passes/14 skips and only
aggregate `test` red. The exact run's executed log confirms DRAFT_LIGHT and
`draft: full battery owed at ready`. Infra/tenant and description guards pass.
No workflow rerun occurred. Full runtime/legal/review/QA/ship gates stay held.
Sandbox process-name checks returned no matching process and add no evidence
about the independently managed export session; its own completed result and
verified files establish successful file-only preparation. Artifact retrieval
also needed exact read-only approval after a sandbox mise refusal.

### Verified platform and Config redirect boundary — 2026-10-19

CTO and security closed the framed-response correction at pushed
`74da79933c3dd081de71b0f0026935cf21150684`. Canonical sync resolved BEHIND
at `960d04e249a2711081fb4f5021b784c2814a1abb`, including main
`cb8423745d9035e3990229d9b12930a96fda1571` (KB postmortem only).
Exact-head file-only preview/export match the same 5,163 runtime inputs,
191 migrations, 57 components and 6,938 source leaves plus metadata.
Pairing `eefcc1a3b78370d204c4e1fb6552f64e78556411bcd2ea130dd7115136aaad7b`;
operational `92c124b00880ba443366e39ffb59668a4a5f59153c705ab1ce5a19056968c783`.
CTO independently reviewed actual manifest
`bdbbca6cd97413b8003a39b752274d2a582ea7d242a206a62e022d828f29fdd5`
and runner `2d186348c8c187d471fe7931f49774435fa41cf73c78710ad5657d82f7f0d2d9`.
File-only source/helper/input/CA/output preflight passed, with 121 loaded
certificates and zero connections before fresh exact-action approval.

The exact command was freshly approved and executed once, observing
200/200/307. It retained the 864-byte platform manifest at raw SHA-256
`168f762c218e167ba88ae7e48194126eb5ba5e99ef652063e3f14f9c4f0ee70f`.
The exact Config descriptor specifies OCI image-config media, 2,646 bytes
and digest `sha256:3f56e44ddc1a5655b8f288a2aa812db567b2f5f0b8bc18ef3da63b94a95608d5`.
Config returned HTTP 307; the response body and Location were not retained,
no redirect was followed, and no Config or layers were downloaded. Declared
layer entries are inert manifest data and establish no image-store presence.
The exclusive marker is spent. Receipt checksum
`75f22c9010fd371939ec4afc0aca40d710651c2429f51d43cb126a0f86427c37`
and file SHA-256
`7a3c40e1a55cbeadc8c9f5310140a22310bfa554a1b5604faf3bb16940f84e81`
verify. Private directory/file modes remain 0700/0600, owner matches, retained
raw bytes/digest/descriptor match the receipt, and Config is absent.
CTO independently verified this actual evidence. Publisher/issuer/ownership/
profile/runtime authority remains false or pending. No follow-on action or
reuse of saved command approval is permitted.

Ruled by CTO agent: the next source-only boundary is a **separate redirect-
header diagnostic**, not an inferred CDN route or a destination download.
Permit exactly two fixed HTTPS GETs: the existing anonymous token request
with unchanged repository scope, then the exact pinned Config endpoint on
`registry-1.docker.io`. Inspect only Config status and bounded headers;
require HTTP 307 and exactly one bounded Location. Read no redirect body,
contact no destination and download no Config. Unexpected status, duplicate/
malformed Location or transport/binding/deadline failure terminates.

Location may carry a sensitive capability. Parse in memory and retain only
HTTPS scheme, normalized DNS hostname, allowed/default port, complete Location
hash/byte length, path hash, query-present and fragment/userinfo-present flags,
and whether the path contains the expected Config digest. Reject credentials/
userinfo, fragments, controls, unsupported scheme and malformed authority.
Never retain the full URL, query values, raw headers, bearer or exception text.
Observed routing information does not authenticate or authorize a destination.
Bind verified platform bytes/descriptor, exact source/helpers/executables,
CA/input/output identities and both request URLs. Preserve private outputs,
one-use consumption, fixed diagnostics, 60-second overall/requested 10-second
limits and independently approved outer timeout. No challenge, retry, layers,
daemon/account config or automatic follow-on. Source implementation, synthetic
tests, independent source review, fresh actual manifest review and fresh exact-
action approval remain pending. Actual header evidence must precede a separate
engineering/security ruling about any constrained destination request.

This closes the current metadata evidence phase at a partial result, with
Config acquisition and the full eleven-role gate still incomplete. Hosted
authentication stays BLOCKED, alternate route PENDING, draft/disarmed/default-
off/customer-blocked state and all build/recovery/routine/Web/CLO/ship holds
remain. Historical source-bound receipts stay unchanged and attributable.

### Classified token-header refusal — 2026-10-19

The separately approved redirect diagnostic at source `8f2700ed` stopped on its
first request: HTTP 200 with `transport/header_shape`. The Config request was
not attempted. Independent review verified the incomplete receipt's integrity
and exclusion of raw headers/body/Location. The precise failed predicate is
unknown. Its one-use marker is consumed and authorizes no retry.

Ruled by CTO agent, 2026-10-19: add diagnostic-local fixed failure classification
only, retaining the generic `header_shape` reason and existing token framing
acceptance. Do not expand the shared registry failure vocabulary or framing.
Rationale: the sanitized evidence proves refusal, not which predicate failed.
Dissent: reconsider broader framing only after classified evidence and separate
engineering/security review of its bounded nonblocking parser.

Source-only acceptance chain:

- Write failing synthesized tests for each token header predicate, including
  deterministic precedence when several predicates fail.
- Add only a fixed allowlisted category for the first failed predicate; never
  retain header names/values, raw headers, token body or exception text.
- Preserve valid responses, header-refusal zero-body-read behavior, Config
  response non-consumption, socket cleanup and absolute-deadline protections.
- Validate the adapter-to-collector classification path and refuse non-allowlisted
  classification values at the receipt boundary.
- Run offline tests and independent source review. Any replacement attempt
  requires fresh source/input/CA/platform/Config/output bindings, actual-manifest
  review and fresh exact-action approval. Historical evidence remains unchanged.

This source-only correction has no production observability surface: local fixed
receipts report the failure. No network action, build, Docker/SQL/provider/browser/
account operation, recovery, qualification, Web/CLO matrix or ship gate is released.

### Bounded token framing — 2026-10-20

The separately approved classified attempt at `deb0f086` stopped before token
body reading with `content_length_count`; Config GET was not attempted. This
does not distinguish missing versus duplicate Content-Length or establish any
Transfer-Encoding. Its marker and approval are consumed.

Ruled by CTO agent, 2026-10-20: implement bounded framing solely for the fixed
token endpoint's HTTP-200 response. Support a single valid Content-Length,
one chunked Transfer-Encoding with no Content-Length, or clean TLS EOF when
neither framing header exists. Continue rejecting duplicate Content-Length,
combined framing headers, duplicate/unsupported transfer coding, invalid length,
unsupported content encoding and non-JSON media before body reading. Preserve
the 16,384-byte decoded-body ceiling and existing absolute deadlines. Config
body reading must remain impossible in every status/framing combination.

Bound chunk count, size-line length, aggregate framing bytes and trailers;
reject extensions and nonempty trailers. Clean EOF completes only close-delimited
mode; premature/ragged EOF must fail. Explicitly disable Python's ragged-EOF
suppression. These modes and ambiguity handling follow
[RFC 9112 framing](https://www.rfc-editor.org/rfc/rfc9112.html#section-6.3);
the TLS setting follows the
[Python SSL API](https://docs.python.org/3.14/library/ssl.html#ssl.SSLContext.wrap_socket).
HTTP/1.0 responses carrying Transfer-Encoding remain refused.

Acceptance tests, written before implementation: fragmented/empty and exact-limit
bodies in all three modes; overflow; duplicate/ambiguous/unsupported framing;
malformed/truncated/oversized chunks; extensions/trailers; premature and ragged
EOF; never-ending/trickling reads; TLS read/write waits and absolute deadlines;
socket cleanup; constant-only receipts; full adapter-to-collector success; and
Config zero-body-read behavior across statuses and framing choices.

After offline suites and independent engineering/security parser review, prepare
fresh bindings and an unused manifest for independent actual-manifest review
and fresh exact-command approval. All historical evidence and broader holds
remain. Dissent: this compatibility change may not resolve the observed refusal
if the response contained duplicate Content-Length; synthetic tests cannot
establish the historical framing or destination authority.

### Reviewed redirect evidence and next boundary — 2026-10-20

The freshly approved bounded diagnostic at `7764f6c91e` completed once with
two requests: token HTTP 200 and pinned Config endpoint HTTP 307. Separate
security evidence review passed receipt self-hash
`4a4d754d0ac5d0da89d9a4c8895d831064b08498b22db23863f9685ff79fdc32`.
Exact bindings, hashes and limitations are recorded in
`redirect-framing-manifest-review-7764f6c9-2026-10-20.md`. The marker and
approval are consumed. The sanitized routing projection identifies HTTPS
`production.cloudfront.docker.com:443`; a query is present and the literal
expected Config digest is absent from its path. Raw Location/query/path/token
and response bodies were not retained. No destination or layer was requested.

Ruled by CTO agent, 2026-10-20: close the approved diagnostic as a successful,
separately reviewed routing observation. All destination requests and Config
body acquisition remain held. The next engineering gate is a source-only
proposal for separately authorized Config-only acquisition; the ruling grants
neither implementation nor execution authority. Registry routing alone does
not establish destination ownership, publisher authenticity or authority.
The discarded capability cannot be reconstructed or replayed from hashes.

The future proposal must resolve each boundary before implementation/approval:

- Establish the registry-to-destination relationship using primary evidence
  and obtain independent engineering/security acceptance of the exact hostname.
  A familiar name or suffix match is insufficient; provenance remains separate.
- Acquire a fresh Location only from the same pinned Config endpoint in a new
  finite action. Permit at most one destination GET to the reviewed exact host,
  HTTPS port 443. Refuse other hosts/schemes, userinfo/fragments, malformed
  authority, further redirect, challenge or retry. Do not replay this attempt.
- Confine the anonymous bearer to the registry. Forward no Authorization,
  cookies, credentials or Referer. Keep query capability only in memory, never
  in command arguments, logs, exceptions or files. Require pinned CA bytes,
  certificate/hostname verification, exact SNI, explicit DNS/address/connected-
  peer checks rejecting private/loopback/link-local/reserved addresses, and no
  ambient proxy substitution.
- Read only the pinned OCI Config under framing/body/deadline bounds. Before
  admission, require exactly 2646 decoded bytes and SHA-256
  `3f56e44ddc1a5655b8f288a2aa812db567b2f5f0b8bc18ef3da63b94a95608d5`,
  then validate its schema. No layers, manifest expansion or recursive fetch.
- Write boundary tests first; independently review transport/security source;
  regenerate source/input/CA/platform/private-output bindings; review the unused
  actual manifest; obtain fresh approval of the fully expanded bounded command.
  Define minimal sanitized outputs with raw URL, bearer, query and Config bytes
  unretained. Review resulting evidence separately before admission/qualification.

Rejected: automatic redirect following, current-attempt retry, hostname-based
trust, RC0-based permission, or treating digest integrity as profile provenance,
hosted-auth clearance or qualification. Dissent: this may require a materially
different acquisition design and primary evidence may not justify this host;
that uncertainty keeps acquisition held. Resync/full CI and all broader build,
Docker/SQL/provider/browser/account, recovery, qualification, Web/CLO, promotion
and ship gates remain unchanged. No new transport has been implemented.
