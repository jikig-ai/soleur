---
title: "KB sync (#4706 follow-ups): reconnect affordance + failure-based stale heuristic"
date: 2026-06-01
issue: 4712
parent_issue: 4706
branch: feat-kb-sync-followups
pr: 4716
lane: cross-domain
brand_survival_threshold: single-user incident
user_brand_critical: true
status: complete
---

# Brainstorm — KB sync #4706 follow-ups (#4712)

## What We're Building

Two follow-ups deferred from the KB-sync freeze incident (#4706), shipped as **two separate PRs on this one worktree, item 1 first**:

1. **Reconnect affordance (user-facing, P1).** Surface a deterministic "this workspace can't sync — Reconnect" path for the `repo_status='ready' AND github_installation_id IS NULL` state, which today is silently unreconcilable (the webhook-reconcile filter requires a non-NULL install id, so the workspace never enters the sync loop and writes zero `kb_sync_history` rows). The reconnect action drives a **real end-to-end re-auth**, not an inform-only banner.

2. **Failure-based stale heuristic (ops-only).** Extend the existing `cron-workspace-sync-health` cron to also alert when a `ready` + **installed** workspace's **latest `kb_sync_history` row is `ok:false`** (a recorded persistent failure, e.g. `error_class: SYNC_FAILED`). Sentry-only, deterministic, no user-facing surface.

## Why This Approach

The parent incident (#4706, plan `2026-05-31-fix-kb-sync-stale-design-folder-frozen-timestamps-plan.md`) shipped read-only Sentry detection for the NULL-install class and the operator reconnected manually. These follow-ups close the two remaining gaps: (a) the user had **no in-product way** to fix or even see the freeze, and (b) a *different* class — workspaces that are installed but persistently failing to sync — is not yet detected.

**Two premise corrections from research** (the issue/plan were factually stale; carry these into the plan so it doesn't re-derive against fiction):
- `RepoConnectionCard` **does not exist**. The real surface is `ProjectSetupCard` (`apps/web-platform/components/settings/project-setup-card.tsx`) + `DisconnectRepoDialog`. The only "reconnect" today is the `error`-state "Retry Setup" `<a>` link.
- `/api/kb/tree` **does not 409 on `repo_status='error'`** (it 404s on `not_connected`, 503 on `workspace_status!='ready'`; the 409s live in `/api/kb/sync`). The "don't flip to `error`" constraint still holds in *spirit* (degrading the tree is worse than a stale-but-visible tree) → still use a new derived flag, never mutate `repo_status`.
- **Decisive enabler:** `/api/repo/detect-installation` already exists as the NULL-install auto-heal path (resolves GitHub login → finds installation → stores id → mirrors to solo workspace per ADR-044). So "Reconnect" is a genuine one-click fix, not a dead-end.

Item 2 chose the **deterministic failure-based** signal over the issue's literal time-based "no `ok:true` in N days" wording because the triad + learnings flagged calendar-time-only as the highest false-positive design (idle repos with no pushes look frozen forever). A `latest row is ok:false` signal is a real recorded failure → near-zero false positives, no threshold to tune. The went-quiet / no-new-rows class is deferred (see Open Questions + follow-up issue).

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | Both items, two PRs on this worktree, **item 1 first** | Item 1 is deterministic + UX-reviewable + high value; item 2 is ops-only. Sequenced, not bundled into one PR. |
| 2 | Item 1: derive `needsReconnect = (repo_status='ready' AND github_installation_id IS NULL)` **server-side** in both `/api/repo/status` (feeds settings card) and `/api/kb/tree` (feeds KB-view notice) | Reuse requests the UI already makes; add `github_installation_id` to each SELECT. Never mutate `repo_status`. |
| 3 | Item 1 surfaces: **(a) `ProjectSetupCard` "needs reconnect" variant** in settings **+ (b) KB-view inline notice** at the point of pain (above the stale tree) | Operator chose two surfaces. Settings card = where you manage the connection; KB-view notice = where you feel the freeze. Both gated on the deterministic boolean; not an ambient dashboard banner. |
| 4 | Reconnect action → call `/api/repo/detect-installation` first, fall through to full GitHub-App install/authorize (`/connect-repo` flow) only if no install found | detect-installation auto-heals the common case (install exists, id wasn't stored); full OAuth consent only when no install exists at all. Honest CTA copy (CLO). |
| 5 | KB-view inline notice must be **code-traced end-to-end** (trigger→render) and gated on judgment-relevance (fire only on the real `needsReconnect` signal) | Silent-UI learnings (`.catch(noop)` / unreachable-toast failure modes). |
| 6 | Item 2: extend **existing** `cron-workspace-sync-health` (not a sibling cron) with a second scan: `ready` + installed workspace whose latest `kb_sync_history` row is `ok:false` → `reportSilentFallback(feature:"workspace-sync-health", op:"stale-sync-failed", extra:{workspaceId})` | Same scan authority, same plumbing, one registration. Deterministic signal. |
| 7 | Item 2 is **ops-only Sentry**; log **workspace UUID only** (no repo names/paths/owner handles) | CPO: no user-facing stale banner (trust erosion). CLO: data-minimization. |
| 8 | Visual design (wireframes) **deferred to plan/spec time** via `ux-design-lead` | CPO explicitly: route the install/authorize flow + card variant to ux-design-lead at spec time. Scope is a state-variant on an existing card + a reused inline-notice pattern — no Pencil wireframe needed at brainstorm. |

## Open Questions

- **Item 2 data location:** `kb_sync_history` is a JSONB array on `public.users` (not `workspaces`). The cron scans `workspaces`; item 2's scan must resolve the owner user to read the latest row (service-client read). Plan-time implementation detail.
- **Went-quiet class (deferred):** a `ready`+installed workspace that simply stops receiving webhooks writes **no new rows at all** (latest row stays `ok:true` forever). The failure-based signal won't catch this. Deferred to a follow-up (time-based / push-correlation arm) — see follow-up issue. Re-evaluate if Sentry shows this class occurring.
- **`#4666` reconcile ignore-list:** `jikig-ai/soleur` (the platform's own dev repo) is on the ignore-list; even after reconnect, `workspace-reconcile-on-push.ts:149` short-circuit may need attention for that specific repo. Out of scope here (detection still fires regardless).

## User-Brand Impact

- **Artifact:** KB-sync visibility/recovery (reconnect affordance + failure detection).
- **Vector:** (a) silent data staleness recurring — a user's KB frozen indefinitely with no error shown; (b) trust breach via false alarms — a too-sensitive heuristic nagging healthy/idle workspaces; (c) reconnect dead-end — a button that looks actionable but doesn't actually re-authorize. The operator endorsed **all three** as the risks these changes address.
- **Threshold:** `single-user incident` (inherited from parent plan #4706). Even N=1 clears it because the failure mode is silent and indefinite. Mitigations: item 1's flag is a deterministic boolean (~zero false positives); item 2 is ops-only + deterministic + UUID-only logging; reconnect drives a real re-auth.
- **Data durability note:** KB content is git-backed in the user's own GitHub repo — this is *sync staleness*, not data loss. Severity framed accordingly (no GDPR Art. 33/34 trigger — see CLO).

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering (CTO)

**Summary:** Both items extend established patterns — no ADR, no new service/schema. Item 1: derive `needsReconnect` in existing endpoints, wire into `ProjectSetupCard`, reuse `detect-installation`; no new component (YAGNI). Item 2: extend the existing cron; deterministic `latest-row-ok:false` avoids the idle-repo false-positive trap. Corrected the `RepoConnectionCard` fiction and the `/api/kb/tree` 409 mislocation. Ship item 1 first, two PRs.

### Product (CPO)

**Summary:** Item 1 is P1 build-now — deterministic boolean → ~zero false-positive, must work end-to-end (inform-only recreates the dead-end). Item 2 stays operator-facing only; a user-facing stale banner on idle repos is the exact trust erosion to avoid. Single confirmed user today, but silent-and-indefinite failure clears the single-user threshold. Route install/authorize flow design to ux-design-lead at spec time.

### Legal (CLO)

**Summary:** No material legal exposure — no statutory clock, no DPA trigger, standard product change. GitHub renders its own re-auth consent screen (no new Soleur disclosure). Stale-sync heuristic processes no new personal data; log workspace UUID only (data-min). Silent staleness of intact, git-backed data is a product-quality defect, not a personal-data breach (no Art. 33/34 duty). Honest reconnect CTA copy is the only soft requirement.

## Capability Gaps

None. Verified present on `main`: `/api/repo/detect-installation` (NULL-install auto-heal), `/api/repo/install` + `/connect-repo` state machine (full OAuth flow), `ProjectSetupCard` + `DisconnectRepoDialog` (settings surface), `cron-workspace-sync-health` (cron scaffold + `reportSilentFallback` plumbing), `append_kb_sync_row` RPC + `KbSyncRow` types (`ok`/`error_class` fields). Evidence: `git grep` of each symbol across `apps/web-platform/` (see repo-research findings, this session).
