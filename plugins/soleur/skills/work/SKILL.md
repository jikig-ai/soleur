---
name: work
description: "This skill should be used when executing work plans efficiently while maintaining quality and finishing features."
---

# Work Plan Execution Command

Execute a work plan efficiently while maintaining quality and finishing features.

## Introduction

This command takes a work document (plan, specification, or todo file) and executes it systematically. The focus is on **shipping complete features** by understanding requirements quickly, following existing patterns, and maintaining quality throughout.

## Headless Mode Detection

If `$ARGUMENTS` contains `--headless`, set `HEADLESS_MODE=true`. Strip `--headless` from `$ARGUMENTS` before processing the remainder as a plan path. Pipeline mode (file path detection) already covers all prompt bypasses for work's own prompts — `--headless` is only needed for forwarding to child skills in Phase 4.

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

1. Run `git branch --show-current` to get the current branch name
2. If the branch starts with `feat-`, read `knowledge-base/project/specs/<branch-name>/tasks.md` if it exists

**If knowledge-base/ exists:**

1. Read `CLAUDE.md` if it exists - apply project conventions during implementation
2. If `# Project Constitution` heading is NOT already in context, read `knowledge-base/project/constitution.md` - apply principles during implementation. Skip if already loaded (e.g., from a preceding `/soleur:plan`).
3. Detect feature from current branch (`feat-<name>` pattern)
4. Read `knowledge-base/project/specs/feat-<name>/tasks.md` if it exists - use as work checklist alongside TodoWrite
5. Announce: "Loaded constitution and tasks for `feat-<name>`"

**If knowledge-base/ does NOT exist:**

- Continue with standard work flow (use input document only)

### Phase 0.5: Pre-Flight Checks

Run these checks before proceeding to Phase 1. A FAIL blocks execution with a remediation message. A WARN displays and continues. If all checks pass, proceed silently.

**Environment checks:**

1. Run `git branch --show-current`. If the result is empty (detached HEAD), FAIL: "Detached HEAD state -- checkout a feature branch or create a worktree." If the result is the default branch (main or master), FAIL: "On default branch -- create a worktree before starting work. Run: `bash ./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh feature <name>`"
2. Run `pwd`. If the path does NOT contain `.worktrees/`, WARN: "Not in a worktree directory. You can create one via `git-worktree` skill in Phase 1."
3. Run `git status --short`. If output is non-empty, WARN: "Uncommitted changes detected. Consider committing or stashing before starting new work."
4. Run `git stash list`. If output is non-empty, WARN: "Stashed changes found. Review stash list to avoid forgotten work."

**Scope checks:**

5. If a plan file path was provided as input (ends in `.md` or starts with a path-like pattern), verify it exists and is readable. If not, FAIL: "Plan file not found at the specified path." If the input appears to be a text description rather than a file path, WARN: "Input appears to be a description, not a file path. Scope validation limited."
6. Run `git diff --name-only HEAD...origin/main` to identify files that diverged between this branch and main. If output is non-empty, WARN: "Branch has diverged from main in [N] files: [file list]. Consider merging main before starting." If the git command fails (e.g., offline, no remote), skip this check silently.
7. If a plan file was provided (check 5 passed), scan for a `## Domain Review` or `## UX Review` heading (both are accepted for backward compatibility). If NEITHER heading found: scan the plan content for UI file patterns (page.tsx, layout.tsx, template.tsx, .jsx, .vue, .svelte, .astro, +page.svelte, app/, pages/, components/, layouts/, routes/). If UI patterns found, WARN: "Plan references UI files but has no Domain Review section. Consider running /soleur:plan to add domain review before implementing." If either heading IS present: pass silently.

**Design artifact checks:**

8. Check if prior phases produced design artifacts. Search the repo for design files matching the feature name: `git ls-files '*.pen' '*.fig' '*.sketch' | grep -i "<feature-name>"` and check `knowledge-base/product/design/` for related files. If design artifacts exist AND the current tasks include UI/page implementation (patterns: `.njk`, `.html`, `.tsx`, `.jsx`, `.vue`, `.svelte`, `pages/`, `components/`, `layouts/`): store the artifact paths as `DESIGN_ARTIFACTS` for use in Phase 2.

**Specialist review checks:**

