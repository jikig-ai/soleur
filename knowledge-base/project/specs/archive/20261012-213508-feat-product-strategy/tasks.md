# Tasks: Product Strategy Validation Plan

**Branch:** feat-product-strategy
**Plan:** [2026-03-03-feat-product-strategy-validation-plan.md](../../plans/2026-03-03-feat-product-strategy-validation-plan.md)
**Issue:** #430

---

## Phase 1: Setup + Content (Weeks 1-2)

### 1.1 Onboarding Audit [auto] -- DONE

- [x] 1.1.1 Check Getting Started nav position (must be top 3) -- PASS
- [x] 1.1.2 Fresh install test: `claude plugin install soleur` on a new project -- PASS with caveats
- [x] 1.1.3 Test `/soleur:sync` on project with no knowledge-base -- PASS
- [x] 1.1.4 Test 3 non-engineering domain tasks end-to-end -- PASS (legal, brand, competitive)
- [x] 1.1.5 Document "first 5 minutes" flow -- FAIL (see audit report)
- [x] 1.1.6 Fix blockers found -- 3 blockers identified, tracked in #432 (CLOSED 2026-03-04)
- [x] 1.1.7 Write audit report to `knowledge-base/project/specs/feat-product-strategy/onboarding-audit.md`

### 1.2 Write Case Studies [auto + human] -- DONE (drafts)

- [x] 1.2.1 Write case study: Legal document generation (9 docs from scratch)
- [x] 1.2.2 Write case study: Brand guide creation
- [x] 1.2.3 Write case study: Competitive intelligence scan
- [x] 1.2.4 Write case study: Business validation workshop
- [x] 1.2.5 Write case study: Operations management
- [x] 1.2.6 Review all against brand guide voice -- reviewed 2026-03-10, approved

### 1.3 Interview Guide [auto] -- DONE

- [x] 1.3.1 Write interview guide with questions, definitions, and response table
- [x] 1.3.2 Save to `knowledge-base/project/specs/feat-product-strategy/interview-guide.md`

### 1.4 Publish Case Studies [human]

- [ ] 1.4.1 Post to Discord (via discord-content skill)
- [ ] 1.4.2 Post to Twitter/X
- [ ] 1.4.3 Post to IndieHackers
- [ ] 1.4.4 Post to Claude Code Discord
- [ ] 1.4.5 Create inbound tracker at `knowledge-base/project/specs/feat-product-strategy/inbound-tracker.md`

## Phase 2: Interviews + Product Test (Weeks 2-5)

### 2.1 Recruit Founders [human]

- [ ] 2.1.1 Post recruitment messages across channels
- [ ] 2.1.2 Screen applicants (solo founder, uses AI, building product)
- [ ] 2.1.3 Confirm 10 participants (minimum 7) with scheduled times

### 2.2 Interview + Onboard [human] (blocked by: 1.1, 1.3)

- [ ] 2.2.1 Conduct interview 1-5 using standardized script
- [ ] 2.2.2 Code responses immediately after each interview
- [ ] 2.2.3 Guided onboarding for founders 1-5 (install, sync, one domain task)
- [ ] 2.2.4 Conduct interview 6-10
- [ ] 2.2.5 Code responses immediately after each interview
- [ ] 2.2.6 Guided onboarding for founders 6-10
- [ ] 2.2.7 Have second person review response coding for consistency

### 2.3 Monitor Unassisted Usage [human]

- [ ] 2.3.1 Weekly check-in calls (15 min each) -- note domains used
- [ ] 2.3.2 Track which domains mentioned unprompted (non-guided)
- [ ] 2.3.3 Track confusion points and breakage reports

## Phase 3: Debrief + Decision (Weeks 5-6)

### 3.1 Debrief Interviews [human] (blocked by: 2.3)

- [ ] 3.1.1 Conduct debrief interviews with all participants (3 questions, 15 min)
- [ ] 3.1.2 Record WTP (exact dollar, not anchored)
- [ ] 3.1.3 Record churn resilience ("what would you miss?")

### 3.2 Gate Assessment [human]

- [ ] 3.2.1 Compile G1: count founders with independent multi-domain pain (>= 3 intensity)
- [ ] 3.2.2 Compile G2: count founders with unprompted non-guided domain use
- [ ] 3.2.3 Compile G3: count founders with WTP >= $25/month
- [ ] 3.2.4 Check G4: any Cowork CaaS threat during weeks 1-6?
- [ ] 3.2.5 Write gate assessment to `knowledge-base/project/specs/feat-product-strategy/gate-assessment.md`
- [ ] 3.2.6 Make decision: proceed / iterate / pivot

## Separate: Blog Infrastructure [auto] -- DONE

Merged from main (built in separate PRs). Case studies migrated 2026-03-10.

- [x] S.1 Create `plugins/soleur/docs/pages/blog/` directory and listing page
- [x] S.2 Add blog to nav configuration
- [x] S.3 Set up post template with frontmatter (title, date, description, tags)
- [x] S.4 Migrate case studies to blog posts
