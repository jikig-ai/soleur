---
title: "feat: Regenerate X/Twitter banner using Pencil MCP flow"
type: feat
date: 2026-03-10
---

# feat: Regenerate X/Twitter Banner via Pencil MCP Flow

[Updated 2026-03-10]

## Enhancement Summary

**Deepened on:** 2026-03-10
**Sections enhanced:** 7 (Technical Considerations, Implementation Phases 0-3, Dependencies & Risks, Test Scenarios)
**Research sources:** Pencil MCP tool schema inspection, live connection test, 8 institutional learnings, Pencil design guidelines, brand guide, ux-design-lead agent workflow

### Key Improvements

1. **Critical blocker discovered:** Live `get_editor_state` test returns `WebSocket not connected to app: pencil` despite Pencil Desktop running. The MCP is registered with `--app desktop` (not `--app pencil`). Phase 0 now includes a WebSocket troubleshooting sequence before any design work.
2. **Concrete `batch_design` operations:** Phase 1 now contains copy-paste-ready Pencil MCP operation syntax derived from the actual tool schema, replacing vague "use batch_design" instructions.
3. **Playwright screenshot path trap:** Screenshots from Playwright MCP land in the main repo root, not the worktree. All screenshot paths now use absolute worktree paths per learning `2026-02-17`.
4. **Export strategy clarified:** Pencil's `get_screenshot` returns an image via the MCP response (not a file on disk). The plan now includes the Pillow step to save the screenshot data to the target PNG path and verify exact 1500x500 dimensions.

### New Considerations Discovered

- The `--app` flag value in MCP registration (`desktop`) does not match the expected WebSocket target (`pencil`). This may require re-registration with `--app pencil` or investigating whether Pencil Desktop needs a document open before WebSocket connects.
- Pencil `batch_design` has a 25-operation limit per call. The banner design fits within this but should be split into 2 calls (frame+background, then text elements) for robustness.
- The `G()` (Generate Image) operation in `batch_design` supports AI-generated and stock images applied as frame fills -- this could replace programmatic gradients for background texture.
- `snapshot_layout(problemsOnly=true)` should be called after design to catch layout issues Pencil detects automatically.

---

## Overview

Regenerate the @soleur_ai X/Twitter banner (1500x500px) using the Pencil MCP design flow. The original banner was created via Pillow-only pipeline because Pencil MCP was unavailable during the first session. Now Pencil Desktop is running with `--no-sandbox` and MCP is registered with `--app desktop`, enabling the intended design-first workflow: design in Pencil, export/screenshot, then upload to X.

## Problem Statement

The current banner (`plugins/soleur/docs/images/x-banner-1500x500.png`) was generated programmatically via Pillow with hardcoded coordinates and gradient code. While functional, it bypassed the Pencil mockup step (task 1.4 was skipped). Regenerating through Pencil MCP:

1. Establishes a `.pen` source-of-truth that can be iterated visually
2. Validates the Pencil Desktop MCP pipeline end-to-end (dogfooding)
3. Produces a higher-fidelity result through Pencil's design tools (proper kerning, visual alignment, gradient controls)

## Proposed Solution

**Pencil-first pipeline:** Design the banner in a `.pen` file using Pencil MCP tools, then export/screenshot for the final PNG. No Gemini dependency (free tier has zero image gen quota per learning).

### Pipeline

```
Pencil MCP (design in .pen) -> get_screenshot (capture) -> Pillow (verify 1500x500) -> Playwright (upload to X)
```

1. **Verify Pencil MCP connection** via `get_editor_state` -- resolve WebSocket blocker first
2. **Open or create .pen document** -- use `open_document` with absolute path or `"new"`
3. **Design banner** using `batch_design` MCP calls (2 batches, max 25 ops each)
4. **Verify layout** via `get_screenshot` and `snapshot_layout(problemsOnly=true)`
5. **Save screenshot** to PNG via Pillow (screenshot returns image data, not a file)
6. **Verify dimensions** are exactly 1500x500px
7. **Upload** to @soleur_ai via Playwright MCP (headed mode, absolute paths)
8. **User saves .pen** (Ctrl+S) -- no programmatic save exists

