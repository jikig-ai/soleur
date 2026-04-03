---
category: workflow-issues
module: marketing-content-pipeline
severity: medium
tags: [content-publishing, cadence, cloud-migration, campaign-calendar, scheduled-tasks, content-strategy]
date: 2026-04-03
---

# Learning: Content cadence gap from campaign expiry and Cloud task migration

## Problem

Content publishing stopped for 12 days (March 21 to April 3). Two manually planned distribution files (Vibe Coding, PWA Milestone) were overdue. Two auto-generated files (Paperclip comparison, Repo Connection launch) were created by the content generator but stuck in `draft` status with empty `publish_date`, so the content publisher never picked them up.

Three compounding root causes:

1. **Campaign-bounded cadence:** The 2x/week Tue/Thu cadence was defined in `case-study-distribution-plan.md` as a 3-week campaign (March 12-30). When the campaign ended, no perpetual cadence replaced it.
2. **Cloud task migration dropped a critical instruction:** PR #1095 (March 25) migrated the content generator from a GHA workflow to a Cloud scheduled task. The GHA prompt included "After the distribution file is created, ensure its frontmatter has: publish_date, status: scheduled." The Cloud task prompt omitted this instruction. Generated articles were left as `status: draft` with empty `publish_date`.
3. **No overdue detection:** The campaign calendar workflow refreshed the calendar view weekly but never checked for overdue items or updated the content-strategy review date.

## Solution

1. **Perpetual cadence defined in content-strategy.md** -- Added a "Publishing Cadence" section establishing 2x/week Tue/Thu as an ongoing cadence independent of any campaign. Changed `review_cadence` from quarterly to weekly.
2. **Cloud task prompt corrected** -- Updated the Cloud scheduled task to include the missing frontmatter instruction.
3. **Campaign calendar workflow extended** -- Added overdue detection (creates GitHub issues for past-due items) and weekly content-strategy review date update.
4. **Backlog cleared** -- Rescheduled 4 overdue distribution files: Vibe Coding (Apr 7), PWA (Apr 10), Paperclip (Apr 15), Repo Connection (Apr 17).
5. **Campaign marked completed** -- Added post-campaign note in case-study-distribution-plan.md confirming Tue/Thu cadence is now perpetual.

## Key Insight

When migrating functionality between systems (GHA workflows to Cloud tasks), prompt content must be diffed line-by-line against the original. Rewriting from memory drops instructions that seem implicit but are critical. Additionally, any time-bounded campaign must define its succession -- either a replacement campaign or explicit adoption into a perpetual cadence. A campaign that ends without a successor creates a silent publishing gap that no one notices until the founder asks "why didn't we publish yesterday?"

## Prevention

1. **Migration prompt-diff checklist:** When migrating prompts between systems, extract and diff both prompts line-by-line. Every removed line must be justified as intentional or restored.
2. **End-of-campaign succession rule:** Campaign definitions must specify what happens after they end -- successor campaign or perpetual cadence adoption.
3. **Automated overdue detection:** The weekly campaign calendar workflow now flags overdue content via GitHub issues with `action-required` label.
4. **Post-migration output verification:** After migrating a scheduled task, run it once and compare output artifacts against a known-good baseline.

## Related

- PR #1095: Cloud task migration that dropped the frontmatter instruction
- Issue #1094: Parent migration tracking issue
- Learning: `2026-03-24-content-generator-pipeline-learnings.md`
- Learning: `2026-03-16-scheduled-skill-wrapping-pattern.md`
- Learning: `2026-03-23-strategy-review-cadence-system.md`

## Tags

category: workflow-issues
module: marketing-content-pipeline
