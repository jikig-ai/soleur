---
name: product-roadmap
description: "This skill should be used when roadmapping."
---

# Product Roadmap Workshop

A CPO-grade interactive workshop for defining and operationalizing product roadmaps. Synthesizes knowledge-base context, guides the founder through strategic decisions, and creates GitHub milestones.

**Note: The current year is 2026.**

## Roadmap Context

<roadmap_context> #$ARGUMENTS </roadmap_context>

**If the context above is empty**, ask: "What product would you like to create a roadmap for? Describe the product, or say 'current' to use the existing knowledge-base context."

## Headless Mode

If `$ARGUMENTS` contains `--headless`, set `HEADLESS_MODE=true`. Strip `--headless` from `$ARGUMENTS` before processing remaining content. When `HEADLESS_MODE=true`, skip all AskUserQuestion prompts and use KB-derived defaults. If insufficient KB context exists to derive defaults, generate a minimal single-phase roadmap with all open issues and flag that manual review is needed.

## Phase 0: Setup

**Branch safety check:** Run `git branch --show-current`. If the result is `main` or `master`, abort: "Error: product-roadmap cannot run on main/master. Checkout a feature branch first."

**Load project conventions:** Read `CLAUDE.md` if it exists.

**Read knowledge-base artifacts.** For each artifact below, check if the file exists and read it. Record status (found/missing) and key findings:

1. `knowledge-base/marketing/brand-guide.md` -- Identity, Positioning, Target Audience
2. `knowledge-base/product/business-validation.md` -- Verdict, customer definition, problem statement
3. `knowledge-base/product/competitive-intelligence.md` -- Executive summary, tier 0 threats
4. `knowledge-base/product/pricing-strategy.md` -- Pricing hypothesis, validation gates
5. `knowledge-base/product/roadmap.md` -- Existing roadmap (triggers update mode)
6. Scan `knowledge-base/project/specs/` for spec directories

**Read GitHub state:**

```bash
gh issue list --state open --limit 100 --json number,title,labels,milestone
```

```bash
gh api repos/{owner}/{repo}/milestones --jq '.[] | {title, open_issues, closed_issues, due_on}'
```

**Present Context Summary.** Display a table of what was found and what is missing. If an existing `roadmap.md` was found, ask whether to update it or start fresh. In headless mode: default to "Update existing" if found, "Start fresh" if not.

**Fill gaps.** For each missing critical artifact, ask a brief targeted question or suggest running the relevant specialist agent (competitive-intelligence for competitive gaps, business-validator for validation gaps). In headless mode: skip gap-filling, proceed with available context.

## Phase 0.5: CPO Pre-Analysis

Spawn the CPO agent as a background task with all context gathered in Phase 0 (KB artifacts, GitHub state, existing roadmap if any). The CPO produces a **draft roadmap proposal** before the interactive workshop begins.

**CPO task prompt:** "You are the CPO. Analyze the following knowledge-base artifacts and GitHub state to produce a draft product roadmap proposal. Include: (1) 2-4 strategic themes with rationale grounded in business validation, competitive intelligence, and current product state, (2) 3-5 proposed phases with objectives, scope, and feature lists drawn from open GitHub issues, (3) gaps and risks you identified — things the founder may not have considered (onboarding flows, infrastructure requirements, missing integrations, legal prerequisites), (4) prioritization rationale explaining why you ordered the phases this way, (5) open questions for the founder. Challenge assumptions. Be opinionated — propose a direction, don't just list options. Context: {all Phase 0 findings}"

Wait for the CPO analysis to complete, then present it to the founder.

**In headless mode:** Use the CPO proposal as the final roadmap without interactive refinement (skip Phase 1 workshop).

## Phase 1: Workshop (CPO-Facilitated)

The CPO's draft proposal is the starting point. The workshop refines it through multi-turn dialogue. The CPO role is to **facilitate and challenge** — not just present options, but push back on choices, identify gaps the founder may have missed, and advocate for the user's perspective.

### 1.1 Strategic Themes

Present the CPO's proposed themes. For each, show the rationale grounded in KB artifacts. Ask the founder which resonate and what to change. If the founder proposes a theme the CPO didn't include, the CPO should either support it with evidence or challenge it with a counter-argument.

### 1.2 Phase Definitions

Present the CPO's proposed phases. For each phase, show the objective, scope, and estimated duration if timeline context exists. If updating an existing roadmap, present current phases and suggest modifications based on progress data. The CPO should flag any phase that seems overloaded, underspecified, or missing prerequisites. Ask to adjust.

### 1.3 Feature Prioritization

