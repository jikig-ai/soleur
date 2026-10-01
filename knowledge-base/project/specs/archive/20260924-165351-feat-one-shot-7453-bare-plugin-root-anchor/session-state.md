# Session State

## Plan Phase

- Plan file: knowledge-base/project/plans/2026-09-24-chore-migrate-skills-plugin-root-default-sites-to-bare-anchor-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors

- `gh issue create` refused twice by the filing gate: once for an unreadable scratchpad `--body-file` (rewritten via Write), once because User-Impact named no user surface (reworded). #8729 then filed.
- Foreground `sleep 60` blocked; used a background wait.
- One plan splice missed its anchor (assertion caught 0 matches); re-applied against the correct text.
- Observability layer mis-numbered (workflow-run log is layer 6, not 5); fixed.

### Decisions

- §R3 substitution prerequisite already resolved (ADR-179 A10 measured the bare-token-in-bash-fence arm; #8391 Arm 5 covers commands on Claude Code + Grok); reconfirmed in-session, not re-measured. Option-(d) sites were already migrated by #7482; the live severity-first item is Pattern C (two unconditional git-root code roots in preflight/SKILL.md).
- 97 agent-executable sites → quoted, payload-relative bare form; 4 prose mentions reworded; schedule/SKILL.md's workflow-template site drops the machine-local lock instead of taking the token; 5 Read-surface docs get loader-anchored pointers plus an absolute sentinel and a fail-closed admin-merge block (exit 5).
- safe-bash.ts keeps exact-string equality: four exact literals (bare + SOLEUR_PLUGIN_PATH_DEFAULT-substituted, each for list/ls); no ^bash regex, SHELL_METACHAR_DENYLIST untouched.
- Guards: Guard 1 zero-tolerance over payload markdown (readsRootUnsafely + new plantsRootUnsafely); Guard 2 dynamic-prefix and `..` escape; Guard 4 Read-surface docs; Guard 5 pins the carve-out; ratchet drops the `:-` form.
- Out of scope with trackers: #6222 (CWD-relative runner operands), #8729 (~128 CWD-relative `Read plugins/soleur/…`), #8730 (Grok nested-Read token unsubstituted). ADR-179 amended A18–A20; ADR-093 "Amended by" extended; no C4 change.

### Components Invoked

soleur:plan, soleur:plan-review, soleur:deepen-plan; repo-research-analyst, learnings-researcher, functional-discovery, cto (x2), cpo, dhh-rails-reviewer, kieran-rails-reviewer, code-simplicity-reviewer, architecture-strategist, spec-flow-analyzer, security-sentinel, test-design-reviewer, observability-coverage-reviewer, git-history-analyzer, scoped advisor, verify-the-negative pass.

### Carry-in for compound

PR #8686 post-merge: CodeQL caught 3 high alerts (regex built from data escaped only `-`/`:`; single-pass `<!--` strip) that a 12-agent review panel missed; fixed in 1b240b96df.
