# Learning: Synthetic User Research Methodology for Pre-Validation Hypothesis Sharpening

## Problem

Soleur's PIVOT verdict requires 10 real founder interviews but only ~2 were completed. The interview guides, value proposition framings, and pricing models were untested. The founder needed a faster way to generate directional signals before the next batch of real conversations, without treating synthetic results as validation evidence.

## Solution

Designed 10 synthetic founder personas covering the ICP spectrum (4 revenue stages, 3 technical depths, 4 domain pain categories, 5 industries, including AI skeptics and non-technical founders). Ran them through three parallel research gates:

1. **Interview prep:** Both interview guides (15-min and 30-min) run against all 10 personas. Identified 5 questions needing rewrites and 6 missing questions.
2. **Value prop testing:** 3 framings (CaaS, pain-point, tool-replacement) tested qualitatively. Pain-point won 7/10.
3. **Pricing sensitivity:** 3 models (flat, hybrid, outcome-based) tested for objection patterns. Outcome-based = on-ramp, not business model.

Compiled into a research brief, then ran two additional rounds of dogfooding (V1 → V2) to validate the improvements:

- **V1 re-run:** Applied rewrites and new questions, re-ran all 10 personas. 15-min: 52% → 81% rich. 30-min: 48% → 76% rich. Identified remaining weak spots (Q9 at 40%, Q12 at 50%, emotional fatigue risk, 15-min guide too long).
- **V2 re-run:** Applied V1 fixes (rewrote Q9/Q12, cut redundant question, reordered emotional sequence), re-ran all personas. 15-min: 84% rich. 30-min: 93% rich. Both at synthetic ceiling.

All findings cascaded into source artifacts (interview guides, brand guide, pricing strategy) in the same PR.

## Key Insight

**Synthetic persona research is most valuable for stress-testing research instruments, not for generating market data.** The highest-value outputs were: (a) discovering 3 pain archetypes the interview guides missed (burden, avoidance, anxiety), (b) identifying 7 weak interview questions across 2 rounds, and (c) surfacing the "memory" differentiator as the buried lead across all framings. The lowest-value outputs were: specific dollar amounts, aggregate scores, and statistical claims — these are "the model predicting what its own predictions would look like" and should not be trusted.

**Iterative dogfooding is the correct workflow for research instruments.** A single research pass identifies problems but can't validate fixes. Running the same personas through updated instruments confirms whether rewrites actually work — and surfaces second-order weak spots the first pass missed. Three rounds (Original → V1 → V2) took the 30-min guide from 48% to 93% rich. The marginal return from a fourth round is near-zero (remaining flats are structural, not fixable by wording).

**Research findings MUST cascade into source artifacts in the same PR.** The first round produced 5 question rewrites, 6 new questions, and a value prop recommendation — none of which were applied until the founder asked "was any action taken?" This is now an AGENTS.md hard rule: research findings that sit in a brief without updating the documents they target are dead knowledge.

**Parallel subagent fan-out works well for independent research gates.** The three gates (interview prep, value prop, pricing) had no dependencies on each other and produced independent output files. Running them in parallel cut wall-clock time roughly 3x.

**Subagent-generated markdown often fails lint.** Both the brainstorm and the pricing findings failed markdown lint on blank-lines-around-lists. Subagents don't inherit the project's lint conventions. Now a constitution rule.

## Session Errors

**Markdown lint failures on subagent-generated content** — Recovery: fixed manually (brainstorm) and via Python script (pricing findings). Prevention: run `markdownlint` on subagent output files before staging, or add a pre-commit step that auto-fixes MD032.

## Tags

category: workflow-patterns
module: knowledge-base, product-research, brainstorm, plan, work
