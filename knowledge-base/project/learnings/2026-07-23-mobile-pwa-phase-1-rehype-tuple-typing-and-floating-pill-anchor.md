---
title: "rehype plugin-with-options tuple typing, floating-pill anchoring, and iOS visualViewport keyboard lift"
date: 2026-07-23
branch: feat-one-shot-mobile-pwa-phase-1
category: ui-bugs
tags: [rehype-highlight, react-markdown, typescript, pwa, ios-safari, visualviewport, scroll-guard, tailwind]
---

# Learning: mobile + PWA Phase 1 — three non-obvious frontend traps

## Problem

Phase 1 of the mobile/PWA hardening of `apps/web-platform` (viewport/manifest, 16px input floor, chat scroll-guard, iOS keyboard lift, highlight.js grammar trim) surfaced three traps that neither the plan nor `tsc` predicted, plus one that only multi-agent review caught.

## Solution / Key Insights

### 1. A `rehype`/`remark` plugin-with-options tuple needs contextual typing — and it must come from a DECLARED dependency

The plan asserted this compiles untyped:
```ts
const REHYPE_PLUGINS = [[rehypeHighlight, { detect: false, languages: {...} }]];
```
It does **not** — `tsc` rejects it with TS2322 because the inner array literal `[rehypeHighlight, {...}]` is widened to a `(Plugin | Options)[]` union instead of the `[Plugin, Options]` tuple that `react-markdown`'s `rehypePlugins` prop (`PluggableList`) requires. Contextual typing from an annotation fixes the tuple inference.

The **wrong** fix (first attempt) was `import type { PluggableList } from "unified"` — `unified` is not in `apps/web-platform/package.json`; it only resolves as a hoisted transitive dep, so a strict/pnpm install or a dedupe shift would break `tsc` on a type the app never declared.

The **right** fix derives the type from the already-declared consumer:
```ts
import type { Components, Options } from "react-markdown";
const REHYPE_PLUGINS: NonNullable<Options["rehypePlugins"]> = [ ... ];
```
Generalizable rule: to type a plugin-with-options tuple, annotate with the CONSUMER's own prop type (`Options["rehypePlugins"]` / `Options["remarkPlugins"]`), never by importing `PluggableList`/`Pluggable` from `unified` unless `unified` is a direct dependency.

### 2. A floating "jump to latest" pill must anchor to the composer's real height, not a fixed offset

Mounting the pill on the non-scrolling root with `style={{ bottom: 'calc(6rem + Npx)' }}` overlaps the composer as soon as the textarea grows (it autosizes to `max-h-[140px]`). The robust pattern: wrap the pill + composer in a `relative` shell and give the pill `absolute bottom-full mb-2` so it always sits just above the composer's actual top edge, and it rides the keyboard up automatically because the composer's own `marginBottom` (the keyboard inset) pushes it up. No height measurement needed.

### 3. iOS Safari ignores `interactiveWidget: "resizes-content"` — lift the composer with `visualViewport`

`viewport.interactiveWidget` is Chromium/Android-only. On iOS Safari the keyboard overlays without reflowing `dvh`, so a bottom-pinned composer under `h-full` + no outer scroll is trapped behind the keyboard. Subscribe to `window.visualViewport` `resize`+`scroll` and apply a bottom offset = `max(0, window.innerHeight - vv.height - vv.offsetTop)` (round it so React's `Object.is` bail collapses the sub-pixel render burst during the keyboard animation). Stays 0 on Android/desktop.

### Bonus: `h-full` beats `calc(100dvh - bar)` for a slot-filling surface

When a surface is a direct child of a `flex-1` item inside a definite-height (`h-dvh`) flex column, `h-full` resolves to the true slot height. A `calc(100dvh - <bar>)` regresses the moment `viewportFit:cover` makes the bar's `env(safe-area-inset-top)` non-zero, or the bar grows (`min-h-*`).

## Session Errors

1. **Plan asserted an untyped rehype tuple compiles; tsc rejected it (TS2322).** — Recovery: annotate the constant. **Prevention:** treat a plan's "this compiles" / "keep untyped" claims as preconditions to verify with `tsc`, not facts — run the app's pinned `./node_modules/.bin/tsc --noEmit` at the phase that lands the code, not only at the end.
2. **First type-fix imported `PluggableList` from the undeclared transitive `unified`.** — Recovery: re-typed via `react-markdown` `Options["rehypePlugins"]`. **Prevention:** before importing a type, confirm the package is in the app's `package.json`; prefer deriving from an already-imported declared dependency.
3. **Scroll-guard pill used a fixed `6rem` bottom offset and overlapped a multi-line composer.** — Recovery: `relative` shell + `bottom-full`. **Prevention:** any element floated above a growable input must anchor to that input's box, never a magic offset.
4. **`Edit` failed with string-not-found on the close-nav button** (indentation differed from a sibling). — Recovery: re-`Read` the exact region, match verbatim. **Prevention:** for repeated-shape elements, read the specific occurrence before editing rather than reusing a sibling's string.
5. **A `grep` failed with "No such file or directory"** because the Bash CWD sat at the worktree root after a `cd <root> && git commit`. — Recovery: re-`cd` into `apps/web-platform`. **Prevention:** the Bash tool persists CWD across calls; prefix path-relative commands with `cd <abs-path> &&` when the prior command may have changed directory.

## Tags
category: ui-bugs
module: apps/web-platform (chat-surface, markdown-renderer, layout, manifest)
