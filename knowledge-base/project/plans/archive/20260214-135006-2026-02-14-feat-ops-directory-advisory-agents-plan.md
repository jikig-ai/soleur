---
title: "feat: Add Operations Directory with Ops Advisor Agent"
type: feat
date: 2026-02-14
issue: "#81"
version_bump: MINOR
revised: 2026-02-14
---

# feat: Add Operations Directory with Ops Advisor Agent

## Overview

Establish the operations domain in the Soleur plugin with one advisory agent and two structured markdown data files. This is Phase 1 of the ops roadmap -- structure and conventions only, no automation.

[Updated 2026-02-14] Simplified from 3 agents + 3 files to 1 agent + 2 files after plan review. Hosting merged into expenses as a category. Single agent handles all ops data files.

## Problem Statement / Motivation

The Soleur plugin has zero operational components despite "operations" being planned as one of five startup domains. There is no way to track costs, manage domains, or inventory hosting -- even manually. As the project grows (website deployments, API subscriptions, domain purchases), this gap compounds.

## Proposed Solution

1. **One advisory agent** under `plugins/soleur/agents/operations/ops-advisor.md` -- auto-discovered as `soleur:operations:ops-advisor`
2. **Two data files** under `knowledge-base/ops/` -- expenses.md and domains.md
3. **Version bump** from 2.7.0 to 2.8.0 (MINOR -- new agent)

### Non-Goals

- Browser-automated purchasing (Phase 2)
- Semi-autonomous execution with budget controls (Phase 3)
- External API integration (WHOIS, pricing APIs)
- Multi-currency conversion
- Permission models or access control
- Schema migration tooling
- Separate hosting data file (hosting is a category in expenses)

## Technical Approach

### Data File Schemas

All files use ISO 8601 dates (`YYYY-MM-DD`), USD amounts as plain numbers (`49.99`), and pipe-delimited markdown tables.

#### `knowledge-base/ops/expenses.md`

```markdown
---
last_updated: 2026-02-14
---

# Expenses

## Recurring

| Service | Provider | Category | Amount | Renewal Date | Notes |
|---------|----------|----------|--------|--------------|-------|
| GitHub Copilot | GitHub | dev-tools | 10.00 | 2026-03-14 | Business plan |
| Hetzner CX22 | Hetzner | hosting | 5.83 | 2026-03-01 | 2 vCPU, 4 GB RAM, 40 GB SSD, eu-central |
| soleur.dev | Cloudflare | domain | 12.99 | 2027-02-01 | Annual renewal |

## One-Time

| Service | Provider | Category | Amount | Date | Notes |
|---------|----------|----------|--------|------|-------|
```

**Column definitions:**
- **Service**: Product name (e.g., "GitHub Copilot", "Hetzner CX22")
- **Provider**: Company (e.g., "GitHub", "Hetzner")
- **Category**: Free-form tag -- common values: `hosting`, `domain`, `dev-tools`, `saas`, `api`
- **Amount**: Cost in USD, plain number, no currency symbol (e.g., `5.83`). Monthly for recurring, total for one-time.
- **Renewal Date**: Next renewal in `YYYY-MM-DD`
- **Notes**: Free text for specs, billing frequency, region, or other context. Use for exceptions -- if a pattern repeats, consider a column.

Hosting entries use Notes for specs and region (e.g., `2 vCPU, 4 GB RAM, eu-central`). Domain entries use Notes for billing cycle (e.g., `Annual renewal`).

#### `knowledge-base/ops/domains.md`

```markdown
---
last_updated: 2026-02-14
---

# Domains

| Domain | Registrar | Renewal Date | Nameservers | Notes |
|--------|-----------|--------------|-------------|-------|
| soleur.dev | Cloudflare | 2027-02-01 | ns1.cloudflare.com, ns2.cloudflare.com | Primary project domain |
```

