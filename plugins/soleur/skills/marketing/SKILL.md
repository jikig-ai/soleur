---
name: marketing
description: "This skill should be used when performing cross-domain marketing assessment, unified marketing strategy creation, or marketing launch planning. It delegates to the CMO agent for orchestration of brand, SEO, content, community, and CRO specialists."
---

# Marketing

Run cross-domain marketing workflows by delegating to the CMO agent, which orchestrates specialist agents for brand, SEO, content, community, CRO, paid media, pricing, and retention.

## Sub-commands

| Command | Description |
|---------|-------------|
| `marketing audit` | Assess marketing posture across all domains (brand, SEO, content, community) |
| `marketing strategy` | Create unified marketing strategy with prioritized initiatives |
| `marketing launch <feature>` | Plan marketing activities for a feature launch |

If no sub-command is provided, display the table above and ask which sub-command to run.

---

## Sub-command: audit

Assess current marketing state across all domains and produce a unified report with gaps and priorities.

### Steps

1. Check for brand guide:

   ```bash
   if [[ -f "knowledge-base/overview/brand-guide.md" ]]; then
     echo "Brand guide found."
   else
     echo "Warning: No brand-guide.md found. Brand assessment will be limited."
   fi
   ```

2. Launch the CMO agent via the Task tool:

   ```text
   Task cmo: "Run a marketing audit. Assess the current marketing posture by
   delegating to specialists in parallel:

   - Task brand-architect: Review the brand guide (if it exists) for completeness
     and consistency. If no brand guide exists, report this as a critical gap.
   - Task growth-strategist: Audit existing content for keyword alignment and
     search intent coverage. Use Read/Glob to scan knowledge-base/ and docs/.
   - Task seo-aeo-analyst: Check technical SEO health -- structured data, meta tags,
     llms.txt, sitemap. Use the site URL if available.
   - Task community-manager: Assess community health -- Discord activity, GitHub
     engagement, member growth trends.

   After all specialists report back, synthesize a unified marketing posture report:
   - Per-domain status table (domain, health rating, top issue, recommended action)
   - Cross-domain gaps (e.g., brand guide missing affects content voice)
   - Prioritized action list (P1/P2/P3)"
   ```

3. Present the CMO's synthesized report to the user.

---

## Sub-command: strategy

Create a unified marketing strategy with prioritized initiatives across all marketing domains.

### Steps

1. Check for brand guide (same as audit step 1).

2. Launch the CMO agent via the Task tool:

   ```text
   Task cmo: "Create a unified marketing strategy.

   1. Assess: Check for brand-guide.md, inventory existing marketing artifacts
      (content, landing pages, SEO state, community presence).

   2. Recommend: Based on assessment, produce a prioritized marketing strategy with:
      - Positioning audit (customer, alternatives, unique value prop)
      - Top 3-5 strategic initiatives ranked by impact and effort
      - For each initiative: which specialist agent would execute it, expected outcome,
        dependencies on other initiatives
      - Timeline: what to do first, second, third (sequencing matters)

   Output as structured tables with columns: initiative, owner (agent), impact,
   effort, dependencies, recommended order."
   ```

3. Present the CMO's strategy to the user.

---

## Sub-command: launch

Plan marketing activities for a specific feature launch. Produces a three-phase launch plan (pre-launch, launch, post-launch).

### Steps

1. Parse the argument as the feature name or description.

2. Check for brand guide (same as audit step 1).

3. Launch the CMO agent via the Task tool:

   ```text
   Task cmo: "Create a marketing launch plan for: <feature>.

   1. Assess: What marketing assets exist? What is the current brand positioning?
      What channels are active?

   2. Recommend: Produce a three-phase launch plan:

      Pre-launch:
      - Channels, activities, owners, timeline, success metrics

      Launch:
      - Channels, activities, owners, timeline, success metrics

      Post-launch:
      - Channels, activities, owners, timeline, success metrics

   3. Delegate: For each phase, identify which specialist agents should execute:
      - copywriter for landing page and email copy
      - seo-aeo-analyst for launch page SEO
      - community-manager for community announcements
      - paid-media-strategist for paid campaigns (if applicable)
      - conversion-optimizer for signup/upgrade flow changes

   Output as structured tables per phase."
   ```

4. Present the CMO's launch plan to the user.

---

## Important Guidelines

- Each sub-command is independent. No sub-command requires a prior run of another.
- The `audit` sub-command runs specialist agents in parallel for faster results.
- All sub-commands produce inline output only -- no files are written.
- For focused work on a single marketing domain, use the domain-specific skill instead (`/soleur:growth`, `/soleur:seo-aeo`, `/soleur:community`).
- For brand identity workshops, use the brainstorm command which routes to brand-architect.
