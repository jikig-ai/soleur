<!-- Adapted from Hallmark (MIT) — see /LICENSES/hallmark.MIT.txt -->

# Slop rules — React/Next.js Tier 1 (v1) + Tier 2 (v1.5 documented)

The scanner parses the **active rules** table below. Rows with `tier: 1` ship in v1 as deterministic ripgrep gates over `apps/web-platform/{app,components}/**/*.{tsx,jsx,css}`. Rows with `tier: 2` are kept here so v1.5 can wire them into the LLM-judgment reviewer agent without re-derivation; the v1 scanner ignores them.

Each rule maps 1:1 (or 1:few) to a gate from Hallmark's slop-test. The `hallmark_gate` column points back to the gate number in [`hallmark/references/slop-test.md`](https://github.com/Nutlope/hallmark/blob/main/references/slop-test.md).

Per-file disable comment: `<!-- anti-slop:disable RULE_ID reason="..." -->` (the scanner honors this; emitted alongside a `disabled` finding in `--verbose` mode for audit trail).

## Active rules

| id | tier | category | hallmark_gate | severity | pattern | message | suggested_fix |
|---|---|---|---|---|---|---|---|
| GRADIENT-TEXT | 1 | visual | 5 | high | `\bbg-clip-text\b.*\btext-transparent\b.*\bbg-gradient-to-` | `bg-clip-text + text-transparent + bg-gradient-to-*` triad — gradient-fill headline reads as AI default. | Use solid ink. Reach for weight, italic, or a display face for emphasis. |
| GENERIC-DISPLAY-FONT | 1 | visual | 1 | medium | `import\s*\{\s*(Inter\|Roboto\|Open_Sans\|Poppins\|Lato)\s*[\},].*from\s*["']next/font/google` | Generic display-font import. One-font Inter/Roboto/Poppins page is a template page. | Pair a distinctive display face with a refined body face. |
| PURPLE-BLUE-GRADIENT | 1 | visual | 2 | medium | `bg-gradient-to-\w+\s+(?:[^"]*\s)?from-(?:purple\|violet\|fuchsia)-\d+\s+(?:[^"]*\s)?to-(?:blue\|cyan\|sky)-` | Purple→blue (or violet→cyan) gradient — single most-recognised AI aesthetic. | Pick a single anchor hue. No gradient backgrounds. Tint neutrals for warmth. |
| SIDE-STRIPE-CARD | 1 | visual | 6 | medium | `\bborder-l-4\b.*\bborder-(?:purple\|blue\|pink\|indigo\|emerald)-` | Thick coloured left side-stripe on card — common Bootstrap-era tell. | Drop the stripe. Use a single header rule or vary card surface instead. |
| MIN-H-SCREEN-CENTERED-HERO | 1 | visual | 7 | low | `\bmin-h-screen\b.*\bflex\b.*\bitems-center\b.*\bjustify-center\b` | `min-h-screen` + centred-everything hero. | Pick at most two centred elements; break alignment for the others. |
| PURE-BW-BASE | 1 | visual | 8 | medium | `(?:bg-black\|bg-white)(?:\s\|"\|'\|/)` | Raw `bg-black` / `bg-white` on root layout / page wrapper. | Tint every neutral toward the anchor hue (≥ 0.005 chroma). |
| TRANSITION-ALL | 1 | microinteractions | 11 | low | `\btransition-all\b` | `transition-all` — animates every property. Composability fail. | Name the property: `transition-opacity`, `transition-colors`, etc. |
| UNIFORM-HOVER-SCALE | 1 | microinteractions | 12 | low | `\bhover:scale-105\b` | Uniform `hover:scale-105`. Fires when ≥ 4 occurrences in the same file. | Reserve scale for primary CTAs. Other surfaces vary: colour, shadow, opacity. |
| BOUNCY-EASING-UI | 1 | microinteractions | 13 | medium | `cubic-bezier\(0\.34,\s*1\.56` | Bouncy / overshoot easing on UI state changes. | Reserve overshoot for physical interactions only. Use cubic-out for UI. |
| ANIM-DIMENSION-PROPS | 1 | microinteractions | 15 | medium | `\btransition-(?:width\|height\|top\|left\|margin\|padding)\b` | Animating layout-shifting props (width/height/top/left/margin/padding). | Animate `transform` + `opacity` only. |
| PLACEHOLDER-NAMES | 1 | comprehension | 20 | low | `\b(?:Jane Doe\|John Smith\|Acme(?: Inc\|, Inc)?\|Nexus\|Seamless\|Unleash)\b` | Placeholder names / startup-cliché names. | Use the user's actual customer names or remove the section. |
| ZERO-CHROMA-OKLCH | 1 | visual | 24 | low | `oklch\(\s*[0-9.]+%?\s+0\s+` | Zero-chroma OKLCH neutral — reads as flat. | Tint every neutral ≥ 0.005 chroma toward the anchor hue. |
| OFF-SCALE-SPACING | 1 | visual | 26 | low | `\b(?:p\|m\|gap)-\[(?:[1-3]\|[5-9]\|1[0-9]\|2[1-9]\|3[1-9])px\]` | Arbitrary spacing value not on the 4 px scale. | Use the named scale (`--space-3xs` … `--space-5xl`, multiples of 4 px). |
| PROSE-WIDTH-OUT-OF-RANGE | 1 | comprehension | 27 | low | `\bmax-w-\[(?:[0-9]\|[1-3][0-9]\|4[0-4]\|7[6-9]\|[89][0-9]\|1[0-9]{2})ch\]` | Prose `max-width` outside the 45–75 ch readable range. | Measure must read: under 45 ch is choppy, over 75 ch loses the eye. |
| TWO-ICON-LIBS | 1 | visual | 32 | medium | `from\s+["'](?:lucide-react\|react-icons[^"']*\|@heroicons/react[^"']*)["']` | Multiple icon libraries imported in the same file. | Pick one library. Two icon faces on the page is the icon-set tell. |

