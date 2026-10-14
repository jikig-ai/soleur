# Session State — chore-one-shot-9053-pending-sites (#9053 / PR #9155)

## Where we are

Implementation + review-revision complete, PR #9155 marked ready with
auto-merge queued (squash). Branch synced with main (merge ce85ee43e7,
clean). CI running on the synced HEAD.

## Done

- All 13 grandfathered hand-rolled pending sites converted to
  `usePendingAction` — zero exemptions. Per-row granularity preserved
  (each row/card owns its hook).
- New error surfaces: delegation-acceptance-modal `role="alert"`;
  connected-services `removeError` (parent `handleRemove` now throws on
  non-OK — review-found P2).
- `create-project-state` uses `latch()` (canonical teardown-terminal site).
- `today-card` keeps `AbortSignal.timeout(PENDING_WATCHDOG_MS)` bounds.
- README §Deliberate non-adoptions drained.
- New tests: create-project latch-hold, connected-services remove
  (throw + non-OK), delegation-modal failure surfaces.
- Review: 3 lenses (structural-enumeration, code-quality, test-design);
  convergent P2 (non-OK remove swallow) + P3s resolved in-branch.
- Residual out-of-scope hand-rolled sites filed as #9162.
- Review trailer emitted (Reviewed-Coverage: full 3/3).

## Remaining

- CI on synced HEAD → auto-merge → post-merge verify (files on main).
- #9093: PR #9164 in flight separately (docs/compound, auto-merge queued).
