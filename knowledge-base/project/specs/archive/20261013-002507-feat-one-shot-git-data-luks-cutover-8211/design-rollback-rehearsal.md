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
and CPO weigh the rest. What the code does show: with the flag on, a session's working tree is created under
`WORKTREE_ROOT` (host-local NVMe) and replicated only at session end; the rollback flips the flag off and copies
nothing back, so `workspacePathForWorkspaceId` resolves to `/workspaces` again and any tree left under `WORKTREE_ROOT`
is unreachable (the resolver's own comment names "flag back to false while trees still live under the NVMe root"). A
session killed by the rollback redeploy never reaches its session-end replication. The window therefore exposes every
real user with an active session, not only the canary, and the abort criteria below cover that case (section 7).

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
false. Its reachable scope is NARROWER than "a later flip fails before its stamp": the finalizer unwinds the flag
(flag off, redeploy, unfreeze) on any exit after a flag write was attempted whenever `cutover_at_written` is absent
(`git-data-cutover.yml`, step `finalizer`, which also covers a write that landed and then failed its read-back), so a
failed flip leaves the flag false and the stale stamp inert. It matters only when that unwind does not complete
(`RECOVERY_FAILED`), when the runner is killed (the finalizer never runs; the flag stays `true` until the resume arm
re-runs and writes a fresh stamp), or when an operator sets the flag by hand. In each case the rehearsal's older
stamp would satisfy a soak for a flip that never concluded. Nothing deletes the stamp today (the only
`GIT_DATA_LUKS_CUTOVER_AT` write is the flip tail's `doppler secrets set`). Downstream dependency, recorded here as a
design requirement: `design-wipe-body-pr.md` W3 refuses the wipe unless the stamp is at least 7 days old and the flag
reads `true`, so a stale rehearsal stamp is also a wipe-gate input. The stamp-clearing fix (section 6) is therefore a
recorded PRECONDITION of the wipe-body PR, not only of the rehearsal; `design-wipe-body-pr.md` cites it (W3 and its
precondition 1 name this document's F-D, R8 and section 6, read in that file). Section 6 closes it.

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
build, the rotate precondition (`d6_replace_stale`; see the next paragraph, the reader does not enforce what it
claims), the heartbeat precondition (until #9943 is built, the runbook re-read; afterwards the machine check in
design-9943), the items #8101 carried (#8101 is CLOSED, 2026-09-30, read with `gh issue view`; it has no remaining items to track, so the owner
confirms by name that each item it covered, the rsync of `hooks/` and the mapper-device assertion in the wrappers, is on the deployed
build, and does not look for a status on that issue), `GIT_DATA_EMITTER_FLOOR` and `GIT_DATA_DENY_FLOOR` set, #8573 flag seam
credential provisioned. The rehearsal is therefore NOT earlier than the flip chain; it is the first use of it.

Design requirement, predecessor window (d6 cannot discharge it today). The `d6_replace_stale` reader in
`git-data-cutover.yml` (step `flip_preconditions`) accepts the first of the latest 40 `apply-web-platform-infra.yml`
dispatch runs on `main` in which the `git_data_host_replace` job AND a step matching "rotate confirm token" both
concluded `success`. In `apply-web-platform-infra.yml` that step ("Validate dispatch inputs (rotate confirm token)")
is unconditional and exits 0 with `rotate confirm: n/a` for any target other than `git-data-host-rotate`, so a plain
`git-data-host-replace` stamps `d6 rotate stamp: run <id>`; the loop also `continue`s past a failed newer run and takes
an older success, so a newest rotate that failed after creating the new host is skipped; and a `plan_only=true`
dispatch (the input exists for `git-data-host-replace`, and its apply steps are `if: inputs.plan_only != true`) can
read as a success job. This is tracked as open issue #10166 ("should the cutover's key-rotation check only accept a
real rotate run?"). Therefore: (1) #10166 is a HARD precondition of R1 (the reader fixed, or the check below applied
by name), and (2) the rehearsal must not rely on d6 to establish that a real rotate happened. R0 adds an independent,
owner-named check, read-only: for the rotate run the owner names, read its job's `Terraform apply (git-data-host
-replace)` step conclusion (`success`), confirm `plan_only` was not true, and read the NEW server's `stage=boot_complete`
event from Better Stack timed after that run's apply step (the poll step's own VERDICT line is the same signal), with
the run id, conclusions and event timestamp recorded. A rotate whose apply step did not conclude `success`, or whose
`boot_complete` post-dates a later replace, does not discharge the window.

Design requirement, quiet window. A measured count of active agent sessions, taken at R0 and again immediately before R1
and R4, must read zero, or the owner names a maintenance window in which sessions are refused. The metric source is a
build-PR item (no existing read of "active sessions" is verified here); until it exists R1 does not proceed on a
guess. Level 2's single synthetic session (section 4) is the only session permitted inside the flag-on window.

Design requirement, counts are not refusal. Every count above is a point-in-time read, not a control: nothing in
this design stops a session from starting between two reads. No session-refusal mechanism (a maintenance mode that
refuses new sessions) is verified to exist (a search of `apps/web-platform/server` and `apps/web-platform/lib` found
none). A named session-refusal control built by the build PR, or an owner acceptance recorded in the run record
naming the residual cases of section 7 "Cannot prove", is therefore a hard PRECONDITION of R1 under the
`single-user incident` threshold; a zero count alone does not discharge it.

Design requirement, no rotate after the first flip. After R1 the only copy of every repository written in the
window may be the LUKS volume, and the rotate precondition does not know it. `apply-web-platform-infra.yml`, step
"Rotate precondition - served store measured empty", reads through `git_data_served_empty_read`
(`scripts/lib/git-data-boot-signal-poll.sh`) ONLY the newest `stage=boot_complete` row of `host_name=soleur-git-data`,
with no time bound and no read of the flag or the stamp, and passes on `served_repos=0`. That row is written once per
boot, so it stays `0` after the flip populates the store until the host next boots. A `git-data-host-rotate`
dispatch after R1 therefore passes the precondition and destroys the populated LUKS volume, the sole copy. The
rehearsal's own end state (F-B: a rollback leaves the store populated, flag off) is exactly the vulnerable one. Rules:
no `git-data-host-rotate` dispatch between R1 and an exit read (R7) of `clear`, and never one after the real flip
(the owner does not dispatch it; there is no guard that stops them today). The hazard is tracked in
#10175; a workflow guard is that issue's scope, not this
design's, and until it lands this rule is the only control. The rotate predecessor in R0 is therefore a step BEFORE
R1 only, and nothing here pushes the owner to dispatch a rotate afterwards.

| Step | Action | Kind | Evidence recorded |
|---|---|---|---|
| R-1 | Queue proof pair (a precondition of the R4 queue lever ONLY, which exists for a Level-1-only rehearsal; skip it when the lever is not used; not an R1 precondition and not stated in section 8): on the `git-data-state` group, dispatch a read-only `mode=proof` run A and, while A is `in_progress` or waiting, a second `mode=proof` run B; read from `gh run list`/`gh run view` that B stayed `pending`, started only after A concluded, and was not cancelled, and record how a THIRD dispatch (a newer pending run) treats B. Scheduled before R1 so the result gates the R4 lever | OWNER-GATED dispatch (proof is read-only on hosts) | run ids, A/B/C statuses with timestamps |
| R0 | Read-only baseline: flag `false`; the stamp absent; `mode=proof` last read `clear` (run id); the live pin-fault rule read (`scripts/sentry-alert-live-fidelity.sh` or the latest `scheduled-sentry-alert-drift.yml` run, under 24 h); startup lines `git_data_pin=present fp=...`, `git_data_ssh_client=present`, `git_data_store=disabled` on both hosts from Better Stack (pinned reads, not the dashboard); heartbeat `up` and a `state=ok` liveness event under 15 minutes old and newer than `boot_complete`; the independent rotate check of the section 3 predecessor-window paragraph (apply-step conclusion, `plan_only` not true, new server `boot_complete` after it); the measured active-session count `== 0` | read-only | values and timestamps |
| R1 | Owner names and dispatches `flip` (section 8 lists the literal command); the environment reviewer approves; active-session count re-read `== 0` immediately before; the session-refusal control or recorded owner acceptance of the quiet-window paragraph is in place; no rotate is dispatched from here until an exit read of `clear` | OWNER-GATED | run URL |
| R2 | Read the flip run through `gh run view <id> --json jobs`: every step `success`, in particular "Per-host git_data_store= assertion" for both hosts, the probe, and the stamp step; if the finalizer ran, STOP: the rehearsal failed (record why; no rollback needed, the unwind already ran) | read-only | step conclusions, the `host web-1/web-2: git_data_store=enabled observed` lines |
| R3 | App-path level 2 only (section 4): the synthetic session described there runs inside the window | OWNER-GATED (production write) | the canary identifiers by hash only |
| R3b | Reconcile before the rollback dispatch: list the workspace directories under `WORKTREE_ROOT` (through a workflow-owned read, never a hand SSH read) and classify each as the canary's or NOT. Any non-canary directory is a real user's working tree that the rollback will strand (the path resolves to `/workspaces` after it) and is not silently abandoned: the owner decides, per section 7, between delaying the rollback until the session ends and replicates (the flag-on window grows, which is a cost to weigh) and routing the directory to the incident decision with the CLO. The read is a build-PR deliverable (no such workflow-owned read is verified to exist) | OWNER-GATED decision after a read-only read | the directory count and the classification, by hash only |
| R4 | Owner names and dispatches `rollback` AFTER R2, R3 and R3b, never before them: R3's Level 2 session is mandatory (CLO addendum) and R3b's reconcile and decision must be complete first, and the active-session count is re-read immediately before this dispatch (the dispatch then waits for its own reviewer approval, whose latency lengthens the flag-on window and is recorded). The queue lever (dispatch `rollback` while the flip is still running so it starts as the flip ends) is allowed ONLY for a Level-1-only rehearsal, which per the CLO addendum does NOT discharge the Art. 17 condition and so is a mechanics-only run: a rollback queued during the flip starts the moment the flip concludes, which skips R3 and R3b and reads the session count at queue time, not at the rollback's redeploy, so for a run that includes Level 2 the lever is dropped. Where the lever is used: the workflow-level group `git-data-state` has `cancel-in-progress: false`, but GitHub keeps ONE pending run in a group and replaces an older pending run when a newer one arrives (the workflow header says "a pending run replaced by a newer dispatch in the git-data-state group notify nobody"), and the same group name is shared with the git-data host replace/birth jobs of `apply-web-platform-infra.yml`; R-1 must have confirmed the queueing on a proof pair first (without that read the owner dispatches and approves the rollback after the flip concludes); a queued rollback that is cancelled or replaced notifies nobody and silently lengthens the flag-on window, so R2 reads the run list at the flip's stamp step and, if no pending rollback is visible, the owner dispatches at once; a flip that fails and unwinds turns the queued rollback into `nothing_to_rollback`, exit 0. | OWNER-GATED | run URL; the minutes between the flip's stamp step and the rollback's flag-off step |
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

Mechanism gap, stated plainly: nothing in the repository today creates the synthetic account, drives one agent
session as it, deletes it and reads back. What exists is the delete route itself: `POST /api/account/delete`
(`apps/web-platform/app/api/account/delete/route.ts`) validates the request origin (`validateOrigin`), requires the
middleware-verified user identity (a real authenticated session of THAT user, so an agent cannot call it without
the synthetic user's session) and a body `confirmEmail` that must match, then calls `deleteAccount(userId, ...)`.
Design requirement for the build PR (section 9): a scripted synthetic-account lifecycle with exact commands for
create, one session, delete through that route, and read-back, each marked read-only or production-write, and with the
credentials it needs named without printing them. Until that script exists, Level 2 is NOT headlessly runnable and
each of its steps is a named OWNER step (the owner creates and signs in the synthetic account, runs the one session,
and issues the delete from that account's own session); R3 must not be dispatched on the assumption that an agent
can drive it.

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
reconcile:     repositories written in the window: <n by proof> ; non-canary NVMe trees under WORKTREE_ROOT at R3b: <n> ; incident <none|url>
predecessor:   rotate run <id>, apply step <conclusion>, plan_only <false>, new-server boot_complete <UTC>; #10166 <state>
queue check:   R4 lever used <yes (Level-1-only)|no>; proof pair <ids|n/a> B stayed pending <yes|no|n/a>; active sessions at R0/R1/R4 <n/n/n>
session ctl:   <control name or the recorded owner acceptance>; rotate dispatched between R1 and a clear exit read <no>
not covered:   real-user replication load, web-2 behaviour beyond the log line, any state a flip writes that a
               rollback does not remove (the stamp, until R8), the Art. 17 requests refused during the freeze (swept per the runbook)
```

