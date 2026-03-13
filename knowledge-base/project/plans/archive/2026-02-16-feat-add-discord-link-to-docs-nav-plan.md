---
title: "feat: Add Discord link to docs site navigation"
type: feat
date: 2026-02-16
version-bump: PATCH
deepened: 2026-02-16
---

# Add Discord Link to Docs Site Navigation

## Enhancement Summary

**Deepened on:** 2026-02-16
**Sections enhanced:** 2 (Verification, Implementation notes)

### Key Improvements
1. Added local verification steps from documented base-href learning
2. Added post-edit verification command to catch missed files
3. Noted accessibility considerations for external links

Add the Discord server invite link to the website header nav and footer on all pages, alongside the existing GitHub link.

## Acceptance Criteria

- [ ] Discord link (`https://discord.gg/PYZbPBKMUY`) appears in header nav on all 8 HTML pages
- [ ] Discord link appears in footer on all 8 HTML pages
- [ ] Link opens in new tab (`target="_blank" rel="noopener"`)
- [ ] Link uses same styling as existing GitHub link (no CSS changes needed)
- [ ] Mobile hamburger menu includes the Discord link
- [ ] `sitemap.xml` unchanged (external link, not a page)

## Test Scenarios

- Given any docs page, when I look at the header nav, then I see a "Discord" link after "GitHub"
- Given any docs page, when I look at the footer, then I see a "Discord" link after "GitHub"
- Given the Discord link, when I click it, then it opens `https://discord.gg/PYZbPBKMUY` in a new tab
- Given mobile viewport, when I open the hamburger menu, then Discord link is visible

## Context

### Files to Update (8 total)

1. `plugins/soleur/docs/index.html`
2. `plugins/soleur/docs/404.html`
3. `plugins/soleur/docs/pages/agents.html`
4. `plugins/soleur/docs/pages/commands.html`
5. `plugins/soleur/docs/pages/skills.html`
6. `plugins/soleur/docs/pages/mcp-servers.html`
7. `plugins/soleur/docs/pages/changelog.html`
8. `plugins/soleur/docs/pages/getting-started.html`

### Current Nav HTML Pattern

```html
<li><a href="https://github.com/jikig-ai/soleur" target="_blank" rel="noopener">GitHub</a></li>
```

Add after this line:

```html
<li><a href="https://discord.gg/PYZbPBKMUY" target="_blank" rel="noopener">Discord</a></li>
```

### Current Footer HTML Pattern

```html
<li><a href="https://github.com/jikig-ai/soleur" target="_blank" rel="noopener">GitHub</a></li>
```

Add after this line:

```html
<li><a href="https://discord.gg/PYZbPBKMUY" target="_blank" rel="noopener">Discord</a></li>
```

### No CSS Changes

Existing `.nav-links a` and `.footer-links a` styles apply automatically.

### Implementation Notes

**Edit strategy:** Use string replacement on the GitHub `<li>` line in each file, inserting the Discord `<li>` immediately after. The GitHub link appears exactly once in the nav and once in the footer per file = 2 edits per file, 16 edits total.

**Post-edit verification (from learning: base-href-breaks-local-dev-server):**

```bash
# Verify all 8 files have BOTH Discord links (nav + footer = 2 per file)
grep -c "discord.gg/PYZbPBKMUY" plugins/soleur/docs/**/*.html plugins/soleur/docs/*.html
# Expected: each file shows "2"

# Verify no files were missed
grep -rL "discord.gg" plugins/soleur/docs/*.html plugins/soleur/docs/pages/*.html
# Expected: empty output (no files missing the link)
```

**Local testing (from learning: base-href-breaks-local-dev-server):**

```bash
mkdir -p /tmp/soleur-docs-test/soleur
cp -r plugins/soleur/docs/* /tmp/soleur-docs-test/soleur/
cd /tmp/soleur-docs-test && python3 -m http.server 8766
# Access at http://localhost:8766/soleur/index.html
```

**Accessibility:** The `rel="noopener"` attribute is already in the pattern. No additional ARIA attributes needed -- the link text "Discord" is self-descriptive.

## Non-goals

- No new community page (tracked in issue #96)
- No Discord widget or embed
- No SVG icon for Discord link

## References

- Related issue: #96 (rethink community presence -- future)
- Discord invite: `https://discord.gg/PYZbPBKMUY`
- Docs site: `plugins/soleur/docs/`
