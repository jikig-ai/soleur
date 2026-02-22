---
title: "feat: Add Sales domain with CRO and specialist agents"
type: feat
date: 2026-02-22
---

# Add Sales Domain

## Overview

Add a Sales domain to Soleur with a CRO (Chief Revenue Officer) domain leader and 3 specialist agents. The Sales domain fills the unowned mid-to-bottom revenue funnel (MQL-to-close). Single PR following the existing domain pattern (copy-paste, not refactor).

**Issue:** #247
**Branch:** feat-sales-domain
**Brainstorm:** `knowledge-base/brainstorms/2026-02-22-sales-domain-brainstorm.md`
**Spec:** `knowledge-base/specs/feat-sales-domain/spec.md`

## Problem Statement

Soleur has 5 business domains (Engineering, Legal, Marketing, Operations, Product) but nobody owns the revenue conversion pipeline -- lead qualification through deal closing. The Marketing domain generates demand; Sales converts it.

## Proposed Solution

Add `agents/sales/` with 4 agents following the existing domain pattern. Copy-paste the brainstorm command routing (Legal pattern as template). Trim a few bloated agent descriptions to stay under the 2,500-word budget.

[Updated 2026-02-22] Plan review unanimously recommended dropping the table-driven routing refactor. At 6 domains, the copy-paste cost (~18 lines) is trivial. Explicit LLM instructions are more reliable than data-driven generic routing. Refactor deferred until 8+ domains if needed.

## Technical Considerations

### CRO Naming Collision

The CMO description currently lists "CRO" as shorthand for the conversion-optimizer (Conversion Rate Optimization). **Resolution:** Update CMO description to spell out "conversion-optimizer." Sales owns the "CRO" abbreviation going forward.

### Sales Assessment Question

> **Sales implications** -- Does this feature involve sales pipeline management, outbound prospecting, deal negotiation, proposal generation, revenue forecasting, or converting leads into customers through human-assisted sales motions?

