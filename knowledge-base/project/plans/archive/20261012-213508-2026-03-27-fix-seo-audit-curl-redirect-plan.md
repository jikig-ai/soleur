---
title: "fix: SEO audit agent should use curl -L when fetching live pages"
type: fix
date: 2026-03-27
---

# fix: SEO Audit Agent curl Redirect Handling (#1169)

## Enhancement Summary

**Deepened on:** 2026-03-27
**Sections enhanced:** 3 (Root Cause Analysis, Proposed Solution, Test Scenarios)
**Research sources:** Agent prompt learnings, codebase curl usage audit, scheduled workflow analysis

### Key Improvements

1. Confirmed fix is correctly scoped to only `seo-aeo-analyst.md` -- other agents use `curl -s` for different purposes (JSON APIs, webhooks, header checks) where `-L` is unnecessary or incorrect
2. Validated two-mention approach against "sharp edges only" agent prompt design principle (learning: 2026-02-13) -- curl redirect behavior with Cloudflare is exactly the kind of non-obvious gotcha that belongs in agent prompts
3. Mapped the full invocation chain: `scheduled-seo-aeo-audit.yml` workflow triggers `soleur:seo-aeo fix` skill, which triggers `seo-aeo-analyst` agent -- fix at agent level propagates to all invocation paths
4. Identified that audit steps beyond Meta Tags (Structured Data JS-injection check, AI Discoverability crawlability verification) could also trigger live page fetches -- the generic Important Guidelines bullet serves as catch-all coverage

### New Considerations Discovered

- The agent prompt currently contains zero curl references -- the agent independently chooses to use curl, making this a genuine "sharp edge" that the model gets wrong without explicit guidance
- Other marketing agents (growth-strategist, etc.) do not fetch live pages and are not affected
- The `infra-security` agent uses `curl -sI` intentionally without `-L` (checking response headers, not content) -- this is correct behavior, not a bug

## Overview

The `seo-aeo-analyst` agent uses `curl -s` without the `-L` flag when it independently decides to fetch live pages for verification during audits. Cloudflare's Bot Fight Mode returns a 301 redirect before serving actual page content. Without `-L`, `curl` receives only the redirect response (a bare 301 page with no meta tags, structured data, or content), causing false positive findings.

This caused false positives in:

- #1121 (meta tags reported missing -- actually present after redirect)
- #1123 (case studies reported missing from feed -- actually present)

