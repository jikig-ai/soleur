# Learning: Nunjucks block inheritance requires wrapping {{ content | safe }}

## Problem

When adding `{% block extraHead %}` to `base.njk` for child template head injection, child templates cannot inject content into `<head>` if `base.njk` uses `{{ content | safe }}` directly (Eleventy's default content rendering pattern) without also wrapping the body content in a `{% block content %}`.

## Solution

When introducing Nunjucks block inheritance to an Eleventy layout that uses `{{ content | safe }}`:

1. Add `{% block extraHead %}{% endblock %}` before `</head>` (for head injection)
2. Wrap `{{ content | safe }}` in `{% block content %}{{ content | safe }}{% endblock %}` (for body override)

Both changes are backwards-compatible — existing templates that don't define these blocks work unchanged because Nunjucks falls through to the default block content.

Child templates then use:
```njk
{% block extraHead %}
<meta property="og:type" content="article" />
<script type="application/ld+json">...</script>
{% endblock %}

{% block content %}
<section>...</section>
{% endblock %}
```

## Key Insight

Nunjucks block inheritance is all-or-nothing per layout. You cannot selectively inject into `<head>` via `{% block %}` while keeping the body as `{{ content | safe }}`. The body must also use `{% block content %}` to enable the inheritance mechanism. This is a Nunjucks constraint, not an Eleventy one.

## Tags
category: build-errors
module: eleventy-templates
