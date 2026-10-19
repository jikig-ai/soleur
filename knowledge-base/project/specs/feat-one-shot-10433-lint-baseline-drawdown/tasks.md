# Tasks: feat-one-shot-10433-lint-baseline-drawdown

Plan: knowledge-base/project/plans/2026-10-19-chore-lint-baseline-drawdown-plan.md
Issue: Closes #10433, Ref #10331 (keep #10331 OPEN). Follow-up: #10583.

## Phase 0 - Pre-flight

- [ ] 0.1 Run `python3 plugins/soleur/scripts/lint-ratchet.py ruff --check` and `eslint-test-dirs --check` (expect 44 / 20 baselined)
- [ ] 0.2 `git fetch origin main`; a base that added a finding is fixed in this PR, never re-baselined

## Phase 1 - Group A (repo tooling, 25 findings) - commit 1

- [ ] 1.1 `.claude/hooks/security_reminder_hook.py` S110 x2 -> `contextlib.suppress` (no output, never blocks)
- [ ] 1.2 `scripts/backfill-frontmatter.py` F401 + F841 x2 (keep the `rename_dateless_file()` call)
- [ ] 1.3 `scripts/ci-pr-affected-replay.py` SIM115 x3 (`with`, re-indent, read with `git diff -w`)
- [ ] 1.4 S112 sites: `lint-agents-enforcement-tags.py` (suppress); `lint-anthropic-content-position.py` and `lint-trap-tempfile-ownership.py` (sentinel)
- [ ] 1.5 `scripts/lint-rule-ids.py` S110 x2; `scripts/lint-shell-capture-exit.py` SIM115 (add `Path` import); `scripts/lint-workflow-local-action-checkout.py` S110 + S112 x2 (L307 sentinel)
- [ ] 1.6 `scripts/regenerate-shard-manifest.py` SIM115 x4 (`with open` + `enumerate(fh, 1)`, never `splitlines`)
- [ ] 1.7 `tests/conftest.py` S110 x2 + S112; `tests/scripts/test_lint_rule_ids.py` F401
- [ ] 1.8 `py_compile` each file and run each file's covering suite from the plan's Covering Suites table (a missing import only shows in the suite)
- [ ] 1.9 `ruff --update`, stage the baseline with the code (lefthook requires baseline == live census), commit with a per-file equivalence note

## Phase 2 - Group B (fixtures and mutation harness, 16 findings) - commit 2

- [ ] 2.1 `doppler-download-error-channel.mutation.py` x2; `fake-playwright-mcp.py` x4; `make-proxy-mutant.py` x2; `session-facts.py` x3; `wiring_facts.py` x1 (add `Path` imports)
- [ ] 2.2 `proxy-session-driver.py` x4 (stderr handle via `ExitStack`, closed where `err.close()` is today)
- [ ] 2.3 Run the proxy suite and the wiring suite; run the mutation battery once, awaited with `Monitor`: expect `control: GREEN`, no `SURVIVED` (on any survivor take a before-run in a detached worktree and compare per-mutant counts)
- [ ] 2.4 `ruff --update`, stage the baseline, commit

## Phase 3 - Group C (shipped plugin scripts, 3 findings) - commit 3

- [ ] 3.1 `git grep -nE 'from quick_validate import \*|quick_validate\.os'` must print nothing before editing
- [ ] 3.2 `founder-check.py`: delete `word_start` (4 assignments) and `status`
- [ ] 3.3 `quick_validate.py`: delete `import os`
- [ ] 3.4 `bun test plugins/soleur/test/preflight-founder-check.test.ts`; `py_compile`; import smoke for `quick_validate` + `package_skill`
- [ ] 3.5 `ruff --update`, stage the baseline, commit

## Phase 4 - Group D (eslint test dirs, 20 findings) - commit 4

- [ ] 4.1 Delete dead helpers/consts/imports/locals per the plan table; loop `eslint-test-dirs --list` until empty
- [ ] 4.2 `harness-model-map.test.ts`: delete `checked` (no restored assertion; plan R7); `preflight-discoverability-test.test.ts`: delete `compared` and reword its comments
- [ ] 4.3 `redirect-tombstones.test.ts`: drop `date` from `DATED_POST` and its four call sites; `skill-security-scan.test.ts`: keep a bare `JSON.parse(r.stdout || "{}");`
- [ ] 4.4 Run every touched test file under its runner, plus `apps/web-platform/test/eslint-test-dirs-ratchet.test.ts`
- [ ] 4.5 `eslint-test-dirs --update`, stage the baseline, commit

## Phase 5 - Final baselines, docs, ship

- [ ] 5.1 Rebase onto fresh `origin/main`, then re-run both `--update` and both `--check` (expect 0 findings baselined); the Observability probe prints `entries 0`
- [ ] 5.2 ADR-290 Amendment 2 line referencing #10583
- [ ] 5.3 `bash scripts/test-all.sh --affected` for the final diff plus the Covering Suites table
- [ ] 5.4 `soleur:ship` (PR body: `Ref #10331`, `Closes #10433`, #10583 linked), then `soleur:postmerge`; BEHIND + auto-merge armed waits for the merge queue
