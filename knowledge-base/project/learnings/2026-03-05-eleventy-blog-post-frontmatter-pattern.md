# Learning: Eleventy blog post frontmatter and JSON-LD pattern

## Problem

When creating blog posts in the Eleventy docs site, it's unclear which frontmatter fields to include and whether to generate inline JSON-LD for BlogPosting schema.

## Solution

Blog posts inherit `layout` and `ogType` from `blog.json` directory data file. Individual blog post frontmatter should only include: `title`, `description`, `date`, `tags`. Do NOT add `layout` or `ogType` to individual posts.

For JSON-LD: the layout template handles BlogPosting schema automatically. Only add **inline** JSON-LD for supplemental schemas like FAQPage. Adding duplicate BlogPosting JSON-LD causes schema validation warnings.

Prose sections on listing pages (agents, skills) use the wrapper pattern from getting-started.md:

```html
<section class="content"><div class="container"><div class="prose">
  ...content...
</div></div></section>
```

## Key Insight

Eleventy directory data files (`blog.json`) cascade frontmatter to all files in the directory. Adding fields that are already inherited creates duplicates and can break templates. Always check for directory data files before adding frontmatter to individual pages.

Keyword density for SEO: primary keyword should appear 8-12 times in a ~3,000-word article (0.3-0.4% density) to stay natural without triggering stuffing penalties.

## Tags

category: build-errors
module: docs-site