9. If a plan file was provided (check 5 passed) and a `## Domain Review` section exists with a `### Product/UX Gate` subsection: check whether domain leader assessments recommended specialists (copywriter, ux-design-lead, conversion-optimizer) that are NEITHER listed in `**Agents invoked:**` NOR in `**Skipped specialists:**`. If the `**Decision:**` field says `reviewed (partial)`, WARN: "Domain review was partial — some specialist agents failed. Review the Domain Review section before proceeding." If any recommended specialist is missing from both fields: **Interactive mode:** FAIL with message listing the missing specialists and options: (a) "Run \<specialist\> now" — invoke the specialist agent directly, update the plan file's `**Agents invoked:**` field, then continue; (b) "Skip with justification" — prompt for reason, add to the plan file's `**Skipped specialists:**` field, then continue. **Pipeline mode (headless/one-shot):** auto-invoke each missing specialist agent. If the agent succeeds, add to `**Agents invoked:**`. If it fails, add to `**Skipped specialists:**` with note `(auto-skipped — agent unavailable in pipeline)` and WARN. Do not FAIL in pipeline mode. If all recommended specialists are accounted for (in `**Agents invoked:**` or `**Skipped specialists:**`): pass silently.

   **UX artifact commit checkpoint (after each specialist in check 9):** After each specialist agent completes successfully (interactive "Run specialist now" or pipeline auto-invoke), commit the output:

   1. Run `git status --short` to discover new/modified files from the specialist
   2. Stage specialist output files: `git add <discovered files>`
   3. Commit: `git commit -m "wip: <specialist-name> artifacts for <feature-name>"`

   Each specialist gets its own commit so partial progress is preserved if a later specialist fails. Do not commit on specialist failure.

**On FAIL:** Display the failure message with remediation steps and stop. Do not proceed to Phase 1.

**On WARN only:** Display all warnings together and proceed to Phase 1.

**On all pass:** Proceed silently to Phase 1.

### Phase 1: Quick Start

**Pipeline detection:** If `$ARGUMENTS` contains a file path (ends in `.md` or matches a path-like pattern), this skill is running in **pipeline mode** (invoked by one-shot or another orchestrator). In pipeline mode, skip all interactive approval gates and proceed directly. If `$ARGUMENTS` is empty or a plain text description, this is **interactive mode** — keep the approval gates below.

1. **Read Plan and Clarify**

   - Read the work document completely
   - Review any references or links provided in the plan
   - Before proceeding, verify the plan does not contradict conventions in AGENTS.md and constitution.md: file format (markdown tables not YAML), kebab-case naming, directory structure (agents recurse, skills flat), required frontmatter fields, shell script conventions
   - **Interactive mode only:** If anything is unclear or ambiguous, ask clarifying questions now. Get user approval to proceed. **Do not skip this** - better to ask questions now than build the wrong thing.
   - **Pipeline mode:** Skip clarifying questions and approval. Proceed directly to step 2.

2. **Setup Environment**

   First, check the current branch by running `git branch --show-current`. Then determine the default branch by running `git symbolic-ref refs/remotes/origin/HEAD` and extracting the branch name. If that fails, check whether `origin/main` exists (fallback to `master`).

   **If already on a feature branch** (not the default branch):
   - **Interactive mode only:** Ask: "Continue working on `[current_branch]`, or create a new branch?"
   - **Pipeline mode:** Continue on current branch without asking.
   - If continuing, proceed to step 3
   - If creating new, follow the worktree creation instructions below

   **If on the default branch**, you MUST create a worktree before proceeding. Never edit files on the default branch -- parallel agents cause silent merge conflicts, and this repo uses `core.bare=true` where `git pull` and `git checkout` are unavailable.

   Create a worktree for the new feature:

   ```bash
   bash ./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh --yes create feature-branch-name
   ```

   Then `cd` into the worktree path printed by the script. The worktree manager handles bare-repo detection, branch creation from latest origin/main, .env copying, and dependency installation.

   Use a meaningful name based on the work (e.g., `feat-user-authentication`, `fix-email-validation`).

