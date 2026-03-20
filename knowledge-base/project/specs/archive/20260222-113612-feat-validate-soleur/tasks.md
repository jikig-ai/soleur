# Tasks: Align Onboarding with Company-as-a-Service Vision

Issue: #248
Plan: `knowledge-base/plans/2026-02-22-feat-validate-soleur-vision-alignment-plan.md`

## Phase 1: Agent Fixes

- [x] 1.1 Fix business-validator agent (`plugins/soleur/agents/product/business-validator.md`)
  - [x] 1.1.1 Add Step 0.5: Read Project Identity (insert between Step 0 and Gate 1)
  - [x] 1.1.2 Make Gate 6 vision-aware (change question 1, add breadth-coherence criterion)
  - [x] 1.1.3 Add Vision Alignment Check before Final Write section
- [x] 1.2 Fix CPO agent (`plugins/soleur/agents/product/cpo.md`)
  - [x] 1.2.1 Add cross-reference check between business-validation.md and brand-guide.md in Assess phase

## Phase 2: Content Alignment

- [x] 2.1 Fix plugin.json description (`plugins/soleur/.claude-plugin/plugin.json`)
  - [x] 2.1.1 Change description: "engineering knowledge" -> "company knowledge", mention all 5 domains
  - [x] 2.1.2 Update keywords: add "company-as-a-service", "solo-founder"
  - [x] 2.1.3 Verify agent/skill/command counts match actual files
- [x] 2.2 Fix root README (`README.md`)
  - [x] 2.2.1 Replace line 5 hedging with 5-domain description
  - [x] 2.2.2 Add "Your AI Organization" table with 5 departments and entry points
- [x] 2.3 Fix Getting Started page (`plugins/soleur/docs/pages/getting-started.md`)
  - [x] 2.3.1 Replace hardcoded counts with dynamic template variables (preserve bold)
  - [x] 2.3.2 Add "Beyond Engineering" section with non-engineering workflows
  - [x] 2.3.3 Fix Learn More description to mention all 5 domains
- [x] 2.4 Fix llms.txt (`plugins/soleur/docs/llms.txt.njk`)
  - [x] 2.4.1 Replace line 9 with full platform description
- [x] 2.5 Fix plugin README subtitle (`plugins/soleur/README.md`)
  - [x] 2.5.1 Change line 3 to mention all 5 domains
- [x] 2.6 Fix AGENTS.md line 1 (`AGENTS.md`)
  - [x] 2.6.1 Replace "structured software development workflows" with 5-domain scope

## Phase 3: Business Validation Rewrite

- [x] 3.1 Rewrite business-validation.md (`knowledge-base/overview/business-validation.md`)
  - [x] 3.1.1 Reframe problem: solo founders managing a company, not devs wanting coding workflows
  - [x] 3.1.2 Reframe customer: solo founders building with AI, not just devs
  - [x] 3.1.3 Reframe competitive landscape: AI agent workforce platforms
  - [x] 3.1.4 Reframe demand evidence: honest assessment framed around Company-as-a-Service demand
  - [x] 3.1.5 Reframe business model through Company-as-a-Service lens
  - [x] 3.1.6 Reframe minimum viable scope: 5 domains IS the minimum
  - [x] 3.1.7 Cross-reference every section against brand-guide.md

## Phase 4: Version Bump and CI

- [ ] 4.1 PATCH version bump
  - [ ] 4.1.1 Update `plugins/soleur/.claude-plugin/plugin.json` version
  - [ ] 4.1.2 Update `plugins/soleur/CHANGELOG.md`
  - [ ] 4.1.3 Update `plugins/soleur/README.md` counts
  - [ ] 4.1.4 Update `README.md` version badge
  - [ ] 4.1.5 Update `.github/ISSUE_TEMPLATE/bug_report.yml` placeholder
- [ ] 4.2 Verify CI passes
  - [ ] 4.2.1 All changes pass markdownlint
  - [ ] 4.2.2 SEO validation passes
  - [ ] 4.2.3 Component tests pass
  - [ ] 4.2.4 Agent description word count under 2500
