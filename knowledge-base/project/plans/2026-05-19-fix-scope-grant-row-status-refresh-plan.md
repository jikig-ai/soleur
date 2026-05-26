---
title: "fix: scope-grant row status refresh after Authorize/Revoke (#4048)"
type: fix
date: 2026-05-19
issue: 4048
branch: feat-one-shot-scope-grant-row-status-refresh-4048
lane: single-domain
requires_cpo_signoff: false
---

# fix: scope-grant row status text refresh after Authorize/Revoke (#4048)

## Enhancement Summary

**Deepened on:** 2026-05-19
**Sections enhanced:** Overview, Proposed Solution, Test Scenarios, Risks
**Research surfaces:** installed-version probe (Next 15.5.18, vitest 3.1.0, @testing-library/react 16.3.2, happy-dom via component project), codebase precedent grep, AGENTS-rule-citation verify, vitest project-routing audit

### Key Improvements

1. **Canonical test precedent located.** `apps/web-platform/test/api-usage-retry-button.test.tsx` is the exact-shape precedent for asserting `router.refresh()` is called from a click handler — uses `vi.hoisted(() => ({ mockRefresh: vi.fn() }))` to share the mock between module mock-factory and `expect`. Adopt this pattern verbatim instead of the looser `settings-page.test.tsx` shape (whose `refresh: vi.fn()` is recreated per call and not directly assertable).
2. **Vitest project routing verified.** `apps/web-platform/vitest.config.ts:44` routes `test/**/*.test.tsx` to the `component` project (happy-dom + `test/setup-dom.ts`). The new `apps/web-platform/test/scope-grant-row.test.tsx` lands in the component project automatically — no `testMatch` extension needed, no config edit. Sibling `tool-use-chip.test.tsx` is the precedent.
3. **`startTransition` + `router.refresh` interaction is beneficial, not problematic.** The existing `onGrant` / `onRevoke` wrap the mutation in `startTransition(async () => { ... })`. Calling `router.refresh()` inside the transition extends `isPending` until the refreshed server data is ready (Next 15 App Router contract). The Authorize/Update/Revoke button stays disabled across the round-trip until the new server-rendered status string is visible. This is a UX improvement, not a regression — surface it in the Risks section so reviewers don't flag it as accidental.
4. **`router.refresh()` after success only, never after failure.** The pessimistic-UI invariant requires that a failed mutation NOT trigger a server re-render (otherwise a transient 500 would clobber the local `committedTier` revert with stale-but-still-correct server state — confusing UX with no benefit). Place `router.refresh()` inside the success branch, AFTER `setCommittedTier(...)`, BEFORE the `try` block exits. FR4 is the test that pins this invariant.
5. **AGENTS rule-ID audit.** All three cited IDs (`wg-before-every-commit-run-compound-skill`, `wg-use-closes-n-in-pr-body-not-title-to`, `hr-weigh-every-decision-against-target-user-impact`) verified as active in `AGENTS.core.md`/`AGENTS.rest.md`. No fabrications.

### New Considerations Discovered

- **`fireEvent.click` is sufficient; `userEvent` not required.** `api-usage-retry-button.test.tsx` uses `fireEvent.click` for the simplest possible click assertion. For our row, the user flow is "select radio → click button," which `fireEvent.click` handles equally well as `userEvent.click` — no `act()` warnings expected because state updates are wrapped in `startTransition` which RTL handles natively.
- **`fetch` mock placement matters under happy-dom + `setup-dom.ts`.** `test/setup-dom.ts:47-58` restores `globalThis.fetch` in `afterAll`. Per-test `global.fetch = vi.fn(...)` assignments are intra-file stable (no cleanup leakage between tests because `vi.restoreAllMocks()` does not undo raw property writes — but the afterAll restoration handles the file boundary). For inter-test isolation within the file, prefer `vi.stubGlobal("fetch", vi.fn())` + `vi.unstubAllGlobals()` in `beforeEach`, or just re-assign per test as `settings-page.test.tsx` does.
- **No XHR involved.** The mutation uses `fetch` only; no need to mock `XMLHttpRequest`.

## Overview

