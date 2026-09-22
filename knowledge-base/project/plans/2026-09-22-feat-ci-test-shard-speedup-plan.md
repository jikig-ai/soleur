---
title: "ci: carve the three heavy test-all suites into a dedicated `scripts-heavy` group and rebalance `test-scripts` to K=5"
type: feat
date: 2026-09-22
slug: feat-ci-test-shard-speedup
branch: feat-ci-test-shard-speedup
issue: 8006
closes: []
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# ci: carve heavy test-all suites into `scripts-heavy` + rebalance `test-scripts` to K=5

## Overview

The required `test` check's long pole is `test-scripts` leg 2/3 at **31–39 min wall clock** (measured 2026-09-22 on runs 35741817851, 35743333085, 35743569887), while legs 1/3 finish in 11–15 min and `test-webplat`/`test-bun` finish in ~5/~1.5 min. This plan removes the long pole without new machinery: move the three heaviest suites — `tests/scripts/registry-gate-mutation-battery` (523 s CI-measured), `scripts/battery-tag-authorship-mutations` (380 s), `.github/scripts/test/run-all.sh` (371 s) — into a new `TEST_GROUP=scripts-heavy` executed by a dedicated 3-leg matrix job, and bump the remaining `scripts` group from K=3 to K=5. Simulated over the CI-measured per-suite timings (artifact `suite-timings-*` on run 35743569887), worst leg drops to ≈ max(battery 8.7 min + ~1 min setup, ~39.2 min of light work / 5 legs ≈ 7.8 min + setup) ≈ **~10 min**, versus 21.5 min for a bare K=5.

## Problem Statement / Motivation

Operator-visible symptom (the session output that triggered this): "The shards are the long pole (~30-40 min each, parallel)." Every merge and every release waits on `test`, which waits on the slowest `test-scripts` leg. The cause is structural, measured, and already half-documented in `ci.yml`:

- **Serial execution.** `scripts/test-all.sh` runs ~237 registered suites sequentially in one bash process per leg (`run_suite` › `scripts/test-all.sh:905`).
- **Positional, not duration-aware, partitioning.** `_shard_selects` (`scripts/test-all.sh:835`) round-robins by registration ordinal. Leg membership is a positional accident: on the 2026-09-22 CI order the three heaviest suites (combined ~21.2 min) all landed on leg 2.
- **The floor.** `registry-gate-mutation-battery` alone is 523 s on CI (8.7 min; 14.3–27.9 min under local contention). No K beats the longest single suite.
- **Growth.** 374 → 392 → ~237 effective registrations churned constantly; the embedded K-simulation table in `ci.yml` was already stale twice before merge and is stale again today.

