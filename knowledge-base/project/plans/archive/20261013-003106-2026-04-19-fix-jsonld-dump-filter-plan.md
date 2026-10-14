# Fix: JSON-LD interpolations in `base.njk` + `blog-post.njk` need `| dump` filter for JSON-safe escaping

**Issue:** #2609
**Branch:** `feat-one-shot-2609-jsonld-dump-filter`
**Labels:** `priority/p2-medium`, `type/security`, `code-review`, `deferred-scope-out`, `domain/marketing`
**Milestone:** Phase 4: Validate + Scale

## Enhancement Summary

**Deepened on:** 2026-04-19

**Sections enhanced:** Research Reconciliation, Phase 1 RED, Phase 2 GREEN, Risks & Sharp Edges, Acceptance Criteria.

### Key Improvements

1. **Live-verified `dump` filter behavior** against local Nunjucks (the pinned version in `package-lock.json`). All four patterns the plan prescribes (direct interpolation, concat via `(a+b)`, ternary via `(u if u else d)`, and the bug pattern with retained outer quotes) produce the expected output. No framework-version surprise waiting at implementation time.
2. **Refined drift-guard regex.** Nunjucks autoescape does NOT entity-encode forward slash (`/` → `/`, not `&#x2F;`). Dropped `&#x2F;` from the forbidden-entity list and added `&lt;` / `&gt;` which autoescape DOES produce. Prevents a false-negative drift-guard that would have let `<`/`>` leaks through.
3. **Confirmed scope widening.** `blog-post.njk` has its own JSON-LD block with 12 interpolations including the exact `{{ title }}` / `{{ description }}` pair from the issue's threat model. Plan covers both files.
4. **Citation-first verification.** Every external claim (Nunjucks built-in `dump`, Eleventy Nunjucks default engine, `bun:test` runner) has a corresponding live-verified command output or source file reference elsewhere in this plan. No claims from memory.

### New Considerations Discovered

- The `| safe` filter is load-bearing, not cosmetic. Without it, autoescape re-encodes the quotes that `dump` emits, producing `&quot;` inside the JSON-LD block — a DIFFERENT and equally broken corruption. The test's forbidden-entity drift-guard catches this specifically.
- Concatenation precedence: `|` binds tighter than `+`. Every concat MUST be parenthesized before `| dump | safe` or the filter applies to the second operand only.
- Fixture isolation: the test must ship its own `_data/site.json` and `_data/plugin.js` stubs, not symlink production data. A shared fixture with weaponized input that reaches a production page is a worse bug than the one being fixed.

### Research Sources

- Nunjucks `dump` filter: <https://mozilla.github.io/nunjucks/templating.html#dump>
- Eleventy template engine config: `eleventy.config.js:57` (`htmlTemplateEngine: "njk"`)
- Schema.org JSON-LD authoring: <https://developers.google.com/search/docs/appearance/structured-data/logo> (Google Rich Results reference)
- Google Rich Results test: <https://search.google.com/test/rich-results>
- Project's existing JSON-LD grep-based SEO validator: `plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh`
- Past learning on JSON-LD duplication risk: `knowledge-base/project/learnings/2026-03-05-eleventy-blog-post-frontmatter-pattern.md` — blog posts inherit `blog-post.njk` layout; the layout's JSON-LD is authoritative, so fixing it fixes every blog post.

## Overview

