# Soleur

AI-powered development tools that get smarter with every use. Make each unit of engineering work easier than the last.

## Quick Start

Install the plugin:

```bash
claude plugin install soleur
```

## The Soleur Workflow

Soleur provides a structured workflow for feature development. Use these commands in order:

```text
/soleur:brainstorm  -->  /soleur:plan  -->  /soleur:work  -->  /soleur:review  -->  /soleur:compound
```

**For existing codebases:** Run `/soleur:sync` first to populate your knowledge-base with conventions and patterns before starting the workflow.

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

Analyze an existing codebase and populate the knowledge-base with conventions, architecture patterns, testing practices, and technical debt. Run this before starting the workflow on a project that already has code.

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
| Agents | 25 |
| Commands | 8 |
| Skills | 37 |
| MCP Servers | 1 |

## Agents

Agents are organized by domain, then by function. Cross-domain agents stay at root level.

### Marketing (1)

| Agent | Description |
|-------|-------------|
| `brand-architect` | Interactive brand identity workshop producing structured brand guides |

### Engineering (16)

#### Review (14)

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
| `test-design-reviewer` | Score test quality using Farley's 8 properties with weighted rubric |

#### Design (1)

| Agent | Description |
|-------|-------------|
| `ddd-architect` | Domain-Driven Design with strategic bounded contexts and tactical patterns |

#### Infra (1)

| Agent | Description |
|-------|-------------|
| `terraform-architect` | Generate and review Terraform configurations for Hetzner Cloud and AWS |

### Operations (1)

| Agent | Description |
|-------|-------------|
| `ops-advisor` | Track expenses, manage domains, advise on hosting |

### Cross-domain (7)

#### Research (5)

| Agent | Description |
|-------|-------------|
| `best-practices-researcher` | Gather external best practices and examples |
| `framework-docs-researcher` | Research framework documentation and best practices |
| `git-history-analyzer` | Analyze git history and code evolution |
| `learnings-researcher` | Search institutional learnings for relevant past solutions |
| `repo-research-analyst` | Research repository structure and conventions |

#### Workflow (2)

| Agent | Description |
|-------|-------------|
| `pr-comment-resolver` | Address PR comments and implement fixes |
| `spec-flow-analyzer` | Analyze user flows and identify gaps in specifications |

## Commands

All commands use the `soleur:` prefix to avoid collisions with built-in commands:

| Command | Description |
|---------|-------------|
| `/soleur:brainstorm` | Explore requirements and approaches before planning |
| `/soleur:plan` | Create implementation plans |
| `/soleur:work` | Execute work items systematically |
| `/soleur:review` | Run comprehensive code reviews |
| `/soleur:compound` | Document solved problems to compound team knowledge |
| `/soleur:sync` | Analyze codebase and populate knowledge-base with conventions, patterns, and overview documentation |
| `/soleur:help` | List all available Soleur commands, agents, and skills |
| `/soleur:one-shot` | Full autonomous engineering workflow from plan to PR |

## Skills

### Architecture & Design

| Skill | Description |
|-------|-------------|
| `agent-native-architecture` | Build AI agents using prompt-native architecture |

### Engineering Methodology

| Skill | Description |
|-------|-------------|
| `atdd-developer` | Acceptance Test Driven Development with RED/GREEN/REFACTOR permission gates |
| `user-story-writer` | Decompose features into INVEST-compliant stories using Elephant Carpaccio |

### Development Tools

| Skill | Description |
|-------|-------------|
| `andrew-kane-gem-writer` | Write Ruby gems following Andrew Kane's patterns |
| `compound-docs` | Capture solved problems as categorized documentation |
| `dhh-rails-style` | Write Ruby/Rails code in DHH's 37signals style |
| `dspy-ruby` | Build type-safe LLM applications with DSPy.rb |
| `frontend-design` | Create production-grade frontend interfaces |
| `skill-creator` | Create, refine, audit, and package Claude Code skills |

### Planning & Review

| Skill | Description |
|-------|-------------|
| `changelog` | Create engaging changelogs for recent merges |
| `deepen-plan` | Enhance plans with parallel research agents |
| `deploy-docs` | Validate and prepare documentation for deployment |
| `plan-review` | Multi-agent plan review in parallel |
| `release-announce` | Announce releases to Discord and GitHub Releases |
| `release-docs` | Build and update documentation site with current components |

### Resolution & Automation

| Skill | Description |
|-------|-------------|
| `resolve-parallel` | Resolve TODO comments in parallel |
| `resolve-pr-parallel` | Resolve PR comments in parallel |
| `resolve-todo-parallel` | Resolve CLI todos in parallel |
| `triage` | Triage and categorize findings for the CLI todo system |

### Testing & QA

| Skill | Description |
|-------|-------------|
| `agent-native-audit` | Run comprehensive agent-native architecture review |
| `feature-video` | Record video walkthroughs and add to PR description |
| `heal-skill` | Fix skill documentation issues |
| `report-bug` | Report a bug in the plugin |
| `reproduce-bug` | Reproduce bugs using logs, console, and browser screenshots |
| `test-browser` | Run browser tests on PR-affected pages |
| `xcode-test` | Build and test iOS apps on simulator |

### Content & Workflow

| Skill | Description |
|-------|-------------|
| `discord-content` | Create and post brand-consistent community content to Discord |
| `every-style-editor` | Review copy for Every's style guide compliance |
| `file-todos` | File-based todo tracking system |
| `git-worktree` | Manage Git worktrees for parallel development |
| `ship` | Enforce feature lifecycle checklist before creating PRs |

### Deployment

| Skill | Description |
|-------|-------------|
| `deploy` | Deploy containerized applications via Docker build, GHCR push, and SSH |

### File Transfer

| Skill | Description |
|-------|-------------|
| `rclone` | Upload files to S3, Cloudflare R2, Backblaze B2, and cloud storage |

### Browser Automation

| Skill | Description |
|-------|-------------|
| `agent-browser` | CLI-based browser automation using Vercel's agent-browser |

### Image Generation

| Skill | Description |
|-------|-------------|
| `gemini-imagegen` | Generate and edit images using Google's Gemini API |

**gemini-imagegen features:**

- Text-to-image generation
- Image editing and manipulation
- Multi-turn refinement
- Multiple reference image composition (up to 14 images)

**Requirements:**

- `GEMINI_API_KEY` environment variable
- Python packages: `google-genai`, `pillow`

## MCP Servers

| Server | Description |
|--------|-------------|
| `context7` | Framework documentation lookup via Context7 |

### Context7

**Tools provided:**

- `resolve-library-id` - Find library ID for a framework/package
- `get-library-docs` - Get documentation for a specific library

Supports 100+ frameworks including Rails, React, Next.js, Vue, Django, Laravel, and more.

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

**Issue:** The bundled Context7 MCP server may not load automatically when the plugin is installed.

**Workaround:** Manually add it to your project's `.claude/settings.json`:

```json
{
  "mcpServers": {
    "context7": {
      "type": "http",
      "url": "https://mcp.context7.com/mcp"
    }
  }
}
```

Or add it globally in `~/.claude/settings.json` for all projects.

## Version History

See [CHANGELOG.md](CHANGELOG.md) for detailed version history.

## License

Apache-2.0
