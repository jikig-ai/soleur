# Tasks — fix: git-data remote URL path the transport wrapper rejects (#8211)

Plan: `knowledge-base/project/plans/2026-10-27-fix-git-data-remote-url-wrapper-path-plan.md`
Branch: `feat-one-shot-8211-git-data-remote-url-path`. PR body starts `Ref #8211` (not Closes).

## Phase 1 — RED tests (fail on the current `/repositories` constant)

- 1.1 Create `apps/web-platform/test/git-data-remote-url-wrapper.test.ts`
  - 1.1.1 Fixture: temp bare repo (`receive.advertisePushOptions=true`), real `findmnt` SOURCE/mount values, UUID stub on PATH, marker, empty hooks dir; fail loud if `findmnt --mountpoint` is empty
  - 1.1.2 Shim named `ssh` on PATH + `GIT_SSH_COMMAND`: log the last argv, rewrite `/mnt/git-data/repositories` to the fixture root, exec the REAL wrapper under `env -i` with explicit PATH/HOME and seam env
  - 1.1.3 Rows: R-URL (UUID and `ws-uuid-123`), R-PUSH (ensureGitDataRemote, push by remote name with both push options, refs only under the worktree namespace), R-FETCH, R-STALE, R-PARITY (app vs wrapper default, cutover.sh composition, cloud-init mount + `/repositories`; exactly one match each)
- 1.2 Update pinned URL in `apps/web-platform/test/git-data-replication.test.ts` and `apps/web-platform/test/git-data-client.test.ts`
- 1.3 `apps/web-platform/infra/git-data-transport-wrapper.test.sh`: section U (prefix extracted from the app constant; U1 fetch accept, U2 push accept, U3 old form refused, U4 round trip lands refs); add the old-form input to the existing stub loop; raise the floor
- 1.4 `apps/web-platform/infra/git-data-cutover-access.test.sh`: CPU1 only (probe command equals git's emission for the app-constant prefix); raise any floor

## Phase 2 — the fix

- 2.1 `apps/web-platform/server/git-data-replication.ts`: `GIT_DATA_REPO_PATH_PREFIX = "/mnt/git-data/repositories"`
- 2.2 Rewrite the comments at lines 42-51 and 332 (absolute path for `ssh://`; symlink serves scp-style only)

## Phase 3 — green and sweep

- 3.1 Run the new vitest file, the three neighbouring vitest files, the wrapper / cutover-access / ownership suites, `c4-count-parity`
- 3.2 Residual sweep `rg -n 'ssh://[^/ ]+/repositories/'` over `server/` and the three touched app tests returns nothing; leave the opaque samples in `git-auth.test.ts` and `git-data-ssh-connect-bound.test.ts`
- 3.3 Confirm untouched: wrapper, bootstrap, cloud-init, `git-data.tf`, `cron-egress-nftables.sh`, `AGENTS.rules.md`

## Phase 4 — runbook

- 4.1 R3 checks: positive refs evidence required; `<id>.git`, `store_not_empty`, provisioning success never count; negative Sentry evidence alone is INCONCLUSIVE; state that no no-SSH refs read exists yet
- 4.2 R6 checks and failure column: `store_not_empty` necessary, not sufficient
- 4.3 Re-run the runbook word-census case after the edit

## Phase 5 — hand-off

- 5.1 PR body: `Ref #8211`, link `decision-challenges.md`, #11086 untouched
- 5.2 One comment on #8211 parking the three follow-ups (no new issues)
- 5.3 Commits via `git commit -F`, Jean Deruelle identity, Co-Authored-By trailer last; explicit pathspecs; no `git add -A`; no `git stash`
