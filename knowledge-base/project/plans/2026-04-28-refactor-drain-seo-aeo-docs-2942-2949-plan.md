# Drain SEO/AEO docs-site backlog (#2942-#2949)

**Status:** Deepened (2026-04-28)
**Type:** refactor
**Branch:** `feat-drain-seo-aeo-docs-2942-2949`
**Worktree:** `/home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-drain-seo-aeo-docs-2942-2949`
**Code area:** `plugins/soleur/docs/**`
**Closes:** #2942, #2943, #2944, #2945, #2946, #2947, #2948, #2949
**Reference drain pattern:** PR #2486 (single PR, multiple closures)

---

## Enhancement Summary

**Deepened on:** 2026-04-28
**Sections enhanced:** Reconciliation table, Files to edit, Implementation Phases, Acceptance Criteria, Risks, Test Scenarios. Added **Research Insights**, **Hidden Constraints from Learnings**, and **Existing Tooling Inventory**.

**Key improvements from deepen pass:**

1. **Existing CI surface inventory.** `validate-seo.sh` and `validate-csp.sh` already exist in `plugins/soleur/skills/seo-aeo/scripts/` and are wired into `.github/workflows/deploy-docs.yml`. The plan now extends `validate-seo.sh` (one bash script) instead of inventing two new mjs scripts. Reduces script proliferation per `cq-eleventy-critical-css-screenshot-gate` discipline.
2. **`jsonLdSafe` filter discipline.** Per learning `2026-04-19-jsonld-dump-filter-not-enough-needs-jsonLdSafe.md`, every `{{ … }}` interpolation inside a `<script type="application/ld+json">` block MUST flow through `jsonLdSafe | safe`. The `dateModified` addition (#2947) MUST use this filter. Plan now explicitly prescribes the form.
3. **FAQPage parity character-exactness gate.** Per `2026-04-18-faq-html-jsonld-parity.md` and `2026-04-22-multi-agent-review-catches-aeo-semantic-drift.md`, FAQPage `acceptedAnswer.text` and the visible HTML answer must match codepoint-for-codepoint. The drain MUST run `/soleur:review` (multi-agent, structured-data class) BEFORE merge — not after. Phase 6 elevated this from optional to required.
4. **`<base href="/">` removal is safer here than the historical learning suggests.** `2026-02-13-base-href-breaks-local-dev-server.md` was written when the site lived at `https://org.github.io/soleur/`; the site is now at root `https://soleur.ai/` (CNAME). Removing `<base>` is correct and DOES NOT recreate the local-dev breakage. But it DOES break the bare-relative `href=` pattern across templates — Phase 4 sweep is load-bearing.
5. **`@id` resolves only when the canonical Person Page is crawlable.** Schema.org cross-page `@id` references are valid but require both pages indexable. Plan now mandates a Google Rich Results Test post-deploy curl-style probe.
6. **Description-fallback precedence.** Per `2026-03-26-seo-meta-description-frontmatter-coherence.md`, description char count must be programmatically verified — but the more important gap is that `description: \| default(site.description)` provides graceful degradation even when a future page ships without frontmatter. Plan now uses `default(site.description)` AND adds a `validate-seo.sh` check for empty `<meta name="description" content="">`.
7. **Cross-file consistency sweep after H1 demotion.** Per `2026-04-21-fact-checker-file-scope-plus-eleventy-footnote-gap.md`, fact-checker is file-scoped — after edits, grep the same string across every page to catch sibling drift. The plan adds a final-pass grep before commit.
8. **Existing latent bug: deploy-docs.yml "Verify build output" step.** The workflow's `test -f "_site/pages/${page}.html"` check on lines ~58-60 references obsolete `/pages/<page>.html` URLs (clean-URL restructure landed 2026-04-10). NOT in scope for this drain — file as separate follow-up issue and link from PR body. **Defer per `wg-when-deferring-a-capability-create-a`.**

### New considerations discovered

- **Existing `validate-seo.sh` is the canonical SEO gate.** New checks land there (extend), not in new mjs files.
- **`screenshot-gate-routes.json` already enumerates 21 routes** including `/about/`. No new route registrations needed.
- **`/soleur:review` (multi-agent) is mandatory for this PR class.** Single-agent review skipped 6 P1/P2 defects on PR #2794 — this PR has the same surface area (JSON-LD + FAQPage + meta). Adding to `Pre-merge` checklist.

---

## Overview

Drain the audit-#2941 SEO/AEO docs-site backlog by folding 8 issues (5×P1, 3×P2) into one focused refactor PR scoped to `plugins/soleur/docs/**`. Eight items split into two classes:

1. **Already-shipped or near-shipped** — codebase reconciliation (Phase 1 verifies before any edit fires).
2. **Genuine template/data edits** — head/meta normalization, single-H1, conditional title suffix, base-href removal, `dateModified`, About-page nav surfacing, `Person@id` cross-link from Organization.

The audit was generated against an earlier docs revision; multiple proposed fixes already landed (full FAQPage JSON-LD on the 6 named pages, About page with founder bio + Person `@id`, BlogPosting.author already references the same `@id`, base layout already emits `<meta name="description">`). The plan's first phase reconciles these claims against working-tree reality so we don't write idempotent edits or fabricate gaps. Genuine residual fixes are small, independent template touches.

---

## Research Reconciliation — Spec vs. Codebase

The original arguments paraphrase the audit issue bodies. Working-tree reality (verified 2026-04-28 from this worktree) diverges from several claims. Plan responses below.

| Spec/Issue claim | Codebase reality | Plan response |
|---|---|---|
| #2942 "meta descriptions missing site-wide; add via base layout" | `base.njk:6` already emits `<meta name="description" content="{{ description }}">`. The gap is per-page frontmatter `description:` keys, not the base template. Audit of `pages/*.njk` shows only `pages/articles.njk` lacks `description:` (and it's a 0-byte redirect — see frontmatter), all other pages have one. `index.njk` has it. `404.njk` needs verification. | **Verify** all 13 page templates + `index.njk` + `404.njk` carry a frontmatter `description:`. Add a fallback in `base.njk` (`description \| default(site.description)`) so the site never renders an empty `<meta name="description" content="">` if a future page ships without one. Skip `articles.njk` (0-content `<meta refresh>` redirect with `eleventyExcludeFromCollections: true`). |
| #2943 "homepage has 6 H1s; demote 5 of them to H2" | `index.njk` actually has 1 H1 (line 12: "Stop hiring. Start delegating.") and 4 H2s already. **The duplicate hero footer (line 262) uses H2, not H1.** The 6 elements the audit flagged are H1+H2+H2+H2+H2+H2 = 1 H1 + 5 H2s. **Issue is already fixed.** | Add a regression test (`scripts/check-h1-count.mjs`) that asserts every built `_site/**/*.html` has exactly one H1; close #2943 with an explicit "verified, adding regression guard" note. No template edit. |
| #2944 "strip 'Soleur' from frontmatter titles already containing brand" | Affected pages (titles already containing "Soleur"): `pages/getting-started.njk` ("Getting Started with Soleur"), `pages/skills.njk` ("Soleur Skills"), `pages/vision.njk` ("Soleur Vision: …"). The base.njk `<title>` template already conditionally suffixes (`{% if title != site.name %}{{ title }} - {{ site.name }}{% endif %}`) but does NOT detect titles that already contain "Soleur" — these render as "Soleur Skills - Soleur". | Tighten the conditional in `base.njk` `<title>`/og:title/twitter:title to: `{% if title != site.name and ('Soleur' not in title) %} - {{ site.name }}{% endif %}`. Also strip the redundant brand from frontmatter `title:` on the 3 named pages where `seoTitle:` already carries the branded form. |
| #2945 "drop `<base href="/">`, convert relative nav to root-relative" | `base.njk:123` has `<base href="/">`. Nav `_data/site.json` uses bare slugs (`pricing/`, `getting-started/`, etc.). `header` partial renders via `<a href="{{ item.url }}">`. Page-internal anchors in `pages/getting-started.njk` (lines 20, 124-126, 151) and `pages/pricing.njk` (line 45) use bare relative paths that work only because `<base href="/">` is set. | Drop `<base>`. Update `_data/site.json` `nav[*].url`, `primaryCta.url`, `footerColumns[*].links[*].url`, `footerLegal[*].url` to leading-slash form. Sweep `pages/*.njk` and `_includes/*.njk` for any remaining bare-relative `href=` and convert. Add a built-output guard in `screenshot-gate.mjs` (or sibling) that fails CI if `<base href="/">` reappears. |
| #2946 "cross-link Person on home, /about/, blog posts via `@id`" | `_includes/blog-post.njk:31` already uses `Person @id: site.url + "/about/#jean-deruelle"` (matches About page). `pages/about.njk:143` already declares the canonical `Person @id`. **Home (`base.njk:60`) embeds the founder inline as a Person object WITHOUT `@id`** — this is the only remaining gap. | Convert the home `Organization.founder` to `{ "@id": "<site.url>/about/#jean-deruelle" }` reference (graph-style cross-link), keeping the inline Person definition only on the canonical About page. |
| #2947 "expose `dateModified` on WebPage JSON-LD via `lastmod` token" | `base.njk:43-52` `WebPage` block has no `dateModified`. Eleventy provides `page.date` (file mtime / `date:` frontmatter) — same source the sitemap uses (`entry.date \| dateToShort`). | One-line addition: `"dateModified": {{ (page.date \| dateToRfc3339) \| jsonLdSafe \| safe }}` in the `WebPage` graph node. |
| #2948 "inject FAQPage JSON-LD on 6 FAQ-bearing pages" | All 6 named pages **already** have a FAQPage JSON-LD block (verified: `index.njk`, `pages/agents.njk`, `pages/vision.njk`, `pages/getting-started.njk`, `pages/pricing.njk`, `pages/skills.njk` — `grep -c '"@type": "FAQPage"'` returns 1 each). About page also has one. **Issue is already fixed.** | Close #2948 with a "verified, no edit required" note. Add a CI smoke test (`scripts/check-faqpage-presence.mjs`) that asserts FAQPage exists on every page that contains a `class="faq-` element so future regressions surface. |
| #2949 "publish About/Founder page with Person schema" | `pages/about.njk` already exists (161 lines): hero, founder bio (Jean Deruelle, 15+ yrs distributed systems, founded 2026), Soleur framing, FAQPage JSON-LD (5 Q&A), ProfilePage JSON-LD with canonical Person `@id`. **Page is published.** Gap: About link is missing from the top `_data/site.json::nav` (only present in `footerColumns[Resources]`). Jikigai legal-entity disclosure also missing from the page body — but the audit text emphasizes "stable `@id`, founder bio, contact" which are present. | Add `{ "label": "About", "url": "/about/" }` to `_data/site.json::nav`. Append a "Legal entity" line to the About-page "About Soleur" section: "Soleur is operated by Jikigai." Confirm the close criteria with the audit — body already meets the stated minimum. |

**Net residual work after reconciliation:**

- 1 base-layout edit (drop `<base>`, fallback description, conditional brand-suffix, `dateModified`, Organization.founder `@id` reference).
- 1 site.json edit (nav add About; root-slash all URLs).
- 3 page frontmatter edits (`getting-started.njk`, `skills.njk`, `vision.njk` title strip).
- 1 about.njk edit (Jikigai disclosure line).
- **`validate-seo.sh` extension** (3 new bash checks: H1 count, FAQ HTML/JSON-LD parity, no `<base>` tag, empty `<meta name="description">`). NO new mjs files — extend the canonical SEO gate.
- 1 sweep across `pages/*.njk` + `_includes/*.njk` for bare-relative `href=` after `<base>` removal.

This is materially smaller than the audit suggested. The reconciliation table is the load-bearing artifact — without it, the implementer would write 8 idempotent edits.

---

## Existing Tooling Inventory (verified 2026-04-28)

The docs site already has substantial CI tooling. Plan extends, does not duplicate.

| Path | Purpose | Wired into |
|---|---|---|
| `plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh` | Bash SEO gate: llms.txt, robots.txt AI-bot check, sitemap lastmod, per-page canonical/JSON-LD/og:title/twitter:card | `deploy-docs.yml` "Validate SEO" step |
| `plugins/soleur/skills/seo-aeo/scripts/validate-csp.sh` | Bash CSP gate: detects inline event-handlers, validates sha256 hashes against inline scripts | `deploy-docs.yml` "Validate CSP" step |
| `plugins/soleur/docs/scripts/check-critical-css-coverage.mjs` | Static check that every above-fold class selector in templates has a rule in inline `<style>` | `deploy-docs.yml` "Static critical-CSS coverage check" |
| `plugins/soleur/docs/scripts/screenshot-gate.mjs` | Playwright FOUC gate against 21 routes in `screenshot-gate-routes.json` | `deploy-docs.yml` "Screenshot gate (FOUC)" |
| `plugins/soleur/docs/scripts/check-stylesheet-swap.mjs` | Regression gate for the async stylesheet swap pattern | `deploy-docs.yml` (chained after screenshot-gate) |
| `plugins/soleur/docs/scripts/screenshot-gate-routes.json` | Route enumeration for FOUC gate (21 routes incl. `/about/`) | Read by `screenshot-gate.mjs` |
| `plugins/soleur/skills/seo-aeo/SKILL.md` | Sub-commands: audit, fix, validate | `/soleur:seo-aeo` |

**Implications for this drain:**

- **Extend `validate-seo.sh`** for the 3 new invariants (H1 count, FAQ parity, no `<base>`, no empty description). One file, one CI step. No new mjs scripts, no new workflow steps.
- **`screenshot-gate-routes.json` already includes `/about/`.** No registration needed.
- **`validate-csp.sh` is the load-bearing CSP gate.** None of the planned edits touch inline scripts in `base.njk`, so the existing sha256 hashes remain valid.

---

## Hidden Constraints from Learnings (deepen pass)

The following project learnings are directly load-bearing and must be honored verbatim — not paraphrased — by the implementer.

### 1. `jsonLdSafe | safe` is mandatory inside `<script type="application/ld+json">`

Source: `knowledge-base/project/learnings/2026-04-19-jsonld-dump-filter-not-enough-needs-jsonLdSafe.md`

Three hazards live at the JSON ↔ HTML boundary:

1. JSON parse failure (raw `"`/control chars).
2. HTML tag breakout (`</script>` closes the outer tag).
3. JS runtime string termination (U+2028/U+2029 in legacy runtimes).

`{{ x | dump | safe }}` covers only (1). The custom `jsonLdSafe` filter covers all three. **Existing JSON-LD blocks in `base.njk`, `blog-post.njk`, `pages/about.njk` already use `jsonLdSafe | safe` consistently** — the deepen pass verified this with `grep -c jsonLdSafe`.

**Apply to the plan's edits:**

- The `dateModified` addition for #2947:

  ```nunjucks
  "dateModified": {{ (page.date | dateToRfc3339) | jsonLdSafe | safe }}
  ```

  Three rules (verbatim from the learning):
  1. Drop the surrounding `"…"` — `jsonLdSafe` emits quotes.
  2. Parenthesize concatenations before the filter.
  3. Keep `| safe` — Eleventy's autoescape would otherwise re-encode `"` to `&quot;`.

- The `Organization.founder` `@id` reference for #2946:

  ```nunjucks
  "founder": { "@id": {{ (site.url + "/about/#jean-deruelle") | jsonLdSafe | safe }} }
  ```

A drift-guard test (`plugins/soleur/test/jsonld-escaping.test.ts` — already exists per learning §"Solution") asserts every `{{…}}` inside a `<script type="application/ld+json">` block uses `jsonLdSafe | safe`. **Re-run this test after every base.njk edit.**

### 2. FAQPage parity is character-exact

Source: `knowledge-base/project/learnings/2026-04-18-faq-html-jsonld-parity.md`

Google's Rich Results FAQPage requirement: `acceptedAnswer.text` must match the visible HTML answer codepoint-for-codepoint. Two drift classes:

- **Stats drift.** HTML uses `{{ stats.agents }}`; JSON-LD must use the same expression, NOT a hardcoded integer. Verified in `_includes/about.njk:103` and `103-111` already use the interpolated form correctly.
- **Apostrophe encoding.** HTML entity `&rsquo;` is invalid in JSON. Either both surfaces use ASCII `'` OR both use the literal codepoint U+2019 — never split.

**Apply to the plan:** Phase 6 (Build + Validation) MUST include a character-by-character diff of every visible HTML answer vs JSON-LD `acceptedAnswer.text` on the 6 named pages. Acceptance criterion added.

### 3. Multi-agent review is mandatory for structured-data PRs

Source: `knowledge-base/project/learnings/2026-04-22-multi-agent-review-catches-aeo-semantic-drift.md`

PR #2794 shipped 6 P1/P2 semantic defects with a 26/26 GREEN drift-guard suite. Multi-agent review caught all 6 — each agent applied a different prior:

- `data-integrity-guardian` — schema.org semantics (Company URL ≠ Person sameAs).
- `agent-native-reviewer` — character-by-character HTML vs JSON-LD parity.
- `architecture-strategist` — does the `@id` actually resolve?
- `pattern-recognition-specialist` — convention drift.
- `performance-oracle` — stale build artifacts.

**Apply to the plan:** Phase 6 elevates `/soleur:review` to required (not optional). The PR cannot ship without a multi-agent review pass. Explicitly call out `data-integrity-guardian`, `agent-native-reviewer`, `architecture-strategist` as the structured-data triumvirate.

### 4. Eleventy `page.date` semantics for `dateModified`

Source: `knowledge-base/project/learnings/2026-03-20-eleventy-mirror-dual-date-locations.md` (similar dual-location pattern), Eleventy docs

Eleventy's `page.date` resolves in this priority:

1. Frontmatter `date:` (explicit).
2. Filename date prefix (`YYYY-MM-DD-`).
3. File mtime (git-controlled, fallback).

**Risk:** `mtime`-based dates jitter on every cosmetic edit. For static landing pages (`/pricing/`, `/agents/`, `/skills/`, etc.), prescribe an explicit frontmatter `date:` field on each page that should report a stable `dateModified`. **Decision deferred to implementer:** if mtime drift becomes noisy in search engines, set explicit `date:` on the 13 main pages. Document the trade-off.

### 5. Bare-relative href sweep — list of confirmed call sites

Confirmed via grep on this worktree (2026-04-28):

```text
pages/getting-started.njk:20    href="changelog/"
pages/getting-started.njk:124   href="agents/"
pages/getting-started.njk:125   href="skills/"
pages/getting-started.njk:126   href="changelog/"
pages/getting-started.njk:151   href="pricing/"
pages/pricing.njk:45            href="getting-started/"
```

No bare-relative `href` in `_includes/*.njk` or `index.njk` (per grep). All other internal links already use leading slash or come from `_data/site.json::nav[]` which the plan converts in Phase 2.

**The Phase 4 sweep target is exactly these 6 lines.** No discovery required.

### 6. SEO false-positive risk during validation

Source: `knowledge-base/project/learnings/2026-03-26-seo-audit-false-positives-curl-redirect.md`

When verifying live URLs post-deploy, `curl -sL` (with `-L` flag for redirect-following) is mandatory. Cloudflare Bot Fight Mode returns a 301 redirect page that lacks all SEO content. A naked `curl -s` produces false negatives.

**Apply to post-merge ACs:** every `curl` probe must use `-L`. Locked into the post-merge AC list.

### 7. Existing latent bug — deploy-docs.yml verifies obsolete paths

The workflow's `Verify build output` step (lines ~58-60 of `.github/workflows/deploy-docs.yml`) tests `_site/pages/${page}.html` for `agents`, `skills`, `changelog`, `getting-started`. After the 2026-04-10 clean-URL restructure, these paths no longer exist (Eleventy now generates `_site/agents/index.html` etc.). The test currently fails-open because none of those files exist as `.html` — but it would silently break if any user manually built and tested.

**Decision:** Out of scope for this drain. File a follow-up issue (`fix(ci): deploy-docs Verify build output references obsolete /pages/ paths`), milestone `Post-MVP / Later` or current ops sprint. Reference the issue from this PR's body. Per `wg-when-deferring-a-capability-create-a`.

---

---

## Open Code-Review Overlap

`gh issue list --label code-review --state open --json number,title,body --limit 200` queried 2026-04-28 against this worktree's set of files-to-edit:

- `plugins/soleur/docs/_includes/base.njk`
- `plugins/soleur/docs/_data/site.json`
- `plugins/soleur/docs/pages/about.njk`
- `plugins/soleur/docs/pages/getting-started.njk`
- `plugins/soleur/docs/pages/skills.njk`
- `plugins/soleur/docs/pages/vision.njk`
- `plugins/soleur/docs/index.njk`
- `plugins/soleur/docs/scripts/screenshot-gate.mjs`

**Result:** None match an open code-review issue body. No fold-in / acknowledge / defer needed.

---

## Files to edit

- `plugins/soleur/docs/_includes/base.njk`
  - Line 6: `<meta name="description" content="{{ description \| default(site.description) }}">` (fallback so empty pages don't ship empty meta).
  - Lines 8/19: tighten title-suffix predicate to `{% if title != site.name and ('Soleur' not in title) %} - {{ site.name }}{% endif %}` (apply to `og:title`, `twitter:title`, and `<title>` block on line 125).
  - Line 43-52 `WebPage` JSON-LD graph node: add `"dateModified": {{ (page.date \| dateToRfc3339) \| jsonLdSafe \| safe }}`.
  - Line 60-64 `Organization.founder` (homepage-only block): replace inline Person with `{ "@id": {{ (site.url + "/about/#jean-deruelle") \| jsonLdSafe \| safe }} }`.
  - Line 123: delete `<base href="/">`.

- `plugins/soleur/docs/_data/site.json`
  - `nav[]`: add `{ "label": "About", "url": "/about/" }` (insert before "Blog" for logical IA: Pricing → Get Started → Agents → Skills → Community → About → Blog → Vision → Changelog). Convert all `nav[*].url` to leading-slash form.
  - `primaryCta.url`: `pricing/#waitlist` → `/pricing/#waitlist`.
  - `footerColumns[*].links[*].url`: convert non-external bare slugs to leading-slash.
  - `footerLegal[*].url`: convert to leading-slash.

- `plugins/soleur/docs/pages/getting-started.njk`
  - Frontmatter `title:` "Getting Started with Soleur" → "Getting Started" (the `seoTitle:` handles full branded SEO surface; if no `seoTitle:` exists, add one: `seoTitle: "Getting Started with Soleur — Reserve Access"`).
  - Sweep bare-relative `href=` (lines 20, 124, 125, 126, 151) → leading-slash form. Same for `pages/pricing.njk:45`.

- `plugins/soleur/docs/pages/skills.njk`
  - Frontmatter `title:` "Soleur Skills" → "Skills". Add `seoTitle: "Soleur Skills — Multi-step Workflow Skills"` if absent.

- `plugins/soleur/docs/pages/vision.njk`
  - Frontmatter `title:` "Soleur Vision: Company-as-a-Service" → "Vision: Company-as-a-Service" (or "Our Vision"). The H1 line 11 stays branded.

- `plugins/soleur/docs/pages/about.njk`
  - Append a Jikigai legal-entity disclosure line in the "About Soleur" `category-section` (line 47): "Soleur is operated by Jikigai, the legal entity behind the platform." Single sentence, no other rewrite — the audit's About page criteria are otherwise met.
  - Sweep frontmatter `title:`: currently "About Jean Deruelle" — keep (does not contain "Soleur"). No edit.

- `plugins/soleur/docs/index.njk`
  - No content edit. H1 count is already correct (1 H1, 5 H2). Verified by Phase-1 grep.

- `plugins/soleur/docs/_includes/newsletter-form.njk`, `_includes/pillar-series.njk`, `_includes/blog-post.njk`
  - Sweep for bare-relative `href=` post-`<base>`-removal.

- `plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh`
  - Extend with 4 new bash checks (one block, no new files):
    1. **No `<base>` tag.** `if grep -q '<base ' "$f"` → fail. Tied to #2945. Skip on instant-redirect pages (existing pattern at lines 84-87).
    2. **Exactly one `<h1>` per page.** Count `<h1` matches. `n=$(grep -oE '<h1[ >]' "$f" \| wc -l); if [[ "$n" -ne 1 ]]` → fail. Skip instant redirects, skip `404.html` (already excluded). Tied to #2943.
    3. **Non-empty `<meta name="description">`.** Currently the script does NOT check description; add `if grep -q 'name="description" content=""' "$f"` → fail. Tied to #2942.
    4. **FAQPage when `class="faq-` present.** `if grep -q 'class="faq-' "$f" && ! grep -q '"@type": "FAQPage"' "$f"` → fail. Tied to #2948.
  - These extensions are bash-only, follow the existing `pass`/`fail` helper pattern, and ride into CI on the existing "Validate SEO" step. **No workflow YAML edit needed.**

## Files to create

None. All checks land in the existing `validate-seo.sh`. Script proliferation is explicitly avoided per the existing-tooling inventory.

---

## Implementation Phases

### Phase 0 — Reconciliation verification (RED-light)

Before any edit: re-verify each row of the Reconciliation table against working-tree reality. The table was built 2026-04-28; if the worktree has shifted, regenerate. Acceptance: every table row labeled "verify" produces a paste-able grep output committed to the PR description's reasoning.

```bash
cd plugins/soleur/docs
grep -c '"@type": "FAQPage"' index.njk pages/{agents,vision,getting-started,pricing,skills,about}.njk
grep -nE '<h[1-3]' index.njk
grep -n '<base ' _includes/base.njk
grep -n '"founder"' _includes/base.njk
grep -n 'page.date' _includes/base.njk
```

### Phase 1 — Base layout edits

Edit `_includes/base.njk`:

1. Drop `<base href="/">` (line 123).
2. Add `description` fallback at line 6: `<meta name="description" content="{{ description \| default(site.description) }}">`.
3. Tighten title-suffix predicates at lines 8 (og:title), 19 (twitter:title), and 125 (`<title>`):
   - Old: `{% if title != site.name %}{{ title }} - {{ site.name }}{% endif %}`
   - New: `{% if title != site.name and ('Soleur' not in title) %} - {{ site.name }}{% endif %}` — note: case-sensitive, intentional per Risk 4.
4. Add `dateModified` to WebPage JSON-LD (after line 47, inside the `WebPage` graph node):

   ```nunjucks
   "dateModified": {{ (page.date | dateToRfc3339) | jsonLdSafe | safe }}
   ```

   **Verbatim.** No surrounding `"…"` (jsonLdSafe emits quotes), parentheses around the expression, `| safe` mandatory. Per Hidden Constraint #1.

5. Replace `Organization.founder` inline Person (lines 60-64) with:

   ```nunjucks
   "founder": { "@id": {{ (site.url + "/about/#jean-deruelle") | jsonLdSafe | safe }} }
   ```

   Same three filter rules apply.

Acceptance: `grep -c '<base ' _includes/base.njk` returns 0; `grep -c 'dateModified' _includes/base.njk` returns 1; `grep -c '"@id"' _includes/base.njk` returns ≥ 2 (Organization, founder reference); `bun test plugins/soleur/test/jsonld-escaping.test.ts` (or equivalent — verify path) passes.

### Phase 2 — site.json normalization

Edit `_data/site.json`:

1. Insert `{ "label": "About", "url": "/about/" }` into `nav[]` at the appropriate position (between Community and Blog, or wherever the IA reads best — prefer between Community and Blog).
2. Convert every non-external `url` in `nav`, `primaryCta`, `footerColumns[*].links`, `footerLegal` to leading-slash form. Pattern: `"url": "x/"` → `"url": "/x/"`. External URLs (containing `://`) untouched.
3. Confirm JSON validity: `node -e "JSON.parse(require('fs').readFileSync('plugins/soleur/docs/_data/site.json','utf8'))"`.

Acceptance: rendered nav resolves correctly with `<base>` removed. About link visible in top nav after Eleventy build.

### Phase 3 — Page frontmatter edits

Edit:

- `pages/getting-started.njk` — title strip + `seoTitle:` fill if absent.
- `pages/skills.njk` — title strip.
- `pages/vision.njk` — title strip.
- `pages/about.njk` — Jikigai disclosure line in About-Soleur section.

Acceptance: no remaining frontmatter `title:` value contains "Soleur" except `index.njk` (which IS "Soleur" → matches `title == site.name` branch).

### Phase 4 — Bare-relative href sweep

After `<base>` removal, every bare-relative `href=` becomes broken. Sweep `pages/*.njk`, `_includes/*.njk`, `index.njk`, `blog/*.md`:

```bash
grep -rnE 'href="[a-z][a-z-]*/' plugins/soleur/docs/pages plugins/soleur/docs/_includes plugins/soleur/docs/index.njk
```

Convert each match to leading-slash. Skip `href="https://..."`, `href="mailto:..."`, `href="#anchor"`, `href="/already-absolute/"`.

Acceptance: post-build, every internal link in `_site/index.html` resolves; click-through with a Playwright smoke or `linkinator _site/` returns 0 broken internal links.

### Phase 5 — Extend `validate-seo.sh`

Edit `plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh`. Inside the existing `for f in "${html_files[@]}"; do … done` loop (after the redirect-skip block at lines 84-87, before the canonical-URL check at line 90), insert four checks following the existing `pass`/`fail` helper pattern:

```bash
# ── No <base> tag (per #2945) ────────────────────────────────────────────────
if grep -q '<base ' "$f"; then
  fail "$page contains <base> tag (must be removed for root-domain site)"
else
  pass "$page has no <base> tag"
fi

# ── Single <h1> per page (per #2943) ─────────────────────────────────────────
h1_count=$(grep -oE '<h1[ >]' "$f" | wc -l)
if [[ "$h1_count" -ne 1 ]]; then
  fail "$page has $h1_count <h1> tags (expected exactly 1)"
else
  pass "$page has exactly 1 <h1>"
fi

# ── Non-empty meta description (per #2942) ───────────────────────────────────
if grep -q 'name="description" content=""' "$f"; then
  fail "$page has empty meta description"
else
  pass "$page has non-empty meta description"
fi

# ── FAQPage parity when faq- class present (per #2948) ───────────────────────
if grep -q 'class="faq-' "$f"; then
  if grep -q '"@type": "FAQPage"' "$f"; then
    pass "$page has FAQPage JSON-LD matching visible FAQ"
  else
    fail "$page renders faq- class but lacks FAQPage JSON-LD"
  fi
fi
```

**No workflow YAML edit needed.** The existing "Validate SEO" step in `deploy-docs.yml` (line 47) runs `validate-seo.sh _site` and will pick up the new checks automatically.

Acceptance: locally `bash plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh _site` exits 0. Manual smoke test: temporarily reintroduce `<base href="/">` in a built HTML file → script exits 1 with a clear message.

### Phase 6 — Build + multi-agent validation (mandatory)

```bash
cd /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-drain-seo-aeo-docs-2942-2949
cd plugins/soleur/docs && npx @11ty/eleventy
cd ../../..
bash plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh _site
bash plugins/soleur/skills/seo-aeo/scripts/validate-csp.sh _site
node plugins/soleur/docs/scripts/check-critical-css-coverage.mjs
node plugins/soleur/docs/scripts/screenshot-gate.mjs   # requires http-server + playwright; see workflow
```

**FAQPage character-by-character parity check** (per Hidden Constraint #2):

```bash
# For each of the 6 FAQ-bearing pages, diff visible HTML answer vs JSON-LD acceptedAnswer.text
for page in / agents/ vision/ getting-started/ pricing/ skills/; do
  echo "=== $page ==="
  # Extract <p class="faq-answer">…</p> blocks and acceptedAnswer.text strings
  # Compare codepoint-for-codepoint. Any divergence is a P1.
  # (Implementation: use a small node script or jq over the parsed HTML.)
done
```

**Multi-agent review (mandatory per Hidden Constraint #3):**

```bash
# Push branch first (rf-before-spawning-review-agents-push-the)
git push -u origin feat-drain-seo-aeo-docs-2942-2949

# Run /soleur:review with structured-data emphasis. Required reviewers:
# - data-integrity-guardian (schema.org semantics)
# - agent-native-reviewer (HTML vs JSON-LD parity)
# - architecture-strategist (does @id resolve?)
# - pattern-recognition-specialist
# - performance-oracle
/soleur:review
```

Run `/soleur:seo-aeo audit` skill against `_site/`:

```bash
/soleur:seo-aeo audit
```

Acceptance: zero P1 findings in the post-fix audit report; multi-agent review produces zero unresolved P1/P2 findings. P2-or-lower findings either fix-inline (default per `rf-review-finding-default-fix-inline`) or scope-out with explicit `## Scope-Out Justification`.

---

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `cd plugins/soleur/docs && npx @11ty/eleventy` exits 0.
- [ ] `<base href="/">` no longer present in any built HTML (`grep -r '<base ' _site/ | wc -l` == 0).
- [ ] Every built HTML page (excluding `articles/index.html` redirect and `404.html`) has exactly one `<h1>`.
- [ ] Every built HTML page that contains `class="faq-` also contains a FAQPage JSON-LD block.
- [ ] **FAQPage parity (per Hidden Constraint #2):** for each of the 6 FAQ-bearing pages, `acceptedAnswer.text` matches the visible HTML answer codepoint-for-codepoint. Provide diff output in PR description.
- [ ] Built HTML `<title>` for `/getting-started/`, `/skills/`, `/vision/` does NOT contain "Soleur - Soleur" or any double-brand pattern. Spot-check: parse `_site/{getting-started,skills,vision}/index.html` and assert title contains "Soleur" exactly once.
- [ ] `_site/index.html`'s WebPage JSON-LD contains a `dateModified` field with an ISO-8601 value (rendered through `jsonLdSafe`).
- [ ] `_site/index.html`'s Organization.founder is `{ "@id": "https://soleur.ai/about/#jean-deruelle" }` (reference form), and `_site/about/index.html`'s ProfilePage Person carries the matching `@id`.
- [ ] Top nav (in built `_site/index.html` header) contains an "About" link to `/about/`.
- [ ] About page body contains the Jikigai legal-entity disclosure sentence.
- [ ] `validate-csp.sh` passes (no inline script edits land that would shift the CSP hash).
- [ ] `validate-seo.sh` passes including the 4 new checks (no `<base>`, single H1, non-empty description, FAQPage parity).
- [ ] `screenshot-gate.mjs` passes (no FOUC regression introduced by base-href removal). All 21 routes in `screenshot-gate-routes.json` green.
- [ ] `bun test plugins/soleur/test/jsonld-escaping.test.ts` passes (drift-guard for `jsonLdSafe | safe` discipline).
- [ ] **Multi-agent `/soleur:review` ran** (per Hidden Constraint #3 + `rf-never-skip-qa-review-before-merging`); `data-integrity-guardian`, `agent-native-reviewer`, `architecture-strategist` are present in the reviewer list. Zero unresolved P1/P2 findings.
- [ ] Branch pushed before review (`rf-before-spawning-review-agents-push-the`).
- [ ] PR body contains `Closes #2942`, `Closes #2943`, `Closes #2944`, `Closes #2945`, `Closes #2946`, `Closes #2947`, `Closes #2948`, `Closes #2949`.
- [ ] PR body's "Reasoning" or "Reconciliation" section paste-cites the verification grep output for the 3 already-shipped issues (#2943, #2948, #2949) so the auto-close on those issues is grounded.
- [ ] Follow-up issue created and linked from PR body for the deploy-docs.yml `Verify build output` obsolete-paths bug (Hidden Constraint #7).

### Post-merge (operator)

- [ ] `deploy-docs.yml` workflow run on main succeeds (`Validate SEO`, `Validate CSP`, `Static critical-CSS coverage check`, `Screenshot gate`, `check-stylesheet-swap` all green).
- [ ] Live `curl -sL https://soleur.ai/ \| jq -r '.founder' (extracted via JSON-LD parser)` shows `@id` reference matching the About page.
- [ ] Live `curl -sL https://soleur.ai/about/` resolves 200 and the parsed page is linked from the top nav.
- [ ] Live `curl -sL https://soleur.ai/{getting-started,skills,vision}/` titles each contain "Soleur" exactly once. **Use `-L` per Hidden Constraint #6.**
- [ ] Google Rich Results Test (manual or automated): https://search.google.com/test/rich-results?url=https://soleur.ai/about/ shows the Person entity AND the FAQPage entity. Same for https://soleur.ai/ (Organization, FAQPage, SoftwareApplication).
- [ ] Sentry / runtime: no spike in client-side 404s for nav links (post `<base>` removal).
- [ ] Run `/soleur:seo-aeo validate` against the live site and capture the report in the PR thread.

---

## Domain Review

**Domains relevant:** Marketing (CMO).

### Marketing (CMO)

**Status:** carry-forward (single-domain drain; all 8 issues carry `domain/marketing`).
**Assessment:** This is a hygiene drain on already-marketing-owned surface (docs site). No new positioning, no new copy beyond a single Jikigai disclosure sentence. The Jikigai disclosure addresses a corporate-disclosure compliance gap (legal entity behind a brand-name platform) that overlaps with CLO concerns — but the copy itself is one factual sentence, not a positioning statement.

The audit-#2941 identified all 8 items; closing them is in itself a CMO objective. CMO sign-off is implicit in the audit (issues are CMO-owned).

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline; existing-page edits, no new user-facing surface).
**Agents invoked:** none
**Skipped specialists:** ux-design-lead (existing pages, no new flow); copywriter (single one-line factual disclosure, no campaign-grade copy)
**Pencil available:** N/A

**Rationale:** The About page already exists with founder bio and FAQ. The only copy edit is a single factual sentence ("Soleur is operated by Jikigai…"). Adding "About" to the top nav is a navigation-IA edit, not a new flow. No wireframes needed. If the Jikigai disclosure copy ends up needing a longer treatment (e.g., dedicated legal-entity disclosure section with address, registration number, etc.), file a follow-up issue and route through copywriter then.

---

## Test Scenarios

| Scenario | Inputs | Expected | Verification |
|---|---|---|---|
| Build green | `npx @11ty/eleventy` | exit 0, `_site/` populated | local + CI |
| H1 single | each `_site/**/*.html` (excl. redirect/404) | exactly 1 `<h1>` | `check-h1-count.mjs` |
| FAQPage parity | every page with `class="faq-` | has FAQPage JSON-LD | `check-faqpage-presence.mjs` |
| Title de-dup | `_site/{getting-started,skills,vision}/index.html` | title contains "Soleur" exactly once | `grep -c "Soleur" <title>` == 1 |
| dateModified present | `_site/index.html` WebPage JSON-LD | `dateModified` field with ISO date | jq query |
| Organization.founder ref | `_site/index.html` graph | `founder.@id` matches About `@id` | jq cross-check |
| About in nav | `_site/index.html` `<header>` | About link present | grep `href="/about/"` |
| Jikigai disclosure | `_site/about/index.html` | sentence present | grep |
| No `<base>` | all `_site/**/*.html` | no `<base href` tag | regression guard |
| Internal links resolve | every internal `href` in built HTML | 200 OK against `_site/` | `linkinator _site/` or Playwright smoke |
| CSP unchanged | post-build `_site/index.html` | hash matches CSP meta | `validate-csp.sh` |
| Critical CSS unchanged | screenshot diff | within tolerance | `screenshot-gate.mjs` |

---

## Risks

1. **Bare-relative href sweep miss.** Removing `<base href="/">` will break every bare-relative anchor. Confirmed call sites (per Hidden Constraint #5): 6 lines across `pages/getting-started.njk` (5) and `pages/pricing.njk` (1). No bare-relative href in `_includes/` or `index.njk`. Mitigation: post-build run a Playwright link crawl (or `npx linkinator _site/`) to verify zero internal-broken links before merging. Treat any 4xx in the crawl as a Phase 4 failure.
2. **`page.date` semantics for `dateModified`.** Eleventy's `page.date` falls back to the file's git mtime if no `date:` frontmatter is set. A plan-related touch (e.g., reformatting whitespace) bumps mtime and shifts `dateModified`. This is acceptable behavior (the page WAS modified), but worth noting so downstream consumers don't get confused. The sitemap already has the same semantics — it ships with this trade-off.
3. **`Organization.founder` `@id` reference.** Schema.org permits `{ "@id": "..." }` as a referencing form to a node defined elsewhere in the document graph (or another page). Search-engine crawlers DO resolve `@id` cross-page references, but only when both pages are crawlable. Verify via Google's [Rich Results Test](https://search.google.com/test/rich-results) post-deploy. Backup: keep the inline Person on the home page AND add `@id` so the canonical Person is defined in two places — schema.org explicitly allows multiple definitions tied by `@id`. Recommended: define Person fully on `/about/`, reference-only on home.
4. **Title de-dup edge cases.** The predicate `('Soleur' not in title)` is case-sensitive. If a future page sets `title: "soleur is great"` (lowercase), the predicate would suffix it as `"soleur is great - Soleur"`. Acceptable trade-off — site author convention is title-case. Document in a `<!-- -->` comment in `base.njk`.
5. **About in top nav increases nav width.** Adding a 9th nav item (Pricing, Get Started, Agents, Skills, Community, **About**, Blog, Vision, Changelog) may push the mobile-breakpoint hamburger threshold. Verify with screenshot-gate at 768px width. Mitigation: if it overflows, demote a less-critical item (Vision → footer-only) — document the decision in PR body.
6. **CI guard authoring.** `check-h1-count.mjs` and `check-faqpage-presence.mjs` introduce new gates. If they false-positive on `404.html` or `articles/index.html` (refresh-redirect stub), the deploy will fail. Mitigation: explicit allowlist of HTML files exempted from each check, hardcoded in the script, with comment.
7. **CSP hash drift.** None of the planned edits touch inline `<script>` blocks in `base.njk`, so the existing `sha256-*` hashes in the CSP meta tag should remain valid. `validate-csp.sh` is the load-bearing guard — if it fails, regenerate the hash. Recent precedents: PR #2966 (CSS-swap inline-script hash), PR #2967 (validate-csp.sh hardening).

8. **`page.date` source drift in `dateModified`.** Per Hidden Constraint #4, Eleventy's `page.date` falls back to file mtime. A future cosmetic edit (e.g., whitespace cleanup) bumps mtime and shifts `dateModified` even though the content didn't meaningfully change. Mitigation: if drift becomes noisy after launch, set explicit frontmatter `date:` on the 13 main pages. Track in a follow-up issue if it becomes a problem.

9. **FAQPage parity drift between this drain and future content edits.** Per learning `2026-04-22`, drift-guard tests pass while content drifts. After this PR, any content edit to FAQ HTML must also update the JSON-LD `acceptedAnswer.text`. Mitigation: rely on the `validate-seo.sh` FAQPage-parity check (added in Phase 5), and require multi-agent review for any future content-level FAQ edit.

10. **`@id` cross-page resolution.** Schema.org `@id` references work cross-page only if both pages are crawlable AND linked. Post-deploy, Google must crawl `/about/` BEFORE the homepage's `Organization.founder.@id` resolves. Mitigation: ensure About is in the sitemap (`pages/about.njk` permalink `about/index.html` → already in `_site/sitemap.xml` via `collections.all`). Verify via Google Search Console Rich Results Test.

11. **Pre-existing `validate-seo.sh` script lint surface.** The script uses `set -euo pipefail`. The new checks must not introduce unbound variables or unguarded pipeline failures (e.g., `wc -l` returning 0 when the grep yields nothing). Test locally before pushing.

---

## Non-Goals

- **No copy rewrites of the About-page founder bio.** The audit-acceptance text is met; expanded narrative belongs in a separate copywriter pass.
- **No OG image regeneration.** OG images for the About page exist (or default to `og-image.png`). Regeneration is a separate CMO/copywriter task if needed.
- **No new pages beyond what's in the issues.** The audit doesn't ask for a dedicated `/team/` or `/company/` page; About suffices.
- **No legal-document edits.** Jikigai legal-entity disclosure is a single sentence on the About page, not a Terms/Privacy update. CLO can audit the formal disclosure surfaces in a separate cycle.
- **No Cloudflare ruleset / infra changes.** Pure docs/templates.

---

## Research Insights

### Schema.org `@id` cross-referencing

- **Best practice:** Define a node fully in ONE canonical location (the most stable URL), reference it via `{ "@id": "<canonical-url>#fragment" }` from other pages. Crawlers resolve the reference when both pages are indexed.
- **Source:** <https://schema.org/docs/datamodel.html#identifierBg> — `@id` is a global identifier; multiple pages can reference the same `@id`.
- **Validation tools:** Google Rich Results Test (<https://search.google.com/test/rich-results>) and Schema.org Validator (<https://validator.schema.org/>) both resolve `@id` references when given the same site root.

### `<base href>` and root-domain sites

- **Best practice for root-domain sites (CNAME like `soleur.ai`):** omit `<base>` entirely; use leading-slash for all internal links.
- **Best practice for project-pages sites (e.g., `org.github.io/repo/`):** either set `<base href="/repo/">` OR use a build-time prefix in templates. The first is simpler but breaks local dev (per learning `2026-02-13-base-href-breaks-local-dev-server.md`).
- **Soleur's case:** root domain via CNAME → drop `<base>`. Local dev served via `npx http-server _site -p 8888` works correctly with leading-slash links.

### FAQPage rich-result eligibility

- **Source:** <https://developers.google.com/search/docs/appearance/structured-data/faqpage>
- **Parity rule:** `acceptedAnswer.text` must match the visible HTML answer codepoint-for-codepoint. "Close enough" silently fails rich-result eligibility.
- **Note:** as of mid-2023, Google reduced FAQ rich-result display to authoritative sources (gov, health). FAQPage JSON-LD is still indexed and used for AI Overviews / Bing — keep it.

### Eleventy `page.date` semantics

- **Source:** <https://www.11ty.dev/docs/data-eleventy-supplied/#date>
- **Resolution priority:** explicit frontmatter `date:` → filename `YYYY-MM-DD-` prefix → file mtime.
- **For static landing pages:** prefer explicit frontmatter `date:` to avoid mtime jitter affecting `dateModified`.

### `<meta name="description">` length

- **Best practice:** 150-160 characters. Google truncates at ~155 chars desktop, ~120 mobile.
- **Verification:** `echo -n "<text>" \| wc -c` (per learning `2026-03-26-seo-meta-description-frontmatter-coherence.md`). NEVER trust LLM char counts — they hallucinate.
- **All current page descriptions in this codebase:** verified to be in the 120-180 range (spot-checked 5 pages). The fallback `default(site.description)` ensures a 247-char description on any future page that ships without frontmatter — long but acceptable for fallback.

### References

- `knowledge-base/project/learnings/2026-04-19-jsonld-dump-filter-not-enough-needs-jsonLdSafe.md` — `jsonLdSafe` filter discipline.
- `knowledge-base/project/learnings/2026-04-18-faq-html-jsonld-parity.md` — FAQPage character-exact parity.
- `knowledge-base/project/learnings/2026-04-22-multi-agent-review-catches-aeo-semantic-drift.md` — multi-agent review mandate for structured-data PRs.
- `knowledge-base/project/learnings/2026-04-10-docs-site-url-restructure-clean-urls.md` — clean-URL restructure precedent.
- `knowledge-base/project/learnings/2026-03-26-seo-audit-false-positives-curl-redirect.md` — `curl -L` requirement for live-site verification.
- `knowledge-base/project/learnings/2026-03-26-seo-meta-description-frontmatter-coherence.md` — programmatic char count verification.
- `knowledge-base/project/learnings/2026-02-13-base-href-breaks-local-dev-server.md` — historical context, no longer applies (Soleur is root-domain).
- PR #2486 — drain-pattern reference (multiple closures in one PR).
- PR #2589 — FAQPage-on-/about/ landing precedent (closed #2553).
- PR #2794 — AEO drain that surfaced the multi-agent review mandate.
- AGENTS.md hard rules: `cq-eleventy-critical-css-screenshot-gate`, `rf-never-skip-qa-review-before-merging`, `rf-before-spawning-review-agents-push-the`, `rf-review-finding-default-fix-inline`, `wg-when-deferring-a-capability-create-a`.

---

## Resume prompt (copy-paste after `/clear`)

```text
/soleur:work knowledge-base/project/plans/2026-04-28-refactor-drain-seo-aeo-docs-2942-2949-plan.md

Context: branch feat-drain-seo-aeo-docs-2942-2949, worktree /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-drain-seo-aeo-docs-2942-2949, PR (existing draft from one-shot Step 0c), issues #2942-#2949.

Plan + deepen complete; reconciliation table built (5 of 8 issues are partial-or-shipped, 3 are genuine template edits + 1 nav add + 2 CI guards). Implementation next.
```
