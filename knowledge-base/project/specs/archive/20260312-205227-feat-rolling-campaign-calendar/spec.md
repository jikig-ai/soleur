# Feature: Rolling Campaign Calendar

## Problem Statement

The current content distribution plan (`knowledge-base/marketing/content-strategy.md`) is a fixed document that expires March 30, 2026. It has no mechanism to roll forward, can't reflect real-time status changes from the content publisher, and doesn't surface capacity constraints — a failure mode that caused a prior 15-piece plan to go 100% unexecuted.

## Goals

- Provide a bird's-eye view of all content distributions (upcoming, published, draft)
- Derive calendar data from `distribution-content/` frontmatter so it's always in sync
- Surface per-week capacity to prevent overcommitment
- Include CMO strategy notes (what's working, gaps, recommendations)
- Run on a schedule (twice weekly) via GitHub Actions without manual intervention

## Non-Goals

- Replacing the strategic content-strategy.md in `knowledge-base/overview/` (that document stays)
- Forward-looking content planning beyond what exists as distribution-content/ files (open question from brainstorm)
- Archiving the old content-strategy.md (deferred to separate cleanup)
- Modifying the content-publisher.sh or its frontmatter schema

## Functional Requirements

### FR1: Data Table Generation

Scan `knowledge-base/marketing/distribution-content/*.md`, parse frontmatter (`title`, `type`, `publish_date`, `channels`, `status`), and produce a markdown table grouped by status: upcoming (scheduled), published, and draft.

### FR2: Capacity View

Generate a per-week summary showing how many content pieces are scheduled. Flag weeks that appear overcommitted.

### FR3: CMO Strategy Notes

Invoke the CMO agent to analyze the calendar data and append strategy commentary: what's working, content gaps, and recommendations for next content.

### FR4: Scheduled Refresh

GitHub Actions workflow triggers twice weekly (Monday and Thursday) invoking the `soleur:campaign-calendar` skill. Updated calendar is committed and pushed to main.

### FR5: Manual Invocation

The skill is also invocable manually via `/soleur:campaign-calendar` for on-demand refresh.

## Technical Requirements

### TR1: Skill Architecture

Implement as a dedicated Soleur skill at `plugins/soleur/skills/campaign-calendar/`. Follows existing skill conventions (SKILL.md frontmatter, scripts/ directory).

### TR2: Frontmatter Parsing

Reuse the proven `parse_frontmatter()` / `get_frontmatter_field()` pattern from `scripts/content-publisher.sh` or implement equivalent logic. Must handle the existing 5-field schema without modification.

### TR3: GitHub Actions Workflow

Create `.github/workflows/scheduled-campaign-calendar.yml` with cron schedule for Monday and Thursday. Use direct push (not PR) following the pattern established by `scheduled-content-publisher.yml`. Guard against empty commits with `git diff --cached --quiet`.

### TR4: Output Location

Generated calendar lives at `knowledge-base/marketing/campaign-calendar.md` with living-document frontmatter (`last_updated`, `last_reviewed`, `review_cadence`, `depends_on`).
