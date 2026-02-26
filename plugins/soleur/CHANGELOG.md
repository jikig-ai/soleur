# Changelog

All notable changes to the Soleur plugin will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).


## [3.3.4] - 2026-02-26

### Fixed

- **Ship SKILL.md** -- Reordered phases: tests (Phase 4) now run before version bump (Phase 5), ensuring compound's route-to-definition edits are captured. Removed redundant pre-push compound gate from Phase 7 (Phase 2 already enforces compound).
- **One-shot SKILL.md** -- Added version-bump-recheck (step 6.5) after second compound run to catch route-to-definition edits that occur after ship's version bump.
- **Work SKILL.md** -- Updated inline ship phase description to reflect new ordering.

## [3.3.3] - 2026-02-26

### Added

- **`draft-pr` subcommand** in `worktree-manager.sh` -- creates empty commit, pushes branch, and opens a draft PR. Idempotent (skips if PR already exists). Warns but continues on network failure.

### Changed

- **Brainstorm SKILL.md** -- Phase 3 now calls `draft-pr` after worktree creation. Phase 3.6 commits brainstorm doc + spec together and pushes at skill boundary.
- **Brand Workshop / Validation Workshop** references -- call `draft-pr` after worktree creation, commit + push workshop artifacts before completion.
- **One-shot SKILL.md** -- Step 0c creates draft PR after branch creation.
- **Plan SKILL.md** -- Save Tasks section commits plan + tasks.md together and pushes at skill boundary.
- **Ship SKILL.md** -- Phase 7 detects existing draft PR via `gh pr list --head`, uses `gh pr edit` + `gh pr ready` instead of creating new PR. Falls through to `gh pr create` when no draft PR exists (backwards compatible).

## [3.3.2] - 2026-02-26

### Added

- **Worktree write guard hook**: New PreToolUse hook (`.claude/hooks/worktree-write-guard.sh`) that blocks `Write` and `Edit` tool calls targeting the main repo checkout when worktrees exist, preventing the recurring problem of agents creating files on main instead of in the active worktree

### Fixed

- **cleanup-merged untracked file false positive**: Change uncommitted-changes check in `cleanup_merged_worktrees()` to only consider tracked file changes (`git diff --quiet HEAD` + `git diff --cached --quiet`), so untracked files (screenshots, temp artifacts) no longer block the post-cleanup `git pull`

## [3.3.1] - 2026-02-25

### Fixed

- **Double-namespaced commands**: Move commands from `commands/soleur/*.md` to `commands/*.md` to fix double-namespacing (`soleur:soleur:go` -> `soleur:go`). The plugin loader uses subdirectory names as part of the namespace, so `commands/soleur/go.md` produced `soleur:soleur:go` instead of the intended `soleur:go`
- Update command frontmatter `name` fields to omit the `soleur:` prefix (plugin namespace auto-adds it)
- Update all internal path references (`AGENTS.md`, `helpers.ts`, `stats.js`, `compound-capture`, `sync`, `help`)

## [3.3.0] - 2026-02-25

### Added

- **Legal benchmark audit mode**: Extend `legal-compliance-auditor` agent and `legal-audit` skill with a `benchmark` sub-command that checks legal documents against GDPR Article 13/14 regulatory disclosure checklists and compares clause coverage against peer SaaS policies (Basecamp, GitHub)
  - GDPR Art 13/14 enumerated disclosure checklist (13 items) with `[REGULATORY]` finding labels
  - Peer comparison via WebFetch with curated URL table and graceful `[SKIPPED]` fallback
  - Benchmark summary with disclosure coverage score and peer comparison stats
  - CLO delegation table updated to suggest `legal-audit benchmark` for competitive benchmarking

## [3.2.2] - 2026-02-25

### Fixed

- **functional-discovery approval prompt**: Merge two separate bash blocks in "Already-Installed Check" into a single command, preventing the agent from inserting `echo "---"` separators that trigger Claude Code's "quoted characters in flag names" approval prompt

## [3.2.1] - 2026-02-25

### Fixed

- **cleanup-merged pull failure**: Fix silent pull failure in `worktree-manager.sh cleanup-merged` -- stderr was suppressed (`2>/dev/null`), verbose guard hid messages in non-TTY mode, and missing `return 0` let failed pull exit code leak as script exit code
- Pull success/failure messages now always print (removed TTY-only verbose guard)
- Pull errors captured in variable and displayed in warning message for diagnosis

## [3.2.0] - 2026-02-24

### Added

- **New skill: `archive-kb`** -- Archive knowledge-base artifacts (brainstorms, plans, specs) to `archive/` subdirectories with timestamped prefixes. The script encapsulates `date`, `git add`, and `git mv` into a single command, eliminating `$()` command substitution from all SKILL.md files that reference archival
- `--dry-run` flag for previewing what would be archived without executing

### Changed

- Replace inline archival instructions in `compound-capture` Step E with `archive-kb.sh` invocation (reduces ~35 lines to ~5 lines)
- Update archival references in `compound`, `brainstorm`, and `plan` SKILL.md files to invoke `archive-kb.sh`
- Add error handling instruction to `compound-capture` Step E (stop on non-zero exit)
- Register `archive-kb` in `docs/_data/skills.js` SKILL_CATEGORIES (Workflow)

## [3.1.0] - 2026-02-24

### Changed

- **License:** Switch from Apache-2.0 to BSL 1.1 (Business Source License)
  - All individual and internal company use remains permitted
  - The only restriction: offering Soleur as a competing hosted/managed service
  - Each version auto-converts to Apache-2.0 after 4 years
  - Prior versions (v3.0.10 and earlier) remain Apache-2.0
- Update LICENSE files (root and plugin) with BSL 1.1 text
- Update plugin.json license field to `BUSL-1.1`
- Update README license badges and sections (root and plugin)
- Update all legal documents (Terms, Privacy Policy, Disclaimer, Cookie Policy, GDPR Policy, AUP, DPA) to reflect source-available status
- Sync Eleventy legal page templates with source markdown

## [3.0.10] - 2026-02-24

### Changed

- Standardize all agents to `model: inherit` (changed learnings-researcher from `model: haiku`)
- Add Model Selection Policy section to AGENTS.md documenting the inherit-by-default standard
- Update Agent Compliance Checklist to require `model: inherit` with justification for overrides
- Add `CLAUDE_CODE_EFFORT_LEVEL=high` to project settings for explicit max reasoning effort

## [3.0.9] - 2026-02-24

### Changed

- Add `git pull --ff-only origin main` to `cleanup-merged` script after cleaning branches, so the next worktree branches from the latest main
- Update ship, merge-pr, and AGENTS.md to document the auto-pull behavior
- Add constitution rule: post-merge cleanup must update local main with `--ff-only`

## [3.0.8] - 2026-02-24

### Fixed

