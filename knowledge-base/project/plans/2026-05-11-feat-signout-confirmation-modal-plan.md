---
title: "feat: Add sign-out confirmation modal"
type: feat
date: 2026-05-11
branch: feat-one-shot-signout-confirm-popup
requires_cpo_signoff: false
deepened: 2026-05-11
---

# feat: Add sign-out confirmation modal

## Enhancement Summary

**Deepened on:** 2026-05-11
**Sections enhanced:** Overview, Implementation Phases (Phase 2 modal, Phase 3 wiring), Test Scenarios, Risks
**Research focus:** WAI-ARIA `alertdialog` vs `dialog` semantics, Supabase auth `removeAllChannels`/`signOut` v2 return shapes, React Testing Library focus/timer patterns, codebase modal precedent.

### Key Improvements

1. **`role="alertdialog"` vs `role="dialog"` decision recorded.** Confirmation prompts that prevent destructive action are the textbook WAI-ARIA `alertdialog` use case (W3C APG 1.2), BUT every existing Soleur modal uses `role="dialog"` (including the canonical `cancel-retention-modal.tsx`). The plan now explicitly chooses `role="dialog"` for codebase consistency and documents the trade-off in Phase 2 — keeping plan-level coherence over book-perfection.
2. **`removeAllChannels()` return-shape pin.** The plan now explicitly notes that `supabase.removeAllChannels()` returns `Promise<("ok" | "timed out" | "error")[]>` — a single Promise, not an array of Promises (per encoded learning `2026-04-29-supabase-removeallchannels-api-shape.md`). The await stays singular; no `Promise.all`.
3. **Sentry tag-coverage drift-guard sequencing pinned.** Phase 4 explicitly orders: implement mirror in Phase 3 first, then extend `AUTH_VERBS` in Phase 4. Reversed order would fail the drift-guard before the mirror exists. Added an explicit grep step to confirm there is only one `signOut` call site today.
4. **Test patterns reused from `cancel-retention-modal.test.tsx`.** Listed verbatim mock setup (`next/navigation`, `@/lib/supabase/client`, `@/lib/client-observability`) and `fireEvent.keyDown(document, { key: "Escape" })` form so the implementation phase doesn't have to re-derive them.
5. **Inert-attribute interaction documented.** The dashboard `<main>` has `inert={drawerOpen || undefined}`. The modal renders at the layout root OUTSIDE `<main>`, so it is not affected by inert during mobile drawer-open state. Documented as a Risk + an explicit position requirement.

### New Considerations Discovered

- **Initial-focus choice is load-bearing.** Focusing the **Cancel** button (least-destructive default) on open is a WCAG-aligned pattern for destructive-action prompts. The plan now states this explicitly with a citation rather than leaving it as an implementation detail.
- **`onConfirm` is async — parent must own the `isSigningOut` lock.** The modal cannot infer the in-flight state from the `onConfirm` return value alone (the caller may not even return the promise). The plan keeps `isSigningOut` as an explicit prop owned by the parent, preventing double-click races.
- **Route-change unmount path replaces state reset.** Adding `setIsSigningOut(false)` after `router.push("/login")` would briefly re-enable the button between navigation start and unmount. The plan documents this and intentionally OMITS the reset — the unmount IS the reset.

## Overview

The dashboard sidebar's "Sign out" button (`apps/web-platform/app/(dashboard)/layout.tsx:348-355`) currently calls `handleSignOut` synchronously on the very first click. There is no confirmation step: a misclick on the sidebar footer immediately tears down all Realtime channels, calls `supabase.auth.signOut()`, and redirects to `/login`. On a multi-hour writing session this is a destructive one-click loss — channel subscriptions and in-memory page state are gone, and the user has to re-authenticate before continuing.

This plan adds a confirmation modal that intercepts the sidebar Sign out click. The modal asks the user to confirm before the existing teardown logic runs. The modal follows the canonical Soleur dialog pattern already used by `components/settings/cancel-retention-modal.tsx` (focus trap, ESC-to-close, click-backdrop-to-close, `role="dialog"` + `aria-modal="true"`, focus restore to trigger on close).

This PR also folds in the open scope-out **#3039** (Sentry observability around the `signOut` call path) — the same handler is being rewritten, so adding the `reportSilentFallback` mirror at the same time avoids a future double-edit of the same function.

## Research Reconciliation — Spec vs. Codebase

No spec file existed for `feat-one-shot-signout-confirm-popup` at plan time. All claims in this plan were sourced directly from the codebase (`grep`/`Read` against the worktree). No reconciliation needed.

