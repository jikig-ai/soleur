# Tasks: feat-model-tier-optimization

Derived from `knowledge-base/project/plans/2026-06-10-feat-model-tier-optimization-plan.md` (v3, post-5-agent-review). Lane: cross-domain. Threshold: single-user incident.

## Phase 0: Empirical capture (gates FR5)

- [ ] 0.1 Run a throwaway 1-agent Workflow with `agent(prompt, { model: 'haiku', label: 'capture-probe' })`, raw PostToolUse stdin teed to a scratch file
- [ ] 0.2 Record answers: tool_input.model populated? label location? executed-model field in tool_response?
- [ ] 0.3 If NO model-shaped field exists anywhere → STOP, document plan deviation, rethink FR5
- [ ] 0.4 Paste redacted capture JSON in PR body (AC0); save as fixture input for 2.1

## Phase 1: Policy + ADR + enum sync

- [ ] 1.1 Amend `plugins/soleur/AGENTS.md` Model Selection Policy (~:144-151): three-tier vocabulary, absolute-pin semantics incl. pin-above-session, never-downgrade exemption list, allowlist-test enforcement note; update compliance-checklist line ~:125
- [ ] 1.2 `knowledge-base/project/constitution.md` ~:20 — add `fable` to frontmatter enum
- [ ] 1.3 `plugins/soleur/test/components.test.ts:13` — add `"fable"` to `VALID_MODELS`
- [ ] 1.4 Create `knowledge-base/engineering/architecture/decisions/ADR-051-per-call-model-tiering-for-workflow-subagent-spawns.md` (semantics, lifecycle/silent-retarget, telemetry limitation per Phase 0 outcome, failure semantics, rejected alternatives)
- [ ] 1.5 Verify: AC5 greps; `bun test plugins/soleur/test/components.test.ts` green (AC6)

## Phase 2: Telemetry (FR5)

- [ ] 2.1 RED: extend `.claude/hooks/agent-token-tee.test.sh` — AC0-derived fixture asserts model key; field-absent fixture asserts `"inherit"`
- [ ] 2.2 GREEN: `.claude/hooks/agent-token-tee.sh` — single `model` field (executed ?? requested ?? inherit per Phase 0 mapping), sanitized, added to jq read pass (~:70-79) + `line=` builder (~:136-144); `schema:1` unchanged
- [ ] 2.3 Consumer-tolerance check: `grep -n "schema\|total_tokens" plugins/soleur/skills/compound/scripts/token-efficiency-report.sh`
- [ ] 2.4 Verify: `bash .claude/hooks/agent-token-tee.test.sh` (AC1)

## Phase 3: Pins + allowlist test + skill guidance

- [ ] 3.1 12 inline pins (single-quoted) + one-line justification comment per site, re-located by `label:` string: review `classify`→sonnet, `file`→haiku; plan-review `detect`→sonnet; deepen-plan `parse`→sonnet; resolve-parallel `analyze`/`commit`→sonnet; resolve-todo-parallel `analyze`/`commit`→sonnet; resolve-pr-parallel `fetch`→haiku, `commit`→sonnet; drain `cluster`/`report`→sonnet
- [ ] 3.2 One handwritten disclosure `log()` line adjacent to each workflow's pins
- [ ] 3.3 Create `plugins/soleur/test/workflow-model-pins.test.ts`: (a) `model:` occurrences across `plugins/soleur/skills/*/workflows/*.workflow.js` == exact 12-entry label→model allowlist; (b) zero pins in `agent-native-audit.workflow.js`
- [ ] 3.4 `plugins/soleur/skills/deepen-plan/SKILL.md` — one-line FR2 advisory (verify-the-negative + self-audit passes spawn with `model: sonnet`)
- [ ] 3.5 Verify: AC2 greps; `bun test plugins/soleur/test/workflow-model-pins.test.ts` (AC4); AC9

## Phase 4: CI pin

- [ ] 4.1 `.github/workflows/claude-code-review.yml` — add `claude_args: '--model claude-sonnet-4-6'` to the claude-code-action step (do NOT bump action SHA)
- [ ] 4.2 Verify: `actionlint` exits 0 + grep (AC3); push, then AC10 head-SHA run-log check (record not-verifiable-in-logs if the action omits the model string)

## Phase 5: Acceptance (TR5, narrowed)

- [ ] 5.1 Run the branch's pinned review workflow once on this PR's diff
- [ ] 5.2 Assert: telemetry model attribution (pinned on classify/file, inherit on judgment spawns); classify matches known diff-class; file-step output well-formed
- [ ] 5.3 Paste summary in PR body (token counts primary; $ assumes session model) (AC7)

## Out of scope (tracked)

- Inngest registry + MODEL_PRICING parity → #5106
- BYOK ledger model column + legal lockstep → #5099
- model-launch-review skill / te-* drift rule → #5100