3. **Create Todo List (TDD-First Structure)**

   Structure tasks as RED/GREEN/REFACTOR units, not as "implement everything, then test":

   - For each feature requirement with Acceptance Criteria or testable behavior:
     - Create a **RED task**: "Write failing test for [feature]" — the test file with at least one failing test
     - Create a **GREEN task**: "Implement [feature] to pass tests" — blocked by its RED task
     - Group these as a TDD unit with `blockedBy` dependency (GREEN blocked by RED)
   - Infrastructure-only tasks (config files, CI, scaffolding, legal docs) are exempt from RED/GREEN pairing — create them as standalone tasks
   - Place a final "Run full test suite and lint" task at the end, blocked by all other tasks
   - Keep tasks specific and completable

   **Anti-pattern to avoid:** Creating a task list like `[implement A, implement B, implement C, ..., write tests, lint]`. This structure guarantees TDD violation because the agent executes tasks in order. The correct structure is `[RED: test A, GREEN: implement A, RED: test B, GREEN: implement B, ..., lint]`.

   **Post-creation validation (HARD GATE):** After creating all tasks, scan the task list for any non-exempt implementation task (GREEN) that does NOT have a corresponding RED test task in its `blockedBy` list. If found, restructure the task list before proceeding. Do not start Phase 2 with an invalid task structure. **Why:** In PR #2428, the agent created flat tasks ("Fix X", "Write tests") and started implementation before tests — the user had to intervene and force a restructure. The anti-pattern instruction was not enough without a validation gate.

### Phase 2: Execute

1. **Execution Mode Selection** (HARD GATE — must complete before executing ANY task)

   **Do NOT execute any task before completing this analysis.** Analyze independence first, select the execution tier, then begin. Starting sequential execution "because the first tasks feel simple" is a workflow violation — it forfeits parallelization savings on the remaining tasks.

   Before starting the sequential task loop, check for parallelization opportunities:

   **Step 0: Tier 0 pre-check (Lifecycle Parallelism)**

   Read the plan. Apply a single judgment: "Does this plan have distinct code and test workstreams that can be assigned to separate agents with non-overlapping file scopes?"

   - If yes (interactive mode): offer Tier 0 to the user
   - If yes (pipeline mode): auto-select Tier 0 without prompting
   - If declined or ineligible: fall through to Step 1 below

   **Read `plugins/soleur/skills/work/references/work-lifecycle-parallel.md` now** for the full Tier 0 protocol (offer/auto-select, generate contract, spawn 2 agents, collect/commit, test-fix-loop, docs). If Tier 0 executes, proceed directly to Phase 3 after completing Step 06 of the protocol. If declined, fall through to Step 1.

   ---

   **Step 1: Analyze independence**

   Read the TaskList. Identify tasks that have no `blockedBy` dependencies and reference
   different files or modules (no obvious file overlap). Count the independent tasks.

   If fewer than 3 independent tasks exist, skip to **Tier C: Sequential** below.

   If 3+ independent tasks exist, proceed through the tiers in order (A, then B, then C).
   Each tier either executes or falls through to the next.

   ---

   **Pipeline mode override:** If running in pipeline mode (plan file argument detected in Phase 1), auto-select Tier 0 if eligible (Step 0 above). If Tier 0 is ineligible, skip Tier A entirely and auto-accept Tier B without prompting. Do not present "Run as Agent Team?" or "Run in parallel?" questions -- proceed directly to Step B2 of the Subagent Fan-Out protocol if 3+ independent tasks exist, otherwise fall through to Tier C.

   ---

   **Tier A: Agent Teams** (highest capability, ~7x token cost)

   **Read `plugins/soleur/skills/work/references/work-agent-teams.md` now** for the full Agent Teams protocol (offer, activate, spawn teammates, monitor/commit/shutdown). If declined or failed, fall through to Tier B.

   ---

   **Tier B: Subagent Fan-Out** (fire-and-gather, moderate cost)

   **Read `plugins/soleur/skills/work/references/work-subagent-fanout.md` now** for the full Subagent Fan-Out protocol (offer, group/spawn, collect/integrate). If declined, fall through to Tier C.

   ---

   **Tier C: Sequential** (default)

   Proceed to the task execution loop below.