All values come from `gh run view --json`, the pinned Better Stack reads and the Sentry read token, collected by a
read-only collector (working name `scripts/followthroughs/git-data-rehearsal-evidence.sh`; it is unbuilt and the name
is provisional; `hr-no-dashboard-eyeball-pull-data-yourself`).
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
value is the defect); the flip's own stamp-write step is untouched. Recorded precondition: this stamp-clearing change
(or an equivalent that makes the stamp absent after a rollback and after an unwound flip) merges before the wipe-body
PR's `mode=wipe` can be dispatched, because that design's W3 anchors the 7-day soak on this stamp; the wipe design's
precondition list carries it as an item (precondition 1 there, read in that file).

## 7. Abort criteria, blast radius, what a rehearsal can and cannot prove

Abort (stop and do not proceed to the next step): any `FREEZE_HELD`, `RECOVERY_FAILED`, `PROBE_FAILED` or
`STATE UNKNOWN` word from `notify-failure` (follow its row in the runbook's "When a cutover run fails" table, never a
reflex `gh run rerun`); a flip whose per-host `git_data_store=enabled` is not observed (the finalizer unwinds; the
rehearsal is FAILED); a rollback whose per-host `git_data_store=disabled` is not observed (the fleet may be on the
old env: `mode=redeploy` converges it, runbook "Also open"); the exit read `store_not_empty` (F-B); a non-zero active-session count at R0, R1 or R4; a R3b read that finds any
non-canary directory under `WORKTREE_ROOT`, until the owner has decided per directory (wait for replication, or route
to the incident); on a Level-1-only run that used the R4 queue lever, a queued rollback that is no longer pending at the flip's stamp step (dispatch it at once).