## Technical Considerations

### Pencil Desktop MCP Mode

Per learning `2026-03-10-pencil-desktop-standalone-mcp-three-tier-detection.md`:

- Pencil Desktop is running with `--no-sandbox` (Electron flag for Linux)
- MCP registered with `--app desktop` (Desktop binary mode, not IDE mode)
- No IDE dependency -- `.pen` tab visibility in Cursor is NOT required
- Pencil Desktop must be running for MCP tools to connect

### Research Insights: WebSocket Connection Blocker

**Live test result:** `get_editor_state` returns `WebSocket not connected to app: pencil` despite:

- Pencil Desktop process confirmed running (PID 248616, `--no-sandbox`)
- MCP server registered and showing "Connected" in `claude mcp list`
- Display server available (X11 `:0`, Wayland `wayland-0`)

**Diagnosis sequence for Phase 0:**

1. Check if Pencil Desktop has a document open (WebSocket may only connect when a canvas is active)
2. If no document is open, use `open_document` with `"new"` to create one -- this may establish the WebSocket
3. If still failing, check `--app` flag mismatch: registration uses `--app desktop` but error says `app: pencil`. May need re-registration:

   ```bash
   claude mcp remove pencil
   claude mcp add pencil -- /tmp/.mount_PencilVuY4uO/resources/app.asar.unpacked/out/mcp-server-linux-x64 --app pencil
   ```

4. After re-registration, restart Claude Code for the MCP to reconnect
5. If still failing after restart, the AppImage mount path (`/tmp/.mount_PencilVuY4uO/`) may have changed. Re-extract and verify the path with `pgrep -a pencil`

**Key insight from learnings:** The MCP server binary and the Desktop app communicate via WebSocket. The "Connected" status in `claude mcp list` means the MCP binary started, not that it connected to Desktop. The WebSocket handshake is a separate step.

### MCP Tool Sequence

Per learning `2026-02-27-pencil-editor-operational-requirements.md` and constitution.md:

1. **Always `batch_get` before `batch_design`** -- mockup values diverge from assumptions
2. **`get_editor_state`** first to verify connection
3. **`get_screenshot`** after design changes to visually verify
4. **`snapshot_layout(problemsOnly=true)`** after design to catch Pencil-detected issues
5. **User must Ctrl+S** after all `batch_design` operations to flush to disk
6. **MCP tools resolve from repo root** -- use absolute paths for all file references
7. **Max 25 operations per `batch_design` call** -- split complex designs into multiple calls

### Research Insights: batch_design Operation Syntax

The `batch_design` tool uses a JavaScript-like DSL with specific operations:

| Operation | Syntax | Purpose |
|-----------|--------|---------|
| Insert | `id=I(parent, {nodeData})` | Create new element |
| Update | `U(path, {updateData})` | Modify existing element |
| Copy | `id=C(sourceId, parent, {overrides})` | Duplicate element |
| Replace | `id=R(path, {nodeData})` | Swap element contents |
| Delete | `D(nodeId)` | Remove element |
| Move | `M(nodeId, parent, index)` | Reposition element |
| Image | `G(nodeId, "ai"/"stock", prompt)` | Apply image fill |

**Critical rules:**

- Every I(), C(), R() MUST have a binding name (left-hand assignment)
- `"document"` is a predefined binding for the document root
- Bindings only work within the same `batch_design` call
- On error, all operations in that call are rolled back
- Images are fills on frames/rectangles -- there is no "image" node type

### Pencil MCP Tools Available

| Tool | Purpose | Key Notes |
|------|---------|-----------|
| `get_editor_state` | Verify Pencil Desktop is connected | Returns selection, canvas state; pass `include_schema=true` for .pen schema |
| `open_document` | Open .pen file or create new | Pass absolute path or `"new"` |
| `batch_design` | Create/modify design elements | Max 25 ops per call; JavaScript-like DSL |
| `batch_get` | Read current property values | Combine searches into one call; use `patterns` for type/name search |
| `get_screenshot` | Capture canvas/node state | Returns image data in MCP response, not file |
| `find_empty_space_on_canvas` | Find placement coordinates | Useful for auto-positioning new frames |
| `get_style_guide` / `get_style_guide_tags` | Read design inspiration | Tags-based style guide retrieval |
| `get_guidelines` | Design rules by topic | Topics: landing-page, design-system, table, code, tailwind |
| `snapshot_layout` | Capture layout structure | Use `problemsOnly=true` to catch issues |
| `get_variables` / `set_variables` | Manage design tokens | Could store brand palette as variables |

