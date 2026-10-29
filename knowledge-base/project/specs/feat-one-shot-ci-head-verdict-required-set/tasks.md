# Tasks: ci-head-verdict.sh required subcommand

Plan: knowledge-base/project/plans/2026-10-29-feat-ci-head-verdict-required-set-plan.md
Branch: feat-one-shot-ci-head-verdict-required-set | PR #11542 | Epic #9927 (Ref, not Closes) | Follow-up #11544

## Phase 1: Setup and failing tests (extend plugins/soleur/test/ci-head-verdict.test.sh)

- 1.1 Check each existing mutant M1 to M49 `old` literal against the planned new code (Sharp Edges list); note collisions before writing code
- 1.2 Extend the gh stub: `actions/runs?head_sha=...&per_page=100`; real-child argv (`pr view --json ...`, pulls files, rules/branches/main, commits check-runs) with its own `prview.json`
- 1.3 Add the child stub (fixture marker plus rc) selected through `ADMIN_MERGE_READY_BIN`; real-child rows set the seam to the real script through `VRUN_ENV`
- 1.4 Write rows R1 to R11 and R-E1 (table-driven R5 to R8) and extend V19 with the `required` usage cases; confirm they are RED against the unmodified script

## Phase 2: Core implementation (plugins/soleur/scripts/ci-head-verdict.sh)

- 2.1 `read_pr` captures `.base.ref` into `PR_BASE` (verdict behaviour unchanged)
- 2.2 `req_marker` (single printf), `emit_required`, `fail_api` `required` branch (`-` for unknown scalars and arrays)
- 2.3 `amr_parse` (strict prefix, single last marker line, byte-exact array round trip, JSON array of strings, total <= required)
- 2.4 `classify_required` (exit-code allow-list, rows 1 to 12 of the state table, precedence failed > absent > pending)
- 2.5 `resolve_owners` (one runs-list read, unique normalized workflow-name match, else candidates; read failure degrades text only; skip for stalled / awaiting-approval)
- 2.6 `cmd_required` wiring, `required` in the subcommand case and `usage()`, header contract (reason vocabulary, seam, F-rulings)
- 2.7 Make R1 to R11 and R-E1 green; run the whole suite

## Phase 3: Mutants, floors and docs

- 3.1 Add mutants M50 onward (matrix rows 1 to 10 under Guard Contract) with kill rows; raise MIN_ASSERTIONS and MIN_MUTANTS to measured counts
- 3.2 Add the section to plugins/soleur/skills/ship/references/ready-run-wait.md (no second ready-count/wait chain); R11 checks it
- 3.3 Run ci-head-verdict.test.sh, admin-merge-ready.test.sh, admin-merge-ready-wiring.test.sh, monitor-pr-checks.test.sh and shellcheck

## Phase 4: Ship-time

- 4.1 PR body: Changelog, the sentence that this gap moves out of the epic's LUKS scope, `Ref #9927`, link #11544; label semver:patch
- 4.2 Comment (not a body edit) on #9927 linking the PR
