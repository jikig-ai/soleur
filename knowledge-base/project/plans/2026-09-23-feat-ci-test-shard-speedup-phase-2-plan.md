---
title: "ci: test-shard speedup phase 2 — split the mutations battery, K=6, parallel guard enumeration, heavy manifest"
type: feat
date: 2026-09-23
slug: feat-ci-test-shard-speedup-phase-2
branch: feat-one-shot-8006-ci-speedup-phase2
issue: 8006
closes: []
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# ci: test-shard speedup phase 2

## Overview

Phase 2 of #8006's CI wall-clock work. Phase 1 shipped the heavy carve-out
(`test-scripts-heavy`, PR #8585), the duration-aware label→leg manifest
(`scripts/suite-shard-legs.tsv` + sticky-LPT generator, PR #8612, ADR-240),
and a manifest regen from run 35911999612 (PR #8656, 489 labels, predicted
legs 475.9s–491.1s).

Measured on run 35911999612 (job wall times incl. ~60s setup):

| Job | Wall |
|---|---|
| `shard-totality-mutations` | **9m35s** — the long pole |
| `test-scripts` legs 1–5 | 7m22s–9m02s |
| `test-scripts-heavy` legs 1–3 | 6m42s–8m32s |
| everything else | ≤4m38s |

This plan ships four changes to bring the worst job to **≈8.5m or less**:
(A) split the mutations battery into 2 matrix legs, (B) `test-scripts`
K=5→K=6 with a manifest regen, (C) parallelize the totality guard's
`--enumerate` child invocations, (D) extend the manifest architecture to
`scripts-heavy`. One PR; if review prefers, A+C ship together and B+D ship
together (the file overlap is only the battery and ci.yml).

## Problem Statement / Motivation

Every merge and every release waits on `test`, which waits on the slowest
job in the run. After phase 1 the wall is ~10 min, dominated by:

- **`shard-totality-mutations` at 9m35s.** The battery runs a CONTROL plus
  21 rows, each invoking the guard, which itself drives ~40 sequential
  `bash scripts/test-all.sh --enumerate` children per invocation. Two
  independent levers exist on this one job: split the row set across two
  matrix legs (A), and stop running the guard's independent enumerations
  serially (C). Both are inside the same two files and compose — A halves
  the row count per leg, C roughly quarters the per-guard-invocation cost.
- **`test-scripts` worst leg 9m02s.** With the manifest in place the legs
  are balanced (predicted 476–491s of suite time), so the remaining lever
  is K. K=6 moves ~39 min of light suite work to ~6.5 min/leg ≈ ~7.5–8m
  wall — the same one-line-edit class phase 1 measured (K=3→20.73m,
  K=5→10.77m).
- **`test-scripts-heavy` leg-1 8m32s.** Three registrations over three legs
  is already a bijection — duration-aware assignment (D) cannot beat that
  and is honest scope for insertion-stability, not speed. The ≤8.5m target
  is met without touching the battery's own runtime; if review decides the
  heavy leg must go under 8m, the lever is splitting
  `tests/scripts/test-registry-gate-mutation-battery.sh` itself (the A
  mechanism applied to the heaviest suite) — recorded as an alternative,
  not planned work.

## Research Insights

### Premise Validation (Phase 0.6)

- `#8006` verified OPEN via `gh issue view` — title: "ci: matrix-leg
  balance — LPT does not deliver insertion-stability and the chokepoint
  cannot compute it".
- `#8612` MERGED 2026-09-23T20:30Z (manifest architecture), `#8656` MERGED
  (regen from run 35911999612), `#8585` MERGED (heavy carve-out + K=5).
  `#8329` OPEN — the affected-test-gate PR that also edits
  `scripts/test-all.sh` and `scripts/test-all-affected.test.sh` (conflict
  risk recorded in Dependencies & Risks). `#8665` OPEN — this branch's
  draft PR, exists already.
- Cited artifacts verified on this branch: `scripts/suite-shard-legs.tsv`
  (489 labels + `# n=5` header), `scripts/test-all.sh`,
  `scripts/regenerate-shard-manifest.py`,
  `plugins/soleur/test/scripts-shard-totality-mutations.sh` (21 rows,
  MIN_ROWS=21), `plugins/soleur/test/scripts-shard-totality.test.sh` (611
  lines, light + heavy passes), `plugins/soleur/test/scripts-shard-manifest.test.sh`,
  `plugins/soleur/test/regenerate-shard-manifest.test.sh`,
  `plugins/soleur/test/ci-test-aggregator-diagnosis.test.sh`,
  `scripts/test-all-affected.test.sh`, `scripts/check-adr-ordinals.sh`,
  `scripts/followthroughs/ci-leg-durations-8006.{sh,test.sh}`,
  `.github/workflows/ci.yml`, the packed-string learning
  `knowledge-base/project/learnings/2026-09-23-a-packed-string-searched-by-glob-is-a-quadratic-map.md`,
  ADR-240, runbook `ci-test-scripts-sharding.md`.
- `shard-totality-mutations` verified ABSENT from
  `infra/github/ruleset-ci-required.tf` and `scripts/required-checks.txt`
  (grep, rc=1) — a matrix inside the existing job name needs no
  aggregator/ruleset/synthetic-checks change. Its ci.yml comment already
  documents it as non-required.
- ADR corpus grepped for the proposed mechanisms: **ADR-240 §Rejected
  alternatives contains "Per-group manifests (heavy included). Unneeded
  today: 3 suites / 3 legs is already optimal."** — change D implements an
  explicitly-rejected alternative, so the ADR is AMENDED in this PR
  (rejected-premise reversal), not superseded. ADR-238 (heavy taxonomy),
  ADR-235 (generated-artifact conflict rules — sticky-LPT exists because
  of it), ADR-181 (relevance gating — skip_suite consumes the same
  label-keyed lookup), ADR-193 (instrument self-test convention),
  ADR-176 (checkpoint semantics — this plan file), ADR-231 (workflow
  byte-budget — ci.yml growth kept minimal).
- Correction to a task-brief claim, verified against code: "ci.yml
  aggregator `test` needs: is byte-pinned by
  `ci-test-aggregator-diagnosis.test.sh` W3" — the needs-cardinality pin is
  **W2** (asserts exactly 6 watched legs) and the armed-leg shape pin is
  **W3** (encryption-posture only). `shard-totality-mutations` is not in
  `test`'s needs list at all, so adding matrix legs to it touches the
  aggregator nowhere. If the split were done as two new job names instead,
  W2 would still not reach them (they stay out of needs) — the real reason
  to prefer a matrix is job-identity stability, not aggregator pins.
- Second correction: the brief's "~11 leg enumerations per guard call" —
  the guard actually drives ~40 child `bash test-all.sh --enumerate`
  invocations (6 light legs + 7 altK + 10 malformed + 2 spec probes + 1
  unset + 3 heavy legs + 5 heavy altK + 1 heavy-over + 4 heavy-malformed +
  1 heavy-unset + 1 TEST_GROUP=all + 1 reference glob pass). The
  parallelization target is bigger than stated, which strengthens C.

### Mechanism Minimality (Phase 0.6b)

**Property List** (what the ask actually needs):

- P1: `shard-totality-mutations` wall ≤ ~5m without losing a mutation row
  or its vacuity floor.
- P2: worst `test-scripts` leg ≤ ~8m wall.
- P3: the guard's enumeration cost scales sub-linearly with leg count
  (helps the standalone guard suite inside `test-scripts` legs too).
- P4: heavy-group assignments keep the same fail-closed +
  deterministic-fallback semantics the light group now has, so a future
  heavy registration cannot silently co-locate with the battery on one leg.
- P5: every co-change the four edits force (probe leg counts, mutation
  anchors, runbook literals, lint sections) is enumerated and lands in the
  same diff — no green-over-stale-literal tail.

**Cut List** — mechanisms considered and removed:

- *Two new job names for the battery split* → buys nothing over a 2-leg
  matrix on the existing job; adds ruleset/canonical-checks surfaces for
  zero gain (the job is non-required by design).
- *An in-file `[heavy]` section inside `suite-shard-legs.tsv`* → a second
  file (`suite-shard-legs-heavy.tsv`) buys the same property while the
  light file's strict parsers (runner row-parse, ⊆ lint, leg-range check)
  stay verbatim; a section marker would force section-awareness into three
  parsers.
- *Splitting `registry-gate-mutation-battery` internally* → its own global
  floor contracts (MIN_SUITES-class) make internal row-splitting a heavier
  change than the whole rest of this plan; deferred, see Non-Goals.
- *K>6* → diminishing returns (~6.5m/leg at K=6 already meets P2) plus
  org-level runner-pool pressure already tracked by #8450.

### Value-Proposition Measurement (Phase 0.6c)

The claimed saving is wall-clock, so the baseline is the measured one:
run **35911999612** job durations (above). Predicted post-change wall:

- `shard-totality-mutations`: 21 rows ≈ 9.5m serial → ~5m per leg after
  A (row halving) × C (enumerate parallelization). Command that produced
  the per-invocation cost: the guard's own enumerate calls are ~1.4s each
  (measured in the packed-string learning) and a guard run issues ~40 —
  parallelizing to ~10-way puts the enumeration floor near the slowest
  single child.
- `test-scripts`: manifest-predicted 476–491s/leg at K=5 → ~390–410s/leg
  at K=6 + ~60s setup ≈ 7.5–8m wall.
- `test-scripts-heavy`: unchanged ~8.5m (bijection; D buys stability).
- Success bound per VERIFY: worst job ≈8.5m or less on the PR's own run.

### Repo research (fan-out findings)

- `scripts/test-all.sh:706` — manifest engagement is
  `(( _SHARD_N > 0 )) && [[ "$TEST_GROUP" == "scripts" ]]`; heavy is
  excluded by that one predicate. Parse/validate/dup-check is label-generic
  (`:732-776`) — the heavy arm reuses it with a different default path.
  `SOLEUR_SHARD_MANIFEST` (`:708-726`) is a single override consumed and
  unset at `:806`.
- `_shard_selects` (`scripts/test-all.sh:985-1020`) — manifest lookup →
  `cksum % _SHARD_N + 1` fallback (`:1007`); positional arm at `:1015`.
  The call shape `_shard_selects "$label" || return 0` at `:1085` (run_suite)
  and `:1268` (skip_suite) is pinned by `test-all-affected.test.sh` A3 —
  do not alter it.
- Heavy block (`scripts/test-all.sh:3450-3498`) — three registration
  *sites* (registry battery, tag-authorship, run-all), each making exactly
  one `run_suite`/`skip_suite` call → ordinals 1,2,3 → legs 1,2,3
  positionally. Confirmed bijection.
- `plugins/soleur/test/scripts-shard-totality-mutations.sh` — `row()`/
  `frow()`/bespoke structure (`:200-265`), CONTROL at `:271-278`, M-fixture
  block at `:476-502`, M4 at `:508-532` (computes `% 5` and `SCRIPTS_SHARD=…/5`
  literals at `:513,:521,:524`), MIN_ROWS floor at `:567-574`, dirty-tree
  refusal at `:91-103` (needs clean tree on 3 targets), EXIT-trap restore
  at `:80`.
- `plugins/soleur/test/scripts-shard-totality.test.sh` — `enumerate_leg`
  at `:89-100` (writes `$out`, rc masked by pipe through grep|cut under
  pipefail → rc IS meaningful for wait-capture), light leg loop `:230-240`,
  altK `{2,5}` `:287-301`, malformed loop `:315-323`, over/long probes
  `:341-362`, unset `:365`, heavy mirror `:392-575`, MIN_ROWS=30 `:597`.
- `.github/workflows/ci.yml` — `test-scripts` matrix `["1/5".."5/5"]` at
  `:1013` with K=5 comment block `:998-1046`; `test-scripts-heavy` at
  `:1204-1268`; `shard-totality-mutations` at `:1296-1320`
  (timeout-minutes: 30, single run line); aggregator `test` at `:1369+`
  (needs list `:1375`, entries array `:1440` — byte-pinned by W1/W2, but
  unaffected here).
- `scripts/regenerate-shard-manifest.py` — `LIGHT_ARTIFACT` regex `:59`,
  `read_ci_leg_count` `:150-157` (test-scripts block only), `registered_labels`
  `:160-172` (`--enumerate scripts`), GENERATOR_VERSION "1" `:54`.
- `scripts/followthroughs/ci-leg-durations-8006.sh` — expected-leg contract
  at `:142-152`: `nlight -ne 5 || nheavy -ne 3 || nok -ne 8`. **K=6 makes
  every post-merge run non-qualifying → NOT YET forever → #8006 never
  auto-closes.** Co-change is mandatory, not optional.
- `plugins/soleur/test/ci-test-aggregator-diagnosis.test.sh` — W1
  (`:406-435`) env→needs exact `${{ needs.X.result }}` wiring, W2 (`:441-447`)
  needs-cardinality==6, W3 (`:450-493`) encryption-posture armed-leg shape.
- Live-corpus guards that react to changed `.sh` files:
  `scripts/guard-vacuity-floor.test.sh`,
  `scripts/lint-shell-capture-exit.test.sh` (+`.py`+`.baseline.txt`),
  `plugins/soleur/test/fixture-relative-assert.test.sh` (+ baseline; the
  battery already has a baseline row at `:304`), `scripts/lint-orphan-test-suites.sh`.
- `plugins/soleur/test/fixtures/admin-merge-ready/check-runs.json:119`
  names `shard-totality-mutations` — matrix legs display as
  `shard-totality-mutations (1-12)`. Synthetic fixture, not live gating;
  verify no test asserts the bare name against live check-runs.

### Institutional learnings applied

- `2026-09-23-a-packed-string-searched-by-glob-is-a-quadratic-map.md`
  (PR #8612, same session line): parallel indexed arrays + literal `==`,
  never packed-string/case-glob; `"${arr[@]}"` on empty arrays is a bash-3.2
  `set -u` death — all new iteration is index-based. Also: live-corpus
  guards carry construction contracts only CI showed — run the three named
  guards locally before pushing.
- `2026-09-20-the-ops-only-green-verdict-claimed-a-fact-the-gate-never-measured.md`
  — measured-baseline discipline; the D speed claim is corrected by
  measurement, not repeated.
- Battery design contract (file header, #7902): anchors are byte-exact
  unique strings; a drifted anchor fails the row loudly — every edit to
  the guard/runner must be swept for anchor overlap (listed per change).

### External research decision (Phase 1.6)

Skipped — strong local context. The mechanisms are already proven in-repo
(manifest architecture, matrix sharding, `&`/`wait` patterns), the ADR
governs the design, and the measurement source is this repo's own CI
artifacts. No external API or unfamiliar territory is touched.

### Related issues

- `#8006` (open, tracking) — this plan is its phase-2 arm; issue stays open
  for the leg-duration soak probe.
- `#8450` (open) — org 20-job concurrency ceiling; K=6 adds one leg —
  pressure acknowledged, decision already made to raise the ceiling
  (2026-09-21 brainstorm).
- `#8329` (open PR) — affected-test gate; edits `scripts/test-all.sh` +
  `scripts/test-all-affected.test.sh` — rebase ordering risk.
- `#7942`, `#8659` (open code-review) — see Open Code-Review Overlap.
- `#8231` intra-leg parallelism, `#8163` contention ceiling — Non-Goals.

## Proposed Solution

### Change A — split `shard-totality-mutations` into 2 matrix legs

`plugins/soleur/test/scripts-shard-totality-mutations.sh` gains a
`--rows A-B` flag; `ci.yml` matrixes the job over two ranges. Rows are
already serial in an isolated `mktemp` WORK dir, so index-splitting is
clean. Details:

- **Row indexing.** A `next_row` helper increments a `DECLARED` counter at
  every row call site — `row` calls, `frow` calls, and the bespoke blocks
  (ROW6 tautology, M4) — and returns whether that index is inside the
  selected range. Out-of-range call sites increment `DECLARED` but execute
  nothing. Row index = call-site order in the file (ROW1=1 … MUSTPASS=21;
  24 after D's M7–M9).
- **CONTROL + instrument self-test run on every leg.** A half-battery
  without a green unmutated control is void the same way the whole battery
  is; the control is one guard invocation and stays unconditionally first.
- **Flag contract.** `--rows` must match `^[0-9]+-[0-9]+$` with
  `1 <= A <= B <= DECLARED_TOTAL`; anything else exits 2 (same fail-closed
  convention as `SCRIPTS_SHARD`). Unset = all rows, preserving direct local
  invocation. Parse before WORK setup so a bad flag cannot leave a dirty
  checkout mid-restore.
- **Floor semantics (load-bearing).** Replace `MIN_ROWS=21` with three
  counters asserted at exit: `DECLARED == DECLARED_TOTAL` (constant, 21→24
  with D's rows — updated in the same edit that adds a row), `EXECUTED ==
  IN_RANGE` (no in-range row silently skipped), `IN_RANGE >= 1`. The floor
  counts TOTAL DECLARED rows, never executed rows — per the task brief, a
  per-half executed floor would false-positive on each half.
- **ci.yml** adds `strategy: { fail-fast: false, matrix: { rows: [...] } }`
  and `run: bash plugins/soleur/test/scripts-shard-totality-mutations.sh
  --rows "${{ matrix.rows }}"`. Job name unchanged → no aggregator,
  ruleset, required-checks, or synthetic-checks edits. `timeout-minutes`
  stays 30 (hang cap, not an estimate — the comment block is updated to
  say so). The `21 rows × ~12 leg-enumerations` comment updates to the new
  row count + split.

### Change B — `test-scripts` K=6

- `ci.yml` `test-scripts` matrix → `["1/6","2/6","3/6","4/6","5/6","6/6"]`;
  the `K=5`/`five positional` comment block is re-derived (K=6, ~39min/6
  ≈ 6.5m/leg + setup).
- `scripts/suite-shard-legs.tsv` regenerated (`# n=6`): the generator reads
  N from ci.yml itself, so after the ci.yml edit
  `python3 scripts/regenerate-shard-manifest.py --run 35911999612 --write`
  reuses the phase-1 run's per-suite timings (leg-agnostic label→ms data)
  and reassigns over 6 legs. Post-merge follow-up: regen again from the
  first green K=6 run.
- Co-change sweep (all literals pinned to 5):
  - `scripts-shard-totality-mutations.sh` ROW5 anchors → new K=6 literal
    (old: `["1/5".."5/5"]`, mutant drops `"6/6"` → declares 5 legs while
    partition computes mod 6; update the row description text).
  - M4 (`:513,:521,:524`): `% 5` and `…/5` → derive n from the committed
    manifest's `# n=` header (follows manifest n, per brief — not a new
    literal).
  - `scripts/followthroughs/ci-leg-durations-8006.sh` + `.test.sh`:
    `nlight` expected 5→6, `nok` 8→9, header's `(1/5..5/5)`/“8 legs” text.
    Without this every post-merge run is non-qualifying and the probe
    reports NOT YET forever — the silent-never-close failure class.
  - `scripts/test-all.sh:3442` “fans out over five legs” → six.
  - `runbooks/ci-test-scripts-sharding.md`: K=5 rows (~lines 17, 25),
    append the measured K=6 row to the K-simulation table (:113-117),
    “five legs” at :178.
  - `scripts-shard-totality.test.sh` altK `{2,5}`: keep — under N=6 both
    values are non-canonical, which is exactly what the rows exist to
    prove. The configured-N path is covered by the ci.yml leg loop.
  - No edit needed: `scripts-shard-manifest.test.sh` and
    `regenerate-shard-manifest.test.sh` derive N from ci.yml dynamically.
  - Full-residue AC: untruncated `grep -rn` for `"1/5"`, `/5"`, `% 5`,
    `K=5`, `five legs`, `mod 5` across `scripts/ plugins/soleur/test/
    .github/workflows/ knowledge-base/engineering/operations/runbooks/`
    returns only intentional non-shard hits.

### Change C — parallelize `enumerate_leg` inside the totality guard

`plugins/soleur/test/scripts-shard-totality.test.sh` — every independent
child `bash test-all.sh --enumerate` invocation runs `&` and its rc is
captured per-pid via `wait`, then verdicts are emitted serially in declared
order (deterministic output). Enumerate children take no advisory lock by
design (`test-all.sh:808-816`) so concurrency is safe.

- Parallelize: the light leg-union loop, each altK inner loop (per-altK),
  the 10-spec malformed loop, the over/long/unset probes, the
  TEST_GROUP=all enumerate, and the entire heavy mirror (hleg loop, altK
  heavy, malformed-heavy, unset_heavy, enum_all).
- Per-child rc capture: `child & pids[i]=$!` then `wait "${pids[i]}"; rc=$?`
  — never bare `wait` (it discards which job failed). Any non-zero rc where
  zero is expected → `fail` (fail-closed); the malformed probes keep their
  rc==2 expectation, now read from per-spec rc files or waited pids.
- Distinct `$WORK` outputs per child (`leg_$i`, `alt_leg_${altK}_${k}`,
  `mal_rc_$i`, …); union files are concatenated in index order after `wait`
  — file contents and pass/fail line order stay deterministic.
- Bash 3.2: index loops only; no `declare -A`; no `"${arr[@]}"` on possibly-
  empty arrays; no packed-string maps (learning). Bounded fan-out ≤ ~10
  concurrent children per group — no semaphore needed on a 2-vCPU runner,
  but note the bound in the comment.
- Byte-exact preservation (battery anchors live here): `totality_holds`'
  `diff -q "$1" "$2" >/dev/null 2>&1` body (HARNESS row), the reference
  derivation `cat "$WORK/ref_static" "$WORK/ref_glob" | sort -u >
  "$WORK/reference"` (ROW6 `_taut_old` anchor), `enumerate_leg`'s signature
  and `env … bash "$RUNNER" --enumerate "$group"` shape (callers pass the
  same argv — parallelization wraps call sites, not the callee).
- Keep serial: instrument self-test, reference derivation, leg-list awk
  extraction, wire checks, positive controls, assertion floor — anything
  ordering- or state-dependent.

### Change D — duration-aware assignment for `scripts-heavy`

A second manifest file, not an in-file section (Cut List rationale):
`scripts/suite-shard-legs-heavy.tsv` — identical format (`# n=<heavy-N>` +
same provenance keys + `label<TAB>leg`).

- `scripts/regenerate-shard-manifest.py`: add `--group {light,heavy}`
  (default light, back-compat). The heavy arm switches: artifact regex →
  `^suite-timings-scripts-heavy-\d+$` (previously excluded by
  `LIGHT_ARTIFACT`); registered set → `bash scripts/test-all.sh
  --enumerate scripts-heavy`; leg count → `test-scripts-heavy` job block
  in `read_ci_leg_count`; default `--manifest` →
  `scripts/suite-shard-legs-heavy.tsv`; header `# runner:` line notes the
  group. `GENERATOR_VERSION` 1→2 (capability grew; provenance must say so).
- `scripts/test-all.sh`: the engagement predicate gains the heavy arm —
  `TEST_GROUP=scripts-heavy` loads `suite-shard-legs-heavy.tsv` through the
  SAME parse/validate/activate path (malformed → exit 2, absent →
  positional notice, heavy-n != `_SHARD_N` → degrade to positional).
  New `SOLEUR_SHARD_MANIFEST_HEAVY` override mirroring
  `SOLEUR_SHARD_MANIFEST` (off/empty/non-absolute/missing → same exit-2
  semantics; consumed and unset at the same `:806` site) so the battery can
  fixture the heavy table without reinterpreting it as the light one.
  Update the `:687-689` comment (heavy no longer excluded) and the
  `:3442` leg-count line.
- `plugins/soleur/test/scripts-shard-manifest.test.sh`: parallel heavy
  section — heavy `# n=` == `test-scripts-heavy` matrix N, rows ⊆
  `--enumerate scripts-heavy` set, legs in range, no duplicates, every leg
  pinned, rows ≥ 1 (explicitly NOT the ≥100 light floor; the registered
  count is ~3 and the suite must say so).
- Battery M7–M9 (new `frow` rows, indices 22–24): heavy minus-one → GREEN
  (untabled heavy label hash-falls-back to exactly one leg), heavy
  phantom → GREEN (inert), heavy empty → GREEN (all-hash total). Bound via
  `SOLEUR_SHARD_MANIFEST_HEAVY` so the light committed table is untouched.
- Honest scope: at 3 suites/3 legs the assignment is already a bijection —
  expected wall-clock gain ≈ 0. What D buys is P4: insertion-stability for
  the group most likely to grow, one mechanism instead of two, and a loud
  lint when heavy's n drifts. ADR-240 is amended to say exactly this.

## Technical Considerations

- **Architecture impact:** D reverses an ADR-240 rejected alternative — the
  ADR is amended in this PR (Phase 2.10, deliverable not deferred).
  A/B/C are operational tuning inside existing architecture.
- **Performance:** all four changes target CI wall-clock; nothing in the
  product path changes. The guard's parallel fan-out is bounded (~10) and
  enumerate children take no lock.
- **Security:** `${{ matrix.rows }}` interpolation follows the existing
  `SCRIPTS_SHARD` pattern (literal matrix values, no untrusted input). No
  new credentials, endpoints, or secret surfaces.
- **NFR:** reliability (fail-closed preserved everywhere), observability
  (probe contract updated rather than silently invalidated).

## User-Brand Impact

- **If this lands broken, the user experiences:** a silent-green CI
  partition — a mis-wired matrix or a dropped row set runs zero/fewer
  suites green and a plugin update ships built on suites that never ran
  (the #7471 defect class). The loud variant (red-forever `test`) blocks
  every merge; recoverable but total.
- **If this leaks, the user's [data / workflow / money] is exposed via:**
  no data surface — the vector is trust in the release pipeline
  (false-green → unverified code ships).
- **Brand-survival threshold:** `single-user incident`

*Carry-forward (phase 1, same failure class): CPO confirmed
`single-user incident` on 2026-09-22 via the silent-green release path;
the load-bearing mitigations named then — totality guard, zero-assignment
refusal, mutation battery — are the same surfaces this diff touches.
`requires_cpo_signoff: true` is set; sign-off is re-confirmed by the
plan-review panel seat before `soleur:work` per the lifecycle model.*

## Observability

```yaml
liveness_signal:
  what: "test-scripts / test-scripts-heavy / shard-totality-mutations leg durations + suite-timings artifacts"
  cadence: "per CI run"
  alert_target: "required `test` check on every PR + ci-leg-durations-8006 sweep probe on main"
  configured_in: ".github/workflows/ci.yml (test, test-scripts, test-scripts-heavy, shard-totality-mutations jobs); scripts/followthroughs/ci-leg-durations-8006.sh"
error_reporting:
  destination: "GitHub Actions job log + required-check status"
  fail_loud: "non-success leg conclusion surfaced by the `test` aggregator's per-shard diagnosis; zero-assignment leg refuses exit 2; battery floor exits 1 naming DECLARED/EXECUTED/IN_RANGE counts"
failure_modes:
  - mode: "manifest n-mismatch after a K change (light or heavy)"
    detection: "runtime degrades to positional with a stderr notice; scripts-shard-manifest lint reds the n-pin"
    alert_route: "required `test` check red via the lint suite inside test-scripts"
  - mode: "battery half silently skips its rows"
    detection: "DECLARED==DECLARED_TOTAL + EXECUTED==IN_RANGE floor at exit"
    alert_route: "shard-totality-mutations leg red"
  - mode: "probe expected-leg count drifts from ci.yml"
    detection: "every post-merge run non-qualifying → sweeper comments NOT YET on #8006 (visible, but the co-change in this diff prevents it)"
    alert_route: "follow-through sweep comments on the tracking issue"
  - mode: "leg duration regresses above target"
    detection: "suite-timings artifacts + ci-leg-durations-8006 leg wall-clock probe"
    alert_route: "follow-through sweep FAIL comment on #8006"
logs:
  where: "GitHub Actions run logs + uploaded suite-timings-scripts-{i} / suite-timings-scripts-heavy-{i} artifacts"
  retention: "GitHub default; artifacts retention-days: 14"
discoverability_test:
  command: "bash scripts/test-all.sh --enumerate scripts"
  expected_output: "SUITE_REGISTRATION"
```

**Follow-Through (existing enrollment, updated in this PR):**
`scripts/followthroughs/ci-leg-durations-8006.sh` stays the soak probe —
this diff updates its expected-leg contract (6 light + 3 heavy = 9) so the
K=6 world is measurable rather than silently non-qualifying. Budget stays
900s/leg (#8006's bound). No new probe needed.

## Guard Contract

### Guard 1 — battery row-range dispatch (`--rows A-B`)

**Property.** Every declared mutation row executes in exactly one leg's
selected range; a row dropped, double-executed, or silently skipped is a
failure — and the vacuity floor counts declared rows, not executed rows.

**Assembly.** Every `row`/`frow`/bespoke call site in
`scripts-shard-totality-mutations.sh` — the chokepoint is the `next_row`
gate each site passes through; the counters are `DECLARED`, `IN_RANGE`,
`EXECUTED` asserted at exit; the flag parser is the single `--rows`
validation site.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete one `row` call site | RED — DECLARED(23) != DECLARED_TOTAL(24) |
| 2 | Make `next_row` skip without incrementing DECLARED | RED — DECLARED floor under-counts |
| 3 | Run `--rows 1-24` twice as two legs but bound IN_RANGE to `< B` | RED — last row unexecuted: EXECUTED < IN_RANGE |
| 4 | Pass `--rows 99-100` (beyond declared) | exit 2 at flag validation — never a green empty range |
| 5 | (harness) Neuter `in_range` to always-true on leg 1 | RED — both legs execute all rows; EXECUTED > IN_RANGE on each |
| 6 | (must-PASS) `--rows` unset | GREEN — full battery, back-compat local invocation |

### Guard 2 — parallel enumerate in the totality guard

**Property.** Every leg/spec child is enumerated, each child's rc is
captured and checked fail-closed, and each writes a distinct output file —
parallelism must not lose a leg's verdict or collide outputs.

**Assembly.** All `enumerate_leg` and direct child-runner call sites in
`scripts-shard-totality.test.sh` — the light union loop, altK loops (light
+ heavy), malformed-spec loops (light + heavy), over/long/unset probes,
TEST_GROUP=all enumerate — plus the per-pid `wait`+rc block that is the
single collection point.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Drop one leg's `wait`/rc check (collect n-1 of n pids) | RED — the un-collected leg's rc is lost; per-leg non-empty + rc assert must still fire |
| 2 | Replace per-pid `wait` with bare `wait` | RED — a mid-batch child's non-zero rc is un-attributable; the rc-name mapping breaks |
| 3 | Two children write the same `$WORK` file | RED — interleaved output collides the union/totality assertion or the per-leg non-empty row |
| 4 | A malformed-spec child expected to exit 2 is collected with `|| true` | RED — the rc==2 contract is erased; every malformed row reports the wrong verdict |
| 5 | (harness) Run the fan-out but evaluate verdicts before `wait` completes | RED — verdicts read files children haven't written |
| 6 | (must-PASS) All children green in parallel | GREEN — serial-equivalent verdicts, deterministic order |

### Guard 3 — heavy manifest lint + engagement

**Property.** `suite-shard-legs-heavy.tsv` is well-formed, its `# n=` equals
the `test-scripts-heavy` matrix N, its labels are ⊆ the registered-heavy
set — and a stale/absent/mismatched table degrades to positional, never to
wrong coverage.

**Assembly.** The heavy section of `scripts-shard-manifest.test.sh` (n-pin,
⊆, leg-range, dup, per-leg-pinned, non-empty rows), the runner's heavy
engagement arm (`TEST_GROUP=scripts-heavy` → heavy default path /
`SOLEUR_SHARD_MANIFEST_HEAVY` override / n-mismatch degrade), and the
generator's `--group heavy` arm that produces the file.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Heavy manifest `# n=2` while matrix is 3 | RED at lint (n-pin) AND positional degrade at runtime |
| 2 | Phantom label row in heavy manifest | RED — ⊆ violation (the stale-subset drift this lint exists for) |
| 3 | Heavy label assigned leg 4 (outside 1..3) | exit 2 at runner parse — same fail-closed path as light |
| 4 | (dispatch) `--group heavy` run reads `suite-timings-scripts-*` (light) artifacts | RED — generator must filter to the heavy artifact family, or the heavy table is built from the wrong timings |
| 5 | (harness) `SOLEUR_SHARD_MANIFEST_HEAVY=` (set-but-empty) | exit 2 — explicit override that cannot be honoured is a programming error, not a degrade |
| 6 | (must-PASS) heavy manifest absent | positional degrade + stderr notice — coverage never depends on the table |

### Guard 4 — followthrough probe expected-leg contract

**Property.** The probe's qualifying-run shape equals ci.yml's real leg
shape (6 light + 3 heavy), so post-merge runs are measured rather than
silently non-qualifying.

**Assembly.** `ci-leg-durations-8006.sh`'s expected-leg counts
(`nlight`/`nheavy`/`nok`) + its `.test.sh` fixture set + the ci.yml matrix
literals it mirrors.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Probe still expects 5 light legs in a 6-leg world | every real run non-qualifying → NOT YET forever (asserted by the probe's own fixture suite) |
| 2 | `nok` bumped to 9 but `nlight` left at 5 | non-qualifying — partial co-change caught by the suite's shape rows |
| 3 | (harness) Fixture run with a failed leg counted `ok` | non-qualifying — conclusion must gate, not just presence |

## Acceptance Criteria

- [ ] AC1: `bash plugins/soleur/test/scripts-shard-totality-mutations.sh
  --rows 1-12` and `--rows 13-24` each exit 0 on a clean tree, each report
  `DECLARED=24 EXECUTED=IN_RANGE`, and the two ranges union to all 24 rows
  with no overlap. `--rows` malformed/absent-bounds → exit 2; unset → full
  battery (back-compat).
- [ ] AC2: `ci.yml` `shard-totality-mutations` runs as a 2-leg matrix with
  `fail-fast: false`; job name, ruleset membership (absent), `test`
  aggregator needs/env/entries all unchanged — verified by
  `plugins/soleur/test/ci-test-aggregator-diagnosis.test.sh` staying green
  with zero edits.
- [ ] AC3: `test-scripts` matrix is K=6; `scripts/suite-shard-legs.tsv`
  carries `# n=6` regenerated by the generator (provenance header intact);
  `scripts-shard-manifest.test.sh` green with zero edits (it derives N).
- [ ] AC4: `SCRIPTS_SHARD=1/6 TEST_GROUP=scripts bash scripts/test-all.sh
  --enumerate` assigns ≥1 registration and `SCRIPTS_SHARD=6/6` likewise;
  unset enumerates the full group.
- [ ] AC5: `scripts-shard-totality.test.sh` runs its enumerate children in
  parallel (per-pid `wait` + rc capture), emits identical verdict lines in
  identical order, and every malformed spec still fails closed at exit 2.
  `MIN_ROWS` floor intact.
- [ ] AC6: `suite-shard-legs-heavy.tsv` exists with `# n=3`; the runner
  engages it under `TEST_GROUP=scripts-heavy SCRIPTS_SHARD=k/3` (manifest
  lookup logged via `[shard] manifest assignment active`); absent file →
  positional degrade notice; `# n` mismatch → degrade; malformed/dup/
  out-of-range row → exit 2.
- [ ] AC7: `SOLEUR_SHARD_MANIFEST_HEAVY` mirrors the light override
  (off/empty/non-absolute/missing → exit 2; valid path → fixture table);
  consumed and unset at the same site as `SOLEUR_SHARD_MANIFEST`.
- [ ] AC8: `ci-leg-durations-8006.sh` + `.test.sh` expect 6 light + 3 heavy
  = 9 green legs; the suite's fixture rows cover the stale-count failure
  shape.
- [ ] AC9: ADR-240 amended in this PR — “Per-group manifests” moved from
  Rejected alternatives to an adopted amendment noting the 3/3-bijection
  premise, the separate-file choice over an in-file section, and that the
  motivation is insertion-stability not wall-clock.
- [ ] AC10: Untruncated literal sweep green: no residual `"1/5"`/`/5"`/
  `% 5`/`K=5`/`five legs`/`mod 5` shard literals outside intentional
  non-shard hits (runbook prose updated in the same diff).
- [ ] AC11: Live-corpus guards green locally before push:
  `scripts/guard-vacuity-floor.test.sh`,
  `scripts/lint-shell-capture-exit.test.sh`,
  `plugins/soleur/test/fixture-relative-assert.test.sh` (baseline updated
  in the same commit if new flagged sites are added),
  `scripts/lint-orphan-test-suites.sh`, plus
  `scripts/test-all-affected.test.sh` (A3 shape untouched) and
  `plugins/soleur/test/regenerate-shard-manifest.test.sh` (heavy arm
  fixtures added).
- [ ] AC12: `actionlint .github/workflows/ci.yml` clean. (Plan/tasks live
  under `knowledge-base/project/` — out of markdownlint scope by design,
  `.markdownlintignore` #7927; no lint claim is made for them.)
- [ ] AC13: On this PR's own CI run, `shard-totality-mutations` legs are
  ≈5m or less and the worst job overall is ≈8.5m or less — measured from
  the run's job durations, not assumed.
- [ ] AC14: The mutation battery's own anchors still match: the battery
  exits 0 (not anchor-miss exit 3/4) on its CONTROL + rows against the
  edited guard/runner — proof the byte-exact anchors survived the C and D
  edits.

## Test Scenarios

- Given `--rows 1-12` on the battery, when it runs, then rows 1–12 execute,
  DECLARED=24 is asserted, and rows 13–24 produce no verdict lines.
- Given a `test-scripts` leg with `SCRIPTS_SHARD=3/6`, when the runner
  enumerates, then exactly the manifest-assigned + hash-fallback labels of
  leg 3 appear — no tabled label lands off its leg.
- Given `TEST_GROUP=scripts-heavy SCRIPTS_SHARD=2/3` with the heavy
  manifest present, when the runner enumerates, then leg 2 emits exactly
  its tabled label; with the file removed, same command degrades to
  positional and still assigns the same label (bijection) with a stderr
  notice.
- Given the totality guard with a child enumeration forced to fail (e.g.,
  a stubbed runner exiting 3 on one leg), when the guard runs, then that
  leg's rc is captured and the suite reports RED naming the leg — never a
  lost-pid green.
- Given the probe against a fixture run shaped 6-light/3-heavy/all-green,
  when it runs, then qualifying=1; against 5-light expectation remnants,
  then non-qualifying.
- Regression: the failure mode this fixes — a single job holding ~9.5m of
  sequential guard invocations — is covered by AC13's measured bound, not
  by assertion on row order.

## Success Metrics

- Worst job wall on the PR run: **≤ ~8.5m** (from ~10m), decomposed:
  `shard-totality-mutations` ≈5m/leg, `test-scripts` ≈7.5–8m/leg,
  `test-scripts-heavy` ~8.5m (unchanged).
- No coverage reduction: union of legs == registration set in every mode
  (positional, light manifest, heavy manifest, hash fallback) — guarded,
  not sampled.
- `#8006` probe keeps measuring: qualifying post-merge runs under the 9-leg
  contract, every leg < 900s.

## Dependencies & Risks

- **PR #8329 conflict** (`feat-8322-affected-test-gate`, OPEN): edits
  `scripts/test-all.sh` + `scripts/test-all-affected.test.sh`. Our edits
  touch the manifest-load block (:676-777) and the heavy registration
  comment (:3440s); theirs the `_suite_affected` path inside `run_suite`.
  Ordering: whichever lands second rebases —
  `plugins/soleur/scripts/sync-pr-behind.sh` per repo runbook; if the
  BEHIND treadmill repeats, admin-merge once CI is green is acceptable.
- **Battery half-balance:** the 1-12/13-24 split is by row count, not
  measured cost — M-rows are cheap, runner-mutation rows expensive. If the
  PR run shows one half >6m, rebalance the range literals (data, not
  architecture).
- **Parallel-enumerate contention:** ~10 concurrent `bash test-all.sh
  --enumerate` children on a 2-vCPU runner — bounded, lock-free by design;
  the risk is output interleave, closed by file-per-child + serial verdicts.
- **K=6 pool pressure:** +1 leg against the org ceiling — #8450's own
  decision (GitHub Team upgrade) covers it; leg-count increase is the
  cheap direction either way.
- **Manifest drift windows:** between ci.yml edit and manifest regen the
  lint n-pin reds — the regen is in the same commit, so the window does
  not exist at review time.
- **`#8006` stays open:** this delivers phase 2; the issue closes when the
  leg-duration soak probe passes on main.

## Non-Goals (documented deferrals)

- Internal splitting of `tests/scripts/test-registry-gate-mutation-battery.sh`
  (the ~8.5m heavy long pole) — deferred: its global floor contracts make
  internal row-splitting a heavier change than this entire plan; the ≤8.5m
  target is met without it. Re-evaluation: if the PR run shows heavy
  leg-1 >8.5m and the operator wants <8m, this is the lever.
- Promoting `shard-totality-mutations` into the required-checks ruleset —
  tracked separately per its own ci.yml comment (ruleset + canonical-JSON
  + synthetic-fabrication surface).
- Runner-pool/org-concurrency ceiling — #8450 (separate decided track).
- Intra-leg suite parallelism — #8231.
- plugins/soleur/test `*.mutation.sh` gating — #7942.
- `test-all-affected` local-gate rework — #8329 (sibling PR).

## Domain Review

**Domains relevant:** Engineering | none

### Engineering

**Status:** reviewed (inline assessment — no Task spawn available in this
subagent context; the plan-review panel covers the eng lenses next)
**Assessment:** Devex/CI-internal change on the #8006 surface already
reviewed by soleur:engineering:cto for phase 1. The load-bearing
enumerations carried forward: SCRIPTS_SHARD group-scope refusal stays
{scripts, scripts-heavy}; `want_scripts_heavy` keeps `all`; A3-pinned
`_shard_selects "$label" || return 0` call shape untouched; enumerate
children are lock-free by design; the probe leg-count contract is the
co-change most easily missed; heavy positional→manifest is semantics-
preserving by construction (bijection).

### Product/UX Gate

**Tier:** none (no UI surface; mechanical override did not fire — no
`components/**`/`app/**` paths in Files lists)
**Decision:** reviewed — threshold carries the phase-1 CPO-confirmed
`single-user incident` via the silent-green release path.
**Agents invoked:** none this phase (inline; sign-off re-confirmed at
plan-review per `requires_cpo_signoff: true`)
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

## Architecture Decision (ADR/C4)

D reverses an ADR-240 rejected alternative — amendment is a deliverable of
THIS plan.

- `### ADR` — **amend ADR-240** (no new ordinal): move “Per-group
  manifests (heavy included)” from Rejected alternatives to an adopted
  amendment: premise was “unneeded today” at 3/3; adopted now for
  insertion-stability and semantic uniformity with the light group, as a
  SEPARATE file (`suite-shard-legs-heavy.tsv`) rather than an in-file
  section so the light file's strict parsers stay verbatim. Update the
  Consequences line “The `test-scripts-heavy` job is unaffected
  (n-mismatch → positional)” — no longer true; heavy engages when
  heavy-n == _SHARD_N.
- `### C4 views` — none: enumerated (a) external human actors: none new;
  (b) external systems/vendors: none new (GitHub Actions is the existing
  substrate, and repo CI topology is below the model's floor — `model.c4`
  carries no ci/test-all/shard elements); (c) containers/data stores:
  none; (d) access relationships: none. Verified by grepping
  `knowledge-base/engineering/architecture/diagrams/model.c4` for
  ci|workflow|test-all|shard — only the plugin/workflow-skill containers
  match, none of which this diff changes.
- `### Sequencing` — amendment lands in this PR describing the landed
  state (no soak gate on the decision itself).

## Open Code-Review Overlap

Queried open `code-review` issues against the file list (76 issues):

- **#8659** “33 test suites replace test-helpers' composed EXIT trap and
  leak the incident sandbox on direct runs” — **acknowledge**: names
  `scripts/test-all.sh` but concerns test-helper trap composition, a
  different concern; this plan neither fixes nor worsens it.
- **#7942** “Two mutation batteries in plugins/soleur/test/ are named
  *.mutation.sh and run in no gate” — **acknowledge**: different files
  (`*.mutation.sh`, not `scripts-shard-totality-mutations.sh` which is
  gated in its own CI job).

## Files to Edit

- `.github/workflows/ci.yml` — `test-scripts` matrix + comment, mutations
  job matrix + run line + comment.
- `scripts/test-all.sh` — heavy manifest engagement arm,
  `SOLEUR_SHARD_MANIFEST_HEAVY`, comment updates (:687-689, :3442).
- `scripts/regenerate-shard-manifest.py` — `--group` arm, heavy artifact
  regex, heavy leg-count, GENERATOR_VERSION 2.
- `scripts/suite-shard-legs.tsv` — regenerated at n=6.
- `plugins/soleur/test/scripts-shard-totality-mutations.sh` — `--rows`
  flag + DECLARED/IN_RANGE/EXECUTED floor, K=6 anchors, M4 manifest-n
  derivation, M7–M9 heavy rows.
- `plugins/soleur/test/scripts-shard-totality.test.sh` — parallel
  enumerate with per-pid rc capture (light + heavy + malformed + probes).
- `plugins/soleur/test/scripts-shard-manifest.test.sh` — heavy section.
- `plugins/soleur/test/regenerate-shard-manifest.test.sh` — `--group
  heavy` fixtures.
- `scripts/followthroughs/ci-leg-durations-8006.sh` + `.test.sh` —
  expected-leg contract 5/3/8 → 6/3/9.
- `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md`
  — K=6 + heavy-manifest updates.
- `knowledge-base/engineering/architecture/decisions/ADR-240-shard-assignment-is-checked-in-derived-data.md`
  — amendment per Phase 2.10.

## Files to Create

- `scripts/suite-shard-legs-heavy.tsv` — generated (3 rows, n=3).

## References & Research

- Mechanism + constraints: #8006 body; ADR-240 (the decision this amends);
  ADR-238 (heavy carve-out); ADR-235 (generated-artifact diff rules);
  ADR-181 (relevance gating); ADR-193 (instrument self-test); ADR-176
  (checkpoint protocol); ADR-231 (workflow byte budget).
- Prior phases: `knowledge-base/project/plans/archive/20260923-182911-2026-09-22-feat-ci-test-shard-speedup-plan.md`
  (phase 1, format + threshold precedent),
  `knowledge-base/project/plans/archive/20260923-182608-2026-09-23-feat-ci-duration-aware-shards-plan.md`
  (manifest phase).
- CI measurement: run 35911999612 job durations + `suite-timings-*`
  artifacts; manifest predicted legs 475.9–491.1s.
- Learning: `knowledge-base/project/learnings/2026-09-23-a-packed-string-searched-by-glob-is-a-quadratic-map.md`.
- Runbook: `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md`.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only
  TBD/placeholder text, or omits the threshold will fail `deepen-plan`
  Phase 4.6 — filled above.
- The battery's `row`/`mutate` anchors are byte-exact; every edit to the
  guard or runner was swept for anchor overlap (totality_holds body,
  reference-derivation line, `_shard_selects` call shape) — the sweep is
  AC14, not a hope.
- Verification greps asserting absence (AC10) are untruncated — a
  `| head` on an absence claim is the #8006-class false-green this plan
  exists to prevent.
- The probe leg-count co-change (AC8) is the single most likely missed
  edit: it is silent, it is in `scripts/followthroughs/`, and its failure
  mode (NOT YET forever) looks like patience, not breakage.
