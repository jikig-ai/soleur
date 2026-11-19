# Tasks: fix syncPush publishes only Soleur-built knowledge-base commits (#12600), plus #12718 and #12714

Plan: `knowledge-base/project/plans/2026-11-12-fix-syncpush-kb-only-push-plan.md`. Rulings (A-P, R1-R20, T1, U1; extension X1-X5, R13b, V1-V6, V-M, W1-W7; review D1-D24; deepen 2026-11-17 D25-D30) are in
`knowledge-base/project/specs/feat-one-shot-12600-syncpush-owner-approval/decision-challenges.md`. Make one commit per
phase, and record that phase's RED runs with it.

## Phase 0: Measure, then write the failing tests

- [x] 0.1 Build the Dockerfile `runner` stage. Rerun `probe6.sh`, `probe7.sh` and `probe8.sh` inside it, using them as
  synthesized fixture scripts. Record `git --version` in the image and on CI. If a hash-check or hand-off row differs,
  stop: that is a P0 redesign.
- [x] 0.2 On the hardened isolated arm against a `file://` bare remote, measure:
  - `ls-remote --symref <url> HEAD refs/heads/soleur/kb-sync`;
  - `fetch --depth 1 --no-tags <url> refs/heads/soleur/kb-sync`.
- [x] 0.3 Measure a two-parent side commit `(P, T)`: after a simulated PR merge, `pull --ff-only` must still be a
  fast-forward.
- [x] 0.4 Record what a bare push from a feature branch in a single-branch `--depth 1` clone does today (the "before"
  behaviour for `non_default_branch`).
- [x] 0.5 Write `apps/web-platform/test/session-sync-kb-only-push-real-git.test.ts`.
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

- [x] 1.1 Move `runProtectedFallback` and the push call into `server/kb-sync-publish.ts` with no behaviour change, as
  its own commit. Add a header comment that states Guard 1.
- [x] 1.2 Create `server/git-isolated-local.ts` with `runIsolatedGitLocal` (lazy `child_process`, `HARDENED_GIT_ARGS`,
  `buildIsolatedGitEnv`, a timeout, exit codes surfaced) and `verifyObject`.
  - Rewrite `checkCommitPresent` in `push-branch.ts` on top of it.
  - Export `disposeIsolated`.
  - Add a `CENSUS_ONLY` row in `test/host-git-consumers-real-git.test.ts`.
- [x] 1.3 Add `readWorkspaceHeadRef` -> `{ sha, refName | null }` to `server/approval/workspace-head.ts`. Leave the
  existing export unchanged.
- [x] 1.4 Add two verbs to `ALLOWED_GIT_SUBCOMMANDS`:
  - `update-ref --no-deref`, in the two guarded shapes only, with CAS mandatory on `refs/heads/<D>`;
  - `unpack-objects -q`.

  Any other argv throws. Add path-allowlist test rows.
- [x] 1.5 Export `AGENT_AUTHOR_NAME` / `AGENT_AUTHOR_EMAIL` from `push-branch.ts`.

## Phase 2: Remote state, verify, build, guard, push

- [x] 2.1 `readRemoteState`: one hardened `ls-remote --symref`, exactly one `ref: refs/heads/<D>\tHEAD` line, an exact
  match on the `soleur/kb-sync` line, and a throw on duplicate lines.
- [x] 2.2 `buildKbOverlay(parent, kbSourceSha, { secondParent? })` builds with `ls-tree -z` / `mktree -z` /
  `commit-tree`, the `-c user.*` identity and `KB_SYNC_SIDE_COMMIT_MSG`. Add `assertRootDiffersOnlyInKb` and the
  three-object hash check (`hash_mismatch`).
- [x] 2.3 `pushVerifiedKbOnly`: re-run the guard, then a non-force push of `<sha>:<ref>`, with `ref` limited to `D` or
  `soleur/kb-sync`. It holds the only push argv.
- [x] 2.4 `classifyPushError` matches the line-anchored `^remote: error: GH006:` and keeps `GH013` as `other`. Add
  `test/server/classify-push-error.test.ts`.
