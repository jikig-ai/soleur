---
title: "Playwright toHaveClass(/re/) already auto-retries — a toHaveClass→expect.poll(getAttribute) swap is a cosmetic no-op; the real fix for a hydrated-client flake is a pre-click settle"
date: 2026-06-29
category: test-failures
module: apps/web-platform/e2e
tags: [playwright, e2e, flaky-test, hydration, expect-poll, code-review, grep]
issue: 5698
pr: 5699
---

# Learning: a class-assertion flake is a hydration-before-interaction bug, not a `toHaveClass` timing bug

## Problem

The nav-states e2e test "the « toggle button collapses/expands the rail and rotates
its glyph" (`apps/web-platform/e2e/nav-states-shell.e2e.ts`) flaked intermittently in
CI: `expect(aside).toHaveClass(/md:w-14/, { timeout: 7_000 })` timed out — the rail
never collapsed. Issue #5698 hypothesized the synchronous `toHaveClass` read "races the
`md:transition-[width]` animation + localStorage hydration" and proposed swapping all
three class asserts (`md:w-14`, `rotate-180`, `md:w-56`) to
`expect.poll(() => locator.getAttribute("class")).toContain(...)`.

## Root cause

The issue's mechanism was a **misdiagnosis**. Two facts the issue got wrong:

1. **`expect(locator).toHaveClass(/re/, { timeout })` is already a web-first,
   auto-retrying assertion** — Playwright re-reads the `class` attribute every poll tick
   until the matcher passes or the timeout expires. It is NOT a one-shot synchronous
   read. So `toHaveClass(/re/)` → `expect.poll(() => getAttribute("class")).toContain(...)`
   is two equivalent polling loops. The swap changes the *retry primitive*, not the
   *retry behavior* — it is a cosmetic no-op for flake resistance.
2. **A class assertion doesn't race a width transition.** The `md:w-14`/`md:w-56` class
   is present in the DOM the instant React re-renders on the state change; the 200 ms
   `transition-[width]` animates the pixel *value*, which only matters for `clientWidth`
   reads (the sibling drag tests, which correctly use `expect.poll(asideWidth)`).

The actual flake: **hydration-before-interaction.** The collapse toggle is a hydrated
client component; its `onClick` attaches at React hydration. The test clicked it with no
settle, so an early click hit a handler-less button → no-op → the rail never collapsed →
every downstream poll (whether `toHaveClass` or `expect.poll`) exhausted its 7 s window.
The sibling double-click and mobile-drawer tests already carry `await page.waitForTimeout(1500)`
before their first interaction; the « toggle test was the lone outlier.

## Solution

Add the missing `await page.waitForTimeout(1500)` hydration settle before the first
`toggle.click()` — the load-bearing fix. Do **not** add the `expect.poll` swap: it is
cosmetic, and for *class* assertions it diverges from the file's uniform `toHaveClass`
idiom and loses `toHaveClass`'s structured failure message (`getAttribute("class")` can
also return `null`, throwing inside the poll). Net diff: 1 settle line + comment.

## Key Insight

When an e2e assertion "never sees the expected class/state" on an interactive element,
suspect **the interaction was a no-op (pre-hydration click)** before suspecting the
assertion's retry primitive. The cure is settling for hydration before the click, not
polling harder after it. Web-first Playwright matchers (`toHaveClass`, `toBeVisible`,
`toHaveText`, …) already auto-retry — swapping them for `expect.poll` adds verbosity, not
liveness.

## Session Errors

- **Two review agents asserted false premises that nearly reverted a correct line for the
  wrong reason.** `code-simplicity-reviewer` claimed "zero existing `expect.poll` in the
  file" — but a single-line `grep "expect.poll"` MISSES the multi-line fluent-chain form
  the file actually uses (`await expect\n  .poll(...)` at lines 786/801). `code-quality-analyst`
  claimed the cited learning file "contains no string 'trap'" — a bad grep; it does
  (`## ... e2e traps`, "2. Hydration-before-interaction"). **Recovery:** verified both
  premises empirically with multi-line-aware reads before acting; the revert stood on
  independent grounds (cosmetic swap + class-assert idiom uniformity), not the false
  premises. **Prevention:** when a grep for `obj.method(` returns zero, re-check with a
  multi-line-aware search (`rg -U 'expect\s*\n?\s*\.poll'` or `grep -A1 'await expect$'`)
  before concluding a fluent-chain idiom is absent — fluent chains are commonly line-broken.
- **Playwright e2e is blocked-on-tool on ubuntu26.04-x64** (`Playwright does not support
  chromium on ubuntu26.04-x64`; bridged build crashes intermittently). **Recovery:** proved
  environmental via the unchanged hydration-protected sibling test (crashes identically at
  `page.goto`); deferred live verification to CI's containerized e2e job. **Prevention:**
  already the QA-skill posture (CI e2e is authoritative; local crash-at-navigation on
  untouched surface = env flake). One-off note, not a new rule.
- **Stale `.next/types` tsc false-positive** (`OmitWithTag` TS2344 in `(dashboard)/layout`).
  The Playwright `webServer` started `npm run dev`, generating `.next/types`. **Recovery:**
  `rm -rf .next` then re-run → clean. **Prevention:** already documented in the work skill.
- **Bash CWD drift** — repeated `cd apps/web-platform` and a tsc `EXIT=127`. **Recovery:**
  absolute paths. **Prevention:** already covered (Bash tool does not persist CWD reliably
  across calls).
- **`gh issue view 5698` → HTTP 401 in the planning subagent's environment.** **Recovery:**
  parent-session `gh` worked; confirmed #5698 OPEN before routing. **Prevention:** one-off
  (subagent-env-specific auth transient); not reproducible in the parent.
- **plan+deepen subagent emitted two plan files** (a 167-line pre-deepen + a 284-line
  deepened, differing only by slug). **Recovery:** removed the duplicate; used the
  subagent-reported path. **Prevention:** low-impact note — one-shot already extracts the
  reported plan path, so the stray file is cosmetic; not this PR's subsystem to fix.

## Tags
category: test-failures
module: apps/web-platform/e2e