Closes #4048. On `/dashboard/settings/scope-grants`, the row's headline status paragraph ("Not authorized — Soleur will not act on this class." vs. "Active at <tier> since <date>") does not refresh after a successful Authorize click. The action button + radio bindings flip correctly via local state, but the status string is derived from a combination of `committedTier` (local) AND `grantedAt` (server prop). After Authorize, `committedTier` becomes truthy but `grantedAt` is still `null` (stale prop), so the conditional falls through to the "Not authorized" else branch. Only a full page reload re-renders the server component with the new `grantedAt`, fixing the display.

The fix is to call `router.refresh()` after both grant and revoke succeed, matching the established pattern at `apps/web-platform/components/settings/key-rotation-form.tsx:49` (where a sibling settings client component triggers a server re-render after a mutation that changed the server-rendered prop). This is Option 2 from the issue body — the option-1 alternative (lift `grantedAt` into local state) was rejected because the client-side timestamp would not match the canonical server `granted_at` until a refresh anyway.

## Problem Statement / Motivation

**Where the bug lives:** `apps/web-platform/components/scope-grants/scope-grant-row.tsx:127-136`

```tsx
{committedTier && grantedAt ? (
  <p className="mt-1 text-xs text-soleur-text-muted">
    Active at {TRUST_TIER_COPY[committedTier].label} since{" "}
    {new Date(grantedAt).toLocaleDateString()}
  </p>
) : (
  <p className="mt-1 text-xs text-soleur-text-muted">
    Not authorized — Soleur will not act on this class.
  </p>
)}
```

- `committedTier` (local state) is set in `onGrant` success to `selectedTier` (line 86).
- `grantedAt` is a **prop** from the server component (`page.tsx:75`), passed once per server render.
- After Authorize: `committedTier` flips truthy, but `grantedAt` is still `null` (was `null` for an unauthorized class). The conditional `committedTier && grantedAt` short-circuits to `false`, the "Not authorized" branch keeps rendering.
- After a full page reload, the server component re-fetches the new `granted_at` from `scope_grants` and passes it down — the status finally updates.

**Why it matters:** Visual contradiction between the headline ("not authorized") and the actions ("Revoke" implies authorized) is mildly trust-eroding on a security-sensitive screen. Caught while executing PR-G post-merge POST-2 (operator scope-grant seed) on prd 2026-05-19.

