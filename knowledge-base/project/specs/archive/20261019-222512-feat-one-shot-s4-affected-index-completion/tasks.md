# Tasks: complete the S4 affected index and ratchet it (Ref #9729, #10448 option i)

Plan: `knowledge-base/project/plans/2026-10-19-feat-s4-affected-index-completion-plan.md`
Decisions: `knowledge-base/project/specs/feat-one-shot-s4-affected-index-completion/decision-challenges.md`
Every PR body ends `Ref #9729` and `Ref #10448` (never a closing keyword) and quotes the live `SOLEUR_PR_AFFECTED_AUDIT` line from its own tree. Baseline at plan time: `suites=643 always_on=116 audited=526 unaudited=1 gap_suites=195 gap_refs=1108`.

## Phase 1: PR1 - spike, fast and total audit, accept-row validation

- 1.0 Spike (results in the PR body, before any tokeniser code)
  - 1.0.1 Measure the cold cost of a nested `--print-selection` walk from inside a `test-all.sh` suite on a fresh clone; compare with the ceiling (180 s billed per full-battery run, 300 s suite timeout); if over, plan the `--rows FILE` fallback.
  - 1.0.2 Prototype timing of the component-boundary match with per-file memoisation on the pinned tree (target 30 s or less); if it misses, memoisation alone is the fallback and boundary precision becomes the conditional PR2.
- 1.1 Write failing tests first (Guard 2 also: M5 basename-collision and cache-poisoning rows, M6 comment/heredoc/CRLF fixtures, no-trailing-newline fixture, extra out-of-charset shapes; receipt check reads stored line text) in `plugins/soleur/test/ci-pr-affected-replay.test.sh` (Guard 2 rows M1-M5, harness rows, must-PASS suffix-path and tab-preceded fixtures; operation-count fixture, not wall clock)
- 1.2 Replace the `f in blob` scan in `suite_refs` (`scripts/ci-pr-affected-replay.py`) with the component-boundary scan, prefix set, per-file memoisation, cached one-hop library reads; leave `edge_hit` unchanged
- 1.3 Commit `receipts/audit-differential.tsv` (old versus new refs on a pinned tree); mechanically check every dropped ref has a mid-component start; run `scripts/audit-suite-reads.sh record --mode check --cover-from-selection` over the dropped refs of the heavy-tail suites and fail if any is observed opened
- 1.4 Directory-suite scan (bun-discoverable test files under a `dir/` pattern); reject `*` accept rows that name a readable suite
- 1.5 Accept-row validation in `load_accept`/`cmd_audit`: anchor column, mandatory `false-positive:` reason, (suite, path) accepted only when every boundary-match line is accepted, stale row fails, missing file means no exemptions; unit fixtures
- 1.6 Report the new live total after the directory-suite scan; apply the PR4/PR5 re-split trigger if added refs exceed half of 1,108
- 1.7 Raise the "human-written" wording on #10448 in the PR text (agent-drafted reasons, line anchors, reviewed as diff lines)
- 1.8 Carry this plan, `tasks.md` and `decision-challenges.md` in PR1; run the replay suite and `bash scripts/lint-orphan-test-suites.sh`

### PR1 review round 1 (CTO rulings 29-34, applied on this branch before merge)

- R1.1 `normalise()` single boundary definition (row 33); regex, `boundary()` and the test share it; fixtures for `\0`, `\x09`, `\011`, `\u0009`, `\a`, `\e`, `\033[0m<path>` (declared drop)
- R1.2 `git ls-files -z`; remove `len(f) > 6`; `BUN_TEST` superset (mjs, cjs, mts, cts) and bunfig `pathIgnorePatterns`; negatives (`x.test.ts.snap`, `latest.ts`)
- R1.3 `not-a-gap` stale rows (row 30); unreadable directory-suite member is `unaudited` with the file named (row 31)
- R1.4 extract `audit_census` and `load_rows`; keep line numbers (blank-replace comments, split on newline only); `--all-refs` prints `ref<TAB>suite<TAB>path<TAB>file:line<TAB>anchor/ordinal<TAB>text`
- R1.5 tests: an independent operation-count instrument (a floor and an upper bound, widths 40 versus 4000 top-level names), a preceding-character table, `boundary()` mutants, `mutant_outcome` crash-is-not-a-kill, empty-reason and comment-line accept fixtures, an old-scan oracle fixture asserting new is a subset of old
- R1.6 error text: name the field, say the 3-column format is retired; OSError to ReadError; stderr note for a missing `--accept` path
- R1.7 commit `receipts/audit-differential.py` (the regenerator) and regenerate the receipt per occurrence
- R1.8 runbook note for the new 5-column accept grammar, `plugins/soleur` audited, `stale=`; spike.md arithmetic; row 7 numbers

