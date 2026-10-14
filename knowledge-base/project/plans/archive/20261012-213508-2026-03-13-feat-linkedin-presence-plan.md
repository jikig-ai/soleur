---
title: "feat: Extend Community Agent with LinkedIn Presence"
type: feat
date: 2026-03-13
---

# feat: Extend Community Agent with LinkedIn Presence

[Updated 2026-03-13 — scope reduced after plan review: one variant, manual-only, no scripts/docs site/workflow changes]

## Overview

Add LinkedIn as a content generation target in `social-distribute` and register it as a known platform in the community ecosystem. LinkedIn is manual-only in v1 — content is generated for copy-paste, matching the pattern for IndieHackers, Reddit, and Hacker News. No API scripts, no automated publishing, no docs site card until the LinkedIn company page exists and API access is approved.

Related: #138, #96 (original community agent), #470 (adapter refactor — separate PR)

## Problem Statement / Motivation

LinkedIn is the #1 platform for B2B developer tools marketing. Engineering managers, team leads, and technical decision-makers are more reachable there than any other platform. Soleur has zero LinkedIn presence. The social-distribute skill generates variants for 5 platforms (Discord, X, IndieHackers, Reddit, HN) but not LinkedIn.

## Proposed Solution

Minimal LinkedIn integration focused on content generation:

1. **social-distribute** — Add Phase 5.6: one `## LinkedIn` variant per blog post (thought-leadership tone, usable from personal profile on day one)
2. **Brand guide** — Add `### LinkedIn` Channel Notes with platform-specific voice guidance
3. **community SKILL.md** — Add LinkedIn to platform detection table (registers the platform even though credentials won't be set yet)
4. **community-manager.md** — Update description to mention LinkedIn as a supported platform
5. **Content file template** — Include `## LinkedIn` section in generated content files for manual copy-paste

LinkedIn is NOT added to the content file `channels` frontmatter field — it is manual-only, like IndieHackers, Reddit, and HN. The content-publisher pipeline is unchanged.

## Technical Considerations

### LinkedIn is Manual-Only in v1

Like IndieHackers, Reddit, and HN in social-distribute today: content is generated in the content file, displayed in the summary, and the user copies it to LinkedIn manually. No `channels` field entry, no content-publisher integration, no API scripts.

This avoids:

- The one-channel-to-one-section ambiguity (SpecFlow Q1)
- Content-publisher partial-publish status issues (SpecFlow Gap 10)
- Dead stub scripts that print "go do it manually" (Simplicity review)

### One Variant, Not Two

The brainstorm decided on two variants (company page + personal profile). Plan review unanimously recommended deferring the company page variant — the page doesn't exist, the `LINKEDIN_ORGANIZATION_ID` isn't set, and the content distinction is speculative. Ship one `## LinkedIn` variant with thought-leadership tone. Split when there's real data showing company page needs different content.

### social-distribute Phase 5.6: LinkedIn

```markdown
#### 5.6 LinkedIn Post

- Thought-leadership framing: case studies, reflections, lessons learned
- First-person, authentic founder voice
- Aim for ~1,300 characters (optimal organic visibility), max 3,000
- Professional but not corporate — distinct from X's brevity and Discord's casual tone
- Match brand voice from `## Voice` and `## Channel Notes > ### LinkedIn`
- Tuesday-Thursday mornings perform best (note in guidance, not enforced)
- Include article URL naturally in context
```

### Brand Guide Channel Notes

Add `### LinkedIn` under `## Channel Notes` in `knowledge-base/marketing/brand-guide.md`:

- Thought leadership, case studies, reflective posts
- Professional but authentic tone — longer-form than X, more polished than Discord
- First-person founder voice for personal profile posting
- Tuesday-Thursday morning cadence guidance
- No hashtag stuffing; one or two relevant hashtags max

### Edge Case: Missing LinkedIn Channel Notes

social-distribute SKILL.md line 103: "If a channel notes section is missing for a platform, generate content using only the `## Voice` section." This handles the ordering dependency — LinkedIn variants work even before channel notes are added. But we add channel notes early in implementation to get the best output.

## Acceptance Criteria

- [ ] `social-distribute SKILL.md` has Phase 5.6 generating a `## LinkedIn` variant
- [ ] Brand guide has `### LinkedIn` Channel Notes under `## Channel Notes`
- [ ] `community SKILL.md` platform detection table includes LinkedIn row (`LINKEDIN_ACCESS_TOKEN`)
- [ ] `community-manager.md` description includes LinkedIn
- [ ] social-distribute Phase 6 presentation includes LinkedIn variant with character count
- [ ] social-distribute content file template includes `## LinkedIn` section
- [ ] LinkedIn is NOT in the `channels` frontmatter field (manual-only)

## Test Scenarios

- Given a blog post path, when `social-distribute` runs, then 6 variants are generated (5 existing + 1 LinkedIn)
- Given brand guide has `### LinkedIn` Channel Notes, when `social-distribute` runs, then LinkedIn variant reflects channel-specific voice guidance
- Given brand guide has NO `### LinkedIn` Channel Notes, when `social-distribute` runs, then LinkedIn variant uses `## Voice` section as fallback
- Given community `platforms` sub-command runs, then LinkedIn appears with `[not configured]` status (no credentials set)
- Given existing Discord/X/GitHub operations, when LinkedIn changes are deployed, then zero regressions in current platform operations

## Success Metrics

- LinkedIn variant appears in social-distribute output for every new blog post
- Content files include `## LinkedIn` section for manual copy-paste
- Zero regressions in existing Discord/X/GitHub community operations

## Deferred Items (follow-up issues to file)

| Item | Gate | Tracking |
|------|------|----------|
| `linkedin-community.sh` + `linkedin-setup.sh` | LinkedIn API approval | File as new issue |
| `content-publisher.sh` LinkedIn channel automation | LinkedIn API approval | File as new issue |
| `site.json` + `community.njk` LinkedIn card | LinkedIn company page URL exists | File as new issue |
| `scheduled-community-monitor.yml` LinkedIn secrets | LinkedIn API approval | File as new issue |
| Second LinkedIn variant (company page) | Company page exists + data on content differentiation | File as new issue |
| LinkedIn comment engagement | API approval + established presence | Tracked in #138 as future scope |

## References & Research

### Internal References (pattern files)

- `plugins/soleur/skills/social-distribute/SKILL.md:105-152` — Variant generation phases (follow Phase 5.4/5.5 pattern)
- `plugins/soleur/skills/community/SKILL.md:26-31` — Platform detection table
- `plugins/soleur/agents/support/community-manager.md` — Agent description to update
- `knowledge-base/marketing/brand-guide.md:128` — Channel Notes section

### Institutional Learnings Applied

- **External API scope calibration** — X was overscoped 3x. Apply scope heuristic: flag if >3 new files. This plan touches ~5 files.
- **Verify external platforms before strategizing** — LinkedIn API not needed for manual-only v1; deferred to follow-up.
- **Reddit API automation risk** — Precedent for "generate automatically, post manually" when platform is hostile to bots.

### Related Work

- Brainstorm: `knowledge-base/project/brainstorms/2026-03-13-linkedin-presence-brainstorm.md`
- Spec: `knowledge-base/features/specs/feat-linkedin-presence/spec.md`
- Issue #138: Extend Community Agent with LinkedIn Presence
- Issue #96: Original community agent (established patterns)
- Issue #470: Platform adapter refactor (deferred, separate PR)
