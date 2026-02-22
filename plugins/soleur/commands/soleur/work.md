---
name: soleur:work
description: Execute work plans efficiently while maintaining quality and finishing features
argument-hint: "[plan file, specification, or todo file path]"
---

# Work Plan Execution Command

Execute a work plan efficiently while maintaining quality and finishing features.

## Introduction

This command takes a work document (plan, specification, or todo file) and executes it systematically. The focus is on **shipping complete features** by understanding requirements quickly, following existing patterns, and maintaining quality throughout.

## Input Document

<input_document> #$ARGUMENTS </input_document>

## Execution Workflow

### Phase 0: Load Knowledge Base Context (if exists)

**Load project conventions:**

```bash
# Load project conventions
if [[ -f "CLAUDE.md" ]]; then
  cat CLAUDE.md
fi
```

**Clean up merged worktrees (silent, runs in background):**

Navigate to the repository root, then run `bash ./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh cleanup-merged`. Report cleanup results: how many worktrees were cleaned up, which branches remain active.

**Check for knowledge-base directory and load context:**

Check if `knowledge-base/` directory exists. If it does:

1. Read `knowledge-base/overview/constitution.md`
2. Run `git branch --show-current` to get the current branch name
3. If the branch starts with `feat-`, read `knowledge-base/specs/<branch-name>/tasks.md` if it exists

**If knowledge-base/ exists:**

1. Read `CLAUDE.md` if it exists - apply project conventions during implementation
2. Read `knowledge-base/overview/constitution.md` - apply principles during implementation
3. Detect feature from current branch (`feat-<name>` pattern)
4. Read `knowledge-base/specs/feat-<name>/tasks.md` if it exists - use as work checklist alongside TodoWrite
5. Announce: "Loaded constitution and tasks for `feat-<name>`"

**If knowledge-base/ does NOT exist:**

- Continue with standard work flow (use input document only)

### Phase 1: Quick Start

1. **Read Plan and Clarify**

   - Read the work document completely
   - Review any references or links provided in the plan
   - If anything is unclear or ambiguous, ask clarifying questions now
   - Get user approval to proceed
   - **Do not skip this** - better to ask questions now than build the wrong thing

2. **Setup Environment**

   First, check the current branch by running `git branch --show-current`. Then determine the default branch by running `git symbolic-ref refs/remotes/origin/HEAD` and extracting the branch name. If that fails, check whether `origin/main` exists (fallback to `master`).

   **If already on a feature branch** (not the default branch):
   - Ask: "Continue working on `[current_branch]`, or create a new branch?"
   - If continuing, proceed to step 3
   - If creating new, follow Option A or B below

   **If on the default branch**, you MUST create a branch before proceeding. Never edit files on the default branch -- parallel agents cause silent merge conflicts.

   **Option A: Create a new branch (default)**

   ```bash
   git pull origin [default_branch]
   git checkout -b feature-branch-name
   ```

   Use a meaningful name based on the work (e.g., `feat/user-authentication`, `fix/email-validation`).

   **Option B: Use a worktree (recommended for parallel development)**

   ```bash
   skill: git-worktree
   # The skill will create a new branch from the default branch in an isolated worktree
   ```

   Prefer worktree if other worktrees already exist or multiple features are in-flight.

3. **Create Todo List**
   - Use TodoWrite to break plan into actionable tasks
   - Include dependencies between tasks
   - Prioritize based on what needs to be done first
   - Include testing and quality check tasks
   - Keep tasks specific and completable

### Phase 2: Execute