## Phase 1b: PR1b - audit reach (mandatory, before PR2 and PR3; rulings 29, 33)

- 1b.1 Failing tests first (Guard 2 rows for each item below, mutation-proven, with negative controls for the declared limits)
- 1b.2 Scan every existing tracked file listed in the row `pats` (files only, memoised per file), plus the suite inputs
- 1b.3 Comment stripping by extension, blanks replace stripped lines, newline-only splitting
- 1b.4 Resolve `$(dirname "$0")/`, `$SCRIPT_DIR/`, `$DIR/` source operands against the including file for any extension, depth 8 as the selector
- 1b.5 Credit an edge only if `_diff_edge_hit` would: parity fixture per edge kind (exact, dir, well-formed glob, malformed glob, raw non-caret entry)
- 1b.6 Report the new `SOLEUR_PR_AFFECTED_AUDIT` line; if PR1b adds more than 622 pairs re-split PR4 and PR5 by gap class; more than 1,244 stops the series for a re-ruling
- 1b.7 Reach is frozen from PR3 to PR5; open a deferral issue for the declared limits that need an owner (RUNNER_TRIGGERS premise, runner-declined suites, directory reads)

## Phase 2: PR2 (conditional) - boundary precision

- 2.1 Must land BEFORE PR3. Open only if memoisation alone met the 30 s target AND the dry run shows the rule drops at least 30 gap pairs; otherwise handle those pairs as accept rows in Phase 4/5
- 2.2 Failing tests first (Guard 3 rows M1-M4, harness rows); denylist left boundary, right boundary `[A-Za-z0-9_-]`
- 2.3 Commit `receipts/boundary-differential.tsv`; recorder must observe none of the dropped refs opened

## Phase 3: PR3 - the ratchet, the baseline, the ADR-276 amendment

- 3.1 Failing tests first in `scripts/ci-pr-affected-index-ratchet.test.sh` (Guard 1 rows M1-M14 plus M5b (same-suite pair swap) each with a pristine control and a distinct failure token, harness rows, declared-limit negative controls for variable-built paths / hop-2 libs / non-literal `source`, failure-text contract; controls from `--list` fixtures and scratch `git init` repos with `GIT_CEILING_DIRECTORIES`; one real selector walk)
- 3.2 `ratchet` subcommand in `scripts/ci-pr-affected-replay.py`: structural floors, exit codes 0/1/2 (ReadError and unexpected errors map to 2), baseline equals live gap set, merge-base growth rule as a pair-set subset check (not a count check) via `resolve_base`/`baseline_at` from `scripts/lint-ratchet.py` keyed on `RATCHET_BASELINE`, duplicate and unsorted refusal, absent baseline is strict zero except at the bootstrap PR, failure text with suite/path/line and both remedies
- 3.3 Create `scripts/ci-pr-affected-audit.baseline.tsv` (sorted, regenerated on the rebased tree just before merge)
- 3.3b `ratchet --print-baseline` (stdout only); failure text separates edited-suite / added-file / stale-row causes and prints the file and line to delete
- 3.3c Load `resolve_base`/`baseline_at` from `scripts/lint-ratchet.py` with `importlib.util.spec_from_file_location`; fixture proves the load
- 3.4 Register by exact file at the END of the block in `scripts/test-all.sh`; add the label to `ALWAYS_ON_SUITES` in `scripts/lib/test-affected-paths.sh`; add its own leg to `scripts/suite-shard-legs.tsv` and a row to `scripts/suite-durations.tsv` (registration-only runner diff); generate the leg and duration rows with `scripts/regenerate-shard-manifest.py`, do not hand-edit; add a real-registration test running `_aff_classify_runner_diff` on the PR3 diff (expects `registration-only`)
- 3.5 Measure and state the ratchet's cost cold and with a restored cache in the PR body; confirm it fits the ceiling or stop and re-rule
- 3.6 Run `bash scripts/lint-orphan-test-suites.sh`, the shard-totality census and `bash plugins/soleur/test/c4-count-parity.test.sh`
- 3.7 Append ADR-276 `## Amendment <date> (S4 index completion ratchet, #10448)` and a Stage-status line (non-activating; supersedes the `plugins/soleur` `*`-row clause by subject; residuals stated; append-only)
- 3.8 Update `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md` sections 2 and 3 (ratchet, baseline path, drain a row, contributor how-to, rollback recipe) plus sections "ratchet red on main" (fix forward leaving the ratchet green, no bypass, or revert), "bot PRs", "one drain PR at a time"; verify `grep -c '^test$' scripts/required-checks.txt` is 1 and the queue run executes the suite; simulate the revert in a scratch detached worktree and record what it needed

