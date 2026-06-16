---
title: Fix Concierge workspace-checkout self-heal + reconnect recovery + auto-sync push/BYOK-lease resilience
date: 2026-06-16
type: fix
branch: feat-one-shot-concierge-reconnect-self-heal-checkout
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
status: draft
---

# 🐛 Fix Concierge reconnect self-heal + auto-sync push/BYOK-lease resilience

## Enhancement Summary

**Deepened on:** 2026-06-16 (multi-agent pass: verify-the-negative, architecture-strategist,
observability-coverage-reviewer, spec-flow-analyzer).

### Key corrections folded in (all P0/P1 from review)
1. **cc-dispatcher cannot write `repo_status` with its tenant client** (RLS-filtered to zero rows; it is
   off the service-role allowlist by design). The optimistic lock now lives in a NEW SECURITY DEFINER RPC
   (`claim_repo_clone_lock` + `set_repo_status`) callable via tenant `.rpc()`. **Added a migration line
   item the v1 plan was missing entirely** — this was the biggest gap (architecture P0-1).
2. **The stale-`cloning` self-heal was a terminal trap** — a `.neq("cloning")` predicate can never
   re-acquire a `cloning` row, stranding a dead-winner row forever. Replaced with an
   `error OR (cloning AND repo_last_synced_at < now()-5min)` RPC predicate (spec-flow P0-1).
3. **Auto-sync retry would re-INSERT the sync conversation per attempt** (orphan rows). Conversation INSERT
   now happens ONCE outside the retry; only `startAgentSession` is retried (architecture P0-3).
4. **FIX 1b's surface was wrong** — `kb-reconnect-banner.tsx` does not exist, and `ReconnectNotice` renders
   only for `ready`, never the `error`/`cloning` states it targets. Re-wired into `project-setup-card.tsx`'s
   `error` branch + added a bounded status poll (only `connect-repo/page.tsx` polls today → otherwise
   spinner-forever) + a repo-reachability guard (spec-flow P0-2/P0-3/P2).
5. **`op auto-sync-degraded` had no emit site** (`startAgentSession` is `Promise<void>`); now read back from
   `conversations.status` or dropped. New self-heal op gets a NEW Sentry alert resource (appending to the
   chat-save rule breaks `sentry-chat-alert-op-contract.test.ts`). Client `reconnect-resetup` uses the
   browser Sentry SDK, not the server-only `reportSilentFallback` (observability P1/P2).
6. **Proxy-vs-invariant ACs hardened** — added AC1b (post-self-heal `.git` actually exists, not just
   `{ok:true}` from a stub) and marked AC3/AC10 as doc-contract/presence proxies.

## Overview

A Concierge dispatch dead-ends with a `Repository setup failed: … Reconnect in Settings → Repository`
message even after the user clicks Reconnect, because **Reconnect structurally cannot re-clone** and
the readiness gate that emits that message blocks dispatch *before* the existing on-disk self-heal can
run. This plan closes that loop and hardens the two post-clone auto-sync failure modes (GH013 push
rejection, BYOK-lease race) that surfaced alongside it (Sentry web-platform, 2026-06-16 08:57–09:01 CEST).

No new dependencies. No version-file bumps (`plugins/soleur/AGENTS.md` — `plugin.json`/`marketplace.json`
are frozen sentinels). Tests-first per `cq-write-failing-tests-before`.

This work is **surgical** — it extends three existing, recently-merged systems rather than rebuilding them:

- the `#5394` repo-readiness dispatch gate (`server/repo-readiness.ts` + `cc-dispatcher.ts:1563`),
- the `#5340/#5240/#5367/#4890` session-start self-heal (`server/ensure-workspace-repo.ts`),
- the `/api/repo/setup` clone + auto-sync path (`app/api/repo/setup/route.ts`).

## Research Reconciliation — Spec vs. Codebase

The bug report is **directionally correct but stale on three mechanism details**. The codebase is further
along than the report assumes (the self-heal already exists). Reconciling before planning:

| Bug-report claim | Codebase reality (verified) | Plan response |
| --- | --- | --- |
| "the readiness gate fails with 'workspace directory doesn't exist on disk'" | That exact string is **not** in the codebase. `evaluateRepoReadiness` (`repo-readiness.ts:69`) keys **only** on `repo_status ∈ {cloning, error}` — it never tests `.git`/dir presence. The dir-missing symptom ("configured CWD `/workspaces/<uuid>` doesn't exist") comes from the bwrap sandbox build, guarded separately by `ensureWorkspaceDirExists` (`ensure-workspace-repo.ts:83`). | FIX 1 targets the **real** dead-end: the `repo_status=error` gate throw at `cc-dispatcher.ts:1568`, which fires **before** the self-heal at `:1697`. The "dir missing but installation present" case is already handled by `ensureWorkspaceRepoCloned` once the gate lets dispatch through. |
| "re-run `provisionWorkspaceWithRepo` to re-hydrate the checkout" (in the dispatch path) | `provisionWorkspaceWithRepo` (`workspace.ts:166`) is **destructive** — it calls `removeWorkspaceDir` (`:185`) to wipe-and-reclone. It is NOT idempotent and would clobber un-pushed agent commits in a `.git`-present workspace. The **idempotent** safe re-clone is the existing `ensureWorkspaceRepoCloned` (`.git`-absent gated, lands `.git` last as success sentinel). | FIX 1 (dispatch path) reuses `ensureWorkspaceRepoCloned` — it does NOT call `provisionWorkspaceWithRepo`. The destructive wipe-and-reclone belongs only to the **operator-initiated** reconnect path (FIX 1b → `/api/repo/setup`). |
| "self-heal re-clone in the dispatch readiness path" as a NEW mechanism | The self-heal already exists at `cc-dispatcher.ts:1674` (`ensureWorkspaceDirExists`) + `:1697` (`ensureWorkspaceRepoCloned`). The gap is **gate ordering**: `error`/`cloning` short-circuits at `:1568` *upstream* of the recovery — the exact anti-pattern in learning `2026-06-14-short-circuit-guard-must-sit-after-the-recovery-it-gates.md`. | FIX 1 is a **gate-reordering / self-heal-then-re-evaluate** change, NOT a new clone mechanism. The `error` branch attempts recovery (`ensureWorkspaceRepoCloned` under an optimistic `repo_status` lock) before honestly blocking. |
| "RuntimeAuthError: …; retry shortly" originates from `byok-lease.ts:375` | `byok-lease.ts:375` is `ByokLeaseError("escape", "Authentication unavailable; retry shortly")` (lease accessor called outside its ALS scope). `RuntimeAuthError` (`lib/supabase/tenant.ts:86`) is a **distinct** type with the same user-facing copy, thrown on tenant-JWT mint failure. Both can surface from the post-clone auto-sync `startAgentSession` (no retry/backoff anywhere). | FIX 3 makes the **auto-sync trigger** (`setup/route.ts`) resilient to BOTH error classes via bounded retry/defer — it does not need to disambiguate them at the call site; `getUserApiKey` (`agent-runner.ts:216`) stays the authoritative chat-time backstop. |
| "the sync agent commits KB scaffolding and `git push`es, hitting GH013" | The server `pushBranch` MCP tool (`server/push-branch.ts:57`) **already** rejects protected branches. So GH013 is NOT from `pushBranch` — it is the `/soleur:sync --headless` agent running a **raw `git push`** (Bash tool) inside the user's freshly-cloned workspace, whose checked-out branch after `git clone --depth 1` is the protected default. | FIX 2 makes the **headless sync** commit locally / open a PR via the worktree→PR workflow and handle GH013 gracefully (the sync command body + the auto-sync invocation), never a raw push to the default branch. |

**Premise Validation (Phase 0.6):** All cited file paths exist and were read. Sibling worktree
`feat-one-shot-gate-legacy-leader-repo-status` exists (local + remote) and targets a **different** gap —
adding the readiness gate to the **legacy leader** dispatch path (`agent-runner.ts startAgentSession`,
which currently has **no** `evaluateRepoReadiness` call). This plan touches the **cc-dispatcher** gate and
the **setup/reconnect** paths only; the two do not collide. `#5394` (gate) and `#5395` (block-dispatch)
are merged to main (commits `867f77978`, present in git log). No cited GitHub issue is already-closed in a
way that makes this premise stale; the bug is a live gap on top of the merged gate.

