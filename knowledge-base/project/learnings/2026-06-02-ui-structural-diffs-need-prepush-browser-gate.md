---
date: 2026-06-02
category: workflow-patterns
tags: [testing, jsdom, playwright, visual-regression, nav-rail, qa-gate, ci]
relates:
  - knowledge-base/engineering/architecture/decisions/ADR-047-nav-context-band-outside-swap.md
  - knowledge-base/engineering/architecture/decisions/ADR-048-headless-visual-regression-gate.md
  - knowledge-base/project/learnings/2026-06-02-server-audit-must-read-rpc-body-and-ssr-identity-needs-css-placement.md
issue: 4834
pr: 4833
---

# UI-structural diffs require a pre-push real-browser screenshot gate

## What happened

PR #4810 collapsed the dashboard into a single nav rail. It passed **every** automated gate —
8166 vitest green, tsc clean, 6-agent review, GDPR gate — and deployed to prod with two CSS-layout
bugs that the gates were structurally incapable of seeing:

1. **Bug 1:** the `Soleur` wordmark + collapse chevron + `ThemeToggle` rendered outside the
   `drill === null ? <primaryNav> : <slot>` swap, so top-level chrome leaked into every drilled
   route.
2. **Bug 2:** `WorkspaceContextBand` had no collapsed (icon-only) form, so at `md:w-14` the org
   switcher + repo + KB tree wrapped into an unreadable strip.

## Why every gate missed it

Three compounding causes — none individually unusual, together a guaranteed escape:

1. **jsdom (vitest) renders no CSS.** `md:w-14`, `hidden md:block`, `flex-wrap`, `display:none`
   are all invisible to jsdom. DOM-presence tests pass while the *rendered layout* is broken. The
   plan even said "never assert jsdom layout values → Playwright" — and then the Playwright step
   was deferred.
2. **The real-browser check (AC10) was deferred to post-merge.** A deferred verification gate is a
   skipped one for the merge it was supposed to guard.
3. **Workflow asymmetry:** `/soleur:one-shot` runs `/soleur:qa` pre-merge, but a direct
   `/soleur:work` invocation does not. This PR went through direct `/work`, so it had **no browser
   check on any path**.

## The rule

**Any diff touching a UI-structural surface (nav/layout/shell, `app/(dashboard)/**`,
`components/dashboard/**`, any `layout.tsx`) must pass a committed, headless, real-CSS visual-
regression gate BEFORE push — not a jsdom DOM-presence test, and not a post-merge walkthrough.**

## How to apply

- Make the gate a **committed `@playwright/test` spec** (durable regression guard), not an agent-
  driven ad-hoc walkthrough. Reuse the existing `authenticated` project (real headless Chromium +
  real SSR + **offline mock-Supabase storageState**) — it needs **zero credentials** and is
  CI-portable.
- **Do not** reach for a live-dev-server + `dev-signin` seed when a headless 307→/login blocks you.
  That reintroduces the failure and forces real `DEV_USER_*` creds + `FLAG_DEV_SIGNIN` into CI (an
  auth-bypass surface). The mock-Supabase storageState already renders the real SSR-identity path.
- Force client-state (e.g. collapsed rail) **deterministically** — seed the backing store
  (`localStorage["soleur:sidebar.main.collapsed"]`), never click + wait on animation (the #1
  e2e flake source).
- Assert what jsdom can't: element visibility under CSS, `scrollWidth <= clientWidth` (no overflow
  / no text wrap), presence/absence by rendered state. Keep an LLM screenshot **vision pass** as an
  *advisory* overlay, never the blocking gate (headed MCP can't run headless/autonomous).
- **Close workflow asymmetries:** if one entry path runs a gate and another skips it, wire the gate
  into the skipping path (here: `/soleur:work` Phase 4 behind a diff-path predicate). A gate that
  only fires on one of N entry points is a gate with N-1 holes.
- **Prove the gate by making it go RED on the live bug first**, then GREEN after the fix, in the
  same PR. A green-from-birth gate is unvalidated.