Stranded or stale working trees (design requirement). The `store_not_empty` incident route (runbook "Store not empty":
open an incident, route to the CLO, do not replace the host, do not wipe either volume) is extended to name the
host-local NVMe trees too: a rollback leaves each non-canary tree under `WORKTREE_ROOT` unreachable by path, and a tree
whose session was killed by a redeploy never replicated, so the data may exist ONLY there. The incident record names
the count of such trees (by hash), the web host they sit on, and that erasing or reclaiming `WORKTREE_ROOT` is the
incident's decision, never the rehearsal's. Brand-survival threshold: the `single-user incident` threshold applies to
the rehearsal-build PR AND to the flip PR (the rehearsal's flip is a production flip for every user with a session in
the window), not only to the wipe-build PR.

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
that a SECOND flip after a rehearsal is clean (F-B is read, not assumed). Also not proven, because counts are
point-in-time reads and not session refusal: (a) a session that starts between two count reads, or after the last R3b
read and before the rollback redeploy completes, whose tree is stranded (or replicated and caught only by R7) with no
further read; (b) a user opening an EXISTING workspace during the flag-on window, whose path resolves to
`WORKTREE_ROOT` and who may find the workspace missing until the rollback; both are covered only by the R1 session-refusal
precondition (a control or a recorded owner acceptance) of section 3.

