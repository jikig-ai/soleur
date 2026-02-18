---
title: "Eleventy v3 passthrough copy and Nunjucks template gotchas"
category: build-errors
module: docs
tags: [eleventy, nunjucks, ssg, passthrough-copy, frontmatter]
date: 2026-02-18
symptoms:
  - "Static assets (CSS, fonts, images) missing from build output"
  - "Template variables render as literal text in meta tags"
  - "Double slashes in og:url meta tags"
  - "Duplicate main tags in page layouts"
---

# Eleventy v3 Passthrough Copy and Nunjucks Template Gotchas

## Problem

When migrating Soleur's documentation site from hand-maintained HTML to Markdown + Eleventy v3, several configuration and templating issues emerged:

1. **Missing static assets**: CSS, fonts, and images were not copied to the build output, breaking all styling.
2. **Literal variable text in meta tags**: Template variables like `{{ stats.agents }}` rendered as the literal string `{{ stats.agents }}` in `<meta name="description">` tags instead of the computed value.
3. **Malformed og:url**: Open Graph URL meta tags had double slashes: `https://soleur.ai//pages/...` instead of `https://soleur.ai/pages/...`.
4. **Duplicate main elements**: Pages requiring custom classes on `<main>` ended up with two `<main>` tags in the DOM.
5. **Noisy catalog descriptions**: Agent and skill descriptions in catalog cards contained system-prompt prefixes like "You are a..." or "Use this agent when...", making them verbose and less user-friendly.

## Root Cause

### 1. Eleventy v3 passthrough copy path resolution

In Eleventy v3, when you set an input directory (e.g., `dir.input = "plugins/soleur/docs"`), passthrough copy paths are **always resolved relative to the project root, NOT the input directory**.

```javascript
// WRONG: This looks for "css/" at project root, not plugins/soleur/docs/css/
eleventyConfig.addPassthroughCopy("css");

// CORRECT: Explicit mapping from source (relative to project root) to output
eleventyConfig.addPassthroughCopy({ "plugins/soleur/docs/css": "css" });
```

### 2. Nunjucks does not resolve variables in YAML frontmatter

YAML frontmatter is parsed before template rendering. Nunjucks variable syntax in frontmatter values is treated as literal text:

```yaml
---
description: "{{ stats.agents }} agents available"  # Renders as literal "{{ stats.agents }}"
---
```

The Nunjucks template engine only processes the template body, not the frontmatter metadata. To use dynamic values in frontmatter, you must use Eleventy computed data or construct values in the template body.

### 3. page.url already starts with slash

Eleventy's `page.url` variable includes a leading slash: `/pages/agents.html`. Concatenating it with a base URL that also ends with a path separator creates double slashes:

```nunjucks
{{ site.url }}/{{ page.url }}  <!-- https://soleur.ai//pages/agents.html -->
```

### 4. Base layout already defines main tag

When a page template extends a base layout that contains `<main>`, adding another `<main>` in the child template creates invalid nested structure.

### 5. Agent/skill source files use system-prompt style

Agent `.md` files begin with instructions like "You are a code review agent..." and skill `SKILL.md` files start with "This skill should be used when...". These are meant for the LLM, not end users.

## Solution

### 1. Use explicit path mapping for passthrough copy

Always map from project root to output directory:

```javascript
// .eleventy.js
eleventyConfig.addPassthroughCopy({
  "plugins/soleur/docs/css": "css",
  "plugins/soleur/docs/fonts": "fonts",
  "plugins/soleur/docs/images": "images"
});
```

### 2. Build dynamic descriptions in template body

Instead of trying to use variables in frontmatter, construct meta tag content in the template:

```nunjucks
{# In base.njk #}
{% set metaDescription = description or site.description %}
<meta name="description" content="{{ metaDescription }}">

{# In page template #}
{% set description %}{{ stats.agents }} agents, {{ stats.skills }} skills, {{ stats.commands }} commands{% endset %}
```

Or use Eleventy computed data in `.eleventy.js`:

```javascript
eleventyConfig.addGlobalData("pageDescription", function() {
  return this.stats ? `${this.stats.agents} agents available` : this.description;
});
```

### 3. Concatenate URLs without extra slash

```nunjucks
<meta property="og:url" content="{{ site.url }}{{ page.url }}">
```

### 4. Add optional mainClass to base layout

Allow pages to customize the main element class via frontmatter:

```nunjucks
{# base.njk #}
<main{% if mainClass %} class="{{ mainClass }}"{% endif %}>
  {{ content | safe }}
</main>

{# 404.njk frontmatter #}
---
mainClass: "error-page"
---
```

### 5. Strip system-prompt prefixes from descriptions

For agents:

```javascript
function cleanAgentDescription(content) {
  // Remove "You are..." prefix
  return content.replace(/^You are (a |an |the )?/i, '').trim();
}
```

For skills:

```javascript
function cleanSkillDescription(content) {
  // Remove "This skill should be used when/before..." prefix
  return content
    .replace(/^This skill should be used (when|before) /i, '')
    .replace(/\.$/, '')  // Remove trailing period
    .trim();
}
```

## Key Insight

**Static site generators resolve paths at build time, not runtime**. When using input directories, always verify where paths are resolved from. In Eleventy v3, passthrough copy paths are relative to project root regardless of input directory setting.

**Template engines process in phases**. YAML frontmatter parsing happens before Nunjucks rendering. Variables in frontmatter remain literal text. Dynamic content must be computed in template logic or via Eleventy's data cascade.

**URL construction requires understanding the data shape**. Don't assume URL components need separators -- check if they're already included in the variable values.

**Content written for machines needs filtering for humans**. System prompts and instruction text should be stripped when displaying to end users.

## Prevention

1. **Always use explicit path mappings for passthrough copy** when working with non-root input directories. Don't rely on string-only paths.

2. **Test frontmatter variable resolution early**. If you need dynamic meta tags, verify the approach works before building out all templates.

3. **Inspect Eleventy data variables** in development. Use `{{ page | dump }}` or `{{ site | dump }}` to see actual values and avoid guessing at separators.

4. **Separate machine-readable from human-readable content**. Add a `userDescription` field to agent/skill frontmatter, or always clean descriptions at render time.

5. **Validate build output structure**. After layout changes, check the generated HTML for duplicate or nested semantic elements (`<main>`, `<header>`, `<footer>`).
