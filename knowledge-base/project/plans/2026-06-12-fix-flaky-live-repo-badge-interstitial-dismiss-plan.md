---
title: "fix(test): flaky live-repo-badge revocation-interstitial dismiss (vacuous absence-wait)"
date: 2026-06-12
type: fix
issue: 5234
branch: feat-one-shot-fix-flaky-live-repo-badge-interstitial-5234
lane: single-domain
status: planned
---

# 🐛 fix(test): flaky `live-repo-badge.test.tsx:155` — dismiss assertion races async removal

## Enhancement Summary

**Deepened on:** 2026-06-12

**Gate checks (all pass):** 4.6 User-Brand Impact present (threshold `none`,
test-only path → not sensitive, no scope-out needed); 4.7 Observability present
(test-only Files-to-Edit → Phase 2.9 skip, documented); 4.8 no PAT-shaped
variables; 4.9 no UI-surface file in scope (production component untouched) →
no `.pen` required.

**Key correction discovered at deepen time (verify-the-negative pass):** the
plan v1 cited line 114 as a *precedent* for the absence-poll fix. Live grep
proved line 114 is itself a **bare synchronous post-dismiss absence assertion** —
the SAME vacuous-wait race as line 155, not a precedent. The fix scope grew from
1 site to 2: both line 155 (reported) and line 114 (same-class sibling, not yet
flaked but identically armed) are folded into one PR. Lines 53/125 verified
OUT of scope — they carry upstream `pollCommitted`/`regainCommitted` settle
anchors and are already correct.

**Live-verified facts pinned into the plan:** issue #5234 is OPEN
(`gh issue view 5234`); the cited learning file resolves; `vi` is imported
(line 1); the test path matches the `component` project glob
`test/**/*.test.tsx` (`vitest.config.ts:60`); runner is
`apps/web-platform/node_modules/.bin/vitest`; `configure({ asyncUtilTimeout: 10_000 })`
present at `test/setup-dom.ts:11` (does NOT reach `vi.waitFor`).

## Overview

`apps/web-platform/test/live-repo-badge.test.tsx` line 155 asserts
`expect(interstitial).not.toBeInTheDocument()` **synchronously** on the line
immediately following `fireEvent.click(dismiss)`. The component's dismissal is a
React state update (`setDismissed(true)` → re-render → `return null`). Under
full-suite parallel load (`TEST_GROUP=webplat bash scripts/test-all.sh`, ~760
files) the forked worker can be CPU-starved between `fireEvent.click` flushing
and the assertion tick, so the interstitial node is still attached at the moment
of assertion and the test flakes red. In isolation it passes (the re-render
flushes within the same microtask window).

This is the **vacuous-absence-wait class** documented in
`knowledge-base/project/learnings/test-failures/2026-06-10-parallel-load-flake-two-mechanisms-and-vacuous-absence-waits.md`
(Key Insight 3): a bare absence check is not anchored on a positive settle
signal, so it asserts at an arbitrary tick rather than after the state commit.

The fix: wrap the absence assertion in a poll so it retries until the removal
commits. Concretely:

```tsx
// apps/web-platform/test/live-repo-badge.test.tsx — the "dismissing the interstitial hides it" case
await vi.waitFor(() =>
  expect(screen.queryByTestId("revocation-interstitial")).toBeNull(),
);
```

Note on anchoring: the canonical learning recommends a positive settle flag
(`.finally(() => { settled = true; })`) for **poll-driven absence** (where the
element appears *because* an async fetch resolved, then you assert it stays
absent). Here the disappearance is driven by a *synchronous user event*
(`fireEvent.click`), not by a fetch settling — there is no fetch body to flag.
The correct anchor is therefore the React commit itself: `vi.waitFor` retries
`queryByTestId(...).toBeNull()` until the `setDismissed(true)` re-render removes
the node. This is not vacuous here because the interstitial is **present** at the
start of the wait (the click has not yet flushed the unmount), so the first tick
can legitimately fail and the poll proves "absent AFTER the commit." This is the
exact shape already used at line 114 of this file.

**Why `vi.waitFor` and not RTL `waitForElementToBeRemoved`:** the file already
standardizes on `vi.waitFor` (lines 48, 122, 130) and `screen.queryByTestId`
(lines 53, 54, 74, 114, 125). Staying with `vi.waitFor` keeps the file
internally consistent and avoids importing a new RTL helper.

