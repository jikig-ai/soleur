# Learning: skill-description word budget uses a different tokenizer than the cross-component `grep | wc -w` survey

## Problem

During review of PR #2629 (rename `cleanup-scope-outs` → `drain-labeled-backlog`), the pattern-recognition-specialist reported a P2 word-budget overrun: **1895 / 1800** cumulative skill descriptions. The plan had explicitly verified the budget at **1798 / 1800** during deepen-pass using the tokenizer inside `plugins/soleur/test/components.test.ts`. Both numbers were produced honestly; the agent flagged a budget failure that did not exist.

## Root cause

Two distinct tokenizers are in play:

1. **The enforced CI check** (`plugins/soleur/AGENTS.md` Skill Compliance Checklist):

   ```bash
   bun test plugins/soleur/test/components.test.ts
   ```

   Internally splits the `description:` YAML *value* via `desc.split(/\s+/).filter(Boolean).length`. Counts only the content of the string, not the `description:` key or the surrounding quotes.

2. **The survey tokenizer** (reused from the agent-budget pattern in `plugins/soleur/AGENTS.md` Agent Compliance Checklist):

   ```bash
   grep -h 'description:' plugins/soleur/skills/**/SKILL.md | wc -w
   ```

   Includes the `description:` key, surrounding quotes, and any leading whitespace in each match. Inflates the count by ~5 words per skill and produces a different "cumulative" figure.

The **agent** Compliance Checklist uses the `grep | wc -w` shape for a 2500-word budget — different scale. The **skill** Compliance Checklist uses the bun test — 1800-word budget. Agents reading AGENTS.md sometimes carry the grep pattern across and apply it to the skill budget, producing apparent overruns that the CI gate does not see.

## Solution

- Budget truth is `bun test plugins/soleur/test/components.test.ts`. If that passes, the budget is satisfied regardless of what `grep | wc -w` prints.
- When reporting a skill description word-budget finding, always cite the tokenizer. A `grep | wc -w` figure is a survey, not a gate.
- If a large delta appears between the two counts, that is expected — the grep tokenizer includes ~5 extra words of YAML framing per skill (`"description:"` + quotes).

## Prevention

- Reviewer agents evaluating skill word budgets MUST run the bun test locally (or read the test's tokenizer source) before reporting an overrun. The test file is at `plugins/soleur/test/components.test.ts`.
- If a future refactor wants a single tokenizer across both budgets, pick one and update both `plugins/soleur/AGENTS.md` sections in the same change. Today they are intentionally different because the two budgets target different files.

## Session context

- Plan deepen-pass recorded the correct pre-rename total (1798) by replicating the bun tokenizer in a shell one-liner — see the plan's Sharp Edges for the replication command.
- The PR added 2 words to the new description (`drain-labeled-backlog` supports `type/security` as a third example label). Post-rename total: 1800, at the ceiling but compliant. Bun test passed.

## Tags

category: best-practices
module: plugins/soleur/skills
