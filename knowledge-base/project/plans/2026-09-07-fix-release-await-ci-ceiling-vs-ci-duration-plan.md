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

## Overview

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

The `await-ci` job in the Web Platform Release workflow starts alongside `ci.yml` on the merge
SHA and polls for CI to conclude, bounded by a 3000s (50 minute) wall-clock ceiling. `ci.yml` on
main has outgrown that bound, so the gate reaches its ceiling and fail-closes on runs where CI is
healthy but slow. The gate's fail-closed posture is correct and is not the defect.

Measurement shows the duration is not diffuse: **one unsharded job, `test-scripts`, is 89.6% of
CI wall clock at p50**, and a single step inside it is 98.3% of that job. This plan shards that
job and puts a declared ceiling on every job that can block a deploy, so CI duration is a bounded,
observable budget rather than an unbounded quantity that silently consumed a downstream gate.

## Problem Statement

`await-ci` and `ci.yml` both start from the same push to main, and `await-ci` gets **essentially
no head start** — measured delta between `await-ci` job start and the corresponding `ci.yml` run
creation is +3s to +511s (p50 ≈ +22s) across 30 runs. Its 50-minute budget therefore has to cover
`ci.yml`'s *entire* wall clock, including `ci.yml`'s own runner queue. When CI exceeds 50 minutes,
the gate fail-closes and the deploy is skipped.

**ci.yml wall clock on main** (`gh api .../workflows/ci.yml/runs?branch=main&event=push`, n=40,
window 2026-09-03 → 2026-09-07):

| statistic | value |
|---|---|
| p50 | 34.27 min |
| p90 | 51.77 min |
| p95 | 54.12 min |
| max | 57.40 min |
| runs ≥ 50 min | **5 / 40 (12%)** |

**Where the time goes** (per-job, n=29 completed runs):

| job | p50 | p90 | max |
|---|---|---|---|
| **test-scripts** | **29.93** | **35.07** | **38.98** |
| test-webplat (1/2) | 4.30 | 5.51 | 10.63 |
| e2e | 3.73 | 8.47 | 11.50 |
| test-webplat (2/2) | 3.27 | 4.68 | 9.35 |
| all 18 other jobs | ≤ 2.00 | — | ≤ 17.62 |
| test (aggregator) | 0.05 | 0.07 | 0.08 |

`test-scripts` is **7.0x** the next-longest job and is the last job to finish in 10/10 spot-checked
runs. `ci.yml`'s DAG is almost flat — only two `needs` edges exist in 1113 lines — so the critical
path is simply `run created → runner dispatch → test-scripts → test`, measured at **99.8% of wall
clock at p50**. Inside `test-scripts`, the single step `bash scripts/test-all.sh scripts` is
**p50 98.31%** of the job (fixed overhead: a measured ~0.45 min of checkout + gitleaks + likec4 +
bun setup). That step is one monolithic `run:` with no internal parallelism, executing the scripts
group's suites sequentially, while `test-webplat` already runs a 2-way matrix.

**Both observed failures are the ceiling, not a test.** Release runs `34141449046` (b551bdc1a) and
`33866770160` (b576e4ab7) failed `await-ci` at **50.13** and **50.20** minutes — the 3000s ceiling
exactly. They are the only two runs above 42.3 minutes; there is no organic failure mode here, only
a step function at 50 minutes. Notably `33866770160` failed while its `ci.yml` run **succeeded** in
57.40 minutes — a pure false negative, a healthy commit blocked from production.

## Research Reconciliation — Spec vs. Codebase

| Claim | Reality (measured/verified) | Plan response |
|---|---|---|
| ci.yml "climbed to 50–54 min" | Confirmed, slightly worse: p90 51.77, p95 54.12, max 57.40; 5/40 ≥ 50 min | Adopted |
| `test-scripts` is the long pole; registry batteries dominate | **Confirmed and stronger than claimed**: p50 89.6% of wall clock, 99.8% of the critical path, last to finish 10/10; one step is 98.3% of the job | Promoted from "unverified premise" to the plan's primary target |
| Option 3 (`workflow_run`) "removes the class" | It removes the *ceiling*, but leaves main's CI at ~57 min and carries a **fail-open** hazard (below). It is also already tracked by OPEN issue #5806 | **Deferred**, with #5806 updated and re-armed — see the decision record |
| Option 1 (raise the ceiling) is cheap | It is **not free**: ADR-072 pins `timeout-minutes ≥ 1.2 × CEILING_S`, and `prod-version-drift-check.test.sh` B9 computes `max(release 60, await-ci 60) + migrate 30 + verify-migrations 15 + deploy 90 = 195`, **exactly equal** to `DRIFT_SUSTAINED_THRESHOLD_MIN=195` — zero margin. Raising the ceiling reds B9 until the prod drift alerter is made less sensitive | Rejected as the primary fix; any future raise is data-gated and must move the threshold first |
| Only the ceiling constant needs changing | False. Sharding touches `scripts/test-all.sh`, an awk-based job-block parser, a 3-site gitleaks pin parity assertion, and ADR-133's contention lock | All enumerated in Files to Edit |
| `test-scripts` can be parallelised in-process | **False.** ADR-133 makes `test-all.sh` sequential deliberately (tmpfs contention plus a Bun FPE crash, managed by an advisory lock). A **job matrix** — separate runners, each still sequential internally — is the only safe shape | Design constrained to a matrix |

## Premise Validation

- **#7902** — `OPEN`, `closedByPullRequestsReferences: []`. Labels `priority/p1-high`, `type/bug`,
  `domain/engineering`; milestone *Phase 4: Validate + Scale*.
- **ADR-072** — exists, `status: accepted`, read in full. Its option 3 is the issue's option 3.
- **#5806** — `OPEN`, the ADR-072 option-3 tracking issue. Its re-evaluation criteria *did* fire
  (a real event exceeded the 50m ceiling). Evaluating them is what this plan does; the outcome is
  that the fired criteria pointed at a cause the criteria themselves did not anticipate — an
  unsharded job, not irreducible CI cost. #5806 is updated and re-armed rather than executed.
