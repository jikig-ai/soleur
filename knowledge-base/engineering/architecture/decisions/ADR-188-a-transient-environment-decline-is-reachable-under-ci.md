---
title: A transient environment decline is reachable under CI, and must corroborate rather than infer
status: adopting
date: 2026-08-12
amends: [ADR-181]
related_adrs: [ADR-166, ADR-177, ADR-180, ADR-181]
related: [7291]
related_plans:
  - knowledge-base/project/plans/archive/20260816-203421-2026-08-12-fix-t5-mutation-arm-network-flake-plan.md
related_specs:
  - knowledge-base/project/specs/archive/20260816-203421-feat-one-shot-7291-t5-mutation-network-flake/session-state.md
brand_survival_threshold: aggregate pattern
---

# ADR-188: a transient environment decline is reachable under CI, and must corroborate rather than infer

## Context

`git-data-runcmd-rehearsal.test.sh` carries a mutation arm for T5, the guard that proves a wrong
Doppler checksum aborts before `chmod +x /usr/local/bin/doppler` runs on an unverified tarball as
root. The mutation arm exists to prove the `CHMOD_RAN` marker is *reachable*, so that its absence in
the primary arm is evidence of the abort rather than evidence that nothing ever prints it.

The arm's design comment stated its premise plainly: *"curl SUCCEEDS (real network, genuine
tarball), so the checksum is the ONLY thing that can stop the chain."* That premise is false under a
degraded network. When the container's `apt-get` or the tarball download fails, the chain aborts
**earlier** than the checksum, `CHMOD_RAN` never prints, and the arm reported:

```
FAIL: T5 MUTATION: without set -e the chain still did not reach chmod — T5's check is vacuous
```

Measured on the reporting branch: 4 pass / 2 fail across 6 runs, against 44/44 on a clean
`origin/main` run. The suite is registered in `infra-validation.yml`, so the flake reddens a
required check on unrelated PRs.

The failure direction was **correct** — an unreachable marker being reported as "this check proved
nothing" is the honest verdict, and is exactly what ADR-180 asks of a guard that cannot demonstrate
its own failing direction. What was wrong is that the arm could not distinguish *the mutant ran and
the guard is vacuous* (a real finding about the SUT) from *the mutant never ran* (a statement about
the network). Both produced the same verdict, and only one of them is about this repository.

## Decision

The arm gains a third verdict, `SKIP`, reachable **only** on positive corroboration that the driver
never executed, and bounded by a counted ceiling. Four properties are load-bearing.

**1. The skip turns on the absence of a DISTINCT, EARLIER marker — not on the absence of the success marker.** The driver's `drive.sh` emits an
execution marker immediately above its `. /work/doppler-dl.sh` line and **below** the capture-server
guard. The verdict reads that marker, not the exit code alone. Absence of `CHMOD_RAN` plus presence
of the marker is a genuine vacuity and stays a `FAIL`; absence of both is the environment decline.
This is still an absence test — the code reads `! grep` — and calling it positive corroboration
would be false. What makes it sound is WHICH absence: a distinct marker emitted earlier in the
driver, localising the failure upstream of the download block rather than merely observing that
the success marker did not appear. Inferring the decline from a non-zero docker rc alone would
have re-created the original defect one level up — a missing signal read as a verdict about the
SUT.

**2. A missing measurement ALONGSIDE A ZERO EXIT is a harness bug, never an environment skip.** A
capture-integrity precondition runs *ahead* of the verdict branch: an empty `$TMP/out/stdout` **with
`rc == 0`** hard-fails. This is the row that stops the fix relocating the bug it closes (matrix
row 5).

The `rc == 0` conjunct is load-bearing and the property is deliberately **not** stated
unconditionally. A degraded container legitimately exits non-zero *and* produces an empty capture —
measured, matrix row 2 (the only real skip in the matrix) recorded `docker rc=100` with an empty
tail. Widening this precondition to fire on an empty capture regardless of rc would convert that
skip back into the false FAIL this ADR exists to remove. "The container said it succeeded and
produced nothing" is a harness bug; "the container said it failed and produced nothing" is the
environment.

**3. The branch order is load-bearing and commented.** `CHMOD_RAN` → `FIXTURE:` → marker → else
fail. Testing the marker before `CHMOD_RAN` would skip a slow-but-successful run; testing it before
the `FIXTURE:` literal would absorb a deterministic fixture defect (the capture server failing to
bind :8099) into the environment bucket, where nothing would ever act on it.

