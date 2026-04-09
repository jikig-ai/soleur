---
name: plan
description: "Transform feature descriptions into well-structured project plans following conventions. Creates actionable implementation plans with research, domain review, and task breakdown."
triggers:
- plan
- create plan
- implementation plan
- project plan
- plan feature
---

# Create a Plan for a New Feature or Bug Fix

**Note: The current year is 2026.** Use this when dating plans and searching for recent documentation.

Transform feature descriptions, bug reports, or improvement ideas into well-structured markdown plan files that follow project conventions and best practices.

## Feature Description

If the user has not provided a feature description in the conversation, ask: "What would you like to plan? Please describe the feature, bug fix, or improvement you have in mind."

Do not proceed until you have a clear feature description from the user.

### 0. Load Knowledge Base Context (if exists)

**Load project conventions:**

```bash
if [[ -f "AGENTS.md" ]]; then
  cat AGENTS.md
fi
```

**Branch safety check (defense-in-depth):** Run `git branch --show-current`. If the result is `main` or `master`, abort immediately with: "Error: plan cannot run on main/master. Checkout a feature branch first."

**Check for knowledge-base directory and load context:**

If `knowledge-base/` exists:

1. Read `AGENTS.md` if it exists — apply project conventions during planning
2. Read `knowledge-base/project/constitution.md` if it exists — use principles to guide planning decisions
3. Detect feature from current branch (`feat-<name>` pattern)
4. Read `knowledge-base/project/specs/feat-<name>/spec.md` if it exists — use as planning input

### 0.5. Idea Refinement

**Check for brainstorm output first:**

Before asking questions, look for recent brainstorm documents in `knowledge-base/project/brainstorms/` that match this feature:

```bash
ls -la knowledge-base/project/brainstorms/*.md 2>/dev/null | head -10
```

**If a relevant brainstorm exists** (topic matches, created within last 14 days):

1. Read the brainstorm document
2. Announce: "Found brainstorm from [date]: [topic]. Using as context for planning."
3. Extract key decisions, chosen approach, and open questions
4. **Skip the idea refinement questions below** — the brainstorm already answered WHAT to build
5. Proceed to Phase 1 — all sub-phases still apply

**If no brainstorm found, run idea refinement:**

Ask questions one at a time to understand the idea fully:

- Prefer multiple choice questions when natural options exist
- Focus on: purpose, constraints, success criteria
- **Directional ambiguity gate:** If the task involves merging, moving, or restructuring, explicitly confirm the direction with the user
- Continue until the idea is clear OR user says "proceed"

## Main Tasks

### 1. Local Research (Always Runs — Parallel)

Use the `delegate` tool to run research agents in parallel:

```
spawn: ["repo-research", "learnings-research"]
delegate:
  repo-research: "Research the repository for existing patterns, AGENTS.md guidance, technology familiarity related to: {feature_description}"
  learnings-research: "Search knowledge-base/project/learnings/ for documented solutions and lessons learned related to: {feature_description}"
```

### 1.5. Community Discovery Check (Conditional)

**Read `.plugin/skills/plan/references/plan-community-discovery.md` now** for the full community discovery procedure (stack detection, coverage gap check). Skip if no uncovered stacks detected.

### 1.5b. Functional Overlap Check

**Read `.plugin/skills/plan/references/plan-functional-overlap.md` now** for the functional overlap check procedure (always runs).

### 1.6. Research Decision

Based on signals from Step 0 and findings from Step 1, decide on external research.

- **High-risk topics → always research.** Security, payments, external APIs, data privacy.
- **Strong local context → skip external research.** Good patterns, clear guidance.
- **Uncertainty or unfamiliar territory → research.**

Announce the decision and proceed.

### 1.6b. External Research (Conditional)

**Only run if Step 1.6 indicates external research is valuable.**

Use the `delegate` tool to run in parallel:

```
spawn: ["best-practices", "framework-docs"]
delegate:
  best-practices: "Research current best practices for: {feature_description}"
  framework-docs: "Research framework documentation relevant to: {feature_description}"
```

### 1.7. Consolidate Research

After all research steps complete, consolidate findings:

- Document relevant file paths from repo research
- Include relevant institutional learnings from `knowledge-base/project/learnings/`
- Note external documentation URLs and best practices (if external research was done)
- List related issues or PRs discovered

### 2. Issue Planning & Structure

**Title & Categorization:**

- Draft clear, searchable issue title using conventional format (e.g., `feat: Add user authentication`)
- Determine issue type: enhancement, bug, refactor
- Convert title to filename: date prefix, strip prefix colon, kebab-case, add `-plan` suffix

**Content Planning:**

- Choose appropriate detail level based on issue complexity
- List all necessary sections for the chosen template
- Gather supporting materials
- When planning a directory rename, enumerate ALL files in the target directory

