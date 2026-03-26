---
title: "feat: enforce milestone assignment on all issue creation surfaces"
type: feat
date: 2026-03-26
---

# feat: Enforce Milestone Assignment on All Issue Creation Surfaces

## Problem

GitHub issues are created across 17 different surfaces (shell scripts, GitHub Actions workflows, skill instructions, and agent prompts) but **none** of them enforce milestone assignment at creation time. The only workflow that assigns milestones post-creation is the weekly growth audit, which uses a follow-up CPO agent step. This leaves most issues untracked against roadmap phases.

Currently 10 open issues have no milestone. The roadmap document (`knowledge-base/product/roadmap.md`) defines 6 milestones corresponding to product phases, but the issue creation pipelines do not reference them.

## Root Cause

No constitution rule, AGENTS.md gate, or skill instruction mandates milestone assignment when creating GitHub issues. The existing AGENTS.md rule about roadmap/milestone consistency (the "Workflow Gates" section) only applies when *moving* issues between milestones -- it does not require assignment at creation.

## Approach

### Strategy: Two-layer enforcement

1. **Convention layer (AGENTS.md rule):** Add a hard rule that all `gh issue create` invocations must include milestone assignment. This catches agent-prompted issue creation (the majority of surfaces).

2. **Implementation layer (code changes):** Update each concrete issue creation surface to include milestone assignment. For shell scripts and workflow `run:` blocks, add `--milestone` flag. For agent-prompted creation (claude-code-action prompts), update the prompt text to instruct milestone assignment.

### Milestone determination logic

Different surfaces create issues with different domain context. The milestone assignment strategy varies:

| Surface Type | Milestone Determination | Rationale |
|---|---|---|
| **Operational alerts** (token expiry, drift, review reminders) | Default to "Post-MVP / Later" unless the alert is P0/P1 | Operational issues are maintenance, not roadmap features |
| **Content/marketing** (content-publisher, growth-audit, SEO/AEO) | Default to "Post-MVP / Later" unless CPO overrides | Marketing issues are typically low-urgency improvements |
| **Agent-prompted** (roadmap-review, competitive-analysis, content-generator) | Agent reads `roadmap.md` and assigns based on phase fit | These agents already have roadmap context |
| **Skills** (plan, brainstorm, brand-workshop, validation-workshop) | CPO determines via domain review or user selects | Feature work requires product judgment |

### Key learning from #1080

`gh issue create --milestone` requires the milestone **title string**, not the integer number. The two-step pattern (create, then PATCH) is needed if using milestone numbers. For simplicity, use title strings in all surfaces.

## Surfaces to Modify

### Category 1: Shell scripts (direct `gh issue create` -- add `--milestone` flag)

- [ ] `scripts/content-publisher.sh` (line 452) -- add `--milestone "Post-MVP / Later"` (content publishing failures are maintenance)
- [ ] `scripts/strategy-review-check.sh` (line 145) -- add `--milestone "Post-MVP / Later"` (strategy review reminders are operational)

### Category 2: GitHub Actions workflows (direct `gh issue create` -- add `--milestone` flag)

- [ ] `.github/workflows/review-reminder.yml` (line 129) -- add `--milestone "Post-MVP / Later"` (review reminders are operational)
- [ ] `.github/workflows/scheduled-terraform-drift.yml` (line 180) -- add `--milestone "Post-MVP / Later"` (drift issues are infra maintenance)
- [ ] `.github/workflows/scheduled-linkedin-token-check.yml` (line 78) -- add `--milestone "Post-MVP / Later"` (token expiry is maintenance)
- [ ] `.github/workflows/scheduled-cf-token-expiry-check.yml` (line 121) -- add `--milestone "Post-MVP / Later"` (token expiry is maintenance)

### Category 3: GitHub Actions workflows (agent-prompted -- update prompt instructions)

- [ ] `.github/workflows/scheduled-roadmap-review.yml` -- update prompt to instruct: "When creating the summary issue, assign milestone 'Post-MVP / Later'. When creating tracking issues for inconsistencies, assign the milestone matching the roadmap phase."
- [ ] `.github/workflows/scheduled-content-generator.yml` -- update prompt to instruct: "When creating issues, include `--milestone 'Post-MVP / Later'`"
- [ ] `.github/workflows/scheduled-growth-audit.yml` -- already has CPO milestone assignment step; update to also assign milestones at creation time (agent creates tracking issues in Step 5.5 without milestones, then CPO assigns them in Step 6 -- move milestone assignment to creation time)
- [ ] `.github/workflows/scheduled-seo-aeo-audit.yml` -- update prompt to instruct milestone assignment
- [ ] `.github/workflows/scheduled-growth-execution.yml` -- update prompt to instruct milestone assignment
- [ ] `.github/workflows/scheduled-competitive-analysis.yml` -- update prompt to instruct milestone assignment

### Category 4: Skills (agent-executed -- update skill instructions)

