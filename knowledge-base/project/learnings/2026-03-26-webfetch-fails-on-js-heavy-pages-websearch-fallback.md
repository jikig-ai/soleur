# Learning: WebFetch Fails on JS-Heavy Pages — WebSearch Fallback Pattern

## Problem

`WebFetch` returns only CSS/HTML structure (no article content) when fetching JS-heavy blog pages like `figma.com/blog/*`. The actual content is rendered client-side via JavaScript, which WebFetch cannot execute. This happened twice in the same session, confirming it's not a transient failure.

## Solution

Use a two-step fallback:

1. **Try WebFetch first** — works on static/SSR pages
2. **If content is empty/CSS-only, fall back to WebSearch** — search engines have crawled and indexed the rendered content
3. **Fetch third-party analysis articles** — tech blogs (Muzli, AlternativeTo, Abduzeedo) often provide better structured summaries than the original announcement
4. **Fetch official documentation pages** — help centers and developer docs are usually static/SSR and WebFetch-friendly (e.g., `help.figma.com`, `developers.figma.com`)

In the Figma investigation, the combination of WebSearch + 4 third-party WebFetch calls produced more complete information than the original blog post would have.

## Key Insight

WebFetch is effectively a static HTML scraper — it cannot execute JavaScript. For modern SPA/CSR blog platforms, WebSearch is the primary research tool, not a fallback. Third-party coverage articles are often more information-dense than original announcements because they synthesize multiple sources.

## Session Errors

1. **WebFetch returned CSS-only content from Figma blog (twice)** — Recovery: switched to WebSearch + third-party articles. Prevention: check if first WebFetch returns meaningful content before retrying the same URL; if content appears to be only CSS/markup, immediately fall back to WebSearch.
2. **CTO background agent didn't complete in time** — Recovery: captured assessment as "pending" in brainstorm doc. Prevention: for time-sensitive brainstorms, don't block on domain assessments; weave them in if they arrive, note as pending if they don't.

## Tags

category: integration-issues
module: web-research
