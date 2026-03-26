---
title: "fix: add marketplace add step to getting-started page"
type: fix
date: 2026-03-26
---

# fix: Add marketplace add step to getting-started page

## Enhancement Summary

**Deepened on:** 2026-03-26
**Sections enhanced:** 3 (Proposed Solution, Acceptance Criteria, Context)
**Research sources:** Institutional learnings (3), codebase grep (27 files)

### Key Improvements

1. Added three-location lockstep update rule from institutional learning (FAQ visible text, FAQ `<details>`, JSON-LD must match)
2. Identified 6 additional files with the same missing marketplace step (out of scope but documented for follow-up)
3. Added explicit HTML code examples for the `<code>` tag nesting in the FAQ answer

### Relevant Institutional Learnings Applied

- `2026-03-26-case-study-three-location-citation-consistency.md` -- Three-location lockstep update pattern (body, FAQ details, JSON-LD)
- `2026-03-17-faq-section-nesting-consistency.md` -- FAQ section DOM depth consistency across templates
- `2026-03-26-seo-meta-description-frontmatter-coherence.md` -- Frontmatter fields must be updated as a unit

## Overview

The getting-started page (`plugins/soleur/docs/pages/getting-started.njk`) instructs users to run `claude plugin install soleur` but omits the prerequisite `claude plugin marketplace add jikig-ai/soleur` command. Since Soleur is a self-hosted marketplace (not on the official Anthropic registry), users must first register the marketplace before the install command will resolve. Without this step, `claude plugin install soleur` fails silently or errors.

## Problem Statement

New users following the getting-started instructions hit a dead end because the marketplace registration step is missing. This affects:

1. **Installation section** (line 57): Only shows `claude plugin install soleur`
2. **FAQ answer** (line 168): "What do I need to run Soleur?" mentions only `claude plugin install soleur`
3. **Structured data** (line 204): The JSON-LD FAQPage schema repeats the incomplete instructions

## Proposed Solution

Add `claude plugin marketplace add jikig-ai/soleur` as Step 1 before the existing install command in all three locations within `getting-started.njk`. The two-step sequence should be:

```
claude plugin marketplace add jikig-ai/soleur
claude plugin install soleur
```

### Changes Required

#### 1. Installation section (`plugins/soleur/docs/pages/getting-started.njk`, line 56-58)

Replace the single `<pre><code>` block with a two-line code block showing both commands in sequence:

```html
<div class="quickstart-code">
  <pre><code>claude plugin marketplace add jikig-ai/soleur
claude plugin install soleur</code></pre>
</div>
```

**Note:** The two commands must be on separate lines inside a single `<code>` element (no `<br>` tags) so they render as a multi-line code block. Do not add leading whitespace on the second line -- `<pre>` preserves all whitespace literally.

#### 2. FAQ answer (`plugins/soleur/docs/pages/getting-started.njk`, line 168)

Update the "What do I need to run Soleur?" answer to include both steps. Change from:

> Install with `claude plugin install soleur`

To:

> First, add the Soleur marketplace with `claude plugin marketplace add jikig-ai/soleur`, then install with `claude plugin install soleur`

The full updated `<p>` tag:

```html
<p class="faq-answer">For the self-hosted version, you need the Claude Code CLI with an Anthropic API key or a Claude subscription. First, add the Soleur marketplace with <code>claude plugin marketplace add jikig-ai/soleur</code>, then install with <code>claude plugin install soleur</code> and run <code>/soleur:go</code> to start. No additional dependencies or server setup needed. The cloud platform (coming soon) requires only a browser and a Soleur subscription.</p>
```

#### 3. JSON-LD structured data (`plugins/soleur/docs/pages/getting-started.njk`, line 204)

Update the FAQPage schema text to match the updated FAQ answer, including the marketplace add step. Per the three-location lockstep rule (learning: `2026-03-26-case-study-three-location-citation-consistency`), the JSON-LD `"text"` field must be plain text (no HTML/markdown) but semantically identical to the FAQ `<details>` answer:

```json
"text": "For the self-hosted version, you need the Claude Code CLI with an Anthropic API key or a Claude subscription. First, add the Soleur marketplace with claude plugin marketplace add jikig-ai/soleur, then install with claude plugin install soleur and run /soleur:go to start. The cloud platform (coming soon) requires only a browser and a Soleur subscription."
```

## Acceptance Criteria

- [ ] Installation section shows both `marketplace add` and `plugin install` commands in the correct order
- [ ] FAQ "What do I need to run Soleur?" answer includes both commands
- [ ] JSON-LD FAQPage structured data matches the updated FAQ text
- [ ] Eleventy docs build passes (`npx @11ty/eleventy --input=plugins/soleur/docs`)

## Test Scenarios

- Given a new user viewing the getting-started page, when they read the Installation section, then they see `claude plugin marketplace add jikig-ai/soleur` before `claude plugin install soleur`
- Given a new user reading the FAQ, when they expand "What do I need to run Soleur?", then the answer mentions adding the marketplace first
- Given a search engine parsing the page, when it reads the JSON-LD structured data, then the FAQ answer text includes the marketplace add step

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- documentation copy fix within an existing page.

## Context

- **File:** `plugins/soleur/docs/pages/getting-started.njk`
- **Marketplace config:** `.claude-plugin/marketplace.json` (owner: `jikig-ai/soleur`)
- **Scope note:** Other files also reference `claude plugin install soleur` without the marketplace step. These are out of scope for this task but should be tracked as a follow-up issue:
  1. `README.md` (line 21) -- repo root installation instructions
  2. `plugins/soleur/docs/pages/changelog.njk` (line 38, 66) -- "How do I upgrade?" FAQ + JSON-LD
  3. `plugins/soleur/docs/blog/what-is-company-as-a-service.md` (line 225) -- CaaS blog post
  4. `plugins/soleur/docs/blog/2026-03-16-soleur-vs-anthropic-cowork.md` (line 133) -- comparison post
  5. `plugins/soleur/docs/blog/2026-03-17-soleur-vs-notion-custom-agents.md` (line 130) -- comparison post

### Research Insights

**Three-location lockstep rule:** Per learning `2026-03-26-case-study-three-location-citation-consistency`, when the same factual claim appears in visible body text, FAQ `<details>` answer, and JSON-LD structured data, all three must be updated atomically. AI engines penalize pages where JSON-LD contradicts visible content.

**`<pre>` whitespace sensitivity:** The `<pre><code>` block in the Installation section preserves all whitespace literally. The second command must start at column 1 (no leading spaces) to render correctly. A common mistake is indenting the second line to match the HTML nesting depth.

**Edge case -- upgrade vs. fresh install:** The changelog.njk FAQ says "Run `claude plugin install soleur` to get the latest version." For upgrades, the marketplace is already registered, so only the install command is needed. The getting-started page is for first-time setup, where both steps are required. This distinction matters if the follow-up issue addresses changelog.njk.

## References

- `.claude-plugin/marketplace.json` -- confirms marketplace namespace is `jikig-ai/soleur`
- `plugins/soleur/docs/pages/getting-started.njk` -- the file to edit
- `knowledge-base/project/learnings/2026-03-26-case-study-three-location-citation-consistency.md` -- three-location update pattern
- `knowledge-base/project/learnings/2026-03-17-faq-section-nesting-consistency.md` -- FAQ DOM depth consistency
