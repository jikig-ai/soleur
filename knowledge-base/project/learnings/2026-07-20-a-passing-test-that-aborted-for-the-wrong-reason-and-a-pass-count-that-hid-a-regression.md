---
date: 2026-07-20
problem_type: logic_error
component: infra
module: workspaces-luks-cutover
severity: high
symptoms:
  - "L6k passed on main for four PRs while the failure it asserts never once occurred"
  - "Fixing an unrelated bug flipped L6k from pass to fail while the suite's pass count IMPROVED 21/3 to 23/1"
  - "suppressed_rc went 1 to 0 — an un-inspectable repo stopped aborting the gate entirely"
root_cause: unverified_assumption
tags: [vacuous-tests, accidental-abort, pass-count-metric, test-environment-capability, git-fsck, mutation-testing, luks]
issue: 6733
synced_to: []
---

# Learning: a test that aborted for the wrong reason, and a pass count that hid a regression

## Problem

Test case L6k in `apps/web-platform/infra/workspaces-luks-loopback.test.sh` asserts the leading
hypothesis (H1) behind a real incident: the cutover runs as root, container repos are uid 1001, and
`git` refuses with `fatal: detected dubious ownership` at rc 128 **before reading a single object**.
If the gate classified that as `preexisting` instead of `probe_failed`, it would certify a copy it
never inspected — and a later phase deletes the plaintext original.

L6k passed on `main` for four PRs. **The ownership refusal never fired once.**

## What actually happened

The case overrode `_fsck_one` to drop the SUT's `-c safe.directory=` so real git would refuse, and
hardcoded `printf "0" > …objs`. On the runner the refusal did not fire, so:

```
refusal absent → rc=0 + objs 0/0 → classify `ok` → object-count floor fires
              → `unclassified` → ABORT → suppressed_rc=1 → assertion satisfied
```

The abort was real. The *reason* was an unrelated zero-object floor. The assertion checked only that
the run aborted, so it could not tell the two apart.

A later commit correctly fixed the hardcoded `objs=0` (it was a genuine blind fixture). That removed
the floor's trigger — and with it the accident:

```
refusal still absent → rc=0 + real objs → `ok` → NO abort → suppressed_rc=0
```

So the branch did not break L6k. **It removed the accident that had been concealing four PRs of
blindness.** An un-inspectable repo would now pass the gate — strictly worse than the original
failure, and it arrived wearing an improved pass count (21/3 → 23/1).

## Root cause

Three compounding errors, each of a documented class:

1. **The assertion named a symptom, not the property.** `[ "$rc" -ne 0 ]` is satisfied by every abort
   in the classifier, including four that have nothing to do with H1. The property is
   `classification=probe_failed` carrying the H1 line.
2. **The precondition was assumed, never measured.** Nothing checked whether the harness could
   *produce* an ownership refusal. Two mechanisms were tried across two commits — a foreign uid
   (65534, neither 0 nor `$SUDO_UID`) and `GIT_TEST_ASSUME_DIFFERENT_OWNER=1` — and neither fires on
   the runner. The env var is a **git test-suite knob with no compatibility promise**; it produces
   the refusal locally on git 2.53.0 and not on the runner's 2.54.0 (version is the leading
   candidate, not an isolated cause — no experiment varied it alone).
3. **A commit message asserted a mechanism that does not exist.** It claimed `objs=0` "masks the
   probe_failed this case asserts". It cannot: `probe_failed` returns **first** in `_fsck_classify`,
   and the floor only applies to `ok|preexisting|src_only`. The floor never pre-empts a setup fatal —
   it was *manufacturing a different abort*, which is the opposite failure and the one that mattered.

## Fix

Split the case by what is actually provable on the runner:

- **Arm (i) — deterministic.** The stub now **synthesizes** the H1 stderr (`fatal: detected dubious
  ownership in repository at '<repo>'`, rc 128). This tests the SUT's classifier — which this repo
  owns — rather than git's ownership heuristics, which it does not. `L6e` already proves the same
  abort wiring against **real** git via `fatal: bad config`, uid-independently, and passes on the
  runner.
- **Arm (ii) — downgraded, honestly.** It no longer claims to prove `-c safe.directory=` is
  load-bearing (that needs a real refusal). It is now labelled a health control: it shows the fixture
  is otherwise clean, so arm (i)'s abort is attributable to the synthesized fatal. The `ok()` string
  says so, because a green L6k must never be read as evidence the flag was exercised.
- **L6k-CAP — new, non-asserting.** Emits the host's ownership-check capability on **every** run:
  git version, euid, `SUDO_UID`, fixture uid, both probe rcs, `safe.directory` scope, and an explicit
  "this host CAN / CANNOT produce H1". A runner that cannot produce H1 is a fact about the runner,
  not a defect in the gate — but "the refusal never fired" must never again be indistinguishable
  from "nobody looked".

The assertion now greps `classification=probe_failed`. Measured: if `_FSCK_SETUP_FATAL_RE` ever stops
matching the H1 line, the run lands in `unclassified` and **still aborts rc=1** — so an
abort-only assertion would stay green while proving nothing. That is precisely how this passed.

## Prevention

- **A pass-count delta is not a safety metric.** 21/3 → 23/1 concealed a case going from
  aborting-by-accident to not-aborting-at-all. Diff **per-case verdicts** across runs, not totals; a
  case whose recorded rc changes is a finding even when the count improves.
- **When a test asserts "the guard fired", assert *which* guard.** In any classifier with more than
  one aborting outcome, the exit code is a symptom shared by all of them. Name the classification.
- **Measure the harness's ability to produce the precondition, and emit it every run.** If the
  environment cannot produce the failure, that is a third outcome — neither pass nor skip. Report it.
  A silent skip and a green assertion are equally misleading; a printed capability line is neither.
- **Treat another project's test-only env knob as unavailable.** `GIT_TEST_*` (and equivalents) are
  not API. If a test depends on one, it needs a fallback and a capability probe — or it should
  synthesize the condition and say so.
- **Before writing "X masks Y" in a commit message, trace the order.** Here the claimed mechanism was
  impossible in the direction stated, and the real mechanism was the reverse. A wrong mechanism in a
  commit message outlives the commit and misdirects the next reader.

## Related

- [[2026-07-20-the-fix-for-an-evidence-discarding-gate-discarded-its-evidence]] — the same gate; a fix
  that reinstated the defect it removed.
- [[2026-07-20-every-property-i-asserted-instead-of-measuring-was-wrong]] — the assert-vs-measure
  discipline this case violated in a new place.
- [[2026-07-16-a-mutation-battery-only-covers-what-you-mutate]] — a green battery measures the
  mutations you thought of; L6k's "it aborted" was the assertion nobody thought to mutate.
- #6766 — `infra-validation.yml` has no `push` trigger and `deploy-script-tests` is not a required
  check, which is why #6745 merged with this suite red and four PRs inherited it.