- [x] 2.5 `syncPush` steps 1-3:
  - `MERGE_HEAD` skip before the auto-commit;
  - refusals: `detached_head`, `non_default_branch`, `remote_branch_absent`, `remote_unknown_tip`, `remote_ahead`,
    `kb_not_tree`, `held_foreign`;
  - early return when `T == headSha`, after setting the tracking ref;
  - one `try/finally` with `disposeIsolated`;
  - bookkeeping only after a push;
  - `KbSyncError` with a closed reason and no URL or sha.

## Phase 3: Local branch update (P7)

- [x] 3.1 CAS-to-`S` arm when the trees are equal; otherwise the `M` arm with `KB_SYNC_MERGE_MSG`.
- [x] 3.2 Hand the objects over with `pack-objects` | `unpack-objects`, then the `--no-deref` CAS before the push.
- [x] 3.3 On failure, refuse with `head_moved` / `ref_update_failed` / `unpack_failed`. After the push, set the
  tracking ref to `S`.

## Phase 4: Protected-branch fallback

- [x] 4.1 Side parent: take it from `readRemoteState`, `fetch --depth 1` it when it is not local, and hash-verify it.
- [x] 4.2 Extend ruling I to the side branch (`side_ahead`). Parents are `(P, T)`, or `T` alone. Skip when the KB entry
  is equal. Push via `pushVerifiedKbOnly` with base `T`. The PR base is `D`.
- [x] 4.3 Delete `resolveDefaultBranchForFallback`, plus the workspace `checkout -f -B` / overlay checkout / `commit` /
  `reset --hard`.
- [x] 4.4 When the trees are equal, CAS local `D` to `side` and set the tracking ref to `side`. A failed CAS after a
  successful push is `head_moved`, not a fallback failure. Add the `fallback_reason` tag.
- [x] 4.5 Trim `test/server/session-sync-protected-fallback.test.ts` to the op and alert-contract rows on the new call
  shapes.

## Phase 5: Self-heal gate (R18)

- [x] 5.1 In the default-branch arm of `selfHealNonFastForward`: if `status --porcelain --untracked-files=no` shows a
  tracked non-KB change, fire `self-heal-aborted-dirty-nonkb` and return `ERROR_CLASS_NON_FAST_FORWARD`.
- [x] 5.2 Add `test/server/workspace-sync-self-heal-dirty-nonkb.test.ts`. Keep
  `workspace-sync-no-pre-self-heal-error-mirror.test.ts` and `kb-route-helpers.test.ts` green.

## Phase 6: Observability

- [x] 6.1 Reason union. Each outcome first writes an unconditional `log.info`. Anomalies go through
  `mirrorWarnWithDebounce`:
  - `errorClass` is `kb-sync-push-held:<reason>`, with one static message per reason;
  - tags are `reason` / `outcome`;
  - extra is the hashed `userId`.
- [x] 6.2 Add a `reason` tag to the outer `syncPush` catch. Add the registry comment in `server/observability.ts`.
- [x] 6.3 Update `test/server/session-sync-sentry-mirror.test.ts` (AC5) and
  `test/server/session-sync-workspace-last-synced.test.ts` (AC6).

## Phase 7: Records and verification

- [x] 7.1 ADR-309: addendum plus three pointers, located by text. ADR-068 (d): addendum. ADR-050: update its entry if
  it names the legacy push.
- [x] 7.2 Run each matrix mutation and record the RED run with that phase's commit.
- [x] 7.3 Run the AC11 vitest suite and `tsc --noEmit`.
- [ ] 7.4 PR body, via `soleur:ship`:
  - `Closes #12600`, `Closes #12718`, `Closes #12714` (AC22);
  - links to #12713, #12714, #12718, #12719 and #12734;
  - the Phase 0 measurements;
  - the plain-words behaviour sentence (AC12).

## Extension (#12718, #12714): commit order per CTO R13b — Phases 0-7, then 8, 9, 10 (own commit), 11

## Phase 8: Isolated-fetch hardening (X2)

- [x] 8.1 Add `-c core.alternateRefsCommand=true` to `HARDENED_GIT_ARGS` with the F1 rationale in its comment; pin the
  argv in `test/git-auth-hardened-env.test.ts`.

## Phase 9: Session-start pull on the hardened arm (#12718; X1, X4, X5, D25-D28)

