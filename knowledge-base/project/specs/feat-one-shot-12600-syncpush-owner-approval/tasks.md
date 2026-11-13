# Tasks: fix syncPush publishes only Soleur-built knowledge-base commits (#12600)

Plan: `knowledge-base/project/plans/2026-11-12-fix-syncpush-kb-only-push-plan.md`. Rulings (A-P, R1-R20, T1, U1) are in
`knowledge-base/project/specs/feat-one-shot-12600-syncpush-owner-approval/decision-challenges.md`. Make one commit per
phase, and record that phase's RED runs with it.

## Phase 0: Measure, then write the failing tests

- [ ] 0.1 Build the Dockerfile `runner` stage. Rerun `probe6.sh`, `probe7.sh` and `probe8.sh` inside it, using them as
  synthesized fixture scripts. Record `git --version` in the image and on CI. If a hash-check or hand-off row differs,
  stop: that is a P0 redesign.
- [ ] 0.2 On the hardened isolated arm against a `file://` bare remote, measure:
  - `ls-remote --symref <url> HEAD refs/heads/soleur/kb-sync`;
  - `fetch --depth 1 --no-tags <url> refs/heads/soleur/kb-sync`.
- [ ] 0.3 Measure a two-parent side commit `(P, T)`: after a simulated PR merge, `pull --ff-only` must still be a
  fast-forward.
- [ ] 0.4 Record what a bare push from a feature branch in a single-branch `--depth 1` clone does today (the "before"
  behaviour for `non_default_branch`).
- [ ] 0.5 Write `apps/web-platform/test/session-sync-kb-only-push-real-git.test.ts`.
  - Cover matrix rows 1-21, harness rows H1-H7 and the Test Scenarios list.
  - Build a template remote in `beforeAll` and copy it per row; no row mutates the template.
  - Record every argv. Widen protocols for `buildIsolatedGitEnv`, and also for `hostGitInvocation` in the
    `syncWorkspace` and legacy-arm rows.
  - Set `GIT_CONFIG_GLOBAL=/dev/null` and `GIT_CONFIG_NOSYSTEM=1`, and give commits increasing `GIT_COMMITTER_DATE`
    values.
  - Call `__resetMirrorDebounceForTests` in `beforeEach`. Use 30 s test timeouts and explicit `vi.waitFor` timeouts.
  - Use a real `pre-receive` GH006 hook.
  - Confirm every row is RED on the unmodified `syncPush`, except the must-PASS rows. Measure the battery's runtime
    against the shard timeout.

## Phase 1: Move, runner and reads

- [ ] 1.1 Move `runProtectedFallback` and the push call into `server/kb-sync-publish.ts` with no behaviour change, as
  its own commit. Add a header comment that states Guard 1.
- [ ] 1.2 Create `server/git-isolated-local.ts` with `runIsolatedGitLocal` (lazy `child_process`, `HARDENED_GIT_ARGS`,
  `buildIsolatedGitEnv`, a timeout, exit codes surfaced) and `verifyObject`.
  - Rewrite `checkCommitPresent` in `push-branch.ts` on top of it.
  - Export `disposeIsolated`.
  - Add a `CENSUS_ONLY` row in `test/host-git-consumers-real-git.test.ts`.
- [ ] 1.3 Add `readWorkspaceHeadRef` -> `{ sha, refName | null }` to `server/approval/workspace-head.ts`. Leave the
  existing export unchanged.
- [ ] 1.4 Add two verbs to `ALLOWED_GIT_SUBCOMMANDS`:
  - `update-ref --no-deref`, in the two guarded shapes only, with CAS mandatory on `refs/heads/<D>`;
  - `unpack-objects -q`.

  Any other argv throws. Add path-allowlist test rows.
- [ ] 1.5 Export `AGENT_AUTHOR_NAME` / `AGENT_AUTHOR_EMAIL` from `push-branch.ts`.

## Phase 2: Remote state, verify, build, guard, push

- [ ] 2.1 `readRemoteState`: one hardened `ls-remote --symref`, exactly one `ref: refs/heads/<D>\tHEAD` line, an exact
  match on the `soleur/kb-sync` line, and a throw on duplicate lines.
- [ ] 2.2 `buildKbOverlay(parent, kbSourceSha, { secondParent? })` builds with `ls-tree -z` / `mktree -z` /
  `commit-tree`, the `-c user.*` identity and `KB_SYNC_SIDE_COMMIT_MSG`. Add `assertRootDiffersOnlyInKb` and the
  three-object hash check (`hash_mismatch`).
