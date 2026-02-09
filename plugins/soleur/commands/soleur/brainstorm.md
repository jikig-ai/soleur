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
Use **AskUserQuestion tool** to suggest: "Your requirements seem detailed enough to proceed directly to planning. Should I run `/soleur:plan` instead, or would you like to explore the idea further?"

### Phase 1: Understand the Idea

#### 1.1 Repository Research (Lightweight)

Run a quick repo scan to understand existing patterns:

- Task repo-research-analyst("Understand existing patterns related to: <feature_description>")

Focus on: similar features, established patterns, CLAUDE.md guidance.

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
   ```
   WORKTREE_PATH=".worktrees/feat-<name>"
   ```
   All files written after this point MUST use this path prefix.

### Phase 3.5: Capture the Design

Write the brainstorm document. **Use worktree path if created.**

**File path:**
- If worktree exists: `${WORKTREE_PATH}/knowledge-base/brainstorms/YYYY-MM-DD-<topic>-brainstorm.md`
- If no worktree: `knowledge-base/brainstorms/YYYY-MM-DD-<topic>-brainstorm.md`

**Document structure:** See the `brainstorming` skill for the template format. Key sections: What We're Building, Why This Approach, Key Decisions, Open Questions.

Ensure the brainstorms directory exists before writing.

### Phase 3.6: Create Spec and Issue (if worktree exists)

**If worktree was created:**

1. **Check for existing issue reference in feature_description:**
   ```bash
   # Parse for issue patterns: #N (first occurrence)
   existing_issue=$(echo "<feature_description>" | grep -oE '#[0-9]+' | head -1 | tr -d '#')
   ```

   **If issue reference found**, validate and handle by state:

   ```bash
   if [[ -n "$existing_issue" ]]; then
     issue_state=$(gh issue view "$existing_issue" --json state --jq .state 2>/dev/null)

     if [[ "$issue_state" == "OPEN" ]]; then
       # Use existing issue - skip creation, proceed to step 3
       echo "Using existing issue: #$existing_issue"
     elif [[ "$issue_state" == "CLOSED" ]]; then
       # Warn and create new issue with reference
       echo "Warning: Issue #$existing_issue is closed."
       echo "Creating new issue with reference to closed one."
       # Proceed to step 2, include "Replaces closed #$existing_issue" in body
     else
       # Issue not found - prompt user
       echo "Warning: Issue #$existing_issue not found."
       # Use AskUserQuestion: "Create new issue anyway?"
       # If yes, proceed to step 2. If no, abort.
     fi
   fi
   ```

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
   ```bash
   existing_body=$(gh issue view "$existing_issue" --json body --jq .body)
   new_body="${existing_body}

   ---
   ## Artifacts
   - Brainstorm: \`knowledge-base/brainstorms/YYYY-MM-DD-<topic>-brainstorm.md\`
   - Spec: \`knowledge-base/specs/feat-<name>/spec.md\`
   - Branch: \`feat-<name>\`
   "
   gh issue edit "$existing_issue" --body "$new_body"
   ```

4. **Generate spec.md** using `spec-templates` skill template:
   - Fill in Problem Statement from brainstorm
   - Fill in Goals from brainstorm decisions
   - Fill in Non-Goals from what was explicitly excluded
   - Add Functional Requirements (FR1, FR2...) from key features
   - Add Technical Requirements (TR1, TR2...) from constraints

5. **Save spec.md** to worktree: `${WORKTREE_PATH}/knowledge-base/specs/feat-<name>/spec.md`

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
2. **Refine design further** - Continue exploring
3. **Done for now** - Return later

## Output Summary

When complete, display:

```
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
