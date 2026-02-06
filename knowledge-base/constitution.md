# Project Constitution

Project principles organized by domain. Add principles as you learn them.

## Code Style

### Always

- Skill descriptions must use third person ("This skill should be used when..." NOT "Use this skill when...")
- Reference files in skills must use markdown links, not backticks (e.g., `[file.md](./references/file.md)`)

### Never

- Avoid second person ("you should") - use objective language ("To accomplish X, do Y")

### Prefer

- Prefer ASCII characters unless the file already contains Unicode
- Use imperative/infinitive form for instructions (verb-first)

## Architecture

### Always

- Core workflow commands use `soleur:` prefix to avoid collisions with built-in commands
- Every plugin change must update three files: plugin.json (version), CHANGELOG.md, and README.md (counts/tables)

### Never

- Never delete or overwrite user data; avoid destructive commands

### Prefer

- Use convention over configuration for documentation paths - branch names map to spec directories (`feat-<name>` → `knowledge-base/specs/feat-<name>/`)
- Include sequence diagrams for complex flows

## Testing

### Always

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

### Never

### Prefer