- [ ] 2.3 `pushVerifiedKbOnly`: re-run the guard, then a non-force push of `<sha>:<ref>`, with `ref` limited to `D` or
  `soleur/kb-sync`. It holds the only push argv.
- [ ] 2.4 `classifyPushError` matches the line-anchored `^remote: error: GH006:` and keeps `GH013` as `other`. Add
  `test/server/classify-push-error.test.ts`.
- [ ] 2.5 `syncPush` steps 1-3:
  - `MERGE_HEAD` skip before the auto-commit;
  - refusals: `detached_head`, `non_default_branch`, `remote_branch_absent`, `remote_unknown_tip`, `remote_ahead`,
    `kb_not_tree`, `held_foreign`;
  - early return when `T == headSha`, after setting the tracking ref;
  - one `try/finally` with `disposeIsolated`;
  - bookkeeping only after a push;
  - `KbSyncError` with a closed reason and no URL or sha.

## Phase 3: Local branch update (P7)

- [ ] 3.1 CAS-to-`S` arm when the trees are equal; otherwise the `M` arm with `KB_SYNC_MERGE_MSG`.
- [ ] 3.2 Hand the objects over with `pack-objects` | `unpack-objects`, then the `--no-deref` CAS before the push.
- [ ] 3.3 On failure, refuse with `head_moved` / `ref_update_failed` / `unpack_failed`. After the push, set the
  tracking ref to `S`.

## Phase 4: Protected-branch fallback

- [ ] 4.1 Side parent: take it from `readRemoteState`, `fetch --depth 1` it when it is not local, and hash-verify it.
- [ ] 4.2 Extend ruling I to the side branch (`side_ahead`). Parents are `(P, T)`, or `T` alone. Skip when the KB entry
  is equal. Push via `pushVerifiedKbOnly` with base `T`. The PR base is `D`.
- [ ] 4.3 Delete `resolveDefaultBranchForFallback`, plus the workspace `checkout -f -B` / overlay checkout / `commit` /
  `reset --hard`.
- [ ] 4.4 When the trees are equal, CAS local `D` to `side` and set the tracking ref to `side`. A failed CAS after a
  successful push is `head_moved`, not a fallback failure. Add the `fallback_reason` tag.
- [ ] 4.5 Trim `test/server/session-sync-protected-fallback.test.ts` to the op and alert-contract rows on the new call
  shapes.

## Phase 5: Self-heal gate (R18)

- [ ] 5.1 In the default-branch arm of `selfHealNonFastForward`: if `status --porcelain --untracked-files=no` shows a
  tracked non-KB change, fire `self-heal-aborted-dirty-nonkb` and return `ERROR_CLASS_NON_FAST_FORWARD`.
- [ ] 5.2 Add `test/server/workspace-sync-self-heal-dirty-nonkb.test.ts`. Keep
  `workspace-sync-no-pre-self-heal-error-mirror.test.ts` and `kb-route-helpers.test.ts` green.

## Phase 6: Observability

- [ ] 6.1 Reason union. Each outcome first writes an unconditional `log.info`. Anomalies go through
  `mirrorWarnWithDebounce`:
  - `errorClass` is `kb-sync-push-held:<reason>`, with one static message per reason;
  - tags are `reason` / `outcome`;
  - extra is the hashed `userId`.
- [ ] 6.2 Add a `reason` tag to the outer `syncPush` catch. Add the registry comment in `server/observability.ts`.
- [ ] 6.3 Update `test/server/session-sync-sentry-mirror.test.ts` (AC5) and
  `test/server/session-sync-workspace-last-synced.test.ts` (AC6).

## Phase 7: Records and verification

- [ ] 7.1 ADR-309: addendum plus three pointers, located by text. ADR-068 (d): addendum. ADR-050: update its entry if
  it names the legacy push.
- [ ] 7.2 Run each matrix mutation and record the RED run with that phase's commit.
- [ ] 7.3 Run the AC11 vitest suite and `tsc --noEmit`.
- [ ] 7.4 PR body, via `soleur:ship`:
  - `Closes #12600`;
  - links to #12713, #12714, #12718, #12719 and #12734;
  - the Phase 0 measurements;
  - the plain-words behaviour sentence (AC12).
