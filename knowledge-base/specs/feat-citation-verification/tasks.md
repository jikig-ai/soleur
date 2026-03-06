# Tasks: Citation Verification

## Phase 1: Setup

- [ ] 1.1 Read existing marketing agents for structure reference (`copywriter.md`, `cmo.md`)
- [ ] 1.2 Check cumulative agent description word count baseline
- [ ] 1.3 Read content-writer `SKILL.md` current phase structure

## Phase 2: Core Implementation

- [ ] 2.1 Create fact-checker agent (`plugins/soleur/agents/marketing/fact-checker.md`)
  - [ ] 2.1.1 Write YAML frontmatter (`name`, `description` under 45 words, `model: inherit`)
  - [ ] 2.1.2 Add disambiguation sentence referencing copywriter agent
  - [ ] 2.1.3 Write verification protocol in agent body (extract claims, fetch URLs, compare, report)
  - [ ] 2.1.4 Define structured output contract (Verification Report with heading-level sections)
  - [ ] 2.1.5 Verify cumulative description word count stays under 2,500
- [ ] 2.2 Add Phase 2.5 to content-writer skill (`plugins/soleur/skills/content-writer/SKILL.md`)
  - [ ] 2.2.1 Insert Phase 2.5: Citation Verification between Phase 2 (Generate Draft) and Phase 3 (User Approval)
  - [ ] 2.2.2 Add Task tool invocation of fact-checker agent with draft content
  - [ ] 2.2.3 Parse verification report and annotate claims with PASS/FAIL/UNSOURCED status
  - [ ] 2.2.4 Update Phase 3 presentation to include verification status per claim
  - [ ] 2.2.5 Handle edge case: no verifiable claims found (proceed normally)
  - [ ] 2.2.6 Handle edge case: WebFetch failures (mark as FAIL, do not block)
  - [ ] 2.2.7 Remove or update the passive guideline at line 124 (now enforced by Phase 2.5)
- [ ] 2.3 Add constitution rule (`knowledge-base/overview/constitution.md`)
  - [ ] 2.3.1 Add `## Content` section with verification rule
  - [ ] 2.3.2 Rule: never publish quantitative claims, attributed quotes, or factual assertions without a linked, fetchable source URL

## Phase 3: Documentation Updates

- [ ] 3.1 Update `plugins/soleur/AGENTS.md` CMO domain leader table if agent count changes
- [ ] 3.2 Verify README.md agent count reflects the new agent

## Phase 4: Verification

- [ ] 4.1 Verify agent description word count is under 2,500
- [ ] 4.2 Verify content-writer skill phase numbering is consistent
- [ ] 4.3 Run markdownlint on all modified files
- [ ] 4.4 Run compound (`skill: soleur:compound`)