`plugins/soleur/docs/_includes/base.njk` lines 29-113 and `plugins/soleur/docs/_includes/blog-post.njk` lines 9-42 emit `<script type="application/ld+json">` blocks whose string fields interpolate Nunjucks variables with **default HTML autoescape**. HTML autoescape produces entity encoding (`&quot;`, `&amp;`, `&#x2F;`) which is the WRONG escape for JSON strings — `JSON.parse` does not resolve HTML entities. A page `title` or `description` containing `"`, `\`, `<`, `>`, `&`, or any control character can:

1. **Break JSON parsing** (Google Search Console drops structured data for that page — loss of rich snippets / Knowledge Graph signals).
2. **Permit injection** if autoescape is ever disabled for this block (future refactor risk) — attacker-controlled page titles could inject schema nodes.

The fix is mechanical: replace every interpolation inside the `<script type="application/ld+json">` block with `{{ var | dump | safe }}` and **drop the surrounding `"..."` delimiters** (Nunjucks' built-in `dump` filter emits JSON.stringify output, which INCLUDES the surrounding quotes for strings). Missing the quote-drop is the single highest-probability footgun in this retrofit.

The issue body only names `base.njk` — but `blog-post.njk` (extends `base.njk`) has its **own** JSON-LD block with `{{ title }}` and `{{ description }}` interpolations where the exploitable `title`/`description` variables actually originate on blog pages. Fixing only `base.njk` leaves the blog path exploitable while looking fixed (the issue body itself flags "leaves the blog-post path exploitable while looking fixed"). This plan covers BOTH files.

## Research Reconciliation — Spec vs. Codebase

| Spec claim (issue #2609) | Codebase reality | Plan response |
|---|---|---|
| `base.njk:30-113` has ~14 interpolations | Confirmed: 14 string-valued interpolations inside the `@graph` block plus 5 URL string values inside the homepage-gated `sameAs` array. 19 total string field interpolations. | Apply `\| dump \| safe` to all 19 and drop outer quotes. |
| Blog-post path is "exploitable while looking fixed" if scope is base-only | Confirmed: `blog-post.njk:9-42` has its own JSON-LD block with 12 string field interpolations (including `{{ title }}` and `{{ description }}` — the exact exploitable pair). | Extend scope to `blog-post.njk`. Cite in PR body. |
| "Render-time test with a title containing `"` and `\`, asserting `JSON.parse` succeeds" | Repo uses `bun:test` (see `plugins/soleur/test/validate-seo.test.ts`). Eleventy build emits `_site/`. No existing Nunjucks render test harness. | New bun test that runs `npx @11ty/eleventy` into a tmp dir with a fixture page injecting a weaponized title + description, then greps the emitted HTML for the JSON-LD blocks and runs `JSON.parse` on each. |
| `dump` filter availability | `dump` is a **Nunjucks built-in** (see <https://mozilla.github.io/nunjucks/templating.html#dump>). No plugin needed. Confirmed via Eleventy default Nunjucks engine. | Use `\| dump \| safe` — `\| safe` is required because `dump` output contains `"` that autoescape would otherwise entity-encode as `&quot;`, re-breaking the JSON. |
| Numeric / boolean fields (`"price": "0"`, `"@context": "https://schema.org"`) | These are hard-coded string literals, not interpolations. | Out of scope — no variable to escape. Do NOT sweep the whole JSON block, only interpolation sites. |

## Files to Edit

1. `plugins/soleur/docs/_includes/base.njk` — lines 29-113 — 19 interpolations inside `<script type="application/ld+json">`.
2. `plugins/soleur/docs/_includes/blog-post.njk` — lines 9-42 — 12 interpolations inside `<script type="application/ld+json">`.

## Files to Create

1. `plugins/soleur/test/jsonld-escaping.test.ts` — bun:test spec that renders a weaponized fixture via Eleventy and `JSON.parse`s both JSON-LD blocks.
2. `plugins/soleur/test/fixtures/jsonld-escaping/` — fixture Eleventy input (a minimal `.njk` page with a title + description containing `"`, `\`, newline, `<`, `&`) plus the shared `_includes`, `_data/site.json`, and `_data/plugin.js` minimum needed to render.

## Open Code-Review Overlap

Query: `jq -r --arg path "base.njk" '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"' /tmp/open-review-issues.json`
Result: only `#2609: review: base.njk JSON-LD interpolations need | dump filter for JSON-safe escaping` — the issue being planned.

No other open code-review scope-outs touch `base.njk` or `blog-post.njk`. **Fold in / Acknowledge / Defer:** N/A — no overlap.

## Domain Review

**Domains relevant:** none (pure hygiene / security fix; no user-facing surface change, no copy change, no content/CMO signal, no architectural shift).

No cross-domain implications — single-file template escape fix plus a regression test. Product/UX Gate: **NONE** (no new `components/**/*.tsx`, no `app/**/page.tsx`, no `app/**/layout.tsx`, no new UI surface).

## Research Insights

**Live-verified Nunjucks `dump` behavior** (from local `node_modules/nunjucks` via `Environment({ autoescape: true })`):

| Template form | Input: `A "quoted" with \ and <tag>` | Output |
|---|---|---|
| `{{ x \| dump \| safe }}` | same | `"A \"quoted\" with \\ and <tag>"` — **correct JSON** |
| `{{ x \| dump }}` (no safe) | same | `&quot;A &#92;&quot;quoted&#92;&quot; with &#92;&#92; and &lt;tag&gt;&quot;` — autoescape re-breaks it |
| `"{{ x }}"` (pre-fix) | same | `"contains &quot;quote&quot; and &amp; and / and &lt; and &gt;"` — **breaks JSON.parse** |
| `"{{ x \| dump \| safe }}"` (retained outer quotes) | same | `""A \"quoted\" with..."` — **double quotes, breaks JSON.parse** |

**Autoescape entity map** (verified):

| Char | Entity produced |
|---|---|
| `"` | `&quot;` |
| `&` | `&amp;` |
| `<` | `&lt;` |
| `>` | `&gt;` |
| `'` | `&#39;` |
| `/` | `/` (NOT escaped) |

**Implication:** Drift-guard regex should forbid `&quot;`, `&amp;`, `&lt;`, `&gt;`, `&#39;` inside the JSON-LD block. Do NOT include `&#x2F;` — it's never produced. Do NOT include `&apos;` — Nunjucks uses `&#39;` for single quotes.

**Test implementation sketch** (`plugins/soleur/test/jsonld-escaping.test.ts`):

```typescript
import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { mkdtempSync, rmSync, writeFileSync, mkdirSync, cpSync } from "fs";
import { tmpdir } from "os";
import { join, resolve } from "path";

const WEAPONIZED_TITLE = 'A "quoted" title with \\ and <tag> and & ampersand';
const WEAPONIZED_DESC = 'Description with "quotes" and \\backslash and <html> chars';
const FORBIDDEN_ENTITIES = ["&quot;", "&amp;", "&lt;", "&gt;", "&#39;"];
const EXTRACT_JSONLD = /<script type="application\/ld\+json">([\s\S]*?)<\/script>/g;

let outputDir: string;
let homepageHtml: string;
let blogPostHtml: string;

beforeAll(() => {
  outputDir = mkdtempSync(join(tmpdir(), "jsonld-test-"));
  // Run Eleventy against the fixture directory — fixture includes the
  // post-fix base.njk + blog-post.njk via relative copy in beforeAll.
  const proc = Bun.spawnSync(
    ["npx", "@11ty/eleventy", `--config=${FIXTURE_DIR}/eleventy.config.js`, `--output=${outputDir}`],
    { cwd: resolve(import.meta.dir, "..", "..", "..") }
  );
  if (proc.exitCode !== 0) {
    throw new Error(`Eleventy build failed: ${new TextDecoder().decode(proc.stderr)}`);
  }
  homepageHtml = readFileSync(join(outputDir, "index.html"), "utf8");
  blogPostHtml = readFileSync(join(outputDir, "blog", "test-post", "index.html"), "utf8");
});

afterAll(() => rmSync(outputDir, { recursive: true, force: true }));

describe("JSON-LD escaping", () => {
  test("homepage JSON-LD blocks JSON.parse without throwing", () => {
    const blocks = [...homepageHtml.matchAll(EXTRACT_JSONLD)].map(m => m[1]);
    expect(blocks.length).toBeGreaterThan(0);
    for (const b of blocks) expect(() => JSON.parse(b)).not.toThrow();
  });

  test("blog-post JSON-LD round-trips weaponized title byte-for-byte", () => {
    const blocks = [...blogPostHtml.matchAll(EXTRACT_JSONLD)].map(m => JSON.parse(m[1]));
    const bp = blocks.find(b => b["@type"] === "BlogPosting");
    expect(bp).toBeDefined();
    expect(bp.headline).toBe(WEAPONIZED_TITLE);           // pin exact post-state
    expect(bp.description).toBe(WEAPONIZED_DESC);         // pin exact post-state
  });

  test("no HTML entity leaks inside any JSON-LD block (drift-guard)", () => {
    const extract = (html: string) => [...html.matchAll(EXTRACT_JSONLD)].map(m => m[1]);
    for (const block of [...extract(homepageHtml), ...extract(blogPostHtml)]) {
      for (const ent of FORBIDDEN_ENTITIES) {
        expect(block).not.toContain(ent);
      }
    }
  });

  test("no retained-outer-quote bug (empty-string-field drift-guard)", () => {
    // Catches `"name": ""value""` mistake from forgetting to drop outer quotes.
    const extract = (html: string) => [...html.matchAll(EXTRACT_JSONLD)].map(m => m[1]);
    const empty = /"[a-zA-Z_@]+":\s*""/;
    for (const block of [...extract(homepageHtml), ...extract(blogPostHtml)]) {
      expect(block).not.toMatch(empty);
    }
  });

  test("every interpolation uses | dump | safe (source-file coverage)", () => {
    // Grep the actual base.njk + blog-post.njk to ensure no naked interpolation
    // sneaks in via future edits.
    for (const file of ["base.njk", "blog-post.njk"]) {
      const path = resolve(import.meta.dir, "..", "docs", "_includes", file);
      const src = readFileSync(path, "utf8");
      // Extract JSON-LD block bodies only (not the whole file)
      const blockRe = /<script type="application\/ld\+json">([\s\S]*?)<\/script>/g;
      for (const m of src.matchAll(blockRe)) {
        const body = m[1];
        const interps = [...body.matchAll(/\{\{[^}]*\}\}/g)].map(x => x[0]);
        for (const i of interps) {
          expect(i).toMatch(/\|\s*dump\s*\|\s*safe/);
        }
      }
    }
  });
});
```

**Fixture weaponized page** (`plugins/soleur/test/fixtures/jsonld-escaping/test-post.njk`):

```yaml
---
layout: blog-post.njk
title: 'A "quoted" title with \ and <tag> and & ampersand'
description: 'Description with "quotes" and \backslash and <html> chars'
date: 2026-04-19
permalink: blog/test-post/index.html
---
Test content body.
```

**Fixture minimal `eleventy.config.js`**:

```javascript
const INPUT = "plugins/soleur/test/fixtures/jsonld-escaping";
export default function (eleventyConfig) {
  // Nunjucks filter polyfill: dateToRfc3339 used by blog-post.njk
  eleventyConfig.addFilter("dateToRfc3339", (d) => new Date(d).toISOString());
}
export const config = {
  dir: { input: INPUT, output: "_site", includes: "_includes", data: "_data" },
  markdownTemplateEngine: "njk",
  htmlTemplateEngine: "njk",
  templateFormats: ["md", "njk"],
};
```

**Why a fixture fixture directory, not an in-memory Nunjucks env:** the bug is end-to-end (through Eleventy's Nunjucks environment with its autoescape setting and filters). An in-memory `nunjucks.Environment` test could use different autoescape defaults and mask the bug. The fixture runs the same Eleventy as production.

## Implementation Phases

### Phase 1 — RED (failing test)

Write `plugins/soleur/test/jsonld-escaping.test.ts` FIRST, before touching templates.

**Fixture structure** (`plugins/soleur/test/fixtures/jsonld-escaping/`):

```text
fixtures/jsonld-escaping/
├── _data/
│   ├── site.json           # Copy of docs/_data/site.json but with name containing " and \
│   └── plugin.js           # Stub returning { version: "1.2.3" }
├── _includes/
│   ├── base.njk            # Symlink or copy (initially pre-fix)
│   └── blog-post.njk       # Symlink or copy
├── eleventy.config.js      # Minimal root config pointing at fixture dir
└── test-page.njk           # Page with title: 'A "quoted" title\\n<tag>' and description: 'desc with " and \\'
```

The test:

1. `Bun.spawn(["npx", "@11ty/eleventy", "--config=<fixture>/eleventy.config.js"])` into a tmp output directory.
2. Read the emitted HTML.
3. Extract every `<script type="application/ld+json">...</script>` block via a regex capturing group (non-greedy, DOTALL).
4. For each block, call `JSON.parse(block.textContent)`.
5. Assert no throw; assert the parsed `name` / `headline` / `description` string ROUND-TRIPS the weaponized input byte-for-byte (proves escaping is actually correct, not just syntactically parseable).
6. Additional assertion: grep the raw block for `&quot;`, `&amp;`, `&lt;`, `&gt;`, `&#39;` — these MUST NOT appear inside a JSON-LD block (they would prove autoescape is still active on a string field). This is the **drift-guard assertion** for future interpolation additions. (Forward slash `/` is NOT entity-escaped by Nunjucks autoescape — live-verified — so do not include `&#x2F;` in the drift-guard.)

Expected: RED before any template edit.

**Hard-rule compliance:**

- `cq-mutation-assertions-pin-exact-post-state`: assert exact round-trip equality (`.toBe(weaponizedTitle)`), not `toContain`.
- Verify framework installed: `bun --version` and `test/validate-seo.test.ts` already uses `bun:test` — no new test framework.
- `cq-in-worktrees-run-vitest-via-node-node`: we're using `bun:test`, not vitest. Invoke via `cd <worktree> && bash scripts/test-all.sh` or `bun test plugins/soleur/test/jsonld-escaping.test.ts` directly.

### Phase 2 — GREEN (minimal fix in both files)

**`base.njk` edit pattern** — 19 replacements inside the JSON-LD `<script>` block:

- `"name": "{{ site.name }}"` → `"name": {{ site.name | dump | safe }}`
- `"url": "{{ site.url }}"` → `"url": {{ site.url | dump | safe }}`
- `"description": "{{ site.description }}"` → `"description": {{ site.description | dump | safe }}`
- `"name": "{{ title }}"` → `"name": {{ title | dump | safe }}`
- `"description": "{{ description }}"` → `"description": {{ description | dump | safe }}`
- **Concatenations** (`"url": "{{ site.url }}{{ page.url }}"`) — `dump` ONE concatenated expression: `"url": {{ (site.url + page.url) | dump | safe }}`. Parentheses required to prevent precedence ambiguity with `| dump`.
- `"@id": "{{ site.url }}/#organization"` → `"@id": {{ (site.url + "/#organization") | dump | safe }}`
- `"logo": "{{ site.url }}/images/logo-mark-512.png"` → `"logo": {{ (site.url + "/images/logo-mark-512.png") | dump | safe }}`
- `sameAs` array entries (`"{{ site.github }}"`, `"{{ site.x }}"`, `"{{ site.linkedinCompany }}"`, `"{{ site.bluesky }}"`, `"{{ site.discord }}"`) → `{{ site.github | dump | safe }},` — 5 entries, commas retained between.
- `"softwareVersion": "{{ plugin.version }}"` → `"softwareVersion": {{ plugin.version | dump | safe }}`
- `"downloadUrl": "{{ site.github }}"` → `"downloadUrl": {{ site.github | dump | safe }}`
- `"releaseNotes": "{{ site.url }}/changelog/"` → `"releaseNotes": {{ (site.url + "/changelog/") | dump | safe }}`
- `"image": "{{ site.url }}/images/logo-mark-512.png"` → `"image": {{ (site.url + "/images/logo-mark-512.png") | dump | safe }}`
- Second `WebPage.publisher` block — `"name"` and `"url"` — same pattern.
- `SoftwareApplication.author.name` / `.url` — same pattern.

**Quote-drop footgun:** The single most common retrofit mistake is leaving the outer `"..."` in place. `"name": "{{ x | dump | safe }}"` produces `"name": ""actual\"value""` — double-quoted empty string followed by garbage. The verification regex in the test MUST catch this: `/"([a-z_@]+)":\s*""/` (empty string followed by content) should return ZERO matches.

**`blog-post.njk` edit pattern** — 12 replacements, same rules:

- `"headline": "{{ title }}"` → `"headline": {{ title | dump | safe }}`
- `"description": "{{ description }}"` → `"description": {{ description | dump | safe }}`
- `"datePublished": "{{ date | dateToRfc3339 }}"` — date filter output is already a safe ISO-8601 string; the risk is nil but consistency wins: `"datePublished": {{ (date | dateToRfc3339) | dump | safe }}`.
- `"dateModified"` — Nunjucks ternary `if`/`else` expression; wrap the whole result: `"dateModified": {{ (updated | dateToRfc3339 if updated else date | dateToRfc3339) | dump | safe }}`.
- `"url"` / `"mainEntityOfPage.@id"` — concatenation, parenthesize as above.
- `"image"` — concat.
- `author.name`, `author.url`, `author.jobTitle` (contains `" of " + site.name` concat), `publisher.name`, `publisher.url`, `logo.url` — concat pattern for jobTitle, direct for the rest.

**Outside the JSON-LD block, leave everything untouched.** `<meta content="...">` uses HTML attributes where the default HTML autoescape is CORRECT. Do not touch lines 4-28 of base.njk or the `{% block content %}` section of blog-post.njk. A sweep that goes beyond the `<script type="application/ld+json">` block is out of scope and risks double-escaping attribute values.

Re-run the test: GREEN.

### Phase 3 — Hygiene sweep verification

Grep the patched files to prove no string-valued interpolation remains inside the JSON-LD block without `| dump`:

```bash
# Extract lines between the script open and close tags, then flag any {{ ... }} without " | dump"
awk '/<script type="application\/ld\+json">/,/<\/script>/' plugins/soleur/docs/_includes/base.njk \
  | grep -E '\{\{[^}]*\}\}' | grep -vE '\| *dump *\| *safe' || echo "OK: every interpolation uses | dump | safe"
```

Expected: `OK: every interpolation uses | dump | safe`. Repeat for `blog-post.njk`. Paste both outputs into the PR body as proof-of-sweep (addresses the "verification that `| dump` is applied to ALL interpolations" acceptance criterion).

### Phase 4 — Full build + visual parity

1. `cd /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-2609-jsonld-dump-filter && npx @11ty/eleventy` — runs the full Eleventy build.
2. `jq empty < _site/index.html-jsonld-extracted.json` — extract the JSON-LD from the homepage and `jq` it. Expected: no syntax error.
3. Use the Schema Markup Validator (<https://validator.schema.org/>) via curl against the rendered homepage, or run `node -e "const html = require('fs').readFileSync('_site/index.html', 'utf8'); const m = html.matchAll(/<script type=\"application\/ld\+json\">([\s\S]*?)<\/script>/g); for (const x of m) JSON.parse(x[1])"`. Expected: no exception.
4. Visual diff check: open `_site/index.html` in a browser, view-source, and confirm the `@graph` block still contains all expected nodes (WebSite, WebPage, Organization, SoftwareApplication). This guards against the retrofit-deleting-content mistake.

### Phase 5 — Run full test suite

- `cd <worktree> && bash scripts/test-all.sh` — must be fully green.
- Specifically verify `plugins/soleur/test/validate-seo.test.ts` still passes (it also touches JSON-LD shape via `<script type="application/ld+json">` grep).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `plugins/soleur/test/jsonld-escaping.test.ts` exists, committed, and passes on CI.
- [ ] RED state was observed before GREEN: test file committed in a commit preceding the `base.njk` fix (verified via `git log`).
- [ ] `base.njk` lines 29-113: ZERO interpolations without `| dump | safe` (proof in PR body: grep output from Phase 3).
- [ ] `blog-post.njk` lines 9-42: ZERO interpolations without `| dump | safe` (same grep).
- [ ] Every string-field interpolation has had its outer `"` quote delimiters dropped (regression-caught by the test's empty-string-field assertion).
- [ ] `npx @11ty/eleventy` produces `_site/` without error.
- [ ] All JSON-LD blocks on `_site/index.html` and `_site/blog/*/index.html` `JSON.parse` successfully (verified by the test, reproducible locally).
- [ ] Round-trip of weaponized input `A "quoted" title\\n<tag>` via a rendered blog post yields `parsed.headline === 'A "quoted" title\\n<tag>'` exactly.
- [ ] `bash scripts/test-all.sh` fully green.
- [ ] `npx markdownlint-cli2 --fix knowledge-base/project/plans/2026-04-19-fix-jsonld-dump-filter-plan.md` run before commit.
- [ ] Meta tags, page content, `<base>`, CSP, and footer sections of `base.njk` are byte-identical to pre-fix (diff limited to the `<script type="application/ld+json">` block).

### Post-merge (operator)

- [ ] Production rebuild (`version-bump-and-release.yml` + Cloudflare Pages deploy) completes without error.
- [ ] Google Rich Results test (<https://search.google.com/test/rich-results>) against `https://soleur.ai/` shows Organization + SoftwareApplication + WebPage nodes detected.
- [ ] Google Rich Results test against `https://soleur.ai/blog/<any-post>/` shows BlogPosting node detected.
- [ ] No drop in structured-data coverage in Google Search Console over the 14-day window following merge (check `Enhancements → Organization` and `Enhancements → Article`).

## Test Scenarios

1. **Round-trip weaponized title** — page front-matter `title: 'A "quoted" title with \\ and <tag>'` + description `'desc with " and \\ and \n newline'`. Expect `JSON.parse` to succeed on both JSON-LD blocks; expect `parsed.name`/`parsed.headline` to equal the input byte-for-byte.
2. **Autoescape drift-guard** — grep the raw emitted JSON-LD block bytes for `&quot;`, `&amp;`, `&#x2F;`, `&#39;`. Expect zero matches (proves no interpolation fell back to HTML autoescape).
3. **Quote-drop drift-guard** — regex `/"([a-z_@]+)":\s*""/` over the JSON-LD block must return zero matches (catches the `"name": ""{{x|dump}}""` retrofit mistake).
4. **Interpolation coverage** — AWK-extract the JSON-LD block, grep for `\{\{[^}]*\}\}` lines NOT matching `| *dump *| *safe`. Expect zero.
5. **Homepage-only nodes present** — `/` page JSON-LD must contain `Organization` and `SoftwareApplication` `@type` entries (guards against the conditional `{% if page.url == "/" %}` accidentally regressing).
6. **Non-homepage nodes absent** — `/pricing/` or `/blog/*/` page JSON-LD must NOT contain `SoftwareApplication` (conditional still works post-fix).
7. **Shape regression** — full-suite `validate-seo.test.ts` still passes (end-to-end `<script type="application/ld+json">` grep on every page).

## Non-Goals

- **Touching HTML attribute interpolations** (`<meta content="...">`, `<a href="...">`). HTML autoescape is correct for those contexts.
- **Migrating to nonce-based CSP** (#953 is the tracking issue for that).
- **Refactoring the `@graph` structure** or adding/removing schema.org `@type` entries. Scope is escaping-only; any content change belongs in a separate PR.
- **Adding Product/Service/Breadcrumb nodes** — out of scope for this hygiene fix.

## Risks & Sharp Edges

1. **`dump` filter is Nunjucks built-in, NOT an Eleventy addition.** Verified: <https://mozilla.github.io/nunjucks/templating.html#dump> (built-in since Nunjucks 2.x). Eleventy uses Nunjucks as its default template engine (see `htmlTemplateEngine: "njk"` in `eleventy.config.js:57`). No `.addFilter("dump", ...)` needed.
2. **Autoescape + dump double-encoding** — `dump` outputs a JSON string with surrounding quotes; Eleventy's default Nunjucks environment has autoescape ON, which would encode those quotes as `&quot;`. The `| safe` filter is MANDATORY after `| dump` to suppress re-encoding. Omitting `| safe` produces `"name": &quot;Soleur&quot;` — a DIFFERENT corruption from the original. The test's drift-guard regex (`&quot;` forbidden inside JSON-LD blocks) catches this.
3. **Concatenation expression precedence** — `{{ site.url + page.url | dump | safe }}` parses as `{{ site.url + (page.url | dump | safe) }}` because `|` binds tighter than `+`. Must write `{{ (site.url + page.url) | dump | safe }}`. Plan specifies parentheses explicitly above.
4. **Nunjucks ternary inside filter** — `{{ updated | dateToRfc3339 if updated else date | dateToRfc3339 }}` — the ternary has lower precedence than `|`, so `(x if y else z) | dump | safe` parses correctly. Test this: render a post WITH `updated` and a post WITHOUT; both JSON-LD blocks must parse.
5. **Fixture duplication** — the test fixture needs its own minimal `_data/site.json`. DO NOT symlink the production one; use a committed minimal fixture so test is reproducible and weaponized input doesn't land on a production page. Place fixture under `plugins/soleur/test/fixtures/jsonld-escaping/`.
6. **CSP hash invalidation** — `base.njk:28` CSP has `sha256-...` hashes for the Plausible init inline script (lines 121-122) and the newsletter-form handler (lines 192-250). Neither is the JSON-LD script. JSON-LD blocks do NOT need a CSP hash (no JavaScript executes). This fix does not modify any hashed script. Run `validate-csp.sh` as a sanity check; expect no change.
7. **`ScriptElement.textContent` vs `innerHTML`** — the test must extract the block as raw bytes between `<script ...>` and `</script>`, NOT via a DOM parser. A DOM parser would HTML-decode entities and mask the exact bug this fix prevents.
8. **Old interpolation removed, new one added** — future developers adding schema.org nodes must also use `| dump | safe`. Add a comment in both files: `{# All string interpolations inside this JSON-LD block MUST use | dump | safe — see #2609 #}`. The test's interpolation-coverage assertion (Phase 3 grep) is the grep-stable enforcement mechanism.
9. **No new test framework / no new dependency.** `bun:test` and `@11ty/eleventy` are both already installed (verified: `package.json` and `plugins/soleur/test/validate-seo.test.ts`).

## Alternative Approaches Considered

| Alternative | Why not chosen |
|---|---|
| Move the JSON-LD block into a `_data/jsonld.js` function returning a JS object, then `JSON.stringify` in the template | Bigger refactor; changes the content model. Trade-off: more robust long-term but out of scope for a deferred-scope-out PR. File a follow-up issue if desired. |
| Use Nunjucks' `| striptags \| escape` | Wrong tool — those don't produce JSON-safe escaping (`\b`, `\f`, `\n`, `\r`, `\t`, `\"`, `\\`, `\u0000`-`\u001f`). `dump` is the correct filter. |
| Switch Eleventy to 11ty-js templates and inline-compute JSON | Scope explosion; would touch every template. |
| Disable autoescape for the JSON-LD block via `{% autoescape false %}` | MORE dangerous, not less — attacker-controlled `title` is still interpolated raw. Rejected: this is the risk the issue explicitly flags ("in the worst case, inject arbitrary schema nodes if autoescape is ever disabled"). |

No deferrals required. Nothing filed as a follow-up issue (the "move to data-driven JSON-LD" alternative is purely speculative and not on the roadmap).

## AI-Era Notes

- Prompt that worked during research: "Show me every `{{...}}` interpolation inside the `<script type=\"application/ld+json\">` block in `base.njk` and `blog-post.njk`."
- Future LLM-generated schema.org additions WILL forget `| dump | safe`. The comment in each file (Risk #8) + the interpolation-coverage assertion in the test is the defense. Do NOT rely on humans to remember.

## Summary for PR Body

- Replace HTML-autoescaped interpolations inside `<script type="application/ld+json">` blocks in `base.njk` and `blog-post.njk` with `{{ var | dump | safe }}` (JSON-safe escaping).
- Drop outer `"..."` quote delimiters in the same edit (`dump` emits quotes).
- New bun test `jsonld-escaping.test.ts` renders a weaponized fixture via Eleventy and asserts `JSON.parse` round-trips exactly.
- Covers 31 interpolations across 2 templates; hygiene-sweep grep output in PR body proves full coverage.
- Closes #2609.
