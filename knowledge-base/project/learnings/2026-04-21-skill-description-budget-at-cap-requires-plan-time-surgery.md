---
category: best-practices
module: plan-skill
date: 2026-04-21
tags:
  - token-budget
  - skill-descriptions
  - plan-acceptance-criteria
  - soleur-plugin
---

# Learning: Skill description budget at 1800/1800 means new-skill plans need surgery built-in

## Problem

While implementing the `peer-plugin-audit` sub-mode (#2722), measurement of cumulative skill descriptions showed exactly **1800/1800 words** — the hard cap enforced by `plugins/soleur/test/components.test.ts`. Zero headroom.

Any plan that adds a new skill, adds a sub-mode description mention, or expands an existing description by a single word — without simultaneously trimming siblings — breaks `bun test` at work-phase time. The failure only surfaces during validation, which is late enough to force an inline surgery or a separate chore PR.

A related paper-cut: the test measures `desc.split(/\s+/).filter(Boolean).length`, and my plan's Phase 4.2 draft claimed "~28 words" for the proposed description. Actual word count when written was 25 words. The plan's word-count estimates were not verified at plan-time; Kieran's reviewer agent caught a similar "28 vs 23" claim in the earlier plan draft.

## Solution

**Plan-time** (required for any PR editing skill `description:` fields):

1. Re-measure total skill description words at plan-time via the one-liner below. Record baseline in the plan's Research Insights.
2. If baseline ≥ 1790 (within 10w of cap), the plan MUST include exact before/after text for the sibling descriptions it will trim. Deferred decisions ("pick during work") break down: (a) they force the work-phase agent to make description-rewrite decisions without review, (b) if trimming fails, implementation has no fallback.
3. Target: new/expanded description stays ≤ 30 words per sibling (Skill Compliance Checklist recommendation).
4. If the change requires net-new words but baseline is at cap, either trim siblings inline OR split into two PRs: a `chore(plugin): trim descriptions` PR that lands first, then the feature PR.

**Work-phase**: re-measure after every description edit. A mid-implementation test failure is a red flag that plan-time measurement was skipped or wrong.

**Measurement one-liner** (portable; avoids awk edge cases):

```bash
node -e "
const fs = require('fs');
const path = require('path');
const root = 'plugins/soleur/skills';
const dirs = fs.readdirSync(root).filter(d => fs.statSync(path.join(root, d)).isDirectory());
let total = 0;
const counts = [];
for (const d of dirs) {
  const f = path.join(root, d, 'SKILL.md');
  if (!fs.existsSync(f)) continue;
  const content = fs.readFileSync(f, 'utf-8');
  const match = content.match(/^description:\s*\"?([\s\S]*?)\"?\s*$/m);
  if (match) {
    const words = match[1].split(/\s+/).filter(Boolean).length;
    total += words;
    counts.push({d, words});
  }
}
console.log('Total:', total, '/ 1800. Headroom:', 1800 - total);
console.log('Top 5:', counts.sort((a,b) => b.words - a.words).slice(0,5).map(c => c.d + ':' + c.words).join(', '));
"
```

## Key Insight

**A test at exact capacity is a silent-fail surface.** Cumulative-budget tests (token, bundle size, file count) pass today but fail on any additive change. Plans that edit the regulated surface must treat the budget as a first-class constraint with exact-text mitigation, not as a validation step at the end.

## Session Errors

- **Token budget discovered at 1800/1800 during plan-phase research, not surfaced earlier** — learned via Node one-liner in plan-phase, not during brainstorm. Recovery: plan included surgical trim. **Prevention:** any skill-level brainstorm that mentions new-skill or description expansion should run the measurement one-liner in Phase 1 and record headroom. If ≤ 10w headroom, the brainstorm MUST raise the constraint before action planning.
- **Plan word-count estimates were off by ~3 words** (Kieran caught "28 vs 23", work phase measured "25 vs 29"). Recovery: actual measurement overrides estimates; headroom was sufficient. **Prevention:** plans that quote a word count must include the exact proposed text so a reader can re-measure. "Approximately N words" without the text is not a measurement.
- **Markdownlint auto-trimmed trailing space inside backtick-inline-code** (`peer-plugin-audit ` → `peer-plugin-audit`). Semantic-preserving for routing ("arguments start with" still matches), but a reviewer might expect the trailing space. **Prevention:** when describing routing based on a token-plus-space prefix, use prose ("the first whitespace-delimited word") rather than a trailing-space literal inside inline code.

## Proposed Skill/AGENTS.md Edits

- **plan skill** — add a Phase 1 sub-step: "If the plan edits any `description:` in `plugins/soleur/skills/*/SKILL.md`, run the budget one-liner, record baseline headroom, and if < 10 words, include exact sibling-trim text in the plan's Phase 5 before proceeding to Phase 2."
- **brainstorm skill** — add a Phase 2 checkpoint for skill-adding brainstorms: "Run token-budget measurement before proposing action plan. Surface constraint if headroom is tight."
- **AGENTS.md** — candidate new rule (budget permitting):

  > `[id: cq-skill-description-budget-headroom]` When a PR edits any `description:` in `plugins/soleur/skills/*/SKILL.md`, the plan MUST measure and include the current cumulative word headroom (cap: 1800). If headroom < 10 words, the plan MUST prescribe exact sibling-description trims with before/after text. **Why:** PR `#2734` — this learning.

  Rule budget cost: ~520 bytes. Current: 106/100 rules, 36566/40000 bytes — budget warning active. Adding this rule would require retiring another rule first OR migrating narrative to a learning file. Deferred: file as separate issue.

## Related

- `knowledge-base/project/plans/2026-04-21-feat-peer-plugin-audit-sub-mode-plan.md` (this feature's plan)
- `knowledge-base/project/learnings/2026-04-21-peer-plugin-audit-brainstorm-patterns.md` (earlier session learning)
- `knowledge-base/project/specs/feat-claude-skills-audit/spec.md` TR2 (Token-budget compliance)
- `plugins/soleur/test/components.test.ts:140-161` (the enforcing test)
- PR `#2734`, issue `#2722`
