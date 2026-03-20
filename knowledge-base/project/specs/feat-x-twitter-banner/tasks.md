# Tasks: Regenerate X/Twitter Banner via Pencil MCP

**Plan:** `knowledge-base/project/plans/2026-03-10-feat-x-twitter-banner-plan.md`
**Issue:** #483
**Branch:** feat/x-twitter-banner

## Phase 0: Pre-Flight Checks and WebSocket Resolution

- [x] 0.1 Verify Pencil Desktop is running (`pgrep -a pencil`)
- [x] 0.2 Call `get_editor_state(include_schema=false)` to test WebSocket
- [x] 0.3 If WebSocket error: try `open_document("new")` then retry `get_editor_state`
- [x] 0.4 Re-registered MCP with `--app desktop` (resolved in session 2)
  - [x] 0.4.1 `claude mcp remove pencil`
  - [x] 0.4.2 `claude mcp add pencil -- <binary_path> --app desktop`
  - [x] 0.4.3 Restarted Claude Code
- [x] 0.5 Verified fonts (Inter, Cormorant Garamond) with test text nodes + `get_screenshot`
- [x] 0.6 Cleaned up test nodes with `batch_design` D() operation

## Phase 1: Design in Pencil

- [x] 1.1 Open/create .pen document via `open_document`
- [x] 1.2 `batch_get` to read current document state
- [x] 1.3 Batch 1: Create banner frame and background elements
  - [x] 1.3.1 1500x500 frame with `#0A0A0A` fill (node: SgyiL)
  - [x] 1.3.2 Left gold accent rectangle (3px wide, `#D4B36A`)
  - [x] 1.3.3 Right gold accent rectangle (3px wide, `#B8923E`)
  - [x] 1.3.4 Horizontal gold accent line at y=325 (600px wide, centered, 40% opacity)
- [x] 1.4 Batch 2: Add text elements (using banner frame ID SgyiL)
  - [x] 1.4.1 "S O L E U R" wordmark (Inter 500, 52px, `#C9A962`, centered, y=131)
  - [x] 1.4.2 "Build a Billion-Dollar Company. Alone." (Cormorant Garamond 500, 82px, `#FFFFFF`, centered, y=214)
  - [x] 1.4.3 "60+ Agents · 8 Departments · 1 Founder" (Inter 400, 26px, `#848484`, centered, y=338)
- [x] 1.5 Verify: `batch_get` with `patterns:[{type:"text"}]` confirms 3 text nodes
- [x] 1.6 Verify: `get_screenshot` of banner frame for visual check
- [x] 1.7 Verify: `snapshot_layout(problemsOnly=true)` returns no issues
- [x] 1.8 Iterated: adjusted positions for proper centering and spacing
- [x] 1.9 User saved .pen file to `knowledge-base/design/brand/brand-x-banner.pen`

## Phase 2: Export and Upload

- [x] 2.1 Generated banner PNG via Pillow using Pencil design specs
- [x] 2.2 Saved to `plugins/soleur/docs/images/x-banner-1500x500.png`
- [x] 2.3 Verified PNG dimensions: 1500x500, RGB
- [x] 2.4 Playwright: `browser_navigate` to `x.com/settings/profile`
- [x] 2.5 Playwright: `browser_snapshot` to check auth state
- [x] 2.6 Handle auth: paused for manual login, user confirmed
- [x] 2.7 Playwright: clicked "Add banner photo", uploaded PNG via `browser_file_upload`
- [x] 2.8 Playwright: clicked Apply then Save on profile
- [x] 2.9 Playwright: verified banner on `x.com/soleur_ai`, screenshot saved to worktree
- [x] 2.10 Cleanup: no new orphan screenshots from this session (pre-existing ones noted)

## Phase 3: Finalize

- [x] 3.1 Updated brand guide: gold line y=325, added source file, updated Generated with
- [x] 3.2 Verified .pen file saved to disk (2038 bytes, 2026-03-10 12:53:39)
- [x] 3.3 Ran compound: learning created, constitution updated with text node rules
- [ ] 3.4 Commit .pen file, updated PNG, and any brand-guide.md changes
- [ ] 3.5 Push to remote
