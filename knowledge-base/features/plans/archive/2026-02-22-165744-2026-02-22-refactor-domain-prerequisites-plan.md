---
title: Refactor Domain Prerequisites
type: refactor
date: 2026-02-22
---

# Refactor Domain Prerequisites

## Overview

Three prerequisite fixes that unblock future domain additions by addressing the token budget ceiling, brainstorm routing scalability, and stale domain enumeration copy.

## Problem Statement

1. Agent description token budget is at 2,496/2,500 words -- no room for new agents or domains.
2. Brainstorm Phase 0.5 requires ~25 lines of edits per new domain across 3 separate sections (~258 lines for 7 domains). The code itself flags this: "Consider table-driven refactor at 5+ domains."
3. Multiple files enumerate domains as "engineering, marketing, legal, operations, and product" -- missing Sales (added in v2.28.0).

## Proposed Solution

### Phase 1: Trim Agent Descriptions

Audit all 54 agent descriptions and trim to recover 200+ words. Current top candidates:

| Agent | Current Words | File |
|-------|--------------|------|
| git-history-analyzer | 68 | `agents/engineering/research/git-history-analyzer.md` |
| repo-research-analyst | 67 | `agents/engineering/research/repo-research-analyst.md` |
| agent-finder | 66 | `agents/engineering/discovery/agent-finder.md` |
| kieran-rails-reviewer | 65 | `agents/engineering/review/kieran-rails-reviewer.md` |
| functional-discovery | 64 | `agents/engineering/discovery/functional-discovery.md` |
| deployment-verification-agent | 61 | `agents/engineering/review/deployment-verification-agent.md` |
| seo-aeo-analyst | 60 | `agents/marketing/seo-aeo-analyst.md` |
| growth-strategist | 58 | `agents/marketing/growth-strategist.md` |
| business-validator | 56 | `agents/product/business-validator.md` |
| terraform-architect | 56 | `agents/engineering/infra/terraform-architect.md` |

**Rules:**
- Keep disambiguation sentences ("Use X for Y; use this agent for Z")
- Keep imperative voice ("Use this agent when...")
- Strip filler phrases, redundant scope lists, and wordy explanations
- Implementation guidance: target 35-45 words per specialist, 25-35 per leader
- Gate: `shopt -s globstar && grep -h 'description:' agents/**/*.md | wc -w` <= 2,300

### Phase 2: Refactor Brainstorm Phase 0.5 to Table-Driven

Replace the three inline sections (Assessment lines 63-81, Routing lines 83-152, Participation lines 250-314) with one config table and generic processing instructions.

Brand-specific routing is merged into marketing (one row with 3 options instead of two separate rows). This mirrors how product already works (3 options: workshop / include / skip).

**Domain Config Table**

| Domain Key | Assessment Question | Leader | Routing Prompt | Options | Task Prompt |
|------------|-------------------|--------|----------------|---------|-------------|
| marketing | Does this feature involve content changes, audience targeting, brand impact, brand identity definition, brand guide creation, voice and tone development, go-to-market activities, SEO/AEO concerns, pricing communication, or public-facing messaging? | cmo | "This feature has marketing or brand relevance. How would you like to proceed?" | **Start brand workshop** - Run the brand-architect agent to create or update a brand guide / **Include marketing perspective** - CMO joins the brainstorm to add marketing context / **Brainstorm normally** - Continue with the standard brainstorm flow | "Assess the marketing implications of this feature: {desc}. Identify marketing concerns, opportunities, and questions the user should consider during brainstorming. When the assessment involves visual layout or page structure, explicitly recommend delegating to conversion-optimizer or ux-design-lead for layout review. Output a brief structured assessment (not a full strategy)." |
| engineering | Does this feature require significant architectural decisions, infrastructure changes, system design, or technical debt resolution beyond normal implementation? | cto | "This feature has architectural implications. Include technical assessment?" | **Include technical assessment** - CTO joins the brainstorm to assess technical implications / **Brainstorm normally** - Continue without CTO input | "Assess the technical implications of this feature: {desc}. Identify architecture risks, complexity concerns, and technical questions the user should consider during brainstorming. Output a brief structured assessment." |
| operations | Does this feature involve operational decisions such as vendor selection, tool provisioning, expense tracking, process changes, or infrastructure procurement? | coo | "This feature has operational implications. Include operations assessment?" | **Include operations assessment** - COO joins the brainstorm to assess operational implications / **Brainstorm normally** - Continue without operations input | "Assess the operational implications of this feature: {desc}. Identify cost concerns, vendor decisions, process changes, and operational questions the user should consider during brainstorming. Output a brief structured assessment." |
| product | Does this feature involve validating a new business idea, assessing product-market fit, evaluating customer demand, competitive positioning, or determining whether to build something? | cpo | "This looks like it involves product validation. How would you like to proceed?" | **Start validation workshop** - Run the business-validator agent to validate the business idea / **Include product perspective** - CPO joins the brainstorm to add product context / **Brainstorm normally** - Continue with the standard brainstorm flow | "Assess the product implications of this feature: {desc}. Identify product strategy concerns, validation gaps, and questions the user should consider during brainstorming. Output a brief structured assessment (not a full strategy)." |
| legal | Does this feature involve creating, updating, or auditing legal documents such as terms of service, privacy policies, data processing agreements, or compliance documentation? | clo | "This feature has legal implications. Include legal assessment?" | **Include legal assessment** - CLO joins the brainstorm to assess legal implications / **Brainstorm normally** - Continue without legal input | "Assess the legal implications of this feature: {desc}. Identify compliance requirements, legal document needs, regulatory concerns, and legal questions the user should consider during brainstorming. Output a brief structured assessment." |
| sales | Does this feature involve sales pipeline management, outbound prospecting, deal negotiation, proposal generation, revenue forecasting, or converting leads into customers through human-assisted sales motions? | cro | "This feature has sales implications. Include sales assessment?" | **Include sales assessment** - CRO joins the brainstorm to assess sales implications / **Brainstorm normally** - Continue without sales input | "Assess the sales implications of this feature: {desc}. Identify pipeline concerns, revenue conversion opportunities, and sales questions the user should consider during brainstorming. Output a brief structured assessment." |

