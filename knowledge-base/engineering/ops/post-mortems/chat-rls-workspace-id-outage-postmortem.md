---
title: "Postmortem: interactive chat message-saving RLS-blocked for ~3 weeks (messages.workspace_id)"
date: 2026-06-02
incident_pr: 4831
incident_window: "2026-05-11 (last interactive message saved; migration 059 RLS sweep made messages.workspace_id NOT NULL + member-keyed INSERT policy) → 2026-06-02 ~22:36Z (PR #4831 deployed: workspace_id populated on all interactive INSERT sites)"
suspected_change: "Migration 059_workspace_keyed_rls_sweep — added messages.workspace_id NOT NULL + messages_workspace_member_insert WITH CHECK (is_workspace_member(workspace_id, auth.uid())) without updating the 4 application INSERT sites"
brand_survival_threshold: single-user incident
status: closed
closed_on: 2026-06-02
closed_via: "PR #4831 (merged + Web Platform Release green); post-deploy message-persistence verification tracked in #4839"
triggers:
  - chat send failure
  - messages RLS insert
  - workspace_id null
  - unexpected error bubble
  - migration column add not swept
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a — availability outage, no personal-data exposure (data was BLOCKED from being written, not exposed/breached)"
---

## Actor key

- `agent` — Claude Code did this autonomously.
- `agent-with-ack` — Claude Code did this after operator confirmation.
- `human` — Operator did this directly.

## Symptom

Sending any message in the interactive chat returned the generic bubble **"An unexpected error occurred. Please try again."** The product's core surface was unusable. For the affected workspace (`754ee124-…`, founder / tenant-zero) the last successfully-saved interactive message was **2026-05-11** — chat had been silently broken for ~3 weeks.

## Root-cause hypothesis

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| Migration 059 made `messages.workspace_id` NOT NULL + member-keyed INSERT RLS, but the 4 interactive INSERT sites never set `workspace_id` → NULL → `is_workspace_member(NULL, auth.uid())` false → RLS reject | Sentry `Failed to save user message: new row violates row-level security policy for table messages` `[dispatchSoleurGo(index)]` @ 2026-06-02T19:06:18Z; prod `messages` gap since 2026-05-11; 059 policy text; all 4 sites omitted the column | none | **Confirmed** |
| Service-role cron writes masked the outage | Recent `messages` rows in a different workspace via service-role (RLS-bypassing) cron; zero interactive rows in the user's workspace | none | **Confirmed (contributing)** |

## Timeline

