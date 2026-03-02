---
feature: document-cadence-enforcement
branch: feat-document-cadence
created: 2026-03-02
---

# Tasks: Document Cadence Enforcement

- [x] 1. Rewrite `review-reminder.yml`: replace `next_review` with `last_reviewed` + `review_cadence`, widen scan to `knowledge-base/`, fix overdue skip bug, use path-based slugs, update issue body template
- [x] 2. Migrate 3 existing `next_review` files to new model (see migration table in plan)
- [x] 3. Add `last_reviewed` + `review_cadence` frontmatter to 3 strategic docs (brand-guide, business-validation, constitution)
- [ ] 4. Verify with `workflow_dispatch` + `date_override`
