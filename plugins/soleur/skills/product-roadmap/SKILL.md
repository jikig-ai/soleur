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

Do not proceed until there is input.

## Phase 0: Setup & Discover

**Headless detection:** If the context contains `--headless`, set headless mode. Strip the flag before processing remaining content. In headless mode, skip all AskUserQuestion prompts and use KB-derived defaults.

**Branch safety check:** Run `git branch --show-current`. If the result is `main` or `master`, abort: "Error: product-roadmap cannot run on main/master. Checkout a feature branch first."

**Load project conventions:** Read `CLAUDE.md` if it exists.

**Read knowledge-base artifacts.** For each artifact below, check if the file exists and read it. Record status (found/missing) and key findings:

1. `knowledge-base/marketing/brand-guide.md` -- Identity, Positioning, Target Audience sections
2. `knowledge-base/product/business-validation.md` -- Verdict, customer definition, problem statement
3. `knowledge-base/product/competitive-intelligence.md` -- Executive summary, tier 0 threats
4. `knowledge-base/product/pricing-strategy.md` -- Pricing hypothesis, validation gates
5. `knowledge-base/product/roadmap.md` -- Existing roadmap (triggers update mode)
6. Scan `knowledge-base/project/specs/` for spec directories -- list open feature specs

**Read GitHub state:**

```bash
gh issue list --state open --limit 100 --json number,title,labels,milestone
```

```bash
gh api repos/{owner}/{repo}/milestones --jq '.[] | {title, open_issues, closed_issues, due_on}'
```

**Present Context Summary** using the **AskUserQuestion tool**:

Display a table of what was found and what is missing. If an existing `roadmap.md` was found, ask:

"An existing roadmap was found (last updated: DATE). Would you like to **update** it or **start fresh**?"

Options:

1. **Update existing roadmap** -- Preserve structure, merge new decisions
2. **Start fresh** -- Create a new roadmap from scratch

In headless mode: default to "Update existing" if found, "Start fresh" if not.

## Phase 1: Fill Gaps

For each missing artifact, ask a targeted question using **AskUserQuestion**. Ask one at a time.

**If brand guide is missing:**
"I have no brand context. Tell me about your product: What does it do? Who is it for? What is your positioning vs competitors?"

**If business validation is missing:**
"No business validation found. What problem does your product solve? What stage are you at? Do you have paying users?"

**If competitive intel is missing:**
"No competitive landscape found. Who are your 2-3 main competitors? What differentiates your product?"

**If pricing strategy is missing:**
"No pricing information found. What is your pricing model? What do you charge or plan to charge?"

**Exit condition:** All critical gaps filled, or user says "proceed" or "skip".

In headless mode: skip all gap-filling questions. Proceed with whatever context is available.

## Phase 2: Research (Optional)

Assess whether additional research would improve the roadmap.

**If competitive intelligence is missing or stale (last_updated > 30 days ago):**
Ask via **AskUserQuestion**: "Competitive intelligence is missing/stale. Run a competitive scan before roadmapping?"

Options:

1. **Yes, run competitive scan** -- Spawn competitive-intelligence agent (adds ~2 minutes)
2. **No, proceed without** -- Use available context

If yes: `Task competitive-intelligence: "Run a competitive intelligence scan for tiers 0,3. Read brand-guide.md and business-validation.md for positioning context, and write the report to knowledge-base/product/competitive-intelligence.md."`

**If business validation is missing and user indicated they have no users:**
Ask: "Run a quick business validation to stress-test the idea before roadmapping?"

If yes: `Task business-validator: "Run a quick business validation for: {product_description}. Write to knowledge-base/product/business-validation.md."`

In headless mode: skip all research. Proceed with available context.

## Phase 3: Workshop

Multi-turn dialogue covering four topics. Present a synthesis from KB artifacts, then ask the user to confirm, modify, or reject. Use **AskUserQuestion** for each topic.

### 3.1 Strategic Themes

Based on the knowledge-base synthesis, present 2-4 candidate strategic themes. Each theme should have a name and rationale grounded in the artifacts read.

Example themes:

- "Fix blockers" (from open P1 issues or broken validation gates)
- "Validate with users" (from business validation verdict)
- "Build visibility" (from competitive positioning gaps)
- "Harden for scale" (from security/compliance gaps)

Ask: "Here are the strategic themes I derived from your knowledge base. Which resonate? What would you change?"

Present as multiple-choice with an "Other" option.

### 3.2 Phase Definitions

Based on the confirmed themes, propose 3-5 phases. For each phase, provide:

