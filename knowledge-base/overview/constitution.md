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
- Organize agents into category subdirectories (review/, research/, design/, workflow/, docs/)
- Skills must have a SKILL.md file and may include scripts/, references/, and assets/ subdirectories

### Never

- Never delete or overwrite user data; avoid destructive commands
- Never state conventions in constitution.md without tooling enforcement (config files, pre-commit hooks, or CI checks)

### Prefer

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

## Testing

### Always

- Run `bun test` before merging changes that affect parsing, conversion, or output
- All markdown files must pass markdownlint checks before commit

### Never

### Prefer

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