### Font Handling in Pencil

Unlike Pillow (which needed TTF file downloads), Pencil Desktop uses system-installed fonts or its own font library. Verify Inter and Cormorant Garamond are available in Pencil's font picker.

### Research Insights: Font Verification

Before designing, verify fonts by creating a test text node and checking `get_screenshot`:

```javascript
// Test font availability
testText=I(document, {type:"text", content:"Font Test", fontFamily:"Inter", fontSize:20})
```

If the font renders as a fallback (default sans-serif), it is not installed. Install system-wide:

```bash
# Inter and Cormorant Garamond from google/fonts GitHub repo
# Already in tmp/fonts/ from the original Pillow session if available
fc-list | grep -i "inter\|cormorant"
```

### Path Resolution

MCP tools resolve from the repo root, not shell CWD. Absolute paths required:

- .pen file: `/home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-x-twitter-banner/knowledge-base/design/brand/x-banner.pen`
- Output PNG: `/home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-x-twitter-banner/plugins/soleur/docs/images/x-banner-1500x500.png`

### Research Insights: Playwright Path Trap

Per learning `2026-02-17-playwright-screenshots-land-in-main-repo.md`:

**Playwright MCP screenshots land in the MAIN REPO root, not the worktree.** Always pass absolute worktree paths:

```
# WRONG -- lands in /home/jean/git-repositories/jikig-ai/soleur/
browser_take_screenshot(filename: "x-profile-after.png")

# RIGHT -- lands in worktree
browser_take_screenshot(filename: "/home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-x-twitter-banner/tmp/x-profile-after.png")
```

After upload verification, clean up any screenshots that leaked to the main repo:

```bash
ls /home/jean/git-repositories/jikig-ai/soleur/*.png 2>/dev/null
```

### Playwright Upload Flow

Per learning `2026-03-09-x-provisioning-playwright-automation.md`:

X Free tier API cannot upload banners. Use Playwright MCP in headed mode:

1. Navigate to `x.com/settings/profile` via `browser_navigate`
2. Take `browser_snapshot` to assess page state
3. If login required: pause for manual auth (per ops-provisioner pattern: never enter credentials via automation)
4. Click banner edit area via `browser_click`
5. Upload image via `browser_file_upload` with **absolute path** to the banner PNG
6. Click save via `browser_click`
7. Navigate to `x.com/soleur_ai` and `browser_take_screenshot` with absolute path for verification

## Non-Goals

- Redesigning the avatar or logo
- Creating banners for other platforms (Discord, GitHub)
- Light mode variant
- Gemini AI background generation (zero quota on free tier -- per learning)
- Building a reusable banner generation pipeline

## Acceptance Criteria

