# Session State

## Plan Phase
- Plan file: /data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-8006-ci-speedup-phase2/knowledge-base/project/plans/2026-09-23-feat-ci-test-shard-speedup-phase-2-plan.md
- Tasks file: knowledge-base/project/specs/feat-one-shot-8006-ci-speedup-phase2/tasks.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
None blocking. Subagent had no Skill/Task tool — `plan` and `deepen-plan` were executed procedurally from their SKILL.md files; Phase 5 sub-agent fan-out could not run (recorded in plan's Domain Review). `scripts/markdown-lint.sh` reported "nothing to lint" — knowledge-base/ is excluded by `.markdownlintignore` (#7927); lint AC restated accordingly.

### Decisions
- Matrix inside the existing `shard-totality-mutations` job name — zero aggregator/ruleset/required-checks changes (verified absent from all three).
- Battery floor counts DECLARED rows, not executed: `DECLARED == DECLARED_TOTAL` + `EXECUTED == IN_RANGE` replaces `MIN_ROWS`; M7–M9 insert before MUSTPASS (indices 21–23); heavy rows need new `hfrow()` binding `SOLEUR_SHARD_MANIFEST_HEAVY`; ci.yml ranges `1-11`/`12-21` then `1-12`/`13-24` in the M7–M9 commit.
- Parallel enumerate via per-pid `wait` + rc capture, file-per-child outputs, serial verdict emission; byte-exact anchors preserved by wrapping call sites.
- Heavy manifest = separate file `suite-shard-legs-heavy.tsv` + generator `--group heavy` + `SOLEUR_SHARD_MANIFEST_HEAVY`; ADR-240 amended in-PR. D buys insertion-stability, not wall-clock (3/3 already bijective).
- `ci-leg-durations-8006.sh` probe is a mandatory co-change (expects 5+3=8 → 6+3=9, plus fixtures).
- #8450 is CLOSED (Team-plan upgrade) — K=6's +1 leg well inside ceiling.

### Components Invoked
- `plan` skill (procedural), `deepen-plan` skill (procedural)
- `lint-guard-contract.py` (green, 4 entries), `scripts/markdown-lint.sh`, `gh issue/pr view` sweeps

### Collision Check (Step 0a.5)
- #8006 OPEN — linked:issue hit #7990 lacks #8006 in closingIssuesReferences → citation. Body-probe open: none. No live sibling.
- #8612, #8656, #8585 = MERGED PRs → contextual citations, continue.
- Open PR 8329 also edits `scripts/test-all.sh` + `scripts/test-all-affected.test.sh` — merge-conflict risk noted in plan.