**4. The skip is counted, denominated in assertion cost, and capped.** `SKIPPED_ASSERTIONS` increments by the
number of assertions the skipped arm would have made, the floor compares `passes + fails + SKIPPED_ASSERTIONS`,
and a counted ceiling asserts `SKIPPED_ASSERTIONS <= 1` — one skip-eligible arm exists. This follows
`infra-config-apply.test.sh`, which already ships the counter, the assertion-cost denomination, the
sum-floor and a degraded-run `NOTE`. Only the ceiling is new here. Denominating in assertion cost
rather than in arms resolves the ceiling's unit ambiguity outright and is forward-compatible with
the deferred `run_case()` / `_s1_run()` extension, where one skipped case suppresses several
follow-on assertions at once.

## The carve-out this ADR adds, and the axis it turns on

ADR-181 property 4 holds that **"a decline is UNREACHABLE under CI, not merely detected"**, and
makes it so: `_diff_touches` returns true unconditionally when `CI` is set.

**This is a second carve-out on an axis ADR-181 already opened, not a reversal.** ADR-181's own
Scope paragraph already exempts one decline from CI-forcing — *"The infra runner's own pre-existing
decline is deliberately **not** forced under CI"* — justified on coverage-ownership grounds. So a
CI-reachable decline is not a new category; what this ADR owes is the rule for *when* one is
legitimate.

