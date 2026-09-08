---
title: "infra(release): ci.yml duration crossed the await-ci 3000s ceiling — every web-platform deploy is now blocked fail-closed"
type: fix
date: 2026-09-07
slug: fix-release-await-ci-ceiling-vs-ci-duration
branch: feat-one-shot-7902-awaitci-ceiling
issue: 7902
closes: 7902
priority: p1-high
domain: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

## Enhancement Summary

**Deepened on:** 2026-09-07. Four reviewers (architecture-strategist, test-design-reviewer,
code-simplicity-reviewer, spec-flow-analyzer) plus a CTO ruling and a strong-model consult.

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

**Two reversals, both driven by measurement rather than argument:**

1. The plan originally chose ADR-072's option 3 (`workflow_run`). A CTO ruling and per-job
   measurement overturned it: `test-scripts` is 89.6% of CI wall clock, and option 3 carries a
   demonstrated **fail-open** (`EXPECTED_SHA` would self-certify an un-CI'd tree). Option 3 stays
   deferred on #5806, now scoped with fourteen findings it did not previously carry.
2. Review then found the revised plan **measured the wrong quantity** and, on the strength of it,
   a **bounded ceiling raise was wrongly excluded**. Both are corrected below.

**Key corrections folded in:** the gated metric is time-to-`test`-conclusion, not run wall clock
(measured equal today, but only because `test-scripts` is the tail — the two diverge precisely when
this plan succeeds); the partition keys on the `run_suite` **label**, since ~198 suites are
hand-registered and 24 have no path at all; round-robin at the `run_suite` chokepoint makes totality
and determinism structural, deleting a whole guard; relevance-gated suites (ADR-181) mean Guard 1
must quantify over **assigned**, not executed; and `TC_RUNTIME_CEILING_S` needed no change at all.

## Overview

The `await-ci` job in the Web Platform Release workflow polls for `ci.yml`'s `test` aggregator
check-run on the merge SHA, fail-closing once a 3000s (50 minute) wall-clock ceiling elapses. CI has
outgrown that bound, so the gate now fail-closes on healthy-but-slow runs and every web-platform
deploy is skipped. The fail-closed posture is correct and is not the defect.

The plan does two things, in this order: it **raises the ceiling by a bounded amount** so production
is unblocked deterministically at merge, and it **removes the cause** by sharding the one job that
accounts for ~90% of CI wall clock, so the raised ceiling stays comfortable rather than being spent.

## Problem Statement

`await-ci` starts with essentially no head start on `ci.yml` — measured delta between its job start
and the `ci.yml` run creation is +3s to +511s (p50 ≈ +22s) across 30 runs — so its 50-minute budget
must cover CI's entire wall clock including CI's own runner queue.

**The gated quantity is time-to-`test`-conclusion, not run wall clock.** `await-ci` polls
`commits/<sha>/check-runs` for the check named `test` and `exit 0`s the moment it concludes
success (`web-platform-release.yml`, the `if [ "$status" = "completed" ]` arm). `test` needs only
`[test-webplat, test-bun, test-scripts]`. Jobs outside that closure — `e2e`, `lockfile-sync`,
`critical-css-gate`, `web-platform-build`, `grok-fidelity` — can never delay the gate.

Measured over the 22 most recent completed push runs on main
(`gh api repos/jikig-ai/soleur/actions/workflows/ci.yml/runs?branch=main&event=push&per_page=40`,
then `runs/<id>/jobs`):

| statistic | run wall clock | **time-to-`test` (the gated metric)** |
|---|---|---|
| p50 | 34.1 min | **34.1 min** |
| p90 | 49.7 min | **49.6 min** |
| max | 56.1 min | **56.1 min** |
| runs ≥ 50 min | 3 / 22 | **3 / 22** |

The two are equal to within 0.1 min in **22 of 22 runs** — but that equivalence is a *finding, not
an assumption*, and it holds only because `test-scripts` is the tail. It will break the moment this
plan works, and it breaks in the favourable direction (see the residual section).

**Where the time goes** (per-job, n=29):

| job | p50 | p90 | max |
|---|---|---|---|
| **test-scripts** | **29.93** | **35.07** | **38.98** |
| test-webplat (1/2) | 4.30 | 5.51 | 10.63 |
| e2e | 3.73 | 8.47 | 11.50 |
| test-webplat (2/2) | 3.27 | 4.68 | 9.35 |
| all 18 other jobs | ≤ 2.00 | — | ≤ 17.62 |
| test (aggregator) | 0.05 | 0.07 | 0.08 |

`test-scripts` is 7.0x the next-longest job, is the last to finish in 10/10 spot-checked runs, and a
single step inside it (`bash scripts/test-all.sh scripts`) is **p50 98.31%** of the job. Fixed
per-job overhead measures ~0.45 min.

**Runner dispatch is the second term, and it is large.** `test-scripts`'s dispatch delay (run
creation → job start) measures **p50 1.4 min, p90 12.4 min, max 21.0 min**. That gap explains the
failures: `test-scripts` maxes at 38.98 min, yet the two failed gates sat at **50.13** and **50.20**
minutes — the 3000s ceiling exactly. They are the only two runs above 42.3 min; there is no organic
failure mode, only a step function at 50 minutes. Release run `33866770160` failed while its CI run
**succeeded** in 57.40 min — a healthy commit blocked from production.

## Research Insights

**Measurement provenance.** `gh run list --workflow=ci.yml --branch=main --event=push` returned a
**stale index** (August runs). Every number here comes from the
`gh api .../workflows/ci.yml/runs?branch=main&event=push&per_page=40` form over 2026-09-03 →
2026-09-07, with per-job timings from `runs/<id>/jobs`. Re-derive with the API form.

**Established by reading code, not assumed:**

- `await-ci` gates on the `test` **check-run**, never on the ci.yml run conclusion — so the gated
  metric is time-to-`test`, and jobs outside `test`'s closure are irrelevant to it.
- The required check is the aggregator `test`. `test-scripts` appears nowhere in
  `scripts/required-checks.txt` nor in
  `scripts/ci-required-ruleset-canonical-required-status-checks.json`. `test-webplat` **already**
  carries `strategy:` and renders as `test-webplat (1/2)`, and `test` reads its rolled-up result
  today — so matrixing a shard is proven safe in this repo.
- The `test` aggregator is a colon-delimited loop over three `needs.<shard>.result` values. Matrix
  legs roll into one result; **no aggregator edit is needed**.
- **The scripts group is overwhelmingly hand-registered.** `scripts/test-all.sh` carries ~198
  imperative `run_suite` calls across three `want_scripts` blocks; exactly **one** registration is
  glob-driven (`run_suite "$f" bash "$f"` inside the `SUITE_GLOBS` loop, expanding to ~188 files).
  Roughly 24 registrations have no bash path at all (`python3 -m unittest …`, `node --test …`), so
  **there is no "suite path" to hash** — the stable key is the `run_suite` **label**, which is the
  `TEST_TIMING_LOG` key and is unique across all registrations.
- **The chokepoint is `run_suite()`**, which increments `suites` on entry. Its sibling `skip_suite()`
  also increments `suites`. Any partition filter must sit at both, or per-leg denominators diverge.
- **Relevance gating is real and large.** `_diff_touches` and `SOLEUR_INCIDENT_SKIP` decline suites
  via `skip_suite`, so *executed ⊊ registered* even in an unsharded run.
  `tests/scripts/registry-gate-mutation-battery` carries a **2,500,000 ms budget** with measured
  runs of 860,692 ms and 1,675,430 ms, and its own header calls it "about 32% of a full local run" —
  it is declined on most commits, and whichever leg owns it is ≥14 min alone when it is not.
