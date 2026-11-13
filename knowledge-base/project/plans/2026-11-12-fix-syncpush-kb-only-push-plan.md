---
title: "fix(security): post-session syncPush publishes only knowledge-base commits, verified against the remote tip"
type: fix
date: 2026-11-12
slug: fix-syncpush-kb-only-push
branch: feat-one-shot-12600-syncpush-owner-approval
issue: 12600
closes: 12600
priority: p2
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
---

# fix: post-session syncPush publishes only Soleur's knowledge-base commits

## Overview

The post-session sync in the legacy agent runner (`syncPush` in `apps/web-platform/server/session-sync.ts`) pushes every
local commit ahead of the upstream branch with the GitHub App installation token. Nothing checks that those commits are
Soleur's own knowledge-base auto-commits, and no Owner approves the push, so a commit a member's agent made through Bash
reaches the connected repository at the end of the turn. This plan makes the sync push only a commit the server builds
itself: the remote tip's hash-verified tree with just the `knowledge-base` entry replaced, Soleur's message and
identity. It moves the local branch before the push so no other consumer of the clone sees a divergence, stops
self-heal from erasing uncommitted code edits, and pins the behaviour with tests.

## Enhancement Summary

**Deepened on:** 2026-11-13 (plan written and plan-reviewed 2026-11-12)
**Sections enhanced:** Proposed Solution, Attack Surface, Performance, Implementation Phases, Files, User-Brand Impact,
Observability, Guard Contract, Scope Check, Acceptance Criteria, Test Scenarios
**Agents used:** plan review (dhh, kieran, code-simplicity, architecture-strategist, spec-flow-analyzer, cto devex, cpo);
deepen (security-sentinel, test-design-reviewer, user-impact-reviewer, observability-coverage-reviewer,
learnings-researcher, a verify-the-negative pass); CTO rulings R1-R20.

### Key Improvements

1. **Overlay-only publish (R14).** A measured probe showed `rev-list --full-history --simplify-merges` and
   `diff-tree` read forged object bytes without a hash check. That makes the planned history-walk predicate
   bypassable through a check-then-swap. The sync now pushes only server-built commits from three hash-verified
   objects. This also closes `Fixes #N` and forged-author publication.
2. **The clone never diverges (R1, R14, R17).** The local branch moves to `S`, or to a merge `M` while code commits are
   held, by a `--no-deref` CAS before the push. The fallback side commit descends from `T`. Self-heal, the ADR-068
   overlay and the next turn all see a fast-forward.
3. **Self-heal gate (R18).** Held code commits become the steady state, so `selfHealNonFastForward` must no longer
   erase dirty non-KB edits on an upstream push.
4. **Authoritative default branch (R2, R17).** One hardened `ls-remote --symref`, an exact ref-name match, a
   line-anchored `GH006` and no agent-chosen name in argv. `resolveDefaultBranchForFallback` is deleted.
5. **Observability made searchable.** Per-reason error classes and tags, an unconditional Better Stack line, a static
   `KbSyncError` (raw push errors now embed the repo URL and sha), `fallback_reason` and layer citations.

### New Considerations Discovered

- The reconcile webhook fires on the App's own push and reads no sender (verified).
- `--no-deref` is needed on every ref write (CTO measurement).
- A real `pre-receive` hook works on `file://` remotes despite `core.hooksPath=/dev/null` on the pusher.
- Follow-ups filed: #12718 (P1, token-bearing pull on the legacy arm), #12719 (conflicted pull), #12734 (rulesets
  `GH013`), and a residual comment on #5221.

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed). (No `spec.md` exists for this branch.)

## Research Insights

### Premise Validation

- #12600 is OPEN, closed by no PR. #12567 (the push-disclosure PR) is MERGED and is background only: it never touched
  `syncPush`. #12597 is CLOSED (PR #12646). #12197, #12598, #12605 are OPEN.
- `syncPush` exists on this branch at `apps/web-platform/server/session-sync.ts` (`export async function syncPush`),
  `hasLocalCommits` (`rev-list --count @{u}..HEAD`, falling back to `rev-list --count HEAD`) and the bare push
  `gitWithInstallationAuth(["push"], installationId, …)` are as the issue describes. Its only production caller is
  `apps/web-platform/server/agent-runner.ts` ("Sync: push changes to the ACTIVE workspace's remote"). It runs on every
  `result` event (every turn), not only at session end.
- Collision pre-check: the only open PR naming #12600 is #12704, this branch's own WIP draft (no files). The foreign
  `test-all.sh` processes belong to an unrelated worktree (`feat-kernel-patch-web-hosts-12008`).
- ADR corpus: ADR-309 (`knowledge-base/engineering/architecture/decisions/ADR-309-durable-action-bound-approval-requests.md`)
  names `syncPush` as "#12600's path" three times (item 8 discharge note, the 2026-11-10 #12197 addendum, and the
  workspace-settings note). No ADR rejects a commit filter on the sync push.

### Property List (Phase 0.6b)

- P1. After any session (Owner or member), no commit that changes a path outside `knowledge-base/` reaches the connected
  repository through the post-session sync.
- P2. The set of commits the sync analyses is exactly the set the push sends: no workspace-config or ref the agent can
  write may widen what is pushed beyond what was checked.
- P3. A refused sync loses nothing: the member's commits and working-tree edits stay in the workspace.
- P4. A refusal is visible to the operator without SSH (Sentry), and carries no tenant paths, shas or raw user ids.
- P5. The workspace's knowledge-base changes keep reaching the remote in the normal case, including after a
  session-start pull merge of upstream changes (as Soleur-built commits since R14, not the local auto-commits).
- P6. A test pins the chosen behaviour (issue acceptance bullet 2).
- P7. The sync never leaves the workspace's default branch diverged from what it pushed: after a successful push, the
  remote tip is an ancestor of local HEAD, so `syncWorkspace`'s self-heal, the ADR-068 git-data overlay and the next
  turn's tip check all see a fast-forwardable clone (plan review, spec-flow G1 / architecture 1).

### Cut List (Phase 0.6b)

- Copy change to `PUSH_DISCLOSURE` (option 2 of the issue) -> buys an accurate Settings claim -> the code fix makes the
  existing sentence accurate for the agent-commit route; any remaining copy question goes to a follow-up for CPO/CLO
  (operator constraint: no Settings or legal copy edits here).
- Commit-message allowlist (`AUTO_COMMIT_MSG_PUSH` / `AUTO_COMMIT_MSG_PULL`) as the predicate -> buys nothing: an agent
  can run `git commit -m "Auto-commit after session"`; P1 is a property of paths, not of messages.
- A new Owner-approval flow for the sync push -> P1 is met by refusing; routing the sync through the approval queue would
  touch the approval-queue flag surface, which the operator ruled out.

- History-walk predicate over `<T>..<headSha>` (plan-time ruling B) -> bought P1 for pushes of agent-authored KB-only
  commits -> cut at deepen-plan (R14): it reads forged object bytes (measured), and pushing only server-built commits
  buys P1 without it.

### Plan-time measurements (scratch real-git probe, git 2.56.0) — superseded by R14

Kept as the record of why the history-walk predicate was first chosen. `probe7.sh` (Proposed Solution, Research
Insights) then showed the walk reads forged object bytes, so R14 replaced it with the overlay-only publish; none of
the rows below is load-bearing any more.

Probe script: `/tmp/claude-1000/-data-git-repositories-jikig-ai-soleur/4fed09e4-fd93-4c8b-8997-43367c6a07a8/scratchpad/probe3.sh`
plus inline runs. Command shape: `git rev-list --count <flags> <base>..<head> -- . ':(exclude)knowledge-base/'`.

| Case | default flags | `--no-merges --full-history` | `--full-history --simplify-merges` |
|---|---|---|---|
| KB-only linear commits | 0 | 0 | 0 |
| add then delete `.github/w.yml`, then upstream pull-merge | **0 (bypass)** | 2 | 3 |
| KB-only local + pull-merge of upstream non-KB change (legit) | n/a | 0 | 0 |
| evil merge (merge commit itself adds `src/evil`) | 1 | **0 (miss)** | 1 |
| top-level FILE named `knowledge-base` with `:(exclude)knowledge-base` (no slash) | | 0 (miss) | |
| same with `:(exclude)knowledge-base/` (trailing slash) | | 1 | |
| `.git/shallow` planted inside the range | | 2 (fails closed: the commit becomes a root) | |
| `GIT_LITERAL_PATHSPECS=1` | | counts all commits (fails closed) | |
| KB-only root commit, no remote base | | 0 | |
| rename `src/x` -> `knowledge-base/m/x` | | counted (the delete is a non-KB change) | |
| symlink or gitlink inside `knowledge-base/` | | 0 (KB path; residual, see Risks) | |

Conclusions: plain `rev-list` history simplification is a bypass; `--no-merges` misses an evil merge;
`--full-history --simplify-merges` with the trailing-slash exclude is the one form that is right on every measured row.

### Relevant files

- `apps/web-platform/server/session-sync.ts`: `ALLOWED_AUTOCOMMIT_PATHS` (`/^knowledge-base\//`),
  `ALLOWED_GIT_SUBCOMMANDS` (status/add/commit/remote/rev-list), `runConnectedRepoGit`, `hasLocalCommits`,
  `runProtectedFallback`, `syncPush`, `resolveDefaultBranchForFallback` (private).
- `apps/web-platform/server/git-auth.ts` `gitWithInstallationAuth`: the legacy arm runs through `hostGitInvocation` with
  the workspace's own `.git/config`, so a bare `git push` follows agent-authored `push.default`, `remote.origin.push`,
  `branch.<b>.merge`; `@{u}` resolves to a `refs/remotes/origin/*` ref the agent can also write.
- `apps/web-platform/server/host-git.ts` + `server/inngest/functions/_git-hardening.ts`: `--no-replace-objects`,
  `GIT_NO_REPLACE_OBJECTS=1`, refusal of `commondir`, alternates and `info/grafts`. No literal-pathspec setting.
