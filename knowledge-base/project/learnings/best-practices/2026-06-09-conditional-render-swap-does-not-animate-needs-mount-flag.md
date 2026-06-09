---
title: A conditional-render panel swap does not animate — a CSS transition needs a from→to change on a persistent element
date: 2026-06-09
category: best-practices
module: apps/web-platform/components
tags: [react, tailwind, animation, transition, prefers-reduced-motion, anti-slop]
pr: 5075
---

# Learning: conditional-render panel swap does not animate — use a mount-reveal flag

## Problem

The shared-document CTA banner (`apps/web-platform/components/shared/cta-banner.tsx`)
was changed so closing **collapses** it to a thin reopenable bar and clicking the
bar **re-expands** the full banner "with a smooth animation" (an explicit acceptance
criterion). The first implementation rendered the two panels with a mutually-exclusive
conditional render and slapped `transition-all duration-300` on each wrapper.

It typechecked, all unit tests passed, and it shipped **zero visible animation**.

## Root cause

A CSS transition animates the delta between a property's old value and its new value
**on the same persistent DOM element**. When you conditionally render
`{panel === "expanded" ? <A/> : <B/>}`, switching `panel` *unmounts* A and *mounts a
fresh* B. The new element paints once, already at its final `translate-y-0 opacity-100`
— there is no prior committed frame to transition *from*, so the browser snaps. The
outgoing element is gone instantly too (no exit animation possible without keeping both
mounted). `transition-all` on a freshly-mounted node is inert.

Unit tests can't catch this: jsdom/happy-dom does not evaluate `@media` or run the
compositor, and the tests assert presence/role/aria — never computed transition values.

## Solution

Ease each panel in **on mount** with a one-frame state flip, so there *is* a from→to
change on a persistent element:

```tsx
function Reveal({ children, className = "" }: { children: ReactNode; className?: string }) {
  const [entered, setEntered] = useState(false);
  useEffect(() => {
    const id = requestAnimationFrame(() => setEntered(true)); // next frame: flip
    return () => cancelAnimationFrame(id);
  }, []);
  return (
    <div className={`${className} transition-[transform,opacity] duration-300 ease-out
        motion-reduce:transition-none motion-reduce:duration-0
        ${entered ? "translate-y-0 opacity-100" : "translate-y-1 opacity-0"}`}>
      {children}
    </div>
  );
}
```

Wrap each conditionally-rendered panel in `<Reveal>`. Because each panel mounts a fresh
`Reveal` on every collapse/expand, the slide/fade replays each time. This mirrors the
existing repo idiom in `apps/web-platform/components/kb/selection-toolbar.tsx`
(rAF + state-flip mount reveal).

Two ancillary points:
- Use a **named** transition (`transition-[transform,opacity]`), never `transition-all`
  — the anti-slop Tier-1 scanner flags `TRANSITION-ALL`, and naming the property is the
  composable, intentional form.
- web-platform has **no `tailwindcss-animate`** plugin and no `animate-in`/`slide-in`
  keyframes (only one custom `pulse-border`), so the common
  `animate-in slide-in-from-bottom-2` one-liner is unavailable — the rAF mount-flag is
  the simplest in-repo path.

## Key insight

"Add a `transition-*` class" only animates an element that **persists across the state
change**. If the state change mounts/unmounts the element (conditional render, keyed
remount, route swap), the transition is inert — you need a mount-reveal flag
(rAF → flip a from-state class) or a library that injects enter keyframes. Pair every
animated utility with a `motion-reduce:` reset so the change is instant under
`prefers-reduced-motion`.

## Session Errors

1. **Write tool rejected `cta-banner.tsx` ("File has not been read yet")** — the file
   had only been viewed via `git show origin/main:...`, which does not satisfy the
   Read-before-Write state the harness tracks (hard rule
   `hr-always-read-a-file-before-editing-it`). **Recovery:** `Read` the worktree path,
   then `Write`. **Prevention:** treat `git show` as informational only — always `Read`
   the actual worktree file before the first `Edit`/`Write`, even if you've seen its
   content another way.
2. **Animation AC silently unmet by the plan's prescribed approach** (this learning).
   The plan even flagged the risk ("if the unanimated swap reads fine, drop the entry
   flag") but `/work` shipped the non-animating swap first. **Recovery:** the anti-slop
   `TRANSITION-ALL` finding during self-review prompted the trace; added `<Reveal>`.
   **Prevention:** when a plan's animation note is conditional ("add an entry flag only
   if the swap doesn't animate"), verify the swap actually animates before resolving it
   — for a conditional-render swap the answer is always "it doesn't."
3. **`${PIPESTATUS[0]}` after `| head` returned empty** — transient; re-ran `tsc` cleanly
   with `echo "tsc-exit=$?"`. One-off; no recurrence vector.
