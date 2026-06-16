---
feature: feat-one-shot-pause-wireframe-feedback
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-16-feat-pause-for-wireframe-operator-feedback-plan.md
status: ready
---

# Tasks: Pause for Operator Feedback on UX Wireframes

Derived from the plan. Orchestration/docs-only change — no runtime, infra, or data surface.
Pause lives in the **orchestrator** (brainstorm 3.55 / plan 2.5), never in the ux-design-lead
subagent (subagents cannot pause). Gate is **mode-conditional**: pause interactive, auto-proceed
headless.

## Phase 1 — RED (failing test)

- [ ] 1.1 Create `plugins/soleur/test/wireframe-feedback-pause.test.ts`, mirroring
  `plugins/soleur/test/mandatory-wireframes-hardening.test.ts` (bun:test, `readFileSync`,
  `REPO_ROOT = resolve(import.meta.dir, "../../..")`).
- [ ] 1.2 Assert brainstorm Phase 3.55 has the interactive AskUserQuestion review gate (approve /
  request-changes) — AC1.
- [ ] 1.3 Assert plan Phase 2.5 has the same gate after the step-4 invocation — AC2.
- [ ] 1.4 Assert both gates name a headless/pipeline no-pause branch — AC3.
- [ ] 1.5 Assert both request-changes arms re-invoke ux-design-lead and loop until approve — AC4.
- [ ] 1.6 Assert ux-design-lead body keeps `xdg-open` AND cross-references the orchestrator pause — AC5.
- [ ] 1.7 Run the suite; confirm the new tests FAIL on unmodified prose (real RED).

## Phase 2 — GREEN: brainstorm Phase 3.55b gate

- [ ] 2.1 In `plugins/soleur/skills/brainstorm/SKILL.md` after line 411, add **Phase 3.55b — Wireframe
  review pause**: interactive AskUserQuestion (Approve → Phase 3.6 / Request changes → re-invoke
  ux-design-lead with feedback + re-open + re-ask, loop until Approve).
- [ ] 2.2 Add the headless/pipeline arm (predicate identical to brainstorm `:101`): do NOT pause, echo
  `Phase 3.55b: pipeline mode — wireframes ready for async review at <dir>`, continue.
- [ ] 2.3 Add one-line `**Why:**` citing the Phase N.5 defense-in-depth + mid-plan-pause learnings.

## Phase 3 — GREEN: plan Phase 2.5 step 4b gate

- [ ] 3.1 In `plugins/soleur/skills/plan/SKILL.md` after step 4 (`:327`), add **step 4b — Wireframe
  review pause**: interactive approve / request-changes loop (approve → continue to step 5).
- [ ] 3.2 Add the headless/pipeline arm mirroring the ADVISORY auto-accept (`:340`): subagent / file-path
  / `--headless` context → do NOT pause, log, continue. Confirm it fires on the one-shot Task-subagent
  path (`:70`).
- [ ] 3.3 Add one-line `**Why:**` cross-reference (same two learnings).

## Phase 4 — GREEN: ux-design-lead cross-reference

- [ ] 4.1 In `plugins/soleur/agents/product/design/ux-design-lead.md` Step 3, keep item 5 (`xdg-open`)
  verbatim; append the one-sentence note that the interactive review pause lives in the orchestrator
  (brainstorm 3.55b / plan 2.5 step 4b), citing `2026-05-12-task-subagent-prompt-text-only.md`.

## Phase 5 — Verify

- [ ] 5.1 Run `cd plugins/soleur && bash scripts/test-all.sh` (the `package.json` `scripts.test` runner);
  confirm GREEN incl. the new file — AC7.
- [ ] 5.2 `python3 scripts/lint-agents-rule-budget.py` + `python3 scripts/lint-rule-ids.py` pass
  (defensive; no sidecar touched) — AC6.
- [ ] 5.3 Confirm no `description:` frontmatter changed; `bun test plugins/soleur/test/components.test.ts`
  green if any did — AC8.
- [ ] 5.4 Manual read: both gates co-locate their headless branch; no prose instructs a headless pause.

## Notes

- **No new AGENTS.md rule** — `B_ALWAYS` at 22994/23000 (6 bytes); behavior rides existing
  `wg-ui-feature-requires-pen-wireframe` as SKILL.md prose.
- Keep the headless predicate wording identical across brainstorm 3.55b and plan 2.5 step 4b
  (duplicated by necessity; note the coupling inline).
- Request-changes loop MUST have an exit (the Approve branch) — no dead end.