## Documented Tier 2 rules (deferred to v1.5 — judgment-required)

| id | tier | category | hallmark_gate | defer | rationale |
|---|---|---|---|---|---|
| STRUCTURAL-FINGERPRINT | 2 | structural | 9 | v1.5 | Requires page-level macrostructure knowledge — "Hero → 3 features → CTA → footer" pattern detection needs LLM judgment. |
| EQUAL-RHYTHM-SECTIONS | 2 | structural | 10 | v1.5 | "Sections separated only by equal whitespace" requires layout analysis. |
| MULTI-HOVER-EFFECT | 2 | microinteractions | 14 | v1.5 | Detecting > 1 simultaneous hover effect (translate + scale + shadow + colour) needs JSX-prop walk. |
| FOCUS-RING-FADE-IN | 2 | microinteractions | 16 | v1.5 | "Focus ring transitions into existence" requires CSS-rule pairing analysis. |
| CELEBRATORY-SUCCESS-TOAST | 2 | microinteractions | 17 | v1.5 | Judgment: does the action have a visible effect already? |
| TOOLTIP-EQUAL-DELAYS | 2 | microinteractions | 18 | v1.5 | Requires cross-prop comparison on tooltip components. |
| CAROUSEL-NO-PAUSE | 2 | microinteractions | 19 | v1.5 | Requires component-shape analysis (carousel without pause-on-hover/focus). |
| INVENTED-METRIC | 2 | comprehension | 56 | v1.5 | Hardest judgment gate — distinguishes user-supplied numbers from fabricated ones. |
| REDRAWN-CHROME | 2 | visual | 57 | v1.5 | Requires recognising fake browser bar / phone frame / IDE chrome — visual shape, not regex. |
| MID-RENDER-TOKEN | 2 | visual | 58 | v1.5 | Detecting raw hex / oklch outside `:root` token blocks needs CSS-rule context awareness. |
| TWO-LINE-CLICKABLE | 2 | responsive | 59 | v1.5 | "Wraps to 2 lines" requires rendered-layout measurement, not source-static check. |
| EMOJI-AS-ICON | 2 | visual | 60 | v1.5 | Requires distinguishing emoji-as-content from emoji-as-feature-icon. Glyph context. |

## Cut from v1 (require AST — deferred to v1.5 with ts-morph)

These gates need parent-walk / JSX shape analysis and are explicitly **out of scope** for v1's regex-only scanner per Sharp Edge `2026-04-02-lazy-regex-semicolons-typescript-structural-tests.md`. They land in v1.5 alongside Tier 2.

| id | hallmark_gate | reason |
|---|---|---|
| CARD-IN-CARD | 4 | Requires JSX parent-walk (card-shape element nested inside same-shape element). |
| MISSING-FOCUS-VISIBLE-ACTIVE-DISABLED | 28 | Multi-selector cross-cutting; regex would false-positive on inherited motion. |
| ANIM-WITHOUT-REDUCED-MOTION | 29 | Paired-regex (animation + media query) — needs structural pairing. |
