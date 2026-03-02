# Document Cadence Enforcement

- **Date:** 2026-03-02
- **Status:** Decided
- **Participants:** User, Claude
- **Issue:** #334

## What We're Building

Extend the existing `review-reminder.yml` GitHub Actions workflow to enforce periodic review of strategic knowledge-base documents. Replace the fragile `next_review` fixed-date model with a `last_reviewed` + `review_cadence` abstraction that auto-computes staleness.

### Problem

Knowledge-base documents like `business-validation.md` are point-in-time snapshots with no mechanism to enforce review cadence. When they go stale, downstream agents (CPO, CMO, brainstorm) consume them as ground truth and propagate errors. The Cowork Plugins incident (2026-02-25 learning) proved this: the team discovered a competitive threat 22 days late because `business-validation.md` was never re-reviewed.

A `review-reminder.yml` workflow already exists and runs monthly, but has three gaps:
1. Only scans `knowledge-base/learnings/` (misses strategic docs)
2. Only 3 of ~237 files use `next_review`
3. No cadence abstraction -- fixed dates require manual computation

### Solution

1. New frontmatter model: `last_reviewed` + `review_cadence` (replaces `next_review`)
2. Widen workflow scan to all of `knowledge-base/` (opt-in via frontmatter presence)
3. Add frontmatter to strategic living docs
4. Migrate the 3 existing `next_review` files

## Why This Approach

### Rejected: New Soleur skill/agent
The issue proposed a dedicated `document-cadence` skill. We rejected this because the existing `review-reminder.yml` already does the heavy lifting (monthly cron, issue creation, label management). Adding a skill for 5-10 documents would be over-engineering. If interactive checking is needed later, a skill can be layered on top.

### Rejected: Support both next_review and last_reviewed
Maintaining two date models means two code paths in the workflow. With only 3 files using `next_review`, a clean migration is trivial. One model everywhere.

### Rejected: Hardcoded scan paths
Instead of listing specific files/directories in the workflow, we scan all of `knowledge-base/` and only act on files that have `review_cadence` frontmatter. This is opt-in -- authors decide what matters. No workflow edits needed to add new documents.

### Why last_reviewed + review_cadence over next_review
- `next_review` requires manual date computation after every review
- `review_cadence: quarterly` is self-documenting intent
- Reviewer just updates `last_reviewed` to today's date -- no date math
- Workflow computes `next_due = last_reviewed + cadence` automatically

## Key Decisions

1. **Mechanism:** Extend `review-reminder.yml`, no new skill
2. **Frontmatter model:** `last_reviewed` (date) + `review_cadence` (monthly|quarterly|biannual|annual)
3. **Scan scope:** All of `knowledge-base/`, opt-in via `review_cadence` frontmatter
4. **Target docs:** Strategic living docs (brand-guide.md, business-validation.md, constitution.md, competitive intelligence)
5. **Migration:** Replace `next_review` in 3 existing learnings files with new model
6. **Staleness threshold:** Issue created if `next_due` is within 7 days (past or upcoming), matching existing behavior

## Existing Infrastructure

| Component | Status | Role |
|-----------|--------|------|
| `review-reminder.yml` | Exists, needs extension | Monthly cron, issue creation, label management |
| `next_review` frontmatter | 3 files use it, migrating away | Being replaced by `last_reviewed` + `review_cadence` |
| `soleur:schedule` | Exists, not needed | Workflow already runs on cron |
| `compound-capture` | Exists, potential future integration | Could auto-set `review_cadence` on learnings (out of scope) |

## Open Questions

1. Should `compound-capture` auto-add `review_cadence` to new learnings? (Deferred -- scope creep for this issue)
2. Should the workflow auto-close stale review issues that have been resolved? (Deferred -- existing behavior is manual close)
3. Should the date field inconsistency (`updated` vs `last_updated`) be standardized as part of this? (Deferred -- separate cleanup)
