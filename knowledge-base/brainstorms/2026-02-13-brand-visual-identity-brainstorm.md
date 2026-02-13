# Brainstorm: Soleur Brand & Visual Identity

**Date:** 2026-02-13
**Status:** Active — seeking external feedback
**Branch:** `feat-brand-identity`

---

## What We're Building

A foundational visual identity for Soleur — the Company-as-a-Service platform for solo founders. This covers logo direction, color palette, typography, and overall brand aesthetic. The goal is to establish brand DNA now while the project is small, so every future asset (docs site, social presence, community templates) is consistent from day one.

## Context

- **Positioning:** Ambitious platform — Company-as-a-Service. The Claude Code plugin is Phase 1 of a bigger vision.
- **Brand energy:** Tesla / SpaceX — audacious, mission-driven, future-focused. The brand IS the ambition.
- **Name meaning:** Solo + Solar — entrepreneur energy and light to better the world. A portmanteau combining the solo founder with the power of the sun.
- **Brand voice:** Ambitious-inspiring (like Vercel's marketing). Bold, forward-looking, energizing.
- **Current state:** Zero visual assets exist. Strong informal positioning language in READMEs but nothing formalized.

## Visual Concepts

Four directions were explored as hero section mockups. Each interprets "solar energy powering the solo founder" differently.

### Concept 1: Solar Forge (Leading Direction)

**Metaphor:** A forge — raw power being shaped by one person's judgment. Energy against darkness.

- **Palette:** Deep black (#0A0A0A) + warm gold (#C9A962) accent + white text
- **Typography:** Cormorant Garamond (serif) for headlines, Inter for UI, JetBrains Mono for data
- **Logo:** Bordered square "S" mark in gold on black, spaced-out "SOLEUR" wordmark
- **Corners:** Sharp (0px radius) — architectural precision
- **CTA:** Gold gradient buttons (#D4B36A → #B8923E)
- **Headline:** "Infinite Leverage. One Founder."
- **Feel:** Premium, powerful, concentrated. The darkness isn't brooding — it's the backdrop that makes the light hit harder.

**Pros:**
- Most aligned with Tesla/SpaceX audacity
- Gold-on-dark is instantly premium
- Serif headlines (Cormorant Garamond) distinguish it from every dev tool
- Scales well from favicon to billboard
- The forge metaphor connects directly to "solo founder building something massive"

**Cons:**
- Dark-first can feel heavy if overdone
- Needs careful balance to avoid "crypto bro" territory
- Serif font may feel unexpected for a developer tool

### Concept 2: First Light

**Metaphor:** Sunrise — the moment before everything changes.

- **Palette:** Warm off-white (#FFFBF5) + amber-to-orange gradient (#F59E0B → #EA580C) + dark text
- **Typography:** Inter (all type), weight contrast (800 vs 400)
- **Logo:** Gradient circle with "S", "Soleur" wordmark
- **Corners:** Rounded (8-10px)
- **Headline:** "Build Your Empire. Stay Solo."
- **Feel:** Clean, approachable, energetic. Forward-looking.

**Pros:**
- More approachable for a broad audience
- Warm gradient provides energy
- Clean, modern, professional

**Cons:**
- Risks looking like a generic SaaS startup (every Y Combinator company looks like this)
- Harder to feel "audacious" in a light palette
- Less distinctive

### Concept 3: Stellar

**Metaphor:** A star — one source of light in a vast universe.

- **Palette:** Deep blue-black (#0C0C14) + violet/indigo gradient (#7C3AED → #4F46E5) + light accents (#A78BFA)
- **Typography:** Sora (bold headlines), Inter (body)
- **Logo:** Radial gradient circle, "SOLEUR" in tracked-out Sora
- **Corners:** Moderate (6-8px)
- **CTA:** Purple gradient with glow effect
- **Headline:** "One Mind. Unlimited Scale."
- **Feel:** Cosmic, vast, futuristic. Tech-platform energy.

**Pros:**
- Most visually distinctive of the dark options
- Cosmic scale matches the "$1B outcome" positioning
- Glow effects add depth and modernity

**Cons:**
- Can feel cold or distant without warm elements
- Purple is heavily used in AI/tech space (Anthropic, Vercel AI, etc.)
- Harder to pull off without looking generic "tech"

### Concept 4: Solar Radiance

**Metaphor:** The sun itself — pure radiant energy from a single source.

- **Palette:** Warm cream (#FFFAF0) + amber/gold (#F59E0B, #D97706, #FCD34D) + dark text (#1C1917)
- **Typography:** DM Sans (all type) — warm, geometric, humanist
- **Logo:** Glowing sun mark (radial gradient with white core, amber glow) + "Soleur" wordmark
- **Corners:** Fully rounded (pill buttons, 28px CTAs)
- **CTA:** Amber gradient with glow shadow
- **Headline:** "One Source of Light. Endless Reach."
- **Feel:** Radiant, warm, confident. The sun as central identity.

**Pros:**
- Strongest connection to the name's solar meaning
- The sun mark is immediately recognizable and distinctive
- Warm palette stands out in a sea of dark-mode dev tools
- DM Sans is modern without being cold

**Cons:**
- Light palette carries less "weight" than dark alternatives
- Sun symbolism could feel generic if not executed precisely
- Pill buttons and rounded corners may feel less "serious"

## Key Decisions Made

1. **Positioning:** Lead with the ambitious platform vision, not the plugin description
2. **Brand energy:** Tesla/SpaceX — audacious, mission-driven, future-focused
3. **Name identity:** Solar + Solo — intentional dual meaning
4. **Leading direction:** Solar Forge (Concept 1) with Solar Radiance (Concept 4) as the light counterpart
5. **Gold gradient CTAs:** Added to Solar Forge for warmth without losing restraint

## Open Questions (For External Feedback)

1. **Solar Forge vs Solar Radiance?** Dark + gold premium or bright + sun radiance? Or both (dark for main brand, light for docs)?
2. **Serif headlines (Cormorant Garamond)?** Does the serif feel right for a developer-facing platform, or should we stick with a bold sans-serif?
3. **Logo mark direction?** Bordered square "S" (Solar Forge) vs glowing sun circle (Solar Radiance)?
4. **Should both light and dark variants coexist?** E.g., dark for landing page/marketing, light for documentation?
5. **What's the right level of "ambition" in the visual?** Does the gold feel premium or pretentious? Does the sun feel distinctive or generic?

## Next Steps

- [ ] Gather external feedback on the 4 concepts
- [ ] Finalize primary direction
- [ ] Run the `brand-architect` agent to produce the formal brand guide at `knowledge-base/overview/brand-guide.md`
- [ ] Design the documentation site using the chosen identity
- [ ] Create logo variations (favicon, social preview, etc.)