Both were closed as false positives. This issue (#1169) addresses the root cause in the agent prompt.

## Root Cause Analysis

The `seo-aeo-analyst.md` agent prompt (in `plugins/soleur/agents/marketing/seo-aeo-analyst.md`) does not mention `curl` anywhere. The agent independently decides to use `curl` when verifying live pages during Step 2 (Audit). Since no guidance is provided, it defaults to `curl -s` without `-L`, which fails silently when Cloudflare returns a 301 redirect.

**Evidence chain:**

1. `curl -s https://soleur.ai | head -5` returns `<html><head><title>301 Moved Permanently</title></head>` (no content)
2. `curl -sL https://soleur.ai | grep -E 'og:|twitter:|canonical'` returns all 15+ meta tags correctly
3. The scheduled SEO audit workflow (`scheduled-seo-aeo-audit.yml`) invokes the agent, which then runs curl without `-L`
4. Build-time validation (`validate-seo.sh`) passes because it checks `_site/` output, not live URLs

### Research Insights

**Full invocation chain:** `.github/workflows/scheduled-seo-aeo-audit.yml` (cron: Monday 10:00 UTC) triggers `claude-code-action` with prompt `/soleur:seo-aeo fix`. The `seo-aeo` skill (SKILL.md) launches the `seo-aeo-analyst` agent via Task. The agent then independently decides to fetch live pages with curl. Fix at the agent prompt level propagates to all invocation paths (scheduled, manual `seo-aeo audit`, manual `seo-aeo fix`).

**Codebase curl audit:** 7 other agents reference curl, but all use it for different purposes where `-L` is either unnecessary or incorrect:

- `functional-discovery.md` / `agent-finder.md`: `curl -s --max-time 5` for JSON registry APIs (no redirects expected)
- `community-manager.md`: `curl -s -o /dev/null -w "%{http_code}"` for Discord webhooks (status code check only)
- `infra-security.md`: `curl -sI` for HTTP security header auditing (intentionally checks the redirect response itself, not the target)

**Agent prompt design principle:** Per learning `2026-02-13-agent-prompt-sharp-edges-only.md`, agent prompts should contain only what the model would get wrong without them. Cloudflare Bot Fight Mode's 301 redirect stripping page content is a non-obvious CDN behavior the model cannot predict from training data -- this is a textbook "sharp edge."

## Proposed Solution

Add explicit curl guidance to `plugins/soleur/agents/marketing/seo-aeo-analyst.md` in two locations:

### Change 1: Add to "Important Guidelines" section (line ~155)

Add a bullet to the existing "Important Guidelines" section at the bottom of the file:

```markdown
- When fetching live URLs with curl, always use `-L` to follow redirects -- Cloudflare Bot Fight Mode and similar CDN protections return 301/302 redirects that strip all page content from the initial response
```

**File:** `plugins/soleur/agents/marketing/seo-aeo-analyst.md` (line ~162, after the last existing bullet)

### Change 2: Add inline note to Meta Tags audit step

Add a guidance note within the Step 2 Meta Tags section to reinforce the `-L` flag at the point where the agent is most likely to reach for curl:

```markdown
- When fetching live pages for verification, always use `curl -sL` (follow redirects) -- Cloudflare Bot Fight Mode returns 301 redirects that strip all page content
```

**File:** `plugins/soleur/agents/marketing/seo-aeo-analyst.md` (after line ~52, within the Meta Tags audit block)

### Why Two Mentions

The Important Guidelines bullet (Change 1) is the generic catch-all covering all audit steps that might fetch live pages (Structured Data JS-injection check, AI Discoverability crawlability verification, Sitemap URL verification). The Meta Tags inline note (Change 2) targets the highest-frequency false positive source -- Meta Tags was the category where both #1121 and #1123 false positives occurred. Agent prompts benefit from reinforcement at the point of action, unlike code where DRY applies.

## Acceptance Criteria

- [x] `seo-aeo-analyst.md` "Important Guidelines" section includes a bullet about using `curl -L` to follow redirects
- [x] `seo-aeo-analyst.md` Meta Tags audit step includes an inline note about `curl -sL`
- [ ] Next scheduled SEO audit does not produce false positives for meta tags or feed entries (verified by running the audit after merge)

## Test Scenarios

- Given the updated `seo-aeo-analyst.md`, when the agent runs an SEO audit on a Cloudflare-proxied site, then it should use `curl -sL` (with `-L`) to follow redirects and receive the actual page content
- Given a site behind Cloudflare Bot Fight Mode returning 301 redirects, when the agent checks meta tags on the live page, then it should report the tags as present (not falsely missing)
- Given the agent prompt, when grep for "curl" in `seo-aeo-analyst.md`, then at least two matches should appear (Important Guidelines + Meta Tags section)

**Deterministic verification:**

```bash
# Verify curl mentioned in both locations (should return 2)
grep -c 'curl' plugins/soleur/agents/marketing/seo-aeo-analyst.md

# Verify -L flag is present in both mentions
grep -c '\-L' plugins/soleur/agents/marketing/seo-aeo-analyst.md

# Verify Important Guidelines section contains curl guidance
grep -A1 'Important Guidelines' plugins/soleur/agents/marketing/seo-aeo-analyst.md | grep -q 'curl.*-L'

# Verify Meta Tags section contains curl guidance
sed -n '/\*\*Meta Tags:\*\*/,/\*\*AI Discoverability:\*\*/p' plugins/soleur/agents/marketing/seo-aeo-analyst.md | grep -q 'curl.*-sL'
```

**Post-merge validation:** After merging, trigger a manual SEO audit run via `gh workflow run scheduled-seo-aeo-audit.yml`, then verify the resulting GitHub issue does not contain false positive findings for meta tags or feed entries.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- internal tooling fix to prevent false positive audit findings.

## Context

- **Learning:** `knowledge-base/project/learnings/2026-03-26-seo-audit-false-positives-curl-redirect.md` documents the full false positive investigation
- **Related plan:** `knowledge-base/project/plans/2026-03-26-fix-seo-bug-batch-1121-1122-1123-1124-plan.md` handled the real bugs from the same audit batch
- **Related issues:** #1121 (closed, false positive), #1123 (closed, false positive), #1122 (real, fixed), #1124 (real, fixed)

## References

- Target file: `plugins/soleur/agents/marketing/seo-aeo-analyst.md`
- Related issue: #1169
- Closes: #1169
