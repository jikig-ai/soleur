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
- [ ] 3.1 `lib/inbox-severity.ts` (name TBD): `deriveSeverity()` (statutory→action_required; non-statutory email→info; task_completed→info; system→info|action_required-if-blocking — ~6 lines) + the two-source merge (bounded fetch per source → deriveSeverity → stable sort → concat; statutory uncapped-pinned exempt from the NEEDS YOU cap). Single source of truth.
- [ ] 3.2 `GET /api/inbox`: user-context client (**no `createServiceClient`**), consumes 3.1, merges `inbox_item` + `email_triage_items`; deep links built from `source_ref` (discriminated-union builder) at render.
- [ ] 3.3 New **`inbox_list` agent tool** (`server/*-tools.ts`) consuming the SAME 3.1 module (agent-native parity AP-004). Collapse the existing route↔`email-triage-tools.ts` duplication into 3.1.
- [ ] 3.4 Deadline chip: cosmetic red/amber from `received_at + window(statutory_class)`; never affects severity/pin; no-chip fallback for unknown class.

## Phase 4 — Surface
- [ ] 4.1 `InboxItemRow` component (new): severity dot + title + relative time + cosmetic deadline chip; builds link from `source_ref`; non-navigating when target missing/RLS-hidden.
- [ ] 4.2 Extend `inbox-surface.tsx`: NEEDS YOU / GOOD TO KNOW groups; per-group empty states (Appendix A copy); dispatch to `EmailTriageRow` vs `InboxItemRow` by source; keep Active/Archived tabs + SWR keys + never-re-sort contract.
- [ ] 4.3 Archive confirmation for `action_required` (wireframe screen 19); guard until acted.
- [ ] 4.4 Nav badge: outstanding `action_required` only (`9+` cap), FYI-only unread → gold dot, never "0" (align to `nav-count-badge.tsx`).

## Phase 5 — Tests + observability + ADR/C4
- [ ] 5.1 Migration/RLS tests: **Owner A cannot read Owner B's items (merge-gate)**; targeted-row private to recipient; service-role-only INSERT; archive-guard rejects un-acted action_required; retention never deletes un-acted action_required; workspace-delete + user-delete cascades.
- [ ] 5.2 Merge tests: all non-archived statutory pinned (incl. acknowledged, far-from-deadline); chip color ≠ severity; NEEDS YOU cap with statutory exempt; dedup (retry doesn't re-push).
- [ ] 5.3 `notifyInboxItem` insert-once + push-only-on-insert + Sentry mirror on action_required failure.
- [ ] 5.4 ADR-075 (verify next-free ordinal at ship) + edit 3 `.c4` files (Operational Inbox store, dispatcher→store, Founder→store, agent→store edges) + c4 tests green.
- [ ] 5.5 `## Observability` wiring (Sentry `op=notify-inbox-action-required` rule). Runner: `cd apps/web-platform && ./node_modules/.bin/vitest run test/**/inbox*.test.ts`.

## Exit
- [ ] `tsc --noEmit` clean; targeted vitest green; CPO sign-off recorded (GO-WITH-CHANGES, folded); source-grep gate (no `createServiceClient` under `app/api/inbox/**`).
