---
title: "feat: Add sign-out confirmation modal"
type: feat
date: 2026-05-11
branch: feat-one-shot-signout-confirm-popup
requires_cpo_signoff: false
---

# feat: Add sign-out confirmation modal

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

- [ ] Clicking the sidebar "Sign out" button opens a modal instead of signing out immediately.
- [ ] Modal contains a heading ("Sign out?"), a one-sentence body explaining what will happen, and two CTAs: "Sign out" (primary) and "Cancel" (secondary).
- [ ] Modal renders with `role="dialog"` and `aria-modal="true"` and `aria-labelledby` pointing to the heading.
- [ ] Pressing ESC closes the modal without signing the user out.
- [ ] Clicking the backdrop closes the modal without signing the user out.
- [ ] Clicking "Cancel" closes the modal without signing the user out.
- [ ] Clicking "Sign out" runs the existing teardown contract verbatim: `try { await supabase.removeAllChannels() } finally { await supabase.auth.signOut(); router.push("/login") }`.
- [ ] While the sign-out is in flight, the "Sign out" button shows a `Signing out…` label and is `disabled`; the "Cancel" button is also disabled (no escape from the teardown).
- [ ] Focus moves into the modal on open (initial focus on the Cancel button — least-destructive default) and returns to the sidebar Sign out button on close.
- [ ] Tab key cycles focus inside the modal; Shift+Tab from the first element wraps to the last.
- [ ] Modal works in both collapsed and expanded sidebar states (the modal is portaled/positioned independently of the sidebar collapse state).
- [ ] On mobile (drawer-open state), the modal still appears centered on the viewport, not clipped by the drawer overlay (modal z-index > 50, drawer overlay = 40, drawer aside = 50; modal needs z-index ≥ 60).
- [ ] `handleSignOut` mirrors `removeAllChannels` and `signOut` failures to Sentry via `reportSilentFallback({ feature: "auth", op: "signOut" })` — folds in #3039. The `finally` redirect MUST still run; Sentry is a side-effect, never load-bearing.
- [ ] `apps/web-platform/test/auth/sentry-tag-coverage.test.ts` `AUTH_VERBS` array is extended to include `signOut` so the drift-guard now covers the new mirror. PR body uses `Closes #3039`.
- [ ] Unit tests cover: modal open/close, ESC, backdrop click, Cancel click, Sign out click triggers teardown, focus restore.
- [ ] No regression in the dashboard layout tests (`apps/web-platform/test/dashboard-layout-*.test.tsx`, `apps/web-platform/test/dashboard-sidebar-collapse.test.tsx`).
- [ ] `bun typecheck` and `bun test` pass.

### Post-merge (operator)

- [ ] None — the change is pure application code; no infra, migrations, secrets, or external service config.

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
- The inner `removeAllChannels()` is wrapped in its own try/catch + Sentry mirror so a Realtime teardown error does not skip `signOut()` (the current code's `await` on `removeAllChannels()` *would* throw out of the `try` and skip the inner `await signOut()` — the current `finally` only runs `signOut()` because... wait — re-read the current code: the current `finally` runs `signOut() + push`, so a `removeAllChannels` throw does *not* skip them. We preserve that contract: redirect always happens. But we now mirror the `removeAllChannels` error to Sentry instead of swallowing it silently.
- `signOut()` errors are also mirrored to Sentry — currently they bubble unhandled.

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