1. **Execution Mode Selection**

   Before starting the sequential task loop, check for parallelization opportunities:

   **Step 1: Analyze independence**

   Read the TaskList. Identify tasks that have no `blockedBy` dependencies and reference
   different files or modules (no obvious file overlap). Count the independent tasks.

   If fewer than 3 independent tasks exist, skip to **Tier C: Sequential** below.

   If 3+ independent tasks exist, proceed through the tiers in order (A, then B, then C).
   Each tier either executes or falls through to the next.

   ---

   **Tier A: Agent Teams** (highest capability, ~7x token cost)

   Persistent teammates with peer-to-peer messaging for plans where tasks share context
   or integration points.

   **Step A1: Offer Agent Teams**

   Present the user with teammate count, task assignments, and cost context:

   "I found N independent tasks that could run as an Agent Team.
   This spawns persistent teammates that can coordinate via messaging (~7x token cost).

   Proposed assignments:
   - Teammate 1: [tasks]
   - Teammate 2: [tasks]
   ...

   Run as Agent Team? (Or decline to try subagent fan-out instead)"

   - If declined: fall through to Tier B
   - If accepted: continue to Step A2

   **Step A2: Activate Agent Teams and initialize**

   Enable the experimental Agent Teams feature and initialize the team:

   ```bash
   export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
   ```

   Then initialize the team directory with `spawnTeam`:

   ```text
   spawnTeam("soleur-{branch}")
   ```

   If `spawnTeam` fails (stale team exists): attempt `cleanup`, retry once.
   If retry still fails, deactivate the flag and fall through to Tier B:

   ```bash
   unset CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS
   ```

   **Step A3: Spawn teammates**

   Spawn teammates via Task tool with `team_name` parameter. Each teammate receives
   task-specific context and instructions:

   ```text
   Task general-purpose (team_name="soleur-{branch}"): "You are a teammate
   executing part of a work plan.

   BRANCH: [current branch name]
   WORKING DIRECTORY: [current working directory path]

   YOUR TASKS:
   [Task descriptions and relevant plan sections for this teammate]

   FILES YOU MAY MODIFY:
   [Explicit list of files this teammate is allowed to touch]

   INSTRUCTIONS:
   - Read CLAUDE.md and referenced files before modifying them
   - Follow existing codebase patterns and conventions
   - Write tests for new functionality
   - Run tests relevant to your changes
   - Do NOT commit -- the lead will commit after reviewing all work
   - Do NOT modify files outside the list above
   - Mark each task as completed via TaskUpdate when done"
   ```

   Assign overlapping tasks to the same teammate to prevent file conflicts.

   **Step A4: Monitor, test, commit, and shutdown**

   Lead monitors progress via `TaskList` and coordinates via `write`/`broadcast`.

   If a teammate fails: retry once via the team. If retry fails, lead completes
   that task sequentially. Other teammates continue unaffected.

   When all tasks complete:

   - Run the full test suite to verify integration
   - If tests pass: create incremental commits for the batch
   - If tests fail: fix integration issues, then commit
   - Send `requestShutdown` to all teammates
   - Run `cleanup` to remove team config and task files
   - Deactivate the experimental flag:

     ```bash
     unset CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS
     ```

   - Update TaskList to mark all completed tasks

   Then proceed to the remaining dependent tasks (if any) using the sequential loop,
   or skip directly to Phase 3 if all tasks are done.

   ---

   **Tier B: Subagent Fan-Out** (fire-and-gather, moderate cost)

   Independent subagents that execute in parallel without peer-to-peer communication.

   **Step B1: Offer subagent fan-out**

   "I found N independent tasks that could run in parallel via subagents.
   This uses more tokens but completes faster. Run in parallel?"

   - If No: fall through to Tier C
   - If Yes: continue to Step B2

   **Step B2: Group and spawn subagents**

   Group independent tasks into clusters (max 5 groups). Each group gets one Task
   general-purpose agent. Spawn all groups in parallel using a single message with
   multiple Task tool calls:

   ```text
   Task general-purpose: "You are executing part of a work plan.

   BRANCH: [current branch name]
   WORKING DIRECTORY: [current working directory path]

   YOUR TASKS:
   [Task descriptions and relevant plan sections for this group]

   REFERENCED FILES:
   [List files this group needs to read or modify]

   INSTRUCTIONS:
   - Read referenced files before modifying them
   - Follow existing codebase patterns and conventions
   - Write tests for new functionality
   - Run tests relevant to your changes
   - Do NOT commit -- the lead will commit after reviewing all work
   - Do NOT modify files outside your assigned scope
   - Report back: what you completed, files modified, any issues encountered"
   ```

   **Step B3: Collect results and integrate**

   Wait for all subagents to complete. Then:

   - Review each subagent's report for completeness and issues
   - If any subagent failed or reported issues: complete those tasks
     sequentially using the task loop below
   - Run the full test suite to verify integration across all parallel work
   - If tests pass: create an incremental commit for the parallel batch
   - If tests fail: fix integration issues, then commit
   - Update TaskList to mark all completed tasks

   Then proceed to the remaining dependent tasks (if any) using the sequential loop,
   or skip directly to Phase 3 if all tasks are done.

   ---

   **Tier C: Sequential** (default)

   Proceed to the task execution loop below.

