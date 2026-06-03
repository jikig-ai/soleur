# ADR-049: Headless Visual-Regression Gate for Structural-UI Diffs

- **Status:** Accepted
- **Date:** 2026-06-02
- **Deciders:** Jean (operator), CTO/CPO/CLO triad (brainstorm)
- **Relates to:** ADR-047 (nav context band outside swap), PR #4810, PR #4833

## Context

PR #4810 collapsed the dashboard into a single nav rail. It passed every automated gate — 8166
vitest green, tsc clean, 6-agent review, GDPR gate — and deployed to prod with two CSS-layout
bugs that none of those gates could see:

1. **jsdom (vitest) renders no CSS.** `md:w-14`, `hidden md:block`, `flex-wrap`, `display:none`
   are all invisible. DOM-presence tests pass while the rendered layout is broken.
2. **The real-browser walkthrough was deferred to post-merge** (AC10), so nothing rendered the
   real page before merge.
3. **Workflow asymmetry:** `/soleur:one-shot` runs `/soleur:qa` pre-merge, but a direct
   `/soleur:work` invocation skips it — so the PR had no browser check on any path.

The operator framed the unblocking question as "auth-seed via dev-signin or storageState?" —
because every local attempt to reach `/dashboard/*` headlessly 307'd to `/login`.

## Decision

**Structural-UI diffs require a committed headless visual-regression spec that renders real CSS,
runs with zero credentials, and is CI-portable.**

Concretely:

1. The gate is a committed `@playwright/test` spec in the existing `authenticated` project
   (`apps/web-platform/playwright.config.ts`), which runs **real headless Chromium against a real
   Next.js SSR dev server** (full middleware + the ADR-047 SSR-identity path), seeded by an
   **offline mock-Supabase storageState** (`e2e/global-setup.ts`).
2. **No dev-signin, no live backend, no real credentials** — local and CI use the same mock fork.
3. Deterministic assertions encode the structural invariants (chrome hidden when drilled, no
   horizontal overflow, collapsed band icon-only, identity band always visible). The LLM vision
   pass in `/soleur:qa` is an **advisory overlay, not the blocking gate**.
4. The gate is wired into the path that previously skipped it (`/soleur:work` Phase 4) behind a
   tight diff-path predicate, in addition to running CI-blocking.

## Alternatives Considered

| Option | Rejected because |
|--------|------------------|
| **Live `doppler -c dev` server + `/api/auth/dev-signin`** (the framed "key unknown") | Reintroduces the exact 307→/login failure (mock JWT won't validate against live dev Supabase); forces `FLAG_DEV_SIGNIN=1` + real `DEV_USER_*` creds into CI (auth-bypass / creds-exfil surface the 4-layer defense was built to avoid); headed-only (Playwright MCP pinned `headless:false`) so it can't run in autonomous `/work` or CI. |
| **Agent-driven Playwright MCP walkthrough as the blocking gate** | Headed-only, non-durable (no committed regression guard), depends on an agent remembering to walk the matrix. Kept as advisory vision only. |
| **agent-browser CLI script** | Headless and scriptable, but builds a parallel harness instead of reusing the proven `authenticated` Playwright project; no `expect`/`storageState` ergonomics. |
| **Rely on jsdom DOM-presence tests** | Cannot see CSS — the root cause. (We still *strengthen* the jsdom test for the DOM-presence half of Bug 1, as cheap belt-and-suspenders, but it is not the gate.) |

## Consequences

**Positive:** CSS-layout regressions on the nav shell are caught pre-merge, headless, with zero
credentials; the spec is a durable regression guard; the auth-bypass surface is eliminated; the
one-shot/`work` asymmetry is closed.

**Negative / costs:** Adds the `authenticated` webServer + a viewport matrix to the blocking CI
path (kept small by scoping to the shell + 1-2 drilled routes). Collapsed state must be seeded via
`localStorage["soleur:sidebar.main.collapsed"]` (not clicked) to avoid animation flakiness.

**Constraint (CLO):** baselines/screenshots must be synthetic-fixture-only (`test@e2e.com` + mock
UUID); the gate must never point at a live/staging origin. If it ever does, re-trigger the
gdpr-gate.

**Scope boundary:** this gate covers the nav/dashboard shell. Broad per-page visual regression is
deferred (YAGNI) to a tracked issue; extending coverage is a one-line route-list addition.
