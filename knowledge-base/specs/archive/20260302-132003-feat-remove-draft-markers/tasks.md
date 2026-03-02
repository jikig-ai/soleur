---
title: "Remove DRAFT markers from legal documents"
plan: knowledge-base/plans/2026-03-02-feat-remove-draft-markers-legal-docs-plan.md
issue: "#189"
---

# Tasks: Remove DRAFT markers from legal documents

## Phase 1: Source docs cleanup

- [ ] 1.1 Remove DRAFT blockquote from top and bottom of `docs/legal/acceptable-use-policy.md`
- [ ] 1.2 Remove DRAFT blockquote from top and bottom of `docs/legal/cookie-policy.md`
- [ ] 1.3 Remove DRAFT blockquote from top and bottom of `docs/legal/data-processing-agreement.md`
- [ ] 1.4 Remove DRAFT blockquote from top and bottom of `docs/legal/disclaimer.md`
- [ ] 1.5 Remove DRAFT blockquote from top and bottom of `docs/legal/gdpr-policy.md`
- [ ] 1.6 Remove DRAFT blockquote from top and bottom of `docs/legal/privacy-policy.md`
- [ ] 1.7 Remove DRAFT blockquote from top and bottom of `docs/legal/terms-and-conditions.md`
- [ ] 1.8 Update Terms & Conditions section 6.2 body text (`docs/legal/terms-and-conditions.md` line 104) to reflect reviewed status

## Phase 2: Rendered pages cleanup

- [ ] 2.1 Remove DRAFT blockquote from top and bottom of `plugins/soleur/docs/pages/legal/acceptable-use-policy.md`
- [ ] 2.2 Remove DRAFT blockquote from top and bottom of `plugins/soleur/docs/pages/legal/cookie-policy.md`
- [ ] 2.3 Remove DRAFT blockquote from top and bottom of `plugins/soleur/docs/pages/legal/data-protection-disclosure.md`
- [ ] 2.4 Remove DRAFT blockquote from top and bottom of `plugins/soleur/docs/pages/legal/disclaimer.md`
- [ ] 2.5 Remove DRAFT blockquote from top and bottom of `plugins/soleur/docs/pages/legal/gdpr-policy.md`
- [ ] 2.6 Remove DRAFT blockquote from top and bottom of `plugins/soleur/docs/pages/legal/privacy-policy.md`
- [ ] 2.7 Remove DRAFT blockquote from top and bottom of `plugins/soleur/docs/pages/legal/terms-and-conditions.md`
- [ ] 2.8 Update Terms & Conditions section 6.2 body text (`plugins/soleur/docs/pages/legal/terms-and-conditions.md` line 114) to reflect reviewed status

## Phase 3: Landing page update

- [ ] 3.1 Update `plugins/soleur/docs/pages/legal.njk` line 22 to remove draft/review language

## Phase 4: Version bump and validation

- [ ] 4.1 Bump PATCH version in `plugins/soleur/.claude-plugin/plugin.json`
- [ ] 4.2 Update `plugins/soleur/CHANGELOG.md` with removal entry
- [ ] 4.3 Verify `plugins/soleur/README.md` version references
- [ ] 4.4 Update `.claude-plugin/marketplace.json` version
- [ ] 4.5 Run verification commands from plan (grep checks for removed markers AND preserved references)
- [ ] 4.6 Run site build (`npx @11ty/eleventy`) to verify no breakage

## Preserve list (DO NOT EDIT these files)

These files contain "draft" references about the generator's output behavior. Verify they are unchanged after all edits:

- `plugins/soleur/agents/legal/legal-document-generator.md`
- `plugins/soleur/skills/legal-generate/SKILL.md`
- `plugins/soleur/agents/legal/clo.md`
- `plugins/soleur/CHANGELOG.md`
- `plugins/soleur/README.md`
