# Learning: Pencil MCP is a Local Binary, Not a Bundleable Service

## Problem

When planning to bundle the Pencil MCP server in plugin.json mcpServers (like context7 which uses HTTP), we discovered that Pencil MCP is a local stdio binary bundled with the IDE extension (VS Code/Cursor). There is no npm package, no HTTP endpoint, and no way to reference it portably in plugin.json.

## Solution

Instead of trying to bundle Pencil MCP:
1. Document it as an optional dependency in the README
2. Have the agent check for tool availability and degrade gracefully with a clear error message
3. Link to installation docs: https://docs.pencil.dev/getting-started/installation

The agent's Prerequisites section checks if `mcp__pencil__*` tools are available and stops with installation instructions if not.

## Key Insight

Not all MCP servers can be distributed via plugin.json. HTTP servers (like context7) can be bundled. Stdio servers that depend on IDE extensions cannot -- they require separate installation. When designing agents that depend on external MCP tools, always include a graceful degradation path and clear installation instructions.

## Tags
category: integration-issues
module: plugin-architecture
symptoms: MCP server cannot be bundled in plugin.json
