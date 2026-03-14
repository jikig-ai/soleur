---
title: "feat: LinkedIn company page variant + Playwright setup"
type: feat
date: 2026-03-14
semver: minor
---

# feat: LinkedIn Company Page Variant + Playwright Setup

**Issue:** #593
**Branch:** feat-linkedin-company-variant
**Brainstorm:** `knowledge-base/brainstorms/2026-03-14-linkedin-company-variant-brainstorm.md`
**Spec:** `knowledge-base/specs/feat-linkedin-company-variant/spec.md`

## Summary

Clear the gate on #593 by: (1) creating a LinkedIn company page via Playwright MCP automation in linkedin-setup.sh, and (2) adding a second social-distribute LinkedIn variant for company page content with official announcement tone. Three commits in one PR.

## Non-Goals

- LinkedIn API automation for posting (tracked in #590)
- Content-publisher automated LinkedIn posting (depends on #590)
- LinkedIn comment engagement
- Platform adapter interface refactor (#470)
- Adding LinkedIn to `channels` frontmatter (stays manual-only like IndieHackers/Reddit/HN)

## Architecture Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Playwright interaction model | Agent-orchestrated MCP tool calls with AskUserQuestion pauses | Playwright MCP tools are LLM tool calls, not bash commands. linkedin-setup.sh handles credential validation; the Playwright flow is documented as agent instructions. |
| Channel names | `linkedin-personal` + `linkedin-company` | Hyphenated compound names. Maps to `## LinkedIn Personal` and `## LinkedIn Company Page` section headings. |
| site.json field names | `"linkedin"` (personal) + `"linkedinCompany"` (company) | Flat keys matching existing `discord`, `x` pattern. camelCase for multi-word. |
| LinkedIn in channels frontmatter | No | Manual-only platform. Matches IndieHackers/Reddit/HN pattern. `channel_to_section()` mappings serve social-distribute content generation, not content-publisher automation. |
| UTM source split | `linkedin` (personal, backward compatible) + `linkedin-company` (new) | Preserves existing analytics continuity for personal variant. |
| Brand guide section rename | `### LinkedIn` → `### LinkedIn Personal` | Consistent naming across brand guide, content files, and channel names. |
| Content file migration | No-op (confirmed: zero existing files have `## LinkedIn` sections) | All 6 distribution-content files pre-date LinkedIn variant shipping. Only SKILL.md template needs updating. |
| Variant count | 6 → 7 | Update all references in SKILL.md description, Phase 6, and summary. |
| community.njk | One card for company page | Company page is the public-facing entity. LinkedIn brand blue `#0A66C2`, category "Social". |

## Implementation Plan

### Commit 1: linkedin-setup.sh + Playwright company page creation

**New file:** `plugins/soleur/skills/community/scripts/linkedin-setup.sh`

Following x-setup.sh pattern (327 lines), create with subcommands:

```text
linkedin-setup.sh <command>

Commands:
  create-company-page   Guide Playwright MCP company page creation (prints instructions)
  validate-credentials  Test LinkedIn OAuth token validity
  write-env             Write LinkedIn credentials to .env
  verify                Source .env and validate credentials
```

**Script structure:**
- Header with usage docs, env var requirements (`LINKEDIN_ACCESS_TOKEN`, `LINKEDIN_ORGANIZATION_ID`), exit codes
- `set -euo pipefail`
- `require_jq()` dependency check
- `require_credentials()` checking env vars with setup instructions if missing
- `validate_credentials()` — GET LinkedIn API endpoint with token, HTTP status dispatch
- `write_env()` — append LinkedIn credentials to `.env` with `chmod 600`
- `verify()` — source `.env` then run `validate_credentials`
- `create_company_page()` — print Playwright MCP workflow instructions (the actual Playwright automation is agent-driven, not bash-driven)
- Main dispatch case statement

**Playwright MCP workflow** (agent-orchestrated, documented in script output and plan):

```text
Step 1: browser_navigate to https://www.linkedin.com/company/setup/new/
Step 2: browser_snapshot — check if login required
Step 3: [If login needed] AskUserQuestion: "Please log into LinkedIn in the browser. Press continue when done."
Step 4: browser_snapshot — verify on company page creation form
Step 5: browser_fill_form with company details:
        - Company name (from site.json "name" field)
        - Company URL (from site.json "url" field)
Step 6: browser_snapshot — verify fields filled, check for additional required fields
Step 7: AskUserQuestion: "Review the form. Fill any remaining fields (logo, industry). Press continue when ready to submit."
Step 8: browser_click submit button
Step 9: browser_snapshot — capture resulting page URL
Step 10: Extract company page URL from browser URL bar or page content
Step 11: Write URL to site.json as "linkedinCompany" field
```

**Key safety patterns:**
- `git rev-parse --show-toplevel` for repo root resolution
- Credentials never passed as CLI args
- `2>/dev/null` on curl to prevent credential leakage
- Idempotent: `create-company-page` checks if `linkedinCompany` already exists in site.json

**site.json update** (`plugins/soleur/docs/_data/site.json`):

Add two fields after existing `"x"` field:
```json
"linkedin": "",
"linkedinCompany": ""
```

Personal URL populated manually or via future setup. Company URL populated by Playwright workflow.

### Commit 2: social-distribute Phase 5.7 + template updates

**Edit:** `plugins/soleur/skills/social-distribute/SKILL.md`

1. **Update description frontmatter** — change "6 variants" to "7 variants" (or use "platform-specific variants" to avoid hardcoding count)

2. **Update UTM table (Phase 3)** — split LinkedIn row:

| Platform | utm_source | utm_medium | utm_campaign |
|----------|-----------|------------|-------------|
| LinkedIn Personal | linkedin | social | `<slug>` |
| LinkedIn Company Page | linkedin-company | social | `<slug>` |

3. **Update Phase 4 (Read Brand Guide)** — add instruction to read both `### LinkedIn Personal` and `### LinkedIn Company Page` Channel Notes

4. **Rename Phase 5.6** — `#### 5.6 LinkedIn Post` → `#### 5.6 LinkedIn Personal`
   - Update section heading reference from `## LinkedIn` to `## LinkedIn Personal`
   - Keep all other content (tone, character limits, voice) unchanged

5. **Add Phase 5.7** — `#### 5.7 LinkedIn Company Page`

```text
#### 5.7 LinkedIn Company Page

Generate a LinkedIn company page variant:
- Official announcement tone, third-person company voice ("Soleur now supports...")
- ~1,300 chars optimal, max 3,000
- Professional framing: product updates, feature announcements, milestones
- UTM: utm_source=linkedin-company&utm_medium=social&utm_campaign=<slug>
- Match brand voice from ## Voice and ## Channel Notes > ### LinkedIn Company Page
- Section heading: ## LinkedIn Company Page
```

6. **Update Phase 6 (Present All Variants)** — add LinkedIn Company Page to display list, update count from 6 to 7

7. **Update content file template (Phase 9)** — rename `## LinkedIn` to `## LinkedIn Personal`, add `## LinkedIn Company Page` section after it:

```text
---

## LinkedIn Personal

<LinkedIn personal variant content>

---

## LinkedIn Company Page

<LinkedIn company page variant content>
```

8. **Update Phase 10 (Summary)** — add LinkedIn Company Page to manual posting list

**Edit:** `knowledge-base/marketing/brand-guide.md`

1. **Rename** `### LinkedIn` (lines 180-201) → `### LinkedIn Personal`
2. **Add** `### LinkedIn Company Page` section after it:

```text
### LinkedIn Company Page

- Official announcement tone, third-person company voice
- Product updates, feature announcements, milestone celebrations
- Professional framing: "Soleur now supports...", "Today we're releasing..."
- ~1,300 chars optimal, 3,000 max
- Link to blog post or docs for details
- Minimal hashtags (1-2 max, same as personal)
- Cross-reference ### LinkedIn Personal for cadence and skip rules
```

### Commit 3: content-publisher channel mapping + tests + community.njk

**Edit:** `scripts/content-publisher.sh`

1. **Update `channel_to_section()` (lines 53-59):**

```bash
channel_to_section() {
  local channel="$1"
  case "$channel" in
    discord)            echo "Discord" ;;
    x)                  echo "X/Twitter Thread" ;;
    linkedin-personal)  echo "LinkedIn Personal" ;;
    linkedin-company)   echo "LinkedIn Company Page" ;;
    linkedin)           echo "LinkedIn Personal" ; echo "Warning: 'linkedin' is deprecated. Use 'linkedin-personal' instead." >&2 ;;
    *)                  echo "" ;;
  esac
}
```

Note: LinkedIn channels will NOT appear in `channels` frontmatter (manual-only), so the publishing loop case statement does NOT need new branches. The `channel_to_section()` mappings exist for social-distribute content generation consistency and potential future automation (#590).

**Edit:** `test/content-publisher.test.ts`

1. **Update existing LinkedIn test (lines 313-317):**

```typescript
test("maps linkedin-personal to LinkedIn Personal", () => {
  const result = runFunction(`channel_to_section "linkedin-personal"`);
  expect(result.stdout).toBe("LinkedIn Personal");
});

test("maps linkedin-company to LinkedIn Company Page", () => {
  const result = runFunction(`channel_to_section "linkedin-company"`);
  expect(result.stdout).toBe("LinkedIn Company Page");
});

test("maps legacy linkedin to LinkedIn Personal with deprecation warning", () => {
  const result = runFunction(`channel_to_section "linkedin"`);
  expect(result.stdout).toBe("LinkedIn Personal");
  expect(result.stderr).toContain("deprecated");
});
```

**Edit:** `test/helpers/sample-content.md`

Add LinkedIn sections after Hacker News:

```text
---

## LinkedIn Personal

I've been thinking about how AI agents change the way we ship software...

This is a test LinkedIn personal post with thought leadership framing.

---

## LinkedIn Company Page

Soleur now supports automated competitive intelligence scanning.

This is a test LinkedIn company page post with official announcement framing.
```

**Edit:** `plugins/soleur/docs/pages/community.njk`

Add LinkedIn card after X/Twitter card (line 36), before GitHub card:

```html
<a href="{{ site.linkedinCompany }}" target="_blank" rel="noopener" class="component-card community-card-link">
  <div class="card-header">
    <span class="card-dot" style="background: #0A66C2"></span>
    <span class="card-category">Social</span>
  </div>
  <h3 class="card-title">LinkedIn</h3>
  <p class="card-description">Follow the Soleur company page for product updates, feature announcements, and engineering insights.</p>
</a>
```

**Edit:** `plugins/soleur/docs/_data/site.json`

Ensure `linkedin` and `linkedinCompany` fields are populated (from Commit 1 or Playwright workflow).

## Files Changed

| File | Action | Commit |
|------|--------|--------|
| `plugins/soleur/skills/community/scripts/linkedin-setup.sh` | CREATE | 1 |
| `plugins/soleur/docs/_data/site.json` | EDIT | 1 |
| `plugins/soleur/skills/social-distribute/SKILL.md` | EDIT | 2 |
| `knowledge-base/marketing/brand-guide.md` | EDIT | 2 |
| `scripts/content-publisher.sh` | EDIT | 3 |
| `test/content-publisher.test.ts` | EDIT | 3 |
| `test/helpers/sample-content.md` | EDIT | 3 |
| `plugins/soleur/docs/pages/community.njk` | EDIT | 3 |

## Test Scenarios

### linkedin-setup.sh

```text
Given linkedin-setup.sh exists with validate-credentials command
When LINKEDIN_ACCESS_TOKEN is not set
Then exit with code 1 and print setup instructions

Given linkedin-setup.sh exists with validate-credentials command
When LINKEDIN_ACCESS_TOKEN is set and valid
Then exit with code 0 and print success

Given site.json already has a linkedinCompany URL
When create-company-page is called
Then skip creation and print existing URL
```

### content-publisher channel mapping

```text
Given channel_to_section function
When called with "linkedin-personal"
Then return "LinkedIn Personal"

Given channel_to_section function
When called with "linkedin-company"
Then return "LinkedIn Company Page"

Given channel_to_section function
When called with "linkedin" (legacy)
Then return "LinkedIn Personal" and print deprecation warning to stderr

Given a content file with channels: "discord, x"
When content-publisher processes it
Then LinkedIn sections are ignored (not in channels list)
```

### social-distribute

```text
Given a blog post to distribute
When social-distribute runs Phase 5.6 and 5.7
Then two LinkedIn variants are generated:
  - LinkedIn Personal with first-person founder voice
  - LinkedIn Company Page with third-person official voice

Given social-distribute content file template
When Phase 9 writes the file
Then both ## LinkedIn Personal and ## LinkedIn Company Page sections are present
And channels frontmatter contains "discord, x" only (no LinkedIn)
```

### extract_section

```text
Given a content file with both ## LinkedIn Personal and ## LinkedIn Company Page
When extract_section is called with "LinkedIn Personal"
Then only the personal section content is returned (no bleed into company section)

Given a content file with both LinkedIn sections
When extract_section is called with "LinkedIn Company Page"
Then only the company section content is returned
```

## Risks and Mitigations

| Risk | Mitigation |
|------|-----------|
| LinkedIn changes company page creation form (selector breakage) | Playwright uses accessibility tree snapshots (ref-based), not CSS selectors. AskUserQuestion pauses allow human recovery. |
| Company name already taken on LinkedIn | Script checks for error messages in browser_snapshot after submission. Agent reports failure and asks user to resolve. |
| LinkedIn rate-limits or blocks page creation | AskUserQuestion pause if unexpected modal detected. Human can complete manually; script captures URL afterward. |
| Legacy `linkedin` channel in old content files | Backward-compatible mapping with deprecation warning. No existing files use this, so risk is theoretical. |

## Rollback Plan

Each commit is independently revertable:
- Commit 3 (channel mapping + tests): `git revert` — content-publisher returns to 2-channel mapping
- Commit 2 (social-distribute + brand guide): `git revert` — reverts to single LinkedIn variant
- Commit 1 (linkedin-setup.sh + site.json): `git revert` — removes setup script and site.json fields
