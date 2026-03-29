---
module: Content Pipeline
date: 2026-03-29
problem_type: best_practice
component: documentation
symptoms:
  - "Broken internal link using wrong blog slug"
  - "JSON-LD structured data contained duplicate word"
  - "Prohibited brand term used in content"
  - "Inaccurate factual claim about credential helper duration"
root_cause: inadequate_documentation
resolution_type: workflow_improvement
severity: medium
tags: [content-pipeline, review-agents, fact-checking, brand-voice, blog-post]
synced_to: []
---

# Content Pipeline: Review Agents Catch Quality Issues Before Ship

## Problem

Content creation pipeline for repo connection feature launch produced 3 content pieces (product update blog, technical deep-dive, social distribution). Without review, 5 quality issues would have shipped: a broken internal link (404), a JSON-LD typo indexed by search engines, a prohibited brand term, a misleading anchor text, and an inaccurate factual claim about credential helper exposure duration.

## Solution

The one-shot pipeline's review step (Step 4) ran two parallel review agents:

1. **Code reviewer** — caught broken link (`why-agentic-engineering-tools-plateau` vs correct `why-most-agentic-tools-plateau`), misleading anchor text ("GitHub App" linking to CaaS article), JSON-LD duplicate word, prohibited brand term "assistant", and stale `last_updated` frontmatter
2. **Fact-checker** — verified 22 technical claims against source code, found 2 inaccuracies: "typically under one second" credential helper duration (actual timeout is 120s for clones) and misleading attribution of auto-commit recovery to failed push scenarios

All issues were fixed in a single commit before proceeding to ship.

## Key Insight

Content review agents are as valuable for documentation/blog PRs as code review agents are for source code PRs. The fact-checker agent's 22-claim verification against actual source code prevented shipping inaccurate technical statements that would undermine credibility with developer audiences. Blog post internal links are particularly fragile because slugs are derived from filenames and easy to mis-remember.

## Session Errors

Session error inventory: no process errors detected. All quality issues were content-level and caught by the review phase (working as designed).

## Prevention

- Always run review agents on content PRs, not just code PRs
- For technical blog posts, use fact-checker agent to verify claims against source code
- For internal links, verify blog slugs against actual filenames in `plugins/soleur/docs/blog/` before using `{{ site.url }}blog/<slug>/` patterns
- Check brand guide prohibited terms list before finalizing content

## Tags

category: best_practice
module: Content Pipeline
