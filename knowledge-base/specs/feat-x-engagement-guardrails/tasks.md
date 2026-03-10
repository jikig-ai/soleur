# Tasks: X Engagement Guardrails

## Phase 1: Setup

- [ ] 1.1 Read `knowledge-base/overview/brand-guide.md` to confirm current `### X/Twitter` structure
- [ ] 1.2 Verify `#### Profile Banner` sub-heading location (insertion point is above it)
- [ ] 1.3 Verify `## Voice` and `## Channel Notes` headings exist (contract baseline)

## Phase 2: Core Implementation

- [ ] 2.1 Add `#### Engagement Guardrails` subsection under `### X/Twitter`
  - [ ] 2.1.1 Add "Topics to Avoid" content (politics, religion, competitor criticism, speculation, legal-sensitive, risky trending hashtags)
  - [ ] 2.1.2 Add exception clause for legitimate tech ecosystem engagement (#solofounder, #buildinpublic, AI/dev tooling)
  - [ ] 2.1.3 Add "When to Skip" content (spam, off-topic, rage-bait, bots, negative amplification, bare RT/QT, brand association risk)
  - [ ] 2.1.4 Add "Reply Cadence" content (max 10 per session, default to skip, one reply per thread, space replies naturally)
  - [ ] 2.1.5 Add "Tone Matching" content (match register, never argue, redirect complex, credit insights, human voice)
- [ ] 2.2 Verify heading hierarchy: `## Channel Notes` > `### X/Twitter` > `#### Engagement Guardrails` > `#### Profile Banner`
- [ ] 2.3 Verify content uses imperative/infinitive form, not second person
- [ ] 2.4 Verify guardrails apply to both automatic and manual (403 fallback) modes -- no mode-specific language

## Phase 3: Testing

- [ ] 3.1 Verify `#### Profile Banner` sub-heading still intact after the new section
- [ ] 3.2 Verify `## Voice` and `## Channel Notes` top-level headings unchanged (contract preserved)
- [ ] 3.3 Run markdownlint on `brand-guide.md`
- [ ] 3.4 Verify no second-person language ("you should") in the guardrails section
- [ ] 3.5 Verify exception clause exists alongside topic prohibitions (learning: brand violation cascade)
