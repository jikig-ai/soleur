---
issue: 5591
lane: single-domain
plan: knowledge-base/project/plans/2026-06-30-fix-owner-canary-multi-owner-sweep-and-close-plan.md
note: No spec.md for this branch; lane taken from the plan (genuinely single-domain — one server-util docstring + issue hygiene).
---

# Tasks — fix(workspace): owner-canary multi-owner resolver — sweep + observability-inventory completion + close #5591

> **Context:** The primary resolver fix already shipped in **PR #5734 (MERGED)** with 3-branch test coverage. The planning-time sweep (13 TS + 5 SQL owner-touching sites) found **zero** residual buggy sites. This is a verify-and-close PR whose only code change is completing an existing observability op-inventory docstring. Do NOT re-implement the resolver, build a helper, or add a CI guard (see plan Sharp Edges).

## Phase 0 — Preconditions (read-only)
- [ ] 0.1 `git show origin/main:apps/web-platform/server/inngest/functions/workspace-reconcile-on-push.ts | sed -n '254,346p'` — confirm the deterministic multi-owner owner pick is present. If ABSENT, STOP (plan premise invalid).
- [ ] 0.2 `grep -n "multiple-owners-reconcile\|owner-attribution-probe" apps/web-platform/server/observability.ts` — expect NO match (the gap this PR closes).
- [ ] 0.3 `grep -n "multiple-owners-reconcile\|owner-attribution-probe" apps/web-platform/server/inngest/functions/workspace-reconcile-on-push.ts` — expect the emit sites (~:281, ~:316).

## Phase 1 — Observability-inventory completion (docstring only)
- [ ] 1.1 Edit `apps/web-platform/server/observability.ts`, the `workspace-reconcile-push` family bullet (~:362-370). After the existing `ownerless-reconcile` sentence, add:
  - `multiple-owners-reconcile` — **info-level** `Sentry.addBreadcrumb` (non-paging) for the by-design ≥2-owner state; carries `{ workspaceId, ownerCount }`; introduced by #5734/#5591.
  - `owner-attribution-probe` — **warn-level** `reportSilentFallback` op on a transient owner-read DB error (NOT on zero owners); reconcile falls back to the workspace-keyed audit; introduced by #5734/#5591.
- [ ] 1.2 Keep it factual, 2-3 sentences. No code-path change, no new emit site, no other file touched.

## Phase 2 — Verify (no SSH)
- [ ] 2.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` — exits 0. (AC3)
- [ ] 2.2 `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/workspace-reconcile-on-push.test.ts` — green; the #5734 multi-owner suite (self-row / earliest-created / zero-owner) intact. (AC4)
- [ ] 2.3 `grep -c` confirms both ops now in the inventory. (AC1/AC2)
- [ ] 2.4 Confirm diff is confined to `observability.ts` (no `server/inngest/`, no `supabase/migrations/`, no `*.tsx`). (AC5)

## Phase 3 — Close-out
- [ ] 3.1 PR body: `Closes #5591`; reference #5734 (fix), #5756 (SQL/RPC + ADR residual — state "RPC/data-model residual tracked in #5756"), #5733 (filesystem strand). (AC6)
- [ ] 3.2 (Optional, NOT a gate) Post-merge: via Supabase MCP read-only, confirm `754ee124` `kb_sync_history` carries a recent `trigger: webhook_push` entry (#5730 AC12 loop). If absent → #5734/#5733 follow-up, not a regression here.

## Out of scope (do NOT touch)
- SQL/RPC single-owner reconciliation + dedicated ADR → **#5756**. Advisory: #5756's ADR should also reconcile **AP-015** (`principles-register.md:23`).
- `/soleur:go` agent-container-vs-server filesystem strand → **#5733**.
- Creation-path guard (issue item 3) → **#5673 (OPEN)**.
