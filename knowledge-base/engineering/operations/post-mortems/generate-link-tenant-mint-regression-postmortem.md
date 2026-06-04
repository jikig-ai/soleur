---
title: "Generate-link button broken by migration 059 workspace_id NOT-NULL sweep miss (+ initial misdiagnosis)"
date: 2026-06-04
incident_pr: 4913
fix_pr: 4920
incident_window: "migration 059 deploy → 2026-06-04"
recovery_at: "on merge of the workspace_id insert fix (PR #4920)"
suspected_change: "migration 059_workspace_keyed_rls_sweep (workspace_id NOT NULL on kb_share_links, no DB default; createShare insert never updated)"
brand_survival_threshold: single-user incident
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

The "Generate link" button in the KB document Share popover silently stopped producing public share links — clicking it returned to the idle panel with no error. **Root cause:** migration `059_workspace_keyed_rls_sweep` added `workspace_id uuid NOT NULL` (no DB default) to `kb_share_links`, but the `createShare` INSERT (`server/kb-share.ts`) was never updated to set it. Every share-create insert therefore failed with Postgres **23502 (not-null violation)** → `db-error` 500 → the client `share-popover.tsx` resets to idle on any non-ok response.

**Initial misdiagnosis (PR #4913).** The first fix blamed PR #3854's tenant-JWT mint (a service-role 503-fallback in `resolveUserKbRoot`). That hypothesis was never verified against production before shipping; it did NOT fix the button. The actual tenant read works fine in prod — verified by minting a real founder tenant JWT via the GoTrue admin path and replicating the exact `.from("users")…single()` read (it returned the row with no error).

## Status

resolved — fixed in PR #4920 (set `workspace_id` on `kb_share_links` / `push_subscriptions` / `conversations` inserts).

## Symptom

Clicking "Generate link" → brief "Loading…" → bounce back to the "Generate a public link…" idle panel, no error toast. The popover *opened* fine (GET/`checkShare` never inserts), masking the failure as "nothing happens on click."

## Incident Timeline

| Actor | Time (UTC) | Action |
|---|---|---|
| system | migration 059 deploy | `kb_share_links.workspace_id` becomes NOT NULL (no default); `createShare` insert unchanged → all share-creates 23502. |
| human | 2026-06-04 | Founder reports the dead "Generate link" button (screenshot). |
| agent | 2026-06-04 | **Misdiagnosed** as tenant-mint 503; shipped PR #4913 (service-role fallback). Did not fix the button. |
| human | 2026-06-04 | Founder reports "still failing in production." |
| agent | 2026-06-04 | Pulled prod ground truth (Sentry via `SENTRY_IAC_AUTH_TOKEN`; prod DB via `DATABASE_URL_POOLER`); reproduced the real `23502` on `kb_share_links.workspace_id`; verified fix; swept all NOT-NULL workspace_id tables → 2 more broken inserts. PR #4920. |

## Participants and Systems Involved

`apps/web-platform` — `server/kb-share.ts` (`createShare`), `app/api/kb/share`, `app/api/push-subscription`, `app/api/repo/setup`, `app/api/kb/upload`; Supabase Postgres (`kb_share_links`, `push_subscriptions`, `conversations` — all gained `workspace_id NOT NULL` in migration 059).

## Detection (+ MTTD)

- **How detected:** founder dogfooding (external/manual). The `createShare` db-error path DOES call `reportSilentFallback`, but no alert was wired to its rate, and a Sentry query during diagnosis showed no matching issue — the silent-fallback signal was not reaching an actionable surface.
- **MTTD:** the latent window spanned from the 059 deploy to the founder report.

## Triggered by

system — a large workspace-multi-tenancy migration (059) added a NOT-NULL FK column to many tables; the writer-side sweep missed several insert call sites.

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| Tenant-JWT mint 503s `resolveUserKbRoot` (PR #3854) | git archaeology: #3854 changed `route.ts:37` | Minted a real founder JWT in prod → tenant self-read returns the row, no error; PR #4913 fallback did NOT fix the button. | **REJECTED (misdiagnosis)** |
| `kb_share_links.workspace_id` NOT NULL, insert omits it | prod INSERT without workspace_id → 23502; with it → success | — | **CONFIRMED** |

## Resolution

`createShare` now takes a `workspaceId` and sets `workspace_id` on the insert; the share route + MCP tool resolve it via `resolveCurrentWorkspaceId` (claim → solo fallback = userId). The same omission was found and fixed on `push_subscriptions` (new push subscriptions) and `conversations` (repo-setup sync conversation). `kb_files` upload wsId resolution was switched off the buggy `workspace_members…maybeSingle()` (which throws for multi-workspace owners) to `resolveCurrentWorkspaceId`.

## Recovery verification

Per-fix prod proof via `DATABASE_URL_POOLER`: each insert fails 23502 without `workspace_id` and succeeds with it. Full webplat vitest shard green CI-equivalent. New regression assertion in `kb-share.test.ts` asserts the insert carries `workspace_id`.

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. **Why did the button do nothing?** `POST /api/kb/share` returned 500 `db-error`; the client resets to idle on any non-ok.
2. **Why 500?** `createShare`'s insert into `kb_share_links` violated a NOT NULL constraint (Postgres 23502).
3. **Why was the constraint violated?** `kb_share_links.workspace_id` is NOT NULL with no DB default (migration 059), but the insert never set it.
4. **Why didn't the migration update the insert?** Migration 059 swept RLS + added `workspace_id NOT NULL` to ~13 tables but the writer-side (every `.insert`/`.upsert` call site) was not exhaustively swept — `hr-write-boundary-sentinel-sweep-all-write-sites` was not mechanically enforced for the column-addition class.
5. **Why did it take a misdiagnosis + a second report to fix?** The first fix trusted a plan-time git-archaeology hypothesis (tenant mint) without pulling prod ground truth (the actual 23502). Once prod DB/Sentry was queried and the mint read replicated, the real cause was obvious in minutes.

## Lessons Learned

### What went wrong
- A NOT-NULL FK column added to existing tables by a large migration was not paired with an exhaustive insert-site sweep → silent 23502 in prod across multiple features (share, push, repo-setup).
- A fix shipped on an **unverified hypothesis**. Symptom → root-cause tracing requires the *actual* producer error, not a plausible mechanism.
- The db-error path's `reportSilentFallback` was not wired to an alert, so a constraint that breaks EVERY insert sat latent.

### What went well
- The no-SSH prod toolchain (`SENTRY_IAC_AUTH_TOKEN` for issues, `DATABASE_URL_POOLER` for DB introspection + safe rollback-tx reproduction) pinned the real cause definitively and cheaply.
- The schema-driven sweep (enumerate NOT-NULL-no-default `workspace_id` columns from the DB, then grep every insert site) generalised one bug into three.

## Follow-ups

- [ ] Workflow/skill safeguard: when a migration adds a NOT-NULL column with no default to an EXISTING table, mechanically sweep every insert/upsert writer. See the new learning + `apps/web-platform/scripts/audit-not-null-column-insert-coverage.mjs`.
- [ ] Wire an alert on the kb-share / kb-route db-error `reportSilentFallback` rate so a constraint that breaks every insert pages instead of sitting latent.
- [ ] Revert the unnecessary service-role fallback PR #4913 added to `resolveUserKbRoot` (dead code now — the mint was never the cause; restoring the tenant-only boundary removes the unjustified `.service-role-allowlist` re-introduction). CODEOWNERS-gated allowlist edit; tracked separately.

## Action Items

- PR #4920 — the real fix (this incident).
- Alert on kb db-error `reportSilentFallback` rate — to file (supersedes the narrower #4918 tenant-mint-only framing).
- #4914 (file-route tenant-mint fallback) — **close as based-on-misdiagnosis** (the mint was never the cause).