## Phase 4: PR4 - heavy-tail suites (about 611 of 1,108 refs)

- 4.1 For `scripts/test-affected-derive`, `.claude/hooks/grep-q-pipe-guard.test.sh`, `scripts/test-all-infra-coverage-notice`, `scripts/ci-pr-selection`, `tests/scripts/scratch-residue`: classify each ref from its line context; recorder as positive oracle
- 4.2 Always-on classification where the verdict is a whole-tree property (record minutes from `scripts/suite-durations.tsv`; rows instead when duration is 60 s or more)
- 4.3 One batched edit of `scripts/lib/test-affected-paths.sh`; drain the matching baseline pairs in the same commit

## Phase 5: PR5 - remainder, strict zero, closing line

- 5.1 Batch every remaining pair into one edit of `scripts/lib/test-affected-paths.sh` (alphabetical by label) plus anchor-keyed rows in `scripts/ci-pr-affected-audit.accept.tsv` (line kind and number in each reason); doc-class paths declared per suite that really reads them
- 5.2 Delete `scripts/ci-pr-affected-audit.baseline.tsv`; edit `scripts/ci-pr-affected-index-ratchet.test.sh` (retire baseline-only rows, add strict-zero rows including "reintroduced baseline refused")
- 5.3 Confirm `python3 scripts/ci-pr-affected-replay.py audit --accept scripts/ci-pr-affected-audit.accept.tsv` exits 0 with `gap_suites=0 unaudited=0`
- 5.4 Append the closing dated line to ADR-276 `### Stage status`; update the runbook; comment the result on #10448 (the replay re-run and go/no-go are a separate gate with their own go-ahead)

## Cross-cutting checks (every PR)

- No edit to `scripts/ci-pr-selection.sh`, `scripts/required-checks.txt`, `.github/workflows/ci.yml`, the `CI_PR_AFFECTED` variable or PR D files (`git diff origin/main...HEAD --stat -- <paths>` prints nothing)
- No commit identity `s@example.invalid`; `scripts/test-all-orphan-log-retention` red alone is the known flake, re-run it
- Re-check `gh pr view 10389 --json files` for overlap at the start of each PR
- 3.9 (review round 1, rulings 29 and 32) PR3 floors: rows printed equal `AFFECTED_SUMMARY of=`; malformed or space-prefixed rows are counted, not skipped; a fixture pinning what a registration-only diff selects; a non-blocking `oracle-inputs-changed:` line; every input from the PR tree and only the baseline growth rule reads the merge base; the ADR-276 amendment lists the declared limits (dynamic names, directory reads, ADR-262-gated suites, registration-only and staged diffs, bun helpers and bunfig preload, `\033` drops, block-comment over-report) and calls the audit necessary but not sufficient
