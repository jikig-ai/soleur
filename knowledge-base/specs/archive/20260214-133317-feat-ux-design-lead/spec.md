# feat: UX Design Lead Agent + Pencil MCP Integration

**Issue:** #87
**Branch:** feat-ux-design-lead
**Brainstorm:** [2026-02-14-ux-design-lead-brainstorm.md](../../brainstorms/2026-02-14-ux-design-lead-brainstorm.md)

## Problem Statement

PR #82 (brand identity) left design artifacts untracked (.pen files, playwright session data). More broadly, Soleur has no dedicated agent for visual design work. The brand-architect handles brand identity but doesn't create visual designs. The frontend-design skill generates code but doesn't produce design artifacts. There's a gap between brand strategy and code implementation where visual design exploration should happen.

## Goals

- G1: Commit missing design artifacts from PR #82 and establish conventions for .pen files
- G2: Bundle the Pencil MCP server so design tools are available out of the box
- G3: Create a ux-design-lead agent that handles the full UX design workflow in .pen files
- G4: Chain brand-architect -> ux-design-lead in the brainstorm brand routing

## Non-Goals

- Modifying brand-architect's core text-based workflow
- Generating code from .pen designs (frontend-design skill's responsibility)
- Building a full design system (future work)
- Automated design review capabilities

## Functional Requirements

- FR1: `.playwright-mcp/` added to .gitignore
- FR2: `knowledge-base/design/brand/brand-visual-identity-brainstorm.pen` committed
- FR3: Constitution updated with .pen file directory convention (`knowledge-base/design/{domain}/`)
- FR4: Pencil MCP server added to `plugin.json` mcpServers
- FR5: New `agents/design/ux-design-lead.md` agent file with full UX workflow instructions
- FR6: Brainstorm command updated to chain brand-architect -> ux-design-lead

## Technical Requirements

- TR1: Agent uses Pencil MCP tools (get_guidelines, get_style_guide, batch_design, get_screenshot)
- TR2: Agent reads brand-guide.md for color/typography decisions when available
- TR3: .pen files follow naming convention: `{descriptive-name}.pen` within domain directories
- TR4: Plugin version bumped (MINOR -- new agent + MCP server)
- TR5: CHANGELOG.md, README.md, plugin.json all updated

## Implementation Notes

### Agent Capabilities (ux-design-lead)

The agent should handle:
1. **Wireframes** -- Low-fidelity layout exploration
2. **Visual design** -- High-fidelity screens using brand colors/typography
3. **Design system components** -- Reusable components in .pen format
4. **Design validation** -- Screenshot-based visual QA

### Pencil MCP Server Config

Add to plugin.json mcpServers alongside context7. Reference the pencil.dev MCP endpoint.

### Brainstorm Chain

In `commands/soleur/brainstorm.md`, after brand-architect completes:
- Ask user: "Would you like to explore visual design based on this brand identity?"
- If yes, spawn ux-design-lead with the brand-guide.md context
