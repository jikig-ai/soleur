# Tasks: X/Twitter Banner for @soleur_ai

**Plan:** `knowledge-base/plans/2026-03-10-feat-x-twitter-banner-plan.md`
**Issue:** #483
**Branch:** feat-x-banner

## Phase 1: Prerequisites and Design

- [ ] 1.1 Verify `GEMINI_API_KEY` environment variable is set and functional
- [ ] 1.2 Download Inter (.ttf, weight 400+500) and Cormorant Garamond (.ttf, weight 500) from Google Fonts to `tmp/fonts/`
- [ ] 1.3 Verify Pillow can load both fonts via `ImageFont.truetype()`
- [ ] 1.4 Create Pencil mockup at 1500x500 layout
  - [ ] 1.4.1 Open new .pen document
  - [ ] 1.4.2 Create 1500x500 frame with #0A0A0A background
  - [ ] 1.4.3 Place "S O L E U R" wordmark (center-top, gold)
  - [ ] 1.4.4 Place thesis text (center, white)
  - [ ] 1.4.5 Place optional metrics line (below thesis, secondary gray)
  - [ ] 1.4.6 Add gold accent elements at edges
  - [ ] 1.4.7 Screenshot mockup for reference

## Phase 2: Image Generation

- [ ] 2.1 Generate background texture via Gemini
  - [ ] 2.1.1 Craft prompt: dark forge atmosphere, gold gradients, no text, brand palette
  - [ ] 2.1.2 Run `generate_image.py` with `--model gemini-3-pro-image-preview --aspect 21:9 --size 2K`
  - [ ] 2.1.3 Verify output is usable (no safety filter, correct mood)
- [ ] 2.2 Post-process with Pillow
  - [ ] 2.2.1 Center-crop from 21:9 to 1500x500
  - [ ] 2.2.2 Overlay "S O L E U R" wordmark (Inter 500, gold #C9A962, centered horizontally, upper third)
  - [ ] 2.2.3 Overlay thesis "Build a Billion-Dollar Company. Alone." (Cormorant Garamond 500, white, center)
  - [ ] 2.2.4 Attempt metrics line overlay — evaluate if it fits without clutter
  - [ ] 2.2.5 Save as `plugins/soleur/docs/images/x-banner-1500x500.png`
- [ ] 2.3 Generate version without metrics for comparison
- [ ] 2.4 Visual review: verify mobile safe zone (center 900px contains all text)

## Phase 3: Upload to X

- [ ] 3.1 Screenshot current @soleur_ai profile (backup, absolute path)
- [ ] 3.2 Navigate to `x.com/settings/profile` via Playwright (headed mode)
- [ ] 3.3 Handle authentication (pause for manual login if needed)
- [ ] 3.4 Upload banner via profile edit flow
- [ ] 3.5 Save profile changes
- [ ] 3.6 Navigate to `x.com/soleur_ai` and screenshot for verification

## Phase 4: Documentation

- [ ] 4.1 Add banner specs to `knowledge-base/overview/brand-guide.md`
  - [ ] 4.1.1 Add under `### X/Twitter` in `## Channel Notes`
  - [ ] 4.1.2 Document: dimensions (1500x500), file path, typography, safe zone, colors
- [ ] 4.2 Update spec status to Complete

## Phase 5: Finalize

- [ ] 5.1 Run `soleur:compound` to capture learnings
- [ ] 5.2 Commit all artifacts
- [ ] 5.3 Push to remote
