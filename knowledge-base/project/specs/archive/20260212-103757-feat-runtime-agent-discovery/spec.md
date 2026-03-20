# Runtime Agent Discovery and Project-Aware Filtering

**Issue:** #46
**Branch:** `feat-runtime-agent-discovery`
**Date:** 2026-02-12
**Status:** Draft

## Problem Statement

The Soleur review command (and other commands) hardcode agent lists that include framework-specific agents (e.g., `kieran-rails-reviewer`, `dhh-rails-reviewer`) regardless of the project's actual tech stack. This wastes tokens and time on irrelevant reviews, and means the plugin can't leverage community-maintained agents from external registries.

## Goals

1. Commands automatically detect project type and only spawn relevant local agents.
2. External agent registries (tessl.io, skills.sh) are queryable via MCP servers for discovering new agents.
3. Users can approve and install external agents with tiered security vetting.
4. Installed external agents become first-class plugin agents (persist, work offline).

## Non-Goals

- Auto-installing agents without user consent.
- Building a custom agent registry or marketplace.
- Modifying how agents execute (only how they're selected and discovered).
- Supporting non-Soleur plugins.

## Functional Requirements

- **FR1:** Project type detection via file-based heuristics (`Gemfile`, `package.json`, `go.mod`, `Cargo.toml`, `pyproject.toml`, etc.).
- **FR2:** Agent frontmatter extended with `frameworks`, `languages`, and `applies-to` metadata fields.
- **FR3:** Commands filter agents by matching project type against agent metadata before spawning.
- **FR4:** MCP server integration for tessl.io and/or skills.sh to query external agent registries.
- **FR5:** Agent suggestion flow: detect project type -> query registry -> present candidates with rationale and risk score -> user approves -> install to `plugins/soleur/agents/`.
- **FR6:** Tiered security assessment: quick summary (source, popularity, last updated) by default, opt-in deep scan (permissions, tool access, vulnerabilities).
- **FR7:** Any command (not just review) can trigger agent discovery and suggestion.

## Technical Requirements

- **TR1:** Agent metadata tags must be backward-compatible (agents without tags are treated as universal).
- **TR2:** MCP server integration follows the same pattern as context7 (tool-based, no custom HTTP clients).
- **TR3:** Installed external agents are standard markdown files in `plugins/soleur/agents/` with no special runtime treatment.
- **TR4:** Project detection must complete in under 1 second (file existence checks only, no parsing).
- **TR5:** Version bump required: MINOR (new feature).

## Success Criteria

- Running `/soleur:review` on a TypeScript project does not spawn Rails-specific agents.
- Running `/soleur:review` on a Rails project still spawns Rails-specific agents.
- User can discover, vet, and install an external agent from a registry in a single workflow.
- Installed external agents participate in subsequent command runs automatically.
