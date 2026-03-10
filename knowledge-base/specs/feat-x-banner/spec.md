# Spec: X/Twitter Banner Image for @soleur_ai

**Issue:** #483
**Branch:** feat-x-banner
**Status:** Complete

## Problem Statement

The @soleur_ai X account lacks a banner/header image, leaving the profile incomplete. The banner is key visual real estate for communicating Soleur's identity to visitors.

## Goals

- G1: Create a 1500x500px banner image consistent with Soleur brand guide
- G2: Upload banner to @soleur_ai X profile
- G3: Document banner specs in brand guide for future reference

## Non-Goals

- NG1: Redesigning the avatar or logo
- NG2: Creating banners for other platforms (Discord, GitHub)
- NG3: Light mode variant

## Functional Requirements

- FR1: Banner displays "S O L E U R" wordmark (Inter 500, letterSpacing 4)
- FR2: Banner displays thesis "Build a Billion-Dollar Company. Alone." (Cormorant Garamond)
- FR3: Banner optionally displays metrics "60+ Agents · 8 Departments · 1 Founder" if space allows
- FR4: Content is center-weighted within the mobile safe zone (~900x500px center)
- FR5: Gold accent elements at edges are decorative and safe to crop
- FR6: Banner is uploaded to @soleur_ai via Playwright MCP

## Technical Requirements

- TR1: Dimensions exactly 1500x500px
- TR2: Uses brand palette only (#0A0A0A background, #C9A962 gold accent, #D4B36A-#B8923E gradient)
- TR3: Sharp corners (0px border-radius) per brand guide
- TR4: Design created in Pencil (.pen file), rendered via Gemini image generation
- TR5: Final image saved to `plugins/soleur/docs/images/` for version control
- TR6: Brand guide updated with banner specifications under X/Twitter section

## Acceptance Criteria

- [x] Banner image is 1500x500px
- [x] Banner uses only brand colors and typography
- [x] Core content visible in center 60% (mobile safe zone)
- [x] Banner uploaded to @soleur_ai profile
- [x] Brand guide updated with banner specs
- [x] Avatar does not obscure key content (bottom-left safe area respected)