## User-Brand Impact

**If this lands broken, the user experiences:** the same dead-end loop they have today — Concierge says
"Repository setup failed: … Reconnect in Settings → Repository", the user clicks Reconnect, the button
re-verifies the GitHub App but the workspace checkout is still missing/errored, and the very next message
shows the identical error. The user is structurally stuck with no in-product recovery (the symptom that
produced the 08:57–09:01 Sentry cluster). A bad FIX 1 (e.g., calling the destructive
`provisionWorkspaceWithRepo` on the dispatch path) could **wipe un-pushed agent commits** in a
`.git`-present workspace — silent work-loss.

**If this leaks, the user's workflow is exposed via:** the readiness-gate error message and any Sentry
event. The gate already routes its reason through `sanitizeGitStderr` + `parseErrorPayload`
(`repo-readiness.ts:81-83`), and all new Sentry emits use `reportSilentFallback`/`warnSilentFallback`
(pseudonymized `userIdHash`, sanitized `message`). No new raw-stderr or raw-`userId` surface is introduced.

**Brand-survival threshold:** single-user incident — one founder hitting this once is a full
recovery-loop dead-end on the core onboarding→work path. `requires_cpo_signoff: true`;
`user-impact-reviewer` runs at review time.

## Problem Statement

### BUG 1 (PRIMARY) — Reconnect cannot recover a missing/errored checkout

```text
Concierge dispatch (cold)  →  realSdkQueryFactory (cc-dispatcher.ts:1465)
  └─ Promise.all reads getCurrentRepoStatus (:1548)  → repo_status="error"
  └─ evaluateRepoReadiness (:1563)  → { ok:false, code:"error" }
  └─ throw RepoNotReadyError (:1568)  ❌ DEAD-END, dispatch never reaches:
       ensureWorkspaceDirExists (:1674)     ← would re-create the dir
       ensureWorkspaceRepoCloned (:1697)    ← would re-clone the .git-less checkout
  catch (:3346 / :3422)  →  sendToClient "Repository setup failed: … Reconnect in Settings → Repository"
```

