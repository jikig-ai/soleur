---
feature: feat-vision-road-ahead
issue: "#274"
date: 2026-02-22
---

# Tasks: Rework Vision Road Ahead

## Phase 1: Implementation

- [ ] 1.1 Edit `plugins/soleur/docs/pages/vision.njk` -- replace "The Road Ahead" section (lines 119-148) with "Master Plan" section containing 3 milestone cards
- [ ] 1.2 Verify Eleventy build passes with no errors

## Phase 2: Verification

- [ ] 2.1 Take desktop screenshot of vision page Master Plan section
- [ ] 2.2 Take mobile screenshot (resize to 375px width) to verify responsive layout
- [ ] 2.3 Visual review of both screenshots for alignment and readability

## Phase 3: Ship

- [ ] 3.1 Version bump (PATCH) -- update plugin.json, CHANGELOG.md, README.md
- [ ] 3.2 Commit, push, and create PR referencing #274
