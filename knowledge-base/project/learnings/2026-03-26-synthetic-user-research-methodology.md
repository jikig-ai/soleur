# Learning: Synthetic User Research Methodology for Pre-Validation Hypothesis Sharpening

## Problem

Soleur's PIVOT verdict requires 10 real founder interviews but only ~2 were completed. The interview guides, value proposition framings, and pricing models were untested. The founder needed a faster way to generate directional signals before the next batch of real conversations, without treating synthetic results as validation evidence.

## Solution

Designed 10 synthetic founder personas covering the ICP spectrum (4 revenue stages, 3 technical depths, 4 domain pain categories, 5 industries, including AI skeptics and non-technical founders). Ran them through three parallel research gates:

1. **Interview prep:** Both interview guides (15-min and 30-min) run against all 10 personas. Identified 5 questions needing rewrites and 6 missing questions.
2. **Value prop testing:** 3 framings (CaaS, pain-point, tool-replacement) tested qualitatively. Pain-point won 7/10.
3. **Pricing sensitivity:** 3 models (flat, hybrid, outcome-based) tested for objection patterns. Outcome-based = on-ramp, not business model.

Compiled into a research brief with confidence levels and explicit limitations.

## Key Insight

**Synthetic persona research is most valuable for stress-testing research instruments, not for generating market data.** The highest-value outputs were: (a) discovering 3 pain archetypes the interview guides missed (burden, avoidance, anxiety), (b) identifying 5 weak interview questions, and (c) surfacing the "memory" differentiator as the buried lead across all framings. The lowest-value outputs were: specific dollar amounts, aggregate scores, and statistical claims — these are "the model predicting what its own predictions would look like" and should not be trusted.

**Parallel subagent fan-out works well for independent research gates.** The three gates (interview prep, value prop, pricing) had no dependencies on each other and produced independent output files. Running them in parallel cut wall-clock time roughly 3x.

**Subagent-generated markdown often fails lint.** Both the brainstorm and the pricing findings failed markdown lint on blank-lines-around-lists. Subagents don't inherit the project's lint conventions. A post-subagent lint check should be standard practice for knowledge-base writes.

## Session Errors

**Markdown lint failures on subagent-generated content** — Recovery: fixed manually (brainstorm) and via Python script (pricing findings). Prevention: run `markdownlint` on subagent output files before staging, or add a pre-commit step that auto-fixes MD032.

## Tags

category: workflow-patterns
module: knowledge-base, product-research, brainstorm, plan, work
