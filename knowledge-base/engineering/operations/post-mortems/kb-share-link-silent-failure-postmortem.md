---
title: "KB share-link 'Generate link' silently failed in production"
date: 2026-06-04
incident_pr: 4947
incident_window: "unknown start (≤ 2026-06-04) → 2026-06-04"
recovery_at: "2026-06-04 (root cause via PR #4922; residual UX via PR #4947)"
suspected_change: "migration 059 (workspace-keyed RLS sweep) added kb_share_links.workspace_id NOT NULL with no DB default; createShare insert was not updated to set it"
brand_survival_threshold: none
status: resolved
triggers:
  - system
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option.
- `human` — Operator did this directly.

# Incident Overview

The KB document "Share → Generate link" flow silently failed in production. Clicking
"Generate link" returned the user to the same idle "Generate a public link" popup with no
error and no link, on the C4 diagram doc (`engineering/architecture/diagrams/c4-model.md`).
Detected after-the-fact by the operator (tenant-zero) via a screenshot while using the live
app. Not an availability outage of the platform — a single feature (KB public sharing)
silently non-functional.

## Status

resolved — dominant root cause fixed by PR #4922 (merged 2026-06-04); residual silent-error
UX + defensive FK-error mapping fixed by PR #4947.

## Symptom

"Generate link" POST to `/api/kb/share` failed; the client swallowed the failure and reset
the popup to its idle prompt, so a failed mint was indistinguishable from "nothing happened."

## Incident Timeline

