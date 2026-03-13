# Tasks: Business Validation (CPO + Business Validator)

## Phase 1: Business Validator Agent

- [ ] 1.1 Create `plugins/soleur/agents/product/business-validator.md`
  - [ ] 1.1.1 YAML frontmatter (name, description with disambiguation, model: inherit)
  - [ ] 1.1.2 Step 0: Detect-and-resume logic (check for existing business-validation.md)
  - [ ] 1.1.3 Steps 1-6: Six validation gates with AskUserQuestion flow
  - [ ] 1.1.4 Kill criterion override flow (revise/override/end options)
  - [ ] 1.1.5 Web search at Gate 3 (query construction, fallback)
  - [ ] 1.1.6 Output document contract (headings, frontmatter)
  - [ ] 1.1.7 Atomic write with `last_updated` frontmatter
  - [ ] 1.1.8 Important Guidelines section

## Phase 2: CPO Domain Leader

- [ ] 2.1 Create `plugins/soleur/agents/product/cpo.md`
  - [ ] 2.1.1 YAML frontmatter (name, description with disambiguation, model: inherit)
  - [ ] 2.1.2 Phase 1: Assess (product maturity, existing artifacts)
  - [ ] 2.1.3 Phase 2: Recommend (product direction with trade-offs)
  - [ ] 2.1.4 Phase 3: Delegate (routing decision tree)
  - [ ] 2.1.5 Sharp Edges section

## Phase 3: Brainstorm Integration

- [ ] 3.1 Update `plugins/soleur/commands/soleur/brainstorm.md` Phase 0.5
  - [ ] 3.1.1 Add assessment question item 4 (product strategy implications)
  - [ ] 3.1.2 Add routing block with AskUserQuestion
  - [ ] 3.1.3 Add CPO participation block in Domain Leader Participation section
  - [ ] 3.1.4 Add business-validator workshop route (worktree + STOP pattern)
  - [ ] 3.1.5 Update multi-domain note

## Phase 4: Disambiguation

- [ ] 4.1 Update `plugins/soleur/agents/product/spec-flow-analyzer.md` description
- [ ] 4.2 Update `plugins/soleur/agents/product/design/ux-design-lead.md` description

## Phase 5: Plugin Infrastructure

- [ ] 5.1 Update `plugins/soleur/AGENTS.md` domain leaders table
- [ ] 5.2 MINOR version bump in `plugins/soleur/.claude-plugin/plugin.json` (from main)
- [ ] 5.3 Update `plugins/soleur/CHANGELOG.md` with new version entry
- [ ] 5.4 Update `plugins/soleur/README.md` (Product count, agent table, total count, reconcile discrepancies)
- [ ] 5.5 Update root `README.md` version badge
- [ ] 5.6 Update `.github/ISSUE_TEMPLATE/bug_report.yml` placeholder
- [ ] 5.7 Update `plugins/soleur/.claude-plugin/plugin.json` description agent count

## Phase 6: Dogfooding

- [ ] 6.1 Run business-validator on Soleur itself
- [ ] 6.2 Review and commit the validation output