- **ADR-133 needs no change — verified, not assumed.** `tc_acquire` short-circuits with
  `LOCK_SKIPPED_CI: CI is set; matrix shards are already isolated.` and the runtime ceiling resolves
  to `_CEILING_S=0` under `CI`, with an inline comment naming matrix shards as the reason. An earlier
  draft proposed scaling `TC_RUNTIME_CEILING_S` per leg; reading the code showed the work was
  unnecessary and would have tightened only *local* runs, which the constant's own header warns
  against.
- **B9 margin is exactly zero.** `max(release 60, await-ci 60) + migrate 30 + verify-migrations 15 +
  deploy 90 = 195`, and `DRIFT_SUSTAINED_THRESHOLD_MIN=195`. Any ceiling raise moves B9.
- `scripts/lint-orphan-test-suites.sh` already proves every tracked `*.test.sh` is registered with
  some runner across six surfaces, and invokes the runner as
  `env -u TEST_GROUP … bash "$RUNNER" --print-suite-globs`. It must not inherit `SCRIPTS_SHARD`.
- Only `lint-webplat` declares `timeout-minutes` in `ci.yml`. `ci.yml` has exactly **two** `needs:`
  edges, so `test`'s closure is exactly four jobs — not the ~23 an earlier draft implied.

**Shard-balance feasibility.** The glob-discovered set alone is 192 files
(`plugins/soleur/test/` 80, `.claude/hooks/` 48, `plugins/soleur/skills/*/test/` 29, others 35),
plus ~186 hand-registered entries — roughly 374 suites. K=3 puts ~125 on each leg, ample granularity
*except* for the one dominant relevance-gated battery noted above, which is why K is derived from
measured timings in Phase 0 rather than assumed.

**Premise validation** is in `## Premise Validation`; the Property and Cut lists are in
`## Mechanism Minimality Gate`; the option-3 reversal is in
`knowledge-base/project/specs/feat-one-shot-7902-awaitci-ceiling/decision-challenges.md`.

## Research Reconciliation — Spec vs. Codebase

| Claim | Reality (measured/verified) | Plan response |
|---|---|---|
| ci.yml "climbed to 50–54 min" | Confirmed: p90 49.6, max 56.1 on the gated metric; 3/22 ≥ 50 min | Adopted |
| `test-scripts` is the long pole | **Confirmed and stronger**: 89.6% of wall at p50, last to finish 10/10, one step 98.3% of the job | Primary target |
| Option 3 "removes the class" | Removes the ceiling, but leaves CI at ~56 min and carries a fail-open `EXPECTED_SHA` hazard | Deferred to #5806 with 14 scoping findings |
| Option 1 (raise ceiling) is a pure deferral | **Partly wrong.** It is a deferral *as the only fix*, but its cost is 12 min of drift latency on a probe whose own measured tick interval is 61–243 min. Excluding it left production blocked on a probabilistic fix | **Bundled**, bounded, in the safe order |
| Partition by hashing the suite path | **Impossible**: ~198 suites are hand-registered and ~24 have no path | Round-robin at the `run_suite` chokepoint, keyed on label |
| Guard totality = executed suites | **Wrong**: relevance gating makes executed ⊊ registered even unsharded, so the guard would red on nearly every commit | Quantify over **assigned**; assert executed = assigned − declines per leg |
| `TC_RUNTIME_CEILING_S` needs scaling | **False**: CI-exempt by design | Cut entirely |
| Post-shard tail set by `critical-css-gate` / `lockfile-sync` | **False**: neither is in `test`'s closure, so neither can delay the gate | Residual restated on the real mechanism (dispatch draws) |

## Premise Validation

- **#7902** — `OPEN`, no closing PR. `priority/p1-high`, `type/bug`, `domain/engineering`.
- **ADR-072** — `status: accepted`, read in full. Its option 3 is the issue's option 3.
- **#5806** — `OPEN`, the option-3 tracking issue. Its re-evaluation criteria fired; evaluating them
  is what this plan does, and the outcome is that they pointed at a cause they did not anticipate.
- **ADR-133 / ADR-181** — govern `test-all.sh`'s sequentiality, CI exemptions, and relevance-decline
  accounting. Both directly constrain the partition.
- **ADR ordinal** — 204 is highest on `origin/main`, but **205 and 206 are claimed on pushed
  branches** (`origin/feat-one-shot-7849-…-fixture-env-ledger-ancestry` and
  `origin/feat-one-shot-7759-net-issue-flow-filing-cites-issue`). A `main`-scoped probe reports 205
  free and is wrong. Derive across every `origin/*` ref, and re-derive before merge.

## Mechanism Minimality Gate

**Property List:**

1. A merge that passes CI reaches production without a human intervening.
2. A merge that fails CI never reaches production (fail-closed preserved).
3. Production deploys the SHA that CI validated.
4. CI's contribution to the deploy gate is bounded, and growth is visible before it consumes the gate.
5. The mechanism does not silently re-break as the suite count grows.

**Cut List:**

| Mechanism | Property | Already covered by | Disposition |
|---|---|---|---|
| Swap the release trigger to `workflow_run` | P1, P3 | P3 is held by the `#3409` `EXPECTED_SHA` gate, which the swap would break | **Cut**; deferred to #5806 |
| A superseded-SHA guard on `deploy` | P3 | `EXPECTED_SHA` already holds it | **Cut** (also rejected by ADR-072 review) |
| A new "deploy gated" alerting channel | P4 | `notify-gated` exists and is retained unchanged — this plan does not touch the release job graph | **Cut** |
| **Shard-determinism guard** | P5 | Round-robin at the `run_suite` counter is deterministic *by construction* (registration order is static source order) | **Cut** — the guard existed only because an earlier draft chose a hash |
| Scale `TC_RUNTIME_CEILING_S` | P4 | Already CI-exempt | **Cut** |
| `--list-shard-coverage` public flag | P4 | `TEST_TIMING_LOG` already records `label<TAB>elapsed_ms` for every suite including declines | **Cut** |
| Hash-mod-N partition | P5 | Round-robin at the chokepoint is total by construction *and* balances better | **Cut** |
| Per-job change detection in ci.yml | P4 | The workflow is already path-filtered | **Cut** |

Two mechanisms survive: **bound the gate's budget**, and **reduce the quantity it reacts to**.

## Proposed Solution

