---
title: "fix(chat): Concierge status box text overflows card right border"
type: fix
date: 2026-06-03
branch: feat-one-shot-concierge-box-text-overflow
lane: single-domain
brand_survival_threshold: aggregate pattern
---

# 🐛 Fix Concierge status box text overflow

## Enhancement Summary

**Deepened on:** 2026-06-03
**Sections enhanced:** Approach (Research Insights), Files to Create, Acceptance
Criteria, Observability, Phase 0, Risks (R4).
**Method:** Inline deepen (Task-tool parallel agents unavailable in this
environment); all findings verified live via `grep`/config-read against the
worktree. Deepen halt gates 4.6 (User-Brand Impact), 4.7 (Observability), 4.8
(PAT-shaped), 4.9 (UI-wireframe) all PASS.

### Key Improvements

1. **Corrected the Playwright test path (load-bearing).** v1 prescribed
   `apps/web-platform/test/<...>.spec.ts`, which would be **silently skipped** —
   Playwright here uses `testDir: "./e2e"` + `testMatch: "**/*.e2e.ts"`
   (`playwright.config.ts:13-14`), and the bubble tests require the
   `authenticated` project restricted to `cc-soleur-go-*` / `start-fresh-*` /
   `nav-states-*` (`:48-53`). The test must be `e2e/cc-soleur-go-*.e2e.ts` (or
   extend `e2e/cc-soleur-go-bubbles.e2e.ts`). This is the #3743 testMatch-drift
   class — catching it here saves a mid-`/work` pivot AND prevents shipping a
   verification that never runs.
2. **Pinned the overflow-assertion precedent.** `e2e/nav-states-shell.e2e.ts:259,277`
   already implements `scrollWidth - clientWidth` overflow checks with an
   empty-band guard (`:19`). The new test reuses it verbatim — no novel assertion.
3. **Verified the CSS mechanism against codebase precedent.** `[overflow-wrap:anywhere]`
   is already used at `message-bubble.tsx:242` and `:269`; Option A is a
   convention match, and the `min-w-0` ancestor chain (`:157/159/165`) is what
   actually prevents #4852's premature wrap from returning — not `whitespace-nowrap`.

### New Considerations Discovered

- The existing `e2e/cc-soleur-go-bubbles.e2e.ts` already wires `attachWsInjector`
  + Supabase mocks to drive the real reducer's routing bubble — extending it is
  cheaper than a fresh harness.
- jsdom returns 0 for layout values (constitution line 312), so the vitest test
  can only assert the className mechanism; the actual overflow proof is e2e-only.

---

The Soleur Concierge status box ("Soleur Concierge" header + "Working" badge +
status label such as "Routing to the right experts...") renders the status label
on a single forced line that **overflows past the right border** of the bordered
Concierge card when the label is wider than the bubble's max-width cap.

