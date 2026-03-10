# Tasks: Regenerate X/Twitter Banner via Pencil MCP

**Plan:** `knowledge-base/plans/2026-03-10-feat-x-twitter-banner-plan.md`
**Issue:** #483
**Branch:** feat/x-twitter-banner

## Phase 0: Pre-Flight Checks and WebSocket Resolution

- [ ] 0.1 Verify Pencil Desktop is running (`pgrep -a pencil`)
- [ ] 0.2 Call `get_editor_state(include_schema=false)` to test WebSocket
- [ ] 0.3 If WebSocket error: try `open_document("new")` then retry `get_editor_state`
- [ ] 0.4 If still failing: re-register MCP with `--app pencil` (current uses `--app desktop`)
  - [ ] 0.4.1 `claude mcp remove pencil`
  - [ ] 0.4.2 `claude mcp add pencil -- <binary_path> --app pencil`
  - [ ] 0.4.3 Inform user to restart Claude Code
- [ ] 0.5 If WebSocket resolved: verify fonts (Inter, Cormorant Garamond) with test text nodes + `get_screenshot`
- [ ] 0.6 Clean up test nodes with `batch_design` D() operation

## Phase 1: Design in Pencil

- [ ] 1.1 Open/create .pen document via `open_document`
- [ ] 1.2 `batch_get` to read current document state
- [ ] 1.3 Batch 1: Create banner frame and background elements
  - [ ] 1.3.1 1500x500 frame with `#0A0A0A` fill
  - [ ] 1.3.2 Left gold accent rectangle (3px wide, `#D4B36A`)
  - [ ] 1.3.3 Right gold accent rectangle (3px wide, `#B8923E`)
  - [ ] 1.3.4 Horizontal gold accent line at y=355 (600px wide, centered, 40% opacity)
- [ ] 1.4 Batch 2: Add text elements (using banner frame ID from 1.3)
  - [ ] 1.4.1 "S O L E U R" wordmark (Inter 500, 52px, `#C9A962`, centered, y=140)
  - [ ] 1.4.2 "Build a Billion-Dollar Company. Alone." (Cormorant Garamond 500, 82px, `#FFFFFF`, centered, y=210)
  - [ ] 1.4.3 "60+ Agents . 8 Departments . 1 Founder" (Inter 400, 26px, `#848484`, centered, y=310)
- [ ] 1.5 Verify: `batch_get` with `patterns:[{type:"text"}]` confirms 3 text nodes
- [ ] 1.6 Verify: `get_screenshot` of banner frame for visual check
- [ ] 1.7 Verify: `snapshot_layout(problemsOnly=true)` returns no issues
- [ ] 1.8 Iterate: adjust positions, sizes, spacing based on screenshot review
- [ ] 1.9 Prompt user to Ctrl+S to save .pen file

## Phase 2: Export and Upload

- [ ] 2.1 `get_screenshot` of banner frame node (returns image data)
- [ ] 2.2 Save screenshot to PNG via Pillow (decode, verify 1500x500, save to absolute path)
- [ ] 2.3 Verify PNG dimensions: `python3 -c "from PIL import Image; print(Image.open(...).size)"`
- [ ] 2.4 Playwright: `browser_navigate` to `x.com/settings/profile`
- [ ] 2.5 Playwright: `browser_snapshot` to check auth state
- [ ] 2.6 Handle auth: pause for manual login if needed
- [ ] 2.7 Playwright: click banner edit, `browser_file_upload` with absolute PNG path
- [ ] 2.8 Playwright: save profile changes
- [ ] 2.9 Playwright: navigate to `x.com/soleur_ai`, `browser_take_screenshot` with absolute worktree path
- [ ] 2.10 Cleanup: check for orphan screenshots in main repo root

## Phase 3: Finalize

- [ ] 3.1 Verify brand guide X/Twitter banner section is accurate (update `Generated with` if changed)
- [ ] 3.2 Verify .pen file saved to disk (`stat --format='%y'` check)
- [ ] 3.3 Run `soleur:compound` to capture Pencil MCP design learnings
- [ ] 3.4 Commit .pen file, updated PNG, and any brand-guide.md changes
- [ ] 3.5 Push to remote