- **ADR-133** — governs `test-all.sh`'s deliberate sequentiality and the `TC_RUNTIME_CEILING_S`
  contention lock. Directly constrains the sharding design.
- **Own capability claims, verified by reading rather than asserted:** the `test` aggregator is a
  single colon-delimited loop over three `needs.<shard>.result` values, so matrix legs rolling into
  one job result need **no** aggregator edit; `test-webplat` shards via `VITEST_SHARD` forwarded to
  `vitest --shard`, which is **native runner sharding the scripts group does not have**; only
  `lint-webplat` declares `timeout-minutes` in `ci.yml`.

## Mechanism Minimality Gate

**Property List:**

1. A merge that passes CI reaches production without a human intervening.
2. A merge that fails CI never reaches production (fail-closed preserved).
3. Production deploys the SHA that CI actually validated.
4. CI duration is bounded, and growth becomes visible before it consumes a downstream gate.
5. The mechanism does not silently re-break as the suite count grows.

**Cut List:**

| Mechanism | Property | Already covered by | Disposition |
|---|---|---|---|
| Swap the release trigger to `workflow_run` | P1, P3 | P3 is already held by the `#3409 build_sha` gate (`EXPECTED_SHA`); the swap would *break* it (below) | **Cut from this PR**; stays deferred in #5806 |
| Raise `CEILING_S` | P1 (temporarily) | Nothing — and it costs drift-alert sensitivity via B9's zero margin | **Cut** as primary; data-gated later |
| A new "deploy gated" alerting channel | P4 | `notify-gated` already exists and is **retained unchanged** — this plan does not touch the release workflow, so the sub-minute push signal is preserved rather than traded for the slower probes | **Cut** — nothing new is built |
| A superseded-SHA guard on `deploy` | P3 | `EXPECTED_SHA` already holds it | **Cut** (also rejected by ADR-072 review) |
| In-process parallelism inside `test-all.sh` | P4 | — | **Cut** — ADR-133 forbids it |
| Per-job change detection in ci.yml | P4 | The workflow is already path-filtered | **Cut** |

One mechanism survives: **reduce the quantity the ceiling reacts to, and bound it.**

## Proposed Solution

1. **Shard `test-scripts` into a job matrix**, mirroring the `strategy.matrix` pattern
   `test-webplat` already uses. Matrix legs roll up into a single `needs.test-scripts.result`, so
   the `test` aggregator is untouched and the required-check name is unchanged.
2. **Declare `timeout-minutes` on every `ci.yml` job that can block a deploy.** Today exactly one
   job of ~23 declares a ceiling; the rest inherit GitHub's 360-minute default, which is why CI
   duration could grow unboundedly until it silently ate a downstream gate. A declared budget turns
   growth into a red check instead of a production outage.
3. **Leave the `await-ci` gate, its ceiling, and `notify-gated` exactly as they are.** Sharding
   moves the distribution far under the existing ceiling; changing the gate in the same PR would
   couple a mechanical, pre-merge-testable change to a topology change that cannot be tested before
   merge.

### Architecture Decision

**Chosen: option 2 — shard the long pole and declare CI's duration budget.**

**This reverses the plan's own provisional call.** The plan initially selected option 3 on the
strength of ADR-072 having named it "the structural fix" and #5806's re-evaluation criteria having
fired. Two independent measurements and a CTO review overturned that. The reversal is recorded here
rather than quietly applied, because the reasoning is the deliverable.

**Why option 3 is not the fix now:**

- **It has a demonstrated fail-open mode that is worse than the current outage.** The `deploy` job
  sets `EXPECTED_SHA: ${{ github.sha }}` (`web-platform-release.yml:767`) and compares it against
  the deployed `/health` `build_sha` — the #3409 gate that exists precisely to catch "right semver,
  wrong source tree". Under `workflow_run`, `github.sha` is the **default-branch tip**, not the SHA
  CI validated. `reusable-release.yml`'s `BUILD_SHA` and this `EXPECTED_SHA` would *both* resolve
  to main-tip, so they would **match each other while both being the un-CI'd SHA**. The gate would
  report itself verified on exactly the tree it was built to catch. Today's failure is a blocked
  deploy; that failure is an unverified deploy reporting success.
- **It makes the drift alerter silently wrong.** B8/B9 parse only `web-platform-release.yml` and
  its callee — never `ci.yml`. Under `workflow_run`, ci.yml's ~57 minutes joins the serial critical
  path but stays invisible to the formula, so B9 stays green while the true bound grows by an hour.
  Correcting it costs a permanent ~90-minute loss of drift-alert sensitivity.
- **It cannot be exercised before merge** (`workflow_dispatch` resolves the workflow file from the
  default branch only), it touches a workflow shared with `version-bump-and-release.yml`, and it
  adds a measured ~8.5 min p50 to time-to-prod by serialising build behind CI.
- **Above all, it does not make CI faster.** It stops the deploy from *noticing* a 57-minute CI
  while every PR and every merge keeps paying it.

**Why option 2 is the fix:** it removes the actual quantity. Projected K-shard wall clock, modelled
as `0.45 + (test_scripts − 0.45)/K` against the measured distribution:

| | baseline | K=2 | K=3 | K=4 |
|---|---|---|---|---|
| wall p50 | 35.72 | 18.08 | **13.18** | 10.37 |
| wall p90 | 53.20 | 36.40 | **33.42** | 31.12 |
| saved p50 | — | 15.27 | **20.19** | 21.92 |

**K=3 is chosen.** Returns fall off sharply after it (K=2→3 buys 4.9 min at p50; K=3→4 buys only
2.8 min), and every additional leg adds a runner slot to a pool that measurement shows is already
contended.

**Honest residual — this plan does not claim to eliminate the cliff.** In the four most
runner-starved runs, sharding saves 0–13 minutes *regardless of K*, because a different job
(`critical-css-gate` at 49.12 min, `lockfile-sync` at 40.52 min) becomes the new tail purely from
dispatch queueing, and projected wall **max stays ~53 min even at K=4** — still above the 50-minute
ceiling. So option 2 makes the failure rare rather than impossible. Removing the cliff entirely is
option 3, correctly implemented, which is why #5806 stays open and re-armed rather than closed.
Phase 3's declared ceilings are what will make the residual visible if it recurs.