For each phase, present the CPO's feature list drawn from open GitHub issues, specs, and the analysis. Apply P1 (must-have for phase exit) / P2 (important but not blocking) / Deferred. Present as a table per phase. The CPO should challenge any feature that seems premature or missing. Ask to reorder.

### 1.4 Success Criteria

For each phase, present the CPO's proposed measurable exit criteria. Ask to adjust.

### 1.5 Gap Check

Before moving to Domain Review, the CPO presents any gaps identified during pre-analysis that were not addressed in the workshop: missing onboarding flows, infrastructure requirements, integration dependencies, legal prerequisites, UX considerations. The founder decides which gaps to address now and which to defer.

In headless mode for all workshop topics: use CPO-derived defaults from the pre-analysis.

## Phase 1.5: Domain Review Gate

Before generating the roadmap, assess which domain leaders should review the proposed phases. Read [brainstorm-domain-config.md](../../skills/brainstorm/references/brainstorm-domain-config.md) for the domain assessment table.

### Auto-Detection

For each proposed phase, evaluate against the assessment questions in the domain config table:

| Phase Content Signal | Domain | Leader |
|---------------------|--------|--------|
| Infrastructure, architecture, tech stack, performance, scaling | Engineering | CTO |
| PII, GDPR, payments, vendor agreements, compliance, terms of service | Legal | CLO |
| Vendor costs, pricing decisions, budget, burn rate, revenue model | Finance | CFO |
| Positioning changes, launch content, recruitment channels, brand | Marketing | CMO |
| Vendor selection, tool provisioning, hosting, procurement | Operations | COO |
| Sales pipeline, outbound, pricing communication, deal structure | Sales | CRO |
| User support, documentation, community, onboarding | Support | CCO |

A domain is relevant if **any** proposed phase matches its content signals.

### Spawn Domain Leaders

For each relevant domain, spawn the domain leader as a parallel background Agent using the Task Prompt from the domain config table. Pass the full workshop output (themes, phases, features, exit criteria) as context via `{desc}`.

Example prompt format: "Assess the [domain] implications of this product roadmap: {full workshop summary}. Identify risks, blockers, complexity concerns, and questions the founder should consider. Output a brief structured assessment with risk levels (low/medium/high) per phase."

Spawn all relevant leaders in parallel (`run_in_background: true`). Present each assessment as it completes.

### In headless mode

Skip the domain review gate. Generate the roadmap with a footer note: "Domain review was skipped (headless mode). Run interactively to include domain leader assessments."

### Present and Adjust

After all assessments complete, present a consolidated summary table:

| Domain | Key Finding | Risk | Recommended Change |
|--------|------------|------|--------------------|

Use AskUserQuestion to ask: "Domain leaders have reviewed the roadmap. Adjust any phases before generating?"

Incorporate accepted changes into the phase definitions before proceeding to Generate.

## Phase 2: Generate

Write `knowledge-base/product/roadmap.md` with the following structure:

**Required frontmatter:**

```yaml
---
last_updated: YYYY-MM-DD
last_reviewed: YYYY-MM-DD
review_cadence: monthly
owner: CPO
depends_on:
  - knowledge-base/product/business-validation.md
  - knowledge-base/product/competitive-intelligence.md
  - knowledge-base/product/pricing-strategy.md
---
```

**Required sections:** Strategic Themes, Phases (each with a feature table linking issues via `#N` and exit criteria gates). Include a `Generated: YYYY-MM-DD` footer listing source artifacts.

If updating an existing roadmap, merge workshop decisions into the existing structure. Preserve content the user did not explicitly change.

**Commit the artifact:**

```bash
git add knowledge-base/product/roadmap.md
git commit -m "docs(product): generate product roadmap"
```

## Phase 3: Operationalize

### 3.1 Create Milestones (idempotent)

List existing milestones, then create any that are missing:

```bash
gh api repos/{owner}/{repo}/milestones --jq '.[].title'
```

For each phase not already present:

```bash
gh api repos/{owner}/{repo}/milestones --method POST \
  -f title="Phase N: <Title>" \
  -f description="<Phase objective>" \
  -f state="open"
```

Only include `-f due_on="YYYY-MM-DDT00:00:00Z"` if the user provided timeline estimates.

### 3.2 Assign Issues to Milestones

Assign issues to their phase milestones. Use `-F` (not `-f`) for numeric milestone values in `gh api`.

## Phase 4: Handoff

Present an output summary listing the document path, milestones created, issues assigned, and strategic themes. Suggest `/soleur:plan` for individual features.

Proceed to the next step in the orchestrator's sequence.
