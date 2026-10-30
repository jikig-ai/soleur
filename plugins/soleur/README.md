# Soleur

A full AI organization across engineering, finance, marketing, legal, operations, product, sales, and support. Every decision you make teaches the system. Every project gets better and faster than the last.

## Quick Start

Install the plugin:

**Devin CLI:**

```bash
devin plugins install jikig-ai/soleur#plugins/soleur -y
```

Start a Devin session and use `/soleur:go <what you want to do>`. Use `-y` to skip the confirmation prompt. If the install hangs or fails, clone the repository and install from `./soleur/plugins/soleur`.

**Claude Code (recommended, via the published marketplace):**

```bash
claude plugin marketplace add jikig-ai/soleur-marketplace
claude plugin install soleur@soleur-marketplace
```

**Grok Build:** load the same in-repo plugin from the repository root — `grok inspect` must list the Soleur plugin, then start a session with `grok`. Use `/go <intent>`. See the [Grok Build onboarding guide](../../knowledge-base/engineering/grok-onboarding.md).

**OpenCode:**

Install Soleur into your OpenCode config directory via npm (this needs `bun` on `PATH`), then start a session:

```bash
npx @soleur/opencode install
# or: bunx @soleur/opencode install
```

Verify the install with `npx @soleur/opencode install --check` — it prints `opencode-install ok` when the vendored payload in `~/.config/opencode/soleur/` matches. (From a local checkout of this repository, you can also run `bun plugins/soleur/scripts/install-opencode-adapter.ts` and keep the checkout in place.) Use `/go <what you want to do>`. Commands are bare (`/go`, `/sync`, `/help`) and skills are invoked by bare id (`plan`, not `soleur:plan`), because OpenCode has no `soleur:` namespace. Two guards decide shell commands on OpenCode, and both run for real — a `deny` blocks the call, an `ask` opens a prompt — but they decide shell calls only: actions taken through OpenCode's code-mode `execute` are not covered. Soleur's operator-stage approval gate is not wired on OpenCode: those flows refuse rather than approve. OpenCode has no Stop hook, so the pipeline's `<promise>DONE</promise>` completion marker is advisory: a finished gate sequence is reported rather than hard-stopped, and autonomous skills rely on their own structural checks. `/version` is installed but reports an unknown version, because the canonical command resolves the plugin through `CLAUDE_PLUGIN_ROOT`, which this harness does not set. Full routing rules and the remaining capability differences: [OpenCode instructions](opencode/INSTRUCTIONS.md).

## The Soleur Workflow

**Local data the plugin writes:** one metadata-only line per `/soleur:go` routing
decision into `.soleur/decisions.jsonl` at your project root (event names,
skill/agent labels, timestamps — never prompt text, args, or file paths; the
directory self-ignores in git and nothing leaves your machine). Opt out with
`SOLEUR_DISABLE_DECISION_LOG=1`. See
[ADR-254](../../knowledge-base/engineering/architecture/decisions/ADR-254-tester-owned-local-decision-log.md).

**Codex:** install with `codex plugin marketplace add jikig-ai/soleur --sparse .agents/plugins --sparse plugins/soleur`,
then `codex plugin add soleur@soleur`. Start a new session, review `/hooks`,
and use `$soleur:go <intent>`. Codex shares the same skills and agent
definitions; see [compatibility instructions](codex/INSTRUCTIONS.md).

