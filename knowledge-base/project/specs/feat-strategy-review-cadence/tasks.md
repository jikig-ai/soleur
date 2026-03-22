---
feature: strategy-review-cadence
issue: 1005
status: ready
created: 2026-03-22
---

# Tasks: Strategy Document Review Cadence

## Phase 1: Frontmatter Schema Migration

- [ ] 1.1 Define canonical frontmatter schema (5 fields: last_updated, last_reviewed, review_cadence, owner, depends_on)
- [ ] 1.2 Audit all .md files in knowledge-base/{product,marketing,sales}/ for current frontmatter state
- [ ] 1.3 Add/update frontmatter on product docs (business-validation, competitive-intelligence, roadmap, pricing-strategy)
- [ ] 1.4 Add/update frontmatter on marketing docs (brand-guide, marketing-strategy, content-strategy, campaign-calendar, case-study-distribution-plan, seo-refresh-queue, validation-outreach-template)
- [ ] 1.5 Add/update frontmatter on sales battlecards (6 files — add owner: CRO)
- [ ] 1.6 Commit: "chore: standardize frontmatter across strategy documents"

## Phase 2: Scheduled Strategy Review Workflow

- [ ] 2.1 Create `scripts/strategy-review-check.sh` with frontmatter parsing and staleness detection
  - [ ] 2.1.1 Reuse awk counter pattern from content-publisher.sh
  - [ ] 2.1.2 Implement cadence-to-days mapping (monthly=30, quarterly=90)
  - [ ] 2.1.3 Implement dedup check (skip if open issue already exists for doc)
  - [ ] 2.1.4 Apply overdue-document-skip bug fix (never skip negative days_until)
- [ ] 2.2 Create `.github/workflows/scheduled-strategy-review.yml`
  - [ ] 2.2.1 Cron: Monday 08:00 UTC + workflow_dispatch
  - [ ] 2.2.2 Label pre-creation step
  - [ ] 2.2.3 Discord failure notification
- [ ] 2.3 Commit: "feat: add scheduled strategy review workflow"

## Phase 3: Business Validation Update

- [ ] 3.1 Read full business-validation.md
- [ ] 3.2 Add user research finding to Demand Evidence section (5+ conversations, 3 themes)
- [ ] 3.3 Update Gate 2 (Customer): re-evaluate beachhead assumption
- [ ] 3.4 Update Gate 3 (Competitive): note delivery format competitive shift
- [ ] 3.5 Update Gate 4 (Demand Evidence): upgrade from 1-2 to 5+ conversations
- [ ] 3.6 Update Gate 5 (Business Model): flag cost structure implication
- [ ] 3.7 Update Gate 6 (Minimum Viable Scope): breadth validated, delivery challenged
- [ ] 3.8 Update verdict commentary: two-dimensional pivot (thesis + delivery format)
- [ ] 3.9 Update frontmatter: last_updated=2026-03-22, last_reviewed=2026-03-22
- [ ] 3.10 Commit: "docs(product): update business validation with user research"

## Phase 4: Cascade Review

- [ ] 4.1 Spawn CPO agent to review: roadmap.md, pricing-strategy.md, competitive-intelligence.md
- [ ] 4.2 Spawn CMO agent to review: brand-guide.md, marketing-strategy.md, content-strategy.md
- [ ] 4.3 Both agents run in parallel, each updates last_reviewed/last_updated
- [ ] 4.4 Review agent outputs for consistency
- [ ] 4.5 Commit: "docs: cascade strategy review after validation update"

## Phase 5: Verification

- [ ] 5.1 Run strategy-review-check.sh locally to verify no false positives/negatives
- [ ] 5.2 Verify all frontmatter fields are parseable
- [ ] 5.3 Ship PR via /soleur:ship
- [ ] 5.4 After merge: `gh workflow run scheduled-strategy-review.yml` and verify
