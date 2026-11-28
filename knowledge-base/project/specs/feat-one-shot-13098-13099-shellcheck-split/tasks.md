# Tasks — fix ShellCheck scan bound and argv-bearer split (#13098, #13099)

Plan: `knowledge-base/project/plans/2026-11-27-fix-shellcheck-timeout-argv-sweep-split-plan.md`
Branch: `feat-one-shot-13098-13099-shellcheck-split`

Ordering note: write failing contracts first. Keep the scan-gate change and the mechanical suite split in separable commits inside this one PR. Rebase onto current `origin/main` before implementation; the extraction line ranges are coordinates to re-verify, not immutable anchors.

## Phase 1 — failing contracts

- [x] 1.1 Extend `plugins/soleur/skills/review/test/review-scan-gate.test.sh` with hermetic rows for per-file invocation order, findings aggregation across two files, hanging-stub timeout, missing `timeout`/`gtimeout`, `gtimeout` fallback, malformed JSON, leading-dash filename handling, and `ok` only when `unscannable=0`.
- [x] 1.2 Add the driver-embedded structural preamble in RED form, deriving `git ls-files 'tests/scripts/argv-bearer-sweep/*.sh'` and parsing driver source order; the current monolith must fail because no compliant fragment manifest exists yet.
- [x] 1.3 Run both focused suites and record the intended RED failure mode before implementation.

## Phase 2 — bounded scan gate

- [x] 2.1 Implement timeout-binary resolution (`timeout` then `gtimeout`), 30s/5s bound, no byte-size prefilter, per-file ShellCheck invocation with `--`, per-file JSON parsing, and `scanned=`/`unscannable=` receipt accounting in `plugins/soleur/skills/review/scripts/review-scan-gate.sh`.
- [x] 2.2 Keep full default ShellCheck analysis; do not pass `--extended-analysis=false` in this implementation.
- [x] 2.3 Repair the adjacent double-`mktemp`/`TMP` reassignment so one tempdir owner is covered by one cleanup trap.
- [x] 2.4 Update `plugins/soleur/skills/review/SKILL.md`, `plugins/soleur/agents/engineering/review/semgrep-sast.md`, and `plugins/soleur/agents/engineering/review/security-sentinel.md` with unscannable/refuse semantics and the zero-finding interpretation (`ok` + `findings=0` + `unscannable=0`).
- [x] 2.5 Amend `knowledge-base/engineering/architecture/decisions/ADR-324-review-scan-evidence-is-the-orchestrator-read.md` in the same commit series.
- [x] 2.6 Run the scan-gate focused suite green and exercise the Guard 1 mutation rows.

## Phase 3 — mechanical argv-bearer split

- [x] 3.1 Mechanically extract the ten fragments under `tests/scripts/argv-bearer-sweep/` using the contiguous ranges in the plan after re-verifying boundary text post-rebase; prepend only `# shellcheck shell=bash` and the sourced-fragment header.
- [x] 3.2 Rewrite `tests/scripts/test-argv-bearer-sweep.sh` as the stable driver retaining core harness/prelude, final verdict/floor, and canonical contiguous ordered source statements.
- [x] 3.3 Compare extracted content to the pre-split `HEAD` ranges with only the documented normalization; investigate any semantic difference before proceeding.
- [x] 3.4 Update `scripts/lib/test-affected-paths.sh` with the fragment directory prefix `tests/scripts/argv-bearer-sweep/` (not a static ten-member list) and re-anchor stale line-number comments to content anchors.
- [x] 3.5 Update `tests/scripts/trio-baseline.tsv` and `plugins/soleur/test/fixture-relative-assert.baseline.txt` only where the owning checks require it, using their committed regeneration commands and reviewing the resulting diff row by row.
- [x] 3.6 Do not edit `scripts/test-all.sh` or shard/duration metadata for the structural check; it rides inside the already-registered argv-bearer suite to avoid adding another registration surface.
- [x] 3.7 Preserve/update the floor-history comment and exact `EXPECTED_TESTS` count from measured post-split output.

## Phase 4 — verification

- [x] 4.1 Run `bash plugins/soleur/skills/review/test/review-scan-gate.test.sh` green.
- [x] 4.2 Verify the structural preamble indirectly through `bash tests/scripts/test-argv-bearer-sweep.sh` and through static scratch mutants where cheap, with conditional execution covered by exact runtime row-count equality.
- [x] 4.3 Run `bash tests/scripts/test-argv-bearer-sweep.sh` green at the same measured row count as the pre-split oracle (currently 832 unless implementation evidence proves otherwise).
- [x] 4.4 Run a bounded full-analysis ShellCheck probe over driver plus all ten fragments; completion is required, warning findings are disclosed rather than silently rewritten away.
- [x] 4.5 Exercise the Guard 2 mutation rows in scratch copies.
- [x] 4.6 Before any broad `test-all.sh` run, re-check foreign full-battery processes; prefer focused suites plus CI while contention remains.
- [x] 4.7 Record the actual receipt shape for one clean scan and one synthetic timeout in implementation evidence, including `scanned=` and `unscannable=`.

## Acceptance criteria

See the plan's `## Acceptance Criteria` (FR-1 through FR-10 plus NFR and quality gates).
