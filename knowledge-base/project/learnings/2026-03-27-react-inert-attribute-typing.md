# Learning: React inert attribute requires boolean, not string

## Problem

Plan prescribed `inert=""` (empty string attribute) for focus trapping based on the HTML spec and React 19 documentation stating `inert` was added to type definitions. The Next.js 15.5 production build failed with:

```
Type '{ children: ReactNode; inert?: string | undefined; className: string; }'
is not assignable to type 'DetailedHTMLProps<HTMLAttributes<HTMLElement>, HTMLElement>'.
Types of property 'inert' are incompatible.
Type 'string | undefined' is not assignable to type 'boolean | undefined'.
```

## Solution

Use `inert={drawerOpen || undefined}` instead of `{...(drawerOpen ? { inert: "" } : {})}`. React's type definitions for `inert` expect `boolean | undefined`, not `string`. The `|| undefined` pattern correctly removes the attribute when the value is `false`.

## Key Insight

React 19+ types `inert` as a boolean HTML attribute, diverging from the raw HTML spec where `inert` is a boolean attribute set via empty string or presence. When working with newer HTML attributes in React, check the actual TypeScript definitions (`@types/react`) rather than relying on MDN docs or the HTML spec. The `next build` type-check catches this; standalone `bunx tsc` may not due to sandboxed module resolution.

## Session Errors

1. **inert attribute type mismatch** — Plan prescribed `inert=""` but build required `boolean`. Recovery: changed to `inert={drawerOpen || undefined}`. Prevention: always verify newer HTML attribute typings against React's `@types/react` definitions, not MDN.
2. **bunx tsc unusable for type-checking** — bunx sandboxing doesn't resolve project node_modules, producing false-positive "Cannot find module 'react'" on every file. Recovery: used `next build` for TypeScript validation. Prevention: use `next build` or the project's configured type-check script, not standalone `bunx tsc`.
3. **Markdown lint failure on session-state.md** — Missing blank lines around headings/lists. Recovery: rewrote with correct formatting. Prevention: follow MD022/MD032 rules when generating markdown programmatically.
4. **Backdrop conditional rendering breaks fade transition** — Architecture reviewer caught `{drawerOpen && <div/>}` causes instant snap. Recovery: always-render backdrop with opacity transition. Prevention: always-render overlay elements that participate in CSS transitions; use opacity+pointer-events pattern.

## Tags

category: ui-bugs
module: web-platform
