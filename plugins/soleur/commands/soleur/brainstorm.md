---
name: soleur:brainstorm
description: Explore requirements and approaches through collaborative dialogue before planning implementation
argument-hint: "[feature idea or problem to explore]"
---

# Brainstorm a Feature or Improvement

**Note: The current year is 2026.** Use this when dating brainstorm documents.

Brainstorming helps answer **WHAT** to build through collaborative dialogue. It precedes `/soleur:plan`, which answers **HOW** to build it.

**Process knowledge:** Load the `brainstorming` skill for detailed question techniques, approach exploration patterns, and YAGNI principles.

## Feature Description

<feature_description> #$ARGUMENTS </feature_description>

**If the feature description above is empty, ask the user:** "What would you like to explore? Please describe the feature, problem, or improvement you're thinking about."

Do not proceed until you have a feature description from the user.

## Execution Flow

### Phase 0: Setup and Assess Requirements Clarity

**Load project conventions:**

```bash
# Load project conventions
if [[ -f "CLAUDE.md" ]]; then
  cat CLAUDE.md
fi
```

Read `CLAUDE.md` if it exists - apply project conventions during brainstorming.

Evaluate whether brainstorming is needed based on the feature description.

**Clear requirements indicators:**

- Specific acceptance criteria provided
- Referenced existing patterns to follow
- Described exact expected behavior
- Constrained, well-defined scope

**If requirements are already clear:**
Use **AskUserQuestion tool** to suggest: "Your requirements seem clear enough to skip brainstorming. How would you like to proceed?"

Options:
1. **One-shot it** - Run `/soleur:one-shot` for full autonomous execution (plan, deepen, implement, review, resolve todos, browser test, feature video, PR). Best for simple, single-session tasks like bug fixes or small improvements.
2. **Plan first** - Run `/soleur:plan` to create a plan before implementing
3. **Brainstorm anyway** - Continue exploring the idea

If one-shot is selected, pass the original feature description (including any issue references) to `/soleur:one-shot` and stop brainstorm execution. Note: this skips brainstorm capture (Phase 3.5), worktree creation (Phase 3), and spec/issue creation (Phase 3.6) -- the one-shot pipeline handles setup through `/soleur:plan`.

### Phase 0.5: Domain Leader Assessment

Assess whether the feature description has implications for specific business domains. Domain leaders participate in brainstorming when their domain is relevant.

<!-- To add a new domain: add a row to the Domain Config table below. No other structural edits needed. -->

#### Domain Config

Read the feature description and assess relevance against each domain in the table below. For each relevant domain, use **AskUserQuestion tool** with the routing prompt and options from the table.

