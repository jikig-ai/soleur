# Tasks: brand-hex-commit-gate target repository (#10793)

Plan: knowledge-base/project/plans/2026-10-26-fix-brand-hex-commit-gate-target-repo-plan.md
Rule for every phase: commit AND push before starting the next one. Commit messages via `-F`, ending with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.

## Phase 0 - Baseline
- [ ] 0.1 Verify cwd is the worktree; run `bash .claude/hooks/brand-hex-commit-gate.test.sh` (expect 24 passed, 0 failed)

## Phase 1 - Tests first (RED)
- [ ] 1.1 Add helpers: bare-root-with-worktree fixture (physical paths), `_run_cmd` (OUT/ERR/RC, optional PATH stub), `_expect`
- [ ] 1.2 T25/T25b cd form deny + allow twin from a bare-root cwd
- [ ] 1.3 T26/T26b/T26c -C form deny + twin + other-repo-from-clean-tree
- [ ] 1.4 T27/T28 bare-root no-cd allow; no-cd regression; quoted-prose allow; commit-tree allow
- [ ] 1.5 T29 diff base: -C with -a (unstaged deny), without -a (allow), cd + -a, flag-like text in -m
- [ ] 1.6 T30 two roots (prefix by basename, union incl. cwd root) with allow twin
- [ ] 1.7 T31 per-root palette isolation
- [ ] 1.8 T32 relative / quoted / nonexistent targets
- [ ] 1.9 T33 undeterminable: variable, tilde, glob, GIT_DIR, --git-dir -> warn + allow + bypass incident row, exit 0
- [ ] 1.10 T34 no-perl PATH stub; T35 lib-missing copy of the hook
- [ ] 1.11 T36 header content anchors; T37 fixture control
- [ ] 1.12 Run suite: new deny rows RED, twins and regressions green; commit and push

## Phase 2 - Hook implementation (GREEN)
- [ ] 2.1 Loose trigger after the unchanged strict test (keep line 119 stable)
- [ ] 2.2 Fail-soft lib load + explicit declare -f / CTR_STAGE_API assertions (no sim lib)
- [ ] 2.3 ctr_collect / ctr_resolve_roots flow; commit-seen handling; undeterminable -> warn + bypass row + allow
- [ ] 2.4 Root set = CTR_ROOTS + process-cwd toplevel, deduped (a failing cwd lookup at a bare root, rc 128, means no cwd root - never undeterminable); unset ambient GIT_* on the lexed path
- [ ] 2.5 NAME_REF: textual regex when `git commit` present, else CTR_COMMIT_ALL
- [ ] 2.6 scan_root function with per-root palette reset; multi-root basename prefix; explicit `return 0`
- [ ] 2.7 Suite green, shellcheck clean; commit and push

## Phase 3 - Comments and ledgers
- [ ] 3.1 Rewrite header and in-body trigger comment (drop "identical" claims and the KNOWN LIMITATION line)
- [ ] 3.2 Add lib + lexer paths to the ONE existing AFFECTED_CLAUDE_HOOKS_BRAND_HEX_COMMIT_GATE_TEST_SH_PATHS array
- [ ] 3.3 README.md paragraph; guardrail-audit.md consumer text
- [ ] 3.4 Commit and push

## Phase 4 - Repo-global checks (before every push)
- [ ] 4.1 `bash scripts/check-adr-ordinals.sh`
- [ ] 4.2 `bash plugins/soleur/test/boundary-prefix.test.sh` (re-key line-number exemption if hook lines moved)
- [ ] 4.3 `python3 -I scripts/ci-pr-affected-replay.py ratchet` (accept rows only for pairs that merely name a file)
- [ ] 4.4 `bash plugins/soleur/skills/verification-scaffold/test/manifest.test.sh`
- [ ] 4.5 `bash .claude/hooks/grep-q-pipe-guard.test.sh`
- [ ] 4.6 secret-scan suite and hook-input-contract suite stay green; AC9 untouched-files diff check

## Phase 5 - Ship
- [ ] 5.1 PR body via --body-file: `Closes #10793`, `Ref #10331`, `Ref #10609`; file the sim-adoption follow-up issue if absent
- [ ] 5.2 If the merge queue shows UNMERGEABLE behind another PR, wait, then merge origin/main and resolve
