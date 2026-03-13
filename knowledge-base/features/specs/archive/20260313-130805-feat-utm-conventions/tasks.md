# Tasks: UTM Conventions

## Phase 1: Content File Updates (priority — file 02 publishes 2026-03-17)

- [x] 1.1 Update `knowledge-base/marketing/distribution-content/02-operations-management.md` — UTM-tag URLs in Discord and X sections (IH/Reddit/HN are placeholders)
- [x] 1.2 Update `knowledge-base/marketing/distribution-content/03-competitive-intelligence.md` — UTM-tag URLs in Discord, X, and IH sections (Reddit is self-post with no URL; HN is placeholder)
- [x] 1.3 Update `knowledge-base/marketing/distribution-content/04-brand-guide-creation.md` — UTM-tag URLs in Discord and X sections (IH/Reddit/HN are placeholders)
- [x] 1.4 Update `knowledge-base/marketing/distribution-content/05-business-validation.md` — UTM-tag URLs in Discord, X, IH, and HN sections (Reddit is self-post with no URL)

## Phase 2: SKILL.md + Documentation

- [x] 2.1 Update `plugins/soleur/skills/social-distribute/SKILL.md`
  - [x] 2.1.1 Phase 3: Add UTM mapping table with slug derivation and sanitization note
  - [x] 2.1.2 Phase 5: Update each platform variant to use platform-specific tracked URL
- [x] 2.2 Add UTM Conventions section to `knowledge-base/marketing/content-strategy.md`

## Phase 3: Verification

- [ ] 3.1 Run social-distribute on a test article, grep output for `utm_source=discord`, `utm_source=x`, `utm_source=reddit` (without utm_medium)
