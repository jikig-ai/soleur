# Tasks — feat-one-shot-9035-tiling-guard-hardening

Derived from `knowledge-base/project/plans/2026-09-27-feat-tiling-guard-hardening-plan.md`.
Issue: #9035. Row/site names below match the plan's Guard Contract matrices.

## Phase 1 — Widen the guard (`plugins/soleur/test/scripts-shard-totality.test.sh`)

- [x] 1.1 Add shared declaration-regex constants (`_DECL_PREFIX_RE`, `_DECL_RE`)
      near the top of the guard: keyword whitelist
      `(export|readonly|local|typeset|declare)` with optional flag argument,
      anchored to line-start with whitespace separators.
  - [x] 1.1.1 Apply at the battery ground-read `sed` (the `_decl_total`
        derivation for the ci.yml arm).
  - [x] 1.1.2 Apply at the per-token `grep -lE` (rs_decl_tokens), the
        per-token `sed` reader (`_decl`), and the `_decl_lines` counter.
  - [x] 1.1.3 Apply at the Direction-2 census grep.
- [x] 1.2 Spelling-tolerant `rows:` handling:
  - [x] 1.2.1 Singleton census regex → `^[[:space:]]*["']?rows["']?[[:space:]]*:`
        (covers `rows :`, `"rows":`, `'rows':`, column-0).
  - [x] 1.2.2 Same tolerance in the `shard-totality-mutations` job-block awk —
        both the `inj &&` match and the `gsub` list extraction.
- [x] 1.3 Whole-token `--rows` capture in the run_suite awk extractor:
  - [x] 1.3.1 Emit the verbatim next token after `--rows` (not the
        `[0-9]+-[0-9]+` prefix).
  - [x] 1.3.2 Per-token loop: any flagged range field failing
        `^[0-9]+-[0-9]+$` → dedicated `malformed --rows spec '<tok>'` fail,
        evaluated before sorting/tiling.
- [x] 1.4 Direction-1 literal census: replace `scripts/lib/*.sh` with
      recursive `git ls-files`-based lib-tree enumeration (tracked +
      untracked-non-ignored; `*.sh`/`*.bash` basename or extensionless shell
      shebang; document the `fixtures/` data-dir exclusion in the comment).
- [x] 1.5 Direction-2 declaration census: replace the two-tree `grep -rlE`
      with `git -C "$REPO_ROOT" ls-files --cached --others --exclude-standard`
      ∩ shell predicate minus `**/fixtures/**`; enumeration failure fails
      loudly; add `[[ -s "$WORK/decl_census" ]]` fail-closed check.
- [x] 1.6 Re-derive `MIN_ROWS` (45 + new assertion sites added).
- [x] 1.7 Checkpoint: guard exits 0 on the unmutated tree.

## Phase 2 — Battery drivers (`plugins/soleur/test/scripts-shard-totality-mutations.sh`)

- [x] 2.1 Extend the managed-target set: add `scripts/suite-shard-legs.tsv`
      and `scripts/lint-orphan-test-suites.test.sh` — pristine copies,
      `restore_all` entries, `row()` `case` arms, dirty-tree refusal list.
- [x] 2.2 Add `erow()` helper (write ephemeral file → `guard_rc` → score →
      remove → verify removal) + `EPHEMERAL_FILES` array consumed by the
      EXIT trap.
- [x] 2.3 Land the fifteen row sites after `ROWS-SWAP`, each `in_range`-gated,
      every RED row carrying its `want_sig`:
  - [x] 2.3.1 `ROWS-CI-GAP` — ci.yml last-leg lo-bound +1 → RED
        ("mutation row ranges do not tile").
  - [x] 2.3.2 `ROWS-CI-ORDER` — reorder matrix literals → GREEN (must-PASS).
  - [x] 2.3.3 `ROWS-CI-KEY2` — phantom job block with canonical `rows:` →
        RED ("rows: matrix keys").
  - [x] 2.3.4 `ROWS-CI-KEY2-SPACE` — phantom job with `rows :` → RED.
  - [x] 2.3.5 `ROWS-CI-KEY2-QUOTE` — phantom job with `"rows":` → RED.
  - [x] 2.3.6 `ROWS-MALFORMED-SUFFIX` — `--rows 9-16` → `--rows 9-16x` →
        RED ("malformed --rows spec").
  - [x] 2.3.7 `ROWS-MALFORMED-TRISEG` — `--rows 9-16` → `--rows 9-16-24` →
        RED ("malformed --rows spec").
  - [x] 2.3.8 `ROWS-UNRESOLVED` — `bash` → `sh` on -a registration →
        RED (`<unresolved>`).
  - [x] 2.3.9 `ROWS-ALL-UNFLAGGED` — drop both `--rows` flags (two-line
        anchor) → RED ("carry no --rows").
  - [x] 2.3.10 `DIR1-MIDLINE` — `run_suite` → `true && run_suite` on -a →
        RED ("literal census").
  - [x] 2.3.11 `DIR1-LIBSUBDIR` — `erow` ephemeral `scripts/lib/zz/x.sh`
        (uncalled function holding a `--rows` literal) → RED
        ("literal census").
  - [x] 2.3.12 `LEGS-COLOCATE` — TSV `-b` leg 5 → 3 → RED ("pin to legs").
  - [x] 2.3.13 `DECL-SCOPE-FOREIGN` — `erow` ephemeral
        `apps/zz-decl-scope-battery.sh` declaring `DECLARED_TOTAL=3`
        unregistered → RED ("NEITHER run_suite argv nor a ci.yml").
  - [x] 2.3.14 `DECL-PREFIX-CENSUS` — `erow` ephemeral
        `scripts/zz-decl-prefix-fixture.sh` with `export DECLARED_TOTAL=2`
        → RED ("NEITHER run_suite argv nor a ci.yml").
  - [x] 2.3.15 `DECL-PREFIX-READER` — `DECLARED_TOTAL=16` →
        `export DECLARED_TOTAL=16` on lint-orphan battery → GREEN
        (must-PASS, end-to-end prefix tolerance).
- [x] 2.4 `DECLARED_TOTAL` 27 → 42; update header comment (three
      invocations, new total).
- [x] 2.5 Checkpoint: `bash plugins/soleur/test/scripts-shard-totality-mutations.sh --rows 1-42`
      — every new row lands and scores as designed.

## Phase 3 — Re-split the matrix (`.github/workflows/ci.yml`)

- [x] 3.1 `rows: ["1-14", "15-27"]` → `rows: ["1-14", "15-28", "29-42"]`.
- [x] 3.2 Update the job comment block (two-leg → three-leg, row counts,
      ~24 s/row sizing basis).

## Phase 4 — Verification

- [x] 4.1 `bash plugins/soleur/test/scripts-shard-totality-mutations.sh`
      for each of `--rows 1-14`, `15-28`, `29-42` — all-in-range rows green.
- [x] 4.2 `bash plugins/soleur/test/scripts-shard-totality.test.sh` exits 0
      on the clean tree.
- [x] 4.3 `python3 scripts/lint-guard-contract.py` exits 0 repo-wide.
- [x] 4.4 `bash scripts/test-all.sh scripts` — the shard carrying the guard
      suite passes.
- [x] 4.5 Acceptance criteria AC1–AC8 in the plan verified against the diff.
