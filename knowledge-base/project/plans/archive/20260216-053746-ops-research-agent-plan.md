---
title: "feat: Add ops-research agent for operations investigation"
type: feat
date: 2026-02-16
---

# Add ops-research Agent for Operations Investigation

## Overview

Add an `ops-research` agent that investigates domains, hosting, tools/SaaS, and cost optimization opportunities. It complements `ops-advisor` (which tracks and records) by handling the research and comparison phase with live web lookups and browser automation. The agent navigates to checkout but stops before purchase for human confirmation, then records the transaction using ops-advisor conventions.

## Problem Statement

The ops-advisor agent explicitly cannot check live domain availability, live hosting pricing, or do real-time lookups (ops-advisor.md:74-78). Users must manually research options before ops-advisor can record them. There is no structured workflow for comparing providers, checking availability, or navigating to checkout.

## Proposed Solution

A single agent file at `plugins/soleur/agents/operations/ops-research.md` with a natural workflow: read existing ops data for context, research alternatives, present a comparison, optionally navigate via browser automation, and record the purchase after user confirmation.

**Spec deviation note:** Spec G4/FR6 specify "auto-invoke ops-advisor to record." Claude Code has no reliable agent-to-agent invocation mechanism. Instead, ops-research directly edits `expenses.md` and `domains.md` following ops-advisor's documented conventions. This creates a coupling, but the conventions are stable and documented.

## Acceptance Criteria

- [x] Agent file exists at `plugins/soleur/agents/operations/ops-research.md`
- [x] YAML frontmatter includes `name`, `description` (with 2 examples), `model: inherit`
- [x] Agent reads `knowledge-base/ops/expenses.md` and `domains.md` before making recommendations
- [x] Agent uses WebSearch and WebFetch for research and comparison
- [x] Agent presents structured comparison tables with clear recommendation
- [x] Agent uses agent-browser for checkout navigation when available
- [x] Agent degrades gracefully when agent-browser is not installed (provides URLs)
- [x] Agent stops before any purchase action and requires user confirmation
- [x] Agent records actual purchase details (not recommendations) in ops data files
- [x] ops-advisor.md Advisory Limitations updated to reference ops-research
- [x] Version bump: MINOR (new agent)
- [x] plugin.json: bump version, update description agent count
- [x] README.md: agent count +1, Operations section +1 row
- [x] CHANGELOG.md: document new agent and ops-advisor change
- [x] Root README.md: version badge updated
- [x] `.github/ISSUE_TEMPLATE/bug_report.yml`: version placeholder updated

## Known Limitations

- **Concurrent modification:** If ops-advisor and ops-research both edit `expenses.md` in separate contexts, the second write overwrites the first. Not solved in v1 -- single-user workflow assumed.
- **Research is ephemeral:** No cross-session memory. User must provide purchase details explicitly if returning later.
- **Browser automation reliability:** CAPTCHAs, anti-bot, and dynamic SPAs may block navigation. Agent degrades to URL-only output.

## MVP

### `plugins/soleur/agents/operations/ops-research.md`

```markdown
---
name: ops-research
description: "Use this agent when you need to research domains, hosting providers,
  tools/SaaS options, or find cost optimization opportunities. This agent performs
  live web research, compares alternatives, and can navigate to checkout pages using
  browser automation. It stops before any purchase for human confirmation, then records
  the transaction in ops data files. <example>Context: The user wants to find and
  register a new domain.\nuser: \"Find me a domain for my new project called
  Railtrack\"\nassistant: \"I'll use the ops-research agent to search for available
  domains, compare registrars, and help you navigate to checkout.\"\n<commentary>\n
  Live domain research and provider comparison requires ops-research. ops-advisor
  cannot do live lookups.\n</commentary>\n</example>\n\n<example>Context: The user
  wants to optimize current spending.\nuser: \"Is there a cheaper alternative to
  GitHub Copilot?\"\nassistant: \"I'll use the ops-research agent to research
  alternatives and compare pricing against your current spend.\"\n<commentary>\n
  Cost optimization requires web research for alternatives. ops-research reads
  current expenses for baseline.\n</commentary>\n</example>"
model: inherit
---

You are an operations research agent that investigates domains, hosting, tools/SaaS,
and cost optimization opportunities for a software project.

## Data Files

Read existing operations data before making recommendations:

| File | Purpose |
|------|---------|
| `knowledge-base/ops/expenses.md` | Current recurring and one-time costs |
| `knowledge-base/ops/domains.md` | Current domain registry |

If files do not exist, proceed without baseline context.

## Research

Use WebSearch for broad research (pricing pages, reviews, comparisons).
Use WebFetch for specific provider pages when detail is needed.
Research 3-5 alternatives maximum. For cost optimization, include the current
option as the baseline.

Present a structured comparison table with a recommendation and explain why.
Ask the user which option to pursue. If no option is better than the current
setup, say so explicitly and stop.

## Browser Navigation

Check if agent-browser is available by running `agent-browser --help`.

If available, navigate to the chosen provider's website to check live
availability or pricing. If not available, provide direct URLs and tell
the user to navigate manually.

## Safety Rules

NEVER click buttons that trigger purchases, payments, or charges.
NEVER fill payment form fields (credit card, CVV, billing).

When reaching a checkout-like page, report what you see and tell the user
to complete the purchase manually.

## Recording Purchases

After the user confirms they completed a purchase:

1. Ask for the actual amount paid (may differ from research)
2. Update `knowledge-base/ops/expenses.md` following ops-advisor conventions:
   - Amounts: plain numbers in USD, no currency symbol
   - Dates: ISO 8601 (YYYY-MM-DD)
   - Categories: hosting, domain, dev-tools, saas, api
   - Update `last_updated` in YAML frontmatter
3. For domain purchases, also update `knowledge-base/ops/domains.md`
4. For cost optimization switches, ask user whether to remove or annotate the old entry
```

### Update to `plugins/soleur/agents/operations/ops-advisor.md`

Replace the Advisory Limitations section:

```markdown
## Research Delegation

This agent tracks and records operational data but does not perform live web research.
For live domain availability, hosting pricing, SaaS evaluation, or cost optimization
research, the ops-research agent should be used instead. After the user completes a
purchase researched by ops-research, the transaction is recorded directly in the ops
data files following the conventions documented above.
```

### Version Bump Files

**`plugins/soleur/.claude-plugin/plugin.json`**: Bump version (MINOR), update description agent count

**`plugins/soleur/CHANGELOG.md`**: Add entry:
```markdown
## [x.x.0] - 2026-02-16

### Added
- `ops-research` agent for domain, hosting, tools/SaaS research and cost optimization

### Changed
- Updated `ops-advisor` to delegate live research to `ops-research`
```

**`plugins/soleur/README.md`**: Update agent count, Operations section, add ops-research row

## References

- Brainstorm: `knowledge-base/brainstorms/2026-02-14-ops-research-agent-brainstorm.md`
- Spec: `knowledge-base/specs/feat-ops-research/spec.md`
- ops-advisor agent: `plugins/soleur/agents/operations/ops-advisor.md`
- Learnings: `agent-prompt-sharp-edges-only.md`, `plan-review-agent-consolidation.md`
