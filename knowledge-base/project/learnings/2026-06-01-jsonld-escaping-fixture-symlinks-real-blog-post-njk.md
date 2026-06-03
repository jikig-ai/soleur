# Learning: jsonld-escaping fixture symlinks the real blog-post.njk — site.author schema changes must update the fixture stub too

## Problem

PR (#3174) repointed the blog-post `Person.knowsAbout` JSON-LD from
`site.author.credentials` to a new `site.author.knowsAbout` array. The
`docs:build` and the seo-aeo-drift-guard suite passed, but
`plugins/soleur/test/jsonld-escaping.test.ts` failed at its Eleventy fixture
build:

```
EleventyNunjucksError: Error in Nunjucks Filter `jsonLdSafe`
(./plugins/soleur/test/fixtures/jsonld-escaping/test-post.njk)
TypeError: Cannot read properties of undefined (reading 'replace')
```

## Root cause

`plugins/soleur/test/fixtures/jsonld-escaping/_includes/blog-post.njk` is a
**symlink** to the real `plugins/soleur/docs/_includes/blog-post.njk`:

```
_includes/blog-post.njk -> ../../../../docs/_includes/blog-post.njk
```

The fixture supplies its OWN `_data/site.json` stub. When the real template
started reading `site.author.knowsAbout`, the fixture's stub still had only
`credentials` — so `site.author.knowsAbout` was `undefined`, and
`jsonLdSafe(undefined)` threw on `.replace`. The error surfaces in the
*fixture* file, not the real one, which obscures the cause.

## Solution

Add the new field to the fixture stub
`plugins/soleur/test/fixtures/jsonld-escaping/_data/site.json` whenever
`site.author.*` (or any `site.*` key the symlinked template reads) changes.
Because this is the *escaping* fixture, include entries with quote/ampersand
breakout characters so the new field is also escaping-tested:

```json
"knowsAbout": ["Topic with \"quotes\"", "Topic with & ampersand", "Distributed systems"],
```

## Key Insight

Any template under `plugins/soleur/docs/_includes/` reachable through the
jsonld-escaping fixture symlink couples the real `site.json` schema to the
fixture's `_data/site.json` stub. Adding/repointing a `site.*` field the
template interpolates requires a mirror edit to the fixture stub in the same
change, or the fixture Eleventy build throws `jsonLdSafe(undefined)`. Grep
`_includes/blog-post.njk` for `site.author.` after any author-schema edit, then
diff the fixture stub's keys against the real one.

## Session Errors

- **jsonld-escaping fixture build threw on undefined `site.author.knowsAbout`** — Recovery: added `knowsAbout` to the fixture `_data/site.json` stub. Prevention: this learning + grep `_includes/blog-post.njk` for `site.*` reads and mirror the fixture stub on any `site.author.*` schema change.
- **`git stash list` blocked by PreToolUse hook** — Recovery: re-ran the probe without it. Prevention: already hook-enforced (`hr-never-git-stash-in-worktrees`); use `git show <ref>:<path>` / `ls -la` to inspect instead.
- **`Edit` to site.json rejected ("File has not been read yet")** after inspecting via `python3 -c json.load` — Recovery: Read tool first, then Edit. Prevention: already covered by `hr-always-read-a-file-before-editing-it`; a python/jq dump does not satisfy the read-before-edit tracker.

## Tags
category: build-errors
module: plugins/soleur/docs
