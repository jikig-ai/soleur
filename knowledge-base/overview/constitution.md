# Project Constitution

Project principles organized by domain. Add principles as you learn them.

## Code Style

### Always

- Skill descriptions must use third person ("This skill should be used when..." NOT "Use this skill when...")
- Reference files in skills must use markdown links, not backticks (e.g., `[file.md](./references/file.md)`)
- All skill, command, and agent markdown files must include YAML frontmatter with `name` and `description` fields
- Use kebab-case for all file and directory names (agents, skills, commands, learnings, plans)
- Agent descriptions must be 1-3 sentences of routing text only (when to use this agent) -- no `<example>` blocks, no `<commentary>`, no protocol details. Examples bloat the system prompt on every turn; routing accuracy comes from concise descriptions plus disambiguation sentences for sibling agents
- Agent prompts must contain only instructions the LLM would get wrong without them -- omit general domain knowledge, error handling, and boilerplate the model already knows
- Agent frontmatter must include a `model` field (`inherit`, `haiku`, `sonnet`, or `opus`) to control execution model
- Command frontmatter must include an `argument-hint` field describing expected arguments
- Shell scripts must use `#!/usr/bin/env bash` shebang and declare `set -euo pipefail` at the top
- Shell scripts use snake_case for function names and local variables, SCREAMING_SNAKE_CASE for global constants
- Shell functions must declare all variables with `local`; error messages go to stderr (`>&2`)
- Shell scripts use `[[ ]]` double-bracket tests and validate required arguments early with exit 1 and usage message
- TypeScript, JSON, and HTML templates use 2-space indentation throughout
- TypeScript uses `import type` for type-only imports
- TypeScript uses inline `export` at declaration site, not separate `export {}` blocks
- CSS is organized into `@layer` cascade layers in order: reset, tokens, base, layout, components, utilities; custom properties follow semantic naming (`--color-*`, `--font-*`, `--text-*`, `--space-*`)
- CHANGELOG follows Keep a Changelog format with `### Added`, `### Changed`, `### Fixed`, `### Removed` section headers under `## [X.Y.Z] - YYYY-MM-DD` version entries
- Plan files use `YYYY-MM-DD-<type>-<descriptive-name>-plan.md` filename format; learning files use `YYYY-MM-DD-<descriptive-slug>.md` format

### Never

- Avoid second person ("you should") - use objective language ("To accomplish X, do Y")

### Prefer

