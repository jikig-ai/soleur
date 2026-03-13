# Tasks: Self-Healing Workflow (v1 — Deviation Analyst)

## Phase 1: Add Deviation Analyst to Compound

- [x] 1.1 Read `plugins/soleur/skills/compound/SKILL.md` to understand current Phase structure
- [x] 1.2 Add Phase 1.5 "Deviation Analyst" section (sequential, after parallel fan-out, before Constitution Promotion)
  - [x] 1.2.1 Define responsibilities: read AGENTS.md Always/Never rules, read session-state.md for pre-compaction deviations, scan current context for post-compaction actions
  - [x] 1.2.2 Define output format: structured list with `rule_violated`, `evidence`, `proposed_enforcement` (hook/skill_instruction/prose_rule)
  - [x] 1.2.3 For hook proposals, include inline draft script following `.claude/hooks/` conventions (shebang, header comment, set -euo pipefail, stdin JSON, jq parsing, deny/allow)
  - [x] 1.2.4 Integrate output into Constitution Promotion flow (existing Accept/Skip/Edit gate)
  - [x] 1.2.5 Handle empty case: if no deviations found, skip deviation section in Constitution Promotion
  - [x] 1.2.6 Handle duplicate case: if deviation already has an existing hook, note it and skip proposal

## Phase 2: Testing and Validation

- [ ] 2.1 Run compound in a session with a known deviation and verify Deviation Analyst catches it
- [x] 2.2 Verify no regressions: run `bun test` if applicable (953 pass, 0 fail)
- [x] 2.3 Verify compound's existing subagents still work (parallel fan-out unchanged)