**Option 1 (raise the ceiling) is deliberately not bundled.** It is available and cheap in
isolation, but B9's margin is exactly zero today, so any raise must first loosen the prod drift
alerter. Spending that sensitivity now — before measuring the post-shard distribution — would be
paying a permanent cost for a tail this PR is about to shrink. It is data-gated instead: if
post-shard p100 on main exceeds 60% of `CEILING_S`, raise the threshold first, then the ceilings.

## Technical Approach

### Architecture

```
BEFORE                                   AFTER (K=3)
  test-scripts  ~30 min (1 runner) ────┐   test-scripts (1/3) ~10 min ─┐
  test-webplat 1/2, 2/2  ~4 min        │   test-scripts (2/3) ~10 min  ├─> test
  test-bun, e2e, +18 jobs  ≤2 min      ├─> test-scripts (3/3) ~10 min ─┤   (aggregator
                                        │   test-webplat 1/2, 2/2       │    unchanged:
  critical path = dispatch              │   test-bun, e2e, +18 jobs     │    one result
    + test-scripts + test = 99.8%       ┘                               ┘    per shard)
  wall p50 35.7 / p90 53.2                 wall p50 13.2 / p90 33.4
```

The `await-ci` gate, `CEILING_S`, `notify-gated`, and the whole release topology are **unchanged**.

### Implementation Phases

Contract before consumer: the shard-selection mechanism lands in `test-all.sh` with its totality
guard **before** `ci.yml` starts calling it with a shard argument, so no phase leaves a state where
CI silently runs a subset.

#### Phase 1: Deterministic, total shard partition in `scripts/test-all.sh`

- Add a `SCRIPTS_SHARD` env var of the form `k/N` (mirroring the existing `VITEST_SHARD` naming and
  its shell-injection-safe `env:`-passing convention, `test-all.sh:1896-1935`).
- Partition the scripts group by a **deterministic total function** over the suite path — a stable
  hash modulo N — not a checked-in balance manifest, which can drift out of sync with the suite
  list. Determinism matters independently of totality: if a suite can move between legs across
  runs, a flake becomes unattributable.
- Unset or empty `SCRIPTS_SHARD` must run the full group, so local invocation and
  `main-health-monitor.yml`'s `TEST_GROUP=all` path are unchanged.
- Emit the executed suite list per leg so the totality guard (Guard 1) can assert on it.
- Lower `TC_RUNTIME_CEILING_S` (`scripts/lib/test-contention.sh:101`, currently 14400s)
  proportionally for a sharded leg, since ADR-133's 2700s baseline describes a full uncontended
  gate, not one leg of it.

#### Phase 2: Matrix the `test-scripts` job

- Add `strategy: {fail-fast: false, matrix: {shard: ["1/3","2/3","3/3"]}}` to `ci.yml`'s
  `test-scripts` job and pass `SCRIPTS_SHARD: ${{ matrix.shard }}` via `env:`.
- The job **name must stay `test-scripts`** so the `test` aggregator's `needs.test-scripts.result`
  and the required-check contract are untouched.
- Every leg keeps the identical runtime profile: the same gitleaks and likec4 installs at the same
  pins, and no `setup-node`/`setup-bun` version pin — 47 `.claude/hooks/*.test.sh` suites and
  others carry comments asserting "the test-scripts CI shard has no bun and no node", so that
  profile is load-bearing and must be identical across legs.
- Re-verify `plugins/soleur/test/scripts-shard-runtime-coverage.test.sh`'s job-block extractor
  (`awk '/^  test-scripts:/{f=1} f&&/^  [a-z][a-z0-9-]*:$/&&!/^  test-scripts:/{exit} f'`) still
  bounds the block correctly once `strategy:` is present. It must be re-run, not assumed.
- Re-verify `plugins/soleur/test/required-checks-canonical-parity.test.sh`'s gitleaks pin-parity
  assertion across its install sites now that one site is a matrix.

#### Phase 3: Declare `timeout-minutes` on deploy-critical ci.yml jobs

- Declare an explicit ceiling on `test-scripts` (per leg), `test-webplat`, `test-bun`, `test`, and
  every other job with a `needs`-path into `test`.
- Size each ceiling above the **measured post-shard p100** with named headroom, not above p50 — a
  ceiling that kills a slow-but-healthy leg fail-closes the deploy for a new reason, which is the
  defect this plan is fixing, reintroduced one layer down.
- This is the missing feedback loop: CI duration becomes a declared budget whose growth reddens a
  check, instead of an unbounded quantity discovered by a production outage.

#### Phase 4: Guards

Implement Guards 1–3 (contracts below). Guard 1 — shard totality — is the highest-risk deliverable
in this plan and is written before the partition it guards.

#### Phase 5: Architecture records

