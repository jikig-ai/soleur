# Learning: Agent hallucinated author name from org/company name context

## Problem

The blog author name in `plugins/soleur/docs/_data/site.json` was set to "Jean Jikig" -- a hallucinated name that combined the founder's first name "Jean" with the company name "Jikigai" (from the GitHub org `jikig-ai`). This incorrect name appeared on all blog posts, in BlogPosting JSON-LD structured data, and in the Atom feed.

## Root Cause

The `docs-site` skill template (`plugins/soleur/skills/docs-site/SKILL.md`) did not include an `author` field in its `site.json` template. When blog infrastructure was added later, the agent inferred the author name from available context (GitHub org name, company name) rather than asking the user explicitly. The inference produced a plausible but fabricated name.

## Solution

1. Changed `site.json` author name from "Jean Jikig" to "Jean Deruelle"
2. Added `author` field (name + url) to the `docs-site` skill's `site.json` template so future scaffolding asks for it explicitly
3. Added "Author name" as item #3 in the docs-site skill's "Gather Project Info" step

## Key Insight

Personal names are proper identity data that should never be inferred from org names, GitHub handles, email prefixes, company names, or URL slugs. Any derivation is a hallucination risk. When a task requires a person's name, either read it from a canonical source or ask the user explicitly. A missing field is always less harmful than a fabricated one.

## Prevention Strategies

- Add a `## Founder` section to the brand guide with the canonical name, so content-generating skills have an authoritative source
- Content-generating skills (content-writer, social-distribute) should read `site.author.name` from `site.json` rather than inferring
- The `seo-aeo` audit should validate author field values against `site.json`, not just check for presence
- Scaffold templates should treat author/personal-name fields as required inputs, never optional with agent-derived defaults

## Tags

category: content-quality
module: docs-site
severity: medium
