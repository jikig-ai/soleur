---
status: draft
branch: feat-social-distribute
pr: 457
---

# Social Distribution Workflow Spec

## Problem Statement

Blog content is published to soleur.ai but never distributed to social channels. The marketing strategy describes distribution as a step, but no executable workflow, skill, or automation exists. The first article ("What Is Company-as-a-Service?") shipped 2026-03-05 with zero social distribution.

## Goals

- G1: Every published article gets distributed to all relevant social channels within 24 hours of publish
- G2: Platform-specific content variants are generated automatically, respecting each channel's voice, format, and constraints
- G3: Channels with API access (Discord, X/Twitter) receive automated posts with user approval
- G4: Channels without API access (IndieHackers, Reddit, HN) receive formatted text ready for copy-paste

## Non-Goals

- Engagement monitoring or analytics (future iteration)
- Scheduled posting / delayed publishing
- Auto-posting without user approval
- Email newsletter distribution
- Paid promotion or boosting

## Functional Requirements

- FR1: Skill reads a published blog article by file path
- FR2: Skill reads brand guide channel notes for platform-specific voice guidance
- FR3: Skill generates content variants for: X/Twitter thread, Discord announcement, IndieHackers update, Reddit post, HN submission title
- FR4: Skill posts to Discord via existing webhook with user approval
- FR5: Skill posts to X/Twitter via API with user approval (graceful degradation to text output when no API keys configured)
- FR6: Skill outputs formatted markdown for manual platforms
- FR7: Brand guide includes channel notes for X/Twitter, IndieHackers, Reddit, and Hacker News

## Technical Requirements

- TR1: Skill follows discord-content approval pattern (generate, validate brand voice, present for approval, post)
- TR2: X/Twitter integration uses API v2 (requires developer account + OAuth)
- TR3: API credentials stored in .env (not committed)
- TR4: Skill degrades gracefully when API credentials are missing -- outputs text instead of posting
- TR5: Post-publish distribution checklist exists as knowledge-base reference document

## Acceptance Criteria

- [ ] Running `/soleur:social-distribute` with a blog post path generates variants for all 5 platforms
- [ ] Discord post is sent via webhook after approval
- [ ] X/Twitter thread is posted via API after approval (or text output if no keys)
- [ ] Manual platform output is formatted and ready for copy-paste
- [ ] Brand guide has channel notes for all social platforms
- [ ] Post-publish checklist document exists
- [ ] CaaS blog article inaccuracies are fixed before distribution
