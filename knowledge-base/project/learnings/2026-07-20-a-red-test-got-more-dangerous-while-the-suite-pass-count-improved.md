---
date: 2026-07-20
problem_type: logic_error
component: infra
module: workspaces-luks-cutover
severity: high
symptoms:
  - "Suite improved 21 passed/3 failed to 23/1 while one case became strictly more dangerous"
  - "L6k failed for a reason unrelated to the one it names, so its recorded rc looked like the trap had sprung"
  - "The gate's ANY-vs-ALL probe_failed threshold had no test at all — every fixture was single-workspace"
root_cause: unverified_assumption
tags: [vacuous-tests, failure-mode-regression, pass-count-metric, threshold-coverage, single-fixture-blindness, git-fsck, mutation-testing, luks]
issue: 6733
synced_to: []
---

# Learning: a red test got more dangerous while the suite's pass count improved

## Problem

Test case L6k in `apps/web-platform/infra/workspaces-luks-loopback.test.sh` asserts the leading
hypothesis (H1) behind a real incident: the cutover runs as root, container repos are uid 1001, and
`git` refuses with `fatal: detected dubious ownership` at rc 128 **before reading a single object**.
If the gate classified that as `preexisting` instead of `probe_failed`, it would certify a copy it
never inspected — and a later phase deletes the plaintext original.

Across #6745 and its follow-up the suite went **21 passed / 3 failed → 23 passed / 1 failed**. Read
as a headline that is progress. Read per-case, L6k went from `suppressed_rc=1` to `suppressed_rc=0`:
**an un-inspectable repo stopped aborting the gate at all.** The aggregate improved while the one
case guarding the incident's own failure mode got strictly more dangerous.

## What actually happened

L6k was **red the whole time** — it was one of the three failures on #6745. But it was red for a
reason unrelated to the one it names, and that is what made the regression invisible.

The case overrode `_fsck_one` to drop the SUT's `-c safe.directory=` so real git would refuse, and
hardcoded `printf "0" > …objs`. The refusal never fired on the runner. So:

```
main:   refusal absent → rc=0 + objs 0/0 → classify `ok` → object-count floor
                       → `unclassified` → abort rc=1
        assertion: [ rc -ne 0 ] PASSED, grep 'could NOT INSPECT' FAILED  →  RED
```

The two aborting classifications emit **different** die strings — `could NOT INSPECT` for
`probe_failed`, `cannot classify` for `unclassified` — so the third conjunct caught it. Good. But
the *first* conjunct (`rc != 0`) passed, and `suppressed_rc=1` was duly recorded in the failure
line. Anyone reading that line saw an abort and concluded the trap had sprung; only the grep knew
otherwise.

Then a later commit correctly fixed the hardcoded `objs=0` (a genuine blind fixture). That removed
the floor's trigger:

```
branch: refusal still absent → rc=0 + real objs → `ok` → NO abort → suppressed_rc=0  →  still RED
```

Same colour, worse meaning. The case had gone from *aborting for the wrong reason* to *not aborting
at all*, and nothing in the suite's output distinguished those two reds.

## The larger hole this exposed

Chasing L6k surfaced something worse. `verify_git_fsck_differential` elects its abort class with
`elif [ "$n_probefail" -gt 0 ]` — abort on **ANY** un-inspectable repo. **Nothing tested that
threshold.** Every gate fixture (L6b, L6e, L6f, L6g, L6i, L6k) probed exactly one workspace, and at
one workspace `1-of-1` is indistinguishable from `all-of-1`.

Mutation-proven in a sandbox copy: restoring the superseded ALL threshold
(`&& [ "$n_probefail" -eq "$total" ]`) passed every single-workspace case, and turned a 1-of-2
`probe_failed` into **rc 0, "no copy-introduced regression"**. That is run 29725194755's 8-of-10
shape landing in the **gate** path — inside the freeze, where a false green is followed by Phase 5
wiping the plaintext original. L6j guards the same threshold, but only for the pre-freeze *advisory*
probe, which is the strictly less dangerous of the two locations.

## Root cause

1. **The assertion named a symptom, not the property.** `[ "$rc" -ne 0 ]` is satisfied by every
   abort in the classifier. With more than one aborting outcome, an exit code is a shared symptom.
2. **The precondition was assumed, never measured.** Nothing checked whether the harness could
   *produce* an ownership refusal. Two mechanisms were tried — a foreign uid (65534) and
   `GIT_TEST_ASSUME_DIFFERENT_OWNER=1`, a git **test-suite knob with no compatibility promise** —
   and neither fired on the runner. The cause was neither of them and was found only once the probe
   printed its own inputs: the runner image ships `safe.directory = *` in the SYSTEM gitconfig, so
   git allowed every directory and no ownership check could fire under any mechanism. See Prevention.
3. **One fixture per case, for logic that is about counts.** A threshold cannot be tested by a
   population of one.
4. **A dead regex alternative.** Measuring all seven alternatives of `_FSCK_SETUP_FATAL_RE` found
   `cannot chdir` never matched anything: git emits `fatal: cannot change to '<path>'`. Fail-closed
   via branch (2b), so nothing was mis-certified — but the allowlist asserted precision it lacked.