**Column definitions:**
- **Domain**: FQDN (e.g., `soleur.dev`)
- **Registrar**: Provider name (e.g., "Cloudflare", "Namecheap")
- **Renewal Date**: Next renewal in `YYYY-MM-DD`
- **Nameservers**: Comma-separated (e.g., `ns1.cloudflare.com, ns2.cloudflare.com`)
- **Notes**: Free text

### Agent Architecture

Single agent handles all operational queries by reading the appropriate data file based on context.

- **Location**: `plugins/soleur/agents/operations/ops-advisor.md`
- **Discovery name**: `soleur:operations:ops-advisor`
- **Model**: `inherit`
- **Prompt style**: Sharp edges only

#### `ops-advisor.md`

Reads and updates `knowledge-base/ops/expenses.md` and `knowledge-base/ops/domains.md`. Capabilities:
- Summarize total monthly/annual spend by category
- Add, update, or remove expense/domain entries
- Flag upcoming renewals (within 30 days)
- Compare hosting options (advisory, using training data)
- Advise on domain strategy (no live WHOIS)

**Sharp edges to embed:**
- File paths: `knowledge-base/ops/expenses.md` and `knowledge-base/ops/domains.md`
- expenses.md has two sections: `## Recurring` and `## One-Time`
- Amounts are plain numbers in USD (no `$` prefix in table cells)
- Hosting entries go in expenses.md with `Category: hosting` -- specs in Notes column
- Domain entries go in domains.md for DNS details, AND in expenses.md for cost tracking
- When summarizing annual spend: multiply monthly amounts by 12, add annual amounts as-is (check Notes for "annual")
- Cannot check live domain availability or live pricing -- advise user to verify, then record result
- Nameservers use comma separation (no pipes -- would break table)
- Update `last_updated` frontmatter when modifying any data file
- When file is empty/missing, create with YAML frontmatter and table headers (use exact templates from this plan)

**Example agent frontmatter:**

```yaml
---
name: ops-advisor
description: "Use this agent when you need to track operational expenses, manage domain registrations, or get hosting recommendations. This agent reads and updates structured markdown files in knowledge-base/ops/ to maintain an operational ledger.

<example>
Context: The user wants to know their current monthly spend.
user: \"How much are we spending per month?\"
assistant: \"I'll use the ops-advisor agent to read expenses.md and summarize recurring costs.\"
<commentary>
Since the user is asking about operational costs, use the ops-advisor agent which maintains the expense ledger.
</commentary>
</example>

<example>
Context: The user just purchased a new domain and wants to track it.
user: \"I just bought example.com on Cloudflare for $12/year\"
assistant: \"I'll use the ops-advisor agent to add this domain to the registry and expense tracker.\"
<commentary>
Domain purchases need entries in both domains.md (DNS details) and expenses.md (cost tracking).
</commentary>
</example>"
model: inherit
---
```

### File Initialization

When the agent is asked to read a data file that does not exist:
1. Create the directory `knowledge-base/ops/` if missing
2. Create the file with YAML frontmatter and table headers (exact templates from schemas above, no data rows)
3. Inform the user: "Created `<file>` with empty template. You can start adding entries."

### Version Bump

- **Type**: MINOR (2.7.0 -> 2.8.0)
- **Reason**: 1 new agent = new user-facing capability
- **Files to update**:
  1. `plugins/soleur/.claude-plugin/plugin.json` -- version to `2.8.0`, description count "24 agents" -> "25 agents"
  2. `plugins/soleur/CHANGELOG.md` -- add `## [2.8.0]` entry
  3. `plugins/soleur/README.md` -- update agent count, add Operations section:
     ```markdown
     ### Operations Agents
     - `ops-advisor` - Track expenses, manage domains, advise on hosting
     ```

## Acceptance Criteria