- Amend ADR-072; author the new ADR; update and re-arm #5806. See `## Architecture Decision
  (ADR/C4)`.

## Alternative Approaches Considered

| Approach | Verdict | Why |
|---|---|---|
| Trigger release off `workflow_run` on ci.yml (option 3) | **Deferred to #5806** | Fail-open `EXPECTED_SHA` hazard; drift formula blind to ci.yml; untestable pre-merge; touches a shared workflow; +8.5 min time-to-prod; leaves CI at 57 min |
| Raise `CEILING_S` (option 1) | Rejected as primary; data-gated later | B9 margin is exactly zero, so a raise costs prod-drift sensitivity; re-breaks on the same trajectory |
| In-process parallelism inside `test-all.sh` | Rejected | ADR-133: tmpfs contention + a Bun FPE crash make within-runner parallelism unsafe |
| K=4 or higher sharding | Rejected | K=3→4 buys only 2.8 min at p50 while adding a runner slot to an already-contended pool |
| Checked-in shard balance manifest | Rejected | Drifts silently out of sync with the suite list; a deterministic total function cannot |
| Delete `await-ci` and rely on branch protection | Rejected | Branch protection gates the merge, not the deploy; ADR-072 invariant #2 requires the `test` check-run to authorise the cutover |

## Architecture Decision (ADR/C4)

### ADR

- **Create ADR-207** (ordinal **provisional**). 204 is the highest on `origin/main`, but 205 and
  206 are each already claimed on a pushed branch — `origin/feat-one-shot-7849-...-fixture-env-ledger-ancestry`
  holds ADR-205 and `origin/feat-one-shot-7759-net-issue-flow-filing-cites-issue` holds ADR-206.
  A probe scoped to `origin/main` (or to the local tree) reports 205 as free and is wrong; the
  ordinal must be derived across **every** `origin/*` ref, and re-derived immediately before merge
  because `main` moves under a long session —
  *"CI wall-clock is a declared budget: shard the long pole, bound every deploy-critical job."*
  This is a genuine architecture decision: it establishes a new coupling between `ci.yml`'s
  declared ceilings and the release gate's viability, and it records the shard-totality invariant
  that makes a sharded required check trustworthy.
- **Amend ADR-072 — amend, not supersede.** Nothing in its Decision is reversed: the adaptive wait
  and the fail-closed posture stand and are retained by this plan. What is falsified is Decision
  item 4's *sizing premise* ("sized above the observed p100 CI-under-contention duration (~28m,
  measured 2026-06-30)"). Add the dated re-measurement (p50 34.27 / p90 51.77 / p95 54.12 / max
  57.40, 5 of 40 at or over the ceiling) and a consequence recording that the ceiling's validity
  depended on a CI duration that nothing was bounding. Correct the record on option 1: its
  rejection was pre-adaptive-wait and no longer stands on that ground — it now fails on the B9
  coupling instead.
- **Update #5806, do not close or execute it.** Record that criteria 1 and 3 fired, were evaluated,
  and the outcome was *root cause was an unsharded job, not irreducible CI cost*. Re-arm with a
  criterion that survives this fix: *post-shard ci.yml p100 on main exceeds 60% of `CEILING_S`*. A
  criterion that fires and is then silently not acted on becomes noise; recording the evaluation is
  what keeps it credible.

  This plan's research produced a substantially better scoping of that deferred work than #5806
  currently carries. Record all of it on the issue, so the eventual implementation starts from a
  complete record rather than rediscovering it:

  1. **Fail-open `build_sha` gate.** Under `workflow_run`, `github.sha` is the default-branch tip,
     so `reusable-release.yml`'s `BUILD_SHA` and the deploy job's `EXPECTED_SHA` would match each
     other while both being the un-CI'd SHA — the #3409 gate would self-certify the exact wrong
     tree it exists to catch.
  2. **Out-of-order deploy is a silent prod rollback.** CI duration varies 22–57 min, so for merges
     A then B, CI(B) can complete before CI(A). Under `push` the newest run won; under
     `workflow_run` each completion fires independently, so release(A) can run *after* release(B)
     and roll production back to A **with a green pipeline and a correctly-labelled SHA**. Format
     validation of `head_sha` does not catch this — it validates the SHA's shape, not its position.
     The fix is an ancestry check in the resolve step (fetch the deployed `build_sha`, then
     `git merge-base --is-ancestor $DEPLOYED $HEAD_SHA`, **skip** rather than fail when false) plus
     a `concurrency` group on the deploy path with `cancel-in-progress: false` so two survivors
     serialise. ADR-072 named out-of-order risk generically; this is the concrete mechanism.
  3. **`github.sha` is not the whole surface.** A grep for it misses the env-var forms
     `$GITHUB_SHA` / `$GITHUB_REF` / `$GITHUB_REF_NAME` in shell steps and scripts;
     `docker/metadata-action`'s `type=sha` and the `org.opencontainers.image.revision` label, which
     read `context.sha` implicitly; any release-tracking step naming a release by commit; and
     `concurrency: ${{ github.ref }}`, which under `workflow_run` resolves to the default branch for
     every run and would collapse all releases into one group. The structural fix that covers all of
     them: derive `resolved_sha` from `git rev-parse HEAD` **after** checkout and assert it equals
     the requested ref, fail-closed — then anything reading the tree is correct by construction.
  4. **Convert `await-ci`, do not delete it.** The right shape turns it from a poller into a fast
     verifier that still asserts the `test` check-run `conclusion == success` for the resolved SHA,
     returning in seconds. That preserves ADR-072 invariant #2 (the workflow-run `.conclusion` must
     never authorise the cutover) and keeps B8e's pinned needs-closure and the drift formula's shape
     intact.
  5. **Keep a gated notification, in conclusion-based form.** `types: [completed]` fires on
     `failure` and `cancelled` too, so a job gated on
     `github.event.workflow_run.conclusion != 'success'` gives a *better* signal than today's
     `notify-gated` — it also covers CI-failed-on-main, which the timeout never did. Deleting it and
     relying on the */30 drift probe and the 6-hourly monitor would be a detection-latency
     regression on the exact failure mode being redesigned.
  6. **`workflow_run` has no `paths` filter**, so the `on.push` denylist disappears. Decide
     explicitly whether docs/KB-only commits start a (no-op) release run or whether the filter is
     reimplemented in the resolve step; do not let it fall out by accident.
  7. **Recursion is not a risk.** No commit is pushed to main — tags materialise via the Releases
     API — and `branches: [main]` excludes tag pushes; cosign's `COSIGN_IDENTITY_REGEXP` pin on
     `reusable-release.yml@refs/heads/main` is preserved under `workflow_run`.
  8. **It cannot be verified pre-merge**, so the resolve logic must live in a committed, locally
     testable script rather than inline YAML.
  9. **`live-verify` silently disarms.** Its `if:` ends `&& github.event_name == 'push'`
     (`web-platform-release.yml:918`), which is never true under `workflow_run`, so the **blocking**
     dark-launch gate becomes permanently `skipped`, its per-run Sentry emission drops to zero, and
     `scripts/watch-live-verify-pass.sh` never observes a PASS again. The obvious fix is a trap:
     switching to `!= 'workflow_dispatch'` leaves the job's `BEFORE_SHA: ${{ github.event.before }}`
     undefined under `workflow_run`, so the compare API 404s and the gate goes *vacuous-but-green*,
     which is worse than skipped. Both the `if:` and the compare endpoints must change.
  10. **A CI re-run would ship a production release.** `types: [completed]` fires on every
      completion including a `gh run rerun` of an existing main CI run and a `workflow_dispatch` of
      `ci.yml`. `reusable-release.yml` has no "already released this SHA" short-circuit — it mints
      the next patch version — so clicking "re-run" would cut a new semver, run migrations and swap
      the container. The resolve step must additionally require
      `workflow_run.event == 'push'` and `workflow_run.run_attempt == 1`.
  11. **Four jobs check out the wrong tree.** `migrate`, `verify-migrations`,
      `verify-doppler-secrets` and `deploy` all use a bare `actions/checkout` with no `ref:`, which
      under `workflow_run` resolves to main tip. Migrations would be applied from a newer tree than
      the image being deployed. Threading `ref` into `reusable-release.yml` alone does not cover
      them.
  12. **`release-outcome` must gain the new job.** It lists `await-ci`/`notify-gated` in `needs:`
      and its own header warns that omitting a job fails silently. Without rewiring, a resolve step
      that fail-closes on a malformed SHA leaves every downstream job `skipped`, and the outcome
      classifier reports "no alert" — the one guaranteed fail-closed path would be the one with no
      notification.
  13. **The gate's semantics silently widen.** `await-ci` polls only the `test` aggregator
      check-run; `workflow_run.conclusion` is the **run-level** conclusion, so `e2e`,
      `lockfile-sync`, `critical-css-gate` and every advisory job would begin blocking production.
      That may be desirable, but it is a decision to name, not a side effect to inherit.
  14. **Also stale on that path:** `plugins/soleur/skills/ship/SKILL.md`'s admin-merge hatch
      (documented entirely in terms of `await-ci` timing out), the learning
      `2026-06-29-admin-merge-skips-deploy-via-await-ci-gate.md`, the dispatch input comment at
      `web-platform-release.yml:47`, and `gh release create` at `reusable-release.yml:385`, which
      has no `--target` and would tag main tip rather than the built SHA.

