# Tasks: fix syncPush publishes only knowledge-base commits (#12600)

Plan: `knowledge-base/project/plans/2026-11-12-fix-syncpush-kb-only-push-plan.md`. Rulings (A-P, R1-R13, T1, U1):
`knowledge-base/project/specs/feat-one-shot-12600-syncpush-owner-approval/decision-challenges.md`. One commit per phase.

## Phase 0: Measure, then failing tests

- [ ] 0.1 Build the Dockerfile `runner` stage; rerun the predicate probe inside it; record `git --version` there and on
  CI. A row that differs from the 2.56.0 table stops work (P0 redesign, R10).
- [ ] 0.2 Measure on the hardened isolated arm against a `file://` bare remote: `ls-remote --symref <url> HEAD
  refs/heads/<b> refs/heads/soleur/kb-sync`, and `fetch --depth 1 --no-tags <url> refs/heads/soleur/kb-sync` into a
  shallow isolated dir.
- [ ] 0.3 Measure the predicate in the isolated GIT_DIR on a `--depth 1` clone (shallow boundary at `T`); a missing or
  malformed shallow must error (refusal).
- [ ] 0.4 Measure `pack-objects --stdout` | `unpack-objects -q` into the workspace via `hostGitInvocation`, then CAS
  `update-ref`; `git status` stays clean.
- [ ] 0.5 Write `apps/web-platform/test/session-sync-kb-only-push-real-git.test.ts`: matrix rows 1-12i, H1-H7, the
  Test Scenarios list; template remote in `beforeAll`, `GIT_CONFIG_GLOBAL=/dev/null`, `GIT_CONFIG_NOSYSTEM=1`,
  increasing `GIT_COMMITTER_DATE`, `__resetMirrorDebounceForTests` in `beforeEach`, 30 s timeouts. Confirm RED on the
  unmodified `syncPush` (must-PASS rows excepted).

## Phase 1: Move, runner and reads

- [ ] 1.1 Move `runProtectedFallback` and the push call into `server/kb-sync-publish.ts` with no behaviour change (own
  commit); header comment states Guard 1.
- [ ] 1.2 `server/git-isolated-local.ts` `runIsolatedGitLocal` (lazy `child_process`, `HARDENED_GIT_ARGS`,
  `buildIsolatedGitEnv`, timeout, exit codes); rewrite `push-branch.ts` `checkCommitPresent` on it; `CENSUS_ONLY` row in
  `test/host-git-consumers-real-git.test.ts`.
- [ ] 1.3 `server/approval/workspace-head.ts` `readWorkspaceHeadRef` -> `{ sha, refName | null }` (existing export
  unchanged).
- [ ] 1.4 `ALLOWED_GIT_SUBCOMMANDS` += `update-ref` (two guarded shapes, CAS mandatory on `refs/heads/<D>`) and
  `unpack-objects -q`; any other argv throws; path-allowlist test rows.
- [ ] 1.5 Export `AGENT_AUTHOR_NAME` / `AGENT_AUTHOR_EMAIL` from `push-branch.ts`.

## Phase 2: Remote state, predicate, explicit push

- [ ] 2.1 `readRemoteState` (one hardened `ls-remote --symref`, exact ref-name match, one line per ref).
- [ ] 2.2 `checkKbOnlyRange(base, sha)` (walk + `diff-tree`, strict count parse, refusal on any throw/NaN).
- [ ] 2.3 `pushVerifiedKbOnly({ base, sha, ref, … })` (base-ancestor check, predicate, non-force `<sha>:<ref>`, `ref`
  limited to `D` or `soleur/kb-sync`); the only push argv; `classifyPushError` on stderr.
- [ ] 2.4 `syncPush` steps 1-3: `MERGE_HEAD` skip before the auto-commit, `detached_head`, `non_default_branch`,
  `remote_branch_absent`, `T == headSha` early return + tracking ref, `remote_unknown_tip`, `remote_ahead`, fast path +
  tracking ref; one `try/finally` disposing the isolated dir; bookkeeping only after a push.

## Phase 3: Synthetic commit and local merge

- [ ] 3.1 `buildKbOverlay(parent, kbSourceSha)` (`ls-tree -z` / `mktree -z` / `commit-tree -p`, `-c user.*` identity,
  `KB_SYNC_SIDE_COMMIT_MSG`); `held_foreign` when KB trees are equal; `kb_not_tree`.
- [ ] 3.2 `M` build, pack + `unpack-objects`, CAS `update-ref` before the push (`head_moved` on failure), push `S`,
  tracking ref to `S`.

## Phase 4: Protected-branch fallback

- [ ] 4.1 Side parent from `readRemoteState` (`fetch --depth 1` when not local); ruling I extended (`side_ahead`);
  KB-equal skip; `buildKbOverlay`; push via `pushVerifiedKbOnly`; PR base `D`.
- [ ] 4.2 Delete `resolveDefaultBranchForFallback` and the workspace `checkout -f -B` / overlay checkout / `commit` /
  `reset --hard`; KB-only + equal trees -> CAS `update-ref` to the side commit, else leave the workspace.
- [ ] 4.3 Trim `test/server/session-sync-protected-fallback.test.ts` to op and alert-contract rows on the new call shapes.

## Phase 5: Observability

- [ ] 5.1 Reason union; `kb-sync.push-held` via `mirrorWarnWithDebounce` with `errorClass` `kb-sync-push-held:<reason>`,
  tags `reason` / `outcome`, extra `nonKbCommitCount` + `userId`; info outcomes to pino only.
- [ ] 5.2 Outer-catch throws carry a `reason` tag; registry comment in `server/observability.ts`.
- [ ] 5.3 `test/server/session-sync-sentry-mirror.test.ts` (AC5) and `test/server/session-sync-workspace-last-synced.test.ts` (AC6).

## Phase 6: Records and verification

- [ ] 6.1 ADR-309 addendum + three pointers located by text; ADR-068 (d) addendum; ADR-050 entry if it names the
  legacy push.
- [ ] 6.2 Run each matrix mutation and record the RED run per phase commit.
- [ ] 6.3 AC10 vitest run and `tsc --noEmit`.
- [ ] 6.4 PR body (via `soleur:ship`): `Closes #12600`; links #12713, #12714, #12718, #12719; Phase 0 measurements;
  the plain-words behaviour sentence (AC11).
