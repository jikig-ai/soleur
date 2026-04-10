# Tasks: fix domain leader gh verify task prompts

## 1. Core Implementation

### 1.1 Update brainstorm-domain-config.md Task Prompts

- [ ] 1.1.1 Read `plugins/soleur/skills/brainstorm/references/brainstorm-domain-config.md`
- [ ] 1.1.2 Add `gh issue view` verification sentence to Marketing Task Prompt
- [ ] 1.1.3 Add `gh issue view` verification sentence to Engineering Task Prompt
- [ ] 1.1.4 Add `gh issue view` verification sentence to Operations Task Prompt
- [ ] 1.1.5 Add `gh issue view` verification sentence to Product Task Prompt
- [ ] 1.1.6 Add `gh issue view` verification sentence to Legal Task Prompt
- [ ] 1.1.7 Add `gh issue view` verification sentence to Sales Task Prompt
- [ ] 1.1.8 Add `gh issue view` verification sentence to Finance Task Prompt
- [ ] 1.1.9 Add `gh issue view` verification sentence to Support Task Prompt

### 1.2 Normalize CCO agent wording

- [ ] 1.2.1 Read `plugins/soleur/agents/support/cco.md`
- [ ] 1.2.2 Change "a specific GitHub issue" to "a GitHub issue" on line 16

## 2. Verification

- [ ] 2.1 Grep all 8 Task Prompts in brainstorm-domain-config.md for `gh issue view` -- expect 8 matches
- [ ] 2.2 Grep all 8 domain leader agent files for `gh issue view` -- expect 8 matches (unchanged)
- [ ] 2.3 Verify CCO wording matches other agents
- [ ] 2.4 Run `npx markdownlint-cli2 --fix` on changed `.md` files

## 3. Deferred (separate issue)

- [ ] 3.1 Create GitHub issue for named agent spawning (Approach B) -- change brainstorm/plan skills to use `Task <leader-name>(Task Prompt)` instead of anonymous Tasks
