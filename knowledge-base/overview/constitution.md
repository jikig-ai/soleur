---
last_reviewed: 2026-03-02
review_cadence: quarterly
---

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
- Add allow rules to `.claude/settings.json` for session-start commands that inherently require `$()` -- don't extract them into scripts
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
- Never use shell variable expansion (`${VAR}`, `$VAR`, `$()`) in bash code blocks within skill, command, or agent .md files -- use angle-bracket prose placeholders (`<variable-name>`) with substitution instructions instead, or relative paths (e.g., `./plugins/soleur/...`) for plugin-relative paths; the ship skill's "No command substitution" pattern is the reference implementation
- Never anchor guardrail grep patterns to `^` alone -- the Bash tool chains commands with `&&`, `;`, and `||`, so a `^`-anchored pattern only catches the first command; match at command boundaries with `(^|&&|\|\||;)` instead
- Never write bash code blocks in agent/skill prompts that trigger Claude Code's approval heuristics -- pre-combine multiple blocks into a single `;`-joined command (models insert `echo "---"` separators otherwise), avoid quoted strings starting with dashes (`"---"`, `"-flag"`), and keep commands simple enough to auto-approve; if a command requires user consent, the agent blocks waiting for input it will never receive when running as a subagent

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

- Verify the root cause before implementing any fix -- reproduce the error or run the simplest diagnostic first; do not change code based on a guess
- Core workflow stages (brainstorm, plan, work, review, compound, one-shot) are skills invoked via the Skill tool; only three commands remain (`go`, `sync`, `help`) using the `soleur:` prefix to avoid collisions with built-in commands
- Every plugin change must update three files: plugin.json (version), CHANGELOG.md, and README.md (counts/tables); `.claude-plugin/marketplace.json` plugin version must also be kept in sync
- Always fetch and check main before version bumps (`git fetch origin main && git log --oneline origin/main -3`) -- parallel feature branches that bump without checking cause version collisions that require rebase
- When adding a new skill, manually register it in `docs/_data/skills.js` SKILL_CATEGORIES -- skill discovery does not recurse and the docs site will silently omit unregistered skills
- After version bumps, diff root README agent/skill counts against plugin README counts -- they drift independently and have diverged multiple times
- Organize agents by domain first (engineering/, etc.), then by function (review/, design/). Cross-domain agents stay at root level (research/, workflow/)
- Skills must have a SKILL.md file and may include scripts/, references/, and assets/ subdirectories
- Every SKILL.md interactive prompt (AskUserQuestion) must accept an `$ARGUMENTS` bypass path for programmatic callers -- agents and pipeline skills cannot answer interactive prompts; provide flag-based argument passthrough (e.g., `--name`, `--yes`) that skips the prompt when present
- Lifecycle workflows with hooks must cover every state transition with a cleanup trigger; verify no gaps between create, ship, merge, and session-start
- At session start, run `worktree-manager.sh cleanup-merged` to remove worktrees whose remote branches are [gone]; this is the recovery mechanism for the merge-then-session-end gap where cleanup was deferred
- Post-merge cleanup scripts must update the local main branch to match origin/main -- use `--ff-only` to enforce the no-direct-commits-to-main invariant
- Operations that modify the knowledge-base or move files must use `git mv` to preserve history and produce a single atomic commit that can be reverted with `git revert`
- Skill instructions that use `git mv` must prepend `git add` on the source file to handle untracked files created during the session -- `git add` on an already-tracked file is a no-op
- New commands must be idempotent -- running the same command twice must not create duplicates or corrupt state
- Run code review and compound (skill: `soleur:compound`) before committing -- the commit is the gate, not the PR; compound must be explicitly offered to the user before every commit, never silently skipped; compound must never be placed after `git push` or CI because compound produces a commit that invalidates CI and creates an infinite loop
- Version bump must run after compound in all workflow paths -- compound's route-to-definition phase can stage plugin file edits, and version bump must capture these; version bump is a sealing operation that snapshots the final state before push
- When reading file content during an active git merge conflict, use stage numbers: `git show :2:<path>` (ours) and `git show :3:<path>` (theirs); `git show HEAD:<path>` only returns one side and discards the incoming changes
- Before staging files after a merge, grep staged content for conflict markers: `git diff --cached | grep -E '^\+(<{7}|={7}|>{7})'` -- conflict markers are invisible in normal review and have been committed undetected
- When modifying agent instructions (adding checks, changing behavior), also update any skill Task prompts that reference the agent with hardcoded check lists -- stale prompts silently ignore new agent capabilities
- Infrastructure agents that wire external services (DNS, SSL, Pages) must own the full verification loop -- use `gh` CLI, `openssl`, `curl`, and `agent-browser` to verify each step programmatically instead of asking the user to check manually; only stop for genuine decisions, not mechanical verification
- Pencil MCP edits require three conditions: (1) the .pen file tab must be visible in Cursor so the editor webview connects via WebSocket, (2) after `batch_design` operations, the user must Ctrl+S to flush changes to disk (no programmatic save exists), (3) always `batch_get` current property values before `batch_design` updates -- mockup values diverge from live CSS
- Network and external service failures must degrade gracefully -- warn (if interactive) and continue rather than abort the workflow
- All Discord webhook payloads must include explicit `username` and `avatar_url` fields rather than relying on webhook defaults -- webhook messages freeze author identity at post time; only delete+repost changes identity on existing messages
- Plans that create worktrees and invoke Task agents must include explicit `cd ${WORKTREE_PATH}` + `pwd` verification between worktree creation and agent invocation
- When adding or integrating new agents, verify the cumulative agent description token count stays under 15k tokens -- agent descriptions are injected into the system prompt on every turn and bloated descriptions degrade all conversations
- Before adding new GitHub Actions workflows, audit existing ones with `gh run list --workflow=<name>.yml` -- remove workflows that are always skipped (condition never matches) or superseded by newer workflows that absorbed their functionality
- Agent descriptions for agents with overlapping scope must include a one-line disambiguation sentence: "Use [sibling] for [its scope]; use this agent for [this scope]." When adding a new agent to a domain, update ALL existing sibling descriptions to cross-reference the new agent -- disambiguation is a graph property, not just a property of the new node
- After creating a worktree, run `npm install` before any build commands (`npx @11ty/eleventy`, etc.) -- worktrees do not share `node_modules/` with the main working tree, and missing dependencies cause silent hangs rather than error messages
- The project uses Bun as the JavaScript runtime with ESM modules (`"type": "module"`); pre-commit hooks are managed by lefthook (not Husky)
- Claude Code effort level must be set via `env.CLAUDE_CODE_EFFORT_LEVEL` in `.claude/settings.json`, not as a top-level `effortLevel` field (which is not in the schema); valid values: `low`, `medium`, `high`
- When fixing a pattern across plugin files (e.g., removing `$()`, renaming a reference), search ALL `.md` files under `plugins/soleur/` -- not just the category (commands/, skills/, agents/) that triggered the report; reference docs, SKILL.md, and agent definitions all contain executable bash blocks
- GitHub Actions workflows that create issues with labels must pre-create labels via `gh label create <name> ... 2>/dev/null || true` -- `gh issue create --label` fails if the label does not exist; it does NOT auto-create labels
- GitHub Actions workflows invoking LLM agents (claude-code-action) must set `timeout-minutes` on the job to cap runaway billing -- without it, a stuck agent runs for the 6-hour GitHub default
- GitHub Actions workflows using `claude-code-action` must include `id-token: write` in the permissions block -- the action requires OIDC token access for authentication and fails immediately without it
- GitHub Actions workflows using `claude-code-action` where the agent needs to run shell commands (gh issue create, gh pr create, etc.) or web research must include `--allowedTools Bash,Read,Write,Edit,Glob,Grep,WebSearch,WebFetch` in `claude_args` -- the sandbox blocks Bash, Write, WebSearch, and WebFetch by default and silently drops denied tool calls (workflow reports success with no output)