**Same-class sibling — line 114 (`re-arms…` test).** Verification at deepen time
found that line 114 (`expect(screen.queryByTestId("revocation-interstitial")).toBeNull()`
immediately after `fireEvent.click(dismiss)` on line 113) is the **same vacuous
post-dismiss absence assertion** as line 155 — it is NOT wrapped in `vi.waitFor`.
The `vi.waitFor` sites at lines 48/122/130 all anchor on a *fetch settle flag*
(`pollCommitted`/`regainCommitted`) or on element *appearance*, none on a
post-dismiss absence. Line 114 has not yet flaked in the issue report, but it is
the identical race and will eventually flake under the same contention. Per
`hr-write-boundary-sentinel-sweep`-style class-completeness discipline (and the
review-backlog net-positive pattern), **fold line 114 into the same PR** — fixing
only line 155 leaves a known same-class flake armed. See AC1b / Files-to-Edit. The global
`configure({ asyncUtilTimeout: 10_000 })` in `test/setup-dom.ts:11` does NOT
apply to `vi.waitFor` (vitest and RTL have independent config surfaces — Key
Insight 2), but `vi.waitFor`'s 1000 ms default is ample for a synchronous
state-commit re-render even under contention (the failure mode is a *single
missed tick*, not a multi-second stall). No per-call `{ timeout }` bump is
needed; the other `vi.waitFor` sites in this file carry `{ timeout: 10_000 }`
only because they await an async *fetch* resolution, which this assertion does
not.

## Research Reconciliation — Spec vs. Codebase

| Premise (issue body) | Reality (verified on branch) | Plan response |
| --- | --- | --- |
| Line 155 asserts `expect(interstitial).not.toBeInTheDocument()` synchronously after `fireEvent.click(dismiss)` | Confirmed verbatim — `live-repo-badge.test.tsx:152-155` | Wrap in `vi.waitFor` |
| Dismissal removal is async (state update) | Confirmed — `live-repo-badge.tsx:20,43,28` (`setDismissed(true)` → `return null`) | Anchor absence on the commit via poll |
| Belongs to vacuous-absence-wait class | Confirmed — learning file Key Insight 3 cited verbatim | Fix matches the documented remedy |
| Proposed fix `await waitFor(() => expect(queryByTestId(...)).toBeNull())` | File uses `vi.waitFor` + `screen.queryByTestId` throughout; the `vi.waitFor` sites (48/122/130) anchor on a fetch settle-flag or appearance, NOT on post-dismiss absence | Adopt `vi.waitFor` form for file consistency |
| Issue body implies line 114 is already an absence-poll precedent for the fix | **Corrected at deepen time:** line 114 is itself a bare synchronous post-dismiss absence assertion (`fireEvent.click` line 113 → bare `queryByTestId().toBeNull()` line 114) — the SAME vacuous-wait race, not a precedent | Fold line 114 into the same PR (AC1b); fixing only 155 leaves a known same-class flake armed |
| `interstitial` variable (captured node ref from `findByTestId`) | Still in scope; switching to `queryByTestId` re-queries live DOM instead of asserting on a detached ref | Re-query via `screen.queryByTestId` (more robust than `.not.toBeInTheDocument()` on a stale ref) |

## User-Brand Impact

**If this lands broken, the user experiences:** nothing user-facing — this is a
test-only assertion change in `apps/web-platform/test/live-repo-badge.test.tsx`.
A regression here would surface as a flaky-or-failing CI check on the
test suite, never in the running product. The production component
(`live-repo-badge.tsx`) is **not modified**.

**If this leaks, the user's data is exposed via:** N/A — no data path, no
schema, no auth, no network surface is touched. The change is confined to a unit
test's timing of an absence assertion.

**Brand-survival threshold:** none — test-only change, no production code path,
no regulated-data surface, no user-facing artifact.

## Acceptance Criteria

### Pre-merge (PR)

- [x] AC1 — the "dismissing the interstitial hides it" case (was line 155)
  asserts absence via a `vi.waitFor` poll, not a bare synchronous check:
  `git grep -n 'await vi.waitFor' apps/web-platform/test/live-repo-badge.test.tsx`
  returns a site inside that test.
- [x] AC1b — the same-class sibling at line 114 (the `re-arms…` test's
  post-dismiss absence assertion) is ALSO converted to a `vi.waitFor` poll. After
  the fix, **every** post-dismiss (`fireEvent.click(dismiss)`-followed) absence
  assertion in the file is poll-wrapped: manually confirm both the line-113→114
  and line-152→155 dismiss sites now `await vi.waitFor(() => expect(...).toBeNull())`.