### 2.5. Domain Review Gate

After generating the plan structure, assess which business domains this plan has implications for.

**Step 1 — Domain Sweep:**

1. **Brainstorm carry-forward check:** If the brainstorm document contains a `## Domain Assessments` section, carry forward the findings.
2. **Fresh assessment (if needed):** Read `.plugin/skills/brainstorm/references/brainstorm-domain-config.md`. Assess all 8 domains against the plan content.
3. **Spawn domain leaders:** For each relevant domain (except Product), use the `delegate` tool to spawn domain leader agents in parallel using the Task Prompt from the config.

**Step 2 — Product/UX Gate:**

If Product domain was flagged as relevant, classify:

- **BLOCKING**: Creates new user-facing pages, multi-step flows, or significant new UI components
- **ADVISORY**: Modifies existing user-facing pages or components
- **NONE**: No user-facing impact

**Writing the `## Domain Review` section:**

```markdown
## Domain Review

**Domains relevant:** [comma-separated list] | none

### [Domain Name]

**Status:** reviewed | error
**Assessment:** [leader's structured assessment summary]
```

### 3. SpecFlow Analysis

If spec-flow-analyzer was not already invoked in Phase 2.5, use the `delegate` tool to validate:

```
spawn: ["spec-flow"]
delegate:
  spec-flow: "Analyze this feature specification for gaps, edge cases, and missing requirements: {feature_description} with research findings: {research_findings}"
```

### 4. Choose Implementation Detail Level

**Read `.plugin/skills/plan/references/plan-issue-templates.md` now** to load the three issue templates (MINIMAL, MORE, A LOT). Select the appropriate detail level based on complexity.

### 5. Issue Creation & Formatting

**Content Formatting:**

- Use clear, descriptive headings with proper hierarchy
- Include code examples in triple backticks with language syntax highlighting
- Use task lists (`- [ ]`) for trackable items
- Add collapsible sections for lengthy content using `<details>` tags
- Apply appropriate emoji for visual scanning

**Cross-Referencing:**

- Link to related issues/PRs using `#number` format
- Reference specific commits with SHA hashes
- Mention relevant team members with `@username`

### 6. Final Review & Submission

**Pre-submission Checklist:**

- Title is searchable and descriptive
- All template sections are complete
- Links and references are working
- Acceptance criteria are measurable
- Browser task automation check: scan for steps labeled "manual" — rewrite as automation steps
- Deferral tracking check: create GitHub issues for deferred items

## Output Format

**Filename:**

```text
knowledge-base/project/plans/YYYY-MM-DD-<type>-<descriptive-name>-plan.md
```

## Save Tasks to Knowledge Base (if exists)

If `knowledge-base/` exists and on a feature branch:

1. **Generate tasks.md** — extract actionable tasks, organize into phases
2. **Save tasks.md** to `knowledge-base/project/specs/feat-<name>/tasks.md`
3. **Commit and push:**

   ```bash
   git add knowledge-base/project/plans/ knowledge-base/project/specs/feat-<name>/tasks.md
   git commit -m "docs: create plan and tasks for feat-<name>"
   git push
   ```

## Plan Review (Always Runs)

After writing the plan file, use the `delegate` tool to run three specialized reviewers in parallel:

```
spawn: ["dhh-reviewer", "kieran-reviewer", "simplicity-reviewer"]
delegate:
  dhh-reviewer: "Review this plan for overengineering and enforce simplicity: {plan_content}"
  kieran-reviewer: "Review this plan for correctness, completeness, and convention adherence: {plan_content}"
  simplicity-reviewer: "Review this plan for YAGNI violations and unnecessary complexity: {plan_content}"
```

Present consolidated feedback, then ask: "Apply these changes?" (Yes / Partially / Skip)

## Post-Generation Options

After plan review, ask the user:

"Plan reviewed and ready at `knowledge-base/project/plans/<filename>`. What would you like to do next?"

1. **Start work** — Begin implementing this plan (use the work skill)
2. **Create Issue** — Create issue in project tracker (GitHub)
3. **Simplify** — Reduce detail level
4. **Refine** — Make specific changes

## Issue Creation

When user selects "Create Issue":

```bash
gh issue create --title "<type>: <title>" --body-file <plan_path> --milestone "Post-MVP / Later"
```

After creation, check `knowledge-base/product/roadmap.md` and update the milestone if a more specific phase applies.

## Managing Plan Documents

**Update an existing plan:** Read the existing plan first. Update in place. Preserve prior content and mark changes with `[Updated YYYY-MM-DD]`.

**Archive completed plans:** Run `bash ./plugins/soleur/skills/archive-kb/scripts/archive-kb.sh` from the repository root.
