# Resolver-only source implementation and review — 2026-10-20

Status: source implemented; scoped independent source review pending.
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
was resolved, and no operational manifest, marker or receipt was created.
Historical evidence remains untouched. No full PR/SAST/QA/preflight/CI verdict
or real-helper runtime result is claimed.

## Continuing limits

Containment and truthful outcome classification are requirements to prove, not
runtime observations. A future diagnostic outcome cannot explain the spent Config
attempt. Preparation, actual-manifest review, exact-command execution approval
and separate evidence review remain future, distinct gates. Hosted auth BLOCKED;
alternate route PENDING. PR #9051 remains draft/disarmed/conflicting.
