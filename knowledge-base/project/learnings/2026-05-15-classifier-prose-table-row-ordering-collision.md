---
date: 2026-05-15
category: best-practices
module: commands, classifiers, plan-skill, brainstorm-domain-config
tags: [classifier-prose-table, row-ordering, semantic-routing, brand-survival, single-user-incident, user-impact-reviewer-catch]
related-pr: "#3780"
related-issues: ["#3785"]
related-learnings:
  - knowledge-base/project/learnings/2026-05-15-five-agent-plan-review-revision-pass-brand-survival-plan.md
---

# Learning: Classifier prose-table row ordering matters semantically when rows share keywords

## Problem

`/soleur:go` Step 2 Classify table routes operator input to a workflow skill or agent. Rows are prose-described (Intent / Trigger Signals / Routes To), and the routing agent matches semantically — there's no regex, just an LLM reading the table top-to-bottom and picking the first row whose Trigger Signals plausibly describe the input.

When PR #3780 added a `legal-threshold` row to route legal-domain mentions (MSA, DSAR, breach, AI vendor terms, OSS license) to `clo`, the row was placed above `default` (correct) but **below `incident`**:

| Row order (initial, wrong) | Trigger excerpt |
|---|---|
| `incident` | "outage, **breach**, customer-impact, Sentry alert" |
| `legal-threshold` | "vendor MSA, DSAR, **breach** / data exposure / unauthorized access" |
| `default` | "everything else" |

Both rows triggered on the keyword "breach." First-match wins in the classifier's semantic interpretation. A founder typing `/soleur:go "we had a security incident and someone may have accessed user PII"` would route to `incident` (PIR scaffold) — NOT `legal-threshold` (which would invoke `clo` and surface the GDPR Art. 33 72-hour deadline H3).

This is a **brand-survival single-user-incident vector**: the founder's recourse for a 72-hour legal clock gets shadowed by ops-postmortem scaffolding that has no deadline awareness. They miss the statutory clock.

The defect was caught at PR-time by the `user-impact-reviewer` agent (because the plan declared `Brand-survival threshold: single-user incident`), NOT at plan-time by Kieran or arch-strategist. Plan-time review evaluated each row in isolation and missed the cross-row collision; user-impact-reviewer's "name artifact + name vector" mandate forced enumeration of "what's the founder under pressure actually clicking" and surfaced the routing path.

## Solution

Two-part fix to `/soleur:go` Step 2 table:

1. **Reorder so legal-threshold matches BEFORE incident.** Per first-match semantic, the row whose trigger more specifically describes the input wins.
2. **Scope-exclude in the now-second row.** Add explicit prose to `incident` clarifying it is ops-only ("outage, customer-impact, Sentry alert. NOTE: pure data breaches without an operational outage route to `legal-threshold` above; use `incident` for ops-postmortem scope (uptime, latency, error-rate)").

Belt-and-suspenders: even if a future input ambiguously matches both, the explicit exclusion language steers the classifier to the right row.

## Key Insight

**Classifier prose-tables that use semantic-prose triggers (not regex) compose poorly across rows. Adding a row requires reading EVERY existing row's triggers for keyword overlap — and the cost of missing a collision is whatever brand-survival vector the routes-to side of the colliding rows protects.**

The generalizable rule (proposed routing target: plan-skill Sharp Edges, OR commands/go.md maintainer note, OR brainstorm-domain-config.md classifier table — pending operator triage on issue #3795):

> When adding a row to a semantic-prose classifier table (e.g., `/soleur:go` Step 2, `brainstorm-domain-config.md`, any future intent-routing surface), grep every existing row's trigger description for any keyword the new row also names. If overlap exists, either (a) reorder so the new row matches first when both apply (when the new row's path is more specific), or (b) add explicit-exclusion language to the existing row that scopes its trigger away from the new domain. Plan-time review evaluates rows in isolation and reliably misses cross-row collisions; the catch lives at PR-time only when `user-impact-reviewer` fires (i.e., when brand-survival threshold = single-user incident).

This pattern is distinct from the existing `cq-union-widening-grep-three-patterns` rule (consumer-side enum exhaustiveness): that's about typed-value gates; this is about prose-trigger gates. Both share the underlying pattern of "additive change to a multi-branch dispatch must enumerate the existing branches."

## Session Errors

1. **PreToolUse hook false-positive on test file write.** First Write attempt for `plugins/soleur/test/legal-recommended-tools.test.ts` was blocked by a hook printing a security warning about shell-process invocation, even though the file uses only `readFileSync` from `node:fs`. **Recovery:** retried Write; second attempt succeeded (apparently advisory after first warning). The same hook fired again on this learning file because the file body discusses the hook's own diagnostic text. **Prevention:** the hook pattern over-fires on TypeScript and markdown content containing the substring it warns about. Worth filing a fix issue against the hook script if it recurs; not blocking because the hook is advisory.

2. **clo.md word-budget overrun after subsection rename.** PR-1 review fix renamed the threshold-detection subsection and added a 2-sentence intro clarifying placement. Pushed `wc -w plugins/soleur/agents/legal/clo.md` from 846 to 883, breaking the plan's ≤ 850 ceiling. **Recovery:** trimmed the new intro paragraph (1 sentence cut) AND tightened the Sharp Edges entry (split verbose single bullet into two terser bullets, also satisfying code-simplicity-reviewer recommendation #4). Final 827 words. **Prevention:** when renaming + expanding existing prose, re-run `wc -w` in the same edit cycle, not as an afterthought.

3. **Test-driven structure shaping in recommended-tools.md H2 count.** Initial write included `## Why this page exists` + `## Maintenance` as H2 footers, making total H2 = 7. Vendor-neutrality test asserted "exactly 5 H2 sections (frozen catalog)." **Recovery (initial):** demoted to H3 to satisfy the assertion. **Recovery (after pattern-recognition + code-simplicity reviewers flagged):** changed the test to count tool-table H2s (via `extractTableSections().length`) instead of all H2s; promoted the footers to live under `## About this page` H2 with H3 children. **Prevention:** when an assertion's count would force a non-canonical document structure, the assertion is wrong (test-driven structure shaping). The assertion should target the *structural role* (sections-with-tables, sections-matching-anchor-pattern) not the *count of an HTML element*.

## Workflow Feedback Proposals

- **Plan-skill Sharp Edges (DOMAIN-SCOPED):** "When applying a review fix that expands prose in a budget-constrained file, re-run the budget check (`wc -w`, `bun test components.test.ts`, etc.) in the same edit cycle. Plan AC enforcement at PR-time discovers the overrun late."
- **Plan-skill Sharp Edges (DOMAIN-SCOPED):** "When adding rows to a semantic-prose classifier table (e.g., `/soleur:go` Step 2, `brainstorm-domain-config.md`), grep every existing row's trigger description for keyword overlap. Plan-time review evaluates rows in isolation and misses cross-row collisions; the catch lives at PR-time only when `user-impact-reviewer` fires."
- **Test-skill / components.test.ts pattern (DOMAIN-SCOPED):** "Assertions on docs-page structure should target structural roles (e.g., 'sections containing a tool table'), not raw HTML-element counts. The latter forces non-canonical structure when the count constraint is artificial."

These would route to issue #3795 as additional proposals (already established for plan-skill Sharp Edges) — within bounded-surface rule for that issue.
