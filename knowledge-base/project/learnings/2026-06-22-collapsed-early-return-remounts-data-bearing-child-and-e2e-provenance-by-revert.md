# Learning: a `collapsed` early-return that omits a data-bearing child remounts+refetches it; prove an e2e failure's provenance by reverting touched files to origin/main

## Problem

The dashboard workspace selector flashed and reloaded every time the user
collapsed/expanded the sidebar. `WorkspaceContextBand` early-returned a
*structurally different* subtree when `collapsed` that omitted
`OrgSwitcherContainer` entirely (feeding a separate `useActiveWorkspace` hook
instead). React reconciles by position, so swapping to a subtree without the
container **unmounted it on every collapse and remounted a fresh instance on
every expand** — re-running its `/api/workspace/list-memberships` fetch,
resetting state, and discarding the in-flight switch-confirm dialog. This was a
regression against ADR-047 ("band never gated on `collapsed`"): the original
`!collapsed` unmount bug, relocated one level deeper into the band's internal
render path.

A second issue surfaced during QA: the `nav-states` structural-UI e2e gate
reported test #18 (the « collapse-toggle glyph test, just added by #5630)
failing deterministically (3/3) on a mechanism the diff never touched.

## Solution

**The fix (remount):** keep ONE `OrgSwitcherContainer` mounted at a
structurally stable tree position across the toggle and vary only presentation
(`OrgSwitcher` gains a `collapsed` icon-only mode). Retire the redundant
`useActiveWorkspace` hook (it existed only to feed the gated-out collapsed
tile, double-fetching the same endpoint). The "never gated on `collapsed`"
invariant is **structural, not locational** — an element swap that removes a
data-bearing child from the tree is prohibited even one level deep (ADR-047
Amendment 2026-06-22).

**The regression test:** happy-dom renders no compositor and presence/role
assertions never observe a remount — so the load-bearing test must assert the
mount/fetch *lifecycle*. Spy on `fetch`, toggle `collapsed` via `rerender`, and
assert the `list-memberships` call count is unchanged across expand→collapse→expand.
A DOM-presence assertion would pass vacuously against the buggy code.

**The e2e-provenance technique:** a deterministically-failing e2e on a mechanism
your diff doesn't touch is not automatically yours. Prove provenance by reverting
the touched source files to origin/main and re-running the single failing test:

```bash
git checkout origin/main -- <touched source files>   # restore clean main state
./node_modules/.bin/playwright test <spec>:<line> --project=authenticated --reporter=list
git checkout HEAD -- <files> && git rm/reset as needed  # restore your committed work
```

Test #18 failed identically on clean origin/main, proving it a pre-existing
local headless-Chromium issue (the toggle click not registering) — #5630 merged
with green CI, so CI is the authoritative `nav-states` gate. Every assertion
covering the actual change surface (collapsed icon identity, no-overflow, mobile
band) passed 22/23.

## Key Insight

- Reconcile-by-position: a conditional *element swap* around a data-bearing
  child is an unmount, not a re-render. To preserve a child's fetch/state across
  a UI-mode change, keep ONE instance at a stable position and branch *className*,
  never the element tree. `key` cannot rescue an *absent* element.
- Test the invariant (zero refetch across the toggle), not a proxy (DOM presence)
  — jsdom/happy-dom cannot see a remount.
- A deterministic e2e failure ≠ your regression. Revert the touched files to
  origin/main and re-run the one test: identical failure = pre-existing; only a
  failure that *clears* on revert is yours. Cheap, unambiguous, no second worktree.

## Session Errors

- **Playwright `webServer` failed to start on the first `nav-states` run (exit 1).**
  Recovery: retried; the second run started cleanly. Cause: `playwright.config.ts`
  configures two `webServer` entries that both run `npm run dev`, racing on the
  same `.next/dev-server.mjs` esbuild outfile. Prevention: recurring local-env
  flake already documented in the QA skill's nav-states sharp edges (#5009);
  CI's containerized e2e job is the authoritative gate. No new action.
- **`nav-states` #18 failed deterministically (3/3).** Recovery: proved
  pre-existing by reverting to origin/main (technique above) and re-running —
  identical failure. Prevention: this learning documents the revert-to-prove-provenance
  technique so the next session reaches the verdict without re-deriving it.

## Tags
category: ui-bugs
module: apps/web-platform/components/dashboard
related: [ADR-047, 5632, 5630, 5009]
