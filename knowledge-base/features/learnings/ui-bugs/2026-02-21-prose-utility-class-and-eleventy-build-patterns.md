# Learning: Prose utility class and Eleventy build patterns

## Problem

The soleur.ai docs site had three readability issues: (1) long-form content (legal, changelog, getting started) stretched to the full 1200px container width, making text hard to read; (2) the changelog had `.changelog-entry` CSS that never applied because markdown-it generates plain HTML without wrapper classes; (3) the header used plain text instead of the gold S logo mark.

## Solution

### Single `.prose` utility class

Added one CSS class to `@layer components` providing `max-width: 75ch` and vertical rhythm (heading margins, paragraph margins, list padding). Applied via `<div class="prose">` wrapper in templates rather than per-page scoped styles.

For the changelog, combined `.prose` class with `#changelog-content` ID-scoped overrides for changelog-specific styling (mono font h2, border-bottom, first-child margin reset). This avoids duplicating rhythm rules.

### Eleventy build gotchas

1. **No `--config` flag needed** -- Eleventy auto-discovers `.eleventy.js` at the project root. Running with an explicit `--config` that doesn't exist fails silently or errors.
2. **Run from repo root, not docs dir** -- Data files (`_data/agents.js`) use relative paths like `plugins/soleur/agents` that resolve from CWD. Running `npx @11ty/eleventy --input=plugins/soleur/docs` from the repo root works; running from inside docs/ breaks.
3. **markdown-it not in devDependencies** -- `_data/changelog.js` imports markdown-it but it wasn't in package.json. `npm install markdown-it --no-save` fixes for local testing. Should be added to devDependencies if not already.

### Edit tool with non-unique patterns

Legal pages have identical `</div>\n</section>` closings for both `page-hero` and `content` sections. The Edit tool requires unique matches. Fix: include more surrounding context (the preceding paragraph text or DRAFT notice) to disambiguate.

## Key Insight

A single utility class (`.prose`) reused across all content pages is simpler than per-page CSS or a new template layout. When markdown-it generates classless HTML, use the parent container's ID for scoped overrides rather than trying to add classes to generated markup.

For Eleventy builds: always run from the repo root with `--input` pointing to the docs directory. This matches how data files resolve their relative paths.

## Session Errors

1. Eleventy build with `--config` flag failed (no config file at specified path)
2. Eleventy build from docs directory failed (relative path resolution)
3. Missing `markdown-it` package (not in devDependencies)
4. Edit tool duplicate match on `</div>\n</section>` in legal pages (needed more context)

## Tags

category: ui-bugs
module: docs-site
symptoms: content-too-wide, changelog-unstyled, eleventy-build-failure
