---
title: "fix: SEO audit agent should use curl -L when fetching live pages"
type: fix
date: 2026-03-27
---

# fix: SEO Audit Agent curl Redirect Handling (#1169)

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

## Acceptance Criteria

- [ ] `seo-aeo-analyst.md` "Important Guidelines" section includes a bullet about using `curl -L` to follow redirects
- [ ] `seo-aeo-analyst.md` Meta Tags audit step includes an inline note about `curl -sL`
- [ ] Next scheduled SEO audit does not produce false positives for meta tags or feed entries (verified by running the audit after merge)

## Test Scenarios

- Given the updated `seo-aeo-analyst.md`, when the agent runs an SEO audit on a Cloudflare-proxied site, then it should use `curl -sL` (with `-L`) to follow redirects and receive the actual page content
- Given a site behind Cloudflare Bot Fight Mode returning 301 redirects, when the agent checks meta tags on the live page, then it should report the tags as present (not falsely missing)
- Given the agent prompt, when grep for "curl" in `seo-aeo-analyst.md`, then at least two matches should appear (Important Guidelines + Meta Tags section)

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