**Devin CLI:** install with `devin plugins install jikig-ai/soleur#plugins/soleur -y` and update with `devin plugins update soleur`. To work
on the plugin from this checkout, run `bash scripts/setup-devin.sh`, start a Devin session,
and use `/soleur:go <intent>`. Devin shares the same skills and agent definitions; see
[compatibility instructions](devin/INSTRUCTIONS.md). Devin **Cloud** sessions run under
Soleur Cloud Mode — skills, rules, and MCP carry, but plugin subagents and
SessionStart/SessionEnd hooks are absent, and degradation is disclosed rather than
silent; see the [cloud-vs-local capability matrix](devin/INSTRUCTIONS.md#cloud-mode-devin-cloud-sessions).

The recommended way to use Soleur is through the unified entry point:

```text
/soleur:go <what you want to do>
```

This classifies your intent and routes to the right workflow skill. For existing codebases, run `/soleur:sync` first to populate your knowledge-base.

Claude Code: `/soleur:go`. Grok Build: `/go`. Codex: `$soleur:go`. Devin CLI: `/soleur:go`. OpenCode: `/go`.

| Step | Claude Code | Grok Build | Codex | Devin CLI | OpenCode |
|------|-------------|------------|-------|-----------|----------|
| Entry | `/soleur:go` | `/go` | `$soleur:go` | `/soleur:go` | `/go` |
| Sync | `/soleur:sync` | `/sync` | `$soleur:sync` | `/soleur:sync` | `/sync` |
| Help | `/soleur:help` | `/local:help` | `$soleur:help` | `/soleur:help` | `/help` |
| Version | `/soleur:version` (Claude Code only) | not available | not available | not available | `/version` (reports unknown) |
| Next skill | Skill tool `soleur:<skill>` | Read `SKILL.md` in this process (`/<skill>`) | Load `$soleur:<skill>`, or read `SKILL.md` | Slash `/soleur:<skill>` | `skill` tool, bare id (`plan`) |

Per-harness setup guides: [Claude Code](https://code.claude.com/docs/en/plugins) · [Grok Build](../../knowledge-base/engineering/grok-onboarding.md) · [Codex](codex/INSTRUCTIONS.md) · [Devin](devin/INSTRUCTIONS.md) · [OpenCode](opencode/INSTRUCTIONS.md).

The 6-step workflow (invoked automatically via `/soleur:go` or Skill tool `soleur:<skill>` on Claude Code; via `/go` then Read `SKILL.md` in this process on Grok Build; via `/go` then the Skill tool with the bare id on OpenCode):

```text
brainstorm  -->  plan  -->  work  -->  review  -->  compound  -->  ship
```

| Skill | Purpose |
|-------|---------|
| `brainstorm` | Explore requirements and approaches before planning |
| `plan` | Create structured implementation plans |
| `work` | Execute plans with incremental commits |
| `review` | Run comprehensive code review with specialized agents |
| `compound` | Capture learnings for future work |
| `ship` | Prepare the feature for production deployment |
| `one-shot` | Full autonomous workflow from plan to PR |

## Components

| Component | Count |
|-----------|-------|
| Agents | 67 |
| Commands | 4 |
| Skills | 105 |
| MCP Servers | 5 |

## Agents

Agents are organized by domain, then by function.

### Marketing (12)

| Agent | Description |
|-------|-------------|
| `analytics-analyst` | Analytics tracking setup, event taxonomy design, A/B test planning, and attribution modeling |
| `brand-architect` | Interactive brand identity workshop producing structured brand guides |
| `cmo` | Marketing domain leader -- orchestrates marketing strategy and delegates to specialist agents |
| `conversion-optimizer` | Analyze and optimize conversion surfaces: landing pages, signup flows, onboarding, forms, popups, paywalls |
| `copywriter` | Marketing copy for landing pages, email sequences, cold outreach, social content, and copy editing |
| `growth-strategist` | Content strategy analysis and execution: keyword research, content auditing, gap analysis, AI agent consumability, and applying fixes |
| `paid-media-strategist` | Paid advertising campaigns across Google, Meta, and LinkedIn: structure, targeting, budget, and creative |
| `pricing-strategist` | SaaS pricing strategy: research methods, tier design, value metric selection, and competitive analysis |
| `programmatic-seo-specialist` | Template-based SEO page generation at scale: comparison pages, alternatives, integrations |
| `retention-strategist` | Churn prevention, payment recovery, referral programs, and free tool strategy |
| `seo-aeo-analyst` | Audit Eleventy docs sites for SEO and AEO (AI Engine Optimization) issues |

### Finance (4)

| Agent | Description |
|-------|-------------|
| `cfo` | Finance domain leader -- orchestrates financial strategy and delegates to specialist agents |
| `budget-analyst` | Create budget plans, analyze spending allocation, model burn rate, and review budget-to-actual variance |
| `revenue-analyst` | Track revenue, build financial forecasts, model P&L projections, and analyze revenue trends |
| `financial-reporter` | Generate financial summaries, cash flow statements, and periodic financial reports |

### Legal (3)

| Agent | Description |
|-------|-------------|
| `clo` | Legal domain leader -- orchestrates legal strategy and delegates to specialist agents |
| `legal-document-generator` | Generate draft legal documents (Terms, Privacy Policy, Cookie Policy, GDPR, AUP, DPA, Disclaimer) |
| `legal-compliance-auditor` | Audit legal documents for compliance gaps, outdated clauses, and cross-document consistency |

### Engineering (31)

| Agent | Description |
|-------|-------------|
| `cto` | Engineering domain leader -- assesses technical implications and flags architecture risks during brainstorm and planning |
| `prompt-engineer` | Author, optimize, and test prompts and agent/skill definitions; ship happy/edge/failure prompt test cases |

#### Review (17)

| Agent | Description |
|-------|-------------|
| `agent-native-reviewer` | Verify features are agent-native (action + context parity) |
| `architecture-strategist` | Analyze architectural decisions and compliance |
| `code-quality-analyst` | Formal quality reports with severity-scored smells and prioritized refactoring roadmaps |
| `code-simplicity-reviewer` | Final pass for simplicity and minimalism |
| `data-integrity-guardian` | Database migrations and data integrity |
| `data-migration-expert` | Validate ID mappings match production, check for swapped values |
| `deployment-verification-agent` | Create Go/No-Go deployment checklists for risky data changes |
| `dhh-rails-reviewer` | Rails review from DHH's perspective |
| `kieran-rails-reviewer` | Rails code review with strict conventions |
| `legacy-code-expert` | Safely modify untested legacy code using Feathers' dependency-breaking techniques |
| `observability-coverage-reviewer` | Verify every new error path / log call is reachable from Sentry/Better Stack without SSH (server-side code only) |
| `pattern-recognition-specialist` | Analyze code for patterns and anti-patterns |
| `performance-oracle` | Performance analysis and optimization |
| `security-sentinel` | Security audits, vulnerability assessments, and multi-org / workspace boundary integrity (R1-R6 checklist) |
| `semgrep-sast` | Deterministic SAST scanning using semgrep CLI for known vulnerability patterns |
| `test-design-reviewer` | Score test quality using Farley's 8 properties with weighted rubric |
| `user-impact-reviewer` | Enumerate user-facing failure modes when a plan declares Brand-survival threshold = single-user incident |

#### Discovery (2)

| Agent | Description |
|-------|-------------|
| `agent-finder` | Find and install community agents/skills from trusted registries for uncovered stacks |
| `functional-discovery` | Search community registries for skills/agents with similar functionality to prevent redundant development |

#### Design (1)

| Agent | Description |
|-------|-------------|
| `ddd-architect` | Domain-Driven Design with strategic bounded contexts and tactical patterns |

#### Infra (2)

| Agent | Description |
|-------|-------------|
| `infra-security` | Audit domain security posture, configure DNS records, and wire domains to services via Cloudflare API |
| `terraform-architect` | Generate and review Terraform configurations for Hetzner Cloud and AWS |

#### Research (5)

| Agent | Description |
|-------|-------------|
| `best-practices-researcher` | Gather external best practices and examples |
| `framework-docs-researcher` | Research framework documentation and best practices |
| `git-history-analyzer` | Analyze git history and code evolution |
| `learnings-researcher` | Search institutional learnings for relevant past solutions |
| `repo-research-analyst` | Research repository structure and conventions |

#### Workflow (1)

| Agent | Description |
|-------|-------------|
| `pr-comment-resolver` | Address PR comments and implement fixes |

### Operations (5)

| Agent | Description |
|-------|-------------|
| `coo` | Operations domain leader -- orchestrates ops-advisor, ops-research, and ops-provisioner |
| `ops-advisor` | Track expenses, manage domains, advise on hosting |
| `ops-provisioner` | Guide SaaS tool account setup, purchase, configuration, and verification |
| `ops-research` | Research domains, hosting, tools/SaaS, and cost optimization with browser automation |

### Product (5)

| Agent | Description |
|-------|-------------|
| `business-validator` | Validate business ideas through structured 6-gate workshop (market research, competitive analysis, business model) |
| `competitive-intelligence` | Recurring competitive landscape monitoring and market research reports |
| `cpo` | Orchestrate product domain -- assess product strategy, validate business models, delegate to specialist agents |
| `spec-flow-analyzer` | Analyze user flows and identify gaps in specifications |

#### Design (1)

| Agent | Description |
|-------|-------------|
| `ux-design-lead` | Visual design in .pen files using Pencil MCP (wireframes, screens, components). Requires [Pencil extension](https://docs.pencil.dev/getting-started/installation). |

### Sales (4)

| Agent | Description |
|-------|-------------|
| `cro` | Sales domain leader -- orchestrates sales strategy and delegates to specialist agents |
| `deal-architect` | Create proposals, SOWs, competitive battlecards, objection-handling playbooks, and deal negotiation frameworks |
| `outbound-strategist` | Design outbound prospecting sequences, ICP targeting, lead scoring, and multi-channel cadence strategies |
| `pipeline-analyst` | Analyze sales pipeline health, model revenue forecasts, define stage criteria, and review deal velocity |

### Support (3)

| Agent | Description |
|-------|-------------|
| `cco` | Support domain leader -- orchestrates support strategy and delegates to specialist agents |
| `community-manager` | Analyze community engagement, generate digests, and assess health metrics across Discord, GitHub, and X/Twitter |
| `ticket-triage` | Classify and route GitHub issues by severity (P1/P2/P3) and domain |

## Commands

All commands use the `soleur:` prefix to avoid collisions with built-in commands:

| Command | Description |
|---------|-------------|
| `/soleur:go` | Unified entry point -- classifies intent and routes to the right workflow skill |
| `/soleur:sync` | Analyze codebase and populate knowledge-base with conventions, patterns, and overview documentation |
| `/soleur:help` | List all available Soleur commands, agents, and skills |
| `/soleur:version` | Show the installed plugin version and whether a newer release exists |

## Skills

### Content & Release

| Skill | Description |
|-------|-------------|
| `brainstorm-techniques` | Explore intent, approaches, and design decisions |
| `changelog` | Create engaging changelogs for recent merges |
| `compound` | Document solved problems to compound team knowledge |
| `community` | Manage community presence across Discord, GitHub, and X/Twitter |
| `compound-capture` | Capture solved problems as categorized documentation |
| `deploy-docs` | Validate and prepare documentation for deployment |
| `docs-site` | Scaffold Eleventy documentation sites with data-driven catalogs |
| `discord-content` | Create and post brand-consistent community content to Discord |
| `every-style-editor` | Review copy for Every's style guide compliance |
| `feature-video` | Record video walkthroughs and add to PR description |
| `file-todos` | File-based todo tracking system |
| `gemini-imagegen` | Generate and edit images using Google's Gemini API |
| `content-writer` | Generate full article drafts with brand voice, Eleventy frontmatter, and JSON-LD |
| `growth` | Content strategy: keyword research, content auditing, gap analysis, fix, AI agent consumability |
| `legal-audit` | Audit legal documents for compliance gaps, outdated clauses, and cross-document consistency |
| `legal-generate` | Generate draft legal documents from company context (14 document types, 3 jurisdictions) |
| `release-announce` | Announce releases via GitHub Releases (CI posts to Slack) |
| `release-docs` | Build and update documentation site with current components |
| `seo-aeo` | Audit, fix, and validate SEO/AEO for Eleventy docs sites |
| `triage` | Triage and categorize findings for the CLI todo system |

### Development

| Skill | Description |
|-------|-------------|
| `agent-native-architecture` | Build AI agents using prompt-native architecture |
| `agent-native-audit` | Run comprehensive agent-native architecture review |
| `andrew-kane-gem-writer` | Write Ruby gems following Andrew Kane's patterns |
| `atdd-developer` | Acceptance Test Driven Development with RED/GREEN/REFACTOR permission gates |
| `code-to-prd` | Reverse-engineer a Next.js codebase into a redacted PRD for buyer/investor handoff |
| `dhh-rails-style` | Write Ruby/Rails code in DHH's 37signals style |
| `dspy-ruby` | Build type-safe LLM applications with DSPy.rb |
| `frontend-design` | Create production-grade frontend interfaces |
| `model-launch-review` | Audit the per-Anthropic-model-release checklist and auto-fix stale model-ID swaps via a CI-gated PR |
| `skill-creator` | Create, refine, audit, and package Claude Code skills |
| `spec-templates` | Structured feature specifications and task tracking |
| `user-story-writer` | Decompose features into INVEST-compliant stories using Elephant Carpaccio |

### Review & Planning

| Skill | Description |
|-------|-------------|
| `architecture` | Create and manage Architecture Decision Records and interactive LikeC4 diagrams |
| `brainstorm` | Explore requirements and approaches before planning |
| `competitive-analysis` | Run competitive intelligence scans and market research reports |
| `deepen-plan` | Enhance plans with parallel research agents |
| `gdpr-gate` | Audit diffs and plans for GDPR/CCPA/HIPAA compliance gaps (advisory) |
| `heal-skill` | Fix skill documentation issues |
| `plan` | Create structured implementation plans |
| `plan-review` | Multi-agent plan review in parallel |
| `product-roadmap` | Define and operationalize product roadmaps through CPO-grade workshop; `validate`/`next` sub-commands give a read-only roadmap-vs-milestone drift report and next-action advisory |
| `qa` | Run functional QA before merge — browser flows and API verification |
| `review` | Run comprehensive code review with specialized agents |

### Workflow

| Skill | Description |
|-------|-------------|
| `admin-ip-refresh` | Refresh the prod SSH allowlist (Doppler ADMIN_IPS) after operator IP rotation |
| `agent-browser` | CLI-based browser automation using Vercel's agent-browser |
| `archive-kb` | Archive knowledge-base artifacts with timestamped prefixes |
| `cf-token-scope` | Widen a Cloudflare API token's scope via Playwright, then run the ADR-130 retained-scope probe set |
| `cohort-status` | Print the alpha-tester cohort table: tally, checkpoint state, quiet flags (pull-based, operator-invoked) |
| `deploy` | Deploy containerized applications via Docker build, GHCR push, and SSH |
| `git-worktree` | Manage Git worktrees for parallel development |
| `invoice` | Get paid via your own Stripe account: list who owes you, create/send behind an approval preview, chase overdue (test mode only in v1) |
| `merge-pr` | Autonomous single-PR merge with conflict resolution and cleanup |
| `one-shot` | Full autonomous engineering workflow from plan to PR |
| `pencil-setup` | Auto-detect, install, and register Pencil MCP server with Claude Code CLI |
| `rclone` | Upload files to S3, Cloudflare R2, Backblaze B2, and cloud storage |
| `reproduce-bug` | Reproduce bugs using logs, console, and browser screenshots |
| `registry-breakglass-mirror` | Mirror GHCR images into zot datacenter-side when the registry tunnel bridge is down (break-glass only) |
| `resolve-parallel` | Resolve TODO comments in parallel |
| `resolve-pr-parallel` | Resolve PR comments in parallel |
| `resolve-todo-parallel` | Resolve CLI todos in parallel |
| `schedule` | Generate GitHub Actions cron workflows for scheduling Soleur skills |
| `ship` | Enforce feature lifecycle checklist before creating PRs |
| `test-browser` | Run browser tests on PR-affected pages |
| `test-fix-loop` | Autonomous test-fix iteration with checkpoint commit isolation |
| `work` | Execute plans with incremental commits |
| `xcode-test` | Build and test iOS apps on simulator |

## MCP Servers

| Server | Description |
|--------|-------------|
| `context7` | Framework documentation lookup via Context7 |
| `cloudflare` | Cloudflare platform access (DNS, Workers, Zero Trust) via OAuth |
| `vercel` | Vercel platform access (deployments, projects, logs, domains) via OAuth |
| `stripe` | Stripe platform access (payments, customers, subscriptions) via OAuth |
| `playwright` | Browser automation via `@playwright/mcp`, routed through `playwright-mcp-redact-proxy.py` (accessibility snapshots redacted in flight; dedicated persistent `soleur-playwright-mcp-profile` browser profile under the XDG cache root). Registered via plugin-root `.mcp.json` on Claude Code ≥2.1.139; requires `python3` and `npx` |

### Context7

**Tools provided:**

- `resolve-library-id` - Find library ID for a framework/package
- `get-library-docs` - Get documentation for a specific library

Supports 100+ frameworks including Rails, React, Next.js, Vue, Django, Laravel, and more.

### Vercel

**Tools provided:**

- `search_documentation` - Search Vercel and Next.js documentation (no auth required)
- `list_teams`, `list_projects`, `get_project` - Project management
- `list_deployments`, `get_deployment`, `get_deployment_build_logs`, `get_runtime_logs` - Deployment monitoring
- `check_domain_availability_and_price`, `buy_domain` - Domain management
- `get_access_to_vercel_url`, `web_fetch_vercel_url` - URL access
- `use_vercel_cli`, `deploy_to_vercel` - CLI and deployment

Requires OAuth authentication for most tools (Claude Code handles this automatically on first use). Documentation search works without authentication.

MCP servers start automatically when the plugin is enabled.

## Browser Automation

This plugin uses **agent-browser CLI** for browser automation tasks. Install it globally:

```bash
npm install --prefix ~/.local -g agent-browser@0.22.3
agent-browser install  # Downloads Chrome for Testing
```

The `agent-browser` skill provides comprehensive documentation on usage.

## Installation

**Devin CLI:**

```bash
devin plugins install jikig-ai/soleur#plugins/soleur -y
```

Use `-y` to skip the confirmation prompt. You must be signed in (`devin auth login`) for plugin installation. If the remote install hangs or fails, clone the repository and install from `./soleur/plugins/soleur`.

**Claude Code (recommended, via the published marketplace):**

```bash
claude plugin marketplace add jikig-ai/soleur-marketplace
claude plugin install soleur@soleur-marketplace
```

This installs the plugin subtree only — about 10 MiB in well under a minute.

**Grok Build:** Soleur loads the same in-repo plugin under Grok Build. From the repository root, confirm discovery and start a session:

```bash
grok inspect    # the soleur plugin, skills, agents, and MCP servers must appear
grok            # interactive session
```

Use `/go <intent>` (Grok's bare entry name), not `/soleur:go`. If `grok inspect` does not list Soleur, stop — there is no `grok plugin install` command to fall back on today. See the [Grok Build onboarding guide](../../knowledge-base/engineering/grok-onboarding.md).

<details>
<summary>Installing from the monorepo directly (slower, and may time out)</summary>

A first-time `claude plugin marketplace add jikig-ai/soleur` clones the whole repository
(~181 MiB), which takes about 329 seconds — well past the CLI's 120-second default. Add `--sparse`
so it fetches only what a plugin install needs; that completes in about 78 seconds, inside the
default limit:

```bash
claude plugin marketplace add jikig-ai/soleur --sparse .claude-plugin plugins
claude plugin install soleur@soleur
```

**Only on a first add.** If you already have a plain `~/.claude/plugins/marketplaces/soleur`
checkout, do **not** add `--sparse` to it: applying `--sparse` to an existing checkout does not
convert it in place, it forces a full re-clone — which on the monorepo is the 329-second operation
that cannot finish under the 120-second default. Migrate instead, using the commands below. Details
and recovery: the
[plugin delivery runbook](../../knowledge-base/engineering/operations/runbooks/plugin-delivery-recovery.md),
under `## Symptom 2`.

Once the checkout exists, routine refreshes are incremental `git pull`s rather than fresh clones, so
the 329 seconds is a one-time cost of adding this way — but it is paid again whenever a refresh
cannot update in place and restarts as a re-clone.

**Already installed this way?** Switch to the marketplace above — the migration never clones the
monorepo, so it is not subject to the timeout:

```bash
claude plugin marketplace add jikig-ai/soleur-marketplace
claude plugin install soleur@soleur-marketplace
claude plugin uninstall soleur@soleur
claude plugin marketplace remove soleur
```

Restart the CLI afterwards; plugin changes apply on restart. If your original install used
`--scope project` or `--scope local`, pass the same `--scope` to every command above — the
default is `user`, and a scope mismatch silently targets an install that isn't there.

Removing the marketplace does **not** reclaim the plugin cache — though it does remove the
marketplace checkout itself. Measured: after `uninstall` and `marketplace remove` both succeed, the
378 MiB checkout is gone and the old plugin **cache** survives — 26 MiB on the machine this was
measured on, with no CLI verb to reclaim it. Expect more the longer the install has been updating:
each update caches into a new directory and leaves the previous one behind.

**Do this only once the migration above has completed.** First confirm the new install is live
and the old one is gone:

```bash
claude plugin list
```

You should see `soleur@soleur-marketplace` and no `soleur@soleur`. If you still see
`soleur@soleur`, stop — the migration did not finish, and the directory below is still your
working install.

Then ask the CLI which paths are actually in use, and delete only what is **not** in that list:

```bash
claude plugin list --json | jq -r '.[].installPath'
```

```bash
rm -rf ~/.claude/plugins/cache/soleur
```

The old and new cache directories differ by a single suffix — `soleur` versus
`soleur-marketplace` — so compare against the output above rather than typing from memory.
Note that scope does not change this path: installs made with `--scope project` or
`--scope local` still cache under your home directory, so the directory above is yours to
check regardless of how you installed.

</details>

## Version Visibility

`/soleur:help` prints the installed version in its header. On Claude Code, `/soleur:version` prints
the installed version, the latest release, whether a newer one exists, and the update commands. A
marketplace install is identified by its 12-character commit hash (the published manifest carries
no `version` key by design), so today you see `Soleur commit <sha12>` rather than a semver; the
banner shows `Soleur v<X.Y.Z>` only for an install whose manifest does carry a version. A plugin run in
place from a local git checkout (a local-folder marketplace, or `--plugin-dir`) shows `Soleur commit
<sha12> (local checkout)`: that is the HEAD commit of the git checkout that contains the plugin folder,
read from its files without running git, not its uncommitted or unsynced files (a plugin folder vendored
inside another project's repository shows that project's HEAD); `/soleur:version` prints the update steps
for it.

**Session-start banner (on by default, no network).** Every session start shows one line, `Soleur
commit <sha12>` (or `Soleur v<X.Y.Z>`), read from the local install. It makes no network call.
`SOLEUR_DISABLE_VERSION_BANNER=1` turns the banner off.

**Opt-in newer-release check.** Only the check for a newer release is off by default. To add it to
the session-start banner, set `SOLEUR_UPDATE_CHECK=1` (exactly `1`) in your **user-level** Claude
Code settings (`~/.claude/settings.json`), not in a checked-in project `.claude/settings.json`:

```json
{
  "env": { "SOLEUR_UPDATE_CHECK": "1" }
}
```

Remove the key to turn the check off. Do not enable it in CI or ephemeral containers: the lookup
uses unauthenticated GitHub requests, which GitHub limits to 60 per hour per IP address. A lookup
runs `git ls-remote --tags` against github.com/jikig-ai/soleur and, for a commit-hash or local-checkout install
only, one unauthenticated GitHub compare API request whose URL includes the installed commit hash (for a
local checkout, its current commit, which may be one you have never pushed). It runs
with git configuration isolated (no user git config, no ssh, no credentials of its own, https only; a
proxy configured in your environment is still used) and each
request is time-limited (8 seconds by default, `SOLEUR_FETCH_TIMEOUT` to change). While lookups keep
failing, the check retries at most once every 10 minutes.

The result is cached in one file per install, `${XDG_CACHE_HOME:-~/.cache}/soleur/latest-release.<install id>`
(a relative `XDG_CACHE_HOME` is ignored; every commit of a local checkout shares `latest-release.checkout`). A cached result is treated as fresh for 24 hours and
re-checked after that; the file stays on disk until it is replaced or deleted.

`/soleur:version` is an explicit, user-started request (the model cannot start it) and runs the same
lookup even if you did not opt in. "No release newer than yours" means only that no release tag newer
than your install was found, not that nothing else has changed. The lookup is implemented in
`plugins/soleur/scripts/plugin-version.sh`, shared by the hook, `/soleur:version` and `/soleur:help`.

## Compaction-Aware Session Hooks

When a session's context is compacted, Soleur injects a short directive telling
the model to re-read the plan and spec rather than trust the paraphrased
summary, and — on the **second automatic compaction of the same session
window** — recommends continuing in a fresh session at the next phase boundary.
Before a compaction it tells the summarizer which resume identifiers to keep
verbatim.

This replaces the old unconditional "run `/clear` and resume" advice, which
fired at fixed points regardless of whether any context had been lost.

`plugins/soleur/hooks/compaction-state.sh` is bound twice in `hooks.json`:
`PreCompact` (matcher `manual|auto`) and `SessionStart` (matcher
`startup|resume|clear|compact`). It is fully local — nothing leaves the machine, and nothing is written to your
repository. It is not read-only: it keeps a small per-session counter under
`TMPDIR` (mode 0700, two files of one word each, reaped after 7 days). Its per-session
counter lives under `TMPDIR` and is disposable.

**It does nothing in a repository Soleur does not manage.** A plugin hook is
global, so the hook stays silent unless the enclosing repository carries a
`knowledge-base/project/plans` or `specs` directory — the artifacts
`/soleur:plan` writes. Without that check, compacting work on an unrelated
application would get a summary shaped around PR numbers and operator holds it
does not have.

This is a *relevance* check, not a security boundary, and the distinction is
worth stating: any repository can contain a directory of that name, so a
repository you clone can satisfy it. That is bounded by what the hook emits —
pointers and integers it derives itself, with every free-text value reduced to a
conservative character set — and by the fact that a cloned repository already
reaches the model more directly through `CLAUDE.md`, which Claude Code loads
unconditionally.

| Setting | Default | Effect |
|---|---|---|
| `SOLEUR_DISABLE_COMPACTION_HOOKS` | unset | `1` disables both events entirely — no directive, no summary shaping, nothing written |
| `jq` (not a setting) | required | Without `jq` on `PATH` the hook emits a static `reason=jq-unavailable` envelope and can produce no recommendation. The Claude Code row below assumes it is present. |
| `SOLEUR_COMPACTION_COUNT_THRESHOLD` | `2` | Automatic compactions in one session window before a fresh session is recommended. `1` recommends on the first; a high value effectively never recommends. `0` and any non-numeric value fall back to the default — `0` reads as "off" to most people, and honouring it literally would mean "recommend always", so use the kill switch above instead |
| `SOLEUR_COMPACTION_CLI_VERSION` | derived from `claude --version` | Pins the CLI version stamped into the directive, for drift attribution |

`SOLEUR_DISABLE_UNKEPT_PROMISE_HOOK=1` makes the `unkept-promise-hook.sh` Stop hook exit immediately. The web platform sets it for every agent session (`AGENT_ENV_OVERRIDES` in `apps/web-platform/server/agent-env.ts`) because that hook's block turn would replace the chat reply and its closing-text rules are operator-CLI workflow; an operator can export it as a kill switch. Only the exact value `1` opts out.

### Harness support

The compaction lifecycle is a Claude Code API. The other four harnesses
degrade to **silence**, never to a false claim that the behaviour is present.

| Harness | Compaction hooks | What you get instead |
|---|---|---|
| Claude Code | Yes (2.1.76+; measured on 2.1.273) | Evidence-based directive and fresh-session recommendation |
| Codex | No | The skill-prose fallback: the end-of-work resume prompt still fires, with no `/clear` recommendation |
| Devin Cloud | No | Same as Codex. Plugin hooks do not fire in cloud sessions at all — see `devin/INSTRUCTIONS.md` §Cloud Mode |
| Grok Build | No | Same as Codex |
| OpenCode | No | Same as Codex. The adapter carries no compaction hook, so nothing is written and no directive is emitted |

## Destructive-Command Guard

`plugins/soleur/hooks/destructive-command-guard.sh` is a `PreToolUse` hook on the Bash tool. It asks you before
`terraform|tofu destroy` or `apply -destroy`, a force-push or deletion of a default branch, and a recursive delete of
the working directory or one of its ancestors. It denies a recursive delete of `/`, your home directory or an
ancestor of it.

The guard does not cover a plain `terraform apply`, secret writes, SQL, non-Bash tools, `terragrunt` or `pulumi` destroy, or indirect command forms (scripts or heredocs fed to a shell, wrappers it does not unwrap, obfuscated command names), and is not a substitute for scoped credentials.

Not active in Soleur-hosted sessions: hosted Bash runs in the sandbox under the workspace's approval mode, and in the default autonomous mode (after the owner's one-time acknowledgement) commands outside a short blocklist run without a prompt, apart from a separate Soleur check that pauses to ask before the default-branch force-push, delete and mirror, `terraform destroy` and `gh` ref or repository delete forms it recognises (it does not recognise every spelling); this guard does not add a prompt.

It is a seatbelt, not a boundary: an agent that can edit your settings can switch it off.

The guard also asks, rather than allows, when it cannot read a command it was given: an oversized or unparsable command, a path, command name or option longer than 4096 bytes, `env -S`, or wrappers nested more than eight deep (the last two only on a command the guard parses in full, which any command that spells `rm`, `destroy` or `push`, or uses a quote or `$`, is). You may meet such an ask on a command that is not destructive.

`SOLEUR_DISABLE_DESTRUCTIVE_GUARD=1` turns it off. Set it in your own shell before you start the session; the
harness reads it at startup, so a running session needs a restart. Any other value, including `0` and empty, leaves
the guard on.

It needs `bash`, `jq`, `perl` and `git`. Without `jq` or `perl` it scans with a narrower set of patterns and prints a
notice on stderr, which a person may never see, and a command that scan misses runs without a prompt. That scan cannot see the branch or the quoting, so it also asks on a force push to any branch (a routine `git push --force-with-lease` of a feature branch) and on text that only names a destroy, such as a commit message. It also needs `/dev/fd`
(standard on Linux and macOS); in a minimal sandbox without it the guard asks with a "could not parse" reason instead of denying.

Headless and CI: under `claude -p` an ask blocks the call and the agent is told why (measured on Claude Code 2.1.291). There is
no per-rule allow, and the kill switch is all-or-nothing and is read when the process starts. Soleur's own server-side scheduled
agents that load this plugin outside the hosted session environment are covered by the guard too, and an ask there blocks the
same way (ADR-277).

## Known Issues

### Updating the Marketplace Does Not Update the Installed Plugin

**Issue:** `/plugin marketplace update soleur` advances the marketplace checkout under
`~/.claude/plugins/marketplaces/` to the new HEAD, but does **not** re-pull the plugin
install under `~/.claude/plugins/cache/`. The install keeps its own `gitCommitSha` in
`installed_plugins.json`, and `${CLAUDE_PLUGIN_ROOT}` resolves to that install — not to the
marketplace checkout. So a fix verified against the marketplace copy reads as shipped while
every run still executes the old payload.

**Workaround:** run both steps, then confirm the two agree:

```bash
claude plugin marketplace update soleur-marketplace
claude plugin update soleur@soleur-marketplace
```

Both halves name the marketplace deliberately. On current releases the bare plugin name can
fail with `Plugin not found`; an Anthropic collaborator confirmed `<plugin>@<marketplace>` as
the reliable form on anthropics/claude-code#76882 (2026-08-17). `soleur-marketplace` is the id
for the published marketplace; if you added this repository directly it is `soleur`, so run
`claude plugin list` and use whatever it prints beside `soleur`.

**If that does not converge them, reinstall.** This is now a fallback rather than the only
mechanism, and the reason it used to be the only one is worth knowing: `plugin.json` carried a
frozen `0.0.0-dev` sentinel, so the install directory name never changed and `plugin update` had
no version bump to act on (measured in ADR-178 — an actively-used install carried 64 skills
against 96 in the repo, three months stale, while reporting success). The manifests became
keyless on 2026-08-12, and the CLI now records a compound version whose leading half is the
delivered commit, so the string changes with every commit and `update` has something to compare.
See ADR-182 for the mechanism and its measurements:

```bash
claude plugin uninstall soleur@soleur-marketplace && claude plugin install soleur@soleur-marketplace
```

**Symptom to watch for:** `/soleur:sync` emitting
`SOLEUR_SYNC_PRODUCER_MISSING producer=<path> … reason=absent-from-verified-root` means the
verified plugin root does not carry a file that run needed — most often an install that
predates it. That marker is why this failure now names itself instead of surfacing as an
unattributed interpreter error (#7474).

### MCP Servers Not Auto-Loading

**Issue:** The bundled MCP servers (Context7, Vercel) may not load automatically when the plugin is installed.

**Workaround:** Manually add them to your project's `.claude/settings.json`:

```json
{
  "mcpServers": {
    "context7": {
      "type": "http",
      "url": "https://mcp.context7.com/mcp"
    },
    "vercel": {
      "type": "http",
      "url": "https://mcp.vercel.com"
    }
  }
}
```

Or add them globally in `~/.claude/settings.json` for all projects.

### External output filters (rtk, Headroom)

**Issue:** User-installed output-filtering tools (rtk's Bash rewriting, Headroom's
compression, local proxies) can remove literals Soleur's evidence gates read, and a
resulting failure arrives looking like a Soleur defect. Soleur does not adopt these
tools; rtk command wrappers are unwrapped by the destructive-command guard, and a
`SOLEUR_EXT_FILTER` session-start marker reports detected filters with an
evidence-gated posture.

`SOLEUR_DISABLE_EXT_FILTER_DETECT=1` turns the marker off.

**Workaround:** follow the three-rung diagnosis — check the `SOLEUR_EXT_FILTER`
marker, reproduce with the filter disabled (`mode = "disabled"` in
`~/.config/rtk/config.toml`, or `rtk run` passthrough; there is no `RTK_DISABLED`
env var), then compare verbatim vs filtered output. Postures, footguns and the
canonical grammar table: [known-external-tools](https://soleur.ai/known-external-tools/)

## Version History

See [GitHub Releases](https://github.com/jikig-ai/soleur/releases) for detailed version history.

## License

BSL 1.1 (Business Source License). See [LICENSE](LICENSE) for details.

Source-available for all individual and internal company use. The only restriction is offering Soleur as a competing hosted service. Each version converts to Apache-2.0 after 4 years. Versions v3.0.10 and earlier remain Apache-2.0.

## Terms

The licence governs what you may do with the source. Separately, the [Terms and Conditions](https://soleur.ai/legal/terms-and-conditions) govern your use of Soleur and bind on **installation** — not only on signing up to the hosted platform. The [Privacy Policy](https://soleur.ai/legal/privacy-policy), [Acceptable Use Policy](https://soleur.ai/legal/acceptable-use-policy), and [Data Protection Disclosure](https://soleur.ai/legal/data-protection-disclosure) apply on the same basis.

If you install only the plugin and never create a hosted account, you never pass through the platform's accept-terms flow — so this link is the notice. The Data Protection Disclosure is the one worth reading. It explains that where the plugin runs **on your own machine, under your own API key, for your own purposes**, Jikigai is neither a controller nor a processor of the data processed there. All three conditions matter: if Jikigai's own credential pays for a run, or Jikigai observes your content for its own purposes, that position does not apply and a separate instrument is required.