- `apps/web-platform/test/host-git-consumers-real-git.test.ts`: real-git harness with `file://` remotes (the host-git mock
  widens `allowProtocol` with `:file`); its exec-site census regex matches only literal `exec*("git"`, so new
  `runConnectedRepoGit` / `gitWithInstallationAuth` calls need no census row. It mocks `resolveInstallationId` to `null`,
  so it never reaches the push today.
- `apps/web-platform/test/server/session-sync-protected-fallback.test.ts` `makeGitMock`: keys the main push on
  `args[0] === "push" && args.length === 1` and the side-branch push on `args[0] === "push"`. An explicit-refspec main
  push would fall through to the side-branch arm and make the protected, shallow and auth rows pass vacuously: this mock
  must change with the push form.
- Other syncPush harnesses (mocked git, no push-argv assertion): `test/server/session-sync-sentry-mirror.test.ts`
  (`if (argv[0] === "push") throw`), `test/server/session-sync-workspace-last-synced.test.ts`,
  `test/session-sync-path-allowlist.test.ts`.
- Sentry: no op registry. `apps/web-platform/infra/sentry/issue-alerts.tf` `kb_sync_protected_fallback_failed` filters
  `op in "kb-sync.protected-fallback-failed"`, pinned by
  `test/sentry-kb-sync-protected-fallback-alert-op-contract.test.ts`. A new op pages nobody unless added there.
- Workspace clones are `git clone --depth 1` (shallow, single-branch, default branch checked out, upstream set by clone)
  (`server/workspace.ts`). `provisionWorkspace`'s "Initial workspace" commit lives only in no-remote workspaces
  (`syncPush` returns at `hasRemote`). No Soleur-authored non-KB commit is expected to reach GitHub through `syncPush`
  (`inflight-checkpoint` writes `refs/checkpoints/*`; `c4-writer` commits through the GitHub API).
- git-data replication force-pushes all refs and a re-clone overlays the git-data tip
  (`server/ensure-workspace-repo.ts`, `merge-base --is-ancestor HEAD dataRef`), so an unpushed local commit survives a
  host move only while the GitHub tip is an ancestor of the local branch (ADR-068 (d)); P7 keeps that true.
