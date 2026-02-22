---
name: soleur:plan
description: Transform feature descriptions into well-structured project plans following conventions
argument-hint: "[feature description, bug report, or improvement idea]"
---

# Create a plan for a new feature or bug fix

## Introduction

**Note: The current year is 2026.** Use this when dating plans and searching for recent documentation.

Transform feature descriptions, bug reports, or improvement ideas into well-structured markdown files issues that follow project conventions and best practices. This command provides flexible detail levels to match your needs.

## Feature Description

<feature_description> #$ARGUMENTS </feature_description>

**If the feature description above is empty, ask the user:** "What would you like to plan? Please describe the feature, bug fix, or improvement you have in mind."

Do not proceed until you have a clear feature description from the user.

### 0. Load Knowledge Base Context (if exists)

**Load project conventions:**

```bash
# Load project conventions
if [[ -f "CLAUDE.md" ]]; then
  cat CLAUDE.md
fi
```

**Check for knowledge-base directory and load context:**

Check if `knowledge-base/` directory exists. If it does:

1. Run `git branch --show-current` to get the current branch name
2. If the branch starts with `feat-`, read `knowledge-base/specs/<branch-name>/spec.md` if it exists

**If knowledge-base/ exists:**

1. Read `CLAUDE.md` if it exists - apply project conventions during planning
2. If `# Project Constitution` heading is NOT already in context, read `knowledge-base/overview/constitution.md` - use principles to guide planning decisions. Skip if already loaded (e.g., from a preceding `/soleur:brainstorm`).
3. Detect feature from current branch (`feat-<name>` pattern)
4. Read `knowledge-base/specs/feat-<name>/spec.md` if it exists - use as planning input
5. Announce: "Loaded constitution and spec for `feat-<name>`"

**If knowledge-base/ does NOT exist:**

- Continue with standard planning flow

### 0.5. Idea Refinement

**Check for brainstorm output first:**

Before asking questions, look for recent brainstorm documents in `knowledge-base/brainstorms/` that match this feature:

```bash
ls -la knowledge-base/brainstorms/*.md 2>/dev/null | head -10
```

**Relevance criteria:** A brainstorm is relevant if:

- The topic (from filename or YAML frontmatter) semantically matches the feature description
- Created within the last 14 days
- If multiple candidates match, use the most recent one

**If a relevant brainstorm exists:**

1. Read the brainstorm document
2. Announce: "Found brainstorm from [date]: [topic]. Using as context for planning."
3. Extract key decisions, chosen approach, and open questions
4. **Skip the idea refinement questions below** - the brainstorm already answered WHAT to build
5. Proceed to Phase 1 -- **all sub-phases still apply** (1, 1.5, 1.5b, 1.6). Having a brainstorm skips idea refinement only, not community discovery or research.

**If multiple brainstorms could match:**
Use **AskUserQuestion tool** to ask which brainstorm to use, or whether to proceed without one.

**If no brainstorm found (or not relevant), run idea refinement:**

Refine the idea through collaborative dialogue using the **AskUserQuestion tool**:

- Ask questions one at a time to understand the idea fully
- Prefer multiple choice questions when natural options exist
- Focus on understanding: purpose, constraints and success criteria
- Continue until the idea is clear OR user says "proceed"

**Gather signals for research decision.** During refinement, note:

- **User's familiarity**: Do they know the codebase patterns? Are they pointing to examples?
- **User's intent**: Speed vs thoroughness? Exploration vs execution?
- **Topic risk**: Security, payments, external APIs warrant more caution
- **Uncertainty level**: Is the approach clear or open-ended?

**Skip option:** If the feature description is already detailed, offer:
"Your description is clear. Should I proceed with research, or would you like to refine it further?"

## Main Tasks

### 1. Local Research (Always Runs - Parallel)

<thinking>
First, I need to understand the project's conventions, existing patterns, and any documented learnings. This is fast and local - it informs whether external research is needed.
</thinking>

Run these agents **in parallel** to gather local context:

