# External Agent Discovery via Registry Integration

**Issue:** #55
**Branch:** `feat-external-agent-discovery`
**Date:** 2026-02-12
**Updated:** 2026-02-18
**Status:** Draft (revised)

## Problem Statement

The Soleur plugin ships with a fixed set of agents and skills. When a project uses a framework or pattern not covered by built-in artifacts (Flutter, Rust, Elixir, etc.), users have no way to discover community-maintained alternatives. Discovery should happen naturally during the planning workflow, not require a separate command.

## Goals

1. During `/plan`, detect when the project's stack has no matching built-in agents/skills.
2. Query external registries for community artifacts matching the detected stack.
3. Only surface artifacts from trusted sources (Anthropic repos + verified publishers).
4. Install approved artifacts into the plugin's `community/` directories with provenance tracking.
5. Installed community artifacts work identically to built-in ones (offline-capable, standard markdown).

## Non-Goals

- Auto-installing artifacts without user consent.
- Building a custom registry or marketplace.
- Auto-updating installed community artifacts.
- Supporting discovery during commands other than `/plan` (v1).
- Discovery for MCP servers or hooks (only agents and skills).

## Prerequisites

- **Phase 0 loader test** -- Verify the plugin loader ignores unknown frontmatter fields (`stack`, `source`, `registry`, `installed`, `verified`). If it rejects them, provenance moves to markdown comment blocks.

Note: Skills loader recursion was originally listed as a prerequisite but is no longer needed. Skills use flat naming: `skills/community-<name>/SKILL.md` (works with current loader).

## Functional Requirements

- **FR1:** Pre-plan gap detection -- `/plan` detects the project stack and checks whether built-in agents/skills cover it.
- **FR2:** Registry search -- When a gap is detected, query `api.claude-plugins.dev`, `claudepluginhub.com`, and Anthropic's GitHub repos for matching artifacts.
- **FR3:** Source gating -- Only surface artifacts from trusted sources. Default allowlist: Anthropic repos + verified registry publishers. User-extensible.
- **FR4:** Conflict prevention -- Do not suggest artifacts that overlap with existing local agents/skills.
- **FR5:** User consent -- Present artifact name, source, description, and relevance rationale. User approves or skips each suggestion.
- **FR6:** Installation -- Approved agents install to `plugins/soleur/agents/community/`. Approved skills install to `plugins/soleur/skills/community-<name>/SKILL.md` (flat naming, no loader change needed).
- **FR7:** Provenance tracking -- Installed artifacts include frontmatter: `stack`, `source`, `installed`, `registry`, `verified`.
- **FR8:** Graceful degradation -- Network failures warn and continue with local agents only. Never blocks planning.

Note: Caching was originally FR8 but is deferred to v2. Re-detection uses the `stack` frontmatter field on installed agents, not a cache.

## Technical Requirements

- **TR1:** Discovery logic lives in a dedicated agent: `plugins/soleur/agents/engineering/discovery/agent-finder.md`.
- **TR2:** Data sources queried via Bash `curl` (unauthenticated JSON REST APIs). WebFetch avoided for JSON endpoints (designed for HTML).
- **TR3:** Trust allowlist hardcoded in agent instructions for v1. Configurable allowlist deferred to v2.
- **TR4:** Community directories are backward-compatible -- plugin works identically if `community/` is empty or absent.
- **TR5:** Registry research document maintained at `knowledge-base/specs/feat-external-agent-discovery/registry-research.md`.
- **TR6:** Version bump: MINOR (new agent + new directory + new behavior in `/plan`).

## Success Criteria

- Running `/plan` on a Flutter project (no built-in Flutter agents) triggers discovery and suggests relevant community agents.
- Installing a community agent makes it available to all subsequent command runs.
- Removing a community agent (deleting the file) cleanly removes it from the system.
- All workflows function normally when registries are unreachable.
- Artifacts from untrusted sources are never suggested.