- [ ] `plugins/soleur/skills/plan/SKILL.md` (line 476) -- update `gh issue create` example to include milestone selection. Add instruction: "After creating the issue, determine the correct milestone by reading `knowledge-base/product/roadmap.md` and assign with `gh issue edit <number> --milestone '<milestone title>'`." The two-step approach is necessary because the skill creates the issue body from a file and the milestone requires roadmap context.
- [ ] `plugins/soleur/skills/brainstorm/SKILL.md` (line 234) -- update issue creation to include milestone. Add instruction to read `roadmap.md` and select the appropriate milestone.
- [ ] `plugins/soleur/skills/brainstorm/references/brainstorm-brand-workshop.md` (line 11) -- update issue creation to include milestone
- [ ] `plugins/soleur/skills/brainstorm/references/brainstorm-validation-workshop.md` (line 13) -- update issue creation to include milestone

### Category 5: Constitution and AGENTS.md (governance)

- [ ] Add to `AGENTS.md` Hard Rules: "Every `gh issue create` invocation must include a `--milestone` flag. If the correct milestone is unclear, default to 'Post-MVP / Later' and the monthly roadmap review will re-triage. When creating feature-related issues (from plan, brainstorm, or work skills), read `knowledge-base/product/roadmap.md` to determine the correct milestone phase."
- [ ] Add to `knowledge-base/project/constitution.md` Architecture > Always: "GitHub Actions workflows and shell scripts that create issues must include `--milestone` -- issues without milestones are invisible to roadmap tracking; default to 'Post-MVP / Later' for operational/maintenance issues"

### Category 6: Fix existing un-milestoned issues

- [ ] Assign milestones to all 10 currently un-milestoned open issues (CPO determines correct milestone for each based on roadmap context)

## Acceptance Criteria

- [ ] All 17 issue creation surfaces include milestone assignment (either `--milestone` flag or prompt instruction)
- [ ] AGENTS.md contains a hard rule mandating milestone assignment on issue creation
- [ ] Constitution.md contains a convention for milestone assignment in workflows/scripts
- [ ] All currently un-milestoned open issues have been assigned milestones
- [ ] No regression: existing issue creation functionality works (labels, deduplication, body content)

## Domain Review

**Domains relevant:** Product

### Product/UX Gate

**Tier:** NONE
**Decision:** N/A

This plan modifies internal workflow tooling (shell scripts, CI workflows, skill instructions). No user-facing pages or UI components are affected. The CPO's involvement is as a domain expert for milestone assignment logic, not as a UX gate.

## Test Scenarios

- Given a content-publisher failure creates a fallback issue, when the issue is created, then it has milestone "Post-MVP / Later" assigned
- Given a terraform drift is detected, when the workflow creates an issue, then it has milestone "Post-MVP / Later" assigned
- Given a token expiry is detected (LinkedIn or Cloudflare), when the workflow creates an issue, then it has milestone "Post-MVP / Later" assigned
- Given a review reminder fires for overdue reviews, when issues are created, then each has milestone "Post-MVP / Later" assigned
- Given the growth audit agent creates tracking issues, when the CPO step runs, then each issue already has a milestone (not left blank for CPO to assign retroactively)
- Given the plan skill creates a GitHub issue, when the issue is created, then it has a milestone matching the roadmap phase for the feature
- Given the brainstorm skill creates a GitHub issue, when the issue is created, then it has a milestone matching the roadmap phase for the feature
- Given the monthly roadmap review runs, when it scans for un-milestoned issues, then it finds zero (enforcement prevents the gap)
- Given a milestone title is used with `--milestone`, when the milestone title matches an existing GitHub milestone, then the issue is created successfully
- Given a milestone title does not match any existing milestone (typo or renamed), when `gh issue create --milestone` runs, then the command fails visibly (not silently)

## Implementation Notes

### Milestone title strings

Use exact title strings from GitHub:

- `Phase 1: Close the Loop (Mobile-First, PWA)`
- `Phase 2: Secure for Beta`
- `Phase 3: Make it Sticky`
- `Phase 4: Validate + Scale`
- `Phase 5: Desktop Native App (Browser Automation)`
- `Post-MVP / Later`

### Two-step pattern for skills

For skills where the agent needs roadmap context to choose the right milestone, use the two-step pattern:

1. Create the issue first
2. Read `roadmap.md` to determine phase
3. `gh issue edit <number> --milestone '<milestone title>'`

This avoids the `--milestone 1` integer gotcha documented in `knowledge-base/project/learnings/2026-03-24-monthly-roadmap-review-process.md`.

### Default milestone rationale

"Post-MVP / Later" as the default for operational/maintenance issues is deliberate:

- It ensures every issue appears in milestone tracking
- Operational issues rarely block product phases
- The monthly roadmap review (`scheduled-roadmap-review.yml`) will re-triage and promote issues to earlier phases if needed
- Better to have an issue in the wrong milestone (visible, correctable) than in no milestone (invisible)
