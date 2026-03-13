# Tasks: LinkedIn Presence

## Phase 1: Brand Guide

- [x] 1.1 Add `### LinkedIn` section under `## Channel Notes` in `knowledge-base/marketing/brand-guide.md`
  - [x] 1.1.1 Thought leadership, case studies, reflective posts tone guidance
  - [x] 1.1.2 Professional but authentic voice (distinct from X brevity, Discord casual)
  - [x] 1.1.3 First-person founder voice for personal profile
  - [x] 1.1.4 Tuesday-Thursday morning cadence guidance
  - [x] 1.1.5 ~1,300 chars optimal, 3,000 max; 1-2 hashtags max

## Phase 2: Social Distribute Integration

- [x] 2.1 Update `plugins/soleur/skills/social-distribute/SKILL.md`
  - [x] 2.1.1 Add Phase 5.6: LinkedIn Post variant (thought-leadership, ~1300 chars, founder voice)
  - [x] 2.1.2 Update Phase 4 to read `## Channel Notes > ### LinkedIn` from brand guide
  - [x] 2.1.3 Update Phase 6 presentation to include LinkedIn variant with character count
  - [x] 2.1.4 Update content file template (Phase 9) to include `## LinkedIn` section
  - [x] 2.1.5 Do NOT add `linkedin` to `channels` frontmatter field (manual-only, like IndieHackers/Reddit/HN)
  - [x] 2.1.6 Update Phase 10 summary to mention LinkedIn variant
  - [x] 2.1.7 Update description frontmatter to include LinkedIn

## Phase 3: Community Skill & Agent Updates

- [x] 3.1 Update `plugins/soleur/skills/community/SKILL.md`
  - [x] 3.1.1 Add LinkedIn row to Platform Detection table (`LINKEDIN_ACCESS_TOKEN`)
  - [x] 3.1.2 Update description frontmatter to include LinkedIn
- [x] 3.2 Update `plugins/soleur/agents/support/community-manager.md`
  - [x] 3.2.1 Update description frontmatter to include LinkedIn

## Phase 4: Follow-Up Issues

- [x] 4.1 File GitHub issue: LinkedIn API scripts — #589
- [x] 4.2 File GitHub issue: Content-publisher LinkedIn automation — #590
- [x] 4.3 File GitHub issue: Docs site LinkedIn card — #591
- [x] 4.4 File GitHub issue: Scheduled workflow LinkedIn secrets — #592
- [x] 4.5 File GitHub issue: Second LinkedIn variant (company page) — #593

## Phase 5: Verification

- [ ] 5.1 Verify social-distribute generates 6 variants (5 existing + 1 LinkedIn)
- [ ] 5.2 Verify LinkedIn variant uses Channel Notes when present, falls back to Voice section when absent
- [ ] 5.3 Verify community `platforms` sub-command shows LinkedIn as `[not configured]`
- [ ] 5.4 Verify existing Discord/X/GitHub operations still work (no regressions)
