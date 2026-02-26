---
name: brainstorm
description: "This skill should be used when exploring requirements and approaches through collaborative dialogue before planning implementation."
---

# Brainstorm a Feature or Improvement

**Note: The current year is 2026.** Use this when dating brainstorm documents.

Brainstorming helps answer **WHAT** to build through collaborative dialogue. It precedes the `soleur:plan` skill, which answers **HOW** to build it.

**Process knowledge:** Load the `brainstorm-techniques` skill for detailed question techniques, approach exploration patterns, and YAGNI principles.

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

**Plugin loader constraint:** Before proposing namespace changes (bare commands, command-to-skill migration), verify plugin loader constraints -- bare namespace commands are not supported, and commands/skills have different frontmatter and argument handling.

Evaluate whether brainstorming is needed based on the feature description.

**Clear requirements indicators:**

- Specific acceptance criteria provided
- Referenced existing patterns to follow
- Described exact expected behavior
- Constrained, well-defined scope

**If requirements are already clear:**
Use **AskUserQuestion tool** to suggest: "Your requirements seem clear enough to skip brainstorming. How would you like to proceed?"

Options:
1. **One-shot it** - Use the **Skill tool**: `skill: soleur:one-shot` for full autonomous execution (plan, deepen, implement, review, resolve todos, browser test, feature video, PR). Best for simple, single-session tasks like bug fixes or small improvements.
2. **Plan first** - Use the **Skill tool**: `skill: soleur:plan` to create a plan before implementing
3. **Brainstorm anyway** - Continue exploring the idea

If one-shot is selected, pass the original feature description (including any issue references) to `skill: soleur:one-shot` and stop brainstorm execution. Note: this skips brainstorm capture (Phase 3.5), worktree creation (Phase 3), and spec/issue creation (Phase 3.6) -- the one-shot pipeline handles setup through the plan skill.

### Phase 0.5: Domain Leader Assessment

Assess whether the feature description has implications for specific business domains. Domain leaders participate in brainstorming when their domain is relevant.

<!-- To add a new domain: add a row to the Domain Config table below. No other structural edits needed. -->

#### Domain Config

**Read `plugins/soleur/skills/brainstorm/references/brainstorm-domain-config.md` now** to load the Domain Config table with all 8 domain rows (Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support). Each row contains: Assessment Question, Leader, Routing Prompt, Options, and Task Prompt.

#### Processing Instructions

1. Read the feature description and assess relevance against each domain in the table above.
2. For each relevant domain, use **AskUserQuestion tool** with the routing prompt and options from the table.
3. Workshop options ("Start brand workshop" in Marketing, "Start validation workshop" in Product): follow the named workshop section below (Brand Workshop, Validation Workshop).
4. Standard participation: for each accepted leader, spawn a Task using the Task Prompt from the table, substituting `{desc}` with the feature description. Weave each leader's assessment into the brainstorm dialogue alongside repo research findings.
5. If multiple domains are relevant, ask about each separately.
6. If no domains are relevant or the user declines all domain leaders, continue to Phase 1.

#### Brand Workshop (if selected)

**Read `plugins/soleur/skills/brainstorm/references/brainstorm-brand-workshop.md` now** for the full Brand Workshop procedure (worktree creation, issue handling, brand-architect handoff, completion message). Follow all steps in the reference file, then STOP -- do not proceed to Phase 1.

#### Validation Workshop (if selected)

**Read `plugins/soleur/skills/brainstorm/references/brainstorm-validation-workshop.md` now** for the full Validation Workshop procedure (worktree creation, issue handling, business-validator handoff, completion message). Follow all steps in the reference file, then STOP -- do not proceed to Phase 1.

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

**Guidelines (see `brainstorm-techniques` skill for detailed techniques):**

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

4. **Create draft PR:**

   Switch to the worktree and create a draft PR:

   ```bash
   cd .worktrees/feat-<name>
   bash ./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh draft-pr
   ```

   This creates an empty commit, pushes the branch, and opens a draft PR. If the push or PR creation fails (no network), a warning is printed but the workflow continues.

### Phase 3.5: Capture the Design

Write the brainstorm document. **Use worktree path if created.**

**File path:**

- If worktree exists: `<worktree-path>/knowledge-base/brainstorms/YYYY-MM-DD-<topic>-brainstorm.md` (replace `<worktree-path>` with the actual worktree path, e.g., `.worktrees/feat-<name>`)
- If no worktree: `knowledge-base/brainstorms/YYYY-MM-DD-<topic>-brainstorm.md`

**Document structure:** See the `brainstorm-techniques` skill for the template format. Key sections: What We're Building, Why This Approach, Key Decisions, Open Questions.

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

6. **Commit and push all brainstorm artifacts:**

   After the brainstorm document (Phase 3.5) and spec are both written, commit and push everything:

   ```bash
   git add knowledge-base/brainstorms/ knowledge-base/specs/feat-<name>/
   git commit -m "docs: capture brainstorm and spec for feat-<name>"
   git push
   ```

   If the push fails (no network), print a warning but continue. The artifacts are committed locally.

7. **Switch to worktree:**

   ```bash
   cd .worktrees/feat-<name>
   ```

   **IMPORTANT:** All subsequent work for this feature should happen in the worktree, not the main repository. Announce the switch clearly to the user.

8. **Announce:**
   - If using existing issue: "Spec saved. **Using existing issue: #N.** Now working in worktree: `.worktrees/feat-<name>`. Use `skill: soleur:plan` to create tasks."
   - If created new issue: "Spec saved. GitHub issue #N created. **Now working in worktree:** `.worktrees/feat-<name>`. Use `skill: soleur:plan` to create tasks."

**If knowledge-base/ does NOT exist:**

- Brainstorm saved to `knowledge-base/brainstorms/` only (no worktree)
- No spec or issue created

### Phase 4: Handoff

**Context headroom notice:** Before presenting options, display: "All artifacts are on disk. Starting a new session for `/soleur:plan` will give you maximum context headroom."

Use **AskUserQuestion tool** to present next steps:

**Question:** "Brainstorm captured. Now in worktree `feat-<name>`. What would you like to do next?"

**Options:**

1. **Proceed to planning** - Use `skill: soleur:plan` (will auto-detect this brainstorm)
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

Next: Use `skill: soleur:plan` when ready to implement.
```

**Issue line format:**

- `#N (using existing)` - When brainstorm started with an existing issue reference
- `#N (created)` - When a new issue was created
- `none` - When no worktree/issue was created

## Managing Brainstorm Documents

**Update an existing brainstorm:**
If re-running brainstorm on the same topic, read the existing document first. Update in place rather than creating a duplicate. Preserve prior decisions and mark any changes with `[Updated YYYY-MM-DD]`.

**Archive old brainstorms:**
Run `bash ./plugins/soleur/skills/archive-kb/scripts/archive-kb.sh` from the repository root. This moves matching artifacts to `knowledge-base/brainstorms/archive/` with timestamp prefixes, preserving git history. Commit with `git commit -m "brainstorm: archive <topic>"`.

## Important Guidelines

- **Stay focused on WHAT, not HOW** - Implementation details belong in the plan
- **Ask one question at a time** - Don't overwhelm
- **Apply YAGNI** - Prefer simpler approaches
- **Keep outputs concise** - 200-300 words per section max

NEVER CODE! Just explore and document decisions.