**Generic processing instructions** replace per-domain blocks:

1. Read the feature description and assess relevance against each domain in the table above.
2. For each relevant domain, use AskUserQuestion with the routing prompt and options from the table.
3. Workshop options (marketing "Start brand workshop", product "Start validation workshop"): follow the named workshop section below (Brand Workshop, Validation Workshop).
4. Standard participation: for each accepted leader, spawn a Task using the Task Prompt from the table, substituting `{desc}` with the feature description. Weave each leader's assessment into the brainstorm dialogue alongside repo research findings.
5. If multiple domains are relevant, ask about each separately.
6. If no domains are relevant, continue to Phase 1.

**What stays as-is:** Brand Workshop and Validation Workshop procedural sections remain unchanged. These are structural workshop flows referenced by the table's workshop options.

### Phase 3: Fix Domain Enumeration

Update all files that list domains without "sales":

| File | Issue |
|------|-------|
| `plugins/soleur/.claude-plugin/plugin.json` | Missing "sales" in description |
| `plugins/soleur/README.md` | Missing "sales" |
| `README.md` | Missing "sales" |
| `AGENTS.md` | Missing "sales" |
| `plugins/soleur/docs/pages/getting-started.md` (lines 21, 114) | Missing "sales" |
| `plugins/soleur/docs/llms.txt.njk` | Missing "sales" |
| `plugins/soleur/docs/pages/legal/terms-and-conditions.md` | Says "five domains" with title-case list, missing Sales |

Verification grep (catches both cases and title-case):

```bash
grep -ri "five domains\|engineering, marketing, legal, operations, and product" \
  --include="*.md" --include="*.json" --include="*.njk"
```

## Acceptance Criteria

- [ ] `shopt -s globstar && grep -h 'description:' plugins/soleur/agents/**/*.md | wc -w` reports <= 2,300
- [ ] Brainstorm Phase 0.5 uses a single config table, not per-domain inline blocks
- [ ] All 8 active files list all 6 domains including "sales"
- [ ] Workshop sections (Brand, Validation) preserved and functional
- [ ] Version bump (PATCH -- no new components)

## Test Scenarios

- Given a brainstorm run with a brand-specific feature, when Phase 0.5 executes, then marketing routing shows 3 options (workshop / include-CMO / skip)
- Given a brainstorm run with a general marketing feature (not brand), when Phase 0.5 executes, then marketing routing shows the same 3 options
- Given a brainstorm run with a product validation feature, when Phase 0.5 executes, then product routing shows 3 options (workshop / include-CPO / skip)

## Non-Goals

- Adding the Support domain or any new agents
- Token budget CI enforcement (follow-up issue)
- Clarifying the `community/` directory purpose (follow-up)
- Changing agent behavior (only descriptions change)

## Dependencies and Risks

- **Risk: Trimmed descriptions lose routing accuracy.** Mitigation: preserve disambiguation sentences, test by reading each trimmed description and verifying it still clearly indicates when to use the agent.
- **Risk: Table-driven brainstorm routing changes LLM behavior.** Mitigation: preserve exact question text, full option labels with descriptions, and task prompt text from current inline blocks.

## References

- Brainstorm: `knowledge-base/brainstorms/2026-02-22-domain-prerequisites-brainstorm.md`
- Brainstorm source: `plugins/soleur/commands/soleur/brainstorm.md` lines 57-314
- Issue: #251
