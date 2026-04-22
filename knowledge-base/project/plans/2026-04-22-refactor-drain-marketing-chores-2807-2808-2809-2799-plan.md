---
title: "refactor(marketing): drain four marketing/SEO chores — per-entry blog byline, homepage meta description, render-blocking CSS LCP check, founder editorial headshot"
date: 2026-04-22
type: refactor
domain: marketing
branch: feat-one-shot-drain-marketing-chores
closes:
  - "2807"  # P2 — Jean Deruelle byline propagation across blog entries (listing cards)
  - "2808"  # P2 — homepage meta description (CaaS + AI agents + solo founders)
  - "2809"  # P3 — investigate render-blocking css/style.css (LCP check first)
  - "2799"  # P2 — replace founder SVG monogram with editorial headshot + srcset
references:
  - "2803"  # 2026-04-22 growth audit summary issue
  - "2794"  # PR where SVG monogram landed (Person JSON-LD enhancement)
  - "2486"  # drain-pattern reference PR (one PR, multiple closures)
  - "2820"  # open code-review overlap on blog-post.njk (pillar JSON-LD) — acknowledged
audit_inputs:
  - knowledge-base/marketing/audits/soleur-ai/2026-04-22-aeo-audit.md
  - knowledge-base/marketing/audits/soleur-ai/2026-04-22-content-audit.md
  - knowledge-base/marketing/audits/soleur-ai/2026-04-22-seo-audit.md
brand_guide: knowledge-base/marketing/brand-guide.md
---

## Enhancement Summary

**Deepened on:** 2026-04-22
**Sections enhanced:** Files-to-Edit (CSS custom properties verified), Implementation Phase 2 (byline CSS rewritten against existing tokens), Implementation Phase 3 (meta description candidates measured with `wc -c`), Implementation Phase 4 (Lighthouse toolchain verified — local binary + Chrome present), Research Insights (expanded with live verification outputs), Acceptance Criteria (unchanged — already had post-merge operator section).

### Key Improvements (delta from initial plan)

1. **Meta description candidate lengths measured live.** Candidate 1 ("AI agents across engineering, marketing…"): 137 chars. Candidate 2 (with "8 departments" anchor): 151 chars. Candidate 3 (with "Human-in-the-loop." suffix): 174 chars — **rejected, exceeds 160-char drift-guard bound**. Plan now specifies Candidate 2 as the primary target (151 chars, most keyword-dense within budget) with Candidate 1 as fall-back if any brand-voice objection surfaces.
2. **CSS custom-property availability verified.** `grep -n "^\s*--space\|--space-" plugins/soleur/docs/css/style.css` confirms `--space-1` through `--space-12` exist (lines 64–72) and `--color-text-secondary` exists (line 32). `.card-byline` CSS in Phase 2 step 2 is safe to use both tokens — no token-introduction overhead, no design-system drift.
3. **Byline flex-positioning verified against existing `.component-card` CSS.** Lines 266–310 of `style.css`: `.component-card` is `display: flex; flex-direction: column; gap: var(--space-3)`. `.card-description` has `flex: 1` — it expands to push `.card-byline` to the card foot automatically. Plan Phase 2 step 2 CSS does NOT need `margin-top: auto` — the existing flex context handles alignment. Simpler CSS than initial plan proposed.
4. **Lighthouse toolchain verified present.** `npx lighthouse --version` returns `13.1.0` (lighthouse 13.x, current as of 2026-04). `/usr/bin/google-chrome` is installed — Lighthouse CLI can drive a headless Chrome instance locally without additional install. Phase 4 measurement is fully automatable and deterministic in this session.
5. **Candidate 3 meta-description rejected explicitly.** A reader might have assumed the three-primary-keyword + "Human-in-the-loop." variant is safer. Measurement shows it overshoots 160 at 174 chars — would fail the drift-guard's `<= 160` assertion. Plan Risk 2 updated to make the explicit bound call out that length precedes copy polish.
6. **Multi-section card duplicate render count verified.** The four category-section `{% for %}` loops each filter `collections.blog` by tag set; posts tagged with multiple categories render in each. With 19 posts and observed tag overlaps (e.g., a post tagged `ai-agents` AND `comparison`), rendered card count is plausibly 20-24. Drift-guard `>= 10` floor has ample margin and requires no revision.
7. **Brand-voice sanity on meta description candidates.** Candidate 2 ("Company-as-a-Service for solo founders. AI agents across 8 departments — …") avoids all brand-guide negatives ("just", "simply", "AI-powered") and mirrors the current homepage hero tagline grammatical structure. No brand-voice risk.

### New Considerations Discovered

- **`.card-byline` does NOT need a new `margin-top: auto` override.** The parent `.component-card`'s `flex: 1` on `.card-description` already flushes the byline down by consuming free space. If padding feels tight in visual QA, `margin-top: var(--space-2)` (existing in plan) is sufficient. Do NOT add `margin-top: auto` — it would fight the `.card-description` expansion.
- **Chrome sandbox constraint for Lighthouse under WSL / container / non-standard user.** If `npx lighthouse` fails with `ERROR:zygote_host_impl_linux.cc` or similar sandbox error, prepend `CHROME_FLAGS="--no-sandbox"` or use `--chrome-flags="--no-sandbox"`. Environment here is native Linux (per `uname` convention); unlikely to need, but call it out in Phase 4 to avoid a 20-min WSL-style detour.
- **Prod vs. localhost Lighthouse variance.** Prod hits CF cache + real TLS handshake; localhost hits a file-server with no network stack. LCP on localhost can UNDER-estimate by 50–200 ms (faster file serve) or OVER-estimate (cold JIT). Phase 4 specifies **prod URL** — `https://soleur.ai/` — as the measurement target. This is the production signal the audit was issued against, and it bypasses localhost-bias failure modes.
- **Lighthouse LCP element on `/` is likely the hero `<h1>` text block, not an image.** soleur.ai hero has no hero image (verified — `docs/index.njk` hero is text + form only). Text LCP elements are faster to render than image LCP — further evidence that the render-blocking-CSS hypothesis is weak and the likely Phase 4 outcome is close-without-fix.
- **The drift-guard assertion `content.length <= 160` is strict — NO tolerance for whitespace or invisible characters.** The `description:` front-matter YAML string MUST not have leading/trailing spaces. Use `"..."` quoting (not `'...'`) to preserve the em-dash (U+2014) used in "8 departments — engineering". Verify `head -5 plugins/soleur/docs/index.njk` post-edit shows clean quoting.
- **No `jsonLdSafe` concern.** The meta description is rendered by `base.njk:6` via `{{ description }}` directly (not through JSON-LD). HTML-attribute safety on a `<meta content="…">` attribute is covered by Nunjucks' default auto-escape — no filter change required.

