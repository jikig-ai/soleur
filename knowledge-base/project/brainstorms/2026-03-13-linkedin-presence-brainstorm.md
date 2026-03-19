# Brainstorm: Extend Community Agent with LinkedIn Presence

**Date:** 2026-03-13
**Issue:** #138
**Branch:** feat/linkedin-presence
**Status:** Complete

## What We're Building

Add LinkedIn as the 4th supported platform in the community ecosystem. This includes:

- **Content creation** via `social-distribute`: generate two LinkedIn post variants per piece of content — one for the company page (official announcement) and one for the founder's personal profile (thought-leadership reflection)
- **Monitoring/analytics** via `community-manager`: collect LinkedIn metrics (impressions, engagement, followers) and surface them in community digests
- **Hybrid API approach**: manual posting workflow with API stubs in `linkedin-community.sh` that activate once LinkedIn API credentials are provisioned
- **Brand guide update**: add `### LinkedIn` Channel Notes with platform-specific voice guidance (thought leadership, case studies, reflective posts)
- **Docs site update**: add LinkedIn company page card to community.njk

## Why This Approach

LinkedIn is the #1 platform for B2B developer tools marketing. Engineering managers, team leads, and technical decision-makers are more reachable on LinkedIn than any other platform for purchase decisions. The "building a company with AI agents" narrative maps directly to LinkedIn's algorithm preferences for case studies and reflective posts.

We chose the full-stack approach (content creation + monitoring in one PR) because LinkedIn's primary value is content publishing, not monitoring. A monitoring-only PR would ship low value.

The hybrid API approach (manual posting + API stubs) mirrors what worked for X/Twitter — ship immediately without waiting for LinkedIn's API approval process (which can take weeks), then upgrade to full automation when credentials arrive.

## Key Decisions

1. **Both company page AND personal profile from the start.** Company pages get 2-5% organic reach; personal profiles get 10-15x more. The standard B2B playbook is both: founder posts thought leadership from personal profile, company page gets the official version. `social-distribute` generates two LinkedIn variants per content piece.

2. **social-distribute owns content creation, community-manager owns monitoring.** Clean separation matching existing architecture. social-distribute generates LinkedIn post variants (company page + personal profile). community-manager handles analytics collection and surfaces LinkedIn metrics in digests. No comment engagement in v1.

3. **Hybrid API approach.** Build `linkedin-community.sh` with API stubs that activate when `LINKEDIN_ACCESS_TOKEN` is set. Until then, social-distribute generates content that the user copies to LinkedIn manually. Same pattern X used with Free tier limitations.

4. **Adapter interface (#470) deferred to a separate PR.** LinkedIn ships as an independent script like X did. A follow-up PR handles the adapter refactor that standardizes all 4+ platforms. Keeps scope tight.

5. **Monitoring only for v1 engagement.** Community agent collects LinkedIn analytics and surfaces them in digests. No automated comment engagement. Can be added once the platform is established.

6. **No brainstorm routing changes needed.** The existing CCO routing via "community engagement" assessment question already covers LinkedIn. Confirmed by both CCO assessment and repo research.

7. **Tuesday-Thursday morning posting cadence.** Codified in social-distribute's LinkedIn guidance and content-publisher scheduling. Thought leadership, case studies, and reflective posts outperform promotional content.

## Open Questions

1. **LinkedIn company page URL** — needs to be created manually (browser-only OAuth consent). Once created, add to `site.json` and `community.njk`.
2. **LinkedIn API App approval timeline** — apply for Marketing API access in parallel. The hybrid approach means this doesn't block shipping.
3. **Content-publisher LinkedIn scheduling** — should the scheduler enforce Tuesday-Thursday constraints programmatically, or is it a guideline for the operator?

## Domain Leader Assessments

### CMO Assessment
- Brand guide exists but needs `### LinkedIn` Channel Notes added
- LinkedIn content differs fundamentally from X (long-form thought leadership vs. 280-char brevity)
- Company page + personal profile is the correct dual-surface strategy
- Cross-platform content repurposing via social-distribute is incremental once LinkedIn variant format is defined
- "Building a company with AI agents" is a high-interest LinkedIn narrative

### CCO Assessment
- Community skill needs LinkedIn row in platform detection table
- community-manager needs LinkedIn in Capabilities 1 (Digest), 2 (Health), 3 (Content Suggestions)
- Digest file contract needs optional `## LinkedIn Metrics` heading
- LinkedIn credential management needs attention (60-day refresh tokens vs. X's long-lived tokens)
- Content publisher needs `linkedin` in `channel_to_section()` case statement

## Scope Summary

### In Scope
- `linkedin-community.sh` script with hybrid API stubs
- `social-distribute` LinkedIn variants (company page + personal profile)
- `community-manager` LinkedIn monitoring/analytics in digests
- Brand guide `### LinkedIn` Channel Notes
- `content-publisher.sh` LinkedIn channel support
- `site.json` + `community.njk` LinkedIn card (placeholder URL until page created)
- Scheduled workflow LinkedIn env vars
- `linkedin-setup.sh` credential validation script

### Out of Scope
- Platform adapter interface refactor (#470 — separate PR)
- LinkedIn comment engagement (v1 is monitoring only)
- LinkedIn API App approval (parallel manual process)
- LinkedIn company page creation (manual browser action)