This is the **inverse failure mode** of the regression PR #4852 (merged, commit
`7c44c9e8`) fixed. #4852 added `whitespace-nowrap` to the chip label to stop
*premature* wrapping (the label wrapped to two lines even when horizontal space
was available — a flex min-content collapse). That fix shipped bare
`whitespace-nowrap` with no upper bound, so now when the label is *longer* than
the bubble max-width (`max-w-[90%]`/`md:max-w-[80%]`, line 159), `nowrap` forces
the text to overflow the card instead of wrapping. The same plan even named this
risk (`2026-06-02-fix-concierge-prefill-400-tool-approval-and-status-box-wrap-plan.md`
**R4**: "`whitespace-nowrap` on the wrong element could clip long status labels
off-screen") but the shipped code never implemented R4's "wraps at the cap"
mitigation.

The fix must satisfy **both** constraints simultaneously:
1. Short labels keep their natural single-line width (do not re-break #4852 —
   no premature wrap when space is available).
2. Labels wider than the bubble max-width **wrap** (or otherwise stay contained)
   instead of overflowing the right border.

## Root Cause

`apps/web-platform/components/chat/message-bubble.tsx:24-30` — `ToolStatusChip`:

```tsx
export function ToolStatusChip({ label }: { label: string }) {
  return (
    <div className="flex items-center gap-2 py-0.5" data-testid="tool-status-chip">
      <span className="whitespace-nowrap text-sm text-soleur-text-secondary">{label}</span>
    </div>
  );
}
```

The bubble container (line 159) is `flex min-w-0 max-w-[90%] gap-3 md:max-w-[80%]`
and the inner card (line 165) is `relative min-w-0 ...`. With `whitespace-nowrap`
on the label **and** a hard `max-w` cap **and** `min-w-0`, the only remaining
degree of freedom is overflow: the text cannot wrap (nowrap) and the box cannot
grow past the cap → it spills past the right border.

Note the **leader-header primary span** (line 193, "Soleur Concierge" / "CMO
Riley") also carries `whitespace-nowrap` from #4852. Leader names are short and
asserted single-line by `message-bubble-header.test.tsx:128-141`. **Do not touch
line 193** — it is not the overflow culprit and its nowrap is intentional.

## Research Reconciliation — Spec vs. Codebase

| Claim (from issue / prior plan) | Reality (verified on branch) | Plan response |
|---|---|---|
| #4852 fixed "status box wrap" | Merged (commit `7c44c9e8`); added bare `whitespace-nowrap` at `message-bubble.tsx:27` + `:193` | Fix the *inverse* failure mode (#4852's own R4 risk, never mitigated in code) at line 27 only |
| #4852 plan said bubble gets `w-fit` for routing-chip case (plan line 104) | `grep -n "w-fit" message-bubble.tsx` → **no match**; `w-fit` never shipped | The grow-then-wrap mechanism was never implemented; this plan implements it |
| Overflow is in "the Concierge card" | Originates in `ToolStatusChip` label span (line 27), rendered inside the `tool_use` bubble path (line 264-266) | Scope fix to the chip label span |
| Existing test enforces `whitespace-nowrap` on the chip | `message-bubble-tool-status-chip.test.tsx:71-83` (#4852) asserts `labelSpan.className` contains `"whitespace-nowrap"` | This test MUST be updated to the new mechanism, not silently broken |
| Header span also has `whitespace-nowrap` | True (line 193); `message-bubble-header.test.tsx:128-141` asserts it for leader names | Out of scope — leader names are short; keep nowrap on line 193 |
| Both render variants affected | `variant: "full"` (chat-surface) + `variant: "sidebar"` (`kb-chat-content.tsx:178`, narrower container → overflow MORE likely) | Verify the fix in both variants (Playwright) |

**Premise Validation:** All cited artifacts verified present on the branch.
`ToolStatusChip` exists at `message-bubble.tsx:24-30`; the call site is
`chat-surface.tsx:744-754` (`isClassifying` routing chip, `toolLabel="Routing to
the right experts..."`) and the general `tool_use` path at `message-bubble.tsx:264-266`.
PR #4852 confirmed MERGED. The bug is **broken behavior of a shipped component**,
not a never-built feature — this is a patch, not a build. No external premise is
stale.

## User-Brand Impact

- **If this lands broken, the user experiences:** the Soleur Concierge status text
  ("Routing to the right experts...") spilling past the right border of the
  Concierge card on the chat/Dashboard — the brand-visible `/soleur:go` front
  door — looking visually broken / unpolished on every in-flight turn whose
  status label exceeds the bubble width (more pronounced in the narrow sidebar
  variant).
- **If this leaks, the user's data is exposed via:** N/A — this is a presentational
  CSS-only change. No data, auth, or workflow surface is touched. The status label
  is non-PII UI copy already rendered to the user.
- **Brand-survival threshold:** `aggregate pattern` — cosmetic overflow degrades
  perceived polish across all users who see a long status label; no single-user
  incident, no data exposure. (Sensitive-path note: the diff touches only
  `apps/web-platform/components/chat/*.tsx` + `apps/web-platform/test/*.test.tsx`;
  no schema/auth/API/migration surface, so no preflight Check-6 scope-out bullet
  is required.)

## Observability

This plan touches `apps/web-platform/components/**` (client React/CSS) only — no
server, infra, or new runtime surface. Per plan Phase 2.9, a presentational
CSS-only change to an existing client component carries no new failure mode that
requires liveness/error wiring. The "observability" for a CSS layout fix is the
visual regression assertion itself:

```yaml
liveness_signal:
  what: "Playwright deterministic screenshot of the Concierge tool_use bubble (long-label case)"
  cadence: per-PR (CI Playwright run on the affected route)
  alert_target: PR CI status (red on visual/structural regression)
  configured_in: apps/web-platform/e2e/cc-soleur-go-bubbles.e2e.ts (extend) or e2e/cc-soleur-go-status-overflow.e2e.ts (new) — authenticated Playwright project
error_reporting:
  destination: N/A — no runtime error path added; client render is presentational
  fail_loud: CI test failure (vitest className assertion + Playwright no-clip assertion)
failure_modes:
  - mode: "long status label overflows card right border"
    detection: Playwright assertion that label scrollWidth <= card clientWidth (or no horizontal overflow), run in CI
    alert_route: PR author via red CI check
  - mode: "short label regresses to premature wrap (re-break #4852)"
    detection: Playwright assertion that a short label renders on a single line when space is available
    alert_route: PR author via red CI check
logs:
  where: N/A — no server log surface; CI test output only
  retention: CI run retention (GitHub Actions default)
discoverability_test:
  command: "cd apps/web-platform && ./node_modules/.bin/vitest run test/message-bubble-tool-status-chip.test.tsx"
  expected_output: "all tests pass — chip label carries the wrap-capable mechanism (not whitespace-nowrap-only)"
```

## Approach

The canonical CSS pattern for "single line when it fits, wrap when it doesn't" is
to let the text wrap on overflow rather than forcing nowrap. The bubble already
demonstrates this exact pattern for the streaming body at
`message-bubble.tsx:269`: `min-w-0 whitespace-pre-wrap [overflow-wrap:anywhere]`.

Two candidate mechanisms (the implementer picks ONE; **Option A is recommended**
as the simplest and matching existing convention):

- **Option A (recommended) — wrap-on-overflow:** Replace `whitespace-nowrap` on
  the chip label (line 27) with `[overflow-wrap:anywhere]` (or `break-words`),
  matching the line-269 body pattern. Short labels stay on one line naturally
  (the flex parent + `min-w-0` already give the bubble content width up to the
  cap); long labels wrap at the cap instead of overflowing. This is the smallest
  diff and reuses the codebase's established wrap idiom.
  - **#4852-regression guard:** #4852's premature wrap was a *flex min-content
    collapse*, not a `whitespace-normal` issue — the chip `<div>` is already
    `flex items-center` and the label is the only child, so removing nowrap does
    NOT reintroduce the min-content collapse (which was about the bubble width,
    addressed by the existing `min-w-0` chain). The implementer MUST verify the
    short-label single-line behavior in Playwright (both variants) to prove #4852
    is not re-broken.

- **Option B (fallback) — grow-then-wrap with `w-fit`:** Keep `whitespace-nowrap`
  on the label but give the **bubble card** (line 165) `w-fit` so it grows to the
  label's natural single-line width, bounded by the existing `max-w` cap, then
  the label wraps once it hits the cap. This implements the #4852 plan's
  never-shipped `w-fit` intent (plan line 104). Larger blast radius (changes
  bubble width semantics for ALL bubble states, not just the chip), so prefer A
  unless A's short-label behavior cannot be verified.

**Decision criterion:** Ship Option A. Fall back to B only if Playwright shows A
regresses the short-label single-line case. Whichever ships, the existing chip
test assertion (`message-bubble-tool-status-chip.test.tsx:82`) must be updated to
assert the chosen mechanism (`[overflow-wrap:anywhere]`/`break-words` for A; the
bubble `w-fit` class for B) — **never delete the regression intent**, re-point it.

### Research Insights

**CSS mechanism — why Option A is correct and low-risk:**

- `[overflow-wrap:anywhere]` (CSS `overflow-wrap: anywhere`) instructs the layout
  engine to break a line only when the content would otherwise overflow its
  container; it does NOT force breaks when the content fits. So a short label
  ("Working") on a flex parent with available width stays on one line, while a
  long label wraps at the bubble's `max-w` cap. This is precisely the
  "single-line-when-it-fits, wrap-when-it-doesn't" semantic the bug requires, and
  it is the idiom the codebase already uses (verified `grep -n "overflow-wrap:anywhere"`)
  at exactly two sites: the user-bubble wrapper (`message-bubble.tsx:242`,
  `min-w-0 [overflow-wrap:anywhere]`) and the streaming body (`:269`,
  `min-w-0 whitespace-pre-wrap [overflow-wrap:anywhere]`). Adopting it on the chip
  label is a convention match, not a novel pattern.
- Subtle distinction vs. `whitespace-normal`: the chip label currently has
  `whitespace-nowrap`. Removing it returns the span to the default `whitespace:
  normal`, under which `overflow-wrap:anywhere` governs break points. `break-words`
  (`overflow-wrap: break-word`) is a near-equivalent; prefer `[overflow-wrap:anywhere]`
  for exact parity with line 269 (it also breaks within an unbroken long token,
  which a status label generally is not, but the parity keeps the codebase
  uniform).
- **#4852 non-regression mechanism (why A does not re-break the premature wrap):**
  #4852's premature wrap was a *flex min-content collapse of the bubble width* —
  the bubble shrank to its min-content and the label wrapped even with room. That
  was already addressed by the `min-w-0` chain on the flex ancestors
  (`message-bubble.tsx:157, 159, 165`), which lets the bubble take content width up
  to the `max-w` cap. `whitespace-nowrap` was an over-correction on top of that.
  With the `min-w-0` chain intact, the bubble still grows to content width; the
  only behavior change from dropping `nowrap` is that a label *exceeding* the cap
  now wraps instead of overflowing. The Playwright short-label single-line
  assertion is the empirical proof obligation.

**Precedent-diff (Phase 4.4) — overflow-assertion pattern:**

- `git grep "scrollWidth - .*clientWidth" apps/web-platform/e2e/` →
  `e2e/nav-states-shell.e2e.ts:259,277`. Canonical form:
  `await el.evaluate((el) => el.scrollWidth - el.clientWidth)` with an explicit
  empty-band guard (`:19` comment) so a collapsed/empty element cannot vacuously
  pass `scrollWidth <= clientWidth`. The new test reuses this verbatim — no novel
  assertion shape. **No precedent diverges**; the pattern is established.

**No external framework research required:** this is a Tailwind/CSS layout fix on
an existing component using idioms already present three times in the same file;
Context7/WebSearch would add nothing the codebase precedent does not already pin.

## Files to Edit

- `apps/web-platform/components/chat/message-bubble.tsx` — `ToolStatusChip` label
  span at **line 27** only (Option A: swap `whitespace-nowrap` → wrap-capable
  class; Option B: add `w-fit` to the bubble card at line 165 and leave line 27).
  **Do NOT touch line 193** (leader-header span — intentional nowrap for short
  leader names).
- `apps/web-platform/test/message-bubble-tool-status-chip.test.tsx` — update the
  #4852 regression test at **lines 71-83**. Re-point the `whitespace-nowrap`
  className assertion to the new mechanism. Add a RED→GREEN structural assertion
  that the label span carries the wrap-capable class. Keep the three existing
  passing tests (single child, verbatim label, "Working" pill, active border)
  intact.

## Files to Create / Extend (Playwright)

- **Extend `apps/web-platform/e2e/cc-soleur-go-bubbles.e2e.ts`** (preferred) OR
  create **`apps/web-platform/e2e/cc-soleur-go-status-overflow.e2e.ts`** —
  deterministic browser test that drives the Concierge `tool_use`/routing bubble
  via the existing `attachWsInjector` WS-frame harness (NOT a fresh mount) with a
  long status label, then asserts **no horizontal overflow** of the card, AND a
  short label renders single-line. Run in BOTH `full` and `sidebar` variants.

  **CORRECTED at deepen-plan (was wrong in v1):** Playwright in this app uses
  `testDir: "./e2e"` + `testMatch: "**/*.e2e.ts"` (`playwright.config.ts:13-14`).
  A `test/*.spec.ts` file (v1's path) would be **silently skipped** — it matches
  neither the dir nor the glob (the #3743 testMatch-drift class). The bubble
  tests additionally require the `authenticated` project, whose `testMatch` is
  `["**/start-fresh-*.e2e.ts", "**/cc-soleur-go-*.e2e.ts", "**/nav-states-*.e2e.ts"]`
  (`playwright.config.ts:48-53`) — so the filename MUST start with `cc-soleur-go-`
  (or extend the existing `cc-soleur-go-bubbles.e2e.ts`, the cleanest option since
  it already wires `attachWsInjector` + Supabase mocks for the routing bubble).

  **Overflow assertion — reuse the existing precedent.** `e2e/nav-states-shell.e2e.ts:259,277`
  already does `el.evaluate((el) => el.scrollWidth - el.clientWidth)` and documents
  the empty-band pitfall (line 19: "an empty band would satisfy
  `scrollWidth<=clientWidth`, so we ALSO assert the band [is populated]"). Mirror
  this: assert `card.scrollWidth - card.clientWidth <= <tolerance>` for the long
  label AND assert the label element is non-empty / has the expected text, so an
  empty/collapsed card cannot vacuously pass. (Per constitution line 312,
  jsdom/vitest returns 0 for layout values — the overflow assertion MUST live in
  Playwright; vitest only asserts the className mechanism.)

## Open Code-Review Overlap

None checked at plan-write time (Task-tool research agents unavailable in this
environment). deepen-plan / one-shot review phase should run the standard
`gh issue list --label code-review --state open` overlap check against the two
edited files (`message-bubble.tsx`, `message-bubble-tool-status-chip.test.tsx`).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `message-bubble.tsx` chip label span (line 27) no longer forces a single
      line on overflow: it carries the wrap-capable mechanism (Option A:
      `[overflow-wrap:anywhere]` or `break-words`; Option B: bubble `w-fit` +
      `max-w` cap). Verify with `grep -n "overflow-wrap:anywhere\|break-words\|w-fit" apps/web-platform/components/chat/message-bubble.tsx`.
- [ ] Line 193 (leader-header span) is unchanged — still `whitespace-nowrap`.
      Verify `message-bubble-header.test.tsx:128-141` still passes.
- [ ] `message-bubble-tool-status-chip.test.tsx` updated: the #4852 assertion at
      line 82 now asserts the new mechanism (no orphaned `whitespace-nowrap`
      expectation on the chip label). All 5 tests in the file pass.
- [ ] New/extended Playwright **e2e** test (`e2e/cc-soleur-go-*.e2e.ts`, authenticated
      project) asserts **no horizontal overflow** of the Concierge card
      (`card.scrollWidth - card.clientWidth <= tolerance` AND label non-empty, per
      the `nav-states-shell.e2e.ts:259,277` precedent) for a long status label, in
      BOTH `full` and `sidebar` variants.
- [ ] Same e2e test asserts a short label renders single-line when space is
      available (proves #4852 not re-broken).
- [ ] The new test FILE matches `testMatch` — `ls apps/web-platform/e2e/cc-soleur-go-*.e2e.ts`
      includes it (or it lives inside the existing `cc-soleur-go-bubbles.e2e.ts`).
- [ ] `cd apps/web-platform && ./node_modules/.bin/vitest run test/message-bubble-tool-status-chip.test.tsx test/message-bubble-header.test.tsx` is green.
- [ ] `tsc --noEmit` clean for `apps/web-platform`.

### Post-merge (operator)

- None — pure client CSS change deployed by the standard `web-platform-release.yml`
  pipeline on merge to main (path-filtered `apps/web-platform/**`).

## Test Scenarios

- Given the Concierge `tool_use` bubble with `toolLabel="Routing to the right
  experts..."`, when rendered in the narrow `sidebar` variant, then the label
  wraps inside the card and no text crosses the card's right border (Playwright).
- Given the same bubble with a short label ("Working"), when there is horizontal
  space, then the label stays on a single line (Playwright — #4852 non-regression).
- Given the `tool_use` chip, when rendered (jsdom/vitest), then the label span's
  className contains the wrap-capable mechanism and NOT `whitespace-nowrap`
  (structural assertion; no layout-engine gating per constitution line 312).
- Given the leader-header for `cc_router`, when rendered, then "Soleur Concierge"
  stays single-line (existing `message-bubble-header.test.tsx` unchanged).

## Domain Review

**Domains relevant:** Product (UI surface)

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none (Task tool unavailable in this planning environment; the
one-shot review phase + deepen-plan handle agent spawning)
**Skipped specialists:** none — this is a CSS-only wrap fix to an **existing**
component (no new user-facing page, flow, or interactive surface), so it is
ADVISORY not BLOCKING; `ux-design-lead`/`.pen` wireframes are not required for a
presentational overflow fix to an existing component (matches the #4852 plan's own
classification: "non-wrapping/width tweak to the existing Concierge status chip —
ADVISORY").
**Pencil available:** N/A — no new UI surface (CSS-only wrap change to an existing
component).

#### Findings

The mechanical UI-surface override fires (`components/**/*.tsx` in Files to Edit),
forcing Product-relevant = true. However, no NEW file matches
`components/**/*.tsx` / `app/**/page.tsx` / `app/**/layout.tsx` in Files to
**Create** (the only new file is an `.e2e.ts` Playwright test), so the mechanical BLOCKING
escalation does not fire. The change modifies an existing component's wrap
behavior without adding any interactive surface → ADVISORY. In pipeline context
ADVISORY auto-accepts.

## Risks & Mitigations

- **R1 — Option A reintroduces #4852's premature wrap.** The #4852 wrap was a flex
  min-content collapse of the *bubble width*, fixed by the `min-w-0` chain (lines
  157/159/165), not by `whitespace-nowrap` per se. *Mitigation:* the Playwright
  short-label single-line assertion (both variants) is a required AC; if it fails,
  fall back to Option B (`w-fit` grow-then-wrap).
- **R2 — touching line 193 breaks the leader-name single-line invariant.**
  *Mitigation:* scope explicitly excludes line 193; `message-bubble-header.test.tsx`
  guards it.
- **R3 — jsdom test silently no-ops on overflow.** jsdom returns 0 for
  `clientWidth`/`scrollWidth` (constitution line 312). *Mitigation:* the overflow
  assertion lives in Playwright; vitest asserts only the className mechanism.
- **R4 — Playwright test filename misses the project `testMatch` glob** (AGENTS.md
  Sharp Edge / #3743). **RESOLVED at deepen-plan:** config verified —
  `testDir: ./e2e`, `testMatch: **/*.e2e.ts`, authenticated project restricted to
  `cc-soleur-go-*` / `start-fresh-*` / `nav-states-*`. The plan now prescribes
  `e2e/cc-soleur-go-*.e2e.ts` (or extending `cc-soleur-go-bubbles.e2e.ts`). The
  v1 `test/*.spec.ts` path would have been silently skipped — the exact bug class
  R4 names.
- **R5 — fix verified in only one render variant.** The bug is more visible in the
  narrow `sidebar` variant (`kb-chat-content.tsx:178`). AGENTS.md Sharp Edge:
  "verify alignment in both toggle/render states." *Mitigation:* Playwright runs
  both `full` and `sidebar` as required ACs.

## Phase 0 (work-time preconditions — grep before editing)

1. `grep -n "whitespace-nowrap" apps/web-platform/components/chat/message-bubble.tsx`
   → confirm exactly two sites (line 27 chip, line 193 header); edit only line 27.
2. **VERIFIED at deepen-plan:** `apps/web-platform/playwright.config.ts:13-14`
   → `testDir: "./e2e"`, `testMatch: "**/*.e2e.ts"`; the `authenticated` project
   (`:48-53`) restricts to `**/cc-soleur-go-*.e2e.ts` (+ `start-fresh-*`,
   `nav-states-*`). The new test MUST be `e2e/cc-soleur-go-*.e2e.ts` or extend
   `e2e/cc-soleur-go-bubbles.e2e.ts`. (Do not use `test/*.spec.ts` — silently
   skipped.)
3. `grep -n "include" apps/web-platform/vitest.config.ts` → confirm the updated
   `.test.tsx` is collected by `test/**/*.test.tsx` (it already lives there).
4. Re-read `message-bubble.tsx:24-30, 155-175, 264-269` to confirm line numbers
   have not drifted since plan-write.

## Implementation Phases

1. **Phase 0** — run the Phase 0 grep preconditions above.
2. **Phase 1 (RED)** — update `message-bubble-tool-status-chip.test.tsx` to assert
   the wrap-capable mechanism on the chip label (fails against current
   `whitespace-nowrap`). Add the Playwright spec (fails / overflows against current
   code).
3. **Phase 2 (GREEN)** — apply Option A to `message-bubble.tsx:27`. Re-run vitest
   + Playwright. If the short-label single-line Playwright assertion fails, switch
   to Option B (`w-fit` at line 165) and update the test assertion accordingly.
4. **Phase 3 (verify)** — `tsc --noEmit`; full `message-bubble-*` + `cc-routing-panel-concierge-visibility` suites green; Playwright both variants green.

## References

- Prior plan (the regression this reconciles against):
  `knowledge-base/project/plans/2026-06-02-fix-concierge-prefill-400-tool-approval-and-status-box-wrap-plan.md`
  (R4 risk named, never mitigated in code)
- PR #4852 (merged, commit `7c44c9e8`) — added the `whitespace-nowrap` that causes
  this inverse overflow.
- Component: `apps/web-platform/components/chat/message-bubble.tsx:24-30` (chip),
  `:159-169` (bubble width), `:264-266` (tool_use render path), `:269` (existing
  wrap-on-overflow idiom to mirror).
- Call site: `apps/web-platform/components/chat/chat-surface.tsx:744-754`.
- Narrow variant: `apps/web-platform/components/chat/kb-chat-content.tsx:178`.
- Constitution conventions: line 312 (no jsdom layout-gated assertions), line 318
  (RED/GREEN/REFACTOR), line 302 (worktree vitest invocation).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan`
  Phase 4.6. (This plan's section is filled; threshold = `aggregate pattern`.)
- Do not assert overflow in jsdom/vitest — `clientWidth`/`scrollWidth` return 0
  (constitution line 312). Overflow assertions are Playwright-only.
- Verify the fix in BOTH render variants (`full` + `sidebar`) — the bug is more
  visible in the narrow sidebar; an alignment/wrap fix verified in one state can
  leave the other broken (AGENTS.md both-toggle-states Sharp Edge).
- Do not touch the leader-header `whitespace-nowrap` (line 193) — it is guarded by
  `message-bubble-header.test.tsx` and is the correct behavior for short leader
  names.
