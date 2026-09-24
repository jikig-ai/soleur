---
name: spec-templates
description: "This skill should be used when creating structured feature specifications and task tracking documents. It provides standardized templates for spec.md, tasks.md, and component.md in the knowledge-base/ directory."
---

<!-- soleur-cloud-mode:start -->
**Cloud Mode (Devin):** before pipeline work run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/cloud-detect.sh"`. If `CLAUDE_PLUGIN_ROOT` is unset (cloud exec shells do not export it), resolve the root by IDENTITY, never by script basename: for `d` in `"$HOME/.local/share/devin/cli/plugins/cache"` and `/opt/.devin/plugins`, skip unless `[ -d "$d" ]`, then `MANIFEST="$(find "$d" -path '*/.claude-plugin/plugin.json' -exec grep -l '"name"[[:space:]]*:[[:space:]]*"soleur"' {} + 2>/dev/null | head -1)"`, `ROOT="${MANIFEST%/.claude-plugin/plugin.json}"` — one resolution, two consumers: `$ROOT/scripts/cloud-detect.sh` and `$ROOT/scripts/precommit-guard.sh`. (Shape check, not authentication: a planted `{"name":"soleur"}` dir passes — ADR-179 A11.) `local` or `not-local:no-devin-env` proceeds normally; any other `not-local:<reason>` applies `<plugin-root>/devin/INSTRUCTIONS.md` §Cloud Mode: emit the `--banner`, fan out sequentially with `Reviewed-Coverage: sequential-fallback` disclosure (never claim an independent review ran), `message_user` ack before any secrets read or production mutation, and run `precommit-guard.sh` before any `git commit` — hooks do not fire in cloud.
<!-- soleur-cloud-mode:end -->

<!-- grok-harness-invoke:start -->
**Grok Build (`plugins/soleur/lib/harness.ts` `invokeSkill()`):** Read this SKILL.md in this process and run it to completion. A one-segment `soleur:<name>` in this document names a SKILL — on Grok Build, Read `plugins/soleur/skills/<name>/SKILL.md` in this process; it is not a nested tool_use. A multi-segment id such as `soleur:<domain>:<name>` names an AGENT: spawn it, never Read it, and on Grok Build spawn_subagent takes the id with its colons replaced by hyphens (`agentIdToGrokSubagentType`). **Claude Code:** Skill tool for a skill (`soleur:<name>`), Task tool with `subagent_type` for an agent. Forbidden is executing a subset, not the Read.
<!-- grok-harness-invoke:end -->

# Spec Templates

Provides templates for structured feature specifications.

## When to Use

- At the end of `soleur:brainstorm` to create spec.md
- At the end of `soleur:plan` to create tasks.md
- When starting any new feature in `knowledge-base/project/specs/`

**Vocabulary.** Before committing a word that names a concept, check it against `knowledge-base/project/glossary.md` and use the sense its pointer settles; if the word is materially ambiguous and has no entry, hedge in the artifact and name the ambiguity. The instruction is stated once in [glossary-format.md](../kb-glossary/references/glossary-format.md) §The consumer pointer and is not restated here.

## spec.md Template

Use this template for feature specifications:

```markdown
# Feature: [name]

## Problem Statement

[What problem are we solving?]

## Goals

- [What we want to achieve]

## Non-Goals

- [What is explicitly out of scope]

## Functional Requirements

### FR1: [name]

[User-facing behavior]

## Technical Requirements

### TR1: [name]

[Architecture, performance, security considerations]
```

## tasks.md Template

Use this template for task tracking:

```markdown
# Tasks: [name]

## Phase 1: Setup

- [ ] 1.1 Task description

## Phase 2: Core Implementation

- [ ] 2.1 Main task
  - [ ] 2.1.1 Subtask if needed

## Phase 3: Testing

- [ ] 3.1 Task description
```

## Directory Structure

Each feature gets its own directory:

```
knowledge-base/project/specs/feat-<name>/
  spec.md      # Requirements (FR/TR)   — indexed in INDEX.md
  tasks.md     # Phased task checklist  — indexed in INDEX.md
  <anything else>                        # working state, NOT indexed
```

Only `spec.md` and `tasks.md` are listed in `knowledge-base/INDEX.md`. Every other
file sitting **flat** in a spec directory is treated as branch-lifetime working state
and is on disk but unindexed (ADR-174). A file you deliberately organise into a
**subdirectory** stays indexed — that is the escape hatch for durable content. If a file here is durable knowledge rather than scratch,
either fold it into `spec.md` or file it under the knowledge-base domain it belongs
to — do not rely on it being discoverable through the index.

## Usage Examples

### Creating a spec for "user-auth" feature

1. Create directory: `knowledge-base/project/specs/feat-user-auth/`
2. Create `spec.md` using the template above
3. Fill in Problem Statement, Goals, Non-Goals
4. Add Functional Requirements (FR1, FR2, ...)
5. Add Technical Requirements (TR1, TR2, ...)

### Creating tasks from a spec

