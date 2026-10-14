---
module: Web Platform
date: 2026-09-28
problem_type: logic_error
component: frontend_react
symptoms:
  - A `usePendingAction` asyncFn awaited `onRemove(provider)` — which resolves void on BOTH success and HTTP failure — so a 500 DELETE released the button with the row still connected-looking and no error surface
  - Three review lenses independently missed the asymmetry at first pass; a structural-enumeration seat caught it by reading the PARENT's resolve contract, not the card's
root_cause: logic_error
resolution_type: code_fix
severity: medium
status: closed
tags: [pending-state, error-surface, non-ok-vs-throw, fetch, ui-action-feedback]
---

# Troubleshooting: A resolved void-returning handler is not a failure signal — check the callee's !res.ok contract, not just the caller's try/catch

## Problem

The #9053 conversion wrapped `await onRemove(provider)` in `try/catch` inside the
hook's asyncFn — the mechanically correct pattern — but the parent's `handleRemove`
resolved normally on `!res.ok` (`if (res.ok) setServices(...)`, no else). Result:
a DELETE returning HTTP 500 released `removing`, kept the row connected-looking,
and rendered nothing — the exact silent dead-click the change was prescribed to
kill. The card's catch only fired on a *thrown* error (network down), which is
the rarer failure shape.

## Diagnosis

When a caller's error handling depends on a prop callback's throw contract, the
call site proves nothing — read the callee. Two distinct failure classes live on
opposite sides of the await: thrown (network, abort, JSON parse) and resolved-
non-OK (HTTP status). A `try/catch` around the await covers the first only; the
second needs the callee to throw, or to return a discriminated result.

Companion timing trap the same sweep surfaced: `fireEvent.click` +
same-tick `getByRole("alert")` asserts on pre-transition DOM — a handler moved
inside `usePendingAction`'s `startTransition` flushes its `setState` one tick
later, so regression tests asserting synchronously on the error surface flake
red even though the user-visible behavior is unchanged. Assert on settled
state (`await waitFor`).

## Fix

- Parent `handleRemove` now `throw`s on `!res.ok` (`connected-services-content.tsx`),
  so the card's `removeError` surface fires on the common failure shape; added a
  non-OK test (the original test stubbed a throw, pinning only the rarer class).
- Litmus for pending-conversion review: *which of {throw, resolve-non-OK,
  resolve-empty} does each awaited prop callback return?* — enumerate per prop,
  not per call site.

## Related

- `2026-09-27-resolution-is-not-terminality-and-a-zombie-episode-can-kill-the-retry.md` —
  the latch/epoch sibling class (resolution is not terminality); this one is the
  mirror (resolution is not *success* either).