`POST /api/repo/detect-installation` (the Reconnect button's target, `use-reconnect.ts:33`) only
re-verifies the GitHub App and mirrors `github_installation_id` (`detect-installation/route.ts`) — it has
**zero** references to `repo_status`, `provisionWorkspaceWithRepo`, or setup. The only route that clones
(and resets `repo_status` to `cloning`→`ready`) is `/api/repo/setup`. So a workspace whose DB row is
`repo_status=error` (e.g. a clone that 403'd on a cross-account install) can never recover: the gate
blocks dispatch, and Reconnect can't re-clone.

The self-heal at `:1697` **could** recover a `.git`-less checkout (it's idempotent, `.git`-absent gated),
but the `error` gate throw at `:1568` amputates it — the textbook
`short-circuit-guard-must-sit-after-the-recovery-it-gates` anti-pattern.

### BUG 2 — Auto-sync pushes to a protected branch (GH013)

After a successful clone, `setup/route.ts:266` fires `startAgentSession(… "/soleur:sync --headless")`.
The `/soleur:sync` agent runs in the user's freshly-cloned workspace; its checked-out branch after
`git clone --depth 1` is the repo's **protected default**. When the agent commits KB scaffolding and runs a
raw `git push` (Bash tool, NOT the protected-branch-rejecting `pushBranch` MCP tool), GitHub returns
`GH013: Repository rule violations` (branch protection / push protection). The agent surfaces a hard error.

### BUG 3 — BYOK lease race in auto-sync

The morning `RuntimeAuthError: Authentication unavailable; retry shortly` originates from the **same**
post-clone auto-sync `startAgentSession`. The sync fires immediately after the clone resolves; the
BYOK lease (`resolveKeyOwnerThenLease` → `runWithByokLease`, `byok-resolver.ts:119`) was not yet leasable
(tenant-JWT mint blip → `RuntimeAuthError`, or a lease accessor invoked outside its ALS scope →
`ByokLeaseError("escape")` at `byok-lease.ts:375`). There is **no** retry/backoff anywhere in the
auto-sync trigger, so the rejection escapes into the fire-and-forget `.then()` promise. The setup route's
`userHasEffectiveByokKey` gate (`:228`) checks key *presence*, not lease *availability at fire time*.

## Architecture (current, verified)

```text
                 ┌──────────────────────────── /api/repo/setup (clone path) ────────────────────────────┐
                 │ optimistic lock: users.repo_status "cloning" (.neq cloning) :125-147                  │
                 │ provisionWorkspaceWithRepo (DESTRUCTIVE wipe+reclone) :166                            │
                 │ .then(): repo_status="ready" :192 ──► userHasEffectiveByokKey :228 ──► auto-sync      │
                 │           startAgentSession("/soleur:sync --headless") :266  ◄── BUG 2 + BUG 3        │
                 │ .catch(): repo_status="error" + sanitized repo_error :306                             │
                 └──────────────────────────────────────────────────────────────────────────────────────┘

  Reconnect button (use-reconnect.ts) ──► POST /api/repo/detect-installation
                                          (re-verify App, mirror installation_id; NO re-clone)  ◄── BUG 1b

  Concierge dispatch (cc-dispatcher.ts realSdkQueryFactory):
     getCurrentRepoStatus :1548 ─► evaluateRepoReadiness :1563 ─► throw RepoNotReadyError :1568  ◄── BUG 1a
                                                                  (dead-ends ABOVE the self-heal)
     ensureWorkspaceDirExists :1674   (unconditional mkdir, fail-loud)
     ensureWorkspaceRepoCloned :1697  (idempotent, .git-absent gated, fail-soft)
```

## Goals

1. **FIX 1a (dispatch self-heal):** when the readiness gate sees `repo_status=error` (or a stale
   `cloning`) **and** an installation + `repo_url` are present **and** the on-disk checkout is missing/
   `.git`-less, attempt the existing idempotent `ensureWorkspaceRepoCloned` recovery (under an optimistic
   `repo_status` lock) and **re-evaluate** before honestly blocking — instead of dead-ending at the gate.
2. **FIX 1b (reconnect recovery):** wire `use-reconnect.ts` (and the `detect-installation` success path)
   so that when `repo_status != ready`, Reconnect re-triggers `POST /api/repo/setup` for the connected
   `repoUrl` — the button does what its own error message promises.
3. **FIX 2 (sync push):** the headless sync must NOT raw-`git push` to a protected branch — commit
   locally and/or open a PR (worktree→PR workflow), and handle GH013/push-rule rejection gracefully
   (clear status, Sentry mirror per `cq-silent-fallback-must-mirror-to-sentry`).
4. **FIX 3 (lease race):** the auto-sync trigger retries/backs off (or defers) when the BYOK lease/auth is
   unavailable at fire time, never throws into the setup background promise, and never leaves
   `repo_status` in a bad state. `getUserApiKey` stays the authoritative backstop.

## Non-Goals

- Adding the readiness gate to the **legacy leader** dispatch path (`agent-runner.ts startAgentSession`) —
  that is the sibling worktree `feat-one-shot-gate-legacy-leader-repo-status`'s scope. Do not touch it.
- Full-history / branch-aware clone (the self-heal stays `--depth 1`; a deliberate first-slice limit).
- Team/multi-member repo-setup flows (`#4560`); all writes here remain solo-only (`workspace.id === user.id`).
- Decomposing `cc-dispatcher.ts` (`#3243`) — surgical edits only (see Open Code-Review Overlap).
- Replacing `provisionWorkspaceWithRepo`'s destructive semantics — it stays the operator-reconnect path.

## Implementation Phases

### Phase 0 — Preconditions (verify at /work time, before any edit)

- `grep -n "evaluateRepoReadiness" apps/web-platform/server/cc-dispatcher.ts` → confirm the gate is still
  at `:1563`-`:1573`, upstream of `ensureWorkspaceRepoCloned` (`:1697`).
- `grep -n "removeWorkspaceDir" apps/web-platform/server/workspace.ts` → confirm `provisionWorkspaceWithRepo`
  still wipes (so the plan's "use `ensureWorkspaceRepoCloned` on the dispatch path, NOT
  `provisionWorkspaceWithRepo`" decision holds).
- Confirm the optimistic-lock shape on `users.repo_status` at `setup/route.ts:123-129`
  (`.update({…repo_status:"cloning"}).neq("repo_status","cloning").select("id").maybeSingle()`).
- Test runner: `cd apps/web-platform && ./node_modules/.bin/vitest run <path>` (vitest, NOT bun — bunfig
  `pathIgnorePatterns=["**"]` blocks bun discovery, #1469). Test files MUST live under
  `apps/web-platform/test/**/*.test.{ts,tsx}` to match `vitest.config.ts` `include` globs.
- Typecheck: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (NOT `npm run -w`; repo root has no
  `workspaces` field).

### Phase 1 — Failing tests first (RED) — `cq-write-failing-tests-before`

Write three failing tests covering the three required scenarios (a)/(b)/(c). All under
`apps/web-platform/test/`.

1. **(a) gate self-heals when checkout missing but installation present.**
   File: `apps/web-platform/test/server/cc-dispatch-repo-self-heal.test.ts` (new).
   - Drive the extracted decision function (Phase 2 introduces `resolveRepoReadinessWithSelfHeal` — a
     pure-ish orchestrator that takes injected `ensureWorkspaceRepoCloned` + `transitionRepoStatus`
     seams, mirroring the `__setGraftForTests` seam pattern in `ensure-workspace-repo.ts:30`).
   - RED assertions: given `repo_status="error"`, `installationId != null`, `repoUrl` set, and a stubbed
     self-heal that succeeds → the function transitions status to `cloning`, invokes the self-heal, and
     returns `{ ok: true }` (dispatch proceeds) — NOT a thrown `RepoNotReadyError`.
   - Branch matrix: self-heal `"failed"` → returns `{ ok:false, code:"error" }` (honest block preserved);
     `installationId == null` OR `repoUrl == null` → no self-heal attempt, honest block (no installation
     to recover with); `repo_status="ready"` → `{ ok:true }`, no self-heal (unchanged happy path);
     concurrent-dispatch optimistic-lock loser → no double `ensureWorkspaceRepoCloned` invocation.

2. **(b) reconnect re-triggers setup when `repo_status != ready`.**
   File: extend `apps/web-platform/test/components/repo/use-reconnect.test.tsx` AND a
   `project-setup-card` test (the surface that mounts reconnect in the `error` state — verify the test
   path against `vitest.config.ts` globs; component tests live under `test/`, NOT co-located).
   - RED: mock `fetch` so `POST /api/repo/detect-installation` → `{ installed:true, repos:[…repoUrl…] }`
     AND a status probe reports `repo_status != "ready"` with a known connected `repoUrl` (in the repo
     list) → assert the reconnect path issues `POST /api/repo/setup { repoUrl }` then polls
     `GET /api/repo/status` until terminal.
   - Branch: `repo_status === "ready"` → NO setup POST; `installed:false` → existing `/connect-repo`
     redirect (unchanged); connected `repoUrl` NOT in the returned repo list → `/connect-repo` redirect
     (reachability guard); setup POST non-200 → falls loud via the **client** Sentry SDK
     (`lib/client-observability`, NOT server `reportSilentFallback`) + still resolves (no dead button,
     #4712); background-clone failure (`status` polls to `error`) → terminal actionable state shown (no
     spinner-forever).

3. **(c) sync handles GH013 without hard-failing.**
   File: `apps/web-platform/test/server/auto-sync-trigger.test.ts` (new) for the server-side trigger
   resilience, plus a sync-command-body assertion.
   - RED (server, BUG 3 + the trigger half of BUG 2): drive the extracted
     `triggerHeadlessSync(userId, …, { startAgentSession })` (Phase 5) with a stubbed `startAgentSession`
     that rejects once with `RuntimeAuthError`/`ByokLeaseError("escape")` then resolves → assert bounded
     retry/backoff, eventual success, **exactly ONE `conversations` INSERT across all attempts** (no
     orphan rows — architecture P0-3), and that on exhausted retries it mirrors to Sentry
     (`reportSilentFallback`, op `auto-sync-trigger`) and **does not** rethrow into the setup `.then()`
     and **does not** mutate `repo_status` (stays `ready`).
   - RED (sync command body, BUG 2): a markdown-contract test asserting the headless branch of
     `plugins/soleur/commands/sync.md` instructs commit-local / worktree→PR and explicit GH013
     handling — never a raw `git push <protected-default>`. Use a `plugins/soleur/test/*.test.ts`
     drift-guard grep (the repo's existing skill-doc test convention) OR a vitest source-grep under
     `apps/web-platform/test/` if the sync body lives where vitest collects. (Pick the runner that
     actually discovers the file — verify with the Phase 0 globs.)

Run all three; confirm they FAIL for the right reason (not import errors).

### Phase 2 — FIX 1a: dispatch self-heal + re-evaluate (GREEN)

`server/repo-readiness.ts` + `server/cc-dispatcher.ts` + a NEW Supabase migration (definer RPC).

> **[Deepen-plan correction — architecture P0-1 + P0-3 + spec-flow P0-1]:** Three load-bearing fixes
> from multi-agent review are folded in here:
> 1. **cc-dispatcher cannot write `repo_status` with its tenant client.** `repo_status` lives on
>    `workspaces` (ADR-044); `workspaces` has **no UPDATE RLS policy for `authenticated`** — every
>    existing status write goes through a **service-role** client (`workspace-repo-mirror.ts:35-37`).
>    cc-dispatcher was **deliberately migrated OFF the service-role allowlist** (PR-D;
>    `cc-dispatcher.ts:1642-1644`). A tenant-client UPDATE on `workspaces` is **silently RLS-filtered to
>    zero rows** → the predicate-lock `maybeSingle()` returns `null` for EVERY dispatch → the self-heal
>    is dead-on-arrival. **Fix: a SECURITY DEFINER RPC** does the lock + status writes server-side,
>    callable via the **tenant `.rpc()`** with an internal membership check — keeping cc-dispatcher off
>    the allowlist (`hr-write-boundary-sentinel-sweep-all-write-sites`).
> 2. **The stale-`cloning` self-heal is a terminal trap, not a recovery.** A `.neq("repo_status","cloning")`
>    predicate can NEVER re-acquire a row already in `cloning`. A winner that dies after the
>    `error→cloning` flip but before the `failed→error` write leaves a `.git`-absent `cloning` row that no
>    dispatch can ever exit (every dispatch honest-waits forever). **Fix: the self-heal acts ONLY on
>    `error` rows** (never `cloning→cloning`), and the dead-winner `cloning` row is recovered by an
>    `updated_at`-guarded heartbeat in the RPC + the reconnect path (FIX 1b can reset `cloning`→`error`).

- **New migration `NNN_repo_clone_self_heal_rpc.sql`** (`apps/web-platform/supabase/migrations/` — `ls`
  the latest 2-3 first; no `CREATE INDEX CONCURRENTLY`/non-transactional DDL per migration-runner
  transaction wrap). Two SECURITY DEFINER functions, `search_path` pinned to `pg_catalog, pg_temp`
  (`cq-pg-security-definer-search-path-pin-pg-temp`), `REVOKE EXECUTE FROM public, anon, authenticated,
  service_role` then `GRANT EXECUTE TO authenticated` (mirror migration 079's 4-role pattern):
  - `claim_repo_clone_lock(p_workspace_id uuid) RETURNS boolean` — internal membership check
    (`auth.uid()` ∈ workspace members); `UPDATE workspaces SET repo_status='cloning', repo_last_synced_at=now()
    WHERE id=p_workspace_id AND (repo_status='error' OR (repo_status='cloning' AND repo_last_synced_at <
    now() - interval '5 minutes'))` — the `error`-OR-**stale-`cloning`** predicate is the dead-winner
    escape (an `updated_at`/heartbeat guard, NOT a `.neq` predicate); returns `FOUND` (won/lost). This is
    the ONLY place `cloning→cloning` re-acquire is permitted, and only past the staleness window.
  - `set_repo_status(p_workspace_id uuid, p_status text, p_error text) RETURNS void` — membership-checked
    terminal write of `ready`/`error` + sanitized reason; writes BOTH `workspaces.repo_status` and (for
    the error reason consumed by the gate) the dual-write `users.repo_error` server-side, so the TS
    `mirrorRepoColsToSoloWorkspace` (service-role-only) is NOT needed on the dispatch path.
  - Precedent-diff the definer pattern against migration 079 + 083 (`SECURITY DEFINER` + REVOKE/GRANT
    shape) and cite it in Risks.
- Add a new `resolveRepoReadinessWithSelfHeal(args, seams)` orchestrator. Keep `evaluateRepoReadiness`
  **pure** (AC7). Per architecture P0-2, the orchestrator takes **injected seams** so the pure module
  stays DB-free in test: `{ evaluateRepoReadiness, claimCloneLock, setRepoStatus, ensureWorkspaceRepoCloned,
  gitDirExists }`. **House the orchestrator in a new `server/repo-readiness-self-heal.ts`** (NOT in the
  pure `repo-readiness.ts` — keep the decision layer free of I/O imports). It:
  1. `const r = evaluateRepoReadiness(status, repoError)`; if `{ ok:true }` → return it immediately
     (zero-await fast path — `ready`/`not_connected` never touch a seam).
  2. if `{ ok:false, code:"error" }` AND `installationId != null` AND `repoUrl` present AND
     `gitDirExists(workspacePath) === false`:
     - `const won = await claimCloneLock(workspaceId)` (the RPC — `error`-or-stale-`cloning`→`cloning`).
       **loser** (`won === false`) → return `{ ok:false, code:"cloning", message: REPO_CLONING_MSG }`
       (another dispatch is actively healing within the window — honest-wait, never double-clone).
     - **winner** → `const outcome = await ensureWorkspaceRepoCloned({ userId, workspacePath,
       installationId: effectiveInstallationId, repoUrl })` (idempotent, `.git`-absent-gated, fail-soft;
       reuse `effectiveInstallationId` per `2026-06-15-parallel-recovery-path-must-reuse-same-resource-selection`).
       - `"ok"` → `await setRepoStatus(workspaceId, "ready", null)`; return `{ ok:true }` (dispatch
         proceeds into the existing `:1674`/`:1697` region, which now no-ops because `.git` is present).
       - `"failed"` → `await setRepoStatus(workspaceId, "error", <sanitized reason>)`; mirror to Sentry
         (`reportSilentFallback`, feature `cc-dispatcher`, op `repo-readiness-self-heal`); return
         `{ ok:false, code:"error", … }` (honest block preserved — but only after a real attempt).
  3. if `{ ok:false, code:"cloning" }` (a fresh in-window cloning, NOT stale) → return it unchanged
     (honest-wait; the staleness escape lives in `claimCloneLock`, so a genuinely-in-progress
     `/api/repo/setup` clone is never disturbed).
  4. else (no installation / no repoUrl / `.git` present) → return the original `{ ok:false }` (cannot
     recover — honest block, unchanged).
- **Gate placement** (`cc-dispatcher.ts`): keep a **zero-await `evaluateRepoReadiness` fast-path check at
  the current `:1563` site** that short-circuits `ready`/`not_connected` immediately (no behavior change,
  no extra probe). Only the `error`/`cloning` branch falls through to call
  `resolveRepoReadinessWithSelfHeal` **after** `effectiveInstallationId` (`:1656`) + `ensureWorkspaceDirExists`
  (`:1674`) — the self-heal needs the dir guaranteed + the promoted install. This two-stage shape avoids
  paying the `resolveEffectiveInstallationId` JWT-probe on the ready/not_connected hot path (architecture
  P1-1) while applying the `short-circuit-guard-must-sit-after-the-recovery-it-gates` correction for the
  recoverable branch. Throw `RepoNotReadyError` only on the orchestrator's `{ ok:false }`.
- **Concurrency vs in-progress `/api/repo/setup`** (architecture P1-2): because the self-heal acts only on
  `error` rows (or `cloning` past the 5-min staleness window), and a live setup clone holds a FRESH
  `cloning` (well within the window), the dispatch never races a live setup clone — it honest-waits. The
  `ensureWorkspaceRepoCloned` graft is itself race-safe vs a second dispatch (`randomUUID` temp dir +
  `.git`-sentinel re-check, `ensure-workspace-repo.ts:217-242`).

### Phase 3 — FIX 1b: reconnect re-triggers setup (GREEN)

`components/repo/use-reconnect.ts` + `components/settings/project-setup-card.tsx`.

> **[Deepen-plan correction — spec-flow P0-2 + P0-3]:** The originally-named surface was wrong.
> `components/kb/kb-reconnect-banner.tsx` **does not exist**. `ReconnectNotice`
> (`components/repo/reconnect-notice.tsx`) is mounted in exactly ONE state:
> `repoStatus === "ready" && needsReconnect` (`project-setup-card.tsx:56`) — the #4712
> install-null-but-ready affordance. It is **never** rendered for `repo_status ∈ {error, cloning}` — those
> states render a **"Retry Setup → /connect-repo"** link (`project-setup-card.tsx:85-97`) and a static
> spinner (`:99-104`) respectively. So a `repo_status != ready` branch added to `useReconnect` alone would
> be **dead code** (its button never shows in the targeted states). Additionally, **only
> `connect-repo/page.tsx` polls `/api/repo/status`** — the Settings card's spinner is a static server
> snapshot, so a kicked-off re-setup whose background clone fails transitions to `error` **invisibly**
> (spinner-forever / stale view until manual reload).

- **Surface the recovery in the state that needs it.** In `project-setup-card.tsx`, change the **`error`
  branch's** "Retry Setup" affordance (and, for an origin-mismatch `ready` row, the existing
  `ReconnectNotice`) to call a `reconnect()` that, on `detect-installation {installed:true}` + a known
  connected `repoUrl`, issues `POST /api/repo/setup { repoUrl }` (the canonical wipe-and-reclone) — rather
  than (or in addition to) the bare `/connect-repo` redirect. The `error` state is the primary FIX 1b
  entry point; do NOT rely on `ReconnectNotice` (which only renders for `ready`).
- **Add a status poll after re-setup.** `POST /api/repo/setup` returns `{status:"cloning}` immediately and
  clones fire-and-forget; the card must poll `GET /api/repo/status` until terminal (`ready` → refresh /
  `error` → show the actionable failure), mirroring `connect-repo/page.tsx`'s existing poll. Without this
  the recovery is invisible (spinner-forever). Bound the poll (max attempts + interval) and surface a
  clear terminal state on `error`.
- Keep every branch code-traced (no `.catch(noop)`): a setup POST failure falls loud — for the **client**
  surface use the **browser Sentry SDK** (`Sentry.captureException` via `lib/client-observability`, which
  routes through the client-side config layer), NOT the server-only `reportSilentFallback`
  (`server/observability.ts` is a server module — observability P2 finding); tag `feature:kb-reconnect
  op:reconnect-resetup`. Still resolves so the button is never dead (#4712). The existing `installed:false`
  → `/connect-repo` redirect is untouched.
- **1a vs 1b are complementary, not redundant** (spec-flow Q3): FIX 1a (`.git`-absent self-heal) recovers
  the missing-checkout `error` row on the next message; FIX 1b (`/api/repo/setup` wipe-and-reclone) is the
  ONLY path that re-clones an **origin-mismatch / `.git`-present-but-wrong** workspace, which 1a's
  `.git`-absent gate deliberately refuses to touch (`ensure-workspace-repo.ts:142`). 1b also resets a
  dead-winner `cloning` row (it always re-locks via setup's own `users.repo_status` optimistic lock).
- **Reachability guard before re-setup** (spec-flow P2): `detect-installation {installed:true}` aggregates
  repos across the reachable set but does NOT prove the connected `repoUrl` is covered by the (possibly
  changed) installation. Before firing re-setup, confirm the connected `repoUrl` is in the returned repo
  list; if absent, redirect to `/connect-repo` (the repo must be re-selected) rather than POSTing a setup
  that will 400/403. (`setup/route.ts` already returns a 400 "not installed" — surface it as the actionable
  terminal state, not a silent failure.)
- The button's error message ("Reconnect in Settings → Repository") now matches behavior: Reconnect
  re-clones via setup.

### Phase 4 — FIX 2: headless sync must not push to a protected branch (GREEN)

`plugins/soleur/commands/sync.md` (the `/soleur:sync` body) + the auto-sync invocation in `setup/route.ts`.

- Add an explicit **headless / `--headless`** execution contract to `sync.md`: in headless mode the sync
  agent (a) commits KB scaffolding **locally**, and (b) if it would push, uses the **worktree→PR**
  workflow (matching the project's existing pattern and the `pushBranch` protected-branch contract) —
  it MUST NOT raw-`git push` the checked-out default branch. On a `GH013`/`! [remote rejected]`/push-rule
  rejection it surfaces a clear, actionable status ("knowledge-base committed locally; could not open a PR
  — branch protection rejected the push") rather than a hard error.
- Headless mode also short-circuits the interactive `AskUserQuestion` gates already in `sync.md`
  (Phase 2 review / Phase 4 definition-sync) — in headless they auto-skip (the body must state this so the
  agent doesn't block on a prompt that can never be answered).
- **Observability of the degraded outcome** (observability P1 finding): `startAgentSession` is
  `Promise<void>` (fire-and-forget) — its result surfaces only via the WS stream + `conversations.status`,
  never a return value. So the trigger CANNOT inspect a return value for "committed-locally-but-GH013".
  To make `op auto-sync-degraded` reachable: the headless sync writes a **degraded marker** the trigger
  can read — set `conversations.status` (e.g. a `failed`/degraded value) OR a dedicated
  `conversations.sync_degraded` sentinel on GH013; the trigger, after the `startAgentSession` promise
  settles, **reads `conversations.status` back** and, on the degraded value, emits `reportSilentFallback`
  (feature `repo-setup`, op `auto-sync-degraded`) per `cq-silent-fallback-must-mirror-to-sentry`. If the
  marker mechanism is judged too heavy for the first slice, **drop the `auto-sync-degraded` op** and state
  that GH013-degraded is observed via the existing chat-failure path (`conversations.status="failed"` +
  the existing chat-failure alert) — do NOT ship an op slug with no emit site (it would resolve to zero
  Sentry events and mislead).

### Phase 5 — FIX 3: auto-sync trigger lease/auth resilience (GREEN)

`app/api/repo/setup/route.ts` (extract the auto-sync trigger to a testable helper).

- Extract the lines `setup/route.ts:222-281` (the `hasEffectiveKey` gate + conversation insert +
  `startAgentSession` fire) into `server/auto-sync-trigger.ts` `triggerHeadlessSync(userId, repoUrl, {…})`
  with an injectable `startAgentSession` seam (so the resilience is unit-testable without the SDK).
- **Conversation INSERT happens ONCE, outside the retry boundary** (architecture P0-3): create the sync
  `conversations` row (single `crypto.randomUUID()` id + `session_id`) **before** the retry loop, then
  wrap **only** the `startAgentSession(conversationId, …)` call in the bounded retry, reusing the **same**
  `conversationId` on every attempt. Retrying the whole body would mint a new conversation per attempt →
  orphaned "active" conversations behind the ready screen (the exact orphan the `userHasEffectiveByokKey`
  gate at `:228` was added to prevent). `RuntimeAuthError`/`ByokLeaseError("escape")` are raised at
  lease-bind time BEFORE any agent work, so retrying `startAgentSession` is idempotent w.r.t. the lease as
  long as no durable side effect sits inside the retried span.
- Wrap the `startAgentSession` call in **bounded retry with backoff** specifically for the
  lease/auth-unavailable classes: catch `RuntimeAuthError` and `ByokLeaseError` (and the
  `"Authentication unavailable; retry shortly"` message as a defensive substring), retry up to N times
  (e.g. 3) with exponential backoff (e.g. 1s/3s/9s — the lease/JWT-mint blip is short). On success → done.
  On exhausted retries → `reportSilentFallback` (feature `repo-setup`, op `auto-sync-trigger`,
  pseudonymized userId) and **return** — never rethrow into the `.then()`/escape unhandled (learning
  `2026-03-20-fire-and-forget-promise-catch-handler`), and **never** touch `repo_status` (it stays
  `ready`; the clone succeeded; only the convenience auto-sync is degraded). On exhaustion, also mark the
  single pre-created conversation appropriately (or leave it for manual `/soleur:sync`) — never INSERT a
  second row.
- `getUserApiKey` (`agent-runner.ts:216`) remains the authoritative chat-time enforcement backstop — the
  retry here is a convenience for the *auto* trigger only, not a replacement for the lease lifecycle.
- The existing `userHasEffectiveByokKey(onErrorReturn:true)` presence-gate stays (skip sync entirely for
  keyless users); the retry layers on top for the keyed-but-lease-not-yet-ready race.

### Phase 6 — Verify (REFACTOR + full suite)

- Run the three RED suites → GREEN.
- `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean.
- Targeted re-run of adjacent suites that could regress: `repo-readiness.test.ts`,
  `ensure-workspace-repo.test.ts`, `cc-reprovision.test.ts`, `use-reconnect.test.tsx`,
  `server/byok-lease.test.ts`.
- Sync-doc drift-guard green.

## Files to Edit

- `apps/web-platform/server/repo-readiness.ts` — UNCHANGED decision (`evaluateRepoReadiness` stays pure);
  the orchestrator goes in a NEW module (below), not here.
- `apps/web-platform/server/cc-dispatcher.ts` — keep the zero-await `evaluateRepoReadiness` fast-path at
  `:1563` (ready/not_connected); fall the `error`/`cloning` branch through to
  `resolveRepoReadinessWithSelfHeal` AFTER `effectiveInstallationId` (`:1656`) + `ensureWorkspaceDirExists`
  (`:1674`); preserve the `RepoNotReadyError` catch at `:3346`/`:3422`.
- `apps/web-platform/components/repo/use-reconnect.ts` — re-trigger `POST /api/repo/setup` when
  `repo_status != ready` (with the reachability guard); poll status to terminal; fall-loud via the
  **client** Sentry SDK on failure.
- `apps/web-platform/components/settings/project-setup-card.tsx` — surface the re-setup recovery in the
  `error` branch (the state that actually renders for a broken checkout), not only `ReconnectNotice`
  (`ready`-only); add the bounded status poll mirroring `connect-repo/page.tsx`.
- `apps/web-platform/app/api/repo/setup/route.ts` — extract the auto-sync trigger; call
  `triggerHeadlessSync`.
- `plugins/soleur/commands/sync.md` — add the headless execution contract (commit-local / worktree→PR /
  GH013 handling / auto-skip interactive gates). NOTE: `sync.md` is a `commands/` file, not a `skills/`
  description — the 1800-word skill-description budget does NOT apply (no `bun test components.test.ts`
  budget impact).

## Files to Create

- `apps/web-platform/supabase/migrations/NNN_repo_clone_self_heal_rpc.sql` — `claim_repo_clone_lock` +
  `set_repo_status` SECURITY DEFINER RPCs (membership-checked, `search_path` pinned, 4-role REVOKE +
  GRANT to `authenticated`). The load-bearing fix for the tenant-client write barrier (architecture P0-1).
- `apps/web-platform/server/repo-readiness-self-heal.ts` — `resolveRepoReadinessWithSelfHeal` orchestrator
  with injected seams (`evaluateRepoReadiness`, `claimCloneLock`, `setRepoStatus`,
  `ensureWorkspaceRepoCloned`, `gitDirExists`) — keeps `repo-readiness.ts` I/O-free.
- `apps/web-platform/server/auto-sync-trigger.ts` — `triggerHeadlessSync` (conversation INSERT once;
  retry wraps only `startAgentSession`) + bounded retry/backoff + Sentry mirror + degraded-result read-back.
- `apps/web-platform/test/server/cc-dispatch-repo-self-heal.test.ts` — RED scenario (a) (decision-level,
  injected seams; includes the post-self-heal `.git`-existence integration assertion per AC1b).
- `apps/web-platform/test/server/auto-sync-trigger.test.ts` — RED scenario (c) server half (incl.
  one-conversation-INSERT assertion).
- (extend) `apps/web-platform/test/components/repo/use-reconnect.test.tsx` + a `project-setup-card` test —
  RED scenario (b).
- A migration/RPC unit (or `BEGIN; SELECT claim_repo_clone_lock(...); ROLLBACK;` shape) asserting the
  lock predicate (`error`-or-stale-`cloning`→`cloning`, never fresh-`cloning`) — verify the test runner
  the migration suite uses.
- A sync-doc drift-guard test under the runner that discovers it (`plugins/soleur/test/` bun OR
  `apps/web-platform/test/` vitest — verify at Phase 0).

## Open Code-Review Overlap

`#3243` (arch: decompose cc-dispatcher.ts into focused modules) touches the file FIX 1 edits.
**Acknowledge** — this plan makes a surgical, additive change (one rewired gate call + a new orchestrator
function) and does NOT undertake the decomposition; the two are compatible and #3243 remains open as its
own cycle. No other open `code-review` issue names any file in `## Files to Edit`/`## Files to Create`
(checked `cc-dispatcher`, `repo-readiness`, `ensure-workspace-repo`, `setup/route`, `use-reconnect`,
`detect-installation`, `byok-lease`, `auto-sync-trigger`).

## Observability

```yaml
liveness_signal:
  what: "Sentry issue-alert rate for feature=cc-dispatcher op=repo-readiness-self-heal (recovery attempts) vs op=repo-readiness-gate (honest blocks). A drop in honest-block rate after deploy = self-heal recovering what used to dead-end."
  cadence: "per-dispatch (event-driven), reviewed in Sentry Issues"
  alert_target: "A NEW dedicated sentry_issue_alert resource for feature=cc-dispatcher op IS_IN {repo-readiness-self-heal} (do NOT append to the existing cc-dispatcher chat-save op-contract rule — its op IS_IN set is pinned to the three persistUserMessage slugs and the test/sentry-chat-alert-op-contract.test.ts drift-guard fails on any append). Pick an unused frequency value (taken: 5,10,15,30,60,61,62)."
  configured_in: "apps/web-platform/infra/sentry/issue-alerts.tf (NEW resource, mirror the byok rule shape ~line 286+)"
error_reporting:
  destination: "SERVER paths: Sentry via reportSilentFallback/warnSilentFallback (server/observability.ts) — tags feature+op, pseudonymized userIdHash, sanitized message; mirrored to pino → Better Stack. CLIENT path (reconnect-resetup): browser Sentry SDK via lib/client-observability (server reportSilentFallback is server-only and would NOT reach the pino mirror)."
  fail_loud: "Self-heal clone failure → reportSilentFallback (error level). Lease-retry exhaustion → reportSilentFallback. Reconnect re-setup failure → client Sentry.captureException. Honest cloning-block → logger.info breadcrumb only (expected transient, NOT an incident — matches existing #5394 pattern at cc-dispatcher.ts:3347)."
failure_modes:
  - mode: "dispatch self-heal clone fails (token expired / repo gone / network)"
    detection: "Sentry feature=cc-dispatcher op=repo-readiness-self-heal (server reportSilentFallback)"
    alert_route: "NEW cc-dispatcher self-heal issue alert"
  - mode: "reconnect re-setup POST fails"
    detection: "Sentry feature=kb-reconnect op=reconnect-resetup (CLIENT browser Sentry SDK — lib/client-observability, NOT server reportSilentFallback)"
    alert_route: "Sentry issue search (low volume; user-visible terminal state persists)"
  - mode: "auto-sync lease/auth unavailable after N retries"
    detection: "Sentry feature=repo-setup op=auto-sync-trigger (server reportSilentFallback)"
    alert_route: "Sentry issue alert"
  - mode: "headless sync committed locally but GH013-rejected the PR push (degraded)"
    detection: "Sentry feature=repo-setup op=auto-sync-degraded — emitted by triggerHeadlessSync after reading conversations.status back (NOT from startAgentSession's void return); IF the read-back marker is descoped, observed instead via conversations.status='failed' + the existing chat-failure alert (drop this op rather than ship an emit-less slug)."
    alert_route: "Sentry issue alert OR existing chat-failure path"
logs:
  where: "Better Stack (pino mirror of every server reportSilentFallback/warnSilentFallback + the cc-dispatcher logger.info honest-block breadcrumb)"
  retention: "per existing Better Stack retention (unchanged)"
discoverability_test:
  command: "Open Sentry → Issues → search `feature:cc-dispatcher op:repo-readiness-self-heal`, `op:repo-readiness-gate`, `feature:repo-setup op:auto-sync-trigger`, and (if kept) `op:auto-sync-degraded`, and the CLIENT-emitted `feature:kb-reconnect op:reconnect-resetup`. Each kept tag pair resolves to queryable events with NO SSH."
  expected_output: "Self-heal events tagged feature=cc-dispatcher op=repo-readiness-self-heal; lease-retry-exhaustion events tagged feature=repo-setup op=auto-sync-trigger. Honest-block rate visible as logger.info breadcrumbs in Better Stack. (Every op slug in the plan has a real emit site in the diff — no emit-less slugs.)"
```

Observability layer cited: **Sentry issue-alert tag filtering** (`apps/web-platform/infra/sentry/issue-alerts.tf`
`feature`/`op` `EQUAL`/`IS_IN` filters; a NEW resource for the self-heal op) + **client Sentry SDK**
(`lib/client-observability`) for the reconnect path + **Better Stack** (pino mirror). No SSH in any
verification path (`hr-observability-as-plan-quality-gate`, `hr-no-ssh-fallback-in-runbooks`,
`hr-observability-layer-citation`).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 (a):** `cc-dispatch-repo-self-heal.test.ts` proves: `repo_status="error"` + installation +
      `repoUrl` + `.git`-absent → `claimCloneLock` won → `ensureWorkspaceRepoCloned` invoked → `{ ok:true }`
      (dispatch proceeds), NOT a thrown `RepoNotReadyError`. Branch matrix: self-heal `failed` →
      `setRepoStatus(error)` + honest block; no-installation/no-repoUrl → honest block, NO clone; lock
      loser → `{ ok:false, code:"cloning" }` honest-wait, NO `ensureWorkspaceRepoCloned` call; fresh
      `cloning` (not stale) → honest-wait unchanged; `ready` → `{ ok:true }`, no seam touched.
- [ ] **AC1b (invariant, not proxy):** an integration-shaped assertion that after a SUCCESSFUL self-heal,
      `gitDirExists(workspacePath)` is true (the real `ensureWorkspaceRepoCloned` landed `.git`) — NOT just
      that the orchestrator returned `{ ok:true }` with a stub. (Closes the proxy-vs-invariant gap: a stub
      returning "ok" while leaving `.git` absent must NOT satisfy the AC.)
- [ ] **AC1c (RPC):** a migration/RPC test proves `claim_repo_clone_lock` flips `error`→`cloning` AND
      stale-`cloning`(> 5 min)→`cloning`, but returns false (no-op) for a FRESH `cloning` row and for a
      non-member caller; `set_repo_status` is membership-gated. SECURITY DEFINER + `search_path` pin +
      4-role REVOKE/GRANT present (precedent: migration 079/083).
- [ ] **AC2 (b):** `use-reconnect.test.tsx` + `project-setup-card` test prove: `detect-installation
      {installed:true}` + connected `repoUrl` in the returned repo list + `repo_status != "ready"` →
      `POST /api/repo/setup {repoUrl}` issued, THEN `GET /api/repo/status` polled to terminal.
      `repo_status=="ready"` → no setup POST. `repoUrl` NOT in repo list → `/connect-repo` redirect.
      Setup-POST failure → **client** Sentry SDK (`lib/client-observability`) + still resolves (no dead
      button). Background-clone failure → `status` polls to `error` → terminal actionable state (no
      spinner-forever). The `error`-state surface (`project-setup-card.tsx`) actually renders the
      reconnect affordance (not `ReconnectNotice`, which is `ready`-only).
- [ ] **AC3 (c):** `auto-sync-trigger.test.ts` proves: `startAgentSession` rejecting with
      `RuntimeAuthError`/`ByokLeaseError("escape")` → bounded retry → eventual success with **exactly ONE
      `conversations` INSERT** across attempts; exhausted retries → `reportSilentFallback` (op
      `auto-sync-trigger`), NO rethrow into the `.then()`, `repo_status` stays `ready`. (Proxy note: the
      sync-doc drift-guard below is a DOC-CONTRACT proxy — it proves `sync.md` prose, not the LLM agent's
      runtime push behavior.) Sync-doc drift-guard proves the `--headless` branch commits-local /
      worktree→PR / handles GH013, never instructs a raw `git push <protected-default>`.
- [ ] **AC4:** `evaluateRepoReadiness` remains a pure function (DB-free; the AC7-style unit branches still
      pass) — the self-heal lives in the new `repo-readiness-self-heal.ts` orchestrator with injected
      seams, NOT in the pure `repo-readiness.ts` module (no I/O imports added to `repo-readiness.ts`).
- [ ] **AC5:** The dispatch self-heal calls `ensureWorkspaceRepoCloned` (idempotent), NOT
      `provisionWorkspaceWithRepo` (destructive) — verified by grep: no new `provisionWorkspaceWithRepo`
      caller in `cc-dispatcher.ts`/`repo-readiness-self-heal.ts`.
- [ ] **AC5b (write-boundary):** cc-dispatcher writes `repo_status` ONLY via the tenant `.rpc()` to
      `claim_repo_clone_lock`/`set_repo_status` — NO service-role client introduced, no
      `mirrorRepoColsToSoloWorkspace` call on the dispatch path. `cc-dispatcher.ts` stays OFF the
      service-role allowlist (grep the allowlist file — no new entry).
- [ ] **AC6:** The self-heal reuses `effectiveInstallationId` (the promoted, entitlement-gated install),
      not the raw stored `installationId` — verified at the call site.
- [ ] **AC7:** No edits to `apps/web-platform/server/agent-runner.ts` `startAgentSession` readiness gating
      (sibling-worktree boundary intact — that path stays un-gated by THIS PR).
- [ ] **AC8:** `./node_modules/.bin/tsc --noEmit` clean; full adjacent suite (repo-readiness,
      ensure-workspace-repo, cc-reprovision, use-reconnect, byok-lease, sentry-chat-alert-op-contract)
      green — including `sentry-chat-alert-op-contract.test.ts` (the new self-heal op must NOT be appended
      to the chat-save rule, so that drift-guard stays green).
- [ ] **AC9:** No version-file bump (`plugin.json`/`marketplace.json` untouched).
- [ ] **AC10 (presence proxy):** Every Sentry op slug kept in the Observability block has a real
      `reportSilentFallback`/`warnSilentFallback`/client-`captureException` emit site in the diff (grep
      each `op:"…"` literal in the new/edited files). NOTE this is a presence check, not a
      path-reachability proof. If `auto-sync-degraded`'s read-back marker is descoped, the slug is REMOVED
      from the block (no emit-less slug ships).

### Post-merge (operator)

- [ ] **AC11:** Add a **NEW** `sentry_issue_alert` resource for `feature=cc-dispatcher op IS_IN
      {repo-readiness-self-heal}` to `apps/web-platform/infra/sentry/issue-alerts.tf` (unused frequency;
      mirror the byok rule shape) — do NOT append to the chat-save rule's `op IS_IN` (breaks
      `sentry-chat-alert-op-contract.test.ts`). Apply via the existing `apply-sentry-infra.yml` `-target=`
      flow. **Automation:** Terraform apply via the existing Sentry-infra workflow (no SSH, no dashboard).
      Emission is verified read-only via Sentry issue search (discoverability test) — no prod write needed
      to confirm. If the alert resource is deferred, file a follow-up issue (the emit sites still ship; the
      events are queryable without the rule).

## Domain Review

**Domains relevant:** Product (UX-adjacent: the Reconnect button behavior + Concierge error copy), Engineering (carried in plan body).

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none (pipeline/headless context — plan-file-path argument provided)
**Skipped specialists:** none — no new user-facing page/flow/component is created. The change modifies the
*behavior* behind existing affordances (`project-setup-card.tsx`'s error-state "Retry Setup" and the
`Reconnect` hook) and adds a status poll; no new `.tsx` page/component file is created (`use-reconnect.ts`
is a hook; `project-setup-card.tsx` and `reconnect-notice.tsx` are existing components getting behavior +
a poll threaded). Mechanical UI-surface override did NOT fire (no new `components/**/*.tsx`,
`app/**/page.tsx`, or `app/**/layout.tsx` in `## Files to Create`).
**Pencil available:** N/A (no new UI surface)

#### Findings

The user-facing surface is copy + button behavior. The Reconnect button's existing error message
("Reconnect in Settings → Repository") becomes *truthful* (it now re-clones). No wireframe needed — the
visual surface is unchanged; only the action wired behind it changes. CPO sign-off is required at plan
time per the `single-user incident` threshold (frontmatter `requires_cpo_signoff: true`); the product
concern is narrow (make an existing affordance do what it claims).

## GDPR / Compliance Gate

The new migration touches a Supabase DDL surface (Phase 2.7 trigger). Advisory assessment: the RPCs read/
write `workspaces.repo_status` + `users.repo_error` (workspace/repo metadata + a sanitized git error
reason) — **no Art. 9 special-category data, no new personal-data processing activity, no new lawful-basis
or Art. 30 trigger.** `repo_error` is already sanitized at the write boundary (`sanitizeGitStderr`). The
RPCs add membership-gated access (tighter than the status quo), not broader exposure. No Critical finding;
no `compliance/critical` issue needed. (Run `/soleur:gdpr-gate` at /work time against the migration diff to
confirm before merge.)

## Infrastructure (IaC)

The new Sentry alert resource (`sentry_issue_alert` for the self-heal op) lands in
`apps/web-platform/infra/sentry/issue-alerts.tf` and applies via the existing `apply-sentry-infra.yml`
`-target=` workflow (no SSH, no dashboard click — `hr-all-infrastructure-provisioning-servers`). The
Supabase migration applies via the existing `web-platform-release.yml#migrate` job on merge to main (NOT a
manual `supabase db push`). No new server, secret, vendor, or persistent process is introduced — the rest
of the change is pure code against already-provisioned surfaces.

## Risks & Mitigations

- **Risk: dispatch self-heal clobbers un-pushed agent commits.** Mitigated by using `ensureWorkspaceRepoCloned`
  (`.git`-absent gated — never touches an existing `.git`), NOT `provisionWorkspaceWithRepo`. Precedent:
  learnings `2026-06-03-self-heal-on-brand-path-only-acts-on-safe-symptom` +
  `2026-06-03-self-heal-reset-must-gate-on-actual-repo-state-not-assumed-mirror`.
- **Risk: cc-dispatcher cannot write `repo_status` with its tenant client (RLS-filtered to zero rows).**
  Mitigated by the SECURITY DEFINER RPC (`claim_repo_clone_lock`/`set_repo_status`) callable via tenant
  `.rpc()` — cc-dispatcher stays OFF the service-role allowlist (architecture P0-1). **Precedent-diff:**
  the RPC mirrors migration 079's definer + 4-role REVOKE/GRANT shape and 083's own-key short-circuit
  pattern; `search_path` pinned to `pg_catalog, pg_temp` per `cq-pg-security-definer-search-path-pin-pg-temp`.
  Grep `git grep -n "SECURITY DEFINER" apps/web-platform/supabase/migrations/079*.sql 083*.sql` and diff
  the GRANT block at /work time.
- **Risk: two concurrent cold dispatches both clone.** Mitigated by the RPC lock
  (`error`-or-stale-`cloning`→`cloning`) — one wins, the other gets `false` and honest-waits. The graft
  itself is also race-safe (`randomUUID` temp + `.git`-sentinel re-check).
- **Risk: stale-`cloning` terminal trap.** A `.neq("cloning")` predicate can never re-acquire a `cloning`
  row, so a winner that dies after `error→cloning` but before `failed→error` would strand the row forever
  (spec-flow P0-1). Mitigated: the RPC's escape predicate is `error OR (cloning AND repo_last_synced_at <
  now() - 5min)`, NOT `.neq("cloning")` — a dead-winner `cloning` row is recoverable past the window; a
  FRESH `cloning` (live setup clone) is never disturbed. Also reconnect (FIX 1b) can reset `cloning`→`error`
  via setup's own lock. (This is the named defense-relaxation: the 5-min staleness ceiling replaces the
  no-timer first draft, per `2026-05-05-defense-relaxation-must-name-new-ceiling`.)
- **Risk: moving the gate evaluation later regresses the `ready`/`not_connected` zero-await fast path.**
  Mitigated by a two-stage shape: the zero-await `evaluateRepoReadiness` check stays at `:1563` and
  short-circuits ready/not_connected; only `error`/`cloning` falls through to the post-`effectiveInstallationId`
  self-heal (architecture P1-1).
- **Risk: auto-sync retry re-INSERTs the sync conversation.** Mitigated by creating the conversation row
  ONCE outside the retry boundary; the retry wraps only `startAgentSession` (architecture P0-3).
- **Risk: lease-retry backoff delays the auto-sync visibly.** Mitigated by bounding retries (3, ~1s/3s/9s)
  and by the fact that auto-sync is a *convenience* — degradation never blocks the user; `repo_status`
  stays `ready` and the user can sync manually or it self-heals on next cold dispatch.
- **Risk: sibling-worktree collision.** Mitigated by AC7 (no `agent-runner.ts` gating edits) — the legacy
  leader path stays the sibling's scope.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or
  omits the threshold will fail `deepen-plan` Phase 4.6. (This plan's section is filled with the
  single-user-incident threshold.)
- **The stale-`cloning` escape needs `repo_last_synced_at`, not `.neq`.** `repo_status="cloning"` carries
  no dedicated started-at, but `repo_last_synced_at` IS stamped on the `cloning` flip (the RPC sets it),
  so the RPC's staleness predicate is `repo_last_synced_at < now() - interval '5 minutes'`. A `.neq
  ("cloning")` predicate is a terminal trap (can never re-acquire `cloning`) — do NOT use it; the RPC's
  `error OR stale-cloning` predicate is the correct lock.
- **`repo_status` is writable from cc-dispatcher ONLY via the definer RPC.** The tenant client cannot
  UPDATE `workspaces` (no RLS UPDATE policy); a direct write silently no-ops. Never reach for
  `mirrorRepoColsToSoloWorkspace` (service-role-only) on the dispatch path, and never add cc-dispatcher to
  the service-role allowlist.
- **`kb-reconnect-banner.tsx` does not exist.** Do not list it as an edit target. The reconnect affordance
  for a broken checkout renders in `project-setup-card.tsx`'s `error` branch; `ReconnectNotice` renders
  only for `ready && needsReconnect`.
- **Only `connect-repo/page.tsx` polls `/api/repo/status` today.** The Settings card's `cloning` spinner
  is a static server snapshot — FIX 1b MUST add its own bounded poll or the recovery is invisible.
- **`startAgentSession` is `Promise<void>` (fire-and-forget).** Its result is not inspectable by return
  value — degraded outcomes (GH013) must be read back from `conversations.status`, or the
  `auto-sync-degraded` op has no emit site and must be dropped.
- **`sync.md` is a `commands/` file, not a `skills/` description.** No 1800-word skill-description budget
  applies; do NOT run the `components.test.ts` budget gate against it.
- **Test runner is vitest, files under `test/**`.** `bun test` is blocked by bunfig
  `pathIgnorePatterns=["**"]` (#1469); typecheck is in-package `./node_modules/.bin/tsc --noEmit` (no
  `npm run -w`). Component tests live under `test/`, NOT co-located (`vitest.config.ts` `include` globs).
- **`provisionWorkspaceWithRepo` is destructive.** Only the operator-initiated `/api/repo/setup` reconnect
  path may call it. The dispatch self-heal must use `ensureWorkspaceRepoCloned`.

## Test Scenarios

1. `repo_status=error`, installation present, `repoUrl` set, `.git` absent, self-heal succeeds → dispatch
   proceeds (no `RepoNotReadyError`).
2. Same but self-heal `failed` → honest `RepoNotReadyError` block (after a real attempt).
3. `repo_status=error`, installation **null** → honest block, no clone attempt.
4. Two concurrent cold dispatches, both see `error` → exactly one clones (lock), the other honest-waits.
5. Reconnect: `detect-installation installed:true` + `repo_status=cloning`/`error` + `repoUrl` →
   `POST /api/repo/setup` issued.
6. Reconnect: `repo_status=ready` → no setup POST (just `onReconnected`).
7. Auto-sync: `startAgentSession` rejects `ByokLeaseError("escape")` twice then resolves → retried,
   succeeds, no rethrow.
8. Auto-sync: rejects all retries → `reportSilentFallback`, `repo_status` stays `ready`, no unhandled
   rejection.
9. Headless sync on a protected default branch → commits local / opens PR; GH013 → clear degraded status,
   Sentry `op:auto-sync-degraded`.

## References

- `knowledge-base/project/learnings/best-practices/2026-06-14-short-circuit-guard-must-sit-after-the-recovery-it-gates.md` — the gate-ordering principle FIX 1 applies.
- `knowledge-base/project/learnings/2026-06-03-self-heal-on-brand-path-only-acts-on-safe-symptom.md` — `.git`-absent-only self-heal scope.
- `knowledge-base/project/learnings/2026-06-03-self-heal-reset-must-gate-on-actual-repo-state-not-assumed-mirror.md` — never wipe a workspace that may hold un-pushed commits.
- `knowledge-base/project/learnings/best-practices/2026-06-15-parallel-recovery-path-must-reuse-same-resource-selection.md` — reuse `effectiveInstallationId`.
- `knowledge-base/project/learnings/bug-fixes/2026-06-15-clone-into-temp-subdir-must-ensure-parent-exists.md` — `mkdir` parent before temp-dir clone.
- `knowledge-base/project/learnings/2026-03-20-fire-and-forget-promise-catch-handler.md` — never let the auto-sync rejection escape unhandled.
- `knowledge-base/project/learnings/best-practices/2026-05-20-hr-observability-as-plan-quality-gate-why-and-how.md` — the `## Observability` discoverability-without-SSH contract.
- `knowledge-base/engineering/architecture/decisions/ADR-044-workspace-repo-ownership.md` — `repo_status` source-of-truth (`workspaces`) + mirror.
- Code: `apps/web-platform/server/cc-dispatcher.ts:1465-1730,3346,3422`; `server/repo-readiness.ts`;
  `server/ensure-workspace-repo.ts`; `server/workspace.ts:166-257`; `app/api/repo/setup/route.ts:121-322`;
  `app/api/repo/detect-installation/route.ts`; `components/repo/use-reconnect.ts`;
  `server/byok-resolver.ts:119`; `server/byok-lease.ts:370-377`; `server/push-branch.ts:57`;
  `apps/web-platform/infra/sentry/issue-alerts.tf`.
