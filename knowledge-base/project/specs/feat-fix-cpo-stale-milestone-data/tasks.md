# Tasks: fix CPO stale milestone data

## Phase 1: CPO Agent Fix

- [ ] 1.1 Read `plugins/soleur/agents/product/cpo.md`
- [ ] 1.2 Add new milestone API query bullet as FIRST item in the Assess section (before business-validation.md check)
  - Run `gh api repos/{owner}/{repo}/milestones` (open) and `gh api repos/{owner}/{repo}/milestones?state=closed` (closed)
  - Do NOT use `--paginate` (avoids concatenated-array footgun per constitution.md line 29; milestones are bounded by phase count)
  - Instruction: "Query GitHub milestones FIRST to get authoritative phase status before reading any file"
- [ ] 1.3 REMOVE the existing "Roadmap consistency check" bullet (line 22) -- do not leave it in place
- [ ] 1.4 Add a reconciliation step AFTER spec files check (replaces old Roadmap consistency check)
  - New text: read roadmap.md Current State, compare against API results, trust API when conflict, flag staleness
  - This is the second half of the split -- the first half is the API query at the top (1.2)
- [ ] 1.5 Verify only ONE instruction references `gh api milestones` (no duplication)

## Phase 2: AGENTS.md Workflow Gate

- [ ] 2.1 Read `AGENTS.md`
- [ ] 2.2 Add new workflow gate bullet after line 29 (the existing "When moving GitHub issues between milestones" gate)
  - Gate text covers closing phase milestones requiring Current State update
  - Include `**Why:**` with #1878 as the motivating incident

## Phase 3: Roadmap Current State Update

- [ ] 3.1 Read `knowledge-base/product/roadmap.md`
- [ ] 3.2 Re-query milestone API at implementation time (do NOT use plan's snapshot numbers)
  - `gh api repos/jikig-ai/soleur/milestones --jq '.[] | "\(.title) | open:\(.open_issues) | closed:\(.closed_issues)"'`
  - `gh api repos/jikig-ai/soleur/milestones?state=closed --jq '.[] | "\(.title) | open:\(.open_issues) | closed:\(.closed_issues)"'`
- [ ] 3.3 Update `## Current State` section heading date to current date
- [ ] 3.4 Update all phase status rows with live API numbers
- [ ] 3.5 Update `last_updated` frontmatter to current date

## Phase 4: Validation

- [ ] 4.1 Verify CPO agent has API query BEFORE any file reads in Assess section
- [ ] 4.2 Verify old "Roadmap consistency check" bullet is gone (grep for the exact phrase)
- [ ] 4.3 Verify AGENTS.md has milestone closure gate
- [ ] 4.4 Verify roadmap.md Current State numbers match live API
- [ ] 4.5 Run `npx markdownlint-cli2 --fix` on all changed `.md` files
