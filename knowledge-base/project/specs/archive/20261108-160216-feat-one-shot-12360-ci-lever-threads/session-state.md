# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-11-08-fix-ci-lever-residual-threads-plan.md
- Status: complete

### Errors
None. (deepen-plan Phase 4.5 fired lexically on `unreachable`/`timeout` — false positive: verdict reachability/probe wall-budget wording, not network connectivity. Recorded in the plan's Enhancement Summary.)

### Decisions
- Thread 1: bounded-parallel `&`-worker pool (`wait -n -p` reap, `PBG_JOBS` default 8, clamp 1-16, bash>=5.1 serial fallback) across all four read phases; per-unit result FILES; parent owns `cut_ny`/`fail_api` verdicts. `SECONDS` epoch shared with workers — deadline contract unchanged.
- Pending re-scope: new `open` bucket — `state=="open"` exits the escape arm without pending or escaping; merged-PR pending semantics unchanged. Resumable state deferred (no durable substrate under sweeper `env -i`; revisit trigger recorded).
- Thread 2: separate `FOLDED_JOBS` frozenset (13 names: 11 ci.yml `member` tokens + `cla-check`/`cla-evidence`) consulted beside `ALWAYS_RUN_JOBS` — not added to it (parity row asserts exact union). Parity pins to member-token extraction + required-checks.txt CLA rows.
- 8 rows in decision-challenges.md: 1 operator-ruled (single combined PR), 7 `pending - assumed:` technical rows for the parent's batched CTO gate.
- Non-activation preserved: no .github/workflows/*, ci-pr-selection.sh, required-checks.txt, ruleset, or infra edits; third R3 ruling pass out of scope.

### Components Invoked
- soleur:plan (read + executed end-to-end), soleur:deepen-plan (read + executed)
- Inline sequential-fallback roles: repo-research-analyst, learnings-researcher, spec-flow-analyzer, cto (Assess+devex), eng review lenses — sequential-fallback noted in plan coverage
- cloud-detect.sh (not-local:no-devin-env), collision-precheck.sh, lint-guard-contract.py
- Commits: b9fd1901f5 (plan+tasks+decision-challenges), 99b3d6570c (deepened plan)

## Collision/Adjacency Watch
- Open PR #12377 (feat-one-shot-10862-norun-investigation) edits `scripts/ci-pr-affected-replay.py` at `gh_text`/`gh_pages`/`ci_runs`/`cmd_collect` (:271-:636) — disjoint from allowlist region (:199-233, ~:530-549). Re-probe `--files` after planning and rebase on merge order.
- Open PR #12376 (docs for #12015, replay pacing) — docs-only adjacency.
- Sibling worktree contention on the local affected gate is expected — distinguish contention banners from real failures.

## Operator Constraints

- constraint: single PR per thread is fine (threads are decoupled); #12360 is code+tests, #9729 is decision/documentation.
- constraint: Local affected-gate may contend with sibling worktrees - distinguish contention from failures.
- constraint: Resume state file /var/tmp/ci-lever-residuals-resume.md is stale post-merge, reference only.
- constraint: Preserve exit vocabulary (0/1/2/3/78) and the sweeper-refusal on SOLEUR_FT_EARLIEST set-ness.
- constraint: Do NOT activate affected-only PR gating.

## Technical Rulings
- cto_spawns=1 (batched, 7 rows): all assumed defaults confirmed with verified evidence. Rows rewritten to `Ruled by CTO agent, 2026-11-08` in decision-challenges.md.