K alone does not fix this: re-simulated over the real CI order (reconstructed by interleaving the three legs' `suite-timings.tsv` rows, which are written in execution order), K=5 → 21.5 min worst leg, K=8 → 13.6 min.

## Research Insights

### Premise Validation (Phase 0.6)

- `#8006` verified OPEN via `gh issue view` — it prescribes exactly this class of move ("K bump is the cheaper alternative FIRST"; LPT deferred for mechanism defects, not drift).
- `#7902` CLOSED (the 35-min single-job incident that motivated sharding); `#7931` CLOSED (shipped K=3 + `TEST_TIMING_LOG` artifact upload — the data source this plan consumes).
- `#8231`, `#8322`, `#8045`, `#8163` verified OPEN — adjacent, deliberately out of scope (Non-Goals).
- ADR corpus grepped for the mechanism: ADR-133 (tmpfs/advisory lock — CI exempt, untouched), ADR-181 (declines counted — shard non-selection is not a decline), ADR-183 (`TEST_GROUP=all` at ship — `want_scripts_heavy` MUST include `all`), ADR-196 (refusals bind to measured conditions), ADR-212/217 (deploy gate measures time-to-`test` itself — `timeout-minutes` does not bound it), ADR-231 (workflow files byte-budgeted at 490 KB; ci.yml is ~102 KB — relocate the ~140-line stale K-table comment to a runbook rather than grow the file).
- **Cited artifacts verified on `origin/main`:** `scripts/test-all.sh`, `tests/scripts/test-registry-gate-mutation-battery.sh`, `scripts/battery-tag-authorship-mutations.test.sh`, `.github/scripts/test/run-all.sh`, `plugins/soleur/test/scripts-shard-totality.test.sh`, `plugins/soleur/test/scripts-shard-totality-mutations.sh`, `plugins/soleur/test/ci-test-aggregator-diagnosis.test.sh`, `scripts/test-all-enumerate-toolchain.test.sh`, `plugins/soleur/test/scripts-shard-runtime-coverage.test.sh`, `scripts/test-all-infra-coverage-notice.test.sh`, `plugins/soleur/test/ship-battery-owed.test.sh`.

### Mechanism Minimality (Phase 0.6b)

**Property list** (what the plan buys, as observable outcomes):

1. No `test-scripts`/`test-scripts-heavy` leg exceeds ~10 min of suite execution on a normal run.
2. Every registered suite still runs exactly once per CI run (totality), in `TEST_GROUP=all` local/ship runs, and is still relevance-gated locally.
3. A re-partition of either group fails loudly (existing zero-assignment refusal + totality guard), never silently green.
4. The rationale for the partition lives where ADR-231 puts it: a runbook, not a growing comment block.

**Cut list** (mechanisms considered and rejected):

- *Label-keyed LPT pin-table at `_shard_selects`* → property 1 partially; rejected: `_shard_selects` is a streaming per-registration filter that cannot compute a global partition, pins break the guard's any-K totality rows, and pin tables rot on ordinal churn (#8006's own analysis; CTO assessment concurs).
- *Internal splitting of the three heavy suites* → property 1 further (~7 min); rejected here: each heavy suite has a global floor/baseline contract (`dispatched < 56 → exit 2`; `BATTERY_TAG_MUT_MIN_ASSERTIONS=21`; `MIN_SUITES=12`) and the registry battery re-pays a green-baseline preflight per leg — the contract surgery cost exceeds the win at this target. Tracked by #8006 remainder.
- *New per-suite selector env (`SCRIPTS_ONLY`)* → unnecessary; `SCRIPTS_SHARD` on a 3-registration group already yields one suite per leg. Reuses the tested mechanism instead of adding a second carrier (which would need the same `unset` discipline — `test-all.sh:684` — as `SCRIPTS_SHARD`).
- *Direct `bash <path>` steps in ci.yml* → rejected: double coverage trips `lint-orphan-test-suites.sh`'s DOUBLE_COVERED check, and bypasses `run_suite`'s KILLED/budget/timing taxonomy.

### Repo research (fan-out findings)

