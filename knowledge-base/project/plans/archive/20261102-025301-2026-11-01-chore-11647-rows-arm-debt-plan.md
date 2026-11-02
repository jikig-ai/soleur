---
title: "chore(11647): ci/test-scripts --rows arm debt — est provenance tier, rows-range lib, exit-code parity, per-block floors, arm-convention ADR"
type: chore
date: 2026-11-01
slug: chore-11647-rows-arm-debt
branch: feat-one-shot-11647-rows-arm-debt
issue: 11647
closes: 11647
domain: engineering
priority: p3-low
lane: cross-domain
brand_survival_threshold: none
---

# chore(11647): ci/test-scripts `--rows` arm debt — five bundled items

## Overview

Issue #11647 (epic #11556, mandated-by #11562) bundles five deferrals from the
PR #11561 review panel. All five concern the `--rows` arm-split machinery that
#11562 shipped to break the test-scripts shard's worst atomic legs into
`run_suite … --rows A-B` registrations: the durations-table provenance enum,
the four-way-copied flag preamble, the FATAL exit-code doctrine, the ranged
case floor, and the undocumented `-<letter>` arm convention.

**Fact check against this branch:** the issue's premise that "the 7 arm rows
are CI-median × local-share estimates stamped `measured`" is **stale on the
values, live on the mechanism**. Commit `fe6963786f` (#11718, "re-price
test-scripts arm rows from post-merge CI timings") replaced the seeded
estimates with real 8-run medians (runbook
`ci-test-scripts-sharding.md` §2026-10-31 records every seeded→measured
figure). The committed table now holds **9** `measured` `-<letter>` rows
(`ci-pr-affected-replay-{a,b,c}`, `lint-orphan-test-suites-mutations-{a,b}`,
`test-all-affected-{a..d}`), not 7 — and they are honest measurements. The
provenance gap the item names is still real: nothing in the enum lets a future
seeded estimate declare itself, and `src=floor` is the wrong stamp for an
estimate because floor rows re-derive at `floor_ms` (supply no weight) while an
arm seed must supply weight. The enum lands as mechanism; no committed row is
restamped.

## Problem Statement / Motivation

Per bundled item, verified against the tree:

1. **`src=est` provenance tier.** `read_durations_rows` and
   `parse_durations_text` both die on `src ∉ {measured, floor}`
   (`scripts/regenerate-shard-manifest.py:421,480`). An estimate stamped
   `measured` prices legs, anchors the floor median (`read_durations_ms`:602),
   and enters the drift gate's measured baseline (`drift_violations`:493-494) —
   `write_durations_delta` then passes it through byte-identical forever
   (:694,710). `src=floor` cannot express "weight-bearing estimate": floor rows
   re-derive at `floor_ms` and supply no weight (:437-438,667-672). A third
   tier is needed: weight-supplying like `measured`, never counted as a
   measurement.
2. **`scripts/lib/rows-range.sh` extraction.** The `--rows` preamble exists as
   four near-copies with three real semantic variants (catalogued below).
   The copies differ on repeat-flag handling, ordinal enforcement, counter
   names, and bounds-check placement — silent drift on extraction is the
   risk.
3. **Exit-code doctrine.** Repo convention: harness/shape FATALs exit 2,
   verdicts exit 1. `test-all-affected` complies at its end gate but not its
   early FATALs; `lint-orphan` is internally inconsistent (in_range ordinal
   FATAL → 2, every end-gate FATAL → 1); `ci-pr-affected-replay` FATALs exit 1
   throughout; totality-mutations' end gate prints `FAIL:` + exit 1 for what
   are shape failures.
4. **Per-block declared case floors.** `test-all-affected`'s ranged floor is
   `MIN_ARM_CASES=EXPECTED_EXECUTED` (:4262-4267) — ≥1 `cases` per dispatched
   block — so a 30-case block gutted to 1 stays green. `lint-orphan` already
   has the model (`EXPECTED_ASSERTIONS` per row, aggregated at `.rc` replay
   :1194-1220); `totality-mutations` covers it by verdict conservation
   (`TOTAL == EXECUTED + 1`, :1032); replay covers it by
   `MUT_RUN + OW_MUT_RUN == EXECUTED` (:5188). The gap is `test-all-affected`
   only.
5. **Arm-convention ADR + split checklist.** The `-<letter>` suffix is
   load-bearing in `separate_arm_groups`
   (`scripts/regenerate-shard-manifest.py:760-795`) and the totality guard's
   label-shape arm (`scripts-shard-totality.test.sh:937-941`) with no ADR.
   The full site list for an arm split exists only in scattered comments.

## Proposed Solution

Five committable slices, sequenced so each lands independently green:

- **S1 — `estimate` provenance tier** in the durations machinery + tests.
- **S2 — `scripts/lib/rows-range.sh`** exposing `rows_parse_args`,
  `in_range [ord]`, `rows_gate_floor`; retire all four copies behind a
  semantics-preserving extraction.
- **S3 — exit-code normalization** to the doctrine across the four batteries.
- **S4 — per-block declared case floors** for `test-all-affected` via the
  lib's `rows_gate_floor` + a battery-declared block-case map.
- **S5 — ADR-313 + arm-split checklist** in the sharding runbook.

## Technical Approach

### S1 — `estimate` src tier

| Site | Anchor | Change |
|---|---|---|
| `scripts/regenerate-shard-manifest.py` | `read_durations_rows` :421 | enum → `(measured, floor, estimate)`; die message updated (:423) |
| same | `parse_durations_text` :480 | same enum widening (keeps baseline blobs parseable — an `estimate` row in a merge-base blob must not die the drift gate) |
| same | `read_durations` :428-439 | signature → `(weights, floor_labels, est_labels)`; `weights` = `src ∈ {measured, estimate}` (estimates supply weight), `floors`/`ests` partitioned; update the one call site (:1142) and the `src_map` build (:1209-1215) so `--durations`-sourced `estimate` rows re-emit as `estimate`, never `measured` — this is the anti-laundering |
| same | `read_durations_ms` :593-603 | `all_ms` already maps every row (estimates supply weight for leg pricing for free); `measured` stays `src == "measured"` only — an estimate must not anchor the floor median |
| same | `--durations` floor-median :1174,:1207 | `measured = weights` (:1174) — post-change `weights` includes est labels, so `floor_ms = median(measured.values())` (:1207) must exclude `est_labels`; empty measured set → `DEFAULT_SUITE_MS` + WARN, mirroring the incremental path (:1026-1034). Decision-challenges row 17 |
| same | `drift_violations` :487-521 | add `base_e`/`new_e` sets; `estimate→measured` and `measured→estimate` transitions emit named note lines (mirroring the `floor→measured` note at :503-505); `estimate` rows excluded from per-suite measured comparison but a new measured row over an estimate baseline counts toward total growth (same treatment as `floor→measured`) |
| same | `drift_report_group` :638-642 | `estimate` rows join the `floor_labels` population for `DRIFT_ROW`/`FLOOR_UNMEASURED` — an estimate that finally measures IS the drift event the probe exists to name. The emitted `FLOOR_UNMEASURED` token stays LITERAL (`scripts/watch-shard-balance-11564.sh:138,196` parses it) — docstring (:611-623) and runbook (`ci-test-scripts-sharding.md:165-168`) wording widens to cover `estimate` only. Decision-challenges row 8 |
| same | `write_durations_delta` :666-714 | no code change — retained rows pass byte-identical (:694), which preserves `estimate` provenance across incremental regens |
| `plugins/soleur/test/scripts-shard-manifest.test.sh` | `check_durations` :314 | row-shape enum → `{measured,floor,estimate}`; comment at :284 updated |
| `plugins/soleur/test/regenerate-shard-manifest.test.sh` | fixtures | new fixture cases mirroring K/M/N (:340-470): an `estimate` row in `--durations` input (a) supplies its weight to the packing, (b) re-emits `estimate` not `measured`, (c) is excluded from the floor median, (d) `estimate→measured` on a timing-fed write is a named transition, (e) `measured→estimate` is a named downgrade note |
| `scripts/suite-durations.tsv` | rows :177-179,:501-502,:566-569 | **no restamp** — all 9 rows carry real measured medians post-#11718 |
| `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md` | arm-split recipe | document: seeding an arm price by hand stamps `estimate`, never `measured`; the row upgrades to `measured` only when a `--runs`/`--timings-dir` pass has real timing rows |

### S2 — `scripts/lib/rows-range.sh` extraction

**The four copies, verbatim anchors:**

| Battery | Preamble | `in_range` def | End gate | Variant |
|---|---|---|---|---|
| `plugins/soleur/test/scripts-shard-totality-mutations.sh` | :66-103 (`DECLARED_TOTAL=42` :79) | :105-118 (`_row_seq`) | :1003-1035 | **A** — no `_seen_rows_flag` (repeat = last wins); `_rowspec="$2"; shift 2`; unbounded-digit regex; bounds checked **inline** in the case arm (:93-96); counter `_row_seq`; no ordinal |
| `scripts/lint-orphan-test-suites.test.sh` | :78-115 (`DECLARED_TOTAL=35` :84) | :117-133 | :1312-1346 | **B** — `_seen_rows_flag` refuse (:95-98, deliberate divergence per :82-83); `{1,9}` regex; post-loop bounds gated on the flag (:112-115); **`in_range <M-ordinal>` required** — ordinal ≠ `_site_seq` → `FATAL(harness)` exit 2 (:124-127) |
| `plugins/soleur/test/ci-pr-affected-replay.test.sh` | :62-108 (`DECLARED_TOTAL=582` :77) | :110-123 | :5165-5196 | **C** — like B minus the ordinal; `in_range` called from inside `mutate`/`ow_mutate` drivers (:4281, :3746); `_MUT_UNGATED`/`mutate_ungated` escape (:124-127) |
| `scripts/test-all-affected.test.sh` | :325-363 (`DECLARED_TOTAL=38` :335) | :364-375 | :4236-4267 | **C** — same shape as replay |

**Lib API:**

- `rows_parse_args "$@"` — reads the caller's file-scope `DECLARED_TOTAL`
  (which **stays declared in each battery file**: the totality guard reads it
  via `_DECL_READ_RE`, `scripts-shard-totality.test.sh:719`, and
  totality-mutations' `DECL-PREFIX-READER` row :998-1001 pins the literal
  `DECLARED_TOTAL=35   # the gated mutation rows M1..M35…` line byte-for-byte).
  Sets `ROWS_LO`, `ROWS_HI` (0 = unset = all), `_seen_rows_flag`, and zeroes
  `_site_seq`/`EXECUTED`. Refuses: malformed spec, repeat flag, unknown arg,
  out-of-bounds — all `ERROR:` → exit 2. Optional `ROWS_UNIT` noun for the
  error text ("rows"/"sites"/"blocks" today) — or unify on "rows"; cosmetic.
- `in_range [ord]` — increments `_site_seq`; when `ord` is passed, asserts
  `ord == _site_seq` (`FATAL(harness)` exit 2, lint-orphan's :125 message
  shape); then the range test — increments `EXECUTED` and returns 0 in range
  (`ROWS_HI == 0` counts as all), else returns 1.
- `rows_gate_floor` — EOF reconciliation: `_site_seq == DECLARED_TOTAL` and
  `EXECUTED == expected` (unflagged → `DECLARED_TOTAL`, else `HI-LO+1`), each
  `FATAL` exit 2; plus the optional per-block case floor of S4 when
  `ROWS_BLOCK_CASES` is declared. Batteries keep their own battery-specific
  extras after it (lint-orphan's ROWS conservation + `MIN_PARENT_ASSERTIONS`;
  replay's `MUT_RUN+OW_MUT_RUN` + census + OW floors; test-all-affected's
  `MIN_CASES` full-run floor; totality-mutations' `TOTAL == EXECUTED + 1`).

**Normalization folded into the extraction (needs ruling — see
decision-challenges):** repeat-`--rows` becomes refuse-everywhere, including
totality-mutations where it silently last-wins today — the last-wins shape is
the one lint-orphan's comment calls out as the reason the refuse exists ("the
tiling extractor would then assert a coverage the battery ignores"). If the
ruling preserves last-wins, the lib takes `ROWS_REPEAT=allow` before the call.
Likewise `_row_seq` → `_site_seq` at totality-mutations' two use sites
(:1016-1026) and the post-loop bounds placement replaces variant A's inline
check (semantically equivalent: the flag value is stored either way; the
post-loop check fires on the same inputs).

**Hazards baked into the plan:**

- **Direction-2 census** (`scripts-shard-totality.test.sh:1051-1125`): every
  shell file repo-wide is grepped for `^[[:space:]]*(export|readonly|local|
  typeset|declare …)?DECLARED_TOTAL=`. The lib must **never** spell
  `DECLARED_TOTAL=` at line start — it reads the caller's variable or takes
  the total as a positional operand, it does not assign one.
- **Direction-1 literal census** (:1040-1049): counts `--rows <digits>-<digits>`
  literals across `test-all.sh` + `scripts/lib` and requires the count to
  equal extracted `run_suite --rows` flags. The lib's comments/usage text must
  never carry a literal `--rows N-M` (write `--rows A-B` in prose — `A-B` is
  non-digit and invisible to the census regex).
- **Verbatim anchors** (`scripts-shard-totality-mutations.sh`): eight rows
  pin the `run_suite … --rows` lines in `test-all.sh` byte-for-byte
  (:771-937) and `DECL-PREFIX-READER` pins the `DECLARED_TOTAL=35` line
  (:998-1001). The extraction touches **none** of those strings — run_suite
  argv is unchanged, `DECLARED_TOTAL` stays declared in each battery.
- **`set -uo pipefail`**: all four batteries run with `-u`; the lib uses
  `${1-}`/`${2-}` everywhere (bare `in_range` calls have no `$1`).
- **Namespace**: the lib owns `ROWS_LO`, `ROWS_HI`, `EXECUTED`, `_site_seq`,
  `_seen_rows_flag`, `_ROWS_*` internals — every battery already uses these
  names except `_row_seq` (renamed, above). `EXPECTED_EXECUTED`-style locals
  stay battery-side.
- **Sourcing**: `source "$REPO_ROOT/scripts/lib/rows-range.sh"` —
  `REPO_ROOT` is already defined in all four files (totality-mutations :56,
  lint-orphan :61, replay `$SCRIPT_DIR` :39-40 — translate to
  `$REPO_ROOT/scripts/lib/…` or the sibling-relative equivalent,
  test-all-affected :57).
- **Affected-index ratchet**: the four new `source` lines are (suite, path)
  mentions the audit may flag. For the two pr-gated arm sets the remedy is a
  **declared edge**: add `"scripts/lib/rows-range.sh"` to
  `LINT_ORPHAN_BATTERY_PATHS` (test-relevance-paths.sh:171-179) and
  `TEST_ALL_AFFECTED_BATTERY_PATHS` (:207-213) — which is also semantically
  required, since editing the lib must arm those batteries on the PR that
  edits it. For replay (unconditional) and totality-mutations (ci.yml-split)
  run the audit locally and add accept rows to
  `scripts/ci-pr-affected-audit.accept.tsv` only if pairs are flagged
  (`RATCHET_REMEDY_NEW`, `ci-pr-affected-replay.py:1758-1767`).

### S3 — exit-code normalization (harness/shape FATALs → 2, verdicts → 1)

Scope rule: **the battery process's own exit code on a FATAL/harness/shape
path becomes 2; verdict exits stay 1; exits inside fixture subshells, stub
scripts, and rc-producers-under-test are untouched.**

| File | Sites to flip (exit 1 → 2) | Stays 1 (verdict) | Stays as-is (fixtures) |
|---|---|---|---|
| `scripts/test-all-affected.test.sh` | :92 (`ERROR` missing required file), :109 (instrument self-test `[FATAL]`) | :4271 | — |
| `scripts/lint-orphan-test-suites.test.sh` | :1206,1210,1214 (aggregation FATALs), :1320,1325,1333,1342 (end-gate FATALs) | :1346 | `mutate` `sys.exit(3)` :355-356 (deliberate third class, documented :33-36) |
| `plugins/soleur/test/ci-pr-affected-replay.test.sh` | :53,57,59,140,141,145,176,179 (early harness), :5177,5183,5186,5189,5192,5195 (end-gate `[FATAL]`), :711,740,953,1735,2253,2294,2347,2351,2352,2370,1754 (`[FATAL]` inside row/fixture helpers that exit the process) | :5199-5200 | stub scripts (`STUB-MISS` 64, gh-stub 1/4/124/422/429, sel-stub 7/3), `( … ) ||` subshell fixtures, `assert_fixture_dir` already 2 |
| `plugins/soleur/test/scripts-shard-totality-mutations.sh` | :1017-1018,1025-1028,1032-1034 — **and** relabel `FAIL:` → `FATAL:` (these are shape-accounting aborts, not mutation verdicts; decision-challenges row 11) | :1040-1041 (FAIL>0 verdict) | dirty-tree refusal already 2 (:172), setup FATALs already 2 |

Runner-level safety: `suite_exit_class` maps every nonzero rc to `failed`
(`scripts/test-all.sh:1539-1553`) — no caller distinguishes 1 from 2, so the
change is doctrine-hygiene only, not an ABI break. Anything invoking a
battery directly and branching on `rc == 1` would see `2` — checked: the
only rc-sensitive readers are inside the batteries themselves (asserting
SUT exit codes, untouched).

### S4 — per-block declared case floors (`test-all-affected`)

`cases` is a file-global that ticks only inside `if in_range; then … fi`
blocks (:87,111 init; first gated tick :387), so `in_range` can snapshot it
at each gate call:

- Battery declares `ROWS_COUNT_VAR=cases` and an ordinal-indexed floor map,
  e.g. `ROWS_BLOCK_CASES=( <c1> <c2> … <c38> )` — index `_site_seq-1` →
  declared minimum, with a comment mapping ordinals to block letters
  (`a..th8m`). `>=` floors, not equality (several blocks emit loop-driven
  case counts — the header at :332 names "for-loops (q8/th census rows)";
  declare each block's structural minimum).
- Lib's `in_range` records `_ROWS_MARK[_site_seq]="${!ROWS_COUNT_VAR}"` when
  `ROWS_COUNT_VAR` is set; `rows_gate_floor` closes the last block against
  the final counter and `FATAL exit 2`s on any dispatched block whose
  `actual < declared` — naming the block ordinal (and letter where mapped).
- lint-orphan skips (has `EXPECTED_ASSERTIONS`); totality-mutations skips
  (`TOTAL == EXECUTED + 1`); replay skips (`MUT_RUN+OW_MUT_RUN == EXECUTED`
  + per-site verdicts).

Measuring the 38 declared counts is an implementation step: count each
block's `cases+=` sites; loop blocks take their conservative structural
minimum. Proof required: hollow one block to fewer cases → arm reds.

### S5 — ADR-313 + split checklist

- **ADR-313** at
  `knowledge-base/engineering/architecture/decisions/ADR-313-<slug>.md`
  (next free ordinal verified — ADR-312 is top): decision = `--rows` arm
  labels carry the `<stem>-<letter>` suffix and the boundary lives in the
  flag argument, never the label; consequences = the generator's
  `separate_arm_groups` distinct-legs post-pass, the totality guard's
  tiling/`-<letter>`/distinct-legs/census arms, the same-commit
  DECLARED_TOTAL+re-split rule, both split styles (run_suite arms and
  ci.yml `rows:` matrix per totality-mutations).
- **Checklist** into
  `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md`
  (the runbook owns regen cadence and already narrates every arm split):
  full site list — run_suite/skip_suite pairs + `_relevance_declined` count
  (pr-gated arms only); shared `<NAME>_PATHS` array + `RELEVANCE_ARRAYS`
  row; `AFFECTED_CONSUMED_EDGES` rows per arm label; `is_pr_gated_decline`
  in `ci-pr-selection.sh:197-210`; `GATED` rows in
  `test-all-infra-coverage-notice.test.sh:403-419`; battery-gate constants
  (`test-all-pr-battery-gate.test.sh` `L_*`/`ARRAYS`/`own_file`/`add_arm`/
  `arm_id` :73-95,287-289,600-601); battery-side `DECLARED_TOTAL` +
  `rows_parse_args` + `in_range` gates + EOF floors; `--incremental --write`
  regen for both TSVs (distinct legs asserted); totality-mutations verbatim
  anchor re-pin; the ratchet `(suite,path)` check.

### Files to Create

| File | Purpose |
|---|---|
| `scripts/lib/rows-range.sh` | the shared `--rows` preamble: `rows_parse_args`, `in_range [ord]`, `rows_gate_floor`, optional `ROWS_COUNT_VAR`/`ROWS_BLOCK_CASES` tracking |
| `knowledge-base/engineering/architecture/decisions/ADR-313-…` | the `-<letter>` arm convention |
| `scripts/lib/rows-range.test.sh` *(decision row 12)* | unit suite for parse edge cases the batteries can't reach cheaply (repeat, malformed, bounds, ordinal mismatch, per-block floor) — auto-globbed by `SUITE_GLOBS` `scripts/lib/*.test.sh` (:108); if added: `--incremental --write` regen for both TSVs, PRODUCER_JOIN row in `grep-q-pipe-guard.test.sh` if it pipes text to a producer, fixture-assert baseline if it builds fixture dirs |

### Files to Edit

| File | Change |
|---|---|
| `scripts/regenerate-shard-manifest.py` | `estimate` enum in two parsers; `read_durations` 3-tuple; `src_map` est path; `drift_violations` est transitions; `drift_report_group` est rows |
| `plugins/soleur/test/scripts-shard-manifest.test.sh` | `check_durations` enum (:314) |
| `plugins/soleur/test/regenerate-shard-manifest.test.sh` | `estimate` fixture cases |
| `plugins/soleur/test/scripts-shard-totality-mutations.sh` | retire preamble → lib source + call; `_row_seq`→`_site_seq`; end-gate `FAIL:`→`FATAL` + exit 2 |
| `scripts/lint-orphan-test-suites.test.sh` | retire preamble → lib; end FATALs exit 1→2 |
| `plugins/soleur/test/ci-pr-affected-replay.test.sh` | retire preamble → lib; `[FATAL]` exits 1→2 (scoped list above) |
| `scripts/test-all-affected.test.sh` | retire preamble → lib; `EXPECTED_BLOCK_CASES` map + `ROWS_COUNT_VAR`; early FATALs exit 1→2 |
| `scripts/lib/test-relevance-paths.sh` | `scripts/lib/rows-range.sh` into `LINT_ORPHAN_BATTERY_PATHS` + `TEST_ALL_AFFECTED_BATTERY_PATHS` |
| `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md` | `estimate` seeding rule + arm-split checklist |
| `scripts/ci-pr-affected-audit.accept.tsv` | conditional — accept rows only if the ratchet flags the new `source` mentions |

## Alternative Approaches Considered

| Approach | Why rejected |
|---|---|
| Restamp the 9 arm rows `estimate` | They are real 8-run medians post-#11718 — restamping would mislabel measurements as estimates, the inverse laundering |
| Keep `DECLARED_TOTAL` inside the lib | Impossible — the totality guard reads it per-battery-file (`_DECL_READ_RE`) and Direction-2 censuses any `DECLARED_TOTAL=` spelling repo-wide |
| Per-block declarations inside each `if in_range` block (lint-orphan `EXPECTED_ASSERTIONS` style) | 38 edited block sites vs one declared table; the ordinal-indexed central map catches reorder/hollow in the same gate without touching every block — decision-challenges row 9 can overturn |
| `rows_gate_floor` per-battery extras folded in | The extras are battery-specific (conservation, census, OW floors); the lib takes the shared three checks and batteries keep the rest |
| New `rows-range.test.sh` skipped | Kept as a decision row — the four batteries do exercise the lib on every arm, but cheap parse-edge coverage (repeat/bounds/ordinal/floor) argues for the small suite |
| `est` (issue title spelling) vs `estimate` (issue body enum) | Recommend `estimate` — matches the spelled-out `measured`/`floor` house style; flagged to ruling |

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Reality on this branch | Plan response |
|---|---|---|
| "the 7 arm rows are CI-median × local-share estimates stamped `measured`" | **9** arm rows, all re-priced to real medians in `fe6963786f` (#11718) — runbook §2026-10-31 records seeded→measured per row | Build the enum tier; restamp nothing; runbook prescribes `estimate` for future seeds |
| "`--rows` preamble exists as 4 copies" | Confirmed: totality-mutations :66-118, lint-orphan :78-133, replay :62-123, test-all-affected :325-375 | Lib extraction, three variants catalogued above |
| "3 semantic variants" | Confirmed: repeat-flag (allow vs refuse), ordinal (required arg vs implicit), plus surface deltas (counter name `_row_seq`, bounds placement, arg-consume style) | `in_range [ord]` optional arg; refuse-repeat normalized (ruling) |
| "gate-accounting FATALs exit 1 in lint-orphan + replay but 2 in test-all-affected" | Confirmed; additionally totality-mutations' end gate prints `FAIL:`+exit 1, and test-all-affected's own early FATALs (:92,:109) exit 1 | Normalize all battery-process FATALs to 2 |
| "`MIN_ARM_CASES=EXPECTED_EXECUTED` only catches whole-block deletion" | Confirmed :4263-4267; lint-orphan already has the fix (`EXPECTED_ASSERTIONS`) | `ROWS_BLOCK_CASES` ordinal map + lib tracking |
| "`check_durations`'s enum in `scripts-shard-manifest.test.sh`" | Confirmed :314 (`src != measured && != floor`) | Widen to include `estimate` |

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing — worst
  case is a CI shard mis-pricing or a battery mis-reporting red/green on an
  internal test harness; all guards are fail-closed.
- **Brand-survival threshold:** `none`

## Observability

```yaml
liveness_signal:
  what: the four batteries run green on every test-scripts leg; a lib defect surfaces as a battery FATAL on the first arm run
  cadence: per CI run (9 arm registrations exercise the lib on every merge/PR)
  alert_target: required test-scripts check
error_reporting:
  destination: battery stdout/stderr in the CI job log
  fail_loud: every normalization target exits 2 (harness) or 1 (verdict) — no new silent path
failure_modes:
  - mode: lib semantics drift vs a copy (the risk this item retires)
    detection: per-arm `rows_gate_floor` reconciliation + totality-guard tiling arms
    alert_route: red required check
  - mode: `estimate` row priced as measured (laundering)
    detection: fixture cases in regenerate-shard-manifest.test.sh + `src` enum lint in check_durations
    alert_route: red required check
logs:
  where: CI job logs; TEST_TIMING_LOG unchanged
  retention: default Actions retention
discoverability_test:
  command: bash -n scripts/lib/rows-range.sh && grep -q 'rows_parse_args\|in_range\|rows_gate_floor' scripts/lib/rows-range.sh && printf 'ok\n'
  expected_output: ok
```

## Scope Check

| # | Issue ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "src=est … enum to {measured, floor, estimate} … supplies weight like measured in read_durations/read_durations_ms; widen check_durations" | S1 | mapped |
| 2 | "Extract scripts/lib/rows-range.sh … rows_parse_args, in_range [ord], rows_gate_floor; retire the copies" | S2 | mapped |
| 3 | "harness/shape FATALs exit 2, verdicts exit 1" | S3 | mapped |
| 4 | "per-block case counts (or a block-density map) so a gutted row reds" | S4 | mapped |
| 5 | "arm-convention ADR + split checklist … runbook or test-relevance-paths.sh HOW-TO" | S5 | mapped |

## Acceptance Criteria

- [ ] AC1: `label<TAB>ms<TAB>estimate` rows parse through `read_durations_rows`/`parse_durations_text`, supply weight in `read_durations`/`read_durations_ms` (`all_ms`/`weights`), and are never emitted as `measured` on any regen path (`src_map` preserves `estimate`).
- [ ] AC2: `check_durations` accepts `estimate`; fixture cases pin laundering refusal in `regenerate-shard-manifest.test.sh`.
- [ ] AC3: `scripts/lib/rows-range.sh` exists; all four batteries source it and call `rows_parse_args`/`in_range`/`rows_gate_floor`; no `--rows`-parse copy remains in any battery; ordinal enforcement is an optional arg (`in_range <ord>` used by lint-orphan).
- [ ] AC4: Every battery-process `FATAL`/`FATAL(harness)`/`[FATAL]`/shape-abort path exits 2; every verdict exit stays 1; the scoped site list above is the census.
- [ ] AC5: A `test-all-affected` block hollowed to fewer than its declared case count reds the ranged floor on every arm.
- [ ] AC6: `knowledge-base/engineering/architecture/decisions/ADR-313-*.md` exists and the sharding runbook carries the arm-split site checklist.
- [ ] AC7: `plugins/soleur/test/scripts-shard-totality.test.sh` green — Direction-1 literal census balanced, Direction-2 DECLARED_TOTAL census sees no lib declaration, all verbatim anchors hold.
- [ ] AC8: All four batteries green under `--rows <their registered ranges>` AND unflagged (full run) locally or via the shard legs.

## Test Scenarios

- Given `--rows` twice on one battery, then exit 2 naming the duplicate flag (all four — normalized refuse) — `unit`.
- Given `--rows 0-0`/`N-0`/out-of-bounds/garbage, then exit 2 (bounds + malformed arms) — `unit`.
- Given `in_range` fed a wrong ordinal in lint-orphan, then `FATAL(harness)` exit 2 — `unit`.
- Given a gutted `test-all-affected` block (delete all but one `cases+=`), then `rows_gate_floor` exits 2 naming the block — `unit` (the S4 proof).
- Given a `--durations` input with an `estimate` row, then the emitted table carries `estimate` and the packing used its weight — `unit`.
- Given `estimate` → measured upgrade via timings, then a named transition note (not a laundering refusal) — `unit`.

## Dependencies & Risks

- **Silent semantic drift on extraction** (the named risk): mitigated by the
  per-variant table above, a copy-level diff review, and running each battery
  per registered arm + unflagged before commit.
- **Anchor rot**: totality-mutations pins `run_suite --rows` lines and the
  `DECLARED_TOTAL=35` comment — none are touched; `bash
  plugins/soleur/test/scripts-shard-totality-mutations.sh` per matrix leg
  verifies.
- **`rows_parse_args` in sourced lib under `set -u`**: `${1-}` defaults;
  tested by every arm.
- **Est rows in baseline blobs**: `parse_durations_text` widened in the same
  commit — a merge-base blob containing `estimate` never dies the drift gate.
- **Exit-code flip breaking a caller**: none found — `suite_exit_class`
  collapses all nonzero to `failed`; recorded as a decision row for the
  reviewer to re-check.

## Deferrals

- Emitting `estimate` rows from the generator itself (today only hand-seeding
  produces them — the `--durations` round-trip preserves them, which is the
  laundering guard the item asks for; a `--seed-estimate` write path is
  out of scope).
- `ROWS_UNIT` error-text unification — cosmetic; each battery keeps its noun
  ("rows"/"sites"/"blocks") via `ROWS_UNIT` or the default.
- Promoting `estimate→measured` transitions into the drift *gate* (v1 emits a
  named note line like `floor→measured`).

## References & Research

- Issue jikig-ai/soleur#11647 (bundled deferrals), epic #11556, mandated-by #11562 (PR #11561 review panel), dispatch 1 #11648 (merged 0bc2634a40).
- `fe6963786f` (#11718) — arm re-price to real medians (item-1 premise staleness).
- Runbook `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md` §2026-10-30 pre-split baseline / §2026-10-31 re-price.
- Precedent: `EXPECTED_ASSERTIONS` declared floors (`lint-orphan-test-suites.test.sh:1194-1220`), `check_durations` keys-parity (`scripts-shard-manifest.test.sh:279-348`), `-<letter>` grouping (`regenerate-shard-manifest.py:760-795`, `scripts-shard-totality.test.sh:899-1003`).