## 8. Authorization and ordering rules

- Each of R-1, R1, R3, R3b, R4, R7, R8 (when a delete is needed) is its own owner-named command naming the mode and
  token. A menu answer, an earlier "go ahead" or the rehearsal's own approval of the flip is not authorization for the
  rollback or the exit read.
- The literal dispatch strings, as written in the workflow inputs (`git-data-cutover.yml`, `confirm` description; the
  runbook form is `gh workflow run git-data-cutover.yml --ref main -f mode=<MODE> -f confirm=<TOKEN>`), for the owner to
  name or amend:
  - queue pair and exit read: `gh workflow run git-data-cutover.yml --ref main -f mode=proof -f confirm=CUTOVER-GIT-DATA`
  - flip (R1): `gh workflow run git-data-cutover.yml --ref main -f mode=flip -f confirm=FLIP-GIT-DATA`
  - rollback (R4): `gh workflow run git-data-cutover.yml --ref main -f mode=rollback -f confirm=ROLLBACK-GIT-DATA`
  - recovery levers, not part of the happy path: `-f mode=unfreeze -f confirm=UNFREEZE-GIT-DATA -f lineage=cutover-<dead run id>`
    and `-f mode=redeploy -f confirm=REDEPLOY-GIT-DATA`
  - the rotate predecessor (a separate workflow, owner-gated, destroys and re-mints the LUKS store): `gh workflow run
    apply-web-platform-infra.yml --ref main -f apply_target=git-data-host-rotate -f confirm=ROTATE-GIT-DATA -f reason='<why>'`
    (`reason` is a required input; the `plan_only` input must be left unset or false for it to count)
