---
title: Incorporate Princeton GEO Techniques into AEO Tooling
type: feat
date: 2026-02-20
issue: "#164"
version_bump: PATCH
---

# Incorporate Princeton GEO Techniques into AEO Tooling

## Overview

The Princeton GEO (Generative Engine Optimization) research proved that citation, statistics, and quotation techniques improve AI search visibility by 30-40%, while keyword stuffing hurts it by ~10%. Our existing AEO tooling (growth-strategist agent + seo-aeo-analyst agent) covers content-level and technical checks but lacks GEO-specific techniques and AI bot access verification. This plan adds the most impactful GEO techniques to our existing agents without creating new components.

## Problem Statement

Our AEO content audit (growth-strategist) checks conversational readiness, FAQ structure, definition extractability, summary quality, and citation-friendly structure -- but does not prioritize source citations, statistics, or quotations (the top 3 Princeton GEO techniques). Our technical SEO audit (seo-aeo-analyst) checks llms.txt and JSON-LD but does not verify robots.txt allows AI crawlers. The validate-seo.sh CI script has no AI bot access check.

## Proposed Solution

Extend 4 existing files. No new agents, skills, or scripts. Apply "sharp-edges-only" prompt design -- add only what the LLM would get wrong without explicit instructions.

### Changes

**1. `agents/marketing/growth-strategist.md`** -- Add GEO techniques to AEO audit

Current AEO section has 5 checks (conversational readiness, FAQ structure, definition extractability, summary quality, citation-friendly structure). Add 2 GEO-specific checks and a prioritization note:

- **Source citations check:** Do pages cite authoritative external sources inline? Are claims backed by data, studies, or official documentation? Uncited claims reduce AI citation probability.
- **Statistics and specificity check:** Are concrete numbers used instead of vague qualifiers? ("31 agents across 4 domains" not "many agents").
- **Prioritization note at top of AEO section:** "Prioritize findings by GEO impact: source citations > statistics/numbers > quotations > definitions > readability. Keyword density is counterproductive for AI visibility -- flag keyword-stuffed content as a negative signal."
- **Rename section** from "AEO (AI Engine Optimization) Content Audit" to "GEO/AEO Content Audit" to reflect the expanded scope.
- **Update description frontmatter:** Add "GEO (Generative Engine Optimization)" to the first sentence of the description. Update the second example's commentary to say "Content-level GEO/AEO" instead of "Content-level AEO".

**2. `agents/marketing/seo-aeo-analyst.md`** -- Add AI bot access verification

- Update the AI Discoverability row in the analysis checklist table to: `llms.txt exists and follows spec, content is crawlable (no JS-only), robots.txt allows AI crawlers`
- Add a fourth bullet to the AI Discoverability subsection under Step 2: "Check robots.txt for User-agent rules that block AI crawlers (GPTBot, PerplexityBot, ClaudeBot, Google-Extended). If a bot is explicitly blocked with Disallow: /, flag as a warning. Absence of a rule is sufficient -- explicit Allow is better but not required."

**3. `skills/seo-aeo/scripts/validate-seo.sh`** -- Add AI bot access CI check

Add a new section after the llms.txt check:

```bash
# -- robots.txt AI bot access ------------------------------------------------
# Limitation: checks only the line immediately after User-agent for Disallow.
# Multi-line stanzas with comments between directives may be misdetected.

if [[ -f "$SITE_DIR/robots.txt" ]]; then
  pass "robots.txt exists"
  for bot in GPTBot PerplexityBot ClaudeBot Google-Extended; do
    if grep -qi "User-agent: $bot" "$SITE_DIR/robots.txt" && \
       grep -A1 -i "User-agent: $bot" "$SITE_DIR/robots.txt" | grep -qiE "Disallow: /\s*$"; then
      fail "robots.txt blocks $bot"
    else
      pass "robots.txt does not block $bot"
    fi
  done
else
  fail "robots.txt missing"
fi
```

Logic: fail if a bot is explicitly blocked with a full-site `Disallow: /` (anchored to end-of-line to avoid matching partial paths like `Disallow: /private/`). Pass if the bot is not mentioned (implicitly allowed) or explicitly allowed.

