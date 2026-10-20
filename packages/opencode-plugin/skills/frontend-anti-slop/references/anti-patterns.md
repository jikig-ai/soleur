<!-- Adapted from Hallmark (MIT) — see /LICENSES/hallmark.MIT.txt -->

# Anti-patterns — React/Next.js named tells

Each entry: the tell, why it reads as AI-generated, and the fix in JSX/Tailwind form.

---

## Critical

### The gradient headline (rule GRADIENT-TEXT)

```tsx
<h1 className="bg-clip-text text-transparent bg-gradient-to-r from-purple-500 to-pink-500">
  Build the future of your stack
</h1>
```

Three-class `bg-clip-text + text-transparent + bg-gradient-to-*` triad signals AI-generated faster than almost anything else.

**Fix.** Solid ink. If you want presence, reach for weight, italic, or a display face.

```tsx
<h1 className="font-display text-5xl font-medium tracking-tight">
  Build the future of your stack
</h1>
```

### Purple→blue gradient backgrounds (rule PURPLE-BLUE-GRADIENT)

```tsx
<section className="bg-gradient-to-br from-purple-600 to-blue-500 ...">
```

The single most-recognised AI aesthetic. Hero, CTA, badge — anywhere.

**Fix.** Pick one anchor hue. Tint neutrals for warmth instead of pouring gradient.

### Inter / Roboto / Open Sans everywhere (rule GENERIC-DISPLAY-FONT)

```tsx
import { Inter } from "next/font/google";
const inter = Inter({ subsets: ["latin"] });
```

…and `<html className={inter.className}>`. One-face Inter page is a template page.

**Fix.** Pair a distinctive display face (Fraunces, Instrument Serif, GT America Mono, etc.) with a refined body face. Or load a real type file from a foundry.

### Card-in-card (deferred to v1.5 — CARD-IN-CARD)

```tsx
<div className="rounded-xl border ...">
  <div className="rounded-lg border ...">
    <div className="rounded border ...">{label}</div>
  </div>
</div>
```

Three layers of border + radius with no semantic reason. Visual nesting where one container would say it.

**Fix.** Pick one containment layer — usually the outer one is wrong.

### Side-stripe card (rule SIDE-STRIPE-CARD)

```tsx
<div className="border-l-4 border-purple-500 ...">
```

Bootstrap-era hangover. Reads as "alert box" muscle memory.

**Fix.** Drop the stripe. Use the header rule, or vary the card surface tone.

---

## Microinteractions

### `transition-all` (rule TRANSITION-ALL)

```tsx
<button className="transition-all duration-300 hover:scale-105 ...">
```

Animates every property — including layout-affecting ones — at the same curve and duration. Composability fail.

**Fix.** Name the property.

```tsx
<button className="transition-opacity duration-200 hover:opacity-90 ...">
```

### Uniform `hover:scale-105` everywhere (rule UNIFORM-HOVER-SCALE)

When every card, button, and tile in a file lifts by the same 5 %, the page reads as one undifferentiated surface.

**Fix.** Reserve scale for primary CTAs. Other surfaces vary: opacity, colour, shadow.

### Bouncy easing on UI (rule BOUNCY-EASING-UI)

```css
transition-timing-function: cubic-bezier(0.34, 1.56, 0.64, 1);
```

Overshoot is a physical-world cue (a tossed envelope settles past the centre). On a tooltip or modal it reads as "look at me" — the opposite of what UI motion should do.

**Fix.** Reserve overshoot for physical interactions. Use cubic-out (`cubic-bezier(0.0, 0.0, 0.2, 1)`) for UI.

### Animating dimension props (rule ANIM-DIMENSION-PROPS)

```tsx
<div className="transition-width duration-500 ...">
```

Width / height / top / left / margin / padding all trigger layout, which is expensive and jank-prone.

**Fix.** Animate `transform` + `opacity` only. For "growing" effects, use `scale` or `translate`.

---

## Comprehension

### Placeholder names (rule PLACEHOLDER-NAMES)

```tsx
<blockquote>
  "Soleur replaced our marketing team." — Jane Doe, CEO of Acme
</blockquote>
```

Jane Doe / John Smith / Acme / Nexus / Seamless / Unleash are the AI-defaults the model reaches for when no real testimonial exists.

**Fix.** Use a real customer name (with permission) or remove the testimonial. An empty quote slot is taste; a fake one is slop.

### Prose width out of range (rule PROSE-WIDTH-OUT-OF-RANGE)

```tsx
<article className="max-w-[120ch] ...">
```

Under 45 ch the measure is choppy; over 75 ch the eye loses the line return.

**Fix.** Stay in 45–75 ch.

---

## Visual implementation

### Zero-chroma OKLCH neutrals (rule ZERO-CHROMA-OKLCH)

```css
--color-surface-1: oklch(98% 0 0);
```

Pure greys read as flat — every paper colour in the world is tinted somewhere.

**Fix.** Push chroma to at least 0.005 toward the anchor hue.

### Off-scale spacing (rule OFF-SCALE-SPACING)

```tsx
<div className="p-[17px] gap-[13px] m-[23px]">
```

Arbitrary px values not on the 4-px scale are an AI tell — the model picked a number to make something fit instead of using the system.

**Fix.** Use the named spacing scale, or adjust to the nearest 4-px multiple.

### Two icon libraries (rule TWO-ICON-LIBS)

```tsx
import { Search } from "lucide-react";
import { HomeIcon } from "@heroicons/react/24/outline";
```

Two icon faces on the same page is the icon-set tell — the model reached for whichever it remembered for each glyph.

**Fix.** Pick one library and commit. Lucide and Phosphor have full coverage.

### Pure `#000` / `#fff` base (rule PURE-BW-BASE)

```tsx
<html className="bg-black text-white">
```

Pure black / pure white are exhausted defaults. Real product palettes tint the base.

**Fix.** Tint every base. `oklch(98% 0.005 80)` instead of `oklch(100% 0 0)`.

### Centred-everything hero (rule MIN-H-SCREEN-CENTERED-HERO)

```tsx
<section className="min-h-screen flex items-center justify-center">
  <div className="text-center"> ... </div>
</section>
```

Eyebrow, title, lede, CTA all centred on the same axis is the strongest hero fingerprint.

**Fix.** Pick at most two centred elements. Break alignment for the others.
