---
title: "fix: add marketplace add step to getting-started page"
type: fix
date: 2026-03-26
---

# fix: Add marketplace add step to getting-started page

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

#### 2. FAQ answer (`plugins/soleur/docs/pages/getting-started.njk`, line 168)

Update the "What do I need to run Soleur?" answer to include both steps. Change from:

> Install with `claude plugin install soleur`

To:

> First, add the Soleur marketplace with `claude plugin marketplace add jikig-ai/soleur`, then install with `claude plugin install soleur`

#### 3. JSON-LD structured data (`plugins/soleur/docs/pages/getting-started.njk`, line 204)

Update the FAQPage schema text to match the updated FAQ answer, including the marketplace add step.

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
- **Scope note:** Other files also reference `claude plugin install soleur` without the marketplace step (README.md, changelog.njk, 3 blog posts). These are out of scope for this task but should be tracked as a follow-up issue.

## References

- `.claude-plugin/marketplace.json` -- confirms marketplace namespace is `jikig-ai/soleur`
- `plugins/soleur/docs/pages/getting-started.njk` -- the file to edit
