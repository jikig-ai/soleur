# Tasks: X/Twitter Banner for @soleur_ai

**Plan:** `knowledge-base/plans/2026-03-10-feat-x-twitter-banner-plan.md`
**Issue:** #483
**Branch:** feat-x-banner

## Phase 1: Design and Generate

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
- [ ] 1.5 Generate background texture via Gemini
  - [ ] 1.5.1 Craft prompt: dark forge atmosphere, gold gradients, no text, brand palette
  - [ ] 1.5.2 Run `generate_image.py` with `--model gemini-3-pro-image-preview --aspect 21:9 --size 2K`
  - [ ] 1.5.3 Verify output is usable (no safety filter, correct mood)
- [ ] 1.6 Post-process with Pillow
  - [ ] 1.6.1 Center-crop from 21:9 to 1500x500
  - [ ] 1.6.2 Overlay "S O L E U R" wordmark (Inter 500, gold #C9A962, centered horizontally, upper third)
  - [ ] 1.6.3 Overlay thesis "Build a Billion-Dollar Company. Alone." (Cormorant Garamond 500, white, center)
  - [ ] 1.6.4 Attempt metrics line overlay — remove if cluttered
  - [ ] 1.6.5 Save as `plugins/soleur/docs/images/x-banner-1500x500.png`
- [ ] 1.7 Visual review: verify mobile safe zone (center 900px contains all text)

## Phase 2: Upload to X

- [ ] 2.1 Screenshot current @soleur_ai profile (backup, absolute path)
- [ ] 2.2 Navigate to `x.com/settings/profile` via Playwright (headed mode)
- [ ] 2.3 Handle authentication (pause for manual login if needed)
- [ ] 2.4 Upload banner via profile edit flow
- [ ] 2.5 Save profile changes
- [ ] 2.6 Navigate to `x.com/soleur_ai` and screenshot for verification

## Phase 3: Document and Finalize

- [ ] 3.1 Add banner specs to `knowledge-base/overview/brand-guide.md`
  - [ ] 3.1.1 Add under `### X/Twitter` in `## Channel Notes`
  - [ ] 3.1.2 Document: dimensions (1500x500), file path, typography, safe zone, colors
- [ ] 3.2 Update spec status to Complete
- [ ] 3.3 Run `soleur:compound` to capture learnings
- [ ] 3.4 Commit all artifacts and push