- **Start time (detected):** 2026-06-04 (operator screenshot; true start ≤ this date, bounded below by migration 059's deploy)
- **End time (recovered):** 2026-06-04
- **Duration (MTTR):** root cause fixed same day it was diagnosed (PR #4922)

| Actor | Time (UTC) | Action |
|---|---|---|
| human | 2026-06-04 | Operator hit "Generate link" on a live diagram doc; it silently failed (screenshot). |
| agent | 2026-06-04 | Diagnosed: migration 059 made `kb_share_links.workspace_id` NOT NULL; `createShare` insert never set it → Postgres 23502 → 500 → silent client reset. |
| agent | 2026-06-04 | PR #4922 set `workspace_id` on the insert via `resolveCurrentWorkspaceId` (root cause). |
| agent | 2026-06-04 | PR #4947 added client error state + retry + 409 recovery, and a distinct `workspace-missing` code for the residual 23503 FK case. |

## Participants and Systems Involved

`apps/web-platform` KB share surface: `components/kb/share-popover.tsx`, `app/api/kb/share/route.ts`,
`server/kb-share.ts`; Supabase Postgres (`kb_share_links` table, migration 059).

## Detection (+ MTTD)

- **How detected:** external/manual — operator noticed the failure in the live app and reported it with a screenshot. No automated alert fired (the server 500 was mirrored to Sentry via `reportSilentFallback`, but the client silently swallowed it so there was no user-facing signal and no operator was watching Sentry).
- **MTTD:** unknown (after-the-fact discovery).

## Triggered by

system — a schema migration (059) that added a NOT-NULL column without updating the writer.

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| Client-side caching (operator's initial guess) | popup "came back to the same prompt" | No caching on the POST path; `generateLink` resets to idle on any `!res.ok`/throw | rejected |
| Missing `workspace_id` on insert → 23502 → silent 500 | migration 059 added NOT-NULL `workspace_id`; insert omitted it | — | confirmed (fixed #4922) |

## Resolution

PR #4922 set `workspace_id` on the `createShare` insert (resolved via `resolveCurrentWorkspaceId`,
solo fallback = userId). PR #4947 added the missing client error surfacing so any remaining/transient
failure is visible (generic copy + "Try again"), a 409 concurrent-retry recovery, and a distinct
`workspace-missing` (SQLSTATE 23503) error code so a missing-workspace-row FK violation is
discriminable from a generic DB error in telemetry.

## Recovery verification

Unit suite RED→GREEN for all three behaviors (`test/share-popover.test.tsx`, `test/kb-share.test.ts`,
`test/c4-workspace.test.tsx`); full web-platform suite green. Post-deploy Playwright/manual smoke on the
live diagram doc is tracked as the PR's ⏳ test-plan item.

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. Why did "Generate link" fail? → The `createShare` insert hit Postgres 23502 (NOT-NULL violation) and returned a 500.
2. Why a NOT-NULL violation? → `kb_share_links.workspace_id` was made NOT NULL by migration 059 with no DB default, but the insert never set it.
3. Why didn't the insert set it? → The workspace-keyed RLS sweep (059) added the column without sweeping every writer of the table in the same change.
4. Why did the user see nothing? → The client (`share-popover.tsx`) swallowed every non-OK response and every throw into a silent reset to `idle`, with no error state.
5. Why was it found late? → The only failure signal was a server-side Sentry mirror; no user-facing error and no one watching the dashboard (operator is solo, dogfooding).

## Versions of Components

- **Version(s) that triggered:** the build carrying migration 059 with the un-swept `createShare` insert.
- **Version(s) that restored:** PR #4922 (root cause) + PR #4947 (UX hardening).

## Impact details

### Services Impacted

KB document public sharing (link generation) only. No platform-wide outage; auth, chat, KB read all unaffected.

### Customer Impact (by role)

- Prospect: none (feature is owner-authenticated).
- Authenticated app user / owner: could not generate a public share link for KB docs; failure was silent.
- Legal-document signer: none.
- Admin via Access: none.
- Billing customer: none (no charge involved).
- OAuth installation owner: none.

### Revenue Impact

None.

### Team Impact

Minimal — one solo operator; ~one diagnosis+fix cycle.

## Lessons Learned

### Where we got lucky

The operator dogfooded the exact feature and screenshotted it; otherwise the silent failure could have persisted unnoticed (no user-facing signal existed).

### What went well

Server already mirrored the 500 to Sentry via `reportSilentFallback`; root cause was diagnosable from code + the migration.

### What went wrong

(1) A NOT-NULL migration shipped without sweeping every writer of the table (the `hr-write-boundary-sentinel-sweep-all-write-sites` class, for a NOT-NULL column rather than a tenant sentinel). (2) The client swallowed all failures into a silent reset, hiding the outage from the only person who could detect it.

## Follow-ups

- [x] Client error surfacing so share failures are visible (PR #4947).
- [x] Distinct `workspace-missing` (23503) telemetry code (PR #4947).
- [ ] ⏳ Post-deploy Playwright/manual smoke of the live Generate-link flow (tracked on PR #4947 test plan).

## Action Items

- Already addressed in PR #4947 (client error state, retry, 409 recovery, 23503 mapping). No new GitHub issue warranted — the recurrence vectors (silent client swallow; un-swept NOT-NULL writer) are both closed by #4922 + #4947, and the writer-sweep discipline is already encoded as `hr-write-boundary-sentinel-sweep-all-write-sites`.

## Update — deeper residual root cause (PR #4953, 2026-06-05)

PR #4947's client error UX revealed the create was STILL failing for the operator
(the new error state showed instead of a silent reset). Diagnosis this cycle found a
THIRD, deeper cause beyond #4922's `workspace_id` insert fix and #4947's UX layer:

- **ADR-044 resolver-consolidation gap.** The KB *read* routes (content/tree/search/
  c4-project) had migrated to the service-role, membership-scoped
  `resolveActiveWorkspaceKbRoot`, but the `kb/share` + `kb/upload` *write* routes were
  left on the legacy `resolveUserKbRoot` — a per-request TENANT client reading the
  caller's `users.workspace_status` under RLS, which is stale/empty for users
  provisioned after the ADR-044 `users → workspaces` relocation → silent 503
  "Workspace not ready" before `createShare` even ran. The branch was invisible
  because `createShare`'s 5 pre-insert validation returns + the resolver-error
  response did NOT mirror to Sentry (only the INSERT branches did).
- **Fix (PR #4953):** (A) instrument all 5 pre-insert validation returns + the
  resolver-error response to Sentry with `reason=<code>`; (B) migrate share + upload
  to `resolveActiveWorkspaceKbRoot` (+ a `resolveActiveWorkspaceRepoMeta` sibling for
  upload's git-push metadata reading `workspaces.repo_url` + the membership-checked
  `resolveInstallationId` RPC) and REMOVE `resolveUserKbRoot`. Also fixed a latent
  #4543 dual-ownership bug for shared members.
- **Recurrence prevention:** captured as
  `knowledge-base/project/learnings/best-practices/2026-06-05-adr-resolver-migration-must-sweep-write-routes-not-just-read-routes.md`
  and routed to the `work` skill — an ADR resolver migration is not done until
  `git grep <oldResolver>` returns 0 (write routes are consumers too).

### Follow-up status update
- [x] ⏳ Post-deploy smoke (line 148) — superseded: Workstream A's instrumentation makes
  the exact failing branch observable in Sentry on the next prod "Generate link" click,
  and the A+B fix is verified by the unit/component suite + multi-agent security review
  (R1–R6 PASS). Confirm green via a single prod click post-deploy.
