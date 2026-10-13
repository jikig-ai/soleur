---
title: In-flight work durability — ref-based worktree checkpoint + gated restore (#5275)
date: 2026-06-15
type: feat
issue: 5275
refs: 5240
branch: feat-one-shot-5240-inflight-work-durability
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
brainstorm: knowledge-base/project/brainstorms/2026-06-14-durable-session-resume-brainstorm.md
prior_plan: knowledge-base/project/plans/2026-06-14-feat-durable-session-resume-v1-plan.md
---

# Plan: In-flight work durability — ref-based worktree checkpoint + gated restore (#5275)

## Enhancement Summary
**Deepened on:** 2026-06-15. **Plan-review applied:** DHH + Kieran + Simplicity (3 P0 code-verified
correctness fixes + consensus scope cut). **Deepen-plan gates:** 4.6 User-Brand Impact ✓,
4.7 Observability ✓ (5 fields, no-ssh), 4.8 PAT-shaped ✓ (none), 4.9 UI-wireframe ✓ (no UI surface).
Verify-the-negative + precedent-diff passes run.

### Key improvements over the first draft
1. **`workspacePath` re-resolution** at the abort catch (NOT in closure — code-verified P0).
2. **Temp-index for BOTH checkpoint AND restore** (real index never mutated — `git read-tree`
   into the real index would stage the snapshot; P0).
3. **Path-allowlist, never `git add -A`** (`hr-never-git-add-a-in-user-repo-agents`) — AND the
   allowlist is deliberately **wider than `knowledge-base/**`** so the agent's code edits (the
   actual in-flight work) are captured, not dropped.
4. **Clean-tree is the primary no-clobber guarantor**; the slot probe is a team-workspace-only
   belt with a `last_heartbeat_at >= now()-120s` liveness filter (else it refuses in the solo case).
5. **Orphan-TTL prune DEFERRED** (refs self-clean; build a ref-count gauge first) — only the
   account-deletion erasure cascade is in v1.
6. **Greenfield git-plumbing wrapper** `runPlumbingGit` modeled on `_cron-safe-commit.ts runGit`
   (the verbs are NOT in any existing allowlist).

### New considerations discovered
- Stale concurrency slots are swept by pg_cron every minute AND lazily in the acquire RPC — but
  NOT on the resume read path, so the 120s liveness filter on the probe is load-bearing.
- The `knowledge-base/**`-scoped `getAllowlistedChanges` is the wrong predicate for *work*
  durability; reuse its porcelain-parse shape, widen its path predicate.

## Overview

Build the **PRESERVE** half of #5240 design item #4. The "accurately report the fate"
half already shipped (FR1 verified workspace-rebind + honest-status; the stuck-watchdog
liveness reset; the honest `worktree_enter_failed` runtime guardrail; the
stream-since-disconnect replay + reconnect state-machine hardening). What is **unbuilt**:
when a client disconnects mid-turn, the 30s grace timer
(`DISCONNECT_GRACE_MS`, `ws-handler.ts:203`) fires `abortSession`
(`ws-handler.ts:2843-2856`); the `disconnected` abort branch in `agent-runner.ts`
(~2261-2287) persists the partial assistant **text** but does **not** preserve the
workspace's **uncommitted git changes**. They sit dirty + unreferenced on the persistent
volume and a later resume can clobber them.

This plan: at grace-expiry abort, durably **checkpoint** the in-flight working-tree state
to a dedicated `refs/checkpoints/<conversationId>` git ref (a snapshot commit object built
with `git commit-tree` over a temp index — HEAD / index / working tree untouched), and on
resume **restore** it into the same physical workspace **only when it is provably safe**;
otherwise honestly report the saved checkpoint rather than overwriting newer work.

**Scope guard (honored):** in-flight preservation/restoration only. No isolation-boundary
change. No `git stash` (hook-enforced `hr-never-git-stash-in-worktrees`; verified that even
`git stash create` is blocked by `guardrails.sh:189`) — the checkpoint is ref/commit-based.
TDD-first (Phase 1 RED).

## The load-bearing constraint (why this plan is gated, not naive)

Verified in code, and it governs the entire design:

1. **The interactive agent workspace is a SHARED CLONE keyed by `workspace_id`** at
   `/workspaces/<workspace_id>` (`workspace-resolver.ts:718` `workspacePathForWorkspaceId`).
   It is **NOT** a per-conversation `git worktree` and **NOT** a per-conversation branch —
   all `git worktree add` / `checkout -B` calls in the repo are in **cron** functions
   (`_cron-safe-commit.ts`, `cron-compound-promote.ts`), never the interactive path. Every
   conversation on a connected repo shares **one** working tree on the repo's default branch.
2. **Concurrency cap is PER-USER and can be > 1** (`lib/plan-limits.ts:11-17` —
   free=1, solo=2, startup=5, scale/enterprise=50). New conversations take their
   `workspace_id` from `resolveUserWorkspaceBinding(userId)` (`ws-handler.ts:856-863`). So a
   solo user with 2 active conversations on their connected repo has **two conversations
   sharing one working tree** — mutating it concurrently.