| Domain | Assessment Question | Leader | Routing Prompt | Options | Task Prompt |
|--------|-------------------|--------|----------------|---------|-------------|
| Marketing | Does this feature involve content changes, audience targeting, brand impact, brand identity definition, brand guide creation, voice and tone development, go-to-market activities, SEO/AEO concerns, pricing communication, or public-facing messaging? | cmo | "This feature has marketing or brand relevance. How would you like to proceed?" | **Start brand workshop** - Run the brand-architect agent to create or update a brand guide / **Include marketing perspective** - CMO joins the brainstorm to add marketing context / **Brainstorm normally** - Continue with the standard brainstorm flow | "Assess the marketing implications of this feature: {desc}. Identify marketing concerns, opportunities, and questions the user should consider during brainstorming. When the assessment involves visual layout or page structure, explicitly recommend delegating to conversion-optimizer or ux-design-lead for layout review. Output a brief structured assessment (not a full strategy)." |
| Engineering | Does this feature require significant architectural decisions, infrastructure changes, system design, or technical debt resolution beyond normal implementation? | cto | "This feature has architectural implications. Include technical assessment?" | **Include technical assessment** - CTO joins the brainstorm to assess technical implications / **Brainstorm normally** - Continue without CTO input | "Assess the technical implications of this feature: {desc}. Identify architecture risks, complexity concerns, and technical questions the user should consider during brainstorming. Output a brief structured assessment." |
| Operations | Does this feature involve operational decisions such as vendor selection, tool provisioning, expense tracking, process changes, or infrastructure procurement? | coo | "This feature has operational implications. Include operations assessment?" | **Include operations assessment** - COO joins the brainstorm to assess operational implications / **Brainstorm normally** - Continue without operations input | "Assess the operational implications of this feature: {desc}. Identify cost concerns, vendor decisions, process changes, and operational questions the user should consider during brainstorming. Output a brief structured assessment." |
| Product | Does this feature involve validating a new business idea, assessing product-market fit, evaluating customer demand, competitive positioning, or determining whether to build something? | cpo | "This looks like it involves product validation. How would you like to proceed?" | **Start validation workshop** - Run the business-validator agent to validate the business idea / **Include product perspective** - CPO joins the brainstorm to add product context / **Brainstorm normally** - Continue with the standard brainstorm flow | "Assess the product implications of this feature: {desc}. Identify product strategy concerns, validation gaps, and questions the user should consider during brainstorming. Output a brief structured assessment (not a full strategy)." |
| Legal | Does this feature involve creating, updating, or auditing legal documents such as terms of service, privacy policies, data processing agreements, or compliance documentation? | clo | "This feature has legal implications. Include legal assessment?" | **Include legal assessment** - CLO joins the brainstorm to assess legal implications / **Brainstorm normally** - Continue without legal input | "Assess the legal implications of this feature: {desc}. Identify compliance requirements, legal document needs, regulatory concerns, and legal questions the user should consider during brainstorming. Output a brief structured assessment." |
| Sales | Does this feature involve sales pipeline management, outbound prospecting, deal negotiation, proposal generation, revenue forecasting, or converting leads into customers through human-assisted sales motions? | cro | "This feature has sales implications. Include sales assessment?" | **Include sales assessment** - CRO joins the brainstorm to assess sales implications / **Brainstorm normally** - Continue without sales input | "Assess the sales implications of this feature: {desc}. Identify pipeline concerns, revenue conversion opportunities, and sales questions the user should consider during brainstorming. Output a brief structured assessment." |
| Finance | Does this feature involve financial planning, budgeting, budget allocation, cash flow management, or financial reporting? | cfo | "This feature has finance implications. Include finance assessment?" | **Include finance assessment** - CFO joins the brainstorm to assess financial implications / **Brainstorm normally** - Continue without finance input | "Assess the financial implications of this feature: {desc}. Identify budget concerns, revenue model questions, and financial planning considerations the user should consider during brainstorming. Output a brief structured assessment." |
| Support | Does this feature involve customer support workflows, issue triage, help documentation, community engagement, or customer success? | cco | "This feature has support implications. Include support assessment?" | **Include support assessment** - CCO joins the brainstorm to assess support implications / **Brainstorm normally** - Continue without support input | "Assess the support implications of this feature: {desc}. Identify support process gaps, documentation needs, community engagement opportunities, and support questions the user should consider during brainstorming. Output a brief structured assessment." |

#### Processing Instructions

1. Read the feature description and assess relevance against each domain in the table above.
2. For each relevant domain, use **AskUserQuestion tool** with the routing prompt and options from the table.
3. Workshop options ("Start brand workshop" in Marketing, "Start validation workshop" in Product): follow the named workshop section below (Brand Workshop, Validation Workshop).
4. Standard participation: for each accepted leader, spawn a Task using the Task Prompt from the table, substituting `{desc}` with the feature description. Weave each leader's assessment into the brainstorm dialogue alongside repo research findings.
5. If multiple domains are relevant, ask about each separately.
6. If no domains are relevant or the user declines all domain leaders, continue to Phase 1.

#### Brand Workshop (if selected)

1. **Create worktree:**
   - Derive feature name: use the first 2-3 descriptive words from the feature description in kebab-case (e.g., "define our brand identity" -> `brand-identity`). If the description is fewer than 3 words, default to `brand-guide`.
   - Run `./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh feature <name>`
   - Set `WORKTREE_PATH`

2. **Handle issue:**
   - Parse feature_description for existing issue reference (`#N` pattern)
   - If found: validate issue state with `gh issue view`. If OPEN, use it. If CLOSED or not found, create a new one.
   - If not found: create a new issue with `gh issue create --title "feat: <Topic>" --body "..."`
   - Update the issue body with artifact links (brand guide path, branch name)
   - Do NOT generate spec.md -- brand workshops produce a brand guide, not a spec

3. **Navigate to worktree:**

   Run `cd` to the worktree path from step 1 (e.g., `.worktrees/feat-<name>`), then run `pwd` to verify the path shows `.worktrees/feat-<name>`.

4. **Hand off to brand-architect:**

   ```
   Task brand-architect(feature_description)
   ```

   The brand-architect agent runs its full interactive workshop and writes the brand guide to `knowledge-base/overview/brand-guide.md` inside the worktree.

5. **Display completion message and STOP.** Do NOT proceed to Phase 1. Do NOT run Phase 2 or Phase 3.5. Display:

   ```text
   Brand workshop complete!

   Document: none (brand workshop)
   Brand guide: knowledge-base/overview/brand-guide.md
   Issue: #N (using existing) | #N (created)
   Branch: feat-<name> (if worktree created)
   Working directory: .worktrees/feat-<name>/ (if worktree created)

   Next: The brand guide is now available for discord-content and other marketing skills.
   ```

   End brainstorm execution after displaying this message.

#### Validation Workshop (if selected)

<!-- Follows brand-architect workshop pattern: worktree, issue, hand off, STOP. See constitution for the workshop archetype. -->

