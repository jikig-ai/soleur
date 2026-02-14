# Project Constitution

Project principles organized by domain. Add principles as you learn them.

## Code Style

### Always

- Skill descriptions must use third person ("This skill should be used when..." NOT "Use this skill when...")
- Reference files in skills must use markdown links, not backticks (e.g., `[file.md](./references/file.md)`)
- All skill, command, and agent markdown files must include YAML frontmatter with `name` and `description` fields
- Use kebab-case for all file and directory names (agents, skills, commands, learnings, plans)
- Agent descriptions must include at least one `<example>` block with context, user/assistant dialogue, and `<commentary>` explaining the selection rationale
- Agent frontmatter must include a `model` field (`inherit`, `haiku`, `sonnet`, or `opus`) to control execution model
- Command frontmatter must include an `argument-hint` field describing expected arguments

### Never

- Avoid second person ("you should") - use objective language ("To accomplish X, do Y")

### Prefer

- Prefer ASCII characters unless the file already contains Unicode
- Use imperative/infinitive form for instructions (verb-first)
- When spawning parallel subagents to generate HTML pages, provide an explicit CSS class name reference list (not the full CSS file) -- subagents independently invent class names that don't match the shared stylesheet
- After version bumps, grep all HTML docs for hardcoded version strings (`grep -r "vX.Y.Z" plugins/soleur/docs/`) and update them -- the versioning triad extends to any file displaying version badges
- Prefer numbered phase sections (Phase 1, Phase 2) in SKILL.md for multi-step workflows, with XML semantic tags (`<critical_sequence>`, `<decision_gate>`, `<validation_gate>`) to mark control flow

## Architecture

### Always

- Core workflow commands use `soleur:` prefix to avoid collisions with built-in commands
- Every plugin change must update three files: plugin.json (version), CHANGELOG.md, and README.md (counts/tables)
- Organize agents by domain first (engineering/, etc.), then by function (review/, design/). Cross-domain agents stay at root level (research/, workflow/)
- Skills must have a SKILL.md file and may include scripts/, references/, and assets/ subdirectories
- Lifecycle workflows with hooks must cover every state transition with a cleanup trigger; verify no gaps between create, ship, merge, and session-start
- Operations that modify the knowledge-base or move files must use `git mv` to preserve history and produce a single atomic commit that can be reverted with `git revert`
- New commands must be idempotent -- running the same command twice must not create duplicates or corrupt state
- Run code review and `/soleur:compound` before committing -- the commit is the gate, not the PR
- Network and external service failures must degrade gracefully -- warn (if interactive) and continue rather than abort the workflow
- Plans that create worktrees and invoke Task agents must include explicit `cd ${WORKTREE_PATH}` + `pwd` verification between worktree creation and agent invocation

### Never

- Never delete or overwrite user data; avoid destructive commands
- Never state conventions in constitution.md without tooling enforcement (config files, pre-commit hooks, or CI checks)
- Never commit local config files that may contain secrets (`.claude/settings.local.json`, `.env`, `*.local.*`) -- add them to `.gitignore` at project initialization
- Never edit files in the main repo root when a worktree is active for the current feature -- verify `pwd` shows `.worktrees/<name>/` before writing; place feature-scoped directories (todos, reports) inside the app directory within the worktree

### Prefer

- Plugin infrastructure (agents, commands, skills) is intentionally static - behavior changes require editing markdown files, not runtime registration
- Use skills for agent-discoverable capabilities; use commands only for multi-phase orchestration workflows or actions requiring human judgment -- commands are invisible to agents
- Verify documentation against implementation reality before trusting it; treat docs about "what exists" as hypotheses to verify

- `overview/` documents what the project does; `overview/constitution.md` documents how to work on it
- Component documentation in `overview/components/` should follow the component template from spec-templates skill

