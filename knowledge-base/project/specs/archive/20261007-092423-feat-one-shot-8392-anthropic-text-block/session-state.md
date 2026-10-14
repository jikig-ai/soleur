# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-19-fix-cron-anthropic-first-text-block-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
None. CWD verified first call; all deepen-plan halt gates passed or correctly skipped; lint-infra-no-human-steps.py and lint-guard-contract.py clean.

### Decisions
- Scope widened from 2 files to the whole class: four fixed-position content readers — `_cron-shared.ts:659` and `scripts/compound-promote.sh:231` live-broken on claude-sonnet-5; `domain-router.ts:181` and `scripts/learning-retrieval-bench.sh:360` latent on Haiku 4.5. AC2 is a tree-wide census (4 → 0).
- The workflow gap fixed in the same PR (`wg-when-a-workflow-gap-causes-a-mistake-fix`): `audit-models.sh` printed a request-side-only "thinking-API shape … (no-op)" that contradicted its own SKILL.md row; replacement census reuses the script's `$ROOT`-anchored, rc-discriminating scan.
- Phase order inverted: fixtures normalize first so each new case is a single red signal; the green fixture run is not credited as verification — the 8→0 fixture census is the instrument.
- Two unfalsifiable gates rewritten (AC10's "clusters > 0 OR a named status"; discoverability_test accepting rc 0 and rc 2).
- A vacuous thinking-only test case now carries a decoy `text` on the thinking block, pinning selection-by-type rather than by position.
- Three scope/taste challenges recorded, not silently applied (DC1 filter().join() declined; DC2 scope widening; DC3 DHH's cut-the-prod-arm P0 declined with the CTO counter-argument recorded).

### Components Invoked
soleur:plan, claude-api, soleur:plan-review, soleur:deepen-plan; agents repo-research-analyst, learnings-researcher, functional-discovery, dhh-rails-reviewer, kieran-rails-reviewer, code-simplicity-reviewer, engineering:cto, observability-coverage-reviewer, test-design-reviewer.
