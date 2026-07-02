---
feature: L5 Runaway Guard — safety floor (v2)
issue: 5767
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-07-02-feat-l5-runaway-guard-plan.md
---

# Tasks: L5 Runaway Guard (v2 — notification + working pause)

Single-PR scope. Derived from the finalized (post-5-agent-review) plan. Follow-ups tracked as separate
issues (see Phase 5).

## Phase 1 — Fix the broken pause (SAFETY core)

- [x] 1.1 Add a **spawn-entry pause gate** in `agent-on-spawn-requested.ts` (before the turn loop ~`:319`):
  read `users.runtime_paused_at`; if set, halt via `persistFailure` before any Anthropic call.
- [x] 1.2 Follow-up migration on the cap RPC (`061` lineage): return `kill_tripped = true` whenever
  `runtime_paused_at IS NOT NULL` (not transition-only). Defense-in-depth.
- [x] 1.3 Add the **operator-resume clearer** (route/action) — the ONLY code path setting
  `runtime_paused_at = NULL`. Cap-check steps never clear it (set-never-clear contract).
- [x] 1.4 RED→GREEN: AC1 (paused founder → zero new `audit_byok_use` rows) + AC2 (single clearer, grep-asserted).

## Phase 2 — Notification

- [x] 2.1 Extend `NotificationPayload` union in `notifications.ts:72-91` with `CostBreakerNotificationPayload`
  (`reason` subset, `which_window`, `context` cents). Add push body + email template.
- [x] 2.2 Wire `notifyOfflineUser` into `persistFailure` (`:913-962`) — **single site**, BEFORE the
  `action_sends` UPDATE. Fire only for `cost_ceiling_exceeded|byok_cap_exceeded|leader_max_turns_exceeded|cap_check_unavailable`; never for `cancelled_by_operator`.
- [x] 2.3 Add distinct `cap_check_unavailable` failure reason (transient DB error ≠ false "budget exceeded").
- [x] 2.4 RED→GREEN: AC3 (one site, right reasons, ordering) + AC4 (dollars, which_window, honest copy vs
  wireframe `03a`/`03c`).

## Phase 3 — Legal / ADR reconciliation

- [x] 3.1 Amend ToS `docs/legal/terms-and-conditions.md` §3a.5 (remove false "no ceiling" claim) + §11
  overage carve-out (clo-attestation — v1 counsel-review gate).
- [x] 3.2 Amend ADR-041 `## Decision` + `## Alternatives Considered` (notification + working-pause
  contract) + reconcile stale daily/monthly prose vs SQL `interval '1 hour'`.
- [x] 3.3 Fix ADR-042 frontmatter `adr: 040` → `042` + title (pre-existing bug).
- [x] 3.4 Update `knowledge-base/legal/article-30-register.md` (PA-21/22/23 modification).
- [x] 3.5 Run `/soleur:gdpr-gate` at work Phase 2 exit; annotate any new column `-- LAWFUL_BASIS: ...`.

## Phase 4 — Verify

- [x] 4.1 Typecheck: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
- [ ] 4.2 Tests via package runner (check `package.json scripts.test` / vitest include globs — do NOT
  assume `bun test`).
- [x] 4.3 C4: verify web-push edge against all three `.c4` files; add + `views.c4` include if unmodeled;
  run `apps/web-platform/test/c4-*.test.ts`.
- [ ] 4.4 `/soleur:qa` before merge.

## Phase 5 — File deferred follow-up issues (before PR-ready)

- [x] 5.1 **Cron cost-enforcement** (top priority — real overnight-burn surface): crons write
  `audit_byok_use` / share the cap RPC so a dollar ceiling covers them.
- [x] 5.2 Rolling-24h founder budget (product/tunability increment).
- [x] 5.3 Per-run cost ceiling ($20 CFO-recommended).
- [x] 5.4 Pre-run cost estimate (avg; no HITL modal).
- [x] 5.5 Doom-loop detector (web-only, own ADR, behind telemetry).
