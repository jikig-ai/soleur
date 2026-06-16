---
title: "ADR-044 dual-resolver divergence stranded invited team-workspace members"
date: 2026-06-17
incident_pr: 5435
incident_window: "latent since the ADR-044 read-path cutover (#4543) until PR-1 (#5435)"
recovery_at: "2026-06-17 (PR-1 merge)"
suspected_change: "ADR-044 read-path cutover left a silent solo-fallback in resolveActiveWorkspaceIdWithMembership + a second raw resolve at cc-dispatcher.ts:1703"
brand_survival_threshold: single-user incident
status: resolved
triggers:
  - invited team-workspace member opens any Concierge workflow
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option.
- `human` — Operator did this directly.

# Incident Overview

Invited team-workspace members could not dispatch Concierge work. The `soleur:go`
Step 0.0 gate told them "workspace isn't ready — reconnect your repository," but
they do not own the connection and reconnecting cannot fix it — an infinite loop.
This is an **availability** incident (a class of users cannot use a feature), not a
data-exposure one: no cross-tenant read actually occurred (the resolver fail-closed
to the caller's own solo workspace), so Art. 33/34 are not triggered.

## Status

resolved — PR-1 (#5435) cuts the dispatch read path to one membership-verified id and
makes the divergence observable + non-stranding. The full always-enforce-workspace
invariant holds after the PR-2 write-path relocation + legacy-column drop (tracked
under #5437).

## Symptom

An invited member opens `/soleur:go` (or any Concierge route) and is told to "reconnect
your repository in Settings → Repository" — an action they cannot perform (they are not
the connection owner). The message recurs on every attempt. Zero Sentry signal.

## Incident Timeline

- **Start time (detected):** latent since the ADR-044 read-path cutover (#4543); first
  diagnosed during the #5437 investigation.
- **End time (recovered):** 2026-06-17 (PR-1 #5435 merge).
- **Duration (MTTR):** the fix slice (PR-1) was implemented + reviewed in one session.

| Actor | Time (UTC) | Action |
|---|---|---|
| human | (during #5437) | Member-stranding reported / diagnosed. |
| agent | 2026-06-17 | PR-1 implemented: unified membership-verified resolver, threaded one id into all dispatch consumers + the :1703 self-heal, dispatch-boundary not-ready copy, divergence breadcrumb, owner-gate, residual membership backfill (mig 109). |
| agent | 2026-06-17 | Multi-agent review (security/migration/user-impact/pattern/architecture) — all clean, zero P1/P2. |

## Participants and Systems Involved

`apps/web-platform` Concierge dispatch (`cc-dispatcher.ts`, `soleur-go-runner.ts`), the
workspace resolver (`workspace-resolver.ts`), the repo connect/disconnect routes, and the
`workspace_members` / `workspaces` / `organizations` schema (mig 053/091/098/109).

## Detection (+ MTTD)

- **How detected:** external/manual — diagnosis during the #5437 investigation. The
  divergence emitted **zero Sentry** (the silent solo fallback swallowed it), so no
  monitor could have caught it. Making it queryable is exactly what PR-1's FR4 breadcrumb
  adds.
- **MTTD:** unbounded (invisible until manually diagnosed).

## Triggered by

user — an invited member dispatching against a team workspace they belong to.

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| Two resolver paths diverge inside one `Promise.all` (`cc-dispatcher.ts:1533-1556`) + a second raw resolve at `:1703` | `fetchUserWorkspacePath` resolved the CWD/clone through the membership self-heal (could fall back to `userId`), while repo+install resolved directly; clone landed in `/workspaces/<userId>` (no `.git`) while repo+install resolved the team | none | confirmed |

## Resolution

PR-1 (#5435):
1. Refactored the silent `resolveActiveWorkspaceIdWithMembership` into the explicit
   `resolveActiveWorkspace` (`{ok,workspaceId,resetFromClaim?}|{ok:false,db-error}`); the
   only `ok` returns are a membership-verified team id or the caller's own `userId` (TR1).
2. Resolved ONCE before the `Promise.all` and threaded the single id into all four
   consumers + the `:1703` self-heal — no second divergent resolve.
3. Fail-closed not-ready copy at the dispatch boundary (transient `db-error`; member
   reset-to-empty-solo switcher) + de-stranded `go.md` Step 0.0 copy.
4. Fingerprint-deduped `repo_resolver_divergence` Sentry breadcrumb (the formerly-invisible
   path is now queryable).
5. Owner-gate on the connect/disconnect routes + read-only member repo card.
6. Residual membership backfill (mig 109) so the owner-membership canary the gate depends
   on is universal (prd was already 0-missing).

## Recovery verification

- `resolveActiveWorkspace` unit tests (4 outcomes incl. TR1 db-error-not-claim-id); dispatcher
  threading test (all consumers + `:1703` receive one id); copy + breadcrumb + route-403 tests.
- `tsc --noEmit` clean; full `vitest` 10,496 passed / 0 failed; `test-all.sh` green; semgrep clean.
- mig 109 verified in a rolled-back dev transaction (18,287→0, idempotent) + a `verify/109`
  CI sentinel asserting `users_missing_owner_canary = 0` post-deploy.
- The `repo_resolver_divergence` breadcrumb makes the next occurrence queryable by fingerprint
  (no SSH).

## 5 Whys (final root cause)

1. **Why were members stranded?** The Concierge dispatch resolved the agent CWD/clone to a
   different workspace than repo+install.
2. **Why did they diverge?** `fetchUserWorkspacePath` went through a membership self-heal that
   could fall back to `userId`, while repo+install resolved the claim directly; a second raw
   resolve at `:1703` re-derived the claim independently.
3. **Why was the fallback silent?** `resolveActiveWorkspaceIdWithMembership` returned a bare
   `userId` on both a non-member claim and a probe error, with no discriminator and no Sentry.
4. **Why no discriminator?** The ADR-044 read-path cutover kept the pre-existing
   string-returning resolver instead of an explicit result type.
5. **Why did it stay invisible?** Zero observability on the divergence — no breadcrumb existed
   for the non-member-claim reset.

Root cause: a silent, string-returning, membership-self-healing resolver used on the dispatch
path with no result discriminator and no observability — fixed by an explicit, fail-closed,
membership-verified resolver resolved once and threaded, plus a deduped divergence breadcrumb.

## Action Items & Follow-ups

| Issue | Item | Owner | Status |
|---|---|---|---|
| #5437 | PR-2 (soak-gated): relocate connect-time writes (`repo/setup`, `repo/create`, `detect-installation`, cron) to `workspaces.*`; drop legacy `users.repo_url`/`workspace_path`/`github_installation_id` with `.down.sql`; update `dsar-export.ts` + `account-delete.ts`; `/soleur:gdpr-gate` on the migration. | agent | deferred (soak-gated on PR-1's breadcrumb) |
| #5437 | Fast-follow: `sentry_issue_alert` routing for the `repo-resolver-divergence` fingerprint (`apps/web-platform/infra/sentry/*.tf`, `-target=sentry_issue_alert.*`), added once the breadcrumb has demonstrably fired in soak. | agent | deferred (soak-gated) |
