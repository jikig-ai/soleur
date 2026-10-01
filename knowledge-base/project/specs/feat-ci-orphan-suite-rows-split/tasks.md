# Tasks — feat-ci-orphan-suite-rows-split

Derived from `knowledge-base/project/plans/2026-09-26-feat-ci-orphan-suite-rows-split-plan.md`
(post-review). Issue #8864 · PR #8967 · Branch `feat-ci-orphan-suite-rows-split`.

## 1. Battery: `--rows` gate + DECLARED_TOTAL floors

Edit `scripts/lint-orphan-test-suites.test.sh`:

- [ ] 1.1 Add `DECLARED_TOTAL=16` (bare constant — the tiling guard greps
  `^DECLARED_TOTAL=`; no trailing comment on the assignment). Gated space =
  M1–M16; C0/R1/R1b stay unconditional.
- [ ] 1.2 Port the `--rows A-B` parser from
  `plugins/soleur/test/scripts-shard-totality-mutations.sh` (:79-100),
  placed **before** `build_pristine`: `^[0123456789]+-[0123456789]+$`,
  `10#` decode, `1<=A<=B<=DECLARED_TOTAL` else exit 2, unknown args exit 2,
  `ROWS_HI=0` = all rows. **Divergence:** a repeated `--rows` also exits 2.
- [ ] 1.3 Adapt the ported header comment: name `test-all.sh` `run_suite`
  argv as the split site, the same-commit DECLARED_TOTAL-bump + re-split
  rule, and the tiling guard's location.
- [ ] 1.4 Add `in_range()` keyed on `${_id#M}` (suffix ordinal asserted equal
  to incremented `_site_seq`); increment `_site_seq` on every gated call,
  `EXECUTED` only in-range.
- [ ] 1.5 Dispatch C0 ahead of the gate; gate M1–M16 via standalone
  `in_range || continue` (never `in_range && ( worker ) &` — `&` binds the
  AND-list into the subshell).
- [ ] 1.6 Record dispatched ids parent-side (`EXEC_IDS+=("$_id")` or a
  `$TMP/executed` file); replay + aggregation iterate that set — never
  re-derive (no substring membership: `M1` ⊂ `M10`–`M16`; never re-call
  `in_range`).
- [ ] 1.7 Directory-side `.rc` audit: count == `1 + EXECUTED`; every `.rc`
  id dispatched-or-C0 (rogue → FATAL); dispatched-but-missing →
  `harness_die` preserved.
- [ ] 1.8 Replace `MIN_ROWS=18` floors: `_site_seq == DECLARED_TOTAL`,
  `EXECUTED == (ROWS_HI==0 ? DECLARED_TOTAL : hi-lo+1)`, `EXECUTED >= 1`,
  conservation `ROWS == EXECUTED + 3`. `printf >&2` + `exit 1` directly,
  constant on the line immediately above each `if` (ADR-193).
- [ ] 1.9 `.rc` gains field 4 (declared expected assertions, written beside
  the `run_<id>` call) and field 5 (elapsed seconds — permanent, powers
  future re-splits). Aggregation: `read -r _p _f _g _d _t`; `_d`
  mandatory-numeric (missing → FATAL); per-row `actual >= declared`; +
  `2*GLOB_MEMBER_N` only when M5 executes (M5 may fold the term into its
  own declared field). Unconditional base = 5 (`:198`, `:202`, R1, R1b,
  positive-control net). Starting values to verify: M1=3 M2=3 M3=3 M4=2
  M5=1 M6=3 M7=2 M8=3 M9=4 M10=3 M11=2 M12=2 M13=4 M14=3 M15=3 M16=3
  (Σ=44; C0=3; total = 52 + 2G).

## 2. Registration + manifest (same commit as Phase 3)

- [ ] 2.1 Measure per-row elapsed (task 1.9's field) via one local battery
  run; pick the split boundary that balances halves (placeholder `1-8` /
  `9-16`).
- [ ] 2.2 `scripts/test-all.sh` :3486 — two `run_suite` lines:
  `…-mutations-a bash scripts/lint-orphan-test-suites.test.sh --rows <lo-mid>`
  and `…-mutations-b … --rows <mid+1-16>`; registration comment names the
  pairing and corrects "eleven rows".
- [ ] 2.3 `scripts/suite-shard-legs.tsv` — drop the phantom
  `lint-orphan-test-suites-mutations` row; pin `-a`/`-b` on distinct legs
  (≤ n=7); note hand-edit provenance.
- [ ] 2.4 `scripts/lib/test-affected-paths.sh` :103 — `ALWAYS_ON_SUITES`
  swap old label → both new labels.
- [ ] 2.5 Comment fixes: `test-all.sh` :4592 "six legs" → "seven legs";
  noun-sweep `legs`|`K=` scoped to edited regions (:3677 "all six jobs" is
  deploy legs — leave).

## 3. Tiling guard (same commit)

`plugins/soleur/test/scripts-shard-totality.test.sh`, beside :695-738:

- [ ] 3.1 Extractor: `run_suite` lines carrying `--rows` (join continuations,
  strip `#`-onward, anchor on the flag arg, never label; never `skip_suite`).
- [ ] 3.2 Group per command token; read each battery's `DECLARED_TOTAL`;
  sort ranges by lo-bound; assert contiguous `1..DECLARED_TOTAL` tiling.
- [ ] 3.3 Arms: non-vacuity (DECLARED_TOTAL battery → zero ranges = RED);
  unflagged same-token registration = RED; missing-DECLARED_TOTAL token =
  finding; distinct-legs pin for `-a`/`-b` in the TSV.
- [ ] 3.4 Committed positive control (mirroring `totality_holds` :289-298):
  fixture `1-8` + `10-16` vs `DECLARED_TOTAL=16` must report the gap.

## 4. Verification

- [ ] 4.1 Local: no-flag full run; both ranges; malformed/out-of-bounds/
  repeated `--rows` exit 2 before pristine build; deleted-site, dead-worker,
  rogue-`.rc` mutations each FATAL.
- [ ] 4.2 Tiling guard dev-driven RED on each mutation-matrix row.
- [ ] 4.3 `python3 scripts/regenerate-shard-manifest.py --run <id>` dry-run:
  no predicted leg ≥ ~9.5 min.
- [ ] 4.4 Neighbor ratchets: `fixture-relative-assert.test.sh`,
  `guard-vacuity-floor.test.sh`, `no-control-regex`.
- [ ] 4.5 Runbook `ci-test-scripts-sharding.md` — measured-history entry
  recording the split.
- [ ] 4.6 CI on this PR: both halves on distinct legs < ~9.5 min; name them
  in the PR body (leg-distinctness evidence). `--affected` degrades to full
  battery on `run_suite` diffs — expected.