### Never

- Never delete or overwrite user data; avoid destructive commands
- Never state conventions in constitution.md without tooling enforcement (config files, pre-commit hooks, or CI checks)
- Never commit local config files that may contain secrets (`.claude/settings.local.json`, `.env`, `*.local.*`) -- add them to `.gitignore` at project initialization
- Never edit files in the main repo root when a worktree is active for the current feature -- verify `pwd` shows `.worktrees/<name>/` before writing; place feature-scoped directories (todos, reports) inside the app directory within the worktree
- Never use `git stash` in a worktree to hold significant uncommitted work during merge operations -- commit first (even as WIP), then merge; a stash pop conflict can destroy the worktree and branch, losing all uncommitted changes irrecoverably
- Never allow agents to work directly on the default branch -- create a worktree (`git worktree add .worktrees/feat-<name> -b feat/<name>`) before the first file edit, even for trivial fixes; bare branches on the main checkout block parallel work
- Never persist aggregated security findings (audit reports, posture assessments) to files in an open-source repository -- output inline in conversation only; the aggregation is the risk, not the individual facts
- Never design skills that invoke other skills programmatically -- skills are user-invoked entry points with no inter-skill API; redirect users to the target skill or route through an agent via Task tool. Note: pipeline orchestration via the Skill tool (e.g., one-shot sequencing plan then work) is the approved pattern; this principle targets tight programmatic imports between skill implementations, not Skill tool invocations from commands or other skills
- Never put `<example>` blocks or `<commentary>` tags in agent description frontmatter -- these belong in the agent body (after `---`) which is only loaded on invocation; descriptions are loaded into the system prompt on every turn and their cumulative size must stay minimal
- Never skip compound's constitution promotion or route-to-definition phases in automated pipelines (one-shot, ship) -- the model will rationalize skipping them as "pipeline mode" optimization, but these are the phases that prevent repeated mistakes across sessions
- Never spawn file-modifying agents (ops-provisioner, brand-architect, etc.) from the main branch -- create a worktree first; agents that edit project files should include a defensive branch check as a safety net, but the primary enforcement belongs at the caller (command/skill) layer
- Never nest command `.md` files in subdirectories under `commands/` -- the plugin loader treats subdirectory names as namespace segments, causing double-namespacing (e.g., `commands/soleur/go.md` becomes `soleur:soleur:go` instead of `soleur:go`)
- Never construct filesystem paths from git ref names -- use `git worktree list --porcelain` to resolve actual worktree paths; refs use `/` separators (e.g., `feat/fix-x`) but worktree directories may use `-` (e.g., `feat-fix-x`), causing silent path mismatches

