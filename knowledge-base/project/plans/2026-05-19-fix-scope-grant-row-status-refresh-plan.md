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

- `apps/web-platform/test/scope-grant-row.test.tsx` — vitest + RTL test file. Mocks `next/navigation` with `useRouter: () => ({ refresh })` and `global.fetch`. Three tests:
  1. After successful Authorize on unauthorized class: status text reads "Active at <label> since <date>" and `router.refresh` was called once.
  2. After successful Revoke on authorized class: status text reads "Not authorized — Soleur will not act on this class." and `router.refresh` was called once.
  3. After Authorize that returns non-2xx: status text stays "Not authorized", error appears, `router.refresh` NOT called (pessimistic-UI invariant preserved).

  Sibling test convention: `apps/web-platform/test/tool-use-chip.test.tsx` + `apps/web-platform/test/settings-page.test.tsx` for `next/navigation` mock shape.

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

- [ ] **FR1** — After clicking Authorize on a previously-unauthorized action class, within ~200ms the row's status paragraph reads "Active at <tier-label> since <today's-date>" without requiring a full page reload. (Issue acceptance.)
- [ ] **FR2** — After clicking Revoke on a previously-authorized action class, the row's status paragraph reads "Not authorized — Soleur will not act on this class." without requiring a full page reload. (Symmetric to FR1; also already passing pre-fix via committedTier short-circuit — but the post-fix test must still pass, and `router.refresh()` must still be called once.)
- [ ] **FR3** — After clicking Update on an already-authorized action class with a new tier, the row's status paragraph reads "Active at <new-tier-label> since <today's-date>" without requiring a full page reload. (Closes the tier-update-stale-date silent failure noted in Research Reconciliation.)
- [ ] **FR4** — If Authorize fails (non-2xx response or network error), the status paragraph remains "Not authorized — Soleur will not act on this class.", the inline error renders, and `router.refresh()` is NOT called. (Pessimistic-UI invariant preserved per existing PR-G design.)

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

### scope-grant-row.test.tsx skeleton

```tsx
import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";

const refresh = vi.fn();
vi.mock("next/navigation", () => ({
  useRouter: () => ({ refresh }),
}));

describe("ScopeGrantRow router.refresh on success", () => {
  beforeEach(() => {
    refresh.mockClear();
    global.fetch = vi.fn();
  });

  it("FR1: calls router.refresh and updates status after Authorize", async () => {
    (global.fetch as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: async () => ({ id: "abc", action_class: "finance.payment_failed", tier: "draft_one_click" }),
    });
    const { ScopeGrantRow } = await import("@/components/scope-grants/scope-grant-row");
    render(<ScopeGrantRow actionClass="finance.payment_failed" currentTier={null} grantedAt={null} />);
    // select tier, click authorize, await waitFor → assert status text + refresh called once
  });
  // FR2, FR3, FR4, regression E …
});
```

## Risks & Sharp Edges

- **Risk: double-render on `force-dynamic`.** Calling `router.refresh()` re-executes the server component. Since the page is `export const dynamic = "force-dynamic"` (`page.tsx:17`), there is no cache to bust — the cost is one extra round-trip per Authorize/Revoke. Acceptable: settings actions are low-frequency.
- **Risk: future test-runner project assignment.** New file lives at `apps/web-platform/test/scope-grant-row.test.tsx`. The `vitest.config.ts` (or `vite.config.ts`) `test.include` glob in `apps/web-platform/` covers `test/**/*.test.{ts,tsx}` (verified via sibling `tool-use-chip.test.tsx` running). No new glob needed — sanity-confirm at /work Phase 0 by running `bun run --filter=web-platform test:ci -- scope-grant-row` and checking the file is picked up.
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
- Test convention precedent: `apps/web-platform/test/settings-page.test.tsx:9-12` (next/navigation mock with `refresh: vi.fn()`), `apps/web-platform/test/tool-use-chip.test.tsx` (vitest + RTL + dynamic-import pattern for client components)

### Related Work

- PR #3984 — PR-G (cohort onboarding) shipped the scope-grants UI being fixed here. Plan landed at `knowledge-base/project/plans/archive/…-pr-g-cohort-onboarding-plan.md`.
- Caught while executing PR-G post-merge POST-2 on prd 2026-05-19.
- Issue: #4048 (closes via PR body once merged).
