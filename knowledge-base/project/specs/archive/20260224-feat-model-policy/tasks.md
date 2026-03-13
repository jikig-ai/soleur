# Tasks: Model Selection Policy

**Branch:** feat-model-policy
**Plan:** `knowledge-base/plans/2026-02-24-docs-model-selection-policy-plan.md`

## Phase 1: Core Changes

- [x] 1.1 Change `learnings-researcher.md` line 4 from `model: haiku` to `model: inherit`
- [x] 1.2 Add Model Selection Policy section to `plugins/soleur/AGENTS.md` between lines 117-119
- [x] 1.3 Update Agent Compliance Checklist line 101 to reference new policy
- [x] 1.4 Add `CLAUDE_CODE_EFFORT_LEVEL=high` via `env` key in `.claude/settings.json` (note: `effortLevel` is not a valid settings.json field -- must use env var)

## Phase 2: Version Bump and Verification

- [x] 2.1 PATCH bump: plugin.json (3.0.10), CHANGELOG.md, root README.md badge (was stale at 3.0.7)
- [x] 2.2 Run post-edit verification grep checks (all 60 agents use inherit, effortLevel confirmed)
