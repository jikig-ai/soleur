---
date: 2026-04-15
category: best-practices
module: brainstorm, agent-native
tags: [brainstorm, agent-native, ux-review, governance, calibration, askuserquestion]
related_issues: [2341, 2342, 2343, 2344]
related_learnings:
  - 2026-02-17-ux-review-gap-visual-polish-vs-information-architecture.md
  - 2026-03-16-scheduled-skill-wrapping-pattern.md
  - 2026-04-13-codeql-alert-triage-and-issue-automation.md
---

# Learning: Brainstorm Calibration Pattern + Governance-Loop Prevention for Agent-Authored Issues

## Problem

Brainstorm on #2341 / #2342 produced two reusable patterns the existing learnings did not capture:

1. **Sequencing dilemma.** When building an autonomous reviewer that will file GitHub issues, how do we know its judgment is trustworthy before we rely on it? Ship the reviewer first → file issues we can't verify. Ship the first fix first → no loop yet.
2. **Governance loop.** An agent that files issues, runs through auto-triage that labels and re-prioritizes, and feeds into an auto-fix skill can end up authoring its own backlog of work. Nothing in the existing rules prevented that closed loop.

Also one minor tool-use error: `AskUserQuestion` was invoked with 6 options in a multiSelect, violating the ≤4 constraint.

## Solution

### Pattern 1: Calibration via known-good finding (sequence B→A, not A→B)

When building an auditor that will file issues for humans to triage:

1. Build the auditor first (the skill + workflow + dedup + cap).
2. Pick **one known-good finding** — an issue you already know the auditor should file — and set it as the calibration criterion.
3. Run the auditor once.
4. If the calibration finding lands in the top-N, the auditor is calibrated; ship the fix for that finding as "proof-of-loop artifact."
5. If it doesn't, remediate (prompt tweaks, rubric, screenshot scale) before trusting any other findings.

This inverts the instinct to ship the low-hanging fix first. The fix is cheap; what's expensive is trusting an agent's unseen judgment over many future runs. The first run against a known answer buys that trust in one shot.

Applied to #2341 / #2342: the three collapsible sidebars are the known-good finding. Ship `soleur:ux-audit` first. If run #1's top-5 surfaces "sidebars take too much space / no collapse control," ship the sidebar fix as marketing artifact #1.

### Pattern 2: Governance-loop prevention for agent-authored issues

Agent files issue → auto-triage labels it → auto-fix skill picks it up → agent ships its own idea. That loop looks productive but has no human in the prioritization chain.

Prevention rules (all applied to #2341):

| Guardrail | Mechanism |
|---|---|
| Agent-authored issues default to `Post-MVP / Later` | Human promotes to active milestone explicitly |
| Per-run cap (5 issues) | Forces the agent to prioritize; low-severity findings get cut |
| Global open cap (20) | Skill refuses to file when cap reached; forces human triage before more findings enter |
| Distinguishable label (`agent:ux-design-lead` + `ux-audit`) | Allows every downstream skill to filter by label |
| Exclude label from auto-fix and auto-triage workflows | `--exclude-label ux-audit` on filing-adjacent skills breaks the loop |
| Dedup by stable identifier hash in issue body | Prevents the same finding being re-filed each run |

The exclusion rule (row 5) is the load-bearing one. Without it the other four are just speed bumps.

### Pattern 3: AskUserQuestion option-count fix

`AskUserQuestion` caps options at 4 per question (single or multiSelect). When you have more than 4 guardrails, bundle related ones into one "full bundle" option. Only keep separate options if the user might reasonably pick a subset.

Bundling that worked for the governance question:

- "Cap 5/run + global cap 20 + default Post-MVP milestone" (3 guardrails bundled)
- "Labels: agent:X + ux-audit + domain/product" (3 labels bundled)
- "Exclude ux-audit from auto-fix/auto-triage" (standalone)
- "Public marketing-site link" (standalone)

## Key Insight

**Calibration is a property of the first run, not of the prompt.** You can spend unlimited time tuning an agent's prompt against imagined inputs. One run against a known answer tells you more than a day of prompt engineering.

**Governance is a property of the label graph, not of the prompt.** Prompting an agent not to "queue-jump its own work" is unenforceable. Excluding its label from downstream skills is enforceable.

## Session Errors

- **`AskUserQuestion` rejected 6-option multiSelect** — Recovery: consolidated to 4 bundled options. Prevention: add an internal checklist to the brainstorm dialogue phase: "before calling AskUserQuestion, confirm options ≤ 4." Not rule-worthy (tool-level limit, self-correcting on first failure); no skill edit proposed.

## Tags

category: best-practices
module: brainstorm, agent-native