- [x] 9.1 Rerun `probe1.sh`-`probe5.sh` (`probes-12718-12714/` in this spec dir) in the built `runner` image; record
  `git --version`; any differing M/F/T row stops the phase (R10 applies). Also measure the `--no-overwrite-ignore`
  refusal and the `merge-tree --write-tree` exit codes there.
- [x] 9.2 Write the failing tests first, RED recorded: `test/session-sync-pull-isolated-real-git.test.ts` (TX1-a..m,
  TX2 with `GIT_DIR` / `GIT_INDEX_FILE` / `GIT_OBJECT_DIRECTORY` / `GIT_ALTERNATE_OBJECT_DIRECTORIES` in the env, TX4-a..d,
  TX5, TX5-b, TX6-a..f), the D27 rows in `test/workspace-sync-self-heal-real-git.test.ts`, `test/kb-sync-pull.test.ts`
  (TX1-e equality half). TX1-a uses a real shallow bare store, not a seam; a fresh bare remote per row that moves the
  remote.
- [x] 9.3 Leaves (D25(1), D25(4)): `server/kb-sync-objects.ts` (verified reads, `isAncestor`, `kbOf`, `commitTree`,
  `handOver`) and `server/kb-sync-remote.ts` (`readRemoteState` moved out of `kb-sync-publish.ts` with a neutral error;
  the NEW hardened `fetchIntoIsolated`: refspec `refs/heads/<D>:refs/heads/fetched`, no `+`, no glob,
  `--no-recurse-submodules --no-write-fetch-head`, an explicit timeout, the tip read with
  `rev-parse --verify refs/heads/fetched^{commit}`, equal to `T` and `verifyObject`-checked before any hand-over).
  Neither imports `kb-sync-publish.ts` or `push-branch.ts`. Move `AGENT_AUTHOR_*` and `disposeIsolated` out of
  `push-branch.ts` into leaves; collapse `SideFallbackInput`.
- [x] 9.4 `server/kb-sync-pull.ts` (D25(2), D25(6)-(8)): pure-git `mergeVerifiedDefault` and `adoptSideTip` over an
  injected `KbPullWriter` (`unpack`, `setTracking`, `casBranch`, `merge`); no stamping, reporting or isolated-dir
  lifecycle; never throws raw. `KbPullHeldReason` with a full `Record` of static messages (adds `fetch_failed`,
  `isolated_refused`, `handover_too_large`, `autostash_conflict`, `merge_conflict_precheck`, `side_not_kb_only`,
  `side_conflict`, `side_pr_unknown`, `side_declined`, `side_pr_created`, `side_linked`; fetch-stage reasons tagged
  `ref=default|side`). `PULL_HANDOVER_MAX_BYTES`; the walk cap (its own constant, not `OBJECT_WALK_ENTRY_CAP`) checked
  before `pack-objects`. A `D` with a leading `-` or failing `validateBranchFormat` is `remote_state`.
- [x] 9.5 `session-sync.ts` (D26): one `readStatus`, then the ONE shared `mergeInProgress` (`MERGE_HEAD` or
  `MERGE_AUTOSTASH`, lstat, no symlink follow, fail-closed, or an unmerged entry) BEFORE the auto-commit in both
  `syncPull` and `syncPush`; `unresolved_merge` with no auto-commit. The writer with `merge` behind a shape-only
  exact-argv guard (TX1-e shape rows in `test/session-sync-path-allowlist.test.ts`): the D26(2) `-c` pins
  (`merge.verifySignatures=false`, the three `gpg.*program=/bin/false`, `merge.renormalize=false`,
  `merge.default=text`, `rerere.enabled=false`, `rerere.autoUpdate=false`, `merge.stat=false`,
  `maintenance.auto=false`, `gc.auto=0`, `core.hooksPath=/dev/null`) and `--no-overwrite-ignore`. `syncPull`
  orchestrates the isolated dir, the default merge, `autostash_conflict` after rc 0, adoption, the held count, one
  `kb-sync.pull-held` report and dispose, and returns `{ heldFiles, pullReason }`.
- [x] 9.6 Side-tip adoption, pull half (D28): step 6b after `merged` and after `up_to_date`; fetch `P` if absent
  (have-refs `T` and HEAD, `ref=side` refusals), `verifyObject(P)`; the KB-only gate
  `diff --quiet --no-renames <merge-base(T,P)> <P> -- . ':(exclude)knowledge-base/'` (`side_not_kb_only`, no
  hand-over); the D17 table moved to `server/kb-sync-side-pr.ts` (open: adopt; none: create, then adopt; closed
  unmerged: `side_declined`; GET failure: `side_pr_unknown`, no write); the link arm (`side_linked`) when `P`'s KB tree
  equals a first-parent commit's; else a `merge-tree` pre-check (`side_conflict`) and the merge with `P`.