- Task repo-research-analyst(feature_description)
- Task learnings-researcher(feature_description)

**What to look for:**

- **Repo research:** existing patterns, CLAUDE.md guidance, technology familiarity, pattern consistency
- **Learnings:** documented solutions in `knowledge-base/learnings/` that might apply (gotchas, patterns, lessons learned)

These findings inform the next step.

### 1.5. Community Discovery Check (Conditional)

**Read `plugins/soleur/commands/soleur/references/plan-community-discovery.md` now** for the full community discovery procedure (stack detection, coverage gap check, agent-finder). Skip if no uncovered stacks detected.

### 1.5b. Functional Overlap Check

**Read `plugins/soleur/commands/soleur/references/plan-functional-overlap.md` now** for the functional overlap check procedure (always runs, spawns functional-discovery agent).

### 1.6. Research Decision

Based on signals from Step 0 and findings from Step 1, decide on external research.

**High-risk topics → always research.** Security, payments, external APIs, data privacy. The cost of missing something is too high. This takes precedence over speed signals.

**Strong local context → skip external research.** Codebase has good patterns, CLAUDE.md has guidance, user knows what they want. External research adds little value.

**Uncertainty or unfamiliar territory → research.** User is exploring, codebase has no examples, new technology. External perspective is valuable.

**Announce the decision and proceed.** Brief explanation, then continue. User can redirect if needed.

Examples:

- "Your codebase has solid patterns for this. Proceeding without external research."
- "This involves payment processing, so I'll research current best practices first."

### 1.6b. External Research (Conditional)

**Only run if Step 1.6 indicates external research is valuable.**

Run these agents in parallel:

- Task best-practices-researcher(feature_description)
- Task framework-docs-researcher(feature_description)

### 1.7. Consolidate Research

After all research steps complete, consolidate findings:

- Document relevant file paths from repo research (e.g., `app/services/example_service.rb:42`)
- **Include relevant institutional learnings** from `knowledge-base/learnings/` (key insights, gotchas to avoid)
- Note external documentation URLs and best practices (if external research was done)
- List related issues or PRs discovered
- Capture CLAUDE.md conventions

**Optional validation:** Briefly summarize findings and ask if anything looks off or missing before proceeding to planning.

### 2. Issue Planning & Structure

<thinking>
Think like a product manager - what would make this issue clear and actionable? Consider multiple perspectives
</thinking>

**Title & Categorization:**

- [ ] Draft clear, searchable issue title using conventional format (e.g., `feat: Add user authentication`, `fix: Cart total calculation`)
- [ ] Determine issue type: enhancement, bug, refactor
- [ ] Convert title to filename: add today's date prefix, strip prefix colon, kebab-case, add `-plan` suffix
  - Example: `feat: Add User Authentication` → `2026-01-21-feat-add-user-authentication-plan.md`
  - Keep it descriptive (3-5 words after prefix) so plans are findable by context

**Stakeholder Analysis:**

- [ ] Identify who will be affected by this issue (end users, developers, operations)
- [ ] Consider implementation complexity and required expertise

**Content Planning:**

- [ ] Choose appropriate detail level based on issue complexity and audience
- [ ] List all necessary sections for the chosen template
- [ ] Gather supporting materials (error logs, screenshots, design mockups)
- [ ] Prepare code examples or reproduction steps if applicable, name the mock filenames in the lists

### 3. SpecFlow Analysis

After planning the issue structure, run SpecFlow Analyzer to validate and refine the feature specification:

- Task spec-flow-analyzer(feature_description, research_findings)

**SpecFlow Analyzer Output:**

- [ ] Review SpecFlow analysis results
- [ ] Incorporate any identified gaps or edge cases into the issue
- [ ] Update acceptance criteria based on SpecFlow findings

### 4. Choose Implementation Detail Level

**Read `plugins/soleur/commands/soleur/references/plan-issue-templates.md` now** to load the three issue templates (MINIMAL, MORE, A LOT). Select the appropriate detail level based on complexity -- simpler is mostly better. Use the template structure from the reference file for the chosen level.

