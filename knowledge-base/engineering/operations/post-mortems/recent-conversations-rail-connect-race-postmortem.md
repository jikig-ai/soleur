---
title: "Recent Conversations rail omits a freshly-started conversation (connect-race; #5391 follow-up)"
date: 2026-06-16
incident_pr: 5421
incident_window: "since before #5391 (2026-06-16); #5391 reduced but did not close it"
recovery_at: "2026-06-16 (PR #5421 merge)"
suspected_change: "rail per-drill portal (ADR-047) + realtime own-channel subscribe-before-scope-resolve; #5391 INSERT subscription was insufficient for the fresh-mount connect window"
brand_survival_threshold: single-user incident
status: resolved
triggers:
  - user-facing UX defect on the most common path (start a new conversation)
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a — no personal-data breach; UX read-freshness/completeness defect, no exposure, no data loss"
---

## Actor key

- `agent` — Claude Code did this autonomously.
- `human` — Operator did this directly.

# Incident Overview

A newly-started conversation did not appear in the left **Recent Conversations** rail until it *completed*. This is the **second** attempt at the bug — PR #5391 added a Supabase Realtime INSERT subscription + a one-shot `SUBSCRIBED` backfill, but the omission persisted on the reported `/dashboard → /dashboard/chat/new` path. Not an operational outage (no downtime, error-rate spike, data loss, or Sentry alert) — a user-facing read-freshness/completeness defect on the operator's most common surface, recorded as a PIR because it recurred across two PRs (the "first fix didn't fully fix it" learning).

## Status

resolved

## Symptom

After starting a new conversation (Concierge "Routing to the right experts…"), the left rail showed only previously-completed conversations; the freshly-started one appeared only after it completed or after a navigation/refetch.

## Incident Timeline

| Actor | Time (UTC) | Action |
|---|---|---|
| human | 2026-06-16 | Operator reported the rail still omits new conversations (screenshot), after #5391. |
| agent | 2026-06-16 | Root-caused the fresh-mount connect-race; fixed in PR #5421 with a transition-gated scope-resolve backfill + Sentry mirror. |

## Detection (+ MTTD)

- **How detected:** external/manual — operator report with screenshot.
- **MTTD:** n/a (latent UX defect, not monitor-detected — read-freshness gaps do not fire Sentry/Better Stack per #5391).

## Triggered by

user (user-facing UX defect surfaced on the new-conversation path).

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| Connect-race: rail subscribes before workspaceId resolves; own-channel INSERT dropped with no recovery; completion UPDATE is map-only | Code trace use-conversations.ts:288-404; ADR-047 per-drill portal; #5391 PIR's "rail stays mounted" framing was wrong | verify-the-negative confirmed 10/10 claims against origin/main | confirmed |

## Resolution

PR #5421: on the rail's own `useConversations` instance, record an own-channel INSERT dropped solely because `workspaceId` is unresolved (`pendingScopeRecoveryRef`), then refetch once when `workspaceId` transitions `null → id` (transition-gated, mirroring `use-kb-layout-state.tsx:232-240`). The silent drop is mirrored to Sentry via `warnSilentFallback`. Scope-guard parity preserved: every insert path still routes through `shouldDropForScope` (F3 cross-workspace containment).

## Recovery verification

Pre-merge: RED→GREEN regression `test/conversations-rail-connect-race.test.tsx` (5 cases, mutation-verified non-vacuous by test-design-reviewer); full blast radius 96 tests + `scripts/test-all.sh` 119/119 green; `tsc --noEmit` clean. Post-deploy: AC8 Playwright MCP live check (tracked as a ⏳ follow-through + `/soleur:postmerge`).

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. **Why didn't the new conversation appear?** Its own-channel realtime INSERT was dropped during the fresh-mount connect window and never recovered.
2. **Why was it dropped?** `shouldDropForScope` correctly drops an INSERT whose `workspace_id` mismatches the rail's `workspaceId`, which is `null` until the async `fetchConversations` resolves it.
3. **Why no recovery?** The only backfill was a single pre-`SUBSCRIBED` snapshot (could run before the row existed) and the completion UPDATE handler is `map`-only (patches existing rows, cannot add one).
4. **Why did #5391 miss it?** Its PIR assumed the rail stays permanently mounted (ADR-047); in fact the rail portals **per-drill** and remounts on chat entry, so the connect-race fires fresh on the dominant path — a framing the first fix never addressed.
5. **Root cause:** a realtime subscription whose scope filter resolves asynchronously *after* subscribe has a silent drop-zone for own-channel events; recovery must be a deterministic backfill keyed on the scope-state transition, not a wider drop guard or a map-only UPDATE.

## Versions of Components

- **Version(s) that triggered:** all builds since the rail's per-drill portal + realtime subscription (#5391 reduced but did not close it).
- **Version(s) that restored:** PR #5421.

## Action Items & Follow-ups

_No action items — incident fully resolved in the source PR with no residual work._
