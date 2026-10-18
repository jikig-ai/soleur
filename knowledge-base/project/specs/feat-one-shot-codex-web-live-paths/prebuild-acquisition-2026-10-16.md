---
title: Separate prebuild evidence acquisition from runtime qualification
date: 2026-10-16
pr: 9051
status: diagnostic-implemented-focused-source-review-pending
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