- Prefer ASCII characters unless the file already contains Unicode
- Use imperative/infinitive form for instructions (verb-first)
- When spawning parallel subagents to generate HTML pages, provide an explicit CSS class name reference list (not the full CSS file) -- subagents independently invent class names that don't match the shared stylesheet
- After version bumps, grep all HTML docs for hardcoded version strings (`grep -r "vX.Y.Z" plugins/soleur/docs/`) and update them -- the versioning triad extends to any file displaying version badges
- Prefer numbered phase sections (Phase 1, Phase 2) in SKILL.md for multi-step workflows, with XML semantic tags (`<critical_sequence>`, `<decision_gate>`, `<validation_gate>`) to mark control flow
- Prefer numeric literal underscores as thousand separators for readability (e.g., `3_000` instead of `3000`)
- Prefer a language identifier after triple backticks in code blocks (e.g., ```bash, ```yaml -- never bare ```)
- Prefer verb-noun naming for skill directories where applicable (e.g., `deploy-docs`, `release-announce`, `resolve-pr-parallel`)

## Architecture

### Always

- Core workflow commands use `soleur:` prefix to avoid collisions with built-in commands
- Every plugin change must update three files: plugin.json (version), CHANGELOG.md, and README.md (counts/tables)
- When adding a new skill, manually register it in `docs/_data/skills.js` SKILL_CATEGORIES -- skill discovery does not recurse and the docs site will silently omit unregistered skills
- After version bumps, diff root README agent/skill counts against plugin README counts -- they drift independently and have diverged multiple times
- Organize agents by domain first (engineering/, etc.), then by function (review/, design/). Cross-domain agents stay at root level (research/, workflow/)
- Skills must have a SKILL.md file and may include scripts/, references/, and assets/ subdirectories
- Lifecycle workflows with hooks must cover every state transition with a cleanup trigger; verify no gaps between create, ship, merge, and session-start
- At session start, run `worktree-manager.sh cleanup-merged` to remove worktrees whose remote branches are [gone]; this is the recovery mechanism for the merge-then-session-end gap where cleanup was deferred
- Operations that modify the knowledge-base or move files must use `git mv` to preserve history and produce a single atomic commit that can be reverted with `git revert`
- New commands must be idempotent -- running the same command twice must not create duplicates or corrupt state
- Run code review and `/soleur:compound` before committing -- the commit is the gate, not the PR; compound must be explicitly offered to the user before every commit, never silently skipped; compound must never be placed after `git push` or CI because compound produces a commit that invalidates CI and creates an infinite loop
- When reading file content during an active git merge conflict, use stage numbers: `git show :2:<path>` (ours) and `git show :3:<path>` (theirs); `git show HEAD:<path>` only returns one side and discards the incoming changes
- Before staging files after a merge, grep staged content for conflict markers: `git diff --cached | grep -E '^\+(<{7}|={7}|>{7})'` -- conflict markers are invisible in normal review and have been committed undetected
- When modifying agent instructions (adding checks, changing behavior), also update any skill Task prompts that reference the agent with hardcoded check lists -- stale prompts silently ignore new agent capabilities
- Infrastructure agents that wire external services (DNS, SSL, Pages) must own the full verification loop -- use `gh` CLI, `openssl`, `curl`, and `agent-browser` to verify each step programmatically instead of asking the user to check manually; only stop for genuine decisions, not mechanical verification
- Network and external service failures must degrade gracefully -- warn (if interactive) and continue rather than abort the workflow
- All Discord webhook payloads must include explicit `username` and `avatar_url` fields rather than relying on webhook defaults -- webhook messages freeze author identity at post time; only delete+repost changes identity on existing messages
- Plans that create worktrees and invoke Task agents must include explicit `cd ${WORKTREE_PATH}` + `pwd` verification between worktree creation and agent invocation
- When adding or integrating new agents, verify the cumulative agent description token count stays under 15k tokens -- agent descriptions are injected into the system prompt on every turn and bloated descriptions degrade all conversations
- Before adding new GitHub Actions workflows, audit existing ones with `gh run list --workflow=<name>.yml` -- remove workflows that are always skipped (condition never matches) or superseded by newer workflows that absorbed their functionality
- Agent descriptions for agents with overlapping scope must include a one-line disambiguation sentence: "Use [sibling] for [its scope]; use this agent for [this scope]." When adding a new agent to a domain, update ALL existing sibling descriptions to cross-reference the new agent -- disambiguation is a graph property, not just a property of the new node
- The project uses Bun as the JavaScript runtime with ESM modules (`"type": "module"`); pre-commit hooks are managed by lefthook (not Husky)
- When fixing a pattern across plugin files (e.g., removing `$()`, renaming a reference), search ALL `.md` files under `plugins/soleur/` -- not just the category (commands/, skills/, agents/) that triggered the report; reference docs, SKILL.md, and agent definitions all contain executable bash blocks

### Never

- Never delete or overwrite user data; avoid destructive commands
- Never state conventions in constitution.md without tooling enforcement (config files, pre-commit hooks, or CI checks)
- Never commit local config files that may contain secrets (`.claude/settings.local.json`, `.env`, `*.local.*`) -- add them to `.gitignore` at project initialization
- Never edit files in the main repo root when a worktree is active for the current feature -- verify `pwd` shows `.worktrees/<name>/` before writing; place feature-scoped directories (todos, reports) inside the app directory within the worktree
- Never use `git stash` in a worktree to hold significant uncommitted work during merge operations -- commit first (even as WIP), then merge; a stash pop conflict can destroy the worktree and branch, losing all uncommitted changes irrecoverably
- Never allow agents to work directly on the default branch -- create a worktree (`git worktree add .worktrees/feat-<name> -b feat/<name>`) before the first file edit, even for trivial fixes; bare branches on the main checkout block parallel work
- Never persist aggregated security findings (audit reports, posture assessments) to files in an open-source repository -- output inline in conversation only; the aggregation is the risk, not the individual facts
- Never design skills that invoke other skills programmatically -- skills are user-invoked entry points with no inter-skill API; redirect users to the target skill or route through an agent via Task tool
- Never put `<example>` blocks or `<commentary>` tags in agent description frontmatter -- these belong in the agent body (after `---`) which is only loaded on invocation; descriptions are loaded into the system prompt on every turn and their cumulative size must stay minimal
- Never skip compound's constitution promotion or route-to-definition phases in automated pipelines (one-shot, ship) -- the model will rationalize skipping them as "pipeline mode" optimization, but these are the phases that prevent repeated mistakes across sessions
- Never spawn file-modifying agents (ops-provisioner, brand-architect, etc.) from the main branch -- create a worktree first; agents that edit project files should include a defensive branch check as a safety net, but the primary enforcement belongs at the caller (command/skill) layer
- Never construct filesystem paths from git ref names -- use `git worktree list --porcelain` to resolve actual worktree paths; refs use `/` separators (e.g., `feat/fix-x`) but worktree directories may use `-` (e.g., `feat-fix-x`), causing silent path mismatches

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
- Prefer inline instructions over Task agents for deterministic checks (shell commands with binary pass/fail outcomes) -- agents add LLM round-trip latency to what would otherwise be millisecond operations
- Plans should specify version bump intent (MINOR/PATCH/MAJOR) not exact version numbers, to avoid conflicts between parallel feature branches
- Experimental feature flags should self-manage within execution scope -- activate on user consent, deactivate on completion or failure -- never require manual setup for features that already have a consent prompt
- Before designing new infrastructure (metadata schemas, detection engines, new directories), check if the existing codebase already has a pattern that solves the problem -- e.g., the review command's conditional agents section was sufficient for project-aware filtering without a metadata system
- Before planning large directory restructures, run a Phase 0 loader test -- move one component, reload, verify it is still discoverable. Different component types have different recursion behavior (agents recurse, skills do not)
- Automate post-merge steps in CI workflows rather than relying on manual skill invocations after merge
- Extend `/ship` with conditional skill invocations rather than inlining domain logic -- ship should remain a thin orchestration layer
- Mechanical notifications (webhooks, emails) belong in CI workflows; keep local skills for AI-powered work that needs Claude -- secrets live in GitHub Actions, not local env vars
- When skills use `!` code fences with permission-sensitive Bash commands, pre-authorize the script path in settings or surface the command earlier in the skill flow -- the Skill tool fails fast on permission denials without showing an interactive approval prompt
- When adding domain leader agents, verify the cumulative agent description word count stays under 2500 with `shopt -s globstar && grep -h 'description:' agents/**/*.md | wc -w` -- the `**` glob requires globstar to recurse into subdirectories
- When one agent/skill produces a structured document consumed by others, define a heading-level contract (exact `##` names, required/optional flags) in the producer -- consumers parse by heading name, not by position
- When bundling external plugins, embed only the mechanism (hooks, scripts) -- do not create new user-facing commands unless the user explicitly requests them; internal infrastructure does not need user-facing surface area
- Route users to specialized agents through existing commands (e.g., brainstorm routes to brand-architect) rather than creating new entry points -- keeps the user workflow unified and avoids proliferating slash commands
- Inventory component counts and descriptions from source file frontmatter rather than hardcoding -- docs stay accurate when the same files the plugin loader reads are the source of truth
- When self-hosting Google Fonts, check if the CSS API returns the same URL for multiple weights -- if so, use one woff2 file with `font-weight: <min> <max>` range syntax instead of downloading duplicate files
- After batch sed operations across multiple files, verify changes landed with `grep -rL` (list files NOT matching) -- sed's append/insert commands fail silently when the address pattern doesn't match
- Agents that depend on external MCP servers (stdio binaries from IDE extensions) must include a graceful degradation check -- only HTTP MCP servers can be bundled in plugin.json; stdio servers require separate installation and the agent must detect unavailability and stop with clear installation instructions
- When a workflow captures domain-specific knowledge, route it to the closest instruction file (skill, agent, command) rather than only centralizing in constitution.md -- domain-specific gotchas belong in domain-specific instructions
- When reviewing docs site changes, audit information architecture separately from visual polish -- check navigation order matches user journey, every page justifies its existence, same-level sections have consistent visual treatment, and first-time users can orient in 30 seconds
- Consolidate catalog categories to ~4-6 groups with 5+ items each; keep category names and ordering consistent across docs pages, README tables, and release tooling
- If skill sub-commands are always run in sequence with no branching decisions between them, merge them into a single sub-command
- Add CSS classes to `style.css` `@layer components` instead of inline styles in Nunjucks templates
- Add test/temp build output directories (e.g., `_site_test/`) to `.gitignore` when introducing new build commands
- When extending commands that run inside an LLM, prefer semantic assessment questions over keyword substring matching -- LLMs are better at understanding intent than pattern matching, and semantic questions are more extensible (one question per domain vs. a keyword table)
- Legal documents exist in two locations (`docs/legal/` for source markdown and `plugins/soleur/docs/pages/legal/` for docs site Eleventy templates) -- both must be updated in sync when legal content changes

## Testing

### Always

- Run `bun test` before merging changes that affect parsing, conversion, or output
- All markdown files must pass markdownlint checks before commit
- New modules and source files must have corresponding test files before shipping
- Plans must include a "Test Scenarios" section with Given/When/Then acceptance tests
- Test files live in a `test/` sibling directory (not co-located with source), named `<module>.test.ts` -- no `.spec.ts` pattern

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