1. **Create worktree:**
   - Derive feature name: use the first 2-3 descriptive words from the feature description in kebab-case (e.g., "validate my SaaS idea" -> `validate-saas`). If the description is fewer than 3 words, default to `business-validation`.
   - Run `./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh feature <name>`
   - Set `WORKTREE_PATH`

2. **Handle issue:**
   - Parse feature_description for existing issue reference (`#N` pattern)
   - If found: validate issue state with `gh issue view`. If OPEN, use it. If CLOSED or not found, create a new one.
   - If not found: create a new issue with `gh issue create --title "feat: <Topic>" --body "..."`
   - Update the issue body with artifact links (validation report path, branch name)
   - Do NOT generate spec.md -- validation workshops produce a validation report, not a spec

3. **Navigate to worktree:**

   Run `cd` to the worktree path from step 1 (e.g., `.worktrees/feat-<name>`), then run `pwd` to verify the path shows `.worktrees/feat-<name>`.

4. **Hand off to business-validator:**

   ```text
   Task business-validator(feature_description)
   ```

   The business-validator agent runs its full interactive workshop and writes the validation report to `knowledge-base/overview/business-validation.md` inside the worktree.

5. **Display completion message and STOP.** Do NOT proceed to Phase 1. Do NOT run Phase 2 or Phase 3.5. Display:

   ```text
   Validation workshop complete!

   Document: none (validation workshop)
   Validation report: knowledge-base/overview/business-validation.md
   Issue: #N (using existing) | #N (created)
   Branch: feat-<name> (if worktree created)
   Working directory: .worktrees/feat-<name>/ (if worktree created)

   Next: Review the validation report. If verdict is GO, run /soleur:plan to start building.
   ```

   End brainstorm execution after displaying this message.

### Phase 1: Understand the Idea

#### 1.1 Research (Context Gathering)

Run these agents **in parallel** to gather context before dialogue:

- Task repo-research-analyst(feature_description)
- Task learnings-researcher(feature_description)

**What to look for:**
- **Repo research:** existing patterns, similar features, CLAUDE.md guidance
- **Learnings:** documented solutions in `knowledge-base/learnings/` -- past gotchas, patterns, lessons learned that might inform WHAT to build

If either agent fails or returns empty, proceed with whatever results are available. Weave findings naturally into your first question rather than presenting a formal summary.

#### 1.2 Collaborative Dialogue

Use the **AskUserQuestion tool** to ask questions **one at a time**.

**Guidelines (see `brainstorming` skill for detailed techniques):**

- Prefer multiple choice when natural options exist
- Start broad (purpose, users) then narrow (constraints, edge cases)
- Validate assumptions explicitly
- Ask about success criteria

**Exit condition:** Continue until the idea is clear OR user says "proceed"

### Phase 2: Explore Approaches

Propose **2-3 concrete approaches** based on research and conversation.

For each approach, provide:

- Brief description (2-3 sentences)
- Pros and cons
- When it's best suited

Lead with your recommendation and explain why. Apply YAGNI—prefer simpler solutions.

Use **AskUserQuestion tool** to ask which approach the user prefers.

### Phase 3: Create Worktree (if knowledge-base/ exists)

**IMPORTANT:** Create the worktree BEFORE writing any files so all artifacts go on the feature branch.

**Check for knowledge-base directory:**

```bash
if [[ -d "knowledge-base" ]]; then
  # knowledge-base exists, create worktree first
fi
```

**If knowledge-base/ exists:**

1. **Get feature name** from user or derive from brainstorm topic (kebab-case)
2. **Create worktree + spec directory:**

   ```bash
   ./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh feature <name>
   ```

   This creates:
   - `.worktrees/feat-<name>/` (worktree)
   - `knowledge-base/specs/feat-<name>/` (spec directory in worktree)

3. **Set worktree path for subsequent file operations:**

   ```text
   WORKTREE_PATH=".worktrees/feat-<name>"
   ```

   All files written after this point MUST use this path prefix.

### Phase 3.5: Capture the Design

Write the brainstorm document. **Use worktree path if created.**

**File path:**

- If worktree exists: `<worktree-path>/knowledge-base/brainstorms/YYYY-MM-DD-<topic>-brainstorm.md` (replace `<worktree-path>` with the actual worktree path, e.g., `.worktrees/feat-<name>`)
- If no worktree: `knowledge-base/brainstorms/YYYY-MM-DD-<topic>-brainstorm.md`

**Document structure:** See the `brainstorming` skill for the template format. Key sections: What We're Building, Why This Approach, Key Decisions, Open Questions.

If domain leaders participated and reported capability gaps in their assessments, include a `## Capability Gaps` section after "Open Questions" listing each gap with what is missing, which domain it belongs to, and why it is needed. Omit this section if no domain leaders participated or no gaps were reported.

