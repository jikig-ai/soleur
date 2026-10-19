# Run sheet: the flip-then-rollback rehearsal on both web hosts (DESIGN ONLY)

Status: design, 2026-10-15. Nothing here was executed or dispatched. It refines
`knowledge-base/project/specs/archive/20261013-002507-feat-one-shot-git-data-luks-cutover-8211/design-rollback-rehearsal.md`
(cited below as "the 10-12 design", sections by number) against the live read in `precondition-recheck-2026-10-15.md`.
Every dispatch below is its own owner-named command; a menu answer or an earlier "go" is not authorization
(`hr-menu-option-ack-not-prod-write-auth`). The headless `pending_deployments` approval form is never valid for a wipe mode.

## 1. What changes versus the 10-12 design

| # | Change | Why (source) |
|---|---|---|
| C1 | **One `flip` dispatch and one `rollback` dispatch cover web-1 and web-2 together.** There is no per-host dispatch. Per-host evidence is the two readback lines, `host web-1: git_data_store=<state> observed` and `host web-2: ...`, printed by the step `Per-host git_data_store= assertion`, which fails the step if either is missing. | Ruled by CTO agent, 2026-10-15. Basis: the flag is one Doppler `prd` secret written once by `flag_write`; workflow inputs are only `mode`, `confirm`, `lineage`; the redeploy step passes `WEB_HOST_PRIVATE_IPS: "10.0.1.10,10.0.1.11"`. |
| C2 | **The rotate predecessor is already discharged.** R0 reads run `38583657167` (rotate, success 2026-10-14 14:53:27Z, `Rotate completed (d6 marker)` green, new server `170370833`, `boot_complete` 14:52:17.960Z) instead of asking for a new rotate. #10166 and #10175 are CLOSED. | `precondition-recheck-2026-10-15.md` row 6. |
| C3 | **The rehearsal flip closes the rotate door for good.** The #10207 guard refuses `git-data-host-rotate` (`rotate precondition REFUSED (store_dirty)`) once any `git-data-cutover.yml` run executed the flag-write step. The rehearsal flip does that. After R1 no rotate is dispatchable until #10211 (store-measured-empty marker) lands; the break-glass is the runbook's "When a rotate is needed after the flip (#10175)". | `.github/workflows/apply-web-platform-infra.yml`, step `Rotate precondition - store never written`; runbook "No post-flip rotate route is accepted, in writing". |
| C4 | **The d6 stamp must still be inside the 100-run window at the real flip.** The flip reads the 100 newest `workflow_dispatch` runs of `apply-web-platform-infra.yml`. Measured 2026-10-15: the rotate is at index 1; the window spans 2026-08-04 to 2026-10-14 (about 1.4 dispatches a day on average, about 7 on 2026-10-14). It leaves the window after 98 further dispatches. Each credential canary is one dispatch, so the chain consumes a handful, not 98. Re-read the index at R0 and again before the real flip. If it has aged out, the flip refuses `d6_replace_stale` and the guard forbids a new rotate (deadlock, #10216 "durable rotate stamp"). | `gh run list --workflow apply-web-platform-infra.yml --event workflow_dispatch --limit 100`. |
| C5 | **Step R-1 (queue proof pair) is dropped.** The R4 queue lever is allowed only for a Level-1-only run, and the CLO ruled Level 1 does not discharge the Art. 17 condition. So the rehearsal is Level 2, the lever is not used, and R-1 has nothing to gate. | 10-12 design section 3 (R4) and the CLO addendum. |
| C6 | **Level 2 stays an owner-run sequence.** No scripted synthetic-account lifecycle exists in the repo. R3 and the delete in R6 are owner steps until a build PR adds one. | 10-12 design section 4, "Mechanism gap". |

## 2. Preconditions that must hold before R1 (the dispatch is refused otherwise)

The first block is enforced by the workflow (step `Flip preconditions`) and was measured on 2026-10-15; the second block is not
enforced and must be held by the owner.

Workflow-enforced, with today's reading:

| Refusal verdict | Needs | Reading 2026-10-15 |
|---|---|---|
| `precondition_8209_open` | `DOPPLER_TOKEN_INFRA_PRIVILEGED` on `web-platform-infra-apply` | present |
| `pin_fault_paging_absent` | rule 1310055 returns HTTP 200 with `status` 0 or `enabled`, read with `SENTRY_ACTIONS_RO_TOKEN` | secret present; rule not readable from here; drift runs green (latest 07:15Z today) |
| `d6_replace_stale` / `d6_last_rotate_failed` / `d6_rotate_in_flight` / `d6_run_unreadable` | newest rotate attempt succeeded with the d6 marker, inside the 100 newest dispatch runs | stamped by run `38583657167` (index 1) |
| `deploy_in_flight` | no `web-platform-release.yml` `workflow_run` run in progress, queued or waiting | not read (point-in-time; read at dispatch) |
| `live_image_stale` | `vars.GIT_DATA_EMITTER_FLOOR` set, `/health` version >= it | **NOT SET** (repo and both environments empty) |
| `sandbox_deny_floor` | `vars.GIT_DATA_DENY_FLOOR` set, `/health` version >= it | **NOT SET** |
| `flag_write_credential_absent` | `DOPPLER_TOKEN_GIT_DATA_FLAG` on `web-platform-infra-apply` (#8573) | **ABSENT** (environment holds only `DOPPLER_TOKEN_GIT_DATA_ROOT` and `DOPPLER_TOKEN_INFRA_PRIVILEGED`) |
| `flag_already_true` (proof) | `GIT_DATA_STORE_ENABLED` not already `true` | absent, so passes |
| `store_not_empty` (proof) | no entry under `repositories/` on the store | not read (proof is a dispatch) |

Owner-held, not enforced:

1. Active agent-session count is `0` at R0, R1 and R4, or a named maintenance window refuses sessions. No metric source and no session-refusal control exist yet (10-12 design section 3, "counts are not refusal"). Under the `single-user incident` threshold a zero count alone does not discharge this; either a control is built or the owner records acceptance of the residual cases in 10-12 design section 7.
2. The heartbeat re-read at the flip dispatch (until #9943 enforces it; CTO ruled #9943 does not fit one small PR and is not a flip precondition): both monitors `up`, newest `state=ok` under 15 minutes old and later than the newest `boot_complete` of `host_name=soleur-git-data`.
3. The credential chain is complete (see `owner-command-chain.md` steps 1 to 6).
4. No `git-data-host-rotate` dispatch between R1 and an exit read of `clear`, and none after the real flip.

## 3. Sequence

Kind: **R** = read-only, **D** = owner-named dispatch (production), **O** = owner-run production step, **PR** = repository change.
Evidence goes into the block in 10-12 design section 5 (unchanged except the per-host lines, which now come from one run per leg).

| Step | Kind | Command | Checks | A refusal or failure looks like |
|---|---|---|---|---|
| R0 | R | Re-run the reads of `precondition-recheck-2026-10-15.md` rows 1 to 4, 7 to 11 and the d6 index (C4), at the dispatch time; read `/health` version; read the live session count if a source exists | heartbeats up; liveness under 15 min; flag absent; stamp absent; running version >= both floors | any row differs: do not dispatch R1; a stale heartbeat means the host is dark, not a workflow problem |
| R1 | D | `gh workflow run git-data-cutover.yml --ref main -f mode=flip -f confirm=FLIP-GIT-DATA`, then the `web-platform-infra-apply` reviewer approves | the `Flip preconditions` step above, then `proof`, freeze, flag write, redeploy of both hosts, per-host `enabled` readback, unfreeze, transactional probe, stamp | `::error title=git-data-cutover preconditions::verdict=<word>` with a `remedy:` line, before any host is touched. Failure after the flag write runs the finalizer (flag off, redeploy, unfreeze, gc restart): the rehearsal is FAILED, no rollback needed. `notify-failure` carries `FREEZE_HELD`, `RECOVERY_FAILED`, `PROBE_FAILED` or `STATE UNKNOWN`; follow the runbook "When a cutover run fails", never `gh run rerun` |
| R2 | R | `gh run view <flip id> --json jobs` | every step `success`; lines `host web-1: git_data_store=enabled observed` and `host web-2: git_data_store=enabled observed`; stamp step `success` | a missing host line fails the assertion step and triggers the finalizer |
| R3 | O | the Level 2 synthetic session (10-12 design section 4, steps 1 to 3 of Level 2): a Soleur-owned synthetic account runs ONE agent session inside the window | `<syntheticId>.git` appears on the store | none headless; the owner confirms the session ran. Active-session count must read `0` apart from this account |
| R3b | R then O | classify every directory under `WORKTREE_ROOT` by hash through a workflow-owned read (**does not exist**; a build item) | only the canary's directory is present | a non-canary directory is a real user's stranded tree: stop, owner decides per directory (wait for replication, or route to the incident with the CLO) |
| R4 | D | `gh workflow run git-data-cutover.yml --ref main -f mode=rollback -f confirm=ROLLBACK-GIT-DATA`, after R2, R3 and R3b only | flag off, same redeploy, per-host `disabled` readback, unfreeze iff the sentinel lineage is this run's, gc restart, transactional probe | `nothing_to_rollback` (exit 0) if the flip already unwound; `PROBE_FAILED` red after the unwind. Record the minutes between the flip's stamp step and the rollback's flag-off step |
| R5 | R | `gh run view <rollback id> --json jobs` | `host web-1: git_data_store=disabled observed` and the web-2 line; `unfreeze` success; `Positive replication probe` success with `STORE probe=probe verdict=ok` | a missing `disabled` line means the fleet may be on the old env: `mode=redeploy` converges it |
| R6 | R then O | Level 1 reads timed after the rollback redeploy: `git_data_pin=present fp=...`, `git_data_ssh_client=present`, `git_data_store=disabled` (Better Stack); live pin-fault rule enabled; zero `op:git-data-bare-repo-erasure` and zero `pin_fault` Sentry events between R1 and R6. Then Level 2: `mode=proof` before deletion (expected `store_not_empty`; the red run opens a `ci/git-data-cutover` issue that is expected), the owner deletes the synthetic account through `POST /api/account/delete` from that account's own session, `mode=proof` again | proof after deletion reads `clear` | still `store_not_empty` after deletion: run the Sentry sweep in the runbook "Store not empty" step 3 to separate a failed canary erase from a real repository |
| R7 | D | `gh workflow run git-data-cutover.yml --ref main -f mode=proof -f confirm=CUTOVER-GIT-DATA` (exit read) | verdict `clear` | `store_not_empty` after R6: incident route to the CLO, first real flip blocked, do not replace the host, do not wipe either volume |
| R8 | R then O | read `GIT_DATA_LUKS_CUTOVER_AT` in `prd` (name listing) | stamp absent | present: the rollback does not clear it (#10297 open). Owner-gated delete with read-back, or merge #10297 first. A stale stamp is inert while the flag is off, but it is the soak anchor for `mode=wipe`, and the real flip overwrites it |
| R9 | PR | replace `*not yet run*` in the runbook section "Before the first flip" with the evidence block | links resolve | review |

## 4. Abort criteria

Unchanged from 10-12 design section 7: stop at any `FREEZE_HELD`, `RECOVERY_FAILED`, `PROBE_FAILED` or `STATE UNKNOWN`; a missing per-host
`enabled` or `disabled` line; exit read `store_not_empty`; a non-zero session count at R0, R1 or R4; any non-canary tree at R3b before an owner decision.

## 5. What blocks scheduling the rehearsal today

1. The three credential rotations, G2, G1 and the flag-write credential (`owner-command-chain.md` steps 1 to 6), and the two floor variables (step 7).
2. Build items that do not exist yet (10-12 design section 9): the stamp-clearing rollback arm (#10297, open), the read-only evidence collector, the session-refusal control or recorded owner acceptance, the active-session read, the `WORKTREE_ROOT` directory read, the synthetic-account lifecycle or an explicit statement that Level 2 is owner-run, and a runbook blast-radius row for the flag-on window.
3. Calendar: a flip stamped after 2026-11-04 cannot finish the 7-day soak before 2026-11-12 (plaintext-volume outer date). Working back: the rehearsal needs a first run, a clean exit read and the build items before the real flip, all by 2026-11-04. The schedule and legal-risk call is the owner's and the CLO's, not made here.

## 6. Residual risks this design does not remove

- Real users with an active session are exposed during the flag-on window (10-12 design section 1, F-A); the abort criteria bound it, they do not remove it.
- The rehearsal cannot prove behaviour under real replication load, web-2 beyond its log line (no SSH ingress), or that a second flip after a rehearsal is clean (F-B is read, not assumed).
- `web-platform-infra-apply` allows self-approval (`prevent_self_review=false`, 1 reviewer): an owner dispatching and approving their own run is permitted by the environment, so the two-key control is procedural (#10343).