- [ ] Pencil MCP WebSocket connection established (get_editor_state succeeds)
- [ ] Banner designed in .pen file using `batch_design` MCP tools
- [ ] `snapshot_layout(problemsOnly=true)` returns no layout errors
- [ ] Banner screenshot/export is exactly 1500x500px PNG
- [ ] Uses only brand colors (#0A0A0A bg, #C9A962 gold, #FFFFFF text)
- [ ] Typography uses Inter (wordmark) and Cormorant Garamond (thesis)
- [ ] Core content visible in center 60% (mobile safe zone ~900px)
- [ ] Avatar overlap area (bottom-left ~150x150px) has no critical content
- [ ] Banner uploaded and visible on @soleur_ai X profile
- [ ] .pen source file saved to `knowledge-base/design/brand/x-banner.pen`
- [ ] Final PNG saved to `plugins/soleur/docs/images/x-banner-1500x500.png`
- [ ] Brand guide X/Twitter banner section remains accurate
- [ ] No orphan screenshots in main repo root after Playwright operations

## Test Scenarios

- Given Pencil Desktop is running with `--no-sandbox`, when `get_editor_state` is called, then it returns a connected state with canvas information
- Given `get_editor_state` fails with WebSocket error, when `open_document("new")` is called first, then retry `get_editor_state` succeeds (document activation may establish WebSocket)
- Given the .pen document is open, when `batch_design` creates a frame with `fill:"#0A0A0A"`, then `batch_get` with the frame ID confirms `fill` equals `#0A0A0A`
- Given all text elements are added, when `batch_get` with `patterns:[{type:"text"}]` is called, then exactly 3 text nodes exist (wordmark, thesis, metrics)
- Given the banner is exported via `get_screenshot`, when the image is saved and measured, then dimensions are 1500x500px
- Given the banner on mobile X profile (center-cropped), when the center 900px is inspected, then wordmark and thesis remain visible
- Given the X avatar overlaps bottom-left (~150x150px), when the banner is displayed, then no text or key element is obscured
- Given the Playwright session is not authenticated on X, when `browser_snapshot` shows a login form, then the workflow pauses for manual login
- Given Playwright takes a screenshot, when the filename uses an absolute worktree path, then the file appears in the worktree (not main repo root)
- Given `batch_design` operations fail and roll back, when the same operations are retried with corrected parameters, then they succeed without leftover state

## Dependencies & Risks

| Risk | Mitigation | Severity |
|------|-----------|----------|
| WebSocket not connecting despite Desktop running | Phase 0 troubleshooting sequence: open_document first, then re-register with `--app pencil`, then restart Claude Code | **Blocker** |
| AppImage mount path changes on restart | Verify path with `pgrep -a pencil` before each session; re-register if path changed | High |
| Fonts not available in Pencil | Check with test text node + `get_screenshot`; install system-wide with `fc-cache -f` if missing | Medium |
| `batch_design` cannot create gradient fills | Use solid gold accent rectangles on left/right edges instead of CSS-style gradients; or use `G()` AI image operation for atmospheric background | Medium |
| `batch_design` rollback on error | Keep operations under 25 per call; split into logical batches; verify each batch with `batch_get` before next | Medium |
| .pen file not saved (no auto-save) | Prompt user to Ctrl+S after design phase; verify with `stat --format='%y'` timestamp check | Medium |
| Playwright screenshots in main repo | Use absolute worktree paths; clean up main repo after Playwright operations | Low |
| X auth session expired | Pause workflow for manual login; use `browser_snapshot` to detect login form | Low |
| get_screenshot returns wrong dimensions | Post-process with Pillow to verify/resize to exact 1500x500 | Low |

## Implementation Phases

### Phase 0: Pre-Flight Checks and WebSocket Resolution

**Goal:** Establish a working Pencil MCP connection.

1. Verify Pencil Desktop is running:

   ```bash
   pgrep -a pencil | grep -v grep
   ```

2. Call `mcp__pencil__get_editor_state(include_schema=false)`
3. **If WebSocket error:**
   a. Try `mcp__pencil__open_document(filePathOrTemplate="new")` -- opening a document may establish the WebSocket
   b. Retry `get_editor_state`
   c. If still failing, check `--app` flag. Current registration uses `--app desktop`. Try re-registering with `--app pencil`:

      ```bash
      claude mcp remove pencil
      claude mcp add pencil -- /tmp/.mount_PencilVuY4uO/resources/app.asar.unpacked/out/mcp-server-linux-x64 --app pencil
      ```

   d. After re-registration, inform user: "Claude Code must be restarted for MCP changes to take effect."
   e. **Fallback:** If WebSocket cannot be resolved, fall back to Pillow-only regeneration (same as original session) and file a GitHub issue for the Pencil Desktop MCP connection bug.
4. Verify fonts -- create a test text node:

   ```javascript
   // In batch_design
   testInter=I(document, {type:"text", content:"Inter Test", fontFamily:"Inter", fontWeight:"500", fontSize:20})
   testCormorant=I(document, {type:"text", content:"Cormorant Test", fontFamily:"Cormorant Garamond", fontWeight:"500", fontSize:20})
   ```

   Then `get_screenshot` to verify both render correctly. Delete test nodes after.
5. Verify or create .pen file:
   - Prefer creating a new dedicated `x-banner.pen` rather than modifying the existing `brand-visual-identity-brainstorm.pen`
   - Use `open_document("new")` if creating fresh, or `open_document` with absolute path to existing file

### Phase 1: Design in Pencil

**Goal:** Build the complete banner layout using batch_design operations.

**Batch 1: Frame and Background (5-8 ops)**

```javascript
// Create the banner frame
banner=I(document, {type:"frame", name:"X Banner", width:1500, height:500, fill:"#0A0A0A", placeholder:true, layout:"vertical"})

// Left gold accent (decorative edge)
leftAccent=I(banner, {type:"rectangle", name:"Left Accent", x:0, y:0, width:3, height:500, fill:"#D4B36A"})

// Right gold accent (decorative edge)
rightAccent=I(banner, {type:"rectangle", name:"Right Accent", x:1497, y:0, width:3, height:500, fill:"#B8923E"})

// Horizontal gold accent line at y=355
hLine=I(banner, {type:"rectangle", name:"Gold Line", x:450, y:355, width:600, height:1, fill:"#C9A962", opacity:0.4})
```

**Batch 2: Text Elements (6-8 ops)**

```javascript
// Wordmark: "S O L E U R"
wordmark=I("bannerId", {type:"text", name:"Wordmark", content:"S O L E U R", fontFamily:"Inter", fontWeight:"500", fontSize:52, textColor:"#C9A962", letterSpacing:4, textAlign:"center", x:0, y:140, width:1500})

// Thesis: "Build a Billion-Dollar Company. Alone."
thesis=I("bannerId", {type:"text", name:"Thesis", content:"Build a Billion-Dollar Company. Alone.", fontFamily:"Cormorant Garamond", fontWeight:"500", fontSize:82, textColor:"#FFFFFF", textAlign:"center", x:0, y:210, width:1500})

// Metrics: "60+ Agents . 8 Departments . 1 Founder"
metrics=I("bannerId", {type:"text", name:"Metrics", content:"60+ Agents \u00B7 8 Departments \u00B7 1 Founder", fontFamily:"Inter", fontWeight:"400", fontSize:26, textColor:"#848484", textAlign:"center", x:0, y:310, width:1500})
```

**Note:** Replace `"bannerId"` with the actual ID returned from Batch 1's `banner` insert. Use the binding from the same call, or read the ID from the `batch_design` response.

**Post-design verification:**

1. `batch_get` with `patterns:[{type:"text"}]` to confirm all 3 text nodes exist with correct properties
2. `get_screenshot` of the banner frame to visually verify layout
3. `snapshot_layout(problemsOnly=true)` to catch alignment or overflow issues
4. Iterate: adjust positions, sizes, or spacing based on screenshot review

**Design adjustments per brand guide:**

- Text sizing follows the 1% rule from learning `2026-03-10-x-banner-session-error-prevention.md`: thesis at 82px = 16.4% of 500px height (within 12-16% guideline), wordmark at 52px = 10.4% (within 8-12%), metrics at 26px = 5.2% (within 4-6%)
- Mobile safe zone: all text centered with `width:1500` and `textAlign:"center"` -- automatically within center 60%
- Avatar overlap: bottom-left ~150x150px is clear (text starts at y=140, centered)

**Prompt user to Ctrl+S** to save the .pen file to disk after all adjustments.

### Phase 2: Export and Upload

**Goal:** Capture the banner as a 1500x500 PNG and upload to X.

1. `get_screenshot` of the banner frame node (pass nodeId of the banner frame)
   - This returns image data in the MCP response
   - The screenshot resolution matches the frame dimensions (1500x500)

2. Save the screenshot image to disk:
   - If `get_screenshot` returns base64 image data, decode and save via Python/Pillow:

     ```python
     from PIL import Image
     import base64, io
     img_data = base64.b64decode(screenshot_base64)
     img = Image.open(io.BytesIO(img_data))
     assert img.size == (1500, 500), f"Expected 1500x500, got {img.size}"
     img.save("/home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-x-twitter-banner/plugins/soleur/docs/images/x-banner-1500x500.png")
     ```

   - If screenshot dimensions differ, resize with `Image.LANCZOS` resampling

3. Verify the saved PNG:

   ```bash
   python3 -c "from PIL import Image; img=Image.open('plugins/soleur/docs/images/x-banner-1500x500.png'); print(f'Size: {img.size}, Mode: {img.mode}')"
   ```

4. **Playwright upload to X** (all paths absolute):
   - `browser_navigate` to `https://x.com/settings/profile`
   - `browser_snapshot` to check auth state
   - If login required: announce "Manual login needed on X. Please log in, then confirm."
   - After auth confirmed:
     - `browser_click` on banner edit area
     - `browser_file_upload` with path `/home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-x-twitter-banner/plugins/soleur/docs/images/x-banner-1500x500.png`
     - `browser_click` to save/apply
     - `browser_navigate` to `https://x.com/soleur_ai`
     - `browser_take_screenshot` with filename `/home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-x-twitter-banner/tmp/x-profile-verified.png`

5. **Cleanup:** Check for orphan screenshots in main repo:

   ```bash
   ls /home/jean/git-repositories/jikig-ai/soleur/*.png 2>/dev/null
   ```

### Phase 3: Finalize

1. Verify brand guide `knowledge-base/overview/brand-guide.md` X/Twitter banner section (lines 167-181) is still accurate
   - If the `Generated with` field changes from "Pillow" to "Pencil Desktop MCP", update it
   - If font sizes or positions changed during iteration, update the spec table

2. Save .pen file:
   - Prompt user to Ctrl+S if not already done
   - Verify disk write: `stat --format='%y' knowledge-base/design/brand/x-banner.pen`
   - If new file, verify with `git status`

3. Run `soleur:compound` to capture Pencil MCP design learnings (specifically the WebSocket connection resolution)

4. Commit artifacts:
   - `knowledge-base/design/brand/x-banner.pen` (new or modified .pen file)
   - `plugins/soleur/docs/images/x-banner-1500x500.png` (regenerated banner)
   - Any brand-guide.md updates

5. Push to remote

## Semver Intent

`semver:patch` -- asset regeneration, no functional changes to plugin code.

## References

### Internal

- Brand guide: `knowledge-base/overview/brand-guide.md` (line 167-181 for X/Twitter banner specs)
- Existing banner: `plugins/soleur/docs/images/x-banner-1500x500.png`
- Existing .pen file: `knowledge-base/design/brand/brand-visual-identity-brainstorm.pen`
- Pencil setup skill: `plugins/soleur/skills/pencil-setup/SKILL.md`
- UX design lead agent: `plugins/soleur/agents/product/design/ux-design-lead.md`
- Pencil MCP operational requirements: `knowledge-base/project/learnings/2026-02-27-pencil-editor-operational-requirements.md`
- Pencil Desktop three-tier detection: `knowledge-base/project/learnings/2026-03-10-pencil-desktop-standalone-mcp-three-tier-detection.md`
- Electron headless crash: `knowledge-base/project/learnings/2026-03-10-electron-appimage-crashes-in-headless-terminal.md`
- X banner session errors: `knowledge-base/project/learnings/2026-03-10-x-banner-session-error-prevention.md`
- X provisioning automation: `knowledge-base/project/learnings/2026-03-09-x-provisioning-playwright-automation.md`
- Playwright screenshot path trap: `knowledge-base/project/learnings/2026-02-17-playwright-screenshots-land-in-main-repo.md`
- Pencil MCP binary constraint: `knowledge-base/project/learnings/2026-02-14-pencil-mcp-local-binary-constraint.md`
- Pencil MCP auto-registration: `knowledge-base/project/learnings/2026-02-27-pencil-mcp-auto-registration-via-skill.md`
- Original spec: `knowledge-base/project/specs/feat-x-banner/spec.md`
- Original tasks: `knowledge-base/project/specs/feat-x-banner/tasks.md`

### Related

- Issue: #483
- Original PR: #489
- Pencil Desktop MCP PR: #493 / #499
- Related: #480 (X links on website), #481 (surface parity)
