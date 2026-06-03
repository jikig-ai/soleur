# Learning: Eleventy does not re-render Nunjucks inside frontmatter string values

## Problem

Building a per-page stat-led summary (#3169/#3994), the natural approach was a
frontmatter override like:

```yaml
pageSummary: "Soleur ships {{ stats.agents }} agents across 8 departments."
```

Eleventy does NOT evaluate `{{ ... }}` inside plain frontmatter *string values* —
the literal `{{ stats.agents }}` braces leak into the rendered HTML.

## Solution

Build the dynamic variants inside the template/include from the data globals
(`stats.*`) and select among them with a plain frontmatter *flag*, keeping a
literal string override only for fully-static text:

```njk
{# page-freshness.njk #}
{% if summaryRegister == "technical" %}
  <p class="page-summary">Soleur: {{ stats.agents }} agents, {{ stats.skills }} skills…</p>
{% elif pageSummary %}
  <p class="page-summary">{{ pageSummary }}</p>   {# static text only #}
{% else %}
  <p class="page-summary">Soleur is a Company-as-a-Service platform: {{ stats.agents }}…</p>
{% endif %}
```

Frontmatter carries the flag (`summaryRegister: technical`) or a static string —
never an interpolation expression.

## Key Insight

Frontmatter values are data, not templates. Interpolation expressions only
evaluate in the template body. To make per-page dynamic content driven by
frontmatter, pass a *selector flag* (enum/boolean) and do the interpolation in
the include. After any such change, grep the built site for leaked `{{`:
`grep -rn '{{' _site/ && echo LEAK`.

## Tags
category: build-errors
module: plugins/soleur/docs
