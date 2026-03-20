---
title: "refactor: Sync landing page .pen file after CaaS badge removal"
type: refactor
date: 2026-02-27
deepened: 2026-02-27
related_issue: "#323"
related_pr: "#317"
---

## Enhancement Summary

**Deepened on:** 2026-02-27
**Sections enhanced:** 4 (Implementation Steps, Acceptance Criteria, Risk Assessment, Context)

### Key Improvements

1. Added concrete .pen padding format documentation -- padding is specified as `[top, right, bottom, left]` array or `[vertical, horizontal]` shorthand or single value, matching CSS shorthand conventions
2. Added Pencil app prerequisite check -- `mcp__pencil__get_editor_state` will fail with `WebSocket not connected` if Pencil is not running; run `pencil-setup` skill first
3. Added worktree path constraint -- all MCP tool `filePath` parameters must use absolute paths from the repo root since MCP servers resolve paths independently of shell CWD
4. Added badge deletion ordering -- delete the badge container frame (not just the text child) to remove the entire pill element; the `D()` operation cascades to children

### New Considerations Discovered

- The `mcp__pencil__get_editor_state` call with `include_schema: true` returns the full .pen schema at runtime. This is critical for understanding how padding, layout, and spacing properties are structured before attempting updates. Always call this first.
- Padding in .pen files can be expressed as: a single number (uniform), a 2-element array `[vertical, horizontal]`, or a 4-element array `[top, right, bottom, left]`. Read the current padding value before updating to preserve the correct format.
- The `mcp__pencil__get_screenshot` tool returns a visual screenshot inline. It must be called with `filePath` (absolute path to .pen) and `nodeId`. This is the primary verification mechanism since .pen files are opaque.
- The `mcp__pencil__batch_get` search with `patterns: [{ "type": "text" }]` and a `parentId` scoped to the hero section is the most efficient way to find the badge text node. Searching the full document would return all text nodes across all mockups.

---

# refactor: Sync landing page .pen file after CaaS badge removal

The Pencil design file at `knowledge-base/design/brand/brand-visual-identity-brainstorm.pen` contains a landing page/homepage hero mockup that still shows the "The Company-as-a-Service Platform" badge. PR #317 (merged) removed this badge from the live landing page (`plugins/soleur/docs/index.njk`) and changed the hero top padding from `--space-12` (128px/8rem) to `--space-10` (80px/5rem). The .pen file needs to be updated to reflect the current live state so design and implementation stay in sync.

## Acceptance Criteria

- [x] The "Company-as-a-Service Platform" badge/pill element is removed from the landing page hero mockup in the .pen file
- [x] Hero top padding/spacing in the mockup is adjusted to match 80px (was 100px in .pen, not 128px as originally assumed)
- [x] A before/after screenshot is captured to verify the change visually
- [x] No other elements in the .pen file are modified (vision page, legal pages, etc. retain CaaS references)
- [x] This is a non-plugin change (design asset only) -- no version bump required

### Research Insights

**Pencil App Prerequisite:**
The Pencil desktop app must be running before any MCP tool calls. If it is not running, `mcp__pencil__get_editor_state` returns: `failed to connect to running Pencil app: cursor after 3 retries: WebSocket not connected to app: cursor`. Run the `pencil-setup` skill first if Pencil MCP is not registered, then launch Pencil from the system tray or application menu.

**Worktree Absolute Path Requirement:**
All `filePath` parameters in Pencil MCP tools must use the absolute worktree path:
`/home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-sync-landing-page-pen/knowledge-base/design/brand/brand-visual-identity-brainstorm.pen`

This is documented in `AGENTS.md` and confirmed by the Playwright screenshot learning (`knowledge-base/learnings/2026-02-17-playwright-screenshots-land-in-main-repo.md`): MCP servers resolve paths from their own process CWD (the repo root), not the shell CWD. Pencil MCP tools accept a `filePath` parameter that overrides this, but it must be absolute.

## Implementation Steps

### Phase 1: Discovery -- Explore the .pen file structure

1. **Open the .pen file** using Pencil MCP:
   - Call `mcp__pencil__open_document` with `filePathOrTemplate` set to the absolute path

2. **Get editor state** to understand the document:
   - Call `mcp__pencil__get_editor_state` with `include_schema: true`
   - This returns the .pen schema including property definitions for `padding`, `layout`, `gap`, etc.

3. **List top-level nodes** to find the landing page mockup:
   - Call `mcp__pencil__batch_get` with `filePath` (absolute) and no `patterns`/`nodeIds` to list document root children
   - Look for frames named "landing page", "homepage", "hero", or similar

4. **Drill into the landing page frame** once identified:
   - Call `mcp__pencil__batch_get` with `nodeIds: [<landing_page_id>]` and `readDepth: 3` to see the hero structure
   - Search for text nodes containing "Company-as-a-Service" or "CaaS"

