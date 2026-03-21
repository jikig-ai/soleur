# Product/UX Gate for Engineering Workflows

**Date:** 2026-03-19
**Issue:** #671
**Branch:** feat-product-ux-gate
**Status:** Brainstorm complete

## What We're Building

A tiered product/UX gate that detects user-facing work in engineering plans and conditionally triggers product and design review agents before implementation begins.

**The problem:** PR #637 built 5+ user-facing screens (signup, login, BYOK setup, dashboard, chat UI) without invoking any product or UX agents. The feature was framed as a "Cloud CLI Engine" (infrastructure), so the plan and work skills treated it as pure engineering. Constitution line 122 mandates UX review for user-facing pages, but no skill enforces it.

**The solution:** Add a semantic UI detection gate to the plan skill (Phase 2.5) that evaluates whether the plan creates new user-facing pages or flows, and conditionally runs the full product agent pipeline (spec-flow-analyzer → CPO → ux-design-lead) before proceeding to implementation.

## Why This Approach

1. **Plan phase is the cheapest intervention point.** Changes are free before code is written. The plan skill already runs spec-flow-analyzer (Phase 3) — we add detection logic before it to make SpecFlow UI-aware.

2. **Semantic assessment over keyword matching.** The repo has documented history of keyword matching being fragile (learning: domain-leader-pattern-and-llm-detection). LLM semantic assessment handles novel naming conventions and non-obvious UI work.

3. **Tiered strictness prevents over-triggering.** A solo founder cannot afford a gate that fires on every CSS tweak. Blocking for new user flows, advisory for modifications.

4. **Backstop in work skill catches plans that skip brainstorm.** Direct `/plan` or `/one-shot` invocations bypass brainstorm domain routing. The work pre-flight backstop ensures no UI-heavy plan reaches implementation without at least a warning.

## Key Decisions

- **Gate strictness:** Tiered — blocking for new user flows (3+ new UI files or new multi-step flows), advisory for modifications to existing UI
- **Detection mechanism:** Semantic LLM assessment after plan generation ("Does this plan create new user-facing pages or flows?"), not keyword/file-pattern matching
- **Agent pipeline when blocking:** spec-flow-analyzer (UI-flow-aware prompt) → CPO (advisory product cross-check) → ux-design-lead (if Pencil MCP available, else skip with notice)
- **Primary gate location:** Plan skill Phase 2.5 (between issue planning and SpecFlow)
- **Backstop location:** Work skill Phase 0.5 pre-flight (scan plan for `## UX Review` section; warn if absent and plan mentions UI)
- **Brainstorm enhancement:** Broaden Product domain assessment question to also trigger on UI creation signals, not just business validation
- **One-shot handling:** Gate fires inside the plan subagent during one-shot — no separate one-shot checkpoint needed. Session summary carries UX review decisions forward.

## Open Questions

- What marker should the plan skill write to signal "UX review completed"? A `## UX Review` section in the plan file seems simplest for both human readability and work backstop detection.
- Should the advisory tier present AskUserQuestion or just print a notice? AskUserQuestion adds friction but ensures acknowledgment.
- How should the gate handle plans generated outside the skill system (manually written plans)? The work backstop catches these since it scans the plan file regardless of origin.

## Scope

### In Scope

- Plan skill Phase 2.5: semantic UI detection + agent pipeline
- Work skill Phase 0.5: backstop pre-flight check
- Brainstorm domain config: broaden Product assessment question
- Constitution enforcement: the rule exists (line 122), implementation closes the gap

### Out of Scope

- New ux-reviewer agent for auditing existing sites (learning #1 recommends this, but it's a separate feature)
- PreToolUse hook enforcement (semantic detection cannot be done in hooks — they are syntactic)
- Changes to agent definitions (spec-flow-analyzer, CPO, ux-design-lead are all capable; the gap is in orchestration, not agent capability)

## Files to Modify

| File | Change | Priority |
|------|--------|----------|
| `plugins/soleur/skills/plan/SKILL.md` | Add Phase 2.5 UI detection gate with semantic assessment + agent pipeline | P0 |
| `plugins/soleur/skills/work/SKILL.md` | Add UX review backstop to Phase 0.5 pre-flight | P0 |
| `plugins/soleur/skills/brainstorm/references/brainstorm-domain-config.md` | Broaden Product domain assessment question to include UI creation signals | P1 |
| `knowledge-base/project/constitution.md` | Mark line 122 as enforced (remove "aspirational" status) | P1 |

## Research Sources

- CPO assessment: tiered gate design, agent invocation order, over-triggering prevention
- 14 institutional learnings, notably: UX review gap (#1), landing page regression (#2), business validation workshop pattern (#3), passive domain routing (#5), domain leader LLM detection (#6)
- Repo research: plan skill Phase 3 SpecFlow, work skill pre-flight, brainstorm domain config, one-shot pipeline, constitution line 122