- **Name**: "Phase N: Title"
- **Objective**: 1-2 sentences
- **Scope**: What is in and out
- **Estimated duration**: If the user has provided timeline context

If updating an existing roadmap, present the current phases and suggest modifications based on progress data from GitHub issues/milestones.

Ask: "Here is the proposed phase structure. Adjust names, scope, ordering, or add/remove phases."

### 3.3 Feature Prioritization

For each phase, list candidate features drawn from:

- Open GitHub issues (matched to phases by labels, title keywords, or milestone)
- Feature specs in `knowledge-base/project/specs/`
- Items discussed during the workshop

Apply a simple priority framework:

- **P1**: Must-have for phase exit
- **P2**: Important but not blocking
- **Deferred**: Move to a later phase

Present as a table per phase. Ask: "Review the feature assignments per phase. Move items between phases or change priorities."

### 3.4 Success Criteria

For each phase, propose measurable exit criteria. Criteria should be concrete and verifiable.

Examples:

- "5 beta users complete the core loop without assistance"
- "All P1 issues in this phase are closed"
- "Security audit passes with no critical findings"

Ask: "These are the proposed exit criteria for each phase. Adjust or add criteria."

In headless mode for all workshop topics: use KB-derived defaults (themes from validation verdict, 3 phases based on issue priorities, issues assigned by label proximity, generic exit criteria based on phase objectives).

## Phase 4: Generate

Ensure the output directory exists:

```bash
mkdir -p knowledge-base/product
```

Write `knowledge-base/product/roadmap.md` with the following structure:

```markdown
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

# Product Roadmap: <Product Name>

## Current State

| Dimension | Status |
|-----------|--------|
| <Key dimension> | <Status> |

**Product maturity stage:** <stage>

---

## Strategic Themes

1. **<Theme 1>** -- <rationale>
2. **<Theme 2>** -- <rationale>

---

## Phases

### Phase N: <Title> (<status>)

<Objective>

| # | Item | Issue | Priority | Status |
|---|------|-------|----------|--------|
| 1 | <Feature> | #N | P1 | Open |

**Exit criteria:**

| Gate | Criteria |
|------|----------|
| <Gate 1> | <measurable criteria> |

(Repeat for each phase)

---

## Dependencies

| Depends on | Path | Why |
|------------|------|-----|
| <Artifact> | <path> | <reason> |

---

## Review Cadence

Monthly CPO review. Next review: YYYY-MM-DD.

---

_Generated: YYYY-MM-DD. Sources: <list of KB artifacts read>._
```

If updating an existing roadmap, merge the workshop decisions into the existing structure. Preserve any content the user did not explicitly change.

## Phase 5: Operationalize

### 5.1 Create Milestones (idempotent)

List existing milestones:

```bash
gh api repos/{owner}/{repo}/milestones --jq '.[].title'
```

For each phase defined in the roadmap, check if a milestone with that title already exists. If not, create it:

```bash
gh api repos/{owner}/{repo}/milestones --method POST \
  -f title="Phase N: <Title>" \
  -f description="<Phase objective>" \
  -f state="open"
```

Only include `-f due_on="YYYY-MM-DDT00:00:00Z"` if the user provided timeline estimates during the workshop.

Log each action: "Created milestone: Phase N: Title" or "Milestone already exists: Phase N: Title".

### 5.2 Assign Issues to Milestones

For each issue assigned to a phase during the workshop:

First, get the milestone number:

```bash
gh api repos/{owner}/{repo}/milestones --jq '.[] | select(.title == "Phase N: <Title>") | .number'
```

Then assign the issue (use `-F` for numeric values):

```bash
gh api repos/{owner}/{repo}/issues/<issue_number> --method PATCH -F milestone=<milestone_number>
```

### 5.3 Error Handling

If any `gh api` call fails (no auth, no network, rate limit):

- Warn the user about the specific failure
- Continue with remaining operations
- The roadmap document is the primary output; milestones are secondary

## Phase 6: Handoff

Present the output summary:

```text
Product roadmap defined.

Document: knowledge-base/product/roadmap.md
Milestones created: N (list names)
Issues assigned: N

Strategic themes:
- <Theme 1>
- <Theme 2>

Phases:
- Phase 1: <Title> (N items)
- Phase 2: <Title> (N items)

The roadmap is ready for implementation. Use `/soleur:plan` for individual features,
or `/soleur:triage` to route new issues to milestones.
```

Proceed to the next step in the orchestrator's sequence.