1. Read the spec.md to understand requirements
2. Create `tasks.md` using the template
3. Break down each FR/TR into concrete tasks
4. Organize into phases (Setup, Core, Testing)
5. Use hierarchical numbering (2.1, 2.1.1, etc.)

## component.md Template

Use this template for project overview component documentation in `knowledge-base/project/components/`:

```markdown
---
component: <component-name>
updated: YYYY-MM-DD
primary_location: <path/to/component/>
related_locations:
  - <other/path>
dependencies:
  - <other-component-name>
---

# <Component Name>

[One paragraph - what this component does]

## Purpose

[Why this component exists and its role in the system]

## Responsibilities

- [Key responsibility 1]
- [Key responsibility 2]

## Key Interfaces

[Public APIs, entry points, exported types]

## Data Flow

[How data enters and exits this component - include mermaid diagram if helpful]

## Dependencies

- **Internal**: [other components it uses]
- **External**: [third-party packages]

The `dependencies:` frontmatter list is the **machine-readable** form of the
`**Internal**` line and MUST be kept in agreement with it. The prose line is
human context; the frontmatter field is what
[`c4-from-components.ts`](../../lib/c4-from-components.ts) parses into diagram
edges. Emit both. A doc that names internal dependencies only in prose yields a
diagram of disconnected boxes — see the relationship-count gate in
[`sync.md`](../../commands/sync.md).

## Examples

[Usage examples with code]

## Related Files

- `path/to/file` - [description]

## See Also

- [constitution.md](../constitution.md) for coding conventions
- [Related component](./related.md)
```

### YAML Frontmatter Fields

| Field | Required | Description |
|-------|----------|-------------|
| `component` | Yes | Kebab-case component name |
| `updated` | Yes | Date last updated (YYYY-MM-DD) |
| `primary_location` | Yes | Main directory/file path |
| `related_locations` | No | Additional paths if component spans directories |
| `dependencies` | No | Kebab-case `component` names this component uses. The machine-readable form of the `**Internal**` line; parsed into C4 diagram edges. Omit (or `[]`) when the component genuinely has none |
| `status` | No | `active`, `deprecated` (default: active) |

### Creating a component doc

1. Identify the logical component (not just directory structure)
2. Create `knowledge-base/project/components/<name>.md`
3. Fill in frontmatter with accurate paths
4. Document purpose, responsibilities, and interfaces
5. Add data flow diagram if the component has complex interactions
6. Link to related files and other components

## prd.md Template

Use this template for reverse-engineered Product Requirements Documents emitted by [`code-to-prd`](../code-to-prd/SKILL.md). PRDs land at `knowledge-base/product/prd/<project>-prd.md`. Section order is load-bearing — the `code-to-prd` test harness asserts every header.

```markdown
---
project: "<package.json name, kebab-case>"
framework: "next.js"
generator: "code-to-prd@v1"
generated_at: "<ISO-8601 UTC>"
walker_count: <int>
walker_excluded: <int>
---

# PRD — <project-name>

<!-- BANNER:DUE-DILIGENCE — non-removable per code-to-prd FR7 -->
> **Due-diligence disclaimer.** [verbatim from banner-template.md]

<!-- BANNER:PII-CONFIDENTIALITY — non-removable per code-to-prd FR7 -->
> **Confidentiality / PII notice.** [verbatim from banner-template.md]

### How to Read This PRD

[Redaction-token format, "redacted ≠ leaked" framing, rotation instruction.]

## Overview

- Project name, framework detected, walk stats.

## Routes

### App Router

[Routes derived from `app/**/page.{tsx,jsx,ts,js}` and `app/**/route.{ts,js}`.]

### Pages Router

[Routes derived from `pages/**/*.{tsx,jsx,ts,js}` excluding `pages/_*`.]

## State Shapes

[Top-level `useState`/`useReducer`/server-component props (regex, best-effort).]

## API & External Dependencies

[fetch() URLs + `@/lib/api*`/`@/server/*` imports + `process.env.*` names + third-party SDK packages from `package.json`.]

## Coverage Caveats

### Frameworks not scanned
### Extraction techniques used
### Excluded by path filter
### GDPR Art. 9 special-category disclaimer

## Gap Analysis

[Populated by `soleur:product:spec-flow-analyzer` Task spawn. Degraded-success leaves `SKIPPED (soleur:product:spec-flow-analyzer unavailable at <ISO-8601>)`.]

---

_Adapted from `alirezarezvani/claude-skills` (MIT) — see [plugins/soleur/NOTICE](../../NOTICE)._
```

### Coverage Caveats contract

`## Coverage Caveats` MUST be non-empty on every emit. All four subsections are mandatory regardless of extractor coverage — even on a maximally simple input. "None" is forbidden. The four subsections (frameworks not scanned, extraction techniques, exclusion counts, Art. 9 disclaimer) are asserted by the `code-to-prd` test harness.

### Banner contract

Banners are **non-removable** — operator-edit of the rendered PRD is allowed, but the dual-banner block (sentinels `BANNER:DUE-DILIGENCE` + `BANNER:PII-CONFIDENTIALITY`) must remain intact. Verbatim string match enforced by the test harness.
