---
date: 2026-06-02
category: best-practices
tags: [skills, diff-predicate, gate, playwright, e2e, flake, false-green]
relates:
  - knowledge-base/project/learnings/best-practices/2026-06-02-visual-regression-gate-must-assert-content-not-band-box.md
  - knowledge-base/engineering/architecture/decisions/ADR-048-headless-visual-regression-gate.md
issue: 4834
pr: 4833
---

# A diff-path-gated skill step must diff against `origin/main`, not `origin/<branch>` — and a CI gate must FAIL on 5xx, never skip

Building the #4834 visual-regression gate, the silent-failure-hunter review caught
three holes that each would have made a brand-survival gate silently no-op. Two are
reusable beyond this feature.

## 1. `origin/<branch>...HEAD` returns 0 files once the branch is pushed → the gate never fires

The work/qa skill step gated on:

```bash
git diff --name-only origin/$(git rev-parse --abbrev-ref HEAD)...HEAD   # WRONG
```

`origin/<branch>` is the branch's OWN remote-tracking ref, so this diff shows only
**unpushed** commits. At `/qa` and `/ship` time the branch is always already pushed →
the diff returns **0 files** → the path predicate is false → the gate is skipped — on
the very PR that edits the files it's meant to guard. It "works" only in the brief
window before the first push, which is never when the gate actually runs.

**Rule:** a diff-path predicate that asks "does this *branch* touch path X?" MUST diff
against the integration base: `git diff --name-only origin/main...HEAD` (the merge-base
diff of branch vs main). Never `origin/<branch>...HEAD`. This applies to every
skill/hook/CI step that gates behavior on "did this branch change a sensitive path."

## 2. A CI gate that `test.skip()`s on a server error exits 0 → false-GREEN

The e2e helper called `test.skip(true, ...)` on a dashboard 5xx (a worktree-local
CSS-compile quirk). A *skipped* Playwright test is **not** a failure — `playwright test`
exits 0, and any "non-zero exit = fail" gate reads GREEN. In CI a real SSR break that
5xx'd every route would skip all tests and the brand-survival gate would report success
on a fully broken shell. **Rule:** branch the skip on `!process.env.CI`; in CI a 5xx
must `throw` (fail). A skip is a developer convenience, never a CI pass.

## 3. Per-route cold compile flakes the first hit — retry page-independently

The `authenticated` Playwright project's dev server compiles each route on first hit;
the first test to touch a route can `net::ERR_ABORTED` or have its async content lag.
A navigation retry helps, but `page.waitForTimeout()` inside the retry **throws
"Target page has been closed"** if a degraded server already tore the context down,
masking the real abort. Use a page-independent delay (`await new Promise(r =>
setTimeout(r, 1500))`) and give content assertions (async app-route fetches) a generous
timeout. CI's `retries: 1` absorbs the residual cold-compile flake; demonstrate GREEN
locally with `--retries=1` to match CI behavior rather than chasing a 0-retry clean run.

## Meta

All three were invisible to the plan-review panel (they're implementation-shaped) and
to the author (the wiring *read* correct). The silent-failure-hunter — prompted
specifically to hunt false-GREEN / never-fire modes on a brand-survival gate — is the
lens that catches "the gate that guards nothing." Always run it on a gate whose whole
job is to fail loudly.
