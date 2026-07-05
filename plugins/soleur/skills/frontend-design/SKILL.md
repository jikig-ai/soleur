---
name: frontend-design
description: "This skill should be used when creating distinctive, production-grade frontend interfaces. It generates creative, polished web components, pages, or applications that avoid generic AI aesthetics with high design quality."
context_queries:
  - knowledge-base/marketing/brand-guide.md
  - knowledge-base/product/design/taste-profile.md
license: Complete terms in LICENSE.txt
---

This skill guides creation of distinctive, production-grade frontend interfaces that avoid generic "AI slop" aesthetics. Implement real working code with exceptional attention to aesthetic details and creative choices.

The user provides frontend requirements: a component, page, application, or interface to build. They may include context about the purpose, audience, or technical constraints.

## Design Thinking

Before coding, understand the context and commit to a BOLD aesthetic direction:
- **Purpose**: What problem does this interface solve? Who uses it?
- **Tone**: Pick an extreme: brutally minimal, maximalist chaos, retro-futuristic, organic/natural, luxury/refined, playful/toy-like, editorial/magazine, brutalist/raw, art deco/geometric, soft/pastel, industrial/utilitarian, etc. There are so many flavors to choose from. Use these for inspiration but design one that is true to the aesthetic direction.
- **Constraints**: Technical requirements (framework, performance, accessibility).
- **Differentiation**: What makes this UNFORGETTABLE? What's the one thing someone will remember?

**CRITICAL**: Choose a clear conceptual direction and execute it with precision. Bold maximalism and refined minimalism both work - the key is intentionality, not intensity.

Then implement working code (HTML/CSS/JS, React, Vue, etc.) that is:
- Production-grade and functional
- Visually striking and memorable
- Cohesive with a clear aesthetic point-of-view
- Meticulously refined in every detail

## Frontend Aesthetics Guidelines

Focus on:
- **Typography**: Choose fonts that are beautiful, unique, and interesting. Avoid generic fonts like Arial and Inter; opt instead for distinctive choices that elevate the frontend's aesthetics; unexpected, characterful font choices. Pair a distinctive display font with a refined body font.
- **Color & Theme**: Commit to a cohesive aesthetic. Use CSS variables for consistency. Dominant colors with sharp accents outperform timid, evenly-distributed palettes.
- **Motion**: Use animations for effects and micro-interactions. Prioritize CSS-only solutions for HTML. Use Motion library for React when available. Focus on high-impact moments: one well-orchestrated page load with staggered reveals (animation-delay) creates more delight than scattered micro-interactions. Use scroll-triggering and hover states that surprise.
- **Spatial Composition**: Unexpected layouts. Asymmetry. Overlap. Diagonal flow. Grid-breaking elements. Generous negative space OR controlled density.
- **Backgrounds & Visual Details**: Create atmosphere and depth rather than defaulting to solid colors. Add contextual effects and textures that match the overall aesthetic. Apply creative forms like gradient meshes, noise textures, geometric patterns, layered transparencies, dramatic shadows, decorative borders, custom cursors, and grain overlays.

NEVER use generic AI-generated aesthetics like overused font families (Inter, Roboto, Arial, system fonts), cliched color schemes (particularly purple gradients on white backgrounds), predictable layouts and component patterns, and cookie-cutter design that lacks context-specific character.

Interpret creatively and make unexpected choices that feel genuinely designed for the context. No design should be the same. Vary between light and dark themes, different fonts, different aesthetics. NEVER converge on common choices (Space Grotesk, for example) across generations.

**IMPORTANT**: Match implementation complexity to the aesthetic vision. Maximalist designs need elaborate code with extensive animations and effects. Minimalist or refined designs need restraint, precision, and careful attention to spacing, typography, and subtle details. Elegance comes from executing the vision well.

Remember: Claude is capable of extraordinary creative work. Don't hold back, show what can truly be created when thinking outside the box and committing fully to a distinctive vision.

### Multi-Variant Fan-Out

When the design brief is a full surface (page, app, or non-trivial component), generate **3 variants in parallel** instead of a single take, then let the operator choose. This is Soleur's all-Claude adaptation of gstack `design-shotgun` (ADR-089).

1. **Load learned taste (FR6 + validate).** The FR6 hook injects a read-directive for `knowledge-base/product/design/taste-profile.md`. Before trusting it, run `bash plugins/soleur/scripts/taste-profile-update.sh --validate knowledge-base/product/design/taste-profile.md`. On a **non-zero** exit, design with **no taste bias** (fail-open — never block on a corrupt profile). On success, read the profile's `## Reinforced Aesthetics` table and take the entries whose `context` matches the current design context (`landing-page | marketing-site | dashboard | app-ui | docs | email | component`); the most-recent value per axis is the operator's current lean.
2. **Seed distinct directions.** Pick 3 distinct aesthetic directions from the Design Thinking tone list. Bias — do not restrict — the seeds toward the loaded taste: if the profile leans `minimalist@dashboard`, one seed should honor it and the others deliberately diverge so the operator still sees range. With an empty/invalid profile, pick 3 maximally-distinct seeds.
3. **Fan out via the Agent tool.** Spawn 3 sub-agents (one per seed), each with the full brief + its assigned direction **in the prompt text** — sub-agents do NOT inherit the FR6 injection, so the taste bias must be passed explicitly. Each returns a self-contained variant.
4. **Present the slate** for selection. Interactive: describe the 3 variants and let the operator choose by natural conversation — **never** `AskUserQuestion` (a nested Task subagent hangs on it). Headless / no operator turn: auto-select the variant matching the top-recency taste entry (or variant 1 if the profile is empty) and skip step 5 (no operator signal = no learning).

### Recording Taste

When the operator selects a variant **in an interactive session**, record the choice so future sessions are primed:

```bash
bash plugins/soleur/scripts/taste-profile-update.sh \
  knowledge-base/product/design/taste-profile.md \
  <context> aesthetic-direction <selected-direction> "$(date -u +%F)"
```

`<context>` is the current design context (the enum above); `<selected-direction>` is the chosen direction as a sanitized lowercase-hyphen token (e.g. `minimalist`, `editorial`). The helper ([`taste-profile-update.sh`](../../scripts/taste-profile-update.sh)) validates every token, recomputes the entry by recency, flags a same-context contradiction, and bumps `last_updated` only. Do **not** hand-edit `taste-profile.md`. Do **not** record in headless runs.
