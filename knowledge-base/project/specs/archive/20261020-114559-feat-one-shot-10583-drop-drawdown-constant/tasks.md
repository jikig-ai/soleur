# Tasks: drop the DRAWDOWN constant and header from lint-ratchet

Plan: `knowledge-base/project/plans/2026-10-20-chore-drop-lint-ratchet-drawdown-constant-plan.md`. Issue: #10583.

All code edits land in ONE commit (the gate compares the baselines to the live working tree).

## Phase 1: Setup

- [x] 1.1 From the worktree, run `python3 plugins/soleur/scripts/lint-ratchet.py ruff --check` and `eslint-test-dirs --check`; both pass.
- [x] 1.2 Run `python3 -m unittest tests.scripts.test_lint_ratchet`; record the passing count N.
- [x] 1.3 Capture the exact pre-change user-form text with a one-off `python3 -c` calling `render_baseline("user-ruff", [], None, None)` on the unmodified engine.

## Phase 2: Tests first (RED)

- [x] 2.1 Delete `"drawdown": "#1"` from `make_config` in `tests/scripts/test_lint_ratchet.py`.
- [x] 2.2 Re-shape every `render_baseline` call: drop the `"#1"` positional on the `fixture` and `ruff` calls; drop both `None, None` positionals on the `user-ruff` calls (keep `header=` by keyword).
- [x] 2.3 Delete `test_the_drawdown_reference_is_one_constant`; remove the `DRAWDOWN` patch from the two user-scope tests (re-join the backslash-continued `with` at ~line 2156).
- [x] 2.4 Rewrite the three exact-text pins (`test_rendered_header_documents_the_recovery_path`, the ~2341 pin, the ~3411 pin) to the new Soleur header.
- [x] 2.5 Add `test_the_user_form_is_byte_identical` using the text captured in 1.3.
- [x] 2.6 Add `test_the_committed_soleur_baselines_equal_the_rendered_empty_form` over `("ruff", "eslint-test-dirs")`.
- [x] 2.7 Run the suite and confirm the new and re-pinned tests are RED against the unmodified engine.

## Phase 3: Engine (GREEN)

- [x] 3.1 Remove `drawdown,` from the module docstring key list (~line 42).
- [x] 3.2 Delete `DRAWDOWN = "#10433"` (~line 93).
- [x] 3.3 Change `render_baseline` to `(name, entries, *, recovery=None, header=None)`, switch on `name == "user-ruff"`, and write the new 4-line Soleur header (no tracker, no PR3a, no `# lint-ratchet baseline` or `# Shrink-only` wording, no rule code).
- [x] 3.4 Update the `update()` call site to pass `recovery=` and `header=` by keyword.
- [x] 3.5 Delete `"drawdown": None` from `build_user_config` and `drawdown=DRAWDOWN` from `build_config`.
- [x] 3.6 `grep -nEi drawdown plugins/soleur/scripts/lint-ratchet.py` prints nothing.

## Phase 4: Regenerate and verify

- [x] 4.1 Run `python3 plugins/soleur/scripts/lint-ratchet.py ruff --update` and `eslint-test-dirs --update`; each reports 0 entries; `git diff` on the baselines shows only the header change.
- [x] 4.2 Both `--check` commands exit 0.
- [x] 4.3 `python3 -m unittest tests.scripts.test_lint_ratchet` is green with N - 1 + 2 tests.

## Phase 5: Docs

- [x] 5.1 Edit the ADR-290 PR3b contract sentence (drop `drawdown,`), set `amended: 2026-10-20` and `related: [10433, 10583]`, append a three-line Amendment 3; leave Amendment 2 untouched.
- [x] 5.2 Confirm `plugins/soleur/skills/work/SKILL.md` is not in the diff.

## Phase 6: Ship

- [ ] 6.1 Run `technical-ruling-gate.sh --branch`.
- [ ] 6.2 Run `soleur:ship`; PR body carries `Closes #10583` and a separate `Ref #10331` line.
- [ ] 6.3 Run `soleur:postmerge`; if the PR is BEHIND with auto-merge armed, arm the watch and wait for the merge queue.