### C4 views

Checked against all three files —
`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}` — by enumerating the
change's actors, systems, containers and relationships rather than grepping for the feature's noun:

- **External human actors:** none added or removed; the change is internal to CI.
- **External systems:** none added. The set this pipeline touches (`github`, `ghcr`,
  `zotRegistry`, `sigstore`, `resend`, `sentry`, `betterstack`, `hetzner`, `tunnel`) is unchanged —
  only the internal job layout of one workflow changes, which the model does not resolve below the
  `github` system boundary.
- **Containers / data stores:** none added or removed.
- **Access relationships:** unchanged in actor, direction and technology.
- **Edges re-read for continued truth:** `model.c4:431` (`github -> webapp`, the drift probe
  "alerting only on staleness sustained past one release cycle") stays accurate — this plan does
  **not** change `DRIFT_SUSTAINED_THRESHOLD_MIN`, precisely because it does not touch the release
  topology. `model.c4:617` (`github -> sentry`) is unaffected: `ci.yml` uses no `sentry-heartbeat`
  composite.
- **Derived cardinalities:** `bash plugins/soleur/test/c4-count-parity.test.sh` was run at plan time
  and passed **10/10**. The gated counts are sentry-heartbeat emitters (11 workflows / 6 schedule /
  5 dispatch), cron monitors (56 / 12 / 44) and Resend emitters (13). Verified:
  `grep -rln actions/sentry-heartbeat .github/workflows/` returns 11 files and **`ci.yml` is not
  among them**, so adding matrix legs and job timeouts moves no gated count. Re-run in AC.

**Conclusion: no `.c4` edit is required**, on the enumeration above plus a green count-parity run.

### Sequencing

Both records are authored in this plan's own PR; nothing is deferred behind a soak.

## User-Brand Impact

- **If this lands broken, the user experiences:** a required CI check that reports green while
  silently running only a subset of the suite — so a regression reaches `app.soleur.ai` with a
  green pipeline. This is the shard-totality failure mode, and it is strictly worse than the
  current blocked-deploy state, which is why Guard 1 is the plan's highest-priority deliverable.
- **If this leaks, the user's data is exposed via:** no new data path is created; the change is
  confined to CI test partitioning. The residual exposure is indirect — a dropped suite could be
  one of the security or credential-path gates that run in the scripts group, so untested
  data-handling code could ship behind a green check.
- **Brand-survival threshold:** `single-user incident`

A single regression reaching the single production host behind a falsely-green required check is a
user-visible incident on its own, without needing an aggregate pattern.

## Observability

