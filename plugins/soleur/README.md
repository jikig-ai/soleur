# Soleur

A full AI organization across engineering, finance, marketing, legal, operations, product, and sales. Every decision you make teaches the system. Every project gets better and faster than the last.

## Quick Start

Install the plugin:

```bash
claude plugin install soleur
```

## The Soleur Workflow

The recommended way to use Soleur is through the unified entry point:

```text
/soleur:go <what you want to do>
```

This classifies your intent and routes to the right workflow. For existing codebases, run `/soleur:sync` first to populate your knowledge-base.

**Advanced workflow** (individual commands):

```text
/soleur:brainstorm  -->  /soleur:plan  -->  /soleur:work  -->  /soleur:review  -->  /soleur:compound
```

### 1. Brainstorm (`/soleur:brainstorm`)

Start here when you have a feature idea but need to explore it further. This command helps you:

- Clarify what you're building through guided questions
- Explore different approaches with pros/cons
- Make key decisions before coding
- Document the design in `knowledge-base/brainstorms/`

**When to use:** New features, unclear requirements, multiple valid approaches.

**Example:** `/soleur:brainstorm Add user authentication to the app`

### 2. Plan (`/soleur:plan`)

Once you know what to build, create an implementation plan. This command:

- Analyzes your codebase for relevant patterns
- Breaks the work into specific, actionable tasks
- Creates a structured plan document
- Optionally runs parallel research agents for deeper analysis

**When to use:** After brainstorming, or when requirements are already clear.

**Example:** `/soleur:plan` (auto-detects recent brainstorm) or `/soleur:plan path/to/spec.md`

### 3. Work (`/soleur:work`)

Execute the plan systematically. This command:

- Reads your plan and sets up the environment
- Detects independent tasks and offers parallel execution via subagents (max 5)
- Tracks progress with TodoWrite
- Makes incremental commits as logical units complete
- Follows existing codebase patterns

**When to use:** When you have a plan ready to execute.

**Example:** `/soleur:work path/to/plan.md`

### 4. Review (`/soleur:review`)

Run comprehensive code review before creating a PR. This command:

- Launches multiple specialized review agents in parallel
- Checks for security, performance, patterns, and simplicity
- Provides actionable feedback on your changes

**When to use:** After completing implementation, before creating PR.

**Example:** `/soleur:review`

### 5. Compound (`/soleur:compound`)

Capture learnings from your work. This command:

- Documents debugging breakthroughs and non-obvious patterns
- Saves knowledge to `knowledge-base/learnings/`
- Makes future similar problems easier to solve

**When to use:** Before creating PR, especially if you solved tricky problems.

**Example:** `/soleur:compound` (or just say "that worked!" and it triggers automatically)

### Sync (`/soleur:sync`)

Analyze an existing codebase and populate the knowledge-base with conventions, architecture patterns, testing practices, and technical debt. Also scans accumulated learnings against skill/agent/command definitions and proposes one-line bullet edits. Run this before starting the workflow on a project that already has code.

**Example:** `/soleur:sync` or `/soleur:sync conventions`

### Help (`/soleur:help`)

List all available Soleur commands, agents, and skills with descriptions and usage hints.

**Example:** `/soleur:help`

### One-Shot (`/soleur:one-shot`)

Full autonomous engineering workflow that goes from plan to PR in a single command. Combines plan, work, review, and compound into one continuous flow.

**Example:** `/soleur:one-shot Add dark mode support`

## Components

| Component | Count |
|-----------|-------|
| Agents | 54 |
| Commands | 8 |
| Skills | 46 |
| MCP Servers | 2 |

## Agents

Agents are organized by domain, then by function.

### Marketing (12)

| Agent | Description |
|-------|-------------|
| `analytics-analyst` | Analytics tracking setup, event taxonomy design, A/B test planning, and attribution modeling |
| `brand-architect` | Interactive brand identity workshop producing structured brand guides |
| `cmo` | Marketing domain leader -- orchestrates marketing strategy and delegates to specialist agents |
| `community-manager` | Analyze community engagement, generate weekly digests, and report health metrics across Discord and GitHub |
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

### Engineering (27)

| Agent | Description |
|-------|-------------|
| `cto` | Engineering domain leader -- assesses technical implications and flags architecture risks during brainstorm and planning |

#### Review (15)

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
| `pattern-recognition-specialist` | Analyze code for patterns and anti-patterns |
| `performance-oracle` | Performance analysis and optimization |
| `security-sentinel` | Security audits and vulnerability assessments |
| `semgrep-sast` | Deterministic SAST scanning using semgrep CLI for known vulnerability patterns |
| `test-design-reviewer` | Score test quality using Farley's 8 properties with weighted rubric |

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

