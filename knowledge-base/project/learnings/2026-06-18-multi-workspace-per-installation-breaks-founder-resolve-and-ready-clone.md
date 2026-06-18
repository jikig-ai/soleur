# Learning: a user's "feature X still broken" can be two downstream bugs; pull the prod signal before scoping

## Problem

A user reported "what's left for #5470? still not working in production" with a screenshot of the Concierge `soleur:go` "workspace isn't ready" gate. #5470 (the ADR-044 service-role installation resolver) was CLOSED and verified live. Treating the report as "5470 regressed" would have been wrong on two counts.

Read-only prod forensics (Supabase REST + Sentry + Better Stack via Doppler `prd`/`prd_terraform`) reclassified BOTH premises:

1. **#5470 was genuinely done.** Its ACs + both scope-expansion items shipped; migration 112 dropped the legacy column cleanly. Not the cause.
2. The real symptom was **two distinct bugs sharing one root cause** — a single user/account can have MULTIPLE workspaces for the same GitHub-App installation+repo (a solo workspace `id == userId` PLUS team/shared workspaces; and one org installation spans many repos), which ADR-044 made true but several code paths still assumed false:
   - **Bug 1 (confirmed: Sentry `WEB-PLATFORM-3M`, 734×/24h):** the NON-PUSH webhook founder resolver (`resolve-founder-for-installation.ts`) joined only on `github_installation_id`, not `repo_url` → a multi-repo org install resolved `>1` solo workspaces → `{kind:ambiguous}` → 404-drop of every non-push event (incl. unmapped `check_suite`). The push path already scoped by `(installation_id, repo_url)`; the non-push path was an incomplete implementation of #5470's own scope-expansion comment #3.
   - **Bug 2 (the user's blocker, NO Sentry signal):** a member's cold dispatch into a `repo_status='ready'` shared workspace whose physical `.git` is ABSENT was never re-cloned — the readiness gate trusted `repo_status` without checking `.git` on disk, and the fire-and-forget `ensureWorkspaceRepoCloned` discarded its `"failed"` outcome. Persisted across retries and disconnect+reconnect.

## Solution

- **Bug 1:** scope the non-push resolver SELECT by `(installation_id, normalizeRepoUrl(repo_url))` (compose `https://github.com/<full_name>` exactly like the push reconcile); pre-compose `!full_name` guard drops missing-repo events without a SELECT; retain the `>1` fail-closed branch for the genuine same-repo two-users-same-fork residual.
- **Bug 2:** add a `ready`-but-`.git`-absent recoverable branch to `repo-readiness-self-heal.ts` (LOCK-FREE — `claim_repo_clone_lock` matches only `error`/stale-`cloning` rows by construction; concurrency via the clone's `randomUUID` temp-dir + atomic-rename `.git`-sentinel re-check). cc-dispatcher widens the gate with `existsSync(join(workspacePath, ".git"))` evaluated AFTER `!repoReadiness.ok` so `getFreshTenantClient` stays off the hot path. Migration 113 re-targets `set_repo_status`'s failure-reason write from the dropped `users.repo_error` to `workspaces.repo_error` (the column the gate has read since migration 110) so a member-triggered heal failure surfaces the honest reason instead of looping.

## Key Insight

A user's "X still doesn't work" is a symptom report, not a root-cause diagnosis. Before re-opening or re-scoping the cited issue: (1) verify the cited issue's actual shipped state, (2) pull the real prod signal yourself (Sentry issue search + the affected DB rows), (3) expect the symptom to decompose into bug(s) DIFFERENT from the cited issue. The loudest Sentry issue (734×/day `WEB-PLATFORM-3M`) and the user's literal symptom were two different bugs with one shared root cause (multi-workspace-per-installation). "No Sentry error exists" is not "the code is fine" — a `ready`-fast-path that never reaches the self-heal mirror is silent by construction.

## Session Errors

- **GoTrue admin `GET /auth/v1/admin/users?email=<x>` silently ignores the `email` filter** and returns the FIRST user in the list (here `live-verify@soleur.ai`, a synthetic test account), which I mis-attributed as the real user's workspace before catching it. **Recovery:** query `GET /rest/v1/users?email=eq.<x>` (public.users) instead. **Prevention:** for prod user lookup by email, always use the PostgREST `public.users?email=eq.` filter, never the GoTrue admin list endpoint's `?email=` param. (recurring — prod-forensics trap)
- `UID` is a readonly shell variable; `UID=$(...)` fails. **Recovery:** rename to `USERID`. **Prevention:** avoid `UID`/`GID`/`PWD` as assignment targets in Bash. (one-off)
- `workspaces.workspace_status` does not exist (42703) — `workspace_status` is on `users`. **Recovery:** drop it from the `workspaces` SELECT. **Prevention:** ADR-044 relocated repo columns to `workspaces` but provisioning/readiness columns (`workspace_status`, `health_snapshot`) stayed on `users`. (one-off)
- (forwarded) plan subagent's initial `Write` targeted the bare-repo path; harness redirected to the worktree per `hr-when-in-a-worktree-never-read-from-bare`. (one-off, auto-handled)

## Tags
category: integration-issues
module: apps/web-platform/server (webhooks, repo provisioning)
related: [[2026-06-15-gsc-crawled-not-indexed-remediation-is-internal-linking]]