### Research Insights

**Schema Discovery Strategy:**
The `get_editor_state` call with `include_schema: true` returns the full .pen file schema. This is the ground truth for how properties like `padding`, `gap`, and `layout` are represented. Always call this before attempting structural edits. The schema will reveal whether padding is stored as `padding` (uniform), `paddingTop`/`paddingRight`/`paddingBottom`/`paddingLeft` (individual), or a shorthand array.

**Node Search Efficiency:**
Use `parentId` to scope `batch_get` searches. Searching with `patterns: [{ "type": "text" }]` at the document root returns every text node in every mockup. Scoping to the hero section's parent ID returns only the relevant nodes. Start with `readDepth: 2` to see structure, then increase to 3 only if needed.

### Phase 2: Identify target elements

5. **Find the badge element** specifically:
   - Use `mcp__pencil__batch_get` with `patterns: [{ "type": "text" }]` and `parentId` set to the hero section ID
   - Look for text content matching "The Company-as-a-Service Platform"
   - Identify the badge container frame (the pill/badge wrapper around the text)
   - The badge in the HTML was a `<div class="hero-badge">` containing a `<span class="hero-badge-dot"></span>` and text. The .pen equivalent is likely a frame with `cornerRadius` (pill shape), containing a child frame (dot) and a text node.

6. **Capture a "before" screenshot**:
   - Call `mcp__pencil__get_screenshot` with `filePath` (absolute) and `nodeId` set to the landing page frame

7. **Measure current hero padding**:
   - Call `mcp__pencil__snapshot_layout` with `filePath` (absolute) and `parentId` set to the hero section
   - Note the current padding values

### Research Insights

**Badge Structure Prediction:**
Based on the CSS that was deleted in PR #317, the badge element had:
- A container frame with `border-radius` (pill shape), `border: 1px solid` accent color, horizontal layout
- A dot child (small circle with `background: accent`, `box-shadow` glow)
- A text child with "The Company-as-a-Service Platform"

In .pen format, this maps to:
- Frame with `cornerRadius: [large_value]` or `cornerRadius: "pill"`, `stroke` property, `layout: "horizontal"`
- Child frame (dot): small width/height, `fill` set to accent color, `cornerRadius` making it circular
- Child text: `content: "The Company-as-a-Service Platform"`

The deletion target is the top-level badge container frame. Deleting it with `D(<badge_frame_id>)` cascades to all children.

### Phase 3: Execute changes

8. **Delete the badge element**:
   - Call `mcp__pencil__batch_design` with `D(<badge_container_id>)` to delete the entire badge
   - Delete the container frame, not just the text child -- `D()` cascades to children
   - If the badge text and dot are direct children of the hero section (no wrapper frame), delete each individually

9. **Update hero padding**:
   - First read the current padding format from Phase 1 schema discovery
   - Call `mcp__pencil__batch_design` with `U(<hero_frame_id>, { padding: <new_value> })`
   - Match the existing format:
     - If padding is `[128, X, 128, X]` (4-value array): change to `[80, X, 80, X]` (keep horizontal values)
     - If padding is `[128, X]` (2-value array): change to `[80, X]`
     - If padding is `128` (single value): change to `80`
     - If padding is stored as individual `paddingTop`/`paddingBottom`: update `paddingTop` only

### Research Insights

**Padding Format in .pen Files:**
From the Pencil design system guidelines, padding in `batch_design` operations accepts these formats:
- Single number: `padding: 32` (uniform all sides)
- 2-element array: `padding: [16, 32]` (vertical, horizontal)
- 4-element array: `padding: [16, 32, 16, 32]` (top, right, bottom, left)

The CSS `.landing-hero` rule was `padding: var(--space-10) var(--space-5) var(--space-10)` which is `padding: 80px 24px 80px` (top, left/right, bottom). In .pen format, this maps to `[80, 24, 80, 24]` or `[80, 24]` depending on how the mockup was built.

**Critical: Read Before Write.**
Always read the current padding value with `batch_get` or `snapshot_layout` before updating. Blindly setting `padding: 80` when the current value is `[128, 24, 128, 24]` would change horizontal padding to 80 too, breaking the layout.

### Phase 4: Verify

10. **Capture an "after" screenshot**:
    - Call `mcp__pencil__get_screenshot` with `filePath` (absolute) and `nodeId` set to the landing page frame
    - Verify: badge is gone, hero h1 headline is now the first visible element in the hero, spacing looks tighter

11. **Check layout for problems**:
    - Call `mcp__pencil__snapshot_layout` with `filePath` (absolute), `parentId` set to the hero section, and `problemsOnly: true`
    - Verify no clipped elements or layout issues introduced by the removal

