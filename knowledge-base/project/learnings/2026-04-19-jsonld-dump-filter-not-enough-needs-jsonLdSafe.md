---
name: JSON-LD `| dump` is not enough — `</script>` breakout requires a dedicated filter
description: Why `{{ x | dump | safe }}` inside `<script type="application/ld+json">` is insecure when a value can contain `</script>`, U+2028, or U+2029, and how a `jsonLdSafe` Eleventy filter closes the gap.
category: security-issues
module: docs/eleventy-templates
---

# JSON-LD `| dump` is not enough — `</script>` breakout requires a dedicated filter

## Problem

Issue #2609 reported that `<script type="application/ld+json">` blocks in `plugins/soleur/docs/_includes/base.njk` and `blog-post.njk` used naked `{{ x }}` interpolations. HTML autoescape produced `&quot;`, `&amp;`, etc. inside JSON string fields — Google dropped the JSON-LD, `JSON.parse` either threw or returned semantically corrupt content.

The initial fix replaced every interpolation with `{{ x | dump | safe }}` (Nunjucks built-in `dump` = `JSON.stringify`). Tests passed. Build was green.

Multi-agent review found **two** follow-on defects.

## Defect 1: Partial remediation — 9 other templates had the same bug

`base.njk` and `blog-post.njk` are the two most-touched templates, but nine other `.njk` files emit their own `<script type="application/ld+json">` blocks:

- `pages/about.njk` (FAQPage + ProfilePage with `{{ site.x }}`, `{{ site.linkedin }}`, etc.)
- `pages/blog.njk` (CollectionPage with `{{ title }}`, `{{ description }}`)
- `pages/agents.njk`, `skills.njk`, `getting-started.njk`, `vision.njk`, `changelog.njk`, `community.njk`, `pricing.njk` (FAQPage blocks with `{{ stats.agents }}`/`{{ stats.departments }}`/`{{ stats.skills }}` embedded inside the `text` field)
- `index.njk` (FAQPage blocks)

The drift-guard test initially scanned only the two included templates — so widening the fix required widening the test glob first. Without that, the other nine files would silently drift back to the bug on future edits.

**Fix pattern for embedded interpolations inside a longer string:**

```njk
"text": {{ ("Soleur deploys " + stats.agents + " agents across " + stats.departments + " departments.") | jsonLdSafe | safe }}
```

Concatenate the full string with `+`, then apply the filter once. Parentheses are load-bearing — Nunjucks `|` binds tighter than `+`.

## Defect 2: `dump` does not escape `</script>`

Live-verified against Nunjucks in `node_modules`:

```js
env.renderString('{{ x | dump | safe }}', { x: 'a</script><script>alert(1)</script>' });
// → "a</script><script>alert(1)</script>"
```

The HTML parser sees a literal `</script>` and closes the `<script type="application/ld+json">` tag. Everything after is parsed as HTML — an XSS breakout if `x` is attacker-controlled (e.g., a blog frontmatter value).

Additionally, U+2028 and U+2029 are valid JSON string characters but terminate JavaScript string literals in some legacy runtimes. `JSON.stringify` does not escape them.

## Solution

Register a custom Eleventy filter `jsonLdSafe` that combines `JSON.stringify` with HTML-embedding escapes:

```js
// eleventy.config.js
eleventyConfig.addFilter("jsonLdSafe", (value) =>
  JSON.stringify(value)
    .replace(/<\//g, "<\\/")
    .replace(/\u2028/g, "\\u2028")
    .replace(/\u2029/g, "\\u2029"),
);
```

Use everywhere a string flows into `<script type="application/ld+json">`:

```njk
"name": {{ site.name | jsonLdSafe | safe }},
"url": {{ (site.url + page.url) | jsonLdSafe | safe }},
"dateModified": {{ (updated | dateToRfc3339 if updated else date | dateToRfc3339) | jsonLdSafe | safe }},
```

Three rules:

1. **Drop the surrounding `"..."`** — `jsonLdSafe` emits quotes.
2. **Parenthesize concatenations** before the filter.
3. **Keep `| safe`** — Eleventy's Nunjucks has autoescape ON by default; without `| safe`, the output's `"` get re-encoded to `&quot;` and JSON.parse breaks.

The drift-guard test is written against the source templates, not the rendered output, so it surfaces missed sites at the edit level rather than at build time:

```ts
// plugins/soleur/test/jsonld-escaping.test.ts
const sources = walkNjkFiles(resolve(REPO_ROOT, "plugins/soleur/docs"));
for (const path of sources) {
  for (const blockMatch of src.matchAll(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/g)) {
    for (const interp of [...blockMatch[1].matchAll(/\{\{[^}]*\}\}/g)]) {
      expect(interp[0]).toMatch(/\|\s*jsonLdSafe\s*\|\s*safe/);
    }
  }
}
```

The fixture weaponized input now includes `</script><script>alert(1)</script>` and U+2028/U+2029, and the test body asserts neither leaks through unescaped.

## Key Insight

For JSON-LD inside HTML `<script>`, `JSON.stringify` is necessary but not sufficient. Three separate hazards live at the JSON ↔ HTML boundary:

1. **JSON → parse failure** — raw `"` or control chars break `JSON.parse`. Fix: stringify.
2. **HTML → tag breakout** — `</script>` closes the outer tag. Fix: `</` → `<\/`.
3. **JS runtime → string termination** — U+2028/U+2029 break legacy JS string parsing. Fix: `\u2028` / `\u2029` escape.

`dump | safe` only covers (1). The "JSON-LD safe" envelope is all three. Anywhere else a stringified value flows into `<script>` (inline JSON config, hydration blobs, JSONP) has the same failure modes.

## Tags

category: security-issues
module: docs/eleventy-templates
related: #2609
tech: eleventy, nunjucks, json-ld, schema.org, xss

## Session Errors

**Symlink depth mismatch in fixture `_includes/`** — Recovery: rm + re-ln -s with correct `../../../../` (4 levels, not 3). Prevention: `readlink -f` the symlink target before running `npx @11ty/eleventy` to surface broken links before the build error.

**YAML single-quote weaponization was too weak to force RED** — Recovery: switched fixture `test-post.njk` front matter to double-quoted YAML with real `\n`. Prevention: when weaponizing an input to force a RED, pick chars that break JSON *structurally* (newline, control chars, `</script>`), not just semantically (entities parse fine as literal bytes).

**Edit rejected with "File has not been read yet" after prior Edit** — Recovery: Read the file, then Edit. Prevention: when Bash output reveals a file's content, it does not count as a Read — re-read via the Read tool before the first Edit on each file in the session.

**Orphan `});` left after appending a helper function to the test file** — Recovery: second Edit to remove the stray brace. Prevention: when appending code after a closing `});`, include the closing brace in `old_string` anchor text so the replacement boundary is unambiguous; re-read the edited region before running tests.

**QA skill expected browser/API scenarios but plan had static-analysis scenarios** — Recovery: executed the scenarios inline via `node -e` and grep against `_site/`. Prevention: `qa` skill could detect static scenarios (regex/grep/JSON.parse in the scenario text) and route to a build-verification branch instead of "no scenarios found — skip".