- [x] Directory `plugins/soleur/agents/operations/` exists with `ops-advisor.md`
- [x] Agent has valid YAML frontmatter (`name`, `description` with two `<example>` blocks, `model: inherit`)
- [x] Agent description uses third-person ("Use this agent when...")
- [x] Directory `knowledge-base/ops/` exists with `expenses.md` and `domains.md`
- [x] Each data file has YAML frontmatter and properly formatted markdown table headers with example rows
- [x] Plugin version bumped from 2.7.0 to 2.8.0 in all three files (plugin.json, CHANGELOG.md, README.md)
- [x] Agent count updated in plugin.json description ("25 agents")
- [x] README.md agent table includes Operations section
- [x] All markdown files pass markdownlint

## Test Scenarios

### Agent Discovery

- Given `ops-advisor.md` exists under `plugins/soleur/agents/operations/`, when the plugin loader scans for agents, then `soleur:operations:ops-advisor` is discovered

### Expense Tracking

- Given `knowledge-base/ops/expenses.md` does not exist, when user asks "how much are we spending?", then ops-advisor creates the file with headers and reports "No expenses tracked yet"
- Given expenses.md has 3 recurring entries totaling $28.82/month, when user asks "show spending summary", then ops-advisor reports ~$28.82/month, ~$345.84/year
- Given expenses.md has entries, when user asks "add Vercel Pro at $20/month", then ops-advisor appends a row to Recurring and updates `last_updated`
- Given expenses.md has a renewal on 2026-03-01, when user asks "any upcoming renewals?" on 2026-02-14, then ops-advisor flags it (within 30 days)

### Domain Management

- Given `knowledge-base/ops/domains.md` does not exist, when user asks about domains, then ops-advisor creates the file with headers
- Given domains.md has entries, when user asks "when do our domains renew?", then ops-advisor lists them sorted by renewal date
- Given user asks "is example.com available?", then ops-advisor advises checking manually (no live WHOIS in v1)
- Given user says "I bought example.com on Cloudflare for $12/year", then ops-advisor adds to BOTH domains.md and expenses.md

### Hosting Advisory

- Given user asks "compare hosting for a Rails app", then ops-advisor gives recommendations using training knowledge with disclaimer to verify current pricing
- Given user says "add Hetzner CX22 at $5.83/month", then ops-advisor adds to expenses.md with `Category: hosting` and specs in Notes

### Version Bump

- Given ops-advisor.md is created, when checking plugin.json, then version is `2.8.0` and description says "25 agents"

## Dependencies and Risks

**Dependencies:**
- None -- clean slate, no existing ops infrastructure to migrate

**Risks:**
- **Low**: Agent prompt may need iteration after testing real queries
- **Low**: Table schemas may need additional columns in Phase 2 -- markdown tables are easy to extend
- **Mitigated**: Concurrent modification handled by git (last-write-wins with conflict detection)

## Implementation Sequence

1. Create `knowledge-base/ops/` directory with 2 data template files (expenses.md, domains.md)
2. Create `plugins/soleur/agents/operations/ops-advisor.md`
3. Version bump: update plugin.json, CHANGELOG.md, README.md
4. Run markdownlint to validate all new files
5. Phase 0 loader test: verify agent discovery works
6. Review, compound, commit, push, PR

## References

### Internal

- Brainstorm: `knowledge-base/brainstorms/2026-02-13-ops-directory-brainstorm.md`
- Spec: `knowledge-base/specs/feat-ops-directory/spec.md`
- Constitution: `knowledge-base/overview/constitution.md`
- Agent example: `plugins/soleur/agents/workflow/pr-comment-resolver.md`
- Learnings: `knowledge-base/learnings/agent-prompt-sharp-edges-only.md`
- Learnings: `knowledge-base/learnings/2026-02-12-plugin-loader-agent-vs-skill-recursion.md`
- Learnings: `knowledge-base/learnings/plugin-versioning-requirements.md`

### Related Issues

- #81 -- This issue (ops directory)
- #75 -- `/soleur:bootstrap` skill (Operations lane overlap)
- #85 -- Enable GitHub Pages (website hosting)