12. **Verify no collateral damage**:
    - Call `mcp__pencil__batch_get` with `patterns: [{ "type": "text" }]` and `searchDepth: 5` scoped to the full document
    - Grep results for "Company-as-a-Service" -- any matches outside the hero section should remain untouched
    - If other mockup screens exist (vision page, etc.), take a quick screenshot to confirm they are unchanged

### Research Insights

**Visual Verification is the Primary Gate:**
Since .pen files are opaque (encrypted binary), the `get_screenshot` tool is the only reliable way to verify changes. The `snapshot_layout` tool provides structural data (bounding boxes, padding, clipping) but not visual fidelity. Always use both: `snapshot_layout` for structural correctness, `get_screenshot` for visual correctness.

**After-State Checklist:**
In the "after" screenshot, verify:
- No badge/pill appears above the headline
- The headline "Build a Billion-Dollar Company. Alone." is the first visible text in the hero
- The vertical spacing between the top of the hero section and the headline is visibly tighter than the "before" screenshot
- No text is clipped or overlapping
- The rest of the landing page mockup below the hero is visually unchanged

## Test Scenarios

- Given the .pen file is opened, when searching for "Company-as-a-Service" text nodes in the hero section, then zero matches are found after the edit
- Given the hero section, when checking its top padding, then it resolves to 80 (not 128)
- Given the full document, when taking a screenshot of the landing page mockup, then no badge/pill appears above the h1
- Given other mockup screens in the .pen file, when inspecting their content, then they are unchanged

## Risk Assessment

**Low risk.** This is a design asset sync -- the .pen file is not consumed by any build pipeline. It serves as a visual reference only. The changes are minimal (delete one element, adjust one padding value). The Pencil MCP tools provide undo capability if something goes wrong.

### Research Insights

**Failure Modes and Recovery:**
1. **Pencil not running** -- `get_editor_state` returns WebSocket error. Recovery: launch Pencil app, re-run `pencil-setup` skill if needed.
2. **Badge element not found** -- the .pen file may have been updated separately, or the badge may use different text. Recovery: visually inspect with `get_screenshot` and search for text containing "CaaS" or "Company" instead.
3. **Padding format mismatch** -- writing a single value when a 4-value array is expected could collapse horizontal padding. Recovery: read current value first, preserve format.
4. **Wrong node deleted** -- if the hero frame itself is deleted instead of the badge child. Recovery: Pencil has undo, or revert from git.

All failure modes are recoverable. The .pen file is tracked in git, so `git checkout -- knowledge-base/design/brand/brand-visual-identity-brainstorm.pen` restores the original.

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
- **MCP paths resolve from repo root** (AGENTS.md): When in a worktree, always pass absolute paths to MCP tools. The .pen file path must be absolute.
- **Playwright screenshots land in main repo** (`knowledge-base/learnings/2026-02-17-playwright-screenshots-land-in-main-repo.md`): MCP servers resolve relative paths from their own process CWD (main repo root), not the Bash session CWD. Pencil MCP tools accept a `filePath` parameter that overrides this, but it must be absolute.

### Prior Art

- Plan for the code-side change: `knowledge-base/plans/2026-02-26-refactor-remove-caas-hero-badge-plan.md`
- PR #317: `refactor(docs): remove CaaS hero badge from landing page (v3.3.7)` (merged)

### Pencil MCP Tool Reference

| Tool | Purpose | Key Parameters |
|------|---------|----------------|
| `open_document` | Open the .pen file | `filePathOrTemplate`: absolute path |
| `get_editor_state` | Get schema and document state | `include_schema: true` for first call |
| `batch_get` | Read node tree, search by pattern | `filePath`, `nodeIds`, `patterns`, `parentId`, `readDepth`, `searchDepth` |
| `batch_design` | Insert/Update/Delete/Copy nodes | `filePath`, `operations` (I/U/D/C/R/M/G syntax) |
| `get_screenshot` | Visual screenshot of a node | `filePath`, `nodeId` |
| `snapshot_layout` | Layout data (bounds, padding, clipping) | `filePath`, `parentId`, `maxDepth`, `problemsOnly` |

## References

- Issue #323: Install Pencil if missing and sync landing page design in .pen file after CaaS badge removal
- `.pen` file: `knowledge-base/design/brand/brand-visual-identity-brainstorm.pen`
- Landing page template: `plugins/soleur/docs/index.njk`
- Landing page CSS: `plugins/soleur/docs/css/style.css` (lines 404-410, `.landing-hero`)
- CSS tokens: `--space-10: 5rem` (80px), `--space-12: 8rem` (128px)
- Pencil design system guidelines: `mcp__pencil__get_guidelines("design-system")`
- Pencil landing page guidelines: `mcp__pencil__get_guidelines("landing-page")`
