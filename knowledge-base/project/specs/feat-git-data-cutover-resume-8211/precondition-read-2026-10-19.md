# Flip preconditions: by-hand live read (git-data LUKS cutover, #8211)

- Read at: 2026-10-19, 11:53Z to 12:00Z (UTC; two later re-reads, labelled in row 1, at 12:19Z), by an agent in a worktree at `origin/main` `652690531b`.
- Scope: read-only. No workflow dispatch, no terraform apply, no production write. No secret value printed: the Better Stack
  and Hetzner read tokens were used as bearer credentials inside `doppler run` (never echoed); every other Doppler read was a
  name listing, except row 13, a value-printing `get` of a non-secret flag name that printed nothing because the name is absent
  (a name listing, as in row 14, is the safer form and the runbook's R0 now says which answers are acceptable).
- This is build 4 of the CTO's rehearsal sequence (`cto-rulings.md`, T2). Each row is VERIFIED (read today, with how) or
  UNVERIFIED. It is a point-in-time record: none of it replaces the reads at R0 and at the dispatch (runbook, "Before the first
  `flip`"). Earlier numbers (2026-10-15 and the CTO's earlier reads of today) were not copied; each row was read again.

## Result

Every workflow-enforced flip precondition read here holds, except two rows that are not verified by this read (row 6, the
pin-fault workflow, cited from #10535's own probe because no headless token exists; row 15, the scope of
`DOPPLER_TOKEN_GIT_DATA_FLAG`) and one that raced a merge: `deploy_in_flight` was not clear at the first read (11:54:10Z) and was
clear at the second (11:59:39Z). The unchecked boxes of the runbook's "Preconditions for the flip" are under "Not read". This
does not make the flip safe to dispatch: the session-refusal control and the rehearsal evidence collector (builds 1 and 2) are
not merged, and PR #10535, which repaired the pin-fault check that refused every flip (the only machine barrier to an unprepared
flip), was merged on 2026-10-19 at 11:43:22Z (GitHub `mergedAt`; squash commit `770f6d035b` dated 10:59:16Z), before builds 1 to
3. See "Ordering note".

| # | Item | Verdict | How it was read (command, UTC) |
|---|---|---|---|
| 1 | d6 rotate stamp: run `38583657167` inside the 100 newest `apply-web-platform-infra.yml` `workflow_dispatch` runs | VERIFIED, index 6 (0-based; the 7th newest) | `gh run list --workflow apply-web-platform-infra.yml --event workflow_dispatch --limit 100 --json databaseId,createdAt,conclusion`, 11:53:54Z, then `index(38583657167)` again at 11:59:39Z: `6` (the flip gate also passes `--branch main`; a re-read at 12:19:55Z with it gave the same index). The `git_data_host_replace` job and the `Rotate completed (d6 marker)` step of that run are `success` (read by the review panel with `gh run view 38583657167 --json jobs`), and the six newer runs are not rotates. The run is `success`, created 2026-10-14T14:47:27Z. The 100-run window spans 2026-08-09 to 2026-10-18; the stamp stays inside it through 93 further dispatches and is pushed out by the 94th (index 6 plus 94 reaches 100). |
| 2 | `GIT_DATA_EMITTER_FLOOR` | VERIFIED, `0.313.5` | `gh variable list` (repo level), 11:53:54Z. `gh variable list --env web-platform-infra-apply` and `--env infra-privileged` printed nothing. Org-level variables were not read. |
| 3 | `GIT_DATA_DENY_FLOOR` | VERIFIED, `0.330.10` | same read as row 2. |
| 4 | Running version at or above both floors | VERIFIED | `curl https://app.soleur.ai/health`: `version` `0.344.8` at 11:53:54Z and `0.344.9` at 11:59:39Z (the version changed between the two reads); both are above `0.313.5` and `0.330.10` by numeric comparison of the three fields. |
| 5 | No `web-platform-release.yml` run in progress (`deploy_in_flight`) | **NOT CLEAR at 11:54:10Z; CLEAR at 11:59:39Z** | `gh run list --workflow web-platform-release.yml --event workflow_run --limit 20 --json databaseId,status,createdAt`, filtered as the flip step filters (`in_progress`, `queued`, `waiting`). First read: run `39246886003` `in_progress` (created 11:45:02Z, head `770f6d035b`, the merge of #10535; job `migrate` running). Second read: an empty list. The flip refuses `deploy_in_flight` while any such run exists, so a dispatch after any merge to `main` waits for the release to settle. |
| 6 | Sentry workflow `1310055` (`git-data-host-key-pin-fault`) enabled | UNVERIFIED by this read; cited from PR #10535's own read | The workflow's token `SENTRY_ACTIONS_RO_TOKEN` is a GitHub repository secret and is NOT in Doppler `prd` or `prd_terraform` (name listings at 11:54Z), so it was not re-read. PR #10535's body records a read-only probe of `workflows/1310055/` returning HTTP 200 with `name=git-data-host-key-pin-fault`, `enabled=true`. The flip step re-reads it at dispatch. |
| 7 | Heartbeat `soleur-git-data-host-prd` | VERIFIED, `up` | `doppler run -p soleur -c prd_terraform --only-secrets BETTERSTACK_API_TOKEN_READONLY -- bash -c 'BS_TOKEN="$BETTERSTACK_API_TOKEN_READONLY" exec bash apps/web-platform/infra/arm-heartbeats.sh --status soleur-git-data-host-prd'`, 11:55:13Z: `id=506836 paused=false status=up period=60 grace=300`. |
| 8 | Heartbeat `soleur-git-data-prd` | VERIFIED, `up` | same command with the other name, 11:55:13Z: `id=498647 paused=false status=up period=60 grace=180`. |
| 9 | Newest `state=ok` liveness event under 15 minutes old and later than the newest `boot_complete` | VERIFIED | Better Stack `stage=liveness`, `host_name=soleur-git-data`, 11:55:39Z (narrowed read, `--only-secrets` for the three query secrets, `env -u DOPPLER_TOKEN -u AWS_*`): newest `ok` at `2026-10-19 11:53:13` (2 min 26 s old; 17 `ok` rows in the last 3 hours). Newest `boot_complete` for `soleur-git-data`: `2026-10-14 14:52:17.959`. |
| 10 | Hetzner server `170370833` | VERIFIED | `GET /v1/servers/170370833` with `HCLOUD_TOKEN_READONLY`, 11:55:50Z: `soleur-git-data`, `running`, created 2026-10-14T14:51:27Z, `protection.delete=false`, volumes `[106867358, 107140231]`. |
| 11 | Hetzner volume `106867358` (plaintext) | VERIFIED | `GET /v1/volumes/106867358`, same read: `soleur-git-data-store`, attached to `170370833`, created 2026-09-14T15:13:37Z, `protection.delete=false`, `available`. |
| 12 | Hetzner volume `107140231` (LUKS) | VERIFIED | `GET /v1/volumes/107140231`, same read: `soleur-git-data-luks-store`, attached to `170370833`, created 2026-10-14T14:51:26Z, `protection.delete=false`, `available`. |
| 13 | `GIT_DATA_STORE_ENABLED` absent in `prd` | VERIFIED, absent | `doppler secrets get GIT_DATA_STORE_ENABLED -p soleur -c prd --plain` at 11:54:30Z: "Could not find requested secret". Absent is not the same as `false`; the app treats it as off. |
| 14 | `GIT_DATA_LUKS_CUTOVER_AT` absent in `prd` | VERIFIED, absent | name listing of `doppler secrets -p soleur -c prd --only-names` at 11:54:30Z, filtered on `GIT_DATA`: only `GIT_DATA_HEARTBEAT_URL`, `GIT_DATA_SSH_HOST` and `GIT_DATA_SSH_HOST_KEY`. |
| 15 | `DOPPLER_TOKEN_GIT_DATA_FLAG` on environment `web-platform-infra-apply` | VERIFIED present BY NAME; scope **UNVERIFIED** | `gh secret list --env web-platform-infra-apply` and `gh api repos/jikig-ai/soleur/environments/web-platform-infra-apply/secrets`, 11:54Z and 11:55:58Z: the secret exists, created and updated 2026-10-19T08:37:51Z (absent on 2026-10-15: cited from `precondition-recheck-2026-10-15.md`, not re-read). The names `DOPPLER_TOKEN_GIT_DATA_ROOT` and `DOPPLER_TOKEN_INFRA_PRIVILEGED` are also present. A secret value cannot be read, and no standalone probe is built (CTO ruling T4b): the scope is first exercised by the rehearsal flip. |
| 16 | Environment `web-platform-infra-apply` review rule | VERIFIED | `gh api repos/jikig-ai/soleur/environments/web-platform-infra-apply`, 12:00Z: one required reviewer, `prevent_self_review=false`, custom branch policies. |

## Ordering note

The CTO ruled (`cto-rulings.md`, T1) that #10535 merges last, after builds 1 to 3 and this record, because its merge repairs the
only machine barrier to a flip (the `Flip preconditions` step refused every flip at `pin_fault_paging_absent`, run
`39225916196`, 08:53:54Z). #10535 was marked ready at 10:33:11Z and merged at 11:43:22Z (GitHub events and `mergedAt`; squash
commit `770f6d035b` dated 10:59:16Z), before builds 1 to 3. The time of the CTO T1 ruling is not recorded here, so whether the
merge preceded it is not established. Read today: the quiet-window control and the evidence collector do not exist. By #10535's
own probe (not yet exercised by a live dispatch: the newest `git-data-cutover.yml` dispatch is the refused run above, before the
merge) a `mode=flip` dispatch is no longer refused at the known-broken check, and would perform a production flip with no session
refusal. Owner restraint is the only control left, which is the
alternative the ruling rejected (T1, rejected alternative a). The release run in row 5 is the deploy of that merge. What to do
about it belongs to the owner and the CTO; this record only states the fact.

## Not read, and why

- Sentry workflow `1310055` directly (row 6): no read-only token in Doppler.
- Org-level GitHub variables (rows 2 and 3).
- The scope of `DOPPLER_TOKEN_GIT_DATA_FLAG` (row 15).
- Active agent-session count: no verified metric exists (the control is build 1).
- The unchecked boxes of the runbook's "Preconditions for the flip" (every merge-triggered apply `success`; the ssh client on the
  deployed build) and the per-id re-erasure status: not read today.
- Better Stack startup lines (`git_data_pin=`, `git_data_ssh_client=`, `git_data_store=`) on the web hosts: not re-read today;
  they are R0 reads.