- Add proactive `git add` before `git mv` in 4 skill archival instructions to prevent "not under version control" errors on untracked files (closes #290)
- Move compound-capture Step E fallback from trailing note to inline code blocks for reliability
- Add constitution rule: skill instructions using `git mv` must prepend `git add` on source files

## [3.0.7] - 2026-02-24

### Changed

- Re-run business validation workshop with fixed agent (closes #259)
- Update validation workshop reference with per-gate relay pattern for interactive subagents
- Add learning: workshop agents as subagents require manual gate relay

## [3.0.6] - 2026-02-22

### Fixed

- Replace bash code blocks in `/soleur:help` command with Read/Glob tool instructions to eliminate `$() command substitution` permission prompts
- Update command-substitution learning with v3.0.6 recurrence and native-tool-replacement insight

## [3.0.5] - 2026-02-22

### Removed

- Remove `community` skill from plugin loader (thin wrapper around community-manager agent; scripts preserved at `skills/community/scripts/`)
- Remove `report-bug` skill from plugin loader (user-only utility incorrectly migrated to skill namespace)

### Changed

- Update community-manager agent to reference setup scripts directly instead of removed `/soleur:community setup` skill
- Update skill counts from 52 to 50 across plugin.json, README, root README, brand guide, and skills.js

## [3.0.4] - 2026-02-22

### Fixed

- Fix compound-capture slug extraction to handle `feat/`, `feat-`, `fix/`, `fix-` branch prefixes (was only stripping `feat-`, causing silent archiving failures on `feat/` branches)
- Fix cleanup-merged to archive brainstorms and plans (was only archiving spec directories)
- Extract `archive_kb_files()` helper in worktree-manager.sh to eliminate code duplication
- Archive 92 orphaned KB artifacts from completed features (13 brainstorms, 38 plans, 41 spec dirs)
- Update compound skill discovery documentation to reflect multi-prefix slug extraction

## [3.0.3] - 2026-02-22

### Fixed

- Move 10 reference files from `commands/soleur/references/` to `skills/<name>/references/` to prevent autocomplete pollution (plugin loader recursively discovers `.md` files in `commands/` as slash commands)

## [3.0.2] - 2026-02-22

### Changed

- Extract heavy, conditionally-used content from 5 skill bodies into 10 reference files loaded on demand (26% static word count reduction: 13,292w to 9,794w)
- Add constitution dedup to plan and work skills -- skip re-reading constitution.md when already in context
- Isolate plan+deepen as a Task subagent in one-shot pipeline with structured return contract
- Add session-state.md error forwarding for multi-phase pipeline error recovery
- Update compound and compound-capture to read session-state.md for forwarded errors from preceding phases
- Add 3 architecture principles to constitution (reference extraction, subagent contracts, compaction checkpoints)

## [3.0.1] - 2026-02-22

### Changed

- Update Getting Started page Common Workflows and Beyond Engineering sections to use `/soleur:go` as entry point

## [3.0.0] - 2026-02-22

### Changed

- **BREAKING:** Migrate 6 workflow commands (brainstorm, plan, work, review, compound, one-shot) from `commands/soleur/` to `skills/` -- pipeline stages are now agent-discoverable via Skill tool
- Rename `brainstorming` skill to `brainstorm-techniques` to free up the clean name
- Rename `compound-docs` skill to `compound-capture` to free up the clean name
- Update all cross-references across 20+ files (skills, agents, docs, constitution)
- Rewrite command naming convention section in AGENTS.md to reflect skills architecture

### Removed

- Remove 6 workflow commands from autocomplete (brainstorm, plan, work, review, compound, one-shot) -- only `go`, `sync`, `help` remain as commands

### Migration Guide

If you previously invoked `/soleur:brainstorm`, `/soleur:plan`, `/soleur:work`, `/soleur:review`, `/soleur:compound`, or `/soleur:one-shot` directly, use `/soleur:go` instead. All workflow stages are now skills invoked automatically through the router. The `skill: soleur:<name>` invocation syntax continues to work unchanged.

## [2.36.2] - 2026-02-22

### Changed

- Rewrite Vision page "The Road Ahead" section as "Master Plan" with 3 milestones: Automate Software Companies, Automate Hardware Companies, Multiplanetary Companies

## [2.36.1] - 2026-02-22

### Changed

- Make landing page department cards, count, and inline list data-driven from `agents.js` DOMAIN_META
- Make legal doc agent/skill counts and domain lists data-driven via Eleventy template variables
- Add `departments` count to `stats.js` (computed from non-empty agent directories)
- Add `departmentList` string export to `agents.js` (comma-separated domain names)
- Replace `DOMAIN_LABELS` with richer `DOMAIN_META` constant (label, icon, card description)
- Update "Adding a New Domain" checklist to reflect auto-generated landing page and legal docs

### Fixed

- Fix stale counts in privacy-policy.md (was "45 agents, 45 skills") and acceptable-use-policy.md (was "45 agents and 45 skills")

## [2.36.0] - 2026-02-22

### Added

- Add `/soleur:go` command -- unified entry point that classifies user intent (explore, build, review) and routes to the right workflow command
- Add plugin loader constraint note to brainstorm.md Phase 0 (bare namespace commands not supported)
- Add router-over-migration principle to constitution.md

### Changed

- Update help.md with new layout: "Getting Started" (go, sync, help) and "Workflow Commands (Advanced)" sections
- Update README.md workflow section to recommend `/soleur:go` as primary entry point
- Update README.md command count from 8 to 9

## [2.35.1] - 2026-02-22

### Fixed

- Update landing page department count from 7 to 8 and add Finance and Support department cards
- Update landing page inline department list to include all 8 domains
- Update landing page departments grid to 4-column layout for 8 cards (2 perfect rows)
- Update terms and conditions from "58 AI agents across seven domains" to "60 AI agents across eight domains"

## [2.35.0] - 2026-02-22

### Added

- Add Support domain with 3 agents: CCO (domain leader), ticket-triage, community-manager (moved from Marketing)
- Add Support row to brainstorm Phase 0.5 domain config table for automatic CCO routing
- Add `--cat-support` CSS variable (#9B59B6 purple) and Support to docs site agent catalog

### Changed

- Move community-manager agent from Marketing to Support domain
- Update CMO description and delegation table to remove community-manager, add cross-domain note
- Add disambiguation sentence to triage skill referencing ticket-triage agent

## [2.34.0] - 2026-02-22

### Added

- Add Finance domain with 4 agents: CFO (domain leader), budget-analyst, revenue-analyst, financial-reporter
- Add Finance row to brainstorm Phase 0.5 domain config table for automatic CFO routing
- Add `--cat-finance` CSS variable (#26A69A teal) and Finance to docs site agent catalog

### Changed

- Update ops-advisor disambiguation to reference CFO for financial analysis boundary
- Update landing page department count from 6 to 7 (no new card -- grid orphan prevention)

## [2.33.2] - 2026-02-22

### Changed

- Trim 16 agent descriptions to recover 342 words of token budget headroom (2,496 -> 2,154)
- Refactor brainstorm Phase 0.5 from inline per-domain blocks to table-driven config (-135 lines)
- Merge brand routing into marketing domain row (7 rows -> 6)

### Fixed

- Add missing "sales" domain to 8 files (plugin.json, README, AGENTS.md, getting-started, llms.txt, terms-and-conditions)
- Fix stale agent/skill counts in terms-and-conditions.md (45 -> 54 agents, 45 -> 46 skills)
- Update "Adding a New Domain Leader" checklist to reference table-driven config

## [2.33.1] - 2026-02-22

### Fixed

- Replace shell variable expansion syntax (`${VAR}`, `$VAR`) in 18 plugin .md files to eliminate "Shell expansion syntax in paths requires manual approval" prompts
- Add constitution rule preventing future shell expansion in bash code blocks

## [2.33.0] - 2026-02-22

### Added

- Add Cloudflare MCP server to plugin.json for native API access via OAuth 2.1
- Expand infra-security agent scope to full Cloudflare platform (DNS, WAF, Workers, Zero Trust, DDoS)

### Changed

- Rewrite infra-security agent from curl-based to MCP-based Cloudflare operations
- Update terraform-architect disambiguation to reflect expanded infra-security scope

## [2.32.0] - 2026-02-22

### Added

- Vercel MCP server integration -- full platform access (deployments, projects, logs, domains, documentation) via OAuth

## [2.31.7] - 2026-02-22

### Changed

- Add CMO-to-UX delegation guidance in brainstorm command for layout-related assessments

## [2.31.6] - 2026-02-22

### Fixed

- Fix orphaned "Knowledge Compounds" card at tablet breakpoint (769-1024px) by removing broken 2-col rule for problem-cards
- Add 2-column responsive rule for department/workflow grids at tablet for clean 3x2 layout
- Replace confusing "1 Automated Workflow" stat with "6 Departments" for clearer value communication
- Add mid-page CTA between quote and features section per CMO conversion assessment
- Increase spacing between department and workflow grid sections to reduce "wall of cards" effect

## [2.31.5] - 2026-02-22

### Fixed

- Remove all command substitution patterns from ship skill to prevent Claude Code security prompts
- Replace "run X then use result in Y" prose with explicit two-step Bash call instructions
- Add global "No command substitution" rule at top of ship SKILL.md

## [2.31.4] - 2026-02-22

### Fixed

- Fix broken landing page grid layout: replace `auto-fill` with `repeat(3, 1fr)` for clean 3x2 grids
- Replace aspirational department cards (Strategy, Support) with real plugin domains (Legal, Operations)
- Add missing "Review" workflow card and rename "Learn & Grow" to "Compound" to match actual workflow
- Tighten Sales card copy per CMO recommendation

## [2.31.3] - 2026-02-22

### Fixed

- Align all onboarding artifacts with Company-as-a-Service vision (#248)
- Fix business-validator agent context-blindness (add Step 0.5: Read Project Identity, make Gate 6 vision-aware, add Vision Alignment Check)
- Fix CPO agent to cross-reference business-validation.md against brand-guide.md
- Rewrite business-validation.md with correct Company-as-a-Service framing
- Update plugin.json description, root README, Getting Started, llms.txt, plugin README, and AGENTS.md to describe all 5 domains
- Replace hardcoded agent/skill counts with dynamic template variables in Getting Started
- Add "Beyond Engineering" section to Getting Started with non-engineering workflows
- Add "Your AI Organization" table to root README
- Fix stale agent counts in brand-guide.md (50 -> 54)
- Add constitution principle: assessment agents must read brand-guide.md before first decision gate

## [2.31.2] - 2026-02-22

### Fixed

- Add missing Sales department card to landing page and update "Agents Execute" text to include sales

## [2.31.1] - 2026-02-22

### Fixed

- Fix stale "Adding a New Domain Leader" checklist in AGENTS.md (expanded from 5 to 8 steps, corrected 3-phase contract reference)

## [2.31.0] - 2026-02-22

### Added

- Add Sales domain with CRO (Chief Revenue Officer) domain leader and 3 specialist agents (#247)
- New agents: `cro`, `outbound-strategist`, `deal-architect`, `pipeline-analyst` under `agents/sales/`
- CRO follows the 3-phase domain leader pattern (Assess, Recommend/Delegate, Sharp Edges)
- Sales detection added to brainstorm Phase 0.5 domain assessment (question #7, routing, participation)
- Cross-domain disambiguation between Sales and Marketing agents (5 Marketing agents updated)

### Changed

- Trim 10 bloated agent descriptions to stay under 2,500-word token budget (2,613 -> 2,497 words)
- Fix AGENTS.md domain leader contract from "4-phase" to "3-phase" to match actual implementation
- Fix CMO description: replace "CRO" abbreviation with "conversion-optimizer" to avoid naming collision
- Update docs site: add Sales to agents.js data, style.css CSS variable (`--cat-sales: #E06666`)

## [2.30.1] - 2026-02-22

### Added

- Add capability gap detection to all 5 domain leader agents (CTO, CMO, COO, CPO, CLO) during brainstorm participation (#234)
- Brainstorm command includes consolidated Capability Gaps section in brainstorm documents when domain leaders report missing agents/skills
- Plan command Phase 1.5b passes brainstorm gap context to functional-discovery for guided registry searches

## [2.30.0] - 2026-02-22

### Added

- Add CLO (Chief Legal Officer) domain leader agent for legal orchestration (#181)
- CLO follows COO's 3-phase pattern (Assess, Recommend/Delegate, Sharp Edges) to orchestrate legal-document-generator and legal-compliance-auditor
- Add legal detection to brainstorm Phase 0.5 domain leader assessment
- CLO auto-consulted via brainstorm domain detection when legal implications are involved

### Changed

- Update legal-document-generator and legal-compliance-auditor descriptions with CLO cross-reference for disambiguation

## [2.29.0] - 2026-02-22

### Added

- Add business-validator agent for 6-gate business idea validation workshop (#141)
- Add CPO (Chief Product Officer) domain leader agent for product domain orchestration (#183)
- Add product strategy detection to brainstorm Phase 0.5 domain leader assessment
- Add validation workshop route to brainstorm (STOP pattern, follows brand-architect template)
- CPO auto-consulted via brainstorm domain detection when product strategy decisions are involved
- Add disambiguation sentences to all product domain agent descriptions
- Dogfood: run business-validator on Soleur itself (verdict: PIVOT)
- Constitution: add workshop archetype principle and agent count reconciliation principle

## [2.28.3] - 2026-02-22

### Fixed

- Replace `!` code block in one-shot command with explicit LLM-executed Bash step -- the `!` auto-execution syntax fails permission checks even with `allowed-tools` frontmatter (#241 follow-up)
- Remove unused `allowed-tools` frontmatter from one-shot command
- Update bundle-ralph-loop learning to document `!` block permission failure pattern

## [2.28.2] - 2026-02-22

### Fixed

- Replace `--jq` inline flags with piped `| jq` in ship, merge-pr, and brainstorm to prevent Claude Code "quoted characters in flag names" warnings
- Add explicit `gh pr create` template to ship skill with unquoted flag names

## [2.28.1] - 2026-02-22

### Fixed

- Add missing `allowed-tools` to one-shot command frontmatter so the ralph-loop setup script executes without permission prompts

## [2.28.0] - 2026-02-22

### Added

- Add COO (Chief Operating Officer) domain leader agent for operations orchestration (#182)
- COO follows CTO's lighter 3-phase pattern (Assess, Recommend/Delegate, Sharp Edges) to orchestrate ops-advisor, ops-research, and ops-provisioner
- Add operations detection to brainstorm Phase 0.5 domain leader assessment
- COO auto-consulted via brainstorm domain detection when operational decisions are involved

### Changed

- Update all 3 ops agent descriptions with COO cross-reference for disambiguation
- Update CMO entry point from standalone skill to brainstorm detection only (consistency with CTO/COO)
- Generalize brainstorm Phase 0.5 multi-domain clause from "both marketing and engineering" to "multiple domains"
- Add scaling note to Phase 0.5 extensibility comment (consider table-driven refactor at 5+ domains)

### Removed

- Remove `/soleur:marketing` standalone skill entry point -- CMO is now accessed exclusively via brainstorm domain detection, consistent with CTO and COO

## [2.27.2] - 2026-02-22

### Fixed

- Fix `cleanup-merged` silently failing to remove worktrees when branch names contain slashes (e.g., `feat/fix-x` vs directory `feat-fix-x`)
- Use `git worktree list --porcelain` to resolve actual worktree paths instead of constructing them from branch names
- Add `--force` retry for worktree removal when untracked files block the first attempt
- Add constitution rule: never construct filesystem paths from git ref names

## [2.27.1] - 2026-02-22

### Fixed

- Remove remaining `$()` command substitution from merge-pr skill, community-manager agent, and 2 reference docs
- Add constitution rule: when fixing patterns across plugin files, search all `.md` under `plugins/soleur/` -- not just the category that triggered the report

## [2.27.0] - 2026-02-22

### Added

- Add `test-fix-loop` skill for autonomous test-fix iteration (#216)
- Auto-detects test runner, diagnoses failures, applies fixes, re-runs in a loop with git stash isolation
- Terminates on: all pass, max iterations, regression, circular fix, non-convergence, or persistent build error

## [2.26.0] - 2026-02-22

### Added

- Add `merge-pr` skill for autonomous single-PR merge pipeline with conflict resolution and cleanup (#214)
- Automates merge main, conflict resolution (deterministic for version files, Claude-assisted for code), conditional version bump, push, PR creation, CI wait, squash merge, and worktree cleanup
- Add 3 constitution rules: git stage numbers for merge-conflict reads, conflict marker detection before staging, compound ordering prohibition after push/CI

## [2.25.3] - 2026-02-22

### Fixed

- Update Plausible Analytics script tag in docs site to use site-specific snippet with outbound link, file download, and form submission tracking
- Add defensive branch check to all 3 ops agents (ops-provisioner, ops-advisor, ops-research) to warn when modifying files on main branch
- Record Plausible Analytics trial entry in expense ledger

## [2.25.2] - 2026-02-22

### Added

- Add Phase 0.5 pre-flight validation checks to `/soleur:work` command (#215)
- Environment checks: default branch detection (FAIL), worktree verification (WARN), uncommitted changes (WARN), stashed changes (WARN), detached HEAD (FAIL)
- Scope checks: plan file existence (FAIL), merge conflict zone detection (WARN), ad-hoc work detection (WARN)
- Convention verification reminder in Phase 1 "Read Plan and Clarify" step

## [2.25.1] - 2026-02-22

### Fixed

- Add HARD RULE to compound command preventing constitution promotion and route-to-definition phases from being skipped in automated pipelines (one-shot, ship)
- Fix stale `/soleur:cancel-ralph` reference in setup-ralph-loop.sh (command no longer exists)

### Changed

- Add constitution rules: never skip compound phases in pipelines; prefer embedding mechanisms over user-facing commands when bundling external plugins
- Update learning document with `synced_to` metadata after routing to definitions

## [2.25.0] - 2026-02-22

### Added

- Add `ops-provisioner` agent for guided SaaS tool account setup, plan purchase, configuration, and verification (#212)
- Update `ops-research` and `ops-advisor` agent descriptions with three-way disambiguation

## [2.24.0] - 2026-02-22

### Added

- Bundle ralph-loop into Soleur plugin -- `/soleur:one-shot` no longer depends on external ralph-loop plugin (#221)
- New `hooks/` directory with stop hook for Ralph loop session interception
- New `scripts/` directory with ralph-loop setup script

### Changed

- Update `/soleur:one-shot` to run ralph-loop setup script directly via `!` code block instead of invoking external command

## [2.23.18] - 2026-02-22

### Fixed

- Remove `$()` command substitution from all commands and skills to eliminate Claude Code permission prompts
- Affected files: 4 commands (brainstorm, plan, work, compound), 9 skills (ship, git-worktree, compound-docs, release-announce, release-docs, deploy, deploy-docs, rclone, file-todos), and AGENTS.md

## [2.23.17] - 2026-02-22

### Fixed

- Update outdated Claude 3/3.5 model IDs to Claude 4.x across 9 reference files (#219)
- Update stale Claude 4.0 IDs (`claude-sonnet-4-20250514`, `claude-opus-4-20250514`) to latest 4.6 aliases
- Update stale pricing comments to current Feb 2026 rates

## [2.23.16] - 2026-02-22

### Fixed

- Remove non-existent `marketplace.json` references from release-docs skill (#218)

## [2.23.15] - 2026-02-22

### Fixed

- Remove command substitution from one-shot command to avoid permission prompt on startup
- Fix stale `.claude/` file paths in compound-docs and review command (#220)

## [2.23.14] - 2026-02-22

### Fixed

- Fix agent description voice: 3 agents now use imperative "Use this agent when..." form per AGENTS.md compliance

## [2.23.13] - 2026-02-21

### Changed

- Sync codebase conventions to constitution: 16 new rules (shell, TypeScript, CSS, changelog, filename formats)
- Sync learnings to 8 definitions: skill-creator, test-browser, legal-document-generator, legal-compliance-auditor, security-sentinel, cmo, ship, infra-security
- Add `synced_to` frontmatter to 7 learnings for definition sync tracking

## [2.23.12] - 2026-02-21

### Changed

- Remove max-width constraint from `.community-text` so paragraphs fill full section width and align naturally

## [2.23.11] - 2026-02-21

### Changed

- Increase `.prose` reading width from 75ch to 85ch for better desktop screen utilization

## [2.23.10] - 2026-02-21

### Changed

- Center `.prose` content with `margin: 0 auto` for balanced reading layout on desktop
- Center `.page-hero` text and subtitle paragraphs to match `.hero` section styling

## [2.23.9] - 2026-02-21

### Added

- Add Plausible Analytics (cookie-free, GDPR-compliant) to docs site via `<script async>` in base layout
- Add Website Analytics Data section (4.3) to GDPR policy with Art. 6(1)(f) three-part test and ePrivacy exemption
- Add analytics as fourth processing activity in GDPR Article 30 register
- Add cookie-free analytics legal update pattern to learnings

### Changed

- Update cookie policy to disclose Plausible as cookie-free analytics provider
- Update privacy policy with Plausible analytics disclosure and legal basis
- Update data protection disclosure to include analytics alongside hosting
- Update all root legal doc copies to mirror Eleventy source changes

## [2.23.8] - 2026-02-21

### Changed

- Replace header logo image with CSS-styled mark matching footer (gold-bordered S + uppercase spaced wordmark)

## [2.23.7] - 2026-02-21

### Changed

- Add `.prose` CSS utility class for reading-width content (max-width: 75ch) with vertical rhythm
- Add gold S logo mark image to site header alongside "Soleur" wordmark
- Fix changelog styling with `#changelog-content` overrides (mono font, border-bottom, spacing)
- Add `.prose` wrapper to all 7 legal pages, changelog, and getting started page
- Add paragraph spacing for vision page community text sections

## [2.23.6] - 2026-02-21

### Changed

- Name Proton AG (Proton Mail) as email provider in GDPR policy and Article 30 register (#204)
- Add Proton Mail to third-party data table in GDPR policy Section 4.2
- Update Article 30 register Treatment N.3 with provider details, DPA reference, and adequacy decision
- Mark audit report Recommendation 3 (email provider clarification) as resolved

## [2.23.5] - 2026-02-21

### Changed

- Correct GDPR policy GitHub DPA reference: formal DPA applies to paid plans only, free-plan orgs covered by GitHub ToS + Privacy Statement (#203)

## [2.23.4] - 2026-02-21

### Changed

- Add Article 30 section and breach notification to GDPR policy
- Affirm Jikigai as data controller (was "may act as controller")
- Add GitHub DPA reference and characterize processor relationship
- Update international transfers to reference EU-US Data Privacy Framework
- Add retention period for GDPR inquiry correspondence
- Add controller identity to Privacy Policy Section 2
- Clarify Jikigai as contracting party in Terms and Conditions
- Fix GDPR response timeline (one month from receipt per Art. 12(3))
- Update related document links to use direct links across all legal docs

## [2.23.3] - 2026-02-21

### Changed

- Fix brand voice violations across 15+ public-facing files (remove "AI-powered", "meant to be", "leverage")
- Update component counts from 31/40 to 45/45 in brand guide, legal docs, and overview
- Add "plugin" boundary exception rule to brand guide
- Restructure root README: remove vision manifesto, add website badge and Learn More links
- Create /vision page on website with restructured manifesto content
- Add "Why Soleur" section to getting-started page
- Update GitHub metadata: homepage to soleur.ai, declarative description, high-traffic topics
- Update plugin.json homepage to soleur.ai

## [2.23.2] - 2026-02-21

### Fixed

- Add mandatory Session Error Inventory step (Phase 0.5) to compound command -- forces enumeration of all session errors before writing learnings, preventing silent omission in pipeline mode

## [2.23.1] - 2026-02-21

### Fixed

- Fix ralph-loop plugin namespace in one-shot command (`ralph-wiggum:ralph-loop` -> `ralph-loop:ralph-loop`)

## [2.23.0] - 2026-02-21

### Added

- Domain Leader pattern with documented interface contract (assess/recommend/delegate/review)
- CMO agent (`cmo`) -- marketing domain leader orchestrating 11 specialist agents, replaces `marketing-strategist`
- CTO agent (`cto`) -- engineering domain leader for brainstorm and planning participation
- `/soleur:marketing` skill with `audit`, `strategy`, and `launch` sub-commands
- LLM-based domain detection in brainstorm command Phase 0.5, replacing keyword substring matching

### Changed

- Brainstorm command Phase 0.5 rewritten from keyword-based brand routing to semantic domain assessment with marketing and engineering routing
- Brand workshop preserved as special case within marketing domain detection
- Updated disambiguation sentences in `conversion-optimizer` and `retention-strategist` (marketing-strategist -> cmo)
- Agent count 44 -> 45 (removed marketing-strategist, added cmo + cto), skill count 44 -> 45

### Removed

- `marketing-strategist` agent (absorbed into `cmo` with all sharp edges preserved)

## [2.22.6] - 2026-02-21

### Added

- Session-Start Hygiene section in AGENTS.md -- runs `cleanup-merged` at the start of every session to remove stale worktrees from prior sessions
- Constitution rule enforcing session-start worktree cleanup as recovery mechanism
- Safety note in ship/SKILL.md Phase 8 about deferred cleanup being handled by next session

### Changed

- Updated Workflow Completion Protocol step 10 to name the merge-then-session-end gap explicitly

## [2.22.5] - 2026-02-20

### Added

- 7 legal document pages on the docs site (Terms & Conditions, Privacy Policy, Cookie Policy, GDPR Policy, Acceptable Use Policy, Data Protection Disclosure, Disclaimer)
- Legal landing page with card grid linking to all 7 documents
- "Legal" link in site footer

### Fixed

- Replaced all `soleur.dev` references with `soleur.ai` across legal documents
- Corrected legal entity name to Jikigai (incorporated in France)
- Updated contact email to `legal@jikigai.com`
- Added registered office address (25 rue de Ponthieu, 75008 Paris, France)

## [2.22.4] - 2026-02-20

### Changed

- Enforced CI-must-pass gate before merge in ship skill and Workflow Completion Protocol -- removed "merge now or later?" prompt, always wait for CI
- Added "merge main" step before version bump to reduce version conflicts on parallel branches

## [2.22.3] - 2026-02-20

### Changed

- Extended compound skill to capture session-level errors (failed commands, wrong approaches, process mistakes) alongside the target problem documentation (#168)

## [2.22.2] - 2026-02-20

### Changed

- Updated landing page, brand guide, plugin description, and README copy to emphasize self-improvement ("reviews, plans, builds, remembers, and self-improves")
- Updated closing sentence to "Every feature or project gets better and faster than the last"

## [2.22.1] - 2026-02-20

### Changed

- Trimmed all 44 agent description frontmatter to remove example blocks and add disambiguation sentences, reducing cumulative agent description size from ~15.8k tokens to ~2.5k tokens for improved performance

## [2.22.0] - 2026-02-20

### Added

- 8 new marketing agents consolidated from coreyhaines31/marketingskills (MIT): marketing-strategist, pricing-strategist, copywriter, conversion-optimizer, paid-media-strategist, analytics-analyst, retention-strategist, programmatic-seo-specialist
- NOTICE file with MIT attribution for adopted material

### Changed

- Expanded growth-strategist with content pillar/cluster planning, searchable vs shareable content classification, scoring matrix, and SAP (Structure/Authority/Presence) AEO framework
- Expanded seo-aeo-analyst with E-E-A-T signal checks, Core Web Vitals source-level indicators, and JavaScript-injected schema detection warning
- Marketing agent count 4 -> 12, total agent count 36 -> 44

## [2.21.0] - 2026-02-20

### Added

- New Legal domain with 2 agents: `legal-document-generator` and `legal-compliance-auditor`
- New `legal-generate` skill for drafting legal documents (Terms, Privacy Policy, Cookie Policy, GDPR, AUP, DPA, Disclaimer)
- New `legal-audit` skill for auditing existing legal documents for compliance gaps
- Legal domain CSS variable (`--cat-legal`) and docs integration (agents.js, skills.js)

## [2.20.1] - 2026-02-20

### Changed

- Enhanced growth-strategist agent with Princeton GEO techniques: source citations check, statistics/specificity check, and GEO impact prioritization ordering
- Added AI crawler access verification (GPTBot, PerplexityBot, ClaudeBot, Google-Extended) to seo-aeo-analyst agent checklist
- Extended validate-seo.sh CI script with robots.txt AI bot blocking checks
- Updated growth skill Task prompts (aeo, fix sub-commands) to include new GEO checks
- Added constitution principle: update skill Task prompts when agent instructions change

## [2.20.0] - 2026-02-20

### Added

- New `semgrep-sast` review agent for deterministic SAST scanning using semgrep CLI, complementing security-sentinel's LLM-based architectural review
- Conditional semgrep invocation in `/soleur:review` command (runs when semgrep CLI is installed and PR modifies source code)

## [2.19.0] - 2026-02-19

### Added

- New `content-writer` skill for generating full article drafts with brand-consistent voice, Eleventy frontmatter, JSON-LD, and FAQ schema
- New `growth fix` sub-command on the `growth` skill to audit and apply keyword/copy/AEO fixes to local source files
- Execution capability added to `growth-strategist` agent (keyword injection, FAQ generation, definition paragraphs, meta description rewrites)

## [2.18.1] - 2026-02-19

### Fixed

- Landing page feature grid cards now maintain logical groupings on mobile and tablet viewports (#160)
- Split single feature grid into separate department and workflow grids with "The Workflow" sublabel
- Added 2-column mobile responsive override to preserve card pairing on narrow screens
- Changed sublabel from `<p>` to `<h3>` for proper heading hierarchy and screen reader navigation

## [2.18.0] - 2026-02-19

### Added

- New `functional-discovery` agent under engineering/discovery for detecting community tools with similar functionality to features being planned
- Phase 1.5b in `/soleur:plan` command to spawn functional-discovery after stack-gap check, searching registries before building redundant features

## [2.17.0] - 2026-02-19

### Changed

- Merged Design domain under Product domain: `agents/design/ux-design-lead.md` moved to `agents/product/design/ux-design-lead.md`
- Agent renamed from `soleur:design:ux-design-lead` to `soleur:product:design:ux-design-lead`
- Reduced top-level agent domains from 5 to 4 (Engineering, Marketing, Operations, Product)
- Removed `--cat-design` CSS variable from docs (replaced by `--cat-tools` for product domain)

## [2.16.0] - 2026-02-19

### Added

- New `growth-strategist` agent under marketing domain for content strategy analysis (keyword research, content auditing, gap analysis, AI agent consumability)
- New `growth` skill with audit/plan/aeo sub-commands for content strategy workflows

## [2.15.3] - 2026-02-19

### Fixed

- Ship skill: added explicit warning not to use `--delete-branch` on merge when worktrees are active

## [2.15.2] - 2026-02-19

### Added

- Community hub page on docs site at `pages/community.html` with Discord, GitHub, contributing, support, and code of conduct sections

### Changed

- Header nav: replaced hardcoded GitHub/Discord external links with single data-driven "Community" link
- Footer nav: replaced GitHub/Discord entries with Community page link
- Added `_site_test/` to `.gitignore` for test build output
- Added `.community-card-link` and `.community-text` CSS classes to avoid inline styles

## [2.15.1] - 2026-02-19

### Changed

- All Discord webhook payloads now include `username` and `avatar_url` fields in community skill, community-manager agent, and discord-content skill
- Added webhook identity guideline to Important Guidelines sections across all Discord-posting components
- Added webhook identity rule to constitution (Architecture > Always)

## [2.15.0] - 2026-02-19

### Added

- New `seo-aeo-analyst` agent under marketing domain for auditing Eleventy docs sites
- New `seo-aeo` skill with audit/fix/validate sub-commands for SEO and AEO
- New `validate-seo.sh` CI validation script checking canonical URLs, JSON-LD, OG tags, Twitter cards, llms.txt, and sitemap
- SEO meta tags: canonical URL, og:locale, Twitter/X cards, enhanced OG tags on all pages
- JSON-LD structured data: WebSite + WebPage on all pages, SoftwareApplication on homepage
- `llms.txt` template following llms-txt.org spec for AI model discoverability
- Build-time changelog rendering using markdown-it (replaces client-side JS fetch)
- Collection-based `sitemap.xml` with `lastmod` dates using `dateToRfc3339` filter
- SEO validation step in `deploy-docs.yml` CI pipeline
- Tests for `validate-seo.sh` and `changelog.js`

### Changed

- Changelog page now renders at build time instead of fetching from GitHub raw at runtime
- 404 page excluded from collections (was appearing in sitemap)

## [2.14.2] - 2026-02-19

### Added

- Hi-res 512x512 brand logo mark (`logo-mark-512.png`) for Discord and social platform avatars
- Updated brand guide component counts from 23+ agents/36+ skills to 30+ agents/39+ skills

### Fixed

- Plugin description skill count corrected from 38 to 39

## [2.14.1] - 2026-02-18

### Added

- New `setup` sub-command for the community skill that automates Discord bot configuration
- New `discord-setup.sh` script with sub-commands: validate-token, discover-guilds, list-channels, create-webhook, write-env, verify
- Bot token passed via `DISCORD_BOT_TOKEN_INPUT` env var (never as CLI argument) for security
- .env written with chmod 600 permissions (owner-only read/write)
- Browser-guided bot creation via agent-browser (opens Discord Developer Portal)

### Changed

- Community skill Phase 0 env var errors now direct users to `/soleur:community setup`
- Community-manager agent prerequisites now reference the setup sub-command

## [2.14.0] - 2026-02-18

### Added

- New `agent-finder` agent for community agent/skill discovery via external registries
- New `agents/community/` directory for community-installed agents
- Community discovery check in `/plan` command (Phase 1.5) -- detects uncovered stacks and offers to install community agents from trusted registries
- New `docs-site` skill for scaffolding Eleventy documentation sites with data-driven catalog pages
- Migrate documentation site from hand-maintained HTML to Markdown + Eleventy v3 (11ty)
- Auto-generate agent and skill catalog pages from source file frontmatter at build time
- Build-time data injection for version strings and component counts (eliminates hardcoded values)
- Auto-generated sitemap.xml from page collection
- Eleventy config (`eleventy.config.js`) and npm scripts (`docs:dev`, `docs:build`)
- New community-manager agent (`agents/marketing/community-manager.md`) for analyzing Discord and GitHub activity, generating weekly digests, and reporting community health metrics
- New community skill (`skills/community/SKILL.md`) with sub-commands: digest, health, post, welcome
- Shell scripts for Discord Bot API (`discord-community.sh`) and GitHub API (`github-community.sh`) data collection

### Changed

- Add `stack: rails` field to `dhh-rails-reviewer` and `kieran-rails-reviewer` agents for gap detection
- Renumber `/plan` phases: Research Decision (1.5 -> 1.6), External Research (1.5b -> 1.6b), Consolidate (1.6 -> 1.7)
- Refactor `release-docs` skill to remove HTML editing instructions (catalog pages now auto-generate)
- Refactor `deploy-docs` skill for Eleventy build workflow and `_site/` output validation
- Update deploy-docs GitHub Actions workflow with Node.js build step and expanded path triggers

### Removed

- Delete 7 hand-maintained HTML source files (replaced by Nunjucks/Markdown templates)

## [2.13.1] - 2026-02-18

### Changed

- Add reference to GitHub Pages wiring learning in infra-security agent prompt
- Document MCP integration audit findings: Cloudflare and GitHub MCP servers not viable for plugin bundling (OAuth/PAT required, no `headers` field in plugin.json)

## [2.13.0] - 2026-02-17

### Changed

- Consolidate agent categories from 6 to 5 real company domains: Design, Engineering, Marketing, Operations, Product
- Move 5 research agents from `agents/research/` to `agents/engineering/research/`
- Move `pr-comment-resolver` from `agents/workflow/` to `agents/engineering/workflow/`
- Move `spec-flow-analyzer` from `agents/workflow/` to new `agents/product/` domain
- Remove "Cross-domain" grouping from README -- all agents now belong to a domain
- Update docs agents page to reflect new category structure

## [2.12.5] - 2026-02-17

### Fixed

- Remove Option C ("continue on default branch") from work command -- agents must always branch before editing
- Add Step 0 branch isolation to one-shot command -- creates feature branch before plan when on default branch

## [2.12.4] - 2026-02-17

### Changed

- Consolidate Skills page from 8 categories to 4: Content & Release, Development, Review & Planning, Workflow
- Order skill categories alphabetically to match Agents page convention
- Update release-docs skill to reference new skill category names

## [2.12.3] - 2026-02-17

### Fixed

- Sort agent categories alphabetically on Agents page (Design, Engineering, Marketing, Operations, Research, Workflow)
- Fix "Fixing a Bug" workflow on Getting Started to recommend one-shot instead of manual work/review/compound

## [2.12.2] - 2026-02-17

### Added

- Sync command now includes Phase 4: Definition Sync -- scans learnings against skill/agent/command definitions and proposes one-line bullet edits (#110)
- Compound-docs Step 8 now writes `synced_to` to learning frontmatter after routing, enabling idempotent sync across both systems

## [2.12.1] - 2026-02-17

### Changed

- Restructure docs site navigation: Get Started first, remove Commands and MCP pages
- Collapse 3 Engineering sub-categories into single Engineering section on Agents page
- Add Common Workflows section to Getting Started page with use case scenarios
- Convert Getting Started workflow steps to card treatment for visual consistency
- Update Learn More links to reference Agents, Skills, and Changelog
- Remove `.workflow-steps` CSS (replaced by `.command-item` cards)
- Update release-docs skill to remove commands.html and mcp-servers.html references
- Update deploy-docs workflow validation to match remaining pages

### Removed

- Delete `commands.html` page (redundant with Getting Started)
- Delete `mcp-servers.html` page (minimal content)
- Remove Commands and MCP links from sitemap.xml

## [2.12.0] - 2026-02-17

### Added

- Compound now routes learnings to skill/agent/command definitions (closes #104)
  - Step 8 in compound-docs: detects active components, proposes one-line bullet edits with Accept/Skip/Edit
  - Compound command updated with routing summary section
  - Feeds insights back into the instructions that govern behavior, preventing repeated mistakes

### Changed

- Renamed compound-docs "7-Step Process" heading to "Documentation Capture Process" to avoid stale numbering

## [2.11.3] - 2026-02-17

### Fixed

- Fix color mismatch between Quick Commands (white) and Workflow (gold) on Getting Started page
- Fix command card text overlap on Commands page by switching from fixed to auto grid columns
- Fix mobile nav panel and backdrop not spanning full viewport height (backdrop-filter containing block issue)
- Add mobile nav backdrop overlay with click-to-dismiss
- Fix MCP badge stretching full width inside flex container
- Remove empty usage code element from /soleur:help command card

### Changed

- Add border-radius to problem cards and feature cards for visual consistency
- Add scroll fade indicator to category pill navigation
- Restyle Learn More links as card grid on Getting Started page
- Switch feature grid from rigid 5-column to responsive auto-fill layout

## [2.11.2] - 2026-02-16

### Changed

- Update docs site with 3 missing agents: infra-security, ops-advisor, ops-research
- Add Operations category to agents page
- Update agent count from 25 to 28 across all pages
- Update landing page stats to 28 agents and 37 skills

## [2.11.1] - 2026-02-16

### Changed

- Update docs site for custom domain: replace `jikig-ai.github.io/soleur/` base paths and OG URLs with `soleur.ai/`
- Add `CNAME` file for GitHub Pages custom domain persistence

## [2.11.0] - 2026-02-16

### Added

- `infra-security` agent (`soleur:engineering:infra:infra-security`) for domain security auditing, DNS configuration, and service wiring via Cloudflare REST API (closes #100)
  - Audit Protocol: security posture assessment with severity-graded findings (SSL/TLS, DNSSEC, HSTS, WAF)
  - Configure Protocol: DNS record CRUD with confirmation-before-mutation safety gate
  - Wire Recipes: GitHub Pages wiring (CNAME, apex A records, SSL configuration)
  - Graceful degradation: falls back to CLI tools (dig, openssl) when API credentials unavailable

## [2.10.2] - 2026-02-16

### Added

- Discord server invite link to docs site navigation header and footer on all 8 HTML pages

## [2.10.1] - 2026-02-16

### Changed

- `/soleur:plan` now automatically runs plan review (DHH, Kieran, Simplicity reviewers) after plan generation instead of offering it as an optional post-generation choice

## [2.10.0] - 2026-02-16

### Added

- `ops-research` agent for domain, hosting, tools/SaaS research and cost optimization with browser automation support

### Changed

- Updated `ops-advisor` to delegate live research to `ops-research` (replaced Advisory Limitations with Research Delegation section)

## [2.9.3] - 2026-02-16

### Fixed

- Consistent messaging: changed "trillion-dollar" to "billion-dollar" in thesis quote across brand guide, docs site, brainstorm doc, and design file to match the hero headline

### Changed

- Removed version badge from docs site header (no more per-release HTML updates across 8 files)
- Changelog page now fetches CHANGELOG.md from GitHub at runtime instead of static HTML duplication
- Removed `.version-badge` CSS class

## [2.9.2] - 2026-02-14

### Fixed

- Changelog page now includes all releases (v1.1.0 through v2.9.1), was stuck at v2.6.2
- Favicon regenerated at higher quality with properly centered S using Cormorant Garamond
- Anchor links on agents and skills pages no longer redirect to home page (`<base>` tag interference)
- Workflow step commands on getting-started page now match quick commands styling (gold accent)

## [2.9.1] - 2026-02-14

### Changed

- Rewrite docs site with Solar Forge brand identity landing page
  - Hero section with tagline, stats strip, problem cards, quote, feature grid, and CTA
  - Self-hosted Cormorant Garamond and Inter fonts (woff2)
  - Favicon and OG image generated from brand .pen file
  - Dark-only theme (removed light/dark toggle and localStorage script)
  - Unified footer across all pages
  - Deleted dead `js/main.js`
  - WCAG AA contrast compliance (tertiary text #737373)

## [2.9.0] - 2026-02-14

### Added

- `ops-advisor` agent (`soleur:operations:ops-advisor`) for tracking operational expenses, managing domain registrations, and advising on hosting
  - Reads and updates `knowledge-base/ops/expenses.md` (recurring and one-time cost ledger)
  - Reads and updates `knowledge-base/ops/domains.md` (domain registry with renewal dates and DNS)
  - Summarizes monthly/annual spend by category, flags upcoming renewals within 30 days
  - Advisory only (no live API calls, no automated purchases)
  - Auto-creates data files with headers on first use
- New `agents/operations/` subdirectory for operations domain agents
- New `knowledge-base/ops/` directory with structured markdown data files for expense and domain tracking
- New `ux-design-lead` agent under `agents/design/` for visual design in .pen files using Pencil MCP
- New `design/` top-level agent domain for cross-cutting visual design work
- `knowledge-base/design/brand/` with .pen design file from brand identity brainstorm
- Brainstorm command Phase 4 handoff now includes "Create visual designs" option
- `.playwright-mcp/` added to .gitignore (ephemeral browser session artifacts)

## [2.7.0] - 2026-02-13

### Added

- Documentation site at `plugins/soleur/docs/` with Solar Forge brand identity
  - Landing page with hero, stats strip, and overview cards
  - Getting Started guide with installation and core workflow
  - Agents reference (23 agents across 5 categories)
  - Skills reference (37 skills across 8 categories)
  - Commands reference (8 workflow commands)
  - Changelog page (v1.17.0 through v2.5.0)
  - MCP Servers page (Context7)
  - Solar Forge theme: dark (#0A0A0A) + gold (#C9A962), Cormorant Garamond headlines, Inter body, JetBrains Mono code
  - Responsive design with mobile nav toggle and sticky sidebar
  - Deploys automatically via existing GitHub Pages workflow

## [2.6.1] - 2026-02-13

### Fixed

- `/ship` Phase 7: add pre-push gate that blocks when unarchived KB artifacts exist -- prevents skipping `/compound` by re-verifying artifact consolidation before `git push`

## [2.6.0] - 2026-02-13

### Added

- `terraform-architect` agent (`soleur:engineering:infra:terraform-architect`) for generating and reviewing Terraform configurations for Hetzner Cloud and AWS (closes #39)
  - Generation protocol with modular file structure, Hetzner firewall/SSH/labels requirements, AWS VPC/S3/encryption requirements
  - Review protocol with severity-based findings (Critical/High/Medium/Low) and remediation HCL
  - State management advisory (S3 native locking for TF 1.10+, Hetzner Object Storage backend)
  - Cost optimization with ARM instance preference and pricing disclaimers
- New `agents/engineering/infra/` subdirectory for infrastructure agents

## [2.5.0] - 2026-02-13

### Added

- Brainstorm command detects brand/marketing topics and offers to route to the brand-architect agent (#76)
- New "Specialized Domain Routing" pattern in brainstorm Phase 0 for future domain extensions

## [2.4.0] - 2026-02-13

### Added

- `deploy` skill (`/soleur:deploy`) for container deployment to remote servers (closes #40)
  - Four-phase workflow: validate env/Docker/SSH, show plan, execute build+push+deploy, verify health
  - Generalized from `apps/telegram-bridge/scripts/deploy.sh` with configurable env vars
  - Health check with fixed 3s interval retries (5 attempts)
  - First-time setup guide in `references/hetzner-setup.md`

### Fixed

- `/soleur:one-shot` missing `/soleur:compound` step -- learnings were silently skipped

## [2.3.1] - 2026-02-12

### Added

- `auto-release.yml` GitHub Actions workflow -- automatically creates GitHub Releases and posts to Discord when plugin.json version changes on merge to main
  - Reads version from plugin.json, extracts changelog section, creates release via `gh release create`
  - Posts to Discord directly (GITHUB_TOKEN releases don't trigger other workflows)
  - Idempotent: skips if release already exists

### Changed

- `/ship` Phase 8: release creation is now automatic via CI; manual `/release-announce` retained as fallback
- `release-announce.yml`: added comment clarifying it handles manually-created releases only

## [2.3.0] - 2026-02-12

### Added

- New `agents/marketing/` domain for brand and marketing agents
- `brand-architect` agent -- interactive brand identity workshop that produces a structured brand guide document at `knowledge-base/overview/brand-guide.md`, covering identity, voice, visual direction, and channel notes
- `discord-content` skill -- creates and posts brand-consistent community content to Discord via webhook, with inline brand voice validation and user approval before posting
- Brand Guide Contract defining exact `##` heading names that downstream tools depend on

## [2.2.3] - 2026-02-12

### Fixed

- `release-announce` workflow: `DISCORD_WEBHOOK_URL` changed from repository variable to secret
  - Secrets cannot be checked in job-level `if` conditions, so the check moves inside the step
  - Workflow now always runs and shows "success" instead of "skipped" when secret is absent

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