- [x] 9.7 Side-tip adoption, push half (D28(2), D28(6)): the two interim `side_ahead` throws in `deliverAndLinkSide`
  stay for an absent `P`, with comments saying the next session-start pull adopts it; a present `P` that fails the
  KB-only check holds `side_not_kb_only`; `recheckSidePr` uses `kb-sync-side-pr.ts`. Row in
  `test/session-sync-kb-only-push-real-git.test.ts`.
- [x] 9.8 Self-heal wiring (D27): the `selfHealNonFastForward` held-commits branch calls `mergeVerifiedDefault` after
  the D15 untracked pre-check and behind a token-free `merge-tree --write-tree` pre-check (`merge_conflict_precheck`,
  workspace untouched), with `--no-overwrite-ignore`; no stamp, no adoption, one report (op
  `self-heal-aborted-held-commits`, tag `reason`); delete `HELD_COMMITS_REASON_INTERIM`. `syncWorkspace` gains
  `workspaceId`, and every caller passes it (`app/api/kb/file/[...path]/route.ts`, `app/api/kb/sync/route.ts`,
  `app/api/kb/upload/route.ts`, `server/c4-writer.ts`, `server/kb-route-helpers.ts`,
  `server/inngest/functions/cron-workspace-sync-health.ts`, `server/inngest/functions/workspace-reconcile-on-push.ts`).
  X3 still covers only the legacy `pull --ff-only` and `fetch origin`.
- [x] 9.9 Checkpoint (D26(7)): TX5-b (`stale-base` after a pull merge); correct the stale comment in
  `server/inflight-checkpoint.ts` ("git pull --autostash runs on every startAgentSession").
- [x] 9.10 Census and repo-wide registration (D25(3), D25(5)): in `test/census-git-push-sites.test.ts`, drop
  `server/session-sync.ts pull legacy` from `GIT_AUTH_SITES`, add the hardened fetch site, extend the all-hardened
  assertion, assert zero `gitWithInstallationAuth` sites and no literal git exec in `kb-sync-held.ts`,
  `kb-sync-objects.ts` and `kb-sync-pull.ts` with known call-site counts per file, and add the import-census row (no
  import of `kb-sync-publish.ts` or `push-branch.ts` from `kb-sync-pull.ts`, `kb-sync-remote.ts`, `kb-sync-objects.ts`
  or `workspace-sync.ts`). Register the new real-git suites in `test/repo-wide-suites.ts`; pull in D24(10)'s app-local
  `gitFixtureEnv` re-export and import it from the new suites.
- [x] 9.11 Update `test/host-git-consumers-real-git.test.ts` driver rows (the new modules absent from `CENSUS_ONLY` and
  `IN_SCOPE`) and `test/server/session-sync-sentry-mirror.test.ts` (`kb-sync.pull-held` rows, the never-throws row).

## Phase 10: Held-files column (#12714, own commit; W2, D29)

- [x] 10.1 Migration 187 (+ down): `kb_sync_held_files integer null` with the named range check,
  `kb_sync_held_checked_at timestamptz null`, a `COMMENT ON COLUMN` for each, no `GRANT` / `REVOKE` on `workspaces`;
  the down drops both columns and the RPC, and its header says to revert the code first. `WorkspaceRepoCols` gains both
  columns.
- [x] 10.2 The RPC (D29(3)): `get_workspace_kb_sync_held(p_workspace_id)` in 187, member-checked `SECURITY DEFINER`,
  `search_path` pinned with `pg_temp` (precedent 158 `get_workspace_web_egress`).
- [x] 10.3 Tests (D29(10)): `test/supabase-migrations/187-workspace-kb-sync-held-files.test.ts` (the AC21 offline shape)
  and `supabase/verify/187_workspace_kb_sync_held_files.sql` (`authenticated` has no SELECT on the new columns; the RPC
  is definer with a pinned path). State in the PR what the grants do: column-split SELECT, table-level INSERT/UPDATE
  from 174, RLS as the barrier.