2. **Task Execution Loop**

   **Design Artifact Gate (before first UI task):** If `DESIGN_ARTIFACTS` was set in Phase 0.5, spawn the `ux-design-lead` agent with the artifact paths and ask it to produce an **implementation brief** (see ux-design-lead "Wireframe-to-Implementation Handoff" workflow). The brief is a structured description of every section, its content, and its layout — this becomes the binding input for all UI tasks. Do not write any markup until the brief is received.

   **UX artifact commit checkpoint (after Design Artifact Gate):** After the implementation brief is received, commit before proceeding to UI tasks:

   1. Run `git status --short` to discover the implementation brief and any generated design files
   2. Stage output files: `git add <discovered files>`
   3. Commit: `git commit -m "wip: UX implementation brief for <feature-name>"`

   This checkpoint ensures the implementation brief survives session crashes.

   For each task in priority order:

   ```text
   while (tasks remain):
     - Mark task as in_progress in TodoWrite
     - Read any referenced files from the plan
     - If task creates UI/pages: verify implementation brief exists (HARD GATE)
     - TDD GATE: (see below)
     - Look for similar patterns in codebase
     - RED: Write failing test(s) for this task's acceptance criteria
     - GREEN: Write minimum code to make the test(s) pass
     - REFACTOR: Improve code while keeping tests green
     - Run full test suite after changes
     - Mark task as completed in TodoWrite
     - Mark off the corresponding checkbox in the plan file ([ ] → [x])
     - Evaluate for incremental commit (see below)
   ```

   **TDD Gate (HARD GATE):** Before writing ANY implementation code for a task, determine if the task has testable behavior:

   1. **Check:** Does the plan have a "Test Scenarios" or "Acceptance Criteria" section that covers this task? If yes, this task requires test-first.
   2. **Exempt:** Infrastructure-only tasks (config files, CI workflows, scaffolding directories, dependency installs) are exempt. If the task only creates/modifies config, it skips to Infrastructure Validation below.
   3. **Enforce:** For non-exempt tasks, write the failing test file FIRST. The test must:
      - Import the component/function/module that will be created (the import will fail — that is correct)
      - Assert the specific behavior from the acceptance criteria
      - Be runnable via the project's test command (even if it fails due to missing implementation)
   4. **Verify RED:** Run the test. It must fail (missing module, assertion failure, etc.). If it passes, the test is not testing new behavior — rewrite it. **For gating/sequencing primitives (semaphores, locks, queues, ordering guarantees), the test must distinguish gate-absent from gate-present: add an intermediate-state assertion that would fail without the primitive (e.g., `count === 2` while two slots are held) in addition to the final-state assertion. A test that passes identically with and without the primitive isn't testing the primitive.** See `knowledge-base/project/learnings/test-failures/2026-04-18-red-verification-must-distinguish-gated-from-ungated.md`.
   5. **Only then:** Write the minimum implementation to make the test pass (GREEN).
   6. **Refactor:** Improve code while keeping tests green.

   Skipping this gate — writing implementation before tests — is a workflow violation equivalent to committing directly to main. The rationalization "this is simple enough to not need test-first" is exactly the reasoning TDD is designed to prevent.

   - When adding MCP tools to an existing registration block in agent-runner.ts, verify each tool's prerequisites are independent of the block's guard condition. Write a test that validates the new tool works WITHOUT the existing block's prerequisites (e.g., Plausible tools work without GitHub installation).

   - When adding route handler tests that require `vi.mock()`, create a separate test file from existing unit tests that import the real module. Vitest hoists all `vi.mock()` calls to the top of the file, clobbering real imports for the entire file regardless of describe block scope.
   - When creating test files with `vi.mock()` factories that reference shared variables, use `vi.hoisted()` from the start -- vitest hoists `vi.mock` to the top of the file before `const`/`let` declarations execute.
   - When mocking `child_process.spawn`, `fetch`, or any constructor returning an event-emitter-like object, use `mockImplementation(() => factory(...))` rather than `mockReturnValue(factory(...))`. `mockReturnValue` evaluates the factory eagerly at test-setup time; any `queueMicrotask` / `setTimeout` / `setImmediate` scheduled inside the factory fires BEFORE the SUT attaches its listeners, producing empty event data or an "uncaught error" test timeout. See `knowledge-base/project/learnings/test-failures/2026-04-17-vitest-mockReturnValue-eager-factory-async-event-race.md`.
   - To prove a cache-hit skips work (not just that the response status is correct), wrap the real implementation in a spy via `vi.importActual` rather than stubbing the return value: `vi.mock("@/module", async () => { const actual = await vi.importActual(...); return { ...actual, expensiveFn: (...args) => { spy(...args); return actual.expensiveFn(...args); } })`. Stubbed returns break any downstream behavior that depends on the real output (hash-match, SQL row shape, etc.); wrapping preserves the contract while exposing call counts for assertions like `expect(spy).toHaveBeenCalledTimes(1)` across a HEAD+GET sequence. **Why:** In PR #2515, verifying that HEAD populates `shareHashVerdictCache` so a follow-up GET skips the SHA-256 drain required counting `hashStream` calls, not stubbing its return — a stubbed return would have broken the post-drain hash-equality check and masked the very regression the test was meant to catch.
   - When testing decorative images (alt="") with happy-dom, use container.querySelector instead of screen.getAllByRole("img", { hidden: true }) -- happy-dom excludes presentational elements from role queries even with hidden: true.
   - When adding `sessionStorage` usage to React components, ensure the component's test file includes `sessionStorage.clear()` in its `beforeEach` block. Shared jsdom environments leak sessionStorage between tests, causing ordering-dependent failures.
   - When asserting on `vi.getTimerCount()`, remember that `vi.useFakeTimers()` mocks every timer-like API by default — including `requestAnimationFrame`, `setImmediate`, `queueMicrotask`, `requestIdleCallback`. The count is a SUM across all fake timer types, not just `setTimeout`. Prefer stability assertions (`count before N extra calls === count after`) over magnitude assertions (`count === 1`) so refactors that add a well-behaved rAF or microtask don't falsely read as leaks. See `knowledge-base/project/learnings/test-failures/2026-04-17-vitest-getTimerCount-counts-requestAnimationFrame.md`.
   - When a component exports an interface that a test harness consumes (e.g., `ChatInputQuoteHandle`), have the test import it via `type X = ExportedInterface` — never shadow with a local duplicate. Duplicate interfaces silently drift when the exported type gains a method; the `tsc --noEmit` failure surfaces only at build time.
   - When adding a new npm dependency, check the installed major version (`node -e "console.log(require('<pkg>/package.json').version)"`) and read the type definitions before using API from docs or training data. Library APIs change across major versions (e.g., `react-resizable-panels` v4 uses `Group`/`Separator`/`orientation`/`useDefaultLayout`, not v2's `PanelGroup`/`PanelResizeHandle`/`direction`/`autoSaveId`).
   - For sizing APIs from third-party libraries, always pass **explicit units as strings** (e.g., `"18%"`, `"100px"`, `"1rem"`) rather than bare numbers. Docstrings may claim a default unit but runtime parsers often treat numbers as pixels. **Why:** `react-resizable-panels` v4 doc said "Percentage of the parent Group (0..100)" for numeric sizes, but the runtime treated `18` as 18px, producing a ~18px-wide sidebar in production. Explicit units make intent visible at the call site and survive library version upgrades.

   **Test environment setup:** If the project's test runner cannot run the type of test needed (e.g., React component tests require jsdom but vitest is configured for node), set up the test environment BEFORE starting the task. This is part of RED — the test infrastructure must exist for the test to fail properly.

   - When configuring bun preload scripts that register DOM globals (e.g., happy-dom), use dynamic `await import()` for all subsequent dependencies — static ES imports are hoisted before any imperative code, causing libraries like @testing-library/react to initialize without DOM globals. See `knowledge-base/project/learnings/test-failures/2026-04-03-bun-test-dom-preload-execution-order.md`.
   - When uploading files via Playwright MCP, save files to repo-accessible paths (not `/tmp/`). Playwright MCP restricts file access to the repo root. When Google Search Console offers Cloudflare auto-verification, prefer "Any DNS provider" manual flow — the popup OAuth flow opens an external tab that crashes the Playwright browser context.
   - After any `Write` whose hook output emits a warning (security, style, rule), immediately `Read` the file to verify the full content landed. PreToolUse hooks that print error output but return non-blocking status can still cause partial writes — detecting this only when tests fail wastes a debug round. See `knowledge-base/project/learnings/2026-04-15-kb-share-binary-files-lifecycle.md`.
   - When adding source-reading regex tests (`readFileSync(path)` + `expect(src).toMatch(...)`) as a negative-space regression gate after an extraction, put them in a standalone `*.test.ts` file — never add them to an existing test file that already mocks `node:fs` or `node:path`. The existing `vi.mock("node:fs", ...)` factory likely omits `readFileSync`, and the new test will fail at collection with "No `readFileSync` export is defined" before any assertion runs. Also trim the gate to only the assertion that cannot be expressed behaviorally — usually the negative "symbol-not-present" check. Positive assertions (import regex, await-call regex) duplicate coverage that mock-based behavioral tests already provide and are brittle to barrel re-exports, aliases, and whitespace. See `knowledge-base/project/learnings/best-practices/2026-04-17-regex-on-source-delegation-tests-trim-to-negative-space.md`.

   **IMPORTANT**: Always update the original plan document by checking off completed items. Use the Edit tool to change `- [ ]` to `- [x]` for each task you finish. This keeps the plan as a living document showing progress and ensures no checkboxes are left unchecked.

3. **Incremental Commits**

   After completing each task, evaluate whether to create an incremental commit:

   | Commit when... | Don't commit when... |
   |----------------|---------------------|
   | Logical unit complete (model, service, component) | Small part of a larger unit |
   | Tests pass + meaningful progress | Tests failing |
   | About to switch contexts (backend → frontend) | Purely scaffolding with no behavior |
   | About to attempt risky/uncertain changes | Would need a "WIP" commit message (exception: UX artifacts use `wip:` prefix) |
   | UX specialist produces artifacts (wireframes, copy, brief) | Specialist is still generating (mid-output) |
   | Domain leader review cycle completes (feedback applied) | Review feedback not yet incorporated |
   | Brand guide alignment pass completes | Alignment still in progress |

   - When lefthook hangs during commit in a worktree (common with `core.bare=true` repos), verify typecheck and tests pass manually, then use `LEFTHOOK=0 git commit`. Always check for stalled lefthook processes (`pgrep -fa lefthook`) before retrying.

   **Heuristic:** "Can I write a commit message that describes a complete, valuable change? If yes, commit. If the message would be 'WIP' or 'partial X', wait."

   **UX artifact heuristic:** "Did a specialist just produce or revise artifacts? If yes, commit with `wip: UX <description> for feat-X`. UX artifacts are high-effort and low-recoverability -- err on the side of committing too often rather than too rarely."

   The `wip:` prefix is intentional -- UX artifacts are valuable at every revision stage, and WIP commits are squashed on merge with no impact on final git history. Do not run compound before UX WIP commits -- compound runs once in Phase 4.

   **Compound-before-commit scope:** AGENTS.md Workflow Gates says "Before every commit, run compound." Within this skill, that rule applies to the **final Phase 4 commit** (the one that closes the feature), not to Phase 2 incremental commits. Running compound per incremental commit is recursive (compound creates commits) and defeats the point of incremental checkpoints. A single compound at Phase 4 covers the whole feature's session-error inventory and learnings.

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
   - **Before writing a new format, date, or util helper in any app, `ls` + grep the app's canonical `lib/` directory (e.g., `apps/web-platform/lib/`) for equivalents.** Canonical helpers are often single-purpose small files named by verb (`relative-time.ts`, `format-currency.ts`); typecheck and tests will not catch duplicated logic. See `knowledge-base/project/learnings/2026-04-17-grep-lib-before-writing-format-helpers.md`.
   - **Before writing data-layer tests that use new PostgREST operators, read the shared mock helper (e.g., `apps/web-platform/test/helpers/mock-supabase.ts`) to confirm it covers every operator the code under test uses.** If not, extend it at the START of Phase 2, not after the first cryptic test failure.
   - **When extracting a pure reducer out of a React hook, migrate ALL companion state (refs the reducer reads or writes) to the reducer's state boundary in the same change.** A half-extraction — pure function plus mutable ref inside a `setState` updater — advertises purity the call site doesn't honor and recreates the StrictMode/concurrent-rendering hazard the extraction was meant to eliminate. See `knowledge-base/project/learnings/best-practices/2026-04-14-pure-reducer-extraction-requires-companion-state-migration.md`.

5. **Test Continuously**

   - **RED**: Write a failing test before implementing any new behavior
   - **GREEN**: Write the minimum code to make the test pass
   - **REFACTOR**: Improve code while keeping tests green
   - Run the full test suite after each RED/GREEN/REFACTOR cycle. When running test suites via Bash, always capture both failure details AND summary in a single run — use `grep -E "(FAIL|ERROR|Test Files|Tests )"` or `| tail -30`, never `| tail -10` which discards failure names and forces a wasteful second run. **Why:** In PR #2430, `| tail -10` discarded failing test names, requiring a full re-run just to identify which 2 of 1580 tests failed.
   - Fix failures immediately -- never move to the next task with failing tests
   - When a class becomes hard to test (too many dependencies), extract an interface and inject dependencies. See the `/atdd-developer` skill for detailed TDD guidance.

6. **Infrastructure Validation**

   When any task modifies files in `apps/*/infra/`, run these checks after each change (in addition to or instead of the app test suite):

   1. **cloud-init schema**: For each modified `cloud-init.yml`:
      `cloud-init schema -c <file>` -- validates YAML syntax AND cloud-init schema in one step. Warnings about missing datasource are expected; only non-zero exit codes are failures. If `cloud-init` is not installed locally, warn and continue.

   2. **Terraform format**: For each infra directory with modified `.tf` files:
      `terraform fmt -check <dir>` -- exit 0 means formatted; exit 3 means violations. Fix with `terraform fmt <dir>`.

   3. **Terraform validate**: For each infra directory with modified `.tf` files:
      `terraform init -backend=false` then `terraform validate` -- catches HCL syntax errors and undefined references without requiring provider credentials.

   These checks replace the "tests may be skipped" exemption for infra files. If any check fails, fix before proceeding to the next task.

   - When cloud-init has `lifecycle { ignore_changes = [user_data] }`, changes to cloud-init templates are never applied to existing servers. Use a `terraform_data` provisioner with `remote-exec` to bridge the gap. Verify systemd services use `EnvironmentFile=` directives (not `/etc/environment`) for token injection.
   - When fixing syscall-level issues in Docker containers, test with `--privileged` first to establish a working baseline, then remove privileges one at a time. Docker's seccomp `includes.caps` is compile-time (evaluated when building BPF filter), not runtime -- processes gaining capabilities inside user namespaces do NOT gain access to capability-gated seccomp rules.
   - When a `terraform_data` provisioner writes a systemd unit or config file via `remote-exec` heredoc, extract the content to a standalone file and use `file()` in both `triggers_replace` and a `file` provisioner. Inline heredoc strings desync from the trigger hash -- partial strings in `triggers_replace` silently skip re-provisioning when the unit content changes.

7. **Track Progress**
   - Keep TodoWrite updated as you complete tasks
   - Note any blockers or unexpected discoveries
   - Create new tasks if scope expands
   - Keep user informed of major milestones

### Phase 2.5: Research Validation Loop (knowledge-base deliverables only)

**Trigger:** This phase runs when the plan's deliverables are knowledge-base research artifacts (findings, analysis, audits, research briefs) that produce recommendations targeting other existing documents. Skip for code-only plans.

**Detection:** After Phase 2 completes, scan the outputs for recommendation patterns — "should rewrite," "needs updating," "add to," "change X in Y.md," or any finding that names a specific target file. If found, enter the loop.

**The loop:**

```text
while (recommendations exist that haven't been applied):
  1. CASCADE: Apply all recommendations to their target artifacts
     - Rewrite questions in interview guides
     - Update framings in brand guide
     - Add alternatives to pricing strategy
     - Any finding that names a file → edit that file
  2. VALIDATE: Re-run the same research methodology against updated artifacts
     - Use the same personas/parameters as the original run
     - Produce a before/after comparison (original → current)
  3. CHECK: Did the validation surface NEW weak spots or recommendations?
     - If yes → apply fixes, loop back to step 2
     - If no (at synthetic ceiling) → exit loop
  4. UPDATE BRIEF: Update the research brief with final validated results
     - Executive summary reflects current state, not original findings
     - Recommendations marked as "Applied" with results
     - Add Cascade Status section tracking all changes to all files
  5. SUMMARIZE: Present founder summary
     - Key findings table
     - All files changed table (file, what changed, before/after metrics)
     - Remaining limitations (structural, not fixable)
```

**Exit condition:** The loop exits when a validation round produces no new actionable recommendations — only structural limitations that can't be fixed by rewording (e.g., a persona's archetype inherently produces flat responses to a specific question type).

