---
title: "feat: Add LinkedIn secrets to scheduled community monitor workflow"
type: feat
date: 2026-03-14
---

# feat: Add LinkedIn secrets to scheduled community monitor workflow

## Overview

Wire LinkedIn credentials into `.github/workflows/scheduled-community-monitor.yml` so the community monitor agent can detect LinkedIn as an enabled platform and collect data via the LinkedIn API scripts. This is the final integration step that connects the existing `linkedin-community.sh` and `linkedin-setup.sh` scripts (#589, merged as #608) to the daily scheduled workflow.

Related: #592, #138 (parent), #589 (LinkedIn API scripts, closed), #608 (scripts PR, merged)

## Problem Statement / Motivation

The LinkedIn API scripts (`linkedin-community.sh`, `linkedin-setup.sh`) are merged and the community-router already has LinkedIn registered with `LINKEDIN_ACCESS_TOKEN,LINKEDIN_PERSON_URN` as required env vars. However, the scheduled workflow does not pass these secrets as environment variables to the Claude Code Action step, so the community-router reports LinkedIn as `disabled` during scheduled runs. The agent prompt also has no instructions for LinkedIn data collection.

## Proposed Solution

Two changes in one file (`.github/workflows/scheduled-community-monitor.yml`):

1. **Add LinkedIn secrets to the `env:` block** of the "Run community monitor" step
2. **Add LinkedIn data collection instructions** to the agent prompt's Step 2 collection section

### Change 1: Secrets (`scheduled-community-monitor.yml` env block)

Add after the X/Twitter secrets block:

```yaml
          LINKEDIN_ACCESS_TOKEN: ${{ secrets.LINKEDIN_ACCESS_TOKEN }}
          LINKEDIN_PERSON_URN: ${{ secrets.LINKEDIN_PERSON_URN }}
```

**Variable name correction:** Issue #592 specifies `LINKEDIN_ORGANIZATION_ID` but the actual scripts (`linkedin-community.sh`, `community-router.sh`) require `LINKEDIN_PERSON_URN`. The organization ID is not used by any existing script. This plan uses the correct variable names matching the implemented code.

### Change 2: Agent prompt instructions

Add a LinkedIn bullet to the Step 2 data collection section, following the pattern of the X/Twitter entry:

```text
              - LinkedIn (if enabled): $ROUTER linkedin post-content is available but
                do NOT post during monitoring runs. fetch-metrics and fetch-activity
                require Marketing API approval and will exit with an error message --
                skip them gracefully. Log LinkedIn as "enabled (posting only)" in the
                digest platform status.
```

**Why not call fetch-metrics/fetch-activity?** Both commands currently exit with error messages explaining Marketing API (MDP) approval is required. The agent should not waste turns calling stubs that will fail. This mirrors the X/Twitter pattern where `fetch-mentions` and `fetch-timeline` are explicitly excluded (Free tier 403).

## Technical Considerations

### Graceful degradation when secrets are not configured

If `LINKEDIN_ACCESS_TOKEN` or `LINKEDIN_PERSON_URN` are not set in GitHub Secrets, the community-router `platforms` command will report LinkedIn as `disabled`. The agent prompt already handles this: Step 1 checks which platforms are enabled/disabled, and Step 2 only collects data from enabled platforms. No code change needed for this case.

### No posting during monitoring runs

The agent's job is to collect data and generate digests, not to post content. The prompt must explicitly prohibit calling `post-content` during monitoring. This prevents accidental autonomous posting, consistent with the workflow's documented principle: "No autonomous posting -- human approval preserved."

### Token TTL awareness

LinkedIn access tokens expire after 60 days. When the token expires, `linkedin-community.sh` returns a clear 401 error message directing the user to `linkedin-setup.sh`. The agent should log this gracefully in the digest rather than treating it as a workflow failure.

### Security model

Same pattern as Discord and X/Twitter: secrets are stored in GitHub repository settings and injected via `${{ secrets.* }}` expressions. Secrets are never logged or interpolated into shell commands (matching the workflow's security comment on lines 10-12).

## Acceptance Criteria

- [ ] `LINKEDIN_ACCESS_TOKEN` secret is passed to the "Run community monitor" step env block (`.github/workflows/scheduled-community-monitor.yml`)
- [ ] `LINKEDIN_PERSON_URN` secret is passed to the "Run community monitor" step env block
- [ ] Agent prompt Step 2 includes LinkedIn data collection instructions with no-post guard
- [ ] Agent prompt LinkedIn instructions handle fetch-metrics/fetch-activity stubs gracefully (skip, don't call)
- [ ] When LinkedIn secrets are not configured, the workflow still succeeds (LinkedIn reported as disabled)

## Test Scenarios

- Given `LINKEDIN_ACCESS_TOKEN` and `LINKEDIN_PERSON_URN` are set in GitHub Secrets, when the scheduled workflow runs, then community-router reports LinkedIn as `enabled`
- Given LinkedIn secrets are NOT set in GitHub Secrets, when the scheduled workflow runs, then community-router reports LinkedIn as `disabled` and the digest is generated without LinkedIn data
- Given LinkedIn token has expired (401 from API), when the workflow runs, then the agent logs the expiry gracefully and continues with other platforms
- Given the monitoring workflow runs with LinkedIn enabled, then the agent does NOT call `post-content` (no autonomous posting)

## Context

The scheduled community monitor runs daily at 08:00 UTC. It uses the community-router for platform detection, which checks env vars to determine enabled/disabled status. LinkedIn is the 5th platform added (after Discord, GitHub, X, HN; Bluesky script exists but is not yet in the workflow).

## MVP

### `.github/workflows/scheduled-community-monitor.yml`

```yaml
      - name: Run community monitor
        uses: anthropics/claude-code-action@1dd74842e568f373608605d9e45c9e854f65f543 # v1.0.63
        env:
          DISCORD_BOT_TOKEN: ${{ secrets.DISCORD_BOT_TOKEN }}
          DISCORD_GUILD_ID: ${{ secrets.DISCORD_GUILD_ID }}
          DISCORD_WEBHOOK_URL: ${{ secrets.DISCORD_WEBHOOK_URL }}
          X_API_KEY: ${{ secrets.X_API_KEY }}
          X_API_SECRET: ${{ secrets.X_API_SECRET }}
          X_ACCESS_TOKEN: ${{ secrets.X_ACCESS_TOKEN }}
          X_ACCESS_TOKEN_SECRET: ${{ secrets.X_ACCESS_TOKEN_SECRET }}
          LINKEDIN_ACCESS_TOKEN: ${{ secrets.LINKEDIN_ACCESS_TOKEN }}
          LINKEDIN_PERSON_URN: ${{ secrets.LINKEDIN_PERSON_URN }}
```

Agent prompt Step 2 addition:

```text
              - LinkedIn (if enabled): $ROUTER linkedin post-content is available but
                do NOT post during monitoring runs. fetch-metrics and fetch-activity
                require Marketing API approval and will exit with an error message --
                skip them gracefully. Log LinkedIn as "enabled (posting only)" in the
                digest platform status.
```

## References

- Pattern: existing Discord/X secret handling in `scheduled-community-monitor.yml` (lines 49-55)
- `plugins/soleur/skills/community/scripts/community-router.sh:16` -- LinkedIn platform registry entry
- `plugins/soleur/skills/community/scripts/linkedin-community.sh` -- Script requiring `LINKEDIN_ACCESS_TOKEN`, `LINKEDIN_PERSON_URN`
- `plugins/soleur/skills/community/scripts/linkedin-setup.sh` -- Credential validation and token generation
- Issue #592: feat: Scheduled workflow LinkedIn secrets
- Issue #589 / PR #608: LinkedIn API scripts (merged)
- Issue #138: Parent LinkedIn Presence tracking issue
- Learning: `knowledge-base/learnings/2026-03-13-platform-integration-scope-calibration.md` -- keep scope tight, match what can be validated on day one