- `TEST_TIMING_LOG` per-leg artifacts (`suite-timings-scripts-{0,1,2}`) upload `if: always()` keyed on `strategy.job-index` — already live; this plan's simulation consumed run 35743569887's artifacts.
- Leg membership is LC_COLLATE-dependent (`test-all.sh:817-826`): all balance derivation MUST come from CI artifacts under C collation, never local `--enumerate`.
- `SCRIPTS_SHARD` is group-scoped to `TEST_GROUP=scripts` (`test-all.sh:653`) and `unset` at `:684` — the heavy job needs the scope widened to `{scripts,scripts-heavy}`.
- `test-all-enumerate-toolchain.test.sh:308` derives groups via `sed 's/…\(all|[a-z|]*\))…/\1/p'` and a `^[a-z]+$` check at :319 — both exclude `-`; `scripts-heavy` breaks the derivation → widen both to admit `[-]` (fail-closed fixture precondition, so this surfaces loudly).
- Aggregator `test` (`ci.yml:1419`) rolls matrix legs into one `needs.<job>.result`; adding `test-scripts-heavy` is the documented one-entry-per-site edit (`needs:`, `env:`, `entries=()`) — but `ci-test-aggregator-diagnosis.test.sh` pins more than the count: W2 `== 4` (:409), success-line needle (:166, :283 ↔ ci.yml :1555), `run_body` 4-arg fixture (:135-141), MIN_ROWS itemisation (:422-432), and the `failure` arm at ci.yml :1503 special-cases only `test-scripts` for matrix wording — widen to both matrix jobs.
- `scripts-shard-totality-mutations.sh` ROW5 anchors the literal `shard: ["1/3", "2/3", "3/3"]` (:297) — K bump breaks the anchor; update it AND add a row mutating the heavy job's matrix.
- `scripts-shard-totality.test.sh` derives its reference from column-0 `if want_scripts` blocks (:123-132) and its leg list from the `test-scripts:` job block (:169-178) + wire check (:201-210) — suites moved under `want_scripts_heavy` leave BOTH scopes → a `scripts-heavy` pass is required or the heavy group's partition is unguarded (silent coverage loss — the worst kind here).
- `prod-version-drift-check.test.sh:751` derives the longest `needs:` path over all ci.yml jobs; keep `test-scripts-heavy` `timeout-minutes ≤ 60` so `test-scripts` stays on a longest path. **Asymmetry to verify at implementation:** `green2-test-scripts-at-boundary` (:2085-2091) *lowers* `test-scripts` to `v2 = threshold − tail − (ci_declared_path − test-scripts)`; if `v2 < 60`, the heavy leg's 60 becomes the max needs member and the expected-crit arithmetic mismatches → false red. Implementer must confirm `v2 ≥ 60` or extend the B9 derivation to take max over both matrix jobs.
- `scripts-shard-totality.test.sh` internals to update for the heavy pass (all hardcode `scripts`): `enumerate_leg` `TEST_GROUP=scripts`/`--enumerate scripts` (:89-99), reference floor `REF_N >= 100` (:157 — scripts-calibrated; the heavy floor is exactly 3 and must NOT copy the 100), malformed/zero-assignment/unset rows (:316,:342,:356,:365), `MIN_ROWS=16` (:377 — re-derive per the file's itemized-floor discipline).
- `ci-test-aggregator-diagnosis.test.sh` also pins the `want` env→needs map at :382-389 — add `SCRIPTS_HEAVY_RESULT: test-scripts-heavy` (a miswired env var passes all the pins the plan originally listed).
- `ship-battery-owed.test.sh:705` extracts `(test-webplat|test-bun|test-scripts|web-platform-build)` — `test-scripts` prefix-matches `test-scripts-heavy`; update the premise comment AND anchor/order the alternation longest-first.
- `test-all-infra-coverage-notice.test.sh` has TWO loops: :227 `all webplat bun scripts infra` and :243 `for group in webplat bun scripts` ("the exact invocations ci.yml uses") — both gain `scripts-heavy`.
- `plugins/soleur/test/fullsuite-merge-gate.test.ts:50` `SHARDS = ["webplat","bun","scripts","infra"]` + positional regex `scripts\/test-all\.sh\s+([A-Za-z]+)` (:145) — the regex cannot match the hyphenated `scripts-heavy` positional arg, so a prescribed `test-all.sh scripts-heavy` invocation would evade the CEILING fixture. Add `scripts-heavy` to `SHARDS` and widen the class to `[A-Za-z-]+` (the `_SHARD=` env-name branch already catches any new selector by construction).
- Doc drift (LOW): `plugins/soleur/skills/work/SKILL.md:1160` lists `TEST_GROUP=` values `(all|webplat|bun|scripts)`; `work/SKILL.md:1037` §9 shard map routes `tests/`+root `scripts/` paths to group `scripts` (a diff touching only a moved suite would gate nothing); `plugins/soleur/skills/ship/SKILL.md:364` + `ship/scripts/battery-owed.sh:26` AND `:375-377` (the `want_*` name list) enumerate the four gate jobs — all gain `scripts-heavy`/`test-scripts-heavy`.
- ci.yml prose sweep (LOW, all must be re-derived not carried): `:57`, `:870` ("3 shards"), `:873-885` ("all three job blocks" lockstep note → four), `:1226-1230`, `:1331-1344`, `main-health-monitor.yml:88` ("4 sites" gitleaks).
- Nested-runner inheritance: `battery-tag-authorship-mutations.test.sh:85` shells subjects with `BATTERY_TAG_RUNNER=$REPO_ROOT/scripts/test-all.sh` (subjects run `TEST_GROUP=all`); `run-all.sh` does NOT invoke test-all.sh. Both are protected by the `unset SCRIPTS_SHARD` at `test-all.sh:684` — verified: job-level env is dropped before any suite executes, so children never inherit the shard selector. Keep the unset; the widened scope check must still run BEFORE it.
- `main-health-monitor.yml` (unsharded `test-all.sh`, `TEST_GROUP=infra`, `JOBS=1`), `lefthook.yml:356`, `grok-pre-push-gate.sh:165` — none set `SCRIPTS_SHARD`; unaffected except via `TEST_GROUP=all` coverage (item 6).

### External research decision (Phase 1.6)

Skipped — internal CI topology change with an already-designed mechanism (#8006) and repo-specific guard contracts; external best practice has no authority over the chokepoint semantics.

### Related issues

Refs #8006 (partially satisfies — the K/rebalance arm; the label-keyed partition mechanism stays open), #7902, #7931, #8231, #8322, #8045, #8163, #7942.

## Proposed Solution

**Phase 1 — runner (`scripts/test-all.sh`), tests first per `cq-write-failing-tests-before`:**

1. Extend the failing guards first (they must go red on the absent group): `test-all-enumerate-toolchain.test.sh` derivation (`[a-z|]*` → `[a-z|-]*`, `^[a-z]+$` → `^[a-z-]+$`), `scripts-shard-totality.test.sh` gains a `scripts-heavy` pass (reference scope `want_scripts_heavy`, leg list from the `test-scripts-heavy:` job block, wire check, union/totality, per-leg non-empty), aggregator diagnosis fixtures updated (W2 `== 5`, 5-arg `run_body`, success-line needle, MIN_ROWS re-derived), `ship-battery-owed.test.sh:705` alternation anchored/longest-first, `test-all-infra-coverage-notice.test.sh:227` loop gains `scripts-heavy`.
2. `test-all.sh`: `TEST_GROUP` validator accepts `scripts-heavy` (`:617-625` + usage strings); `want_scripts_heavy() { [[ "$TEST_GROUP" == "all" || "$TEST_GROUP" == "scripts-heavy" ]]; }` beside `:710-717`; the three heavy registration sites (`:2509-2515` battery incl. its `skip_suite` relevance arm, `:2872` tag-authorship, `:2983-2991` run-all incl. relevance arms) re-gate to `want_scripts_heavy`; SCRIPTS_SHARD group-scope refusal widened to `scripts|scripts-heavy` (`:653-659`); `_suite_budget_ms` unchanged (label-keyed; the battery keeps 2500000). `_shard_selects` untouched — round-robin over a 3-registration group IS one-suite-per-leg.
3. New: `TEST_GROUP=all` enumerate assertion — `--enumerate all` covers the heavy labels (pins requirement: heavy suites never leave the full gate).

**Phase 2 — workflow (`.github/workflows/ci.yml`):**

4. `test-scripts` matrix `["1/3","2/3","3/3"]` → `["1/5"…"5/5"]`; `timeout-minutes: 60` retained (its justification comment re-derived: the battery budget no longer lives on this leg).
5. New `test-scripts-heavy` job: clone of the `test-scripts` step shape (checkout `fetch-depth: 0`, gitleaks, likec4, setup-bun — identical pins per the lockstep note at `ci.yml:881-885`), `matrix.shard: ["1/3","2/3","3/3"]`, `SCRIPTS_SHARD` env, `TEST_TIMING_LOG` + artifact upload, `timeout-minutes: 60` (≤ 60 keeps `test-scripts` on the longest `needs:` path).
6. Aggregator: `needs:` + `SCRIPTS_HEAVY_RESULT` env + `entries=()` + success-line literal + `failure` arm matrix wording covers both `test-scripts*`.
7. ADR-231: move the stale K-simulation comment block (`ci.yml` ~:998-1136) to a new runbook `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md` carrying the re-derived table (below) + reproduction recipe; ci.yml keeps a 2-line pointer comment.

**Phase 3 — guards for the new surface + docs:**

8. `scripts-shard-totality-mutations.sh`: update ROW5 anchor to the new light matrix literal; add a row mutating the heavy matrix literal; add a row that re-gates a heavy registration back under `want_scripts` (must red the reference-derivation asymmetry).
9. `scripts-shard-runtime-coverage.test.sh`: extend `job_block()` coverage to `test-scripts-heavy` (or pin the toolchain minimal contract explicitly).
10. ADR-238 (provisional; ship gate re-verifies): "Carve cost-heavy scripts suites into `TEST_GROUP=scripts-heavy`" — records the group-taxonomy contract consumed by ≥6 surfaces.
11. C4: checked all three `.c4` files — CI-internal topology, no external actor/system/relationship changes; no C4 edit. (Checked: no new external actor, no new external system/vendor, no new data store; GitHub Actions runner topology is not modeled in `model.c4`.)

## Technical Considerations

- **Why a group, not a pin:** `SCRIPTS_SHARD=k/3` over exactly three registrations yields one suite per leg — the existing tested mechanism, zero new carrier. A label→leg pin inside `_shard_selects` would break the guard's any-K totality property (a pin to leg 4 assigns nothing under K=2) and rot on ordinal churn.
- **Relevance gating survives:** both heavy relevance-gated registrations keep their `run_suite`/`skip_suite` chokepoint shape under `want_scripts_heavy`; on CI `_diff_touches` is unconditional-true (`test-all.sh:1187`), so they always run in the heavy job; locally they still decline.
- **Runner-pool risk (declared):** 5+3 legs vs 3 today. ci.yml's own measurement (:1084-1110) shows runner availability is the binding constraint on 76% of runs (median start spread 412 s, max 1708 s). Execution-term win (39→~10 min) dominates, but this is the measured-risk class — AC below requires post-merge observation of the first three `main` push runs.
- **Same-run validation:** because the heavy job joins `test`'s `needs:` in this PR, the PR's own CI run exercises the new topology end-to-end before merge — the dark-launch concern (`wg-dark-launch-deploy-gates`) is satisfied by the PR run itself, since no new check *logic* is introduced (the same suites, same runner, same toolchain; only scheduling changes).

## User-Brand Impact

- **If this lands broken, the user experiences:** the required `test` merge gate — a red-forever `test` blocks every merge (loud, recoverable, internal); the brand-shaped failure is a *silent green*: a mis-wired heavy group runs zero suites green, and a plugin update ships built on suites that never ran (the #7471 defect class).
- **If this leaks, the user's [data / workflow / money] is exposed via:** no data surface — the vector is trust in the release pipeline (false-green → unverified code ships).
- **Brand-survival threshold:** `single-user incident`

*CPO sign-off (2026-09-22, domain review below): "CPO confirms `single-user incident` threshold via the silent-green release path; totality guard + zero-assignment refusal are the load-bearing mitigations. Approved."*

## Observability

```yaml
liveness_signal:
  what: "test-scripts / test-scripts-heavy leg durations + suite-timings artifacts"
  cadence: "per CI run"
  alert_target: "required `test` check on every PR + post-merge monitor (post-merge-monitors the main-push runs)"
  configured_in: ".github/workflows/ci.yml (test, test-scripts, test-scripts-heavy jobs; actions/upload-artifact of TEST_TIMING_LOG)"
error_reporting:
  destination: "GitHub Actions job log + required-check status"
  fail_loud: "non-success leg conclusion surfaced by the `test` aggregator's per-shard diagnosis (ci.yml:1477-1528); zero-assignment leg refuses exit 2 (test-all.sh:2993-3014)"
failure_modes:
  - mode: "heavy group mis-wired (SCRIPTS_SHARD on wrong TEST_GROUP or empty leg)"
    detection: "exit-2 group-scope refusal / zero-assignment refusal; scripts-shard-totality guard in test-bun leg"
    alert_route: "required `test` check goes red — merge blocked, loud"
  - mode: "leg duration regresses above target"
    detection: "suite-timings artifacts + job duration on the first three post-merge main runs (follow-through script below)"
    alert_route: "post-merge monitor / follow-through issue"
  - mode: "suite silently dropped from all groups"
    detection: "scripts-shard-totality union-vs-reference assertion + lint-orphan-test-suites registration walk"
    alert_route: "required `test` check red"
logs:
  where: "GitHub Actions run logs + uploaded suite-timings-scripts-{i} artifacts"
  retention: "GitHub default artifact/log retention"
discoverability_test:
  command: "bash scripts/test-all.sh --enumerate scripts-heavy"
  expected_output: "SUITE_REGISTRATION"
```

**Follow-Through Enrollment (soak AC below):** script `scripts/followthroughs/ci-leg-durations-8006.sh` (new in this PR) — queries the first three `main`-push CI runs after merge via `gh api .../jobs`. Exit contract per `runbooks/followthrough-convention.md`: leg > 15 min → exit 1 (FAIL), fewer than 3 qualifying runs yet → exit 2 (TRANSIENT/not-yet), else 0. The sweeper runs probes under `env -i` with only directive-declared secrets, so the tracker directive MUST carry `secrets=GH_TOKEN` (unauthenticated `gh` → exit 2 on every sweep → silent never-close) and an ISO-8601 `earliest=`: `<!-- soleur:followthrough script=scripts/followthroughs/ci-leg-durations-8006.sh secrets=GH_TOKEN earliest=<merge+1d ISO-8601> -->` + the `follow-through` label.

## Guard Contract

### Guard 1 — scripts-heavy partition totality

**Property.** Every suite registered under `want_scripts_heavy` is assigned to exactly one `test-scripts-heavy` leg, and no `test-scripts` leg runs it.

**Assembly.** The `run_suite`/`skip_suite` chokepoint (`test-all.sh:905,1066`) is the single structural gate all registrations pass through; the reference set is derived independently (`want_scripts_heavy` block extraction + `--print-suite-globs`), never from the partition; the leg list is derived from the `test-scripts-heavy:` job block's matrix values; the wire is the job-level `SCRIPTS_SHARD: ${{ matrix.shard }}` interpolation.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Re-gate one heavy registration back under `want_scripts` | RED — mechanism: the heavy leg that owned it now has zero assigned suites → zero-assignment refusal / per-leg-non-empty row (heavy reference=2/union=2 stays consistent; do NOT claim reference asymmetry) |
| 2 | Delete the `SCRIPTS_SHARD` env binding on `test-scripts-heavy` | RED (all legs run all 3 suites → duplicate-assignment / wire assertion) |
| 3 | Change heavy matrix to `["1/3","2/3"]` (drop a leg) | RED (one suite assigned nowhere → union < reference) |
| 4 | Add a 4th heavy registration with heavy matrix `["1/3","2/3"]` (one leg short) | RED (one suite assigned nowhere → union < reference). NOTE: a 4th registration on K=3 does NOT red — round-robin still partitions totally; the deficit must come from a missing leg |
| 5 | (harness) Point the heavy reference extractor at a nonexistent `want_*` name | RED (0-member reference must fail, not pass vacuously) |
| 6 | (harness) Mutate the guard's heavy-reference extractor (or the `--enumerate` emitter's label field) so reference and runner disagree on one label | RED — the two independent derivations must diverge mechanically, since both read the same `run_suite` literals and no single runner edit produces a mismatch |

### Guard 2 — group-name derivation honesty

**Property.** `test-all-enumerate-toolchain.test.sh`'s derived group list equals the runner's TEST_GROUP case arm — a new group can never escape enumeration coverage silently.

**Assembly.** The single `case "$TEST_GROUP" in` arm in `scripts/test-all.sh` (:617-625) and the sed/regex derivation in `scripts/test-all-enumerate-toolchain.test.sh` (:308,:319).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Add a `case` member the derivation regex cannot parse | RED (derivation drift → fixture precondition exit 1) |
| 2 | Revert the `-` widening while `scripts-heavy` exists | RED (precondition fails: derived list empty/invalid) |
| 3 | Rename `scripts-heavy` in the runner only | RED (ci.yml wire + enumerate reference disagree) |

### Guard 3 — `test` aggregator covers the heavy leg

**Property.** A failing `test-scripts-heavy` leg fails the required `test` check, and the failure text names it as a matrix leg.

**Assembly.** `needs:`/`env:`/`entries=()`/success-line/`failure`-arm wording in the `test` job (`ci.yml:1419-1528`), asserted by `ci-test-aggregator-diagnosis.test.sh` over synthetic result tuples.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Omit `test-scripts-heavy` from `needs:` | RED (W2 count + success-line needle) |
| 2 | `test-scripts-heavy` failure tuple in the fixture set | RED (per-leg failure classification row) |
| 3 | Narrow the `failure` arm back to `== "test-scripts"` only | RED (heavy matrix leg must get matrix-rollup wording) |

## Domain Review

**Domains relevant:** Engineering, Product (sign-off only)

### Engineering

**Status:** reviewed
**Assessment:** (soleur:engineering:cto, 2026-09-22) — Recommended the `scripts-heavy` carve-out over in-place label pinning (breaks any-K totality, pins rot) and over internal battery splitting (global floors + per-leg baseline re-pay). Flagged the enumerated-consumer blast radius: enumerate-toolchain derivation excludes `-`, the SCRIPTS_SHARD group-scope refusal, Guard 1's `want_scripts`-scoped reference leaving the heavy group unguarded, ROW5 anchor, the aggregator suite's five pins (not just the count), `want_scripts_heavy` MUST include `all`, `timeout-minutes ≤ 60` to keep `test-scripts` on the longest needs-path, runtime-coverage/infra-notice/battery-owed-regex secondaries, ADR-231 relocation, and +5-leg runner-pool risk. All folded into phases above.

### Product/UX Gate

**Tier:** none (no UI surface; mechanical override did not fire — no `components/**`/`app/**` paths in Files lists)
**Decision:** reviewed — CPO confirmed `single-user incident` threshold via the silent-green release path; totality guard + zero-assignment refusal named as the load-bearing mitigations.
**Agents invoked:** soleur:product:cpo
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

## Architecture Decision (ADR/C4)

This plan changes an enumerated contract (TEST_GROUP taxonomy) consumed by ≥6 surfaces — a dispatch-boundary change per Phase 2.10 detection.

- `### ADR` — **create ADR-238 (provisional)** via `soleur:architecture`: "Carve cost-heavy scripts suites into `TEST_GROUP=scripts-heavy`." Implementation task in Phase 3. On ordinal collision at ship, renumber AND sweep `grep -rn 'ADR-238' knowledge-base/project/{plans,specs}/feat-ci-test-shard-speedup/` per the renumber-sweep rule.
- `### C4 views` — none: enumerated every external actor (none new), external system/vendor (none new — GitHub Actions is already modeled), data store (none), access relationship (none). CI-internal job topology is below the C4 modeling floor.
- `### Sequencing` — ADR authored in this PR describing the landed state (no soak gate on the decision itself).

## Open Code-Review Overlap

Queried open `code-review` issues against the file list: **#7942** ("Two mutation batteries in plugins/soleur/test/ are named *.mutation.sh and run in no gate") — **acknowledge**: different files (plugins/soleur/test `*.mutation.sh`, not the three moved suites); this plan neither fixes nor worsens it. No other matches.

## Acceptance Criteria

- [ ] AC1: `TEST_GROUP=scripts-heavy` is accepted by the runner's group validator; `bash scripts/test-all.sh --enumerate scripts-heavy` emits exactly the three heavy `SUITE_REGISTRATION` records.
- [ ] AC2: `--enumerate all` output still contains all three heavy labels (full-gate coverage preserved, ADR-183).
- [ ] AC3: `SCRIPTS_SHARD=k/3` with `TEST_GROUP=scripts-heavy` partitions 3 registrations → one suite per leg; the group-scope refusal accepts both `scripts` and `scripts-heavy` and still rejects other groups.
- [ ] AC4: `ci.yml` `test-scripts` matrix is K=5; `test-scripts-heavy` exists with K=3, `timeout-minutes ≤ 60`, `fetch-depth: 0`, `SCRIPTS_SHARD` env, and `TEST_TIMING_LOG` upload; aggregator `needs`/`env`/`entries`/success-line/failure-arm cover it.
- [ ] AC5: `scripts-shard-totality.test.sh` covers both groups (union==reference, no duplicates, non-empty legs, wire check) and `scripts-shard-totality-mutations.sh` anchors both matrix literals + the re-gate mutation row.
- [ ] AC6: On this PR's own CI run, every `test-scripts*` leg completes ≤ 15 min and the `test` aggregator is green (the PR run is the topology's own end-to-end validation).
- [ ] AC7 (soak): the follow-through script `scripts/followthroughs/ci-leg-durations-8006.sh` exits 0 over the first three post-merge `main` runs (no `test-scripts*` leg > 15 min); tracker filed with the `soleur:followthrough` directive.
- [ ] AC8: The stale K-table comment block is relocated to `runbooks/ci-test-scripts-sharding.md` with the re-derived table; `wc -c .github/workflows/ci.yml` does not grow vs. `origin/main`. The suite-count figures in this plan ("~237 effective registrations", ci.yml's "392 suites", "512-suite CI-order") are three different populations — re-derive from `--enumerate` + CI artifacts during implementation and state the derivation in the runbook.
- [ ] AC9: ADR-238 exists; all enumerated consumers updated (enumerate-toolchain derivation, aggregator diagnosis pins incl. W2/success-line/run_body/MIN_ROWS, ship-battery-owed regex, infra-coverage-notice loop, runtime-coverage).
- [ ] AC10: `main-health-monitor.yml`, `lefthook.yml`, `grok-pre-push-gate.sh` full-gate (`TEST_GROUP=all`) runs still cover the heavy suites — asserted via the AC2 enumerate assertion plus a monitor-run smoke (the monitor is K-agnostic).

## Test Scenarios

- Given `TEST_GROUP=scripts-heavy SCRIPTS_SHARD=2/3`, when `test-all.sh` runs, then exactly `battery-tag-authorship-mutations` executes and the other two heavy labels are not executed (they are on other legs).
- Given `TEST_GROUP=scripts-heavy` without `SCRIPTS_SHARD`, when it runs locally, then all three heavy suites run (serially) — and under `TEST_GROUP=all` they run exactly once.
- Given a diff touching none of the relevance paths, when `test-all.sh scripts` runs locally, then the heavy suites show `skip=<reason>` declines under their new group gate and zero under `scripts`.
- Given the `test-scripts-heavy` job with a deliberately emptied matrix leg, when CI runs, then the leg refuses (exit 2) — never green over zero work.
- Given a PR that re-gates a heavy suite under `want_scripts`, when `scripts-shard-totality` runs, then RED.
- Regression: the failure mode this fixes — one leg holding ≥20 min of suites — is covered by AC6's measured bound, not by assertion on ordinal luck.

## Success Metrics

- `test` gate time-to-complete on `main` pushes: from ~40 min (worst observed leg 38.4 min + aggregator) to **≤ ~12 min** including per-leg setup; suite-execution leg max ≈ 9–10 min.
- No reduction in executed suite count: union of all legs == full registration set (guarded, not sampled).

## Dependencies & Risks

- **Runner-pool contention** (+5 parallel legs): declared risk; mitigated by AC6/AC7 measurement rather than assumption.
- **Ordinal churn:** the light group's K=5 partition remains positional (known, accepted — #8006 tracks the principled fix); the heavy group is immune by construction (3 registrations, 3 legs).
- **Guard anchor drift:** ROW5-class anchors are exact-text — plan enumerates every anchor site; a missed one fails loudly (mutation battery exits 3).
- **`#8006` stays open:** this plan delivers the rebalance arm; the label-keyed partition mechanism is still its open remainder (Non-Goals).

## Non-Goals (documented deferrals)

- Internal splitting of `registry-gate-mutation-battery` / `battery-tag-authorship-mutations` / `run-all.sh` — deferred: global floor contracts + per-leg baseline re-pay make it net-negative at this target; #8006 remainder.
- Intra-leg suite parallelism — #8231 (CI forces serial by design; local-only track).
- Affected-suites/ratchet local gate — #8322.
- Lefthook pre-commit battery cost — #8045.
- Battery-under-contention ceiling — #8163.
- plugins/soleur/test `*.mutation.sh` gating — #7942 (acknowledged overlap).

## References & Research

- Mechanism + constraints: #8006 body (LPT rejection, any-K totality constraints, timing-artifact bootstrap), `ci.yml:988-1136` (K-simulation history + dispatch measurement), `scripts/test-all.sh:835-842,905,1066,2993-3014`.
- CI measurement: `suite-timings-scripts-{0,1,2}` artifacts, run 35743569887 (2026-09-22); reconstructed CI order = per-leg TSV row interleave (execution order).
- Plans: `knowledge-base/project/plans/archive/20260908-132617-2026-09-07-fix-release-await-ci-ceiling-vs-ci-duration-plan.md`, `knowledge-base/project/plans/2026-09-09-chore-ci-concurrency-and-workflow-run-deploy-plan.md`, `knowledge-base/project/plans/2026-05-12-feat-ci-test-job-speedup-plan.md`.
- ADRs: 133, 181, 183, 196, 212, 217, 231.