Ensure the brainstorms directory exists before writing.

### Phase 3.6: Create Spec and Issue (if worktree exists)

**If worktree was created:**

1. **Check for existing issue reference in feature_description:**

   Parse the feature description for `#N` patterns (e.g., `#42`). Extract the first issue number found.

   **If issue reference found**, validate its state by running `gh issue view <number> --json state` and pipe to `jq .state`:

   - **If OPEN:** Use existing issue -- skip creation, proceed to step 3
   - **If CLOSED:** Warn the user, then create a new issue with "Replaces closed #N" in the body (proceed to step 2)
   - **If not found or error:** Use AskUserQuestion: "Issue #N not found. Create new issue anyway?" If yes, proceed to step 2. If no, abort.

2. **Create GitHub issue** (only if no valid existing issue):

   ```bash
   gh issue create --title "feat: <Feature Title>" --body "..."
   ```

   Include in the issue body:
   - Summary of what's being built (from brainstorm)
   - Link to brainstorm document
   - Link to spec file
   - Branch name (`feat-<name>`)
   - Acceptance criteria (from brainstorm decisions)
   - If replacing closed issue: "Replaces closed #$existing_issue"

3. **Update existing issue with artifact links** (if using existing issue):

   Fetch the existing issue body with `gh issue view <number> --json body` piped to `jq .body`. Append an Artifacts section with links to the brainstorm document, spec file, and branch name. Then update with `gh issue edit <number> --body "<updated body>"`.

4. **Generate spec.md** using `spec-templates` skill template:
   - Fill in Problem Statement from brainstorm
   - Fill in Goals from brainstorm decisions
   - Fill in Non-Goals from what was explicitly excluded
   - Add Functional Requirements (FR1, FR2...) from key features
   - Add Technical Requirements (TR1, TR2...) from constraints

5. **Save spec.md** to the worktree: `<worktree-path>/knowledge-base/specs/feat-<name>/spec.md` (replace `<worktree-path>` with the actual worktree path)

6. **Switch to worktree:**

   ```bash
   cd .worktrees/feat-<name>
   ```

   **IMPORTANT:** All subsequent work for this feature should happen in the worktree, not the main repository. Announce the switch clearly to the user.

7. **Announce:**
   - If using existing issue: "Spec saved. **Using existing issue: #N.** Now working in worktree: `.worktrees/feat-<name>`. Run `/soleur:plan` to create tasks."
   - If created new issue: "Spec saved. GitHub issue #N created. **Now working in worktree:** `.worktrees/feat-<name>`. Run `/soleur:plan` to create tasks."

**If knowledge-base/ does NOT exist:**

- Brainstorm saved to `knowledge-base/brainstorms/` only (no worktree)
- No spec or issue created

### Phase 4: Handoff

Use **AskUserQuestion tool** to present next steps:

**Question:** "Brainstorm captured. Now in worktree `feat-<name>`. What would you like to do next?"

**Options:**

1. **Proceed to planning** - Run `/soleur:plan` (will auto-detect this brainstorm)
2. **Create visual designs** - Run ux-design-lead agent for .pen file design (requires Pencil extension)
3. **Refine design further** - Continue exploring
4. **Done for now** - Return later

## Output Summary

When complete, display:

```text
Brainstorm complete!

Document: knowledge-base/brainstorms/YYYY-MM-DD-<topic>-brainstorm.md
Spec: knowledge-base/specs/feat-<name>/spec.md
Issue: #N (using existing) | #N (created) | none
Branch: feat-<name> (if worktree created)
Working directory: .worktrees/feat-<name>/ (if worktree created)

Key decisions:
- [Decision 1]
- [Decision 2]

Next: Run `/soleur:plan` when ready to implement.
```

**Issue line format:**

- `#N (using existing)` - When brainstorm started with an existing issue reference
- `#N (created)` - When a new issue was created
- `none` - When no worktree/issue was created

## Managing Brainstorm Documents

**Update an existing brainstorm:**
If re-running brainstorm on the same topic, read the existing document first. Update in place rather than creating a duplicate. Preserve prior decisions and mark any changes with `[Updated YYYY-MM-DD]`.

**Archive old brainstorms:**
Move completed or superseded brainstorms to `knowledge-base/brainstorms/archive/`: `mkdir -p knowledge-base/brainstorms/archive && git mv knowledge-base/brainstorms/<file>.md knowledge-base/brainstorms/archive/`. Commit with `git commit -m "brainstorm: archive <topic>"`.

## Important Guidelines

- **Stay focused on WHAT, not HOW** - Implementation details belong in the plan
- **Ask one question at a time** - Don't overwhelm
- **Apply YAGNI** - Prefer simpler approaches
- **Keep outputs concise** - 200-300 words per section max

NEVER CODE! Just explore and document decisions.
