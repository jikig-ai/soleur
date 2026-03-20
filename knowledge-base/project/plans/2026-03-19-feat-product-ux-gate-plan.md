---
title: "feat: add product/UX gate to engineering workflows"
type: feat
date: 2026-03-19
semver: minor
rollback: revert the merge commit on main
---

# feat: add product/UX gate to engineering workflows

## Overview

Add a tiered product/UX gate to the plan skill (Phase 2.5) that semantically detects user-facing work and conditionally triggers product agent review before implementation. Add a backstop check to the work skill (Phase 0.5) and broaden brainstorm domain routing to catch UI creation signals.

Closes #671.

## Problem Statement / Motivation

PR #637 shipped 5+ user-facing screens (signup, login, BYOK setup, dashboard, chat UI) without any product or UX agent involvement. The feature was framed as a "Cloud CLI Engine" (infrastructure), so plan/work skills treated it as pure engineering. Constitution line 122 mandates UX review for user-facing pages, but no skill enforces it — violating the constitution's own principle (line 147) that conventions must have tooling enforcement.

## Proposed Solution

### Phase 2.5: UI Detection Gate (plan SKILL.md)

Insert between Phase 2 (Issue Planning, ends line 192) and Phase 3 (SpecFlow Analysis, line 194).

**Semantic assessment:** After generating the plan structure, evaluate the plan content:

> "Based on the plan structure generated above, classify this plan into one of three tiers:
> - **BLOCKING**: Creates new user-facing pages, multi-step user flows, or significant new UI components (e.g., signup flows, dashboards, onboarding wizards, chat interfaces)
> - **ADVISORY**: Modifies existing user-facing pages or components (e.g., layout changes, form updates, adding fields to existing screens)
> - **NONE**: Infrastructure, backend, tooling, or orchestration changes with no user-facing impact
>
> A plan that *discusses* UI concepts but *implements* orchestration changes (e.g., adding a UX gate to a skill) is NONE."

**On BLOCKING:**

1. Run spec-flow-analyzer via Task with UI-flow-aware prompt: "Analyze the user flows in this plan. Map each screen, identify entry/exit points, dead ends, missing error states, and flows that drop the user. Focus on user journey completeness, not technical implementation."
2. Run CPO via Task with scoped prompt: "Assess the product implications of this plan: {plan summary}. Cross-reference against brand-guide.md and constitution.md. Identify product strategy concerns, flow gaps, and positioning issues. Output a structured advisory — do not use AskUserQuestion."
3. Invoke ux-design-lead via Task with scoped prompt: "Create wireframes for these user flows: {flow list}. Platform: desktop. Fidelity: wireframe." The agent has its own Pencil MCP prerequisite check — if Pencil is unavailable, the agent will stop with an installation message. If the Task returns without wireframes (agent self-stopped), write `Pencil available: no` in the UX Review section and display: "ux-design-lead skipped (Pencil MCP not available). Consider running wireframes manually before implementation."
4. Write `## UX Review` section to the plan file (see contract below).
5. **Skip Phase 3** (SpecFlow already ran in step 1 with UI-aware prompt — avoids duplicate invocation).

**On ADVISORY:**

1. If in pipeline/subagent context (plan file path was provided as argument, not interactive): auto-accept, write `## UX Review` section with `tier: advisory, decision: auto-accepted (pipeline)`, proceed silently.
2. If interactive: display notice via AskUserQuestion: "This plan modifies existing UI. Run UX review?" Options: "Yes, run full review" / "Skip — I'll handle UX manually". Record choice.
3. Write `## UX Review` section with decision.

**On NONE:**

1. Write `## UX Review` section with `tier: none`. Proceed silently.

### `## UX Review` Heading Contract

```markdown
## UX Review

**Tier:** blocking | advisory | none
**Decision:** reviewed | skipped | auto-accepted (pipeline) | N/A
**Agents invoked:** spec-flow-analyzer, cpo, ux-design-lead | spec-flow-analyzer, cpo | none
**Pencil available:** yes | no | N/A

### Findings

[Agent findings summary, or "No UI detected — infrastructure/tooling change."]
```

