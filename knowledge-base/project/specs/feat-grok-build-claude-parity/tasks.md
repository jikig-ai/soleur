# Tasks: feat-grok-build-claude-parity

Lane: `cross-domain`. Closes #8064.

## Phase 1: Dual-voice + eval

- [ ] 1.1 Add Guard 1 test in `plugins/soleur/test/workflow-fidelity.test.ts` (locked skill list + Skill-tool-only fail)
- [ ] 1.2 Dual-voice `skills/review/SKILL.md` (Claude Skill tool kept; Grok `/compound` `/ship`; pipeline detection matches `/work`)
- [ ] 1.3 Dual-voice `skills/qa/SKILL.md`, `skills/compound/SKILL.md`
- [ ] 1.4 Dual-voice `skills/drain-labeled-backlog/SKILL.md`, `skills/drain-prs/SKILL.md` (Grok AwaitShell not Monitor)
- [ ] 1.5 Dual-voice `skills/work/SKILL.md` Phase 4 (`invokeSkill` / `/review` … `/ship`)
- [ ] 1.6 Enroll the new test (and optionally `harness.test.ts`) in `plugins/soleur/scripts/grok-fidelity-gate.sh`
- [ ] 1.7 Run `bash plugins/soleur/scripts/grok-fidelity-gate.sh` — must exit 0

## Phase 2: Plugin-root

- [ ] 2.1 `go.md` Step 0.0/0: `PLUGIN_ROOT="${GROK_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}}"`; keep plugin.json identity check
- [ ] 2.2 Same expansion in `commands/sync.md` probes
- [ ] 2.3 `hooks/hooks.json` — document/verify Grok interpolates `GROK_PLUGIN_ROOT` or keep Claude var plus fallback

## Phase 3: ADR-110

- [ ] 3.1 Create `plugins/soleur/lib/harness-model-map.ts` + `test/harness-model-map.test.ts`
- [ ] 3.2 Confirm Grok fixture model ids against live xAI docs (do not guess in the plan)
- [ ] 3.3 Update `workflow-model-pins.test.ts` allowlist to `cheap`/`standard`
- [ ] 3.4 Resolve tiers in `agent()` of:
  - `skills/deepen-plan/workflows/deepen-plan.workflow.js`
  - `skills/drain-labeled-backlog/workflows/drain-labeled-backlog.workflow.js`
  - `skills/plan-review/workflows/plan-review.workflow.js`
  - `skills/resolve-parallel/workflows/resolve-parallel.workflow.js`
  - `skills/resolve-pr-parallel/workflows/resolve-pr-parallel.workflow.js`
  - `skills/resolve-todo-parallel/workflows/resolve-todo-parallel.workflow.js`
  - `skills/review/workflows/review.workflow.js`
- [ ] 3.5 `plan` Step 4.5 and `ship` Phase 5.5 spawn `advisor` via resolver
- [ ] 3.6 ADR-110 Status → Accepted
- [ ] 3.7 C4: add `grokBuild` sibling of `platform.engine.claude`; include in views that list `platform.engine.claude`; run c4 syntax/render + `c4-count-parity.test.sh`

## Phase 4: Hook aliases

- [ ] 4.1 `.claude/settings.json`: alias `AskUserQuestion|ask_user_question`, `Task|spawn_subagent`; Bash alias only after verifying Grok PreToolUse name
- [ ] 4.2 Do not add fake Skill or Monitor matchers; document skip in grok-onboarding
- [ ] 4.3 Guard 2 test: Skill and Monitor matcher tokens still present

## Phase 5: Docs (after Phases 1–3 green)

- [ ] 5.1 Refresh `knowledge-base/engineering/grok-onboarding.md`
- [ ] 5.2 Two-column `/go` vs `/soleur:go` on existing `plugins/soleur/docs/pages/getting-started.njk`
- [ ] 5.3 Same table in `README.md` and `plugins/soleur/README.md`
- [ ] 5.4 Re-verify `grok --help` / `grok inspect` tokens if the binary is on PATH

## Phase 6: Legal lockstep

- [ ] 6.1 Canonical `docs/legal/{terms-and-conditions,privacy-policy,data-protection-disclosure,gdpr-policy,acceptable-use-policy}.md` harness-neutral plugin copy
- [ ] 6.2 Eleventy mirrors `plugins/soleur/docs/pages/legal/<same>.md` (hero + body dates)
- [ ] 6.3 Update `apps/web-platform/lib/legal/legal-doc-shas.ts`
- [ ] 6.4 No xAI customer sub-processor row (`git grep xAI docs/legal/` has no new processor table)

## Phase 7: Testing

- [ ] 7.1 Guard 1 mutations (including vacuous dispatch) encoded as tests
- [ ] 7.2 `bash plugins/soleur/scripts/grok-fidelity-gate.sh`
- [ ] 7.3 Claude golden-path case still green
