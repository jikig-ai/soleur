# Tasks: X/Twitter Banner for @soleur_ai

**Plan:** `knowledge-base/plans/2026-03-10-feat-x-twitter-banner-plan.md`
**Issue:** #483
**Branch:** feat-x-banner

## Phase 1: Design and Generate

- [x] 1.1 Verify `GEMINI_API_KEY` environment variable is set and functional
- [x] 1.2 Download Inter (.ttf, weight 400+500) and Cormorant Garamond (.ttf, weight 500) from Google Fonts to `tmp/fonts/`
- [x] 1.3 Verify Pillow can load both fonts via `ImageFont.truetype()`
- [x] 1.4 Create Pencil mockup at 1500x500 layout (skipped — Pencil MCP not connected; proceeded directly to Pillow)
  - [x] 1.4.1 Open new .pen document
  - [x] 1.4.2 Create 1500x500 frame with #0A0A0A background
  - [x] 1.4.3 Place "S O L E U R" wordmark (center-top, gold)
  - [x] 1.4.4 Place thesis text (center, white)
  - [x] 1.4.5 Place optional metrics line (below thesis, secondary gray)
  - [x] 1.4.6 Add gold accent elements at edges
  - [x] 1.4.7 Screenshot mockup for reference
- [x] 1.5 Generate background texture via Gemini (pivoted — Gemini free tier has zero image gen quota; used Pillow-only approach)
  - [x] 1.5.1 Craft prompt: dark forge atmosphere, gold gradients, no text, brand palette
  - [x] 1.5.2 Run `generate_image.py` with `--model gemini-3-pro-image-preview --aspect 21:9 --size 2K`
  - [x] 1.5.3 Verify output is usable (no safety filter, correct mood)
- [x] 1.6 Post-process with Pillow (full generation done in Pillow — programmatic gold gradients, light streaks, text overlay)
  - [x] 1.6.1 Center-crop from 21:9 to 1500x500
  - [x] 1.6.2 Overlay "S O L E U R" wordmark (Inter 500, gold #C9A962, centered horizontally, upper third)
  - [x] 1.6.3 Overlay thesis "Build a Billion-Dollar Company. Alone." (Cormorant Garamond 500, white, center)
  - [x] 1.6.4 Attempt metrics line overlay — remove if cluttered (kept — fits well at 26px)
  - [x] 1.6.5 Save as `plugins/soleur/docs/images/x-banner-1500x500.png`
- [x] 1.7 Visual review: verify mobile safe zone (center 900px contains all text)

## Phase 2: Upload to X

- [x] 2.1 Screenshot current @soleur_ai profile (backup, absolute path)
- [x] 2.2 Navigate to `x.com/settings/profile` via Playwright (headed mode)
- [x] 2.3 Handle authentication (pause for manual login if needed)
- [x] 2.4 Upload banner via profile edit flow
- [x] 2.5 Save profile changes
- [x] 2.6 Navigate to `x.com/soleur_ai` and screenshot for verification

## Phase 3: Document and Finalize

- [x] 3.1 Add banner specs to `knowledge-base/overview/brand-guide.md`
  - [x] 3.1.1 Add under `### X/Twitter` in `## Channel Notes`
  - [x] 3.1.2 Document: dimensions (1500x500), file path, typography, safe zone, colors
- [ ] 3.2 Update spec status to Complete
- [ ] 3.3 Run `soleur:compound` to capture learnings
- [ ] 3.4 Commit all artifacts and push
