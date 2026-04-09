---
name: work
description: "Execute work plans efficiently while maintaining quality and finishing features. Takes a plan document and implements it systematically with TDD, incremental commits, and parallel execution."
triggers:
- work
- execute plan
- implement plan
- start work
- begin implementation
---

# Work Plan Execution

Execute a work plan efficiently while maintaining quality and finishing features.

This skill takes a work document (plan, specification, or todo file) and executes it systematically. The focus is on **shipping complete features** by understanding requirements quickly, following existing patterns, and maintaining quality throughout.

**Process knowledge:** Read `.plugin/skills/work/references/` files for agent-teams, lifecycle-parallel, and subagent-fanout execution strategies.

## Input Document

If the user has not provided a plan path or description in the conversation, ask: "What plan or feature would you like to implement? Please provide a path to the plan file or describe the work."

Do not proceed until you have an input document or description.

## Execution Workflow

### Phase 0: Load Knowledge Base Context (if exists)

**Load project conventions:**

```bash
if [[ -f "AGENTS.md" ]]; then
  cat AGENTS.md
fi
```

**Clean up merged worktrees (silent, runs in background):**

Navigate to the repository root, then run `bash ./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh cleanup-merged`. Report cleanup results.

**Check for knowledge-base directory and load context:**

If `knowledge-base/` exists:

1. Read `AGENTS.md` if it exists — apply project conventions during implementation
2. If `# Project Constitution` heading is NOT already in context, read `knowledge-base/project/constitution.md` — apply principles during implementation. Skip if already loaded (e.g., from a preceding plan).
3. Detect feature from current branch (`feat-<name>` pattern)
4. Read `knowledge-base/project/specs/feat-<name>/tasks.md` if it exists — use as work checklist alongside `task_tracker`
5. Announce: "Loaded constitution and tasks for `feat-<name>`"

If `knowledge-base/` does NOT exist, continue with standard work flow (use input document only).

### Phase 0.5: Pre-Flight Checks

Run these checks before proceeding to Phase 1. A FAIL blocks execution with a remediation message. A WARN displays and continues. If all checks pass, proceed silently.

**Environment checks:**

1. Run `git branch --show-current`. If empty (detached HEAD), FAIL: "Detached HEAD state — checkout a feature branch or create a worktree." If on default branch (main or master), FAIL: "On default branch — create a worktree before starting work."
2. Run `pwd`. If the path does NOT contain `.worktrees/`, WARN: "Not in a worktree directory."
3. Run `git status --short`. If non-empty, WARN: "Uncommitted changes detected."
4. Run `git stash list`. If non-empty, WARN: "Stashed changes found."

**Scope checks:**

5. If a plan file path was provided (ends in `.md` or starts with a path-like pattern), verify it exists and is readable. If not, FAIL: "Plan file not found."
6. Run `git diff --name-only HEAD...origin/main` to identify files that diverged. If non-empty, WARN: "Branch has diverged from main in [N] files."
7. If a plan file was provided, scan for a `## Domain Review` or `## UX Review` heading. If NEITHER heading found, scan for UI file patterns (page.tsx, layout.tsx, .jsx, .vue, .svelte, .astro). If UI patterns found, WARN: "Plan references UI files but has no Domain Review section. Consider running the plan skill first."

**Design artifact checks:**

8. Check if prior phases produced design artifacts. Search for design files matching the feature name. If design artifacts exist AND tasks include UI implementation, store artifact paths as `DESIGN_ARTIFACTS` for Phase 2.

**Specialist review checks:**

9. If a plan file with a `## Domain Review` section has a `### Product/UX Gate` subsection, check whether recommended specialists are accounted for. If missing specialists are found, use the `delegate` tool to invoke each missing specialist agent. After each specialist completes, commit the output: `git add <files> && git commit -m "wip: <specialist-name> artifacts for <feature-name>"`

**On FAIL:** Display the failure message with remediation steps and stop.
**On WARN only:** Display all warnings together and proceed.
**On all pass:** Proceed silently.

### Phase 1: Quick Start

**Pipeline detection:** If the input contains a file path (ends in `.md` or matches a path-like pattern), this skill is running in **pipeline mode** (invoked by another orchestrator). In pipeline mode, skip all interactive approval gates. If the input is empty or plain text, this is **interactive mode** — keep the approval gates.

