# Spec: Sales Domain + Domain Routing Refactor

**Issue:** #247
**Branch:** feat-sales-domain
**Date:** 2026-02-22

## Problem Statement

Soleur has 5 business domains (Engineering, Legal, Marketing, Operations, Product) but no Sales domain. The mid-to-bottom revenue funnel (lead qualification through deal closing) is unowned. Additionally, the brainstorm command's domain routing has reached a maintainability threshold at 5 domains, and the agent token budget is over its 2500-word target.

## Goals

- G1: Refactor brainstorm command Phase 0.5 from hardcoded domain blocks to table-driven routing
- G2: Trim agent descriptions to get back under the 2500-word cumulative budget
- G3: Add Sales domain with CRO leader + 3 specialist agents (outbound-strategist, deal-architect, pipeline-analyst)
- G4: Clean boundary between Marketing (demand generation) and Sales (revenue conversion)

## Non-Goals

- Moving existing agents between domains
- Adding Customer Success, Finance, or other domains (tracked as "watch" items)
- Creating sales-specific skills or commands (agents only for now)
- Changing the plugin loader or agent discovery mechanism

## Functional Requirements

- FR1: Domain routing refactor must support all 5 existing domains + Sales without behavioral changes to existing flows
- FR2: Brand workshop and validation workshop special cases must still work after refactor
- FR3: CRO must follow the 4-phase domain leader contract (Assess, Recommend, Delegate, Review)
- FR4: CRO must orchestrate outbound-strategist, deal-architect, and pipeline-analyst
- FR5: Sales domain must appear on the docs site with proper CSS theming
- FR6: Each Sales agent must have disambiguation sentences referencing Marketing agents with overlapping scope

## Technical Requirements

- TR1: Cumulative agent description word count must be under 2500 words after all changes
- TR2: Brainstorm command Phase 0.5 must use a table-driven approach (no more per-domain code blocks)
- TR3: All 3 versioning files must be updated (plugin.json, CHANGELOG.md, README.md)
- TR4: Docs data files must be updated (agents.js domain labels/CSS vars/order, skills.js categories, style.css)
- TR5: AGENTS.md domain leader table and directory structure must be updated

## Execution Plan

### PR #1: Table-driven domain routing refactor + token audit

**Files to modify:**
- `commands/soleur/brainstorm.md` -- Replace Phase 0.5 hardcoded blocks with table-driven routing
- `agents/**/*.md` -- Trim bloated descriptions to get under 2500-word budget
- Version files (plugin.json, CHANGELOG.md, README.md)

### PR #2: Sales domain

**Files to create:**
- `agents/sales/cro.md` -- Domain leader
- `agents/sales/outbound-strategist.md` -- Prospecting and cadence design
- `agents/sales/deal-architect.md` -- Proposals, battlecards, negotiation
- `agents/sales/pipeline-analyst.md` -- Pipeline metrics and forecasting

**Files to modify:**
- `commands/soleur/brainstorm.md` -- Add one table row for Sales domain
- `docs/_data/agents.js` -- Add Sales to DOMAIN_LABELS, DOMAIN_CSS_VARS, domainOrder
- `docs/_data/skills.js` -- Update SKILL_CATEGORIES if needed
- `docs/css/style.css` -- Add `--cat-sales` CSS variable
- `AGENTS.md` -- Add CRO to domain leader table, update directory tree
- Version files (plugin.json, CHANGELOG.md, README.md)

## Acceptance Criteria

- [ ] Brainstorm Phase 0.5 routing is table-driven (no per-domain code blocks except special workshops)
- [ ] Agent description word count is under 2500 words
- [ ] Sales domain exists with CRO + 3 agents
- [ ] Docs site shows Sales domain with agents
- [ ] No behavioral changes to existing 5 domains
- [ ] All version files updated for both PRs
