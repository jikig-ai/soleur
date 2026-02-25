# Soleur Claude Code Plugin Development

## Versioning Requirements

**IMPORTANT**: Every change to this plugin MUST include updates to all three files:

1. **`.claude-plugin/plugin.json`** - Bump version using semver
2. **`CHANGELOG.md`** - Document changes using Keep a Changelog format
3. **`README.md`** - Verify/update component counts and tables

### Version Bumping Rules

- **MAJOR** (1.0.0 → 2.0.0): Breaking changes, major reorganization
- **MINOR** (1.0.0 → 1.1.0): New agents, commands, or skills
- **PATCH** (1.0.0 → 1.0.1): Bug fixes, doc updates, minor improvements

### Pre-Commit Checklist

Before committing ANY changes:

- [ ] Version bumped in `.claude-plugin/plugin.json`
- [ ] CHANGELOG.md updated with changes
- [ ] README.md component counts verified
- [ ] README.md tables accurate (agents, commands, skills)
- [ ] plugin.json description matches current counts
- [ ] Root `README.md` version badge matches new version
- [ ] `.github/ISSUE_TEMPLATE/bug_report.yml` placeholder matches new version

### Directory Structure

Components are organized by domain, then by function.

```text
agents/
├── engineering/
│   ├── design/            # Architecture agents
│   ├── infra/             # Infrastructure agents
│   ├── research/          # Engineering research agents
│   ├── review/            # Code review agents
│   └── workflow/          # Engineering workflow agents
├── finance/               # Financial planning and reporting agents
├── legal/                 # Legal document and compliance agents
├── marketing/             # Brand and marketing agents
├── operations/            # Ops and expense agents
├── product/               # Product analysis and design agents
│   └── design/            # UX design agents
├── sales/                 # Sales pipeline and revenue agents
└── support/               # Support and community agents

commands/                      # Entry-point commands (go, sync, help)

skills/
└── <skill-name>/          # All skills at root level (flat)
```

### Adding a New Domain

To add a new domain (e.g., product, growth):

1. Create `agents/<domain>/` for domain-specific agents
2. Add `DOMAIN_META` entry in `docs/_data/agents.js` (label, icon, card description)
3. Add key to `domainOrder` and `DOMAIN_CSS_VARS` in the same file
4. Add CSS variable in `docs/css/style.css`
5. Skills stay flat at root level (the skill loader does not recurse into subdirectories)
6. Commands stay flat under `commands/` (only entry-point commands: go, sync, help). Workflow stages are skills.
7. The plugin loader discovers agents recursively -- no config changes needed
8. Landing page department cards, stats, and legal doc counts update automatically from data

## Command and Skill Naming Convention

Only 3 **commands** remain under `commands/`, using the `soleur:` prefix to avoid collisions with built-in commands:

- `/soleur:go` - Unified entry point that routes to workflow skills
- `/soleur:sync` - Populate knowledge base from existing codebase
- `/soleur:help` - List all available Soleur commands, agents, and skills

The 6 workflow stages are now **skills** under `skills/`:

- `soleur:brainstorm` - Explore requirements, make design decisions
- `soleur:plan` - Create implementation plans with research
- `soleur:work` - Execute plans with incremental commits
- `soleur:review` - Multi-agent code review before PR
- `soleur:compound` - Capture learnings for future work
- `soleur:one-shot` - Full autonomous engineering workflow from plan to PR

**Why skills?** Skills are discoverable by agents and invocable via the Skill tool. Commands are invisible to agents. Workflow stages benefit from agent discoverability and Skill tool invocation (e.g., `/soleur:go` routes to skills, one-shot sequences plan then work via the Skill tool).

**Prefix source:** Both commands and skills get their `soleur:` prefix automatically from the plugin namespace. The `name:` field in frontmatter should NOT include the `soleur:` prefix. Commands live flat in `commands/` (not in a subdirectory) to avoid double-namespacing.

## Agent Compliance Checklist

When adding or modifying agents, verify compliance:

### YAML Frontmatter (Required)

- [ ] `name:` present and matches filename (lowercase-with-hyphens)
- [ ] `description:` is 1-3 sentences of routing text only -- when to use this agent
- [ ] `description:` contains NO `<example>` blocks, NO `<commentary>` tags (these bloat the system prompt on every turn)
- [ ] `description:` includes a disambiguation sentence if another agent has overlapping scope ("Use [sibling] for [X]; use this agent for [Y].")
- [ ] `model: inherit` (see Model Selection Policy; explicit overrides require justification)

### Token Budget Check (Required when adding agents)

- [ ] Run: `grep -h 'description:' agents/**/*.md | wc -w` -- cumulative word count must stay under ~2500 words (~3.3k tokens, well under the 15k threshold)
- [ ] Detailed instructions, frameworks, and examples belong in the agent body (after `---`), not in `description:`