### Operations (4)

| Agent | Description |
|-------|-------------|
| `coo` | Operations domain leader -- orchestrates ops-advisor, ops-research, and ops-provisioner |
| `ops-advisor` | Track expenses, manage domains, advise on hosting |
| `ops-provisioner` | Guide SaaS tool account setup, purchase, configuration, and verification |
| `ops-research` | Research domains, hosting, tools/SaaS, and cost optimization with browser automation |

### Product (4)

| Agent | Description |
|-------|-------------|
| `business-validator` | Validate business ideas through structured 6-gate workshop (market research, competitive analysis, business model) |
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

## Commands

All commands use the `soleur:` prefix to avoid collisions with built-in commands:

| Command | Description |
|---------|-------------|
| `/soleur:go` | Unified entry point -- classifies intent and routes to the right workflow |
| `/soleur:brainstorm` | Explore requirements and approaches before planning |
| `/soleur:plan` | Create implementation plans |
| `/soleur:work` | Execute work items systematically |
| `/soleur:review` | Run comprehensive code reviews |
| `/soleur:compound` | Document solved problems to compound team knowledge |
| `/soleur:sync` | Analyze codebase and populate knowledge-base with conventions, patterns, and overview documentation |
| `/soleur:help` | List all available Soleur commands, agents, and skills |
| `/soleur:one-shot` | Full autonomous engineering workflow from plan to PR |

## Skills

### Content & Release

| Skill | Description |
|-------|-------------|
| `brainstorming` | Explore intent, approaches, and design decisions |
| `changelog` | Create engaging changelogs for recent merges |
| `community` | Manage community engagement across Discord and GitHub (setup, digests, health, welcome) |
| `compound-docs` | Capture solved problems as categorized documentation |
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
| `legal-generate` | Generate draft legal documents from company context (7 document types, 3 jurisdictions) |
| `release-announce` | Announce releases to Discord and GitHub Releases |
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
| `dhh-rails-style` | Write Ruby/Rails code in DHH's 37signals style |
| `dspy-ruby` | Build type-safe LLM applications with DSPy.rb |
| `frontend-design` | Create production-grade frontend interfaces |
| `skill-creator` | Create, refine, audit, and package Claude Code skills |
| `spec-templates` | Structured feature specifications and task tracking |
| `user-story-writer` | Decompose features into INVEST-compliant stories using Elephant Carpaccio |

### Review & Planning

| Skill | Description |
|-------|-------------|
| `deepen-plan` | Enhance plans with parallel research agents |
| `heal-skill` | Fix skill documentation issues |
| `plan-review` | Multi-agent plan review in parallel |
| `report-bug` | Report a bug in the plugin |

### Workflow

| Skill | Description |
|-------|-------------|
| `agent-browser` | CLI-based browser automation using Vercel's agent-browser |
| `deploy` | Deploy containerized applications via Docker build, GHCR push, and SSH |
| `git-worktree` | Manage Git worktrees for parallel development |
| `merge-pr` | Autonomous single-PR merge with conflict resolution and cleanup |
| `rclone` | Upload files to S3, Cloudflare R2, Backblaze B2, and cloud storage |
| `reproduce-bug` | Reproduce bugs using logs, console, and browser screenshots |
| `resolve-parallel` | Resolve TODO comments in parallel |
| `resolve-pr-parallel` | Resolve PR comments in parallel |
| `resolve-todo-parallel` | Resolve CLI todos in parallel |
| `ship` | Enforce feature lifecycle checklist before creating PRs |
| `test-browser` | Run browser tests on PR-affected pages |
| `test-fix-loop` | Autonomous test-fix iteration with git stash isolation |
| `xcode-test` | Build and test iOS apps on simulator |

## MCP Servers

| Server | Description |
|--------|-------------|
| `context7` | Framework documentation lookup via Context7 |
| `vercel` | Vercel platform access (deployments, projects, logs, domains) via OAuth |

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
npm install -g agent-browser
agent-browser install  # Downloads Chromium
```

The `agent-browser` skill provides comprehensive documentation on usage.

## Installation

**From the registry (recommended):**

```bash
claude plugin install soleur
```

**From GitHub (without cloning):**

```bash
claude plugin install --url https://github.com/jikig-ai/soleur/tree/main/plugins/soleur
```

## Known Issues

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

## Version History

See [CHANGELOG.md](CHANGELOG.md) for detailed version history.

## License

Apache-2.0