**Max iterations:** 3 rounds. If the third round still produces actionable recommendations, present them to the user rather than looping indefinitely. Synthetic-on-synthetic validation has diminishing returns.

**Why this matters:** Without this loop, research sprints produce findings that sit in briefs without updating the documents they target. The founder has to manually ask "was any action taken?" after each round. This loop makes cascade + validate + re-cascade automatic.

### Phase 3: Quality Check

1. **Run Core Quality Checks**

   Always run before submitting:

   ```bash
   # Run full test suite (use project's test command)
   # Examples: bin/rails test, npm test, pytest, go test, etc.

   # Run linting (per CLAUDE.md)
   # Use linting-agent before pushing to origin
   ```

   - **Run `npx tsc --noEmit` in the app package alongside the test suite.** Vitest type-checks test files lazily, so TS errors in tests pass the suite locally but fail CI. A standalone tsc pass catches them at the work-phase gate instead of deferring to review.
   - **When extracting enforcement logic (auth, CSRF, validation) from route files into a shared helper, update negative-space tests in the same commit.** Route-level detection must prove helper invocation AND failure early-return — not just import presence. Add direct assertions on the helper file for every invariant that moved into it. See `knowledge-base/project/learnings/best-practices/2026-04-15-negative-space-tests-must-follow-extracted-logic.md`.
   - **When adding git operations that contact remotes in Next.js API routes, include the credential helper pattern from `session-sync.ts`** (search `credential.helper`). Bare `git pull`/`git push`/`git fetch` fail silently on private repos. See `knowledge-base/project/learnings/integration-issues/kb-upload-missing-credential-helper-20260413.md`.

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