- [x] AC2 — the bare synchronous form on the captured ref is gone:
  `git grep -n 'not.toBeInTheDocument' apps/web-platform/test/live-repo-badge.test.tsx`
  returns **zero** matches.
- [x] AC3 — the captured `interstitial` const is either removed (if now unused)
  or still referenced; `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`
  passes with **no** `'interstitial' is declared but its value is never read`
  (TS6133) error. (If the `findByTestId` await is kept to anchor "interstitial
  was present first," the const may be dropped to `await screen.findByTestId(...)`
  without assignment.)
- [x] AC4 — the suite passes in isolation:
  `cd apps/web-platform && ./node_modules/.bin/vitest run test/live-repo-badge.test.tsx`
  → all 5 tests green.
- [x] AC5 — the suite passes under contention (the actual flake repro): run the
  file under the full webplat group at least once green —
  `TEST_GROUP=webplat bash scripts/test-all.sh` completes with
  `live-repo-badge.test.tsx` reporting 5/5 pass. (If the full group is too heavy
  for the session, run the file 20× in a loop as a proxy:
  `cd apps/web-platform && for i in $(seq 20); do ./node_modules/.bin/vitest run test/live-repo-badge.test.tsx || break; done` →
  no break.)
- [x] AC6 — typecheck clean: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`
  exits 0.

### Post-merge (operator)

- [ ] AC7 — `Ref #5234` is in the PR body (test-fix; closing is fine via
  `Closes #5234` since the fix lands at merge, not post-merge). Use `Closes #5234`
  — this is a normal code change, not an ops-remediation.

## Implementation Phases

### Phase 1 — RED is already the flake (no new failing test needed)

