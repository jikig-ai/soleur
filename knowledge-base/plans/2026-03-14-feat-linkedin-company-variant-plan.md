---
title: "feat: LinkedIn company page variant + Playwright setup"
type: feat
date: 2026-03-14
semver: minor
---

# feat: LinkedIn Company Page Variant + Playwright Setup

[Updated 2026-03-14 — simplified after plan review: dropped linkedin-setup.sh, dropped legacy mapping, symmetric UTMs, collapsed to 2 commits]

**Issue:** #593
**Branch:** feat-linkedin-company-variant
**Brainstorm:** `knowledge-base/brainstorms/2026-03-14-linkedin-company-variant-brainstorm.md`
**Spec:** `knowledge-base/specs/feat-linkedin-company-variant/spec.md`

## Summary

Clear the gate on #593 by: (1) creating a LinkedIn company page via Playwright MCP during implementation (agent-driven, no script), and (2) adding a second social-distribute LinkedIn variant for company page content with official announcement tone. Two commits in one PR.

## Non-Goals

- LinkedIn API automation for posting (tracked in #590)
- Content-publisher automated LinkedIn posting (depends on #590)
- LinkedIn comment engagement
- Platform adapter interface refactor (#470)
- Adding LinkedIn to `channels` frontmatter (stays manual-only like IndieHackers/Reddit/HN)
- linkedin-setup.sh credential validation (belongs in #590 when API consumers exist)

## Architecture Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Playwright interaction model | Agent-orchestrated MCP tool calls with AskUserQuestion pauses, executed live during implementation | Company page creation is a one-time operation. No bash script needed — the agent drives Playwright MCP directly. |
| Channel names | `linkedin-personal` + `linkedin-company` | Hyphenated compound names. Maps to `## LinkedIn Personal` and `## LinkedIn Company Page` section headings. |
| site.json field names | `"linkedin"` (personal) + `"linkedinCompany"` (company) | Flat keys matching existing `discord`, `x` pattern. camelCase for multi-word. |
| LinkedIn in channels frontmatter | No | Manual-only platform. Matches IndieHackers/Reddit/HN pattern. `channel_to_section()` mappings serve social-distribute content generation, not content-publisher automation. |
| UTM sources | `linkedin-personal` + `linkedin-company` | Symmetric naming. No legacy analytics data exists to preserve (zero existing content files have LinkedIn sections). |
| Brand guide section rename | `### LinkedIn` → `### LinkedIn Personal` | Consistent naming across brand guide, content files, and channel names. |
| Content file migration | No-op | All 6 distribution-content files pre-date LinkedIn variant shipping. Zero have `## LinkedIn` sections. Only SKILL.md template needs updating. |
| Variant count | Use "platform-specific variants" | Avoids hardcoding a count that changes with each new platform. |
| community.njk | One card for company page | Company page is the public-facing entity. LinkedIn brand blue `#0A66C2`, category "Social". 4 cards in `auto-fill` grid — no orphan cards at any breakpoint. |
| Legacy `linkedin` channel name | No backward-compatible mapping | Channel name `linkedin` was never shipped to production. The existing `*) echo "" ;;` catch-all handles unknown channels. |

## Implementation Plan

### Pre-implementation: Create LinkedIn company page via Playwright MCP

Before committing any code, create the company page interactively:

1. `browser_navigate` to `https://www.linkedin.com/company/setup/new/`
2. `browser_snapshot` — check if login is required
3. If login needed: AskUserQuestion — "Log into LinkedIn in the browser. Press continue when done."
4. `browser_snapshot` — verify on company page creation form
5. `browser_fill_form` — company name (from site.json `name`), company URL (from site.json `url`)
6. `browser_snapshot` — verify fields, check for additional required fields (industry, logo)
7. AskUserQuestion — "Review the form. Fill any remaining fields (logo, industry). Press continue when ready to submit."
8. `browser_click` submit button
9. `browser_snapshot` — capture resulting page URL
10. Extract company page URL from browser state
11. Write URL to site.json `linkedinCompany` field

If creation fails (name taken, rate limited, etc.), the human completes manually and provides the URL.

### Commit 1: social-distribute Phase 5.7 + brand guide + site.json

**Edit:** `plugins/soleur/docs/_data/site.json`

Add two fields after existing `"x"` field:
```json
"linkedin": "",
"linkedinCompany": "<captured-url>"
```

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
- Cross-reference ### LinkedIn Personal for cadence, skip rules, and reply guidelines
```

**Edit:** `plugins/soleur/skills/social-distribute/SKILL.md`

1. **Update description frontmatter** — replace hardcoded "6 variants" with "platform-specific variants"

2. **Update UTM table (Phase 3)** — replace single LinkedIn row with two:

| Platform | utm_source | utm_medium | utm_campaign |
|----------|-----------|------------|-------------|
| LinkedIn Personal | linkedin-personal | social | `<slug>` |
| LinkedIn Company Page | linkedin-company | social | `<slug>` |

3. **Update Phase 4 (Read Brand Guide)** — replace the existing line:
   ```
   Read `## Channel Notes > ### LinkedIn`
   ```
   with two lines:
   ```
   Read `## Channel Notes > ### LinkedIn Personal`
   Read `## Channel Notes > ### LinkedIn Company Page`
   ```

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

6. **Update Phase 5 header text** — replace "generate all 6 variants" with "generate all platform-specific variants"

7. **Update Phase 6 (Present All Variants)** — add LinkedIn Company Page to display list with format:
   ```
   ## LinkedIn Company Page (NNNN/1300 optimal, NNNN/3000 max)
   ```
   Replace "all 6 variants" with "all variants"

8. **Update content file template (Phase 9)** — rename `## LinkedIn` to `## LinkedIn Personal`, add `## LinkedIn Company Page` section after it:

```text
---

## LinkedIn Personal

<LinkedIn personal variant content>

---

## LinkedIn Company Page

<LinkedIn company page variant content>
```

9. **Update Phase 10 (Summary)** — add LinkedIn Company Page to manual posting list

### Commit 2: content-publisher channel mapping + tests + community.njk

**Edit:** `scripts/content-publisher.sh`

**Replace `channel_to_section()` (lines 53-59):**

```bash
channel_to_section() {
  local channel="$1"
  case "$channel" in
    discord)            echo "Discord" ;;
    x)                  echo "X/Twitter Thread" ;;
    linkedin-personal)  echo "LinkedIn Personal" ;;
    linkedin-company)   echo "LinkedIn Company Page" ;;
    *)                  echo "" ;;
  esac
}
```

No changes to the publishing loop case statement — LinkedIn is manual-only and will not appear in `channels` frontmatter.

**Edit:** `test/content-publisher.test.ts`

**Replace the existing test at line 313** (`"returns empty for unknown channel"` using `linkedin` as input) with two new tests:

```typescript
test("maps linkedin-personal to LinkedIn Personal", () => {
  const result = runFunction(`channel_to_section "linkedin-personal"`);
  expect(result.stdout).toBe("LinkedIn Personal");
});

test("maps linkedin-company to LinkedIn Company Page", () => {
  const result = runFunction(`channel_to_section "linkedin-company"`);
  expect(result.stdout).toBe("LinkedIn Company Page");
});
```

**Add `extract_section` boundary tests** in the existing `describe("extract_section")` block:

```typescript
test("extracts LinkedIn Personal without bleeding into LinkedIn Company Page", () => {
  const result = runFunction(`extract_section "LinkedIn Personal"`, sampleContent);
  expect(result.stdout).toContain("thought leadership");
  expect(result.stdout).not.toContain("official announcement");
});

test("extracts LinkedIn Company Page without bleeding into LinkedIn Personal", () => {
  const result = runFunction(`extract_section "LinkedIn Company Page"`, sampleContent);
  expect(result.stdout).toContain("official announcement");
  expect(result.stdout).not.toContain("thought leadership");
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

## Files Changed

| File | Action | Commit |
|------|--------|--------|
| `plugins/soleur/docs/_data/site.json` | EDIT | 1 |
| `knowledge-base/marketing/brand-guide.md` | EDIT | 1 |
| `plugins/soleur/skills/social-distribute/SKILL.md` | EDIT | 1 |
| `scripts/content-publisher.sh` | EDIT | 2 |
| `test/content-publisher.test.ts` | EDIT | 2 |
| `test/helpers/sample-content.md` | EDIT | 2 |
| `plugins/soleur/docs/pages/community.njk` | EDIT | 2 |

## Test Scenarios

### content-publisher channel mapping

```text
Given channel_to_section function
When called with "linkedin-personal"
Then return "LinkedIn Personal"

Given channel_to_section function
When called with "linkedin-company"
Then return "LinkedIn Company Page"

Given channel_to_section function
When called with "linkedin" (unknown)
Then return "" (catch-all for unknown channels)

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

### extract_section boundary

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
| LinkedIn changes company page creation form | Playwright uses accessibility tree snapshots (ref-based), not CSS selectors. AskUserQuestion pauses allow human recovery. If automation fails, human completes manually and provides URL. |
| Company name already taken on LinkedIn | Agent checks browser_snapshot for error messages. Human resolves naming conflict. |
| `extract_section` bleed between adjacent LinkedIn sections | Dedicated boundary tests verify no content leakage between `## LinkedIn Personal` and `## LinkedIn Company Page`. |

## Rollback Plan

Each commit is independently revertable:
- Commit 2 (channel mapping + tests + community.njk): `git revert` — content-publisher returns to 2-channel mapping, community page loses LinkedIn card
- Commit 1 (social-distribute + brand guide + site.json): `git revert` — reverts to single LinkedIn variant
