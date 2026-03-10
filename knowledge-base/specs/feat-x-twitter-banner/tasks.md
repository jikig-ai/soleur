# Tasks: Regenerate X/Twitter Banner via Pencil MCP

**Plan:** `knowledge-base/plans/2026-03-10-feat-x-twitter-banner-plan.md`
**Issue:** #483
**Branch:** feat/x-twitter-banner

## Phase 0: Pre-Flight Checks

- [ ] 0.1 Verify Pencil MCP connection via `mcp__pencil__get_editor_state`
- [ ] 0.2 Verify Inter and Cormorant Garamond fonts available in Pencil
- [ ] 0.3 Check existing .pen file (`knowledge-base/design/brand/brand-visual-identity-brainstorm.pen`) or create new `x-banner.pen`

## Phase 1: Design in Pencil

- [ ] 1.1 Open .pen document via `mcp__pencil__open_document`
- [ ] 1.2 `batch_get` existing elements to understand current canvas state
- [ ] 1.3 Create 1500x500 frame with `#0A0A0A` background
- [ ] 1.4 Add "S O L E U R" wordmark
  - [ ] 1.4.1 Font: Inter, weight 500, size 52px, gold `#C9A962`
  - [ ] 1.4.2 Position: centered horizontally, upper third (~y=140)
  - [ ] 1.4.3 Letter spacing: 4
- [ ] 1.5 Add thesis text "Build a Billion-Dollar Company. Alone."
  - [ ] 1.5.1 Font: Cormorant Garamond, weight 500, size 82px, white `#FFFFFF`
  - [ ] 1.5.2 Position: centered horizontally and vertically (~y=220)
- [ ] 1.6 Add metrics "60+ Agents . 8 Departments . 1 Founder"
  - [ ] 1.6.1 Font: Inter, weight 400, size 26px, secondary `#848484`
  - [ ] 1.6.2 Position: centered horizontally, below thesis (~y=310)
- [ ] 1.7 Add gold gradient edge accents (left `#D4B36A`, right `#B8923E`)
- [ ] 1.8 Add 1px horizontal gold accent line at ~y=355
- [ ] 1.9 `get_screenshot` to verify visual layout
- [ ] 1.10 Iterate with `batch_design` adjustments as needed
- [ ] 1.11 Prompt user to Ctrl+S to save .pen file to disk

## Phase 2: Export and Upload

- [ ] 2.1 Export/screenshot canvas at 1500x500 resolution
- [ ] 2.2 Save PNG to `plugins/soleur/docs/images/x-banner-1500x500.png`
- [ ] 2.3 Verify dimensions (1500x500px) and file integrity
- [ ] 2.4 Screenshot current @soleur_ai profile (backup)
- [ ] 2.5 Navigate to `x.com/settings/profile` via Playwright MCP (headed mode)
- [ ] 2.6 Handle authentication (pause for manual login if needed)
- [ ] 2.7 Upload banner image via profile edit flow
- [ ] 2.8 Save profile changes
- [ ] 2.9 Navigate to `x.com/soleur_ai` and screenshot for verification

## Phase 3: Finalize

- [ ] 3.1 Verify brand guide X/Twitter banner section is still accurate
- [ ] 3.2 Run `soleur:compound` to capture Pencil MCP design learnings
- [ ] 3.3 Commit .pen file and updated PNG
- [ ] 3.4 Push to remote
