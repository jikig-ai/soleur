---
title: When plan-review pushes back on a brainstorm-locked architectural choice, dissent + document, do not silently fold
date: 2026-05-19
category: workflow-patterns
tags: [plan, plan-review, brainstorm, operator-decision, dissent-rationale, rf-when-a-reviewer-or-user-says-to-keep-a]
related_prs: ["#4066"]
related_issues: ["#3244"]
source_session: plan — PR-H Daily Priorities multi-source (#3244)
---

# When plan-review pushes back on a brainstorm-locked architectural choice, dissent + document, do not silently fold

## Problem

PR-H brainstorm (2026-05-19) walked the operator through Approach A (single PR-H bundling GitHub source + KB-drift source) vs Approach B (split: PR-H GitHub-only + PR-H2 KB-drift follow-up). The operator picked Approach A after the brainstorm laid out the trade-offs explicitly — "KB-drift slice is genuinely small (nightly cron + 2 walkers + UI affordance); bundling avoids two rounds of regression-test setup."

Plan-review (DHH) returned a P0 finding to **reverse** that choice:

> "Approach A is two PRs in a trenchcoat. Phase 5 (KB-drift) shares zero runtime code with Phases 0-4+6-7 (GitHub). [...] You bundled them because the umbrella AC says '≥3 sources' and you wanted one PR to close it. That is ceremony, not engineering. Ship GitHub first; KB-drift is an internal bash script writing to your own DB; it can land in a 200-line follow-up next week with zero legal review."

The DHH critique is internally coherent and the analysis is correct on its own terms. But it's asking to reverse a decision the operator already made with full information about exactly these trade-offs.

## Root cause

Plan-review's three agents (DHH, Kieran, code-simplicity) read the plan in isolation. They don't have access to:
- The brainstorm's AskUserQuestion sequence where the operator weighed Approach A vs B vs C explicitly.
- The operator's selection event and the rationale captured in the brainstorm Phase 2 dialogue.
- The brainstorm's `## Why this approach` section that documents WHY the rejected alternatives were rejected.

So plan-review is structurally limited to critiquing the chosen approach as-presented. They cannot, in this turn, see that the alternative they're suggesting was actively considered and rejected. From their vantage point, a sound critique is to suggest the alternative.

The natural failure mode at this junction is to **silently fold the plan-review finding** — fewer files, smaller PR, "the experts said so." But that hands a strong reviewer veto over the operator's brainstorm-time judgment. That is the workflow inversion the existing rule `rf-when-a-reviewer-or-user-says-to-keep-a` is written to prevent.

## Solution / Prevention

When a plan-review finding asks to reverse an architectural choice the operator already made in brainstorm:

1. **Locate the brainstorm decision artifact.** Read the brainstorm `## Why this approach` + the AskUserQuestion answer history. Confirm the alternative was actively considered AND the operator's choice was made with the trade-offs surfaced.

2. **If the choice WAS informed:** DISSENT the plan-review finding explicitly. Surface the dissent to the operator via AskUserQuestion with the dissent rationale visible. Do not let the AskUserQuestion default option silently apply the plan-review's suggestion. The recommended option should be "apply review changes, keep dissent" — never "apply all reviews verbatim."

3. **If the choice WAS NOT informed** (brainstorm skipped the question, or the operator picked under different assumptions than the plan-review surfaces): the plan-review finding is *new information*. Re-route to the operator with both the brainstorm context AND the plan-review evidence. The decision belongs to the operator at that point.

4. **Document the dissent in the plan frontmatter.** Add a `plan_review_dissent:` field naming what was rejected and why. This creates a record that the dissent was deliberate, not an oversight — so a future planner reading the plan understands why the apparently-obvious simplification was not taken.

5. **Record the rule reference.** `rf-when-a-reviewer-or-user-says-to-keep-a` covers reviewer pushback at code-review time. The plan-time application is symmetric: an informed brainstorm choice is the operator's "keep it" statement before review even runs.

## Concrete example (this session)

DHH P0: split KB-drift into PR-H + PR-H2.
Brainstorm context: operator explicitly chose Approach A (bundle) after seeing Approach B (split) with the trade-offs surfaced.

**Plan v2 response:**

- Frontmatter: `plan_review_dissent: "Split KB-drift into PR-H + PR-H2 (DHH P0) — brainstorm Phase 2 weighed Approach A vs B with full information and chose A; rf-when-a-reviewer-or-user-says-to-keep-a applies."`
- AskUserQuestion presented the dissent as part of the "Apply edits" question with option-3 explicitly offering to reverse the dissent. Operator picked option-1 ("All — dissent stays"), confirming the decision.

The other 13 plan-review findings (P0/P1/P2 across all three reviewers) were folded. The single architectural-direction finding was dissented.

## Session Errors

1. **None directly attributable to this learning's mechanism** in this session — the dissent was caught correctly. The error this learning prevents is the *silent fold* mode where a plan-review finding gets applied without surfacing the dissent rationale to the operator.

## Key Insight

Plan-review is a parallel critique pass, not a decision-overriding authority. It sees the plan; it does not see the brainstorm's decision history. When plan-review and brainstorm-time operator decisions converge, fold. When they diverge on an architectural choice the operator already made informed, **dissent + surface to operator + document**. The asymmetry between "13 review findings folded" and "1 dissent documented" is itself a signal that the workflow is operating correctly — silent unanimous fold is the failure mode, not the success mode.

The natural variant of this pattern: a plan-review finding can be *correct* (DHH's analysis of KB-drift's structural independence from the GitHub source IS correct) AND simultaneously the wrong action to take (because the operator already weighed that trade-off and chose bundling for legal-review-batching reasons that DHH doesn't have visibility into). "Right analysis, wrong action" is not a contradiction — it's the routine output of incomplete information across parallel agents.

## Tags

category: workflow-patterns
module: plan
