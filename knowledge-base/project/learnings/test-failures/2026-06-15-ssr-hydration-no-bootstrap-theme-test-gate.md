---
title: "Testing the no-bootstrap SSR-hydration theme path needs an init-vs-effect storage gate (and a precondition self-check)"
date: 2026-06-15
category: test-failures
module: apps/web-platform/components/theme
tags: [react, hydration, jsdom, vitest, theme, localStorage, test-fixtures]
---

# Learning: simulating the no-bootstrap SSR-hydration theme path in jsdom

## Problem

The theme bug (`fix(theme): explicit choice survives reload`) only manifests on
the **SSR-hydration, no-bootstrap** path: React's lazy `useState` initializers
run server-side (`window` undefined) and land on `"system"`, React's first
client render reuses that snapshot, and the first-mount effect's else-branch
writes that `"system"` to `documentElement.dataset.theme` when the inline
`NoFoucScript` did not run — letting the OS `prefers-color-scheme` cascade
override the user's explicit stored choice.

A regression test must reproduce: **initial React `theme` state = `"system"`
WHILE `localStorage["soleur:theme"]` holds the real choice AND `dataset.theme`
is absent.** This is hard in jsdom because:

1. A naive client-only mount lets the lazy initializer reach `readStoredTheme()`
   and resolve to the stored value directly → state never lands on `"system"` →
   the bug is masked and the test passes green **before any fix** (vacuous RED).
2. Render and effect flush in the same synchronous `act()`, so there is no
   external injection point between "init reads storage" and "effect reads
   storage".

## Solution

Gate localStorage **visibility** between init and effect so the lazy
initializers observe an empty store (→ state `"system"`) while the post-mount
effect observes the real choice:

- **Do NOT use a `Storage.prototype.getItem` spy.** A call-count spy bleeds
  across tests in a shared jsdom worker (passes in isolation, fails in-suite),
  and a leftover `dataset.theme` attribute from a prior test pollutes later
  inits.
- **Use real localStorage** (empty at init) and write the stored value from
  inside the `matchMedia.matches` getter. `getSystemPreference()` touches
  `matchMedia` during the *second* lazy initializer — strictly after both
  initializers' storage reads, strictly before the first-mount effect. No mock
  state to bleed.
- Scrub `dataset.theme` + clear localStorage **inside** the mount helper
  (immediately before render), plus RTL `cleanup()` in `afterEach`.

```js
let released = false;
const mql = {
  get matches() { localStorage.setItem(KEY, stored); released = true; return osDark; },
  addEventListener(){}, removeEventListener(){},
};
vi.stubGlobal("matchMedia", () => mql);
render(<ThemeProvider><Probe/></ThemeProvider>);
if (!released) throw new Error("fixture did not reproduce SSR-hydration precondition…");
```

## Key Insight

The gate couples to one SUT internal: that `resolvedTheme`'s initializer reads
`matchMedia` before the first-mount effect. Make that coupling **fail loud**
with a precondition self-check (`if (!released) throw`) so a future refactor
that stops touching `matchMedia` at init surfaces as a clear *fixture* error,
not a misleading phantom SUT regression. Always pair "I manufactured a tricky
precondition" with "assert the precondition actually held."

Verify non-vacuity by reverting the fix and confirming the explicit-choice
cases fail while the system-follow control passes in both states.

## Session Errors

1. **Worktree create failed (exit 128)** — Bash CWD persisted from an earlier
   `cd` into a sibling worktree during routing inspection; `worktree-manager.sh
   create` ran from there → `fatal: 'main' is already used by worktree`.
   Recovery: `cd` to bare root first. Prevention: already covered by the
   CWD-persistence warnings in `work`/`one-shot`; one-off here.
2. **Regression-test gate fragility** — see above; 3 iterations (call-count spy
   → matchMedia-flip boolean → real-localStorage via getter). Prevention: this
   learning + the precondition self-check pattern.
3. **CWD drift on `vitest` invocation (exit 127)** — Bash tool did not persist
   `cd apps/web-platform`. Recovery: prepend `cd <abs> &&` in the same call.
   Prevention: already documented in the `work` skill; one-off here.

## Tags
category: test-failures
module: apps/web-platform/components/theme
