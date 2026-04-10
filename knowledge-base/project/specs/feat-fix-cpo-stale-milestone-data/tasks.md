# Tasks: fix CPO stale milestone data

## Phase 1: CPO Agent Fix

- [ ] 1.1 Read `plugins/soleur/agents/product/cpo.md`
- [ ] 1.2 Add new milestone API query bullet as FIRST item in the Assess section (before business-validation.md check)
  - Run `gh api repos/{owner}/{repo}/milestones --paginate` (open) and `gh api repos/{owner}/{repo}/milestones?state=closed --paginate` (closed)
  - Instruction: "Query GitHub milestones FIRST to get authoritative phase status before reading any file"
- [ ] 1.3 Replace the existing "Roadmap consistency check" bullet with a reconciliation step
  - Move after spec files check
  - New text: read roadmap.md Current State, compare against API results, trust API when conflict, flag staleness
- [ ] 1.4 Add conflict resolution instruction: "If the API result conflicts with the roadmap Current State section, trust the API -- the file may be stale. Flag the staleness as an inconsistency finding."

## Phase 2: AGENTS.md Workflow Gate

- [ ] 2.1 Read `AGENTS.md`
- [ ] 2.2 Add new workflow gate bullet after line 29 (the existing "When moving GitHub issues between milestones" gate)
  - Gate text covers closing phase milestones requiring Current State update
  - Include `**Why:**` with #1878 as the motivating incident

## Phase 3: Roadmap Current State Update

- [ ] 3.1 Read `knowledge-base/product/roadmap.md`
- [ ] 3.2 Update `## Current State` section heading date from `2026-04-03` to `2026-04-10`
- [ ] 3.3 Update Phase 3 status: `12 open, 27 closed`
- [ ] 3.4 Update Phase 4 status: `16 open, 11 closed`
- [ ] 3.5 Update Phase 5 status: `5 open, 0 closed`
- [ ] 3.6 Update Post-MVP / Later status: `73 open, 265 closed`
- [ ] 3.7 Update `last_updated` frontmatter to `2026-04-10`

## Phase 4: Validation

- [ ] 4.1 Verify CPO agent has API query before any file reads
- [ ] 4.2 Verify AGENTS.md has milestone closure gate
- [ ] 4.3 Run `npx markdownlint-cli2 --fix` on all changed `.md` files
