# Changelog

All notable changes to the Soleur plugin will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.2.2] - 2026-02-12

### Changed

- Discord notification moved from `release-announce` skill to GitHub Actions workflow
  - Triggered automatically on `release: published` event
  - `DISCORD_WEBHOOK_URL` is now a GitHub repository variable, not a local env var
  - Skill simplified to GitHub Release creation only; CI handles Discord
- Added `.github/workflows/release-announce.yml` for automated Discord posting

## [2.2.1] - 2026-02-12

### Added

- `/ship` Phase 7.5: automatic PR health check after push
  - Mergeability: fetches origin/main, checks `gh pr view --json mergeable`, auto-resolves conflicts
  - CI status: watches checks with `gh pr checks --watch --fail-fast`, investigates failures
  - Falls back to user assistance for unresolvable conflicts or flaky CI

## [2.2.0] - 2026-02-12

### Added

- `release-announce` skill for automated release announcements to Discord and GitHub Releases
  - Parses CHANGELOG.md version section and generates AI-powered summary
  - Posts to Discord via webhook (`DISCORD_WEBHOOK_URL` env var)
  - Creates GitHub Release via `gh release create` with idempotency check
  - Graceful degradation when Discord webhook is not configured or posting fails
- `/ship` Phase 8 now invokes `/release-announce` after merge when plugin.json version was bumped

## [2.1.1] - 2026-02-12

### Changed

