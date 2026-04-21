---
name: fact-checker-file-scope-plus-eleventy-footnote-gap
description: The `fact-checker` agent reviews each target file independently; a remediation applied to one file can leave the same claim stale in sibling files. Plus three Eleventy docs-site authoring gotchas surfaced in the same session (footnote plugin not wired, `#tag` hashtag rendering pitfall, `gemini-imagegen` pre-flight stale signal).
type: integration-issues
date: 2026-04-21
feature: content-service-automation
pr: "#2747"
issue: "#1944"
tags:
  - fact-checker
  - eleventy
  - blog-authoring
  - content-review
  - multi-file-consistency
---

# Learning: Fact-checker is file-scoped; Eleventy docs-site has three hidden authoring pitfalls

## Problem

While shipping the service-automation launch content (PR #2747), four independent traps showed up that share one class: **tooling validates per-file or at one surface, but the defect lives at a cross-file or cross-surface level that the tool can't see.**

1. **Fact-checker file-scope gap.** The `fact-checker` Task subagent was invoked against the blog post + distribution-content launch file together. It returned PASS on most claims and FAIL on three, one of which was "30 new tests" (overcounted vs. PR #1921's actual ~22). Remediation changed the blog body to "20+ new tests" — but Tweet 7 in the distribution file was still "30 new tests. 674 passing." Fact-checker had validated each file independently; after the blog edit, nothing re-crossed the two files. The inconsistency was caught only by the downstream multi-agent code-review pass.

2. **Eleventy footnote `[^1]` renders as literal text.** The blog post used Pandoc-style footnotes: `conversions. [^1]` + `[^1]: Plausible's ...`. `markdownlint-cli2 --fix` passed (valid markdown), the Eleventy build succeeded (no warning), but the rendered HTML contained literal `[^1]` glyphs — the docs site has no `markdown-it-footnote` plugin wired. Found by grepping the built HTML under `_site/blog/<slug>/index.html`. Remediation: inline the caveat as a parenthetical (`*(Note: …)*`). Would have shipped broken if only fact-checker + markdownlint ran.

3. **Fact-checker claimed wrong Eleventy `page.fileSlug` behavior.** On the same run, it flagged 4 "broken slug" findings claiming `/blog/{{ page.fileSlug }}/index.html` preserves `YYYY-MM-DD-` prefixes for dated filenames. Wrong: Eleventy's `TemplateFileSlug._stripDateFromSlug` regex `/\d{4}-\d{2}-\d{2}-(.*)/` strips the prefix automatically. The project's own `knowledge-base/project/learnings/2026-03-24-eleventy-fileslug-date-stripping.md` documents this exact behavior. The fact-checker agent did not consult the knowledge-base before asserting framework behavior. Verified false by reading the actual build output (`_site/blog/agents-that-use-apis-not-browsers/` — date stripped).

4. **`# hashtag` with space parses as ATX H1.** Two lines in the distribution-content file copied the structure of `knowledge-base/marketing/distribution-content/2026-04-17-repo-connection-launch.md` but introduced a space after `#`: `# solofounder` instead of `#solofounder`. CommonMark parses that as an H1 heading. `markdownlint-fix` runs flag MD025 (single-h1-violation) and the autofix is not recoverable per `cq-prose-issue-ref-line-start`. The precedent file pairs `#solofounder` (no space) with `<!-- markdownlint-disable-next-line MD018 -->`; the new file had neither guard.

Bonus session finding (routed to skill definition, not a content gotcha):

5. **`soleur:gemini-imagegen` Phase 0 pre-flight is stale.** The skill's Phase 0 check attempts a minimal generation against `gemini-2.5-flash-image`, but on free-tier keys BOTH `gemini-2.5-flash-image` AND `gemini-3-pro-image` return `429 RESOURCE_EXHAUSTED` with `limit: 0`. The documented default model is `gemini-3-pro-image-preview`, so the pre-flight should exercise that exact model before greenlighting. Without the fix, every session on a free-tier key silently falls through to Pillow fallback without warning the operator.

## Root Cause

**Tool scope is narrower than defect scope.** Each tool validates what it can see:

| Tool | Scope | Blind spot |
|------|-------|------------|
| `fact-checker` agent | One claim at a time, per file | Cross-file consistency of the same claim after a remediation edit |
| `markdownlint-cli2` | Per-file lint rules (ATX headings, whitespace) | Framework-specific rendering (does the site's markdown pipeline actually expose this construct?) |
| Eleventy build | Config validity, template resolution | Raw markdown constructs that pass through unrendered because no plugin consumes them |
| `gemini-imagegen` Phase 0 pre-flight | Does the API key authenticate on the tested model? | Quota availability on the model the skill actually uses in Phase 1+ |

None of these individually surface the defect class they miss. Multi-agent review catches some of it (it caught #1, #4) but not all of it (#2 only surfaced via HTML grep; #3 was a fact-checker false positive contradicted by an existing learning).

## Solution / Prevention

1. **After any fact-check-driven remediation of a load-bearing claim, grep the same string across EVERY file in scope** — not just the one you edited. A single remediation can invalidate the fact-check on sibling files.

   ```bash
   # Example: after editing "30 new tests" → "20+ new tests" in the blog
   grep -rn "30 new tests" plugins/soleur/docs/blog/ knowledge-base/marketing/distribution-content/
   ```

2. **Grep the built HTML for raw-markdown fallthrough before committing any blog post.** If you use `[^N]` footnotes, `~~strike~~`, `==highlight==`, or any extension, run:

   ```bash
   npm run docs:build
   grep -E '\[\^|\^\]' _site/blog/<slug>/index.html  # should return empty
   ```

   If it returns non-empty, the docs site lacks the plugin and the construct will ship broken. Either wire the plugin (`@11ty/eleventy` + `markdown-it-footnote`) or inline the caveat as prose.

3. **Hashtag-line pattern for social distribution files:** always write `#tag` (no space) on its own line, preceded by `<!-- markdownlint-disable-next-line MD018 -->`. Copy from `knowledge-base/marketing/distribution-content/2026-04-17-repo-connection-launch.md` verbatim — don't retype the pattern.

4. **Fact-checker should consult the project's own learnings before asserting framework behavior.** Update the fact-checker agent prompt or instructions to search `knowledge-base/project/learnings/` for keywords from the claim under review before flagging. The Eleventy `fileSlug` behavior has been documented since 2026-03-24; a search would have prevented the false positive.

5. **`gemini-imagegen` Phase 0 should exercise the default model, not an alternate.** Update the skill's Phase 0 pre-flight to attempt a 1x1 generation against `gemini-3-pro-image-preview` (the documented default). If it returns 429, short-circuit to the Pillow fallback with a loud banner — don't silently defer the discovery to Phase 1.

## Session Errors

- **Bash `git status` from bare repo at session start** — Recovery: `cd` into worktree path. **Prevention:** `/soleur:work` Phase 0 should confirm CWD is inside a worktree before any git-status / git-diff / git-stash command; the worktree existed (`.worktrees/feat-content-service-automation/`), but the initial bash call ran from the bare repo root.
- **Plan referenced non-existent pillar filename (`06-why-most-agentic-tools-plateau.md`)** — Recovery: copywriter agent globbed the actual directory and picked `why-most-agentic-tools-plateau.md`. **Prevention:** `/soleur:plan` Phase should verify referenced file paths exist before committing a plan.
- **Fact-checker false positive on Eleventy permalink shape** — Recovery: cross-checked build output, verified date-stripping via existing learning. **Prevention:** see Solution step 4.
- **Cross-file consistency gap after fact-check remediation** — Recovery: multi-agent review caught Tweet 7 still said "30 new tests." **Prevention:** see Solution step 1.
- **Hashtag `# tag` H1 parsing** — Recovery: replaced with `#tag` + MD018 disable comment. **Prevention:** see Solution step 3.
- **Eleventy footnote `[^1]` non-rendering** — Recovery: inlined caveat as parenthetical. **Prevention:** see Solution step 2.
- **`blog_url` unquoted vs. precedent** — Recovery: quoted to match precedent. **Prevention:** linter-level check that `blog_url` frontmatter value is always quoted in `knowledge-base/marketing/distribution-content/*.md`.
- **"Third major capability in Phase 3" overclaim** — Recovery: checked `knowledge-base/product/roadmap.md`, found service-automation is one of ~20 shipped Phase 3 features; replaced with "Part of the Phase 3 'Make it Sticky' roadmap milestone." **Prevention:** when copy references canonical project state (roadmap counts, milestone ordinals), the content-review gate should cross-check `knowledge-base/product/roadmap.md` before merge.
- **awk tweet-length false alarm from MD018 HTML comment** — Recovery: Python-based extractor excluded comment lines, showed actual 254 chars. **Prevention:** tweet-length validators should strip HTML comments and markdownlint disable comments before counting.
- **Gemini image-gen quota exhaustion undetected by Phase 0 pre-flight** — Recovery: fell back to Pillow per documented fallback path. **Prevention:** see Solution step 5.

## Related

- `knowledge-base/project/learnings/2026-03-24-eleventy-fileslug-date-stripping.md` — the existing learning the fact-checker agent failed to consult
- `knowledge-base/project/learnings/2026-03-05-eleventy-blog-post-frontmatter-pattern.md` — related blog-authoring pattern
- `knowledge-base/project/learnings/2026-03-06-blog-citation-verification-before-publish.md` — the original fact-checker mandate (this learning extends that to cross-file consistency)

## Tags

category: integration-issues
module: fact-checker, eleventy-docs-site, gemini-imagegen
