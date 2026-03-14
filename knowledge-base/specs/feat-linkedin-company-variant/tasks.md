# Tasks: LinkedIn Company Page Variant + Playwright Setup

**Issue:** #593
**Branch:** feat-linkedin-company-variant
**Plan:** `knowledge-base/plans/2026-03-14-feat-linkedin-company-variant-plan.md`

## Phase 1: linkedin-setup.sh + site.json (Commit 1)

- [ ] 1.1 Create `plugins/soleur/skills/community/scripts/linkedin-setup.sh` with header, usage docs, `set -euo pipefail`
- [ ] 1.2 Add `require_jq()` and `require_credentials()` functions (check `LINKEDIN_ACCESS_TOKEN`, `LINKEDIN_ORGANIZATION_ID`)
- [ ] 1.3 Add `validate_credentials()` — GET LinkedIn API with token, HTTP status dispatch
- [ ] 1.4 Add `write_env()` — append LinkedIn credentials to `.env` with `chmod 600`, use `git rev-parse --show-toplevel` for path resolution
- [ ] 1.5 Add `verify()` — source `.env` then run `validate_credentials`
- [ ] 1.6 Add `create_company_page()` — print Playwright MCP workflow steps, check if `linkedinCompany` already exists in site.json
- [ ] 1.7 Add main dispatch case statement
- [ ] 1.8 Add `"linkedin": ""` and `"linkedinCompany": ""` fields to `plugins/soleur/docs/_data/site.json`
- [ ] 1.9 Run Playwright MCP workflow to create company page (agent-orchestrated with human pauses)
- [ ] 1.10 Capture company page URL and write to site.json `linkedinCompany` field

## Phase 2: social-distribute + brand guide (Commit 2)

- [ ] 2.1 Rename brand guide `### LinkedIn` → `### LinkedIn Personal` in `knowledge-base/marketing/brand-guide.md`
- [ ] 2.2 Add `### LinkedIn Company Page` Channel Notes section to brand guide
- [ ] 2.3 Update SKILL.md description frontmatter — variant count 6 → 7
- [ ] 2.4 Split UTM table LinkedIn row into LinkedIn Personal + LinkedIn Company Page
- [ ] 2.5 Update Phase 4 to read both LinkedIn Channel Notes sections
- [ ] 2.6 Rename Phase 5.6 `LinkedIn Post` → `LinkedIn Personal`, update section heading reference
- [ ] 2.7 Add Phase 5.7 `LinkedIn Company Page` variant instructions
- [ ] 2.8 Update Phase 6 display list and variant count
- [ ] 2.9 Update Phase 9 content file template — rename `## LinkedIn` → `## LinkedIn Personal`, add `## LinkedIn Company Page`
- [ ] 2.10 Update Phase 10 summary — add LinkedIn Company Page to manual posting list

## Phase 3: content-publisher + tests + community.njk (Commit 3)

- [ ] 3.1 Add `linkedin-personal`, `linkedin-company`, and legacy `linkedin` cases to `channel_to_section()` in `scripts/content-publisher.sh`
- [ ] 3.2 Update `test/content-publisher.test.ts` — replace LinkedIn unknown test with three new tests (linkedin-personal, linkedin-company, legacy linkedin with deprecation warning)
- [ ] 3.3 Add `## LinkedIn Personal` and `## LinkedIn Company Page` sections to `test/helpers/sample-content.md`
- [ ] 3.4 Add LinkedIn card to `plugins/soleur/docs/pages/community.njk` after X/Twitter card
- [ ] 3.5 Run `bun test` to verify all tests pass

## Phase 4: Review + Ship

- [ ] 4.1 Run `/soleur:compound` before each commit
- [ ] 4.2 Run `/soleur:ship` to finalize PR