- Brainstorm command Phase 0 now offers `/soleur:one-shot` as an option when requirements are clear (closes #64)
- Replaces binary plan-or-brainstorm triage with three options: one-shot, plan, or brainstorm
- One-shot option description accurately reflects full pipeline (plan, deepen, implement, review, resolve, test, video, PR)

## [2.1.0] - 2026-02-12

### Added

- Automated test suite for plugin markdown components (`plugins/soleur/test/`)
  - `helpers.ts`: Component discovery (agents, commands, skills) and YAML frontmatter parsing using `yaml` library
  - `components.test.ts`: 443 tests validating frontmatter fields, naming conventions, description voice, and reference links
- Lefthook pre-commit hook (`plugin-component-test`, priority 6) runs tests on `plugins/soleur/**/*.md` changes
- Root `package.json` with `yaml` dev dependency for frontmatter parsing

### Fixed

- `agent-browser` skill description: changed to third-person voice ("This skill should be used when...")
- `rclone` skill description: changed to third-person voice ("This skill should be used when...")
- `help` command: added missing `argument-hint` frontmatter field
- `one-shot` command: added missing `argument-hint` frontmatter field
- `skill-creator` skill: converted 3 backtick file references to proper markdown links

## [2.0.1] - 2026-02-12

### Changed

- Merged `create-agent-skills` into `skill-creator` skill to eliminate overlap (closes #63)
- `skill-creator` now covers creation, refinement, auditing, and best practices
- Rewrote `references/core-principles.md` to use markdown headings instead of XML tags

### Removed

- `create-agent-skills` skill directory (absorbed into `skill-creator`)

## [2.0.0] - 2026-02-12

### Changed

- **BREAKING:** Engineering agents moved to domain-first directory structure
  - 14 review agents: `agents/review/*.md` -> `agents/engineering/review/*.md`
  - 1 design agent: `agents/design/*.md` -> `agents/engineering/design/*.md`
  - Agent subagent_type names change (e.g., `soleur:review:code-simplicity-reviewer` -> `soleur:engineering:review:code-simplicity-reviewer`)
- Cross-domain agents (research/, workflow/) remain at root level unchanged
- README agent tables reorganized into Engineering and Cross-domain sections
- AGENTS.md directory structure updated with domain-first layout and "Adding a New Domain" guide
- Constitution updated: agents organized by domain first, then by function
- Counting globs in help, release-docs, and deploy-docs skills updated from `ls` to recursive `find` for nested directories
- Agent category references in deepen-plan skill updated to new paths

### Removed

- Empty `agents/review/` and `agents/design/` directories (content moved to `agents/engineering/`)

## [1.18.0] - 2026-02-12

### Added

- 6 new skills converted from remaining utility commands: `agent-native-audit`, `deploy-docs`, `feature-video`, `heal-skill`, `report-bug`, `triage`
- `soleur:help` command (replaces top-level `/help`)
- `soleur:one-shot` command (replaces top-level `/lfg`)

### Removed

- 9 top-level utility command files (all converted to skills or moved to `commands/soleur/`)
- `generate_command` command (redundant with `skill-creator` skill)

### Changed

- Command count: 15 -> 8 (all now `soleur:` namespaced, zero top-level utility commands)
- Skill count: 29 -> 35 (6 added)
- `soleur:help` body rewritten to reflect post-consolidation state (dynamic skill listing)
- `soleur:one-shot` stale references fixed (`/deepen-plan`, `/resolve-todo-parallel`, `/test-browser`, `/feature-video`)

## [1.17.0] - 2026-02-12

### Added

- 10 new skills converted from command-only items for agent discoverability: `changelog`, `deepen-plan`, `plan-review`, `release-docs`, `reproduce-bug`, `resolve-parallel`, `resolve-pr-parallel`, `resolve-todo-parallel`, `test-browser`, `xcode-test`

### Removed

- 10 command files replaced by skills above (commands -> skills migration)
- `create-agent-skill` command (pure wrapper; `create-agent-skills` skill already exists)

### Changed

- Command count: 26 -> 15 (11 removed)
- Skill count: 19 -> 29 (10 added)
- Underscore-based command names normalized to kebab-case skill names (e.g., `plan_review` -> `plan-review`)

## [1.16.1] - 2026-02-12

### Changed

- `/soleur:review` moves `kieran-rails-reviewer` and `dhh-rails-reviewer` from unconditional parallel agents to conditional agents section, gated on `Gemfile + config/routes.rb` existence -- Rails-specific agents no longer run on non-Rails projects

## [1.16.0] - 2026-02-12

### Added

- `learnings-researcher` wired into `/soleur:brainstorm` Phase 1.1 alongside `repo-research-analyst` -- past gotchas and documented solutions now inform brainstorming dialogue
- "Challenge assumptions honestly" technique added to brainstorming skill -- brainstorms now push back on flawed reasoning instead of only validating

### Changed

- `/soleur:brainstorm` Phase 1.1 runs 2 research agents in parallel (repo-research + learnings) instead of 1
- Brainstorming skill Question Techniques updated with "Be curious, not prescriptive" guidance and before/after example
- Brainstorming skill Anti-Patterns table includes "forcing scripted questions" row
- `AGENTS.md` adds project-wide "Communication Style" section: challenge reasoning, stop excessive validation, avoid flattery

## [1.15.1] - 2026-02-11

### Changed

- `/soleur:plan` now includes "Test Scenarios" section in all 3 detail templates (MINIMAL, MORE, A LOT) with Given/When/Then format
- `/soleur:work` task execution loop rewritten with explicit RED/GREEN/REFACTOR steps and test-first enforcement
- `/soleur:work` "Test Continuously" section updated with TDD guidance and `/atdd-developer` skill reference
- `/soleur:work` quality checklist now requires test files for new source files
- `/ship` Phase 5 checklist includes test existence verification
- `/ship` Phase 6 checks for missing test files before running the suite, warns and asks before proceeding
- Constitution Testing section expanded with ATDD rules: test file requirements, test scenario mandates, no-zero-tests gate, RED/GREEN/REFACTOR preference, and interface-level mocking guidance

## [1.15.0] - 2026-02-10

### Added

- `code-quality-analyst` wired into `/soleur:review` as always-on parallel agent #10 -- detects code smells and produces refactoring roadmaps
- `test-design-reviewer` wired into `/soleur:review` as conditional agent #13 -- scores test quality against Farley's 8 properties when PR contains test files
- Test file detection patterns for Swift (`*_test.swift`, `*Tests.swift`) and Go (`*_test.go`) in conditional triggers

### Changed

- Renumbered conditional agents sequentially (migration: 11-12, tests: 13) for consistency

## [1.14.0] - 2026-02-10

### Changed

- `/soleur:compound` now auto-consolidates and archives KB artifacts on `feat-*` branches after documenting a learning -- consolidation is no longer a manual menu choice (Option 2 removed, menu renumbered 1-7)
- `/ship` Phase 2 requires `/compound` when unarchived KB artifacts exist for the feature -- Skip option is withheld until artifacts are consolidated

### Added

- 2 architectural principles in constitution.md: multi-tiered parallel execution model and lead-coordinated commits across all tiers
- Archived 5 stale KB artifacts (2 brainstorms, 2 plans, 1 spec directory) from agent-team and community-contributor-audit features

## [1.13.1] - 2026-02-10

### Fixed

- `/soleur:work` Phase 4 now delegates to `/ship` skill instead of duplicating shipping steps inline -- prevents skipping `/compound`, version bumps, and artifact validation
- Removed duplicate Quality Checklist items that `/ship` already enforces

## [1.13.0] - 2026-02-10

### Added

- Agent Teams execution tier in `/soleur:work` Phase 2 -- when `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` is set and 3+ independent tasks exist, offers persistent teammates with peer-to-peer messaging as the highest-capability parallel execution option
  - Tier A (Agent Teams), Tier B (Subagent Fan-Out), Tier C (Sequential) selection flow
  - `spawnTeam` initialization with stale-team cleanup and retry
  - Teammate spawn prompt template with explicit file lists and no-commit instructions
  - Lead-coordinated monitoring via `TaskList`, `write`/`broadcast` messaging
  - `requestShutdown` and `cleanup` lifecycle management
  - Graceful fallthrough from Tier A to Tier B when unavailable or declined

## [1.12.0] - 2026-02-10

### Changed

- License switched from BSL-1.1 to Apache-2.0
- README restructured: product-first with collapsible vision section, badges, verified component counts
- Plugin keywords expanded for better discoverability

### Added

- CONTRIBUTING.md with development setup, PR process, and versioning triad
- CODE_OF_CONDUCT.md (Contributor Covenant v2.1)
- GitHub issue templates (bug report, feature request) and PR template
- GitHub repo description and topics

## [1.11.0] - 2026-02-10

### Added

- Consolidate & archive KB artifacts option in `/soleur:compound` decision menu (Option 2, `feat-*` branches only)
  - Branch-name glob discovery for brainstorms, plans, and specs
  - Single-agent knowledge extraction proposing updates to constitution, component docs, and overview README
  - One-at-a-time approval flow with Accept/Skip/Edit and idempotency checking
  - `git mv` archival with `YYYYMMDD-HHMMSS` timestamp prefix preserving git history
  - Context-aware archival confirmation (different message when all proposals skipped)
  - Single commit for all changes enabling clean `git revert`
- Consolidated 8 principles from 31 artifacts into constitution.md and overview README.md
- Archived 12 brainstorms, 8 plans, and 11 spec directories

## [1.10.0] - 2026-02-09

### Added

- Parallel subagent execution in `/soleur:work` -- when 3+ independent tasks exist, offers to spawn Task subagents (max 5) for parallel execution with lead-coordinated commits and failure fallback

## [1.9.1] - 2026-02-09

### Fixed

- `/ship` skill now offers post-merge worktree cleanup (Phase 8), closing the gap where worktrees were only cleaned on session start or `/soleur:work`, not after mid-session merges

## [1.9.0] - 2026-02-09

### Added

- 4 new review agents from claude-code-agents: code-quality-analyst (Fowler's smell detection + refactoring mapping), test-design-reviewer (Farley Score weighted rubric), legacy-code-expert (Feathers' dependency-breaking techniques), ddd-architect (Evans' strategic DDD)
- 2 new skills: atdd-developer (RED/GREEN/REFACTOR cycle with permission gates), user-story-writer (Elephant Carpaccio + INVEST criteria)
- Problem Analysis Mode in brainstorming skill for deep problem decomposition without solution suggestions

## [1.8.0] - 2026-02-09

### Removed

- 10 unused/inactive agents: design-implementation-reviewer, design-iterator, figma-design-sync, ankane-readme-writer, julik-frontend-races-reviewer, kieran-python-reviewer, kieran-typescript-reviewer, bug-reproduction-validator, lint, every-style-editor (agent duplicate of skill)
- Stale agent references in commands: rails-console-explorer, appsignal-log-investigator, rails-turbo-expert, dependency-detective, code-philosopher, devops-harmony-analyst, cora-test-reviewer
- Empty design/ and docs/ agent directories

### Fixed

- Broken agent references in reproduce-bug, review, and compound commands
- Stale component counts in README files

## [1.7.0] - 2026-02-09

### Added

- `/ship` skill for automated feature lifecycle enforcement (artifact validation, /compound check, README verification, version bump, PR creation)
- Runtime guardrails in root AGENTS.md: worktree awareness, workflow completion protocol, interaction style, plugin versioning reminders

## [1.6.0] - 2026-02-09

### Added

- `/help` command listing all available commands, agents, and skills
- CLAUDE.md auto-loading in Phase 0 of all 6 core workflow commands
- Workspace state reporting after worktree cleanup in `/soleur:work`
- CRUD management for knowledge-base entities:
  - Learnings update/archive/delete in `/soleur:compound`
  - Constitution rule edit/remove in `/soleur:compound`
  - Brainstorm update/archive in `/soleur:brainstorm`
  - Plan update/archive in `/soleur:plan`
- Auto-invoke trigger documentation for all 16 skills (was 5/16)
- Constitution rule documenting plugin infrastructure immutability

## [1.5.0] - 2026-02-06

### Added

- Fuzzy deduplication for `/sync` command (GitHub issue #12)
  - Detects near-duplicate findings using word-based Jaccard similarity
  - Prompts user to skip when similarity > 0.8 threshold
  - Loads existing constitution rules and learnings for comparison
  - Two-stage deduplication: exact match (silent skip) + fuzzy match (user prompt)

## [1.4.2] - 2026-02-06

### Fixed

- `soleur:brainstorm` now detects existing GitHub issue references and skips duplicate creation
  - Parses feature description for `#N` patterns
  - Validates issue state (OPEN/CLOSED/NOT FOUND) before deciding
  - Updates existing issue body with artifact links instead of creating new
  - Shows "Using existing issue: #N" in output summary

## [1.4.1] - 2026-02-06

### Fixed

- git-worktree `feature` command now pulls latest from remote before creating worktree
  - Matches existing behavior in `create_worktree()` for consistency
  - Prevents feature branches from being based on stale local refs
  - Uses `|| true` for graceful failure when offline

## [1.4.0] - 2026-02-06

### Added

- Project overview documentation system in `knowledge-base/overview/`
  - `README.md` with project purpose, architecture diagram, and component index
  - Component documentation files in `overview/components/` (agents, commands, skills, knowledge-base)
  - Component template added to `spec-templates` skill
- `overview` area for `/sync` command to generate/update project documentation
  - Component detection heuristics based on architectural boundaries
  - Preservation of user customizations via frontmatter
  - Review phase with Accept/Skip/Edit for each component
- Constitution conventions for overview vs constitution.md separation
- `cleanup-merged` command in git-worktree skill for automatic worktree cleanup after PR merge
  - Detects merged branches via git's `[gone]` status using `git for-each-ref`
  - Archives spec directories to `knowledge-base/specs/archive/YYYY-MM-DD-HHMMSS-<name>/`
  - Removes worktree and deletes local branch (safe delete)
  - TTY detection: verbose output in terminal, quiet otherwise
  - Safety checks: skips active worktrees and those with uncommitted changes
- SessionStart hook to automatically run cleanup on session start

## [1.3.0] - 2026-02-06

### Added

- `soleur:sync` command for analyzing existing codebases and populating knowledge-base
  - Analyzes coding conventions, architecture patterns, testing practices, and technical debt
  - Sequential review with approve/skip/edit per finding
  - Idempotent operation (exact match deduplication)
  - Supports area filtering: `/sync conventions`, `/sync architecture`, `/sync testing`, `/sync debt`, `/sync all`

## [1.2.0] - 2026-02-06

### Added

- Command integration for spec-driven workflow:
  - `soleur:brainstorm` now creates worktree + spec.md when knowledge-base/ exists
  - `soleur:plan` loads constitution + spec.md, creates tasks.md
  - `soleur:work` loads constitution + tasks.md for implementation guidance
  - `soleur:compound` saves learnings to knowledge-base/, offers manual constitution promotion
- Manual constitution promotion flow (no automation, human-in-the-loop)
- Worktree cleanup prompt after feature completion

## [1.1.0] - 2026-02-06

### Added

- `knowledge-base/` directory structure for spec-driven workflow
  - `specs/` - Feature specifications (spec.md + tasks.md per feature)
  - `learnings/` - Session learnings with date prefixes
  - `constitution.md` - Project principles (Always/Never/Prefer)
- `spec-templates` skill with templates for spec.md and tasks.md
- `feature` command in git-worktree skill to create worktree + spec directory
