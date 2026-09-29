# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-29-fix-backstop-hook-version-resolution-plan.md
- Status: complete

### Errors
- Subagent had no Task/Skill spawn tools; plan/deepen fan-outs substituted with inline verification passes (recorded in plan Research Insights + Enhancement Summary). All mechanical deepen halt gates (4.6–4.11, 4.4) executed for real and pass.
- One self-caught defect corrected in-plan: `_repo_root()` already prefers `CLAUDE_PROJECT_DIR`; AC5 pins existing behavior.

### Decisions
- Resolver shim `memory-backstop-resolve.sh` selects max `BACKSTOP_REVISION` among checkout copy, `${XDG_DATA_HOME}/soleur/hooks/`, and both plugin-cache globs; strictly-newer winners publish atomically to the managed path (flock-serialized, in-lock re-check) before exec — one fresh session upgrades the host.
- Upgrade-lag gap folded in via `repair_stale_scopes()`: `SetUnitProperties` runtime-only convergence of stale `soleur-agent-*.scope` caps at any SessionStart; systemd-timer and advisory alternatives cut as subsumed.
- Plugin vendoring: byte-equal `plugins/soleur/hooks/memory-backstop.sh` (not in hooks.json) + parity test, making `claude plugin update` an independent delivery channel.
- Guards: revision-bump check vs merge-base in `pr-quality-guards.yml`, vendored byte-parity, settings-wiring assertion; ADR-261; `model.c4` hooks-container update. Ledger schema 1→2 adds `backstop_revision`/`resolved_from`/`repaired`.

### Components Invoked
- soleur:plan (inline), soleur:deepen-plan (inline), lint-guard-contract.py, markdownlint-cli2, gh, git
- Commits: a9d358b93c (plan + tasks), 28b188c091 (deepen corrections), pushed.
