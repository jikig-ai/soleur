---
title: "Strengthen internal-link equity for 3 GSC 'Crawled – currently not indexed' blog pages"
type: feat
date: 2026-07-06
branch: feat-one-shot-gsc-internal-linking
lane: cross-domain
brand_survival_threshold: none
status: planned
---

# ✨ Strengthen internal-link equity for 3 structurally-healthy, unindexed blog pages

## Enhancement Summary

**Deepened on:** 2026-07-06
**Change class:** docs-only (6 Markdown internal links across 5 blog posts) — right-sized
deepen (deterministic fact-verification + one targeted SEO-best-practice research pass),
not a full multi-agent fan-out (disproportionate for a 6-link content edit).

### Deepen gate results (all pass)

- **4.4 Precedent-diff (link idiom):** the `{{ site.url }}/blog/<slug>/` leading-slash
  idiom is the established repo precedent (21 existing leading-slash `/blog/` cross-links).
  Not novel; no host-mangle in source today.
- **4.5 Network-outage / 4.55 Downtime & Cutover:** no triggers (no SSH/network/infra/DB
  migration/deploy surface). Skip.
- **4.6 User-Brand Impact halt:** section present; threshold `none` with a valid
  scope-out reason (pure Markdown link insertion, no sensitive path). Pass.
- **4.7 Observability gate:** pure-docs — every Files-to-Edit path is `.md` outside
  `plugins/*/skills/` and `apps/*/`. Skip.
- **4.8 PAT-shaped variable halt:** no PAT-shaped var/literal in plan. Pass.
- **4.9 UI-wireframe halt:** no UI-surface file. Skip.

### Load-bearing facts re-verified deterministically

- **Permalink resolution:** `plugins/soleur/docs/blog/blog.json` sets
  `permalink: "blog/{{ page.fileSlug }}/index.html"`. Eleventy's `fileSlug` strips the
  `YYYY-MM-DD-` date prefix, so the three targets resolve to `/blog/soleur-vs-polsia/`,
  `/blog/your-ai-team-works-from-your-actual-codebase/`, `/blog/billion-dollar-solo-founder-stack/`
  — exactly the URLs in §Overview. `_data/pillars.js:16` independently confirms
  `/blog/billion-dollar-solo-founder-stack/` as the canonical pillar URL. `blogRedirects.js`
  also 301s the date-prefixed form to the clean slug, so the clean-slug links are canonical.
- **All 6 anchor phrases** are present verbatim and **unlinked** at their sites (verified
  by `sed`/`grep` at plan time). The company-as-a-service:107 anchor is the *unlinked tail
  clause* — the existing external link occupies the earlier clause, so no nesting.
- **Dup-check:** none of the 5 source posts currently link their assigned target.

---

# (original plan below)

## Enhancement Summary

**Deepened on:** 2026-07-06

**Deepen-plan halt gates — all clear:**
- Phase 4.6 User-Brand Impact — PASS (section present; threshold `none` with a
  `threshold: none, reason:` scope-out; Files-to-Edit are non-sensitive blog `.md`).
- Phase 4.7 Observability — SKIP (pure-docs; every Files-to-Edit path is `.md` outside
  `plugins/*/skills/` and `apps/*/` — no production code/infra surface).
- Phase 4.8 PAT-shaped variable — PASS (no `var.*_token`/`TF_VAR_*`/literal-token hits).
- Phase 4.9 UI-wireframe — SKIP (no UI-surface file in Files-to-Edit).
- Phase 4.5 network-outage / 4.55 downtime-cutover — SKIP (no SSH/network/infra/DB/deploy
  triggers).

**Deepen verification (deterministic — the load-bearing facts):**
- **Permalink resolution confirmed.** `plugins/soleur/docs/blog/blog.json` sets
  `permalink: "blog/{{ page.fileSlug }}/index.html"`; Eleventy's `fileSlug` strips the
  `YYYY-MM-DD-` date prefix, so the three targets resolve to exactly
  `/blog/soleur-vs-polsia/`, `/blog/your-ai-team-works-from-your-actual-codebase/`, and
  `/blog/billion-dollar-solo-founder-stack/`. `pillars.js` independently pins
  `/blog/billion-dollar-solo-founder-stack/` as the canonical pillar URL. The
  date-prefixed form redirects to the clean slug (`blogRedirects.js`), so the clean-slug
  links are canonical.
