# Spec: Integrate Vercel MCP

**Issue:** #258
**Date:** 2026-02-22
**Status:** Draft

## Problem Statement

Soleur users who host projects on Vercel have no agent-level access to their Vercel platform (deployments, logs, projects, domains). The Vercel MCP server provides these capabilities but is not integrated into the plugin.

## Goals

- G1: Add Vercel MCP server to plugin.json so all Soleur agents can access Vercel platform tools
- G2: Document the integration in README.md MCP Servers section
- G3: Maintain consistency with existing Context7 MCP integration pattern

## Non-Goals

- Updating agent instructions to reference specific Vercel tools (premature without usage data)
- Creating a dedicated Vercel agent
- Modifying the existing deploy skill
- Supporting project-scoped Vercel MCP URLs (can add later)

## Functional Requirements

- FR1: Vercel MCP server entry in plugin.json under `mcpServers`
- FR2: README.md MCP Servers section documents Vercel MCP and its capabilities
- FR3: CHANGELOG.md entry for the addition

## Technical Requirements

- TR1: Use HTTP transport type (same as Context7)
- TR2: URL: `https://mcp.vercel.com`
- TR3: Version bump (MINOR -- new capability) across plugin.json, CHANGELOG.md, README.md

## Acceptance Criteria

- [ ] `plugin.json` contains `vercel` entry in `mcpServers` with correct URL
- [ ] README.md MCP Servers section lists Vercel MCP with tool categories
- [ ] CHANGELOG.md documents the addition
- [ ] Version bumped (MINOR) in all three files