1. **Read Plan and Clarify**

   - Read the work document completely
   - Review any references or links provided
   - Verify the plan does not contradict conventions in AGENTS.md and constitution.md
   - **Interactive mode only:** If anything is unclear, ask clarifying questions now. Get user approval to proceed.
   - **Pipeline mode:** Skip questions, proceed directly.

2. **Setup Environment**

   Check the current branch via `git branch --show-current`. Determine the default branch.

   **If already on a feature branch:**
   - **Interactive mode only:** Ask: "Continue working on `[current_branch]`, or create a new branch?"
   - **Pipeline mode:** Continue on current branch.

   **If on the default branch**, create a worktree:

   ```bash
   bash ./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh --yes create feature-branch-name
   ```

   Then `cd` into the worktree path.

3. **Create Task List (TDD-First Structure)**

   Use the `task_tracker` tool to create tasks structured as RED/GREEN/REFACTOR units:

   - For each feature requirement with testable behavior:
     - **RED task**: "Write failing test for [feature]"
     - **GREEN task**: "Implement [feature] to pass tests"
   - Infrastructure-only tasks (config, CI, scaffolding) are exempt from RED/GREEN pairing
   - Place a final "Run full test suite and lint" task at the end

   **Anti-pattern to avoid:** `[implement A, implement B, ..., write tests, lint]`. Correct: `[RED: test A, GREEN: implement A, RED: test B, GREEN: implement B, ..., lint]`.

### Phase 2: Execute

1. **Execution Mode Selection** (HARD GATE — must complete before executing ANY task)

   Analyze independence first, select the execution tier, then begin.

   **Step 0: Tier 0 pre-check (Lifecycle Parallelism)**

   Read the plan. Does this plan have distinct code and test workstreams with non-overlapping file scopes?

   - If yes (interactive mode): offer Tier 0
   - If yes (pipeline mode): auto-select Tier 0
   - If declined or ineligible: fall through to Step 1

   **Read `.plugin/skills/work/references/work-lifecycle-parallel.md` now** for the full Tier 0 protocol. If Tier 0 executes, proceed to Phase 3 after completion. If declined, fall through.

   ---

   **Step 1: Analyze independence**

   Read the task list. Identify tasks with no dependencies that reference different files. Count independent tasks.

   If fewer than 3 independent tasks: skip to **Tier C: Sequential**.
   If 3+ independent tasks: proceed through tiers A → B → C.

   **Pipeline mode override:** Auto-select Tier 0 if eligible. If ineligible, skip Tier A and auto-accept Tier B. Fall through to Tier C if < 3 independent tasks.

   ---

   **Tier A: Agent Teams** (highest capability, ~7x token cost)

   **Read `.plugin/skills/work/references/work-agent-teams.md` now** for the full protocol. If declined, fall through to Tier B.

   ---

   **Tier B: Subagent Fan-Out** (fire-and-gather, moderate cost)

   **Read `.plugin/skills/work/references/work-subagent-fanout.md` now** for the full protocol. If declined, fall through to Tier C.

   ---

   **Tier C: Sequential** (default)

   Proceed to the task execution loop below.

2. **Task Execution Loop**

   **Design Artifact Gate (before first UI task):** If `DESIGN_ARTIFACTS` was set in Phase 0.5, use the `delegate` tool to spawn the `ux-design-lead` agent to produce an implementation brief. Do not write markup until the brief is received. Commit the brief before proceeding.

   For each task in priority order:

   - Mark task as `in_progress` using `task_tracker`
   - Read any referenced files from the plan
   - If task creates UI/pages: verify implementation brief exists (HARD GATE)
   - **TDD GATE:** If a GREEN task has no preceding RED task with a passing test, write the test first
   - Implement the change
   - Run tests after each change
   - Mark task as `done` using `task_tracker`

3. **Incremental Commits**

   Commit after each logical unit of work:

   | Commit-worthy | NOT commit-worthy |
   |---|---|
   | Feature module implemented + tests pass | Half a function written |
   | Bug fix verified | "It compiles but I haven't tested" |
   | Refactoring complete, tests green | Refactoring mid-step |
   | UX specialist produces artifacts | Specialist still generating |

   ```bash
   git add <files related to this logical unit>
   git commit -m "feat(scope): description of this unit"
   ```

4. **Follow Existing Patterns**

   - Read referenced similar code first
   - Match naming conventions exactly
   - Reuse existing components
   - Follow project coding standards (see AGENTS.md)