"Human-assisted sales motions" differentiates from product-led conversion (Marketing's territory).

### Agent Roster

| Agent | Scope | Disambiguation |
|-------|-------|----------------|
| **cro** | Orchestrates sales domain: pipeline posture, revenue actions, specialist delegation | Use individual sales agents for focused tasks; use this agent for cross-cutting sales strategy |
| **outbound-strategist** | ICP targeting, cadence design, lead scoring, channel mix | Use copywriter for email copy; use this agent for cadence strategy and audience targeting |
| **deal-architect** | Proposals, SOWs, battlecards, objection handling, discount frameworks | Use pricing-strategist for product pricing; use this agent for deal-level negotiation |
| **pipeline-analyst** | Pipeline health, deal velocity, stage definitions, forecast modeling | Use analytics-analyst for marketing attribution; use this agent for post-MQL sales metrics |

CRO follows the 3-phase domain leader pattern (Assess, Recommend/Delegate, Sharp Edges) matching the CLO template.

### Token Budget

Current word count: 2,613 (113 over 2,500 target). Adding 4 agents at ~40 words each = ~160 more. Need to trim ~275 words from existing descriptions. Trim the top 5-8 most bloated descriptions opportunistically -- no per-agent word targets.

### Docs Theme

Sales CSS color: `--cat-sales: #E06666` (coral). Visually distinct from existing palette.

## Files to Create

| File | Description |
|------|-------------|
| `agents/sales/cro.md` | Domain leader (3-phase: Assess, Recommend/Delegate, Sharp Edges) |
| `agents/sales/outbound-strategist.md` | Prospecting and cadence design |
| `agents/sales/deal-architect.md` | Proposals, battlecards, negotiation |
| `agents/sales/pipeline-analyst.md` | Pipeline metrics and forecasting |

## Files to Modify

| File | Change |
|------|--------|
| `commands/soleur/brainstorm.md` | Add assessment question #7, routing block, participation block for Sales (~18 lines) |
| `agents/marketing/cmo.md` | Replace "CRO" with "conversion-optimizer" in description |
| `agents/marketing/copywriter.md` | Add disambiguation: "Use outbound-strategist for cadence strategy" |
| `agents/marketing/pricing-strategist.md` | Add disambiguation: "Use deal-architect for deal-level negotiation" |
| `agents/marketing/analytics-analyst.md` | Add disambiguation: "Use pipeline-analyst for sales pipeline metrics" |
| `agents/marketing/conversion-optimizer.md` | Add disambiguation: "Use outbound-strategist for human-assisted outbound motions" |
| `agents/marketing/retention-strategist.md` | Add disambiguation: "Use pipeline-analyst for deal-level expansion metrics" |
| Top 5-8 bloated agent descriptions | Trim to stay under 2,500 words total |
| `docs/_data/agents.js` | Add Sales to DOMAIN_LABELS, DOMAIN_CSS_VARS, domainOrder |
| `docs/css/style.css` | Add `--cat-sales: #E06666` |
| `AGENTS.md` | Add CRO to domain leader table, update directory tree |
| `README.md` (plugin) | Add Sales section to agent tables, update counts |
| `.claude-plugin/plugin.json` | Version bump (MINOR), update description agent count |
| `CHANGELOG.md` | Document changes |
| Root `README.md` | Update version badge |
| `.github/ISSUE_TEMPLATE/bug_report.yml` | Update version placeholder |

## Acceptance Criteria

- [x] `agents/sales/` directory with cro.md, outbound-strategist.md, deal-architect.md, pipeline-analyst.md
- [x] CRO follows 3-phase domain leader pattern (CLO template)
- [x] All 4 new agents have disambiguation sentences
- [x] All 5 affected Marketing agents have cross-reference disambiguation sentences
- [x] Sales assessment question + routing block + participation block added to brainstorm.md
- [x] CMO description no longer references "CRO" abbreviation
- [x] Docs data files updated (agents.js: 3 edits, style.css: 1 edit)
- [ ] Docs site builds successfully: `npx @11ty/eleventy --input=docs --output=docs/_site_test` from repo root
- [x] AGENTS.md domain leader table and directory tree updated
- [ ] Agent description word count under 2,500: `shopt -s globstar && grep -h 'description:' plugins/soleur/agents/**/*.md | wc -w`
- [ ] All version files updated (plugin.json, CHANGELOG.md, plugin README.md, root README.md badge, bug_report.yml)
- [ ] Version bump: MINOR

## Test Scenarios

- Given a feature about "building an outbound sales cadence", when brainstorm Phase 0.5 runs, then CRO participation is offered
- Given CRO is accepted, when Phase 1.2 runs, then CRO provides a sales assessment alongside repo research
- Given a feature with marketing implications only, when brainstorm Phase 0.5 runs, then only CMO is offered (no false positive for Sales)
- Given `Task outbound-strategist(...)` is called directly, when it executes, then it designs cadence strategy (not email copy)
- Given `npx @11ty/eleventy --input=docs --output=docs/_site_test` runs from repo root, when build completes, then Sales domain appears on agents.html with coral color
- Given the 4 new agents are added, when the word count check runs, then output is under 2,500

## Dependencies and Risks

| Risk | Impact | Mitigation |
|------|--------|-----------|
| Sales detection triggers on Marketing features | False positive routing | Assessment question emphasizes "human-assisted sales motions" |
| Token budget too tight after adding 4 agents | Over 2,500 words | Trim top 5-8 bloated descriptions before adding |
| CRO abbreviation confusion | Misrouting between conversion-optimizer and Chief Revenue Officer | Update CMO description first |

## Non-Goals

- Table-driven routing refactor (deferred until 8+ domains)
- Sales-specific skills or commands
- Moving existing agents between domains
- Creating sales knowledge-base artifacts (CRO bootstraps from existing files)
- Cleaning up `agents/community/` placeholder (separate task)

## References

- Brainstorm: `knowledge-base/brainstorms/2026-02-22-sales-domain-brainstorm.md`
- Domain checklist: `knowledge-base/learnings/integration-issues/adding-new-agent-domain-checklist.md`
- Domain leader pattern: `knowledge-base/learnings/2026-02-21-domain-leader-pattern-and-llm-detection.md`
- CLO agent (template): `plugins/soleur/agents/legal/clo.md`
- Brainstorm command: `plugins/soleur/commands/soleur/brainstorm.md` (lines 57-291)