### Quick Validation Command

```bash
# Check for example blocks in agent descriptions (should return nothing)
grep -l '<example>' agents/**/*.md | xargs grep -l 'description:.*<example>'

# Check cumulative description size
grep -h 'description:' agents/**/*.md | wc -w
# Target: under 2500 words total across all agents
```

## Model Selection Policy

All agents must use `model: inherit` in their YAML frontmatter. This ensures agents run on whatever model the user's session is using, respecting their cost/quality preference.

- **Default:** `model: inherit` for all agents, no exceptions.
- **Override justification:** Explicit model overrides (`haiku`, `sonnet`, `opus`) require written justification in the agent body text explaining why the task is fundamentally mismatched with the session model.
- **Effort control:** Reasoning effort is a session-level setting (`effortLevel` in `.claude/settings.json` or the `/model` slider), not configurable per-agent. The Claude Code plugin spec does not support per-agent effort levels.
- **Current exceptions:** None.

## Skill Compliance Checklist

When adding or modifying skills, verify compliance with skill-creator spec:

### YAML Frontmatter (Required)

- [ ] `name:` present and matches directory name (lowercase-with-hyphens)
- [ ] `description:` present and uses **third person** ("This skill should be used when..." NOT "Use this skill when...")

### Reference Links (Required if references/ exists)

- [ ] All files in `references/` are linked as `[filename.md](./references/filename.md)`
- [ ] All files in `assets/` are linked as `[filename](./assets/filename)`
- [ ] All files in `scripts/` are linked as `[filename](./scripts/filename)`
- [ ] No bare backtick references like `` `references/file.md` `` - use proper markdown links

### Writing Style

- [ ] Use imperative/infinitive form (verb-first instructions)
- [ ] Avoid second person ("you should") - use objective language ("To accomplish X, do Y")

### Quick Validation Command

```bash
# Check for unlinked references in a skill
grep -E '`(references|assets|scripts)/[^`]+`' skills/*/SKILL.md
# Should return nothing if all refs are properly linked

# Check description format
grep -E '^description:' skills/*/SKILL.md | grep -v 'This skill'
# Should return nothing if all use third person
```

## Domain Leader Interface

Domain leaders are agents that orchestrate a business domain's specialist team. Each leader follows a 3-phase contract:

| Phase | Responsibility | Description |
|-------|---------------|-------------|
| **Assess** | Evaluate current domain state | Check existing artifacts, inventory gaps, report status |
| **Recommend and Delegate** | Propose actions and spawn specialist agents | Prioritize initiatives, parallel dispatch for independent analyses |
| **Sharp Edges** | Document boundaries and constraints | Cross-domain boundaries, quality checks, what NOT to do |

### Current Domain Leaders

| Leader | Domain | Agents Orchestrated | Entry Point |
|--------|--------|-------------------|-------------|
| `cto` | Engineering | Research, review, design agents | Auto-consulted via brainstorm domain detection |
| `clo` | Legal | legal-document-generator, legal-compliance-auditor | Auto-consulted via brainstorm domain detection |
| `cmo` | Marketing | 11 specialists | Auto-consulted via brainstorm domain detection |
| `coo` | Operations | ops-advisor, ops-research, ops-provisioner | Auto-consulted via brainstorm domain detection |
| `cpo` | Product | spec-flow-analyzer, ux-design-lead, business-validator | Auto-consulted via brainstorm domain detection |
| `cfo` | Finance | budget-analyst, revenue-analyst, financial-reporter | Auto-consulted via brainstorm domain detection |
| `cro` | Sales | outbound-strategist, deal-architect, pipeline-analyst | Auto-consulted via brainstorm domain detection |
| `cco` | Support | ticket-triage, community-manager | Auto-consulted via brainstorm domain detection |

### Adding a New Domain Leader

1. Create `agents/<domain>/` with leader + specialist `.md` files
2. Follow the 3-phase contract (Assess, Recommend/Delegate, Sharp Edges) -- use `agents/legal/clo.md` as template
3. Add a row to the Domain Config table in `skills/brainstorm/SKILL.md` Phase 0.5 with: domain name, assessment question, leader name, routing prompt, options, and task prompt
4. Add disambiguation sentences to agents with overlapping scope in adjacent domains (both directions)
5. Verify token budget: `shopt -s globstar && grep -h 'description:' agents/**/*.md | wc -w` (under 2,500)
6. Update docs data files: `agents.js` (DOMAIN_META, DOMAIN_CSS_VARS, domainOrder), `style.css` (CSS variable). Landing page and legal docs update automatically from data.
7. Update AGENTS.md (directory tree, domain leader table) and README.md (agent section, counts)
8. Version bump (MINOR) and CHANGELOG

## Documentation

See `knowledge-base/learnings/plugin-versioning-requirements.md` for detailed versioning workflow.