- [x] 10.4 Deploy order (D29(2)): 187 applies before the code that writes it; rollback is the code first, then the
  down. Apply to dev only once the PR is ready for review, with a dev-ledger row naming this PR; QA e2e runs after the
  apply. Re-check the migration number before commit and at ship
  (`git ls-tree origin/main --name-only apps/web-platform/supabase/migrations/`).
  Evidence (2026-11-18): CI tenant-integration applied 187 and 188 to the dev project; the dev-ledger parity check is
  clean (`violations=0`); no manual apply. origin/main tops out at 186 at ship, so 187/188 do not collide.

## Phase 11: Held signal, Settings card, agent line (#12714; W1, W3-W5, V1-V6, D29, D30)

- [x] 11.0 Gate: the wireframe `knowledge-base/product/design/settings/kb-sync-held-commits.pen` is committed and
  linked in the PR (row W7; Pencil available since the 2026-11-17 plan upgrade); no component code before it.
- [x] 11.1 `server/kb-sync-held.ts`: `computeHeldFiles` -> `{ total, onRecovered }` over `<T>...<headSha>` (HEX40 only);
  `readRecoveredKbSyncTips` (lstat, refuses symlinks, at most 20 files of at most 64 B, `packed-refs` lines from a file
  of at most 1 MiB). TW1, TW1-b and TW4-a/b/c real-git rows first.
- [x] 11.2 Wire and write the count (D29(1), D29(9)): the `onHeldFiles` hook in `publishKbOnly` (before the isolated
  dir is disposed, held exits included), the write from a `finally` in `syncPush`, and the computation in `syncPull`.
  Service client, a SEPARATE UPDATE (not folded into `updateLastSynced`), written every time with
  `kb_sync_held_checked_at = now()`. Disconnect and setup (`app/api/repo/disconnect/route.ts`,
  `app/api/repo/setup/route.ts`) null both columns. Remove the push-side `updateLastSynced` (W5) and delete the two
  push-stamp assertions in `test/server/session-sync-workspace-last-synced.test.ts`; TW2, AC17 and the readers census
  over every reader of `repo_last_synced_at`.
