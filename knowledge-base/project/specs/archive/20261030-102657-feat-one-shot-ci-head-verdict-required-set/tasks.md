# Tasks: ci-head-verdict.sh required subcommand

Plan: knowledge-base/project/plans/2026-10-29-feat-ci-head-verdict-required-set-plan.md
Branch: feat-one-shot-ci-head-verdict-required-set | PR #11542 | Epic #9927 (Ref, not Closes) | Follow-up #11544

## Phase 1: Setup and failing tests (extend plugins/soleur/test/ci-head-verdict.test.sh)

- [x] 1.1 Check each existing mutant M1 to M49 `old` literal against the planned new code (Sharp Edges list); note collisions before writing code
- [x] 1.2 Extend the gh stub: `actions/runs?head_sha=...&per_page=100`; real-child argv (`pr view --json ...`, pulls files, rules/branches/main, commits check-runs) with its own `prview.json`
- [x] 1.3 Add the child stub (fixture marker plus rc) selected through `ADMIN_MERGE_READY_BIN`; real-child rows set the seam to the real script through `VRUN_ENV`
- [x] 1.4 Write rows R1 to R11, R-E1 and R-E2 (table-driven R5 to R8) and extend V19 with the `required` usage cases; confirm they are RED against the unmodified script

## Phase 2: Core implementation (plugins/soleur/scripts/ci-head-verdict.sh)

- [x] 2.1 `read_pr` captures `.base.ref` into `PR_BASE` (verdict behaviour unchanged)
- [x] 2.2 `req_marker` (single printf), `emit_required`, `fail_api` `required` branch (`-` for unknown scalars and arrays)
- [x] 2.3 `amr_parse` (strict prefix with `base=[^ ]+`, single last marker line, single-value arrays of strings without control characters, byte-exact round trip, total <= required)
- [x] 2.4 `classify_required` (exit-code allow-list, rows 1 to 12 of the state table; the empty-array reason pass-through (row 10) comes BEFORE the required=0 test (row 11); precedence failed > absent > pending); validate PR_BASE (`bad-base`); INT/TERM/HUP trap -> `error interrupted`; `SHA_OUT=unknown` prints `-`
- [x] 2.5 `resolve_owners` (one runs-list read, unique normalized workflow-name match, else candidates; read failure degrades text only; skip only the `test` context when reason is stalled; stale-row / awaiting-approval pointers; `run=`/`basis=` before quoted ctx/wf; candidates carry no command text)
- [x] 2.6 `cmd_required` wiring, `required` in the subcommand case and `usage()`, header contract (reason vocabulary, seam, F-rulings)
- [x] 2.7 Make R1 to R11 and R-E1 green; run the whole suite

## Phase 3: Mutants, floors and docs

- [x] 3.1 Add mutants M50 onward (matrix rows 1 to 15 under Guard Contract; kill rows assert state AND reason) with kill rows; raise MIN_ASSERTIONS and MIN_MUTANTS to measured counts
- [x] 3.2 Add the section to plugins/soleur/skills/ship/references/ready-run-wait.md (no second ready-count/wait chain); R11 checks it
- [x] 3.3 Run ci-head-verdict.test.sh, admin-merge-ready.test.sh, admin-merge-ready-wiring.test.sh, monitor-pr-checks.test.sh and shellcheck

## Phase 4: Ship-time

- 4.1 PR body: Changelog, the sentence that this gap moves out of the epic's LUKS scope, `Ref #9927`, link #11544; label semver:patch
- 4.2 Comment (not a body edit) on #9927 linking the PR
