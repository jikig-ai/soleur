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
reaches the connected repository at the end of the turn. This plan narrows that push so it can only publish commits that
change `knowledge-base/` paths (or a Soleur-built commit carrying only the knowledge-base tree), keeps the workspace a
descendant of what it pushed so no other consumer of the clone sees a divergence, and pins the behaviour with tests.

Revised after the 7-agent plan review (2026-11-12): CTO rulings R1-R12 in `decision-challenges.md` replace the post-push
`reset --keep`, add the pre-push local merge, pin the target to the authoritative default branch, and move the push half
into `server/kb-sync-publish.ts`.

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
- P5. Soleur's own knowledge-base auto-commits keep reaching the remote in the normal case, including after a
  session-start pull merge of upstream changes.
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

### Plan-time measurements (scratch real-git probe, git 2.56.0; rerun in the runner image is Phase 0 step 1, ruling R10)

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
- `server/git-hardened-env.ts` (home of `buildIsolatedGitEnv`) is a leaf importing only `node:path`;
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
| "`hasLocalCommits` counts all of `@{u}..HEAD`" | True, and `@{u}` itself is agent-writable (`branch.<b>.merge`, `refs/remotes/origin/*`) | Analyse against the authoritative remote tip, never `@{u}`; keep `hasLocalCommits` only as a cheap skip (a forged "no commits" can only suppress a push) and keep it working by setting the tracking ref after a verified push (R8) |
| "Fix-Size: ~40 lines / 3 files (session-sync.ts commit filter, agent-runner call site, one test)" | A filter over `@{u}..HEAD` followed by a bare `git push` is bypassable through agent-written config (CTO ruling C); the protected fallback is a second unapproved route (ruling F); a synthetic commit without a local merge diverges the clone and triggers self-heal (R1) | ~900 lines over the files in `## Files to Edit` / `## Files to Create`; the agent-runner call site needs no change (the signature stays) |
| Option "refuse or skip when `@{u}..HEAD` holds any other commit" | Refusing alone stalls KB sync forever once an agent commits code on the default branch (CTO ruling D) | Synthetic KB-only commit merged into the local branch before the push (rulings D, I, R1), refusal otherwise |
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
(items A-P at plan time, R1-R12 after plan review). Notation: `D` = authoritative default branch, `T` = remote tip of
`D`, `headSha` = frozen local HEAD, `S` = Soleur-built KB-only commit, `M` = local merge of `headSha` and `S`.

0. **Where git runs (rulings P, R2, R6, R12).**
   - Workspace reads, no git process: `headSha` and the ref name through a new `readWorkspaceHeadRef` in
     `server/approval/workspace-head.ts` (sibling of `readWorkspaceHeadSha`); `.git/MERGE_HEAD` existence.
   - Workspace writes, exactly two verbs added to `ALLOWED_GIT_SUBCOMMANDS`, each behind an exact-argv guard:
     `["unpack-objects", "-q"]` (pack on stdin) and `update-ref` in two shapes only,
     `["update-ref", "refs/heads/<D>", <40hex new>, <40hex old>]` (CAS mandatory) and
     `["update-ref", "refs/remotes/origin/<D>", <40hex>]`. No `symbolic-ref`, `mktree` or `commit-tree` in the workspace.
   - Everything else (tip check, predicate, both commit builds, pack, fetch, push) runs in the server-created isolated
     GIT_DIR (`createIsolatedPushDir`: server-written config, workspace objects as a server-fixed alternate, validated
     shallow). Local verbs run token-free through `runIsolatedGitLocal` in the new `server/git-isolated-local.ts`;
     only `ls-remote`, `fetch` and `push` go through `gitWithInstallationAuth(…, { hardened })`.
   - The push half lives in the new `server/kb-sync-publish.ts`; `syncPush` orchestrates (R6).
