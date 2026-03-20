# Tasks: LinkedIn Company Page Variant + Playwright Setup

**Issue:** #593
**Branch:** feat-linkedin-company-variant
**Plan:** `knowledge-base/project/plans/2026-03-14-feat-linkedin-company-variant-plan.md`

## Phase 0: Create LinkedIn Company Page (Playwright MCP)

- [ ] 0.1 Navigate to LinkedIn company page creation form via Playwright MCP
- [ ] 0.2 Complete form with company details (agent fills, human handles auth/logo)
- [ ] 0.3 Capture company page URL and write to `plugins/soleur/docs/_data/site.json` as `linkedinCompany`

## Phase 1: social-distribute + brand guide + site.json (Commit 1)

- [ ] 1.1 Add `"linkedin": ""` and `"linkedinCompany": "<url>"` fields to `plugins/soleur/docs/_data/site.json`
- [ ] 1.2 Rename brand guide `### LinkedIn` → `### LinkedIn Personal` in `knowledge-base/marketing/brand-guide.md`
- [ ] 1.3 Add `### LinkedIn Company Page` Channel Notes section to brand guide
- [ ] 1.4 Update SKILL.md description — replace hardcoded "6 variants" with "platform-specific variants"
- [ ] 1.5 Split UTM table LinkedIn row into `linkedin-personal` + `linkedin-company`
- [ ] 1.6 Update Phase 4 to read both `### LinkedIn Personal` and `### LinkedIn Company Page` Channel Notes
- [ ] 1.7 Rename Phase 5.6 `LinkedIn Post` → `LinkedIn Personal`, update section heading reference
- [ ] 1.8 Add Phase 5.7 `LinkedIn Company Page` variant instructions
- [ ] 1.9 Update Phase 5 header and Phase 6 — replace "all 6 variants" with "all variants", add LinkedIn Company Page display format
- [ ] 1.10 Update Phase 9 content file template — rename `## LinkedIn` → `## LinkedIn Personal`, add `## LinkedIn Company Page`
- [ ] 1.11 Update Phase 10 summary — add LinkedIn Company Page to manual posting list

## Phase 2: content-publisher + tests + community.njk (Commit 2)

- [ ] 2.1 Add `linkedin-personal` and `linkedin-company` cases to `channel_to_section()` in `scripts/content-publisher.sh`
- [ ] 2.2 Replace existing LinkedIn test at line 313 in `test/content-publisher.test.ts` with `linkedin-personal` and `linkedin-company` tests
- [ ] 2.3 Add `extract_section` boundary tests for adjacent LinkedIn sections
- [ ] 2.4 Add `## LinkedIn Personal` and `## LinkedIn Company Page` sections to `test/helpers/sample-content.md`
- [ ] 2.5 Add LinkedIn card to `plugins/soleur/docs/pages/community.njk` after X/Twitter card
- [ ] 2.6 Run `bun test` to verify all tests pass

## Phase 3: Review + Ship

- [ ] 3.1 Run `/soleur:compound` before each commit
- [ ] 3.2 Run `/soleur:ship` to finalize PR
