# Feature: Domain-First Directory Restructure

## Problem Statement

The Soleur plugin's directory structure was built for engineering workflows only. As the project expands to marketing/content, product/design, and branding domains, the flat skill layout and function-only agent categorization cannot scale to support multiple business domains without becoming an unnavigable mess.

## Goals

- Reorganize agents, commands, and skills by startup function domain (shared, engineering, product, growth, operations, support) with a shared tier for cross-domain components
- Enable adding new domains by simply creating subdirectories
- Provide a clear classification of existing components as shared vs engineering-specific
- Clean break at version 2.0.0

## Non-Goals

- Building actual marketing, branding, or product-design agents/skills (that comes later)
- Changing how the plugin loader discovers files (assume it walks directories recursively)
- Renaming any existing agents, commands, or skills (only moving them)
- Splitting into multiple plugins

## Functional Requirements

### FR1: Domain-first directory structure

Reorganize `agents/`, `commands/`, and `skills/` into domain subdirectories with a `shared/` tier:

```
agents/
  shared/research/          # Cross-domain research agents
  shared/workflow/          # Cross-domain workflow agents
  engineering/review/       # Code review agents
  engineering/design/       # Architecture agents
  product/                  # Design, branding, user research
  growth/                   # Marketing, sales, analytics
  operations/               # Finance, legal, HR
  support/                  # Customer success, onboarding

commands/
  shared/soleur/            # Core workflow commands
  shared/*.md               # Cross-domain utility commands
  engineering/*.md          # Engineering-specific commands
  product/
  growth/
  operations/
  support/

skills/
  shared/brainstorming/     # Cross-domain skills
  shared/git-worktree/
  engineering/dhh-rails-style/  # Engineering-specific skills
  engineering/atdd-developer/
  product/
  growth/
  operations/
  support/
```

### FR2: Component classification

Every existing component must be classified as either `shared` or `engineering` based on the classification guide in the brainstorm document. Components are `shared` if they serve any domain; `engineering` if they specifically target software development workflows.

### FR3: Empty domain directories

Create placeholder directories for new domains: `product/`, `growth/`, `operations/`, `support/` under agents, commands, and skills. Each gets a minimal README.md explaining its purpose and what kind of components belong there.

### FR4: Reference integrity

All references between commands and agents must be updated to reflect new paths. A `grep -r` audit must confirm zero stale path references.

## Technical Requirements

### TR1: MAJOR version bump

Update plugin version to 2.0.0 in plugin.json, CHANGELOG.md, README.md, root README.md badge, and bug report template.

### TR2: CHANGELOG documentation

Document every moved file in the CHANGELOG under a "Changed" section with a clear "BREAKING: Directory structure reorganized by domain" notice.

### TR3: README restructure

Update README.md tables to include a "Domain" column or reorganize tables by domain section.

### TR4: AGENTS.md update

Update the directory structure documentation in `plugins/soleur/AGENTS.md` to reflect the new domain-first layout.

### TR5: Git history preservation

Use `git mv` for all file moves to preserve git history/blame.
