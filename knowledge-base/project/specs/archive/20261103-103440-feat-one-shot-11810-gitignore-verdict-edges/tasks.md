# Tasks — chore: declare .gitignore verdict-input edges for grep-q-pipe-guard.test.sh

Plan: `knowledge-base/project/plans/2026-11-03-chore-gitignore-verdict-edges-plan.md`
Issue: #11810 | Binding CTO ruling: issue comment 2026-11-03 (`issuecomment-6597435507`)

## Phase 1 — Edge declaration (`scripts/lib/test-affected-paths.sh`)

- [x] 1.1 Append the `.gitignore` block inside `AFFECTED_CLAUDE_HOOKS_GREP_Q_PIPE_GUARD_TEST_SH_PATHS`, immediately before its closing `)` (after the root-anchored `glob:*.<ext>` rows, ~line 2473): a comment block explaining the verdict-input rationale + the `glob:**.gitignore` prohibition + the new-top-dir residual, then `"​.gitignore"` and exactly one `"glob:<dir>/**.gitignore"` per tracked top-level dir (`.agents .claude .claude-plugin .codex .cursor-plugin .devin .github .grok LICENSES apps bin docs infra knowledge-base packages plugins scripts spike test tests todos`, in that order).
- [x] 1.2 Mint check: `bash scripts/test-all.sh --print-selection --paths=README.md` → the suite's `AFFECTED_SELECTED` edge column contains `^.gitignore` + all 21 `^glob:<dir>/**.gitignore` tokens, and no `^glob:**` verbatim (malformed) token.
- [x] 1.3 Selection check: `bash scripts/test-all.sh --print-selection --paths=.gitignore`, `--paths=apps/web-platform/.gitignore`, `--paths=infra/github/.gitignore` each print `AFFECTED_SELECTED	.claude/hooks/grep-q-pipe-guard.test.sh	1`.

## Phase 2 — Accept-row deletion (`scripts/ci-pr-affected-audit.accept.tsv`)

- [x] 2.1 Delete the 10 rows matching `suite==​.claude/hooks/grep-q-pipe-guard.test.sh` and `path==​.gitignore` via the pair predicate (`awk -F'\t' '!($1==".claude/hooks/grep-q-pipe-guard.test.sh" && $2==".gitignore")'`); assert the file goes 461 → 451 lines. Anchors to remove: `177450ed8313 1b8002147f10 41fcab8fb458 431de38b8410 69439580879b 75ee73f7f5c2 8a31a0e41298 a705f8fd72eb abb8b449c28d d4491363f3a4`.
- [x] 2.2 Verify the 5 `tests/scripts/lint-ratchet` `.gitignore` rows and all other rows untouched (`git diff` shows exactly 10 deletions, no other changes).

## Phase 3 — Verification battery

- [x] 3.1 `python3 -I scripts/ci-pr-affected-replay.py audit --all-refs --accept scripts/ci-pr-affected-audit.accept.tsv` → `stale=0`, `accepted=233`; all other counters identical to the measured baseline (`suites=724 always_on=116 audited=608 unaudited=0 gap_suites=252 gap_refs=1512 refs=4031 files_read=1203`); no `gap`/`ref`/`unaudited`/`stale` line names `.gitignore` or the suite. (Exit 1 expected — baselined gaps remain.)
- [x] 3.2 `python3 -I scripts/ci-pr-affected-replay.py ratchet` → exit 1, but **pre-existing main-side red** (`reason=new-pair live=1512 baseline=1510`): two undeclared pairs introduced by #11843 in `scripts/lint-betterstack-emitter-read.sh:148`→`image-cve-triage.sh` and `scripts/image-cve-triage.sh:66`→`betterstack-query.sh`, in files this diff does not touch. Tracked as #11963.
- [x] 3.3 `bash scripts/lint-orphan-test-suites.sh` → exit 0 (declared-member census enrollment).
- [x] 3.4 `bash scripts/test-all-affected.test.sh` → exit 0 (th6 census + probes).
- [x] 3.5 `bash scripts/test-affected-kb-consumers.test.sh`, `bash scripts/lib/inngest-probe-row.test.sh`, `bash plugins/soleur/test/ci-pr-affected-replay.test.sh` → all exit 0.
- [x] 3.6 `bash .claude/hooks/grep-q-pipe-guard.test.sh` → exit 0 (subject suite green).
- [x] 3.7 lint-ratchet flip-evidence re-check: `grep -n 'classify_user(REPO_ROOT\|check-ignore\|exclude-standard' tests/scripts/test_lint_ratchet.py` — confirm the only real-root arm is the `classify_user` SOLEUR-early-return assertion. If a real-root arm reaching `check-ignore`/`--exclude-standard` exists, STOP and apply the ruling's dissent clause (edge lint-ratchet identically + delete its 5 `.gitignore` accept rows).
- [x] 3.8 Confirm `AFFECTED_TESTS_SCRIPTS_LINT_RATCHET_PATHS` byte-identical to `origin/main` and no `glob:**.gitignore`/`glob:**/.gitignore` member anywhere in `scripts/lib/test-affected-paths.sh` (`grep -n 'glob:\*\*' scripts/lib/test-affected-paths.sh` returns nothing).

## Phase 4 — Ship hygiene

- [x] 4.1 `git diff origin/main --stat` covers only the two Files-to-Edit paths plus `knowledge-base/project/` planning artifacts.
- [x] 4.2 Before merge/queue arm: re-run `audit --all-refs` + `ratchet` on the merged tree (anchor-keyed accept rows are branch-relative; the 2026-10-26 learning).
