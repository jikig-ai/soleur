# Tasks - fix-sync-bare-files-comm-locale

Plan: `knowledge-base/project/plans/2026-10-12-fix-sync-bare-files-comm-locale-plan.md`

Never run `sync`, `sync-bare-files` or `cleanup-merged` against the bare root; fixtures under `$TEST_DIR` only.

## Phase 1 - Setup and RED tests

- 1.1 Calibrate the fixture: seeded search over real HEAD/history lists (read-only) for ~31 HEAD paths + ~9 deleted paths where the legacy `comm` pipeline under `en_US.UTF-8` emits `.claude-plugin/marketplace.json`; freeze the list as literals in the suite.
- 1.2 Add arms F0 (fixture-sensitivity guard), F1 (run once under en_US.UTF-8 and once under C, including the second-run idempotency check), F5 (ceiling), F8 (stub comm injected ordering bug), F7 (sibling census with synthetic offender/compliant self-check and empty-population floor) to `plugins/soleur/test/worktree-manager-bare-sync.test.sh`.
- 1.3 Run against the unmodified script; confirm F1 (en_US) RED with `not in sorted order` evidence and F1 (C) GREEN.

## Phase 2 - Core fix

- 2.1 Rewrite the prune block in `sync_bare_files()` (`worktree-manager.sh`): `LC_ALL=C` on sed/sort/comm, `git -c core.quotePath=false` on `git log` and `git ls-tree`, no separate quoted-line branch (the on-disk `-f`/`-L` check discards git-quoted spellings).
- 2.2 Per-path guard `git cat-file -e "HEAD:$rel"`; any hit logs `ERROR: tracked path in prune set: <rel>` to stderr and aborts the whole prune (exit 0).
- 2.3 Ceiling on the to-remove list, default 5000, override `SOLEUR_SYNC_PRUNE_MAX`; over it skip prune with a loud WARN (exit 0).
- 2.4 bash 3.2 safety: `${a[@]+"${a[@]}"}` idiom, no `mapfile`, no associative arrays.

## Phase 3 - Siblings

- 3.1 `scripts/plugin-delivery-canary.sh` lines 653-654: `LC_ALL=C comm`.
- 3.2 `apps/web-platform/infra/run-registered-suites.sh` line 1068: `LC_ALL=C comm -13 \`.
- 3.3 Run `bash scripts/plugin-delivery-canary.test.sh` and `bash apps/web-platform/infra/run-registered-suites.test.sh`.

## Phase 4 - Verification and docs

- 4.1 Set the `print_results` floor from a green run (en_US present); run the suite under `LC_ALL=en_US.UTF-8` and `LC_ALL=C`.
- 4.2 Mutation spot-checks from the plan's Guard Contract matrices (remove `LC_ALL=C`, delete the cat-file guard, drop the ceiling, revert quotePath on one call, strip `LC_ALL=C` from a sibling comm).
- 4.3 `bash scripts/lint-orphan-test-suites.sh`, `python3 scripts/lint-guard-contract.py`, markdownlint on changed docs.
- 4.4 One sentence in `plugins/soleur/skills/git-worktree/SKILL.md` if it documents the sync-bare-files prune.
- 4.5 Ship via the normal pipeline (no `--admin`); PR body carries `## Changelog`; post-merge verification steps are in the plan and run by the parent pipeline.
