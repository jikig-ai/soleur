# Owner-gated chain: one step, one named command (2026-10-15)

Rules for every step: the owner names the exact command; a menu answer or an earlier "go" is not authorization
(`hr-menu-option-ack-not-prod-write-auth`); nothing here was run. Secret values never appear in a command line or a log;
the `$R` below is `jikig-ai/soleur`. "Refusal" is what the step prints when a precondition fails, quoted from the code or runbook
named in the row; where the repo defines no refusal text the row says so.

**The brief's order is amended by live state** (`precondition-recheck-2026-10-15.md`): the rotate re-dispatch is DONE (run `38583657167`,
2026-10-14), so it leaves the chain. Two blockers the brief did not list are added (steps 7 and 8). The flip is one dispatch for both
hosts (Ruled by CTO agent, 2026-10-15), so "web-1 then web-2" becomes one step.

## A. Credentials (#8209, R5; Ruled by CTO agent, 2026-10-12 on #8209: one credential per session, each with an old-value probe before the old value is deleted)

Each rotation is four owner-named sub-steps; they are separate commands and are never combined. The invariant from
`infra-credential-tiers-8209.md` "Rotation": set the new value in Tier B, run the O4 canary from `main`, only then delete the old value.

| Step | Command the owner names | Preconditions it checks | What a refusal or failure looks like |
|---|---|---|---|
| 0 | `gh run delete 38140050880 38383684022 38384137515` (#10216; any time; owner-only) | None of the three is a pinned run of the rotate guard (`GDSD_PINNED_RUNS="36685251588 37823216637"`, read in `scripts/lib/git-data-store-dirty-scan.sh`) and none carries the d6 marker (the newest rotate is `38583657167`). Verified 2026-10-15: the three are `apply-web-platform-infra.yml` dispatches, 10-11 failure, 10-13 success, 10-13 failure | No repo-defined refusal text. A GitHub permission error means the actor lacks run-delete rights. Never delete `36685251588` or `37823216637`: the guard then turns closed (`scan_unreadable`) |
| 1 | K1/L1 run census (read-only; counts and run ids only) | Exists as an addendum in the merged #10153; rerun only if the owner wants a fresh count. The 90-day Actions-log horizon shrinks the evidence daily | n/a (read-only) |
| 2a | Mint a new Hetzner read/write token in the Hetzner console (no roll API) | none | n/a |
| 2b | Set it as `HCLOUD_TOKEN` in `soleur-infra-privileged/prd`, by stdin from a 0600 file, then `shred -u` the file (runbook "Rotation", Order row 1). #10300 is open: the loader exports the whole privileged project into the git-data job, so a single-name carrier does not exist yet | grep non-READONLY consumers of the old copy first (CTO ruling failure mode "hidden consumer") | A wrong project or config writes to the wrong place; the canary in 2c is what shows it |
| 2c | Dispatch the O4 canary from `main`: `gh workflow run scheduled-terraform-drift.yml -R $R --ref main`, plus a no-op apply of `apply-github-infra.yml` and of `apply-web-platform-infra.yml` (the runbook names the no-op `apply_target` at O4) | every run annotates `source=tier_b`; plan exit `0` or `2`; the no-op applies green | A red canary after one change means the new value is the cause (that is why only one changes at a time) |
| 2d | Delete the old Hetzner token in the console (irreversible), then probe | probe: old token `GET /v1/servers` returns `401` AND `HCLOUD_TOKEN_READONLY` still returns `200` | `200` from the old token means the wrong token was deleted or the delete did not take |
| 3a to 3d | `CF_API_TOKEN_R2`: Cloudflare roll endpoint, response piped straight into `doppler secrets set ... --silent` (never rendered); then canary; then probe. Check the concurrency group is idle first; read the token's permission list for child tokens and check the CF audit log | old value fails `/user/tokens/verify` | the roll invalidates the old value at once and shows the new one once; losing it means a re-roll (the O13 first-roll incident) |
| 4a to 4d | `TF_STATE_AWS_*`: new pair scoped to `soleur-terraform-state` only; canary is a scratch-key `PutObject` with the new pair (`200`); delete the old pair; probe `PutObject` with the old pair (`403`). Do not delete the read-only Tier-A pair `r2-tf-state-read-8209`; confirm `r2-temp-state-copy-8209` is gone | a no-op apply may not write state, hence the scratch-key canary | `200` from the old pair after deletion |
| after each | a green drift run from `main` (the only detective for past state tampering) | `scheduled-terraform-drift.yml` | red or missing |

`DOPPLER_TOKEN_TF` (runbook Rotation row 3, gated on O12b) has a recorded old-value probe per the CTO ruling and is not in the brief's chain.

## B. Gates G2, G1, and the flag credential

| Step | Command the owner names | Preconditions it checks | Refusal / failure |
|---|---|---|---|
| 5 | G2 probes (#9295, ADR-241 D10): the read-only census of which branch-nameable Doppler tokens hold write on `soleur/prd`, ids only; then removal of that write scope. The repo defines no single dispatch string for it; the owner names the census command at the time | #9295 is OPEN. #8573 is blocked-by #9295 | n/a until a command is named |
| 6 | G1 execution (#9294: move `WEBHOOK_DEPLOY_SECRET` and the CF Access pair out of branch-nameable storage, then rotate). Executes LAST among the rotations: rotating before the Tier-A and repo-secret copies are gone would rotate into the open | steps 2 to 5 complete; #9294 OPEN | n/a until a command is named |
| 7 | **Not in the brief.** Provision the windowed prd write credential `DOPPLER_TOKEN_GIT_DATA_FLAG` on `web-platform-infra-apply` (#8573; #8609 blocks ADR-241 D2 from leaving `proposed`). No runbook documents its provisioning command (searched `knowledge-base/engineering/operations/runbooks`); the design is in #8573 and ADR-241 | environment currently holds only `DOPPLER_TOKEN_GIT_DATA_ROOT` and `DOPPLER_TOKEN_INFRA_PRIVILEGED` | `::error title=git-data-cutover secrets::verdict=flag_write_credential_absent` with the remedy "the #8573 write seam (DOPPLER_TOKEN_GIT_DATA_FLAG env secret on web-platform-infra-apply) is not provisioned ... the prd_terraform-scoped write token is never the substitute" |
| 8 | **Not in the brief.** Set the two repository variables `GIT_DATA_EMITTER_FLOOR` and `GIT_DATA_DENY_FLOOR` to the first release carrying the `git_data_store=` emitter and the #9725 dual-root tenant deny. The owner names the two version strings; the running version is read from `https://app.soleur.ai/health` (an agent can read it, it cannot choose the floor) | both are unset today at repo level and in both environments | `verdict=live_image_stale` ("vars.GIT_DATA_EMITTER_FLOOR unset ...") then `verdict=sandbox_deny_floor` ("vars.GIT_DATA_DENY_FLOOR unset ...") |

## C. Rehearsal, flip, soak

| Step | Command the owner names | Preconditions it checks | Refusal / failure |
|---|---|---|---|
| 9 | Rehearsal builds (not commands): see `rehearsal-run-sheet.md` section 5 (#10297 stamp clearing, evidence collector, session control, directory read, Level 2 lifecycle) | n/a | n/a |
| 10a | Rehearsal flip: `gh workflow run git-data-cutover.yml --ref main -f mode=flip -f confirm=FLIP-GIT-DATA` | `Flip preconditions` step: `precondition_8209_open`, `pin_fault_paging_absent` (rule 1310055 HTTP 200 and enabled), d6 (`d6_replace_stale`, `d6_last_rotate_failed`, `d6_rotate_in_flight`, `d6_run_unreadable`), `deploy_in_flight`, `live_image_stale`, `sandbox_deny_floor`; then `flag_write_credential_absent`, then the `proof` (`store_not_empty`, `flag_already_true`) | `::error title=git-data-cutover preconditions::verdict=<word>` plus a `remedy:` line, before any host is touched. Environment: `web-platform-infra-apply`, 1 reviewer, self-review allowed |
| 10b | Rehearsal rollback: `gh workflow run git-data-cutover.yml --ref main -f mode=rollback -f confirm=ROLLBACK-GIT-DATA` (only after R2, R3, R3b) | flag is `true` (else `nothing_to_rollback`, exit 0) | `PROBE_FAILED`, `RECOVERY_FAILED`, `FREEZE_HELD`, `STATE UNKNOWN` via `notify-failure` |
| 10c | Exit read: `gh workflow run git-data-cutover.yml --ref main -f mode=proof -f confirm=CUTOVER-GIT-DATA` | flag false | `store_not_empty` = incident to the CLO; the real flip stays blocked |
| 11 | **Real flip, both hosts in one dispatch:** `gh workflow run git-data-cutover.yml --ref main -f mode=flip -f confirm=FLIP-GIT-DATA`. Per-host evidence is the two lines `host web-1: git_data_store=enabled observed` and `host web-2: ...`; web-2 has no SSH ingress, so the log line IS its check | step 10 complete with a clean exit read; the d6 stamp (rotate run `38583657167`) must still be inside the 100 newest dispatch runs (index 1 on 2026-10-15); heartbeat re-read at dispatch (until #9943) | as 10a. After this dispatch no rotate is dispatchable (`rotate precondition REFUSED (store_dirty)`); #10211 is the exit |
| 12 | Break-glass only if a key compromise forces it: runbook "When a rotate is needed after the flip (#10175)" | n/a | n/a |
| 13 | Seven-day soak, stamped by the flip tail (`GIT_DATA_LUKS_CUTOVER_AT`) | stamp present and the flag `true` | the wipe refuses earlier (W3 in `design-wipe-body-pr.md`) |
| 14 | The wipe: `mode=wipe`, `mode=wipe_finish`, `mode=wipe_check`. **No dispatch string exists on `main`** (PR #10294 is open and not mine to merge). The headless `pending_deployments` approval form is never valid for any wipe mode; the environment approval is an owner action. Re-evaluate #10343 by 2026-10-24 first | #10294 merged; #10343 settled; stamp at least 7 days old; legal wording per the CLO | n/a until the PR lands |
| 15 | ADR-068 to `accepted`; close #6897 | soak complete, wipe verified | n/a |

## D. Things that are NOT steps

- **#9943** (machine-enforce the heartbeat precondition): Ruled by CTO agent, 2026-10-15: does not fit one small PR (script about 250 lines, offline suite 600 or more, plus the notify mapping, sentinel paging and 3,540-line census file), defer to its own PR, and it is not a flip precondition because the owner's re-read is the control until it lands. Minimum slice if cut is still about 400 lines.
- **#6975** (web-2 heartbeat suffix and pin): a gap, not a flip precondition; web-2 needs no per-host cutover step.
- **Legal documents:** edit none before the CLO re-ruling on 2026-10-24 (#9066; wording in #8551 and #10136).

## E. Dates

CLO re-ruling 2026-10-24. Plaintext-volume outer date 2026-11-12: a flip stamped after 2026-11-04 cannot finish the 7-day soak in time, so steps 2 to 11 must all complete by 2026-11-04, 20 days from today. The credential chain is serial (one credential per session, one canary each) and steps 5, 6, 7 and the rehearsal builds have no command or PR yet, so this deadline is at risk, not met. The schedule and legal-risk call is the owner's and the CLO's.

## Update 2026-10-19 (appended; nothing above is edited)

- **Step 14 is now defined on `main`** (#10294 merged 2026-10-15, #10352 merged 2026-10-16). The modes and their typed tokens, from `git-data-cutover.yml`: `wipe_check` with `WIPE-CHECK-GIT-DATA`, `wipe` with `WIPE-GIT-DATA`, `wipe_finish` with `WIPE-FINISH-GIT-DATA` (plus `volume_id` and `origin_run`), and `snapshot_clear` with `CLEAR-SNAPSHOT-GIT-DATA`. The owner still names each exact command; the headless `pending_deployments` approval form is never valid for any wipe mode.
- **`wipe_check` has been dispatched twice by the owner and refused both times** at the host assertion (`wipe_boot_layout_signal_offlist`, runs `39081408368` and `39136900735`; issue #10476). It is therefore a step that needs a decision before the next dispatch: what the third top-level directory on the plaintext volume is. See the 2026-10-19 addendum in `precondition-recheck-2026-10-15.md`.
- **A `proof` dispatch on 2026-10-19 (run `39225306395`) succeeded**: the served store is on the LUKS mapper and empty. Step 10c's exit read has been exercised once on the live host.
- Steps 0 to 11 and the dates in section E are unchanged by this update: the 2026-11-04 latest flip stamp still stands, and 16 days remain from 2026-10-19.
