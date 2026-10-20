# Config acquisition source review — 2026-10-20

Implementation source: `714f48c3e4dd245367ff12ee39e4c31cbc8ec486`, pushed to
draft PR #9051. The operator's subsequent `approved` authorized the
[accepted proposal's source/offline-test stage](config-acquisition-proposal-2026-10-20.md#independent-proposal-acceptance--2026-10-20).
It excluded operational binding/manifest preparation, real-origin requests,
markers and acquisition. That authority has been used for source and synthesized
tests only. No operational manifest or evidence was prepared or executed.

## Implemented boundary

New modules under `scripts/codex-qualification/`:

- `config_https.py` and `config_resolver.py`: fixed token/registry origins and
  one fresh, exact-host destination; closed credential-separated headers;
  strict Location validation; bounded fresh-interpreter DNS; whole-answer
  address rejection; one numeric connection and two peer checks; pinned CA/TLS;
  byte-at-a-time headers, header-only registry/errors and exact Config framing.
- `config_schema.py`: bounded strict JSON and the named OCI normative-null
  contract. A complete local structural reference closure and all component
  source bytes are bound separately. No remote schema references or execution
  defaults; reserved Healthcheck members remain inert. Timestamp checks cover
  syntax/calendar/offset bounds, without a leap-second issuance table.
- `config_acquisition.py`: pure plan construction, source/runtime/input/output
  checks, persistent one-use gate, shared deadlines, exact Config length/digest/
  schema, closed sanitized receipts and dormant preparation/execution entry
  points. Public execution failures are sanitized outside exception handlers.

No existing acquisition/diagnostic module or historical receipt was changed.
The new source requires separately authorized preparation and execution before
use. Memory-only handling makes no physical-zeroization or hostile-host claim.
Runtime paths/versions are bound; executable/shared-library attestation is not
claimed. Config field values remain unretained, so receipts cannot reconstruct
them or serve as actual field-value/profile evidence.

## Verification

Initial coordinator, transport and schema tests failed before implementation.
Corrective tests also ran RED for gate-time accounting, receipt contradictions,
source-binding failure classification and raw publication errors. The
[session learning](../../learnings/workflow-patterns/2026-10-20-source-bound-diagnostic-review-discovery.md#approved-sourceoffline-implementation-addendum--2026-10-20)
records discovery and harness corrections.

- Full offline discovery under `/usr/bin/python3.14 -E -B -W error`:
  **394 tests passed**, exit 0. It includes synthesized local Unix/TLS fixtures;
  the sandbox-denied attempt was rerun with the required fixture access.
- Focused `test_config_*.py`: **65 tests passed**. No real origin or production
  resolver helper is invoked. A synthesized sleeping helper verifies actual
  child cancellation/reaping with a bounded deadline and no DNS.
- Config success uses a narrowly mocked hash over synthesized 2646-byte JSON;
  it does not contain real Config data or claim a preimage of its pinned digest.
  Real negative hashing, schema validation, adapter/coordinator integration,
  source checks and filesystem boundaries are exercised separately.
- Behavioral source mutations use isolated synthesized module fixtures,
  pristine controls and specific assertion failures. They cover selected
  schema, host/framing/peer, replay/output, receipt and execute-dispatch guards;
  they are not an exhaustive correctness proof. Internal errors do not count
  as caught mutations. No tracked source is mutated by the tests.
- Ruff: 44 existing baselined findings, all **123** tracked Python files scanned;
  no baseline change. Semgrep: one worker, `p/python`, metrics off, **151**
  applicable rules over all **eight** new Python files, zero findings/errors.
- Staged color-pinned secret scans and whitespace checks pass. Hook execution
  is not claimed: the worktree's `core.hooksPath` remains `/dev/null`.

## Independent scoped reviews

All source was pushed before reviewer dispatch. The three review seats ran in
parallel; CTO conformance is a subsequent separate seat. These are scoped source
reviews, not the full branch review/QA/preflight or readiness gate.

- Security: initial Medium blocker at `64f978fcba` reproduced a rehashed refusal
  receipt claiming Config validation without a destination send. First-RED
  regressions and mutation checks now require destination send/status/peer/TLS,
  correct schema stage and length/digest evidence. Re-review **PASS at
  `714f48c3e4`**, independently running all 65 focused tests. Docker's exact
  destination listing was rechecked before source review.
- Code quality: initial source review passed; correction-delta re-review
  **PASS at `714f48c3e4`**, independently running all 65 focused tests.
- Test design: initial blockers identified wrong-reason observer refusals,
  unproven execute binding dispatch, untested persisted failure disclosure and
  overbroad deadline/mutation claims. New real-dispatch low-level-mock cases,
  eight-category execute/CLI matrices, publication refusals, across-stage
  deadlines and stronger mutation controls close them. Re-review **PASS at
  `714f48c3e4`**, 65 focused tests, 8.6/10 (B); all three changed test files
  classified unit and passed the pyramid check. The unchanged schema test file
  had already passed its unit classification in the initial review.

The test reviewer attempted no extra ad hoc workspace mutation after its scratch
allocator refused; no fallback or independent mutation run is claimed. Reviewers
changed no source and made no origin requests.

## CTO conformance and next authorization

Ruled by CTO agent, 2026-10-20: accept scoped source conformance at
`714f48c3e4dd245367ff12ee39e4c31cbc8ec486`. The implementation preserves the
accepted host, credential/address/peer/TLS, strict framing, exact Config checks,
shared deadlines, one-use/source/output bindings and non-admission boundaries.
Final independent test-review PASS is recorded above; that prerequisite is met.

The next operator authorization action is explicit permission for **file-only
refresh of source/input/CA/platform bindings and preparation of one fresh unused
Config action manifest in a new private directory**, preserving historical
evidence. That permission excludes marker consumption, receipts, DNS, all network
requests and execution. This ruling does not grant that permission; it remains
ungranted at this record.

Main resync remains held and is not required before this isolated file-only gate.
Freshness requires the final clean, committed, pushed HEAD and the reviewed
component bytes. Any later resync or source/input/CA/platform/runtime change
invalidates affected bindings: refresh the unused manifest and repeat affected
tests/source review and actual-manifest review before seeking execution approval.
Recheck primary exact-host documentation at the prescribed review gates.

Rejected: preparing under the earlier source-only approval, replaying spent
attempts, carrying stale bindings across changed HEAD, executing under preparation
approval, or treating scoped checks as full CI/qualification. Dissent: actual CDN
framing and Config compatibility remain unverified; provenance, recovery,
qualification, full CI/resync and shipping remain incomplete and held.

## Remaining holds

All three historical diagnostic approvals/markers remain spent. No permission
for a retry, destination request, Config acquisition or admission follows from
these test/review results. Exact-host service-use evidence is separate from
ownership, issuer and publisher provenance; all authority/admission fields stay
false and immutable receipt review remains pending.

Operational preparation, actual-manifest review, fresh exact-command approval
and separate evidence review remain distinct gates. Profile/recovery evidence,
qualification, permitted Web/CLO matrices, main resync/full CI, full review/QA/
preflight, promotion and ship remain held. Hosted authentication stays BLOCKED;
alternate route stays PENDING. PR remains OPEN/draft/disarmed and CONFLICTING;
reported GitHub checks are not a complete CI verdict. Archive these live planning
artifacts before any eventual ready/merge action.