- **Idiom precedent confirmed** (Phase 4.4 precedent-diff): 21 existing leading-slash
  `{{ site.url }}/blog/<slug>/` cross-links in the corpus; the pattern is established, not
  novel. Zero host-mangled `{{ site.url }}blog/...` in source today.
- **All 6 anchor phrases verified present and unlinked** in their source posts at plan
  time (exact strings quoted in Phase 1; /work must re-grep as line numbers drift).
- **Dup-check confirmed:** none of the 5 source posts currently links its assigned target.

## Overview

Google Search Console (soleur.ai, report last updated 2026-06-30) flags three canonical
blog pages as **"Crawled – currently not indexed."** All three are verified structurally
healthy: HTTP 200, self-canonical, no robots `noindex`, present in `sitemap.xml`, listed
on the blog index. For a healthy page, "Crawled – currently not indexed" is Google's
*discretionary* call — the only lever we control in-repo is **contextual internal-link
equity**. This is the exact remediation pattern documented in
`knowledge-base/project/learnings/2026-06-15-gsc-crawled-not-indexed-remediation-is-internal-linking.md`
(the prior run of this task class on a sibling set of pages).

This PR adds a small number of *genuinely contextual* internal links from other,
topically-related blog posts, anchored on precise topical phrases already present in the
existing prose. It is **not** a keyword-stuffed link farm (that is an SEO negative). No
`noindex` / canonical / sitemap changes — those surfaces are already correct.

Indexing is Google-controlled and lags; this PR delivers the link-equity lever, not a
guaranteed re-index. The tracking issue (if any) is referenced with **`Ref`, not
`Closes`**.

### Target pages (external inbound count today → after this PR)

| # | File | URL | Inbound today | New | After |
|---|------|-----|---------------|-----|-------|
| 1 | `plugins/soleur/docs/blog/2026-03-26-soleur-vs-polsia.md` | `/blog/soleur-vs-polsia/` | **0** (top priority) | 3 | 3 |
| 2 | `plugins/soleur/docs/blog/2026-03-29-your-ai-team-works-from-your-actual-codebase.md` | `/blog/your-ai-team-works-from-your-actual-codebase/` | 1 | 2 | 3 |
| 3 | `plugins/soleur/docs/blog/2026-04-22-billion-dollar-solo-founder-stack.md` | `/blog/billion-dollar-solo-founder-stack/` | 2 | 1 | 3 |

Inbound counts were verified empirically (self-references excluded):
`grep -rln '<slug>' plugins/soleur/docs/blog/*.md` — matches the brief exactly.

### Link idiom (verified against neighboring posts)

The repo's blog cross-link idiom is **`{{ site.url }}/blog/<slug>/`** with a **leading
slash** — confirmed via `grep -rEoh '\{\{ ?site\.url ?\}\}/?blog/...'` (9 distinct
existing cross-links, all leading-slash; zero host-mangled `{{ site.url }}blog/...` in
source today). The host-mangle bug (missing leading slash → `https://soleur.aiblog/...`)
must NOT be reintroduced.

## User-Brand Impact

**If this lands broken, the user experiences:** a broken internal link in a published
blog post (e.g. a host-mangled `https://soleur.aiblog/...` 404, or a link to a
nonexistent slug) on soleur.ai — a visible credibility papercut on a marketing surface.

**If this leaks, the user's data / workflow / money is exposed via:** N/A — this change
adds only Markdown hyperlinks between already-public blog posts. No data, auth, or PII
surface is touched.

**Brand-survival threshold:** none — content/SEO link insertion on already-public
marketing pages; worst case is a broken hyperlink caught by the Phase-4 build grep before
merge. `threshold: none, reason: pure Markdown internal-link insertion on public blog
posts; no sensitive path, schema, auth, or PII surface touched.`

## Implementation Phases

### Phase 1 — Add contextual internal links (6 links across 5 source posts)

Each link sits on an **existing** topical phrase in the source post's prose. Anchor text,
source line (as of plan time — /work must re-confirm the phrase is present and unlinked
before editing, since line numbers drift), and rationale below. Use the idiom
`[<existing phrase>]({{ site.url }}/blog/<target-slug>/)`.

