# Resolver-only source implementation and review — 2026-10-20

Status: initial source rejected by scoped review; source-only corrections in progress.
No operational preparation or execution is authorized.

## Authorization and accepted boundary

Following independent engineering/security acceptance of the
[proposal](resolver-only-proposal-2026-10-20.md#independent-proposal-review) at
`d63d82a43306d4d04134bd02e8a571616d6c3678`, the operator answered
**“Authorize source and offline tests only”** to:

> Engineering and security accepted the resolver-only proposal at d63d82a433 in
> PR #9051. Your approval so far covers proposal drafting and review only. Do you
> separately authorize implementing that design and running synthesized offline
> tests, with real resolver execution, diagnostics, preparation, DNS/network,
> retries, resync and shipping still held?

This permits dormant source changes, synthesized offline tests and scoped source
review. It excludes the real helper/resolver, any operational binding/manifest/
marker/receipt, DNS or network action, acquisition and retries. Historical evidence
and acquisition/resolver behavior must remain unchanged. Full branch review,
QA/preflight, resync/full CI, build/recovery, qualification, promotion and ship
remain held. Automatic draft checks are not full CI clearance.

## Source tasks and test dependencies

Each GREEN task is blocked by its corresponding RED task. Only synthesized
fixtures and processes may run; none may invoke the production resolver helper
or resolve a real hostname.

- [x] RED(unit): fixed helper protocol, closed manifest/receipt, output minimization
  and rejected contradictory/rehashed outcomes.
- [x] GREEN(unit), blocked by RED(unit): implement the dormant helper/coordinator
  and pure evidence contracts without acquisition continuation.
- [x] RED(integration): synthetic child parent-death/outer-timeout containment,
  kill/reap behavior, private publication, marker replay and failure rollback.
- [x] GREEN(integration), blocked by RED(integration): implement separate supervisor
  containment and owned one-use evidence boundaries.
- [x] Synthesized affected tests, meaningful negative cases and lint.
- [ ] Commit/push source; independent engineering and security source reviews;
  correct findings and repeat affected checks.
- [ ] Record exact source-bound outcomes and next gate without preparing an action.

## Initial RED evidence

Before any new production module existed, the implementation agent wrote 24 test
methods across `test_resolver_diagnostic.py` and `test_resolver_lifecycle.py`.
`python3 -B -m unittest test_resolver_diagnostic test_resolver_lifecycle`, run from
`scripts/codex-qualification/`, exited 1 with two import errors for the absent new
modules. This demonstrates initial RED from missing implementation; it is not a
claim that 24 behavioral assertions executed or failed. The coordinator separately
inspected the authored contract, protocol, process and publication test bodies.
No real helper, resolution or operational action ran.

## Implemented source boundary

Five new files under `scripts/codex-qualification/`; no historical acquisition,
resolver or test file changed:

- `resolver_probe.py`: a dormant fixed-host helper with one explicit resolution
  seam, fixed result categories and bounded memory-only answers.
- `resolver_diagnostic.py`: closed pure manifest/receipt contracts, unchanged
  `config_https.py` › `selected_address()` policy, bounded helper collection,
  one-use marker, descriptor-relative private evidence publication and separate
  dormant preparation/coordinator entry points. Source closure, committed source,
  clean tracked tree, interpreter bytes/version and actual supervisor invocation
  are checked before action consumption/launch. These checks were tested with
  synthesized bindings; no operational bindings were refreshed.
- `resolver_supervisor.py`: Linux parent-death signals, a supervisor-owned process
  group, unreaped leader identity through group termination and subreaper cleanup.
  Only a closed sanitized stage vocabulary may cross the worker-output boundary.
- `test_resolver_diagnostic.py` and `test_resolver_lifecycle.py`: synthesized
  contracts, binding/publication failures and scratch child lifecycle fixtures.
  Test guards refuse real sockets/DNS and unintended child launches; lifecycle
  fixtures allow only generated scratch programs, never the production helper.

The helper cannot continue into application connections, TLS, HTTP or acquisition.
Success terminates this action. Interpreter hashing is not complete kernel/
shared-library attestation; neither memory-only handling nor Linux containment
claims protection against a hostile host administrator.

## Source-only verification

Coordinator rerun on the frozen candidate:
`/usr/bin/python3.14 -E -B -W error -m unittest test_resolver_diagnostic test_resolver_lifecycle`
from `scripts/codex-qualification/`: **37 tests passed**, exit 0, 1.242 seconds.
The implementation agent also passed this suite on the host interpreter.
Pinned cached Ruff **0.16.10**, repository config, all five new files: **PASS**,
no baseline edit, installer or network access. Canonical lint `auto` reported its
user-repository scope unadopted; that report is not a whole-tree lint verdict.

Corrective tests ran RED before their changes: the 32-test refinement run exposed
two assertion failures and four errors (publication-close rollback, raw pipe-close
failure, CLI refusal and missing collector cases). A later 37-test regression
failed once because created-directory ownership was not pinned through rollback;
the directory descriptor now remains held until acceptance/rollback and close
slots are consumed once. Foreign replacements and consumed markers are preserved.
An initial backward-clock expectation was corrected to cleanup uncertainty; a
regex warning was fixed. These are development findings, not evidence about the
spent Config attempt.

All actual source-binding functions in these tests used fabricated identities,
mocked Git/runtime results or temporary synthetic source trees. One preparation
ownership regression exercised only fabricated scratch bindings and files.
No operational preparation/helper/resolver or execution CLI ran, no real hostname
was resolved, and no operational manifest, marker or receipt was created. The
isolated supervisor CLI was exercised only with a malformed synthesized manifest;
it refused at manifest validation before marker creation or helper launch.
Historical evidence remains untouched. No full PR/SAST/QA/preflight/CI verdict
or real-helper runtime result is claimed.

## Initial scoped source reviews — blocked

All three seats reviewed pushed `5ea1e20081a86746ea962a72fa752715b5520bdc`.
Engineering, security and test-design reviewers independently reran the guarded
37-test suite successfully. They nevertheless blocked source acceptance:

- Security/engineering: `coordinate()` could publish an `admitted` receipt and
  then fail its final deadline or output-close check, leaving apparently accepted
  evidence. Publication ownership must cover final acceptance; unknown cleanup
  must never establish admission. Preserve consumed markers, foreign replacements
  and earlier accepted evidence. Never delete by unpinned inode or retry an
  ambiguously closed descriptor.
- All seats: no test invoked the actual coordinator. Collector/component tests
  did not prove supervisor-parent argv checks, process-group/session refusal,
  consumption-to-helper-to-receipt composition or late-publication failures.
  Valid CLI dispatch and actual bounded pipe reading also needed synthesized
  owning-path coverage.
- Test-design score: **8.3/10, Grade B**, with both test files passing their
  unit/process-integration pyramid assessment. That score did not override the
  blocking missing coverage. Independently pinning the allowed outcome tuples
  was recommended to avoid a production-derived rejection oracle.

Ruled by CTO agent: fix these source findings with failing synthesized regressions
before changes, then obtain independent re-review of the corrected pushed source.
No preparation or execution authority follows from the initial green tests.

### Finalization technical ruling

Ruled by CTO agent: choose explicitly provisional persisted receipts plus
separately corroborated supervisor completion. A last-pin close can be ambiguous;
repeating pins or adding another supposedly final file does not resolve that
boundary. Every persisted receipt must have fixed `finalization=provisional` and
`action_accepted=false`; DNS `admitted` is an observation, not action acceptance.
Validate completion separately against closed source/action/receipt bindings,
normal coordinator exit, established process termination/reaping and supervisor
success. A receipt alone, nonzero exit, missing/partial/mismatched signal or
cleanup uncertainty cannot establish completion. Best-effort rollback must use
only still-established ownership, preserve markers/foreign/prior evidence, and
never retry an ambiguous close or delete by stale inode.

Correction tests must exercise actual synthesized coordinator/valid dispatch,
parent argv and PGID/SID refusal, bounded pipe reading, late deadline/directory/
last-pin close and rollback failures, provisional-only receipt rejection, and
partial/forged completion rejection. Source conformance stays blocked until the
corrected pushed source passes the independent scoped reviews.

## Continuing limits

Containment and truthful outcome classification are requirements to prove, not
runtime observations. A future diagnostic outcome cannot explain the spent Config
attempt. Preparation, actual-manifest review, exact-command execution approval
and separate evidence review remain future, distinct gates. Hosted auth BLOCKED;
alternate route PENDING. PR #9051 remains draft/disarmed/conflicting.

### Corrected source candidate — independent re-review complete

The source author reached an API usage limit before applying the finalization
correction. The primary agent completed the saved RED-first correction, without
using operational inputs or actions. The actual coordinator now persists only
`finalization=provisional`, `action_accepted=false` receipts. The outer supervisor
accepts one bounded closed coordinator candidate only after normal exit, group
termination and clean reaping, then emits separate source/manifest/receipt-bound
completion evidence. `checked_completed_action()` also requires independently
observed supervisor exit 0. Late deadline and directory-close failures attempt
rollback only while the receipt inode and directory remain pinned; an ambiguous
pin close leaves provisional evidence and cannot emit completion.

Correction RED evidence: 51 synthesized checks first exposed three assertion
failures in late publication/deadline/close behavior; the expanded 55-check run
exposed the missing provisional fields, missing completion API, and the same
rollback failures. Actual pipe-reader boundary cases were included. After the
correction, `/usr/bin/python3.14 -E -B -W error -m unittest
test_resolver_diagnostic test_resolver_lifecycle` passed **61 tests** (2.174s),
and cached Ruff 0.16.10 over the five scoped source/test files passed. This is
offline source evidence only; no operational census, preparation, helper,
resolver, DNS or network action ran.

The initial 37-test findings above remain historical and are not replaced by
this local result.

### Additional independent review corrections — resolved

Independent re-review of `08eb1c4c810cc4b255a44045f2178262bd799f9f` found four
additional fail-closed requirements: bootstrap the supervisor's local import
under isolated `-I -S`; read the manifest as a bounded no-follow private regular
file; skip already-consumed descriptor slots after ambiguous close and preserve
the real `os.close(None)` behavior in the fault test; and reject completion paired
with any non-admitted receipt. Engineering, security and test-design reviews also
required a deadline check after final pin closes.

These corrections were pushed in commits through
`218e092ef098016243a10b9651b398eb6783efc4`. The 61-test suite includes isolated
supervisor startup with a malformed synthesized manifest, bounded reader
rejection for symlink/FIFO/oversize files, deadline expiry after the final
directory-pin close, and a refusal-receipt/completion contradiction. Focused
tests and Ruff pass; no operational action ran.

### Independent scoped source acceptance — 2026-10-20

Engineering, security and test-design reviewers independently accepted the
corrected pushed SHA `218e092ef098016243a10b9651b398eb6783efc4`. All reviewed the
scope as source conformance and synthesized offline tests only. Engineering and
security found no remaining source blocker; test design scored **8.8/10, Grade B**
and passed both the filesystem/pipe unit layer and synthesized process-integration
layer. Independent focused Python 3.14 runs each reported 61 tests passing.

One security full-suite run reported that the foreign-replacement fixture file was
absent. The exact test then passed 100 isolated repetitions, followed by another
full 61-test pass. The cause remains unknown; neither source-caused deletion nor
concurrent interference was established. Preserve this uncertainty when reporting
the result. No production resolver/helper, real DNS/network, preparation or
operational manifest/marker/receipt was used or created.

This acceptance authorizes no next stage. Separate operator authorization for
file-only binding refresh and creation of one fresh diagnostic manifest is still
required. Actual-manifest review, fresh exact-command execution approval and
separate evidence review remain distinct gates; all broader CI, recovery,
qualification and shipping holds remain in place.

## Separately authorized refusal-stage correction — 2026-10-21

The operator separately authorized read-only actual-manifest review, one exact
supervisor execution, then read-only outcome review. The one execution at source
`c0ee6d2d3d0de6bf6af23397988e28f89c6e1b73` exited **2**, printing only
`Resolver diagnostic refused; no retry authority`. No coordinator stage or
supervisor completion was emitted. That execution permission is spent.

The manifest's canonical JSON digest is
`087199313bd50848b8a4148f02793fa7360231a617b138ccca9e4c552800556e`;
the stored-file digest is
`cb13857cf469604998e381b77b085cbfe30262ddb692c2435a94ee3810958f38`.
The stored file equals canonical JSON plus one newline; those different digests
do not indicate changed content. Independent engineering/security manifest review
accepted the canonical digest for the CLI. The initial comparison of unlike
digests unnecessarily requested another review permission; see the
[session learning](../../learnings/runtime-errors/2026-10-21-resolver-refusal-stages-and-canonical-digests.md).

Separate engineering/security outcome review confirmed the same private directory
identity and modes, unchanged manifest and all 18 source/runtime bindings. Only
the manifest existed; marker and receipt were absent. A read-only current process
snapshot found no matching supervisor/coordinator/helper among 695 readable
processes. These current observations do not prove historical zero helper launches,
zero DNS activity or successful cleanup. The actual refusal cause remains unknown;
do not label this attempt a DNS failure or infer retry authority.

Ruled by CTO agent: record refused/outcome-unestablished and correct the dormant
supervisor's sanitized failure stages with synthesized offline tests. The operator
then explicitly **approved that source-only correction and offline testing**.
Real resolver/helper execution, DNS/network, operational preparation, diagnostics,
retries, acquisition, resync/full CI, full review/QA/preflight, recovery,
qualification, legal/promotion and shipping remain held. Historical operational
files were not modified; their old source bindings must not be reused.

The correction distinguishes fixed supervisor boundaries for source/import and
manifest checks, parent-death/subreaper and signal setup, spawn/monitor, timeout,
interruption/output limits, cleanup, protocol/completion, child exit and finalization.
Labels describe an observed boundary, not a historical root cause. Exception text,
stderr and unrecognized child output remain suppressed. Failure reports and valid
completion publication follow owned-process cleanup, pipe closure and restoration
of installed handlers; a late close/restoration/interruption failure cannot publish
completion. Existing containment, host, address policy, budgets, one-use evidence
and provisional receipt authority remain unchanged.

RED-first evidence: the six initial new unit methods failed with **17 assertion
failures and five errors** against the old source. Three additional fault cases
failed for missing timeout/interruption/output-limit stages. A later synthetic
late-interruption regression failed with returned success before its correction.
No operational inputs or production helper were used. The expanded focused suite
passed **71 tests**, exit 0, 3.126 seconds, using `/usr/bin/python3.14 -E -B -W error
-m unittest test_resolver_diagnostic test_resolver_lifecycle`. Cached Ruff 0.16.10
passed for the three changed Python files; whitespace checks passed. One existing
lifecycle expectation was updated to include the newly required sanitized protocol
stage after a rejected child message. This is scoped offline verification only.

Independent review of the corrected committed/pushed source remains pending.
No new binding census, manifest, marker, receipt or operational attempt was made.

### Offline boundary and fixture corrections

Primary review added two RED cases where a final post-exit pipe drain exceeds
768 bytes with child exit 0 or 1. The correction explicitly marks that observation
uncertain, preserving exit 2 rather than merely printing a refusal. These rows
failed with 0/1 before the one-line correction. They do not describe the prior
operational attempt.

One concurrent full focused run failed because the timeout-after-candidate
lifecycle fixture had not published its receipt within its fixed half-second
startup window. Adding a deliberate 600 ms synthesized startup delay reproduced
the missing receipt deterministically. That fixture now signals readiness after
candidate flush, and an injected clock triggers timeout only after readiness;
a separate real five-second startup cap prevents an indefinite fixture wait.
The deliberate startup delay remains as a regression discriminator. Production
timeouts were not changed. This explains the reproduced fixture failure only,
not the different historical foreign-replacement fixture uncertainty above.

Test-design review recommended stderr assertions, handler-restoration ordering
and a throwing reporter regression; all three are now covered. The expanded
focused suite passed **72 tests**, exit 0, 3.716 seconds, with the same Python 3.14
command. Scoped Ruff and whitespace checks passed. Independent final-source
re-review remains pending; these are offline results, not operational clearance.

### Independent correction acceptance — 2026-10-21

Engineering, security and test-design reviewers independently accepted pushed
`2516b7561ec323771e04ba16e1e132068e576837`, reviewing the complete source correction
against `c0ee6d2d3d0de6bf6af23397988e28f89c6e1b73` and the final correction delta.
All three independently reran the permitted guarded focused suite: **72 tests
passed**, exit 0, respectively 3.870, 3.759 and 3.949 seconds. Test-design score:
**8.8/10, Grade B**, unit and synthetic OS lifecycle checks PASS. No blocking
findings remain in this scoped correction. The test-design recommendations were
implemented before final-source acceptance. These scoped seats are not the held
full PR review, QA, preflight, CI, legal or runtime qualification gates.

Ruled by CTO agent: source conformance PASS; the next gate requires separate
operator permission for file-only binding refresh and one fresh unused diagnostic
manifest. No preparation was performed. Actual-manifest/exact-command review,
fresh one-time execution permission and separate evidence review remain distinct
later gates. The old manifest and all historical attempt evidence remain untouched;
old source bindings and the spent execution approval cannot be reused. The cause
and historical helper activity of the refused attempt remain unestablished.

## Expanded continuation authority and completed resolver action — 2026-10-21

After the correction acceptance above, the operator said **“approved for all the
remaining items”** and **“No need to ask me for each”**. This supersedes the earlier
per-phase operator holds for remaining non-production preparation, reviews,
diagnostics, acquisition, source/tests, isolated recovery, reconciliation and
shipping work. Continue those already authorized steps without repeated permission
questions. Technical review, fresh source/action bindings, containment and evidence
requirements still apply. Destructive shared-production commands retain their
repository-mandated exact-command approval; owner consent does not grant provider
permission or establish missing legal/account facts.

File-only preparation at clean pushed
`da4b1b80a53538f7509993f4c30f7d9e05d54e18` created one new private resolver manifest.
Engineering and security independently accepted the actual manifest and exact
supervisor command before execution. Canonical manifest SHA:
`0531dcf72806ada63e12cfbbf6223dc10a21a54ae09d74f803002dc7a31402ce`;
stored-file SHA:
`1a43515d0babc97adaba1314ddde3fa3f6a711d2646b9563faf52fb295c159d0`.
All 18 source bindings, interpreter, private identity/modes and unused directory
passed. The earlier spent manifest was not reused.

That exact new command ran once and exited **0**, emitting the reviewed supervisor
completion signal. The private receipt records `admitted/complete`, one helper,
reaped cleanup, provisional finalization, `action_accepted=false`, pending review
and all authority fields false. Independent engineering/security evidence reviews
accepted those bindings paired with the observed exit/completion. The separate
private execution observation preserves root's actual tool output; reviewers
verified its consistency rather than independently witnessing the original call.

- Marker raw SHA:
  `fe08d41b96c92beac637c8c4f0ffc1135359c6dfc4abe1fd5b57779a24770ee4`.
- Receipt raw SHA:
  `09a6d45a349d893a5aef95c4012873f4e99353625b4f5fa4dbf64513f8a0616c`.
- Receipt self-hash:
  `fac29c3c1c9057556dac7e043ac6873efd124fa036bb2f04b2fa0136dbb0fdeb`.

This establishes this invocation's bounded resolution/address-policy result and
corroborated completion. It does not explain the older refusals or establish HTTP,
Config, publisher, profile, recovery or qualification admission. The new attempt
is consumed. Ruled by CTO agent: proceed to fresh Config file-only preparation and
actual-command review under the expanded authorization. The subsequent containment
finding and correction are recorded in the
[Config source review](config-acquisition-source-review-2026-10-20.md#config-helper-containment-finding--2026-10-21).