2. **Task Execution Loop**

   For each task in priority order:

   ```text
   while (tasks remain):
     - Mark task as in_progress in TodoWrite
     - Read any referenced files from the plan
     - Look for similar patterns in codebase
     - RED: Write failing test(s) for this task's acceptance criteria
     - GREEN: Write minimum code to make the test(s) pass
     - REFACTOR: Improve code while keeping tests green
     - Run full test suite after changes
     - Mark task as completed in TodoWrite
     - Mark off the corresponding checkbox in the plan file ([ ] → [x])
     - Evaluate for incremental commit (see below)
   ```

   **Test-First Enforcement**: If the plan includes a "Test Scenarios" section, write tests for each scenario BEFORE writing implementation code. If no test scenarios exist in the plan, derive them from acceptance criteria. For infrastructure-only tasks (config, CI, scaffolding), tests may be skipped.

   **IMPORTANT**: Always update the original plan document by checking off completed items. Use the Edit tool to change `- [ ]` to `- [x]` for each task you finish. This keeps the plan as a living document showing progress and ensures no checkboxes are left unchecked.

3. **Incremental Commits**

   After completing each task, evaluate whether to create an incremental commit:

   | Commit when... | Don't commit when... |
   |----------------|---------------------|
   | Logical unit complete (model, service, component) | Small part of a larger unit |
   | Tests pass + meaningful progress | Tests failing |
   | About to switch contexts (backend → frontend) | Purely scaffolding with no behavior |
   | About to attempt risky/uncertain changes | Would need a "WIP" commit message |

   **Heuristic:** "Can I write a commit message that describes a complete, valuable change? If yes, commit. If the message would be 'WIP' or 'partial X', wait."

   **Commit workflow:**

   ```bash
   # 1. Verify tests pass (use project's test command)
   # Examples: bin/rails test, npm test, pytest, go test, etc.

   # 2. Stage only files related to this logical unit (not `git add .`)
   git add <files related to this logical unit>

   # 3. Commit with conventional message
   git commit -m "feat(scope): description of this unit"
   ```

   **Handling merge conflicts:** If conflicts arise during rebasing or merging, resolve them immediately. Incremental commits make conflict resolution easier since each commit is small and focused.

   **Note:** Incremental commits use clean conventional messages without attribution footers. The final Phase 4 commit/PR includes the full attribution.

4. **Follow Existing Patterns**

   - The plan should reference similar code - read those files first
   - Match naming conventions exactly
   - Reuse existing components where possible
   - Follow project coding standards (see CLAUDE.md)
   - When in doubt, grep for similar implementations

5. **Test Continuously**

   - **RED**: Write a failing test before implementing any new behavior
   - **GREEN**: Write the minimum code to make the test pass
   - **REFACTOR**: Improve code while keeping tests green
   - Run the full test suite after each RED/GREEN/REFACTOR cycle
   - Fix failures immediately -- never move to the next task with failing tests
   - When a class becomes hard to test (too many dependencies), extract an interface and inject dependencies. See the `/atdd-developer` skill for detailed TDD guidance.

6. **Track Progress**
   - Keep TodoWrite updated as you complete tasks
   - Note any blockers or unexpected discoveries
   - Create new tasks if scope expands
   - Keep user informed of major milestones

### Phase 3: Quality Check

1. **Run Core Quality Checks**

   Always run before submitting:

   ```bash
   # Run full test suite (use project's test command)
   # Examples: bin/rails test, npm test, pytest, go test, etc.

   # Run linting (per CLAUDE.md)
   # Use linting-agent before pushing to origin
   ```