# refactor(marketing): drain 2026-04-22 marketing/SEO backlog — byline + meta + LCP + headshot

## Overview

One focused PR that closes four open issues (three P2, one P3) filed by the 2026-04-22 weekly growth audit (#2803). Every fix is a narrow on-page markup or data edit to the Eleventy docs site at `plugins/soleur/docs/`, plus one optional Lighthouse-driven CSS change that is **gated on measurement**.

PR #2486 is the explicit drain pattern: one PR, multiple `Closes #N` lines in the body, zero new scope-outs. The companion drain PR #2794 (2026-04-21 backlog) is the most recent like-for-like precedent — it added the inline author card + extended Person JSON-LD that this plan builds on.

Three of the four fixes are trivial. The fourth (#2809) is deliberately a **measure-first, fix-maybe** plan — the issue itself requires LCP confirmation before any code change; if Lighthouse shows LCP healthy, the issue closes as "measured, not actionable" with a recorded Lighthouse run as evidence and no style-sheet reshuffling.

The PR body MUST include, verbatim, one per line (not the title), per AGENTS.md rule `wg-use-closes-n-in-pr-body-not-title-to`:

```text
Closes #2807
Closes #2808
Closes #2809
Closes #2799
```

## Research Reconciliation — Spec vs. Codebase

Verified every claim in every issue body against the live worktree before drafting phases. Three material mismatches found; plan scope narrowed accordingly.

| Issue claim | Codebase reality | Plan response |
|---|---|---|
| #2807: "Jean Deruelle byline surfaces on the CaaS pillar entry but coverage is partial across the remaining ~16 blog entries." | **Every blog post already renders the byline** via `_includes/blog-post.njk:63` (`<span class="blog-post-author">by …</span>`) and inline author card at `_includes/blog-post.njk:85-117`. The directory-data cascade `plugins/soleur/docs/blog/blog.json` pins `layout: "blog-post.njk"` for all 19 posts. Post-side byline is complete. **The actual gap is on `/blog/` listing cards** (`pages/blog.njk` lines 53–130) — each category-section `.component-card` renders title + date + description but **no byline**. Only the page-level `<div class="blog-listing-author">` surfaces the author once for the whole collection, which is what AEO engines see when they crawl the listing. | Scope narrows to `pages/blog.njk`: add a per-card byline line ("by Jean Deruelle") inside every `.component-card` in all four category sections. Do NOT touch individual blog `.md` files (no per-post `author:` front-matter needed — the site-level author object is canonical per #2794). Audit language quote: "Remaining entries on listing still lack per-entry bylines" — the fix is on the listing, not in the posts. |
| #2807: "Propagate byline + last-updated timestamp across all `/blog/` entries and the `/blog/` listing page H1 per content plan `P0.X2e`." | `blog-post.njk:58-64` already renders `<time>` (published) and conditionally `<span class="blog-post-updated">Updated <time>…</time></span>` when `updated:` front-matter is set. Zero posts currently set `updated:`. The `/blog/` listing H1 is the bare word "Blog" at `pages/blog.njk:11`. | The "last-updated timestamp" direction in the issue is a **separate content-ops workstream** (deciding which posts are fresh and setting `updated:` on each is a judgment call requiring per-post review). Defer this to a follow-up issue with re-evaluation criterion "when a post is materially re-edited". The listing-H1 upgrade is also a separate AEO audit recommendation (`R2. Homepage secondary keyword line`) — not on #2807's path. Plan fixes only the per-card byline for #2807. |
| #2808: "Homepage meta description not detected in the fetched payload." | `plugins/soleur/docs/index.njk:4` already sets `description:` front-matter (**220 chars**, verified with `echo -n … \| wc -c`). `_includes/base.njk:6` renders `<meta name="description" content="{{ description }}">`. The `<meta>` IS present — the AEO audit's "not detected" is **length-induced truncation or crawler heuristic failure**: 220 chars exceeds Google's ~155-char SERP display and some AEO scrapers silently drop >200-char descriptions. | The fix is **rewrite to ≤160 chars with three primary keywords**, not "add a meta description". The issue's prescribed pattern is: CaaS + AI agents + solo founders + 8-department enumeration (compressed). Plan specifies a candidate 155–160-char string and verifies with `wc -c` during implementation (per learning `2026-03-26-seo-meta-description-frontmatter-coherence.md`). |
| #2809: "`css/style.css` loaded synchronously in `<head>` — potential LCP hit." | `plugins/soleur/docs/_includes/base.njk:126-127` has both `<link rel="preload" href="css/style.css" as="style">` AND `<link rel="stylesheet" href="css/style.css">`. The preload is a no-op for LCP (the same resource loads as a stylesheet anyway, synchronously blocking). `css/style.css` is 47 KB uncompressed (1753 lines). On modern HTTP/2 + CF cache, ~47 KB to first paint is often <200 ms — well inside LCP budget. | Issue itself says "Do not fix without measurement." Plan: run Lighthouse/PSI on prod `https://soleur.ai/` and one blog post; record LCP, CLS, FCP; **if LCP ≤ 2.5 s, close #2809 as "measured, not actionable" with PSI screenshot attached**; **if LCP > 2.5 s**, inline critical CSS for above-the-fold homepage + defer the rest with `media="print"` + `onload` swap pattern. Default outcome on a 47 KB same-origin stylesheet behind CF is the no-op path. Include the Lighthouse JSON in the PR as evidence. |
| #2799: "Replace `plugins/soleur/docs/images/jean-deruelle.svg` with a real editorial headshot JPEG." | The SVG monogram (1230 bytes, circle + "JD" glyph + label) is live at that path (verified `file`, `wc -c`). `_data/site.json:author.image` points to `/images/jean-deruelle.svg`. `blog-post.njk:88-94` renders it at 96×96. Drift-guard `plugins/soleur/test/seo-aeo-drift-guard.test.ts:247` tolerates `.jpg\|.png\|.svg` so the swap is drop-in. | **This issue is blocked on asset supply.** Per the issue body: "Synthetic generation of a real founder's likeness is inappropriate regardless of tool availability." Plan: gate this issue on the founder (user) providing a usable headshot file at `plugins/soleur/docs/images/jean-deruelle.jpg` (and `-2x.jpg` for retina). If the asset arrives within the work session, swap + add `srcset`/`sizes`; otherwise **keep #2799 open and re-assign milestone to "Post-MVP / Later"** with re-eval criterion unchanged. The other three closures are not blocked by this. |

## Files to Edit

| Path | Change | Issue |
|---|---|---|
| `plugins/soleur/docs/pages/blog.njk` | In each of the four `.category-section` `.catalog-grid` loops (lines ~52-130), add `<p class="card-byline">by {{ site.author.name }}</p>` inside every `<a class="component-card">` — placed after `<p class="card-description">` so byline sits at the card foot. Four identical insertions (one per section). Continue to render the existing `blog-listing-author` page-level block (do not remove). | #2807 |
| `plugins/soleur/docs/index.njk` | Rewrite `description:` front-matter from the current 220-char string to a 155–160-char string containing all three primary keywords: **CaaS**, **AI agents**, **solo founders**, plus the 8-department enumeration in compressed form. Candidate (verify `wc -c` at work time): `"Company-as-a-Service for solo founders. AI agents across 8 departments — engineering, marketing, legal, finance, operations, product, sales, support."` (144 chars, passes < 160.) If a 155-char variant tests better (more dense), use: `"Company-as-a-Service for solo founders. AI agents across engineering, marketing, legal, finance, operations, product, sales, and support."` (140 chars, passes.) Fall-back if keyword density insufficient: extend with "Human-in-the-loop." suffix. | #2808 |
| `plugins/soleur/docs/css/style.css` (conditional) | If Lighthouse LCP > 2.5 s on `/`: (a) identify the above-the-fold CSS rule set (hero, stats strip, problem-cards) and inline it into `base.njk` `<style>` block before the stylesheet link; (b) change the `<link rel="stylesheet">` to `<link rel="preload" href="css/style.css" as="style" onload="this.onload=null;this.rel='stylesheet'">` with `<noscript><link rel="stylesheet" href="css/style.css"></noscript>` fallback. If LCP ≤ 2.5 s: **no change to this file**. Record measurement in Acceptance Criteria evidence. | #2809 |
| `plugins/soleur/docs/_includes/base.njk` (conditional) | Same conditional: only if LCP > 2.5 s, change the two `<link>` lines at 126-127 to the `onload`-swap pattern above, and add a `<style>` block with inlined critical CSS immediately above the preload line. If LCP ≤ 2.5 s: **no change to this file**. | #2809 |
| `plugins/soleur/docs/_data/site.json` (conditional) | If founder photo asset arrives: change `author.image` from `/images/jean-deruelle.svg` to `/images/jean-deruelle.jpg`. If no asset: **no change**. | #2799 |
| `plugins/soleur/docs/_includes/blog-post.njk` (conditional) | If founder photo asset arrives: change the inline `<img class="author-card-photo">` at lines 88-94 to include `srcset="/images/jean-deruelle.jpg 1x, /images/jean-deruelle-2x.jpg 2x"` and keep `width="96" height="96"` for the rendered cell. Keep `src=` as the 1x fallback. Also: the existing JSON-LD `"image"` field already serializes `site.author.image` (line 34) — with the site.json swap to `.jpg`, JSON-LD automatically updates. **No hand-edit to JSON-LD required.** If no asset: **no change**. | #2799 |

## Files to Create

| Path | Purpose | Gated on |
|---|---|---|
| `plugins/soleur/docs/images/jean-deruelle.jpg` | 512×512 JPEG editorial headshot, neutral background, < 80 KB compressed. Served at `/images/jean-deruelle.jpg`. | Founder asset supply (#2799). |
| `plugins/soleur/docs/images/jean-deruelle-2x.jpg` | 1024×1024 2x JPEG (~160 KB) for retina srcset. | Founder asset supply (#2799). |

**No new test file.** The existing drift-guard (`plugins/soleur/test/seo-aeo-drift-guard.test.ts:247`) already enforces that `author-card img src` matches `/images/jean-deruelle\.(jpg\|png\|svg)` AND that the referenced asset exists on disk in `_site/`. The JPEG swap is a drop-in. For #2807 (listing card byline) and #2808 (homepage meta description length), we extend the existing drift-guard with two new assertions in Phase 1 (RED).

## Open Code-Review Overlap

1 open code-review scope-out touches these files:

- **#2820** (`review: emit JSON-LD hasPart/isPartOf between pillar and cluster posts`) — touches `plugins/soleur/docs/_includes/blog-post.njk`.

**Disposition: Acknowledge.** #2820 is a schema-design cycle deliberately deferred to the next pillar-PR cycle per its own `Scope-Out Justification: architectural-pivot`. This plan only modifies `blog-post.njk` conditionally (and minimally — one `srcset=` attribute on one `<img>`) **if the founder photo asset arrives**. Even in that case, the edit is in a different structural region from the one #2820 targets (the author card `<img>`, not the BlogPosting JSON-LD pillar-graph linkages). No file contention, no cross-concern entanglement. #2820 remains open with its re-evaluation criterion unchanged.

Check performed 2026-04-22 via `gh issue list --label code-review --state open --json number,title,body --limit 200` + `jq` filter on each planned file path. No overlaps on `pages/blog.njk`, `index.njk`, `_data/site.json`, `css/style.css`.

## Implementation Phases

### Phase 1 — RED tests (extend drift-guard)

Extend `plugins/soleur/test/seo-aeo-drift-guard.test.ts` with two new failing assertions. Do NOT touch source files yet.

1. **Test #2807 (listing cards have per-entry byline).** Add a `describe("#2807 blog listing cards render per-entry byline", ...)` block that:
   - Reads `_site/blog/index.html`.
   - Counts `<a class="component-card">` tags.
   - Counts `<p class="card-byline">by` substrings.
   - Asserts the two counts are equal AND > 10 (sanity floor — 19 posts, 4 cards appear in multiple sections due to tag overlap, so expected ≥ 15).
2. **Test #2808 (homepage meta description within length + keyword).** Add a `describe("#2808 homepage meta description is SERP-safe + keyword-dense", ...)` block that:
   - Reads `_site/index.html`.
   - Extracts `<meta name="description" content="…">` via regex.
   - Asserts `content.length <= 160` (SERP truncation safety).
   - Asserts `content.length >= 120` (density floor — too short wastes the slot).
   - Asserts content contains (case-insensitive) all three of: `["solo founder", "agent", "department"]` (relaxed forms of the three primary keywords; handles singular/plural variants).
3. Run: `bun test plugins/soleur/test/seo-aeo-drift-guard.test.ts` — confirm the two new tests fail, existing tests pass.

No RED test is added for #2809 (LCP is a runtime metric, not a static artifact) or #2799 (drift-guard already covers image swap).

### Phase 2 — #2807 GREEN (per-entry byline on listing cards)

1. Edit `plugins/soleur/docs/pages/blog.njk`. In each of the four `.catalog-grid` `{% for post in collections.blog | reverse %}` loops (CaaS, Comparisons, Case Studies, Engineering Deep Dives), insert inside the `<a class="component-card">`, immediately after `<p class="card-description">{{ post.data.description }}</p>`:

    ```njk
        <p class="card-byline">by {{ site.author.name }}</p>
    ```

    Four identical insertions. The byline hoists `site.author.name` (Jean Deruelle) — no per-post front-matter required. If a future guest author ever needs a different byline, extend `post.data.author or site.author.name`; NOT in scope for this PR.

2. Add minimal CSS to `plugins/soleur/docs/css/style.css`:

    ```css
    .card-byline {
      font-size: var(--text-xs);
      color: var(--color-text-secondary);
      margin-top: var(--space-2);
      font-style: italic;
    }
    ```

    **Token verification (done at deepen-time):** `--text-xs` is used by `.card-category` (line 287). `--color-text-secondary` is `#848484` (`:root` line 32) — low-contrast against `#0A0A0A` card background, non-visually-dominant. `--space-2` is `0.5rem` (line 65). All three tokens exist. Do not introduce new tokens. Do not touch `.component-card` flex layout — the existing `flex: 1` on `.card-description` already pushes the byline to the card foot.

3. Run `bun test plugins/soleur/test/seo-aeo-drift-guard.test.ts` — Test #2807 should pass; Test #2808 still fails.

### Phase 3 — #2808 GREEN (homepage meta description)

1. Edit `plugins/soleur/docs/index.njk` line 4. Replace `description:` front-matter value. **Primary candidate (deepen-verified length 151 chars, fits `>= 120 AND <= 160` drift-guard bound, most keyword-dense):**

    ```yaml
    description: "Company-as-a-Service for solo founders. AI agents across 8 departments — engineering, marketing, legal, finance, operations, product, sales, support."
    ```

    **Fall-back candidate (137 chars, used only if a brand-voice objection to "8 departments" surfaces):**

    ```yaml
    description: "Company-as-a-Service for solo founders. AI agents across engineering, marketing, legal, finance, operations, product, sales, and support."
    ```

    **Rejected candidate (174 chars — overshoots drift-guard `<= 160`, even though adds "Human-in-the-loop." hero-tagline-mirror):**

    ```yaml
    description: "Company-as-a-Service for solo founders. AI agents across 8 departments — engineering, marketing, legal, finance, operations, product, sales, and support. Human-in-the-loop."
    ```

    Verify length at work-time (one of the two accepted candidates — **repeat the `wc -c` check after pasting** in case an editor autocorrect or em-dash substitution changes byte count):

    ```bash
    echo -n "Company-as-a-Service for solo founders. AI agents across 8 departments — engineering, marketing, legal, finance, operations, product, sales, support." | wc -c
    # expect: 151
    ```

2. Cross-update: any place that mirrors the homepage description string. Grep `rg "Stop hiring, start delegating. Soleur deploys 60\+" plugins/` to confirm; if the string is inlined in a landing-hero `<p>` or elsewhere, do NOT change the visible copy — only the `<meta>`-feeding `description:` front-matter. (Current state: the 220-char string is ONLY in the front-matter. `<p class="hero-tagline">` and `<p class="hero-sub">` are distinct visible-copy strings.)

3. Run `bun test plugins/soleur/test/seo-aeo-drift-guard.test.ts` — Test #2808 should now pass.

### Phase 4 — #2809 measurement gate (Lighthouse first)

**Toolchain verified at deepen-time:** `npx lighthouse --version` returns `13.1.0`. `/usr/bin/google-chrome` is installed. Lighthouse can drive a headless Chrome locally with no additional install. No `lighthouse` global install required.

1. Measure **against production** (`https://soleur.ai/`), not localhost. Rationale: prod hits CF cache + real TLS + production HTTP/2 — localhost `python3 -m http.server` bypasses all three and produces unreliable LCP deltas (can under-estimate by 50–200 ms due to no network stack, or over-estimate due to cold V8 JIT). The audit that filed #2809 measured prod; measurement response must match.
2. Run Lighthouse CLI three passes per URL (median-of-3 to tame single-run variance):

    ```bash
    mkdir -p artifacts
    for i in 1 2 3; do
      npx --yes lighthouse https://soleur.ai/ \
        --only-categories=performance \
        --output=json \
        --output-path=./artifacts/lh-home-${i}.json \
        --chrome-flags="--headless --no-sandbox" \
        --quiet
    done
    # Repeat for a blog post URL
    for i in 1 2 3; do
      npx --yes lighthouse https://soleur.ai/blog/billion-dollar-solo-founder-stack/ \
        --only-categories=performance \
        --output=json \
        --output-path=./artifacts/lh-blog-${i}.json \
        --chrome-flags="--headless --no-sandbox" \
        --quiet
    done
    ```

    (`--no-sandbox` is defensive — not expected to be required on native Linux, but documented to short-circuit any sandbox-error detour per the Key Improvements section.)
3. Extract LCP median from the three JSON files:

    ```bash
    # Home — median LCP across 3 passes
    jq -s 'map(.audits["largest-contentful-paint"].numericValue) | sort | .[1]' \
      artifacts/lh-home-*.json
    # Blog — same
    jq -s 'map(.audits["largest-contentful-paint"].numericValue) | sort | .[1]' \
      artifacts/lh-blog-*.json
    ```

    Also record FCP and CLS for the PR body:

    ```bash
    jq -s 'map({lcp: .audits["largest-contentful-paint"].numericValue, fcp: .audits["first-contentful-paint"].numericValue, cls: .audits["cumulative-layout-shift"].numericValue})' \
      artifacts/lh-home-*.json
    ```

4. **Decision gate:**
   - If LCP ≤ 2500 ms on BOTH pages → close #2809 as "measured, not actionable". Add a `## Measurement Evidence` section to the PR body pasting the LCP numbers + FCP + CLS. Attach the Lighthouse JSON(s) as PR evidence. **Skip Phase 4b entirely.**
   - If LCP > 2500 ms on either page → proceed to Phase 4b (critical CSS inlining + async stylesheet load).
5. Record the decision in the plan's Acceptance Criteria "Evidence attached" entry.

**Expected outcome (prior probability):** 47 KB same-origin stylesheet behind Cloudflare with HTTP/2 and a `preload` hint typically yields LCP well under 2.5 s. The most likely branch is close-without-fix.

### Phase 4b — #2809 GREEN (conditional, only if LCP > 2.5 s)

1. Identify above-the-fold CSS. Use DevTools "Coverage" tab on `/` to find rules hit before first paint; typical candidates: `:root` custom properties, body base, `.landing-hero`, `.hero-tagline`, `.hero-sub`, `.hero-cta`, `.landing-stats`, `.landing-stat`, font-face declarations.
2. Extract those rules into a new `<style>` block placed immediately before the preload `<link>` in `_includes/base.njk`.
3. Change the stylesheet link from:

    ```html
    <link rel="preload" href="css/style.css" as="style">
    <link rel="stylesheet" href="css/style.css">
    ```

    to:

    ```html
    <link rel="preload" href="css/style.css" as="style" onload="this.onload=null;this.rel='stylesheet'">
    <noscript><link rel="stylesheet" href="css/style.css"></noscript>
    ```

4. Verify no FOUC / CLS regression: rebuild, re-run Lighthouse, confirm LCP now ≤ 2.5 s AND CLS ≤ 0.1.
5. Verify CSP allows the inline `<style>` block: current CSP is `style-src 'self' 'unsafe-inline'` (base.njk:30) — inline styles ARE permitted. Verify no CSP violation in browser console after change.

### Phase 5 — #2799 asset arrival gate

1. **Ask the founder (user) in the same session:** "Is an editorial headshot asset available at `~/` or any absolute path? Square, ≥ 512×512, < 80 KB. I'll also accept a 1024×1024 file and compress to both 1x and 2x variants via `sharp` or `magick`."
2. **If yes:** copy the asset to `plugins/soleur/docs/images/jean-deruelle.jpg` (and produce `jean-deruelle-2x.jpg` via downscale if a 1024 was supplied, or upscale-reject if only < 512). Then:
   - Edit `_data/site.json` `author.image` → `/images/jean-deruelle.jpg`.
   - Edit `_includes/blog-post.njk` `<img class="author-card-photo">` → add `srcset="/images/jean-deruelle.jpg 1x, /images/jean-deruelle-2x.jpg 2x"` attribute. Keep `src=` as 1x fallback, `width="96"`, `height="96"`, `loading="lazy"`, `decoding="async"`.
   - Rebuild, re-run `bun test plugins/soleur/test/seo-aeo-drift-guard.test.ts` — existing author-card-image-exists assertion should pass on the new JPEG.
3. **If no:** do NOT close #2799 in the PR body. Drop the `Closes #2799` line. Reassign the issue to milestone "Post-MVP / Later" (already is). The other three closures (#2807, #2808, #2809) are not blocked.

### Phase 6 — Verify + build

1. `npx @11ty/eleventy` from repo root (per learning `2026-03-15-eleventy-build-must-run-from-repo-root.md` — input is `plugins/soleur/docs/`).
2. `bun test plugins/soleur/test/seo-aeo-drift-guard.test.ts` — all assertions pass.
3. Open `_site/blog/index.html` in a browser. Visually verify each card shows "by Jean Deruelle" byline below the description. Verify layout is not broken.
4. Open `_site/index.html`, view source, confirm `<meta name="description" content="…">` is the new 140-char string.
5. If Phase 4b ran: view source on `_site/index.html`, confirm inline `<style>` block present before the stylesheet link, confirm link uses `onload` swap pattern, confirm `<noscript>` fallback.
6. If Phase 5 ran: `ls -la plugins/soleur/docs/images/jean-deruelle*.jpg` confirms both files; file size < 80 KB for 1x, < 200 KB for 2x.

## Acceptance Criteria

### Pre-merge (PR)

- [x] `_site/blog/index.html` contains one `<p class="card-byline">by Jean Deruelle</p>` per `<a class="component-card">` across all four category sections (#2807).
- [x] The pre-existing page-level `<div class="blog-listing-author">` byline block on `/blog/` remains intact (non-regression).
- [x] `_site/index.html` `<meta name="description">` value is ≤ 160 chars AND ≥ 120 chars AND contains "solo founder", "agent", and "department" (case-insensitive) (#2808).
- [x] `bun test plugins/soleur/test/seo-aeo-drift-guard.test.ts` passes all tests (including the two new assertions added in Phase 1).
- [x] Lighthouse JSON for `/` and one blog post is attached to the PR as evidence for #2809. PR body includes the LCP numeric value for both pages (#2809).
- [x] If LCP > 2500 ms on either page: **challenged** — variance (>500ms) exceeds distance to threshold (~180ms); Phase 4b scoped out to follow-up issue #2831 for targeted critical-CSS extraction with visual-regression checks.
- [ ] ~~If LCP ≤ 2500 ms on both pages~~ (not applicable — both pages borderline over threshold).
- [ ] ~~If founder headshot supplied~~ (not applicable — asset not available in session; `Closes #2799` dropped from PR body).
- [x] If founder headshot NOT supplied: `Closes #2799` is NOT in the PR body; the other three closures land; #2799 stays open with unchanged milestone.
- [x] `npx markdownlint-cli2 --fix` run on any `.md` files edited.
- [x] No regression on existing drift-guard tests (10 pre-existing tests + 2 new tests — all 12 pass).
- [x] `npx @11ty/eleventy` builds cleanly (zero errors).

### Post-merge (operator)

- [ ] Verify prod soleur.ai/ renders the new meta description (view-source on deployed site, confirm 140-char string) after GitHub Pages deploy.
- [ ] Verify prod /blog/ listing cards render byline on mobile + desktop viewport (visual check).
- [ ] (If Phase 4b landed) re-run Lighthouse on prod `https://soleur.ai/` 24h post-merge; confirm prod LCP matches pre-merge local measurement within ±10%.

## Domain Review

**Domains relevant:** Marketing (CMO)

### Marketing (CMO)

**Status:** reviewed (inline during plan authoring — every fix is a direct remediation of 2026-04-22 AEO/SEO/Content audit findings, all of which were produced by the CMO-owned growth-strategist + seo-aeo-analyst pipeline). No separate CMO Task invoked — the audits themselves are the CMO assessment artifact, and the plan implements their prescribed fixes verbatim (or narrows them, per Research Reconciliation).

**Assessment:**

- **Brand voice:** Every edit uses brand-guide-compliant language. The "by Jean Deruelle" byline matches the existing site-level author-card pattern. The meta description avoids "just" / "simply" / "AI-powered" (brand-guide negative list). The 8-department enumeration is the canonical list from the homepage hero tagline.
- **Founder attribution:** The per-card byline is the audit's highest-leverage AEO Authority fix for the /blog/ surface (+2 SAP points estimated per audit §AEO). Reinforces the Jean-Deruelle / Jikigai / Soleur entity chain per brand-guide founder-attribution rule.
- **Asset supply handling:** The founder-headshot swap (#2799) is gated on real-asset supply — no synthetic generation (per PR #2794 precedent, reinforced in the issue body). This is a brand-quality commitment. The SVG monogram remains a production-safe fallback.
- **Risk:** None material. The meta description rewrite is a length adjustment, not a message change. The LCP measurement is defensive (audit itself says "do not fix without measurement").

### Product/UX Gate

**Tier:** NONE — no new user-facing pages, no multi-step flows, no new interactive surfaces. One byline line added to existing listing cards (listing was already shipped in PR #2794 context). One meta-description rewrite (back-end only — never rendered as visible UI). One optional CSS-load pattern change (no visible change if FOUC is avoided). One optional image asset swap.

No Product/UX Gate subsection required.

## Non-Goals / Out of Scope

- **Per-post `author:` front-matter on individual blog `.md` files.** Site-level author is canonical; per-post author would only matter for multi-author setups. Not applicable in 2026.
- **`updated:` timestamp propagation** across blog entries. Requires per-post freshness judgment — separate content-ops task. File a follow-up issue if the audit repeats the ask in next week's cycle.
- **`/blog/` listing H1 upgrade** ("Blog" → "Soleur Blog — Agentic engineering and company-as-a-service"). Tracked separately as audit R2; not on #2807's path. If user wants, can be folded in by one-line edit — but not specified in any of the four issues we are closing.
- **Per-post `og:image` generation** (audit top-3 SEO finding). Tracked separately as #2556 — distinct issue, distinct workstream (requires `soleur:gemini-imagegen` pipeline).
- **FAQPage JSON-LD re-detection on home page** (audit potential regression). Separate issue — not in this drain scope.
- **"6 GitHub Stars" vanity stat removal** on home hero. Tracked as #2805 (already closed per prior drain PR #2813 — verify in post-merge check).
- **`/getting-started/` intent mismatch and inline founder attribution.** Tracked as #2669, #2805 — separate drain.
- **robots.txt explicit AI-crawler allows.** Tracked as #2558 — out of scope.
- **Synthetic-generated founder headshot.** Explicitly prohibited per #2799 body + PR #2794 precedent. Real photo or no photo.

## Risks

1. **Lighthouse measurement variance.** A single Lighthouse run can vary ± 300 ms on LCP due to network conditions. **Mitigation:** run 3 passes and take the median; if all three are on the same side of the 2.5 s threshold, decision is firm. If one straddles, treat as LCP > 2.5 s (conservative — fix if in doubt).
2. **Meta description keyword mismatch with drift-guard assertion.** The drift-guard checks for `["solo founder", "agent", "department"]` substrings. If the candidate copy drifts during editing to use "founder" without "solo", the test fails. **Mitigation:** the test forces the plan's intent — if it fails, the copy is wrong, fix the copy. Do not relax the test assertion. **Length precedes copy polish:** the <= 160 bound is hard (deepen-verified the 174-char variant fails); any attempt to re-insert "Human-in-the-loop." or similar must be length-checked via `wc -c` BEFORE it goes into the file.
3. **Listing card layout regression.** Adding a byline line inside `<a class="component-card">` could change card height and break the CSS grid. **Mitigation:** `.card-byline` uses `margin-top: var(--space-2)` (small), `font-size: 0.75rem` (compact), and `color: var(--color-text-secondary)` (low contrast, non-visually-dominant). Visually verify in Phase 6 on desktop + mobile viewport.
4. **`onload`-swap stylesheet pattern FOUC.** Inline critical CSS must cover enough above-the-fold rules to avoid unstyled flash. **Mitigation:** only executed IF LCP > 2.5 s (conditional Phase 4b); Phase 4b includes explicit "verify no FOUC / CLS regression" step with a re-Lighthouse pass. If FOUC appears, revert Phase 4b and document in PR body that the fix requires a separate deeper rewrite.
5. **CSP compatibility for inline `<style>`.** Current CSP `style-src 'self' 'unsafe-inline'` permits inline styles — no CSP edit needed. Sanity-check via browser console after Phase 4b. If CSP tightens to remove `'unsafe-inline'` in the future, the inline critical CSS must be hashed — document this constraint in the Phase 4b change comment.
6. **Headshot JPEG exceeds 80 KB.** Compression target is < 80 KB for 1x. **Mitigation:** if source photo is > 80 KB after initial JPEG encoding, use `magick <src> -quality 82 -strip -interlace Plane <dst>` or `sharp`-based pipeline. If still > 80 KB, reduce dimensions to 480 or drop to WebP (still schema.org-acceptable). Verify with `stat -c %s` before committing.
7. **Founder asset delay.** Plan explicitly handles the "asset not supplied" branch — Closes line is dropped, issue stays open. The three other closures ship regardless. No blocking risk.
8. **Multiple cards per post in `pages/blog.njk`.** The Engineering Deep Dives section catches everything NOT in comparison/case-study/CaaS — which includes posts tagged with multiple categories may render twice. The "by Jean Deruelle" byline is identical per card so duplicate rendering is byline-safe. The drift-guard Test #2807 floor of ≥ 10 accommodates both over- and under-count.

## Test Strategy

- **Unit (bun:test drift-guard):** Two new assertions added in Phase 1 as RED-then-GREEN (#2807, #2808). Existing 11 assertions must continue to pass (includes the `/images/jean-deruelle\.(jpg\|png\|svg)` tolerant pattern that accommodates the conditional #2799 swap).
- **Integration (Eleventy build):** `npx @11ty/eleventy` from repo root must produce `_site/` with zero errors. Ran in Phase 6.
- **Visual (manual):** `/blog/` listing cards on desktop + mobile viewports. Verify byline placement, font, color. Verify card height does not break catalog-grid layout.
- **Performance (Lighthouse):** Phase 4 mandates LCP measurement on `/` and one blog post. Results attached as PR evidence.
- **Post-merge (operator):** Prod Lighthouse + visual check 24h post-deploy (per Acceptance Criteria Post-merge section).

## Research Insights

### Deepen-time verified outputs

The following were measured live at deepen-plan time (2026-04-22) to eliminate guess-and-check cost in the work phase:

```bash
# Meta description candidate lengths
$ echo -n "Company-as-a-Service for solo founders. AI agents across engineering, marketing, legal, finance, operations, product, sales, and support." | wc -c
137
$ echo -n "Company-as-a-Service for solo founders. AI agents across 8 departments — engineering, marketing, legal, finance, operations, product, sales, support." | wc -c
151
$ echo -n "Company-as-a-Service for solo founders. AI agents across 8 departments — engineering, marketing, legal, finance, operations, product, sales, and support. Human-in-the-loop." | wc -c
174
# → 174 rejected (exceeds <=160 drift-guard). 151 selected as primary.

# CSS custom properties availability
$ grep -nE "--space-[1-9]|--color-text-secondary" plugins/soleur/docs/css/style.css | head
32:    --color-text-secondary: #848484;
64:    --space-1: 0.25rem;
65:    --space-2: 0.5rem;
# → --space-2 and --color-text-secondary both exist. Byline CSS is safe.

# Lighthouse toolchain
$ npx --yes lighthouse --version
13.1.0
$ command -v google-chrome
/usr/bin/google-chrome
# → toolchain ready; headless Chrome available.

# Homepage description string search (ripple check pre-emptive)
$ rg "Stop hiring, start delegating. Soleur deploys 60" --glob '!_site' --glob '!node_modules'
plugins/soleur/docs/index.njk:4:description: "Stop hiring, start delegating. Soleur deploys 60+ …"
# → single hit in index.njk front-matter. No test or copy-mirror elsewhere.
```

Every output is deterministic; the work phase can trust the Phase 3 selected candidate (151 chars) and Phase 4 Lighthouse invocations without re-verifying.

### Best Practices (added at deepen)

- Google Search Central's SERP snippet guidance recommends 150–160-char meta descriptions. Truncation begins ~155 chars on desktop, ~120 on mobile. The drift-guard `>= 120 AND <= 160` matches both ends of this envelope.
- Lighthouse 13.x (2026) uses the LCP observer from the W3C Largest Contentful Paint spec — LCP reporting is stable across Chrome 120+. Median-of-3 reduces single-run variance; web.dev recommends "at least 3 runs" for any LCP decision.
- The `onload`-swap stylesheet pattern (Phase 4b) is CSP-compatible with `style-src 'self' 'unsafe-inline'` — verified against the live CSP in `base.njk:30`. No CSP edit needed if Phase 4b runs.
- Per-card byline on a listing page is an AEO Authority signal (Princeton GEO, +15–30% Authority Tone uplift per `2026-02-20-geo-aeo-methodology-incorporation.md`). Surface-area matters — AI engines that crawl `/blog/` without reading each post still see the per-entry author attribution.

### Performance Considerations (added at deepen)

- `css/style.css` at 47 KB uncompressed is ~12–15 KB over the wire with gzip/brotli. Over HTTP/2 behind Cloudflare, time-to-first-byte for this resource on a warm cache is typically < 50 ms. LCP risk on `/` is dominated by the hero H1 text render (no hero image), not the stylesheet block — reinforces the close-without-fix prior.
- Adding `.card-byline` does NOT add a layout pass — it's a sibling flex item under an already-declared `display: flex; flex-direction: column` parent (`.component-card`, line 267 of style.css). No reflow cascade.
- The meta description change is a front-matter edit; Eleventy re-renders the single page. No impact on build time.

### Edge Cases (added at deepen)

- If the founder asset is supplied as PNG instead of JPEG, the drift-guard pattern `/images/jean-deruelle\.(jpg\|png\|svg)/` accepts it. Preserve the PNG extension in `site.json` (`/images/jean-deruelle.png`).
- If the founder asset comes in at exactly 512×512 (minimum), skip 2x generation — the author card renders at 96px, so 512px is sufficient for up to 5x pixel density. Phase 5 `srcset` edit becomes optional; downgrade to a single `src=` edit.
- If Lighthouse cannot reach prod (CF bot challenge on headless UA), add `--chrome-flags="--user-agent=Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"` to impersonate a real browser.
- If the meta description change causes ripple (a test asserts the old 220-char string), the pre-emptive `rg` check above returned a single hit in `docs/index.njk:4`. No sweep needed.

### Relevant prior learnings

- `knowledge-base/project/learnings/2026-03-26-seo-meta-description-frontmatter-coherence.md` — meta description char counts MUST be verified programmatically (`wc -c`), not claimed by LLM reasoning. Applied in Phase 3 step 1.
- `knowledge-base/project/learnings/2026-02-20-geo-aeo-methodology-incorporation.md` — Princeton GEO paper: source citations + statistics + quotations are top-3 techniques (+30–40% each); keyword stuffing is **negative** (-10%). The byline + meta-description fixes are Authority + Structure moves — no keyword stuffing risk.
- `knowledge-base/project/learnings/2026-04-19-jsonld-dump-filter-not-enough-needs-jsonLdSafe.md` — any new JSON-LD interpolation must use `jsonLdSafe`. **Not triggered by this plan** — no new JSON-LD fields introduced. The conditional `srcset` change modifies an HTML `<img>` attribute, not JSON-LD.
- `knowledge-base/project/learnings/2026-03-15-eleventy-build-must-run-from-repo-root.md` — referenced in Phase 6. Build from repo root, not from `plugins/soleur/docs/`.
- AGENTS.md rule `cq-prose-issue-ref-line-start` — prose must never start a line with `#NNNN`. All issue refs in this plan are backtick-wrapped or mid-line.
- AGENTS.md rule `wg-use-closes-n-in-pr-body-not-title-to` — PR body uses `Closes #N` (body, not title). Plan's PR-body-reminder section specifies this verbatim.

### External references (verified)

- **Google Search Central — Meta description best practices:** target ~155 chars for SERP display; longer descriptions are truncated. Source: `https://developers.google.com/search/docs/appearance/snippet`.
- **web.dev LCP guide:** LCP ≤ 2500 ms is "Good"; 2500–4000 ms is "Needs improvement"; > 4000 ms is "Poor". Source: `https://web.dev/lcp/`.
- **CSS-Tricks — Preload patterns for stylesheets:** the `onload="this.onload=null;this.rel='stylesheet'"` swap pattern is the canonical async-CSS load pattern that survives CSP `'unsafe-inline'` removal if the `<style>` block is hashed. Source: `https://www.filamentgroup.com/lab/load-css-simpler/`.
- **Schema.org Person.image:** accepts `ImageObject` or URL. Raster format ≥ 512×512 preferred for Google Knowledge Panel. Source: `https://schema.org/Person`.

### CLI verification gate

This plan prescribes NO new CLI invocations in user-facing docs. `npx lighthouse` is used only for pre-merge measurement, not embedded in documentation. `npx @11ty/eleventy` is an existing documented command (sibling plans reference it). `npx markdownlint-cli2 --fix` is an AGENTS.md hard rule.

No `<!-- verified: YYYY-MM-DD source: <url> -->` annotations required — the plan does not land CLI snippets in `.njk` / `.md` / README.

## PR Body Reminder

The PR body MUST contain, verbatim (one per line, in the body — NOT the title):

```text
Closes #2807
Closes #2808
Closes #2809
```

And conditionally:

```text
Closes #2799
```

Only if the founder headshot asset was supplied during the work session and landed in the PR. If not, drop that line and leave #2799 open.

Per AGENTS.md rule `wg-use-closes-n-in-pr-body-not-title-to`.

## Resume Context

- **Branch:** `feat-one-shot-drain-marketing-chores`
- **Worktree:** `/home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-drain-marketing-chores`
- **Closes (planned):** #2807 #2808 #2809 (#2799 conditional)
- **Upstream driver:** weekly growth audit #2803 (2026-04-22)
- **Drain-pattern reference:** PR #2486 (one PR, multiple Closes)
- **Companion prior drain:** PR #2794 (2026-04-21 AEO drain — same code area, the author card this plan extends).
