---
title: "feat: Regenerate X/Twitter banner using Pencil MCP flow"
type: feat
date: 2026-03-10
---

# feat: Regenerate X/Twitter Banner via Pencil MCP Flow

[Updated 2026-03-10]

## Overview

Regenerate the @soleur_ai X/Twitter banner (1500x500px) using the Pencil MCP design flow. The original banner was created via Pillow-only pipeline because Pencil MCP was unavailable during the first session. Now Pencil Desktop is running with `--no-sandbox` and MCP is registered with `--app pencil`, enabling the intended design-first workflow: design in Pencil, export/screenshot, then upload to X.

## Problem Statement

The current banner (`plugins/soleur/docs/images/x-banner-1500x500.png`) was generated programmatically via Pillow with hardcoded coordinates and gradient code. While functional, it bypassed the Pencil mockup step (task 1.4 was skipped). Regenerating through Pencil MCP:

1. Establishes a `.pen` source-of-truth that can be iterated visually
2. Validates the Pencil Desktop MCP pipeline end-to-end (dogfooding)
3. Produces a higher-fidelity result through Pencil's design tools (proper kerning, visual alignment, gradient controls)

## Proposed Solution

**Pencil-first pipeline:** Design the banner in a `.pen` file using Pencil MCP tools, then export/screenshot for the final PNG. No Gemini dependency (free tier has zero image gen quota per learning).

### Pipeline

```
Pencil MCP (design in .pen) -> Screenshot/Export (1500x500 PNG) -> Playwright (upload to X)
```

1. **Verify Pencil MCP connection** via `get_editor_state` -- Pencil Desktop must be running
2. **Open or create .pen document** at `knowledge-base/design/brand/brand-visual-identity-brainstorm.pen` (existing file) or create a dedicated `x-banner.pen`
3. **Design banner** using `batch_design` MCP calls:
   - 1500x500 frame with `#0A0A0A` background
   - "S O L E U R" wordmark (Inter 500, 52px, gold `#C9A962`, centered horizontally, upper third)
   - "Build a Billion-Dollar Company. Alone." (Cormorant Garamond 500, 82px, white `#FFFFFF`, centered)
   - "60+ Agents . 8 Departments . 1 Founder" (Inter 400, 26px, secondary `#848484`, below thesis)
   - Gold gradient edge accents (`#D4B36A` left, `#B8923E` right)
   - 1px horizontal gold accent line at ~y=355, fading from center
4. **Screenshot/export** the canvas at 1500x500 resolution
5. **Save** to `plugins/soleur/docs/images/x-banner-1500x500.png` (overwrite existing)
6. **Upload** to @soleur_ai via Playwright MCP (headed mode)
7. **User saves .pen** (Ctrl+S) -- no programmatic save exists

## Technical Considerations

### Pencil Desktop MCP Mode

Per learning `2026-03-10-pencil-desktop-standalone-mcp-three-tier-detection.md`:
- Pencil Desktop is running with `--no-sandbox` (Electron flag for Linux)
- MCP registered with `--app pencil` (Desktop binary mode, not IDE mode)
- No IDE dependency -- `.pen` tab visibility in Cursor is NOT required
- Pencil Desktop must be running for MCP tools to connect

### MCP Tool Sequence

Per learning `2026-02-27-pencil-editor-operational-requirements.md` and constitution.md:

1. **Always `batch_get` before `batch_design`** -- mockup values diverge from assumptions
2. **`get_editor_state`** first to verify connection
3. **`get_screenshot`** after design changes to visually verify
4. **User must Ctrl+S** after all `batch_design` operations to flush to disk
5. **MCP tools resolve from repo root** -- use absolute paths for all file references

### Pencil MCP Tools Available

| Tool | Purpose |
|------|---------|
| `get_editor_state` | Verify Pencil Desktop is connected |
| `open_document` | Open the .pen file |
| `batch_design` | Create/modify design elements |
| `batch_get` | Read current property values |
| `get_screenshot` | Capture canvas state |
| `find_empty_space_on_canvas` | Find placement coordinates |
| `get_style_guide` | Read style guide settings |
| `snapshot_layout` | Capture layout structure |

### Font Handling in Pencil

Unlike Pillow (which needed TTF file downloads), Pencil Desktop uses system-installed fonts or its own font library. Verify Inter and Cormorant Garamond are available in Pencil's font picker. If not, the user may need to install them system-wide.

### Path Resolution

MCP tools resolve from the repo root, not shell CWD. Absolute paths required:
- .pen file: `/home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-x-twitter-banner/knowledge-base/design/brand/x-banner.pen`
- Output PNG: `/home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-x-twitter-banner/plugins/soleur/docs/images/x-banner-1500x500.png`

### Playwright Upload Flow

Same as original plan -- X Free tier API cannot upload banners:
1. Navigate to `x.com/settings/profile` via Playwright MCP (headed mode)
2. Pause for manual login if session expired
3. Click banner edit area, file upload, select image
4. Save profile
5. Screenshot `x.com/soleur_ai` for verification

## Non-Goals

- Redesigning the avatar or logo
- Creating banners for other platforms (Discord, GitHub)
- Light mode variant
- Gemini AI background generation (zero quota on free tier -- per learning)
- Building a reusable banner generation pipeline

## Acceptance Criteria