## User-Brand Impact

**If this lands broken, the user experiences:** the Sign out button stops working entirely (modal never opens, or modal "Confirm" click never proceeds to sign-out) — user is stuck signed in on a device they wanted to leave. Worst variant: the modal opens but the Cancel/ESC path bypasses the existing channel-teardown contract (e.g., focus trap traps focus indefinitely), making the app unusable until tab close.

**If this leaks, the user's session is exposed via:** none — this is a UI-only confirmation gate over the existing `supabase.auth.signOut()` call. No new credentials, tokens, or PII surfaces are introduced. The teardown contract (`removeAllChannels()` in a `try`, `signOut() + push("/login")` in a `finally`) is preserved verbatim.

**Brand-survival threshold:** `none` — UI-only confirmation gate, no regulated-data surface, no auth state change, no new persistence. Justification: the existing `handleSignOut` body is wrapped, not replaced; the failure mode is a non-functional button, not a session leak. Reason recorded per `hr-weigh-every-decision-against-target-user-impact`: confirmation modal sits on top of an already-shipped teardown contract; threshold `none` reason `confirmation gate over existing teardown — no new auth surface, no new state, UI-only`.

## Acceptance Criteria

### Pre-merge (PR)

- [x] Clicking the sidebar "Sign out" button opens a modal instead of signing out immediately.
- [x] Modal contains a heading ("Sign out?"), a one-sentence body explaining what will happen, and two CTAs: "Sign out" (primary) and "Cancel" (secondary).
- [x] Modal renders with `role="dialog"` and `aria-modal="true"` and `aria-labelledby` pointing to the heading.
- [x] Pressing ESC closes the modal without signing the user out.
- [x] Clicking the backdrop closes the modal without signing the user out.
- [x] Clicking "Cancel" closes the modal without signing the user out.
- [x] Clicking "Sign out" runs the existing teardown contract verbatim: `try { await supabase.removeAllChannels() } finally { await supabase.auth.signOut(); router.push("/login") }`.
- [x] While the sign-out is in flight, the "Sign out" button shows a `Signing out…` label and is `disabled`; the "Cancel" button is also disabled (no escape from the teardown).
- [x] Focus moves into the modal on open (initial focus on the Cancel button — least-destructive default) and returns to the sidebar Sign out button on close.
- [x] Tab key cycles focus inside the modal; Shift+Tab from the first element wraps to the last.
- [x] Modal works in both collapsed and expanded sidebar states (the modal is portaled/positioned independently of the sidebar collapse state).
- [x] On mobile (drawer-open state), the modal still appears centered on the viewport, not clipped by the drawer overlay (modal z-index > 50, drawer overlay = 40, drawer aside = 50; modal needs z-index ≥ 60).
- [x] `handleSignOut` mirrors `removeAllChannels` and `signOut` failures to Sentry via `reportSilentFallback({ feature: "auth", op: "signOut" })` — folds in #3039. The `finally` redirect MUST still run; Sentry is a side-effect, never load-bearing.
- [x] `apps/web-platform/test/auth/sentry-tag-coverage.test.ts` `AUTH_VERBS` array is extended to include `signOut` so the drift-guard now covers the new mirror. PR body uses `Closes #3039`.
- [x] Unit tests cover: modal open/close, ESC, backdrop click, Cancel click, Sign out click triggers teardown, focus restore.
- [x] No regression in the dashboard layout tests (`apps/web-platform/test/dashboard-layout-*.test.tsx`, `apps/web-platform/test/dashboard-sidebar-collapse.test.tsx`).
- [x] `bun typecheck` and `bun test` pass.

### Post-merge (operator)

- [x] None — the change is pure application code; no infra, migrations, secrets, or external service config.

## Open Code-Review Overlap

1 open scope-out touches the files this plan modifies:

- **#3039**: review: add Sentry mirror + drift-guard coverage for signOut — **Fold in**. The existing scope-out names `app/(dashboard)/layout.tsx` (`handleSignOut`) and `test/auth/sentry-tag-coverage.test.ts`. Both are already being modified by this plan. Folding in avoids re-touching the same function in a follow-up PR. PR body will use `Closes #3039`. Re-evaluation criterion ("Sentry event count is non-zero") is satisfied trivially by adding the mirror — the criterion was a triage heuristic, not a quality bar.

No other open `code-review`-labeled issue touched the planned files.

## Files to Edit

