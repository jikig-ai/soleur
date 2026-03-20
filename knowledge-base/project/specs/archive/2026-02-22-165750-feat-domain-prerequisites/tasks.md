# Tasks: Domain Prerequisites

**Issue:** #251
**Plan:** `knowledge-base/plans/2026-02-22-refactor-domain-prerequisites-plan.md`
**Branch:** `feat-domain-prerequisites`

## Phase 1: Token Budget Trim

- [ ] 1.1 Run baseline word count: `shopt -s globstar && grep -h 'description:' plugins/soleur/agents/**/*.md | wc -w`
- [ ] 1.2 Trim descriptions for all agents over 50 words (top 10 candidates listed in plan)
- [ ] 1.3 Trim remaining agents to bring cumulative total under 2,300
- [ ] 1.4 Verify disambiguation sentences preserved for all sibling agents
- [ ] 1.5 Run final word count -- must be <= 2,300

## Phase 2: Brainstorm Routing Refactor

- [ ] 2.1 Replace Assessment section (lines 63-81) with merged domain config table (brand folded into marketing)
- [ ] 2.2 Replace Routing section (lines 83-152) with generic processing instructions referencing config table
- [ ] 2.3 Replace Participation section (lines 250-314) -- prompts live in the config table's Task Prompt column
- [ ] 2.4 Preserve Brand Workshop section as-is (referenced by marketing's workshop option)
- [ ] 2.5 Preserve Validation Workshop section as-is (referenced by product's workshop option)
- [ ] 2.6 Update the HTML comment on line 61 to reflect table-driven approach
- [ ] 2.7 Verify: marketing row has 3 options (brand workshop / include-CMO / skip)
- [ ] 2.8 Verify: product row has 3 options (validation workshop / include-CPO / skip)

## Phase 3: Fix Domain Enumeration

- [ ] 3.1 Fix `plugins/soleur/.claude-plugin/plugin.json` -- add "sales" to description
- [ ] 3.2 Fix `plugins/soleur/README.md` line 3
- [ ] 3.3 Fix `README.md` line 5
- [ ] 3.4 Fix `AGENTS.md` line 3
- [ ] 3.5 Fix `plugins/soleur/docs/pages/getting-started.md` lines 21 and 114
- [ ] 3.6 Fix `plugins/soleur/docs/llms.txt.njk` line 9
- [ ] 3.7 Fix `plugins/soleur/docs/pages/legal/terms-and-conditions.md` -- "five domains" and title-case list
- [ ] 3.8 Verify no others missed: `grep -ri "five domains\|engineering, marketing, legal, operations, and product" --include="*.md" --include="*.json" --include="*.njk"`

## Phase 4: Verification and Ship

- [ ] 4.1 Version bump (PATCH) -- update plugin.json, CHANGELOG.md, README.md
- [ ] 4.2 Run `/soleur:review` on unstaged changes
- [ ] 4.3 Run `/soleur:compound` to capture learnings
- [ ] 4.4 Commit, push, create PR
