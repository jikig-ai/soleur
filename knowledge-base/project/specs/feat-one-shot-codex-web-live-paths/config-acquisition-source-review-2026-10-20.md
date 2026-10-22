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

## Fixed pre-consumption stage diagnostic — 2026-10-20

The approved acquisition command exited with its sanitized incomplete result.
The preserved output directory contained only the original mode-0600 manifest;
the marker and receipt were absent. Source ordering creates the marker before
the first DNS/HTTP request, so this attempt did not reach network activity. The
local predicate that failed remains unknown, and the command approval is spent.
The private failed-attempt directory remains unchanged and must not be reused.

At `40b21cf4fff125207861b756189a0689fc08d0fb`, the source adds a closed set of
fixed pre-consumption stage labels and reports only that label outside caught
exception context. The synthesized CLI regression covers source-binding
failure, no marker and no request. Full offline discovery passed **397 tests**;
the added focused tests passed. Security review passed with no authority or
network behavior change. Code-quality review passed (8/10, no findings). Test
design review passed (8.6/10, Grade B) and independently reran the two new
tests. It notes that only source-binding placement is exercised through the
real CLI; other stage placements are injected, and a `gate_write` label does
not establish marker absence. This diagnostic does not identify the historical
failure cause or authorize another attempt.

The exact failed attempt remains immutable. The next separately approved action
is file-only refresh of current source/input/CA/platform bindings and preparation
of one fresh unused manifest in a new private directory. It excludes marker,
receipt, DNS, network and execution. Review the actual manifest and exact
expanded command as separate gates; fresh exact-command authorization and
separate evidence review remain required. All profile, recovery, qualification,
resync/full CI and ship holds persist.

## Approved Config attempt and separate evidence review — 2026-10-20

The operator approved the fully expanded one-time command for the fresh manifest
above. It exited 1 with the fixed generic refusal. The private output now contains
the unchanged mode-0600 manifest, a consumed mode-0600 marker, and a sanitized
mode-0600 receipt; all are regular files in the bound mode-0700 directory. The
receipt canonical self-hash is
`305323043f7eb30ba9e2642f4d62ff88201f4781f325bf376c19ae48a07cdf40`; its raw
SHA-256 is `0280a557343c5fb00cf87007c27638f7f93db188aca5aa44163fad5f28262dc0`.
The marker SHA-256 is
`9824d6f4657a21933708e2be693ad71f5026c95dc64cb42e9a8c7ac197bf75c6`.

Separate security evidence review passed: the closed receipt consistently says
`status=refused`, `stage=token`, `failure=dns`, zero HTTP requests, null HTTP
status/peer/TLS results, zero Config bytes, null Config checks, all authority
flags false, and review pending. Source places DNS/address admission before the
application send boundary and increments request count at send. The evidence
supports that no token, registry or destination HTTP request started. DNS
activity may have occurred; the fixed `dns` category groups helper startup,
resolution, output parsing and address-policy failures, and does not identify
the exact cause or prove absence of DNS traffic. No Config was acquired.

Ruled by CTO agent, 2026-10-20: stop after this receipt; preserve the consumed
marker and spent attempt, with no further diagnostics or acquisition. Source-only
inspection cannot recover the attempt-specific runtime DNS cause. The exact
command approval is spent. Further source-only diagnostics, retries and resolver
or transport probes are rejected; the profile/recovery chain remains gated on
successful acquisition. The independent review and ruling authorize no further
operational action. Historical diagnostic attempts and this Config attempt are
all spent; never remove or reuse their markers or output directories.

## Explicit proposal-only scope change — 2026-10-20