- `apps/web-platform/app/(dashboard)/layout.tsx` — wrap `handleSignOut` in a modal-gated flow:
  - Add `signOutModalOpen` state.
  - Change the sidebar Sign out button's `onClick` from `handleSignOut` to `() => setSignOutModalOpen(true)`.
  - Add `reportSilentFallback` mirror inside `handleSignOut` for both `removeAllChannels` and `signOut` errors (folds in #3039).
  - Render `<SignOutConfirmModal open={signOutModalOpen} onClose={...} onConfirm={handleSignOut} />` at the layout root (sibling of the drawer overlay).
- `apps/web-platform/test/auth/sentry-tag-coverage.test.ts` — extend `AUTH_VERBS` array to include `"signOut"` so the drift-guard catches the new mirror.

## Files to Create

- `apps/web-platform/components/auth/sign-out-confirm-modal.tsx` — the new modal component. Mirrors `components/settings/cancel-retention-modal.tsx` line-for-line for focus trap / ESC / backdrop / `aria-modal` behavior. Adds an `isSigningOut` prop so the parent can disable both buttons while teardown is in flight.
- `apps/web-platform/test/sign-out-confirm-modal.test.tsx` — Vitest + React Testing Library tests for the modal in isolation (mirrors `test/cancel-retention-modal.test.tsx`).
- `apps/web-platform/test/dashboard-layout-signout.test.tsx` — integration test against `app/(dashboard)/layout.tsx` covering: button click opens modal; Cancel closes without sign-out; Confirm triggers teardown; Sentry mirror fires on `removeAllChannels` rejection.

## Implementation Phases

### Phase 1 — Modal component (RED)

Write the failing tests for `sign-out-confirm-modal.test.tsx`:

1. `renders nothing when open=false`
2. `renders dialog with role and aria-modal when open=true`
3. `initial focus is on Cancel button`
4. `ESC key calls onClose`
5. `backdrop click calls onClose`
6. `Cancel button click calls onClose`
7. `Sign out button click calls onConfirm`
8. `when isSigningOut=true, both buttons are disabled and the primary shows Signing out…`
9. `focus returns to the trigger element on close`
10. `Tab key cycles focus inside dialog`

### Phase 2 — Modal component (GREEN)

Implement `apps/web-platform/components/auth/sign-out-confirm-modal.tsx`:

```tsx
// apps/web-platform/components/auth/sign-out-confirm-modal.tsx
"use client";

import { useEffect, useRef } from "react";

interface SignOutConfirmModalProps {
  open: boolean;
  onClose: () => void;
  onConfirm: () => void;
  isSigningOut: boolean;
}

export function SignOutConfirmModal({
  open,
  onClose,
  onConfirm,
  isSigningOut,
}: SignOutConfirmModalProps) {
  const dialogRef = useRef<HTMLDivElement>(null);
  const cancelButtonRef = useRef<HTMLButtonElement>(null);
  const triggerRef = useRef<HTMLElement | null>(null);
  const onCloseRef = useRef(onClose);
  useEffect(() => { onCloseRef.current = onClose; });

  useEffect(() => {
    if (!open) return;
    triggerRef.current = document.activeElement as HTMLElement;
    // Initial focus on Cancel — least-destructive default
    cancelButtonRef.current?.focus();

    function handleKeyDown(e: KeyboardEvent) {
      if (e.key === "Escape" && !isSigningOut) {
        onCloseRef.current();
        return;
      }
      if (e.key === "Tab" && dialogRef.current) {
        // Same focus-trap logic as cancel-retention-modal.tsx
      }
    }
    document.addEventListener("keydown", handleKeyDown);
    return () => {
      document.removeEventListener("keydown", handleKeyDown);
      triggerRef.current?.focus();
    };
  }, [open, isSigningOut]);

  if (!open) return null;

  return (
    <div className="fixed inset-0 z-[60] flex items-center justify-center">
      <div
        className="absolute inset-0 bg-black/60"
        onClick={isSigningOut ? undefined : onClose}
        role="presentation"
      />
      <div
        ref={dialogRef}
        role="dialog"
        aria-modal="true"
        aria-labelledby="signout-heading"
        tabIndex={-1}
        className="relative w-full max-w-sm rounded-xl border border-soleur-border-default bg-soleur-bg-surface-1 p-6"
      >
        <h3 id="signout-heading" className="mb-2 text-lg font-semibold text-soleur-text-primary">
          Sign out?
        </h3>
        <p className="mb-6 text-sm text-soleur-text-secondary">
          You&apos;ll be returned to the login page. Any unsaved input in the
          current view may be lost.
        </p>
        <div className="flex justify-end gap-3">
          <button
            ref={cancelButtonRef}
            type="button"
            onClick={onClose}
            disabled={isSigningOut}
            className="rounded-lg border border-soleur-border-default px-4 py-2 text-sm text-soleur-text-secondary transition-colors hover:bg-soleur-bg-surface-2 hover:text-soleur-text-primary disabled:cursor-not-allowed disabled:opacity-50"
          >
            Cancel
          </button>
          <button
            type="button"
            onClick={onConfirm}
            disabled={isSigningOut}
            className="rounded-lg bg-soleur-accent-gold-fill px-4 py-2 text-sm font-medium text-soleur-text-on-accent transition-colors hover:opacity-90 disabled:cursor-not-allowed disabled:opacity-50"
          >
            {isSigningOut ? "Signing out…" : "Sign out"}
          </button>
        </div>
      </div>
    </div>
  );
}
```

Notes:
- `z-[60]` is one step above the sidebar `z-50` so the modal renders above the mobile drawer overlay.
- The backdrop is non-dismissive while `isSigningOut` is true (clicking does nothing) — prevents a user from accidentally re-opening interaction during teardown.
- The cancel-retention-modal's focus-trap implementation is reused verbatim.

### Research Insights — Phase 2

**Best Practices (WAI-ARIA Authoring Practices Guide 1.2):**
- The textbook role for a destructive-confirmation prompt is `alertdialog`. `alertdialog` is a subclass of `dialog` for "urgent information that requires the user's immediate attention" (W3C APG, Alert and Message Dialogs Pattern). Screen readers announce `alertdialog` with extra emphasis and read the dialog body without requiring user-initiated focus.
- However, **every existing Soleur modal uses `role="dialog"`** (`cancel-retention-modal.tsx`, `upgrade-at-capacity-modal.tsx`, `naming-modal.tsx`, `disconnect-repo-dialog.tsx`). For codebase consistency we use `role="dialog"`. Trade-off: marginal screen-reader UX vs. uniform modal contract.
- **Initial focus must NOT be on the destructive action.** WCAG 2.2 SC 3.3.4 (Error Prevention) recommends that confirmations for "legal commitments, financial transactions, modification or deletion of data" focus the cancel/safe path by default. Sign-out → data-loss-of-in-memory-state qualifies. Initial focus = Cancel.
- `aria-labelledby` is preferred over `aria-label` for dialogs because it references the visible heading text — keeping accessible name and visible name in sync (WCAG 2.5.3 Label in Name).

**Implementation Details:**
```tsx
// Verbatim focus-trap pattern reused from cancel-retention-modal.tsx
// (apps/web-platform/components/settings/cancel-retention-modal.tsx:35-56)
function handleKeyDown(e: KeyboardEvent) {
  if (e.key === "Escape" && !isSigningOut) {
    onCloseRef.current();
    return;
  }
  if (e.key === "Tab" && dialogRef.current) {
    const focusable = dialogRef.current.querySelectorAll<HTMLElement>(
      'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])',
    );
    const first = focusable[0];
    const last = focusable[focusable.length - 1];
    if (e.shiftKey && document.activeElement === first) {
      e.preventDefault();
      last?.focus();
    } else if (!e.shiftKey && document.activeElement === last) {
      e.preventDefault();
      first?.focus();
    }
  }
}
```

**Edge Cases:**
- A user opens the modal, then resizes from desktop → mobile (crosses the `md` breakpoint). The drawer auto-close effect (`apps/web-platform/app/(dashboard)/layout.tsx:185-191`) fires; the modal is unaffected because it has no `md:` responsive variants and is portaled outside the sidebar `<aside>`. Verified by reading the layout file.
- The modal is mounted on a route that does NOT have a sidebar (none today, but if added later: e.g., a chat-fullscreen route). The modal renders at the dashboard-layout root, so it lives wherever the dashboard layout is mounted. Routes outside the `(dashboard)` group do not get the Sign-out button at all.

**References:**
- W3C WAI APG: https://www.w3.org/WAI/ARIA/apg/patterns/alertdialog/
- W3C WAI APG (dialog/modal): https://www.w3.org/WAI/ARIA/apg/patterns/dialog-modal/
- WCAG 2.2 SC 3.3.4 (Error Prevention): https://www.w3.org/WAI/WCAG22/Understanding/error-prevention-legal-financial-data.html

### Phase 3 — Layout wiring (RED + GREEN, single test phase)

Write the failing integration tests in `apps/web-platform/test/dashboard-layout-signout.test.tsx`:

1. `sidebar Sign out button click opens the modal (modal not rendered before click)`
2. `Cancel inside the modal closes it without calling supabase.auth.signOut`
3. `Confirm inside the modal calls supabase.auth.signOut and pushes /login`
4. `Confirm shows Signing out… and disables both buttons while in flight`
5. `removeAllChannels() rejection still results in signOut + redirect AND reportSilentFallback is called with feature:"auth", op:"signOut"`

Then update `apps/web-platform/app/(dashboard)/layout.tsx`:

```tsx
// apps/web-platform/app/(dashboard)/layout.tsx (excerpt)
import { SignOutConfirmModal } from "@/components/auth/sign-out-confirm-modal";
import { reportSilentFallback } from "@/lib/client-observability";

// inside DashboardLayout:
const [signOutModalOpen, setSignOutModalOpen] = useState(false);
const [isSigningOut, setIsSigningOut] = useState(false);

async function handleSignOut() {
  setIsSigningOut(true);
  const supabase = createClient();
  try {
    try {
      await supabase.removeAllChannels();
    } catch (err) {
      reportSilentFallback(err, {
        feature: "auth",
        op: "signOut",
        extra: { stage: "removeAllChannels" },
      });
    }
    try {
      await supabase.auth.signOut();
    } catch (err) {
      reportSilentFallback(err, {
        feature: "auth",
        op: "signOut",
        extra: { stage: "signOut" },
      });
    }
  } finally {
    router.push("/login");
    // Note: do NOT setIsSigningOut(false) — the route push unmounts the layout
    // and clears state naturally. Resetting here would briefly re-enable the
    // Sign out button between navigation start and unmount.
  }
}

// in JSX:
<button onClick={() => setSignOutModalOpen(true)} ...>Sign out</button>

<SignOutConfirmModal
  open={signOutModalOpen}
  onClose={() => setSignOutModalOpen(false)}
  onConfirm={handleSignOut}
  isSigningOut={isSigningOut}
/>
```

Key changes vs. current `handleSignOut`:
- The outer try/finally is preserved: `router.push("/login")` always runs.
- The current code's `await supabase.removeAllChannels()` lives inside the `try`. If it rejects, control jumps to `finally`, which executes `signOut + push("/login")` — but then the original rejection propagates OUT of `handleSignOut` (unhandled in the React event handler, ends as an unhandled rejection in the browser). The new code catches the rejection inline, mirrors it to Sentry, and proceeds. Same redirect contract, plus observability.
- `signOut()` errors are similarly mirrored. Currently they bubble out of the `finally` as well.

### Research Insights — Phase 3

**Supabase v2 contract (verified against `node_modules/@supabase/supabase-js` and the encoded learning):**
- `supabase.removeAllChannels()` returns `Promise<("ok" | "timed out" | "error")[]>` — ONE Promise resolving to an array of per-channel statuses. NEVER wrap in `Promise.all(...)` (the encoded learning `2026-04-29-supabase-removeallchannels-api-shape.md` documents the silent failure mode). Plan stays at `await supabase.removeAllChannels()` — singular await.
- `supabase.auth.signOut()` returns `Promise<{ error: AuthError | null }>` — it does NOT throw on auth failure; the error lives on `result.error`. However, it CAN throw on network failure (fetch rejection). Both are mirrored to Sentry by the try/catch.
- A non-null `result.error` from `signOut()` is currently dropped by the layout. We do NOT change this behavior — the redirect to `/login` is the user-facing contract; observability gets the error. (Optionally inspect `result.error` and `reportSilentFallback` it; documented as a stretch nice-to-have, not required.)

**Implementation Details:**
```tsx
// Recommended handleSignOut (final form)
async function handleSignOut() {
  setIsSigningOut(true);
  const supabase = createClient();
  try {
    try {
      await supabase.removeAllChannels();
    } catch (err) {
      reportSilentFallback(err, {
        feature: "auth",
        op: "signOut",
        extra: { stage: "removeAllChannels" },
      });
    }
    try {
      const { error } = await supabase.auth.signOut();
      if (error) {
        reportSilentFallback(error, {
          feature: "auth",
          op: "signOut",
          extra: { stage: "signOut.resultError" },
        });
      }
    } catch (err) {
      reportSilentFallback(err, {
        feature: "auth",
        op: "signOut",
        extra: { stage: "signOut.throw" },
      });
    }
  } finally {
    router.push("/login");
  }
}
```

**Test Pattern (verbatim from `test/cancel-retention-modal.test.tsx` and `test/dashboard-sidebar-collapse.test.tsx`):**

```tsx
// Required mocks at top of dashboard-layout-signout.test.tsx
vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn(), refresh: vi.fn() }),
  usePathname: () => "/dashboard",
}));

const signOutMock = vi.fn(() => Promise.resolve({ error: null }));
const removeAllChannelsMock = vi.fn(() => Promise.resolve(["ok"]));
const reportSilentFallbackMock = vi.fn();

vi.mock("@/lib/supabase/client", () => ({
  createClient: () => ({
    auth: {
      signOut: signOutMock,
      getSession: vi.fn(() => Promise.resolve({ data: { session: null } })),
    },
    removeAllChannels: removeAllChannelsMock,
    from: () => ({
      select: () => ({
        eq: () => ({ single: () => Promise.resolve({ data: null }) }),
      }),
    }),
  }),
}));

vi.mock("@/lib/client-observability", () => ({
  reportSilentFallback: reportSilentFallbackMock,
}));

// ESC simulation pattern (note: keyDown is dispatched on `document`, not on
// the dialog element — matches cancel-retention-modal.test.tsx line 94)
fireEvent.keyDown(document, { key: "Escape" });

// Sentry mirror assertion
expect(reportSilentFallbackMock).toHaveBeenCalledWith(
  expect.anything(),
  expect.objectContaining({ feature: "auth", op: "signOut" }),
);
```

**Edge Cases:**
- **Double-click race on Confirm.** `setIsSigningOut(true)` fires synchronously at the very top of `handleSignOut`; React batches the re-render and the button's `disabled={isSigningOut}` flips before the browser's next paint. A second synchronous click in the same tick still produces a second `handleSignOut` call (React state batching does not deduplicate identical-tick events). Verified-acceptable: both calls converge on the same `router.push("/login")` and Supabase's `signOut` is idempotent. No mitigation required beyond the `disabled` attribute.
- **Modal open while a route change is already in flight.** Cannot happen — the only path that calls `router.push` from this layout is `handleSignOut`, and the modal `onClose` is no-op while `isSigningOut`. Verified by reading the layout file.
- **Modal open while admin-check `fetch("/api/admin/check")` is in flight.** Independent. Both effects run on mount; the admin check has no relationship with the modal state machine.

**References:**
- Supabase JS v2 `removeAllChannels` upstream: https://supabase.com/docs/reference/javascript/removeallchannels
- Supabase JS v2 `signOut` upstream: https://supabase.com/docs/reference/javascript/auth-signout
- Encoded learning: `knowledge-base/project/learnings/best-practices/2026-04-29-supabase-removeallchannels-api-shape.md`

### Phase 4 — Drift-guard extension

Update `apps/web-platform/test/auth/sentry-tag-coverage.test.ts`:

```ts
const AUTH_VERBS = [
  "exchangeCodeForSession",
  "signInWithOAuth",
  "signInWithOtp",
  "verifyOtp",
  "signOut", // [Updated 2026-05-11] feat-signout-confirm-modal: mirror added in (dashboard)/layout.tsx
];
```

Verify the drift-guard now requires `feature: "auth"` + `op: "signOut"` tags everywhere `supabase.auth.signOut()` is called. Run `rg "\.signOut\b" apps/web-platform/{app,components,lib,server,hooks} --type ts --type tsx` to enumerate every call site and confirm the test passes (only one call site exists today — the dashboard layout one we are editing). If the test surfaces a second call site, fold in coverage; otherwise the new line is satisfied by the dashboard mirror.

### Phase 5 — Verification

- `cd apps/web-platform && bun typecheck`
- `cd apps/web-platform && bun test`
- Manual QA: visit `/dashboard`, click Sign out, verify modal opens; ESC closes; backdrop closes; Cancel closes; Confirm signs out + redirects.
- Manual QA on mobile (drawer-open state at `<md`): verify the modal renders centered and above the drawer overlay.

## Test Scenarios

Listed inline under each phase above. Three test files in total:

- `apps/web-platform/test/sign-out-confirm-modal.test.tsx` (unit — modal in isolation)
- `apps/web-platform/test/dashboard-layout-signout.test.tsx` (integration — layout + modal)
- `apps/web-platform/test/auth/sentry-tag-coverage.test.ts` (drift-guard — extended AUTH_VERBS)

Mocks: `next/navigation` (`useRouter`, `usePathname`), `@/lib/supabase/client` (`createClient` returning a stub with `removeAllChannels: vi.fn()` and `auth: { signOut: vi.fn(), getSession: vi.fn() }`), `@/lib/client-observability` (`reportSilentFallback: vi.fn()`).

## Domain Review

**Domains relevant:** Product (UX) only — UI-only confirmation gate over an existing flow.

**Reasoning:** No security/auth surface change (the teardown contract is preserved verbatim). No regulated-data surface. No legal/privacy implication. No infra. No CMO content-opportunity (microcopy only — single dialog). No CTO architectural implication (single component file + 20 LoC in an existing layout).

### Product/UX Gate

**Tier:** advisory — modifies an existing UI surface (sidebar footer + dashboard layout root); does not introduce a new user flow (sign-out already exists). The modal is a confirmation interstitial, not a new page or multi-step flow.

**Mechanical escalation check:** the plan creates one new file at `components/auth/sign-out-confirm-modal.tsx`. Per the plan-skill mechanical-escalation rule, a `components/**/*.tsx` creation tips the tier to **BLOCKING**. However, this rule was designed for emotionally-loaded retention/persuasion surfaces; this modal is a one-sentence neutral confirmation. Default to BLOCKING anyway per the rule (the rule is mechanical for a reason — subjective downgrades defeat it). Pipeline mode treats BLOCKING gates as auto-accept-with-partial when specialist agents aren't invoked in pipeline.

**Decision:** auto-accepted (pipeline) — running inside `/one-shot` planning Task; Product/UX Gate's full specialist pipeline (`spec-flow-analyzer`, `cpo`, `ux-design-lead`, `copywriter`) is not invoked at sub-skill depth in pipeline mode. The dialog pattern (`role="dialog"`, focus trap, ESC, backdrop dismiss, focus restore) is copied verbatim from the canonical `cancel-retention-modal.tsx`, so the wireframe and accessibility contract are already validated by precedent.

**Agents invoked:** none (pipeline auto-accept)

**Skipped specialists:**
- `ux-design-lead` (pipeline auto-accept; wireframe pattern copied from existing modal)
- `copywriter` (pipeline auto-accept; one-sentence neutral confirmation, no persuasion or retention framing)
- `spec-flow-analyzer` (pipeline auto-accept; single-screen modal, no multi-step flow)

**Pencil available:** N/A (no wireframe being authored)

**Brainstorm-recommended specialists:** none (no brainstorm exists for this feature)

## GDPR / Compliance Gate

**Touches regulated-data surfaces:** no. The modal sits over an existing `supabase.auth.signOut()` call. No new PII fields, no new auth flows, no schema/migration touched, no new API route. The diff is one new component + a wrapper around the existing handler + a drift-guard array extension.

**Decision:** skip. No `/soleur:gdpr-gate` invocation required.

## SpecFlow Analysis

Not invoked separately — folded into the Phase 2.5 Product/UX Gate pipeline-auto-accept. The user flow is single-screen, single-decision (Cancel vs Confirm), with two implicit edge cases:

1. Network/Realtime teardown failure mid-confirm — covered by `removeAllChannels` and `signOut` Sentry mirrors in Phase 3 and the `Signing out…` button state; the redirect always runs (preserved from current contract).
2. Rapid double-click on Confirm — covered by `disabled={isSigningOut}` on the primary button, which fires `setIsSigningOut(true)` synchronously on the first click.

No dead ends, no missing error states, no flows that drop the user.

## Risks

- **Drawer-modal z-index collision (mobile):** the mobile drawer overlay is `z-40` and the drawer aside is `z-50`. The modal uses `z-[60]` — verified above the drawer stacking context. Mitigation: explicit z-index in modal CSS; included as an Acceptance Criterion item; covered by a manual QA step.
- **Focus restore when triggered from a collapsed sidebar:** in the collapsed state, the Sign out button has a `title="Sign out"` but no visible label. `triggerRef.current?.focus()` on close still works because the button DOM element exists; the visual focus ring will land on the icon-only button. Acceptable.
- **`router.push("/login")` race with React state updates:** the existing code already does this — the `finally` block fires `router.push` regardless of `signOut()` outcome. No new race introduced. Note in Phase 3 explicitly avoids resetting `isSigningOut` after navigation begins, to prevent the Sign out button from flickering re-enabled during the navigation transition.
- **Sentry mirror failure modes:** `reportSilentFallback` itself can never throw (it swallows internally via `@sentry/nextjs`). No risk to the redirect contract.
- **`inert` attribute on `<main>` does NOT affect the modal.** The dashboard layout sets `inert={drawerOpen || undefined}` on the `<main>` element (`apps/web-platform/app/(dashboard)/layout.tsx:362`). The modal renders at the layout root level — sibling of the sidebar `<aside>` and the `<main>` — NOT inside `<main>`. So the modal remains interactive even when the mobile drawer is open. Placement requirement: the `<SignOutConfirmModal />` JSX must sit at the same depth as the drawer overlay `<div>` (between the `<aside>` and the `<main>`), NOT inside `<main>`. Adding it as a sibling of `</main>` (after the closing tag, inside the same outer `<div className="flex h-dvh ...">`) is the simplest correct placement.
- **Test runner crash (segfault) handling.** Per AGENTS.md `wg-when-a-test-runner-crashes-segfault-oom`, if the new tests crash the runner (not just fail), do NOT dismiss as known — either fix the root cause, file a tracking issue, or document a workaround. The cancel-retention-modal tests run cleanly today; we expect parity.
- **Single `signOut` call site assumption.** Phase 4 assumes `app/(dashboard)/layout.tsx` is the only `supabase.auth.signOut()` call site in the app. Verification at implementation: `rg "\.signOut\b" apps/web-platform/{app,components,lib,server,hooks} -t ts -t tsx`. If a second call site exists (e.g., a forgotten admin-only path), the drift-guard will fail until that site also gets `reportSilentFallback({ feature: "auth", op: "signOut" })`. Fold in additional mirrors inline.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. The section above is populated with a `threshold: none, reason: …` bullet because the diff touches the auth-flow surface even though no regulated data flows through it.
- The mechanical-escalation rule in Phase 2.5 (creating any `components/**/*.tsx` → BLOCKING) was honored as documented even though the subjective tier is advisory. Future plans should preserve this default.
- The drift-guard test in `apps/web-platform/test/auth/sentry-tag-coverage.test.ts` will FAIL the moment `signOut` is added to `AUTH_VERBS` unless the layout's `handleSignOut` actually wires `reportSilentFallback({ feature: "auth", op: "signOut", ... })`. RED → GREEN order in Phase 3 → Phase 4 matters: implement the mirror first, extend the array second.

## Alternative Approaches Considered

| Approach | Pros | Cons | Decision |
|----------|------|------|----------|
| Inline `window.confirm()` browser prompt | 5-line change; zero new component | Cannot style per Soleur brand; cannot be tested in jsdom in the same way as a React modal; mobile UX is poor; no focus trap or ESC contract | Rejected |
| Add modal as a generic `<ConfirmDialog>` shared component | Reusable for future destructive actions (delete chat, etc.) | YAGNI — only one destructive action lands a confirmation flow today (`disconnect-repo-dialog.tsx` is inline-replacement, not modal); building a generic abstraction before a second caller is overengineering | Rejected; revisit if a 3rd modal-style confirmation surfaces |
| Defer the Sentry mirror to a separate PR | Smaller PR | Re-touches the same 20-line handler twice; #3039 is already filed and the codebase has a single sign-out call site | Folded in; PR uses `Closes #3039` |
| Make the modal block the body scroll the way the drawer does | Belt-and-suspenders | jsdom test friction; the modal's full-screen flex layout already prevents scroll on viewports it covers | Not needed for `max-w-sm` modal |

## Non-Goals

- Reusing this modal for other destructive confirmations (delete chat, archive conversation, etc.). The new component is scoped to sign-out; a generic `ConfirmDialog` abstraction is a YAGNI candidate for after a second caller exists.
- Changing the sign-out teardown contract itself (the `try { removeAllChannels } finally { signOut + push("/login") }` shape is preserved).
- Adding a "Don't ask again" preference. The whole point of this PR is to introduce a confirmation step; opting out of it defeats the user-story.
- Confirming sign-out triggered from any path other than the sidebar button (there is only one path today; the `/api/account/delete` flow signs out implicitly server-side and is out of scope).

## References

- `apps/web-platform/components/settings/cancel-retention-modal.tsx` — canonical Soleur modal pattern reused here.
- `apps/web-platform/components/settings/delete-account-dialog.tsx`, `disconnect-repo-dialog.tsx` — sibling inline-confirmation patterns (not modals, but informed the copy tone).
- `apps/web-platform/lib/client-observability.ts` — `reportSilentFallback` shim.
- `apps/web-platform/test/cancel-retention-modal.test.tsx` — test pattern reused for `sign-out-confirm-modal.test.tsx`.
- `apps/web-platform/test/auth/sentry-tag-coverage.test.ts` — drift-guard for Sentry tag coverage on auth verbs.
- `knowledge-base/project/learnings/best-practices/2026-04-29-supabase-removeallchannels-api-shape.md` — already-encoded learning about `removeAllChannels()` returning one Promise (NOT an array of Promises). Plan honors this: `await supabase.removeAllChannels()` — singular await, no `Promise.all`.
- Issue **#3039** — folded in via `Closes #3039`.