This is a flaky-assertion repair, not a behavior change. `cq-write-failing-tests-before`
is satisfied by the existing flake: the current line 155 *is* the failing-under-load
assertion. There is no production-behavior gap to drive a new test for. Document in
the PR body that the "RED" state is the documented parallel-load flake (#5113-class)
and the change is the GREEN fix.

### Phase 2 — Apply the absence-poll fix

In `apps/web-platform/test/live-repo-badge.test.tsx`, the
`"dismissing the interstitial hides it"` test (currently lines 139-156):

1. Keep `await screen.findByTestId("revocation-interstitial")` so the test still
   proves the interstitial was present *before* dismissal. Decide whether to keep
   the `interstitial` const:
   - **Option A (preferred, simplest):** drop the const, switch the final
     assertion to re-query the live DOM:
     ```tsx
     await screen.findByTestId("revocation-interstitial");
     fireEvent.click(screen.getByRole("button", { name: /dismiss notice/i }));
     await vi.waitFor(() =>
       expect(screen.queryByTestId("revocation-interstitial")).toBeNull(),
     );
     ```
   - **Option B:** keep `const interstitial = await screen.findByTestId(...)`
     only if a later line still reads it; here nothing does, so Option A avoids a
     TS6133 unused-var error (see AC3).
2. Verify `vi` is already imported (it is — line 1: `import { ... vi ... } from "vitest"`).
3. **Sibling fold-in (line 114).** In the `"re-arms the interstitial…"` test,
   wrap the bare `expect(screen.queryByTestId("revocation-interstitial")).toBeNull()`
   that follows `fireEvent.click(dismiss)` (lines 113→114) in the same
   `await vi.waitFor(...)` poll. Same race, same fix.
4. **Scope boundary — do NOT touch lines 53 or 125.** Those two
   `queryByTestId(...).toBeNull()` assertions are each preceded by a
   `vi.waitFor(() => expect(pollCommitted/regainCommitted).toBe(true))` settle
   anchor (lines 48-52 and 122-124), so they already assert absence *after* the
   relevant async fetch commits. Only the two **post-dismiss** absence assertions
   (114, 155) are un-anchored and in scope.
5. No change to `live-repo-badge.tsx` (production component untouched).

### Phase 3 — Verify

Run AC4 → AC6 locally. Confirm AC2 (no `not.toBeInTheDocument` on the captured
ref remains) and AC1 (poll form present).

## Files to Edit

- `apps/web-platform/test/live-repo-badge.test.tsx` — TWO same-class edits:
  1. (line 155, primary) replace the synchronous
     `expect(interstitial).not.toBeInTheDocument()` with a
     `await vi.waitFor(() => expect(screen.queryByTestId("revocation-interstitial")).toBeNull())`
     poll; drop the now-unused `interstitial` const (Option A).
  2. (line 114, sibling fold-in) wrap the existing bare
     `expect(screen.queryByTestId("revocation-interstitial")).toBeNull()` (the
     post-dismiss assertion at line 113→114 in the `re-arms…` test) in the same
     `await vi.waitFor(...)` poll. Same vacuous-wait race; fix in this PR.

## Files to Create

- None.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` was not queried because the
single file in scope (`apps/web-platform/test/live-repo-badge.test.tsx`) is a test
file freshly authored by the #5113 fix series (#5098/#5113); no open scope-out is
expected to target it. Verify at /work time with:
`gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/r.json && jq -r --arg p "live-repo-badge.test.tsx" '.[]|select(.body//""|contains($p))|"#\(.number): \(.title)"' /tmp/r.json`
— if any match, fold-in or acknowledge per the plan-skill 1.7.5 procedure.

## Test Strategy

- **Runner:** in-package vitest — `apps/web-platform/node_modules/.bin/vitest run <path>`.
  Confirmed present. Do NOT use `bun test` (blocked by
  `apps/web-platform/bunfig.toml [test]` pathIgnorePatterns) and do NOT use
  `npm run -w` (repo root declares no `workspaces`).
- **Project glob:** the file is `test/live-repo-badge.test.tsx`, matched by the
  `component` project's `include: ["test/**/*.test.tsx"]` (happy-dom) in
  `apps/web-platform/vitest.config.ts:60`. No new test file, no glob concern.
- **Typecheck:** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
- **Flake-repro proxy:** the 20× loop in AC5 is the cheapest local signal that the
  poll closed the race; the authoritative signal is one green run under the full
  `TEST_GROUP=webplat` group.

## Risks & Mitigations

- **Risk:** `vi.waitFor` default 1000 ms is too tight under extreme contention.
  **Mitigation:** the failure mode is a single missed re-render tick after a
  *synchronous* event, not a multi-second async stall — 1000 ms is ample.
  The sibling poll at line 122 uses `{ timeout: 10_000 }` only because it awaits
  a *fetch* body settling. If AC5's contention run still flakes (it should not),
  add `{ timeout: 10_000 }` to match the file's async-fetch sites; note the
  reason inline.
- **Risk:** dropping the `interstitial` const breaks a downstream reference.
  **Mitigation:** grep confirms nothing else in the test reads it after line 155;
  AC3's `tsc --noEmit` catches any unused-var or dangling-ref regression.
- **Risk:** re-querying with `queryByTestId` instead of asserting on the captured
  node changes test semantics. **Mitigation:** this is *more* correct —
  `queryByTestId` reflects the live DOM after the commit, whereas
  `.not.toBeInTheDocument()` on a detached captured node can pass or fail based on
  ref staleness. The re-query is the file's established idiom (lines 53-54, 74,
  114, 125).

## Observability

Skipped silently — pure test-only change, no Files-to-Edit under
`apps/*/server/`, `apps/*/src/`, `apps/*/infra/`, or `plugins/*/scripts/`, and no
new infrastructure surface. (Plan Phase 2.9 skip condition: test file only.)

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — test-only timing fix. No UI-surface file
in Files-to-Edit (the production component `live-repo-badge.tsx` is untouched;
the only edited path is `apps/web-platform/test/live-repo-badge.test.tsx`, a test
file), so the mechanical UI-surface override does not fire and the Product/UX
Gate is skipped.

## Hypotheses

- **H1 (confirmed):** synchronous absence assertion races the async
  `setDismissed(true)` re-render; under CPU starvation the unmount has not flushed
  at assertion time. Evidence: component re-renders to `null` on dismiss
  (`live-repo-badge.tsx:28,43`); learning file documents this exact class for this
  exact file (#5113). Fix: poll until commit.
- **H0 (rejected):** cross-file pool/state leak. The learning file explicitly
  rejected this hypothesis for `live-repo-badge.test.tsx` — forks+isolate (#3817)
  already close cross-file leak vectors; the observed signature was probabilistic
  CPU starvation, not ordering-dependent.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan`
  Phase 4.6. This section is filled (threshold: none, test-only).
- Do NOT "fix" this by bumping `testTimeout` or adding a `sleep` — the defect is a
  missing settle anchor, not an insufficient budget. The #5113 fix already raised
  the relevant budgets; the residual flake at line 155 is purely the un-anchored
  assertion.
- Keep the `vi.waitFor` form (not RTL `waitFor`) for file consistency; the global
  `asyncUtilTimeout: 10_000` in `setup-dom.ts` does NOT reach `vi.waitFor` (Key
  Insight 2), so do not assume that config bumps this call's ceiling.