- Environment approval: each run waits on the `web-platform-infra-apply` environment. The runbook (the flag-precheck
  section of `git-data-luks-cutover-5274.md`) documents a headless form: after `gh run view <id> --json
  path,event,headBranch,headSha,actor` reads this workflow, `workflow_dispatch`, `main`, the merge SHA and the session's
  own actor, read the environment id with `gh api repos/jikig-ai/soleur/actions/runs/<id>/pending_deployments` and
  approve with `gh api -X POST repos/jikig-ai/soleur/actions/runs/<id>/pending_deployments -F 'environment_ids[]=<env-id>'
  -f state=approved -f comment=<why>`, only with the owner's explicit consent in the session for that run. UNVERIFIED
  here: that this works for the session's actor against the live environment (the environment's reviewer list and
  whether a self-approval is permitted were not read, no live probe was made). The rotate job runs in the
  `infra-privileged` environment (`apply-web-platform-infra.yml`, job `git_data_host_replace`), which the `confirm`
  input description says has no reviewer and is main-only, so it needs no approval call; whether that environment's
  protection rules match the description was not read (UNVERIFIED). This headless approval form is NEVER valid for
  `mode=wipe` or `mode=wipe_finish`: the environment approval there is an owner action (`design-wipe-body-pr.md`, section 7,
  the "Owner-gated" list, item (c)).
- No step is dispatched by an agent on inference. The agent reads, prepares the record PR and waits.
- The owner is present for R1-R4 (two approvals in quick succession) or the window in F-A grows by the approval
  latency; that latency is recorded in section 5's `window`.
- The rehearsal is dispatched on `main` only (the environment's branch policy).

## 9. Build PR checklist (the "rollback-rehearsal dispatch" PR)

Files: the runbook (replace the rehearsal paragraph with sections 3-5 in operator form; add the blast-radius row,
including the flag-on window and the NVMe-tree incident route; add the verdict note for the expected red proof in
level 2; add #10166 as a flip precondition); `.github/workflows/git-data-cutover.yml` (rollback arm
clears the stamp, section 6) with `git-data-cutover-access.test.sh` rows; the read-only evidence collector (section 5) and its test; a
scripted synthetic-account lifecycle (create, one session, delete through `POST /api/account/delete`, read-back) with
exact commands and each step marked read-only or production-write, or an explicit statement in the runbook that Level 2
is an owner-run sequence; the read-only `proof`-pair queue check of R-1, scheduled before R1 and only if the R4 queue lever is kept; the session-refusal control (or the owner-acceptance record) that R1 requires; the runbook text "no rotate between R1 and a clear exit read, never after the flip"; the active-session count
read and the R3b `WORKTREE_ROOT` directory read; the independent rotate check (apply-step conclusion, `plan_only`,
`boot_complete`) until #10166 lands; the CPO sign-off line (the `single-user incident` threshold applies to this PR and
to the flip PR).
Not built: any new mode, any dry-run mode (a mode that claims to rehearse without flipping would prove nothing about
the flip).

## Addendum - 2026-10-12: CLO ruling on Level 1 vs Level 2

Ruled by CLO agent, 2026-10-12: Level 1 alone does NOT discharge the #8211 Art. 17 erasure condition; Level 2 (a Soleur-owned synthetic production account deleted, with `mode=proof` before and after) is required. Level 1 shows the web container is armed but never observes an erasure, and "zero events" with no deletion attempted is vacuous. If the owner declines Level 2 the record must say "app-path erasure NOT exercised end to end", the condition stays open, and the CPO and CLO must accept that gap expressly before the first real flip. Level 1 must never be worded "erasure verified". Safeguards for Level 2: the synthetic account holds no real personal data and is cited by hash only; the expected red `proof` before deletion is documented as expected (not the `store_not_empty` incident); the `proof` after deletion must read `clear`; a Sentry sweep separates a failed canary erase from a real repository being present.
