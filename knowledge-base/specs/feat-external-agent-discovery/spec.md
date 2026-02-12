# External Agent Discovery via Registry Integration

**Issue:** #55
**Branch:** `feat-external-agent-discovery`
**Date:** 2026-02-12
**Status:** Draft

## Problem Statement

The Soleur plugin ships with a fixed set of agents. When a project uses a framework or pattern not covered by built-in agents, users have no way to discover community-maintained agents from external registries. This limits the plugin's usefulness to the specific stacks its maintainers support.

## Goals

1. A dedicated discovery agent can search external registries (tessl.io, skills.sh) for relevant community agents.
2. Commands (review, plan, work) can invoke discovery when they detect capability gaps for the current project type.
3. Users can vet and install external agents with clear provenance tracking.
4. Installed community agents work identically to built-in agents (static markdown, offline-capable).

## Non-Goals

- Auto-installing agents without user consent.
- Building a custom agent registry or marketplace.
- Auto-updating installed community agents.
- Modifying how agents execute (only how they're discovered and installed).
- Supporting non-Soleur plugins or non-agent skill types.

## Functional Requirements

- **FR1:** Discovery agent searches external registries for agents matching the detected project type.
- **FR2:** Discovery uses MCP HTTP endpoints when available, falls back to CLI tools.
- **FR3:** Only agents meeting a minimum quality score threshold are surfaced.
- **FR4:** External agents overlapping with existing local agents are filtered out (conflict prevention).
- **FR5:** User sees registry source, score, description, and relevance rationale before approving installation.
- **FR6:** Approved agents are installed to `plugins/soleur/agents/community/` as standard markdown files with provenance frontmatter.
- **FR7:** Commands with discovery logic (review, plan, work) can spawn the discovery agent before starting their main workflow.
- **FR8:** Network failures degrade gracefully -- warn and continue with local agents only.

## Technical Requirements

- **TR1:** Discovery agent lives in `plugins/soleur/agents/discovery/agent-finder.md`.
- **TR2:** MCP server entries for registries are added to `plugin.json` only if HTTP endpoints are confirmed available.
- **TR3:** Installed community agents use standard agent frontmatter plus tracking fields (`source`, `installed`).
- **TR4:** Community agents are backward-compatible -- the plugin works identically if the `community/` directory is empty or absent.
- **TR5:** Version bump required: MINOR (new agent + new directory).

## Success Criteria

- User can run discovery and find a relevant external agent for their project type.
- Installing an external agent makes it available to all subsequent command runs.
- Removing a community agent (deleting the file) cleanly removes it from the system.
- All workflows function normally when registries are unreachable.
