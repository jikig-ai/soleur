---
title: "FAQPage JSON-LD block terminator must be literal </script>; in-string escape applies only inside Answer values"
date: 2026-04-22
module: docs/blog
problem_type: integration_issue
component: eleventy_nunjucks
symptoms:
  - "FAQPage JSON-LD parse fails with 'Extra data' error"
  - "Content after the JSON-LD block renders as raw markdown instead of HTML"
  - "`## Start Building` heading appears as literal text below the script block"
root_cause: misplaced_escape
severity: high
tags: [jsonld, faqpage, copywriter, content-pillar, 2609-class, script-breakout]
synced_to: [copywriter]
---

# FAQPage JSON-LD block terminator must be literal `</script>`; `<\/` escape applies only inside Answer string values

## Problem

When the copywriter agent drafted the P1.7 pillar post (PR #2811), it produced a FAQPage JSON-LD block that ended with a literal `<\/script>` instead of `</script>`:

```markdown
...
    }
  ]
}
<\/script>

## Start Building
```

At build time Eleventy passed the markdown through unchanged. The browser's HTML parser never saw a real `</script>` close tag, so the entire remainder of the post body (the `## Start Building` heading, the closing paragraph, and all template chrome through the `<footer>`) was absorbed as the `<script>`'s string content. Symptoms:

- Python `json.loads()` on the captured block failed with `Extra data: line 88 column 1 (char 6455)`.
- `## Start Building` appeared as literal text instead of an `<h2>`.
- The `/pricing/` and waitlist links in the CTA paragraph never rendered as anchors.

This is adjacent to the `#2609` `jsonLdSafe` class but isn't the same failure: #2609 is about un-escaped user content inside JSON string values. This one is about confusing WHERE the escape applies.

## Root cause

The [plan's copywriter prompt](../../plans/archive/) said:

> Inside Answer strings, escape any literal `</` token as `<\/`. The block terminator is a real `</script>`.

The copywriter agent collapsed the two rules and applied the `<\/` escape to the block terminator too. The escape IS correct for literal `</` substrings that appear INSIDE an Answer string's value (e.g., an answer about HTML that mentions `</script>` in prose). The escape is WRONG as the block terminator — the browser parses HTML looking for a real `</script>` token.

## Solution

Distinguish the two locations explicitly in the copywriter prompt and in the agent's Sharp Edges. The working structure:

```html
<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "FAQPage",
  "mainEntity": [
    {
      "@type": "Question",
      "name": "What about HTML code snippets inside an answer?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "The closing tag <\/script> must be escaped inside THIS string because the browser would otherwise exit the script block here."
      }
    }
  ]
}
</script>
```

Rule:

- **Inside a JSON string value**: `</` → `<\/` (defense-in-depth against a string that happens to contain the substring)
- **Block terminator**: real `</script>`, always, no exceptions

The JSON spec itself does not require escaping forward slashes (`/`). The `<\/` escape is purely an HTML-parser trap avoidance, and the trap only exists for substrings inside string values.

## Verification

After fixing, three assertions hold against the rendered HTML:

```python
import re, json
blocks = re.findall(r'<script type="application/ld\+json">(.*?)</script>', html, re.DOTALL)
faq = [b for b in blocks if '"FAQPage"' in b]
assert len(faq) == 1
data = json.loads(faq[0])
assert data['@type'] == 'FAQPage'
assert len(data['mainEntity']) == 10
```

And the `## Start Building` heading appears in the output as a proper `<h2 id="start-building">`.

## Prevention

- **Copywriter prompt contract** should spell out both placements with a before/after example for each.
- **CI build-time check** — after Eleventy build, grep `_site/blog/**/index.html` for the pattern `<\\/script>` (literal backslash-slash-script) and fail if any hit is not inside a `"text":` string value. Simpler: assert every `<script type="application/ld+json">` block extracts and JSON-parses.
- **AC in the plan** (was in place for PR #2811) — AC10 asserted the inline JSON parses. Make this a standard AC for every post that ships inline JSON-LD.

## Cross-references

- `#2609` / `jsonLdSafe` class — sibling case for interpolated-string escaping in templates (this case is about hand-written JSON in markdown body)
- `knowledge-base/project/learnings/best-practices/2026-04-19-jsonld-dump-filter-not-enough-needs-jsonLdSafe.md` — `jsonLdSafe` filter usage
- PR #2811 — original incident and fix

## Tags

category: integration-issues
module: docs/blog
