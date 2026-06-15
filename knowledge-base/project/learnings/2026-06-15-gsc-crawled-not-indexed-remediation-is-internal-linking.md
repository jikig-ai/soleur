# Learning: GSC "Crawled - currently not indexed" on healthy pages → the lever is internal linking, not infra

## Problem

A GSC Coverage Drilldown flagged 3 canonical pages as **"Crawled - currently not
indexed."** The instinct on a "fix the SEO report" task is to look for a structural
defect (bad canonical, missing sitemap entry, redirect loop, noindex). For
structurally-healthy pages that instinct sends you chasing infra that is already
correct, and you ship nothing useful.

This pairs with the sibling GSC learnings already in the KB — they cover the OTHER
buckets of a Coverage drilldown:
- [[2026-06-01-gsc-page-with-redirect-is-historical-memory-verify-against-build]] — "Page with redirect" is benign canonicalization memory.
- [[2026-06-12-gsc-duplicate-canonical-on-www-variant-is-benign-consolidation]] — www→apex duplicates are benign.
- [[2026-05-05-gsc-indexing-triage-patterns]] — meta-refresh stubs are non-deterministic for indexing.
- [[2026-06-14-gsc-indexed-though-blocked-by-robots-is-a-real-misconfig-not-benign]] — the one bucket that IS a real misconfig.

This learning fills the remaining bucket: **"Crawled - currently not indexed" on a 200/canonical/in-sitemap/no-noindex page.**

## Solution

### Insight 1 — Bucket the drilldown rows; don't treat the count as one problem

A "Crawled - currently not indexed" table is almost always three different things wearing one label:

1. **Legacy `.html`/`/pages/` paths already 301'd** — GSC `Last crawled` dates predate the redirect deploy. These are *stale snapshots*; they drop off on re-crawl. **Verify, don't assume:** `curl -so /dev/null -w "%{http_code} %{redirect_url}" -A Googlebot <url>` — a clean `301 → apex clean URL` means already-fixed. (`hr-no-dashboard-eyeball-pull-data-yourself`: pull the live status, don't trust the GSC date.)
2. **`www.`/`http://` variants + `feed.xml`** — www 301s to apex (benign, see sibling learnings); feed is intentionally `X-Robots-Tag: noindex`. Not actionable.
3. **Real canonical pages that are genuinely healthy** — 200, `canonical=apex`, in sitemap, no `noindex`, listed on their index. THIS is the only actionable bucket.

### Insight 2 — For healthy pages, the in-our-control lever is internal-link equity

"Crawled - currently not indexed" on a healthy page is Google's *discretionary* call:
crawled it, judged it not important enough to index yet. On a young/low-authority
site this is normal and often self-resolves with time + domain authority. The single
lever you control in-repo is **contextual internal links** — strengthen the site's own
link graph so it signals these pages matter. Confirm the gap empirically before editing:
`grep -rl '<slug>' plugins/soleur/docs/blog/` (a page with 0 contextual inbound links is
the weak one). Add *genuinely contextual* links on precise topical anchors — never a
keyword-stuffed link farm, which is an SEO *negative*. There is no deterministic
"request indexing" API for arbitrary docs pages, so this PR delivers the lever and the
rest is a monitor (`Ref`, not `Closes` — index state is Google-controlled and lags).

### Insight 3 — The rendered-output host-mangle grep doubles as a corpus broken-link finder; fix in scope

The Phase-4 verification gate for `{{ site.url }}` link insertions
(`grep -rEoh 'https://soleur\.ai[a-zA-Z]' _site/blog/`, from
[[2026-04-21-eleventy-site-url-concatenation-broken-without-leading-slash]]) is meant to
catch a slash-drop in *your own* new links. On this PR it surfaced **5 pre-existing
host-mangled links** (`{{ site.url }}blog/...` → `https://soleur.aiblog/...`) in 4 OTHER
blog posts the diff never touched — including one pointing at a page in this PR's own
link graph. Decision: **fix inline.** Shipping a "strengthen internal links for SEO" PR
while knowingly leaving 6 broken internal links one grep away is incoherent; the fix is a
trivial mechanical slash insertion in the same subsystem and same defect class
(`rf-review-finding-default-fix-inline`, `hr-weigh-every-decision-against-target-user-impact`).
Document the in-scope expansion in the plan's Files-to-Edit with rationale so it isn't
read as scope creep. The grep is `_site/`-relative — build first, then grep the built
output, not stale `_site/` from a prior session.

## Key Insight

A GSC Coverage report is a *triage* artifact, not a defect list. Most rows are benign
(canonicalization memory) or stale (already-301'd, pre-deploy crawl dates) — verify each
bucket live with `curl` before acting. The only thing you actually build is internal-link
equity for the handful of genuinely-healthy-but-unindexed pages, and that lever is
delivered in-repo while indexing itself stays Google's call.

## Session Errors

- **`/soleur:one-shot` aborted on the closed-issue collision gate for a contextual citation.** The routing args (constructed by `/soleur:go`) cited `#4577` as "structural causes already fixed in #4577" — a contextual citation, not a work target. `#4577` is a CLOSED issue, so the Step 0a.5 gate fired its closed-issue abort. — Recovery: re-invoked with `#4577` rephrased to date-anchored prose ("merged 2026-05-29"), per the documented remedy in [[2026-05-25-one-shot-closed-issue-gate-fires-on-contextual-refs]]. — Prevention: `/soleur:go` (and any router that constructs one-shot args) should scrub closed `#N` *contextual* citations to date-anchored phrasing BEFORE invoking one-shot — only OPEN work-target refs belong in `#N` form. (Route-to-definition: one-line note added to `/soleur:go`.)
- **Plan Phase 4 cited the build-output dir as `plugins/soleur/docs/_site` but Eleventy writes `_site/` at the worktree root.** — Recovery: detected the real SITE dir dynamically (`for d in _site plugins/soleur/docs/_site; do [ -d "$d/blog" ] && SITE=$d`). — Prevention: one-off; plan paths are plan-time snapshots, not authority (`hr-when-a-plan-specifies-relative-paths-e-g`). Locate the build output by probing, not by trusting the plan literal.

## Tags
category: integration-issues
module: docs-site / seo / gsc
