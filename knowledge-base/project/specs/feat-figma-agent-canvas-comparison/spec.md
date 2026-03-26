# Spec: Multi-Backend Design Abstraction (Pencil + Figma MCP)

**Issue:** [#1158](https://github.com/jikig-ai/soleur/issues/1158)
**Phase:** 3 (Make it Sticky) — Item 3.4
**Status:** Draft
**Created:** 2026-03-26

## Problem Statement

Soleur's design workflow is tightly coupled to Pencil.dev via the `ux-design-lead` agent and custom MCP adapter. With Figma opening their canvas to agents via an official MCP server (March 2026), Soleur needs to support multiple design tool backends to serve users in both local-first and cloud-collaborative workflows.

## Goals

1. Support Pencil.dev AND Figma as design backends through the same `ux-design-lead` agent
2. Maintain Pencil as the default for local/headless/CI scenarios (no GUI, no rate limits, git-trackable files)
3. Enable Figma for teams already in the Figma ecosystem (cloud-collaborative, design system libraries)
4. Keep the abstraction minimal — thin skills layer, not a heavy middleware

## Non-Goals

- Replacing Pencil.dev with Figma
- Building a universal design tool adapter (only Pencil + Figma for now)
- Migrating existing .pen assets to Figma
- Supporting Figma's desktop-only MCP server mode (remote mode only)

## Functional Requirements

| ID | Requirement |
|----|------------|
| FR1 | `ux-design-lead` agent detects available MCP tool namespaces (`mcp__pencil__*` and/or `mcp__figma__*`) at task start |
| FR2 | If both backends available, agent asks user preference or reads config |
| FR3 | `pencil-design` skill encapsulates all Pencil-specific MCP tool instructions |
| FR4 | `figma-design` skill encapsulates all Figma-specific MCP tool instructions |
| FR5 | Both skills produce equivalent output quality for the same design brief |
| FR6 | Design artifacts are saved to appropriate location (`.pen` files for Pencil, Figma cloud for Figma) |

## Technical Requirements

| ID | Requirement |
|----|------------|
| TR1 | No new MCP adapter code — Figma provides their own MCP server |
| TR2 | Figma MCP server registration via existing `pencil-setup` skill (renamed to `design-setup`) or separate `figma-setup` skill |
| TR3 | Agent instructions fork cleanly based on detected backend — no interleaved conditionals |
| TR4 | Figma OAuth flow handled by Figma's MCP server (no custom auth) |
| TR5 | Rate limit awareness: agent should handle Figma rate limit errors gracefully |

## Architecture

```
ux-design-lead agent
  ├── detects: mcp__pencil__* tools → loads pencil-design skill
  └── detects: mcp__figma__* tools → loads figma-design skill

pencil-design skill                    figma-design skill
  ├── batch_design                       ├── use_figma
  ├── batch_get                          ├── get_design_context
  ├── get_screenshot                     ├── get_screenshot
  ├── snapshot_layout                    ├── get_variable_defs
  ├── get_guidelines                     ├── search_design_system
  ├── get_style_guide                    ├── create_new_file
  ├── set_variables                      ├── create_design_system_rules
  ├── export_nodes                       └── generate_figma_design
  └── open_document
```

## Tool Mapping (Pencil ↔ Figma)

| Operation | Pencil Tool | Figma Tool |
|-----------|------------|------------|
| Create/modify design | `batch_design` | `use_figma` |
| Read design data | `batch_get` | `get_design_context` / `get_metadata` |
| Screenshot | `get_screenshot` | `get_screenshot` |
| Design system tokens | `get_style_guide` / `get_variables` | `get_variable_defs` / `search_design_system` |
| Layout analysis | `snapshot_layout` | `get_metadata` |
| Create file | `open_document` | `create_new_file` |
| Export | `export_nodes` | (via Figma export API) |
| Design guidelines | `get_guidelines` | `create_design_system_rules` |

## Open Questions

1. Figma's MCP API is in beta — tool surface may change. How do we handle breaking changes?
2. Can Figma design tokens be imported into Pencil (or vice versa) for cross-tool consistency?
3. What are Figma's post-beta pricing implications for high-frequency agent workflows?
4. Should `design-setup` replace `pencil-setup` or coexist as separate skills?

## Dependencies

- Figma MCP server stability (currently beta)
- Phase 3 item 3.5 (secure token storage) for Figma OAuth credentials
