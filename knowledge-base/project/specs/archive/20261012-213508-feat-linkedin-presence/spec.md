# Feature: LinkedIn Presence

## Problem Statement

Soleur has no LinkedIn presence despite LinkedIn being the #1 platform for B2B developer tools marketing. The community agent supports Discord, GitHub, and X/Twitter, but engineering managers and technical decision-makers — key ICP segments — are most reachable on LinkedIn. The social-distribute skill generates content variants for 5 platforms but not LinkedIn.

## Goals

- Add LinkedIn as the 4th platform in the community ecosystem (content creation + monitoring)
- Generate two LinkedIn post variants per content piece: company page (official) and personal profile (thought leadership)
- Collect LinkedIn analytics and surface them in community digests
- Ship with a hybrid API approach: manual posting with API stubs that activate when credentials arrive
- Update brand guide with LinkedIn Channel Notes

## Non-Goals

- Platform adapter interface refactor (tracked separately in #470)
- LinkedIn comment engagement (v1 is monitoring only)
- LinkedIn API App approval process (parallel manual workstream)
- LinkedIn company page creation (manual browser action)

## Functional Requirements

### FR1: LinkedIn Content Generation (social-distribute)

Generate two LinkedIn post variants per content piece:

- **Company page variant**: official announcement tone, links to full content, professional framing
- **Personal profile variant**: thought-leadership reflection, founder voice, case study / lessons-learned framing
- Character limits: up to 3,000 characters; aim for 1,300 for optimal visibility
- Posting cadence guidance: Tuesday-Thursday mornings

### FR2: LinkedIn Monitoring (community-manager)

Collect LinkedIn metrics and include them in community digests:

- Follower count, impressions, engagement rate
- Optional `## LinkedIn Metrics` heading in digest file contract
- Platform detection via `LINKEDIN_ACCESS_TOKEN` environment variable

### FR3: Hybrid API Script (linkedin-community.sh)

Shell script following the pattern of `x-community.sh`:

- `fetch-metrics`: returns LinkedIn page analytics (stubbed until API credentials available)
- `fetch-activity`: returns recent post engagement (stubbed)
- Manual mode: outputs guidance for manual metric collection when no credentials
- LinkedIn OAuth 2.0 with 60-day refresh token handling

### FR4: Credential Setup (linkedin-setup.sh)

Credential validation script following `x-setup.sh` pattern:

- Validate required env vars: `LINKEDIN_ACCESS_TOKEN`, `LINKEDIN_ORGANIZATION_ID`
- Test API connectivity
- Report token expiry status (60-day refresh tokens)

### FR5: Brand Guide LinkedIn Channel Notes

Add `### LinkedIn` section under `## Channel Notes` in `knowledge-base/marketing/brand-guide.md`:

- Thought leadership, case studies, reflective posts
- Professional but authentic tone (distinct from X's brevity)
- Tuesday-Thursday morning cadence
- Dual-surface guidance (company page vs. personal profile)

### FR6: Content Publisher LinkedIn Support

Add `linkedin` to `content-publisher.sh`:

- `channel_to_section()` case statement for LinkedIn
- LinkedIn publishing logic (manual copy guidance until API available)

### FR7: Docs Site LinkedIn Card

- Add `linkedin` key to `site.json` (placeholder URL until company page created)
- Add LinkedIn card to `community.njk` following Discord/X/GitHub card pattern

## Technical Requirements

### TR1: Script Pattern Conformance

`linkedin-community.sh` must follow the established pattern:

- Same argument interface as `x-community.sh` and `discord-community.sh`
- `set -euo pipefail` header
- Exit codes: 0 success, 1 missing credentials, 2 API error

### TR2: Platform Detection

Add LinkedIn to the community skill's platform detection table:

- Required env vars: `LINKEDIN_ACCESS_TOKEN`
- Optional env vars: `LINKEDIN_ORGANIZATION_ID` (for company page)

### TR3: Scheduled Workflow

Update `.github/workflows/scheduled-community-monitor.yml`:

- Add LinkedIn env vars to secrets section
- Add LinkedIn data collection to prompt instructions

### TR4: No Adapter Refactor

LinkedIn ships as an independent script. The adapter interface (#470) is a separate follow-up PR.