- `server/workspace-sync.ts` `syncWorkspace` -> `selfHealNonFastForward`: on a diverged default-branch clone it branches
  local commits aside to `soleur/recovered-kb-sync-<ts>` and runs `reset --hard origin/<default>` (dirty edits lost).
  Callers: `server/inngest/functions/workspace-reconcile-on-push.ts` (the GitHub push webhook; it reads no sender, so it
  fires on the App's own sync push), `cron-workspace-sync-health.ts`, `c4-writer.ts`, and the KB routes
  (`app/api/kb/upload`, `app/api/kb/file/[...path]`, `app/api/kb/sync`). Verified 2026-11-12.
- `server/approval/workspace-head.ts` `readWorkspaceHeadSha`: reads HEAD with no git process (packed-refs, one symref
  hop, refuses reftable); the plan adds a sibling export that also returns the ref name (no return-type widening of the
  existing export, `hr-type-widening-cross-consumer-grep`).
- `server/push-branch.ts` `checkCommitPresent`: an ad hoc token-free `execFile("git", …)` in the isolated dir (exit 1 vs
  128 split); `AGENT_AUTHOR_NAME` / `AGENT_AUTHOR_EMAIL` are module constants there.
- `server/git-hardened-env.ts` (home of `buildIsolatedGitEnv`) is a leaf importing only `node:path` and the
  import-free constants of `inngest/functions/_git-hardening.ts` (no `fs`, no `child_process`);
  `server/git-isolated-push-dir.ts` documents that it spawns no git (its unit test mocks `node:child_process`).
- `apps/web-platform/server/permission-callback-bash-batch.ts` `NO_BATCH_GIT_VERBS`: `git push` is never batch-granted,
  but `git commit` is an ordinary Bash command.

### Institutional learnings applied

- `knowledge-base/project/learnings/2026-04-27-autoloop-pr-quality-failure-modes.md` (#2905): path allowlist over
  denylist; the auto-commit wrapper allowlists verbs and forbids flags.
- `knowledge-base/project/learnings/2026-05-11-plan-review-caught-git-log-union-trap-and-cross-module-field-assumption.md`:
  verify any pathspec-limited `rev-list` claim in a scratch repo before relying on it (done above).
- `knowledge-base/project/learnings/2026-06-03-self-heal-reset-must-gate-on-actual-repo-state-not-assumed-mirror.md`:
  gate on a computed boolean, fail safe on NaN or ambiguous counts.
- `knowledge-base/project/learnings/2026-05-12-ship-unpushed-commits-fail-open-class.md`: verify the pushed sha, not
  the exit code.
- `knowledge-base/project/learnings/2026-05-04-vacuous-red-via-shared-fixture-and-toolchain-pinning.md`: pick fixture
  inputs that reach the new guard, not a fast path.
- Sharp edge "prefer the tool's effect on a sandbox over its reports": the pinning tests assert the bare remote's refs
  and objects after `syncPush`, not the git argv alone.

### Functional overlap

`soleur:engineering:discovery:functional-discovery`: no community artifact overlaps (closest are developer-terminal
approval gates). Nothing installed.

### CLAUDE.md / AGENTS.md conventions

`cq-silent-fallback-must-mirror-to-sentry`, `cq-write-failing-tests-before`, `cq-test-fixtures-synthesized-only`,
`hr-observability-as-plan-quality-gate`, `hr-no-ssh-fallback-in-runbooks`, `hr-technical-fork-is-not-an-operator-question`.
- Related, out of scope: #12668 (cc Bash can push with the minted token, a different runner and route), #12140 (retire
  the legacy runner; until it lands, this path is live for every legacy-runner turn), #5426 (protected-branch fallback).

## Research Reconciliation — Spec vs. Codebase

| Claim (issue / brief) | Reality on this branch | Plan response |
|---|---|---|
| "When a legacy-runner session ends, `syncPush` pushes" | It runs on every `result` event, so after every turn | Gate every call; the debounce keys on the workspace plus the reason, not the session |
| "`hasLocalCommits` counts all of `@{u}..HEAD`" | True, and `@{u}` itself is agent-writable (`branch.<b>.merge`, `refs/remotes/origin/*`) | Read the remote state from `ls-remote`, never `@{u}`; keep `hasLocalCommits` only as a cheap skip (a forged "no commits" can only suppress a push), kept working by setting the tracking ref after a verified push (R8) |
| "Fix-Size: ~40 lines / 3 files (session-sync.ts commit filter, agent-runner call site, one test)" | A filter over `@{u}..HEAD` plus a bare `git push` is bypassable through agent-written config (ruling C); history walks read agent-forgeable object bytes (measured, R14); the protected fallback is a second unapproved route (ruling F); a pushed commit the clone does not contain triggers self-heal (R1) | ~850 lines over the files in `## Files to Edit` / `## Files to Create`; the agent-runner call site needs no change (the signature stays) |
| Option "refuse or skip when `@{u}..HEAD` holds any other commit" | Refusing alone stalls KB sync forever once an agent commits code on the default branch (ruling D) | Push only a Soleur-built KB-only commit, every time (R14); the member's commits stay local |
| Option "name the post-session sync in the Settings copy" | Copy edits are barred in this PR; the CLO agent finds the sentence accurate after the fix but incomplete | Follow-up #12713 with drafted wording |

## Problem Statement

`syncPush` (`apps/web-platform/server/session-sync.ts`) runs host-side with the GitHub App installation token after every
legacy-runner turn, for Owners and members alike. It auto-commits only `knowledge-base/**` (#2905), but then runs a bare
`git push` that publishes every local commit ahead of upstream. A member's agent can `git commit` any path through Bash
(a `.github/workflows/*` file included) and the commit reaches the Owner's repository at the end of the turn. Since
#12567, `github_push_branch` (the route the agent asks for) needs the Owner's approval in every approval-queue state, and
a session whose web access is running has no credentials in its sandbox, so in exactly the state the Settings sentence
describes this sync is the only unapproved route from an agent commit to the remote.

The bare push is also config-steered: the legacy `gitWithInstallationAuth` arm reads the workspace's own `.git/config`,
which the agent can write, so `push.default=matching`, a `remote.origin.push` refspec or a forged `refs/remotes/origin/*`
tip can widen what is sent beyond any range the server checked. The protected-branch fallback builds on
`refs/remotes/origin/<branch>` (agent-writable), reads its PR base from the agent-writable `refs/remotes/origin/HEAD`
with a token on the legacy arm (`resolveDefaultBranchForFallback`), and its success path runs `checkout -f` plus
`reset --hard origin/<default>`, which today discards dirty edits and any non-KB local commits.

## Proposed Solution

All CTO rulings are recorded in `knowledge-base/project/specs/feat-one-shot-12600-syncpush-owner-approval/decision-challenges.md`
(A-P at plan time, R1-R13 after plan review, R14-R20 at deepen-plan). Notation: `D` = authoritative default branch,
`T` = remote tip of `D`, `headSha` = frozen local HEAD, `S` = Soleur-built KB-only commit, `M` = local merge of
`headSha` and `S`.

**The core rule (R14): the sync only ever pushes a commit the server built.** `S` has parent `T`, a root tree equal to
`T`'s hash-verified root tree with only the `knowledge-base` entry replaced by `<headSha>:knowledge-base`, the fixed
message `KB_SYNC_SIDE_COMMIT_MSG` and the Soleur identity. No agent-authored commit object, message or author ever
reaches the remote through the sync, and no decision rests on a history walk over agent-writable object bytes.

0. **Where git runs (rulings P, R2, R6, R12, R19, R20).**
   - Workspace reads, no git process: `headSha` and the ref name through a new `readWorkspaceHeadRef` in
     `server/approval/workspace-head.ts` (sibling of `readWorkspaceHeadSha`); `.git/MERGE_HEAD` existence.
   - Workspace writes, exactly two verbs added to `ALLOWED_GIT_SUBCOMMANDS`, each behind an exact-argv guard:
     `["unpack-objects", "-q"]` (pack on stdin) and `update-ref --no-deref` in two shapes only,
     `["update-ref", "--no-deref", "refs/heads/<D>", <40hex new>, <40hex old>]` (CAS mandatory) and
     `["update-ref", "--no-deref", "refs/remotes/origin/<D>", <40hex>]`.
   - Everything else runs in the server-created isolated GIT_DIR (`createIsolatedPushDir`: server-written config,
     workspace objects as a server-fixed alternate, validated shallow): hash checks, tree builds, pack, fetch, push.
     Local verbs run token-free through `runIsolatedGitLocal` in the new `server/git-isolated-local.ts`; only
     `ls-remote`, `fetch` and `push` go through `gitWithInstallationAuth(…, { hardened })`.
   - The push half lives in the new `server/kb-sync-publish.ts`; `syncPush` orchestrates (R6).
1. **Pre-checks, in order.** `hasRemote`; `.git/MERGE_HEAD` present -> skip the auto-commit AND the push
   (`merge_in_progress`, R11); auto-commit `knowledge-base/**` (unchanged); `hasLocalCommits` pre-token skip
   (unchanged); installation id; `readWorkspaceHeadRef` -> refuse `detached_head`.
2. **Authoritative remote state (rulings C, R2, R17).** URL = literal `https://github.com/<owner>/<repo>.git` from
   `getCurrentRepoUrl(userId, workspaceId)` + `parseOwnerRepo`, never `remote.origin.url`. One hardened
   `ls-remote --symref <url> HEAD refs/heads/soleur/kb-sync` (no agent-chosen name in argv): exactly one
   `ref: refs/heads/<D>\tHEAD` line gives `D`, the `HEAD` line gives `T`, an exact `refs/heads/soleur/kb-sync` line gives
   the side tip; duplicates or malformed lines throw. Refuse `non_default_branch` unless `refName === "refs/heads/" + D`
   exactly; `remote_branch_absent` when the remote has no `HEAD` (R5). `T == headSha` -> set the tracking ref, return
   early: no push, no history row, no `updateLastSynced` (R8). `T` not present locally -> `remote_unknown_tip`. `T` not
   an ancestor of `headSha` (`rev-list --count <headSha>..<T>` == 0) -> `remote_ahead` (ruling I, kept as an accident
   guard, not a security check: forging it only lets an agent revert remote KB content, which a KB edit can do anyway).
3. **Verify, then build (R14).** In the isolated dir, hash-verify three objects by recomputing their ids
   (`cat-file <type> <id>` | `hash-object -t <type> --stdin` == `<id>`): `T`'s commit, `T`'s root tree and `headSha`'s
   commit. Any mismatch -> `hash_mismatch` (warning; a tamper signal). Then:
   - `<headSha>:knowledge-base` absent or not a tree -> `kb_not_tree`.
   - KB entry of `T`'s root equal to `headSha`'s -> nothing to sync: `held_foreign` when `headSha^{tree}` differs from
     `T^{tree}` (info), else return.
   - `S = buildKbOverlay(T, headSha)`: `ls-tree -z` of the verified root, `knowledge-base` entry replaced, `mktree -z`,
     `commit-tree -p <T>` with `-c user.name=<AGENT_AUTHOR_NAME> -c user.email=<AGENT_AUTHOR_EMAIL>` (constants exported
     from `push-branch.ts`).
   - **Guard:** `ls-tree -z <S^{tree}>` and the verified `T` root differ in exactly the `knowledge-base` entry and
     nothing else (compared on the parsed entry lists the server built; no walk, no git-version dependence).
4. **Keep the clone fast-forwardable before the push (rulings R1, R14; P7).**
   - `S^{tree} == headSha^{tree}` (no non-KB changes local, the common case): hand `S`'s new objects to the workspace
     (`rev-list --objects <S> ^<T> ^<headSha>` | `pack-objects --stdout` | `unpack-objects -q`), then CAS
     `update-ref --no-deref refs/heads/<D> <S> <headSha>`. Local equals what will be pushed; history stays linear; the
     index and working tree do not change (same tree).
   - Otherwise (non-KB changes held local): `M = commit-tree <headSha>^{tree} -p <headSha> -p <S>` with message
     `KB_SYNC_MERGE_MSG` ("Soleur: merge knowledge-base sync") and the Soleur identity; hand over `S` and `M`; CAS
     `update-ref --no-deref refs/heads/<D> <M> <headSha>`.
   - CAS failure (stderr "but expected") -> `head_moved`, nothing pushed; any other `update-ref` or `unpack-objects`
     failure -> `ref_update_failed` / `unpack_failed`, nothing pushed.
   - Push `S` (step 5); on success set the tracking ref to `S`. A failed push leaves an unpushed `S` in local history:
     harmless, the next turn builds a fresh `S` on `T` again. Next turn `T` (= `S`) is an ancestor of local HEAD.
5. **One push chokepoint (R6).** `pushVerifiedKbOnly({ base, sha, ref, url, isolated, installationId })`, `ref` limited
   to `refs/heads/<D>` or `refs/heads/soleur/kb-sync`: re-runs the root-tree guard of step 3 for `sha` against `base`,
   then pushes `<sha>:<ref>` non-force, no lease, through the hardened arm. `classifyPushError` matches only the
   line-anchored `/^remote: error: GH006:/m` in stderr (R2, R16; a ref name in git's status line cannot match it);
   `GH013` (rulesets) stays `other`, pinned by a test, follow-up #12734.
6. **Protected-branch fallback (rulings F, R3, R4, R15, R17).** On a `GH006` reject of the verified push of `S`:
   - Side parent `P` = the side tip from step 2, or `T` when absent; fetch it into the isolated dir when not local
     (`fetch --depth 1 --no-tags <url> refs/heads/soleur/kb-sync`). Hash-verify `P`'s commit and root tree (R15).
   - Ruling I extended (R4): build only when the side branch is absent, `P` is an ancestor of `headSha`, or `P`'s KB
     entry equals `T`'s (the PR merged); else `side_ahead` (warning).
   - `side`: root tree = `T`'s verified root with the `knowledge-base` entry from `headSha`; parents `(P, T)`, or the
     single parent `T` when the side branch is absent or `P` already descends from `T` (R17). `side` descends from `T` by
     construction, so the clone never diverges and the PR diff against `D` shows only KB changes. Skip when the side's
     KB entry equals `P`'s. Push through `pushVerifiedKbOnly({ base: T, sha: side, ref: "refs/heads/soleur/kb-sync" })`;
     PR find/create unchanged, base `D`.
   - Workspace: the step-4 handling already ran against `S`; after a successful side push, CAS local `D` from its
     step-4 value to `side` only when `side^{tree}` equals the step-4 value's tree (KB-only case), and set the tracking
     ref to `side` (R17: stops a token mint every turn while the PR is open; the next `fetch` overwrites it).
     Otherwise leave the workspace as it is. A post-success workspace CAS failure is `head_moved`, never a fallback
     failure (the alert stays for undelivered syncs).
   - Delete `resolveDefaultBranchForFallback` and the workspace `checkout -f -B`, overlay `checkout`, `commit` and
     `reset --hard` calls.
7. **Self-heal gate (R18).** `selfHealNonFastForward` (`server/workspace-sync.ts`), default-branch arm: before the
   branch-aside + `reset --hard`, run `status --porcelain --untracked-files=no`; when any tracked change lies outside
   `knowledge-base/`, refuse the reset, emit op `self-heal-aborted-dirty-nonkb` (warning) and return the existing
   `ERROR_CLASS_NON_FAST_FORWARD`. Held foreign commits are now the steady state, so without this every upstream push
   to `D` would erase a member's uncommitted code edits; the stall ends at the next session-start
   `pull --no-rebase --autostash`. #5221 keeps the broader recovery-and-lock work.
8. **All sessions (ruling E).** No role read: Owner and member sessions take the same path.
9. **Records (rulings G, R5).** ADR-309 addendum discharging the three "#12600's path" mentions (located by text); ADR-068
   addendum (the sync keeps "GitHub tip is an ancestor of the local branch" by updating the local branch before the
   push); ADR-050 consumer-list entry for `session-sync` updated if it names the legacy push. No `model.c4` edit (R5).
   No `PUSH_DISCLOSURE` edit (#12713).

### Research Insights (deepen-plan, 2026-11-13)

**Measured (scratch probes, git 2.56.0):**

| Probe | Result | Consequence |
|---|---|---|
| `probe7.sh`: F's tree object file overwritten with T's tree bytes | `rev-list --count --full-history --simplify-merges T..F -- . ':(exclude)knowledge-base/'` = 0; `diff-tree --quiet` rc 0; same through `GIT_ALTERNATE_OBJECT_DIRECTORIES`; only `ls-tree` / `fsck` report "hash mismatch" | a history walk over workspace objects is no guard (check-then-swap TOCTOU); R14 drops it |
| `probe8.sh`: `cat-file tree <id>` piped to `hash-object -t tree --stdin` | equals the id for genuine objects; differs for forged loose AND packed (`gc`) objects; `cat-file` itself does not refuse | the three-object hash check of step 3 is cheap and catches the forgery |
| `probe6.sh`: S built in a separate GIT_DIR with the workspace as alternate, M merge, `pack-objects` -> `unpack-objects`, CAS `update-ref` | 3 objects handed over; CAS ok, wrong old value refused; dirty tracked file preserved; S pushed, foreign object absent on the remote; `pull --ff-only` ok; remote tip is an ancestor of HEAD; turn 2 sees `T` as an ancestor | the M arm keeps P7; the CAS-to-S arm is the same hand-off with one object fewer |
| test-design reviewer `gh006probe` | a `file://` bare remote's `pre-receive` hook runs even when the pusher passes `-c core.hooksPath=/dev/null`; stderr carries `remote: GH006: …` | the protected-branch fixture works on `file://` |
| CTO: `refs/heads/d` symref to `refs/heads/x` | plain `update-ref refs/heads/d B A` writes `x`; with `--no-deref` `d` becomes the sha, `x` untouched | R19: `--no-deref` on both guarded shapes |

**Precedent diff (§4.4).** `server/inflight-checkpoint.ts` (`commit-tree` -> `update-ref refs/checkpoints/<id>`) and
`server/inngest/functions/_cron-safe-commit.ts` (`commit-tree` -> `update-ref refs/heads/<branch> <sha>`) build commits
in the workspace through `hostGitInvocation` with identity in `extraEnv` and no CAS old value. This plan differs on
purpose: commits are built in the isolated GIT_DIR (ruling P), identity is `-c` argv (ruling L; `buildIsolatedGitEnv`
admits no `GIT_AUTHOR_*` key), and every `refs/heads` write is a `--no-deref` CAS (R1, R19). The checkpoint precedent's
ADR-050 residuals (`filter.*` drivers, `.git/info/attributes`) do not apply: `unpack-objects` and `update-ref` run no
filter.

**Learnings applied at deepen time:**
`knowledge-base/project/learnings/bug-fixes/2026-06-16-diverged-clone-recovery-branch-aside-before-reset.md` (self-heal
counts `@{u}..HEAD`: the tracking ref must equal the pushed sha, H6),
`knowledge-base/project/learnings/best-practices/2026-06-15-git-checkpoint-clean-tree-not-sufficient-head-parity-and-symmetric-clone.md`
(HEAD can move between check and write: the CAS old value is `headSha`),
`knowledge-base/project/learnings/2026-09-20-the-gate-i-built-to-resolve-a-run-could-be-redirected-by-one-env-var.md`
(audit every env key git reads in the isolated arm, not only the named ones),
`knowledge-base/project/learnings/2026-09-21-the-fence-probe-read-the-config-the-bootstrap-writes-not-the-path-a-push-takes.md`
(the pre-receive fixture must be a real hook, not a mock),
`knowledge-base/project/learnings/test-failures/2026-04-07-shared-bare-remote-ordering-dependency.md` (copy the template
remote per row; no row mutates the template),
`knowledge-base/project/learnings/2026-11-07-a-required-shard-on-its-timeout-edge-made-the-merge-queue-a-coin-flip.md`
(measure the battery's runtime against the shard timeout),
`knowledge-base/project/learnings/best-practices/2026-05-29-mirror-warn-debounce-gates-both-pino-and-sentry.md` (the
debounce also drops the pino line: log unconditionally first),
`knowledge-base/project/learnings/test-failures/2026-06-30-vi-waitfor-floor-vs-component-rearm-race.md` (explicit
`vi.waitFor` timeouts).

## Technical Considerations

### Attack Surface Enumeration

Every way a commit an agent authored can reach the connected repository from the legacy runner, and what this plan does:

| Route | Owner-gated today? | After this plan |
|---|---|---|
| `github_push_branch` (agent asks) | yes, every queue state (#12567) | unchanged |
| Sandbox `git push` with egress off (session keeps repo credentials) | no, by design; disclosed by `PUSH_DISCLOSURE` | unchanged (disclosed) |
| `syncPush` main push (bare `git push`) | **no** | closed: only a server-built `S` (verified root, KB entry replaced) is pushed, explicit sha refspec, hardened arm |
| `syncPush` push steered by `push.default`, `remote.origin.push`, `branch.<b>.merge`, `remote.origin.url`, `url.*.insteadOf` | **no** | closed: literal URL and refspec from an isolated GIT_DIR that never reads workspace config |
| Forged `refs/remotes/origin/*` / `@{u}` as a base | **no** | closed: bases come from `ls-remote` |
| Forged object bytes (check reads a lie, push sends the truth) | n/a | closed: no history walk; the three objects the build reads are hash-verified (R14, measured) |
| Agent-written commit message (`Fixes #N` closing Owner issues) or forged author on a pushed commit | **no** | closed: only Soleur-built commits with a fixed message and identity are pushed (R14) |
| Push target chosen by the agent's checked-out branch | **no** | closed: target is the authoritative `D`; another branch refuses `non_default_branch` (R2) |
| Protected fallback side push to `soleur/kb-sync` | **no** (base is an agent-writable ref) | closed: verified side parent and `T`, ruling I extended, root-tree guard, explicit refspec (R4, R15) |
| Fallback PR base from `refs/remotes/origin/HEAD` with a legacy-arm token | **no** | closed: `D` from the hardened `ls-remote --symref` (R2) |
| `classifyPushError` steered by a ref name in git's stderr status line | n/a | closed: line-anchored `^remote: error: GH006:` only (R16) |
| Synthetic commit carrying an agent-chosen identity | n/a | closed: `-c user.name` / `-c user.email` argv; the isolated env admits no identity key (rulings L, P) |
| History rewrites: replace refs, grafts, `commondir`, alternates | already closed by host-git hardening | unchanged; decisions run in the isolated GIT_DIR (ruling P) |
| Fallback `checkout -f` + `reset --hard` destroying dirty non-KB edits and non-KB commits | pre-existing loss | closed: no checkout, no reset; `--no-deref` CAS ref moves with equal trees only (R3, R17) |
| A pushed commit the clone lacks, then `syncWorkspace` self-heal `reset --hard` (reconcile webhook on our own push) | n/a | closed: the local branch is updated before the push (R1, R14) |
| Upstream moves while a foreign commit sits local, then self-heal `reset --hard` loses dirty non-KB edits | pre-existing, now frequent | closed for dirty non-KB edits: `self-heal-aborted-dirty-nonkb` gate (R18); recovery-and-lock work stays on #5221 |
| Conflicted session-start pull, then auto-commit commits conflict markers | pre-existing | closed for the push: `merge_in_progress` skip (R11); pull-side abort is #12719 |
| Session-start `syncPull` token-bearing `pull` on the legacy arm reads workspace `url.*.insteadOf` / `http.*` | pre-existing | residual, P1 issue #12718 (R9) |
| `update-ref` following a symref swapped in after the HEAD read | n/a | closed: `--no-deref` (R19) |
| Symlink planted in the object store or ref/log dirs between `createIsolatedPushDir`'s walk and `unpack-objects` / `update-ref` | n/a | residual, accepted (ADR-309 9b class, R12); it now runs per turn without approval, but the published bytes are server-built and verified |
| Chained `objects/info/alternates` planted after the walk | ADR-309 9b residual, behind Owner approval | now unattended per turn; narrowed: the pushed objects are `S`, its rebuilt root and KB subtrees; a non-KB object can only be sent if referenced by a verified `T` entry, which the remote already has |
| Symlink or gitlink inside `knowledge-base/` | not gated | residual, accepted: a KB path, already staged by the auto-commit sweep today; no effect on CI or code |
| Owner force-push between the tip read and the push | n/a | residual, accepted (ruling J) |
| cc runner Bash push with the minted token | separate | #12668 |

### Performance

Turns with no local commits keep today's cost (`hasLocalCommits` runs before any token mint), and stay that way after a
push because the tracking ref is set to what was pushed (R8, R17). A turn with local commits costs one `ls-remote` round
trip, the isolated-dir object walk (capped at `OBJECT_WALK_ENTRY_CAP`, 250 000 entries; over the cap is a refusal,
reported), three hash checks and a handful of plumbing calls; there is no history walk. The real-git battery builds one
template remote in `beforeAll` and copies it per row (no row mutates the template); per-test timeout 30 s; Phase 0
measures its runtime against the webplat shard timeout (estimate 20-40 s; it runs on the normal webplat shards, not the
mutations leg).

### NFR impacts

Security (integrity of the customer's repository) improves. Availability of KB sync is unchanged on the normal path.
KB edits wait for a later turn or session on `remote_ahead`, `remote_unknown_tip`, `side_ahead`, `head_moved`,
`merge_in_progress`; they never sync from a non-default branch (`non_default_branch`, see User-Brand Impact). The
remote's KB history becomes one "Soleur: sync knowledge-base" commit per synced turn instead of the
"Auto-commit after session" commits (same constant message today, `session-sync.ts` `AUTO_COMMIT_MSG_PUSH`).

## Implementation Phases

One commit per phase (devex review item 8), each with its RED runs recorded.

### Phase 0 — Measure, then write the failing tests (`cq-write-failing-tests-before`)

1. Build the `runner` stage of `apps/web-platform/Dockerfile`, rerun `probe6.sh`, `probe7.sh` and `probe8.sh` (copied
   into the work tree as synthesized fixture scripts) inside it, and record `git --version` there and on CI
   (`ubuntu-latest`). The design no longer depends on `--simplify-merges` (R14); a differing row in the hash-check or
   hand-off probes is a P0 redesign.
2. Measure on the hardened isolated arm against a `file://` bare remote (`GIT_ALLOW_PROTOCOL` widened exactly as
   `test/push-branch-isolated-real-git.test.ts` does): `ls-remote --symref <url> HEAD refs/heads/soleur/kb-sync` and
   `fetch --depth 1 --no-tags <url> refs/heads/soleur/kb-sync` into a shallow isolated dir. Record both for the PR body.
3. Measure a two-parent side commit `(P, T)` on the protected fixture: `pull --ff-only` from a remote whose `D` is
   `T` and whose `soleur/kb-sync` is `side` stays a fast-forward after the PR merges.
4. Verify the behaviour today on a non-default branch (single-branch `--depth 1` clone, new local branch, bare
   `git push`): record what a user on a feature branch got before this change (User-Brand Impact, non-default branch).
5. Write `apps/web-platform/test/session-sync-kb-only-push-real-git.test.ts` (Test Scenarios below). All rows RED on
   the unmodified `syncPush` except the must-PASS rows. Measure its runtime.

### Phase 1 — Move, runner and reads

- Move `runProtectedFallback` and the push call into `server/kb-sync-publish.ts` with no behaviour change (own commit).
  Header comment states Guard 1's property.
- `server/git-isolated-local.ts`: `runIsolatedGitLocal(isolated, args, { input? })` = lazy `child_process`
  `execFile("git", [...HARDENED_GIT_ARGS, ...args])`, `cwd: isolated.gitDir`, `env: buildIsolatedGitEnv(isolated)`, a
  timeout, no credentials; exit codes surfaced (1 vs 128); `verifyObject(isolated, type, id)` (the `cat-file` |
  `hash-object --stdin` check). Rewrite `push-branch.ts` `checkCommitPresent` on it; export `disposeIsolated` from
  `push-branch.ts` (never throws, reports op `isolated-dir-dispose-failed`) and reuse it. `CENSUS_ONLY` row in
  `test/host-git-consumers-real-git.test.ts`.
- `server/approval/workspace-head.ts`: new export `readWorkspaceHeadRef(workspacePath)` -> `{ sha, refName | null }`
  sharing the existing reader's internals; `readWorkspaceHeadSha` unchanged (no return-type widening).
- `session-sync.ts`: `ALLOWED_GIT_SUBCOMMANDS` gains `update-ref` and `unpack-objects` with the exact-argv guards of
  step 0 (`--no-deref`, `validateBranchFormat` on `<D>`, 40-hex checks); any other argv for those verbs throws.
  `FORBIDDEN_GIT_FLAGS` still applies.
- Export `AGENT_AUTHOR_NAME` / `AGENT_AUTHOR_EMAIL` from `push-branch.ts` (no new module, R5).

### Phase 2 — Remote state, verify, build, guard, push

- `readRemoteState(url, isolated, installationId)` -> `{ defaultBranch, tip, sideTip | null }` from one hardened
  `ls-remote --symref` (step 2 parse rules).
- `buildKbOverlay(parent, kbSourceSha, { secondParent? })` (the ONLY commit builder) and `assertRootDiffersOnlyInKb`.
- `pushVerifiedKbOnly(...)` per Proposed Solution step 5: the ONLY push call site for this flow.
- `syncPush`: Proposed Solution steps 1-4. One `try/finally` around everything from `createIsolatedPushDir` on, with
  `disposeIsolated`. `updateLastSynced` and `recordKbSyncHistory` run only after a push succeeded (CPO condition C4).
- Every hardened-git failure is wrapped in a static-message `KbSyncError` with a closed `reason` (`ls_remote_failed`,
  `fetch_failed`, `push_rejected`, `push_transient`) and a stderr class only: never the raw `err.message`, which now
  embeds the literal URL, owner, repo and sha in argv.

### Phase 3 — Local branch update (P7)

- Step 4: the CAS-to-`S` arm, the `M` arm (`KB_SYNC_MERGE_MSG`), the object hand-off, `head_moved` /
  `ref_update_failed` / `unpack_failed`, the tracking ref after the push.

### Phase 4 — Protected-branch fallback (rulings F, R3, R4, R15, R17)

- Per Proposed Solution step 6. Delete `resolveDefaultBranchForFallback` and the workspace `checkout -f -B`,
  `checkout <defaultHead> -- knowledge-base`, `commit` and `reset --hard` calls.
- `kb-sync.protected-fallback-failed` / `kb-sync.push-protected-fallback` ops and their alert contract stay as they are
  (`test/sentry-kb-sync-protected-fallback-alert-op-contract.test.ts` stays green); a closed `fallback_reason` tag
  (`side_fetch_failed`, `side_hash_mismatch`, `side_guard_failed`, `side_push_rejected`, `pr_failed`) is added.

### Phase 5 — Self-heal gate (R18)

- `server/workspace-sync.ts` `selfHealNonFastForward` default-branch arm: `status --porcelain --untracked-files=no`
  through the existing injected `gitWithInstallationAuth`; any tracked path outside `knowledge-base/` -> op
  `self-heal-aborted-dirty-nonkb` (warning, `reportSilentFallback` family `kb-route-helpers` as its siblings), return
  `ERROR_CLASS_NON_FAST_FORWARD`. Test in a new `test/server/workspace-sync-self-heal-dirty-nonkb.test.ts` plus the
  real-git row of the battery.

### Phase 6 — Observability (R7)

- Op `kb-sync.push-held` (feature `session-sync`). Closed reason union exported from `kb-sync-publish.ts`:
  `merge_in_progress`, `detached_head`, `non_default_branch`, `remote_branch_absent`, `remote_unknown_tip`,
  `remote_ahead`, `hash_mismatch`, `kb_not_tree`, `guard_failed`, `head_moved`, `ref_update_failed`, `unpack_failed`,
  `side_ahead`, `held_foreign`, `synthetic_pushed`.
- Every outcome first logs unconditionally: `log.info({ op: "kb-sync.push-held", reason, outcome })` (pino -> Better
  Stack, per-turn counts; the debounce below would otherwise drop the pino line too).
- Warning level, through `mirrorWarnWithDebounce` keyed on the workspace id with `errorClass`
  `kb-sync-push-held:<reason>` and one static message per reason (distinct Sentry issues): `merge_in_progress`,
  `detached_head`, `non_default_branch`, `remote_branch_absent`, `hash_mismatch`, `kb_not_tree`, `guard_failed`,
  `head_moved`, `ref_update_failed`, `unpack_failed`, `side_ahead`. `tags` = `{ reason, outcome }`; `extra` =
  `{ userId }` (`hashExtraUserId` hashes it at the emit boundary). No paths, shas, URLs or branch names.
- Info only (the unconditional log line): `synthetic_pushed`, `held_foreign`, `remote_ahead`, `remote_unknown_tip`.
- The outer `syncPush` catch sets `tags: { reason: err instanceof KbSyncError ? err.reason : "unclassified" }` and
  keeps its static message.
- Add the `session-sync` family entry to the errorClass registry comment in `server/observability.ts`.

### Phase 7 — Records

- ADR-309 addendum "2026-11-12 (Ref #12600): the post-session sync push publishes only Soleur-built knowledge-base
  commits" after the 2026-11-11 addendum, plus a forward pointer at each of the three "#12600's path" mentions, located
  by their text (the #12197 one is an inline sentence inside the 2026-11-05 #11635 addendum, not a heading).
- ADR-068 addendum: (d)'s "GitHub tip is an ancestor of the local branch" holds after a sync push because the local
  branch is moved to `S` (or `M`) before the push.
- ADR-050: update the host-side git consumer entry for `session-sync` if it names the legacy push (locate by text).

## Files to Edit

- `apps/web-platform/server/session-sync.ts` — orchestration (steps 1-2), allowlist guards, `MERGE_HEAD` skip, outer
  catch `reason` tag; the push half moves out.
- `apps/web-platform/server/push-branch.ts` — export the identity constants and `disposeIsolated`;
  `checkCommitPresent` on `runIsolatedGitLocal`.
- `apps/web-platform/server/approval/workspace-head.ts` — `readWorkspaceHeadRef` export.
- `apps/web-platform/server/workspace-sync.ts` — `self-heal-aborted-dirty-nonkb` gate (R18).
- `apps/web-platform/server/observability.ts` — errorClass registry comment entry only.
- `apps/web-platform/test/server/session-sync-protected-fallback.test.ts` — trimmed to the op and alert-contract rows;
  `makeGitMock` follows the new call shapes (the `args.length === 1` main-push key is gone); behaviour rows move to the
  real-git battery (devex review item 6).
- `apps/web-platform/test/server/session-sync-sentry-mirror.test.ts` — push-throw arm follows the new call site; the
  `kb-sync.push-held` payload, the per-reason debounce, the outer-catch `reason` tag.
- `apps/web-platform/test/server/session-sync-workspace-last-synced.test.ts` — refused, held and `T == headSha` turns do
  not call `writeRepoColsToWorkspace`.
- `apps/web-platform/test/session-sync-path-allowlist.test.ts` — the `update-ref --no-deref` / `unpack-objects`
  exact-argv guards (every other argv throws) and the forbidden-flag rows.
- `apps/web-platform/test/host-git-consumers-real-git.test.ts` — `CENSUS_ONLY` row for `git-isolated-local.ts`;
  `syncPushDriver` keeps passing.
- `apps/web-platform/test/push-branch-isolated-real-git.test.ts` — stays green with `checkCommitPresent` on the runner.
- `knowledge-base/engineering/architecture/decisions/ADR-309-durable-action-bound-approval-requests.md` — addendum.
- `knowledge-base/engineering/architecture/decisions/ADR-068-multi-host-workspaces-shared-git-data-lease-coordinator.md`
  — addendum.
- `knowledge-base/engineering/architecture/decisions/ADR-050-likec4-runtime-rerender-via-out-of-process-cli.md` —
  consumer-list entry, only if it names the legacy push.

## Files to Create

- `apps/web-platform/server/kb-sync-publish.ts` — `readRemoteState`, `buildKbOverlay`, `assertRootDiffersOnlyInKb`,
  `pushVerifiedKbOnly`, the fallback, `KbSyncError`, the reason union.
- `apps/web-platform/server/git-isolated-local.ts` — `runIsolatedGitLocal`, `verifyObject`.
- `apps/web-platform/test/session-sync-kb-only-push-real-git.test.ts` — the effect-based battery (real git, bare
  `file://` remotes; it wraps the real `gitWithInstallationAuth` to rewrite only the literal fixture URL token, records
  every argv, widens `GIT_ALLOW_PROTOCOL` the way `push-branch-isolated-real-git.test.ts` does and, for rows that run
  `syncWorkspace` or the legacy arm, widens `hostGitInvocation`'s protocol the way `host-git-consumers-real-git.test.ts`
  does). Fixture helper sets `GIT_CONFIG_GLOBAL=/dev/null`, `GIT_CONFIG_NOSYSTEM=1` and increasing `GIT_COMMITTER_DATE`
  values; `beforeEach` calls `__resetMirrorDebounceForTests`; logs `git --version` once; explicit `vi.waitFor` timeouts.
- `apps/web-platform/test/server/workspace-sync-self-heal-dirty-nonkb.test.ts` — R18 unit rows.
- `apps/web-platform/test/server/classify-push-error.test.ts` — `GH006` line-anchoring (a `GH006` ref name in the
  status line and in `err.message` does not match), `GH013` stays `other`.

## Open Code-Review Overlap

None. Open `code-review` issues touching `agent-runner.ts` (#3242 tool_use name field, #3454 pdf_metadata tool) concern
other code in that file; this plan does not edit `agent-runner.ts`. No open code-review issue names `session-sync.ts`,
`workspace-sync.ts`, their tests or `host-git-consumers-real-git.test.ts`.

## User-Brand Impact

- **If this lands broken, the user experiences:**
  - The bug persists. An Owner's repository still receives a member's unapproved code commit at the end of a turn,
    possibly a workflow file that then runs in the Owner's CI.
  - Every workspace's knowledge-base stops reaching GitHub after each turn (a false refusal). The user sees only KB
    pages missing on GitHub. Settings' "last synced" time does NOT go stale, because `syncPull` stamps it on every
    session-start pull (C4 note below). The operator sees `kb-sync.push-held` events with `reason: guard_failed` or
    `hash_mismatch` on untampered workspaces, and Better Stack's `synthetic_pushed` count drops to zero.
  - The pre-push branch update breaks. After the next KB action or webhook, a member's commits move to a
    `soleur/recovered-kb-sync-*` branch (self-heal on a diverged clone; P7, matrix 14).
- **Who is affected by the behaviour change:** every legacy-runner user, Owners, members and solo founders alike
  (ruling E). An agent's code commits on the default branch used to reach GitHub after every turn. They now stay in
  the workspace until someone publishes them through `github_push_branch` (Owner approval).
- **Degradations the user can see on the day this ships (accepted, tracked):**
  - **Held code commits.** Nothing in the product says an agent's code commit was not published (#12714, CPO F1; its
    milestone is "Post-MVP / Later", Taste row T1). An agent that tells the user "committed and synced" is now wrong
    about the sync part.
  - **Local merge commits.** While code commits are held, each KB-changing turn adds one Soleur-authored merge commit
    (`KB_SYNC_MERGE_MSG`, "Soleur: merge knowledge-base sync") to the local branch. A later `github_push_branch` range
    therefore shows those merges and the already-published `S` commits next to the member's work. Without held code
    commits, history stays linear: the local branch is moved to `S`.
  - **Non-default branch.** A user whose agent works on a feature branch gets `non_default_branch` on every turn, and
    their KB edits never reach GitHub from that branch. Phase 0 step 4 records what they got before (the bare push from
    a single-branch clone with no upstream most likely failed already; unverified until measured). They will see their
    KB edits on GitHub only after switching back to the default branch.
  - **Delayed KB edits.** In the hold cases the Proposed Solution names, KB edits reach GitHub on a later turn or
    session, not the same turn.
  - **Mid-session stall.** When an upstream push lands while code commits are held and code files are dirty, the
    workspace stays un-synced until the next session start, instead of losing those edits (R18).
  - **Host move after the default branch moved upstream.** If code commits are held and the upstream default branch
    has moved, the ADR-068 overlay check fails on a host move. The held commits are then parked on its rescue branch
    and `git-data-overlay-not-descendant` fires. They are recoverable, but no longer on the branch.
- **If this leaks, the user's repository and workflow are exposed via:**
  - a commit an agent authored (any path, including `.github/workflows/*`, any message including `Fixes #N`) published
    to the connected repository with the GitHub App token and no Owner approval;
  - a synthetic commit that reverts a remote knowledge-base edit;
  - a member's uncommitted code edits erased by a self-heal `reset --hard`.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** one Owner receiving one unapproved member commit is a trust breach on its own
  (CTO ruling H); it does not need to aggregate to matter.

`requires_cpo_signoff: true`. CPO agent sign-off (2026-11-12): yes, with conditions C1-C5, all addressed (rulings I,
K, L; C4 below; C5 = #12714). Human CPO review is still owed before `soleur:work` ships, and it should look at the
"Who is affected" and "Degradations" bullets above. `soleur:engineering:review:user-impact-reviewer` runs at review
time.

CPO condition C4: the push path never stamps `repo_last_synced_at` on a refusal, because it returns before
`updateLastSynced`. `syncPull` still stamps it after every successful session-start pull; #12714 tracks that
pre-existing meaning.

## Observability

```yaml
liveness_signal:
  what: "layer 2 (pino -> Sentry via warnSilentFallback): Sentry event op kb-sync.push-held (feature session-sync), warning level, tags reason + outcome, one per workspace per reason per 5 minutes, for the anomaly reasons (merge_in_progress, detached_head, non_default_branch, remote_branch_absent, hash_mismatch, kb_not_tree, guard_failed, head_moved, ref_update_failed, unpack_failed, side_ahead); layer 1 (pino stdout -> Better Stack): one info line per outcome per turn, every reason"
  cadence: "per legacy-runner turn that has local commits; Sentry debounced 5 min per workspace per reason, Better Stack line every turn"
  alert_target: "Sentry issue stream for the web-platform project (warning level, no page); Better Stack web-platform source"
  configured_in: "apps/web-platform/server/kb-sync-publish.ts and apps/web-platform/server/session-sync.ts (log.info + mirrorWarnWithDebounce calls)"

error_reporting:
  destination: "layer 2: Sentry web-platform project via reportSilentFallback (SENTRY_DSN); existing op syncPush with a closed reason tag (KbSyncError) for tip-read, fetch, push and isolation failures; existing op kb-sync.protected-fallback-failed with a fallback_reason tag; new op self-heal-aborted-dirty-nonkb (workspace-sync); op isolated-dir-dispose-failed"
  fail_loud: "Sentry issue with tag op=syncPush, tag reason=<closed reason>, static message 'Sync push failed — next session will retry'; no URL, owner, repo or sha in the message"

failure_modes:
  - mode: "false refusal: every KB push held (builder or guard bug), KB stops reaching GitHub"
    detection: "layer 2: kb-sync.push-held reason:guard_failed or reason:hash_mismatch on a workspace with no tampering; layer 1: Better Stack count of synthetic_pushed drops to zero; CI: the battery's must-PASS rows"
    alert_route: "Sentry issue stream; CI red on the PR"
  - mode: "object tamper detected (forged object bytes)"
    detection: "layer 2: kb-sync.push-held reason:hash_mismatch"
    alert_route: "Sentry issue stream"
  - mode: "isolated GIT_DIR cannot be prepared (object store over 250000 entries, tamper shape) or cannot be disposed"
    detection: "layer 2: op syncPush with reason tag (isolation refusal); op isolated-dir-dispose-failed with an errno class tag"
    alert_route: "Sentry issue stream"
  - mode: "local branch update lost a race or failed (HEAD moved, ref lock, unpack failure)"
    detection: "layer 2: kb-sync.push-held reason:head_moved / ref_update_failed / unpack_failed"
    alert_route: "Sentry issue stream"
  - mode: "protected-branch fallback fails or refuses over unmerged side content"
    detection: "layer 2: existing op kb-sync.protected-fallback-failed with fallback_reason tag; kb-sync.push-held reason:side_ahead"
    alert_route: "existing sentry_alert kb_sync_protected_fallback_failed (email to issue owners); Sentry issue stream"
  - mode: "self-heal refused because a member has uncommitted code edits on a diverged clone"
    detection: "layer 2: op self-heal-aborted-dirty-nonkb (warning)"
    alert_route: "Sentry issue stream"
  - mode: "KB waits on expected holds (remote_ahead, remote_unknown_tip, held_foreign)"
    detection: "layer 1: Better Stack info lines op kb-sync.push-held with the reason; a persistent cause surfaces elsewhere (op syncPull error on a failed pull, merge_in_progress warning on a conflicted pull)"
    alert_route: "Better Stack search (no alert; expected outcomes)"
  - mode: "a non-KB commit reaches the remote (the bug)"
    detection: "CI: the real-git battery asserts the bare remote lacks the foreign commit object; no production signal can see a commit that was wrongly accepted, so the guard is pinned at CI time"
    alert_route: "CI red on the PR"

logs:
  where: "web-platform container stdout (pino, child logger session-sync), shipped to Better Stack"
  retention: "Better Stack plan retention for the web-platform source"

discoverability_test:
  command: "grep -o -m1 kb-sync.push-held apps/web-platform/server/kb-sync-publish.ts"
  expected_output: "kb-sync.push-held"
```

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-309 with an addendum (2026-11-12, Ref #12600): the post-session sync push is no longer an unapproved route for
agent commits. It pushes only a Soleur-built commit whose root tree is the hash-verified remote tip's with the
`knowledge-base` entry replaced, as an explicit sha refspec from the isolated GIT_DIR to the authoritative default
branch, after moving the local branch so the clone stays fast-forwardable; every agent commit stays in the workspace.
Forward pointers at the item 8 discharge note, the inline #12197 sentence and the workspace-settings note. Amend
ADR-068 (d) with the pre-push local-branch invariant. No new ADR: this extends ADR-309's push boundary (and item 9b's
isolated push) to the sync path.

### C4 views

Checked against `model.c4`, `views.c4`, `spec.c4` (repo-research pass, 2026-11-12): the actors, the GitHub external
system, the `engine -> github` "Git operations and CI" edge and the workspace volume element are already modelled; the
workspace volume description ("session-sync.ts autocommits only knowledge-base/**") stays true. No C4 edit (ruling R5):
the ADR addenda carry the change.

### Sequencing

Ships with this PR; no soak.

## Guard Contract

### Guard 1 — KB-only publish gate

**Property.** Every ref update `syncPush` sends (default branch or `soleur/kb-sync`) names a commit the server built,
whose root tree equals the hash-verified remote base's root tree in every entry except `knowledge-base`, whose message
and identity are Soleur's, and which never drops knowledge-base content the remote holds and the workspace never saw.

**Assembly.** The chokepoint is `pushVerifiedKbOnly` in `apps/web-platform/server/kb-sync-publish.ts`: every sync push
call site is there, and it re-runs `assertRootDiffersOnlyInKb` on the exact sha it pushes against its verified base.
Its only inputs are commits from `buildKbOverlay`, the single builder, whose root comes from `verifyObject`-checked
objects. A census row in the real-git battery asserts the argv-array regex `/\[\s*["']push["']/` matches exactly once
in `kb-sync-publish.ts` (inside `pushVerifiedKbOnly`) and zero times in `session-sync.ts`. Every base is read by
`readRemoteState` (never `@{u}` or `refs/remotes/*`). Every decision command runs in the isolated GIT_DIR through
`runIsolatedGitLocal` (ruling P); the workspace contributes objects (alternate), the validated shallow file, `headSha`
and the ref name only, and receives only `unpack-objects` and the `--no-deref` CAS `update-ref`.

**Mutation matrix:** every row asserts the remote's expected positive state (tip sha, parent, tree shape, author) as
well, so a mutation that fails closed reads RED, not green. Rows that are killed only by that positive state are
marked "positive-state".

| # | Mutation (to the design, before code exists) | Expected |
|---|---|---|
| 1 | Push `headSha` instead of `S`; fixture: a `.github/workflows/x.yml` commit plus a KB edit over `T` | RED: bare remote holds the foreign commit object |
| 2 | Skip `verifyObject` on `T`'s root tree; fixture plants T's-root bytes that add a non-KB entry pointing at a subtree already on the remote under another ref | RED: remote `D` gains the non-KB entry |
| 3 | Build `S`'s root from `headSha`'s root (not `T`'s); fixture: foreign commit + KB edit | RED: remote gains the non-KB change; `guard_failed` expected and absent |
| 4 | Remove `assertRootDiffersOnlyInKb` from `pushVerifiedKbOnly` and break `buildKbOverlay` to also copy one non-KB entry from `headSha` | RED (the in-builder guard is the only remaining defense; with both removed the leak reaches the remote) |
| 5 | Parent `S` on `headSha` instead of `T` | RED (positive-state): expected tip `S` with parent `T`; foreign object reaches the remote |
| 6 | Use `@{u}` (or `refs/remotes/origin/<b>`) as the base; fixture forges `refs/remotes/origin/main` | RED: wrong parent (positive-state) |
| 7 | Push through the legacy workspace arm (bare `push`, `cwd` = workspace); fixture sets `push.default=matching` and a second local branch holding a foreign commit | RED: remote gains the second branch |
| 8 | Read the push URL from `remote.origin.url`; fixture points it at a second bare remote | RED: the second remote receives a push (recorded argv names it) |
| 9 | Skip ruling I's ancestor check; fixture: a remote KB edit fetched into the workspace objects without merging, plus a local KB edit | RED: remote KB edit reverted |
| 10 | Side parent from `refs/remotes/origin/soleur/kb-sync` forged to a foreign commit; remote has no `soleur/kb-sync` | RED: remote `soleur/kb-sync` descends from the foreign commit |
| 11 | Drop the `-c user.*` argv | RED (positive-state): remote author/committer is not exactly "Soleur Agent" / `agent@soleur.ai` |
| 12 | Fallback keeps `checkout -f` / `reset --hard`; fixture: protected default, KB-only local edit, a dirty tracked non-KB file | RED: the dirty edit is gone |
| 13 | Fallback CAS-moves the local branch when non-KB changes are held | RED: the foreign commit is no longer on the local branch |
| 14 | Skip the pre-push local branch update (push `S`, leave the branch at `headSha`); then the row runs the real `syncWorkspace` against the bare remote | RED: the foreign commit is moved to a recovery branch (positive control: on correct code `syncWorkspace` returns `{ ok: true }`) |
| 15 | Drop the CAS old value; the 3-argument `refs/heads` shape is refused by the argv guard, so the row mutates the guard too; fixture's wrapper adds a local commit during `ls-remote` | RED: the new commit is no longer on the branch; `head_moved` expected |
| 16 | Remove ruling I's extension on the side range; fixture: side tip holds a KB file not in HEAD's history and the PR is not merged | RED: the side push deletes that file |
| 17 | Remove the `MERGE_HEAD` skip; fixture: a conflicted session-start merge with markers in a KB file | RED: remote gains a commit containing conflict markers |
| 18 | Target the checked-out branch instead of `D`; fixture: local branch `feature` that also exists on the remote | RED: remote `feature` moves; `non_default_branch` expected |
| 19 | Drop `--no-deref`; fixture swaps `refs/heads/<D>` to a symref to `refs/heads/x` after the HEAD read | RED: `refs/heads/x` moves |
| 20 | Single parent `P` on the side commit when `P` does not descend from `T` | RED: after the side push and a PR-merge simulation, `pull --ff-only` fails |
| 21 | Remove the R18 self-heal gate; fixture: held foreign commit + dirty tracked non-KB file, upstream `D` moves, real `syncWorkspace` | RED: the dirty edit is gone |
| 22 | Run the hash checks / build in the workspace (`runConnectedRepoGit`) instead of the isolated dir | no known fixture reds it under host-git hardening: defense-in-depth (ruling P), recorded, not claimed |

Unit (outside the battery): `classifyPushError` with `GH006` only in a ref name inside `err.message` / the stderr
status line -> `other` (the former 12g, which reds on correct code in a real-git fixture); `GH013` -> `other`.

**Harness rows:**

| # | Suite edit or input | Expected |
|---|---|---|
| H1 | must-PASS: KB-only local commit plus a session-start pull merge of an upstream code change | remote tip is `S` (parent `T`, tree == `headSha`'s tree, author "Soleur Agent"); local branch == `S` by CAS; tracking ref == `S`; `git status` unchanged |
| H2 | must-PASS: foreign commit + KB edit | remote tip is `S` (parent `T`, non-KB entries == `T`'s, KB entry == HEAD's); bare remote lacks the foreign object (`git cat-file -e` exits non-zero); local branch is `M` (parents `headSha`, `S`, message `KB_SYNC_MERGE_MSG`), still holds the foreign commit, `git status` unchanged |
| H3 | must-PASS: foreign commit, KB unchanged | remote tip unchanged; one info line `held_foreign`; no Sentry event |
| H4 | Suite edit: stub `syncPush` to a no-op | H1 and H2 go RED (they assert the remote tip moved) |
| H5 | Recorded-argv check: every hardened call names exactly `https://github.com/<o>/<r>.git` before the fixture rewrite | no network is reached; a different URL in any argv fails the row |
| H6 | must-PASS: the turn after a successful push, with no new commits | zero calls to `gitWithInstallationAuth` (no token minted), no history row |
| H7 | must-PASS: turn 2 after H2 adds another KB edit | remote tip is `S2` with parent `S`; local branch is `M2` |

**Anchor.** No stored value is compared; the guard reads the live remote state and hash-verified objects. Not
applicable beyond that statement.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "After a member's session, no commit other than Soleur's KB auto-commit reaches the remote without the Owner's approval, or the copy says it can." [issue #12600] | Proposed Solution 1-6; Phases 1-4; Guard 1 | mapped: only a Soleur-built KB commit is pushed (R14), which is stricter than the path reading considered at plan time |
| 2 | "A test pins the chosen behaviour." [issue #12600] | `test/session-sync-kb-only-push-real-git.test.ts`; Guard 1 matrix | mapped |
| 3 | "Technical forks (code-side refuse/skip of non-Soleur commits vs naming the sync in copy) are ruled by soleur:engineering:cto, never asked of the operator." [brief] | `decision-challenges.md` rows A-P, R1-R20 | mapped |
| 4 | "no production writes; do not touch or flip the approval-queue feature flag; no edits under docs/ or legal documents" [brief] | Files lists (no `docs/`, no `knowledge-base/legal/`, no flag code); copy follow-up #12713 | mapped |
| 5 | "if the CTO ruling would require Settings/legal copy changes, prefer the code-side fix and file the copy part as a follow-up" [brief] | Ruling A, G; #12713 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Server-built KB-only push (`kb-sync-publish.ts`) | asks 1-2 | asked |
| Hash verification of the objects the build reads | "no commit other than Soleur's KB auto-commit reaches the remote" (ask 1) | inferred — justification: CTO ruling R14: object bytes in the workspace are agent-forgeable (measured), so an unverified read is no guard |
| Pre-push local branch update (CAS to `S` or merge `M`) | ask 1 | inferred — justification: CTO rulings R1, R14: without it the reconcile webhook's self-heal destroys member work (P3, P7) |
| Protected-fallback hardening | ask 1 | inferred — justification: CTO rulings F, R3, R4, R15, R17: the fallback is a second unapproved route to the same remote |
| Authoritative default branch, `non_default_branch` | ask 1 | inferred — justification: CTO ruling R2: the push target must not be agent-chosen |
| Self-heal dirty-non-KB gate (`workspace-sync.ts`) | — | inferred — justification: CTO ruling R18: held foreign commits become the steady state, so without it this PR turns a rare dirty-edit loss into a per-upstream-push one |
| `git-isolated-local.ts` runner + census row | — | inferred — justification: CTO rulings P, R6, R20: decide where no agent-written config is read, without a token per local verb |
| `update-ref --no-deref` / `unpack-objects` allowlist guards, `readWorkspaceHeadRef` | — | inferred — justification: CTO rulings R1, R2, R12, R19 |
| `MERGE_HEAD` skip | — | inferred — justification: CTO ruling R11: the auto-commit would push conflict markers |
| `observability.ts` registry comment, `kb-sync.push-held` op, `KbSyncError` | — | inferred — justification: `hr-observability-as-plan-quality-gate` / `cq-silent-fallback-must-mirror-to-sentry`, R7; raw push errors now embed the repo URL and sha |
| ADR-309 / ADR-068 / ADR-050 addenda | — | inferred — justification: `wg-architecture-decision-is-a-plan-deliverable`, CTO rulings G, R5 |
| Edits to the existing syncPush test files, `classify-push-error.test.ts` | ask 2 | asked |
| `test/session-sync-kb-only-push-real-git.test.ts`, `workspace-sync-self-heal-dirty-nonkb.test.ts` | ask 2 | asked |

### Split Assessment

- Subsystems touched: 2 — `apps/web-platform`, `knowledge-base`
- Planned files: 22 | Estimated changed lines: ~850 (≈340 source, ≈450 tests, ≈60 records)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR, over the line threshold by design. CTO devex ruling R13: splitting the fallback out
  leaves the forged-ref route open between merges, the pre-push branch update is inseparable from the synthetic
  commit, and the self-heal gate (R18) must ship with the change that makes held commits the steady state. Review cost
  is handled with one commit per phase.

## Acceptance Criteria

<!-- founder-stated check: see plan-founder-check.md -->

- [ ] AC1 (issue acceptance 1): in the real-git battery, after `syncPush` on a workspace whose range over `T` holds a
  commit touching `.github/workflows/x.yml`, the bare remote does not contain that commit object
  (`git -C <bare> cat-file -e <sha>` exits non-zero), and its default-branch tip is either unchanged or a single commit
  whose parent is `T`, whose root entries other than `knowledge-base` equal `T`'s, and whose author and committer are
  "Soleur Agent" / `agent@soleur.ai`.
- [ ] AC2: every row of the Guard 1 mutation matrix (1-21) is a test that fails when the named mutation is applied
  locally (RED run recorded per phase commit in the PR body); rows killed only by the positive state count once with
  H2 (rows 5, 11); H1-H3, H5-H7 pass on the final code.
- [ ] AC3: the argv-array regex `/\[\s*["']push["']/` matches exactly once in `apps/web-platform/server/kb-sync-publish.ts`
  (inside `pushVerifiedKbOnly`) and zero times in `apps/web-platform/server/session-sync.ts`; the census row asserting
  this is in the battery.
- [ ] AC4: `rg -n '@\{u\}|refs/remotes/' apps/web-platform/server/kb-sync-publish.ts` shows only the tracking-ref
  `update-ref` target; `rg -n 'resolveDefaultBranchForFallback|checkKbOnlyRange|simplify-merges' apps/web-platform/server`
  returns nothing.
- [ ] AC5: the `kb-sync.push-held` payload carries tags `reason` + `outcome` and extra with the hashed user id only;
  two different reasons inside one 5-minute window both emit; every outcome writes its info line even inside the
  debounce window; the outer `syncPush` catch carries a closed `reason` tag and no URL or sha in its message (asserted
  in `session-sync-sentry-mirror.test.ts`).
- [ ] AC6: a refused, held or `T == headSha` turn does not call `writeRepoColsToWorkspace` (asserted in
  `session-sync-workspace-last-synced.test.ts`).
- [ ] AC7: in the real-git battery, no protected-fallback row leaves a dirty tracked non-KB file changed or a foreign
  commit off the local branch (matrix 12, 13), the side commit descends from `T` (matrix 20), and
  `session-sync-protected-fallback.test.ts` keeps its op and alert-contract rows green.
- [ ] AC8: `selfHealNonFastForward` refuses the reset with op `self-heal-aborted-dirty-nonkb` when a tracked non-KB file
  is dirty, and still recovers a clone whose only dirty files are under `knowledge-base/` (asserted in
  `workspace-sync-self-heal-dirty-nonkb.test.ts`; matrix 21);
  `test/server/workspace-sync-no-pre-self-heal-error-mirror.test.ts` and `test/kb-route-helpers.test.ts` stay green.
- [ ] AC9: ADR-309 carries the 2026-11-12 addendum and three forward pointers, ADR-068 carries its addendum; no
  `model.c4` change.
- [ ] AC10: no file under `docs/`, `knowledge-base/legal/` or the approval-queue flag code is in the diff
  (`git diff --name-only origin/main...HEAD`).
- [ ] AC11: `cd apps/web-platform && npx vitest run test/session-sync-kb-only-push-real-git.test.ts test/server/session-sync-protected-fallback.test.ts test/server/session-sync-sentry-mirror.test.ts test/server/session-sync-workspace-last-synced.test.ts test/session-sync-path-allowlist.test.ts test/host-git-consumers-real-git.test.ts test/push-branch-isolated-real-git.test.ts test/server/workspace-sync-self-heal-dirty-nonkb.test.ts test/server/workspace-sync-no-pre-self-heal-error-mirror.test.ts test/kb-route-helpers.test.ts test/server/classify-push-error.test.ts test/sentry-kb-sync-protected-fallback-alert-op-contract.test.ts` passes, and `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes.
- [ ] AC12: the PR body (written by `soleur:ship`) carries `Closes #12600`, links #12713, #12714, #12718, #12719 and
  #12734, quotes the Phase 0 measurements (`git --version` in the runner image and on CI, the hash-check and hand-off
  probes, `ls-remote --symref`, the fallback `fetch`, the non-default-branch "before" behaviour, the battery runtime),
  and states in plain words: "agent code commits on the default branch are no longer published by the end-of-turn
  sync; publish them through `github_push_branch` (Owner approval)" (CPO F5; a PR body is neither Settings nor legal
  copy).

## Domain Review

**Domains relevant:** Engineering, Product, Legal

### Engineering

**Status:** reviewed
**Assessment:** CTO agent ruled A-P at plan time, R1-R13 after the 7-agent plan review and R14-R20 at deepen-plan (see
`decision-challenges.md`). Final design: the sync pushes only a Soleur-built commit whose root is the hash-verified
remote tip's with the `knowledge-base` entry replaced (R14, after a measured object-forgery bypass of the history
walk); authoritative default branch and side tip from one hardened `ls-remote --symref`; everything decided and built
in the isolated GIT_DIR; local branch moved by a `--no-deref` CAS (to `S`, or to a merge `M` when code commits are
held) before the push; fallback side commit descending from `T`; self-heal refuses to erase dirty non-KB edits; push
half in `kb-sync-publish.ts`; per-reason observability. Residuals filed: #12718 (P1, pull on the legacy arm), #12719
(conflicted pull), #12734 (rulesets), #5221 comment (recovery and locking).

### Legal

**Status:** reviewed
**Assessment:** CLO agent: `PUSH_DISCLOSURE` is accurate after the fix (its approval promise is scoped to an
agent-requested push) but incomplete; drafted wording in #12713. No Art. 30 or compliance-posture change: the change
narrows an existing flow to the customer's own repository.

### Product/UX Gate

**Tier:** none (no UI surface in Files to Create or Files to Edit; the mechanical UI-surface override did not fire)
**Decision:** reviewed
**Agents invoked:** soleur:product:cpo (plan-time sign-off and plan-review named panel), user-impact-reviewer (deepen)
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

#### Findings

CPO agent: sign-off yes with conditions C1-C5. C1 (never undo a remote KB change) -> CTO ruling I, extended to the side
range by R4; C2 (no empty synthetic) -> ruling K; C3 (clear message and author) -> ruling L, now on every pushed commit
(R14); C4 (last-synced) -> User-Brand Impact note; C5 (Owner visibility of held commits) -> #12714. Plan-review F1
(#12714 milestone and audience) recorded as Taste row T1; F2, F4, F5 applied; F3 -> R4. Deepen user-impact findings
applied in User-Brand Impact; the self-heal regression -> R18.

## Test Scenarios

All in `apps/web-platform/test/session-sync-kb-only-push-real-git.test.ts` unless named; layer `integration` (real git,
local bare remotes, no network). Fixtures are synthesized (`cq-test-fixtures-synthesized-only`); workspaces are
`git clone --depth 1` of the bare remote so the shallow boundary matches production.

- Given a KB-only auto-commit over `T`, then H1 holds without the pull merge.
- Given a KB-only local commit and a session-start pull merge of an upstream code change, then H1 holds.
- Given a foreign commit plus a KB edit, then H2 holds and one info line `synthetic_pushed` is written.
- Given a foreign commit and no KB change, then H3 holds.
- Given H2, when the real `syncWorkspace` runs next (reconcile webhook shape), then `pull --ff-only` succeeds, no recovery branch is created and the dirty file is intact (P7; matrix 14).
- Given H2, when turn 2 adds another KB edit, then H7 holds; given a re-clone from the bare remote plus the git-data overlay check `merge-base --is-ancestor <remote tip> <local HEAD>`, then it exits 0 (ADR-068).
- Given forged bytes for `T`'s root tree (or commit, or `headSha`'s commit) in the workspace store, then nothing is pushed, `reason: hash_mismatch` (matrix 2).
- Given a remote KB edit made after the workspace's pull (fetched into objects, not merged) plus a local KB edit, then nothing is pushed and the info line says `remote_ahead` (matrix 9); given the remote tip object absent locally, then `remote_unknown_tip`.
- Given mutation rows 1-21, each fixture as named in the matrix, then the row's expected state holds.
- Given a detached HEAD, then nothing is pushed, `reason: detached_head`.
- Given a bare remote with no `HEAD`, then nothing is pushed, `reason: remote_branch_absent`.
- Given the turn after a successful push with no new commits, then H6 holds.
- Given a protected default branch (the bare remote's real `pre-receive` hook prints `remote: error: GH006: …` for pushes to it) and a KB-only local edit, then `soleur/kb-sync` receives a single-parent `side` on `T`, the PR helpers are called (helpers mocked), the local branch moves to `side` by CAS with `git status` unchanged, and the tracking ref is `side`; with a dirty tracked non-KB file, the file is unchanged (matrix 12).
- Given the same with an existing unmerged side tip built on an older `T` that is an ancestor of `headSha`, then `side` has parents `(P, T)` and `pull --ff-only` after a PR-merge simulation is a fast-forward (matrix 20).
- Given the same with a foreign commit present, then the local branch is `M`, keeps the foreign commit and its dirty non-KB files (matrix 13).
- Given a protected default and a side tip that holds unmerged KB content not in HEAD's history, then nothing is pushed, `reason: side_ahead` (matrix 16); given the PR merged (side KB entry == `T`'s), then the side commit is built.
- Given `<headSha>:knowledge-base` is a blob (a file named `knowledge-base` replaced the directory), then nothing is pushed, `reason: kb_not_tree`.
- Given `.git/MERGE_HEAD` present with conflict markers in a KB file, then no auto-commit and no push, `reason: merge_in_progress` (matrix 17).
- Given a held foreign commit and a dirty tracked non-KB file, when upstream `D` moves and the real `syncWorkspace` runs, then no `reset --hard` happens, op `self-heal-aborted-dirty-nonkb` fires and the dirty edit is intact (matrix 21).
- Given a `ls-remote` that throws, then the isolated dir is disposed (no directory left under its parent) and op `syncPush` fires with `reason: ls_remote_failed` and no URL in the message.
- Unit (`test/server/session-sync-sentry-mirror.test.ts`): AC5.
- Unit (`test/session-sync-path-allowlist.test.ts`): `update-ref --no-deref` / `unpack-objects` accept only the guarded argv shapes.
- Unit (`test/server/classify-push-error.test.ts`): `GH006` line-anchored; `GH013` -> `other`.
- Unit (`test/server/workspace-sync-self-heal-dirty-nonkb.test.ts`): AC8.
- Regression: `test/host-git-consumers-real-git.test.ts` carrier rows stay green; `test/push-branch-isolated-real-git.test.ts` stays green with `checkCommitPresent` on the runner.
