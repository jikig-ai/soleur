# Learning: Case study three-location citation consistency

## Problem

Case study pages have cost claims repeated in three locations: the "Cost Comparison" body section, the FAQ `<details>` answer, and the JSON-LD FAQPage structured data `"text"` field. When adding or modifying a citation, updating only the body text creates drift between the visible content and structured data. AI engines penalize pages where JSON-LD structured data contradicts visible content.

## Solution

When modifying any cost claim or citation in a case study, update all three locations in lockstep:

1. **Body text** (`## The Cost Comparison`): Full citation with markdown link and freshness signal
2. **FAQ `<details>` answer**: Same citation with markdown link (inside `<details>` tags, markdown syntax works)
3. **JSON-LD `"text"` field**: Same claim with source name only (plain text, no links — `schema.org` text fields do not support HTML/markdown)

Example pattern:

- Body: `According to [Robert Half's 2026 Legal Salary Guide](url), technology lawyers charge EUR 300-500/hour (as of 2026)`
- FAQ: `According to [Robert Half's 2026 Legal Salary Guide](url), technology lawyers charge EUR 300-500/hour (as of 2026)`
- JSON-LD: `According to Robert Half's 2026 Legal Salary Guide, technology lawyers charge EUR 300-500/hour (as of 2026)`

## Key Insight

Case studies are not single-text pages — they are structured documents where the same factual claims appear in three different rendering contexts. Any agent modifying cost claims must be instructed to update all three locations, not just the visible body text. The JSON-LD is invisible to users but critical for AI engine citation selection.

## Session Errors

1. **Eleventy build failed without --input flag** — Running `npx @11ty/eleventy` from the repo root fails because the docs live in `plugins/soleur/docs/`. Recovery: used `--input=plugins/soleur/docs`. **Prevention:** Document the correct build command in the docs build section of constitution or README.
2. **4 of 12 WebFetch URL verifications returned HTTP 403** — Inc.com, BLS.gov, CNBC, and Carta block automated fetchers. Recovery: accepted as verified based on prior CaaS post verification. **Prevention:** For URLs previously verified in earlier sessions, cross-reference the existing learning rather than re-fetching.
3. **Review agent false positive on "open-source" removal** — Code quality analyst compared against origin/main and flagged changes already merged to main as regressions from this branch. Recovery: verified via `git diff` that unstaged changes were citation-only. **Prevention:** Review agents should diff against the branch base, not against origin/main's full file content.

## Tags

category: content-structure
module: marketing
