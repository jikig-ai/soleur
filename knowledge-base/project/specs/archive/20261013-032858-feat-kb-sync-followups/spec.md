---
title: "KB sync #4706 follow-ups: reconnect affordance + failure-based stale heuristic"
feature: feat-kb-sync-followups
issue: 4712
parent_issue: 4706
branch: feat-kb-sync-followups
pr: 4716
lane: cross-domain
brand_survival_threshold: single-user incident
created: 2026-06-01
status: draft
---

# Spec — KB sync #4706 follow-ups (#4712)

## Problem Statement

A workspace with `repo_status='ready'` but `github_installation_id IS NULL` is silently unreconcilable: the webhook-driven reconcile (`workspace-reconcile-on-push.ts`) selects targets by `github_installation_id`, so a NULL-install workspace never enters the sync loop and writes zero `kb_sync_history` rows. In the parent incident (#4706) this froze a user's Knowledge Base for ~5 weeks — a stale tree, no error shown, and **no in-product way to see or fix it**. #4706 shipped read-only Sentry detection for this class; the operator reconnected manually. Two gaps remain:

1. The user has no in-product reconnect path.
2. A *different* class — `ready` + **installed** workspaces that persistently *fail* to sync (`error_class: SYNC_FAILED`) — is not yet detected.

## Goals

- **G1 (item 1):** Give the affected user a deterministic, in-product, **working** reconnect path for the `ready ∧ NULL-install` state.
- **G2 (item 2):** Make the `ready ∧ installed ∧ latest-sync-failed` class loud (ops-only) so it can't sit frozen unnoticed.
- **G3:** Ship as two sequenced PRs (item 1 first) on this worktree.

## Non-Goals

- **NG1:** No `repo_status` mutation (flipping to `error` degrades the tree — strictly worse). Use a new derived flag only.
- **NG2:** No user-facing surface for item 2 (ops-only Sentry). No dashboard ambient banner for item 1.
- **NG3:** No time-based / "no sync in N days" stale heuristic and no detection of the **went-quiet** class (installed workspace that stops receiving webhooks → no new rows). Deferred to a follow-up issue.
- **NG4:** No migration, no new Inngest function, no new UI component (extend the existing card/cron).
- **NG5:** `#4666` reconcile ignore-list handling for `jikig-ai/soleur` (out of scope; detection still fires).

## Functional Requirements

### Item 1 — Reconnect affordance (PR 1)

- **FR1:** Server-derive `needsReconnect = (repo_status === 'ready' AND github_installation_id IS NULL)` in **`/api/repo/status`** (add `github_installation_id` to its SELECT; return the boolean) — feeds the settings card.
- **FR2:** Server-derive the same `needsReconnect` in **`/api/kb/tree`** (add `github_installation_id` to its SELECT; return alongside `tree`/`lastSync`) — feeds the KB-view notice.
- **FR3:** Add a **"needs reconnect" variant** to `ProjectSetupCard` (`components/settings/project-setup-card.tsx`) shown when `needsReconnect` is true, with a "Reconnect" action and honest copy (re-grants repo access for KB sync).
- **FR4:** Add a **KB-view inline notice** (above the tree) shown when `needsReconnect` is true, with the same Reconnect action. Must be code-traced trigger→render; fires only on the real signal (no ambient/default state).
- **FR5:** The Reconnect action calls **`/api/repo/detect-installation`** first; on no-installation-found, falls through to the full GitHub-App install/authorize flow (`/connect-repo`).

### Item 2 — Failure-based stale heuristic (PR 2)

- **FR6:** Extend **`cron-workspace-sync-health.ts`** with a second `step.run` scan: `ready` + **installed** (`github_installation_id IS NOT NULL`) workspaces whose owner user's **latest `kb_sync_history` row is `ok:false`**.
- **FR7:** For each finding, `reportSilentFallback(err, { feature: "workspace-sync-health", op: "stale-sync-failed", extra: { workspaceId } })`. Read-only; log workspace UUID only (no repo name/path/owner handle).
- **FR8:** No user-facing output for item 2.

## Technical Requirements

- **TR1:** `needsReconnect` is derived server-side only; clients never compute it. `repo_status` is never written by this feature.
- **TR2:** Item 2 resolves the owner user to read `kb_sync_history` (JSONB array on `public.users`; the cron scans `workspaces`). A successful sync = a row with `ok: true` and no `error_class`; failure = `ok: false` + an `error_class`.
- **TR3:** Follow `reportSilentFallback` conventions (`observability.ts`); per `cq-silent-fallback-must-mirror-to-sentry`, every silent branch mirrors to Sentry. Register no new function (item 2 extends the existing cron already registered in `app/api/inngest/route.ts`).
- **TR4:** Tests: item 1 — `needsReconnect` true only for `ready ∧ NULL-install` (false for ready+installed, not_connected, error); reconnect action calls detect-installation then install-fallback. Item 2 — RED→GREEN modeled on `cron-workspace-sync-health.test.ts`: latest-row-`ok:false` ready+installed workspace reports exactly once; ready+installed with latest `ok:true`, NULL-install, and not_connected report none; DB-error path reports once and returns no findings. `vitest run` green + `tsc --noEmit` clean in `apps/web-platform`.
- **TR5:** ux-design-lead engaged at plan time for the card variant + KB-view notice + reconnect flow (per CPO).

## Acceptance Criteria

- [ ] **PR 1:** `needsReconnect` derived in `/api/repo/status` + `/api/kb/tree`; `ProjectSetupCard` variant + KB-view notice render only when true; Reconnect drives detect-installation → install fallback; KB-view notice code-traced. Tests green.
- [ ] **PR 2:** `cron-workspace-sync-health` reports each `ready ∧ installed ∧ latest-row-ok:false` workspace via `reportSilentFallback` (op `stale-sync-failed`, UUID-only); emits nothing for healthy/NULL-install/not_connected; DB-error path reports once. Read-only. Tests green.
- [ ] No `repo_status` mutation anywhere in the diff; no new migration; no new Inngest function.
- [ ] Follow-up issue filed for the went-quiet / time-based arm (NG3).

## Domain Review (carry-forward)

- **CTO:** extend existing patterns, no ADR; item 1 reuses `detect-installation`, item 2 extends the cron; deterministic signals avoid false positives.
- **CPO:** item 1 P1 user-facing (must work end-to-end); item 2 ops-only; ux-design-lead at spec time.
- **CLO:** no statutory clock / DPA trigger; honest reconnect CTA; UUID-only Sentry logging.

Brainstorm: `knowledge-base/project/brainstorms/2026-06-01-kb-sync-followups-brainstorm.md`