### Prefer

- Plugin infrastructure (agents, commands, skills) is intentionally static - behavior changes require editing markdown files, not runtime registration
- Use skills for agent-discoverable capabilities and workflow stages; use commands only for entry-point routing (go), knowledge-base sync (sync), and help -- commands are invisible to agents
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
- AGENTS.md should contain only rules the agent would violate without being told -- move procedural checklists to the skills that automate them; every line in the system prompt competes for attention on every turn
- Run `/soleur:plan_review` after brainstorm-generated plans to catch scope bloat -- plans consistently shrink by 30-50% after review (e.g., 9 components to 6, 3 parallel agents to 1, multi-file to single-file)
- When merging or consolidating duplicate functionality, prefer a single inline implementation over separate files/agents/skills until complexity demands extraction
- When simplifying a multi-command system, prefer migrating workflow stages to skills and adding a router command (go) -- skills are discoverable by agents and invocable via the Skill tool, while commands are invisible to agents; keep only entry-point commands that need slash-command UX
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
- Reconcile agent/skill/command counts from actual files (`find agents -name '*.md' | wc -l`) at merge time, not by incrementing the previous number -- parallel worktrees each increment from stale baselines, causing drift
- When self-hosting Google Fonts, check if the CSS API returns the same URL for multiple weights -- if so, use one woff2 file with `font-weight: <min> <max>` range syntax instead of downloading duplicate files
- After batch sed operations across multiple files, verify changes landed with `grep -rL` (list files NOT matching) -- sed's append/insert commands fail silently when the address pattern doesn't match
- Agents that depend on external MCP servers (stdio binaries from IDE extensions) must include a graceful degradation check -- only HTTP MCP servers can be bundled in plugin.json; stdio servers require separate installation and the agent must detect unavailability and stop with clear installation instructions
- When evaluating MCP servers for bundling, distinguish OAuth-based auth (bundleable via `type: http` -- Claude Code handles the OAuth flow natively) from header-based auth (API keys, PATs -- not bundleable until plugin.json adds a `headers` field)
- When a workflow captures domain-specific knowledge, route it to the closest instruction file (skill, agent, command) rather than only centralizing in constitution.md -- domain-specific gotchas belong in domain-specific instructions
- Interactive workshop agents (brand-architect, business-validator) follow a reusable archetype: detect-and-resume existing documents, sequential gates with one question at a time, atomic writes after each gate, fixed heading contract for downstream parsing -- start from this template when building new assessment agents
- Assessment agents that produce documents consumed by downstream agents must read brand-guide.md (or equivalent positioning artifact) before their first decision gate -- context-blind assessments propagate misalignment through the entire agent chain
- When reviewing docs site changes, audit information architecture separately from visual polish -- check navigation order matches user journey, every page justifies its existence, same-level sections have consistent visual treatment, and first-time users can orient in 30 seconds
- Consolidate catalog categories to ~4-6 groups with 5+ items each; keep category names and ordering consistent across docs pages, README tables, and release tooling
- If skill sub-commands are always run in sequence with no branching decisions between them, merge them into a single sub-command
- Add CSS classes to `style.css` `@layer components` instead of inline styles in Nunjucks templates
- When changing card counts in CSS grids, verify `card_count % column_count == 0` at every responsive breakpoint -- a nonzero remainder means orphaned cards; take screenshots at desktop, tablet, and mobile before shipping
- Marketing-visible changes (landing page, docs site layout) must route through CMO who delegates to UX designer or conversion-optimizer for layout review -- CMO provides strategic direction, specialists verify visual execution
- Add test/temp build output directories (e.g., `_site_test/`) to `.gitignore` when introducing new build commands
- When extending commands that run inside an LLM, prefer semantic assessment questions over keyword substring matching -- LLMs are better at understanding intent than pattern matching, and semantic questions are more extensible (one question per domain vs. a keyword table)
- Legal documents exist in two locations (`docs/legal/` for source markdown and `plugins/soleur/docs/pages/legal/` for docs site Eleventy templates) -- both must be updated in sync when legal content changes
- When adding a new data processing activity, update ALL three privacy/GDPR documents (Privacy Policy, Data Protection Disclosure, GDPR Policy) -- the GDPR Policy requires the most detail (three-part balancing test and processing register entry) but is the easiest to forget
- Always smoke test `pull_request_target` workflows end-to-end on a separate PR after merging the workflow change -- the workflow runs from the base branch, so it cannot be tested on the PR that introduces it; plan for admin bypass merges during bootstrapping
- Verify review agent suggestions against the full user journey before shipping -- review agents optimize locally (e.g., reducing unnecessary workflow triggers) but may break flows they don't fully model (e.g., a body filter on `issue_comment` that blocks CLA signing comments)
- Heavy, conditionally-used content in command/skill bodies must be extracted to reference files loaded on-demand via Read tool -- static baseline context that is always loaded should contain only the execution skeleton and phase triggers, not the full content of each phase
- When spawning isolated subagents (Task tool), establish an explicit return contract with structured headings (`## Session Summary`, `### Errors`, etc.) and a fallback path if the subagent fails or returns malformed output -- session-state.md is the mechanism for multi-phase error propagation when parent context cannot hold child errors
- Add explicit compaction checkpoints to multi-phase workflows -- if context truncation occurs, write an inventory to a known file path (e.g., session-state.md) so downstream phases can recover; silent compaction has caused missing learnings and undocumented errors in pipelines
- When fixing a prefix-stripping or pattern-matching bug, verify the fix code does not repeat the same single-variant assumption being corrected -- the initial worktree-manager.sh fix reproduced the exact `feat-`-only bug it was supposed to fix; multi-agent review catches this reliably but self-review often misses it
- Prefer single-pattern grep guards over ANDing separate greps -- independent substring checks cannot enforce syntactic context (e.g., that `.worktrees/` is an `rm` argument, not comment text); combine into one regex that enforces proximity
- Prefer hook-based enforcement over documentation-only rules for agent discipline -- PreToolUse hooks make violations impossible rather than aspirational; reserve AGENTS.md hard rules for cases where hooks cannot intercept (e.g., reasoning errors, not tool calls)
- Diagnostic scripts must print positive confirmation on success, not just absence of error -- silent success is indistinguishable from a skipped check; always emit an `[ok]` or equivalent status line for each verified condition

## Testing

### Always

- Run `bun test` before merging changes that affect parsing, conversion, or output
- All markdown files must pass markdownlint checks before commit
- New modules and source files must have corresponding test files before shipping
- Plans must include a "Test Scenarios" section with Given/When/Then acceptance tests
- Test files live in a `test/` sibling directory (not co-located with source), named `<module>.test.ts` -- no `.spec.ts` pattern
- Run dependency-detection scripts (`check_deps.sh`) on a real machine before merging -- don't trust assumed dependency graphs or distribution formats

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

## Business

### Always

- Include a "threat assumptions" section in revenue and strategy plans listing which competitive conditions must hold for the plan to remain valid -- assumptions that are invalidated should trigger an immediate reassessment, not wait for a quarterly review
- Use parallel domain leader analysis for strategic competitive threats -- multi-agent convergence (all leaders reaching the same conclusion independently) is a strong validation signal; if 3+ leaders converge on the same insight without coordination, treat it as high-confidence

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
