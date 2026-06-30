---
title: "Multi-workspace-per-installation: non-push webhook 404-drop + ready-but-.git-gone shared-workspace dead-end"
date: 2026-06-18
incident_pr: 5546
incident_window: "unknown start (≥ ADR-044 PR-2b deploy) → 2026-06-18"
recovery_at: "2026-06-18 (fix merged in PR #5546)"
suspected_change: "ADR-044 made workspaces.github_installation_id NON-UNIQUE (fan-out); the non-push founder resolver + the dispatch readiness gate still assumed one-solo-workspace-per-installation"
brand_survival_threshold: single-user incident
status: resolved
triggers:
  - availability (non-push webhook events 404-dropped)
  - single-user incident (member permanently blocked from a shared workspace)
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
---

## Actor key
- `agent` — Claude Code autonomously.
- `human` — Operator.

# Incident Overview

Two production defects shared one root cause: a single account can own MULTIPLE workspaces for the same GitHub-App installation+repo, and one org installation spans many repos — a topology ADR-044 deliberately made valid (`github_installation_id` is intentionally NON-UNIQUE on `workspaces`) but which two code paths still treated as impossible.

## Status
resolved

## Symptom
- **Bug 1:** every non-push GitHub webhook event (`pull_request`, `workflow_run`, `issues`, `check_suite`, …) under a multi-repo org installation was 404-dropped with `"ambiguous founder for installation (>1 solo workspaces)"` — Sentry `WEB-PLATFORM-3M`, **734× / 24h**, install `122213433`. PR-review / CI-failure / issue-triage drafts silently stopped generating.
- **Bug 2:** a member opening `/soleur:go` in a shared `jikig-ai/soleur` workspace got "Your workspace isn't ready yet," persisting across retries AND across disconnect+reconnect — the workspace was permanently unusable in the Concierge.

## Incident Timeline
- **Start (detected):** 2026-06-18 — operator reported "5470 still not working in production" with a screenshot of the readiness gate.
- **End (recovered):** 2026-06-18 — fix merged in PR #5546.
- **Duration (MTTR):** same-session diagnosis + fix.

| Actor | Time (UTC) | Action |
|---|---|---|
| human | 2026-06-18 | Reported the Concierge "workspace isn't ready" symptom, attributing it to #5470. |
| agent | 2026-06-18 | Verified #5470 done; pulled prod Sentry (`WEB-PLATFORM-3M` 734×/24h) + Supabase rows; reclassified into Bug 1 + Bug 2. |
| agent | 2026-06-18 | Implemented repo-scoped non-push resolver + ready-but-.git-gone self-heal + migration 113; merged PR #5546. |

## Detection (+ MTTD)
- **How detected:** external/manual — operator report, corroborated by an existing-but-unwatched Sentry issue (`WEB-PLATFORM-3M`) firing 734×/24h. Bug 2 had NO Sentry signal (the `ready` fast-path never reached the self-heal mirror).
- **MTTD:** Bug 1 was emitting to Sentry since the ADR-044 PR-2b deploy but went unwatched; Bug 2 was structurally invisible until the user report.

## Resolution
- **Bug 1:** scope the non-push founder resolver SELECT by `(installation_id, normalizeRepoUrl(repo_url))` (the same fan-out key the push path already used); pre-compose `!full_name` guard; retain the `>1` fail-closed branch for the genuine same-repo two-users-same-fork residual.
- **Bug 2:** add a `ready`-but-`.git`-absent recoverable branch to `repo-readiness-self-heal.ts` (lock-free graft, atomic-rename `.git`-sentinel); cc-dispatcher widens the readiness gate with `existsSync(.git)` evaluated after `!repoReadiness.ok` (hot path unchanged); migration 113 re-targets `set_repo_status`'s failure-reason write to `workspaces.repo_error` so a member-triggered heal failure surfaces an honest reason instead of looping.

