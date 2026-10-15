# Tasks: Portable repository hook launchers

Plan: `knowledge-base/project/plans/2026-10-15-fix-portable-hook-launchers-plan.md`.

## Phase 1: Setup and Regression

- [ ] 1.1 Read the committed `interface-contract.md`; keep config and test implementers in their file scopes.
- [ ] 1.2 Extract and enumerate actual Codex/Devin command collections; positively assert command populations and coverage, and freeze original interpreter/target/argument expectations independently before config edits.
- [ ] 1.3 Add hermetic fixture regressions reproducing bare-root exit 127 before config edits; reuse `plugins/soleur/test/lib/git-fixture-env.ts`.

## Phase 2: Core Implementation

- [ ] 2.1 Repair `.codex/config.toml`'s two Git bootstrap commands using the plan's bounded fallback and assignment-success chaining.
- [ ] 2.2 Repair every existing deepest Git fallback in `.devin/config.json`, preserving project override precedence, interpreter, target, arguments, matcher and timeout.
- [ ] 2.3 Preserve selected-worktree ownership, single target dispatch, stdin, working directory, output streams and target exit status; failed root resolution launches no target.
- [ ] 2.4 Correct `.claude/hooks/README.md`'s bare-root explanation and state command-level compatibility coverage and Cursor limit accurately.

## Phase 3: Testing

- [ ] 3.1 Execute actual configured commands across ordinary/root/nested, linked-worktree/root/nested, Soleur-style bare and conventional-bare fixtures, including spaces.
- [ ] 3.2 Verify override precedence and empty values, invalid selected roots, missing active-worktree target despite common-root target, non-repository and failed non-bare discovery cases; include a positive bare probe followed by absolute-git-dir failure and assert no dispatch.
- [ ] 3.2.1 Use an interpreter spy with a positive control to prove resolution failures never attempt target execution; absent output alone is insufficient.
- [ ] 3.3 Verify exact arguments/input/output/error bytes, final exit 0/7/42 and exactly one target invocation; preserve interpreter differences including Python targets.
- [ ] 3.4 Add `bootstrap-discoverability` named smoke case exercising the real configured Codex SessionStart command in a synthetic bare root; emit `REPO_HOOK_BOOTSTRAP_OK` only after successful response assertions and keep the selected probe under 15 seconds.
- [ ] 3.5 Smoke actual rules-loader and guardrails entrypoints with safe fixture envelopes; preserve context/deny response behavior and avoid external effects.
- [ ] 3.6 Run the focused suite, affected Codex/Devin setup/plugin suites, `.claude/hooks/devin-matcher-parity.test.sh`, and registered hook consumers derived from changed-file searches.
- [ ] 3.7 Verify the guard-contract mutation rows can fail, run `python3 scripts/lint-guard-contract.py` against the plan, and apply lead-owned review/QA/preflight/shipping gates.
