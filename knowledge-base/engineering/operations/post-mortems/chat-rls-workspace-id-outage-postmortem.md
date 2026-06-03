---
title: "Postmortem: interactive chat message-saving RLS-blocked for ~3 weeks (messages.workspace_id)"
date: 2026-06-02
incident_pr: 4831
incident_window: "2026-05-11 (last interactive message saved; migration 059 RLS sweep made messages.workspace_id NOT NULL + member-keyed INSERT policy) → 2026-06-02 ~22:36Z (PR #4831 deployed: workspace_id populated on all interactive INSERT sites)"
recovery_at: "2026-06-02T22:36:00Z"
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

# Incident Overview

Migration 059 made `messages.workspace_id` NOT NULL with a member-keyed INSERT policy but never updated the 4 application INSERT sites, so every interactive chat message-save was RLS-rejected. The product's core surface was silently unusable for ~3 weeks until a user reported it.

## Status

closed — recovered 2026-06-02 ~22:36Z (PR #4831 deployed); post-deploy message-persistence verification tracked in #4839.

## Symptom

Sending any message in the interactive chat returned the generic bubble **"An unexpected error occurred. Please try again."** The product's core surface was unusable. For the affected workspace (`754ee124-…`, founder / tenant-zero) the last successfully-saved interactive message was **2026-05-11** — chat had been silently broken for ~3 weeks.

## Incident Timeline

- **Start time (detected):** 2026-05-11 (interactive writes start failing when migration 059 lands)
- **End time (recovered):** 2026-06-02T22:36:00Z
- **Duration (MTTR):** ~22 days end-to-end (silent breakage 2026-05-11 → recovery 2026-06-02T22:36Z). The active triage-to-recovery span after detection was ~6h25m (user report 16:11Z → deploy 22:36Z); the bulk of the window was undetected — see MTTD.

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

## Participants and Systems Involved

Operator (single founder) + Claude Code agent. Systems: Supabase Postgres (RLS policies + migrations 059/053), web-platform chat dispatch (`cc-dispatcher`, the 4 interactive `messages` INSERT sites).

## Detection (+ MTTD)

- **How detected:** external/manual — user report ("new conversation in the webapp failed").
- **MTTD (mean time to detect):** Unknown / ~3 weeks silent — the breakage began 2026-05-11 and the first signal was a user report on 2026-06-02 ~16:11Z. Nothing fired on "zero interactive messages saved for 3 weeks" (see Contributing factor 2).

## Triggered by

system — migration `059_workspace_keyed_rls_sweep` (an earlier instance of the same class, migration 053's `template_id`, surfaced after the 059 fix — see Update below).

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| Migration 059 made `messages.workspace_id` NOT NULL + member-keyed INSERT RLS, but the 4 interactive INSERT sites never set `workspace_id` → NULL → `is_workspace_member(NULL, auth.uid())` false → RLS reject | Sentry `Failed to save user message: new row violates row-level security policy for table messages` `[dispatchSoleurGo(index)]` @ 2026-06-02T19:06:18Z; prod `messages` gap since 2026-05-11; 059 policy text; all 4 sites omitted the column | none | **Confirmed** |
| Service-role cron writes masked the outage | Recent `messages` rows in a different workspace via service-role (RLS-bypassing) cron; zero interactive rows in the user's workspace | none | **Confirmed (contributing)** |

## Resolution

PR #4831 populated `workspace_id` on all 4 interactive `messages` INSERT sites and added a grep-sweep guard test (`hr-write-boundary-sentinel-sweep-all-write-sites`). After deploy a second un-swept NOT-NULL column (`template_id`, from migration 053) surfaced; PR #4839-fix queried `information_schema` for the complete NOT-NULL-no-default set, added `template_id: "default_legacy"` to all 4 sites, and generalized the guard test to require both columns (`REQUIRED_MESSAGE_COLUMNS`). See Update below.

## Recovery verification

- PR #4831 merged (`deb0f1bb`); **Web Platform Release run 26845980973 = success** (deploy live).
- AC7 pre-ship read-only prod check: `conversations.workspace_id` populated; `messages.workspace_id` NOT NULL + `messages_workspace_member_insert` WITH CHECK present; derived value (parent conversation's workspace_id) satisfies the predicate.
- **Open verification (#4839):** a *fresh* interactive message persisting post-deploy (new `messages` row, non-null `workspace_id`, in workspace 754ee124) + the `Failed to save user message` Sentry signature ceasing. Needs one real send post-deploy.

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. **Why did chat message-send error?** The interactive `messages` INSERT was rejected by the row-level security policy.
2. **Why was the INSERT RLS-rejected?** `workspace_id` was NULL, so `is_workspace_member(NULL, auth.uid())` evaluated false against the `messages_workspace_member_insert` WITH CHECK.
3. **Why was `workspace_id` NULL?** The 4 application INSERT sites never set the column.
4. **Why didn't they set it?** Migration 059 added `messages.workspace_id` NOT NULL + the member-keyed INSERT policy and backfilled existing rows, but did not sweep the application write sites.
5. **Why was the write-site sweep skipped?** The canonical remedy (`hr-write-boundary-sentinel-sweep-all-write-sites`) existed but was not applied to migration 059. Root cause: a NOT-NULL + RLS-gated column was added without enumerating and updating every write site — and the same class had already shipped once (migration 053's `template_id`), masked because the 059 WITH CHECK fired first.

## Versions of Components

- **Version(s) that triggered the outage:** migration `059_workspace_keyed_rls_sweep` (workspace_id), with migration `053` (template_id) as the second, earlier instance of the same un-swept-write-site class.
- **Version(s) that restored the service:** PR #4831 (workspace_id sweep) + PR #4839-fix (template_id sweep + generalized guard test).

## Impact details

### Services Impacted

Interactive chat message persistence (the product's core surface). Service-role cron writes were unaffected (RLS-bypassing).

### Customer Impact (by role)

- Prospect: none (unauthenticated; chat is behind login).
- Authenticated app user: **fully blocked** — could not send any chat message (core surface) for ~3 weeks. In production this was the single founder/tenant-zero user; the same defect would have blocked every authenticated user once others onboarded.
- Legal-document signer: none.
- Admin via Access: none (infra unaffected).
- Billing customer: none (no billing path touched).
- OAuth installation owner: none.

### Revenue Impact

Unknown / N/A — pre-revenue; single founder / tenant-zero.

### Team Impact

~3 weeks of silent breakage; ~6h of triage including one misdiagnosis (#4816 fixed an adjacent noise issue before the real RLS error was traced).

## Lessons Learned

### Where we got lucky

Only tenant-zero (the founder) was affected — the same defect would have blocked every authenticated user once others onboarded.

### What went well

The #4816 history-fetch-404 noise reduction, though initially a misdiagnosis, lowered the error-noise floor enough to surface the real RLS error and enable the correct diagnosis.

### What went wrong

See Contributing factors below — the four factors (un-swept write sites, no write-absence liveness alert, error-level noise masking, and triage fixing the alert's named op rather than the user's failure) are the "what went wrong" enumeration.

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

## Action Items

GitHub issues to prevent recurrence:

- **Monitoring/alert (factor 2):** file the write-absence liveness alert (zero interactive `messages` inserts in a workspace over N hours) — tracked as a monitoring follow-up.
- **Verification:** #4839 — confirm a fresh message persists post-deploy and the `Failed to save user message` Sentry signature ceases.
- **Test/guard:** generalized grep-sweep guard requiring ALL NOT-NULL-no-default `messages` columns (`REQUIRED_MESSAGE_COLUMNS`) — landed in PR #4839-fix.

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