**4. `skills/growth/SKILL.md`** -- Update Task prompts and descriptions

- Update `aeo` sub-command description in the table to: "Audit content for AI agent consumability and GEO optimization (conversational readiness, FAQ structure, citation quality, source citations, statistics)"
- Update `aeo` sub-command Task prompt (lines 136-141) to include the new checks: "Check conversational readiness, FAQ structure quality, definition extractability, summary quality, citation-friendly paragraph structure, source citation presence, and statistics/specificity."
- Update `fix` sub-command Task prompt (lines 71-78) to mention GEO gaps alongside AEO gaps: "keyword alignment, search intent match, readability, and GEO/AEO gaps"

## Non-Goals

- No new agents, skills, or scripts
- No renaming of `seo-aeo` skill or `aeo` sub-command (avoids breaking existing usage)
- No glossary system, stats data file, or comparison pages (content concerns, not tooling)
- No llms-full.txt support (premature -- spec is still draft)
- No AI search monitoring/measurement tooling (no clear API surface yet)
- No changes to content-writer skill (it already generates FAQ sections)

## Affected Components

- Marketing agents: growth-strategist, seo-aeo-analyst
- Skills: growth (SKILL.md), seo-aeo (validate-seo.sh)
- Users of `growth aeo`, `growth fix`, and `seo-aeo audit/fix/validate` sub-commands

## Rollback

Revert the single commit. No data migrations, schema changes, or external service dependencies.

## Acceptance Criteria

- [ ] growth-strategist.md AEO section renamed to GEO/AEO with 2 new checks (source citations, statistics) and prioritization note
- [ ] growth-strategist.md description frontmatter updated to mention GEO
- [ ] seo-aeo-analyst.md checklist includes AI crawler access verification with specific bot names
- [ ] seo-aeo-analyst.md Step 2 AI Discoverability has fourth bullet for robots.txt AI bot check
- [ ] validate-seo.sh checks robots.txt does not block GPTBot, PerplexityBot, ClaudeBot, Google-Extended (with end-of-line anchoring)
- [ ] validate-seo.sh has limitation comment above the robots.txt section
- [ ] growth/SKILL.md `aeo` sub-command Task prompt includes source citations and statistics checks
- [ ] growth/SKILL.md `fix` sub-command Task prompt mentions GEO/AEO gaps
- [ ] Existing AEO checks preserved unchanged (no regressions)
- [ ] `bun test` passes (if tests exist for modified files)

## Test Scenarios

- Given a site with robots.txt containing `User-agent: GPTBot` + `Disallow: /`, when validate-seo.sh runs, then it reports FAIL for GPTBot blocking
- Given a site with no robots.txt, when validate-seo.sh runs, then it reports FAIL for missing robots.txt
- Given a site with permissive robots.txt (no AI bot blocks), when validate-seo.sh runs, then it passes all AI bot checks
- Given a robots.txt with `Disallow: /private/` (partial path, not root), when validate-seo.sh runs, then it passes (partial blocks are not full-site blocks)
- Given a robots.txt with `User-agent: GPTBot` + `Allow: /`, when validate-seo.sh runs, then it passes
- Given a page with vague claims ("many features"), when growth-strategist runs GEO/AEO audit, then it flags the vague claim and suggests a specific number
- Given a page with no external citations, when growth-strategist runs GEO/AEO audit, then it flags missing source citations
- Given the `growth aeo` sub-command is invoked, when the Task prompt is sent to growth-strategist, then the prompt includes source citations and statistics checks

## References

- Princeton GEO paper: https://arxiv.org/abs/2311.09735 (KDD 2024)
- resciencelab/seo-geo: https://github.com/resciencelab/seo-geo (329 stars, implements all 9 Princeton methods)
- Issue: #164
- Current files:
  - `plugins/soleur/agents/marketing/growth-strategist.md`
  - `plugins/soleur/agents/marketing/seo-aeo-analyst.md`
  - `plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh`
  - `plugins/soleur/skills/growth/SKILL.md`
