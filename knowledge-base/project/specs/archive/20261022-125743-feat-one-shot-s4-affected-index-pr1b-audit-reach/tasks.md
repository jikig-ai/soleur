# Tasks: S4 affected-index PR1b, audit reach (Ref #9729, Ref #10448)

Plan: `knowledge-base/project/plans/2026-10-20-feat-s4-affected-index-pr1b-audit-reach-plan.md`
Decisions: `knowledge-base/project/specs/feat-one-shot-s4-affected-index-pr1b-audit-reach/decision-challenges.md`
PR body ends `Ref #9729` and `Ref #10448` (never a closing keyword) and quotes the live `SOLEUR_PR_AFFECTED_AUDIT` line from the PR's own pinned tree. Hard constraints: no flip of `CI_PR_AFFECTED`, no lock removal, no replay or go/no-go re-run, no PR D; no edit of `scripts/test-all.sh`, `scripts/lib/test-affected-paths.sh`, `.github/workflows/ci.yml`, `scripts/required-checks.txt`.

## Phase 0: baseline on the PR's own pinned tree

- 0.1 `git fetch origin main`; rebase if main moved; record the start commit
- 0.2 Save the old SUT (`git show HEAD:scripts/ci-pr-affected-replay.py`) and its blob sha
- 0.3 Detached worktree at the start commit; build `rows.txt` there in the background (Monitor, no foreground wait); record its sha256; remove the worktree after
- 0.4 Baseline `B` from the OLD SUT with `--root <pin> --list rows.txt` (expect about gap_suites=199, gap_refs=1264); re-split line `ceil(B/2)`, stop line `B`

## Phase 1: failing tests first (RED), `plugins/soleur/test/ci-pr-affected-replay.test.sh`

- 1.1 Section `audit reach (PR1b)` with its own fixture repo `$RREPO` (never `$SREPO`/`$AREPO`); behaviour rows run against the PR1 SUT first and the RED list goes in the PR body; `mutate` rows are written in Phase 2 against anchors that exist; table loops emit a named pass/fail per row; bash oracle computed once
- 1.2 Hop closure fixtures: 3-level chain, 9-lib chain (depth 8 both ways), two-`source` file with `$SCRIPT_DIR/` second, cycle (each line listed once), fan-out lattice under the operation-count instrument
- 1.3 Operand forms: one table-driven loop with a size floor and a two-hop variant (suite to library in A to target in A) (dirname `$0`, dirname BASH_SOURCE, SCRIPT_DIR, HERE, DIR, REPO_ROOT, ROOT_DIR, bare `./`, one unknown `$X/`); negatives (untracked, runner trigger, prose `see. lib/x.sh`, comment)
- 1.4 Pats walk fixtures (walk files also follow `source` hops; per-call `seen` set; both row orders): listed+named read, not-listed not read, listed-not-named not read, `.md`/`.yml`/`.tsv` not read, 9-level chain, runner-trigger stub absent, `glob:`/`dir/` never nodes, per-row same-label fixture (A lists and declares, B does not list)
- 1.5 Unreadable reach (dangling hop target at depth 3, dangling pats code file): that suite `unaudited unreadable:<rel>`, neighbour still scanned
- 1.6 Comment table fixtures (own language blanked, other language kept, unknown extension strips nothing, quotes and `$#`, CRLF, tab, line numbers)
- 1.7 Edge parity: generated table, differential against the real `_NL`, `_diff_edge_hit`, `_diff_touches` extracted by content anchors (env controls neutralised, `LC_ALL=C`), rows run against `$SUT`; each malformed arm isolated so only its own arm can fire (six head alternatives separately) and a path the well-formed reading rejects
- 1.8 Ordinals through the file column of `--all-refs` ref lines (input, its closure, then walk files and their closures), identical `ref` lines when the same rows are presented in both orders (canonical order, CTO round 2)
- 1.9 Marker field list regex; synthetic per-class fixture (`.sh`, `.py`, `.ts` through the walk); cost instrument on `reach_texts`/`audit_census` under settrace: linear in `pats` width (400 vs 4,000, at most about 12x) and not multiplied by files or levels
- 1.10 Harness rows and fixtures only; the `mutate` rows are added in Phase 2 with each helper (one mutant per property failure, separate depth constants, hop memo, canonical sort)

## Phase 2: implementation, `scripts/ci-pr-affected-replay.py`

- 2.1 `COMMENT_PREFIX` + `strip_comments(text, prefixes)`; `read_text` passes the real path
- 2.2 Hop resolver (`hop_targets`, operand table, `.sh`/`.bash` tracked targets, never runner triggers; memo of RAW matches per real path in `index.hops`, resolved per call against the logical including path; symlinked-library fixture)
- 2.3 Source closure in `suite_texts` (depth 8, visited set, per input: input then closure)
- 2.4 `reach_texts` pats walk (per row, row-local seen set, code extension set, depth 8, named literally, sorted per level; walk files also get the hop closure); canonical order of `texts_of` before numbering; `suite_texts` stays closure-only with the frozen 4-tuple shape
- 2.5 `edge_hit` rewrite to the selector grammar (single function, single call site)
- 2.6 Docstring and `--help`: single source of the reach definition and declared limits; "necessary but not sufficient"
- 2.7 Re-anchor existing mutation rows (`audit-comments-counted`, `comment-trailing-stripped`, `comment-tab-indent-kept`, `comment-line-deleted`, `audit-edge-as-regex`, `audit-edge-as-regex-exact`, `audit-glob-not-a-glob`, `scan-library-hop-dropped`, any `edit-failed`)

## Phase 3: receipts

- 3.1 `receipts/reach-differential.py` (importlib, standard library, refuses to write and exits 1 when `added >= base_pairs`, notes the re-split line) and generated `reach-differential.tsv` with header `old_sut tree rows_sha256 base_pairs new_pairs added removed`
- 3.2 One suite row that runs the generator on a scratch repo against a fixture old SUT at B=0, `ceil(B/2)-1`, `ceil(B/2)`, `B-1`, `B` (header counts equal data rows; exit codes; no file written at B); fails, never skips, when the script is not found
- 3.3 Quote the numbers: new audit line, added/removed, code vs non-code split, top ten additions, `audit --list` wall time, pre-pass time separately

## Phase 4: documentation

- 4.1 Runbook `ci-pr-affected-activation.md`: one paragraph (reach, drain-reveal rule, "necessary but not sufficient", pointer to `--help`)

## Phase 5: verification and hand-off

- 5.1 Replay suite green (about seven minutes); PR1 receipt check and `row_regen` rows unchanged and green; pinned-tree `reach-differential` numbers never mixed with the final-tree audit; every re-anchored row lands exactly once and still kills
- 5.2 `reach-differential.py` on the pinned tree and rows; full `audit` once on the final tree
- 5.3 `technical-ruling-gate.sh --branch` PASS; acceptance commands of the plan
- 5.4 PR body: RED list, numbers, re-split decision for PR4/PR5, Handoff list; comment on #10448; keep the operator hold (flip, lock, replay, go/no-go) recorded, executing none of it
- 5.5 Handoff to PR3 (ADR-276 amendment text: frozen reach, declared limits, drain-reveal rule, thresholds) carried in the PR body and the plan's `## Handoff to PR3`
