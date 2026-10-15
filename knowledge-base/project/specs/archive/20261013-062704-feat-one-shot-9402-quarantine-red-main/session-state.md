# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-10-01-chore-quarantine-red-main-checks-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
- `gh issue view --json merged` → "Unknown JSON field" (transient; resolved by querying the PR side — #9339 confirmed MERGED)
- First `git push` returned `remote rejected (failed)`; retry succeeded — transient, no data lost
- Capability limitation: plan-review panel and deepen-plan parallel fan-out ran as inline sequential passes (`Reviewed-Coverage: sequential-fallback` recorded in-plan); no spawn tool in subagent context

### Decisions
- Live-derivation quarantine probe (`plugins/soleur/scripts/check-red-on-main.sh`), not a committed registry; `<!-- soleur:red-on-main -->` sentinel for reporting
- ship/SKILL.md has only 335 B headroom — Phase-7 disposition detail goes to `references/red-on-main-quarantine.md` with a ≤300-byte pointer outside `phase-7-poll-block` markers
- Ceiling flake fixed harness-side: `SOLEUR_TC_BUMP_FILE` file-read bump spliced into `_elapsed_s`; `bump.sh` fixture injects tick (1 s→60 s); production `test-all.sh` untouched
- `--incremental` mode on `regenerate-shard-manifest.py`: pins incumbent rows, assigns only new labels to least-loaded leg; ADR-240 amendment in same PR
- Required vs advisory preserved: red-on-main REQUIRED check → report + escalate; advisory → report + proceed

### Components Invoked
- soleur:plan, soleur:deepen-plan (sequential-fallback), scripts/cloud-detect.sh, scripts/lint-guard-contract.py, markdownlint-cli2, gh CLI (issue/PR/runs probes), spec-templates convention, web search