2. **Consider Reviewer Agents** (Optional)

   Use for complex, risky, or large changes:

   - **code-simplicity-reviewer**: Check for unnecessary complexity
   - **kieran-rails-reviewer**: Verify Rails conventions (Rails projects)
   - **performance-oracle**: Check for performance issues
   - **security-sentinel**: Scan for security vulnerabilities

   Run reviewers in parallel with Task tool:

   ```text
   Task(code-simplicity-reviewer): "Review changes for simplicity"
   Task(kieran-rails-reviewer): "Check Rails conventions"
   ```

   Present findings to user and address critical issues.

3. **Final Validation**
   - All TodoWrite tasks marked completed
   - All tests pass
   - Linting passes
   - Code follows existing patterns
   - Figma designs match (if applicable)
   - No console errors or warnings

### Phase 4: Ship It

Delegate to the `/ship` skill, which enforces the complete shipping checklist:

```text
skill: ship
```

The `/ship` skill handles all shipping steps in order:

1. Validate artifact trail (brainstorms, specs, plans committed)
2. Capture learnings via `/soleur:compound` (asks if not already run)
3. Verify documentation (README counts, tables)
4. Version bump (plugin.json + CHANGELOG + README triad)
5. Run tests
6. Push and create PR (with screenshots for UI changes)
7. Post-merge cleanup (worktree removal)

**Do not skip this delegation.** The `/ship` skill exists specifically to prevent missed steps like forgotten `/compound` runs, uncommitted artifacts, and missing version bumps. Running Phase 4 manually is how steps get skipped.

---

## Key Principles

### Start Fast, Execute Faster

- Get clarification once at the start, then execute
- Don't wait for perfect understanding - ask questions and move
- The goal is to **finish the feature**, not create perfect process

### The Plan is Your Guide

- Work documents should reference similar code and patterns
- Load those references and follow them
- Don't reinvent - match what exists

### Test As You Go

- Run tests after each change, not at the end
- Fix failures immediately
- Continuous testing prevents big surprises

### Quality is Built In

- Follow existing patterns
- Write tests for new code
- Run linting before pushing
- Use reviewer agents for complex/risky changes only

### Review Before You Ship

- Run `/soleur:review` after completing implementation
- Catches issues before they reach PR reviewers
- Faster feedback than waiting for human review
- Builds confidence that your code is solid

### Compound Your Learnings

- Run `/soleur:compound` before creating a PR
- Document debugging breakthroughs, non-obvious patterns, and framework gotchas
- Even "simple" implementations can yield valuable insights
- Future-you and teammates will thank present-you

### Ship Complete Features

- Mark all tasks completed before moving on
- Don't leave features 80% done
- A finished feature that ships beats a perfect feature that doesn't

## Quality Checklist

Before entering Phase 4, verify these Phase 2-3 items are complete:

- [ ] All clarifying questions asked and answered
- [ ] All TodoWrite tasks marked completed
- [ ] Tests pass (run project's test command)
- [ ] New source files have corresponding test files
- [ ] Linting passes (use linting-agent)
- [ ] Code follows existing patterns
- [ ] Figma designs match implementation (if applicable)

Phase 4 (`/ship`) handles the rest: `/compound`, version bump, screenshots, PR creation, and post-merge cleanup.

## When to Use Reviewer Agents

**Don't use by default.** Use reviewer agents only when:

- Large refactor affecting many files (10+)
- Security-sensitive changes (authentication, permissions, data access)
- Performance-critical code paths
- Complex algorithms or business logic
- User explicitly requests thorough review

For most features: tests + linting + following patterns is sufficient.

## Common Pitfalls to Avoid

- **Analysis paralysis** - Don't overthink, read the plan and execute
- **Skipping clarifying questions** - Ask now, not after building wrong thing
- **Ignoring plan references** - The plan has links for a reason
- **Testing at the end** - Test continuously or suffer later
- **Forgetting TodoWrite** - Track progress or lose track of what's done
- **80% done syndrome** - Finish the feature, don't move on early
- **Over-reviewing simple changes** - Save reviewer agents for complex work