## Root Cause(s) — 5-Whys
1. Why did the user get "not ready"? — The shared workspace's physical `.git` was absent and never re-cloned. → Why? The dispatch readiness gate trusted `repo_status='ready'` without checking `.git` on disk, and the fire-and-forget clone discarded its `"failed"` outcome.
2. Why were non-push webhooks dropped? — The founder resolver found >1 solo workspaces. → Why? It joined only on `installation_id`, not `repo_url`, so a multi-repo org install resolved every solo workspace across all repos.
3. Why did both assume one-workspace-per-installation? — ADR-044 made `github_installation_id` NON-UNIQUE (fan-out), but only the PUSH path was migrated to the `(installation_id, repo_url)` key; the non-push resolver and the readiness gate were not swept.

**Cross-cutting cause:** an ADR that changes a uniqueness/cardinality invariant must sweep EVERY consumer of the old invariant, not just the path the originating PR touched.

## Lessons Learned
- A user's "feature X still broken" is a symptom report; verify the cited issue's actual state and pull the prod signal before re-scoping (the loudest Sentry issue and the user's literal symptom were two different bugs).
- "No Sentry error exists" ≠ "the code is fine" — a fast-path that never reaches the error mirror is silent by construction.
- GoTrue admin `?email=` filter is silently ignored (returns the first user) — use `public.users?email=eq.` for prod user lookup.

## Action Items & Follow-ups

| Issue | Item | Owner |
|---|---|---|
| #5274 | Re-evaluate single-host in-session self-heal vs. multi-host snapshot/restore (deferred; single-host suffices today on the persistent `/workspaces` volume). | agent |
| #4755 | Member KB write/refresh route surface (rename/delete/upload/manual-sync) remains in scope; this PR fixed only the dispatch-path clone provisioning. | agent |

## Follow-up 2026-06-18 — Bug 2's ready-clone graft did NOT fully close the incident (dispatch READ-path null-install divergence)

After the Bug 2 ready-clone graft deployed (~14:46 UTC), the operator hit the
**same "no git repository" symptom**, before AND after reconnecting. Root cause:
the graft only fires when `hasConnection` is true
(`installationId !== null && repoUrl`). The agent **was** spawned (it ran the
`/soleur:go` Step 0.0 probe and flailed), which proves the readiness gate
returned `{ok:true}` **without the graft running** — the clone was never
attempted.

The deep cause is a **two-read asymmetry** the ADR-044 sweep missed on the
dispatch READ path: `repo_url`/`repo_status` are non-credential columns read via
a direct RLS `.select()` (member-readable, non-null), while `installationId`
(`workspaces.github_installation_id`) is the credential column read ONLY via the
`resolve_workspace_installation_id` SECURITY DEFINER RPC, which returns NULL on
membership-deny — "indistinguishable from not-connected" (mig 079). So a member
of a connected team workspace reads `repoUrl` non-null while the install RPC
denies/blips → `hasConnection` false → fast-path skip → repo-less agent, with
**no Sentry signal** at the dispatch path.

**Resolution (this PR):** the readiness gate now treats `repoUrl present +
installationId null + .git absent` as a **resolver divergence**, fails honestly
with a membership-deny-aware `RepoNotReadyError` (not a doomed spawn, and NOT the
unactionable "reconnect" CTA), and emits a **paging** `repo_resolver_divergence`
Sentry op (`connected-null-install-at-dispatch`) — closing the previously-dark
dispatch path. The divergence path performs **zero `workspaces` writes** (a
transient/non-member dispatch must not corrupt a healthy team workspace's
`repo_status` for its Owners). ADR-044 amended; credential RPC unmodified; no new
migration. No NEW open action items — this follow-up fully closes the dispatch
arm of the incident.

**Reinforced lesson (extends the cross-cutting cause above):** an ADR that
changes a uniqueness/cardinality invariant must sweep every consumer — including
the ones that read the changed column through a DIFFERENT access path. A
credential column behind a deny-NULL SECURITY DEFINER RPC reads NULL exactly when
a sibling non-credential column reads present; any gate that ANDs the two and
treats NULL as "not connected" silently mis-handles the membership-deny case.
