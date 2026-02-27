---
title: "refactor: Sync landing page .pen file after CaaS badge removal"
type: refactor
date: 2026-02-27
related_issue: "#323"
related_pr: "#317"
---

# refactor: Sync landing page .pen file after CaaS badge removal

The Pencil design file at `knowledge-base/design/brand/brand-visual-identity-brainstorm.pen` contains a landing page/homepage hero mockup that still shows the "The Company-as-a-Service Platform" badge. PR #317 (merged) removed this badge from the live landing page (`plugins/soleur/docs/index.njk`) and changed the hero top padding from `--space-12` (128px/8rem) to `--space-10` (80px/5rem). The .pen file needs to be updated to reflect the current live state so design and implementation stay in sync.

## Acceptance Criteria

- [ ] The "Company-as-a-Service Platform" badge/pill element is removed from the landing page hero mockup in the .pen file
- [ ] Hero top padding/spacing in the mockup is adjusted to match 80px (was 128px)
- [ ] A before/after screenshot is captured to verify the change visually
- [ ] No other elements in the .pen file are modified (vision page, legal pages, etc. retain CaaS references)
- [ ] This is a non-plugin change (design asset only) -- no version bump required

## Implementation Steps

### Phase 1: Discovery -- Explore the .pen file structure

1. **Open the .pen file** using Pencil MCP:
   - Call `mcp__pencil__open_document` with absolute path `/home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-sync-landing-page-pen/knowledge-base/design/brand/brand-visual-identity-brainstorm.pen`

2. **Get editor state** to understand the document:
   - Call `mcp__pencil__get_editor_state` with `include_schema: true` to understand the .pen schema

3. **List top-level nodes** to find the landing page mockup:
   - Call `mcp__pencil__batch_get` with no patterns/nodeIds to list document root children
   - Look for frames named "landing page", "homepage", "hero", or similar

4. **Drill into the landing page frame** once identified:
   - Call `mcp__pencil__batch_get` with the landing page node ID and `readDepth: 3` to see the hero structure
   - Search for text nodes containing "Company-as-a-Service" or "CaaS"

### Phase 2: Identify target elements

5. **Find the badge element** specifically:
   - Use `mcp__pencil__batch_get` with `patterns: [{ "type": "text" }]` scoped to the hero section
   - Look for text content matching "The Company-as-a-Service Platform"
   - Identify the badge container frame (the pill/badge wrapper around the text)

6. **Capture a "before" screenshot**:
   - Call `mcp__pencil__get_screenshot` on the landing page frame for reference

7. **Measure current hero padding**:
   - Call `mcp__pencil__snapshot_layout` on the hero section to see current padding values
   - Note the current `paddingTop` value (expected: 128px or equivalent)

### Phase 3: Execute changes

8. **Delete the badge element**:
   - Call `mcp__pencil__batch_design` with `D(<badge_node_id>)` to delete the badge
   - If the badge is a container frame with a text child, delete the container (which removes children too)

9. **Update hero padding**:
   - Call `mcp__pencil__batch_design` with `U(<hero_frame_id>, { padding: ... })` to change top padding from 128 to 80
   - The exact property depends on how padding is stored in the .pen schema (could be `padding`, `paddingTop`, or a padding array)

### Phase 4: Verify

10. **Capture an "after" screenshot**:
    - Call `mcp__pencil__get_screenshot` on the landing page frame
    - Verify: badge is gone, hero h1 headline is now the first visible element in the hero, spacing looks tighter

11. **Check layout for problems**:
    - Call `mcp__pencil__snapshot_layout` with `problemsOnly: true` on the hero section
    - Verify no clipped elements or layout issues introduced by the removal

12. **Verify no collateral damage**:
    - Check that other mockup screens in the .pen file are unmodified
    - If there are other references to "Company-as-a-Service" in other screens (vision page mockup, etc.), those should be left as-is

## Test Scenarios

- Given the .pen file is opened, when searching for "Company-as-a-Service" text nodes in the hero section, then zero matches are found after the edit
- Given the hero section, when checking its top padding, then it resolves to 80 (not 128)
- Given the full document, when taking a screenshot of the landing page mockup, then no badge/pill appears above the h1
- Given other mockup screens in the .pen file, when inspecting their content, then they are unchanged

## Risk Assessment

**Low risk.** This is a design asset sync -- the .pen file is not consumed by any build pipeline. It serves as a visual reference only. The changes are minimal (delete one element, adjust one padding value). The Pencil MCP tools provide undo capability if something goes wrong.

## Context

### Files to Edit

| File | Change |
|------|--------|
| `knowledge-base/design/brand/brand-visual-identity-brainstorm.pen` | Remove CaaS badge element; adjust hero padding from 128 to 80 |

### Files NOT to Edit

No plugin files, no version bump, no CHANGELOG entry. This is a design asset sync, not a plugin change.

### Relevant Learnings

- **Pencil MCP local binary constraint** (`knowledge-base/learnings/2026-02-14-pencil-mcp-local-binary-constraint.md`): Pencil MCP is a local stdio binary bundled with the IDE extension. The `pencil-setup` skill (PR #335) handles registration.
- **Pencil MCP auto-registration** (`knowledge-base/learnings/2026-02-27-pencil-mcp-auto-registration-via-skill.md`): The `pencil-setup` skill uses `claude mcp add -s user` for global scope. The remove-then-add pattern ensures idempotent registration.
- **MCP paths resolve from repo root** (AGENTS.md): When in a worktree, always pass absolute paths to MCP tools. The .pen file path must be absolute: `/home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-sync-landing-page-pen/knowledge-base/design/brand/brand-visual-identity-brainstorm.pen`

### Prior Art

- Plan for the code-side change: `knowledge-base/plans/2026-02-26-refactor-remove-caas-hero-badge-plan.md`
- PR #317: `refactor(docs): remove CaaS hero badge from landing page (v3.3.7)` (merged)

## References

- Issue #323: Install Pencil if missing and sync landing page design in .pen file after CaaS badge removal
- `.pen` file: `knowledge-base/design/brand/brand-visual-identity-brainstorm.pen`
- Landing page template: `plugins/soleur/docs/index.njk`
- Landing page CSS: `plugins/soleur/docs/css/style.css` (lines 404-410, `.landing-hero`)
- CSS tokens: `--space-10: 5rem` (80px), `--space-12: 8rem` (128px)
