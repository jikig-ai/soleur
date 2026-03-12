---
last_updated: 2026-03-12
---

# Rolling Campaign Calendar Brainstorm

**Date:** 2026-03-12
**Issue:** #558
**Status:** Decided — ready for planning

## What We're Building

A rolling `campaign-calendar.md` at `knowledge-base/marketing/campaign-calendar.md` that provides a bird's-eye view of all content distributions — upcoming, published, and draft. The calendar is derived from scanning `knowledge-base/marketing/distribution-content/*.md` frontmatter and enriched with CMO agent strategy commentary.

Replaces the fixed "Case Study Distribution Plan" in `knowledge-base/marketing/content-strategy.md` (expires March 30, 2026). The old file is left in place for now and will be archived separately once the rolling calendar proves out.

## Why This Approach

**Problem:** The fixed distribution plan has a hard expiry date and no mechanism to roll forward. A prior 15-piece content plan went 100% unexecuted because overcommitment wasn't visible (learnings: `2026-03-03-cmo-orchestrated-strategy-review-pattern.md`). The current plan also can't reflect real-time status changes from the content publisher.

**Approach chosen:** Dedicated Soleur skill (`soleur:campaign-calendar`) triggered by GitHub Actions twice weekly (Mon + Thu). The skill scans distribution-content/ frontmatter, builds a data table with capacity view, then invokes the CMO agent for strategy notes.

**Why a dedicated skill over alternatives:**
- **vs. CMO agent enhancement:** The CMO is a strategic agent — making it do file scanning is a role mismatch. A skill keeps concerns separated and is independently testable.
- **vs. bash script + CMO overlay:** Two-step orchestration adds complexity for marginal reliability gain. A single skill can do both deterministic scanning and intelligent commentary.
- **Why not just a script:** The strategy notes and capacity analysis require CMO intelligence, not just data extraction.

## Key Decisions

1. **Maintenance model:** CMO agent-maintained via a dedicated Soleur skill, triggered on schedule by GitHub Actions (not during brainstorms/reviews).
2. **Content:** Data table (from frontmatter) + per-week capacity summary + CMO strategy notes (what's working, gaps, recommendations).
3. **Location:** `knowledge-base/marketing/campaign-calendar.md` — alongside distribution-content/ and content-strategy.md.
4. **Schedule:** Twice weekly (Monday and Thursday) via GitHub Actions cron.
5. **Frontmatter consumed:** `title`, `type`, `publish_date`, `channels`, `status` (the existing 5-field schema).
6. **Old file disposition:** `content-strategy.md` left in place, archived separately later.
7. **Architecture:** Dedicated `soleur:campaign-calendar` skill — invocable from both CI (scheduled) and manually (`/soleur:campaign-calendar`).

## Open Questions

1. Should the calendar include content ideas that don't yet have distribution-content/ files (forward-looking planning), or strictly reflect what exists on disk?
2. Should the GitHub Actions workflow commit + push the updated calendar directly to main (like content-publisher does), or open a PR for review?
3. What thresholds define "overcommitment" in the capacity view (e.g., >2 pieces/week)?
