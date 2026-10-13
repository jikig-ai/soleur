---
feature: severity-ranked-inbox
lane: cross-domain
plan: knowledge-base/project/plans/2026-07-04-feat-severity-ranked-inbox-plan.md
---

# Tasks — Severity-ranked inbox (#6007)

Derived from the finalized plan (post 3-reviewer pass). All schema decisions reflect the review revisions: inline v1 state (no per-Owner join), reuse `is_workspace_owner` (mig 098:67), narrowed `source` CHECK, ADR-035 dedup, pin-all-statutory.

## Phase 1 — Data model (`inbox_item` migration)
- [x] 1.1 `ls apps/web-platform/supabase/migrations/` for next ordinal (→ 122); read mig 111 (RLS/RPC pattern) + 098:67 (`is_workspace_owner`) + 094 (pg_cron retention) as templates.
- [x] 1.2 Write `122_inbox_item.sql`: table with `id, workspace_id NOT NULL → workspaces ON DELETE CASCADE, user_id NULL → users ON DELETE CASCADE, severity CHECK(action_required|attention|info), source CHECK('task_completed','system'), title NOT NULL, source_ref jsonb, dedup_key text, status DEFAULT 'unread' CHECK(unread|read|archived), created_at, read_at, acted_at, archived_at` (inline v1 state; **no** recipient-state join — deferred to #4672).
- [x] 1.3 RLS: `ENABLE ROW LEVEL SECURITY`; `REVOKE INSERT, UPDATE, DELETE FROM PUBLIC, anon, authenticated`; SELECT policy `USING ((user_id = auth.uid()) OR (user_id IS NULL AND public.is_workspace_owner(workspace_id, auth.uid())))`; no authenticated write policy.
- [x] 1.4 Dedup: partial-unique index `(workspace_id, dedup_key) WHERE dedup_key IS NOT NULL` (ADR-035 shape).
- [x] 1.5 `set_inbox_item_state(p_id, p_action)` RPC: SECURITY DEFINER + `search_path=public,pg_temp`; `auth.uid()` pin; same error for missing+non-authorized row (no oracle); `FOR UPDATE`; **archive-guard** (reject archiving `action_required` when `acted_at IS NULL`); `acted_at` set-once; `acted` idempotent (already-acted → no-op, pre-wires the deferred "already resolved" banner). REVOKE from all incl. service_role, GRANT EXECUTE to authenticated.
- [x] 1.6 Retention: pg_cron sweep deleting archived/`info` > 90d **AND `NOT (severity='action_required' AND acted_at IS NULL)`** (defense-in-depth). Guard pg_cron-absent CI.
- [x] 1.7 `.down.sql`: `cron.unschedule` + drop RPC + table, `undefined_table` warn guard.

## Phase 2 — Emit + push (`notifyInboxItem`)
- [x] 2.1 Add `InboxItemNotificationPayload` (`type:'inbox_item'`) to `NotificationPayload` union in `server/notifications.ts`; swept consumers (`cq-union-widening-grep-three-patterns` — only push/email switches; ws-client `m.type` is a different union) + `tsc --noEmit` clean.
- [x] 2.2 `notifyInboxItem(opts)`: plain-insert + catch `23505` (ADR-035; not `ON CONFLICT DO NOTHING`); **dispatch push ONLY when a row was inserted**; route via existing `notifyOfflineUser` (targeted) or per-Owner broadcast; extended `mirrorNotifyFailure` with `op=notify-inbox-action-required`.
- [x] 2.3 `public/sw.js`: `inbox_item` variant gets its own `tag` (`inbox-item-{id}`), keyed on `data.inboxItemId`; sw notificationclick already same-origin-validates the deep link.
- [x] 2.4 Wired the **`task_completed`** producer at the agent-run terminal success path (`agent-runner.ts`, after `assistantPersisted` + waiting_for_user). **No** `approval_required`/`autopilot_run` emit (deferred to #4672/#4674).

## Phase 3 — Unified read path + shared severity module
- [x] 3.1 `lib/inbox-severity.ts` (pure, client-safe): `deriveEmailSeverity()` (statutory→action_required, clock/status-independent; else info) + native severity + `mergeAndRank()` (statutory pinned first/uncapped → severity rank → recency) + `partitionForDisplay()` (NEEDS YOU cap, statutory-exempt) + `buildInboxDeepLink()` + `countOutstandingActionRequired()`. Single source of truth (shared server fetch in `server/inbox-sources.ts`).
- [x] 3.2 `GET /api/inbox`: user-context client (**no `createServiceClient`** — source-grep gate test), consumes 3.1 via `fetchInboxSources`, merges `inbox_item` + `email_triage_items`; deep links built from `source_ref` at render.
- [x] 3.3 New **`inbox_list` agent tool** (`server/inbox-tools.ts`, auto-approve tier) consuming the SAME 3.1 module + shared `fetchInboxSources` (agent-native parity AP-004); registered in agent-runner.
- [x] 3.4 Deadline is cosmetic-only: `deriveEmailSeverity` IGNORES the clock (tested: acknowledged + far-from-deadline statutory both → action_required), so a chip can never move severity/pin. Email rows keep EmailTriageRow's existing due-date display; native rows have no statutory clock. No-chip fallback = no rule match.

## Phase 4 — Surface
- [x] 4.1 `InboxItemRow` component (new): severity dot (red/amber/grey) + plain-text title + relative time; builds link from `source_ref` via `buildInboxDeepLink`; non-navigating when target missing. Act/archive via new `POST /api/inbox/[id]/state` (RPC).
- [x] 4.2 Rewrote `inbox-surface.tsx` → consumes `GET /api/inbox` (merged); NEEDS YOU / GOOD TO KNOW groups; per-group empty states (Appendix A copy); dispatches `EmailTriageRow` vs `InboxItemRow` by `kind`; keeps Active/Archived tabs + SWR keys (`swrKeys.inbox`) + never-re-sort (partition-only).
- [x] 4.3 Archive confirmation for `action_required` (inline Confirm/Cancel); Archive disabled until the item is marked done (mirrors the RPC archive-guard).
- [x] 4.4 Nav badge: outstanding `action_required` only (`9+` cap via `NavCountBadge cap` prop), FYI-only unread → gold dot, never "0" (COLD/undefined omits). Same shared SWR key as the surface.

## Phase 5 — Tests + observability + ADR/C4
- [x] 5.1 Migration/RLS gates (shape-based harness): SELECT policy predicate (targeted-row private to recipient; broadcast → Owner) reusing `is_workspace_owner`; REVOKE all writes (service-role-only INSERT); archive-guard rejects un-acted action_required; retention carve-out never deletes un-acted action_required; CASCADE FKs — all in `migration-122-inbox-item.test.ts`. Behavioral Owner-A-vs-B isolation is enforced by the RLS predicate + the `inbox-no-service-client` source-grep gate (live RLS verified at CI clean-apply).
- [x] 5.2 Merge tests (`inbox-severity.test.ts`): all non-archived statutory pinned (incl. acknowledged, far-from-deadline); chip color ≠ severity (severity ignores the clock); NEEDS YOU cap with statutory exempt; deep-link builder. Dedup retry-doesn't-re-push in `notifications.test.ts`.
- [x] 5.3 `notifyInboxItem` insert-once + push-only-on-insert + Sentry mirror on action_required failure + per-Owner broadcast (`notifications.test.ts`).
- [x] 5.4 ADR-085 (next-free vs origin/main; ADR-075 already taken) + edited `model.c4` (Operational Inbox store + webapp→store + engine→store edges) + `views.c4` include; c4 tests green (23/23). `spec.c4` needed no change (reused `database` kind).
- [x] 5.5 `## Observability` wiring: `inbox_action_required_notify_failure` Sentry alert (feature=inbox AND op=notify-inbox-action-required, EQUAL) + apply-workflow `-target` + op-contract test. mirrorNotifyFailure emits the op.

## Exit
- [x] `tsc --noEmit` clean; targeted vitest green (94 inbox + c4 + op-contract); CPO sign-off recorded (GO-WITH-CHANGES, folded — see plan Domain Review); source-grep gate (no `createServiceClient` under `app/api/inbox/**`).
