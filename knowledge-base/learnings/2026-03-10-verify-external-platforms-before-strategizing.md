# Learning: Verify external platforms via live fetch before strategizing

## Problem

Community member recommended claude.com/platform/marketplace as a distribution channel. The word "marketplace" combined with "visibility and distribution" context triggered a plugin-directory mental model — everyone assumed it was a browse-and-install app store for Claude Code plugins. Four parallel research agents (repo-research-analyst, learnings-researcher, CPO, CMO) were launched to evaluate the opportunity before anyone actually visited the URL.

When we finally WebFetched the page, it turned out to be an enterprise procurement platform in limited preview (partner waitlist, B2B billing layer) — fundamentally different from the assumed plugin directory. The 4 agents produced analysis grounded in a false premise.

## Solution

Gate external platform evaluations with a mandatory live fetch (WebFetch or browser visit) before spawning research agents. Classify the platform by three questions:

1. **Self-service or waitlist?** (Determines if you can even list)
2. **Discovery surface or procurement layer?** (Determines the audience)
3. **Does it accept your product category?** (Determines fit)

This gate costs 30 seconds. Skipping it cost 4 parallel agent runs (~5 minutes, ~225K tokens) producing analysis built on an incorrect premise.

## Key Insight

Names are not specifications. "Marketplace" can mean a plugin directory, an enterprise procurement portal, a consumer storefront, or a B2B listing. A 30-second page fetch eliminates ambiguity that 4 parallel agents cannot resolve from inference alone. Any assumption about an external platform's current state must be verified live, not inferred from its name or a third party's description.

## Related

- `knowledge-base/brainstorms/2026-03-10-claude-marketplace-evaluation-brainstorm.md` — full evaluation
- `knowledge-base/learnings/2026-02-25-platform-risk-cowork-plugins.md` — prior platform risk analysis
- GitHub issue #521 — revisit tracker (April 2026)

## Tags

category: process-issues
module: distribution-strategy
severity: medium