- [x] 11.3 Route predicate and agent lines (D29(3)-(7)): `isCcGithubPushRouteAvailable` in `cc-github-push.ts`
  (legacy always; cc flag, entitlement, installation and persona under its own deadline, no default-branch lookup, the
  viewer's `userId`, a transient result). `cc-dispatcher.ts`: the RPC in the same `Promise.all`, keyed on the
  `activeWorkspaceId` passed to `resolveCcGithubPushRegistration` (a failure: no line, one warning); the line in the
  query factory's `effectiveSystemPrompt` next to `c4PromptAddendum` (TW3, TW3-b).
- [x] 11.3b Legacy-runner line (D29(4)): `server/agent-runner.ts` appends the held line from `syncPull`'s
  `{ heldFiles, pullReason }`; both runners append the `merge_conflict` / `unresolved_merge` line. Agent strings per
  D29(6) (counted until merged into the main branch; check `github_list_pull_requests` before pushing again; recovered
  branches and the checkout; an "as of" time, no line when null; a `git diff --name-only` command), in agreement with
  `ccPushPromptAddendum` and the push tool description (grep row), never "not on GitHub".
- [x] 11.4 `lib/kb-sync-held-copy.ts` with the V6 strings verbatim (route available, no route, transient; Owner and
  member; singular and plural); Settings page select (service client, `resolveActiveWorkspace`'s id) + predicate,
  `SettingsContent`, `ProjectSetupCard` (reconnect: `ReconnectNotice` only; `{n}` an integer in 1..10000 as a text
  child); unit rows; the readers census test (no tenant select carries the new columns); `vi.mock` for any new server
  import in the orphan route tests.
- [x] 11.4b Final KB notice (V6(5)): in `lib/kb-workspace-sync-notice.ts`, set `detail` to "Your workspace has local
  changes that aren't on your repository's main branch yet, so it was not updated. Until it is, this page may still show
  the files as they were. You don't need to try again." and remove the header's "Interim copy; the #12714 wireframe may
  refine it" sentence; the four `lead` clauses and `kbWorkspaceSyncResyncPendingNotice` stay as shipped.
- [x] 11.5 `e2e/settings-kb-sync-held.e2e.ts` on the dev project after the 10.4 apply (Owner and member flows, V6
  strings, waits on the rendered copy); screenshots at desktop and 375 px for the PR, compared with the wireframe.
  Evidence (2026-11-18): 16/16 green, `authenticated` project, mock dev harness, not the dev Supabase project (8 states x 2 widths, no 375 px h-scroll); `authenticated` + `chromium` 117 passed, 1 skipped.
- [x] 11.6 At ship: file the follow-up issues and link #12719 as not closed. Filed 2026-11-18: #12945 (X3, D38(4)
  residual, FU-5, FU-6), #12946 (W6, C8, D30, D26(3), FU-1..FU-4, FU-8, FU-9, final-verification P3s), #12947 (V12 root
  cause, wireframe frames, 11.5 e2e findings); #12719 stays open:
  - X3 (legacy `syncWorkspace` `pull --ff-only` / `fetch origin`, P1 security; reuses `kb-sync-remote.ts`);
  - W6 (I3, with its trigger);
  - C8 (no publish route);
  - D30: an Owner card for the side-PR states (`side_pending`, `side_declined`, a deleted `soleur/kb-sync`);
  - D30: an Owner line for a permanently stuck merge, with #12719 (needs a new column);
  - D30: the stale tree row after the KB pending notice is dismissed;
  - D26(3): an isolated `merge-tree` merge that reads no workspace config (closes the `filter.*` / `merge.<d>.driver`
    residual).
  - [ ] FU-1 (D47; perf F2(b)): move the KB-route self-heal merge to a per-workspace background job. Reason: architectural
    pivot (new Inngest function, concurrency key, route contract); D38(4)'s 15 s budget bounds it now. Re-evaluate when:
    Better Stack shows more than 50 `self-heal merged the default branch` lines/day for one workspace, or p95 KB-write
    latency above 3 s on held workspaces over 7 days, or one user report.
  - [ ] FU-2 (D47; perf F3): a refusal memo for repeated terminal pull refusals. Reason: contested, stateful design (V4/W6
    precedent: evidence first); no correctness impact. Re-evaluate when: the same workspace logs the same terminal reason
    (`walk_cap`, `handover_too_large`, `side_declined`, `side_not_kb_only`, `side_conflict`) on 10 consecutive session
    starts, or 5 such workspaces within 14 days.
  - [ ] FU-3 (D47; perf F4): `index-pack` hand-over above about 100 objects plus streamed `pack-objects`. Reason: contested
    design (a new connected-repo verb with its own threat review); the D38(1) async writer already removes the loop block.
    Re-evaluate when: `handover_failed` + `handover_too_large` reach 1% or more of pulls over 14 days, or any container OOM
    during a pull.
  - [ ] FU-4 (D47; perf F5): streaming early stop for the held-files diff. Reason: the 10000 clamp and the 5 s budget bound
    it now. Re-evaluate when: any stored count = 10000, or a `nullCause=git_failed` from maxBuffer.
  - [ ] FU-5 (D47, D45(d); structural P2-2): widen `census-git-push-sites` to the sandbox token env, the key-auth wrapper, cron
    clones, env-builders and code outside server/. Reason: pre-existing and unrelated (sandbox E1 by design). Re-evaluate
    when: any new `GIT_INSTALLATION_TOKEN` or `buildIsolatedGitEnv` extraEnv consumer, or the X3 follow-up landing.
  - [ ] FU-6 (D47, D45(c)): revoke anon's table-level SELECT on `workspaces`. Reason: pre-existing (the 174 grants snapshot,
    all columns); RLS is the anon barrier today and `verify/187` pins that no policy names anon/PUBLIC. Re-evaluate when:
    any migration adds a `workspaces` policy for anon/PUBLIC or edits 174's grants, or the next grants-snapshot migration.
  - [x] FU-7 (tracked by existing #12668, cross-referenced 2026-11-18) (D47; type/security, P2, FILE NOW, no trigger): verify whether a cc sandbox raw `git push` or `gh pr create`
    reaches GitHub outside the Owner-approval route. Reason: pre-existing; D41(b) fixes only the baseline text here.
  - [ ] FU-8 (D47, D26 residual; data P3-1): autostash flattening a partially staged file. Reason: pre-existing (legacy
    `pull --autostash`). Re-evaluate when: one user report, or #12719 work starting.
  - [ ] FU-9 (D47; simplicity F19): deduplicate the fixture git helpers across the real-git test files. Reason:
    cross-cutting (3 or more unrelated test files). Re-evaluate when: the next real-git suite is added.
  - [ ] V12 root cause: a same-name team-icon replacement gets a 409 because the client never sends the existing file's
    `sha`; fix the upload to send it (the V12 neutral string then stops appearing and needs no change). Reason: V6(6) scoped
    it out and V12 only made the copy true. Re-evaluate when: one user report of "Replacing an icon ... is not available
    yet", or the next change to `components/settings/conversation-names-settings.tsx` or the team-icon upload route.
  - [ ] D38(4) residual: the self-heal's legacy-arm `fetch origin` keeps its own 30 s timeout and is not on the self-heal
    budget, so a route self-heal can exceed 15 s on that arm. Reason: the legacy arm is X3's to replace (hardened fetch).
    Re-evaluate when: X3 lands, or p95 KB-write latency above 3 s on legacy-arm workspaces over 7 days.
  - [ ] Wireframe: `knowledge-base/product/design/settings/kb-sync-held-commits.pen` frames still show the pre-V7/V11 copy
    ("Nothing is lost", "this notice clears once the merge reaches ..."): Owner held publish route, Owner singular, Owner no
    publish route, Owner incl. recovered branch, Member held publish route, Member singular, Member no publish route,
    Mobile 375 Owner and member, Owner and member transient predicate. Update them to the V7/V9/V11 strings
    (ux-design-lead). Reason: the code ships the CPO strings verbatim; the frames are reference only. Re-evaluate when:
    the next design pass on Settings, or before task 11.5's wireframe screenshot comparison.
  - [ ] Final-verification P3s (verify-final.md, 2026-11-18), one issue, each with its trigger:
    NEW-1 the collision listing keeps the 1 MiB output cap (`workspace-collision.ts`), so about 15k upstream path changes
    fail every merge; NEW-2 the pull's X5 check has no test that reds without it; N1 Supabase and PR REST calls inside
    the workspace lock are not budgeted; N2 the self-heal route bound is not end to end (fast-forward pull fixed 30 s cap,
    success-path count ignores the lock wait); N3 a busy lock is recorded as `sync_failed` in the reconcile and cron
    audit rows and that push's reconcile is dropped; N4 the cc refresh does not apply X5; N5 a self-heal that started
    before a disconnect/reconnect can write a stale pull-blocked value; P3-9 the guarded `.or()` filter is only tested
    against a mock; P3-5 a route fast-forward and the cc refresh never clear pull-blocked; quality-advisory flags three
    direct `userId` log emits in `session-sync.ts`. Trigger: any of these observed in Sentry/Better Stack, or the next
    change to the sync path.
  - [ ] 11.5 e2e findings (2026-11-18), pre-existing or cosmetic, one issue each with its trigger: the "Connected" chip
    (`text-green-400` on `bg-green-900/50`, `components/settings/project-setup-card.tsx`) has near-zero contrast in the
    light theme; `RailResizeHandle` hydration mismatch (`aria-valuemax` 480 server vs 224 client) on every dashboard
    page; at 375 px the Disconnect dialog's `p-6` inside the card's `p-4` wraps "Confirm Disconnect"; the e2e harness
    pins `FLAG_APPROVAL_QUEUE=0`, so the route-available and transient held strings are covered by unit tests only.
    Trigger: the next Settings design pass (the first two at the next accessibility/console sweep).
- [x] 11.7 Settings team icon (V6(6), D24): in `components/settings/conversation-names-settings.tsx`, on
  `workspace_sync: "pending"` show "Saved to GitHub. Your workspace has local changes that aren't on your repository's
  main branch yet, so it was not updated. The new icon appears here once it is; until then, you see the default icon.
  You don't need to try again."; on a 409 from the upload show "An icon with this file name is already on GitHub, so
  nothing was uploaded. If you just uploaded it, it appears here once your workspace is updated from GitHub." instead of
  "Upload failed. Please try again.", which stays for every other failure. Rows in
  `test/conversation-names-settings.test.tsx`.