- [ ] Pencil MCP connection verified via `get_editor_state`
- [ ] Banner designed in .pen file using `batch_design` MCP tools
- [ ] Banner screenshot/export is exactly 1500x500px PNG
- [ ] Uses only brand colors (#0A0A0A bg, #C9A962 gold, #FFFFFF text)
- [ ] Typography uses Inter (wordmark) and Cormorant Garamond (thesis)
- [ ] Core content visible in center 60% (mobile safe zone ~900px)
- [ ] Avatar overlap area (bottom-left) has no critical content
- [ ] Banner uploaded and visible on @soleur_ai X profile
- [ ] .pen source file saved to `knowledge-base/design/brand/x-banner.pen`
- [ ] Final PNG saved to `plugins/soleur/docs/images/x-banner-1500x500.png`
- [ ] Brand guide X/Twitter banner section remains accurate

## Test Scenarios

- Given Pencil Desktop is running with `--no-sandbox`, when `get_editor_state` is called, then it returns a connected state
- Given the .pen document is open, when `batch_design` creates elements, then `batch_get` confirms the properties match the design spec
- Given the banner is exported at 1500x500, when viewed on desktop X profile, then all text is fully visible
- Given the banner on mobile X profile (center-cropped), when the center 900px is inspected, then wordmark and thesis remain visible
- Given the X avatar overlaps bottom-left, when the banner is displayed, then no text or key element is obscured
- Given the Playwright session is not authenticated on X, when navigating to settings, then the workflow pauses for manual login

## Dependencies & Risks

| Risk | Mitigation |
|------|-----------|
| Pencil Desktop MCP not connected | Gate on `get_editor_state` check before any design work |
| Fonts not available in Pencil | Verify font availability early; fall back to Pillow-only if critical fonts missing |
| `batch_design` cannot create complex gradients | Use solid gold accents instead of gradients; iterate with `get_screenshot` |
| .pen file not saved (no auto-save) | Prompt user to Ctrl+S after design phase; verify with `git status` |
| X auth session expired | Pause workflow for manual login, then resume Playwright automation |
| Export resolution mismatch | Verify dimensions with Pillow after export; resize if needed |

## Implementation Phases

### Phase 0: Pre-Flight Checks

1. Verify Pencil MCP connection: `mcp__pencil__get_editor_state`
2. Verify fonts are available in Pencil (Inter, Cormorant Garamond)
3. Verify existing .pen file or create new document

### Phase 1: Design in Pencil

1. Open/create .pen document via `mcp__pencil__open_document`
2. `batch_get` any existing elements to understand current state
3. Create 1500x500 frame with `#0A0A0A` background via `batch_design`
4. Add "S O L E U R" wordmark:
   - Font: Inter, weight 500, size 52px
   - Color: gold `#C9A962`
   - Position: centered horizontally, upper third (~y=140)
   - Letter spacing: 4
5. Add thesis text "Build a Billion-Dollar Company. Alone.":
   - Font: Cormorant Garamond, weight 500, size 82px
   - Color: white `#FFFFFF`
   - Position: centered horizontally and vertically (~y=220)
6. Add metrics "60+ Agents . 8 Departments . 1 Founder":
   - Font: Inter, weight 400, size 26px
   - Color: secondary `#848484`
   - Position: centered horizontally, below thesis (~y=310)
7. Add gold gradient edge accents (left `#D4B36A`, right `#B8923E`)
8. Add 1px horizontal gold accent line at ~y=355
9. `get_screenshot` to verify visual layout
10. Iterate with `batch_design` adjustments as needed
11. Prompt user to Ctrl+S to save .pen file

### Phase 2: Export and Upload

1. Export/screenshot canvas at 1500x500 resolution
2. Save PNG to `plugins/soleur/docs/images/x-banner-1500x500.png`
3. Verify dimensions (1500x500) and file size
4. Screenshot current @soleur_ai profile (backup)
5. Navigate to X settings via Playwright MCP (headed mode)
6. Upload banner image, save profile
7. Screenshot updated profile for verification

### Phase 3: Finalize

1. Verify brand guide X/Twitter banner section is still accurate
2. Run `soleur:compound` to capture Pencil MCP design learnings
3. Commit .pen file and updated PNG
4. Push to remote

## Semver Intent

`semver:patch` -- asset regeneration, no functional changes to plugin code.

## References

### Internal

- Brand guide: `knowledge-base/overview/brand-guide.md` (line 167-181 for X/Twitter banner specs)
- Existing banner: `plugins/soleur/docs/images/x-banner-1500x500.png`
- Existing .pen file: `knowledge-base/design/brand/brand-visual-identity-brainstorm.pen`
- Pencil setup skill: `plugins/soleur/skills/pencil-setup/SKILL.md`
- Pencil MCP operational requirements: `knowledge-base/learnings/2026-02-27-pencil-editor-operational-requirements.md`
- Pencil Desktop three-tier detection: `knowledge-base/learnings/2026-03-10-pencil-desktop-standalone-mcp-three-tier-detection.md`
- Electron headless crash: `knowledge-base/learnings/2026-03-10-electron-appimage-crashes-in-headless-terminal.md`
- X banner session errors: `knowledge-base/learnings/2026-03-10-x-banner-session-error-prevention.md`
- Original spec: `knowledge-base/specs/feat-x-banner/spec.md`
- Original tasks: `knowledge-base/specs/feat-x-banner/tasks.md`

### Related

- Issue: #483
- Original PR: #489
- Pencil Desktop MCP PR: #493 / #499
- Related: #480 (X links on website), #481 (surface parity)