1. **Raise the ceiling by a bounded amount, in the safe order.** `DRIFT_SUSTAINED_THRESHOLD_MIN`
   195 → 207 first, then `CEILING_S` 3000 → 3600, then `await-ci` `timeout-minutes` 60 → 72
   (ADR-072's `timeout-minutes ≥ 1.2 × CEILING_S`). This deterministically clears today's measured
   max of 56.1 min and unblocks production at merge rather than probabilistically at AC-time.
2. **Shard `test-scripts` into a job matrix**, partitioned round-robin at the `run_suite`
   chokepoint. This is what makes the raised ceiling stay comfortable instead of being spent.
3. **Bound CI's contribution to the gate mechanically** — assert that the declared ceilings of
   `test`'s closure sum under `CEILING_S`, so the failure class cannot silently recur.
4. **Leave the release job graph otherwise untouched** — `await-ci`'s logic, `notify-gated`,
   `migrate`/`deploy` wiring all unchanged.

### Architecture Decision

**Chosen: option 2 (shard the long pole) + a bounded option 1 (raise the ceiling), together.**

**This reverses the plan's own provisional call twice**, and both reversals are recorded rather than
quietly applied.

**Why not option 3 (`workflow_run`).** ADR-072 named it the structural fix and #5806's re-evaluation
criteria fired, so it was the first choice. It was rejected on evidence:

- **It has a fail-open mode worse than the current outage.** The deploy job sets
  `EXPECTED_SHA: ${{ github.sha }}` and compares it to prod's `/health` `build_sha` — the #3409 gate
  for "right semver, wrong source tree". Under `workflow_run`, `github.sha` is the default-branch
  tip, so `EXPECTED_SHA` and the image's `BUILD_SHA` would **match each other while both being the
  un-CI'd SHA**. Today's failure is a blocked deploy; that one is an unverified deploy reporting
  success.
- **It silently disarms `live-verify`**, whose `if:` ends `github.event_name == 'push'` — a
  *blocking* dark-launch gate that would become permanently `skipped`, taking its Sentry emission
  and the #5463 soak's denominator with it.
- **A CI re-run would ship a release.** `types: [completed]` fires on `gh run rerun`, and
  `reusable-release.yml` has no already-released-this-SHA short-circuit.
- **It leaves CI at ~56 minutes**, which every PR and merge keeps paying.

**Why option 2 alone was not enough.** The first revision shipped sharding and explicitly declined
the ceiling raise, arguing it would spend drift-alert sensitivity. Review established the true cost:
`crit` moves 195 → 207, i.e. **12 minutes**, against a drift probe whose own header records measured
scheduled intervals of 61–243 minutes. Twelve minutes is inside that probe's granularity. Set
against leaving production blocked on a fix that is untestable pre-merge, the trade was inverted.
The ceiling raise is three integers, verifiable by inspection, and covers today's entire measured
distribution.

**Why the pair, in this order.** The raise is the deterministic unblock; the shard is what stops it
becoming the next incident. Shipping the raise alone repeats the pattern this repo has already
lived twice (`2026-05-07-deploy-poll-ceiling-must-track-realistic-deploy-window.md`). Shipping the
shard alone leaves production blocked until a post-merge measurement confirms it worked.

**K is derived, not assumed.** An earlier revision fixed K=3 from a p50 table while its own risk row
said to choose K against the tail. `TEST_TIMING_LOG` has been recording per-suite `elapsed_ms` all
along, and one suite (`registry-gate-mutation-battery`, measured 860s–1675s) alone floors whichever
leg owns it. Phase 0 pulls that log and picks K against the measured tail; K=3 is the provisional
starting point, not an acceptance criterion.

**Residual, restated correctly.** The earlier revision claimed `critical-css-gate` (49.1 min) and
`lockfile-sync` (40.5 min) would become the new tail and hold wall max near 53 min. That was wrong:
**neither is in `test`'s closure**, so neither can delay the gate. Post-shard, run wall clock and
time-to-`test` will *diverge*, and only the latter matters — so sharding helps the gate more than
the wall-clock projection suggested. The real residual is different and smaller: `test` waits on the
**maximum dispatch draw** across its legs, and K=3 turns one draw for `test-scripts` into three
(the run already takes a max over four draws today, so the marginal change is 4 → 6, not 1 → 3).
With measured dispatch p50 1.4 / p90 12.4 / max 21.0 min and a projected ~11-minute leg, a
pessimistic post-shard time-to-`test` lands near 30 min against a 60-minute ceiling. That is the
margin the raise exists to guarantee and the shard exists to preserve.

## Technical Approach

### Architecture

```
BEFORE                                    AFTER
  test-scripts  ~30 min, 1 dispatch draw    test-scripts (1/K) ┐
  test-webplat 1/2, 2/2  ~4 min             test-scripts (2/K) ├─> test
  test-bun  ~1 min                          test-scripts (3/K) ┤    (aggregator
                                            test-webplat 1/2,2/2│     unchanged)
  time-to-test p50 34.1 / p90 49.6 / max 56.1                  ┘
  ceiling 3000s ..................... crossed
                                            time-to-test ~11 min + max dispatch draw
                                            ceiling 3600s ..... comfortable
```

### Implementation Phases

Contract before consumer, and unblock before optimise.

#### Phase 0: Derive K from data that already exists

- Pull `TEST_TIMING_LOG` from one full scripts-group run. Report the per-suite duration
  distribution and the single longest suite — that value is the floor no K can beat.
- Choose K against the tail. K=3 is provisional.
- Record the baseline gated metric (time-to-`test` p50 34.1 / p90 49.6 / max 56.1).

#### Phase 1: Bounded ceiling raise (the deterministic unblock), in the safe order

- `scripts/prod-version-drift-check.sh`: `DRIFT_SUSTAINED_THRESHOLD_MIN` 195 → 207, updating the
  derivation comment so the arithmetic in the file matches the ceilings in the file.
- `.github/workflows/web-platform-release.yml`: `CEILING_S` 3000 → 3600 and `await-ci`
  `timeout-minutes` 60 → 72, preserving ADR-072's `timeout-minutes ≥ 1.2 × CEILING_S` invariant and
  its wall-clock-keyed ceiling. Name what the new ceiling bounds, per
  `2026-05-05-defense-relaxation-must-name-new-ceiling.md`: it bounds *CI liveness*, and it is
  sized above the measured max of 56.1 min — not above p50.
- Order is load-bearing: the threshold must move **before** the ceilings, or B9 reds in between.

#### Phase 2: Round-robin partition at the `run_suite` chokepoint

- Add `SCRIPTS_SHARD=k/N`. Filter inside `run_suite()` **before** `suites=$((suites + 1))`, and
  mirror the identical filter into `skip_suite()` — both increment `suites`, so filtering only one
  makes per-leg denominators and the epilogue's decline accounting disagree.
- Partition **round-robin on the registration counter** (`(( (n - 1) % N == k - 1 ))`), keyed on the
  `run_suite` **label**. This is total and deterministic *by construction*: every suite passes the
  chokepoint exactly once, and registration order is static source order. It also balances better
  than a hash, which cannot be steered by the timing data Phase 0 produces.
- A shard non-selection is **not** a relevance decline and **not** a runtime-ceiling decline: it must
  not increment `skipped`, must not reach the `_ceiling_declined` accounting, and must not push the
  leg toward ADR-181's `exit 3 (UNRESOLVED)`. State this explicitly — getting it wrong either makes
  every leg exit 3 or reproduces the defect ADR-181 closed.
- Malformed `SCRIPTS_SHARD` (`0/3`, `4/3`, `1/0`, `abc`, empty) **fails closed with exit 2**,
  following the existing `TEST_GROUP` validation precedent. Falling back to the full group would
  hide the bug; falling back to empty is the green-on-zero-coverage catastrophe.
- Unset/empty runs the full group, so local runs, lefthook, `work`/`ship`, and
  `main-health-monitor.yml`'s `TEST_GROUP=all` are unaffected. The filter keys on `SCRIPTS_SHARD`
  presence, never on `TEST_GROUP == scripts`.
- Add an **enumerate mode** that records registrations without executing them, handled in the same
  early block as `--print-suite-globs` (before `TMPDIR` export, the bare-repo guard, `TEST_GROUP`
  validation and `tc_acquire` — a path that blocks on the advisory lock deadlocks the gate on
  itself). Guard 1 consumes it.
- `scripts/lint-orphan-test-suites.sh` invokes the runner and runs *inside* the scripts group, so it
  would inherit an exported `SCRIPTS_SHARD`. Extend its `env -u TEST_GROUP` to
  `env -u TEST_GROUP -u SCRIPTS_SHARD` and widen the matching assertion in its companion suite.

#### Phase 3: Matrix the job

- Add `strategy: {fail-fast: false, matrix: {shard: [...]}}` to `ci.yml`'s `test-scripts`; pass
  `SCRIPTS_SHARD: ${{ matrix.shard }}` via `env:`. Note the group is still passed **positionally**
  (`bash scripts/test-all.sh scripts`) — the two mechanisms sit side by side; comment why.
- Keep the job key literally `test-scripts` so `needs.test-scripts.result` and the required-check
  contract are untouched.
- No leg may carry `continue-on-error`, which would make the rolled-up result report success while
  a leg failed.
- Keep every leg's runtime profile identical — same gitleaks and likec4 pins, no
  `setup-node`/`setup-bun` version pin (many suites assert the shard has no bun and no node).
- Re-run `plugins/soleur/test/scripts-shard-runtime-coverage.test.sh`: its extractor anchors on
  2-space `^  [a-z…]:$` and `strategy:` is indented 4 spaces, so it should survive — verify rather than
  assume. Re-run `required-checks-canonical-parity.test.sh` for gitleaks pin parity now that one
  install site is a matrix.

#### Phase 4: Guards

Implement Guards 1 and 2 (contracts below), written before the code they guard.

#### Phase 5: Architecture records

Amend ADR-072, author the new ADR, update and re-arm #5806. See below.

## Alternative Approaches Considered

| Approach | Verdict | Why |
|---|---|---|
| `workflow_run` trigger (option 3) | Deferred to #5806 | Fail-open `EXPECTED_SHA`; disarms `live-verify`; CI re-run would ship a release; untestable pre-merge; leaves CI at 56 min |
| Ceiling raise **alone** | Rejected | A pure deferral; this repo has raised-and-rebroken ceilings twice |
| Sharding **alone** | Rejected | Leaves production blocked until a post-merge measurement confirms it worked |
| Hash-mod-N over suite path | Rejected | ~198 suites are hand-registered and ~24 have no path; and a hash cannot be steered by measured durations |
| Checked-in shard balance manifest | Rejected for **totality**, available for **balance** | Totality must be structural; a timing table may inform ordering, where staleness costs minutes, never coverage |
| In-process parallelism in `test-all.sh` | Rejected | ADR-133: tmpfs contention + a Bun FPE crash |
| A shard-determinism guard | Cut | Round-robin at the chokepoint is deterministic by construction |
| K=4+ | Rejected pending Phase 0 | Each leg adds a dispatch draw to a pool measurement shows is contended |

## Architecture Decision (ADR/C4)

### ADR

- **Create ADR-208** (ordinal RESOLVED at implementation time; the plan's provisional 207 was
  claimed mid-session by `origin/feat-one-shot-7795-tag-shared-store-softening`, which is exactly
  why the plan said to re-derive across every `origin/*` ref rather than a `main`-scoped probe; a
  `main`-scoped probe is wrong — derive across every `origin/*` ref and re-derive before merge) —
  *"CI's contribution to the deploy gate is a declared, bounded budget."* The decision is the new
  cross-file coupling and its invariant: the declared ceilings of `test`'s closure must sum under
  `CEILING_S`, so the gate cannot be silently outgrown again.
- **Amend ADR-072 — amend, not supersede.** Its Decision items 1–3, 5, 6 and all its named
  invariants survive; only item 4's *sizing premise* ("sized above the observed p100 … ~28m,
  measured 2026-06-30") is falsified. Record the re-measurement, the new ceiling, and — the durable
  lesson — that the original premise was itself stated in **run wall-clock** terms, a quantity the
  gate does not measure. Correct the record on option 1: its rejection was pre-adaptive-wait and no
  longer stands on that ground.
- **Update #5806, do not close it.** Record that criteria 1 and 3 fired and were evaluated, with the
  outcome *root cause was an unsharded job, not irreducible CI cost*. Re-arm with a criterion keyed
  to the **gated metric**: *post-shard time-to-`test` p100 on main exceeds 60% of `CEILING_S`*. The
  fourteen scoping findings this plan's research produced — the `EXPECTED_SHA` fail-open, the
  out-of-order prod-rollback, the `live-verify` disarm and its `github.event.before` trap, the CI
  re-run release, the four bare checkouts, the `release-outcome` rewiring, the gate widening from
  the `test` check-run to the whole run conclusion, the `github.sha`-equivalent surfaces
  (`$GITHUB_SHA`, `docker/metadata-action` `type=sha`, `concurrency: github.ref`), the
  verifier-not-deletion shape, the missing `gh release create --target`, the stale ship-skill and
  learning docs, the absent `paths` filter, and the non-recursion confirmation — belong **on the
  issue**, not duplicated here.

### C4 views

Checked against all three of
`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}` by enumerating
actors, systems, containers and access relationships rather than grepping the feature's noun:

- **External human actors:** none added or removed — the change is machine-to-machine within CI.
- **External systems:** none added; the set this pipeline touches is unchanged. Only the internal
  job layout of one workflow and two integer constants change, below the `github` system boundary.
- **Containers / data stores:** none added or removed.
- **Access relationships:** unchanged in actor, direction and technology.
- **Edges re-read for continued truth:** `model.c4` `github -> webapp` describes the drift probe as
  "alerting only on staleness sustained past one release cycle". Phase 1 lengthens that cycle by 12
  minutes; the prose carries no number, so it stays accurate — confirm the wording during
  implementation. `github -> sentry` is unaffected: `ci.yml` uses no `sentry-heartbeat` composite.
- **Derived cardinalities:** `bash plugins/soleur/test/c4-count-parity.test.sh` passed **10/10** at
  plan time. Gated counts are sentry-heartbeat emitters (11/6/5), cron monitors (56/12/44) and
  Resend emitters (13). Verified: `grep -rln actions/sentry-heartbeat .github/workflows/` returns 11
  files and **`ci.yml` is not among them**; no gated count moves. Re-run in AC.

**Conclusion: no `.c4` edit is required**, on the enumeration above plus a green parity run.

### Sequencing

Both records ship in this PR; nothing is deferred behind a soak.

## User-Brand Impact

- **If this lands broken, the user experiences:** a required CI check reporting green while running
  only a subset of the suite — a regression reaching `app.soleur.ai` behind a green pipeline. This
  is the shard-totality failure mode, and it is strictly worse than today's blocked deploy, which is
  why Guard 1 is the plan's highest-priority deliverable and why the partition is made total by
  construction rather than by assertion alone.
- **If this leaks, the user's data is exposed via:** no new data path is created. The residual
  exposure is indirect — the scripts group contains security and credential-path gates, so a dropped
  suite could let untested data-handling code ship behind a green check.
- **Brand-survival threshold:** `single-user incident`

## Observability

```yaml
liveness_signal:
  what: "the required `test` aggregator check-run on every push and PR — the same check-run await-ci gates on — backed by declared per-job ceilings whose sum is asserted under CEILING_S; plus scheduled-prod-version-drift.yml reading prod /health build_sha"
  cadence: "per push and per pull_request for CI; nominally every 30 minutes for the drift probe (measured delivered interval 61-243 min)"
  alert_target: "GitHub required-check failure on the offending PR; Sentry cron monitor -> operator email for the drift probe; main-health-monitor.yml files a P1 ci/main-broken issue; notify-gated posts to Slack on a fail-closed await-ci"
  configured_in: ".github/workflows/ci.yml, .github/workflows/web-platform-release.yml, .github/workflows/scheduled-prod-version-drift.yml, scripts/prod-version-drift-check.sh"

error_reporting:
  destination: "GitHub Actions check-run status for CI; Sentry cron monitors for the scheduled probes"
  fail_loud: "await-ci emits an ::error:: naming the elapsed seconds and the ceiling before fail-closing, and notify-gated converts that into a Slack push; prod-version-drift-check.sh reports prod build_sha lagging past DRIFT_SUSTAINED_THRESHOLD_MIN"

failure_modes:
  - mode: "a shard partition drops suites, so the required `test` check passes on a subset"
    detection: "Guard 1 compares the union of the legs' ASSIGNED registrations against an independently derived registration set, in CI against the real tree"
    alert_route: "required `test` check fails on the offending PR"
  - mode: "a leg loses its SCRIPTS_SHARD env and silently runs the full group, hiding the benefit while still reporting green"
    detection: "each leg echoes its resolved k/N and the guard asserts N distinct values across N legs; malformed or absent values fail closed with exit 2 under CI"
    alert_route: "required `test` check fails on the offending PR"
  - mode: "CI's declared budget grows back past what the deploy gate can absorb"
    # SUPERSEDED 2026-09-08 (QA). This entry named Guard 2, which was DELETED on the CTO ruling
    # recorded in the Correction stanza and in ADR-208: arithmetic over DECLARED job ceilings
    # omits the concurrency-queue term, so it is green on configurations the gate cannot absorb.
    # Leaving the old text would have left the sharpest hazard reading as mitigated by a control
    # that does not exist. What actually detects this is the gate measuring its OWN quantity.
    detection: "await-ci emits a ::warning:: at 0.7 x CEILING_S keyed on time-to-`test` INCLUDING ci.yml's concurrency queue, exported as the soft_breach job output and consumed by notify-slow-ci; plugins/soleur/test/await-ci-ceiling-invariants.test.sh holds the constants in their declared relationships (ADR-072 #7, MAX_ATTEMPTS x INTERVAL_S == CEILING_S) and asserts soft_breach still has a consumer"
    alert_route: "Slack push from notify-slow-ci one release BEFORE the gate fail-closes; required `test` check fails on a PR that breaks a constant relationship"
  - mode: "ci.yml exceeds the raised ceiling anyway, on a queue-delayed run (mechanism corrected — see the Correction stanza)"
    detection: "await-ci emits its wall-clock ::error:: and notify-gated posts to Slack; the re-armed #5806 criterion is keyed to post-shard time-to-test p100"
    alert_route: "Slack push + red required job, within one release cycle"

logs:
  where: "GitHub Actions run logs per matrix leg; TEST_TIMING_LOG per run for per-suite durations; Sentry cron monitor check-in history"
  retention: "GitHub Actions logs 90 days; Sentry per project retention"

discoverability_test:
  command: "curl -fsS https://app.soleur.ai/health"
  expected_output: "HTTP 200 with a JSON body whose build_sha is a 40-hex commit present in origin/main's history — i.e. production is running a commit CI validated"
```

## Guard Contract

### Guard 1 — Shard totality

**Property.** Every suite registered for the scripts group is **assigned to exactly one** matrix
leg, so the union of the legs' assigned sets equals the full registration set with no gaps and no
duplicates.

**Assembly.** The chokepoint is `run_suite()` in `scripts/test-all.sh` — every scripts-group suite
passes through it exactly once — together with its sibling `skip_suite()`, which shares the `suites`
counter and must carry the identical filter. The guard quantifies over the **registration set**
produced by the new enumerate mode, keyed on the `run_suite` **label** (unique across all
registrations, and already the `TEST_TIMING_LOG` key) rather than on a path, because ~198
registrations are hand-written imperative statements and ~24 name no path at all.

The property is over **assigned**, never **executed**: ADR-181 relevance gating means executed ⊊
registered even in an unsharded run, so an executed-set comparison would red on nearly every commit.
Per-leg, the guard separately asserts `executed = assigned − declines`, with each decline carrying
its recorded reason.

**The reference set must be derived independently of the partition.** Deriving it by invoking the
partition with `K=1` makes the union comparison true by construction for any partition that is a
function of the enumeration — the guard would then be a checksum, green on exactly the dropped-suite
case it exists to catch. It is derived instead by static extraction of `run_suite` registrations
plus `--print-suite-globs` expansion, mirroring the extractor
`scripts/lint-orphan-test-suites.sh` already implements. That existing lint proves a suite is
**registered with some runner**; Guard 1 proves a registered suite is **assigned to exactly one
leg**. The two are adjacent and neither subsumes the other.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Off-by-one in the partition so one registration maps to no leg | RED |
| 2 | Make the enumerate mode return nothing — a guard reporting "0 checked" and exiting 0 is vacuous | RED |
| 3 | Add a **second** registration after a compliant first and assign it to no leg | RED |
| 4 | Make two legs both claim the same label (union correct, multiset wrong) | RED |
| 5 | Set `ci.yml`'s leg count to 2 while the partition still computes mod 3 — leg 3's suites run nowhere and both surviving legs are green | RED |
| 6 | Derive the reference set by calling the partition with `K=1` (the tautology stub) — rows 1/3/5 must not silently pass | RED |
| 7 | Filter in `run_suite` but not in `skip_suite`, so per-leg denominators diverge | RED |
| 8 | Malformed `SCRIPTS_SHARD` (`0/3`, `4/3`, `1/0`, `abc`) falls back to running nothing | RED |

**Harness rows.** Deleting the union-comparison assertion while leaving the guard's iteration must
drive the suite RED. Each mutation must be **line-range-scoped to the target block and its placement
asserted** — `scripts/test-all.sh` is ~2400 lines with ~198 near-identical `run_suite` lines, so a
file-wide `sed` without `/g` silently rewrites a different group's suite and the guard reports a
baseline that is indistinguishable from a pass. Must-PASS non-canonical inputs: a **different valid
K** must PASS (totality is required for any K, not only the configured one), and a **reordered
registration set** must PASS.

### Guard 2 — CI's declared budget is bounded by the deploy gate's ceiling — **REJECTED, NOT SHIPPED**

> **Superseded 2026-09-08 (QA, #7902).** This guard was built and mutation-proven at 10/10, then
> DELETED on the CTO ruling recorded in the Correction stanza and in ADR-208. The design below is
> retained verbatim as the **rejected** design so it is not re-proposed — that is the whole reason
> the section still exists. Do not read anything under this heading as describing shipped code.
>
> **Why it was rejected.** Declared job ceilings bound *execution* only. The quantity the deploy
> gate actually gates is time-to-`test`, which additionally includes `ci.yml`'s own concurrency
> queue (measured 6–21 min; see the Correction stanza). Arithmetic over declared ceilings omits
> that term entirely, so this guard is **green on precisely the configurations the gate cannot
> absorb** — and no headroom factor repairs a missing term. It would have read as a mitigation for
> the plan's sharpest hazard while guarding nothing.
>
> **What ships instead**, splitting the property in two along what each layer can actually measure:
>
> 1. The **quantity** is measured by the gate itself — a `::warning::` at `0.7 x CEILING_S` inside
>    `await-ci`, keyed on elapsed time-to-`test` with the queue included, exported as the
>    `soft_breach` job output and consumed by `notify-slow-ci`. It fires one release *before* a
>    fail-closed deploy rather than after.
> 2. The **constant relationships** are held by
>    `plugins/soleur/test/await-ci-ceiling-invariants.test.sh` (added at QA): ADR-072 invariant #7
>    (`timeout-minutes * 60 >= 1.2 x CEILING_S`), `MAX_ATTEMPTS x INTERVAL_S == CEILING_S`, the soft
>    ceiling being derived rather than restated, and `soft_breach` still having a consumer. Four
>    invariants, each driven RED by its own mutation, plus a control, a MUSTPASS row and an
>    instrument self-test — 10/10. Both relationships ship **exactly tight** (4320 >= 4320,
>    360 x 10 == 3600), so there is no slack to absorb a one-sided edit; before this suite both
>    were unenforced prose in a workflow comment.
>
> Note that `scripts/lint-guard-contract.py` passes on this section either way: it resolves plan
> *entries*, not guard *implementations*. It cannot tell a shipped guard from a described one.

**Property.** The declared execution ceilings of `test`'s `needs`-closure, plus `test`'s own,
sum under the deploy gate's `CEILING_S` — so CI cannot be grown past what the gate can absorb
without a check going red at the moment of divergence.

**Assembly.** Two files, resolved rather than restated: the `needs`-closure of `test` recomputed
from `.github/workflows/ci.yml`'s graph (today exactly `test-webplat`, `test-bun`, `test-scripts`,
`test`, plus the matrix legs), and `CEILING_S` read out of
`.github/workflows/web-platform-release.yml`. This mirrors the resolve-don't-hardcode discipline B8
already applies to the callee release ceiling. A **pinned closure string** accompanies the derived
walk — B8e's shape — because a guard that derives membership from the graph is definitionally green
after a graph edit, and the graph edit is exactly how a job leaves the guarded set while still
gating the deploy.

This guard replaces an earlier "every job declares a timeout" formulation, which was satisfiable by
declaring `timeout-minutes: 360` — GitHub's own default, i.e. today's behaviour written down.
Presence without a bound is not a budget.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove `timeout-minutes` from `test-scripts` (absence must read as the 360 default, not as zero) | RED |
| 2 | Make the graph walk return an empty job set — reporting "0 checked" and exiting 0 is vacuous | RED |
| 3 | Add a **second** job to `test`'s `needs` after a compliant first, without a ceiling | RED |
| 4 | Raise a closure ceiling so the sum exceeds `CEILING_S/60` | RED |
| 5 | Lower `CEILING_S` in `web-platform-release.yml` without lowering the closure ceilings | RED |
| 6 | Remove a `needs` edge so a job leaves the derived set while still gating the deploy — the pinned closure string must catch it | RED |
| 7 | Replace the resolved `CEILING_S` read with a hardcoded literal that drifts from the workflow | RED |

**Harness rows.** Deleting the sum comparison while keeping the per-job iteration must drive the
suite RED. Must-PASS non-canonical input: raising a closure ceiling **and** `CEILING_S` together, by
different amounts, must PASS — the contract permits any sum under the ceiling, not a specific set of
values.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open --limit 200` returned 63 open issues; none
reference `.github/workflows/ci.yml`, `.github/workflows/web-platform-release.yml`,
`scripts/test-all.sh`, `scripts/prod-version-drift-check.sh`,
`scripts/prod-version-drift-check.test.sh`, `scripts/lint-orphan-test-suites.sh`, or `ADR-072`.

## Files to Edit

- `scripts/prod-version-drift-check.sh` — `DRIFT_SUSTAINED_THRESHOLD_MIN` 195 → 207 and its
  derivation comment.
- `.github/workflows/web-platform-release.yml` — `CEILING_S` 3000 → 3600, `await-ci`
  `timeout-minutes` 60 → 72, and the anti-regression comment naming what the new ceiling bounds.
  Nothing else in this file changes.
- `scripts/test-all.sh` — `SCRIPTS_SHARD` round-robin filter in `run_suite` and `skip_suite`;
  enumerate mode in the early pre-side-effect block; malformed-value validation.
- `.github/workflows/ci.yml` — matrix on `test-scripts`; declared `timeout-minutes` on `test`'s
  closure.
- `scripts/lint-orphan-test-suites.sh` — `env -u TEST_GROUP -u SCRIPTS_SHARD`.
- `scripts/lint-orphan-test-suites.test.sh` — widen the assertion that pins that invocation.
- `plugins/soleur/test/scripts-shard-runtime-coverage.test.sh` — re-verify the job-block extractor
  against a job carrying `strategy:`; assert profile identity across legs.
- `plugins/soleur/test/required-checks-canonical-parity.test.sh` — gitleaks pin parity with one
  install site now a matrix.
- `scripts/prod-version-drift-check.test.sh` — B9 must stay green with the new threshold and
  ceilings; B8e's pinned closure is unchanged (no release job is added or removed).
- `knowledge-base/engineering/architecture/decisions/ADR-072-adaptive-ci-signal-wait-for-deploy-gate.md`
  — amend.

## Files to Create

- `knowledge-base/engineering/architecture/decisions/ADR-208-deploy-gate-measures-its-own-gated-quantity.md`
  (ordinal provisional).
- Guard 1 suite (shard totality) and Guard 2 suite (CI budget bounded by `CEILING_S`).

## Acceptance Criteria

### Pre-merge (PR)

- [x] AC1 — `CEILING_S` is `3600`, `await-ci` `timeout-minutes` is `72`, and
      `timeout-minutes*60 >= 1.2 * CEILING_S` holds (ADR-072 invariant #7).
- [x] AC2 — `DRIFT_SUSTAINED_THRESHOLD_MIN` is `207`, and `bash scripts/prod-version-drift-check.test.sh`
      passes with B9 green — proving the threshold moved before/with the ceilings, never after.
- [x] AC3 — **CORRECTED 2026-09-08 (QA).** As written ("touches only the two constants and their
      comment") this was false of what shipped, and ticking it would have certified a narrower diff
      than exists. `web-platform-release.yml` also gains the soft-ceiling early warning derived from
      `CEILING_S`, the `soft_breach`/`soft_elapsed_s` job outputs, `id: await`, and the
      `notify-slow-ci` consumer — the replacement for the rejected Guard 2. What the AC was
      protecting **does** hold and is what is now asserted: `await-ci`'s poll/verdict logic,
      `notify-gated`, and the `migrate`/`deploy` `needs`/`if` wiring are unchanged; every addition
      is additive and none alters the gate's pass/fail decision.
- [x] AC4 — `ci.yml`'s `test-scripts` declares `strategy.matrix` with `fail-fast: false`, the job
      key is still literally `test-scripts`, and no leg carries `continue-on-error`.
- [x] AC5 — **CORRECTED 2026-09-08 (QA).** Measured: the `test:` block is NOT byte-unchanged — it
      gains `timeout-minutes: 10` and its comment (41 -> 48 lines), so the AC as written was false.
      The property it existed to prove is verified and holds: the `needs:` list, the `if:`, and the
      aggregation loop are byte-identical to `origin/main`, which is what shows matrix legs roll up
      into ONE `needs.test-scripts.result` with no aggregator edit.
- [x] AC6 — `scripts/required-checks.txt` is unmodified; `grep -c '^test-scripts$'` is `0` and
      `grep -c '^test$'` is `1`. GitHub renders a matrix leg as `test-scripts (1/3)`, so this is
      what makes matrixing safe for branch protection.
- [x] AC7 — K is justified in the plan/PR by the Phase 0 `TEST_TIMING_LOG` measurement, naming the
      longest single suite (the floor no K can beat).
- [x] AC8 — `SCRIPTS_SHARD` unset runs the full group: `bash scripts/test-all.sh scripts` locally
      and `TEST_GROUP=all` in `main-health-monitor.yml` behave exactly as before.
- [x] AC9 — malformed `SCRIPTS_SHARD` (`0/3`, `4/3`, `1/0`, `abc`, empty-after-trim) exits `2`,
      following the `TEST_GROUP` validation precedent — never a silent full-group or empty run.
- [x] AC10 — each leg echoes its resolved `k/N`, and the values across legs are N distinct entries;
      a leg that lost its `env:` is detected rather than passing green on the full group.
- [ ] AC11 — the enumerate mode and the executing pass emit **identical label sequences** with
      `SCRIPTS_SHARD` unset. Without this the enumerate pass and the partition can agree while
      neither matches what CI runs.
- [x] AC12 — Guard 1 drives RED on every mutation row, each line-range-scoped with its placement
      asserted, and PASSes on its declared non-canonical inputs. Measured **13/13** on the shipping
      battery (`scripts-shard-totality-mutations.sh`), not the eight this AC originally projected:
      ROW9 (a leg assigned 0 registrations) and ROW10 (a collation-widened, unbounded digit class)
      were added after review found both were live false-green paths, plus a control, a harness row,
      the K=1-tautology row and a MUSTPASS row.
- [x] AC13 — ~~Guard 2 drives RED on each of its seven mutation rows~~ **SUPERSEDED 2026-09-08**:
      Guard 2 was deleted (Correction stanza / ADR-208). Discharged instead by
      `plugins/soleur/test/await-ci-ceiling-invariants.test.sh` — 10/10, four invariants each
      driven RED by its own mutation, one MUSTPASS row proving the assertions are not over-broad,
      plus a control and an instrument self-test.
- [x] AC14 — Guard 1 runs in CI against the real tree from a job that can observe **all** legs
      (a non-sharded job invoking the enumerate mode K times, or a join job over uploaded per-leg
      artifacts) — a guard running inside one leg cannot see a cross-leg union.
- [ ] AC15 — a shard non-selection does not increment `skipped`, does not reach `_ceiling_declined`
      accounting, and does not push a leg to ADR-181's `exit 3`.
- [x] AC16 — `bash scripts/lint-orphan-test-suites.test.sh` passes with the widened
      `env -u TEST_GROUP -u SCRIPTS_SHARD` assertion.
- [x] AC17 — `bash plugins/soleur/test/scripts-shard-runtime-coverage.test.sh` and
      `bash plugins/soleur/test/required-checks-canonical-parity.test.sh` pass.
- [x] AC18 — `bash plugins/soleur/test/c4-count-parity.test.sh` passes (10/10).
- [x] AC19 — `actionlint` is clean on both edited workflows and each edited `run:` snippet passes
      `bash -c` extraction. `bash -n` is **not** run against workflow YAML.
- [x] AC20 — ADR-208 exists with `status: accepted`; ADR-072 is **amended, not superseded** (its
      `status:` stays `accepted`), carries the re-measurement, and records that item 4's premise was
      stated in run-wall-clock terms — a quantity the gate does not measure.
- [x] AC21 — the ADR ordinal is free across every `origin/*` ref, re-verified immediately before
      merge; if renumbered, `grep -rn 'ADR-<old>' knowledge-base/project/{plans,specs}/` finds no
      stale reference in this feature's own artifacts.
- [x] AC22 — #5806 is updated with the evaluation outcome, the fourteen scoping findings, and the
      re-armed criterion keyed to **time-to-`test`**, and is **not** closed.
- [x] AC23 — `python3 scripts/lint-guard-contract.py` resolves both guard entries;
      `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` is clean.
- [ ] AC24 — the PR body uses `Closes #7902` and `Ref #5806` (never `Closes #5806`).

### QA pass — 2026-09-08

Executed the Test Scenarios above as shell checks (18/18), Guard 1 (15/15), the shard-totality
mutation battery (13/13), the drift suite (151/151), the orphan lint (68/68), the parity suites,
`bun test` on the merge gate (11/11), and the new `await-ci-ceiling-invariants` guard (10/10).

Four things the pass changed rather than merely recorded:

1. **The `failure_modes` block and the Guard Contract both named Guard 2**, which was deleted on
   the CTO ruling. The plan's sharpest hazard read as mitigated by a control that does not exist,
   and `lint-guard-contract.py` cannot catch this — it resolves plan *entries*, not guard
   *implementations*. Both corrected; the rejected design is retained under an explicit
   REJECTED heading so it is not re-proposed.
2. **AC3 and AC5 were literally false as written** and would have been ticked as-is. Corrected to
   what shipped, with the property each actually protects stated and verified.
3. **Nothing enforced the await-ci constant relationships.** ADR-072 invariant #7 and
   "MAX_ATTEMPTS moves with CEILING_S" were unenforced prose in a workflow comment — and #7902's
   own plan is the proof that such prose does not hold (it omitted MAX_ATTEMPTS, which would have
   bought 60s instead of 10 min). Both relationships ship exactly tight, so there is no slack for
   a one-sided edit. Added `plugins/soleur/test/await-ci-ceiling-invariants.test.sh`.
4. **Adding that suite invalidated the K table by its own stated rule** (375 -> 376; the floor
   suite keeps its leg, but 187 of 375 suites move legs). Rather than re-simulate an order the
   next added suite invalidates again, ci.yml now also records an order-independent bound: the
   whole group is 2115s, so any leg of any partition plus the worst 1260s queue is 3375s, inside
   the 3600s ceiling. Safety no longer depends on the table.

**Deferred to the full battery, not failed:** AC11 (enumerate vs executing label sequences) and
AC15 (a shard non-selection touching neither `skipped`, `_ceiling_declined`, nor ADR-181's
`exit 3`) both need a real EXECUTING run. `test-all.sh` correctly refused with rc=4 — sibling
full-gate runs were in flight in other worktrees — and overriding would have corrupted their
measurements and mine. AC15 is verified structurally in the meantime: `exit 3` is driven only by
`killed` and `_ceiling_declined`, and `_shard_selects` returns before `skip_suite` increments
`skipped`, so a non-selection cannot reach any of the three.

### Post-merge (automated)

- [ ] AC25 — the first `ci.yml` run on main after merge completes with all legs green, and
      **time-to-`test`** (the `test` job's `completed_at` minus the run's `created_at`) is below
      25 min, evaluated over the first 3 runs rather than one — a single queue-delayed run (mechanism corrected — see the Correction stanza)
      legitimately exceeds any single-run bound. Verified via
      `gh api repos/jikig-ai/soleur/actions/runs/<id>/jobs`.
- [ ] AC26 — a deploy of current `main` is dispatched via
      `gh workflow run web-platform-release.yml -f bump_type=patch`, and
      `curl -fsS https://app.soleur.ai/health` reports a `build_sha` matching the deployed commit.
      A `gh`-CLI step the ship phase runs, not a handoff.
- [ ] AC27 — post-shard time-to-`test` p100 over the following 10 main runs is recorded on #5806 and
      the re-armed criterion evaluated against it. This is a soak, tracked on the issue.

## Test Scenarios

### Acceptance Tests (RED phase targets)

- Given `SCRIPTS_SHARD=1/3`, when `test-all.sh scripts` runs, then it executes a strict subset and
  emits exactly that subset's labels.
- Given all legs' emitted label sets, when unioned, then the result equals the independently derived
  registration set, with no duplicates.
- Given `SCRIPTS_SHARD` unset, when `test-all.sh scripts` runs, then it executes the full group and
  emits the same label sequence as the enumerate mode.
- Given `SCRIPTS_SHARD=4/3`, when the runner starts, then it exits `2` without running any suite.
- Given a relevance-declined suite, when its leg runs, then the suite is counted as assigned,
  reported as declined with its reason, and the leg does not exit `3` on that account.
- ~~Given a closure ceiling raised past `CEILING_S/60`, when Guard 2 runs, then it fails.~~
  **WITHDRAWN 2026-09-08 (QA)** — Guard 2 was deleted on the CTO ruling (see the Correction
  stanza); a scenario for a control that does not ship cannot be run, and leaving it listed made
  the QA pass look more complete than it was. Replaced by: given `timeout-minutes` lowered below
  `1.2 x CEILING_S`, or `MAX_ATTEMPTS` left behind while `CEILING_S` rises, or `soft_breach`
  losing its consumer, when `await-ci-ceiling-invariants.test.sh` runs, then it fails — all four
  mutation-proven.

### Regression Tests

- Given the b551bdc1a shape — time-to-`test` of 51.6 min — when the raised ceiling is in effect,
  then `await-ci` concludes success rather than fail-closing at 50 min.
- Given `test-scripts` failing in one leg only, when the aggregator evaluates, then
  `needs.test-scripts.result` is not `success` and the required check fails.
- Given a leg whose `SCRIPTS_SHARD` env was dropped, when it runs the full group, then the distinct
  `k/N` assertion fails rather than the run reporting green.

### Edge Cases

- Given a newly added scripts-group suite, when CI runs, then it is assigned to exactly one leg and
  Guard 1 stays green with no manifest edit.
- Given `ci.yml` reduced from 3 legs to 2 while the partition still computes mod 3, when Guard 1
  runs, then it fails on the orphaned leg's suites.
- Given a run queued behind its predecessor on ci.yml's concurrency group (measured 6-21 min), when
  that queue is added to the post-shard critical path, then time-to-`test` still lands under the
  3600s ceiling — the margin the raise exists to provide. (Mechanism corrected: see the Correction
  stanza. The original wording said "dispatch delays a leg", which does not happen — the queue is
  per-RUN and delays every job in it equally.)

## Risk Analysis & Mitigation

| Risk | Severity | Mitigation |
|---|---|---|
| Shard partition drops suites → required check green on a subset | **High** | Totality is structural (round-robin at the chokepoint), *and* Guard 1 asserts it against an independently derived reference set in CI against the real tree (AC12, AC14) |
| Guard 1's reference set derived from the partition itself → tautology | **High** | Explicit mutation row 6; reference derived by static extraction + `--print-suite-globs` |
| A leg silently runs the full group after losing its env | Medium | Distinct `k/N` assertion across legs (AC10); malformed values fail closed (AC9) |
| One dominant suite floors a leg regardless of K | Medium | Phase 0 derives K from `TEST_TIMING_LOG` and names the longest suite; `registry-gate-mutation-battery` measures 860s–1675s and is relevance-gated |
| K legs add dispatch draws to a contended pool | Medium | Measured dispatch p50 1.4 / p90 12.4 / max 21.0; the run already takes a max over four draws, so the change is 4→6; the raised ceiling absorbs it |
| Ceiling raise costs drift-alert sensitivity | Low | Bounded to 12 min, inside the probe's own measured 61–243 min delivery interval; threshold moves first |
| Relevance gating breaks the totality property | **Retired by design** | Guard 1 quantifies over assigned, not executed; per-leg `executed = assigned − declines` |
| ADR-133 contention violated by parallel legs | **Retired by verification** | Both mechanisms already short-circuit under `CI` — `LOCK_SKIPPED_CI: … matrix shards are already isolated.` |
| Matrix breaks branch protection | **Retired by verification** | Required check is `test`; `test-webplat` already ships a matrix and rolls up correctly today |

## Deferred Work (tracking issues required)

- **#5806 — deploy off `workflow_run` (ADR-072 option 3).** Stays open, updated with the fourteen
  scoping findings and re-armed with the time-to-`test` criterion.
- **Runner-pool contention.** Max concurrency measures 4–17 across runs; dispatch delay reaches
  21 min. Worth its own issue now the DAG's long pole is removed. Verified: no open issue covers it
  (`gh issue list --search "CI duration slow runner contention shard"` is empty), and the labels it
  needs exist — `domain/engineering`, `type/chore`, `priority/p2-medium`, `priority/p3-low`.
- **Aggregator diagnosis honesty.** `test`'s output is `echo "$shard: $result"`, so a
  budget-exceeded leg and a cancelled-by-superseding-push leg render identically as
  `test-scripts: cancelled`. Worth a step-level branch that names the measured cause.
- **`plugins/soleur/test/worktree-manager-porcelain-sigpipe.test.sh` flakiness** — named in #7902 as
  context only, explicitly out of scope; file separately if it recurs.

## References & Research

### Internal References

- `.github/workflows/ci.yml` — `test-scripts` (the long pole), `test-webplat`
  (`strategy.matrix.shard` precedent), `test` (colon-delimited aggregator), `lint-webplat` (the only
  job declaring `timeout-minutes`); exactly two `needs:` edges.
- `.github/workflows/web-platform-release.yml` — `await-ci`'s `test`-check-run poll and `exit 0`;
  `CEILING_S: "3000"`; `EXPECTED_SHA: ${{ github.sha }}` (the #3409 gate); `notify-gated`.
- `scripts/test-all.sh` — `run_suite()`/`skip_suite()` (the chokepoint pair, both incrementing
  `suites`), `SUITE_GLOBS`, `--print-suite-globs`'s pre-side-effect handling, the
  `registry-gate-mutation-battery` budget.
- `scripts/lib/test-contention.sh` — ADR-133's advisory lock and `TC_RUNTIME_CEILING_S`, both
  CI-exempt.
- `scripts/prod-version-drift-check.sh` / `.test.sh` — `DRIFT_SUSTAINED_THRESHOLD_MIN`, B8b parity,
  B8e closure pin, B9 threshold safety.
- `scripts/lint-orphan-test-suites.sh` — the registration-set extractor Guard 1 reuses.
- `knowledge-base/engineering/architecture/decisions/ADR-072-adaptive-ci-signal-wait-for-deploy-gate.md`.

### Institutional Learnings

- `knowledge-base/project/learnings/2026-05-05-defense-relaxation-must-name-new-ceiling.md` — the
  raise names what the new ceiling bounds.
- `knowledge-base/project/learnings/best-practices/2026-05-07-deploy-poll-ceiling-must-track-realistic-deploy-window.md`
  — why a raise alone would re-break.
- `knowledge-base/project/learnings/best-practices/2026-06-30-adaptive-ci-poll-gate-wall-clock-ceiling-not-attempt-count.md`
  — the gate this plan preserves, and why wall-clock keying is load-bearing.
- `knowledge-base/project/learnings/2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md`
  — the tautology row and the harness rows exist because of this.
- `knowledge-base/project/learnings/2026-08-17-the-lint-that-was-meant-to-make-the-class-mechanical-was-never-pointed-at-the-repo.md`
  — AC14 exists because a green test of a gate is not a green gate.
- `knowledge-base/project/learnings/security-issues/2026-07-01-two-stage-privileged-workflow-split-and-its-review-traps.md`
  and `knowledge-base/project/learnings/integration-issues/2026-04-21-workflow-dispatch-requires-default-branch.md`
  — `workflow_run` traps, recorded on #5806.

### Related Work

- Closes #7902. Ref #5806 (updated and re-armed, deliberately not closed).
- #5795 / PR #5051, #5052 — the `await-ci` lineage this plan preserves rather than replaces.
- ADR-133 (sequentiality and CI exemptions), ADR-181 (relevance-decline accounting).

## Correction (2026-09-07, post-review)

Three claims in this plan were falsified during review and are superseded. The plan is a
point-in-time artifact and is not rewritten in place; this stanza is the correction of record.

1. **"Runner dispatch delay p50 1.4 / p90 12.4 / max 21.0 min."** Re-derived from the GitHub API,
   real job dispatch is ~1 SECOND and every job in a run starts within ~15s of the others. Those
   gaps are `ci.yml`'s OWN `concurrency` group serialising each main push behind its
   predecessor's `test` job — four consecutive runs started +1s after the prior run's `test`
   completed; runs created after the group drained started in ~1s. Dispatch is per-RUN, not
   per-leg, so the argument that extra legs each add a dispatch draw is withdrawn. Every
   occurrence of the 1.4/12.4/21.0 figures in this document inherits this correction.

2. **The K table and "K=4 is worse than K=3."** Both were simulated on `main`'s 374-suite order.
   This branch changes the registered suite set, and K=3's slowest leg swung 15.09 -> 20.70 ->
   15.09 minutes purely from adding and removing two files. The shipping figure is 15.09 min on
   the 375-suite `LC_ALL=C` order; K=4 measuring worse is a property of THIS suite set, not of K.
   Re-simulate before touching K.

3. **Guard 2 and its ADR.** The plan's Guard Contract specifies a guard asserting
   `max(closure ceilings) + test's own <= CEILING_S/60`. It was built, mutation-proven at 10/10,
   and then DELETED on a CTO ruling: declared job ceilings bound execution only, so the
   arithmetic omits the queue term of correction 1 and is green on configurations the gate cannot
   absorb — and no headroom factor repairs a missing term. It is replaced by a `::warning::` at
   0.7 x CEILING_S inside `await-ci`, which measures the gated quantity itself, queue included.
   ADR-208 is rewritten accordingly and records the rejection so it is not re-proposed.

Also corrected: measured per-leg install overhead is 0.52 min (not ~1.5), and `test-scripts`
ships `timeout-minutes: 60` (not 30) because one suite on its path declares a 2,500,000 ms
fail-safe budget and a silent bound must never fire before a loud one.