The operator subsequently answered “Authorize proposal-only planning” to an
explicit scope-change question superseding STOP solely for drafting a bounded
proposal for independent engineering/security review. Preparation, diagnostics,
execution, retries, resync and shipping remain held. The
[resolver-only proposal and independent acceptance record](resolver-only-proposal-2026-10-20.md#independent-proposal-review)
now own that limited design scope. Both reviewers accepted its prose boundary at
`d63d82a43306d4d04134bd02e8a571616d6c3678`. Source implementation and synthesized
offline tests require separate operator permission, still ungranted. The spent
attempt, exact historical cause uncertainty and all operational holds above are
unchanged; no new evidence, resolver execution or acquisition is claimed.

### Source authorization update — 2026-10-20

The operator subsequently answered “Authorize source and offline tests only” to
a separate scope question. This grants implementation of the accepted resolver-
only design and synthesized offline tests. It does not authorize diagnostics,
preparation, real resolver execution, DNS/network, retries, resync or shipping.
See the [corrected source record](resolver-only-source-review-2026-10-20.md) for
the offline results and independent review status. Historical evidence is
unchanged.

## Config helper containment finding — 2026-10-21

The operator expanded authorization to all remaining work and expressly removed
repeated per-phase permission questions; the
[continuation record](resolver-only-source-review-2026-10-20.md#expanded-continuation-authority-and-completed-resolver-action--2026-10-21)
owns the scope and completed resolver evidence. After independent acceptance of
that resolver result, file-only preparation at source
`da4b1b80a53538f7509993f4c30f7d9e05d54e18` created fresh operational/image inputs
and Config manifest
`bb5e493296b42938b66570c45da1a444f073aa0dd9d2a259dc08fcd340cae19a`.
The candidate directory was not assembled or created. Primary Docker exact-host
service-use documentation was rechecked on October 21; its allowlist still lists
the authentication and registry/CDN endpoints. This does not attest ownership or
publisher provenance.

Actual-manifest review passed its private identities, CA, retained platform,
runtime, schema, 37 source references and 21 dependency bindings, but engineering
and security **blocked execution** on a containment defect. The Config helper
started a separate session and lacked parent-death protection, so a forcibly
terminated coordinator could leave a blocking helper outside the outer timeout's
group. Normal `finally` cleanup did not establish safety on that path. The finding
was tracked before source correction as [Ref #10760](https://github.com/jikig-ai/soleur/issues/10760).
No Config command was executed. Preserve that unused manifest and all older
evidence; the correction requires new bindings rather than reusing it.

Ruled by CTO agent: retain the helper in its coordinator's timeout group/session,
pass only the allowlisted host and expected parent PID, bootstrap the fixed local
import, arm reviewed parent-death termination, and verify parent group/session
before the sole resolution call. Preserve environment, descriptor, output,
deadline, address-policy and network boundaries. Bind the imported supervisor
and new lifecycle suite in both the operational source-reference census and
Config dependency inventory. A killed coordinator cannot publish evidence of
successful cleanup.

RED-first synthetic helper/lifecycle tests exposed the missing parent contract,
startup refusal and surviving blocking helper after coordinator death. Separate
contract tests failed when the supervisor or lifecycle suite was omitted from
either source inventory; both inventories now require them. The focused helper
suite passed 34 tests after correction; the source author reports independent
group/parent-death mutation discriminators, parent-loss-before-arm, real synthetic
outer-group termination, guard/import failure and cancellation/reaping coverage.
All resolver seams in those tests are synthesized; no real DNS or Config request
was made. Complete offline discovery and independent corrected-source review are
pending at this point. The earlier refusal causes remain unknown.

The [October 21 CLO recheck](../../../legal/audits/2026-10-21-codex-web-hosted-auth-recheck.md)
retains both hosted authentication blocks and the separate alternative-route
pending disposition. Expanded owner approval permits continuing technical work;
it does not manufacture provider permission or allow live hosted qualification.

### Complete offline verification of the containment candidate

Primary rerun: `/usr/bin/python3.14 -E -B -W error -m unittest discover -s .
-p 'test_*.py'` from `scripts/codex-qualification/` passed **480 tests**, exit 0,
64.789 seconds. The focused operational-contract suite separately passed
**14 tests**, including missing supervisor/lifecycle source, after RED runs
showed both omission boundaries accepted absent bindings. Cached Ruff 0.16.10
passed all seven changed Python files; whitespace checks passed. The complete
discovery includes only offline/synthetic qualification tests, not an operational
Config attempt or live provider matrix. Corrected-source independent review is
still required before replacing the preserved unused manifest.

### Mutation execution correction — 2026-10-22

Engineering and security accepted production containment at
`77324397ddefc620c018b07bdd0fb193eae05d09`, but test-design review blocked the
instrument: generated signalling-helper mutants ran on the host. The historical
480-test pass above does not prove namespace safety. The revised lifecycle suite
automatically dispatches all three signalling mutation rows through the repository
allocator and canonical PID namespace, under `timeout -k`, including during
ordinary discovery. Each namespace runs a passing unmutated control first;
refusal and timeout fail closed without a host fallback. Reentry verifies PID 1
and the namespace PID census rather than trusting an environment marker.

The fixture now inventories nonce-owned descendants independently of readiness
and retires PIDs immediately after reap or established absence. Synthetic fault
rows cover readiness/PID-file errors, refusal, timeout, spoofed reentry, a red
control, and the rejected 2147483648 parent boundary. The focused author run
passed 41 tests and removed its allocated sandbox. Primary complete discovery
on the dirty candidate refused the clean-source preparation precondition (481
tests, one setup error); a committed-source rerun and independent re-review are
required. No new Config manifest or execution occurred.
