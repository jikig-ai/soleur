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
├── marketing/             # Brand and marketing agents
├── operations/            # Ops and expense agents
└── product/               # Product analysis and design agents
    └── design/            # UX design agents

commands/
└── soleur/                # All commands (soleur:plan, soleur:review, etc.)

skills/
└── <skill-name>/          # All skills at root level (flat)
```

### Adding a New Domain

To add a new domain (e.g., product, growth):

1. Create `agents/<domain>/` for domain-specific agents
2. Skills stay flat at root level (the skill loader does not recurse into subdirectories)
3. Commands stay under `commands/soleur/` (they are domain-agnostic workflow orchestrators)
4. The plugin loader discovers agents recursively -- no config changes needed

## Command Naming Convention

**Soleur commands** use `soleur:` prefix to avoid collisions with built-in commands:

- `/soleur:brainstorm` - Brainstorm
- `/soleur:plan` - Create implementation plans
- `/soleur:review` - Run comprehensive code reviews
- `/soleur:work` - Execute work items systematically
- `/soleur:compound` - Document solved problems

**Why `soleur:`?** Claude Code has built-in `/plan` and `/review` commands. Using `name: soleur:plan` in frontmatter creates a unique `/soleur:plan` command with no collision.

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

## Documentation

See `knowledge-base/learnings/plugin-versioning-requirements.md` for detailed versioning workflow.