### Phase 4: Handoff

Implementation is complete. Before handing off, run the **Playwright-first audit**, then determine invocation mode.

#### Playwright-First Audit

Scan any "next steps", "setup instructions", or "to use this" text you are about to output. For each step that involves a browser action (account creation, credential generation, settings configuration, form submission, OAuth flow, portal navigation):

1. **Classify:** Is this step automatable via Playwright MCP, or is it genuinely manual (CAPTCHA, interactive OAuth consent)?
2. **If automatable:** Do not list it as a manual step. Either execute it now via Playwright MCP, or note it as "automatable via Playwright — will execute next."
3. **If genuinely manual:** Drive the flow via Playwright up to the manual gate (e.g., navigate to the OAuth consent screen), then hand off only that single interaction to the user.

If you catch yourself writing phrases like "set up X in the browser", "go to the portal and...", or "manually configure..." — stop and attempt Playwright first. This audit is mandatory; skipping it is a deviation.

#### Invocation Mode

**If invoked by one-shot** (the conversation contains `soleur:one-shot` skill output earlier): Output exactly `## Work Phase Complete` and then **immediately invoke** `skill: soleur:review` (step 4 of the one-shot sequence). Do NOT end your turn after outputting the marker — you ARE the orchestrator, so you must continue executing one-shot steps 4 through 10 in order. The marker is a progress signal, not a stopping point.

