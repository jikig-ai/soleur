---
title: "refactor: Remove CaaS hero badge from landing page"
type: refactor
date: 2026-02-26
deepened: 2026-02-26
---

## Enhancement Summary

**Deepened on:** 2026-02-26
**Sections enhanced:** 3 (Acceptance Criteria, Test Scenarios, Context)

### Key Improvements

1. Added CSS dead-code verification -- confirm `--space-12` is still used elsewhere before assuming variable retention
2. Added edge case for `margin-bottom` on deleted badge element -- verify no layout shift from removing the 32px bottom margin
3. Confirmed no mobile-specific `.landing-hero` padding overrides exist -- the padding change applies uniformly and safely

### New Considerations Discovered

- The `.hero-badge` rule includes `margin-bottom: var(--space-8)` (32px). Removing the badge AND reducing top padding changes the total vertical offset above h1 by 80px (48px from padding reduction + 32px from badge margin). This is intentional -- the hero should feel tighter without the badge.
- `--space-12` is used in 2 other CSS rules (`.landing-cta` line 627, `.error-page` line 932), so the variable definition should NOT be removed from `:root`.
- The print media query (line 989) references `.landing-hero` but only resets `margin-top`, so it is unaffected by the padding change.

---

# refactor: Remove CaaS hero badge from landing page

Remove the "The Company-as-a-Service Platform" pill badge from the landing page hero section. The badge duplicates positioning that is covered in depth on the vision page, in `llms.txt`, in `site.json` tagline, and across all legal documents. Removing it declutters the hero and lets the h1 headline ("Build a Billion-Dollar Company. Alone.") land without preamble.

## Acceptance Criteria

- [ ] The `.hero-badge` div (lines 10-13 of `plugins/soleur/docs/index.njk`) is deleted
- [ ] Hero top padding changed from `var(--space-12)` (128px) to `var(--space-10)` (80px) in `plugins/soleur/docs/css/style.css` line 407
- [ ] The `.landing-hero .hero-badge` CSS rule block (lines 410-420) is deleted
- [ ] The `.hero-badge-dot` CSS rule block (lines 421-427) is deleted
- [ ] The frontmatter `description` in `index.njk` line 3 is preserved unchanged (SEO meta tag still references CaaS)
- [ ] No other files are modified -- `site.json` tagline, `llms.txt`, vision page, and legal pages retain CaaS references
- [ ] Version bump in `plugin.json`, `CHANGELOG.md`, and `README.md` (PATCH -- cosmetic docs change)
- [ ] The `--space-12` CSS variable definition in `:root` is NOT deleted (still used by `.landing-cta` and `.error-page`)

### Research Insights

**Dead Code Verification:**
After deleting the `.hero-badge` and `.hero-badge-dot` rules, grep the entire CSS file for `hero-badge` to confirm zero remaining references. The badge class is not used in any other template or CSS rule -- confirmed by repo-wide grep (only `index.njk` lines 10-11 and `style.css` lines 410, 421).

**Spacing Math:**
The total vertical space above the h1 changes as follows:
- Before: `padding-top: 128px` + badge height (~36px) + `margin-bottom: 32px` = ~196px from header to h1
- After: `padding-top: 80px` + no badge = 80px from header to h1
- Net reduction: ~116px. This is a significant visual tightening -- intentional for a headline-first hero.

## Test Scenarios

- Given the landing page is loaded, when the hero section renders, then no badge/pill appears above the h1
- Given the hero section, when inspecting top padding, then `padding-top` resolves to 80px (--space-10) not 128px
- Given the CSS file, when searching for `hero-badge`, then zero matches are found
- Given the frontmatter of `index.njk`, when inspecting `description`, then it still contains "The company-as-a-service platform"
- Given all three responsive breakpoints (mobile <= 768px, tablet 769-1024px, desktop > 1024px), when viewing the hero, then vertical spacing looks intentional with no excessive gap above the h1

### Research Insights

**Responsive Verification:**
No mobile-specific padding override exists for `.landing-hero`. The only mobile rule (line 937) changes `h1` font size from `--text-5xl` to `--text-3xl`. The padding change applies uniformly at all breakpoints. At mobile widths, `80px` top padding is still generous -- no risk of the h1 colliding with the fixed header (`--header-h` handles that via `margin-top`).

**Print Stylesheet:**
The print media query (line 989) sets `.landing-hero { margin-top: 0 }` but does not override padding. The padding change is compatible with print output.

## Context

### Files to Edit

| File | Change |
|------|--------|
| `plugins/soleur/docs/index.njk` | Delete lines 10-13 (`.hero-badge` div) |
| `plugins/soleur/docs/css/style.css` | Line 407: `--space-12` to `--space-10`; delete lines 410-427 (badge CSS) |
| `plugins/soleur/plugin.json` | Patch version bump |
| `plugins/soleur/CHANGELOG.md` | Add entry |
| `plugins/soleur/README.md` | Update version |

### CaaS Positioning Retained Elsewhere

The "Company-as-a-Service" phrase remains in 10+ locations across the docs site:

- `index.njk` frontmatter `description` (SEO meta tag)
- `site.json` tagline
- `llms.txt` (LLM-facing site description)
- `pages/vision.njk` (h2 title + body text)
- 5 legal documents (terms, cookie policy, AUP, GDPR, disclaimer, privacy)

No SEO or positioning loss.

### Relevant Learnings

- **Landing page grid orphan regression** (`knowledge-base/learnings/2026-02-22-landing-page-grid-orphan-regression.md`): When modifying landing page layout, verify all responsive breakpoints. The hero section has no grid, but padding changes should be visually checked at mobile/tablet/desktop.
- **Docs site CSS variable inconsistency** (`knowledge-base/learnings/2026-02-22-docs-site-css-variable-inconsistency.md`): Use `--color-accent` not `--accent`. Not directly relevant here but good to be aware of when touching the CSS file.

### Research Insights

**CSS Variable Audit:**
The `--space-12` variable (`:root` line 72) is used in 3 places total:
1. `.landing-hero` padding (line 407) -- being changed to `--space-10`
2. `.landing-cta` padding (line 627) -- unrelated, keep as-is
3. `.error-page` padding (line 932) -- unrelated, keep as-is

Do NOT remove `--space-12` from `:root`. It remains in use.

**`--color-accent` in Deleted Rules:**
The deleted `.hero-badge` rule references `var(--color-accent)` for text color and border. The deleted `.hero-badge-dot` references `var(--color-accent)` for background and box-shadow. These are the correct variable name (not the broken `--accent` shorthand noted in the learnings). No action needed -- the rules are being deleted entirely.

## MVP

### plugins/soleur/docs/index.njk (lines 8-14, after edit)

```njk
    <!-- Hero -->
    <section class="landing-hero">
      <h1>Build a Billion-Dollar Company. Alone.</h1>
```

### plugins/soleur/docs/css/style.css (lines 404-410, after edit)

```css
  /* Landing page: Hero */
  .landing-hero {
    margin-top: var(--header-h);
    padding: var(--space-10) var(--space-5) var(--space-10);
    text-align: center;
  }
  .landing-hero h1 {
```

## References

- Vision page with full CaaS positioning: `plugins/soleur/docs/pages/vision.njk`
- Landing page template: `plugins/soleur/docs/index.njk`
- Landing page styles: `plugins/soleur/docs/css/style.css`
- CSS token definitions: `plugins/soleur/docs/css/style.css` lines 25-90 (`:root`)
