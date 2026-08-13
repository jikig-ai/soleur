---
title: A transient environment decline is reachable under CI, and must corroborate rather than infer
status: adopting
date: 2026-08-12
amends: [ADR-181]
related_adrs: [ADR-166, ADR-177, ADR-180, ADR-181]
related: [7291]
related_plans:
  - knowledge-base/project/plans/2026-08-12-fix-t5-mutation-arm-network-flake-plan.md
related_specs:
  - knowledge-base/project/specs/feat-one-shot-7291-t5-mutation-network-flake/session-state.md
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

**1. The skip corroborates; it never infers from absence.** The driver's `drive.sh` emits an
execution marker immediately above its `. /work/doppler-dl.sh` line and **below** the capture-server
guard. The verdict reads that marker, not the exit code alone. Absence of `CHMOD_RAN` plus presence
of the marker is a genuine vacuity and stays a `FAIL`; absence of both is the environment decline.
Inferring the decline from a non-zero docker rc alone would have re-created the original defect one
level up — a missing signal read as a verdict about the SUT.

**2. A missing measurement is a harness bug, never an environment skip.** A capture-integrity
precondition runs *ahead* of the verdict branch: a missing or empty `$TMP/out/stdout` alongside a
zero exit code hard-fails. This is the row that stops the fix relocating the bug it closes. The
guard's own mutation matrix drives it (row 5).

**3. The branch order is load-bearing and commented.** `CHMOD_RAN` → `FIXTURE:` → marker → else
fail. Testing the marker before `CHMOD_RAN` would skip a slow-but-successful run; testing it before
the `FIXTURE:` literal would absorb a deterministic fixture defect (the capture server failing to
bind :8099) into the environment bucket, where nothing would ever act on it.

**4. The skip is counted, denominated in assertion cost, and capped.** `SKIPPED` increments by the
number of assertions the skipped arm would have made, the floor compares `passes + fails + SKIPPED`,
and a counted ceiling asserts `SKIPPED <= 1` — one skip-eligible arm exists. This follows
`infra-config-apply.test.sh`, which already ships the counter, the assertion-cost denomination, the
sum-floor and a degraded-run `NOTE`. Only the ceiling is new here. Denominating in assertion cost
rather than in arms resolves the ceiling's unit ambiguity outright and is forward-compatible with
the deferred `run_case()` / `_s1_run()` extension, where one skipped case suppresses several
follow-on assertions at once.

## The reversal this ADR argues

ADR-181 property 4 holds that **"a decline is UNREACHABLE under CI, not merely detected"**, and
makes it so: `_diff_touches` returns true unconditionally when `CI` is set. That reasoning is sound
for the decline ADR-181 governs and does not transfer to this one.

The distinction is **what the decline is a property of**:

| | ADR-181's decline | This ADR's decline |
|---|---|---|
| Property of | the **diff** | the **network at that instant** |
| Computable in advance | yes, always | no |
| Forcing it off under CI | correct — the answer is known, so run everything | impossible — there is no flag that makes a download succeed |

A *relevance* decline is deterministic: the diff is fully known before the suite runs, so declining
is a choice, and under CI the right choice is always "run it". A *container-setup* decline is
transient: nothing computable at dispatch time determines whether the apt archive answers. Setting
`CI=true` cannot make it unreachable — it can only convert it back into the false FAIL this ADR
exists to remove. So ADR-181 property 4 is **narrowed, not overturned**: it continues to bind every
decline whose input is computable, and does not bind a decline whose input is the state of a remote
network.

This is also why the suite's existing `_skip()` is left untouched and un-renamed. It governs a
*dependency-absence* decline (docker, terraform, python3) which IS computable at dispatch, and
ADR-181's logic applies to it in full — under `CI=true` it correctly hard-fails, because a runner
missing docker is a provisioning defect, not weather.

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

- The required check stops flaking on unrelated PRs. That is the whole user-visible effect.
- The suite's floor moves 44 → 45 for the one new counted assertion (the ceiling).
- A degraded run is now legible rather than silent: the summary line reports `Skipped: N` alongside
  the resolved suite path.
- **Accepted residual — no persistence bound.** The three mechanical conditions bound a skip *per
  run*; nothing bounds it *across* runs. An arm that skips on 100% of runs forever satisfies all
  three and reports green. ADR-181 paired its decline with a compensating un-gated run every six
  hours; this ADR has no analogue and does not pretend to. The declared observation window is: if
  the arm skips on more than 1 in 20 post-merge runs, the skip is masking a persistent defect and
  the deferred pre-baked container image is owed immediately.
- **Accepted residual — the ceiling constant is not mechanically drift-proof.** Raising it is not
  detectable by any assertion that would not be text-matching the source, which is the antipattern
  this suite rejects. The mitigation is procedural and declared: the ceiling's value and derivation
  live inside the floor's itemisation comment, where this file's culture already forces review of
  any count change. This is stated rather than papered over, because the in-file `"four plain docker
  run"` comment — stale since the real count reached six — is measured proof that hand-maintained
  numbers here drift silently.

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
