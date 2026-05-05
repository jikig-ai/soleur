# Learning: GSC critical-indexing triage patterns

## Problem

Google Search Console flagged 29 pages on soleur.ai across 5 critical-indexing
categories. Operator handed off the GSC "Critical issues" CSV expecting per-URL
analysis, but the CSV is aggregate-only — categories and counts, no URLs. After
the operator exported per-URL data, three non-obvious patterns emerged that
explained nearly every flagged URL.

## Solution

### Insight 1 — GSC "Critical issues" CSV is aggregate-only

The top-level "Critical issues" CSV exported from GSC's Page Indexing dashboard
contains only `Reason,Source,Validation,Pages` columns. To get the URL list per
category, the operator must click each issue row, then use the per-issue
**Export → CSV** button. The Sitemap-level export and the top-level "Critical
issues" export are both aggregate.

For triage workflows: do not start agent analysis until the per-issue exports
are in hand. Aggregate counts produce speculative root-cause analysis.

### Insight 2 — Meta-refresh + canonical is non-deterministic for indexing

`<meta http-equiv="refresh" content="0;url=...">` paired with
`<link rel="canonical" href="...">` is a "soft" indexing signal Google
classifies inconsistently across at least three buckets:

- "Page with redirect" (some entries)
- "Crawled - currently not indexed" (some entries with the same template)
- "Alternate page with proper canonical tag" (some entries with the same template)

This was observed on soleur.ai's `page-redirects.njk` template: 18 redirect
entries used identical markup but landed in three different GSC categories,
seemingly at random.

**Deterministic alternative:** HTTP 301 served at the edge (Cloudflare Bulk
Redirects, Cloudflare Pages `_redirects`, or origin server). Google
deterministically classifies HTTP 301 as a redirect and follows it.

If a static-site host (e.g., GitHub Pages) doesn't support HTTP 301, lift the
redirect to an upstream proxy (Cloudflare Rulesets / Workers) rather than
emitting meta-refresh HTML.

### Insight 3 — Cloudflare-proxied subdomains are enumerable; 403 is not noindex

soleur.ai had two subdomains in the GSC report that should not have been
discoverable:

- `api.soleur.ai/` (404 JSON) — no public link from the docs site.
- `deploy.soleur.ai/` (403 admin/deployment surface) — no public link.

Discovery vector: Cloudflare-proxied subdomains appear in Certificate
Transparency logs. Googlebot scans CT logs to find new hostnames, then
fingerprints them. **A 403 is not equivalent to a noindex** — Google still
records the URL's existence and may surface it in search results without a
snippet.

**Defense in depth for non-public subdomains:**

1. `X-Robots-Tag: noindex, nofollow` response header (Cloudflare Transform Rule
   scoped to the hostname).
2. `robots.txt` at `https://<subdomain>/robots.txt` with `User-agent: *\nDisallow: /`.
3. If the subdomain is internal-only, prefer Cloudflare Zero Trust / Tunnel
   over a public 403 — eliminate the surface entirely rather than annotating it.
4. Audit DNS records for unintended public exposure (`dig <subdomain>` returns
   a CNAME to an internal CDN endpoint).

A `403` alone is signalling "auth required" to search engines, not "do not list."

## Key Insight

When triaging Google Search Console critical-indexing reports, the cheapest
high-leverage fixes usually fall into three buckets:

1. **Sitemap-build vs deploy-redirect mismatch** (e.g., sitemap declares apex,
   deploy 301s to www): one config file change.
2. **Meta-refresh-style legacy redirects** classified non-deterministically by
   Google: lift to HTTP 301 at the edge.
3. **Subdomain leaks via CT-log enumeration**: defense-in-depth headers, not
   reliance on HTTP-level access control as a discoverability gate.

The brand-survival framing (`hr-weigh-every-decision-against-target-user-impact`)
is essential for category 3. SEO triage looks like marketing hygiene from the
outside — vector 3 is the one where it's actually a security/brand-trust
incident waiting to be amplified by a single config drift.

## Tags

category: integration-issues
module: docs-site, seo, cloudflare, observability
