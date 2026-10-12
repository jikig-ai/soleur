# Design: the flip-then-rollback rehearsal (precondition of the first `flip`)

Status: DESIGN ONLY (plan Phase 4.2, 2026-10-12). Nothing here was executed or dispatched, and no production
system was read. Claims are anchored to a file and a content anchor read in this worktree, never a line number.

Governing text: runbook `knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md`, section
"Before the first `flip`: the rollback rehearsal" (the first flip is not authorized until a flip-then-rollback
rehearsal has run once with the erasure probe passing after the rollback; pair it with an app-path signal; "Record
its run URL here when it exists: *not yet run*"; dispatched only on per-step authorization). Origin: the CPO
condition on #8211 (the rollback is shown to leave erasure working). ADR-239 Amendment 2026-10-02 (the
transactional probe also runs after a rollback; "it does not exercise the app's own erasure path in the redeployed
web container"). Rollback is flag-off only and never touches a mount or volume (ADR-239 Consequences).

## 1. Three findings that shape the design (each read in code, each changes what "rehearsal" can mean)

**F-A. There is no dry run: the rehearsal flip IS a production flip.** `git-data-cutover.yml` has exactly one
read-only mode, `proof`. `flip` freezes the store (writes the sentinel, stops `git-data-gc.timer`, purges legacy
locks), writes `GIT_DATA_STORE_ENABLED=true` into Doppler `prd` through the #8573 seam, redeploys BOTH web hosts,
and writes `GIT_DATA_LUKS_CUTOVER_AT`. Once the flag is `true`, `workspace-resolver.ts` resolves every workspace
path under `WORKTREE_ROOT` (`getWorkspaceWorktreeRoot`: "when enabled the working tree lives on host-local NVMe"),
and `replicateToGitData` provisions and pushes a bare repository on git-data at the end of any agent session
(its own comment: replication is "session-end-coupled"). So the interval between the flip's tail and the rollback
is a window in which real sessions can write real repositories to the store, and in which the flag-on app path
runs for real users. Everything below is built around making that interval short and its consequences read,
not around pretending it is a drill. This document does not measure what an in-flight user session experiences
across the path change; the runbook's blast-radius table states only the web-1 container restart, and the owner
and CPO weigh the rest.

**F-B. A rehearsal that leaves repositories behind can block the real flip.** The flip runs the full `proof`
first, whose `store-empty` probe refuses `store_not_empty` for any entry under `repositories/` (lock dotfiles and
`lost+found` excepted). The runbook's own text for that verdict is: open an incident, route to the CLO, do not
replace the host, do not wipe either volume, "erasing those repositories is the incident's decision", and the
runbook's "After the real cutover" backstop adds that after any rollback git-data-only writes must be reconciled
before the volume is decommissioned. So the rehearsal's exit read (section 3, step R7) is not optional: if it
reads `store_not_empty`, the mechanical legs of the rehearsal may have passed and the first real flip is still
blocked until the incident decision is taken.

**F-C. The runbook's app-path signal, as worded, cannot be positive.** The runbook asks for "an `erasure_outcome`
event for a canary id". `removeGitDataRepo` (`apps/web-platform/server/git-data-replication.ts`) returns
`{status: "erased"}` on a clean erase, and `account-delete.ts` reports to Sentry ONLY for non-`erased`,
non-`skipped` outcomes (the runbook says it too: account deletion "reports `erased` by emitting no
`op:git-data-bare-repo-erasure` event"). `skipped` (an unarmed environment) is ALSO silent. So silence is
ambiguous between "erased" and "never armed", and an `erasure_outcome` event can only ever be a FAILURE signal.
The design therefore defines two evidence levels and never writes "erasure verified end to end" for the weaker one
(section 4).

A fourth, smaller finding (F-D): **the rollback does not clear `GIT_DATA_LUKS_CUTOVER_AT`.** The stamp is written
by the flip tail and nothing in the rollback arm or the finalizer deletes it (`git-data-cutover.yml`, steps
`flag_write` and "Write GIT_DATA_LUKS_CUTOVER_AT", the finalizer's unwind list). `lb-weight-gate.sh` Condition B
needs `GIT_DATA_STORE_ENABLED=="true"` AND a stamp older than the soak, so a stale stamp is inert while the flag is
false. It stops being inert if a later real flip enables the flag and then FAILS to write its (last) stamp: the
rehearsal's older stamp would then satisfy the soak for a flip that never concluded. Section 6 closes it.

## 2. The mechanisms the rehearsal uses (all exist; the rehearsal adds no new mode)

| Leg | Mechanism | Source |
|---|---|---|
| flip | `mode=flip`, token `FLIP-GIT-DATA`: preconditions (`precondition_8209_open`, `pin_fault_paging_absent` from live Sentry rule 1310055, `d6_replace_stale`, `deploy_in_flight`, `live_image_stale`, `sandbox_deny_floor`) -> proof -> freeze -> flag write -> same-version redeploy on both hosts -> per-host `git_data_store=enabled` readback -> unfreeze -> transactional probe -> stamp | step `flip_preconditions` and the flip arm of `cutover` |
| rollback | `mode=rollback`, token `ROLLBACK-GIT-DATA`: flag off -> same-version redeploy -> per-host `git_data_store=disabled` readback -> unfreeze iff the sentinel's writer lineage is this run's -> gc restart -> the transactional probe (provision, fenced push, remove of `cutover-probe-<lineage>`, zero residue). A probe failure fails the run red AFTER the unwind and `notify-failure` carries `PROBE_FAILED`. | steps `flag_write`, redeploy, per-host assertion, `unfreeze`, `probe` |
| unwind | the `if: always()` finalizer unwinds totally on any failure after a flag write was attempted (flag off, redeploy, unfreeze, gc restart). A flip that fails and unwinds is a FAILED rehearsal, not a completed one. | step `finalizer` |
| exit read | `mode=proof` (read-only; legal once the flag is false) reads store-on-mapper, store-verified, and store-empty | `git-data-cutover.sh` |

The rollback leg's probe is the ruled "erasure probe after rollback": it exercises the HOST wrappers through the
CI root key. It does not exercise the web container. Hence F-C and section 4.

## 3. Sequence (every step owner-gated unless marked read-only; "owner-named command" per `hr-menu-option-ack-not-prod-write-auth`)

Preconditions for R1: every item of the runbook's "Preconditions for the flip" holds, because the rehearsal's flip
is refused by the same workflow preconditions: #8209 (Tier-B seam), pin and ssh client present on the deployed
build, the rotate stamp (`d6_replace_stale`, which depends on #10137 and a fresh owner-named rotate), the heartbeat
precondition (until #9943 is built, the runbook re-read; afterwards the machine check in design-9943), #8101's
remaining items, `GIT_DATA_EMITTER_FLOOR` and `GIT_DATA_DENY_FLOOR` set, #8573 flag seam credential provisioned.
The rehearsal is therefore NOT earlier than the flip chain; it is the first use of it.

| Step | Action | Kind | Evidence recorded |
|---|---|---|---|
| R0 | Read-only baseline: flag `false`; the stamp absent; `mode=proof` last read `clear` (run id); the live pin-fault rule read (`scripts/sentry-alert-live-fidelity.sh` or the latest `scheduled-sentry-alert-drift.yml` run, under 24 h); startup lines `git_data_pin=present fp=...`, `git_data_ssh_client=present`, `git_data_store=disabled` on both hosts from Better Stack (pinned reads, not the dashboard); heartbeat `up` and a `state=ok` liveness event under 15 minutes old and newer than `boot_complete` | read-only | values and timestamps |
| R1 | Owner names and dispatches `flip`; the environment reviewer approves | OWNER-GATED | run URL |
| R2 | Read the flip run through `gh run view <id> --json jobs`: every step `success`, in particular "Per-host git_data_store= assertion" for both hosts, the probe, and the stamp step; if the finalizer ran, STOP: the rehearsal failed (record why; no rollback needed, the unwind already ran) | read-only | step conclusions, the `host web-1/web-2: git_data_store=enabled observed` lines |
| R3 | App-path level 2 only (section 4): the synthetic session described there runs inside the window | OWNER-GATED (production write) | the canary identifiers by hash only |
| R4 | Owner names and dispatches `rollback` IMMEDIATELY after R2/R3. A rollback run needs its own reviewer approval, and `git-data-state` queues exactly one pending run, so the lever is: dispatch `rollback` while the flip is still running so it starts as the flip ends (the concurrency group is `cancel-in-progress: false`; a flip that fails and unwinds turns the queued rollback into `nothing_to_rollback`, exit 0). THIS QUEUEING AND APPROVAL BEHAVIOUR IS NOT VERIFIED HERE and must be confirmed once on a `proof` pair before it is relied on; absent confirmation the owner is simply present to approve both. | OWNER-GATED | run URL; the minutes between the flip's stamp step and the rollback's flag-off step |
| R5 | Read the rollback run: flag-off write, redeploy, per-host `git_data_store=disabled observed` for both hosts, `unfreeze` success, step `Positive replication probe` `success` with `STORE probe=probe verdict=ok`, no `notify-failure` job issue | read-only | step conclusions and lines |
| R6 | App-path evidence of level 1 or 2 (section 4) on the REDEPLOYED containers | read-only (level 1) / OWNER-GATED (level 2) | per section 4 |
| R7 | Exit read: `mode=proof` (owner-named, read-only on hosts). `clear` = store empty again. `store_not_empty` = F-B: the rehearsal is recorded as "mechanics passed, store populated", the incident route in the runbook's "Store not empty" row opens (CLO), and the first real flip is blocked until it is decided. | OWNER-GATED dispatch | verdict word |
| R8 | Stamp hygiene (section 6) | read-only, then OWNER-GATED if a delete is needed | the stamp value or its absence, before and after |
| R9 | Record PR: replace `*not yet run*` in the runbook with the evidence block (section 5) | PR | links |

## 4. The app-path signal, resolved

Level 1 (readable without a production write; always required; proves ARMED, not erased):

- on the redeployed containers after the rollback: `git_data_pin=present fp=<the fp the replace run printed>`,
  `git_data_ssh_client=present`, `git_data_store=disabled`, each from a pinned Better Stack read timed AFTER the
  rollback redeploy finished (the startup lines are warn-level by design so they reach Better Stack:
  `logGitDataHostKeyPinAtStartup`);
- the pin-fault rule still enabled and the `art17_erasure_incomplete` rule unchanged (live fidelity script);
- zero Sentry events tagged `op:git-data-bare-repo-erasure` and zero `pin_fault` events between R1 and R6.

Level 1 rules out "never armed" (`skipped` requires no remove key, no provision key and no host: the `git_data_pin=`
and `ssh_client` lines plus the redeploy exclude it) and every known failure outcome, but it does NOT observe an
erasure. The runbook sentence "an `erasure_outcome` event for a canary id" is amended in the record PR to say so.

Level 2 (a positive, uses only existing modes; a production write, owner-gated and a CPO/CLO acceptance item):

1. A Soleur-owned synthetic account (its id is the repository name, N2) runs ONE agent session during the flag-on
   window, so replication provisions and pushes `<syntheticId>.git` (R3).
2. After the rollback and R5, R7's `mode=proof` is run once BEFORE deletion and is EXPECTED to read
   `store_not_empty` (that red run opens a `ci/git-data-cutover` issue via `notify-failure`; the runbook paragraph
   added by the build PR says it is expected so it is not misread as the F-B incident).
3. The synthetic account is deleted through the app's real delete route, which calls `removeGitDataRepo(userId)`.
4. `mode=proof` again: `clear` proves the repository the app wrote is gone, through the app's own path in the
   redeployed container (flag now off, which is the point: erasure is deliberately not gated on the flag), and that
   no other repository remains. If it still reads `store_not_empty`, a Sentry sweep (runbook "Store not empty",
   step 3) separates "the canary's erase failed" (an event exists) from "a real repository is present" (none).

If the owner declines a production synthetic account, level 1 is recorded as "app-path erasure NOT exercised end to
end" and the CPO decides whether the condition on #8211 is met. The design records both outcomes distinctly and
never upgrades the wording. This acceptance is not a technical fork and is left open on purpose.

## 5. Evidence block the record PR writes (replaces `*not yet run*`)

```text
git-data flip-then-rollback rehearsal (#8211, CPO condition)
flip run:      <url>   dispatched <UTC>   conclusion <...>   stamp step <...>   finalizer ran <yes|no>
rollback run:  <url>   dispatched <UTC>   conclusion <...>   probe step <conclusion>   "STORE probe=probe verdict=ok" <seen|not seen>
window:        flag-on from <flip flag_write UTC> to <rollback flag-off UTC> = <n> minutes
per-host:      web-1 git_data_store=enabled <UTC> / disabled <UTC>;  web-2 git_data_store=enabled <UTC> / disabled <UTC>
app path:      level <1|2>; startup lines after rollback redeploy: pin <fp>, ssh_client <present>, store <disabled>; Sentry events R1..R6: <n>
               level 2 only: proof before deletion <store_not_empty>, proof after deletion <clear>
exit read:     mode=proof run <url> verdict <clear|store_not_empty>
stamp:         before R1 <absent>, after rollback <value|absent>, after R8 <absent>
reconcile:     repositories written in the window: <n by proof> ; incident <none|url>
not covered:   real-user replication load, web-2 behaviour beyond the log line, any state a flip writes that a
               rollback does not remove (the stamp, until R8), the Art. 17 requests refused during the freeze (swept per the runbook)
```

All values come from `gh run view --json`, the pinned Better Stack reads and the Sentry read token, collected by a
read-only script (working name `scripts/followthroughs/git-data-rehearsal-evidence.sh`, `hr-no-dashboard-eyeball-pull-data-yourself`).
No step reads a host over SSH by hand (`hr-no-ssh-fallback-in-runbooks`); the only host reads are the workflow's own.

## 6. Closing F-D (the stale stamp)

Resolved fork (technical): the build PR makes the rollback arm clear the stamp. The `flag_write` step already holds
the write-seam token for the flag-off write; deleting `GIT_DATA_LUKS_CUTOVER_AT` with the SAME token in the same
step adds no new binding site, so the census row that pins `DOPPLER_TOKEN_GIT_DATA_FLAG` to exactly
`{flag_write, the stamp step, finalizer}` is unchanged. The token's DELETE permission on `prd` is NOT verified here
(Doppler write scope normally covers it); the build PR proves it against a read-only-safe stub plus one owner-gated
real read of the secret list, and until it is proven R8 is an owner-gated delete with a read-back. A rollback that
finds the flag already off (`nothing_to_rollback`) clears nothing, because it ran no flip. Test rows: rollback arm
deletes then reads back absent; the delete failing fails the step red (the stamp is a soak anchor, a silent stale
value is the defect); the flip's own stamp-write step is untouched.

## 7. Abort criteria, blast radius, what a rehearsal can and cannot prove

Abort (stop and do not proceed to the next step): any `FREEZE_HELD`, `RECOVERY_FAILED`, `PROBE_FAILED` or
`STATE UNKNOWN` word from `notify-failure` (follow its row in the runbook's "When a cutover run fails" table, never a
reflex `gh run rerun`); a flip whose per-host `git_data_store=enabled` is not observed (the finalizer unwinds; the
rehearsal is FAILED); a rollback whose per-host `git_data_store=disabled` is not observed (the fleet may be on the
old env: `mode=redeploy` converges it, runbook "Also open"); the exit read `store_not_empty` (F-B).

Blast radius (runbook "Downtime and blast radius", rows `flip` and `rollback`, used unchanged): web-1's app
container restarts twice (about 75 s each, measured on 2026-10-02, the container's own unavailable window not
measured), and git-data store writes are refused between freeze and unfreeze on each leg, which refuses Article 17
erasures in those windows (each refusal is a logged `op:git-data-bare-repo-erasure` event, swept and re-driven
afterwards; the Art. 12(3) clock runs from the request). Plus the flag-on window of section 1, F-A, which no existing
row covers; the build PR adds a row for it with its measured duration from the first run.

Can prove: the flip and rollback mechanics end to end on real hosts; the finalizer's unwind on the real
credentials; that the host wrappers still provision, accept a fenced push and erase after a rollback; that both web
hosts load and report the flag in both directions; (level 2) that the app's erase path works after a rollback.
Cannot prove: behaviour under real replication load; web-2 beyond its log line (no SSH ingress); the claim that a
rollback restores every user-visible path; Art. 17 completeness for requests that arrived during the freeze windows;
that a SECOND flip after a rehearsal is clean (F-B is read, not assumed).

## 8. Authorization and ordering rules

- Each of R1, R3, R4, R7, R8 (when a delete is needed) is its own owner-named command naming the mode and token. A
  menu answer, an earlier "go ahead" or the rehearsal's own approval of the flip is not authorization for the
  rollback or the exit read.
- No step is dispatched by an agent on inference. The agent reads, prepares the record PR and waits.
- The owner is present for R1-R4 (two approvals in quick succession) or the window in F-A grows by the approval
  latency; that latency is recorded in section 5's `window`.
- The rehearsal is dispatched on `main` only (the environment's branch policy).

## 9. Build PR checklist (the "rollback-rehearsal dispatch" PR)

Files: the runbook (replace the rehearsal paragraph with sections 3-5 in operator form; add the blast-radius row;
add the verdict note for the expected red proof in level 2); `.github/workflows/git-data-cutover.yml` (rollback arm
clears the stamp, section 6) with `git-data-cutover-access.test.sh` rows; `scripts/followthroughs/git-data-rehearsal-evidence.sh`
(read-only collector) and its test; the CPO sign-off line (this builds on a `single-user incident` threshold surface).
Not built: any new mode, any dry-run mode (a mode that claims to rehearse without flipping would prove nothing about
the flip).

## Addendum - 2026-10-12: CLO ruling on Level 1 vs Level 2

Ruled by CLO agent, 2026-10-12: Level 1 alone does NOT discharge the #8211 Art. 17 erasure condition; Level 2 (a Soleur-owned synthetic production account deleted, with `mode=proof` before and after) is required. Level 1 shows the web container is armed but never observes an erasure, and "zero events" with no deletion attempted is vacuous. If the owner declines Level 2 the record must say "app-path erasure NOT exercised end to end", the condition stays open, and the CPO and CLO must accept that gap expressly before the first real flip. Level 1 must never be worded "erasure verified". Safeguards for Level 2: the synthetic account holds no real personal data and is cited by hash only; the expected red `proof` before deletion is documented as expected (not the `store_not_empty` incident); the `proof` after deletion must read `clear`; a Sentry sweep separates a failed canary erase from a real repository being present.