## Fix

- L6k now uses **two** workspaces, synthesizes the H1 stderr for one, and asserts
  `could NOT INSPECT 1 workspace` plus `classification=ok` on the healthy sibling. The **count** is
  the load-bearing token; mutation-verified that restoring the ALL threshold turns it red.
- Arm (i) synthesizes the refusal rather than provoking it, testing the classifier this repo owns
  instead of git's ownership heuristics. `L6e` already proves the same wiring against **real** git
  via `fatal: bad config`, uid-independently.
- Arm (ii) downgraded from "proves `-c safe.directory=` is load-bearing" to a health control, and
  the `ok()` string says so. The real proof lives in **L6m** (below), which the probe made possible.
- New **L6m** — the load-bearing proof, against **real** git, in CI. Once ambient config is
  neutralized the refusal fires on the runner, so two runs over the same foreign-uid repo differing
  only in `-c safe.directory=` (absent → `probe_failed` + abort; present → `ok`) attribute the
  rescue to the flag and nothing else. Gated on L6k-CAP, so a host that genuinely cannot produce a
  refusal skips with a note instead of failing environmentally.
- **L6k-CAP** measures the host's ownership-check capability every run and, on a host that CAN
  produce H1, **asserts real git's refusal still matches `_FSCK_SETUP_FATAL_RE`** — re-joining the
  contract that synthesizing forked, at zero flake cost where the host cannot.
- New **L6l** covers branch (2b): an unrecognised fatal, identical on both sides, must fail closed
  as `unclassified`. That branch was the only thing preventing a `preexisting` green, and had no test.
- `cannot chdir` → `cannot change to`; every alternative now carries a measured/unmeasured record.

## Prevention

- **A pass-count delta is not a safety metric, and neither is a colour.** Diff **per-case verdicts**
  across runs. A case that stays red while its recorded rc changes is a finding — here it was the
  finding.
- **When a test asserts "the guard fired", assert *which* guard.** In any classifier with more than
  one aborting outcome, pin the classification, not the exit code.
- **Threshold logic needs a population > 1.** If the SUT counts (`-gt 0`, `-eq total`, N-of-M), a
  single-item fixture cannot distinguish any of them. Sweep the suite by fixture size before
  trusting threshold coverage.
- **Every synthesis forks the test from the contract it models — re-join it conditionally.**
  Synthesizing is right for determinism, but the real string then exists only in a `printf` the test
  owns. A cheap conditional assertion on hosts that *can* produce the real thing costs nothing and
  is the only drift detector left.
- **Measure the harness's ability to produce the precondition, and print it every run.** "Cannot
  produce" is a third outcome, neither pass nor skip. **This paid off on its first CI run and is the
  strongest result here.** Three explanations had been advanced for why the ownership refusal never
  fired — the fixture uid, then git 2.54.0-vs-2.53.0, then "the runner cannot". All three were
  inference and all three were wrong. The probe printed the answer next to its own verdict: the
  runner image ships `safe.directory = *` in the SYSTEM gitconfig, so git allowed every directory
  and no ownership check could fire. Neutralizing `GIT_CONFIG_SYSTEM/GLOBAL` makes the refusal fire,
  which makes the load-bearing proof runnable in CI after all (now `L6m`). An instrument that
  reports its own inputs alongside its verdict found in one run what three commits of reasoning got
  wrong — and note the failure shape: the probe's *conclusion* ("this host CANNOT produce H1") was
  itself a measurement artifact, true of the measurement and false of the host. Print the inputs,
  not just the verdict.

  **Confirmed on the next run (29746786010): 27 passed, 0 failed.** With ambient config neutralized
  the refusal fires from genuine foreign-uid ownership alone — `rc=128 fatal: detected dubious
  ownership`, no `GIT_TEST_*` knob involved — so `L6m` proves `-c safe.directory=` load-bearing
  against real git, in CI, and L6k-CAP's conditional assertion confirms git's wording still matches
  `_FSCK_SETUP_FATAL_RE`. The capability that three commits had written off as impossible was
  available the whole time, behind one line of ambient config.
- **Treat another project's test-only env knob as unavailable.** `GIT_TEST_*` is not API.

## Related

- [[2026-07-20-the-fix-for-an-evidence-discarding-gate-discarded-its-evidence]] — same gate; a fix
  that reinstated the defect it removed.
- [[2026-07-20-every-property-i-asserted-instead-of-measuring-was-wrong]] — the assert-vs-measure
  discipline. Violated again here: the first draft of *this* learning claimed L6k "passed on main
  for four PRs". It was red. A review agent reproduced main's behaviour and falsified it.
- [[2026-07-16-a-mutation-battery-only-covers-what-you-mutate]] — the ANY-vs-ALL threshold is
  precisely the mutation nobody ran.
- #6766 — `infra-validation.yml` has no `push` trigger and `deploy-script-tests` is not a required
  check, which is why #6745 merged with this suite red.
