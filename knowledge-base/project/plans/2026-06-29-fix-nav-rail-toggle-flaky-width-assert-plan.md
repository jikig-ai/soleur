---
title: "fix: de-flake nav-rail « toggle e2e (width/glyph class asserts)"
issue: 5698
type: bug
brand_survival_threshold: none
lane: single-domain
date: 2026-06-29
---

## Enhancement Summary

**Deepened on:** 2026-06-29
**Sections enhanced:** Research Reconciliation (load-bearing finding), Research Insights (new)
**Gates run:** 4.6 User-Brand Impact (pass), 4.7 Observability (skip — test dir, not in Phase 2.9 production trigger set), 4.8 PAT-shaped (pass, no matches), 4.9 UI-wireframe (skip — no UI-surface file created/edited)

### Key Improvements
1. **Corrected the issue's root-cause framing.** Playwright's `toHaveClass(/re/)` is an auto-retrying web-first assertion (confirmed against installed `@playwright/test ^1.58.2`); the proposed `expect.poll(getAttribute("class")).toContain(...)` swap is an equivalent-polling near-no-op, NOT the cure. The actual flake is hydration-before-interaction (learning trap #2): the first `toggle.click()` lacks the 1500 ms settle that the sibling double-click (line 813) and mobile-drawer (line ~879) tests both carry.
2. **Made the settle the load-bearing change** and the `expect.poll` swaps a secondary, issue-honoring tweak — so the fix actually de-flakes rather than shuffling equivalent polling.
3. **Held scope tight** to the one named test; documented why the sibling and the lines-419–748 asserts stay untouched.

### New Considerations Discovered
- The sibling double-click test is already hydration-protected, which both confirms the diagnosis and answers the "verify both toggle states" learning (the other state needs no change).
- `gh` API was unavailable (401) this session; issue #5698 status is grounded in repo state only — re-confirm at /work or /ship.

# fix: de-flake the « toggle nav-rail e2e test (#5698)

🐛 **Bug (flaky test, not a product regression).** The Playwright test
`apps/web-platform/e2e/nav-states-shell.e2e.ts` →
`widenable KB rail — desktop › the « toggle button collapses/expands the rail and rotates its glyph`
(test body lines 826–851) intermittently fails inside its 7 s assertion windows.

## Overview

The named test clicks the collapse toggle and then asserts the rail's animated
width class and the glyph rotation class:

```ts
// apps/web-platform/e2e/nav-states-shell.e2e.ts (current, lines ~826–851)
const toggle = collapseToggle(page);              // line 830
await expect(toggle).toBeVisible({ timeout: 15_000 });
await expect(toggle).toHaveAccessibleName("Collapse sidebar");
await expect(toggle.locator("svg")).not.toHaveClass(/rotate-180/);

await toggle.click();                             // line 837  ← no hydration settle

await expect(aside).toHaveClass(/md:w-14/, { timeout: 7_000 });                       // 841
await expect(collapseToggle(page)).toHaveAccessibleName("Expand sidebar");
await expect(collapseToggle(page).locator("svg")).toHaveClass(/rotate-180/);          // 843
await expect(page.getByTestId("sidebar-reveal-button")).toHaveCount(0);
await expect(aside).not.toHaveClass(/md:w-0/);                                        // 847

await collapseToggle(page).click();
await expect(aside).toHaveClass(/md:w-56/, { timeout: 7_000 });                       // 850
```

The issue proposes replacing the synchronous `toHaveClass(/md:w-14/, {timeout})`
with a polling `expect.poll(() => aside.getAttribute("class"), {timeout}).toContain("md:w-14")`,
and applying the same to the `md:w-56` re-expand and the `rotate-180` glyph
asserts.

### Research Insights

**Playwright assertion semantics (grounded against installed `@playwright/test ^1.58.2`):**
- `expect(locator).toHaveClass(arg)` is a *web-first, auto-retrying* assertion: it
  polls the element's `class` attribute until the matcher passes or `timeout`
  expires. With a single `RegExp` arg it tests `regexp.test(element.className)`.
- `expect.poll(fn, { timeout }).toContain(s)` re-invokes `fn` each tick until the
  resolved value contains `s`. For a class-membership check the two are
  behaviorally equivalent polling loops — the swap is a readability/uniformity
  change, not a timing fix. (The file already standardizes on `expect.poll` for
  the *measured-width* asserts at lines ~786–803, where polling a `clientWidth`
  read genuinely matters because of the 200 ms width transition — learning trap #1.)
- **Implication:** the de-flake comes from the pre-click hydration settle, not the
  matcher choice. Implement both (the issue asks for the swap) but document the
  settle as load-bearing.

**Edge cases:**
- `getAttribute("class")` returns `string | null`; `.toContain` on `null` throws,
  which `expect.poll` retries. The targeted elements (`aside`, the toggle `<svg>`)
  persist across the toggle, so detachment is not a practical concern here.
- Negative asserts (`not.toHaveClass(/rotate-180/)` at line 835, `not.toHaveClass(/md:w-0/)`
  at line 847) are intentionally left as `toHaveClass` — an `expect.poll(...).not.toContain`
  inverts retry semantics (passes immediately and could mask a late-appearing class)
  with no benefit for these stable pre/post-state guards.

### Research Insights

**Playwright assertion semantics (grounded against `@playwright/test ^1.58.2`):**
- `expect(locator).toHaveClass(value)` is a **web-first, auto-retrying** assertion: Playwright re-queries the element's `class` attribute on each poll tick until it matches or the `timeout` elapses. It is not a one-shot synchronous read. Therefore swapping it for `expect.poll(() => locator.getAttribute("class")).toContain(...)` changes the *retry primitive* but not the *retry behavior* — both poll. Treat the swap as cosmetic/issue-honoring, not curative.
- `expect.poll(fn, { timeout }).toContain(substr)` is valid in 1.58.2 and is already the established idiom in this file (lines 786, 795, 803 poll `asideWidth`). Re-resolve the locator inside the poll callback (`collapseToggle(page).locator("svg").getAttribute("class")`) so each tick re-queries the live DOM.
- `getAttribute("class")` returns `Promise<string | null>`; on a transient `null` the `.toContain` throws and the poll retries — acceptable here since `aside`/`svg` persist across the toggle.

**Why the hydration settle is the real fix (learning trap #2 + same-file precedent):** the collapse toggle is a hydrated client component; clicking before React attaches `onClick` is a silent no-op, so the rail never collapses and every downstream poll (whether `toHaveClass` or `expect.poll`) exhausts its 7 s window. The fix is the same 1500 ms settle the sibling tests already use — established, low-risk, and consistent with the file's existing comments.

## Research Reconciliation — Issue Premise vs. Codebase Reality

| Issue claim | Reality (verified in repo) | Plan response |
| --- | --- | --- |
| "the synchronous `toHaveClass` read fires before the class settles (transition race)" | `expect(locator).toHaveClass(/re/)` is **auto-retrying** — Playwright re-reads the class attribute every poll tick until the matcher passes or the timeout expires. It is **not** a single synchronous read. So a `toHaveClass → expect.poll(getAttribute)` swap is a near-no-op equivalence; both poll. | Treat the swap as honoring the issue's explicit request and a marginal robustness/readability tweak, **not** the load-bearing cure. |
| "races the `md:transition-[width]` animation" | The 200 ms `transition-[width]` animates the *width pixel value*; the **class** `md:w-14`/`md:w-56` is present in the DOM the instant React re-renders on the state change. A *class* assertion does not race the width transition. (The transition race is real for `clientWidth` reads — that is the sibling drag tests at lines ~786–805, which already use `expect.poll(asideWidth)`.) | Width transition is irrelevant to this test's class asserts; do not cite it as the fix rationale. |
| "+ localStorage-hydration … read fires before the class settles" | **This is the real flake.** `toggle.click()` (line 837) fires with **no hydration settle**. The toggle is a client component whose `onClick` attaches at React hydration; an early click hits a handler-less button → no-op → the collapse never happens → `toHaveClass(/md:w-14/)` (and `expect.poll`) poll for the full 7 s and then fail. This is learning trap #2 (hydration-before-interaction). | **Load-bearing fix:** add `await page.waitForTimeout(1500)` before the first `toggle.click()`, matching the established same-file precedent. |

**Same-file precedent confirming the diagnosis (read, not inferred):**
- Sibling test `double-click the Settings grip…` (line 808) has
  `await page.waitForTimeout(1500)` before `handle.dblclick()` (line 813), with
  the comment *"The grip's onDoubleClick handler attaches at hydration; settle first."*
  It is therefore **already protected** and is **out of scope**.
- Mobile test `the close button still dismisses the drawer` (line ~879) has the
  same 1500 ms settle before `openBtn.click()`, commented
  *"Mirrors the widenable-rail drag tests' hydration wait."*
- The named test is the **lone outlier** that clicks a hydrated client toggle
  without settling first.

Conclusion: implement **both** changes per the issue's own
"(or settle hydration before asserting)" clause — the `waitForTimeout(1500)`
settle is the actual cure; the `expect.poll` swaps honor the issue text and are
harmless. Do **not** ship the `expect.poll` swap alone (it would leave the flake
live, and a reviewer would correctly flag it as equivalent to the code it replaces).

## User-Brand Impact

**If this lands broken, the user experiences:** nothing user-facing — this is a
test-only change to an e2e spec. A broken fix would leave a flaky CI signal
(false reds on the `nav-states` Playwright gate), costing engineering time, not
user trust.
**If this leaks, the user's data/workflow/money is exposed via:** N/A — no
runtime code, no data path, no auth surface touched.
**Brand-survival threshold:** none. _Reason: test-only change to
`apps/web-platform/e2e/nav-states-shell.e2e.ts`; no runtime, user-facing, or
data surface is modified._

## Files to Edit

- `apps/web-platform/e2e/nav-states-shell.e2e.ts` — the named test only
  (body lines 826–851):
  1. **Add hydration settle** before the first `await toggle.click();` (line 837):
     ```ts
     // The collapse toggle's onClick attaches at hydration; settle before the
     // first click so it is not a no-op (mirrors the sibling double-click and
     // mobile-drawer tests). See learning 2026-06-03 trap #2.
     await page.waitForTimeout(1500);
     await toggle.click();
     ```
  2. **Collapse width assert** (line 841): replace
     `await expect(aside).toHaveClass(/md:w-14/, { timeout: 7_000 });`
     with
     `await expect.poll(() => aside.getAttribute("class"), { timeout: 7_000 }).toContain("md:w-14");`
  3. **Glyph rotation assert** (line 843): replace
     `await expect(collapseToggle(page).locator("svg")).toHaveClass(/rotate-180/);`
     with
     `await expect.poll(() => collapseToggle(page).locator("svg").getAttribute("class"), { timeout: 7_000 }).toContain("rotate-180");`
  4. **Re-expand width assert** (line 850): replace
     `await expect(aside).toHaveClass(/md:w-56/, { timeout: 7_000 });`
     with
     `await expect.poll(() => aside.getAttribute("class"), { timeout: 7_000 }).toContain("md:w-56");`

**Explicitly NOT changed (scope boundary):**
- Line 829 `toHaveClass(/md:w-56/, 15_000)` — pre-interaction initial-render
  assert; not flaky, not named by the issue.
- Line 835 `not.toHaveClass(/rotate-180/)` — pre-click negative assert; the
  issue names "the `rotate-180` glyph check" = the post-collapse positive at 843.
  Leave as a stable `toHaveClass` (a negative `expect.poll(...).not.toContain`
  would invert retry semantics; no benefit).
- Line 847 `not.toHaveClass(/md:w-0/)` — full-hide-removed regression guard;
  not named, not flaky.
- The sibling `double-click the Settings grip…` test (lines 808–824) — already
  carries the 1500 ms settle; its `md:w-14`/`md:w-56` asserts at lines 816/822
  are not flaky for the hydration reason. No change (answers the
  "verify both toggle states" learning: the other state is already protected).
- The other `md:w-14`/`md:w-56` asserts at lines 419–748 (separate tests, 15 s
  timeouts) — out of scope; not named by #5698 and not reported flaky.

## Files to Create

- None.

## Open Code-Review Overlap

None. (No open code-review scope-out touches `nav-states-shell.e2e.ts`; `gh`
issue API was unavailable this session — see Premise Validation — so this is a
best-effort check.)

## Premise Validation

- **Branch safety:** `git branch --show-current` =
  `feat-one-shot-5698-nav-rail-flaky-width-assert` (not main/master). OK.
- **Cited file/symbol paths — all verified present on the working tree:**
  `apps/web-platform/e2e/nav-states-shell.e2e.ts` exists; the named test body
  is at lines 826–851; helpers `collapseToggle` (def line 374), `asideWidth`
  (line 370), `resizeHandle` (line 369), `RAIL_WIDTH_KEY` (line 35) all exist;
  `expect.poll` is already an established idiom in this file (e.g. lines 786,
  795, 803). The named asserts are at lines 841 (`md:w-14`), 843 (`rotate-180`),
  850 (`md:w-56`).
- **Cited learning file verified present and on-point:**
  `knowledge-base/project/learnings/ui-bugs/2026-06-03-dynamic-width-needs-css-var-not-tailwind-arbitrary-or-usemediaquery.md`
  — its "Playwright e2e for animated / hydration-dependent layout" section
  documents trap #1 (transition race on `clientWidth`) and trap #2
  (hydration-before-interaction); trap #2 is the one that applies here.
- **QA-skill animated-width note verified:** `plugins/soleur/skills/qa/SKILL.md:178`.
- **Issue #5698 status NOT API-verified:** `gh issue view 5698` returned
  `HTTP 401: Bad credentials` this session. The premise is grounded entirely in
  repo state (the flaky-shaped test exists exactly as the issue describes), which
  is sufficient for a test-only fix. /work or /ship should re-confirm the issue
  is open and reference it with `Closes #5698` once `gh` auth is restored.

## Acceptance Criteria

### Pre-merge (PR)
- [ ] **AC1 — settle added:** `grep -n "waitForTimeout(1500)" apps/web-platform/e2e/nav-states-shell.e2e.ts`
  returns a line that sits **between** the `await expect(toggle.locator("svg")).not.toHaveClass(/rotate-180/);`
  line and the first `await toggle.click();` of the named test (i.e. a third
  occurrence is added; the sibling and mobile occurrences remain).
- [ ] **AC2 — collapse assert converted:** the named test contains
  `expect.poll(() => aside.getAttribute("class"), { timeout: 7_000 }).toContain("md:w-14")`
  and no longer contains `toHaveClass(/md:w-14/` within its body (lines 826–851).
- [ ] **AC3 — re-expand assert converted:** the named test contains
  `expect.poll(() => aside.getAttribute("class"), { timeout: 7_000 }).toContain("md:w-56")`
  for the post-second-click assertion (the line-850 site).
- [ ] **AC4 — glyph assert converted:** the named test contains
  `expect.poll(() => collapseToggle(page).locator("svg").getAttribute("class"), { timeout: 7_000 }).toContain("rotate-180")`.
- [ ] **AC5 — scope held:** the sibling `double-click the Settings grip…` test
  and all `md:w-*` asserts at lines 419–748 are byte-for-byte unchanged
  (`git diff` touches only the named-test region).
- [ ] **AC6 — typecheck:** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`
  passes (no new errors attributable to the diff).
- [ ] **AC7 — test passes (stability):** the named test passes; run it repeatedly
  to confirm de-flake. Resolve the runner + invocation form in Phase 0 (see
  Sharp Edges — do not assume `bun test` / `npx playwright`).

## Test Scenarios

- Collapse path: click the (now-hydrated) toggle → rail class includes
  `md:w-14`, glyph class includes `rotate-180`, accessible name = "Expand sidebar".
- Re-expand path: second click → rail class includes `md:w-56`.
- Negative invariants preserved: no `sidebar-reveal-button`, no `md:w-0` class
  (unchanged asserts must still pass).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — test-only change to an e2e spec. No
UI-surface file is created or edited (the edit is a `.e2e.ts` test, not a
`components/**/*.tsx` / `page.tsx` / `layout.tsx`), so the mechanical UI-surface
override does not fire and the Product/UX Gate does not apply.

## Gate Disposition (skipped, with reason)

- **1.4 Network-outage checklist:** no SSH/network keywords. Skip.
- **2.5 Domain Review / Product-UX Gate:** no UI-surface file edited/created. NONE.
- **2.7 GDPR / Compliance:** no schema/auth/API/`.sql`/regulated surface. Skip.
- **2.8 IaC routing:** no server, secret, vendor, DNS, cron, or runtime process
  introduced. Skip.
- **2.9 Observability:** Files-to-Edit is `apps/web-platform/e2e/**` (a test
  dir), not under `apps/*/server/`, `apps/*/src/`, `apps/*/infra/`, and no infra
  surface is introduced. Skip.
- **2.10 ADR/C4:** no architectural decision — a competent engineer reading the
  existing ADRs/C4 would not be misled after this change. Skip.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan`
  Phase 4.6. This plan's section is filled (threshold `none` + reason).
- **Do not ship the `expect.poll` swap alone.** `toHaveClass(/re/)` already
  auto-retries; the swap without the `waitForTimeout(1500)` settle leaves the
  hydration flake live. The settle is the load-bearing change (see Research
  Reconciliation).
- **Runner/invocation must be resolved in Phase 0, not assumed.** This is a
  Playwright e2e spec, not a vitest unit test. Determine the exact command from
  `apps/web-platform/package.json` `scripts` (look for the playwright/e2e
  script) before running — do not hardcode `bun test` (the package uses vitest
  for unit, and `apps/web-platform/bunfig.toml` blocks `bun test` discovery) or
  guess `npx playwright test`.
- **Glyph poll targets a nested locator behind interaction.** The `rotate-180`
  class is on the toggle's `<svg>`, which only carries that class **after** the
  click has flipped state; the `expect.poll` window (7 s) plus the new hydration
  settle covers the timing. Keep the poll on
  `collapseToggle(page).locator("svg").getAttribute("class")`, re-resolving the
  locator each tick (matches the existing `collapseToggle(page)` re-query style
  at lines 842–843).
- **`getAttribute("class")` can return `null`** if the element detaches; `.toContain`
  on `null` throws inside the poll and is retried — acceptable, but the element
  here is stable (`aside`/`svg` persist across the toggle). No special-casing needed.
