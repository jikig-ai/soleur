---
title: "Tasks — fix(workspace): workspace-switch two-phase-commit"
issue: 4917
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-04-fix-workspace-switch-two-phase-commit-plan.md
brand_survival_threshold: single-user incident
---

# Tasks — Workspace-switch two-phase-commit fix (#4917)

Derived from `knowledge-base/project/plans/2026-06-04-fix-workspace-switch-two-phase-commit-plan.md`.
Single-component client-logic fix. No migration / RPC / server / infra change.

## Phase 1 — Setup / RED (failing tests first, per cq-write-failing-tests-before)

- [ ] 1.1 Read `apps/web-platform/components/dashboard/org-switcher-container.tsx` and
  `apps/web-platform/test/org-switcher-container.test.tsx` in full; confirm the post-RPC catch
  at `:95-98` and `handleCancel` at `:115` match the plan's Problem Detail.
- [ ] 1.2 Add failing test: **post-RPC failure force-completes / shows no Cancel** (Test
  Scenario 1) — `mockRpc` resolves `{ error: null }`, `mockRefreshSession` rejects; assert
  `assignMock` called with `/dashboard` AND `queryByRole("button", { name: /cancel/i })` null.
- [ ] 1.3 Add failing test: **pre-RPC failure preserves Retry+Cancel** (Test Scenario 2) —
  regression guard; assert both buttons present, `assignMock` not called.
- [ ] 1.4 Add failing test: **post-RPC offline messaging is honest** (Test Scenario 3) — stub
  `navigator.onLine = false`; assert copy names target workspace + "saved/will finish on
  reconnect", NOT "couldn't switch".
- [ ] 1.5 Add failing test: **bounded retry** (Test Scenario 4) — drive N post-RPC failures;
  assert no unbounded Syncing… spin, terminal converge-forward affordance reached.
- [ ] 1.6 Run `cd apps/web-platform && ./node_modules/.bin/vitest run test/org-switcher-container.test.tsx`
  — confirm the new tests FAIL (RED) and the existing 6 still pass.

## Phase 2 — Core Implementation / GREEN

- [ ] 2.1 Widen `SwitchStatus` to a discriminated set encoding pre- vs post-RPC failure
  (e.g. `"idle" | "switching" | "syncing" | "failed_pre_rpc" | "failed_post_rpc"`). Prefer the
  union over a side boolean so the render branching is exhaustive.
- [ ] 2.2 In the post-RPC catch (`:95-98`): set `failed_post_rpc` and **force-complete** —
  `window.location.assign("/dashboard")` directly (the locked primary treatment). Guard against
  double-navigation.
- [ ] 2.3 In the RPC-error branch (`:76-80`): set `failed_pre_rpc` (keeps existing Retry/Cancel UX).
- [ ] 2.4 Update render: the `failed_pre_rpc` arm keeps Retry+Cancel; the `failed_post_rpc` arm
  renders NO Cancel (force-complete navigates; if a transient pre-nav state is shown, it is
  Continue-only). `handleCancel` must be unreachable from `failed_post_rpc`.
- [ ] 2.5 Offline detection: in the post-RPC catch, read `navigator.onLine` / inspect the caught
  error shape to select honest messaging. Mirror the error-shape reasoning in
  `components/settings/delegation-toggle.tsx:168` — do not invent a new pattern.
- [ ] 2.6 Add `Sentry.captureMessage` on the post-RPC catch (per
  `cq-silent-fallback-must-mirror-to-sentry`) with a message string distinct from the pre-RPC
  console.error; keep the membership-fetch catch silent (`:47-51` unchanged).
- [ ] 2.7 Bounded-retry guard so the UI never spins forever.

## Phase 3 — Verification

- [ ] 3.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes; every `SwitchStatus`
  arm handled (AC6). Grep the component for every `status === "failed"` site post-rename.
- [ ] 3.2 `cd apps/web-platform && ./node_modules/.bin/vitest run test/org-switcher-container.test.tsx`
  — all GREEN (existing 6 + new ≥4) (AC7).
- [ ] 3.3 `git diff` confirms NO edit to `lib/session-claims.ts`, no migration, no `server/*`
  resolver (AC8 — ADR-044 invariants intact).
- [ ] 3.4 Self-check AC1–AC8 against the plan's Acceptance Criteria.

## Phase 4 — Ship

- [ ] 4.1 Commit; PR body uses `Closes #4917` (NOT title; NOT `Ref` — this lands in code at merge).
- [ ] 4.2 No post-merge operator step — deploys via `web-platform-release.yml` container restart
  on merge to `main` touching `apps/web-platform/**`.

## Notes

- `requires_cpo_signoff: true` — single-user-incident threshold. CPO sign-off on the technical
  approach is required at plan time; `user-impact-reviewer` runs at review time.
- deepen-plan domain agents (data-integrity-guardian / architecture-strategist / spec-flow) are
  the substance gate at this threshold — plan-review caught the force-complete-vs-interstitial
  simplification; deepen-plan validates blast radius + flow completeness.
