---
title: "Active conversation missing from Recent Conversations rail (Realtime INSERT gap)"
date: 2026-06-16
incident_pr: 5391
incident_window: "long-standing latent gap; observed 2026-06-15 23:12 UTC → fixed 2026-06-16"
recovery_at: "2026-06-16 (PR #5391 merge + web-platform release)"
suspected_change: "rail data hook (use-conversations.ts) only ever subscribed to Realtime UPDATE events; no INSERT path. Latent since the rail's realtime wiring; not introduced by a single regressing commit. #5317 fixed a sibling cause (repo_url source) but left the INSERT gap."
brand_survival_threshold: single-user incident
status: resolved
triggers:
  - availability/UX: an active conversation was invisible in the rail
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option.
- `human` — Operator did this directly.

# Incident Overview

The **Recent Conversations** rail showed "No conversations yet." while a conversation was actively streaming in the Dashboard. This is a user-facing availability/UX regression of a previously-working surface — no data exposure, no data loss, no statutory-clock implications (Art. 33/34 both `false`).

## Status

resolved — fixed in PR #5391 (Realtime INSERT subscription + bounded SUBSCRIBED backfill).

## Symptom

An active/in-progress conversation did not appear in the rail's Recent Conversations list; the empty-state ("No conversations yet." + "Start one →") rendered instead, until a manual remount/refetch.

## Incident Timeline

- **Start time (detected):** 2026-06-15 23:12 UTC (operator dogfooding; screenshot of the live Dashboard)
- **End time (recovered):** 2026-06-16 (PR #5391 merged + deployed)
- **Duration (MTTR):** ~hours from detection to fix (the underlying gap was long-standing/latent)

| Actor | Time (UTC) | Action |
|---|---|---|
| human | 2026-06-15 23:12 | Incident detected via dogfooding screenshot. |
| agent | 2026-06-16 | Root cause traced (no Realtime INSERT path in `use-conversations.ts`); fix + regression test authored and merged via PR #5391. |

## Participants and Systems Involved

`apps/web-platform` Dashboard conversations rail; Supabase Realtime (`postgres_changes` on `public.conversations`).

## Detection (+ MTTD)

- **How detected:** external/manual — operator dogfooding (not a monitor). No Sentry/Better Stack alert fired (read-freshness gaps are not error-path events).
- **MTTD:** long — the INSERT gap was latent and only surfaced when the operator opened the Dashboard with an empty list and then started a conversation.

## Triggered by

system — architectural composition: per ADR-047 the rail portals outside the Next.js swap region (stays mounted, never re-runs its mount fetch), and the hook subscribed only to Realtime UPDATE events, so a conversation created after mount on an empty list was never added.

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| Repo_url source divergence (the #5317 cause recurring) | same visible symptom | `getCurrentRepoUrl` and the active-repo route both read `workspaces.repo_url` post-#5317 — parity holds | rejected |
| No Realtime INSERT path + no post-create refetch | grep: only `event: "UPDATE"` in the hook; rail stays mounted (ADR-047) | — | confirmed |

## Resolution

PR #5391 added a scoped Realtime INSERT subscription (own + workspace-shared channels) with a shared `shouldDropForScope` guard (repo_url + workspace_id + visibility + archive) and a bounded `SUBSCRIBED`-status backfill refetch to close the create-during-connect race. Fill-only de-dup prevents downgrading enriched rows.

## Recovery verification

Pre-merge: 10-test RED→GREEN hook suite (`test/conversations-rail-insert.test.tsx`), full `vitest run` green (10190 passed), `scripts/test-all.sh` exit 0. Post-merge (AC10): Playwright MCP confirms a conversation appears in the rail within seconds of creation without reload (tracked as the PR's ⏳ follow-through).

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. Why was the conversation missing? The rail never received it. → 2. Why? No Realtime INSERT subscription and no post-create refetch. → 3. Why did the mount fetch not catch it? The rail mounted on an empty list before the conversation existed, and per ADR-047 it portals outside the swap region so it never re-runs the mount effect. → 4. Why was the INSERT path never added? The hook was built with UPDATE-only handling (status changes), and the "appears in the rail" path was implicitly assumed to be the mount fetch. → 5. Why did #5317 not catch it? #5317's test asserts the list populates from the initial fetch; it never exercised "conversation created after mount, list initially empty."

## Versions of Components

- **Version(s) that triggered the outage:** all releases prior to PR #5391 (latent gap).
- **Version(s) that restored the service:** the web-platform release containing PR #5391.

## Impact details

### Services Impacted

`apps/web-platform` Dashboard — Recent Conversations rail only. Conversation creation, streaming, and persistence were unaffected; only the rail's list membership was stale.

### Customer Impact (by role)

- Prospect: none.
- Authenticated app user: the rail appeared empty while actively conversing; could not navigate back to the in-progress conversation from the rail (the conversation itself worked). Tenant-zero (operator) only at this time.
- Legal-document signer: none.
- Admin via Access: none.
- Billing customer: none.
- OAuth installation owner: none.

### Revenue Impact

None.

### Team Impact

Minor — one one-shot engineering cycle.

## Lessons Learned

### Where we got lucky

The defect was read-freshness only — no data was lost or mis-scoped; RLS (migration 075) kept cross-tenant isolation intact throughout.

### What went well

Root cause was traced by reading the hook + ADR-047 rather than guessing; multi-agent review caught a workspace_id scope-guard gap (the new INSERT guard must be scope-equivalent to the fetch query) before merge.

### What went wrong

The INSERT path was never covered by a test; a same-symptom fix (#5317) addressed only one of two causes, leaving this gap open.

## Action Items & Follow-ups

_No action items — incident fully resolved in the source PR with no residual work._ (Anti-recurrence measures all landed in PR #5391: the RED→GREEN regression test, the compound learning, and the work-skill route-to-definition for the realtime-guard / channel-mock-sweep class. The AC10 post-deploy confirmation is tracked via the PR's ⏳ follow-through, not as PIR residual work.)