**Symmetric concern on Revoke:** After a successful Revoke, `committedTier` is set to `null` (line 111), so the `committedTier && grantedAt` conditional correctly short-circuits to the "Not authorized" branch — the status display is already correct without a refresh. HOWEVER, an in-session re-Authorize after a Revoke would re-trigger the same bug (committedTier truthy, grantedAt still the stale post-Revoke `null` from the original render). Update-tier-while-authorized would also silently keep the old "since <date>" string (since `grantedAt` is the original render's value). The fix addresses all three by always calling `router.refresh()` on success.

## Proposed Solution

Add `useRouter` import and call `router.refresh()` after both grant and revoke succeed. Pattern verbatim from `apps/web-platform/components/settings/key-rotation-form.tsx`.

### Files to Edit

- `apps/web-platform/components/scope-grants/scope-grant-row.tsx` — add `useRouter` from `next/navigation`, instantiate `const router = useRouter()`, call `router.refresh()` after grant success (after `setCommittedTier(selectedTier)`) and after revoke success (after `setCommittedTier(null)`). 4 LoC.

### Files to Create

- `apps/web-platform/test/scope-grant-row.test.tsx` — vitest + RTL + happy-dom test file. Routes to the `component` project automatically via `vitest.config.ts:44` (`test/**/*.test.tsx`). Five tests (FR1–FR4 + FR5 regression). The canonical test shape is `apps/web-platform/test/api-usage-retry-button.test.tsx` (uses `vi.hoisted` to share the `mockRefresh` reference between the module-mock factory and the `expect` site — strictly required because vitest hoists `vi.mock` calls above all imports).

  **Mock shape (verbatim from `api-usage-retry-button.test.tsx:4-8`):**

  ```tsx
  const { mockRefresh } = vi.hoisted(() => ({ mockRefresh: vi.fn() }));
  vi.mock("next/navigation", () => ({
    useRouter: () => ({ refresh: mockRefresh, push: vi.fn() }),
  }));
  ```

  Do NOT use the looser `useRouter: () => ({ refresh: vi.fn() })` form from `settings-page.test.tsx:10` — that re-creates the mock per call site and cannot be asserted against.

  **`global.fetch` mock per test:** `(global.fetch as ReturnType<typeof vi.fn>).mockResolvedValueOnce({ ok: true, status: 200, json: async () => ({ ... }) })`. `setup-dom.ts:47-58` restores the original `fetch` in `afterAll`; intra-file safety is handled by `vi.clearAllMocks()` in `beforeEach`.

### Files NOT to Edit

- `apps/web-platform/app/(dashboard)/dashboard/settings/scope-grants/page.tsx` — server component already has `export const dynamic = "force-dynamic"`, so `router.refresh()` will re-execute the server component (no caching to bust).
- `apps/web-platform/app/api/scope-grants/grant/route.ts` + `revoke/route.ts` — the API contract is correct; the bug is purely client-side display.
- `apps/web-platform/server/scope-grants/action-class-map.ts`, `is-granted.ts` — unrelated.

## Research Reconciliation — Spec vs. Codebase

| Issue body claim | Codebase reality | Plan response |
|---|---|---|
| "after Revoke the page also needs a refresh to clear the Active state — symmetric" | Revoke sets `committedTier = null` (line 111). The conditional `committedTier && grantedAt` short-circuits on `committedTier` alone — Revoke is **not currently broken** on the status string, but a follow-up re-Authorize in the same session WOULD be broken. | Apply `router.refresh()` to BOTH paths anyway. The issue body's symmetric framing is the correct one — same-session re-Authorize is a real failure mode caught by the same fix. |
| "Option 1: Lift the status string into the same local state flipped optimistically" | Would require synthesizing `grantedAt` client-side via `new Date().toISOString()`. The displayed date is `toLocaleDateString()` formatted, so client-side vs. server-side timestamp would render identically for same-day grants — but server is the canonical source. | Rejected. Option 2 (router.refresh) matches `key-rotation-form.tsx:49` precedent and avoids a client/server timestamp drift class. |
| File path `apps/web-platform/components/scope-grants/scope-grant-row.tsx` | Confirmed exists; 242 LoC; client component. | No drift. |

## User-Brand Impact

- **If this lands broken, the user experiences:** The scope-grants settings page renders an internally contradictory header (action button says "Revoke" / "Update" while status text says "Not authorized") for the rest of the session after any Authorize click, until they refresh. Authorization itself is correctly persisted server-side — only the display is stale.
- **If this leaks, the user's [data / workflow / money] is exposed via:** N/A. No data exposure, no leak vector. The underlying scope_grant row is correctly created/revoked by the existing RPC; this fix changes only when the client re-fetches the canonical state for display.
- **Brand-survival threshold:** `none` — cosmetic UI consistency bug on an internal settings surface. No money-class action is gated by the status string; the actual gate is the `is-granted.ts` server check against the `scope_grants` table.

*Scope-out override (`threshold: none` AND diff touches `components/scope-grants/`, a security-sensitive folder per preflight Check 6):* `threshold: none, reason: the diff is a client-side useRouter import + two router.refresh() calls; no change to the server authorization gate, no change to RPC contract, no change to RLS, no change to API routes — the underlying authorization invariant is unchanged.`

## Acceptance Criteria

### Functional Requirements

Each FR has TWO acceptance layers: a **unit-testable trigger assertion** (vitest + RTL, mocks `next/navigation`) and a **QA-testable rendered-string assertion** (Playwright against the real Next 15 runtime, where `router.refresh()` actually re-executes the server component). The split is necessary because mocked `router.refresh` is a no-op `vi.fn()` and cannot drive a server re-render in jsdom.

- [ ] **FR1 (Authorize)** — After clicking Authorize on a previously-unauthorized action class:
  - **Unit:** `mockRefresh` called exactly once after the POST resolves with `ok: true`. (vitest)
  - **QA:** Within ~200ms (no manual reload), the row's status paragraph reads "Active at <tier-label> since <today's-date>". (Playwright)
- [ ] **FR2 (Revoke)** — After clicking Revoke on a previously-authorized action class:
  - **Unit:** `mockRefresh` called exactly once after the POST resolves with `ok: true`.
  - **QA:** Within ~200ms, the row's status paragraph reads "Not authorized — Soleur will not act on this class." (Symmetric to FR1; the pre-fix code already short-circuits the paragraph via `committedTier=null` → "Not authorized" branch, but `router.refresh()` is still load-bearing for the prop sync that protects subsequent re-Authorize from re-triggering the bug.)
- [ ] **FR3 (Update)** — After clicking Update on an already-authorized action class with a new tier:
  - **Unit:** `mockRefresh` called exactly once after the POST resolves with `ok: true`.
  - **QA:** Within ~200ms, the row's status paragraph reads "Active at <new-tier-label> since <today's-date>". (Closes the tier-update-stale-date silent failure noted in Research Reconciliation.)
- [ ] **FR4 (failure)** — If Authorize/Revoke fails (non-2xx response or network error):
  - **Unit:** `mockRefresh` NOT called; the inline error region renders with the failure message; pessimistic revert restores prior state.
  - **QA:** N/A (forcing a 500 in prod is not part of the standard QA path).

### Quality Gates

- [ ] **QG1** — New test file `apps/web-platform/test/scope-grant-row.test.tsx` passes under `bun run --filter=web-platform test:ci` (resolves to `vitest run` per `apps/web-platform/package.json`).
- [ ] **QG2** — `tsc --noEmit` clean for the edited file (no new TypeScript errors).
- [ ] **QG3** — The diff for `scope-grant-row.tsx` adds exactly: one `useRouter` import line, one `const router = useRouter()` line, and two `router.refresh()` call sites (one in `onGrant` success path after `setCommittedTier(selectedTier)`, one in `onRevoke` success path after `setCommittedTier(null)`). No other behavior changes.
- [ ] **QG4** — `apps/web-platform/components/scope-grants/scope-grant-row.tsx` still compiles with `"use client";` directive at top (line 1) — the fix does not change the component's client/server boundary.

## Test Scenarios

### Acceptance Tests (RED phase targets)

These map 1:1 to FR1–FR4 and live in `apps/web-platform/test/scope-grant-row.test.tsx`:

- **FR1 → Test A:** Given `<ScopeGrantRow actionClass="finance.payment_failed" currentTier={null} grantedAt={null} />` rendered, when the user selects `draft_one_click`, clicks "Authorize", and `fetch` resolves with `{ ok: true, status: 200, json: { id: "...", action_class: "...", tier: "draft_one_click" } }`, then the rendered DOM contains "Active at Draft, one click since" (via `screen.getByText(/Active at .* since/i)`) AND `router.refresh` mock was called exactly once.
- **FR2 → Test B:** Given `<ScopeGrantRow actionClass="finance.payment_failed" currentTier="draft_one_click" grantedAt="2026-05-19T00:00:00Z" />` rendered (i.e. starts authorized), when the user clicks "Revoke" and `fetch` resolves `{ ok: true }`, then the rendered DOM contains "Not authorized — Soleur will not act on this class." AND `router.refresh` was called exactly once.
- **FR3 → Test C:** Given `<ScopeGrantRow actionClass="finance.payment_failed" currentTier="draft_one_click" grantedAt="2026-05-19T00:00:00Z" />`, when the user changes the radio to `approve_every_time`, clicks "Update", and fetch resolves `{ ok: true }`, then the rendered DOM contains "Active at Approve every time since" AND `router.refresh` was called exactly once.
- **FR4 → Test D:** Given `<ScopeGrantRow actionClass="finance.payment_failed" currentTier={null} grantedAt={null} />`, when the user selects `draft_one_click`, clicks "Authorize", and `fetch` resolves with `{ ok: false, status: 500 }`, then the rendered DOM still contains "Not authorized — Soleur will not act on this class.", the inline error text matches `/Failed to save \(500\)/`, AND `router.refresh` was NOT called.

### Regression Tests

- The existing PR-G `auto`-tier acknowledgement gating MUST still pass. Specifically, selecting `auto` without checking the confirm checkbox MUST keep the "Authorize"/"Update" button disabled. The fix MUST NOT touch the `canSubmit` computation (lines 55-59) or the `acked` state machine. Test E in the new file: select `auto`, assert "Authorize" button is disabled, check the ack box, assert button enabled — verifies the unchanged invariant.

### Integration Verification (deferred to `/soleur:qa` after merge)

- **Browser (manual, captured by /soleur:qa Playwright):** Navigate to `https://soleur.ai/dashboard/settings/scope-grants`, log in as the operator, click Authorize for any unauthorized action class at `draft_one_click`. Within ~200ms (no manual reload), the row's status paragraph must read "Active at Draft, one click since 5/19/2026" (or current local date). Then click Revoke on the same row — within ~200ms the status paragraph must read "Not authorized — Soleur will not act on this class."
- No API verify / cleanup needed — the API contract is unchanged.

## Open Code-Review Overlap

`gh issue list --label code-review --state open` → no open code-review issues touch `apps/web-platform/components/scope-grants/scope-grant-row.tsx`. The query returned zero matches. No fold-in / acknowledge / defer disposition required.

## Domain Review

**Domains relevant:** none

Internal UI consistency fix on an already-shipped client component. No new flow, no new copy, no schema change, no API contract change, no regulated-data surface, no infrastructure. The Product domain assessment ("does this create new user-facing pages, flows, or significant UI components?") is NONE — the change is a 4-line diff inside an existing component, fixing a display defect against criteria the PR-G plan already established. Per the mechanical escalation rule (`components/**/*.tsx` creating a NEW file), the new file is a `*.test.tsx` under `apps/web-platform/test/` — test files do not trigger Product/UX gate.

## GDPR / Compliance Gate

Skipped silently per Phase 2.7 — no regulated-data surface touched (no schema, no migration, no auth flow, no API route, no `.sql` file). The `apps/web-platform/components/scope-grants/scope-grant-row.tsx` file is a pure client display component; the diff adds only a router-refresh call. No (a)/(b)/(c)/(d) expansion trigger fires either: no LLM/external-API processing of operator data, brand-survival threshold = `none` (not `single-user incident`), no cron/workflow reading from learnings/specs, no artifact distribution surface.

## Infrastructure-as-Code Routing Gate

Skipped — pure code change against an already-provisioned surface. No SSH, no `doppler secrets set`, no systemd, no vendor dashboard, no new resource, no new secret. The plan's `## Files to Edit` is one component file; `## Files to Create` is one test file under `apps/web-platform/test/`. No `apps/<app>/infra/` paths touched.

## Implementation Sketch (MVP)

### scope-grant-row.tsx diff

```tsx
// Add to imports (top of file, after the existing react import):
import { useRouter } from "next/navigation";

// Inside ScopeGrantRow component, after the existing useState calls:
const router = useRouter();

// In onGrant success path, after setCommittedTier(selectedTier):
setCommittedTier(selectedTier);
setAcked(false);
router.refresh(); // ← new

// In onRevoke success path, after setCommittedTier(null):
setCommittedTier(null);
setSelectedTier(null);
setAcked(false);
router.refresh(); // ← new
```

### scope-grant-row.test.tsx skeleton (verbatim hoist pattern from api-usage-retry-button.test.tsx)

```tsx
import { describe, test, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";

// vi.hoisted is REQUIRED — vi.mock is hoisted above imports, so a bare
// top-level `const refresh = vi.fn()` would be undefined inside the mock
// factory. Source precedent: api-usage-retry-button.test.tsx:4
const { mockRefresh } = vi.hoisted(() => ({ mockRefresh: vi.fn() }));

vi.mock("next/navigation", () => ({
  useRouter: () => ({ refresh: mockRefresh, push: vi.fn() }),
}));

import { ScopeGrantRow } from "@/components/scope-grants/scope-grant-row";

describe("ScopeGrantRow — router.refresh after Authorize/Revoke (#4048)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    global.fetch = vi.fn();
  });

  test("FR1: Authorize success → status updates AND refresh called once", async () => {
    (global.fetch as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      ok: true, status: 200,
      json: async () => ({ id: "g1", action_class: "finance.payment_failed", tier: "draft_one_click" }),
    });
    render(<ScopeGrantRow actionClass="finance.payment_failed" currentTier={null} grantedAt={null} />);
    fireEvent.click(screen.getByRole("radio", { name: /draft, one click/i }));
    fireEvent.click(screen.getByRole("button", { name: /authorize/i }));
    await waitFor(() => expect(mockRefresh).toHaveBeenCalledTimes(1));
    // Note: the status text in the headline only flips after the server
    // re-renders. In tests, router.refresh is mocked → the server prop
    // grantedAt remains null → the headline still shows "Not authorized".
    // FR1 asserts the *trigger* (refresh called), NOT the post-refresh
    // server render — that lives in the QA Playwright check (Phase 6 task).
  });

  test("FR2: Revoke success → refresh called once", async () => {
    (global.fetch as ReturnType<typeof vi.fn>).mockResolvedValueOnce({ ok: true, status: 200 });
    render(<ScopeGrantRow actionClass="finance.payment_failed" currentTier="draft_one_click" grantedAt="2026-05-19T00:00:00Z" />);
    fireEvent.click(screen.getByRole("button", { name: /revoke/i }));
    await waitFor(() => expect(mockRefresh).toHaveBeenCalledTimes(1));
  });

  test("FR3: Update tier success → refresh called once", async () => {
    (global.fetch as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      ok: true, status: 200,
      json: async () => ({ id: "g2", action_class: "finance.payment_failed", tier: "approve_every_time" }),
    });
    render(<ScopeGrantRow actionClass="finance.payment_failed" currentTier="draft_one_click" grantedAt="2026-05-19T00:00:00Z" />);
    fireEvent.click(screen.getByRole("radio", { name: /approve every time/i }));
    fireEvent.click(screen.getByRole("button", { name: /update/i }));
    await waitFor(() => expect(mockRefresh).toHaveBeenCalledTimes(1));
  });

  test("FR4: Authorize failure → refresh NOT called (pessimistic-UI invariant)", async () => {
    (global.fetch as ReturnType<typeof vi.fn>).mockResolvedValueOnce({ ok: false, status: 500 });
    render(<ScopeGrantRow actionClass="finance.payment_failed" currentTier={null} grantedAt={null} />);
    fireEvent.click(screen.getByRole("radio", { name: /draft, one click/i }));
    fireEvent.click(screen.getByRole("button", { name: /authorize/i }));
    await waitFor(() => expect(screen.getByRole("alert")).toHaveTextContent(/Failed to save \(500\)/));
    expect(mockRefresh).not.toHaveBeenCalled();
  });

  test("FR5 (regression): auto-tier without ack keeps button disabled", () => {
    render(<ScopeGrantRow actionClass="finance.payment_failed" currentTier={null} grantedAt={null} />);
    fireEvent.click(screen.getByRole("radio", { name: /auto/i }));
    expect(screen.getByRole("button", { name: /authorize/i })).toBeDisabled();
    fireEvent.click(screen.getByRole("checkbox"));
    expect(screen.getByRole("button", { name: /authorize/i })).toBeEnabled();
  });
});
```

**Why the FR1 test asserts only `mockRefresh` was called, NOT the post-refresh status string:** In production, `router.refresh()` triggers a server-component re-render that hands a new `grantedAt` prop back to `ScopeGrantRow`. In tests, `next/navigation` is mocked — `router.refresh()` is a no-op `vi.fn()`. The server re-render never happens, so the headline status string cannot flip in jsdom/happy-dom. Asserting the trigger (refresh called once) is the testable invariant; asserting the rendered-string outcome lives in the Playwright/QA layer where the real Next runtime executes the refresh. This separation matches `api-usage-retry-button.test.tsx` (asserts `mockRefresh` called, not the page-state delta).

## Risks & Sharp Edges

- **Risk: double-render on `force-dynamic`.** Calling `router.refresh()` re-executes the server component. Since the page is `export const dynamic = "force-dynamic"` (`page.tsx:17`), there is no cache to bust — the cost is one extra round-trip per Authorize/Revoke. Acceptable: settings actions are low-frequency.
- **Risk: future test-runner project assignment — VERIFIED safe.** New file lives at `apps/web-platform/test/scope-grant-row.test.tsx`. `apps/web-platform/vitest.config.ts:44` routes `test/**/*.test.tsx` to the `component` project (`environment: "happy-dom"`, `setupFiles: ["test/setup-dom.ts"]`, `isolate: true`). The `unit` project at `:28` includes only `test/**/*.test.ts` (no `x`) and would NOT pick up the new file — but that's correct behavior: RTL needs the DOM. No config edit needed. Sibling `apps/web-platform/test/api-usage-retry-button.test.tsx` is the matching shape and runs green today.
- **Risk: `router.refresh()` inside `startTransition` — INTENTIONAL, not a regression.** The existing handler wraps the mutation in `startTransition(async () => { ... })`. Calling `router.refresh()` inside the transition causes `isPending` to remain true until the App Router finishes refetching server data (Next 15 contract). UX effect: the Authorize/Update/Revoke button stays disabled across the round-trip, then snaps back to its new label when the new server prop arrives. Reviewers may flag this as "the button feels slow after click" — it is the correct behavior, not a regression. Document in PR body so review-time concerns are pre-empted.
- **Risk: `useRouter` is a client hook.** The file already starts with `"use client";` (line 1) — no boundary change needed. Adding `useRouter` will not introduce a server/client violation.
- **Risk: `router.refresh` mock leakage between tests.** The `vi.mock("next/navigation", ...)` block uses a module-scoped `refresh` mock that must be cleared in `beforeEach` (per sibling `settings-page.test.tsx` pattern). The test skeleton already encodes `refresh.mockClear()`.
- **Sharp edge: empty `## User-Brand Impact` would fail deepen-plan Phase 4.6 and preflight Check 6.** This plan's section is populated with concrete artifacts and a scope-out override paragraph for the `threshold: none` + sensitive-path case. Do not remove during /work.

## References & Related Work

### Internal References

- Buggy component: `apps/web-platform/components/scope-grants/scope-grant-row.tsx:127-136` (the conditional that conjoins `committedTier && grantedAt`)
- Optimistic-state set sites that need a `router.refresh()` companion: `scope-grant-row.tsx:86` (onGrant success), `scope-grant-row.tsx:111` (onRevoke success)
- Pattern precedent: `apps/web-platform/components/settings/key-rotation-form.tsx:11` (`const router = useRouter()`), `:49` (`router.refresh()` after success)
- Server component (no edits): `apps/web-platform/app/(dashboard)/dashboard/settings/scope-grants/page.tsx`
- API routes (no edits): `apps/web-platform/app/api/scope-grants/grant/route.ts`, `apps/web-platform/app/api/scope-grants/revoke/route.ts`
- Test convention precedent — CANONICAL: `apps/web-platform/test/api-usage-retry-button.test.tsx:4-26` (vi.hoisted mockRefresh + asserting `toHaveBeenCalledTimes(1)`). Use this shape verbatim.
- Test convention precedent — secondary: `apps/web-platform/test/tool-use-chip.test.tsx` (vitest + RTL pattern for `<Component>` rendering), `apps/web-platform/test/settings-page.test.tsx:9-12` (next/navigation mock without assertion). The latter is NOT directly assertable — do not adopt.
- Vitest routing: `apps/web-platform/vitest.config.ts:44` (component project `include: ["test/**/*.test.tsx"]`, happy-dom + setup-dom.ts).
- Refresh-after-mutation pattern precedent: `apps/web-platform/components/settings/dsar-export-job-list.tsx:22-24` (canonical comment block: "We don't keep client-side mutable state for it — router.refresh() re-renders the server component when an active job's status changes."), `apps/web-platform/components/settings/key-rotation-form.tsx:49`, `apps/web-platform/components/settings/api-usage-retry-button.tsx`.

### Related Work

- PR #3984 — PR-G (cohort onboarding) shipped the scope-grants UI being fixed here. Plan landed at `knowledge-base/project/plans/archive/…-pr-g-cohort-onboarding-plan.md`.
- Caught while executing PR-G post-merge POST-2 on prd 2026-05-19.
- Issue: #4048 (closes via PR body once merged).
