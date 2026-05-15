---
name: plan-time-grep-all-agent-invocation-surfaces-not-just-named-entry-point
description: When a plan extends an agent body (review, simplicity, security, etc.), grep ALL invocation surfaces across plugins/**, .claude/hooks/, scripts/, and .github/workflows/ — not just the named entry-point skill (/soleur:review, /soleur:plan-review, etc.). Agents are typically invoked from 3-7 surfaces; brainstorm + first-draft plan reliably name only 1-2. The unnamed surfaces often pass non-diff inputs that require explicit fallback strings in the agent body to avoid hallucinated content.
type: best-practice
tags: [plan-skill, agent-extension, invocation-surface, fallback-strings, plan-review]
category: best-practices
module: plan
---

# Grep ALL Agent Invocation Surfaces at Plan Time

## Problem

In the #2727 brainstorm → plan flow, the brainstorm asserted "extending `code-simplicity-reviewer` inherits `/soleur:review` 8-agent code-class routing for free." The first-draft plan corrected the "8-agent" phrasing to "section 4 + CONCUR-gate" (two surfaces). Both were under-counts.

The 5-agent plan-review panel's architecture-strategist grepped `plugins/**`, `.claude/`, `scripts/`, and `.github/` for `code-simplicity-reviewer` and found **five invocation surfaces** total:

1. `plugins/soleur/skills/review/SKILL.md:380-382` — `/soleur:review` section 4 (every review)
2. `plugins/soleur/skills/review/SKILL.md:502-524` — CONCUR-gate for scope-out filings
3. `plugins/soleur/skills/plan-review/SKILL.md:8` — 3-agent plan-review panel (every plan-review)
4. `plugins/soleur/skills/work/SKILL.md:525,533` — final validation, optional
5. `plugins/soleur/skills/atdd-developer/SKILL.md:39` + `plugins/soleur/skills/compound/SKILL.md:136,504,558` — opportunistic spawns

Surfaces 3-5 pass non-diff inputs (a plan, a finding-without-diff, opportunistic context). The agent body edits initially had no fallback string for these contexts; without explicit instruction, the agent would render `### Hidden Assumptions` / `### Goal Verification` as hallucinated content or trigger AC1 shape-compliance as a false positive.

## Solution

At plan time, for ANY agent-body edit, run a multi-surface grep BEFORE writing FRs:

```bash
git grep -nE "@?agent-?<agent-name>|Task[^(]*<agent-name>\(|<agent-name> via Task" \
  -- 'plugins/**' '.claude/**' 'scripts/**' '.github/workflows/**'
```

Group the matches by surface (named entry-point skill, sibling skills, hooks, workflows). For each surface, classify the invocation context:

- **Diff-shaped:** the agent gets a PR diff or file diff to review. Output sections operate as designed.
- **Finding-shaped:** the agent gets a single finding + criteria (CONCUR-gate). No diff. New audit sections degenerate.
- **Plan-shaped:** the agent gets a plan markdown to review. No diff, no criteria. New audit sections degenerate.
- **Opportunistic:** the agent is spawned with ad-hoc context (compound, atdd). Variable.

For every non-diff-shaped surface, the agent body MUST encode an explicit fallback string (e.g., `_N/A — no diff in scope._`) in the new bullet/section instructions, with an AC verifying the fallback text exists.

## Why

- **Brainstorm under-counts by design.** Brainstorm prompts ask "what's the user-facing entry point?" — the answer names 1-2 surfaces. Sibling skills and opportunistic spawns are invisible to brainstorm research.
- **First-draft plans inherit the brainstorm's invocation map.** Without a deliberate "grep ALL surfaces" gate, the plan FRs implicitly assume diff-shaped input on every invocation, producing fragile behavior on non-diff surfaces.
- **Plan-review's architecture-strategist reliably catches this** — but only because the agent's prompt explicitly asks for invocation-surface coverage. Without a prompt anchor, the agent reviews the plan as written and misses the unmentioned surfaces.

## How to Apply

When `Files to Edit` names ANY agent body in `plugins/*/agents/**/*.md`:

1. Phase 1.1 of plan skill: add a "Grep agent invocation surfaces" subtask. Run the multi-surface grep above.
2. For each surface, classify the invocation context (diff / finding / plan / opportunistic).
3. For every non-diff context, FR2 (or equivalent) MUST include an explicit fallback string in the agent body's new instructions.
4. AC MUST grep the fallback string presence in the agent body.
5. When spawning plan-review's architecture-strategist on an agent-body PR, include "grep all invocation surfaces of <agent-name>" in the prompt as a load-bearing axis.

## Related

- Source plan: `knowledge-base/project/plans/2026-05-15-feat-karpathy-check-extend-simplicity-reviewer-plan.md`
- Source brainstorm: `knowledge-base/project/brainstorms/2026-05-15-karpathy-check-brainstorm.md`
- Companion learning: `knowledge-base/project/learnings/2026-05-15-brainstorm-audit-vs-guidance-direction-reframe.md` (covers the audit-direction vs. guidance-direction split that surfaced this case)
- Plan-review skill: `plugins/soleur/skills/plan-review/SKILL.md` (the panel that caught the gap)
- Issue: #2727 (parent #2718)

## When This Becomes Load-Bearing

- Any future plan extending an agent body in `plugins/*/agents/**/*.md` — invoke this gate at Phase 1.1.
- A future plan-review panel reports "off-context invocation rendering" findings — this is the underlying defect class.
- An agent body adds output sections that key on input shape (diff / criteria / plan) — the input-shape classification matrix above is the design checklist.