```yaml
liveness_signal:
  what: "the required `test` aggregator check-run on every push and PR, now backed by declared per-job timeout-minutes so a duration regression reddens a check instead of silently consuming the deploy gate; plus scheduled-prod-version-drift.yml (*/30) reading prod /health build_sha"
  cadence: "per push and per pull_request for CI; every 30 minutes for the prod drift probe"
  alert_target: "GitHub required-check failure on the offending PR; Sentry cron monitor -> operator email for the drift probe; main-health-monitor.yml files a P1 ci/main-broken issue"
  configured_in: ".github/workflows/ci.yml, .github/workflows/scheduled-prod-version-drift.yml, .github/workflows/main-health-monitor.yml"

error_reporting:
  destination: "GitHub Actions check-run status for CI; Sentry cron monitors for the scheduled probes"
  fail_loud: "a matrix leg exceeding its declared timeout-minutes is recorded by GitHub as `cancelled` and reddens the `test` aggregator, which is a required check; main-health-monitor's filer treats success|failure|cancelled|skipped exhaustively so a timeout files a tracker rather than reading as idle"

failure_modes:
  - mode: "a shard partition silently drops suites, so the required `test` check passes on a subset"
    detection: "Guard 1 (shard totality) diffs the union of the legs' executed suite lists against the unsharded discovery set and fails CI on any difference"
    alert_route: "required `test` check fails on the offending PR"
  - mode: "ci.yml duration grows again until it re-approaches the 3000s await-ci ceiling"
    detection: "the declared per-job timeout-minutes from Phase 3 redden the job at a bound well under the ceiling; the re-armed #5806 criterion (post-shard p100 > 60% of CEILING_S) is the escalation trigger"
    alert_route: "required check failure; #5806 re-evaluation"
  - mode: "a matrix leg drifts to a different runtime profile (gains node/bun, or a different gitleaks pin)"
    detection: "required-checks-canonical-parity.test.sh asserts gitleaks pin parity across install sites; scripts-shard-runtime-coverage.test.sh asserts the shard's runtime profile"
    alert_route: "required `test` check fails on the offending PR"
  - mode: "a deploy ships a different tree than CI validated"
    detection: "the pre-existing #3409 build_sha gate compares the deployed /health build_sha against EXPECTED_SHA and errors on mismatch; unchanged by this plan"
    alert_route: "deploy job fails; notify-gated posts to Slack on a fail-closed await-ci"

logs:
  where: "GitHub Actions run logs per matrix leg; Sentry cron monitor check-in history"
  retention: "GitHub Actions logs 90 days; Sentry per project retention"

discoverability_test:
  command: "bash scripts/test-all.sh --list-shard-coverage"
  expected_output: "the union of the K shard suite lists, printed with a final line stating the union size equals the unsharded scripts-group discovery count, and exit status 0"
```

## Guard Contract

### Guard 1 — Shard totality

**Property.** The union of the suites executed across all `test-scripts` matrix legs is exactly
equal to the set of suites `test-all.sh` discovers for the `scripts` group unsharded — no suite is
dropped, and none is executed twice.

**Assembly.** The chokepoint is the shard-selection function in `scripts/test-all.sh` through which
every scripts-group suite must pass before it can run. The guard quantifies over the *discovery
set* — computed by the same discovery code path the unsharded run uses — not over a hand-listed
inventory of suite names, because members drift on every added suite while the discovery call site
does not. It must compare the union across **all K legs** against that set, in both directions
(missing and duplicated), for arbitrary K rather than a hardcoded 3.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Make the partition drop a suite (e.g. an off-by-one so index `N-1` maps to no leg) | RED |
| 2 | Make the shard-selection function return an empty set for every leg — a guard reporting "0 checked" and exiting 0 is vacuous | RED |
| 3 | Add a **second** new suite to the scripts group after a compliant first, and have the partition assign it to no leg | RED |
| 4 | Make two legs both claim the same suite (double execution, so the union is right but the multiset is not) | RED |
| 5 | Change K in `ci.yml` from 3 to 4 without the partition honouring N — legs 1..3 run and leg 4 is empty | RED |

**Harness rows:** deleting the union-comparison assertion while leaving the guard's iteration in
place must drive the suite RED. Must-PASS non-canonical input: a **different valid K** (for example
K=2 or K=5) with a correct partition must PASS — the contract requires totality for any K, not
only for the K currently configured in `ci.yml`.

### Guard 2 — Shard determinism

**Property.** A given suite path maps to the same leg index on every run for a fixed K, so a
failure is attributable to a stable leg and a flake cannot migrate between legs.

**Assembly.** The same shard-selection function as Guard 1. The guard quantifies over the whole
discovery set, invoking the mapping repeatedly within a run and across a simulated re-run, rather
than sampling one suite — a mapping that is stable for the first suite and unstable for a later one
is the defect this exists to catch.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Seed the partition from anything run-varying (`$RANDOM`, timestamp, `readdir` order) | RED |
| 2 | Make the mapping function unreachable so the guard evaluates zero suites yet exits 0 | RED |
| 3 | Make the mapping stable for the first suite but run-varying for a **second** one | RED |
| 4 | Make the mapping depend on the leg's own index rather than only on the suite path and K | RED |

**Harness rows:** removing the repeat-invocation loop so the guard compares a value against itself
must drive the suite RED. Must-PASS non-canonical input: reordering the discovery output must still
PASS, since the mapping is defined over the suite path, not over discovery order.

### Guard 3 — Deploy-critical ci.yml jobs declare a timeout

**Property.** Every `ci.yml` job on the `needs`-path into the `test` aggregator declares an
explicit `timeout-minutes`, so CI's contribution to the deploy gate has a declared bound rather
than inheriting GitHub's 360-minute default.

**Assembly.** The chokepoint is the `needs` graph of `.github/workflows/ci.yml` resolved backwards
from the `test` job. Membership is **recomputed from the graph**, not hand-listed, so a newly added
shard or a newly added `needs` edge is covered without editing the guard.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove `timeout-minutes` from `test-scripts` | RED |
| 2 | Make the graph walk return an empty job set — reporting "0 checked" and exiting 0 is vacuous | RED |
| 3 | Add a **second** job to `test`'s `needs` without a `timeout-minutes`, after a compliant first | RED |
| 4 | Set `timeout-minutes` to an empty or non-numeric value | RED |
| 5 | Delete a `needs` edge so a job silently leaves the guarded set while still gating the deploy | RED |

