# Learning: Workflow Platform Addition Pattern

## Problem

Adding a new platform (LinkedIn) to the scheduled community monitor workflow required identifying every touchpoint in the workflow YAML and coordinating changes across them. The GitHub issue (#592) referenced `LINKEDIN_ORGANIZATION_ID` as the required secret, but the actual scripts use `LINKEDIN_PERSON_URN` -- blindly following the issue text would have injected a variable nothing consumes.

## Solution

The checklist for adding a platform to `scheduled-community-monitor.yml` has four touchpoints:

1. **Secrets in env block** (lines ~49-58) -- Add `SECRET_NAME: ${{ secrets.SECRET_NAME }}` entries for every env var the platform's scripts expect. Verify variable names against the community-router registry (`community-router.sh` PLATFORMS array), not against the issue text.
2. **Agent prompt Step 2** ("Collect data") -- Add a bullet for the new platform with explicit instructions. For platforms without full API integration, include a no-post/no-fetch guard (e.g., `Do NOT post or fetch data -- log as "enabled (posting only)" and skip`). Keep it concise -- the platform scripts self-document their own failures, so verbose error handling in the prompt is redundant.
3. **Digest section in Step 4** ("Generate digest") -- Add the platform's section heading to the optional sections list (e.g., `## LinkedIn Activity`). Name it based on what data is actually available -- "Activity" not "Metrics" when metrics don't exist yet.
4. **File header comment** (line 1-8) -- Update the comment block to mention the new platform so developers scanning the file see it immediately.

## Key Insight

Issue text decays. When an issue is filed as a deferred scope item (in this case, #592 was filed during the LinkedIn scope calibration in #588), the variable names and implementation details may reflect the plan at filing time, not the code as it evolved. **Always verify secret/variable names against the actual scripts and router registry before implementing.** `LINKEDIN_ORGANIZATION_ID` was in the issue; `LINKEDIN_PERSON_URN` was in the code. The issue was the source of intent, the code was the source of truth.

A secondary lesson: prompt instructions for CI agents should be compressed. The initial draft had 5 lines of defensive instructions for LinkedIn; review reduced it to 2 lines. The scripts already handle errors and print diagnostics -- the prompt only needs to convey intent (skip vs. collect vs. post) and any hard constraints (no-post guard).

## Session Errors

1. **Ralph-loop setup script path** -- The session initially referenced `./plugins/soleur/skills/one-shot/scripts/setup-ralph-loop.sh` which does not exist. The correct path is `./plugins/soleur/scripts/setup-ralph-loop.sh`. This matches the general pattern: scripts live under `plugins/soleur/scripts/`, not nested under individual skill directories, unless they are skill-specific. When a plan prescribes a relative path, trace it before executing (per AGENTS.md hard rule).

## Tags
category: integration-issues
module: community-monitor
issue: 592
related:
  - knowledge-base/learnings/2026-03-13-platform-integration-scope-calibration.md
  - knowledge-base/learnings/2026-03-13-community-router-deduplication.md
