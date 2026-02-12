# Project Constitution

Project principles organized by domain. Add principles as you learn them.

## Code Style

### Always

- Skill descriptions must use third person ("This skill should be used when..." NOT "Use this skill when...")
- Reference files in skills must use markdown links, not backticks (e.g., `[file.md](./references/file.md)`)
- All skill, command, and agent markdown files must include YAML frontmatter with `name` and `description` fields

### Never

- Avoid second person ("you should") - use objective language ("To accomplish X, do Y")

### Prefer

- Prefer ASCII characters unless the file already contains Unicode
- Use imperative/infinitive form for instructions (verb-first)

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
