# Tasks: feat-ui-action-feedback

Plan: `knowledge-base/project/plans/2026-09-25-feat-ui-action-feedback-plan.md` · Issue: #8917 · PR: #8904

## Phase 1: Foundation

- [ ] 1.1 `lib/nav-pending-store.ts` — module-level store, `startNavPending(trigger)`/`stopNavPending()`, idempotent start, last-location ref
- [ ] 1.2 `components/nav/nav-pending-island.tsx` — `useSyncExternalStore` island: bar (`top: env(safe-area-inset-top)`, gold per-palette token), 150–200ms entry delay, ~400ms min-visible (idempotent through hold), ~30s stall timeout + Sentry breadcrumb, `role="status"` live region announcing on bar-show only, popstate listener with `isSameDocTarget`, completion watcher on pathname+searchParams; mount once (Suspense-wrapped) in `app/layout.tsx`
- [ ] 1.3 `components/ui/button.tsx` — forwardRef `Button` (`variant` gold|outlined|ghost|danger, `loading` → disabled+aria-busy+leading SpinnerIcon after ~150ms delay, icon-only content-replacement, `type` no-default, className merge, rest-prop passthrough, press affordance scale-98/opacity-90/120ms, pending opacity 0.55/0.65, reduced-motion)
- [ ] 1.4 `hooks/use-pending-action.ts` — `{run, pending, error}`, `pendingRef`, `opts.latchOnRedirect`, focus-restore-on-resolve, ~30s Sentry breadcrumb watchdog
- [ ] 1.5 `hooks/use-pending-router.ts` — `push`/`replace` skip `start()` on `isSameDocTarget` but still delegate; `refresh`/`back`/`forward`/`prefetch` passthrough; `new URL(href, location.href)` normalization
- [ ] 1.6 `components/ui/nav-link.tsx` — `next/link` + `onNavigate` → `start()` gated on `isSameDocTarget`
- [ ] 1.7 `globals.css` — press affordance, bar keyframes (reuse `refresh-shimmer`), reduced-motion carve-out
- [ ] 1.8 `scripts/check-button-primitive-sweep.sh` + `test/components/button-primitive-sweep.test.ts` — ratchet sentinel (baseline = current native `<button>` count; may only decrease) + `data-button-exempt` reason assertion
- [ ] 1.9 Vitest: store/island (delay, min-visible hold, stall, idempotency, same-target), hook (lifecycle, error, focus restore, latch), NavLink, usePendingRouter (delegate/no-op/passthrough)

## Phase 2: Navigation wiring sweep

- [ ] 2.1 Swap `next/link` → `NavLink` across ~32 files
- [ ] 2.2 Swap `useRouter` → `usePendingRouter` at ~16 push/replace files (refresh-only callers untouched)
- [ ] 2.3 Convert ~16 real internal raw anchors to `NavLink`; verify `/api/`, `mailto:`, external, `#fragment` anchors stay native
- [ ] 2.4 Verify `window.location.*` hard-nav sites unchanged (merge-base diff)

## Phase 3: Button migration sweep (ratchet active; domain-grouped commits)

- [ ] 3.1 Tier 1 (~40 files): billing/auth/consent/send/delete/invite — incl. `billing-section.tsx` Reactivate guard + `redirectTo` latch fix, `sign-out-confirm-modal`, `oauth-buttons`, `scope-grants/*`, `delegation-acceptance-modal`, `bash-autonomous-toggle*`
- [ ] 3.2 **Tier-1 review checkpoint (CPO C4)** — billing/consent diffs get dedicated review before Tier 2
- [ ] 3.3 Tier 2 (~45 files): mutation/form sites (settings, workstream, routines, inbox, crm, connect-repo); 14 `<form>` sites get line-item `type` audit
- [ ] 3.4 Tier 3 (~40 files): pure-UI toggles — press affordance only
- [ ] 3.5 Migrate ~22 `GoldButton`/`OutlinedButton` call sites → `Button`; delete both files
- [ ] 3.6 Generate migration manifest (per-file `mechanical | manual | exempt`) for the PR body; prop-parity check (`data-testid`/`data-tour-id`/`aria-*`)

## Phase 4: Typed-confirm "Sending…"

- [ ] 4.1 `hooks/use-action-send.ts` — keep modal open, `confirmPending` in transition, close on resolution
- [ ] 4.2 `typed-confirm-modal.tsx` — pending render (spinner + "Sending…" + locked input), dismiss suppression via `onClose={pending ? undefined : onCancel}` (Esc/backdrop/close/drag all inert), focus→status, `aria-live` outcome; on failure focus→alert + `SEND` persists
- [ ] 4.3 ~8s "Still working…" escalation at ~3 irreversible/billing sites (reserved-space sublabel, per-episode timer reset)

## Phase 5: Verification + close-out

- [ ] 5.1 `e2e/nav-states-nav-pending.e2e.ts` — authenticated project: bar per channel (Link/push/popstate), clears on commit incl. `?query`, no flash under delay, Enter-during-pending no-resubmit
- [ ] 5.2 Guard 1 mutation-matrix rows verified (mount removal, searchParams watcher, delay, stall, same-URL, idempotency)
- [ ] 5.3 Telemetry: `track("nav_duration_ms", {path: "nav:<trigger>:<section>"})` enum-only; Sentry breadcrumb for durations
- [ ] 5.4 ADR write (provisional ordinal; records exemption budget + revert-unit rule + telemetry-gap drift detector)
- [ ] 5.5 `components/ui/README.md` + one pointer line in root `CLAUDE.md`; reconcile `spec.md` FR1/TR1 mount point
- [ ] 5.6 `web-v*` polish release note ("clearer, more responsive feedback" — never "faster/snappier")

## Deferred (not this PR)

- #8918 — `/api/checkout` server-side idempotency/session reuse
- `loading.tsx` expansion — parallel perf session
- Primitives-supremacy ESLint rule — productize candidate (ADR references)
- ~30s+ mutation abort/cancel affordance — accepted residual; Sentry breadcrumb covers observability