**→ Target 1: `/blog/soleur-vs-polsia/`** (3 new inbound — the Polsia comparison is about
autonomous-vs-human-in-the-loop CaaS architectures; every anchor below already discusses
exactly that axis):

1. `2026-03-31-soleur-vs-paperclip.md` (~line 134, PROSE Q&A body) — anchor the phrase
   **"fully autonomous by design"** in the sentence that already names Polsia
   ("Polsia is the fastest-growing proprietary alternative … but is cloud-hosted,
   closed-source, and fully autonomous by design."). Strongest possible anchor: Polsia is
   named in the same sentence.
   ⚠️ **Do NOT edit the JSON-LD mirror of this sentence** (~line 178, inside
   `<script type="application/ld+json">`) — that is structured data, not rendered prose; a
   Markdown link there breaks the JSON-LD and is never rendered as a link.
2. `2026-05-12-company-as-a-service-platform.md` (~line 62) — anchor **"fully autonomous
   AI companies"** in "This is the distinction from fully autonomous AI companies."
   (verified unlinked prose).
3. `2026-04-21-one-person-billion-dollar-company.md` (~line 86) — anchor **"Human-in-the-loop
   decision gates"** in "Human-in-the-loop decision gates are not a concession to AI
   limitations…" (the exact opposite architecture the Polsia post compares against).

**→ Target 2: `/blog/your-ai-team-works-from-your-actual-codebase/`** (2 new inbound — the
target post is the answer to the "agent starts from a blank workspace / brief it from
scratch every session" problem; both anchors name that problem):

4. `2026-03-24-vibe-coding-vs-agentic-engineering.md` (~line 49) — anchor **"the same
   blank slate"** in "…hand the codebase to another agent for review. And the first thing
   you realize is that the hundredth session starts from the same blank slate as the
   first." (mentions the codebase directly — tight fit for the target).
5. `2026-03-24-ai-agents-for-solo-founders.md` (~line 80) — anchor **"start from a blank
   slate on each session"** in "Agents that start from a blank slate on each session
   require the founder to re-supply context manually every time."

**→ Target 3: `/blog/billion-dollar-solo-founder-stack/`** (1 new inbound — already at 2;
+1 → 3, satisfies the ~2–3 target):

6. `2026-05-12-company-as-a-service-platform.md` (~line 107) — anchor the unlinked clause
   **"a structural outcome of AI agents extending beyond engineering into every function a
   company needs"**. The existing external link in that sentence is on the *earlier*
   clause ("forecast that a one-person billion-dollar company would emerge as soon as
   2026"); the new internal link lands on the later, unlinked clause → the stack post
   documents exactly that function-by-function stack (Medvi proof). No overlap/nesting
   with the existing link.

**In-scope expansion (conditional, same defect class):** if Phase 4's built-output grep
surfaces any PRE-EXISTING host-mangled `https://soleur.ai<letter>` links in other posts
(a known prior occurrence — the 2026-06-15 learning found and fixed 5), fix them inline in
this PR with a trivial leading-slash insertion (`{{ site.url }}blog/` → `{{ site.url }}/blog/`)
and add each edited file to §Files to Edit with rationale. Rationale for folding in:
shipping a "strengthen internal links" PR while knowingly leaving broken internal links
one grep away is incoherent (`rf-review-finding-default-fix-inline`,
`hr-weigh-every-decision-against-target-user-impact`). Source is clean today, so this is
expected to be a no-op — but the grep is the gate, not the assumption.

### Phase 2 — (no code phase)

Pure content change; no build-config, template, or code edits.

### Phase 3 — (no test-authoring phase)

No unit tests apply to prose links. Verification is the Phase-4 build grep (below).

### Phase 4 — Build + host-mangle verification (blocking)

1. Build the Eleventy site from repo root:
   `npx @11ty/eleventy` (the `docs:build` script; `.eleventy.js` lives at repo root and
   emits to `_site/`). Do not trust a stale `_site/` from a prior session — build fresh.
2. **Locate the build dir dynamically** (per the learning's session error — the plan path
   is a snapshot, not authority):
   ```bash
   SITE=""
   for d in _site plugins/soleur/docs/_site; do [ -d "$d/blog" ] && SITE="$d" && break; done
   echo "SITE=$SITE"
   ```
3. **Host-mangle grep — MUST be empty:**
   ```bash
   grep -rEoh 'https://soleur\.ai[a-zA-Z]' "$SITE"/blog/ || echo "CLEAN (no host-mangle)"
   ```
   Any hit = a missing leading slash. If the hit is in one of THIS PR's new links, fix the
   source and rebuild. If the hit is a PRE-EXISTING link in an untouched post, apply the
   in-scope expansion from Phase 1.
4. **Confirm the 6 new links rendered as real anchors** to the correct absolute URLs:
   ```bash
   for slug in soleur-vs-polsia your-ai-team-works-from-your-actual-codebase billion-dollar-solo-founder-stack; do
     echo "== $slug =="; grep -rl "https://soleur.ai/blog/$slug/" "$SITE"/blog/ | wc -l
   done
   ```
   Expect ≥ the new-inbound count per target (3 / 2 / 1, plus any pre-existing inbound).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] 6 new internal links added on existing topical phrases across the 5 named source
      posts (T1×3, T2×2, T3×1); each uses the `{{ site.url }}/blog/<slug>/` leading-slash
      idiom. Verify: `git diff` shows exactly 6 added `{{ site.url }}/blog/` occurrences
      (net), one per link site.
- [ ] No new link is inside a `<script type="application/ld+json">` block (the paperclip
      JSON-LD mirror at ~line 178 is untouched). Verify: `git diff` shows no change inside
      any `application/ld+json` block.
- [ ] Each new anchor sits on the pre-existing phrase named in Phase 1 (no fabricated
      sentences, no keyword-stuffed anchor lists).
- [ ] Anchor text is descriptive and varied, not identical exact-match repeated across
      links (per Google Links best-practices). No two links to the same target use the
      identical anchor string; each anchor is embedded in body prose (not a link widget).
- [ ] Fresh Eleventy build succeeds.
- [ ] `grep -rEoh 'https://soleur\.ai[a-zA-Z]' "$SITE"/blog/` returns **empty** (no
      host-mangle) against the dynamically-located `$SITE`.
- [ ] Built output contains the three target absolute URLs with inbound counts ≥ (3, 2, 1)
      new respectively.
- [ ] If any pre-existing host-mangled link surfaced, it is fixed inline and its file is
      listed in §Files to Edit with rationale (else: grep was clean — no expansion).
- [ ] No changes to `noindex`, `canonical`, `sitemap.xml`, or any frontmatter of the
      target pages.
- [ ] PR body uses **`Ref`** (not `Closes`) for any tracking issue and includes the GSC
      diagnosis summary (below).

## Files to Edit

| File | Change | For target |
|------|--------|-----------|
| `plugins/soleur/docs/blog/2026-03-31-soleur-vs-paperclip.md` | +1 internal link on "fully autonomous by design" (prose ~L134 only; NOT the JSON-LD ~L178) | T1 |
| `plugins/soleur/docs/blog/2026-05-12-company-as-a-service-platform.md` | +2 internal links: "fully autonomous AI companies" (~L62 → T1) and "…every function a company needs" (~L107 → T3) | T1, T3 |
| `plugins/soleur/docs/blog/2026-04-21-one-person-billion-dollar-company.md` | +1 internal link on "Human-in-the-loop decision gates" (~L86) | T1 |
| `plugins/soleur/docs/blog/2026-03-24-vibe-coding-vs-agentic-engineering.md` | +1 internal link on "the same blank slate" (~L49) | T2 |
| `plugins/soleur/docs/blog/2026-03-24-ai-agents-for-solo-founders.md` | +1 internal link on "start from a blank slate on each session" (~L80) | T2 |
| _(conditional)_ any post surfaced by Phase-4 grep | inline leading-slash fix, same defect class | corpus |

Dup-check confirmed at plan time: none of these 5 source posts currently link their
assigned target (`grep -l '<target-slug>' <source>` → no match for all pairs).

### Research Insights — contextual internal linking (Google Search Central, 2025-2026)

Sources: [Google — SEO Link Best Practices](https://developers.google.com/search/docs/crawling-indexing/links-crawlable),
[Google — Page indexing report](https://support.google.com/webmasters/answer/7440203),
[Onely — Fixing "Crawled – currently not indexed"](https://www.onely.com/blog/how-to-fix-crawled-currently-not-indexed-in-google-search-console/).

- **Internal linking is a Google-endorsed lever for this exact bucket.** For structurally
  healthy pages, "Crawled – currently not indexed" reflects Google judging standalone
  importance as low; links from already-indexed, higher-authority pages signal importance
  and distribute crawl priority / link equity. Confirms the learning's Insight 2.
- **Anchor text must be descriptive, concise, relevant — and VARIED.** Repeating one
  exact-match keyword anchor across many links is an over-optimization signal Google can
  discount. Our 6 anchors are sentence-embedded and varied per source; encoded as an AC
  below. (Note: T1's three anchors include two "fully autonomous …" variants — acceptable
  because they are different phrases in different posts and each descriptively names the
  destination's autonomous-vs-human axis; T2's two "blank slate" anchors are likewise
  partial-match, sentence-embedded, not identical.)
- **~6 contextual internal links across 3 targets is conservative and natural.** Healthy
  range for an under-linked page is ~5-10 inbound; manipulation comes from *irrelevance
  and identical anchors*, not from count. Internal links between your own topically-related
  pages carry no PBN/link-farm risk. Reinforces "don't over-link."
- **Body prose beats widgets.** Contextual links inside relevant body copy pass more value
  than footer/sidebar/"related links" widgets (template noise). All 6 links land in body
  prose — correct by construction. Do NOT convert this into a related-links widget.
- **Links are necessary, not sufficient.** Indexing also depends on content quality and is
  Google-controlled + lagged — reinforces `Ref` (not `Closes`) framing.

## Open Code-Review Overlap

None. No open `code-review`-labelled issues touch `plugins/soleur/docs/blog/*.md` link
sites (this is a fresh content edit, not a refactor of reviewed code).

## Domain Review

**Domains relevant:** marketing (SEO) — advisory only.

The change is mechanical insertion of contextual internal links on existing prose to
strengthen the site's link graph for three unindexed pages. No new marketing *copy* is
authored (every anchor is a pre-existing phrase), so no copywriter/brand review is
triggered. No UI-surface files (`components/**`, `app/**/page.tsx`, `app/**/layout.tsx`)
are in §Files to Edit → the mechanical Product/UX override does NOT fire; Product/UX Gate
is NONE. No CPO/CMO fan-out warranted for a 6-link content edit.

## GSC Diagnosis Summary (for the PR body)

The GSC Coverage drilldown (soleur.ai, updated 2026-06-30) buckets into three groups; only
one is actionable in-repo:

- **Legacy `.html` / `/pages/` paths** — all **301 cleanly** to apex clean URLs; GSC
  `Last crawled` dates predate the redirect deploy (stale snapshots, self-resolve on
  re-crawl). Not actionable.
- **`www.` / `http://` variants** — benign apex canonicalization consolidation. Not
  actionable.
- **`403` on the `deploy.soleur.ai` subdomain** — correct (that host is not meant to be
  indexed). Not actionable.
- **Three genuinely-healthy blog pages** (200 / self-canonical / in-sitemap / no-noindex)
  — the ONLY actionable bucket. Fix = contextual internal-link equity (this PR).

Because indexing is Google-controlled and lags, the PR uses **`Ref`** for any tracking
issue and delivers the link-equity lever, not a re-index guarantee.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only TBD/placeholder, or
  omits the threshold will fail `deepen-plan` Phase 4.6. This one is filled (threshold:
  none, with reason).
- **Edit prose, not JSON-LD.** `2026-03-31-soleur-vs-paperclip.md` repeats the Polsia
  sentence inside a `<script type="application/ld+json">` block (~L178). Only the rendered
  prose occurrence (~L134) gets the link.
- **Line numbers drift.** The ~Lxx anchors are plan-time snapshots; /work must
  `grep -n '<exact phrase>'` each source before editing and confirm the phrase is present
  and NOT already inside a `[]()` link.
- **Build dir is `_site/` at worktree root, not `plugins/soleur/docs/_site/`.** Probe both
  dynamically (Phase 4 step 2) — the plan literal is not authority
  (`hr-when-a-plan-specifies-relative-paths-e-g`).
- **Host-mangle grep runs on BUILT output**, not source. Source is clean today; the grep
  is the gate that also doubles as a corpus broken-link finder (fix any hit inline, same
  defect class).
- Don't over-link. 6 links / 5 posts / 3 targets keeps each target at 3 inbound — natural
  editorial density, not a link farm. Resist adding more.
