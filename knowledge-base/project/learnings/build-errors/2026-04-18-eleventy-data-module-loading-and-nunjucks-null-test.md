---
title: "Eleventy data module loading rules and Nunjucks null-test limitations"
category: build-errors
module: docs
tags: [eleventy, nunjucks, data-module, named-exports, null-test, ssg]
date: 2026-04-18
synced_to: [work, plan]
symptoms:
  - "Eleventy data file not exposed as template variable (silent)"
  - "Nunjucks {% if x is not null %} parse error"
  - "Template renders fallback glyph despite live data fetch succeeding"
  - "Eleventy benchmark log omits data file that is physically imported"
---

# Eleventy Data Module Loading and Nunjucks Null-Test Limitations

## Problem

While shipping the AEO third-party validation surface (PR #2596), three distinct Eleventy/Nunjucks semantics blocked or silently broke the build:

1. **Filename drove the template variable name (hyphens unusable).**
   A new data file `plugins/soleur/docs/_data/github-stats.js` built and ran without error, but `{{ githubStats.stars }}` in `index.njk` evaluated to `undefined`. The community page — which consumes `communityStats` (importing `github-stats.js` transitively) — rendered ONLY the Discord row. No error, no warning.

2. **Sibling named exports silenced the default data loader.**
   After renaming to `githubStats.js` (fix #1 worked), adding `export function __resetCache()` next to the `export default async function` caused Eleventy to silently NOT load `githubStats.js` as a top-level data file. The Eleventy benchmark log no longer contained the file, and all `{{ githubStats.* }}` references regressed to `undefined`. The `communityStats.js` file, which statically imports `githubStats.js`, continued to work — but its OWN data key was still populated, masking the regression until the homepage stat strip flashed back to the fallback glyph.

3. **Nunjucks `is not null` test does not exist.**
   A review finding recommended `{% if githubStats.stars is not null %}` to preserve a legitimate `0` value. The test parses without error but evaluates as if the variable were `undefined` — a numeric `6` satisfies `is not null` with `NO`, breaking the guard. No Nunjucks built-in test distinguishes `undefined` from `null`.

## Root Cause

### 1. Eleventy data filename → template key

Eleventy maps `_data/<filename>.js` to the template variable `<filename>` verbatim. Kebab-case filenames (`github-stats.js`) produce variable names with hyphens (`github-stats`), which Nunjucks dotted access (`{{ github-stats.stars }}`) cannot resolve — the hyphen is parsed as subtraction. Bracket access (`{{ data['github-stats'].stars }}`) works, but breaks the convention used everywhere else on the site.

### 2. Eleventy's default-export-only data module contract

Eleventy 3's data loader calls the default export of `_data/*.js` files. When a module adds named exports alongside the default, Eleventy's module introspection appears to skip registration entirely — the file is ingested via transitive imports from sibling modules, but it is NOT registered as a top-level data key. The failure mode is silent: the benchmark log simply omits the file. No stderr, no error in the browser console.

### 3. Nunjucks test-operator surface

Nunjucks ships `is defined`, `is undefined`, `is string`, `is number`, `is divisibleby`, and a handful of others. There is no `is null` test; `is not null` parses but evaluates unpredictably. To distinguish `undefined` / `null` / `0`, either:

- Precompute a boolean in the `_data/*.js` module (e.g., `{ stars, showStars: stars != null }`) and gate the template on `showStars`.
- Use truthy guards and accept that `0` hides the tile (acceptable when the 0-case is uninteresting, e.g., an active public repo).
- Use bracket-compare `{% if x !== null and x !== undefined %}` if the Nunjucks runtime supports it (varies by version).

## Solution

### 1. Filename convention

All new `_data/*.js` files use camelCase matching a valid JavaScript identifier. Renamed `github-stats.js` → `githubStats.js`. Consumer: `{{ githubStats.stars }}`. Match the existing sibling pattern (`communityStats.js`, `blogRedirects.js`, `pageRedirects.js`).

### 2. Test helpers as default-export properties

To keep tests able to reset the module-scope `cached` memo without breaking Eleventy's loader, attach helpers as properties on the default export:

```js
// plugins/soleur/docs/_data/githubStats.js
let cached;

function __resetCache() {
  cached = undefined;
}

async function fetchGithubStats() {
  if (cached) return cached;
  // ...
}

fetchGithubStats.__resetCache = __resetCache;
export default fetchGithubStats;
```

Tests import via the default:

```ts
import githubStats from "../docs/_data/githubStats.js";
const __resetCache = githubStats.__resetCache;
```

This preserves Eleventy's default-export-only contract while keeping test isolation.

### 3. Truthy guard for stat tiles

Accepted the `0`-hides-tile trade-off for an active public repo. The code review's `is not null` suggestion was tested and reverted:

```nunjucks
{% if githubStats.stars %}
<div class="community-stat">
  <div class="community-stat-value">{{ githubStats.stars }}</div>
  <div class="community-stat-label">GitHub Stars</div>
</div>
{% endif %}
```

If a future use-case needs the 0-vs-null distinction, precompute the boolean in the data module.

## Prevention

1. **Data filename must be a JS identifier.** Reject kebab-case in review. Grep: `ls plugins/soleur/docs/_data/ | grep -- -` should return zero.
2. **`_data/*.js` files default-export-only.** Named exports break Eleventy loading silently. Tests attach helpers via `defaultFn.helperName = ...`.
3. **Verify Eleventy benchmark lists every new data file.** After adding `_data/x.js`, the build log must contain `Benchmark ... (Data) \`./plugins/soleur/docs/_data/x.js\``. If missing, the file is not registered.
4. **Never use `is not null` / `is null` in Nunjucks.** They parse but do not work. Precompute booleans in the data module or accept truthy-only guards.

## Session Errors

1. **Eleventy `_data/github-stats.js` not exposed as `githubStats` (hyphen breaks dotted Nunjucks access).**
   **Recovery:** renamed to `githubStats.js`. **Prevention:** enforce camelCase on `_data/*.js` filenames (see Prevention §1).

2. **`export function __resetCache()` alongside `export default` silently disabled Eleventy data-module loading.**
   **Recovery:** attached the helper as a function property on the default export. **Prevention:** keep `_data/*.js` default-export-only (see Prevention §2).

3. **Nunjucks `{% if x is not null %}` parsed but evaluated wrong for numeric values.**
   **Recovery:** reverted to truthy `{% if x %}`. **Prevention:** AGENTS.md / skill note: "Nunjucks has no `is null` test — precompute booleans in the data module or accept truthy-only guards."

4. **Playwright MCP `filename` parameter rejects paths outside repo root.**
   **Recovery:** wrote screenshots under `.worktrees/<branch>/.tmp-qa-screenshots/`. **Prevention:** The existing `hr-mcp-tools-playwright-etc-resolve-paths` already covers this; the corollary is that the `filename` argument is also scoped. Documented here as a reminder; not a new rule.

5. **Background shell composition pitfall: `pgrep … && echo || (npx --serve &)` exited before starting the server.**
   **Recovery:** used `nohup … > log 2>&1 & disown`. **Prevention:** Low ROI — case-by-case, not workflow-level.

## References

- PR #2596 — feat(aeo): third-party validation surface
- Existing learning: `build-errors/eleventy-seo-aeo-patterns.md` — SEO/AEO rendering pattern must be build-time, not client-side.
- Existing learning: `build-errors/eleventy-v3-passthrough-and-nunjucks-gotchas.md` — passthrough copy path resolution, catalog description sanitization.
- Rule carry-forward: `hr-mcp-tools-playwright-etc-resolve-paths` (AGENTS.md).