### 5. Issue Creation & Formatting

<thinking>
Apply best practices for clarity and actionability, making the issue easy to scan and understand
</thinking>

**Content Formatting:**

- [ ] Use clear, descriptive headings with proper hierarchy (##, ###)
- [ ] Include code examples in triple backticks with language syntax highlighting
- [ ] Add screenshots/mockups if UI-related (drag & drop or use image hosting)
- [ ] Use task lists (- [ ]) for trackable items that can be checked off
- [ ] Add collapsible sections for lengthy logs or optional details using `<details>` tags
- [ ] Apply appropriate emoji for visual scanning (🐛 bug, ✨ feature, 📚 docs, ♻️ refactor)

**Cross-Referencing:**

- [ ] Link to related issues/PRs using #number format
- [ ] Reference specific commits with SHA hashes when relevant
- [ ] Link to code using GitHub's permalink feature (press 'y' for permanent link)
- [ ] Mention relevant team members with @username if needed
- [ ] Add links to external resources with descriptive text

**Code & Examples:**

````markdown
# Good example with syntax highlighting and line references


```ruby
# app/services/user_service.rb:42
def process_user(user)

# Implementation here

end
```

# Collapsible error logs

<details>
<summary>Full error stacktrace</summary>

`Error details here...`

</details>
````

**AI-Era Considerations:**

- [ ] Account for accelerated development with AI pair programming
- [ ] Include prompts or instructions that worked well during research
- [ ] Note which AI tools were used for initial exploration (Claude, Copilot, etc.)
- [ ] Emphasize comprehensive testing given rapid implementation
- [ ] Document any AI-generated code that needs human review

### 6. Final Review & Submission

**Pre-submission Checklist:**

- [ ] Title is searchable and descriptive
- [ ] Labels accurately categorize the issue
- [ ] All template sections are complete
- [ ] Links and references are working
- [ ] Acceptance criteria are measurable
- [ ] Add names of files in pseudo code examples and todo lists
- [ ] Add an ERD mermaid diagram if applicable for new model changes

## Output Format

**Filename:** Use the date and kebab-case filename from Step 2 Title & Categorization.

```text
knowledge-base/plans/YYYY-MM-DD-<type>-<descriptive-name>-plan.md
```

Examples:

- ✅ `knowledge-base/plans/2026-01-15-feat-user-authentication-flow-plan.md`
- ✅ `knowledge-base/plans/2026-02-03-fix-checkout-race-condition-plan.md`
- ✅ `knowledge-base/plans/2026-03-10-refactor-api-client-extraction-plan.md`
- ❌ `knowledge-base/plans/2026-01-15-feat-thing-plan.md` (not descriptive - what "thing"?)
- ❌ `knowledge-base/plans/2026-01-15-feat-new-feature-plan.md` (too vague - what feature?)
- ❌ `knowledge-base/plans/2026-01-15-feat: user auth-plan.md` (invalid characters - colon and space)
- ❌ `knowledge-base/plans/feat-user-auth-plan.md` (missing date prefix)

## Save Tasks to Knowledge Base (if exists)

**After writing the plan to `knowledge-base/plans/`, also create tasks.md if knowledge-base/ exists:**

Check if `knowledge-base/` exists. If so, run `git branch --show-current` to get the current branch. If on a `feat-*` branch, create the spec directory with `mkdir -p knowledge-base/specs/<branch-name>`.

**If knowledge-base/ exists and on a feature branch:**

1. **Generate tasks.md** using `spec-templates` skill template:
   - Extract actionable tasks from the plan
   - Organize into phases (Setup, Core Implementation, Testing)
   - Use hierarchical numbering (1.1, 2.1, 2.1.1, etc.)

2. **Save tasks.md** to `knowledge-base/specs/feat-<name>/tasks.md`

3. **Announce:** "Tasks saved to `knowledge-base/specs/feat-<name>/tasks.md`. Run `/soleur:work` to implement."

**If knowledge-base/ does NOT exist or not on feature branch:**

- Plan saved to `knowledge-base/plans/` only (current behavior)

## Plan Review (Always Runs)

After writing the plan file, automatically run `/plan_review <plan_file_path>` to get feedback from three specialized reviewers in parallel:

- **DHH Rails Reviewer** - Challenges overengineering, enforces simplicity
- **Kieran Rails Reviewer** - Checks correctness, completeness, convention adherence
- **Code Simplicity Reviewer** - Ensures YAGNI, flags unnecessary complexity

**After review completes:**

1. Present consolidated feedback (agreements first, then disagreements)
2. Ask: "Apply these changes?" (Yes / Partially / Skip)
3. If Yes: apply all changes to the plan file
4. If Partially: ask which changes to apply, then apply selected changes
5. If Skip: continue unchanged

## Post-Generation Options

After plan review, use the **AskUserQuestion tool** to present these options:

**Question:** "Plan reviewed and ready at `knowledge-base/plans/YYYY-MM-DD-<type>-<name>-plan.md`. What would you like to do next?"

**Options:**

1. **Open plan in editor** - Open the plan file for review
2. **Run `/deepen-plan`** - Enhance each section with parallel research agents (best practices, performance, UI)
3. **Start `/soleur:work`** - Begin implementing this plan locally
4. **Start `/soleur:work` on remote** - Begin implementing in Claude Code on the web (use `&` to run in background)
5. **Create Issue** - Create issue in project tracker (GitHub/Linear)
6. **Simplify** - Reduce detail level

Based on selection:

- **Open plan in editor** → Run `open knowledge-base/plans/<plan_filename>.md` to open the file in the user's default editor
- **`/deepen-plan`** → Call the /deepen-plan command with the plan file path to enhance with research
- **`/soleur:work`** → Call the /soleur:work command with the plan file path
- **`/soleur:work` on remote** → Run `/soleur:work knowledge-base/plans/<plan_filename>.md &` to start work in background for Claude Code web
- **Create Issue** → See "Issue Creation" section below
- **Simplify** → Ask "What should I simplify?" then regenerate simpler version
- **Other** (automatically provided) → Accept free text for rework or specific changes

**Note:** If running `/soleur:plan` with ultrathink enabled, automatically run `/deepen-plan` after plan creation for maximum depth and grounding.

Loop back to options after Simplify or Other changes until user selects `/soleur:work`.

## Issue Creation

When user selects "Create Issue", detect their project tracker from CLAUDE.md:

1. **Check for tracker preference** in user's CLAUDE.md (global or project):
   - Look for `project_tracker: github` or `project_tracker: linear`
   - Or look for mentions of "GitHub Issues" or "Linear" in their workflow section

2. **If GitHub:**

   Use the title and type from Step 2 (already in context - no need to re-read the file):

   ```bash
   gh issue create --title "<type>: <title>" --body-file <plan_path>
   ```

3. **If Linear:**

   Read the plan file content, then run `linear issue create --title "<title>" --description "<plan content>"`.

4. **If no tracker configured:**
   Ask user: "Which project tracker do you use? (GitHub/Linear/Other)"
   - Suggest adding `project_tracker: github` or `project_tracker: linear` to their CLAUDE.md

5. **After creation:**
   - Display the issue URL
   - Ask if they want to proceed to `/soleur:work` or `/plan_review`

## Managing Plan Documents

**Update an existing plan:**
If re-running `/soleur:plan` for the same feature, read the existing plan first. Update in place rather than creating a duplicate. Preserve prior content and mark changes with `[Updated YYYY-MM-DD]`.

**Archive completed plans:**
Move completed or superseded plans to `knowledge-base/plans/archive/`: `mkdir -p knowledge-base/plans/archive && git mv knowledge-base/plans/<file>.md knowledge-base/plans/archive/`. Commit with `git commit -m "plan: archive <topic>"`.

NEVER CODE! Just research and write the plan.