**The axis is contractual ownership, not computability.** An earlier draft of this ADR argued that
a decline may stay CI-reachable when its input is not computable at dispatch (the diff is knowable,
the apt archive's mood is not). That rule is refuted by the precedent this ADR leans on for its
denomination. `infra-config-apply.test.sh` declines on two inputs that are both **fully computable**,
and treats them **oppositely**:

| Decline | Computable? | Under CI | Why |
|---|---|---|---|
| pinned blob absent (shallow clone) | yes | **hard FAIL** — `elif [[ -n "${CI:-}" ]]` | CI *is* contracted to `fetch-depth: 0`; its own message says so |
| not root | yes | **SKIP (loud)**, ungated | CI is *not* contracted to run as root |

Same suite, same computability, opposite verdicts. So the discriminator is: **who owns the missing
precondition?**

| Decline | Owner of the missing precondition | Right verdict |
|---|---|---|
| relevance (ADR-181) | the harness — it *chose* not to run | force off under CI |
| docker / terraform / python3 absent (`_skip()`) | the runner, **contracted** to supply them | hard fail under CI |
| `:8099` never bound (the `FIXTURE:` test) | this harness | fail, always |
| the apt archive at that instant | **nobody** | counted skip |

Computability co-varies with ownership in the two cases the earlier draft examined, and comes apart
in the third — which is why it read as the axis and was not. Docker's absence hard-fails because CI
is contracted to provide docker, not because it is computable.

This is also why the suite's existing `_skip()` is left untouched and un-renamed: a runner without
docker is a provisioning defect against a contract, so ADR-181's logic applies to it in full.

**Category note — `SKIP` vs `INCONCLUSIVE`, considered and REJECTED (not deferred).** ADR-181's
decline means *"we chose not to run"*; this one means *"we ran and could not conclude"*. Those are
different verdict classes, and `INCONCLUSIVE` would name the second one better.

It is rejected rather than deferred, because deferring a rename past the point where the vocabulary
ships into recorded verdicts is the most expensive of the three options. The reason is not churn
cost: it is that the carve-out framing above turned out to be **correct and load-bearing**, not dead
weight. Both of its claims about ADR-181 were independently verified — ADR-181's Scope does exempt
the infra runner's decline from CI-forcing, so this genuinely is a second carve-out on an opened
axis. A rename would remove the section that records *when* a CI-reachable decline is legitimate,
which is the part a future author needs; it would not remove the question.

Recorded here so the next reader meets the decision rather than re-raising it.

## Reconciliation with AP-021 / ADR-166

AP-021 (ADR-166) holds that a message may only name a cause the job actually measured. The skip
verdict is derived from **marker absence**, which is not itself a cause. So the reason line states
what was observed — the marker did not appear — and *offers* the captured docker rc together with
its measured classes (125 = docker CLI / image pull, 100 = apt under the container's outer `set -e`,
2 = the capture-server guard) as classification. It does not assert that any of them happened. The
arm did not measure why the download failed and does not claim to.

## The counter-precedent, recorded

`git-data-rung2-rehearsal.test.sh` takes the opposite position for a superficially similar case: it
uses the doctrine sentence *"a gate that cannot run must not report success"* as a per-arm **FAIL**
detail at two sites (`fail "python3 absent — the workflow-contract arms did NOT run"`). That is a
real counter-precedent and is not being silently overridden.

It distinguishes on the same axis as the reversal above. `python3 absent` is deterministic and
locally fixable — the same input produces the same answer on every run, and a runner without python3
stays without python3 until someone acts. Failing is therefore actionable. A degraded apt archive is
transient: the identical tree passes minutes later, so a FAIL is a message no one can act on, and
its only durable effect is to train readers that a red check on this suite means nothing. That
training is the actual cost, and it is the cost ADR-180 warns about from the other direction.

## Consequences

- The required check stops flaking **in the one measured direction** — the T5 mutation arm. That is
  the whole user-visible effect, and it is deliberately narrower than "the suite stops flaking":
  `run_case()` (2 callers) and `_s1_run()` (2 callers) carry the same exposure and are explicitly
  deferred, so one of ~6 container invocations gains the verdict.
- The suite's floor moves **46 → 47** for the one new counted assertion (the ceiling). The base was
  44 when this ADR was drafted; #7501 raised it to 46 mid-flight, so the number changed while the
  increment (+1) did not — the floor is stated as a delta for exactly that reason.
- A degraded run is now legible rather than silent: the summary line reports `Skipped: N`, and a
  degraded run additionally emits a breakdown NOTE.
- **Accepted residual — no persistence bound, but a narrower hole than it first appears.** The three
  mechanical conditions bound a skip *per run*; nothing bounds it *across* runs, and ADR-181 paired
  its decline with a compensating un-gated run every six hours where this has no analogue.

  One bound does exist and is recorded here rather than left implicit: the T5 **primary** arm runs
  the identical container recipe through `run_case … want=1`. Under a genuinely degraded apt the
  container exits 100 (or 125 on an image pull) and the primary arm **FAILS** the suite. So "skips
  forever behind a green check" is not reachable by a *persistently* degraded environment — it
  requires a condition that hits only the mutant container's window while leaving the primary's
  intact. That is a much narrower hole than "nothing bounds it across runs", and it costs nothing.

  The residual that survives: the skip's only carrier is `Skipped: N` plus a NOTE on the stdout of a
  green required check — no greppable marker reaches an observability layer, and nothing counts
  across runs. The declared observation window is therefore manual: if the arm skips on more than
  1 in 20 post-merge runs, the skip is masking a persistent defect and the deferred pre-baked
  container image is owed immediately.
- **Accepted residual — the ceiling constant is not mechanically drift-proof.** Raising it is not
  detectable by any assertion that would not be text-matching the source, which is the antipattern
  this suite rejects. The mitigation is procedural and declared: the ceiling's value and derivation
  live inside the floor's itemisation comment, where this file's culture already forces review of
  any count change. This is stated rather than papered over: the file's `"four plain docker run"` comment had been
  stale since the count reached six, which is measured proof that hand-maintained numbers here
  drift silently. That comment is corrected in this PR rather than left standing as a live example.

## Alternatives Considered

- **Bounded retry on container setup** — REJECTED for now. It attacks a cause that measurement
  showed *sufficient* but never *actual*, and it would convert the most likely occurrence class from
  visible to invisible, destroying the frequency signal the marker exists to collect. Reconsider only
  if the pre-bake lands and the flake persists; it must then emit `SETUP_RETRIED attempt=N` counted
  and surfaced.
- **Pre-bake the container image** — DEFERRED, and preferred over retry when it lands. It collapses
  six apt transactions to one and makes the *healthy* path faster, where a retry makes the *degraded*
  path slower. Three in-script `docker build` precedents already exist, none pushing to a registry.
  It must carry a `[ ! -d /run/sshd ]` in-arm assertion: S1's finding depends on that directory not
  existing at runcmd time, and installing `openssh-server` at build time changes when it could
  appear.
- **Serve the tarball from a local fixture for the mutant arm only** — REJECTED. It would make the
  arm hermetic at the cost of the property that makes it faithful: the mutant reproduces the
  supply-chain defect precisely *because* it downloads the genuine tarball and then fails the
  checksum. A fixture-served tarball tests a different chain than the one that ships.
- **Lower or remove the assertion floor** — REJECTED. It gives back exactly the detectability the
  floor exists to provide, and makes a legitimate loud skip indistinguishable from an arm that
  silently stopped running — the distinction this ADR is entirely about.
