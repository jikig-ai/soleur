---
title: "feat: Add Finance Domain"
type: feat
date: 2026-02-22
updated: 2026-02-22
---

# Add Finance Domain

## Overview

Add Finance as the 7th agent domain following the Sales domain template. Four agents: CFO (domain leader), budget-analyst, revenue-analyst, and financial-reporter. Operations stays separate per brainstorm decision.

## Problem Statement

The plugin covers 6 domains but lacks financial planning capabilities. Operations handles expense tracking -- not budgeting, revenue forecasting, or financial reporting.

## Proposed Solution

Follow the Sales domain pattern (v2.31.0). Create 4 agent files, update docs infrastructure, add brainstorm routing, bump version.

## Domain Boundary: Sales vs. Finance

Sales owns pipeline-derived revenue (deal-weighted forecasts from opportunity data). Finance owns company-level revenue (P&L, cash flow, financial reporting from aggregate data). Assessment questions must use distinct trigger terms to avoid both firing on the same brainstorm.

## Technical Approach

[Updated 2026-02-22] After merging `feat-domain-prerequisites` (v2.33.2): token budget dropped to 2,154/2,500 (346 words headroom -- no trimming needed), brainstorm routing is now table-driven (one row instead of 3 sections), AGENTS.md already includes "sales".

### Step 1: Agent Files (4 new files)

Create `plugins/soleur/agents/finance/`:

| File | Agent | Role |
|------|-------|------|
| `cfo.md` | CFO | Domain leader. 3-phase contract. Template: `agents/sales/cro.md` |
| `budget-analyst.md` | budget-analyst | Budget planning, allocation, burn rate |
| `revenue-analyst.md` | revenue-analyst | Revenue tracking, forecasting, P&L projections |
| `financial-reporter.md` | financial-reporter | Financial summaries, cash flow statements |

Each agent: YAML frontmatter (`name`, `description` with disambiguation, `model: inherit`), body (Scope, Sharp Edges, Output Format), financial disclaimer.

Disambiguation: each Finance agent references siblings. `ops-advisor.md` gets a disambiguation sentence referencing CFO (expense tracking vs. financial analysis boundary).

### Step 2: Documentation Infrastructure

**`docs/_data/agents.js`** (3 edits):
- `DOMAIN_LABELS`: add `finance: "Finance"` (after `engineering`)
- `DOMAIN_CSS_VARS`: add `finance: "var(--cat-finance)"`
- `domainOrder`: add `"finance"` (after `engineering`, before `legal`)

**`docs/css/style.css`** (1 edit):
- Add `--cat-finance: #26A69A;` to `@layer tokens :root` (teal -- distinct from existing greens)

### Step 3: Brainstorm Routing

[Updated 2026-02-22] Brainstorm routing is now table-driven. Add one row to the Domain Config table in `commands/soleur/brainstorm.md` Phase 0.5:

| Column | Value |
|--------|-------|
| Domain | Finance |
| Assessment Question | Does this feature involve financial planning, budgeting, budget allocation, cash flow management, or financial reporting? (Avoids "revenue" to prevent overlap with Sales) |
| Leader | cfo |
| Routing Prompt | "This feature has finance implications. Include finance assessment?" |
| Options | Include finance assessment / Brainstorm normally |
| Task Prompt | "Assess the financial implications of this feature: {desc}. Identify budget concerns, revenue model questions, and financial planning considerations the user should consider during brainstorming. Output a brief structured assessment." |

### Step 4: Project Documentation + Version Bump

| File | Changes |
|------|---------|
| `AGENTS.md` (plugin) | Add `finance/` to directory tree, add CFO to domain leader table, add "finance" to domain list |
| `README.md` (plugin) | Add Finance section (4 agents), update count to 58 |
| `README.md` (root) | Update domain list, "Your AI Organization" table, count to 58 |
| `plugin.json` | Update description with "finance", count to 58, version bump from 2.33.2 |
| `CHANGELOG.md` | New entry |
| `index.njk` | Update stats "6 Departments" to "7", add "finance" to inline text. Do NOT add Finance card (7 cards orphans the 3-col grid) |
| `bug_report.yml` | Update version placeholder |

## Acceptance Criteria

- [ ] 4 new agent files in `agents/finance/` following Sales template
- [ ] CFO follows 3-phase domain leader contract
- [ ] All agents have disambiguation sentences (siblings + cross-domain)
- [ ] Agent description token budget under 2,500 words
- [ ] Docs site builds successfully
- [ ] Finance domain appears on agents page with teal color
- [ ] Brainstorm routing detects finance implications and routes to CFO
- [ ] Version bumped (MINOR)

## Test Scenarios

- Given a docs build, when checking agents page, then Finance domain appears with 4 agents and teal dot
- Given a brainstorm about "budget planning", when Phase 0.5 runs, then finance relevance is detected and CFO is offered
- Given the agent description budget, when counted after adding Finance, then total is under 2,500 words

## References

- Brainstorm: `knowledge-base/brainstorms/2026-02-22-finance-domain-brainstorm.md`
- Template: `plugins/soleur/agents/sales/` (4 agents)
- Checklist: `knowledge-base/learnings/integration-issues/adding-new-agent-domain-checklist.md`

## Version Bump

MINOR bump (new domain with 4 agents). Base version: 2.33.2.
