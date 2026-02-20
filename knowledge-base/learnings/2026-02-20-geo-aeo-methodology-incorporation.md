---
category: implementation-patterns
module: plugins/soleur
component: marketing
severity: medium
tags: [seo, aeo, geo, growth, content-strategy]
---

# Learning: GEO/AEO Methodology Incorporation

## Problem

Issue #164 required studying the Princeton GEO (Generative Engine Optimization) research and the resciencelab/seo-geo plugin to determine which techniques to incorporate into our existing AEO tooling.

## Solution

Incorporated the top 3 Princeton GEO techniques (source citations, statistics, quotations) into the growth-strategist agent's AEO audit section and added AI crawler access verification to seo-aeo-analyst. Extended validate-seo.sh with robots.txt AI bot checks.

### Key Research Findings

The Princeton GEO paper (KDD 2024, arxiv:2311.09735) tested 9 optimization methods. Results:

| Technique | Impact |
|-----------|--------|
| Cite Sources | +30-40% |
| Add Quotations | +30-40% |
| Add Statistics | up to +40% |
| Authoritative Tone | +15-30% |
| Easy-to-Understand | +15-30% |
| Keyword Stuffing | **-10% (negative)** |

The top 3 (citations, statistics, quotations) dramatically outperform everything else. Keyword stuffing -- the dominant legacy SEO tactic -- actually hurts AI visibility. This inverts traditional SEO wisdom.

### What We Changed (4 files, no new components)

1. **growth-strategist.md** -- Added source citations and statistics checks to AEO audit, plus GEO priority ordering
2. **seo-aeo-analyst.md** -- Added robots.txt AI crawler access verification (GPTBot, PerplexityBot, ClaudeBot, Google-Extended)
3. **validate-seo.sh** -- Added CI checks for robots.txt AI bot blocking with end-of-line anchored grep
4. **growth/SKILL.md** -- Updated Task prompts to include new GEO checks

### What We Skipped (YAGNI)

- No new agents or skills (extended existing ones)
- No llms-full.txt (spec still draft)
- No AI search monitoring (no clear API surface)
- No glossary system, stats data file, or comparison pages (content, not tooling)

## Key Insight

When agents gain new capabilities, the skills that invoke them via Task prompts must also update their prompt text. Otherwise the primary invocation path silently ignores the new checks. This was caught during plan review -- the growth SKILL.md `aeo` sub-command Task prompt listed specific checks by name and would not have included the new GEO checks without an explicit update.

## Gotchas

1. **robots.txt grep -A1 limitation** -- Only checks the line immediately after User-agent for Disallow. Multi-line stanzas with comments between directives may be misdetected. Documented as a known limitation in the script.
2. **Disallow path anchoring** -- `grep "Disallow: /"` false-matches `Disallow: /private/`. Must use end-of-line anchor: `grep -qiE "Disallow: /\s*$"`.
3. **Wildcard User-agent: \*** -- The script only checks named AI bots, not wildcard rules. A `User-agent: *` + `Disallow: /` blocks all bots but is not flagged. Documented as a known limitation via test.

## Prevention

- When modifying agent instructions, always check if skills reference the agent via Task prompts with hardcoded check lists
- When writing grep-based validators for structured text formats (robots.txt, YAML, etc.), use end-of-line anchors and document multi-line parsing limitations