| Actor | Time (UTC) | Action |
|---|---|---|
| — | 2026-05-11 | Last interactive message saved in workspace 754ee124 (migration 059 lands the NOT-NULL + RLS-required `workspace_id` ~this window; interactive INSERTs start failing). |
| human | 2026-06-02 ~16:11Z | User reports "new conversation in the webapp failed." |
| agent | 2026-06-02 ~17:05Z | **Misdiagnosis:** PR #4816 fixes an *adjacent* history-fetch-404 noise issue (real, but not the outage) and downgrades the 404 from error→warning. |
| agent | 2026-06-02 ~21:06Z | User retries ("Fix Issue 4823") — same error. The #4816 noise reduction surfaces the real Sentry error (`Failed to save user message … RLS`). |
| agent | 2026-06-02 ~21:1xZ | Correct diagnosis: traced the user-visible symptom (error on message **send**) → `error-sanitizer.ts:79` fallback ← `cc-dispatcher` catch ← RLS reject; confirmed against prod DB + migration 059. |
| agent | 2026-06-02 ~22:27Z | PR #4831 merged (workspace_id populated on all 4 interactive INSERT sites + grep-sweep guard). |
| agent | 2026-06-02 ~22:36Z | Web Platform Release deployed green. |
| human | 2026-06-02 | Post-deploy message-persistence confirmation requested (tracked #4839). |

## Recovery verification

- PR #4831 merged (`deb0f1bb`); **Web Platform Release run 26845980973 = success** (deploy live).
- AC7 pre-ship read-only prod check: `conversations.workspace_id` populated; `messages.workspace_id` NOT NULL + `messages_workspace_member_insert` WITH CHECK present; derived value (parent conversation's workspace_id) satisfies the predicate.
- **Open verification (#4839):** a *fresh* interactive message persisting post-deploy (new `messages` row, non-null `workspace_id`, in workspace 754ee124) + the `Failed to save user message` Sentry signature ceasing. Needs one real send post-deploy.

## Contributing factors

1. **NOT-NULL + RLS-gated column added without a write-site sweep.** Migration 059 backfilled existing rows and set the policy but did not update the 4 application INSERT sites (`hr-write-boundary-sentinel-sweep-all-write-sites` existed but was not applied to 059).
2. **No liveness alert on absence of writes.** Nothing fired on "zero interactive messages saved in a workspace for 3 weeks." The only signal was the user noticing.
3. **Error-level noise masked the real error.** The unrelated history-fetch-404 fired at `error` level on every fresh open, burying the real RLS error until #4816 silenced it.
4. **Initial triage fixed the alert's named op, not the user's failure.** The Sentry alert named `history-fetch-404`; triage fixed that op rather than tracing the user-visible symptom (message send) to its producer. (See learning `2026-06-02-rls-column-add-must-sweep-all-insert-sites-and-alert-op-is-not-the-user-failure.md`.)

## Follow-ups

- [x] PR #4831 — populate `workspace_id` on all 4 interactive `messages` INSERTs + grep-sweep guard test (`hr-write-boundary-sentinel-sweep-all-write-sites`).
- [ ] #4839 — post-deploy verification a fresh message persists + Sentry signature stops.
- [ ] **Liveness alert (factor 2):** alert when a workspace records zero interactive `messages` inserts over N hours (catches a silent write-path outage without waiting for a user report). File as a monitoring follow-up.
- [x] **Workflow gate (factor 4 + the after-the-fact-postmortem ask):** ship now requires a PIR for any incident-class fix, even when the incident is discovered incidentally during another change (see this PR's `ship` Phase 5.5 Incident-PIR gate + the `wg-incident-detected-always-run-postmortem` workflow gate).
- [x] **Migration-author sweep reminder:** the RLS-column-add → write-site-sweep lesson is captured in `2026-06-02-rls-column-add-must-sweep-all-insert-sites-and-alert-op-is-not-the-user-failure.md`.

## Who was affected (by role)

- Prospect: none (unauthenticated; chat is behind login).
- Authenticated app user: **fully blocked** — could not send any chat message (core surface) for ~3 weeks. In production this was the single founder/tenant-zero user; the same defect would have blocked every authenticated user once others onboarded.
- Legal-document signer: none.
- Admin via Access: none (infra unaffected).
- Billing customer: none (no billing path touched).
- OAuth installation owner: none.

## Prevention — what would have caught this earlier

- A write-site sweep when migration 059 added the RLS-gated NOT-NULL column (the canonical `hr-write-boundary-sentinel-sweep-all-write-sites` remedy — now backed by the grep-sweep guard test from #4831).
- A liveness alert on write absence (factor 2 follow-up).
- Lower error-noise floor so real errors surface (the #4816 noise reduction, in hindsight, was the enabling diagnostic step).
- Triage discipline: trace the user-visible symptom to its producer, not the alert's named op.

## Update (2026-06-02): second un-swept NOT-NULL column — `template_id` (#4839)

After PR #4831 deployed, chat **still** errored on send. The workspace_id RLS error was gone, but the insert now reached the **next** un-swept required column: `Failed to save user message: null value in column "template_id" of relation "messages" violates not-null constraint` (`dispatchSoleurGo`, 2026-06-02T21:14Z). `messages.template_id` was made NOT NULL (no default) by **migration 053** — a separate, earlier instance of the *same* un-swept-INSERT-site class as 059's workspace_id. The 059 RLS WITH CHECK fired first and masked the 053 NOT-NULL violation.

**Process miss:** when fixing #4831 I added only the column named in the error (workspace_id) instead of querying `information_schema` for the **complete** set of NOT-NULL-no-default columns and sweeping them all at once.

**Authoritative fix (PR #4839-fix):** queried prod `information_schema.columns` — the ONLY two NOT-NULL-no-default columns on `messages` are `workspace_id` and `template_id`. Added `template_id: "default_legacy"` (the migration-053 backfill sentinel, satisfies the `^[a-z][a-z0-9_]*$` CHECK) to all 4 interactive INSERT sites, and **generalized the grep-sweep guard test to require BOTH columns** (`REQUIRED_MESSAGE_COLUMNS`) so a third un-swept column would fail CI.

**Added prevention:** when fixing a NOT-NULL/RLS insert failure, enumerate ALL required columns via `information_schema` (NOT NULL + no default) and sweep every site in one pass — a single error message names only the first violation; RLS-check-before-constraint and one-constraint-at-a-time evaluation both mask the rest.