Place after Acceptance Criteria, before Implementation Tasks (or before Test Scenarios if using MORE template). If the plan lacks an Acceptance Criteria heading, place before the last major section or at the end of the plan.

**Decision field values:** BLOCKING → `reviewed` (or `reviewed (partial)` if an agent failed), ADVISORY → `skipped` or `auto-accepted (pipeline)`, NONE → `N/A`.

### Work Backstop (work SKILL.md Phase 0.5)

Add as check 7 in Scope checks (after line 72, before the On FAIL block at line 74):

```
7. If a plan file was provided (check 5 passed), scan for `## UX Review` heading.
   If ABSENT: scan the plan content for UI file patterns (page.tsx, layout.tsx,
   .jsx, .vue, .svelte, .astro, +page.svelte, template.tsx, app/, pages/,
   components/, layouts/, routes/). If UI patterns
   found, WARN: "Plan references UI files but has no UX Review section. Consider
   running /soleur:plan to add product/UX review before implementing."
   If `## UX Review` heading IS present: pass silently.
```

This is keyword-based (not semantic) — appropriate for a lightweight pre-flight check. Advisory-only, never blocks.

### Brainstorm Domain Config Enhancement

Broaden the Product domain Assessment Question from:

> "Does this feature involve validating a new business idea, assessing product-market fit, evaluating customer demand, competitive positioning, or determining whether to build something?"

To:

> "Does this feature involve validating a new business idea, assessing product-market fit, evaluating customer demand, competitive positioning, determining whether to build something, or creating new user-facing pages, multi-step user flows, or significant UI components?"

This mirrors the Phase 2.5 BLOCKING tier language. Minor UI modifications ("fix button color") should NOT trigger the Product domain — only new pages/flows.

Also update the Product domain **Task Prompt** to include UI/UX analysis alongside product strategy:

> "Assess the product implications of this feature: {desc}. Identify product strategy concerns, validation gaps, **user flow and UX considerations**, and questions the user should consider during brainstorming. Output a brief structured assessment (not a full strategy)."

### Constitution Annotation

Update line 122 to add enforcement annotation:

```
- [skill-enforced: plan Phase 2.5, work Phase 0.5] When a plan includes user-facing pages or components...
```

This follows the existing `[hook-enforced: ...]` pattern but indicates skill-level enforcement.

## Technical Considerations

- **No new files.** All changes are edits to existing SKILL.md files and brainstorm-domain-config.md (TR5).
- **Pipeline mode.** The advisory tier must auto-accept in subagent/pipeline context to avoid deadlocking one-shot. Detection: plan file path provided as argument (same heuristic work skill uses).
- **Agent scoping.** CPO and ux-design-lead are invoked via Task with scoped prompts that suppress AskUserQuestion. This prevents interactive deadlocks and reduces user fatigue.
- **SpecFlow deduplication.** Phase 3 is skipped when Phase 2.5 already ran spec-flow-analyzer. Add conditional: "If spec-flow-analyzer was invoked in Phase 2.5, skip this phase."
- **Partial failure.** If any agent in the Phase 2.5 pipeline fails (timeout, error), write partial findings to `## UX Review` and proceed. Do not block the plan on agent failure.
- **Context budget.** Three sequential agents in Phase 2.5 add token load. In one-shot subagent context, this compounds with existing research agents. Acceptable trade-off for blocking-tier plans (high-value gate).

## Acceptance Criteria