- Use convention over configuration for paths: `feat-<name>` maps to `knowledge-base/specs/feat-<name>/` and `.worktrees/feat-<name>/`
- Include sequence diagrams for complex flows
- Complex commands should follow a four-phase pattern: Setup, Analyze, Review, Write
- For user approval flows, present items one at a time with Accept, Skip, and Edit options
- Start with manual workflows; add automation only when users explicitly request it
- Commands should check for knowledge-base/ existence and fall back gracefully when not present
- Run `/soleur:plan_review` before implementing plans with new directories, external APIs, or complex algorithms
- Parallel subagent fan-out requires explicit user consent, bounded agent count (max 5), and lead-coordinated commits (subagents do not commit independently)
- Multi-tiered parallel execution model: Agent Teams (persistent teammates with peer-to-peer messaging) > Subagent Fan-Out (Task tool with max 5) > Sequential -- select the highest available tier that the task warrants
- Lead-coordinated commits in all parallel execution modes -- teammates and subagents propose changes, only the lead agent commits
- Design for v2, implement for v1 -- keep interfaces extensible but ship the simplest working version first (no multi-agent orchestration, no CLI flags, no caching until users request it)
- When adopting external components (agents, skills, libraries), trim to essentials that leverage the model's built-in knowledge rather than embedding encyclopedic reference material
- Run `/soleur:plan_review` after brainstorm-generated plans to catch scope bloat -- plans consistently shrink by 30-50% after review (e.g., 9 components to 6, 3 parallel agents to 1, multi-file to single-file)
- When merging or consolidating duplicate functionality, prefer a single inline implementation over separate files/agents/skills until complexity demands extraction
- Plans should specify version bump intent (MINOR/PATCH/MAJOR) not exact version numbers, to avoid conflicts between parallel feature branches
- Experimental feature flags should self-manage within execution scope -- activate on user consent, deactivate on completion or failure -- never require manual setup for features that already have a consent prompt
- Before designing new infrastructure (metadata schemas, detection engines, new directories), check if the existing codebase already has a pattern that solves the problem -- e.g., the review command's conditional agents section was sufficient for project-aware filtering without a metadata system
- Before planning large directory restructures, run a Phase 0 loader test -- move one component, reload, verify it is still discoverable. Different component types have different recursion behavior (agents recurse, skills do not)
- Automate post-merge steps in CI workflows rather than relying on manual skill invocations after merge
- Extend `/ship` with conditional skill invocations rather than inlining domain logic -- ship should remain a thin orchestration layer
- Mechanical notifications (webhooks, emails) belong in CI workflows; keep local skills for AI-powered work that needs Claude -- secrets live in GitHub Actions, not local env vars
- When one agent/skill produces a structured document consumed by others, define a heading-level contract (exact `##` names, required/optional flags) in the producer -- consumers parse by heading name, not by position
- Route users to specialized agents through existing commands (e.g., brainstorm routes to brand-architect) rather than creating new entry points -- keeps the user workflow unified and avoids proliferating slash commands
- Inventory component counts and descriptions from source file frontmatter rather than hardcoding -- docs stay accurate when the same files the plugin loader reads are the source of truth
- When self-hosting Google Fonts, check if the CSS API returns the same URL for multiple weights -- if so, use one woff2 file with `font-weight: <min> <max>` range syntax instead of downloading duplicate files
- After batch sed operations across multiple files, verify changes landed with `grep -rL` (list files NOT matching) -- sed's append/insert commands fail silently when the address pattern doesn't match

## Testing

### Always

- Run `bun test` before merging changes that affect parsing, conversion, or output
- All markdown files must pass markdownlint checks before commit
- New modules and source files must have corresponding test files before shipping
- Plans must include a "Test Scenarios" section with Given/When/Then acceptance tests

### Never

- Ship feature branches with zero test files for new source code

### Prefer

- RED/GREEN/REFACTOR cycle over write-code-then-test -- use `/atdd-developer` skill for guided TDD
- Interface-level mocking over implementation-level mocking -- define a minimal interface (e.g., BotApi) and inject it, enabling tests without external dependencies
- Prefer Bun's built-in test framework (`bun:test`) with describe/test/expect pattern over external test runners
- Prefer factory functions (e.g., `createMockApi()`, `makeStatus(overrides)`) over inline test data for reusable test fixtures
- Prefer labeling regression tests with their original issue ID (e.g., `P2-014 regression`) for traceability

## Proposals

### Always

- Include rollback plan
- Identify affected teams
- Always include a "Non-goals" section

### Never

### Prefer

## Specs

### Always

- Use Given/When/Then format for scenarios

### Never

### Prefer

## Tasks

### Always

- Break tasks into chunks of max 2 hours
- Definition of Done is "PR submitted," not "tasks checked off" - continue through /compound, commit, push, and PR creation

### Never

### Prefer
