# Tasks — fix ShellCheck scan bound and argv-bearer split (#13098, #13099)

Plan: `knowledge-base/project/plans/2026-11-27-fix-shellcheck-timeout-argv-sweep-split-plan.md`
Branch: `feat-one-shot-13098-13099-shellcheck-split`

Ordering note: write failing contracts first. Keep the scan-gate change and the mechanical suite split in separable commits inside this one PR.

## Phase 1 — failing contracts

- [ ] 1.1 Extend `plugins/soleur/skills/review/test/review-scan-gate.test.sh` with hermetic rows for per-file invocation, aggregation, hanging stub timeout, oversize prefilter, missing timeout binary, malformed JSON, and `ok` only when `unscannable=0`.
- [ ] 1.2 Add the driver-embedded structural preamble in RED form, deriving `git ls-files 'tests/scripts/argv-bearer-sweep/*.sh'` and parsing driver source order; the current monolith must fail because no compliant fragment manifest exists yet.
- [ ] 1.3 Run both focused suites and record the intended RED failure mode before implementation.

## Phase 2 — bounded scan gate

- [ ] 2.1 Implement timeout-binary resolution (`timeout` then `gtimeout`), 30s/5s bound, 524,288-byte prefilter, per-file ShellCheck invocation, per-file JSON parsing, and `scanned=`/`unscannable=` receipt accounting in `plugins/soleur/skills/review/scripts/review-scan-gate.sh`.
- [ ] 2.2 Update `plugins/soleur/skills/review/SKILL.md` with unscannable/refuse semantics and the zero-finding interpretation.
- [ ] 2.3 Amend `knowledge-base/engineering/architecture/decisions/ADR-324-review-scan-evidence-is-the-orchestrator-read.md` in the same commit series.
- [ ] 2.4 Run the scan-gate focused suite green and exercise the Guard 1 mutation rows.

## Phase 3 — mechanical argv-bearer split

- [ ] 3.1 Mechanically extract the ten fragments under `tests/scripts/argv-bearer-sweep/` using the contiguous ranges in the plan; prepend only `# shellcheck shell=bash` and the sourced-fragment header.
- [ ] 3.2 Rewrite `tests/scripts/test-argv-bearer-sweep.sh` as the stable driver retaining core harness/prelude, final verdict/floor, and unconditional ordered source statements.
- [ ] 3.3 Compare extracted content to the pre-split `HEAD` ranges with only the documented normalization; investigate any semantic difference before proceeding.
- [ ] 3.4 Update `scripts/lib/test-affected-paths.sh`, `tests/scripts/trio-baseline.tsv`, and `plugins/soleur/test/fixture-relative-assert.baseline.txt` only where the owning checks require it.
- [ ] 3.5 Do not edit `scripts/test-all.sh` or shard/duration metadata for the structural check; it rides inside the already-registered argv-bearer suite because `scripts/test-all.sh` is oversize under the new scan prefilter.
- [ ] 3.6 Preserve/update the floor-history comment and exact `EXPECTED_TESTS` count from measured post-split output.

## Phase 4 — verification

- [ ] 4.1 Run `bash plugins/soleur/skills/review/test/review-scan-gate.test.sh` green.
- [ ] 4.2 Verify the structural preamble indirectly through `bash tests/scripts/test-argv-bearer-sweep.sh` and directly in scratch mutants.
- [ ] 4.3 Run `bash tests/scripts/test-argv-bearer-sweep.sh` green at the same measured row count as the pre-split oracle (currently 832 unless implementation evidence proves otherwise).
- [ ] 4.4 Run a bounded ShellCheck probe over driver plus all ten fragments; completion is required, warning findings are disclosed rather than silently rewritten away.
- [ ] 4.5 Exercise the Guard 2 mutation rows in scratch copies.
- [ ] 4.6 Before any broad `test-all.sh` run, re-check the foreign full-battery processes observed during planning; prefer focused suites plus CI while they remain active.

## Acceptance criteria

See the plan's `## Acceptance Criteria` (FR-1 through FR-10 plus NFR and quality gates).