- [ ] Plan for "add signup and onboarding flow" triggers BLOCKING tier, runs SpecFlow + CPO + ux-design-lead (if Pencil available)
- [ ] Plan for "fix button color on dashboard" triggers ADVISORY tier with notice
- [ ] Plan for "add Redis caching layer" triggers NONE tier, proceeds silently
- [ ] Plan for "add UX gate to plan skill" triggers NONE tier (self-referential — discusses UI but implements orchestration)
- [ ] BLOCKING tier writes `## UX Review` section with all agent findings
- [ ] ADVISORY tier in pipeline context auto-accepts without AskUserQuestion
- [ ] Phase 3 SpecFlow is skipped when Phase 2.5 already ran it
- [ ] Work skill warns when plan has UI file patterns but no `## UX Review` section
- [ ] Work skill passes silently when `## UX Review` section is present (any tier)
- [ ] Brainstorm for "build a new dashboard page" triggers Product domain leader
- [ ] Brainstorm for "fix button color" does NOT trigger Product domain leader
- [ ] One-shot pipeline completes with UX gate firing inside plan subagent
- [ ] If CPO agent fails during BLOCKING tier, partial findings are written and plan proceeds
- [ ] Constitution line 122 has `[skill-enforced: ...]` annotation

## Test Scenarios

- Given a feature description "add user signup and onboarding flow", when /soleur:plan runs, then Phase 2.5 classifies as BLOCKING and runs spec-flow-analyzer with UI-flow-aware prompt, then CPO with scoped advisory prompt, then offers ux-design-lead
- Given a feature description "improve dashboard card layout", when /soleur:plan runs, then Phase 2.5 classifies as ADVISORY and presents skip option
- Given a feature description "add Redis caching to API endpoints", when /soleur:plan runs, then Phase 2.5 classifies as NONE and writes minimal UX Review section
- Given a plan file with UI file references but no `## UX Review` section, when /soleur:work runs, then Phase 0.5 check 7 warns about missing UX review
- Given a plan file with `## UX Review` section (any tier), when /soleur:work runs, then Phase 0.5 check 7 passes silently
- Given /soleur:one-shot "add login page", when plan subagent reaches Phase 2.5 advisory tier, then advisory auto-accepts without prompting (pipeline mode)
- Given a brainstorm about "build a new customer dashboard", when Phase 0.5 domain routing runs, then Product domain leader is spawned

## Dependencies & Risks

**Dependencies:**
- Pencil MCP for ux-design-lead wireframes (gracefully degrades when unavailable)
- spec-flow-analyzer, CPO agents exist and are capable (confirmed by repo research)

**Risks:**
- Semantic assessment accuracy: LLM classification may misclassify edge cases. Mitigated by the work backstop as safety net.
- Over-triggering in brainstorm: broadened Product assessment question may fire on UI modification features. Mitigated by scoping the broadening to "new" pages/flows only.
- Context budget in one-shot: three additional agents in plan subagent increases token usage. Acceptable for BLOCKING tier (infrequent, high-value).

## Files to Modify

| # | File | Change |
|---|------|--------|
| 1 | `plugins/soleur/skills/plan/SKILL.md:192` | Insert Phase 2.5 UI detection gate between Phase 2 and Phase 3 |
| 2 | `plugins/soleur/skills/plan/SKILL.md:194` | Add conditional skip to Phase 3 when Phase 2.5 ran SpecFlow |
| 3 | `plugins/soleur/skills/work/SKILL.md:72` | Add check 7 (UX review backstop) to Phase 0.5 scope checks |
| 4 | `plugins/soleur/skills/brainstorm/references/brainstorm-domain-config.md:10` | Broaden Product domain Assessment Question |
| 5 | `knowledge-base/project/constitution.md:122` | Add `[skill-enforced: ...]` annotation |

## References & Research

- Brainstorm: `knowledge-base/project/brainstorms/2026-03-19-product-ux-gate-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-product-ux-gate/spec.md`
- Issue: #671
- Related PR: #637 (the incident that exposed this gap)
- Institutional learnings: UX review gap (2026-02-17), landing page regression (2026-02-22), business validation workshop pattern (2026-02-22), passive domain routing (2026-03-12), domain leader LLM detection (2026-02-21)
- SpecFlow analysis: 12 gaps identified, 3 critical (pipeline mode, duplicate SpecFlow, no-UI section contract) — all resolved in this plan