**If invoked directly by the user** (no one-shot orchestrator): Continue through the post-implementation pipeline automatically. Do NOT stop and wait — the earlier learning "Workflow Completion is Not Task Completion" applies. Run these steps in order, forwarding `--headless` if `HEADLESS_MODE=true`:

1. `skill: soleur:review` (or `skill: soleur:review --headless` if headless) — catch issues before shipping
2. `skill: soleur:resolve-todo-parallel` — resolve any review findings (no `--headless` needed; this skill has no interactive prompts)
3. `skill: soleur:compound` (or `skill: soleur:compound --headless` if headless) — capture learnings before committing
3.5. Display: "Tip: After shipping, run `/clear` to reclaim context headroom for the next task."
4. `skill: soleur:ship` (or `skill: soleur:ship --headless` if headless) — commit, push, create PR, merge

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

- Use `skill: soleur:review` after completing implementation
- Catches issues before they reach PR reviewers
- Faster feedback than waiting for human review
- Builds confidence that your code is solid

### Compound Your Learnings

- Use `skill: soleur:compound` before creating a PR
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

After Phase 4 handoff (one-shot only), the same agent continues executing one-shot steps 4-10 (`/review`, `/qa`, `/compound`, `/ship`, `/test-browser`, `/feature-video`).

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
- **Silent plan omissions** - When dropping a conditional plan item, document why in the commit or plan
- **Research without cascade-validate loop** - For knowledge-base research deliverables, Phase 2.5 enforces: cascade findings into source artifacts → re-run validation → cascade again if new weak spots emerge → update brief with final results → present founder summary. "Findings written" is not "done" — "findings applied, validated, and all documents reflect the final state" is done. See Phase 2.5.
- **Missing founder summary** - After completing research, analysis, or audit work, present a concise summary: key findings table + all files changed table (file, what changed, before/after metrics if applicable). The founder needs to review what changed, not just what was discovered.
- **Incomplete replace_all** - After any `replace_all` Edit operation, grep the file to verify zero remaining matches before proceeding to the next task. `replace_all` can miss occurrences with different surrounding context (whitespace, indentation).