**Consequence:** a "snapshot all uncommitted changes" checkpoint cannot be cleanly attributed
to one conversation on a shared tree — it captures any concurrent **sibling** conversation's
dirt, and a blind restore would clobber the sibling's newer work. The change-class is
therefore: **always checkpoint (non-destructive ref, path-allowlist-scoped), auto-restore ONLY
when the workspace is provably single-tenant-at-rest; otherwise refuse-and-report honestly.**
This degrades safely (never corrupts) and makes the dominant case (solo user, one conversation)
fully durable.

**The clean-tree check is the PRIMARY no-clobber guarantor** (plan-review consensus): if the
working tree is empty per `git status --porcelain`, restoring the checkpoint into it cannot
overwrite anyone's newer work — there is none. The **sole-active-slot probe is a secondary belt**
that earns its keep ONLY for **team workspaces** (`workspace_id !== userId`) — a cross-user
shared tree where conversation A could otherwise restore over conversation B's
committed-but-clean state. For the **solo case** (`workspace_id === userId`, the dominant path),
clean-tree alone is provably sufficient, so the plan **skips the slot DB read entirely** there
(no round-trip on 99% of resumes). An implementer must NOT optimize away the dirty-tree check
even when the slot probe reports sole-tenant — the clean-tree gate is the real backstop (a sibling
mid-write dirties the tree, which the probe's slot-table snapshot can miss).

## Research Reconciliation — Spec vs. Codebase

| Issue/brainstorm claim | Codebase reality (verified) | Plan response |
|---|---|---|
| "Checkpointing mid-turn worktrees is expensive; given the persistent volume, uncommitted edits often **survive** anyway" (#5275 body) | True the bytes survive on disk, but they are **unreferenced and unrestorable** — the resume path never re-attaches them, and a fresh turn's writes / a reclone discard them. Survival ≠ recoverability. | Checkpoint gives the surviving bytes a **named ref** so resume can re-attach them. Cheap: `commit-tree` over a temp index is one tree-hash + one commit object. |
| Per-conversation worktree (implied by "the interrupted turn's worktree") | No per-conversation worktree exists; one shared clone per `workspace_id` (`workspace-resolver.ts:718`) | Snapshot the shared tree to a per-conversation **ref**; gate restore on sole-slot + clean-tree (see constraint above) |
| `cron-workspace-gc` can prune stale checkpoint refs (CTO/CLO Q) | `cron-workspace-gc.ts:83-88` sweeps only `soleur-*`-prefixed cron-clone **directories**, maxdepth-1, and is hard-guarded to **never** touch UUID workspace dirs. It does **not** enumerate git refs. | Ref cleanup is **greenfield** — add a ref-aware prune step (Phase 4), not a config tweak |
| Add a nullable `conversations` column to hold the checkpoint ref | The ref name is deterministically derivable from `conversationId`; existence is `git rev-parse --verify --quiet refs/checkpoints/<id>` | **No migration.** Derive the ref; no DB column → no GDPR-gate surface, no schema-drift risk, no extra write on the degraded disconnect path |
| FR1 rebind not yet present | FR1 verified-rebind **merged** (16164d678): `ws-handler.ts:1885-1938` re-aligns `current_workspace_id` to `conversations.workspace_id` on resume | Restoration hooks **after** the rebind succeeds (the workspace path is correct only then) |

## Premise Validation

Checked: **#5240** OPEN (epic; `Ref` not `Closes`, correct). **#5275** OPEN — its body
(`feat: in-flight (mid-turn) work durability via worktree checkpointing`) is the exact
deferral target from the 2026-06-14 brainstorm; this plan **builds** it rather than filing a
duplicate. **#5273** (stream-since-disconnect buffer) CLOSED — merged, as the prompt states.
**#5274** (physical durability) OPEN — out of scope here. The v1 plan's
`tasks.md §"Deferred from v1"` records AC9 (message-during-gap) → #5275; this is the AC9 build.
All cited code re-verified: `DISCONNECT_GRACE_MS` at `ws-handler.ts:203` (prompt said 202 —
drift noted), grace-abort at `2843-2856` (prompt said 2766-2772 — drift noted), disconnect
abort branch at `agent-runner.ts:~2261-2287`. No stale premises.

## Implementation Phases

### Phase 0 — Preconditions (verify before editing; no code)
- **Re-resolve `workspacePath` at the abort catch — it is NOT in closure** (plan-review P0-1,
  code-verified): `agent-runner.ts:997` `const workspacePath` is declared *inside* the
  `runWithByokLease` callback (opened ~950, closed `}); // end runWithByokLease` at **2261**);
  the abort catch is at **2263**, OUTSIDE that callback. So the checkpoint call must
  **re-resolve** the path: `const workspacePath = await resolveActiveWorkspacePath(userId, sessionTenant)`
  (`userId`/`sessionTenant` ARE outer-scope) or `workspacePathForWorkspaceId(...)`. This
  re-resolution can throw → wrap so a failure mirrors to Sentry and does NOT break the
  partial-text persist (AC6). Confirm `classifyAbortReason` yields `kind === "disconnected"`
  for the grace path (`abort-classifier.ts`; grace abort calls `abortSession(uid, convId)` with
  no reason → defaults to `"disconnected"`, `agent-session-registry.ts:196`).
- Confirm the restore hook site: `ws-handler.ts:1938` (immediately after the
  `set_current_workspace_id` RPC succeeds in the `resume_session` case, before
  `session_started` is emitted).
- Confirm git plumbing is runnable in the workspace clone and **not** stash-blocked:
  `git write-tree`, `git commit-tree`, `git update-ref`, `git rev-parse --verify`,
  `git read-tree`/`git checkout-index`, `git status --porcelain` — all confirmed available;
  none match the `git\s+stash` guard (`guardrails.sh:189`).
- Confirm the serialization primitive: `withWorkspacePermissionLock(workspacePath, fn)`
  (`workspace-permission-lock.ts:53`, already imported in `agent-runner.ts:86`) — a
  per-workspace-path in-memory promise lock; reuse it to make the snapshot read internally
  consistent against a concurrent sibling write (CTO B-mitigation #2).
- Confirm the sole-active-slot probe (team-workspace path ONLY — see constraint section): the
  slot table `user_concurrency_slots` carries `workspace_id` (column added NOT NULL in mig
  **059**; populated by the `acquire_conversation_slot` RPC writer in mig **093**). There is **no
  existing read-only RPC** for "other active slot sharing this workspace_id." The probe MUST
  filter on liveness or it over-counts stale slots. Stale slots are swept BOTH lazily inside
  `acquire_conversation_slot` AND by a `pg_cron` job every minute (`* * * * *`, mig 029:219-226) —
  but neither runs on the resume read path, so within the ~120s window the user's own crashed slot
  can still be present → a naive `count(*)` would refuse-and-report in the solo reconnect case the
  plan markets as durable. Required query shape (via the existing tenant client; RLS
  `is_workspace_member(workspace_id, auth.uid())` on the SELECT policy):
  `select count(*) from user_concurrency_slots where workspace_id = $1 and conversation_id <> $2
  and last_heartbeat_at >= now() - interval '120 seconds'`. Pin and confirm it passes RLS in
  Phase 0. (plan-review P1-1, code-verified.)
- Confirm the deletion cascade seam for ref cleanup — **account deletion ONLY** (plan-review
  P1-2, code-verified): there is **no** conversation hard-delete (only soft-archive
  `archived_at`; `app/api/conversations/route.ts` has no DELETE). The real seam is
  `server/account-delete.ts` (`abortAllUserSessions` ~171, then `deleteWorkspace` removes the
  whole clone). So the ref-delete rides account deletion; per-conversation cleanup is
  consume-on-restore (Phase 3). Pin the exact account-delete call site.
- Greenfield confirmation (write-boundary sweep, `hr-write-boundary-sentinel-sweep-all-write-sites`):
  `git grep -n "refs/checkpoints"` → expect **0 hits** (new namespace); `git grep -n "workspacePathForWorkspaceId"`
  to enumerate every shared-tree reader so checkpoint/restore wire at the right boundary only.
- Baseline: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.

### Phase 1 — RED (failing test first, TDD)
Author the failing test that encodes the core scenario (deterministic — assert on git ref
state + restored file bytes, never on LLM prose):
- **RED-A (checkpoint survives grace-abort):** seed a temp git repo as the workspace
  (synthesized fixture, `cq-test-fixtures-synthesized-only`); write an uncommitted **allowlisted**
  file (under `knowledge-base/**`); drive the disconnect abort branch (or its extracted helper —
  see Phase 2) with `kind = "disconnected"`; assert `refs/checkpoints/<conversationId>` now exists,
  its tree contains the allowlisted file's content, and the **real index + HEAD are unchanged**
  (`git diff --cached` empty). (Today: no ref → RED.)
- **RED-B (restore on resume, safe case):** with a checkpoint ref present, a **clean** working
  tree, and **no sibling active slot**, drive the resume restore helper; assert the uncommitted
  file is materialized back into the working tree. (Today: no restore → RED.)
- **RED-C (refuse-and-report, unsafe case):** with a checkpoint ref present but the working tree
  **dirty** (or a sibling slot active), assert restore does **NOT** overwrite — the dirty/newer
  content is preserved and an honest signal (op-tagged Sentry mirror + the deterministic
  user-message value) is emitted instead.
- Test paths MUST match `vitest.config.ts include:` — `test/**/*.test.ts`
  (node project) for the server-side checkpoint/restore helpers. Runner: `vitest`
  (`package.json scripts.test`). NOT `bun test`, NOT a co-located `server/*.test.ts`.

### Phase 2 — GREEN: extract `checkpointInflightWork(workspacePath, conversationId)` (server)
- **Git exec wrapper (deepen-plan precedent-diff):** the plumbing verbs
  (`write-tree`/`commit-tree`/`update-ref`/`read-tree`/`checkout-index`/`for-each-ref`) are
  **greenfield in server code** (zero hits in `apps/web-platform/server/`). They are NOT in
  `session-sync.ts ALLOWED_GIT_SUBCOMMANDS` (`status|add|commit|remote|rev-list`) and
  `runConnectedRepoGit` is private to that module — do NOT reuse it. Define a private
  `runPlumbingGit` in `inflight-checkpoint.ts` modeled on `runGit` in
  `_cron-safe-commit.ts:190-221` (async `promisify(execFile)`, `{ ok, stdout, stderr }` no-throw
  return, `GIT_CONFIG_GLOBAL=/dev/null` / `GIT_CONFIG_NOSYSTEM=1` isolation), passing
  `GIT_INDEX_FILE` via `extraEnv` on the `read-tree`/`add`/`write-tree`/`checkout-index` calls.
- New helper `server/inflight-checkpoint.ts` with two unit-testable entry points, both
  wrapped in `withWorkspacePermissionLock(workspacePath, …)`:
  - `checkpointInflightWork(workspacePath, conversationId)` → returns `void` (the abort caller
    is fire-and-forget on a degraded path and branches on nothing — no result type, plan-review
    P1-2/DHH; log + Sentry-on-failure only):
    1. `git status --porcelain` (lock-held) — if no allowlisted change, **no-op** (nothing to
       checkpoint; log + return).
    2. Build a snapshot over a **temp index living OUTSIDE the worktree** (`os.tmpdir()`, removed
       in `finally`; plan-review P1-3 — a temp index inside the clone shows as `?? .tmpidx` and
       pollutes `status`/sibling reads). Do NOT touch the real index:
       `GIT_INDEX_FILE=<tmp> git read-tree HEAD` →
       `GIT_INDEX_FILE=<tmp> git add -- <allowlisted paths>` **(NOT `git add -A`)** →
       `GIT_INDEX_FILE=<tmp> git write-tree` →
       `git commit-tree <tree> -p HEAD -m "checkpoint: conversation <id> (in-flight, <iso>)"` →
       `git update-ref refs/checkpoints/<conversationId> <commit>`.
    3. **Path scoping is MANDATORY, not optional** (plan-review P0-3, hard rule
       `hr-never-git-add-a-in-user-repo-agents`): `inflight-checkpoint.ts` is a user-repo writer
       — `git add -A`/`.` is forbidden; enumerate explicit paths from `git status --porcelain=v1 -z`
       and `git add -- <paths>`. **Design decision (deepen-plan): the checkpoint allowlist must be
       WIDER than `session-sync.ts getAllowlistedChanges` (which is scoped to `knowledge-base/**`
       only).** In-flight *work* durability means the agent's **code** edits, not just KB files —
       restricting to `knowledge-base/**` would silently drop exactly the work this feature exists
       to preserve. So: reuse the **status-parsing shape** of `getAllowlistedChanges`
       (`session-sync.ts:103`, returns repo-root-relative paths from porcelain `-z`, yields rename
       *destination*, `[]` on git error) but with a **broader path predicate** = "all working-tree
       changes EXCEPT the deny-set" (`.git/`, the temp index, build artifacts) — still an explicit
       enumerated list, never `-A`. The `hr-never-git-add-a` rule forbids the wildcard *verb*, not
       a wide explicit path list. Enumerating the full porcelain set also captures only THIS
       workspace's tree (no `-A` glob), and the sibling-capture concern is bounded by the
       restore-side gate (a checkpoint that captured sibling dirt is never blindly restored).
    4. Parent at current HEAD so the checkpoint is restorable/diffable as `git diff HEAD <ref>`.
       (Connected-repo clones always have a HEAD commit — verified at clone time; if absent the
       commit-tree fails loudly into the Sentry mirror, not silently.)
    5. HEAD, the real index, and the working tree are **never** mutated. No `stash`. No WIP
       commit on the branch (which would move HEAD for every sibling conversation — rejected,
       CTO B).
  - Failure here is a **silent-fallback-to-Sentry** site (`cq-silent-fallback-must-mirror-to-sentry`):
    `reportSilentFallback(err, { feature: "inflight-checkpoint", op: "checkpoint-on-abort", extra: { userId, conversationId } })`.
    A checkpoint failure must NOT break the abort path (the partial-text persist still runs).
- **Wire into the disconnect abort branch** (`agent-runner.ts` `!isSuperseded`, after the
  partial-text persist): **re-resolve `workspacePath`** (Phase 0 — NOT in closure at the catch)
  then call `checkpointInflightWork(workspacePath, conversationId)`. Guard so only the
  `disconnected` grace abort checkpoints (the irrecoverable-window case);
  `user_requested_stop` keeps the conversation continuable (no checkpoint); `superseded`,
  `account_deleted`, `server_shutdown`, `workspace_membership_revoked` own their terminal state.
  Add an `isDisconnected` discriminant to `classifyAbortReason` (it returns only
  `isUserRequested`/`isSuperseded` today). `cq-union-widening` discipline — enumerate **all six**
  `AbortKind` members (`disconnected | user_requested_stop | superseded | account_deleted |
  server_shutdown | workspace_membership_revoked`, `abort-classifier.ts:24-31`) and checkpoint
  **only** on `disconnected`.

### Phase 3 — GREEN: gated restore on resume (server)
- New helper `restoreInflightCheckpoint(workspacePath, conversationId, { siblingSlotActive })`,
  wrapped in `withWorkspacePermissionLock`:
  1. `git rev-parse --verify --quiet refs/checkpoints/<conversationId>` — absent → `{ restored: false, reason: "no-checkpoint" }` (normal; no message).
  2. **Safety precondition — clean-tree is PRIMARY:**
     - working tree **clean** (`git status --porcelain` empty) — necessary AND sufficient for the
       solo case; this is the real no-clobber guarantor. AND
     - `siblingSlotActive === false` — secondary belt, **evaluated only for team workspaces**
       (`workspace_id !== userId`); for solo workspaces the caller passes `false` without a DB
       read (clean-tree alone suffices — plan-review P1-1/DHH).
  3. **Safe → restore (real index UNTOUCHED — plan-review P0-2):** materialize via a **temp
     index outside the worktree**, NOT `read-tree` into the real index (verified: `git read-tree
     <ref>` mutates the real index, leaving the checkpoint staged — breaks the plan's "index
     untouched" invariant). Use:
     `GIT_INDEX_FILE=<tmp> git read-tree refs/checkpoints/<conversationId>` →
     `GIT_INDEX_FILE=<tmp> git checkout-index -a -f` → remove `<tmp>` in `finally`. This writes the
     snapshot into the working tree without moving HEAD or staging anything (the single chosen
     materialization spelling — `git checkout <ref> -- .` alternative dropped, plan-review/Simplicity).
     Then **consume the ref**: `git update-ref -d refs/checkpoints/<conversationId>` (one-shot —
     keeping it would re-restore next resume). Return `{ restored: true }`.
  4. **Unsafe → refuse-and-report:** do NOT overwrite. Return `{ restored: false, reason: "dirty" | "sibling-active" }`
     (the `reason` feeds the Sentry `op` extra for triage; the **user message is ONE string**
     regardless of reason — do not fan out two UI states). Emit (a) `reportSilentFallback(... op:
     "restore-refused")` and (b) the single deterministic message ("Your earlier in-progress
     changes are saved but were not auto-applied because newer work is present — they remain at the
     saved checkpoint."). Reuse the **merged FR1 honest-status surface** (wireframe state 3,
     server-emitted string) — no new UI component, no `.pen`. The message must read sensibly to a
     **teammate**, not only a second tab (team-workspace path — CTO flag).
  5. **Three-way merge: explicitly DEFERRED (YAGNI).** Auto-merging a checkpoint against
     genuinely-newer state is where silent corruption lives; the clean-tree gate covers the
     dominant solo case. File a follow-up only if data shows demand.
- **Hook site:** `ws-handler.ts:1938`, after `set_current_workspace_id` succeeds and before
  `session_started`. Use `workspacePathForWorkspaceId(resumeWorkspaceId)` (the just-rebound id) —
  the resolver value is correct only after the rebind. For team workspaces compute
  `siblingSlotActive` via the Phase-0 liveness-filtered slot probe (excludes the resuming
  conversation's own slot); for solo pass `false`. Restore failure → honest client error via the
  existing terminal catch (`ws-handler.ts:1955-1958`), never a silent solo path.

### Phase 4 — GREEN: erasure cascade (CLO hygiene — required; minimal)
- **Consume-on-restore:** already done in Phase 3 step 3 (ref deleted after a successful
  restore) — this is the primary per-conversation cleanup, not Phase-4 work.
- **Cascade on account deletion:** at the `server/account-delete.ts` seam (Phase 0), delete the
  user's `refs/checkpoints/*` so Art. 17 erasure stays disk-complete (CLO hygiene 2). In practice
  `deleteWorkspace` already removes the whole clone (and thus all its refs) — confirm that, and
  add an explicit ref-delete only if `deleteWorkspace` does not run for every erasure path. A
  deleted ref leaves an unreachable object reclaimed by the clone's normal `git gc` — document.
- **Orphan-TTL prune: DEFERRED** (plan-review unanimous — DHH P0-1, Simplicity, Kieran).
  Rationale: refs self-clean (consume-on-restore for the dominant solo case; whole-clone removal
  on account deletion). A ref only orphans when a `disconnected`-abort conversation is never
  resumed AND never deleted — a slow, kilobyte-scale trickle. The bytes it names already survive
  un-reaped today (#5275 body) with zero cleanup, so a pointer to them adds no new disk-pressure
  class. Building a ref-aware cron sweep + `CHECKPOINT_TTL_DAYS` knob + a dedicated pruned-count
  monitor to defend kilobytes is premature. See Deferred section: build a single ref-count gauge
  FIRST and add the reaper only if it shows accumulation.

### Phase 5 — Verification
- `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
- `cd apps/web-platform && ./node_modules/.bin/vitest run test/inflight-checkpoint.test.ts`
  (and the resume-restore suite) — deterministic asserts on ref state + restored bytes.
- Observability discoverability test (below; NO ssh).
- No browser QA / no `.pen`: this surface emits only server-side messages reusing the merged
  FR1 honest-status states (no new user-facing component — see Domain Review Product/UX = NONE).

## Files to Edit
- `apps/web-platform/server/agent-runner.ts` — wire `checkpointInflightWork` into the
  `disconnected`-only arm of the abort branch (~2261-2287); `workspacePath` from `:997`.
- `apps/web-platform/server/ws-handler.ts` — call `restoreInflightCheckpoint` after the
  resume rebind succeeds (`:1938`) using `workspacePathForWorkspaceId(resumeWorkspaceId)`; add the
  team-workspace-only liveness-filtered slot probe; honest refuse-and-report message via the
  existing terminal catch / FR1 honest-status surface.
- `apps/web-platform/server/abort-classifier.ts` — add an `isDisconnected` discriminant to
  `classifyAbortReason` (enumerate all 6 `AbortKind`).
- `apps/web-platform/server/account-delete.ts` — cascade-delete the user's `refs/checkpoints/*`
  on account erasure (or confirm `deleteWorkspace` already removes the clone+refs). **No
  `cron-workspace-gc.ts` edit** (orphan-TTL prune deferred).

## Files to Create
- `apps/web-platform/server/inflight-checkpoint.ts` — `checkpointInflightWork` +
  `restoreInflightCheckpoint` (+ `CHECKPOINT_TTL_DAYS`, ref-name derivation
  `checkpointRefName(conversationId)`), the unit-testable seam.
- `apps/web-platform/test/inflight-checkpoint.test.ts` — RED-A/B/C (Phase 1), against a
  synthesized temp git repo fixture (`cq-test-fixtures-synthesized-only`).

## Open Code-Review Overlap
Open code-review issues on the edited files (carried from the v1 plan, re-confirmed): `ws-handler.ts`
— #3374 (slot_reclaimed frame), #2191 (clearSessionTimers refactor); `cc-dispatcher.ts` — not
edited here. **Acknowledge** (own cycles): none overlap the checkpoint/restore/ref-prune changes
(distinct concerns: frame typing + timer refactor vs. git-ref snapshot/restore). `agent-runner.ts`,
`inflight-checkpoint.ts` (new), `cron-workspace-gc.ts` — no open review issues touch the
checkpoint surface. `None` to fold in.

## User-Brand Impact
*(carried forward from #5240 brainstorm — `single-user incident`)*
- **If this lands broken, the user experiences:** their in-flight uncommitted work is lost on a
  mid-turn disconnect (status quo) OR — worse, if restore is ungated — a resumed conversation
  **silently overwrites** newer work a sibling tab/teammate made on the shared tree.
- **If this leaks / misfires, the user's workflow is exposed via:** cross-conversation data
  corruption on a shared working tree (a checkpoint capturing or clobbering a sibling
  conversation's edits). The gated-restore design (sole-slot + clean-tree, else refuse-and-report)
  is the control that prevents this.
- **Brand-survival threshold:** single-user incident. `requires_cpo_signoff: true`;
  `user-impact-reviewer` runs at PR review (enumerate: solo single-conversation restore; solo
  two-tab concurrent; team cross-user shared tree; dirty-tree-at-resume; checkpoint-failure-on-abort).

## Domain Review
**Domains relevant:** Engineering (CTO), Legal (CLO). Product/UX = NONE (no new user-facing
component; the honest message is a server-emitted string reusing the merged FR1 honest-status
surface — no `components/**`, no `app/**/page.tsx`, no `.pen` in the Files lists, so the
mechanical UI-surface override does not fire).

### Engineering (CTO)
**Status:** reviewed. Recommendation adopted in full:
- Snapshot scope = **always checkpoint (non-destructive ref) + clean-tree-and-sole-slot-gated
  restore, else refuse-and-report**. Whole-tree blind restore REJECTED (cross-conversation
  corruption under per-user concurrency >1 on a shared tree).
- Primitive = `commit-tree` + `refs/checkpoints/<conversationId>` (temp index; HEAD/index/worktree
  untouched), parented at HEAD. WIP-commit-on-branch REJECTED (moves HEAD for siblings). `stash`
  REJECTED (hook-blocked).
- Restore = clean-tree precondition + refuse-and-report; three-way merge DEFERRED.
- Ref name = **derived**, no migration (`rev-parse --verify` for existence).
- TTL = new ref-aware prune (existing `cron-workspace-gc` is dir-only, won't reach refs).
- Snapshot read serialized via `withWorkspacePermissionLock` (B-mitigation #2, torn-read).
- Flagged: **team workspaces** (`workspace_id !== userId`) are cross-user shared trees → the
  refuse-and-report path is the *normal* path there; the user message must read sensibly to a
  teammate, not only a second tab.
- **ADR suggested:** `/soleur:architecture create "Ref-based in-flight checkpoint on shared
  per-workspace clones"` — record why per-conversation scoping is incoherent on a shared tree,
  why restore is clean-tree-gated not three-way, why no migration. (Plan records the rationale
  inline; ADR is recommended-not-blocking.)

### Legal (CLO)
**Status:** reviewed. **NO legal blocker** (tenant-zero, same-EU Hetzner, signed DPA;
checkpoint = the user's own working-tree state on the same volume/repo/region — same
conversation/workspace-class data already retained; no new Art. 30 PA, no Privacy Policy bullet,
no DPD entry). Required hygiene (folded into Phase 3/4):
1. **Retention control** — checkpoint refs delete on restore-consumption (Phase 3) AND ride
   account-deletion / whole-clone removal (Phase 4; conversation retention = account-lifetime,
   `article-30-register.md:66`). Bounded orphan-TTL prune is **deferred** (plan-review consensus:
   refs self-clean; a TTL reaper defends kilobytes — build a ref-count gauge first). The
   originally-imagined `cron-workspace-gc` reuse was factually wrong (dir-only) — not adopted.
2. **Erasure completeness** — the ref artifact rides the account-deletion path (no
   conversation hard-delete exists; soft-archive only).
3. **Documentation** — one-line carry-forward note (and, if shipped, a one-line
   `compliance-posture.md` Active Items touch): checkpoint refs = conversation-class data, no
   new Art. 30 PA at tenant-zero, lifecycle documented, re-evaluation deferred to first
   arms-length GitHub App install.

### Product/UX Gate
**Tier:** none. No new user-facing surface; honest refuse-and-report reuses the merged FR1
honest-status string (wireframe state 3 already committed at
`knowledge-base/product/design/chat/reconnect-resume-states.pen`). No `.pen` produced here.

## GDPR / Compliance Gate
Trigger (b) fired (single-user-incident), but this plan touches **no** canonical regulated-data
surface: **no migration** (ref name derived, not stored), no `.sql`, no auth flow, no new
PII-handling API route, no new external recipient. CLO assessment above is the substantive
analysis. Disposition: **evaluated, no Critical findings, no `compliance-posture.md` write
required pre-merge** (the optional one-line Active-Items note is hygiene-3, not a gate output).

## Observability
```yaml
liveness_signal:
  what: inflight-checkpoint written on disconnect-abort (refs/checkpoints/<conversationId> created) and consumed on safe resume-restore
  cadence: per disconnected-abort / per resume_session (request-driven)
  alert_target: Sentry issue alert on op="checkpoint-on-abort" error events (checkpoint write failed)
  configured_in: apps/web-platform/infra/sentry/*.tf (issue alert rule on the new op slugs)
error_reporting:
  destination: Sentry via reportSilentFallback (server/observability.ts)
  fail_loud: true (checkpoint failure mirrors to Sentry but does NOT break the abort path; restore-refused mirrors + emits honest user message)
failure_modes:
  - mode: checkpoint write fails on abort (write-tree/commit-tree/update-ref error)
    detection: reportSilentFallback op="checkpoint-on-abort"
    alert_route: Sentry issue alert
  - mode: restore refused (dirty tree or sibling slot active)
    detection: reportSilentFallback op="restore-refused" (expected operational; debounced) + deterministic honest user message
    alert_route: Sentry warn + honest user message (reused FR1 honest-status surface)
  - mode: restore materialization fails (read-tree/checkout-index error after precondition passed)
    detection: reportSilentFallback op="restore-failed"
    alert_route: Sentry issue alert + honest retryable client error via terminal catch
logs:
  where: pino structured logs in inflight-checkpoint.ts / agent-runner.ts / ws-handler.ts (op-tagged)
  retention: existing platform log retention (unchanged)
discoverability_test:
  command: 'curl -s -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" "https://<org>.sentry.io/api/0/organizations/<slug>/issues/?query=op:checkpoint-on-abort" | jq ".[].title"  # NO ssh; org/slug + token per infra/sentry/*.tf + Doppler SENTRY_AUTH_TOKEN'
  expected_output: zero events in steady state; non-zero only on real checkpoint-write failures
```

## Acceptance Criteria

### Pre-merge (PR)
- **AC1 (RED→GREEN core):** a test that disconnects mid-turn with uncommitted working-tree
  changes and grace-aborts asserts `refs/checkpoints/<conversationId>` exists and its tree
  carries the uncommitted content. (Phase 1 RED-A / Phase 2)
- **AC2 (safe restore):** resuming a conversation with a checkpoint ref, a **clean** tree, and
  **no sibling active slot** materializes the prior uncommitted work into the same workspace,
  leaves the **real index unstaged** (`git diff --cached` empty — temp-index restore), and
  **consumes** the ref (`rev-parse --verify` now fails). (Phase 3)
- **AC3 (refuse-and-report, no clobber):** resuming with a checkpoint ref while the tree is
  **dirty** OR a sibling slot is active does **NOT** overwrite — the newer content is intact, the
  ref is retained, and `op="restore-refused"` + the deterministic honest message fire. (Phase 3)
- **AC4 (negative — no ref unless disconnected AND dirty):** one parametrized test asserts NO
  `refs/checkpoints/<id>` is written for (a) each non-`disconnected` kind
  (`user_requested_stop`/`superseded`/`account_deleted`/`server_shutdown`/`workspace_membership_revoked`),
  and (b) a `disconnected` abort over a **clean** tree. (Phase 2 — merges old AC4+AC5.)
- **AC6 (checkpoint failure is non-fatal):** a forced `write-tree`/`update-ref` failure mirrors
  `op="checkpoint-on-abort"` to Sentry but the abort branch still persists partial text + flips
  status (the abort path is not broken). (Phase 2)
- **AC8 (erasure cascade):** an account-deletion removes the user's `refs/checkpoints/*` (or the
  whole clone via `deleteWorkspace`); a successful restore consumes its ref. (Phase 3/4 — TTL
  prune NOT asserted, deferred.)
- **AC-obs (mechanical greps + typecheck):** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`
  clean; op slugs emitted on their paths
  (`grep -rEn 'op: "(checkpoint-on-abort|restore-refused|restore-failed)"' apps/web-platform/server`);
  AND no-stash scope guard — `git grep -n "stash" apps/web-platform/server/inflight-checkpoint.ts`
  returns nothing AND no `git add -A`/`git add .`
  (`git grep -nE "git add (-A|\\.)|add -- ?\\.|add\\b.*-A" apps/web-platform/server/inflight-checkpoint.ts`
  returns nothing — path-allowlist only, `hr-never-git-add-a-in-user-repo-agents`).

### Deferred (tracked, not in this PR)
- **Orphan-TTL prune** (ref-aware sweep + `CHECKPOINT_TTL_DAYS` + pruned-count monitor) — build a
  single checkpoint-ref-count gauge first; add the reaper only if it shows accumulation. Re-eval
  trigger: abort-without-resume refs observed accumulating.
- **Three-way merge** of a checkpoint against genuinely-newer state (Phase 3 step 5) → follow-up
  only if data shows demand (re-eval: users repeatedly hit refuse-and-report AND want auto-merge).

## Test Scenarios
- Unit (vitest, node project, `test/**/*.test.ts`): synthesized temp git repo fixture
  (`cq-test-fixtures-synthesized-only`); RED-A checkpoint, RED-B safe restore, RED-C
  refuse-and-report; AC4 non-disconnect no-checkpoint; AC5 clean-tree no-op; AC6 forced-failure
  non-fatal; AC8 prune + cascade.
- Deterministic only — assert on git ref existence / tree content / restored file bytes / emitted
  message value, never on agent prose (2026-04-19 learning).

## Risks & Mitigations
- **R1 — Shared-tree cross-conversation corruption (the headline risk).** Per-user concurrency >1
  on a shared `workspace_id` tree means a sibling's edits can leak into a checkpoint or be clobbered
  by a blind restore. Mitigation: gated restore (sole active slot + clean tree, else
  refuse-and-report) + `withWorkspacePermissionLock` around snapshot reads. The whole design exists
  to bound this.
- **R2 — Torn read during snapshot** (`write-tree` reads files a sibling is mid-writing).
  Mitigation: snapshot under `withWorkspacePermissionLock(workspacePath)` (already serializes
  workspace mutations). The snapshot is at least internally consistent.
- **R3 — HEAD must not move.** A WIP commit on the branch would move HEAD for every sibling
  conversation and ride a later push. Mitigation: `commit-tree` + dedicated ref only — HEAD/index/
  working tree untouched (verified the ref is invisible to `git status`).
- **R4 — `git stash` hook block.** Even `git stash create` is denied (`guardrails.sh:189`).
  Mitigation: implementation uses only `write-tree`/`commit-tree`/`update-ref`/`read-tree`/
  `checkout-index`/`rev-parse`/`status` — none match the guard. AC7 enforces.
- **R5 — Ref accumulation / disk fill.** `cron-workspace-gc` is dir-only and will never reap
  `refs/checkpoints/*`. Mitigation (v1): consume-on-restore + account-deletion clone removal keep
  the steady-state ref set small; the named bytes already survive un-reaped today, so a pointer
  adds no new disk-pressure class. A bounded ref-aware prune is **deferred** behind a ref-count
  gauge (Deferred section) rather than built speculatively.
- **R6 — Workspace reclone discards the ref.** The ref lives on the volume's clone, not Postgres;
  a wipe-and-reclone (`/api/repo/setup`) loses it. Accepted (reclone is an explicit user-destructive
  action); a DB column would not save the underlying object either (CTO D). Documented in the
  change-class.
- **R7 — Restore site ordering.** Restore must run AFTER the FR1 `set_current_workspace_id`
  rebind (`ws-handler.ts:1938`) — only then is `workspacePath` the correct workspace. Mitigation:
  hook at `:1938`, not before.

## Sharp Edges
- `## User-Brand Impact` is filled (deepen-plan Phase 4.6 gate).
- Deterministic tests only — never assert checkpoint/restore via an LLM prompt.
- Typecheck via `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (no root `workspaces`;
  `npm run -w` fails). Test via `./node_modules/.bin/vitest run` (NOT `bun test`; the package
  runner is vitest). Test FILE PATH must be `test/**/*.test.ts` (node project) — a co-located
  `server/*.test.ts` is silently never run by `vitest.config.ts`.
- `git stash` (incl. `git stash create`) is hook-blocked — the checkpoint MUST be `commit-tree`/
  `update-ref` based; HEAD/index/working tree must stay untouched (a WIP commit on the shared
  branch is a correctness bug, not just a style choice — it moves HEAD for sibling conversations).
- Checkpoint only on `kind === "disconnected"`; `user_requested_stop` keeps the conversation
  continuable (no checkpoint), `superseded`/`account_deleted` own their terminal state.
- The CTO ADR (`/soleur:architecture create …`) is recommended; the rationale is captured inline
  in Domain Review + Risks so the ADR is documentation, not a blocker.
- `refs/checkpoints/*` is a greenfield namespace (`git grep` returns 0) — no existing prune,
  observability, or cleanup covers it; v1 relies on consume-on-restore + account-deletion clone
  removal (orphan-TTL prune deferred).
- **`workspacePath` is NOT in closure at the abort catch** (`agent-runner.ts:2263` is outside the
  `runWithByokLease` callback that closes at 2261). Re-resolve it — code-verified plan-review P0-1.
- **`git read-tree <ref>` into the REAL index mutates the index** and breaks the "index untouched"
  invariant — both checkpoint AND restore MUST use a temp `GIT_INDEX_FILE` outside the worktree
  (code-verified plan-review P0-2/P1-3).
- **`git add -A` is a hard-rule violation** here (`hr-never-git-add-a-in-user-repo-agents`) AND
  captures sibling dirt — checkpoint MUST add only allowlisted paths via `getAllowlistedChanges`.
- The sole-active-slot probe MUST filter `last_heartbeat_at >= now() - 120s` (stale slots are
  swept lazily only inside `acquire_conversation_slot`) or it refuses-and-reports in the solo
  reconnect case — and it runs ONLY for team workspaces (`workspace_id !== userId`).
