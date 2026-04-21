---
date: 2026-04-21
category: best-practices
tags: [eleventy, nunjucks, site.url, url-concatenation, content-move, drift-guard]
related_pr: 2705
related_issues: [2658]
---

# Learning: `{{ site.url }}<path>` without leading slash silently breaks rendered URLs

## Problem

When promoting `/blog/what-is-company-as-a-service/` to a new top-level
`/company-as-a-service/` page (PR #2705 / #2658), I copied the source-of-truth
prose verbatim from the old blog post. The original used two distinct
interpolation patterns inconsistently:

```njk
[Soleur]({{ site.url }})                                    {# ok #}
[…]({{ site.url }}blog/why-most-agentic-tools-plateau/)     {# BROKEN #}
[…]({{ site.url }}/getting-started/)                        {# ok  #}
```

`_data/site.json` declares `"url": "https://soleur.ai"` (no trailing slash).
So `{{ site.url }}blog/...` renders as `https://soleur.aiblog/...` —
host-mangled, not a 404 we'd catch with a link checker, but a wholly broken
hostname that resolves nowhere. Eleventy emits this without warning. Tests
that read template strings (`grep -r 'site.url}}blog' src/`) miss it. Only
inspecting rendered output catches it:

```bash
grep -oE 'https://soleur\.ai[a-zA-Z]' _site/<page>/index.html
# → https://soleur.aiblog/...   ← caught
```

7 broken URLs shipped on the first GREEN pass and were only caught when the
multi-agent review (code-quality-analyst) flagged the inconsistent slash
pattern as P3, prompting a render-output spot-check.

## Solution

```bash
# Detection: render and grep for host-letter concatenation artifacts
grep -oE "https://${HOST}[a-zA-Z]" _site/**/index.html

# Fix: normalize the interpolation to ALWAYS use a leading slash on paths
sed -i 's|{{ site.url }}blog/|{{ site.url }}/blog/|g' <files>
```

Per-page inline check (works because `site.url` has no trailing slash):

- ✅ `{{ site.url }}` (bare, for the homepage)
- ✅ `{{ site.url }}/<path>/` (with leading slash on the path)
- ❌ `{{ site.url }}<path>/` (no leading slash → host mangled)

If the convention were "site.url HAS a trailing slash", invert the rule.
The point is: pick one and grep both halves on every PR that touches
`{{ site.url }}` interpolations.

## Key Insight

**Template interpolation that builds URLs by string concatenation across
two configurable halves (host + path) silently produces malformed output
when one half drops or adds a slash.** The bug is "looks fine in source,
broken in render" — the worst class for code review because the source
diff is plausible. A `grep` of the source for "site.url}}blog" will find
the same bad pattern in 12 places and authoritatively report "consistent."

Detection requires building and inspecting the rendered output. The cheapest
gate is a host-followed-by-letter regex against `_site/`:
`https://${HOST}[a-zA-Z]` is a contradiction (a valid URL after the host
must be `/`, `?`, `#`, or end-of-string) — every hit is broken.

A drift-guard test that runs `eleventy build` in `beforeAll` and asserts
`grep -c '<host><letter>' <rendered-files>` returns 0 would catch this
class permanently. Worth adding to `marketing-content-drift.test.ts` or a
sibling file in a follow-up.

## Related

- PR #2705 (caught + fixed during multi-agent review)
- Plan: `knowledge-base/project/plans/2026-04-21-refactor-marketing-site-aeo-content-drain-plan.md`
- Sibling pattern: `cq-code-comments-symbol-anchors-not-line-numbers` —
  same family of "looks fine in source, breaks at runtime/render."

## Session Errors

- **Test build script wrong** (`npm run build` vs `npm run docs:build`) — Recovery: `cat package.json` → fix command + cwd. Prevention: `jq '.scripts' package.json` before prescribing a build invocation in a new test file.
- **Test SITE_ROOT path wrong** (`<docs>/_site` vs `<repo-root>/_site`) — Recovery: read `eleventy.config.js` `dir.output`. Prevention: When writing a test that reads Eleventy build output, always check `dir.output` + INPUT relativity before hardcoding paths.
- **Stale branch base silently reverted PR #2704** — Recovery: `git fetch origin main && git rebase origin/main`. Pattern-recognition agent caught it at review. Prevention: Add a "rebase before push" step to the `rf-before-spawning-review-agents-push-the` rule, or strengthen `wg-at-session-start` to re-fetch + offer rebase when the branch is more than ~12h old.
- **Broken URL concatenation in content-moved page** (THIS LEARNING) — Recovery: render + grep. Prevention: documented above.
- **Drift-guard allowlist incomplete on first pass** — Test 1 failed with 50+ hits across `distribution-content/` (archival social posts) and `copy/` (page-copy drafts). Recovery: extend allowlist constant + header comment. Prevention: When writing a prose-sweep drift guard, inventory the full matching set (`find <root> -name '*.md' | xargs grep <pattern>`) before committing test predicates.