**Harness rows:** deleting the per-job assertion while keeping the iteration must drive the suite
RED. Must-PASS non-canonical input: a job declaring a *different* valid timeout from its siblings
must PASS — the contract requires a declaration, not a particular value.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open --limit 200` returned 63 open issues; none of
their bodies reference `.github/workflows/ci.yml`, `scripts/test-all.sh`,
`scripts/lib/test-contention.sh`, `plugins/soleur/test/scripts-shard-runtime-coverage.test.sh`,
`plugins/soleur/test/required-checks-canonical-parity.test.sh`, or `ADR-072`.

## Files to Edit

- `scripts/test-all.sh` — add the `SCRIPTS_SHARD` partition over the scripts group; emit the
  per-leg suite list; add the `--list-shard-coverage` reporting path.
- `.github/workflows/ci.yml` — matrix the `test-scripts` job (K=3), pass `SCRIPTS_SHARD` via `env:`,
  declare `timeout-minutes` on the deploy-critical jobs.
- `scripts/lib/test-contention.sh` — scale `TC_RUNTIME_CEILING_S` for a sharded leg.
- `plugins/soleur/test/scripts-shard-runtime-coverage.test.sh` — re-verify the job-block extractor
  against a job that now carries `strategy:`; extend to assert profile identity across legs.
- `plugins/soleur/test/required-checks-canonical-parity.test.sh` — gitleaks pin parity with one
  install site now a matrix.
- `knowledge-base/engineering/architecture/decisions/ADR-072-adaptive-ci-signal-wait-for-deploy-gate.md`
  — amend the sizing premise, add the re-measurement, correct the option-1 record.

## Files to Create

- `knowledge-base/engineering/architecture/decisions/ADR-207-ci-wallclock-declared-budget.md`
  (ordinal provisional).
- Guard 1 + Guard 2 suite (shard totality and determinism).
- Guard 3 suite (deploy-critical job timeout declarations).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1 — `ci.yml`'s `test-scripts` job declares `strategy.matrix.shard` with 3 legs and
      `fail-fast: false`, and the job key is still literally `test-scripts`.
- [ ] AC2 — the `test` aggregator is **unmodified**: `git diff origin/main -- .github/workflows/ci.yml`
      shows no change within the `test:` job block, proving matrix legs roll into one result.
- [ ] AC3 — `scripts/required-checks.txt` is unmodified, proving the required-check contract is
      untouched.
- [ ] AC4 — Guard 1 drives RED on each of its five mutation-matrix rows, and PASSes on a valid
      K other than 3.
- [ ] AC5 — Guard 2 drives RED on each of its four mutation-matrix rows, and PASSes on a reordered
      discovery set.
- [ ] AC6 — Guard 3 drives RED on each of its five mutation-matrix rows, and PASSes on a sibling
      job declaring a different valid timeout.
- [ ] AC7 — the union of the three legs' executed suite lists equals the unsharded scripts-group
      discovery set, asserted by Guard 1 in CI against the real tree — not only against fixtures.
- [ ] AC8 — `SCRIPTS_SHARD` unset runs the full scripts group unchanged, so
      `bash scripts/test-all.sh scripts` locally and `TEST_GROUP=all` in `main-health-monitor.yml`
      behave exactly as before.
- [ ] AC9 — `bash plugins/soleur/test/scripts-shard-runtime-coverage.test.sh` passes, with its awk
      job-block extractor re-verified against the now-`strategy:`-bearing job.
- [ ] AC10 — `bash plugins/soleur/test/required-checks-canonical-parity.test.sh` passes; the
      gitleaks version+SHA256 pin is identical across every install site including each matrix leg.
- [ ] AC11 — every `ci.yml` job with a `needs`-path into `test` declares `timeout-minutes`, each
      sized above the measured post-shard p100 with headroom stated in an inline comment.
- [ ] AC12 — `await-ci` is unchanged: `git diff origin/main -- .github/workflows/web-platform-release.yml`
      is empty, and `CEILING_S` is still `3000`.
- [ ] AC13 — `scripts/prod-version-drift-check.sh` and its test suite are unmodified, and
      `bash scripts/prod-version-drift-check.test.sh` still passes — proving the drift alerter's
      sensitivity was not spent.
- [ ] AC14 — `bash plugins/soleur/test/c4-count-parity.test.sh` passes (10/10).
- [ ] AC15 — `actionlint` is clean on `.github/workflows/ci.yml`, and each edited `run:` snippet
      passes `bash -c` extraction. `bash -n` is **not** run against a workflow YAML file.
- [ ] AC16 — ADR-207 exists with `status: accepted`; ADR-072 carries the dated re-measurement and
      the corrected option-1 record and is **amended, not superseded** (its `status:` stays
      `accepted`).
- [ ] AC17 — the ADR ordinal is free across every `origin/*` ref, re-verified immediately before
      merge; if renumbered, `grep -rn 'ADR-<old>' knowledge-base/project/{plans,specs}/` finds no
      stale reference in this feature's own artifacts.
- [ ] AC18 — #5806 is updated with the evaluation outcome and re-armed with the post-shard
      criterion, and is **not** closed.
- [ ] AC19 — `python3 scripts/lint-guard-contract.py` resolves all three guard entries against the
      shipped guards; `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main`
      is clean.
- [ ] AC20 — the PR body uses `Closes #7902` and `Ref #5806` (never `Closes #5806`).

### Post-merge (automated)

- [ ] AC21 — the first `ci.yml` run on main after merge completes with all three `test-scripts`
      legs green, and measured wall clock is materially below the pre-merge p50 of 34.27 min.
      Verified with `gh run view <id> --json jobs`.
- [ ] AC22 — a deploy of current `main` is dispatched to unblock production via
      `gh workflow run web-platform-release.yml -f bump_type=patch`, and
      `curl -fsS https://app.soleur.ai/health` subsequently reports a `build_sha` matching the
      deployed commit. This is a `gh`-CLI step the ship phase runs, not a handoff.
- [ ] AC23 — post-shard p100 over the following 10 main runs is recorded on #5806, and the re-armed
      criterion (p100 > 60% of `CEILING_S`) is evaluated against it.

## Test Scenarios

### Acceptance Tests (RED phase targets)

- Given `SCRIPTS_SHARD=1/3`, when `test-all.sh scripts` runs, then it executes a strict subset of
  the discovery set and prints exactly that subset.
- Given all three legs' printed subsets, when unioned, then the result equals the unsharded
  discovery set with no duplicates.
- Given `SCRIPTS_SHARD` unset, when `test-all.sh scripts` runs, then it executes the full group.
- Given the same suite path and K, when the mapping is invoked twice, then it yields the same leg.
- Given a `ci.yml` job on the `needs`-path into `test` with no `timeout-minutes`, when Guard 3
  runs, then it fails.

### Regression Tests

- Given the b551bdc1a shape — a CI run that took 51.6 min — when the sharded pipeline runs the same
  tree, then wall clock lands under the 3000s ceiling and `await-ci` concludes success.
- Given `test-scripts` fails in leg 2 only, when the `test` aggregator evaluates, then
  `needs.test-scripts.result` is not `success` and the required check fails.
- Given ADR-133's contention lock, when three legs run on separate runners, then each leg remains
  internally sequential and no in-runner parallelism is introduced.

### Edge Cases

- Given a newly added scripts-group suite, when CI runs, then it is assigned to exactly one leg and
  Guard 1 stays green without any manifest edit.
- Given K changed from 3 to 4 in `ci.yml`, when Guard 1 runs, then totality holds for K=4.
- Given a runner-starved run where dispatch queueing dominates, when CI completes, then wall clock
  may still approach the ceiling — the named residual, escalated via the re-armed #5806 criterion.

## Risk Analysis & Mitigation

| Risk | Severity | Mitigation |
|---|---|---|
| Shard partition silently drops suites → required check green on a subset | **High** — worse than the current outage | Guard 1, written before the partition, asserting totality against real discovery in CI (AC7), not fixtures |
| A single suite longer than a leg's target makes K ineffective | Medium | Measure the per-suite duration distribution before fixing K; if one suite exceeds ~8 min, choose K against the tail, not the mean |
| Matrix leg drifts to a different runtime profile | Medium | Profile identity asserted by the shard-runtime-coverage and pin-parity suites (AC9, AC10) |
| Residual: runner starvation still pushes wall clock near the ceiling | Medium | Named explicitly, not papered over; Phase 3's declared ceilings make it visible; #5806 re-armed with a post-shard criterion |
| ADR-133 contention semantics violated by parallel legs | Medium | Matrix only (separate runners, sequential within); `TC_RUNTIME_CEILING_S` scaled per leg |
| Adding 2 runner slots to an already-contended pool | Low | K=3 chosen over K=4 partly for this reason; net runner-minutes are roughly unchanged while wall clock falls |
| awk job-block extractor breaks on the new `strategy:` key | Low | Re-run rather than assumed (AC9) |

## Deferred Work (tracking issues required)

- **#5806 — deploy off `workflow_run` (ADR-072 option 3).** Stays open, updated with the
  `EXPECTED_SHA` fail-open finding, the verifier-not-deletion shape, the drift-formula blindness,
  and the non-recursion confirmation; re-armed with the post-shard p100 criterion.
- **Raise `CEILING_S`** — only if the re-armed criterion fires. Must move
  `DRIFT_SUSTAINED_THRESHOLD_MIN` first (B9 has zero margin today), then `CEILING_S`, then
  `timeout-minutes` at ≥ 1.2 × `CEILING_S`.
- **Runner-pool contention** — measurement shows max concurrency of 4–17 across runs and that
  runner availability, not the DAG, sets the spread. Worth its own issue now that the DAG's long
  pole is removed.
- **`plugins/soleur/test/worktree-manager-porcelain-sigpipe.test.sh` flakiness** — named in #7902 as
  context only, explicitly out of scope; file separately if it recurs.

## References & Research

### Internal References

- `.github/workflows/ci.yml` — `test-scripts` (unsharded long pole), `test-webplat`
  (`strategy.matrix.shard` pattern to mirror), `test` (colon-delimited aggregator, one result per
  shard), `lint-webplat` (the only job declaring `timeout-minutes`).
- `.github/workflows/web-platform-release.yml` — `await-ci` and `CEILING_S: "3000"`;
  `EXPECTED_SHA: ${{ github.sha }}` at the deploy job's #3409 `build_sha` gate; `notify-gated`.
- `scripts/test-all.sh` — `TEST_GROUP` partitioning; `VITEST_SHARD` forwarding convention.
- `scripts/lib/test-contention.sh` — ADR-133's advisory lock and `TC_RUNTIME_CEILING_S`.
- `scripts/prod-version-drift-check.sh` / `.test.sh` — `DRIFT_SUSTAINED_THRESHOLD_MIN=195`, B8b
  parity, B8e topology pin, B9 threshold safety (zero margin today).
- `plugins/soleur/test/scripts-shard-runtime-coverage.test.sh`,
  `plugins/soleur/test/required-checks-canonical-parity.test.sh` — the two suites coupled to the
  shard's shape and pins.
- `knowledge-base/engineering/architecture/decisions/ADR-072-adaptive-ci-signal-wait-for-deploy-gate.md`.

### Institutional Learnings

- `knowledge-base/project/learnings/2026-05-05-defense-relaxation-must-name-new-ceiling.md` — why a
  bare ceiling raise is a deferral rather than a defense.
- `knowledge-base/project/learnings/best-practices/2026-05-07-deploy-poll-ceiling-must-track-realistic-deploy-window.md`
  — the documented pattern of ceilings raised and re-broken.
- `knowledge-base/project/learnings/best-practices/2026-06-30-adaptive-ci-poll-gate-wall-clock-ceiling-not-attempt-count.md`
  — the gate this plan deliberately leaves intact, and why its wall-clock keying is load-bearing.
- `knowledge-base/project/learnings/2026-08-17-the-lint-that-was-meant-to-make-the-class-mechanical-was-never-pointed-at-the-repo.md`
  — a green test of a gate is not a green gate; Guard 1 must run against the real tree (AC7).
- `knowledge-base/project/learnings/security-issues/2026-07-01-two-stage-privileged-workflow-split-and-its-review-traps.md`
  — `workflow_run` traps, recorded on #5806 for the deferred work.
- `knowledge-base/project/learnings/integration-issues/2026-04-21-workflow-dispatch-requires-default-branch.md`
  — why option 3 cannot be verified pre-merge.

### Related Work

- Closes #7902. Ref #5806 (updated and re-armed, deliberately not closed).
- #5795 / PR #5051, #5052 — the `await-ci` lineage this plan preserves rather than replaces.
- ADR-133 — the sequentiality constraint that forces a matrix rather than in-process parallelism.