5. **Test Continuously**

   - **RED**: Write a failing test before implementing new behavior
   - **GREEN**: Write minimum code to make the test pass
   - **REFACTOR**: Improve code while keeping tests green
   - Run the full test suite after each cycle
   - Fix failures immediately

6. **Infrastructure Validation**

   When tasks modify files in `apps/*/infra/`:

   1. **cloud-init schema**: `cloud-init schema -c <file>` for each modified cloud-init YAML
   2. **Terraform format**: `terraform fmt -check <dir>` for each infra directory
   3. **Terraform validate**: `terraform init -backend=false && terraform validate`

7. **Track Progress**

   Keep `task_tracker` updated as you complete tasks. Note blockers. Create new tasks if scope expands.

### Phase 2.5: Research Validation Loop (knowledge-base deliverables only)

**Trigger:** This phase runs when the plan's deliverables are knowledge-base research artifacts that produce recommendations targeting other existing documents. Skip for code-only plans.

**Detection:** After Phase 2 completes, scan outputs for recommendation patterns — "should rewrite," "needs updating," "add to," "change X in Y.md." If found, enter the loop.

```text
while (recommendations exist that haven't been applied):
  1. CASCADE: Apply all recommendations to their target artifacts
  2. VALIDATE: Re-run the same research methodology against updated artifacts
  3. CHECK: Did validation surface NEW weak spots?
     - If yes → apply fixes, loop back to step 2
     - If no (at synthetic ceiling) → exit loop
  4. UPDATE BRIEF: Update the research brief with final validated results
  5. SUMMARIZE: Present founder summary
```

**Max iterations:** 3 rounds. After the third, present remaining recommendations to the user.

### Phase 3: Quality Check

1. **Run Core Quality Checks**

   ```bash
   # Run full test suite (project's test command)
   # Run linting (per AGENTS.md)
   ```

2. **Consider Reviewer Agents** (Optional, for complex/risky/large changes)

   Use the `delegate` tool to run reviewers in parallel:

   ```
   spawn: ["simplicity", "performance", "security"]
   delegate:
     simplicity: "Review changes for unnecessary complexity"
     performance: "Check for performance issues"
     security: "Scan for security vulnerabilities"
   ```

   Present findings to user and address critical issues.

3. **Final Validation**
   - All `task_tracker` tasks marked `done`
   - All tests pass
   - Linting passes
   - Code follows existing patterns
   - No console errors or warnings

### Phase 4: Handoff

Implementation is complete. Determine invocation mode.

**If invoked as part of a pipeline** (the conversation contains prior pipeline skill output): Output `## Work Phase Complete` and immediately continue to the next pipeline step.

**If invoked directly by the user:** Run the post-implementation pipeline automatically:

1. **Review** — Use the review skill to catch issues before shipping
2. **Compound** — Use the compound skill to capture learnings
3. **Ship** — Use the ship skill to commit, push, create PR, merge

---

## Key Principles

### Start Fast, Execute Faster

Get clarification once at the start, then execute. The goal is to **finish the feature**, not create perfect process.

### The Plan is Your Guide

Work documents should reference similar code and patterns. Load references and follow them. Don't reinvent — match what exists.

### Test As You Go

Run tests after each change, not at the end. Fix failures immediately. Continuous testing prevents big surprises.

### Quality is Built In

Follow existing patterns. Write tests for new code. Run linting before pushing.

### Ship Complete Features

Mark all tasks completed before moving on. Don't leave features 80% done. A finished feature that ships beats a perfect feature that doesn't.

## Quality Checklist

Before entering Phase 4:

- [ ] All clarifying questions asked and answered
- [ ] All `task_tracker` tasks marked `done`
- [ ] Tests pass
- [ ] New source files have corresponding test files
- [ ] Linting passes
- [ ] Code follows existing patterns

## Common Pitfalls to Avoid

- **Analysis paralysis** — Read the plan and execute
- **Skipping clarifying questions** — Ask now, not after building wrong thing
- **Ignoring plan references** — The plan has links for a reason
- **Testing at the end** — Test continuously or suffer later
- **80% done syndrome** — Finish the feature, don't move on early
- **Research without cascade-validate loop** — Phase 2.5 enforces: cascade findings → re-run validation → cascade again → update brief → present summary
- **Missing founder summary** — After research/audit work, present key findings + all files changed
