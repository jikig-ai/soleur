# Learning: SEO/AEO drain — reconciliation-first + consumer-sweep classes (PR #2973)

**Date:** 2026-04-28
**PR:** #2973 (drain #2942-#2949)
**Category:** best-practices
**Tags:** seo, aeo, eleventy, multi-agent-review, consumer-sweep, reconciliation

## Problem

A drain of 8 SEO/AEO docs-site issues (#2942-#2949) generated from audit #2941 needed to be folded into one cleanup PR. Two problem classes surfaced during execution:

1. **Stale audit input.** The audit was run weeks before the drain. Verifying each claim against current code revealed that 3 of 8 issues were already fully or partially shipped (#2943 single H1, #2948 FAQPage JSON-LD on all 6 named pages, #2949 About page with founder bio + Person `@id`). Implementing the issues verbatim would have produced 8 idempotent edits.

2. **Bulk data-shape change broke a silent consumer.** Root-slashing all internal URLs in `_data/site.json` (e.g., `pricing/` → `/pricing/`) broke the `aria-current` comparison in `_includes/base.njk` because the comparison was `page.url == ('/' + item.url)`, which now produced `'//pricing/'` and never matched. The site rendered visually correct; only an a11y screen-reader (or grep for `aria-current="page"` in built HTML) would have surfaced the regression.

Plus three smaller defects, all caught by multi-agent review pre-merge:

3. **`dateToRfc3339` filter crashed on falsy input.** New Eleventy filter `new Date(date).toISOString()` throws `RangeError: Invalid time value` on `undefined`. Build worked because every current page had `page.date` resolving to file mtime — but a future page that explicitly set `date: null` or a virtual collection page would have crashed the entire build.

4. **`<base href="/">` removal sweep missed `404.njk`.** The bare-relative `href` sweep covered `pages/*.njk`, `_includes/*.njk`, `index.njk`, and blog markdown. `404.njk` (sibling of `index.njk` at the docs root) was not on that list and shipped a stale `href="index.html"` survivor.

5. **`validate-seo.sh` h1_count substitution tripped pipefail.** New check `h1_count=$(grep -oE '<h1[ >]' "$f" | wc -l)` aborts the script under `set -euo pipefail` when grep finds no match (exit 1 propagates through pipefail). Switched to `grep -cE ... || true`.

## Solution

### Reconciliation-first plan structure

The deepen-plan phase built a Spec-vs-Codebase table comparing each issue claim to working-tree reality, with "verify" or "edit" disposition per row. The table itself became the load-bearing artifact — without it, 8 idempotent edits would have been written. This pattern works whenever audit input has aged: reconcile before implementing.

### Bulk data change → consumer sweep (same class as several existing AGENTS.md rules)

The `aria-current` regression is the same shape as `cq-raf-batching-sweep-test-helpers`, `cq-preflight-fetch-sweep-test-mocks`, `cq-union-widening-grep-three-patterns`, and `cq-ref-removal-sweep-cleanup-closures`: a data-shape change in one file silently broke a downstream consumer in another. The generalization: **whenever you bulk-edit a data file (site.json, schemas, enums, route tables) or a shape (URL prefix, type widening, function signature), grep ALL consumers of the changed surface in the same edit cycle and verify each still computes correctly against the new shape.**

For this drain specifically, the consumer was a Nunjucks `{% if %}` predicate; for other PRs it's been a TS conditional, a vitest mock chain, or a React effect cleanup. The pattern recurs across surfaces.

### Eleventy custom filter input validation

`new Date(date).toISOString()` is hostile to undefined / null / "" / NaN. Any custom Eleventy date filter that delegates to the Date constructor should guard:

```javascript
eleventyConfig.addFilter("dateToRfc3339", (date) => {
  if (!date) return null;
  const d = new Date(date);
  return Number.isNaN(d.getTime()) ? null : d.toISOString();
});
```

And the template should wrap the JSON-LD line conditionally so a null filter result emits no property at all:

```nunjucks
{% if page.date %}"dateModified": {{ (page.date | dateToRfc3339) | jsonLdSafe | safe }},{% endif %}
```

Schema.org accepts a missing `dateModified` more cleanly than `null`.

### `validate-seo.sh` per-page check writing pattern

Inside a `for f in ...; do` loop under `set -euo pipefail`, command substitution on grep pipelines that may yield zero matches MUST end with `|| true`:

```bash
# Bad — script aborts on a page with zero <h1>:
h1_count=$(grep -oE '<h1[ >]' "$f" | wc -l)

# Good — pipefail-safe, returns 0 on zero matches:
h1_count=$(grep -cE '<h1[ >]' "$f" || true)
```

Also tighten substring detectors to anchor on tag boundaries: `grep -qE '<base[[:space:]>]'` not `grep -q '<base '` (the latter false-positives on prose like `<base 64 string>` in code blocks).

### Multi-agent review was load-bearing

All 4 fixable defects (aria-current, dateToRfc3339, 404.njk, h1_count) were caught by parallel review agents pre-merge. Single-agent review or running only `validate-seo.sh` would have caught at most 1 of them (h1_count, on the first zero-h1 page). Per learning `2026-04-22-multi-agent-review-catches-aeo-semantic-drift`, structured-data and bulk-template PRs need multi-agent review as a hard gate, not an optional polish.

`agent-native-reviewer` produced one false-positive ("CRITICAL dangling @id") from a grep that searched `"@type":"Person"` (no space) instead of the rendered `"@type": "Person"` (with space). Existing rule `cm-` covers this — verify before flagging — no new rule needed.

## Key Insight

Two compounding patterns:

1. **Audit-driven backlogs decay.** When a drain triggers off an audit older than ~14 days, prepend a reconciliation table to the plan. Treat audit claims as hypotheses, not facts.

2. **Bulk-data changes need consumer-sweep gates.** This is now the 5th instance of the pattern in AGENTS.md (test-helper sweep, fetch-mock sweep, union-widening grep, useRef cleanup grep, … nav data root-slash). The generalization is mature enough that a per-surface rule list is more useful than another sweep-class rule.

## Session Errors

1. **`dateToRfc3339` filter omitted falsy guard** — Recovery: added `if (!date) return null` + `Number.isNaN(d.getTime())` guard, wrapped template line in `{% if page.date %}`. Prevention: when adding a custom Eleventy filter that delegates to a JS constructor with throwing behavior on bad input, write the guard and the template-side conditional in the same edit. (Discovered via review; would have crashed build only on a future page lacking `page.date`. Single occurrence; no AGENTS.md rule.)

2. **Root-slashing `_data/site.json` URLs broke aria-current consumer in `_includes/base.njk`** — Recovery: changed comparison from `page.url == ('/' + item.url)` to `page.url == item.url`. Prevention: this is the consumer-sweep class. When changing a URL/data shape in a data file, grep every Nunjucks/template consumer that concatenates or compares against the changed field. Same class as `cq-raf-batching-sweep-test-helpers` and 4 sibling rules — the existing rules already form the pattern; a new rule per surface is byte-budget-prohibitive.

3. **`<base href="/">` removal sweep missed `404.njk`** — Recovery: changed `href="index.html"` → `href="/"`. Prevention: when sweeping bare-relative paths in the docs site, the file list MUST include `404.njk`, `llms.txt.njk`, `sitemap.njk`, `page-redirects.njk` at the docs root in addition to `pages/**` and `_includes/**`. Routed to seo-aeo skill references.

4. **`validate-seo.sh` h1_count substitution tripped pipefail** — Recovery: switched to `grep -cE ... || true`. Prevention: bash idiom — under `set -euo pipefail`, `$(grep ... | wc -l)` aborts on zero matches because pipefail propagates grep's exit 1. Use `grep -c` (returns count incl. 0) with `|| true` rescue. (Discoverability via run; learning file alone suffices.)

5. **Plan prescribed `dateToRfc3339` filter that didn't exist in eleventy.config.js** — Recovery: added the filter. Not a workflow error; plans frequently prescribe new helpers. Discoverability via clean build error.

6. **Agent-native-reviewer false-positive on grep tokenization** — Existing rule covers (verify-via-Read before flagging). No action.

## Tags

- category: best-practices
- module: docs-site, eleventy, validate-seo
- patterns: reconciliation-first, consumer-sweep, multi-agent-review
- prs: 2973, 2486 (drain pattern), 2794 (multi-agent-review pattern source)
- issues-closed: 2942, 2943, 2944, 2945, 2946, 2947, 2948, 2949
- issues-filed: 2977 (deploy-docs.yml obsolete /pages/ paths), 2978 (FAQPage parity drift)