1. **Pre-checks, in order.** `hasRemote`; `.git/MERGE_HEAD` present -> skip the auto-commit AND the push
   (`merge_in_progress`, R11; the auto-commit's `add` would otherwise commit conflict markers); auto-commit
   `knowledge-base/**` (unchanged); `hasLocalCommits` pre-token skip (unchanged); installation id;
   `readWorkspaceHeadRef` -> refuse `detached_head`.
2. **Authoritative remote state (rulings C, R2).** URL = literal `https://github.com/<owner>/<repo>.git` from
   `getCurrentRepoUrl(userId, workspaceId)` + `parseOwnerRepo`, never `remote.origin.url`. One hardened
   `ls-remote --symref <url> HEAD refs/heads/<b> refs/heads/soleur/kb-sync` gives `D`, `T` and the side tip; each ref
   is matched by exact name, one line each. Refuse `non_default_branch` when the local branch is not `D`;
   `remote_branch_absent` when `T` is absent (no empty-repo arm, R5). `T == headSha` -> set the tracking ref, return
   early: no push, no history row, no `updateLastSynced` (R8). `T` not present locally
   (`cat-file -e <T>^{commit}` in the isolated dir) -> `remote_unknown_tip` (a co-member pushed since the session's pull).
   `T` not an ancestor of `headSha` -> `remote_ahead` (ruling I).
3. **The predicate (ruling B, Guard 1).** Over `<T>..<headSha>`:
   `rev-list --count --full-history --simplify-merges <T>..<headSha> -- . ':(exclude)knowledge-base/'` == 0 AND
   `diff-tree -r --quiet <T> <headSha> -- . ':(exclude)knowledge-base/'` exits 0 (kept for git-version independence,
   R5). One helper, `checkKbOnlyRange(base, sha)` in `kb-sync-publish.ts`, owns the pathspec constant
   (`':(exclude)knowledge-base/'`); counts parse strictly (`/^\d+$/`); any non-numeric, NaN or thrown result is a
   refusal. Pass -> push `headSha` (fast path), then set the tracking ref to `headSha`.
4. **Non-KB commits in the range (rulings D, I, K, L, R1).**
   - KB trees of `T` and `headSha` equal -> nothing to sync: `held_foreign` (info), no push.
   - `<headSha>:knowledge-base` not a tree -> `kb_not_tree`.
   - Else, in the isolated dir: `S = buildKbOverlay(T, headSha)` (`ls-tree -z <T>` + `mktree -z` with the
     `knowledge-base` entry replaced by HEAD's, `commit-tree -p <T>`, message `KB_SYNC_SIDE_COMMIT_MSG`, identity via
     `-c user.name=<AGENT_AUTHOR_NAME> -c user.email=<AGENT_AUTHOR_EMAIL>`, constants exported from `push-branch.ts`);
     `M = commit-tree <headSha>^{tree} -p <headSha> -p <S>` (same identity).
   - Guard `S`: `checkKbOnlyRange(T, S)`.
   - **Before the push**: pack the new objects (`rev-list --objects <M> ^<headSha> ^<T>` | `pack-objects --stdout`),
     `unpack-objects -q` them into the workspace, then CAS `update-ref refs/heads/<D> <M> <headSha>`. CAS failure ->
     `head_moved`, nothing pushed. `M`'s tree is `headSha`'s, so the index and working tree do not change.
   - Push `S`; on success set the tracking ref to `S` (`synthetic_pushed`, info). A failed push leaves an unpushed `S`
     inside `M`: harmless, the next turn builds `S2` on `T` again.
   - Next turn: `T` (= `S`) is an ancestor of local HEAD, so the turn builds `S2` on `S` (no turn-2 stall). The member's
     commits stay on the local branch, unpushed; nothing is checked out, reset or deleted.
5. **One push chokepoint (R6).** `pushVerifiedKbOnly({ base, sha, ref, url, isolated, installationId })`, `ref` limited
   to `refs/heads/<D>` or `refs/heads/soleur/kb-sync`: requires `base` to be an ancestor of `sha` and
   `checkKbOnlyRange(base, sha)` to pass, then pushes `<sha>:<ref>` non-force, no lease, through the hardened arm.
   Ruling I's "T is an ancestor of headSha" gate stays in the caller, before `buildKbOverlay`. `classifyPushError`
   reads `stderr` only (R2: `err.message` embeds argv).
6. **Protected-branch fallback (rulings F, F2b as amended by R3, R4).** On a `GH006` reject of a verified push:
   - Side parent `P` = the side tip from step 2's `ls-remote`, or `T` when absent. When present and not in local
     objects, `fetch --depth 1 --no-tags <url> refs/heads/soleur/kb-sync` into the isolated dir (no FETCH_HEAD equality
     check, R5: a non-force push rejects a side tip that moved).
   - Ruling I extended (R4): build only when the side branch is absent, `P` is an ancestor of `headSha`, or
     `<P>:knowledge-base` equals `<T>:knowledge-base` (the PR merged); otherwise `side_ahead` (warning).
   - Skip when the KB trees of `P` and `headSha` are equal. `side = buildKbOverlay(P, headSha)`; push through
     `pushVerifiedKbOnly({ base: P, sha: side, ref: "refs/heads/soleur/kb-sync" })`; PR find/create unchanged, base `D`.
   - Delete the workspace `checkout -f -B`, overlay `checkout`, workspace `commit` and `reset --hard`. In the KB-only
     case only (step 3 passed) and only when `<side>^{tree}` equals `<headSha>^{tree}`: unpack the side objects and CAS
     `update-ref refs/heads/<D> <side> <headSha>` (R3; no reset, cannot race, touches neither index nor files);
     otherwise leave the workspace as it is (info). With non-KB commits present the workspace keeps `M` from step 4.
   - `resolveDefaultBranchForFallback` is deleted; `D` comes from step 2.
7. **All sessions (ruling E).** No role read: Owner and member sessions take the same path.
8. **Records (rulings G, R5).** ADR-309 addendum discharging the three "#12600's path" mentions (located by text); ADR-068
   addendum (the sync keeps "GitHub tip is an ancestor of the local branch" by merging `S` before the push); ADR-050
   consumer-list entry for `session-sync` updated if it names the legacy push. No `model.c4` edit (R5). No
   `PUSH_DISCLOSURE` edit (#12713).

## Technical Considerations

### Attack Surface Enumeration

Every way a commit an agent authored can reach the connected repository from the legacy runner, and what this plan does:

| Route | Owner-gated today? | After this plan |
|---|---|---|
| `github_push_branch` (agent asks) | yes, every queue state (#12567) | unchanged |
| Sandbox `git push` with egress off (session keeps repo credentials) | no, by design; disclosed by `PUSH_DISCLOSURE` | unchanged (disclosed) |
| `syncPush` main push (bare `git push`) | **no** | KB-only predicate over `<T>..<headSha>`, explicit sha refspec, hardened arm |
| `syncPush` main push steered by `push.default`, `remote.origin.push`, `branch.<b>.merge`, `remote.origin.url`, `url.*.insteadOf` | **no** | closed: literal URL and refspec from an isolated GIT_DIR that never reads workspace config |
| Forged `refs/remotes/origin/*` / `@{u}` as the analysis base | **no** | closed: the base is the `ls-remote` tip |
| Push target chosen by the agent's checked-out branch | **no** | closed: target is the authoritative `D`; another branch refuses `non_default_branch` (R2) |
| Protected fallback side-branch push to `soleur/kb-sync` | **no** (base is an agent-writable ref) | authoritative side tip + ruling I extended + predicate + explicit refspec |
| Fallback PR base from `refs/remotes/origin/HEAD` with a legacy-arm token | **no** | closed: `D` from the hardened `ls-remote --symref` (R2) |
| `classifyPushError` steered by a branch name containing `GH006` | n/a | closed: classify on `stderr` only (R2) |
| Synthetic commit carrying an agent-chosen identity | n/a | closed: `-c user.name` / `-c user.email` argv in the isolated GIT_DIR (rulings L, P) |
| Agent-authored KB-only commit on the fast path keeps the agent's own author identity | no | residual, accepted: a path property, not an identity one (Cut List; R1 rejected overlay-only) |
| History rewrites: replace refs, grafts, `commondir`, alternates | already closed by host-git hardening | unchanged; the decision runs in the isolated GIT_DIR (ruling P) |
| Fallback `checkout -f` + `reset --hard` destroying dirty non-KB edits and non-KB commits | pre-existing loss | closed: no `checkout -f`, no reset; CAS `update-ref` with equal trees only (R3) |
| Synthetic push diverging the clone, then `syncWorkspace` self-heal `reset --hard` (reconcile webhook on our own push) | n/a (new with D2) | closed: `M` merged locally before the push (R1) |
| Upstream moves while a foreign commit sits local, then self-heal `reset --hard` loses dirty non-KB edits | pre-existing | residual, tracked on #5221 (comment 2026-11-12) |
| Conflicted session-start pull, then auto-commit commits conflict markers | pre-existing | closed for the push: `merge_in_progress` skip (R11); pull-side abort is #12719 |
| Session-start `syncPull` token-bearing `pull` on the legacy arm reads workspace `url.*.insteadOf` / `http.*` | pre-existing | residual, P1 issue #12718 (R9) |
| Symlink planted in the object store between `createIsolatedPushDir`'s walk and `unpack-objects` | n/a | residual, accepted (ADR-309 9b class, R12) |
| Planted `.git/shallow` inside the range | n/a | fails closed (the commit becomes a root; measured) |
| Symlink or gitlink inside `knowledge-base/` | not gated | residual, accepted: a KB path, already staged by the auto-commit sweep today; no effect on CI or code |
| Owner force-push between the tip read and the push | n/a | residual, accepted (CTO ruling J) |
| Object-store swap after the isolated dir's check | ADR-309 9b residual | unchanged (object bytes only) |
| cc runner Bash push with the minted token | separate | #12668 |

### Performance

Turns with no local commits keep today's cost (`hasLocalCommits` runs before any token mint), and stay that way after a
push because the tracking ref is set to what was pushed (R8). A turn with local commits costs one `ls-remote` round
trip, the isolated-dir object walk (capped at `OBJECT_WALK_ENTRY_CAP`, 250 000 entries; over the cap is a refusal,
reported) and a few local plumbing calls. The real-git battery builds one template remote in `beforeAll` and copies it
per row; per-test timeout 30 s, as `push-branch-isolated-real-git.test.ts` does (estimate, not measured: 20-40 s total;
it runs on the normal webplat shards, not the mutations leg).

### NFR impacts

Security (integrity of the customer's repository) improves; availability of KB sync is unchanged on the normal path. KB
edits wait for a later turn or session only on `remote_ahead`, `remote_unknown_tip`, `side_ahead`, `head_moved` and
`merge_in_progress`.

## Implementation Phases

One commit per phase (devex review item 8), each with its RED runs recorded.

### Phase 0 — Measure, then write the failing tests (`cq-write-failing-tests-before`)

1. Build the `runner` stage of `apps/web-platform/Dockerfile` and rerun the scratch probe
   (`/tmp/claude-1000/-data-git-repositories-jikig-ai-soleur/4fed09e4-fd93-4c8b-8997-43367c6a07a8/scratchpad/probe3.sh`, copied
   into the work tree's test fixtures as a synthesized script) inside it; record `git --version` there and on CI
   (`ubuntu-latest`). Any row that differs from the 2.56.0 table is a P0 redesign (R10).
2. Measure on the hardened isolated arm against a `file://` bare remote (`GIT_ALLOW_PROTOCOL` widened exactly as
   `test/push-branch-isolated-real-git.test.ts` does): `ls-remote --symref <url> HEAD refs/heads/<b> refs/heads/soleur/kb-sync`
   and `fetch --depth 1 --no-tags <url> refs/heads/soleur/kb-sync` into a shallow isolated dir. Record both for the PR body.
3. Measure that `rev-list` / `diff-tree` with the exclude pathspec behave inside the isolated GIT_DIR on a
   `git clone --depth 1` fixture with the shallow boundary at `T`, and that a missing or malformed shallow makes the walk
   error (refusal), never pass.
4. Measure the `pack-objects --stdout` | `unpack-objects -q` hand-off into a workspace through `hostGitInvocation`
   (hooks off, `--no-replace-objects`), and that the CAS `update-ref` leaves `git status` clean.
5. Write `apps/web-platform/test/session-sync-kb-only-push-real-git.test.ts` (Test Scenarios below). All rows RED on
   the unmodified `syncPush` except the must-PASS rows.

### Phase 1 — Move, runner and reads

- Move `runProtectedFallback` and the push call into `server/kb-sync-publish.ts` with no behaviour change (own commit).
  Header comment states Guard 1's property.
- `server/git-isolated-local.ts`: `runIsolatedGitLocal(isolated, args, { input? })` = lazy `child_process`
  `execFile("git", [...HARDENED_GIT_ARGS, ...args])`, `cwd: isolated.gitDir`, `env: buildIsolatedGitEnv(isolated)`, a
  timeout, no credentials; exit codes surfaced (1 vs 128). Rewrite `push-branch.ts` `checkCommitPresent` on it. Its
  exec site gets a `CENSUS_ONLY` row in `test/host-git-consumers-real-git.test.ts`.
- `server/approval/workspace-head.ts`: new export `readWorkspaceHeadRef(workspacePath)` -> `{ sha, refName | null }`
  sharing the existing reader's internals; `readWorkspaceHeadSha` unchanged.
- `session-sync.ts`: `ALLOWED_GIT_SUBCOMMANDS` gains `update-ref` and `unpack-objects` with the exact-argv guards of
  step 0 (`validateBranchFormat` on `<D>`, 40-hex checks); any other argv for those verbs throws. `FORBIDDEN_GIT_FLAGS`
  still applies.
- Export `AGENT_AUTHOR_NAME` / `AGENT_AUTHOR_EMAIL` from `push-branch.ts` (no new module, R5).

### Phase 2 — Remote state, predicate and the explicit push

- `readRemoteState(url, branch, isolated, installationId)` -> `{ defaultBranch, tip | null, sideTip | null }` from one
  hardened `ls-remote --symref`; exact ref-name match, one line per ref; a malformed line or a network error throws a
  static-message error into the outer catch (op `syncPush`, tag `reason`).
- `checkKbOnlyRange(base, sha)` -> `{ ok: true } | { ok: false, reason, nonKbCommitCount }` (returns, does not throw).
- `pushVerifiedKbOnly(...)` per Proposed Solution step 5: the ONLY push call site in the server for this flow.
- `syncPush`: Proposed Solution steps 1-3. One `try/finally` around everything from `createIsolatedPushDir` on, so a
  token or `ls-remote` failure never leaks the isolated dir (spec-flow G7). `updateLastSynced` and
  `recordKbSyncHistory` run only after a push succeeded (CPO condition C4).

### Phase 3 — Synthetic commit and local merge

- `buildKbOverlay(parent, kbSourceSha)` per step 4 (the ONLY commit builder; the fallback reuses it); `M` build; pack
  and `unpack-objects`; CAS `update-ref`; push `S`; tracking ref.
- `head_moved` when the CAS fails (nothing pushed).

### Phase 4 — Protected-branch fallback (rulings F, F2b, R3, R4)

- Per Proposed Solution step 6. Delete `resolveDefaultBranchForFallback` and the workspace `checkout -f -B`,
  `checkout <defaultHead> -- knowledge-base`, `commit` and `reset --hard` calls.
- `kb-sync.protected-fallback-failed` / `kb-sync.push-protected-fallback` ops and their alert contract stay as they are
  (`test/sentry-kb-sync-protected-fallback-alert-op-contract.test.ts` stays green).

### Phase 5 — Observability (R7)

- Op `kb-sync.push-held` (feature `session-sync`). Closed reason union exported from `kb-sync-publish.ts`:
  `merge_in_progress`, `detached_head`, `non_default_branch`, `remote_branch_absent`, `remote_unknown_tip`,
  `remote_ahead`, `predicate_failed`, `kb_not_tree`, `head_moved`, `side_ahead`, `held_foreign`, `synthetic_pushed`.
- Warning level, through `mirrorWarnWithDebounce` keyed on the workspace id with `errorClass`
  `kb-sync-push-held:<reason>`: `merge_in_progress`, `detached_head`, `non_default_branch`, `remote_branch_absent`,
  `predicate_failed`, `kb_not_tree`, `head_moved`, `side_ahead`. `tags` = `{ reason, outcome }`; `extra` =
  `{ nonKbCommitCount, userId }` (`hashExtraUserId` hashes `userId` at the emit boundary). No paths, shas or branch
  names.
- Info level (pino `log.info` only, Better Stack): `synthetic_pushed`, `held_foreign`, `remote_ahead`,
  `remote_unknown_tip` (expected outcomes; a warning per turn would bury the anomalies).
- Isolation refusals (`createIsolatedPushDir` reasons) and tip-read failures throw a static-message error carrying a
  `reason` tag into the existing outer catch (op `syncPush`, error level).
- Add the `session-sync` family entry to the errorClass registry comment in `server/observability.ts`.

### Phase 6 — Records

- ADR-309 addendum "2026-11-12 (Ref #12600): the post-session sync push publishes only knowledge-base history" after
  the 2026-11-11 addendum, plus a forward pointer at each of the three "#12600's path" mentions, located by their text
  (the #12197 one is an inline sentence inside the 2026-11-05 #11635 addendum, not a heading).
- ADR-068 addendum: (d)'s "GitHub tip is an ancestor of the local branch" holds after a synthetic push because `M` is
  merged locally before the push.
- ADR-050: update the host-side git consumer entry for `session-sync` if it names the legacy push (locate by text).

## Files to Edit

- `apps/web-platform/server/session-sync.ts` — orchestration (steps 1-2), allowlist guards, `MERGE_HEAD` skip; the push
  half moves out.
- `apps/web-platform/server/push-branch.ts` — export the identity constants; `checkCommitPresent` on `runIsolatedGitLocal`.
- `apps/web-platform/server/approval/workspace-head.ts` — `readWorkspaceHeadRef` export.
- `apps/web-platform/server/observability.ts` — errorClass registry comment entry only.
- `apps/web-platform/test/server/session-sync-protected-fallback.test.ts` — trimmed to the op and alert-contract rows;
  `makeGitMock` follows the new call shapes (the `args.length === 1` main-push key is gone); behaviour rows move to the
  real-git battery (devex review item 6).
- `apps/web-platform/test/server/session-sync-sentry-mirror.test.ts` — push-throw arm follows the new call site; the
  `kb-sync.push-held` payload (tags `reason`/`outcome`, extra `nonKbCommitCount` + hashed user id only) and the
  per-reason debounce.
- `apps/web-platform/test/server/session-sync-workspace-last-synced.test.ts` — refused, held and `T == headSha` turns do
  not call `writeRepoColsToWorkspace`.
- `apps/web-platform/test/session-sync-path-allowlist.test.ts` — the `update-ref` / `unpack-objects` exact-argv guards
  (every other argv throws) and the forbidden-flag rows.
- `apps/web-platform/test/host-git-consumers-real-git.test.ts` — `CENSUS_ONLY` row for `git-isolated-local.ts`;
  `syncPushDriver` keeps passing.
- `apps/web-platform/test/push-branch-isolated-real-git.test.ts` — stays green with `checkCommitPresent` on the runner.
- `knowledge-base/engineering/architecture/decisions/ADR-309-durable-action-bound-approval-requests.md` — addendum.
- `knowledge-base/engineering/architecture/decisions/ADR-068-multi-host-workspaces-shared-git-data-lease-coordinator.md`
  — addendum.
- `knowledge-base/engineering/architecture/decisions/ADR-050-likec4-runtime-rerender-via-out-of-process-cli.md` —
  consumer-list entry, only if it names the legacy push.

## Files to Create

- `apps/web-platform/server/kb-sync-publish.ts` — `readRemoteState`, `checkKbOnlyRange`, `buildKbOverlay`,
  `pushVerifiedKbOnly`, the fallback, the reason union.
- `apps/web-platform/server/git-isolated-local.ts` — `runIsolatedGitLocal`.
- `apps/web-platform/test/session-sync-kb-only-push-real-git.test.ts` — the effect-based battery (real git, bare
  `file://` remotes; it wraps the real `gitWithInstallationAuth` to rewrite only the literal fixture URL token and widens
  `GIT_ALLOW_PROTOCOL` the way `push-branch-isolated-real-git.test.ts` does). Fixture helper sets
  `GIT_CONFIG_GLOBAL=/dev/null`, `GIT_CONFIG_NOSYSTEM=1` and increasing `GIT_COMMITTER_DATE` values; `beforeEach` calls
  `__resetMirrorDebounceForTests`; logs `git --version` once.

## Open Code-Review Overlap

None. Open `code-review` issues touching `agent-runner.ts` (#3242 tool_use name field, #3454 pdf_metadata tool) concern
other code in that file; this plan does not edit `agent-runner.ts`. No open code-review issue names `session-sync.ts`,
its tests or `host-git-consumers-real-git.test.ts`.

## User-Brand Impact

- **If this lands broken, the user experiences:** either an Owner's repository still receives a member's unapproved code
  commit at the end of a turn (the bug persists, possibly with a workflow file that runs in the Owner's CI), or every
  workspace's knowledge-base stops reaching GitHub after each turn (a false refusal). The user sees only KB pages
  missing on GitHub: Settings' "last synced" time does NOT go stale, because `syncPull` stamps it on every session-start
  pull (C4 note below). The operator sees `kb-sync.push-held` events with `reason: predicate_failed` and
  `nonKbCommitCount: 0`. Or, if the pre-push merge breaks, a member's uncommitted code edits vanish and their commits
  move to a `soleur/recovered-kb-sync-*` branch after the next KB action or webhook (self-heal on a diverged clone; P7,
  matrix 12d).
- **Degradations the user can see on the day this ships (accepted, tracked):** an agent's code commit on the default
  branch is no longer published by the end-of-turn sync and nothing in the product says so (#12714, CPO F1); KB edits
  made after a held turn reach GitHub on a later turn or session, not the same turn, in the cases the Proposed Solution
  names.
- **If this leaks, the user's repository and workflow are exposed via:** a commit an agent authored (any path, including
  `.github/workflows/*`) published to the connected repository with the GitHub App token and no Owner approval; or a
  synthetic commit that reverts a remote knowledge-base edit.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** one Owner receiving one unapproved member commit is a trust breach on its own
  (CTO ruling H); it does not need to aggregate to matter.

`requires_cpo_signoff: true`. CPO agent sign-off (2026-11-12): yes with conditions C1-C5, all addressed (rulings I, K, L;
C4 below; C5 = #12714). Human CPO review is still owed before `soleur:work` ships. `soleur:engineering:review:user-impact-reviewer`
runs at review time.

CPO condition C4: the push path never stamps `repo_last_synced_at` on a refusal (it returns before `updateLastSynced`).
`syncPull` still stamps it after every successful session-start pull; that pre-existing meaning is tracked in #12714.

## Observability

```yaml
liveness_signal:
  what: "Sentry event op kb-sync.push-held (feature session-sync), warning level, tags reason + outcome, one per workspace per reason per 5 minutes, for the anomaly reasons (merge_in_progress, detached_head, non_default_branch, remote_branch_absent, predicate_failed, kb_not_tree, head_moved, side_ahead); expected outcomes (synthetic_pushed, held_foreign, remote_ahead, remote_unknown_tip) log at info to Better Stack"
  cadence: "per legacy-runner turn that has local commits, debounced 5 min per workspace per reason"
  alert_target: "Sentry issue stream for the web-platform project (warning level, no page)"
  configured_in: "apps/web-platform/server/kb-sync-publish.ts and apps/web-platform/server/session-sync.ts (mirrorWarnWithDebounce calls)"

error_reporting:
  destination: "Sentry web-platform project via reportSilentFallback (SENTRY_DSN); existing op syncPush for tip-read and isolation failures (with a reason tag), existing op kb-sync.protected-fallback-failed for the fallback"
  fail_loud: "Sentry issue with tag op=syncPush and message 'Sync push failed — next session will retry' carrying a static reason tag (isolation refusal, tip read failure)"

failure_modes:
  - mode: "false refusal: KB-only range refused (predicate bug), KB stops reaching GitHub"
    detection: "kb-sync.push-held events with tag reason:predicate_failed and extra nonKbCommitCount 0; the real-git battery's must-PASS rows in CI"
    alert_route: "Sentry issue stream; CI red on the PR"
  - mode: "isolated GIT_DIR cannot be prepared (object store over 250000 entries, tamper shape)"
    detection: "op syncPush error event with the static isolation reason tag"
    alert_route: "Sentry issue stream"
  - mode: "local merge CAS lost a race (HEAD moved during the sync)"
    detection: "kb-sync.push-held reason:head_moved"
    alert_route: "Sentry issue stream"
  - mode: "protected-branch fallback fails or refuses over unmerged side content"
    detection: "existing op kb-sync.protected-fallback-failed; kb-sync.push-held reason:side_ahead"
    alert_route: "existing sentry_alert kb_sync_protected_fallback_failed (email to issue owners); Sentry issue stream"
  - mode: "a non-KB commit reaches the remote (the bug)"
    detection: "the real-git battery asserts the bare remote lacks the foreign commit object; no production signal can see a commit that was wrongly accepted, so the guard is pinned at CI time"
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
agent commits; it publishes only knowledge-base-confined history verified against the authoritative remote tip, or a
Soleur-built KB-only commit merged into the local branch first, pushes an explicit sha refspec from the isolated GIT_DIR
to the authoritative default branch, and holds every other commit in the workspace. Forward pointers at the item 8
discharge note, the inline #12197 sentence and the workspace-settings note. Amend ADR-068 (d) with the pre-push merge
invariant. No new ADR: this extends ADR-309's push boundary (and item 9b's isolated push) to the sync path.

### C4 views

Checked against `model.c4`, `views.c4`, `spec.c4` (repo-research pass, 2026-11-12): the actors, the GitHub external
system, the `engine -> github` "Git operations and CI" edge and the workspace volume element are already modelled; the
workspace volume description ("session-sync.ts autocommits only knowledge-base/**") stays true. No C4 edit (CTO ruling
R5): the ADR addenda carry the change.

### Sequencing

Ships with this PR; no soak.

## Guard Contract

### Guard 1 — KB-only publish gate

**Property.** No ref update `syncPush` sends (default branch, synthetic commit or `soleur/kb-sync` side branch) adds to
the remote a commit that changes a path outside `knowledge-base/` relative to its base, a head whose non-KB tree differs
from the base's, or a tree that drops knowledge-base content the remote holds and the workspace never saw.

**Assembly.** The chokepoint is `pushVerifiedKbOnly` in `apps/web-platform/server/kb-sync-publish.ts`: every sync push
call site is there, and it runs the ancestry check and `checkKbOnlyRange` on the exact sha it pushes. Three callers flow
through it: the fast-path push, the synthetic-commit push and the protected-fallback side push. A census row in the
real-git battery asserts the argv-array regex `/\[\s*["']push["']/` matches exactly once in `kb-sync-publish.ts`
(inside `pushVerifiedKbOnly`) and zero times in `session-sync.ts`. Every base is read by `readRemoteState` (never `@{u}`
or `refs/remotes/*`). Every predicate and build command runs in the isolated GIT_DIR through `runIsolatedGitLocal`
(ruling P); the workspace contributes objects (alternate), the validated shallow file, `headSha` and the ref name only,
and receives only `unpack-objects` and the CAS `update-ref`.

**Mutation matrix:** every row asserts the remote's expected positive state too (tip sha and shape), so a mutation that
fails closed reads RED, not green.

| # | Mutation (to the design, before code exists) | Expected |
|---|---|---|
| 1 | Remove the `checkKbOnlyRange` call before the fast push; fixture: one `.github/workflows/x.yml` commit plus a KB edit over `T` | RED: bare remote holds the foreign commit object |
| 2 | `checkKbOnlyRange` parses the count with `parseInt` and treats a throw as 0; fixture's runner wrapper returns empty stdout for the count | RED: push happens; the row expects `predicate_failed` and no push |
| 3 | Check only `--max-count=1`; fixture: a foreign commit, then a KB-only commit | RED |
| 4 | Drop `--full-history`; fixture: add then delete a non-KB file, then a pull merge of upstream | RED (measured: default flags count 0) |
| 5 | Drop the trailing slash from the exclude pathspec; fixture: a top-level FILE named `knowledge-base` | RED (measured): remote gains the blob commit |
| 6 | Use `@{u}` (or `refs/remotes/origin/<b>`) as the base; fixture forges `refs/remotes/origin/main` and the upstream to a local foreign commit | RED |
| 7 | Push through the legacy workspace arm (bare `push`, `cwd` = workspace); fixture sets `push.default=matching` and a second local branch holding a foreign commit | RED: remote gains the second branch |
| 8 | Re-read the workspace HEAD after `ls-remote` instead of the frozen sha; fixture's wrapped `gitWithInstallationAuth` commits a foreign commit in the workspace during the `ls-remote` call | RED |
| 9 | Synthetic `S` parented on `headSha` instead of `T` | RED: expected tip `S` with parent `T` absent (the guard refuses; positive assertion fails) |
| 10 | Skip ruling I's ancestor check; fixture: a remote KB edit fetched into the workspace objects without merging, plus a local foreign commit | RED: remote KB edit reverted |
| 11 | Side parent from `refs/remotes/origin/soleur/kb-sync` forged to a foreign commit | RED |
| 12 | Drop the `-c user.*` argv; fixture runs with a host identity "Fixture Host" in the allowed env | RED: remote commit author is not "Soleur Agent" (or the build fails and the positive assertion fails) |
| 12a | Run the predicate in the workspace (`runConnectedRepoGit`) instead of the isolated dir | no known fixture reds it under host-git hardening: defense-in-depth (ruling P), recorded, not claimed |
| 12b | Fallback keeps `checkout -f` / `reset --hard`; fixture: protected default, KB-only range, a dirty tracked non-KB file | RED: the dirty edit is gone |
| 12c | Fallback moves the local branch when foreign commits are present | RED: the foreign commit is no longer on the local branch |
| 12d | Skip the pre-push local merge (push `S`, leave the branch at `headSha`); then the row runs the real `syncWorkspace` against the bare remote | RED: the foreign commit is moved to a recovery branch and the dirty file is lost (P7) |
| 12e | `update-ref` without the CAS old value; fixture's wrapper adds a local commit during `ls-remote` | RED: the new commit is no longer on the branch; the row expects `head_moved` and no push |
| 12f | Remove ruling I's extension on the side range; fixture: side tip holds a KB file not in HEAD's history and the PR is not merged | RED: the side push deletes that file |
| 12g | `classifyPushError` reads `err.message`; fixture: remote default branch named `GH006`, push rejected non-fast-forward | RED: remote gains `soleur/kb-sync` |
| 12h | Remove the `MERGE_HEAD` skip; fixture: a conflicted session-start merge with markers in a KB file | RED: remote gains a commit containing conflict markers |
| 12i | Target the checked-out branch instead of `D`; fixture: local branch `feature` that also exists on the remote | RED: remote `feature` moves; the row expects `non_default_branch` |
| 13 | Remove the `diff-tree` net-tree check | no known fixture reds it alone (the walk counts every measured case): kept for git-version independence (R5), recorded, not claimed |

**Harness rows:**

| # | Suite edit or input | Expected |
|---|---|---|
| H1 | must-PASS: KB-only local commit plus a session-start pull merge of an upstream code change | remote tip == local `headSha`; tracking ref == `headSha` |
| H2 | must-PASS: foreign commit + KB edit | remote tip is `S` (parent `T`, non-KB tree == `T`'s, KB tree == HEAD's, author "Soleur Agent"); bare remote lacks the foreign object (`git cat-file -e` exits non-zero); local branch is `M` (parents `headSha`, `S`), still holds the foreign commit, `git status` clean |
| H3 | must-PASS: foreign commit, KB unchanged | remote tip unchanged; one info log `held_foreign`; no Sentry event |
| H4 | Suite edit: stub `syncPush` to a no-op | H1 and H2 go RED (they assert the remote tip moved) |
| H5 | Suite edit: drop the URL-rewrite wrapper so the push targets the real literal URL | every push row fails closed on protocol, not green |
| H6 | must-PASS: the turn after a successful push, with no new commits | zero calls to `gitWithInstallationAuth` (no token minted), no history row |
| H7 | must-PASS: turn 2 after H2 adds another KB edit | remote tip is `S2` with parent `S`; local branch is `M2` |

**Anchor.** No stored value is compared; the guard reads the live remote state and the commit graph. Not applicable
beyond that statement.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "After a member's session, no commit other than Soleur's KB auto-commit reaches the remote without the Owner's approval, or the copy says it can." [issue #12600] | Proposed Solution 1-6; Phases 1-4; Guard 1 | reinterpreted (path-scoped): "Soleur's KB auto-commit" is read as "any commit that changes only `knowledge-base/`", because a commit message or author is forgeable (Cut List). An agent-authored KB-only commit still reaches the remote with its own author (Attack Surface residual) |
| 2 | "A test pins the chosen behaviour." [issue #12600] | `test/session-sync-kb-only-push-real-git.test.ts`; Guard 1 matrix | mapped |
| 3 | "Technical forks (code-side refuse/skip of non-Soleur commits vs naming the sync in copy) are ruled by soleur:engineering:cto, never asked of the operator." [brief] | `decision-challenges.md` rows A-P, R1-R12 | mapped |
| 4 | "no production writes; do not touch or flip the approval-queue feature flag; no edits under docs/ or legal documents" [brief] | Files lists (no `docs/`, no `knowledge-base/legal/`, no flag code); copy follow-up #12713 | mapped |
| 5 | "if the CTO ruling would require Settings/legal copy changes, prefer the code-side fix and file the copy part as a follow-up" [brief] | Ruling A, G; #12713 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Predicate + explicit push (`kb-sync-publish.ts`) | asks 1-2 | asked |
| Synthetic KB-only commit + pre-push local merge | "no commit other than Soleur's KB auto-commit reaches the remote" (ask 1) | inferred — justification: CTO rulings D, R1: refusal alone stalls KB sync (P5); without the merge the clone diverges and self-heal destroys work (P3, P7) |
| Protected-fallback hardening | ask 1 | inferred — justification: CTO rulings F, R3, R4: the fallback is a second unapproved route to the same remote |
| Authoritative default branch, `non_default_branch` | ask 1 | inferred — justification: CTO ruling R2: the push target must not be agent-chosen |
| `git-isolated-local.ts` runner + census row | — | inferred — justification: CTO rulings P, R6: decide where no agent-written config is read, without a token per local verb |
| `update-ref` / `unpack-objects` allowlist guards, `readWorkspaceHeadRef` | — | inferred — justification: CTO rulings R1, R2, R12 |
| `MERGE_HEAD` skip | — | inferred — justification: CTO ruling R11: the auto-commit would push conflict markers |
| `observability.ts` registry comment, `kb-sync.push-held` op | — | inferred — justification: `hr-observability-as-plan-quality-gate` / `cq-silent-fallback-must-mirror-to-sentry`, R7 |
| ADR-309 / ADR-068 / ADR-050 addenda | — | inferred — justification: `wg-architecture-decision-is-a-plan-deliverable`, CTO rulings G, R5 |
| Edits to the existing syncPush test files | ask 2 | asked |
| `test/session-sync-kb-only-push-real-git.test.ts` | ask 2 | asked |

### Split Assessment

- Subsystems touched: 2 — `apps/web-platform`, `knowledge-base`
- Planned files: 18 | Estimated changed lines: ~900 (≈380 source, ≈460 tests, ≈60 records)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR, over the line threshold by design. CTO devex ruling (plan review item 8): splitting the
  fallback out leaves the forged-ref route open between merges, and the pre-push merge is inseparable from the
  synthetic commit. Review cost is handled with one commit per phase.

## Acceptance Criteria

<!-- founder-stated check: see plan-founder-check.md -->

- [ ] AC1 (issue acceptance 1): in the real-git battery, after `syncPush` on a workspace whose range over `T` holds a
  commit touching `.github/workflows/x.yml`, the bare remote does not contain that commit object
  (`git -C <bare> cat-file -e <sha>` exits non-zero) and its default-branch tip is either unchanged or a single commit
  whose parent is `T` and whose non-KB tree equals `T`'s.
- [ ] AC2: every row of the Guard 1 mutation matrix (1-12i, except 12a and 13) is a test that fails when the named
  mutation is applied locally (RED run recorded per phase commit in the PR body), and H1-H3, H6, H7 pass on the final
  code.
- [ ] AC3: the argv-array regex `/\[\s*["']push["']/` matches exactly once in `apps/web-platform/server/kb-sync-publish.ts`
  (inside `pushVerifiedKbOnly`) and zero times in `apps/web-platform/server/session-sync.ts`; the census row asserting
  this is in the battery.
- [ ] AC4: `rg -n '@\{u\}|refs/remotes/' apps/web-platform/server/kb-sync-publish.ts` shows only the tracking-ref
  `update-ref` target, and `rg -n 'resolveDefaultBranchForFallback' apps/web-platform/server` returns nothing.
- [ ] AC5: the `kb-sync.push-held` payload carries tags `reason` + `outcome` and extra `nonKbCommitCount` + the hashed
  user id only, and two different reasons inside one 5-minute window both emit (asserted in
  `session-sync-sentry-mirror.test.ts`).
- [ ] AC6: a refused, held or `T == headSha` turn does not call `writeRepoColsToWorkspace` (asserted in
  `session-sync-workspace-last-synced.test.ts`).
- [ ] AC7: in the real-git battery, no protected-fallback row leaves a dirty tracked non-KB file changed or a foreign
  commit off the local branch (matrix 12b, 12c), and `session-sync-protected-fallback.test.ts` keeps its op and
  alert-contract rows green.
- [ ] AC8: ADR-309 carries the 2026-11-12 addendum and three forward pointers, ADR-068 carries its addendum; no
  `model.c4` change.
- [ ] AC9: no file under `docs/`, `knowledge-base/legal/` or the approval-queue flag code is in the diff
  (`git diff --name-only origin/main...HEAD`).
- [ ] AC10: `cd apps/web-platform && npx vitest run test/session-sync-kb-only-push-real-git.test.ts test/server/session-sync-protected-fallback.test.ts test/server/session-sync-sentry-mirror.test.ts test/server/session-sync-workspace-last-synced.test.ts test/session-sync-path-allowlist.test.ts test/host-git-consumers-real-git.test.ts test/push-branch-isolated-real-git.test.ts` passes, and `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes.
- [ ] AC11: the PR body (written by `soleur:ship`) carries `Closes #12600`, links #12713, #12714, #12718 and #12719,
  quotes the Phase 0 measurements (`git --version` in the runner image and on CI, `ls-remote --symref`, the fallback
  `fetch`), and states in plain words: "agent code commits on the default branch are no longer published by the
  end-of-turn sync; publish them through `github_push_branch` (Owner approval)" (CPO F5; a PR body is neither Settings
  nor legal copy).

## Domain Review

**Domains relevant:** Engineering, Product, Legal

### Engineering

**Status:** reviewed
**Assessment:** CTO agent ruled items A-P at plan time and R1-R12 after the 7-agent plan review (see
`decision-challenges.md`): code-side fix; path predicate with `--full-history --simplify-merges` plus net-tree equality;
authoritative default branch, tip and side tip from one hardened `ls-remote --symref`; everything decided and built in
the isolated GIT_DIR; synthetic KB-only commit only when the tip is an ancestor of HEAD, merged into the local branch
with a CAS `update-ref` before the push; fallback rebuilt on the same builder with no checkout or reset (CAS
`update-ref` with equal trees in the KB-only case) and ruling I extended to the side range; push half in
`kb-sync-publish.ts`; per-reason observability; ADR-309 and ADR-068 addenda. Residuals filed: #12718 (P1, pull on the
legacy arm), #12719 (conflicted pull), #5221 comment (self-heal on upstream moves).

### Legal

**Status:** reviewed
**Assessment:** CLO agent: `PUSH_DISCLOSURE` is accurate after the fix (its approval promise is scoped to an
agent-requested push) but incomplete; drafted wording in #12713. No Art. 30 or compliance-posture change: the change
narrows an existing flow to the customer's own repository.

### Product/UX Gate

**Tier:** none (no UI surface in Files to Create or Files to Edit; the mechanical UI-surface override did not fire)
**Decision:** reviewed
**Agents invoked:** soleur:product:cpo (plan-time sign-off and plan-review named panel)
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

#### Findings

CPO agent: sign-off yes with conditions C1-C5. C1 (never undo a remote KB change) -> CTO ruling I, extended to the side
range by R4; C2 (no empty synthetic) -> ruling K; C3 (clear message and author) -> ruling L; C4 (last-synced) ->
User-Brand Impact note; C5 (Owner visibility of held commits) -> #12714. Plan-review findings F1 (#12714 milestone and
audience) recorded as a Taste row in `decision-challenges.md`; F2, F4, F5 applied; F3 -> R4.

## Test Scenarios

All in `apps/web-platform/test/session-sync-kb-only-push-real-git.test.ts` unless named; layer `integration` (real git,
local bare remotes, no network). Fixtures are synthesized (`cq-test-fixtures-synthesized-only`); workspaces are
`git clone --depth 1` of the bare remote so the shallow boundary matches production.

- Given a KB-only auto-commit over `T`, when `syncPush` runs, then the remote tip and the tracking ref equal `headSha` (H1 variant without merge).
- Given a KB-only local commit and a session-start pull merge of an upstream code change, then the remote tip equals `headSha` (H1).
- Given a foreign commit plus a KB edit, then H2 holds and one info log `synthetic_pushed` is written.
- Given a foreign commit and no KB change, then H3 holds.
- Given H2, when the real `syncWorkspace` runs next (reconcile webhook shape), then `pull --ff-only` succeeds, no recovery branch is created and the dirty file is intact (P7; matrix 12d).
- Given H2, when turn 2 adds another KB edit, then H7 holds; given a re-clone from the bare remote plus the git-data overlay check `merge-base --is-ancestor <remote tip> <local HEAD>`, then it exits 0 (ADR-068).
- Given a remote KB edit made after the workspace's pull (fetched into objects, not merged) plus a local foreign commit, then nothing is pushed and the info log says `remote_ahead` (matrix 10); given the remote tip object absent locally, then `remote_unknown_tip`.
- Given mutation rows 1-12i, each fixture as named in the matrix, then the row's expected state holds.
- Given a detached HEAD, then nothing is pushed, `reason: detached_head`.
- Given a remote with no `refs/heads/<D>`, then nothing is pushed, `reason: remote_branch_absent`.
- Given the turn after a successful push with no new commits, then H6 holds.
- Given a protected default branch (the bare remote's `pre-receive` hook rejects pushes to it with a `GH006` line) and a KB-only range, then `soleur/kb-sync` receives a predicate-verified commit, the PR helpers are called (helpers mocked), and the local branch moves to the side commit by CAS with `git status` clean; with a dirty tracked non-KB file, the file is unchanged (12b).
- Given the same with a foreign commit present, then the local branch is `M`, keeps the foreign commit and its dirty non-KB files (12c).
- Given a protected default and a side tip that holds unmerged KB content not in HEAD's history, then nothing is pushed, `reason: side_ahead` (12f); given the PR merged (side KB tree == `T`'s), then the side commit is built.
- Given `<headSha>:knowledge-base` is a blob (a file named `knowledge-base` replaced the directory), then nothing is pushed, `reason: kb_not_tree`.
- Given `.git/MERGE_HEAD` present with conflict markers in a KB file, then no auto-commit and no push, `reason: merge_in_progress` (12h).
- Given a `ls-remote` that throws, then the isolated dir is disposed (no directory left under its parent) and op `syncPush` fires with a `reason` tag.
- Unit (`test/server/session-sync-sentry-mirror.test.ts`): the payload shape and the per-reason debounce (AC5).
- Unit (`test/session-sync-path-allowlist.test.ts`): `update-ref` / `unpack-objects` accept only the guarded argv shapes.
- Regression: `test/host-git-consumers-real-git.test.ts` carrier rows stay green; `test/push-branch-isolated-real-git.test.ts` stays green with `checkCommitPresent` on the runner.
