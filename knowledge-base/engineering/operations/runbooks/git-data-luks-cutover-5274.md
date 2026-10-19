# git-data LUKS cutover runbook — #5274 Phase 3 / Sub-PR 3.D / ADR-068

Runbook for the git-data LUKS cutover route. **Since #8211 PR2 the route runs real modes, not only
the proof.** `git-data-cutover.yml` takes `mode=proof|flip|rollback|unfreeze|redeploy` (default proof):
`proof` is the read-only gate (authenticates to root on git-data through the ADR-220 web-1 jump, reads
the store state and the fence shape, exits); `flip` runs the full window (proof -> freeze -> flag on ->
same-version webhook redeploy -> per-host `git_data_store=` readback -> unfreeze -> transactional probe
-> the `GIT_DATA_LUKS_CUTOVER_AT` stamp); `rollback` is flag-off plus the same redeploy (it never
repoints a mount — the flag-off readback is the rollback); `unfreeze` clears the freeze sentinel
(own lineage, or a stranded one via the `lineage` input); `redeploy` is the standalone pin-load lever.
There is no copy or repoint — the store has served the LUKS mapper since boot (ADR-239); the old
plaintext volume is retained read-only until its wipe decision (#6897/#8571). The residue on it ends
when that volume is destroyed by the DL-2 wipe, never mounted to purge in place; the target date and the slip
rule are in ADR-239, amendment 2026-10-09. Three further modes, `wipe_check`, `wipe` and `wipe_finish` (#10138),
run in a separate job (`wipe`) and retire that volume by detaching it and deleting it at the provider API; they
are owner-named and described in [The wipe](#the-wipe-dl-2-10138--6897).

**No SSH in this runbook.** Every read below is a workflow annotation, a Better Stack API read or a
Sentry query. The dispatch itself uses SSH transport off the app host; you never SSH a host to check
whether it worked (`hr-no-ssh-fallback-in-runbooks`).

## Preconditions for the flip (the workflow enforces them — do not book a window early)

The modes exist (PR2). The `flip` dispatch is refused unless all of these hold:

- **#8211 PR2 merged** — the real modes on real mechanisms (freeze model, same-version webhook
  redeploy, flag-off-only `rollback`, `web-1-swap` membership). PR1 (PR #8564, ADR-239) moved the
  store onto the LUKS mapper at boot and shipped the store assertion. See
  [The LUKS-serving render](#the-luks-serving-render-pr1-of-8211).
- **#8209** — evict the repo-secret-reachable credentials from `prd_terraform` (its own ADR).
- **#7226 / #5914** — pin the SSH host keys of web-1 and git-data (ADR-237). Staged; the open items
  are the [host-key pinning post-merge sequence](#host-key-pinning-post-merge-sequence-7226-5914)
  below:
  - [x] #7226 — closed 2026-09-22 by PR #8511; ADR-237 is `accepted` (PR #9036, host-key step 4).
  - [x] Mechanism: PR #8511 (pending merge at the time of writing). The CI bridge, the Terraform
    `connection` blocks and this workflow's two hops are strict; git-data's key is Terraform-minted
    and rotated on every replace; the app's transport pins when a pin is published (since
    PR #9096 it always pins, and an absent pin refuses).
  - [ ] Step 1 — every merge-triggered apply is `success` (the `web_1_host_key_probe` ran).
  - [x] Step 2 — rung-2 re-rehearsal, then the evidence-only PR. Done: rehearsal run
    [35914294265](https://github.com/jikig-ai/soleur/actions/runs/35914294265) (2026-09-23, `main`,
    `success`), evidence PR #8655 merged 2026-09-23 (#5914 issuecomment-5803357950).
  - [x] Step 3 — `git-data-host-replace` publishes `GIT_DATA_SSH_HOST_KEY`, and the
    run's inline `pin_load` step loads it (startup line `git_data_pin=present`).
    Done: replace run [36118115758](https://github.com/jikig-ai/soleur/actions/runs/36118115758)
    (2026-09-25); startup line `git_data_pin=present fp=SHA256:4eErmLfOuKM17zzNd+2so+26zojG0tsv9NMVNCuXpCs`
    at 2026-09-25T09:39:39Z (#5914 issuecomment-5830287903); re-read on the serving deploy under
    gate G2 before the step-6 merge (recorded in the PR #9096 body).
  - [x] Step 4 — the strict dry run reads `role=git-data-auth verdict=ok`; then tick this item and flip
    ADR-237 to `accepted` in a docs PR. Done: `git-data-cutover.yml` run
    [36119817656](https://github.com/jikig-ai/soleur/actions/runs/36119817656) (from `main`,
    2026-09-25) read `role=git-data-auth verdict=ok` with both hops pinned. The run exited 5 on
    `verdict=already_cut_over` — git-data serves the LUKS mapper from boot since replace run
    36118115758 — a store probe and not a host key. ADR-237 is `accepted` (addendum 2026-09-27).
    That verdict was retired by #8211 PR2's proof half: the probes now require the mapper.
  - [x] Step 5 — every erasure left pending by the pin window is discharged. Done: #5914
    issuecomment-5865758722 (window 2026-09-22T12:07:01Z to 2026-09-28T07:51:53Z: 0 events, 0 ids;
    proof run 36339208990 reused under the 5.2 rule).
  - [x] Step 6 — the #5914 follow-up PR deletes the app's unpinned fallback arm and closes #5914.
    Done: PR #9096.
  - **Flag-flip precondition (hard):** `GIT_DATA_STORE_ENABLED` is never set until the pin is present
    in `prd`, #5914 is closed, **and** #8211 pages on `git_data_replication_push` pin faults (with the
    store on, a stale pin fails every replication push, and today that failure does not page). The
    flag precheck's `TOFU_ARM present|absent|unknown` line is a reminder read from the dispatched
    source tree, not a control: it says whether that ref still carries the fallback arm, not what the
    running app does. The enforcing control is the app's pin resolver, which throws on an absent pin
    while the store flag is on. Only `TOFU_ARM absent` satisfies the reminder.
    **Since PR #9096 (#5914, host-key step 6):** the resolver throws on an absent pin whatever the
    flag says, and a dispatch from `main` reads `TOFU_ARM absent`, which satisfies the reminder. The
    other conditions stand: the pin present in `prd`, #8572 paging, and #8211's per-id re-erasure
    path (the flip must not happen before it exists; see host-key step 5, "Requests after the
    window").
    **Since #8572:** the paging condition is met once its PR has merged **and** both of its runs
    are green: `apply-sentry-infra.yml` (it creates the `git-data-host-key-pin-fault` rule and adds
    per-event re-paging to `art17-erasure-incomplete`) and `web-platform-release.yml` (it deploys the
    emitter). Check the live rule, not only its name: the rule's `in` set is
    `host_key_mismatch,pin_absent,pin_invalid,ssh_client_absent`, it is enabled, and it emails
    issue owners, falling back to active members. `scripts/sentry-alert-live-fidelity.sh` diffs
    every live rule field by field against the Terraform projection: read the latest
    `scheduled-sentry-alert-drift.yml` (or `apply-sentry-infra.yml`) run for
    `sentry_alert live fidelity: PASS`. Before the flip only its boot arm can fire, so "no `pin_fault` event" never
    counts as healthy: a network attacker can hold every dial before the host-key check, which
    stays unclassified, so the flip check needs positive replication evidence. #8211's per-id
    re-erasure path stays a **hard** precondition beside it.
  - [ ] **An ssh client in the web-platform image** (PR #9096): the startup line reads
    `git_data_ssh_client=present` on the deployed build
    (`doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 30m --grep git_data_ssh_client=`).
    Until PR #9096, `node:22-slim` plus `--no-install-recommends` shipped no `ssh` (git only
    Recommends openssh-client), so every app-side git-data dial failed ENOENT: every Art. 17
    erasure read `unreachable`, and no replication call could run. Required before
    `GIT_DATA_STORE_ENABLED` flips.
- A fresh `git-data-host-replace` plus a `GIT_DATA_LUKS_KEY` rotation immediately before the real
  cutover, so nothing planted during the read-only period survives into it (ADR-220 D6).
- **The host's own liveness heartbeat is armed and measured (#9438, hard).** The `flip` freezes
  writes on this host, and the finalizer can only report what it can reach, so a host that is dark
  between boots must page BEFORE the flip. Satisfied means all of: `soleur-git-data-host-prd` was
  armed after a measured `up` transition on the CURRENT host (the manifest row's `arming_pending` is
  gone), and a re-read at the flip dispatch shows it `up` with a `state=ok` event under 15 minutes
  old and later than that host's `boot_complete`. A box ticked once goes stale at the next replace,
  so it is RE-READ, never remembered. **Armed 2026-10-12 (#9438, record PR):** the host that
  replace run 38140050880 created (its `boot_complete` was read; the run's own conclusion is `failure`, at
  a post-apply step after "Apply complete") was armed with `--arm-one` (#9980), `outcome=armed`, `status=up`
  within 11 s, id 506836; the pre- and post-arm `--status` reads are on #9438. That is one read at one
  instant, not the flip-time re-read, which is still taken at the flip dispatch and is the binding one. The
  pre-arm soak read (step 6) is not recorded in this PR or on #9438. Procedure and reads:
  [Liveness heartbeat](#liveness-heartbeat-9438). Until #9943 enforces it in the workflow, this item
  and its re-read are the only control.
- **No post-flip rotate route is accepted, in writing (#10175).** The owner has recorded that from the first flip no
  workflow dispatch can rotate the LUKS key until #8571 or the "store measured empty" marker lands, and names the
  [break-glass](#when-a-rotate-is-needed-after-the-flip-10175) as the only route for a key compromise.
- **#8101** — remaining: the hooks copy, the post-copy fence readback and the wrappers' mapper
  assertion, carried in #8211 ("Carried from #8101"). The wrapper edit is hash-bound, so it follows
  the [two-PR sequence](git-data-rung2-rehearsal.md#changing-the-payload-the-two-pr-sequence). The
  dry run's fence probe is in place.
- The legal-activation dependencies on the roadmap row for #5274 (Article 30 PA-36, #8101, #8094).

A dispatch on the retired vocabulary (`DRY_RUN`/`ROLLBACK`/`CONFIRM_WIPE`) refuses
`verdict=real_cutover_unreconciled` (exit 5) before any remote call; `MODE` is the real selector.

### The modes

```bash
gh workflow run git-data-cutover.yml --ref main -f mode=<MODE> -f confirm=<TOKEN>
```

| mode | confirm token | what it does |
|---|---|---|
| `proof` | `CUTOVER-GIT-DATA` | the read-only gate below; refuses `flag_already_true` under an on flag. |
| `flip` | `FLIP-GIT-DATA` | preconditions (Tier-B seam, live pin-fault rule, `d6_replace_stale`, no deploy in flight, running image >= emitter floor) -> proof -> freeze -> flag on -> webhook redeploy -> `git_data_store=enabled` per host (web-1 matched under either Better Stack `host_name` spelling — `soleur-web-platform` or the live #6616 mislabel `soleur-inngest-prd`) -> unfreeze -> probe -> `GIT_DATA_LUKS_CUTOVER_AT` stamp. Any failure after a flag write was attempted runs the total-unwind finalizer; a gc-timer-only failure does not (see the Verdict map). |
| `rollback` | `ROLLBACK-GIT-DATA` | flag off + the same redeploy + `git_data_store=disabled` readback + unfreeze. Never touches a mount or volume. |
| `unfreeze` | `UNFREEZE-GIT-DATA` | clears a same-lineage sentinel + restarts `git-data-gc.timer` (exit 6 if the timer will not start). A STRANDED sentinel (its writing run is dead) needs `-f lineage=cutover-<dead run id>`. Foreign or unattributed sentinels refuse. |
| `redeploy` | `REDEPLOY-GIT-DATA` | the standalone pin-load/same-version redeploy lever (no flag or host touch). |
| `wipe_check` | `WIPE-CHECK-GIT-DATA` | the read-only front of the wipe (job `wipe`): the soak precheck in report-only form, the provider reads, the boot-signal read and the one-session host assertion including the host-local counts-only listing (a transient device-mapper snapshot with a RAM copy-on-write file, removed before the run ends; a killed run can leave one, see `snapshot_clear`). No loader, detach or delete call. Takes `volume_id`. Ends `NOT authorization`. |
| `snapshot_clear` | `CLEAR-SNAPSHOT-GIT-DATA` | removes a LEFTOVER throwaway device-mapper snapshot of the plaintext volume (job `wipe`, no Tier-B loader, no provider write): the W4 identity read, the SSH bridge, then the host verb with phase `clear`. It proves the leftover is the one the listing makes (origin = the typed device, non-persistent, a loop-backed COW and any mount under the pinned `/dev/shm/tmp.<id>` directory) and refuses `wipe_snapshot_not_ours` otherwise; with no leftover it answers `snapshot=absent`. It never detaches or deletes a volume. See [A leftover snapshot](#a-leftover-snapshot-snapshot_clear). Owner-gated by the same environment as `wipe`. |
| `wipe` | `WIPE-GIT-DATA` | detaches and then deletes, at the provider API, the plaintext volume the owner names by `volume_id`, after the full evidence front. Owner-named, environment-approved. See [The wipe](#the-wipe-dl-2-10138--6897). |
| `wipe_finish` | `WIPE-FINISH-GIT-DATA` | finishes a wipe that stopped between its detach and its delete; takes `volume_id` and `origin_run` (the original `wipe` run). Makes zero detach calls. |

The wipe family also takes `volume_id` (and `wipe_finish` also `origin_run`), refused for every other mode. The headless `pending_deployments` approval form is never valid for any of the three.

### Downtime and blast radius (read before approving each dispatch)

Per `hr-prod-host-config-change-immutable-redeploy`, every mode states what it takes down. Each figure
names where it was measured; a figure marked *not measured* is an upper bound or a floor, never a
promise.

| mode | what stops serving | for how long | source |
|---|---|---|---|
| `proof` | nothing | n/a | read-only |
| `unfreeze` | nothing | n/a | removes the sentinel and restarts `git-data-gc.timer` (exit 6 if it will not start) |
| `flip` | **web-1's app container restarts** (web-1 is the singleton ingress, ADR-143 D2); the freeze refuses git-data store writes for the window between freeze and unfreeze | the same-version redeploy takes ~75 s as a release deploy job (runs 36970234398 and 36962950359, 2026-10-02: 74 s and 77 s wall time, both hosts). The container's own unavailable window is inside that and is *not measured*: no per-host availability probe exists. The job bounds are 2400 s for the redeploy and 900 s for the finalizer's unwind. | `gh run view <id> --json jobs` on the two runs; `track.sh` bounds |
| `rollback` | the same web-1 container restart, with the flag off; git-data keeps serving | as `flip`, plus the erasure probe that follows | as above |
| `redeploy` | the same web-1 container restart; no flag or host change | ~75 s | as above |
| `wipe_check` | nothing | n/a | no volume or provider state changes: provider API reads, a Better Stack read and one host-side session that creates and removes a transient host-local device-mapper snapshot (mounted read-only; a killed run can leave it, see `snapshot_clear`) |
| `snapshot_clear` | nothing | n/a | removes one LEFTOVER host-local device-mapper snapshot of the plaintext device, its loop device and its RAM copy-on-write file; no volume or provider operation |
| `wipe`, `wipe_finish` | nothing stops: git-data keeps serving from the LUKS volume. The retired plaintext volume (not serving since boot) is detached, then deleted at the provider API; no web restart, no flag write, no freeze. During `wipe` (and `wipe_check`), a transient host-local device-mapper snapshot of the kernel read-only plaintext device (copy-on-write file in RAM) exists on the git-data host and is removed before the run continues | *not measured*: no destructive run has happened; the job bound is 30 min (`timeout-minutes: 30`) | `.github/workflows/git-data-cutover.yml` job `wipe`; [The wipe](#the-wipe-dl-2-10138--6897) |
| `git-data-host-rotate` | **git-data is destroyed and rebuilt**: it serves nothing from the destroy until the new host's `boot_complete`, and every Article 17 erasure is refused and logged in that window (see below) | at least 12 min 15 s: the one recorded replace job ran that long before its boot poll budget expired with no `boot_complete` (run 35979304442, 2026-09-24, a failed boot; the poll step ran 09:09:47 to 09:19:37). A *successful* replace has *not been timed* in this record; record its job duration here after the first rotate. The pin redeploy that follows adds the ~75 s web swap. | `gh run view 35979304442` |

web-2 is a standby outside the ingress rotation (ADR-143 D2), so its swap has no user-visible effect.

**What a user sees while git-data is not serving (rotate) or the freeze is held (flip).** A Delete
Account request is refused by the store wrappers, the account deletion itself still completes, and each
refusal is a logged Art. 17 event (`op:git-data-bare-repo-erasure`). Before the first flip nothing is
lost, because the store is empty. After a flip the claim weakens: the app deliberately does not gate
erasure on the flag, so a re-flip or a freeze stranded after the first window can leave real repositories
behind, and the per-id re-erasure path for a populated store is not built (the CPO condition on #8211,
recorded in the plan). The refused ids are swept from Sentry (`op:git-data-bare-repo-erasure`, from the
start of the window) and re-driven afterwards, and the Art. 12(3) one-month clock runs from the request,
not from the re-drive; see #9153 for starting that clock automatically. During a `flip`, the freeze window is bounded by the finalizer: a stranded
sentinel pages through the notify channel below.

### When a cutover run fails (the notify channel)

`git-data-cutover.yml` has a separate `notify-failure` job. It runs when the cutover job fails, is
cancelled or times out, and when a rollback's erasure probe fails even though the rollback itself
succeeded. It opens or updates a `ci/git-data-cutover` issue (the primary channel) and sends the ops
email (secondary, best-effort). The body carries the run URL, the mode and verdict words only.

| verdict in the notification | meaning | next step |
|---|---|---|
| `FREEZE_HELD` | the finalizer could not clear the freeze sentinel (this includes a failed `mode=unfreeze` run, unless it failed only on the gc timer: that is `GC_TIMER_STOPPED`) | the recovery dispatch printed in the body: `mode=unfreeze` with `lineage=cutover-<id of the run that WROTE the sentinel>` (the notifying run's own id only if it froze the store); read the flag state first, and sweep the Art. 17 refusals from the freeze start (the CLO deadline in #9066 applies) |
| `GC_TIMER_STOPPED` | the freeze sentinel is clear and only `git-data-gc.timer` would not start (`gc_timer_restart_failed` in the unfreeze step or finalizer log); the word does not say the rest of the run succeeded, so read any other failing step first (the finalizer may have unwound the flip). Gc stays stopped, so the weekly pack and prune is skipped (one missed run per week is the exposure) | re-dispatch `mode=unfreeze -f confirm=UNFREEZE-GIT-DATA` (no lineage input: the sentinel is already cleared; do not `gh run rerun` the flip for this). A second consecutive failure is a host incident, not a transient |
| `RECOVERY_FAILED` | the unwind did not complete | check the flag in `prd`, both hosts' `git_data_store=` lines and the sentinel before any re-dispatch |
| `PROBE_FAILED` | after a rollback or flip, the probe's store pre-flight refused, or provision, push or remove failed | the probe step log names `residue_left` when a synthetic repo survived (the next boot's store count then refuses, and `mode=proof` shows it as `store_not_empty`); `mode=proof` (read-only) re-verifies the STORE only: no mode re-runs the erasure probe (a second `mode=rollback` exits `nothing_to_rollback`), so a green proof is not evidence that erasure works, and Art. 17 for the window is discharged with the Sentry sweep (query under "Store not empty", step 3). No finalizer cleans the synthetic repository. The probe verifies the store first, so a git-data host that is still booting reads as its store verdict in the probe step log (`old_store_unmounted`, `store_not_on_mapper`, `store_unverified` or `cutover_frozen`) and nothing was pushed or removed; `cutover_frozen` is cleared with `mode=unfreeze` and the lineage of the run that wrote the sentinel (the proof refuses it too); a repositories directory that is missing then surfaces later as `probe_failed reason=provision` |
| `FAILED` (no other word) | the run failed and its finalizer ran; it found no stranded freeze and no partial unwind | read the failing step in the run log; for `mode=proof` nothing on any host changed |
| `STATE UNKNOWN` | no finalizer output exists: the run was cancelled, timed out or lost its runner | read the flag, the sentinel and both hosts before anything else |

The wipe family (`wipe_check`, `wipe`, `wipe_finish`) reports through the same job with its own words, chosen before the generic logic, and no wipe word ever carries the unfreeze remedy: see the failure states S1 to S6 in [The wipe](#the-wipe-dl-2-10138--6897) and the Verdict map.

A failed run whose confirm step rejected the input (a typo in the confirm token, a bad mode) changed nothing and
does not notify. Not covered by the notify job, by platform design: a force-cancel (it skips `always()`), and a
pending run replaced by a newer dispatch in the `git-data-state` group before any job exists (a queued recovery
dispatch can vanish this way). A rollback that finds the flag already off (`nothing_to_rollback`) does not read a
held sentinel (its step says so; `mode=proof` reads it, and the `cutover_frozen` row below gives the lever); the deferred items are tracked in #9439 and #9897. Also open: flip resume arm B never unwinds the flag, and a rollback whose flag-off write landed but whose read-back failed leaves the fleet on the old env (a second `mode=rollback` exits `nothing_to_rollback`; `mode=redeploy` converges the fleet). The notify job is the only failure channel and has no fallback: if
it fails itself (no `RESEND_API_KEY`, an issues API error), the email step records its outcome in the issue, and a
failed `notify-failure` job shows red on the run's own summary, which is then the only signal.

### Before the first `flip`: the rollback rehearsal

The first `flip` is not authorized until a flip-then-rollback rehearsal has run once with the erasure
probe passing after the rollback. The probe proves the HOST wrapper contract (provision, fenced push and
remove with a synthetic id through the CI root key); it does not exercise the app's own erasure path
(`removeGitDataRepo` with its pin and ssh client in the redeployed web container). Pair the rehearsal with an
app-path signal before the flip: the pin-fault rule state and an `erasure_outcome` event for a canary id. Record its run URL here when it exists: *not yet run*. This is a
precondition recorded by #8211's plan review (the CPO condition: the rollback is shown to leave
erasure working); the rehearsal is dispatched only on the user's per-step authorization.

### The D6 rotate (dispatch BEFORE the flip)

**Never dispatch the rotate after the flip, or after any run that executed the flag-write step.** From the first
`flip` the LUKS volume may hold the only copy of the replicated repositories, and a rotate destroys it. The rule for
an operator is: dispatch a rotate only if no run of `git-data-cutover.yml` executed the `Write GIT_DATA_STORE_ENABLED`
step (any conclusion other than skipped, in any attempt). If the guard refuses with `store_dirty`, do not dispatch
again and escalate on #10175 and #8571; with `cutover_in_flight`, wait for that run and re-dispatch once; with
`scan_unreadable`, re-dispatch at most once and then stop and escalate. A flip that was
refused at a precondition, a `mode=proof` run and a rehearsal that never reached the write step leave the store
clean, and the rotate stays allowed. The apply workflow enforces the rule (#10175): the step `Rotate precondition —
store never written (cutover run records)` refuses the rotate once any attempt of any `git-data-cutover.yml` run
executed the flag-write step, whatever that step concluded (a failed or cancelled write may have landed), and a
rollback does not reopen it:
rollback is flag-off only and the data stays on the LUKS volume (ADR-239). There is no bypass input. The rule
reads run records, not the flag and not `GIT_DATA_LUKS_CUTOVER_AT` (the stamp survives a rollback, so it decides
nothing). See [When a rotate is needed after the flip](#when-a-rotate-is-needed-after-the-flip-10175).

`d6_replace_stale` requires a completed `git-data-host-rotate` run — a fresh host PLUS a re-minted
`GIT_DATA_LUKS_KEY`, volume and Doppler secret together (the passphrase can only rotate with a fresh
volume). A rotate run counts only when its job succeeded AND it carries the last-step marker
`Rotate completed (d6 marker)` (#10166): runs from before the marker cannot discharge D6, so the rotate
must be dispatched once more after that change merges (a destructive re-rotate: fresh host, re-minted
key). A later plain replace does not invalidate a stamp (it never re-mints the key); the stamp attests that
a rotate job completed, not the key-escrow state. Never re-run a rotate run from the GitHub UI: the gate
reads the latest attempt, so a re-run hides the failed attempt from it (the failed attempt stays visible with
`gh run view <id> --attempt 1`). A re-run that completes as a rotate stamps, but it re-executes the destructive
apply; one refused at the plan gate reads as nothing having happened and lets an older stamp discharge D6.
Dispatch a fresh rotate instead. A rotate run that dies before its precondition step (checkout or credential setup) or is refused at that step never reached the apply, so it reads `skip` like a failed plain replace: the run record carries no dispatch inputs to tell them apart, and an older stamp stays valid because nothing was changed (a ruled trade-off, 2026-10-13: the gate blocks only on an attempt whose apply began). (Two statements here are inferred from the run-record shape and have not been observed on a live run: that a re-run refused at the plan gate reads `skip`, and that an in-progress run which does not list the job yet is treated as in flight.) The gate
reads the 100 newest dispatch runs of the apply workflow (every target counts toward the 100), so a rotate
older than that is not visible to it. Dispatch it off `main`:

```bash
gh workflow run apply-web-platform-infra.yml --ref main   -f apply_target=git-data-host-rotate -f confirm=ROTATE-GIT-DATA -f reason="<why this rotate, with the issue number>"
```

The rotate's `served_repos=0` precondition reads the latest `stage=boot_complete` emit for
`host_name=soleur-git-data` out of Better Stack — pinned to the git-data source
(`t520508_soleur_git_data_prd_logs` UNION'd with the `s3` archive; the emit is once-per-boot, and the
shared inngest source the reader defaults to answers zero rows for this host) — and fails closed when
the store cannot be read empty. That reading is a once-per-boot observation, **not a live proof of
emptiness**: a flipped store takes writes without a reboot and the row still says `served_repos=0`. It
is therefore only a second layer: the step also requires the row to be strictly newer than the single
`soleur-git-data` server's Hetzner `created` time (so a row from a previous host cannot discharge it), and
the first layer is the run-record step above. Both steps run before the rung-2 interlock and every plan step.

| Rotate precondition refusal (step annotation) | Meaning | Action |
|---|---|---|
| `store_dirty` (names a run id) | That run of `git-data-cutover.yml` executed the flag-write step (any attempt, any conclusion). The store may hold the only copy of replicated repositories. | Do not rotate. Read [When a rotate is needed after the flip](#when-a-rotate-is-needed-after-the-flip-10175). There is no bypass input. |
| `cutover_in_flight` (names a run id) | A cutover run is still running. | Re-dispatch after it finishes. |
| `scan_unreadable` | A run record could not be read: an API error, a page or count mismatch, an unknown run status, no job named `cutover` or no flag-write step in a run created after the seam landed (a rename), or `scan_unreadable pinned_run_missing`: a pinned run is no longer listed as completed, so the history cannot be proven complete. A named run id (`scan_unreadable <id>`) with no job steps is an old post-seam run whose step list was stripped (see the re-baseline section). | Fail closed: an unreadable history is not a clean one. Re-dispatch at most once and then stop. For `pinned_run_missing`, see [Re-baselining the pinned runs](#re-baselining-the-pinned-runs-10175). Otherwise compare the step name constant in `scripts/lib/git-data-store-dirty-scan.sh` with `git-data-cutover.yml` (the parity test pins them). The name GitHub records is the YAML-parsed one, truncated at the first space-then-hash (`Write GIT_DATA_STORE_ENABLED (via the`). |
| `stale_boot_complete` | The newest `boot_complete` row is not newer than the current server's creation, so `served_repos=0` describes a previous host. | Wait for the current host's `boot_complete`, or investigate the emit path. |
| `boot_complete_unreadable` | The `boot_complete` time or the server's creation time could not be read (exactly one server named `soleur-git-data` is required; `HCLOUD_TOKEN` must be loaded). | Fail closed; re-dispatch once the read path is verified. |

The scan reads every attempt of every run (a re-run that skips the write step cannot hide the first attempt's
write). Runs created before 2026-09-30T02:18:17Z predate the write step and could not write the flag, so an
absent step there is clean (verified against the recorded runs, not enforced by code). Known residuals, accepted
by the owner as a floor against the accidental dispatch and not a defence against a hostile owner: a flag set
outside the workflow (a hand-run `doppler secrets set`, the Doppler API, a resume arm B load) is invisible to the
scan; a post-pin run record deleted by hand is outside the threat model (repository write access already allows a
dispatch); and the rotate is gated only by the typed token `ROTATE-GIT-DATA`, this guard and the `main`-only branch
policy of the `infra-privileged` environment, which has **no required reviewers**, so no human approval stands in
front of it. A rotate that is refused here has no in-workflow exit (below). A `d6_replace_stale` that fires again
after a flip attempt (the stamped rotate aged out of the 100-run window) is a deadlock the guard cannot resolve by
dispatch; the durable rotate stamp is tracked in #10216.

### Re-baselining the pinned runs (#10175)

The scan proves the history is complete by requiring two post-seam runs to still be listed as `completed` and their
step lists readable (`GDSD_PINNED_RUNS` in `scripts/lib/git-data-store-dirty-scan.sh`: `36685251588` from 2026-09-30
and `37823216637` from 2026-10-08). Run records can be deleted and `total_count` shrinks with them, so without that
proof a deleted flip would read clean. Two measured facts set the horizon (2026-10-13, read-only API): run records
are still listed at 196 days although the artifact-and-log retention setting reads 90 days, so the deletion horizon is
unknown and not relied on; and GitHub strips a job's step list at about 170 days, after which a step-less post-seam
job reads `unreadable`. The scan therefore turns closed by about **2027-03-18** at the latest (170 days after the
oldest pin), earlier if a pin is deleted. It prints a `::warning::` once the oldest pin is more than 120 days old, but
only while a rotate is dispatched, so the real early warning is the tracker #10216 calendar item for **2026-12-01**.
To re-baseline: while the old pins are still listed and readable, run
`GITHUB_REPOSITORY=jikig-ai/soleur bash -c 'source scripts/lib/git-data-store-dirty-scan.sh; git_data_store_dirty_list | git_data_store_dirty_scan'`
and require `store_clean`; then open a PR that sets `GDSD_PINNED_RUNS` to two newer completed runs of
`git-data-cutover.yml` (dispatch a `mode=proof` run if none is newer than the seam), and update the two run ids in
`plugins/soleur/test/terraform-target-parity.test.ts` only if its derived constants moved (they are read from the
library). **If the window is missed** (the guard already reports `pinned_run_missing`), the history can no longer be
proven complete from run records: the only exits are an owner attestation PR (owner and CLO reviewing) that moves the
pins and states, with evidence (the Doppler `GIT_DATA_STORE_ENABLED` value is not `true`, and no `git_data_store=`
readback of `enabled` in Better Stack since the last pin), that no flip happened in the gap; or the live emptiness
proof (#10211). After a flip the scan is dirty for good, so the pins can no longer be moved.

Moving the pins is not enough by itself once any other post-seam run record has lost its step list (about 170 days
after it was created): the scan reads every listed run, so that run reads `scan_unreadable <id>` until its record is
deleted or the owner attests it in the same PR. Plan the re-baseline PR to cover that too; the standing policy for
stripped post-seam records (an age-aware verdict plus the attestation) is tracked in #10216.

**Owner action after the #10175 PR merges:** a "Re-run failed jobs" on a rotate run that predates the guard executes
the OLD workflow, which has no guard. Delete those run records so nothing can be re-run:
`gh run delete 38140050880`, `gh run delete 38383684022`, `gh run delete 38384137515`. None carries the d6 marker, so
no stamp is lost, but the deletion DOES change the flip gate's reading: while run 38384137515 (a failed rotate
attempt) is the newest rotate record, `d6_last_rotate_failed` blocks the flip and an older success cannot override it;
once it and 38140050880 are deleted the gate reads `d6_replace_stale` (no stamped rotate), and a fresh rotate on the
never-flipped store is the next step. Deleting only one of the two failed attempts leaves the other blocking.

### When a rotate is needed after the flip (#10175)

The guard is a floor against the accidental dispatch, not a prohibition on ever rotating.

- **No bypass input.** The workflow offers none and the step carries no `continue-on-error`.
- **A suspected `GIT_DATA_LUKS_KEY` compromise (a Doppler secret exposure included) is an owner-run break-glass,
  not a workflow dispatch.** Contain first: revoke access to the secret and detach the volume per the host-incident
  procedure. Git-data is a replica of what the web hosts hold, so it is re-seeded from them (each workspace's next
  session end force-pushes every head and tag). Then land a reviewed PR that lifts the guard for one dispatch, with
  the owner and the CLO named as reviewers, then rotate. Containment within hours, re-encryption within days, and
  Art. 33's 72 hours counted from awareness.
- **Accepted residue.** An erased repository is unlinked, not overwritten (ADR-239), so the ordinary Art. 17
  residue stays until a copy mode (#8571) or the "store measured empty" marker (the follow-up below) lands. That
  acceptance is re-evaluated by **2026-11-12**, the date of the plaintext-volume outer-retention decision; a second
  slip returns to the CLO (ADR-239 Amendment 2026-10-12).
- **Escalate** on issue #10175 (the guard) and issue #8571 (copy mode), and to the owner.

Follow-ups, not built here: the mode-unique "store measured empty" marker step in `git-data-cutover.yml`, which is
the later live proof and the exit from dirty (#10211; blocked on #8571 for a populated store); the pinned-run
re-baseline, the durable rotate stamp, `delete_protection` on the LUKS volume and required reviewers on
`infra-privileged` (tracker #10216); #9943 (machine-enforce the
heartbeat flip precondition, merged design, a different workflow); #6975 (a per-host heartbeat suffix so a healthy
web-1 probe cannot mask a dead web-2-to-git-data path, a Terraform fan-out). The web-fed `soleur-git-data-prd`
heartbeat is not a flip precondition, so #6975 does not block the flip: the binding read is the host's own
`soleur-git-data-host-prd`.

## What the read-only dispatch does

`git-data-cutover.yml` (`workflow_dispatch`, input `confirm=CUTOVER-GIT-DATA`, from `main`). One job,
`cutover`, behind the `web-platform-infra-apply` environment approval. The whole run holds the
`git-data-state` concurrency group, so it never overlaps a git-data replace, birth or rehearsal.

1. Confirm token.
2. **Flag precheck** (`git-data-flag-precheck.sh`, the only step holding the `prd` read token). An empty
   token refuses `verdict=flag_token_absent`. A failed read refuses
   `verdict=flag_read_failed reason=<auth_invalid|config_not_found|forbidden|network|scope_mismatch|unknown>`;
   the reason is a fixed word mapped from the CLI's error, which is never printed. `scope_mismatch` means
   the token resolves a config other than `prd`, where a missing flag would read as unset.
   `GIT_DATA_STORE_ENABLED=true` refuses `verdict=flag_already_true`. All exit 5.
   It then prints the informational `TOFU_ARM present|absent|unknown` line (whether the app still
   carries the unpinned fallback arm, #5914) and reads git-data's host-key pin, `GIT_DATA_SSH_HOST_KEY`,
   with the same token. An absent or malformed pin, or a failed read, refuses
   `verdict=git_data_host_key_unavailable reason=<absent|invalid>` (exit 5), or `reason=<word> rc=<n>` when the read itself fails. A valid pin is
   written to `$RUNNER_TEMP/git-data.pin` and only its `SHA256:` fingerprint is printed.
3. **Secrets present.** An empty `DOPPLER_TOKEN_GIT_DATA_ROOT` refuses `verdict=git_data_root_token_absent`.
4. CF tunnel bridge to web-1.
5. **Key fetch** from the separate Doppler project `soleur-git-data-root`. A failure refuses
   `verdict=git_data_root_key_fetch_failed reason=<rc_nonzero|empty|not_openssh_key>`.
6. `ssh_config` writer (literal jump target, `IdentitiesOnly`, no forwarding). It writes one
   known_hosts file through the bridge's validated `write-known-hosts.sh`: `web-1` from the committed
   `apps/web-platform/infra/web-1-ssh-host-key.pub`, `git-data` from the precheck's pin. Both Host
   blocks are strict, each under its own `HostKeyAlias` and algorithm (ECDSA-P256 for web-1, ED25519
   for git-data); the `ProxyCommand` resolves to the web-1 block, so the jump hop is pinned too.
7. **Script.** First a configuration check (`probe=config`, exit 5, nothing dialed or printed): every
   configurable path is a safe literal. Then the access gate (`role=web`, `role=git-data-jump`,
   `role=git-data-auth`; exit 3 on any non-ok, including
   `verdict=host_key_mismatch reason=<changed|unknown|alg>`), then the fail-closed store probes
   (exit 5), in order:
   - `probe=store-mounted`: the store root is mounted on a device (`old_store_unmounted`);
   - `probe=store-on-mapper`: that device is the LUKS mapper `/dev/mapper/git-data`
     (`store_not_on_mapper`; ADR-239 D1 says the render never serves anything else);
   - then ONE ssh session reports two probes, so every fact is read at one instant.
     `probe=store-verified`: the store is still served by that device, the freeze sentinel
     `/mnt/git-data/.cutover-freeze` is absent (read first, so a frozen store reads frozen), the
     mounted filesystem has a UUID, and the bootstrap's marker `/etc/git-data/store-verified` (the
     one every store wrapper requires, ADR-239 D3) holds that UUID on its first line
     (`store_unverified reason=<no_fs_uuid|marker_absent|marker_mismatch>`, or `cutover_frozen`).
     `probe=store-empty`: `repositories/`'s containing mount is the store root, and it holds no
     entry except `.*.init.lock` dotfiles and `lost+found`, the bootstrap's own `_repo_count` rule
     (`store_not_empty`). A `store_unverified` means every wrapper refuses on the host right now;
     `cutover_frozen` means provision, remove, the transport wrapper and pre-receive do. The probes
     read as root while the wrappers run as git, so a permission fault can make the wrappers refuse
     where the proof passes: the proof is never **stricter** than the wrappers, and the git-user
     path is attested by `boot_complete erasure_probe=yes` and the fence probe's `runuser` checks.

   A probe that could not be answered is `probe_failed rc=<n>`; a dangling symlink, a missing
   repositories directory or a second mount over it is `probe_failed`, never a zero count.
   Then the **fence probe** (#8101, exit 5). It checks what a push actually depends on:
   - a real `root:git 750` hooks directory, under a root-owned parent nobody else can write;
   - a real `root:root 755` `pre-receive` that the `git` user can read and execute;
   - the installed transport wrapper pins pushes to that directory on git's command line, and the
     system `core.hooksPath` (includes resolved) names it too;
   - both sit on the store device the first probe accepted.

   It reads `probe=fence-shape verdict=ok`, `verdict=fence_not_intact reason=<word>`, or
   `probe_failed rc=<n>|reason=arg_<name>`. It checks the fence's shape, not which hook is installed.
8. Teardown, always.

Exit 0 means: root authenticated end to end; the store is served by the LUKS mapper, with the
bootstrap's store marker bound to its filesystem; it is not frozen; its repositories directory holds
no entry (lock dotfiles and `lost+found` excepted); and a push would run a root-owned `pre-receive` of the planted shape from that store. It does **not**
determine when encryption at rest became active for the Art. 30 register: that determination is
#8634's, and this dry run leaves it alone. Before PR #8511 a compromised web-1 could forge
that answer (ADR-220 D4). With both hops pinned (ADR-237), web-1 can no longer stand in for
git-data. A pinned key authenticates the host, not the truth of its answer: a compromised git-data
can still answer falsely, which is why the probes stay bounded and fail-closed.

Read the annotations without a dashboard:
`gh api repos/jikig-ai/soleur/check-runs/<job-id>/annotations --jq '.[].message'`, with the job id from
`gh run view <run-id> --json jobs --jq '.jobs[0].databaseId'`.

## Post-merge order (#8189)

Each prod step needs explicit authorization for that step. A menu acknowledgement does not count
(`hr-menu-option-ack-not-prod-write-auth`).

1. **Root-key apply.** Dispatch `apply-git-data-root-key.yml` from `main` with its typed confirm token,
   then approve the environment. The root is additive-only, with no exception: it refuses any plan other
   than a create of exactly its seven addresses or a no-op (`verdict=git_data_root_key_non_additive`,
   which also covers an import or a moved address). Once the fingerprint file is committed, it refuses a
   create of the key itself (`verdict=git_data_root_key_remint_refused`). It prints the key's `SHA256:`
   fingerprint read from Terraform state, and only after that value equals the fingerprint of the
   Hetzner key object's public key (`verdict=git_data_root_key_fingerprint_mismatch` otherwise). Any
   non-success except a run-level cancel emails ops through `notify-root-key-apply`.
2. **Fingerprint PR.** A PR commits the printed value to
   `apps/web-platform/infra/git-data-root-key.fingerprint` and merges.
3. **Replace.** Dispatch `apply-web-platform-infra.yml` from `main` with
   `apply_target=git-data-host-replace`. The replace gate's `git_data_root_key_arm` must pass. This is
   the only way the key reaches the host.
4. **Private-NIC readiness read** (below). It must read `up`.
5. **Dry run.** Dispatch `git-data-cutover.yml` from `main` and approve. It must read
   `role=git-data-auth verdict=ok`, clear the store probes and the fence probe, and exit 0.
   **Done:** first met by run [35119099336](https://github.com/jikig-ai/soleur/actions/runs/35119099336) (2026-09-16, before the fence probe and host-key pinning); met as now worded by run [36339208990](https://github.com/jikig-ai/soleur/actions/runs/36339208990) (2026-09-27, `verdict=clear`, #5914 issuecomment-5859802570).

### Private-NIC readiness read (step 4)

`web-git-data-probe.sh` runs on web-1 every 60 s. On a successful bounded TCP connect to `10.0.1.20:22`
over the private network, it pings the `soleur-git-data-prd` heartbeat (`betteruptime_heartbeat.git_data_prd`
in `git-data.tf`, period 60 s, grace 180 s). A green read proves the fresh host's private NIC is up and
its sshd port answers. It does **not** prove that git transport serves or that the root key was
delivered; the dry run proves that.

Read it no earlier than 4 minutes (period plus grace) after the replace run completed
(`gh run view <run-id> --json conclusion,updatedAt`), so a beat from before the replace cannot account
for `up`:

```bash
curl -fsS -H "Authorization: Bearer $(doppler secrets get BETTERSTACK_API_TOKEN_READONLY --plain -p soleur -c prd_terraform)" \
  'https://uptime.betterstack.com/api/v2/heartbeats?per_page=250' \
  | jq '.data[] | select(.attributes.name == "soleur-git-data-prd") | {id, status: .attributes.status, paused: .attributes.paused}'
```

- `up` — proceed to the dry run.
- `down` — the fresh host's private NIC or sshd is not up. A fresh Hetzner host can boot with its
  private NIC down (learning `2026-07-07-immutable-redeploy.md`). Re-dispatch the replace; both volumes
  are retained.
- `paused` — the heartbeat is not armed, so this read proves nothing. Arming is
  `arm-heartbeats.sh --arm` inside `apply-web-platform-infra.yml`, and it skips an address absent from
  state. Rely on the dry run's `role=git-data-jump` verdict for L3 instead.
- `pending` — Better Stack has not received a first beat since the heartbeat was created or unpaused.
  Treat it like `paused`: it proves nothing either way. Rely on the dry run's `role=git-data-jump`
  verdict.
- **No output** (the command prints nothing and exits 0) — no heartbeat named `soleur-git-data-prd` is
  in the listing. Treat it like `paused`, and rely on the dry run's `role=git-data-jump` verdict. A
  non-zero exit is a failed read, not an answer; read again.

## Host-key pinning post-merge sequence (#7226, #5914)

PR #8511 (ADR-237) pins web-1's host key on every CI path and git-data's on the cutover workflow
and in the app. It publishes no git-data pin by itself: the pin is created by the next
`git-data-host-replace`. Each prod step below needs its own explicit authorization
(`hr-menu-option-ack-not-prod-write-auth`).

1. **Merge.** From this merge on, any merge-triggered `apply-web-platform-infra.yml` run runs
   `terraform_data.web_1_host_key_probe` (a read-only `true` over the strict Terraform path) and must
   end `success`. Read the latest ones; every `conclusion` must be `success`:

   ```bash
   gh run list --workflow apply-web-platform-infra.yml --event push -L 5 --json conclusion,databaseId,createdAt
   ```

   The bash path was proven before merge (AC15): `workspaces-luks-verify.yml` run
   [35636913078](https://github.com/jikig-ai/soleur/actions/runs/35636913078), on branch commit
   `d916e62f1`, concluded `success` over the pinned strict path. Its log shows
   `pinned web-1 ecdsa-sha2-nistp256 SHA256:ARBTzhY4hCGXKwWZ2j9aOc4zZefBYgAxJncoVglvuok` and
   `workspaces-luks re-assert PASSED`.
2. **Rung-2 re-rehearsal, then the evidence-only PR.** Dispatch `git-data-rung2-rehearsal.yml`
   (`REHEARSE-GIT-DATA`, `dry_run=false`, `--ref main`), then land its evidence in an
   evidence-only PR ([two-PR sequence](git-data-rung2-rehearsal.md#changing-the-payload-the-two-pr-sequence);
   PR #8511 is the payload PR and deleted the old evidence file). Until that PR merges, **birth and
   replace refuse, including an emergency replace** — see "The rung-2 emergency-replace gap" below.
   - **HELD until PR #8564 merges** (the operator ruling on DC-2, posted on #5914). PR #8564 changes
     the same hash-bound payload, so a rehearsal dispatched for #8511 alone is voided by that merge.
     One rehearsal after PR #8564 covers both payloads. It must read the values in
     [The LUKS-serving render](#the-luks-serving-render-pr1-of-8211). This lengthens the gap in "The
     rung-2 emergency-replace gap"; that is the accepted price of not paying for two rehearsals.
3. **`git-data-host-replace`.**
   - The replace rotates the host key (`-replace` of `tls_private_key.git_data_host_ssh`),
     `git_data_boot_verify` passes (it includes the cloud-init boot proof that sshd serves exactly the
     Terraform key), and `GIT_DATA_SSH_HOST_KEY` publishes to `prd`.
   - The same apply run (replace, rotate or birth) loads the pin ITSELF: since #8211 PR2 the
     `git-data-pin-redeploy.yml` follower is retired and each git-data job carries an inline
     `pin_load` step that runs after a verified boot poll — it POSTs `/hooks/deploy` and polls
     `/hooks/deploy-status` for the same-version frame (`ok`, `start_ts` newer than the
     pre-dispatch baseline), redeploying the RUNNING image so every web host re-reads `prd` and
     picks up the rotated `GIT_DATA_SSH_HOST_KEY`. Check the apply run's pin_load step:

     ```bash
     gh run view <apply-run-id> --json jobs --jq '.jobs[] | select(.name | test("git.data")) | .steps[] | select(.name | test("pin")) | {name, conclusion}'
     ```

     It must be `success` (skipped is correct only when the boot poll did not pass — a red
     job). Better Stack must then show `git_data_pin=present` with the fingerprint the apply
     run printed (go/no-go below). If `pin_load` failed — webhook unreachable, a degraded
     fan-out, a timeout — the fleet still trusts the OLD pin and every git fetch/push fails
     host-key verification: verify with the same Better Stack check the cutover's per-host
     readback uses, then re-run the load by dispatching `git-data-cutover.yml` with
     `mode=redeploy` (the standalone lever — it runs track.sh without touching the flag or
     the host). Never re-dispatch the replace to get a pin-load.

   - **If the replace failed after the secret published:** re-dispatch the replace. The replace gate
     accepts that plan.
   - **If the replace failed before the new server was created:** state holds the new key, no server,
     and the old host's pin. The replace gate needs a server to delete, so re-dispatch
     `git-data-host-create` instead (see `git-data-birth.md`). The birth gate accepts a pin `update`
     only while the same plan creates `hcloud_server.git_data`.
   - **If only the pin-load failed:** never replace again for it. The pin load is the apply job's
     `pin_load` step (#8211 PR2 — the follower is retired); re-run it with the standalone lever,
     which runs the same track.sh without touching the flag or the host:

     ```bash
     gh workflow run git-data-cutover.yml --ref main -f mode=redeploy -f confirm=REDEPLOY-GIT-DATA
     ```

4. **Strict dry run.** Dispatch `git-data-cutover.yml` from `main`. It must read
   `role=git-data-auth verdict=ok` with both hops pinned. Then tick the #7226 item under Preconditions
   and flip ADR-237 to `accepted` in a docs PR.
   **Done:** run [36119817656](https://github.com/jikig-ai/soleur/actions/runs/36119817656) (2026-09-25) read `role=git-data-auth verdict=ok` with both hops pinned (it exited 5 on `probe=store-not-cut-over verdict=already_cut_over`, a store probe since retired); re-met clean by run [36339208990](https://github.com/jikig-ai/soleur/actions/runs/36339208990) (2026-09-27, `verdict=clear`). ADR-237 `accepted` 2026-09-27 (PR #9036); see Preconditions.
5. **Discharge the erasures left pending.** After the pin is fixed (step 3 GO) and before step 6 or any
   flag flip:
   1. Collect the repository ids from Sentry: every `op:git-data-bare-repo-erasure` event since the
      PR #8511 merge (2026-09-22T12:07:01Z), using the sweep query under "Store not empty" (step 3
      there) with its period widened to cover the merge. Do not filter on `erasure_outcome`: the
      `removeGitDataRepo threw` arm carries no such tag. Read every page: the list call returns a
      `Link: <…>; rel="next"; results="true|false"` header, so capture headers (`curl -D <file>`)
      and follow the cursor until `results="false"`. Run the sweep again just before you write
      the #5914 record; the window ends at that second read. **The ids stay in Sentry.** They go on
      no issue, PR, commit, workflow input or log, and neither does a hash of an id or of the list.
      This repository and its Actions logs are public, and `workspace_id` is `auth.users.id`. The
      record carries counts and Sentry issue ids only. **The agent transcript and the terminal are
      logs too:** never run the "Store not empty" step-3 block as written (its final `jq … @tsv`
      prints one id per line). Write the sweep as an uncommitted script that prints only counts
      and Sentry issue ids, run it as `doppler run -p soleur -c prd -- bash <script>` with
      `set +x`, send `jq`'s stderr to `/dev/null` (a `jq` error echoes the value it failed on),
      read each exit status, and feed ids only into an aggregating `awk` or `sort -u | wc -l`.
      Read the issue list AND each issue's `events/?full=true` with `curl -D` and follow
      `rel="next"`, keeping only events inside the window.

      **Also sweep by message text** (added 2026-09-28 by the first step-5 record, #5914
      issuecomment-5865758722). An Error-path report reaches Sentry as `feature=pino-mirror`
      without its `feature`/`op` tags (#8629), so the tag query alone reads 0 for it whatever
      happened. Until PR #9096 the erasure report used that path, and the `removeGitDataRepo threw`
      arm still does. So over the same window also run the free-text queries `"git-data erasure"`,
      `"refusing unsafe workspace_id"` and `"GIT_DATA_SSH_HOST is unset"` against the organization
      issues endpoint:
      `curl -G -D <hdr> --data-urlencode 'query="git-data erasure"' --data-urlencode start=<window start> --data-urlencode end=<window end> …/organizations/jikigai-eu/issues/`,
      with the same pagination, printing only each issue's `.id` and `.count` (never `.title`: the
      `refusing unsafe workspace_id` title embeds the raw id). De-duplicate hits against the tag
      sweep by issue id. Pair every zero with three positive controls: the token and host list any
      organization issue; the tag syntax (`feature:pino-mirror`) returns issues; free text on a bare
      phrase from an existing issue title returns it. A pre-#9096 Error-path erasure event carries
      its repository id and `detail` in its `category: "pino"` breadcrumb
      (`.entries[] | select(.type=="breadcrumbs") | .data.values[] | select(.category=="pino") | .data.gitDataRepoId`),
      not in `extra`; classify it by its message (`git-data erasure <status>`). Only the
      `removeGitDataRepo threw` arm carries no id; its known throws are pre-dial (see (d)).

      **Sentry is not a complete per-erasure record.** Sentry's default Dedupe integration drops an
      event identical to the previous one from the same process (same message, no stack), so two
      refusals with nothing between them reach Sentry once. The pino line (`log.error`, shipped to
      Better Stack) is written for every refusal and carries `gitDataRepoId` and `detail`. Count
      those lines over the window (`scripts/betterstack-query.sh … --grep git-data-bare-repo-erasure`,
      counts only) and compare with the Sentry event count; a mismatch means ids are missing from
      Sentry and must be read from Better Stack the same counts-only way.
   2. Dispatch `git-data-cutover.yml` from `main`, after the #8211 PR2 proof-half merge and its
      release deploy have concluded (`bash plugins/soleur/scripts/deploy-arm.sh find --wait
      <merge-sha>` prints `DEPLOY=success`, and `deploy-arm.sh served <merge-sha>` prints `CONTAINS`;
      waiting keeps the dry run off a host mid-redeploy).
      An existing `verdict=clear` run from `main` may be reused instead of a new dispatch when its
      head descends from the proof-half merge, that merge's deploy arm ended `DEPLOY=success`
      (`deploy-arm.sh find <full merge sha>`, then the arm run's `updatedAt`) before the run's
      `cutover` **job** started (`gh run view <id> --json jobs`), and no `web-platform-release.yml`
      deploy arm overlapped the job
      (`gh run list --workflow web-platform-release.yml --event workflow_run -L 40 --json databaseId,createdAt,updatedAt,status`
      against the job's `startedAt`/`completedAt`; a queued or in-progress deploy arm counts as
      overlapping). Only the deploy arm (`workflow_run`) redeploys the host; the push arm only
      builds, so it cannot move the host under the job. The wait is about when the job ran, not when it was dispatched (CTO ruling
      2026-09-28; first used by #5914 issuecomment-5865758722). The reuse holds only while
      `GIT_DATA_STORE_ENABLED` has never been on, which (c) re-reads. No per-id erasure
      trigger exists today, and none is needed before the first flag flip: the store cannot hold a
      repository while the flag has never been on.

      The job waits on the `web-platform-infra-apply` environment approval, which hands it
      `DOPPLER_TOKEN_PRD` and the git-data root key. The operator's approval is the single human input.
      An agent may approve only with the operator's explicit consent in the session for this run,
      and only after checking the run is the one it dispatched:
      `gh run view <id> --json path,event,headBranch,headSha,actor` must read
      `.github/workflows/git-data-cutover.yml`, `workflow_dispatch`, `main`, the merge SHA and the
      session's own actor; then read the environment id with
      `gh api repos/jikig-ai/soleur/actions/runs/<id>/pending_deployments` and approve with
      `gh api -X POST repos/jikig-ai/soleur/actions/runs/<id>/pending_deployments -F 'environment_ids[]=<env-id>' -f state=approved -f comment=<why>`.
      A run still unapproved at the end of the session is cancelled (`gh run cancel <id>`), because
      it holds the `git-data-state` group.

      This headless form is for the `cutover` job's modes only. It is never valid for any wipe mode
      (`wipe_check`, `wipe`, `wipe_finish`): see [The wipe](#the-wipe-dl-2-10138--6897).

      **Only a run ending `verdict=clear` discharges the collected ids**, and only with all four of
      these recorded:
      - **(a) The served LUKS store.** The run's `clear`, from a run on `main`: `gh run view <id>
        --json headBranch,headSha,event,conclusion` reads `main`, `workflow_dispatch`, `success`, and
        `git merge-base --is-ancestor <headSha> origin/main` succeeds. The annotations
        (`gh api repos/jikig-ai/soleur/check-runs/<job-id>/annotations --jq '.[] | select(.annotation_level=="notice") | .message'`)
        read the nine notice lines; the flag precheck's `TOFU_ARM present` warning is expected
        until step 6, and the `flag=` precheck line appears only in `gh run view <id> --log`.
        (Since PR #9096 a dispatch from `main` reads `TOFU_ARM absent`; a `present` warning there
        is a finding.)
        `probe=store-empty verdict=ok` means no entry under `repositories/` on the served store when
        the run was made, except `.*.init.lock` dotfiles and `lost+found`.
      - **(b) The retained plaintext volume.** Read the **current** instance's `boot_complete` line
        from Better Stack. It must read all three of `plaintext_volume=present`,
        `plaintext_empty=yes` and `served_repos=0`. `plaintext_empty=yes` alone is not this
        evidence: the bootstrap also emits it with `plaintext_volume=absent` when no plaintext
        volume id was rendered, and then it read nothing. `present` means the bootstrap was given
        the id Terraform renders from `hcloud_volume.git_data` and counted that volume through a
        read-only snapshot. Both counts skip `.*.init.lock` and `lost+found`, so (b) says nothing
        about lock files; (d) covers those. git-data ships to its own Better Stack source, so the
        read names that table; the anchor is the replace run's own `boot-trail anchor` line:

        ```bash
        A=$(gh run view <replace-run-id> --log | sed -nE 's/.*boot-trail anchor: ([0-9]+) .*/\1/p' | head -1)
        doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh \
          --table t520508_soleur_git_data_prd_logs --table-s3 t520508_soleur_git_data_prd_s3 \
          "SELECT dt, raw FROM (SELECT dt, raw FROM remote(\$BS_TABLE) UNION ALL SELECT dt, raw FROM s3Cluster(primary, \$BS_TABLE_S3) WHERE _row_type = 1) WHERE dt > fromUnixTimestamp($A) AND JSONExtractString(raw,'stage') = 'boot_complete' AND JSONExtractString(raw,'host_name') = 'soleur-git-data' ORDER BY dt DESC LIMIT 1 FORMAT JSONEachRow" \
          | jq -r '.raw | fromjson | "plaintext_volume=\(.plaintext_volume) plaintext_empty=\(.plaintext_empty) served_repos=\(.served_repos)"'
        ```

        Record it with the replace run that produced the instance (36118115758 unless a later one
        ran), and show that no host was created since: the server's `created` time
        (`doppler run -p soleur -c prd_terraform -- sh -c 'curl --disable --noproxy "*" -sS -H "Authorization: Bearer $HCLOUD_TOKEN" https://api.hetzner.cloud/v1/servers?name=soleur-git-data' | jq -r '.servers[0].created'`)
        falls inside that replace run, and no later `apply-web-platform-infra.yml` dispatch ran a
        `git_data_host_replace` or `git_data_host_create` job to `success`
        (`gh run list --workflow apply-web-platform-infra.yml --event workflow_dispatch --created '>=<replace start>' --json databaseId`,
        then per run `gh run view <id> --json jobs --jq '.jobs[] | select(.name | test("git_data_host_(replace|create)")) | "\(.name) \(.conclusion)"'`).
        The replace run's own poll step already failed the run unless `plaintext_empty=yes`, so a
        `success` there is a second, weaker source. The marker alone is not this evidence: a
        same-instance bootstrap re-run that FATALs before it removes the marker can leave an older
        one in place. The volume has not been mounted by the render since (ADR-239 D2).
      - **(c) The flag was never on, since before either volume existed.** Record the run's flag
        precheck line, then extend "Two reads to record", read 2: page `doppler configs logs` for
        `GIT_DATA_STORE_ENABLED` back past the `created` time of the **older** of
        `hcloud_volume.git_data` and `hcloud_volume.git_data_luks` (read both with the token above:
        `…/v1/volumes?name=soleur-git-data-store` and `…/v1/volumes?name=soleur-git-data-luks-store`,
        `.volumes[0].created`, GET only). The web containers load `--project soleur --config prd`
        only (`ci-deploy.sh`), so `prd` is the config to page; record that. Read the logs after the
        proof run completes. This read is required: the counts see entries, not freed blocks, so a
        repository written and then deleted would be invisible to them, and only the flag's history
        since the volumes were created excludes one.
      - **(d) No lock file for the collected ids.** Once its guards pass, `git-data-remove.sh`
        opens `REPO_ROOT/.<workspace_id>.init.lock` and never removes it. Neither the proof nor the
        bootstrap count sees it, because both skip `.*.init.lock`. The file is 0 bytes, but its name
        is the user's id, so it is personal data on the store. That describes the pre-#9226 wrapper; since
        #9226 the wrapper opens one shared `.init.lock`, which carries no id, and the host was replaced onto
        that payload on 2026-10-08 (per the workflow run and its head commit, not read from the host; ADR-239, amendment 2026-10-09). Files written before then still count
        here. Classify every
        `op:git-data-bare-repo-erasure` event in the window, per id, by its `erasure_outcome` tag
        and `detail`:
        - **host not reached:** `unreachable`, `unauthorized`, `host_key_mismatch`, `unconfigured`
          (including `ssh_client_absent:` since PR #9096), `threw` (since PR #9096 the
          `removeGitDataRepo threw` arm is tagged; its known throws are pre-dial), and events with
          no `erasure_outcome` tag (that arm before PR #9096) — **except** an `unreachable` whose
          `detail` shows the ssh was killed by its 30-second timeout, which may have connected and
          belongs in "lock may exist";
        - **refused before the lock:** `refused`, with a `detail` naming a guard the wrapper runs
          before it opens the lock: missing or unsafe `workspace_id` (empty, dot path, slash, unsafe
          characters), `mountpoint`/`findmnt` unavailable, store not mounted, not served by the
          mapper, store not verified, frozen, repo root not present, repo root not on the store,
          path escapes the repo root, lock path is a symlink;
        - **lock may exist:** any other `refused` detail (for example `could not acquire init lock`
          or `rm -rf failed`), and any detail you do not recognise.

        An id is discharged only if **every** one of its events is in the first two classes. Any
        id with a "lock may exist" event is not discharged here; it follows "If an item cannot be
        read" below. Lock files left by erasures that completed are not this step's to discharge;
        they are tracked in #9066.

      **If an item cannot be read, or an id is in (d)'s "lock may exist" class.** Nothing is
      discharged for the ids it affects; they stay pending. The same day:
      1. Post the record on #5914 using the template, with `outcome:` reading
         `NOT DISCHARGED — <item>: <what was read, and the error or the oldest date reached>`.
         Counts only, no ids.
      2. Open an issue labelled `clo-attestation`, titled
         `git-data Art. 17 discharge blocked (#5914): <item> — earliest Art. 12(3) deadline <date>`.
         Link the record and route it through `soleur:go`. The CLO rules on it and writes the ruling
         to `knowledge-base/legal/audits/`; the operator does not sign it off.
      3. Retry by reads only: (a) by the 5.3 rule; (b), (c) and (d) by re-reading the same source.
         Nothing in this step replaces a read with a write. A host replace to produce a new
         `boot_complete` needs its own authorization and is the CTO's decision.
      4. The CLO rules no later than 7 days before the earliest Art. 12(3) deadline among the
         affected ids. The ruling either discharges on the evidence that was read, with the gap
         stated in a new #5914 record, or extends the deadline under Art. 12(3) by two further
         months. An extension requires telling each affected data subject, with reasons, before
         the first month ends. Their accounts are deleted, so the ruling must name the channel
         that will be used.

      Record on #5914, using this template:

      ```text
      git-data store Art. 17 discharge (#5914, host-key step 5)
      proof run: <run id>  dispatched: <UTC>  head SHA: <sha>  (headBranch main, event workflow_dispatch)
        [reuse: <why an existing run qualifies under the 5.2 reuse rule>]
      notices (9): <the notice-level annotations, each cited by the ##[group]Run step that printed it>
      (a) counted: every entry under repositories/ except .*.init.lock and lost+found
      (b) instance: replace run <id>  boot_complete: <line, showing plaintext_volume=present plaintext_empty=yes served_repos=0>
          server created <UTC>; no replace or create run between that replace and the proof: <gh run list reference>
      (c) flag precheck line: <line>   oldest Doppler log entry reached: <date> (configs: prd)
          volumes created: git_data <UTC>, git_data_luks <UTC>
      Sentry sweep: 2026-09-22T12:07:01Z (the PR #8511 merge) to <time of this record>,
        op:git-data-bare-repo-erasure, not filtered on erasure_outcome, pagination read to the end:
        <n> distinct repository ids in <e> events, Sentry issues <issue ids>
        (the ids are kept only in Sentry extra.gitDataRepoId and are not reproduced here)
        also swept by message text: <the queries>: <n> issues each
        controls: <token/host>, <tag syntax>, <free text>; Better Stack erasure lines: <n> (vs <e> Sentry events)
      (d) per id: <h> host not reached, <r> refused before the lock, <m> lock may exist
      outcome: git-data store (op=git-data-bare-repo-erasure): no repository held for the <n-m> discharged ids
        (no entry under repositories/ on the served store at the proof or on either volume at boot, with
        lock dotfiles and lost+found not counted); nothing to erase
      not discharged: <m> ids, routed to <clo-attestation issue #> | none
      not covered: .<id>.init.lock files left on the served store and on the retained plaintext volume by
        erasures that passed the wrapper's guards, including completed ones (#9066); the user's
        copy in web-1 /workspaces (a separate operation)
        retained-volume limb: ends when the volume is destroyed (DL-2 wipe, #6897), never mounted to purge
        in place; served-store limb: removed only by the freeze-window purge, which has not run; gc cursor
        (.gc-cursor, may still hold the last repo's name, which can be the erased workspace's id, until a gc run
        completes another repo): not covered by either; dates and slip rule: ADR-239,
        amendment 2026-10-09
      earliest request: <date>  Art. 12(3) deadline: <date>
      ```

      Write "no repository held; nothing to erase", never "erased" and never "no data held". The
      user's copy in web-1's `/workspaces` is erased by a separate operation, and this record must
      not read as covering it. It does not cover lock files left by completed erasures (#9066)
      and says nothing about encryption at rest (#8634).

      **Requests after the window.** The window ends when the #5914 record is written. This record
      discharges nothing after that. The proof does not answer a later request: it reads the store
      as root at one moment and does not see how `git-data-remove.sh` runs for the git user. Each
      later request is answered by its own outcome. Only `erased` closes it; account deletion
      reports `erased` by emitting no `op:git-data-bare-repo-erasure` event, and the lock file it
      leaves falls under #9066. Every event after the record is a pending erasure: any
      `erasure_outcome` (`refused`, `unreachable`, `unauthorized`, `unconfigured`,
      `host_key_mismatch`) and the `removeGitDataRepo threw` arm. Follow its verdict-map row. Then,
      while `GIT_DATA_STORE_ENABLED` has never been on, discharge it by running 5.2 again: a fresh
      proof, fresh reads of (b) to (d), and a new record. After the first flip, emptiness is no
      longer evidence, so the flip must not happen until a per-id re-erasure path exists (#8211).
   3. Any verdict other than `clear` follows its verdict-map row; only `clear` discharges. After
      the row's remedy, re-dispatch **once**. A repeat of the same verdict opens an incident
      instead of a loop, and step 5 resumes with one re-dispatch after the incident closes. If the
      Art. 12(3) deadline is at risk, escalate to the CLO. A `store_not_empty` read stops here and
      follows "Store not empty": erasing those repositories is the incident's decision.
6. **The #5914 follow-up PR.** It deletes the app's unpinned fallback arm (`TOFU_FALLBACK_OPTS` and the
   `null`-pin path), removes `git-auth.ts` from the no-TOFU guard's allow-list
   (`tests/scripts/test-no-tofu-ssh.sh`), and closes #5914. Gate it on the positive step-3 startup line
   (`git_data_pin=present` on the current deploy), not on the absence of Sentry events. It must merge
   before any `GIT_DATA_STORE_ENABLED` flip.
   **Done:** PR #9096. After it, an absent or malformed pin refuses every git-data dial whatever the
   flag says (an erasure returns `unconfigured` `pin_absent:`), and an armed container booting
   without a pin emits `op=pin_absent_at_startup` (ADR-237, Addendum PR #9096). A step-5 record
   whose `outcome:` reads `NOT DISCHARGED` for some ids does not block this step, provided its
   `clo-attestation` issue is open with the earliest Art. 12(3) deadline in its title and nothing
   claims step 5 discharged everything (CLO ruling 2026-09-28): deleting the arm destroys no
   evidence and leaves the reads-only retry untouched. **Never revert PR #9096** to recover from a
   pin fault: a revert restores the unpinned arm AND its Guard 1 allow-list entry, so CI stays
   green. Republish the pin instead (see the pin-fault row).

Step 3 is **not** ADR-220 D6's fresh replace immediately before the real cutover. That replace is still
required; it now also rotates the host key and redeploys the app automatically.

### Deploy-day go/no-go (step 3)

- **GO** requires both:
  - Better Stack shows `git_data_pin=present fp=SHA256:X`, where X is the fingerprint the **source**
    apply run (the replace or birth) printed. The redeploy never reads Terraform state, so it cannot
    print X itself. Read X from that run's log (the same line is in its job summary):

    ```bash
    gh run view <apply-run-id> --log | grep 'git-data host key fingerprint'
    ```

    Then read the startup line. It is logged at warn level because only lines at warn or above reach
    Better Stack. The redeploy can wait up to 75 minutes for its release, so a fixed `30m` window can
    miss the line: start the window at the apply run's start (UTC), and read the newest line after
    the redeploy run's deploy finished:

    ```bash
    doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh \
      --since 'YYYY-MM-DD HH:MM:SS' --grep git_data_pin=
    ```

  - Zero Sentry events tagged `erasure_outcome` between the replace dispatch and that line. The query
    must print nothing; read any issue it lists in full with `scripts/sentry-issue.sh`:

    ```bash
    SENTRY_ISSUE_RO_TOKEN=$(doppler secrets get SENTRY_ISSUE_RO_TOKEN -p soleur -c prd --plain)
    curl -fsS -H "Authorization: Bearer ${SENTRY_ISSUE_RO_TOKEN}" \
      'https://jikigai-eu.sentry.io/api/0/organizations/jikigai-eu/issues/?query=feature%3Aaccount-delete%20op%3Agit-data-bare-repo-erasure%20has%3Aerasure_outcome&start=<dispatch ISO>&end=<now ISO>' \
      | jq -r '.[] | [.id, .count, .title] | @tsv'
    doppler run -p soleur -c prd -- scripts/sentry-issue.sh --latest-event <issue-id>
    ```

    If there are any, collect the repository ids with the sweep query under "Store not empty" (step
    3) and discharge them in post-merge step 5.
- `git_data_pin=absent` or `git_data_pin=invalid` on the new deploy is **NO-GO**: the same-version
  redeploy did not load the pin. Since #8211 PR2 the loader is the inline `pin_load` step (or the
  standalone lever `git-data-cutover.yml` `mode=redeploy`, which runs the same track.sh without
  touching the flag or the host). Re-run the pin load by dispatching
  `gh workflow run git-data-cutover.yml --ref main -f mode=redeploy -f confirm=REDEPLOY-GIT-DATA`, then read
  again.
- **The first rotation cannot produce `host_key_mismatch`.** Until the redeploy, the app has no pin
  and stays on its fallback arm against the new host. Pin lag matters only from the second rotation
  on, and once the store flag is on it stalls replication pushes and fetches as well as erasures.
  **Since PR #9096 (#5914):** there is no fallback arm. A container without a pin refuses
  (`unconfigured` `pin_absent:`) and emits `op=pin_absent_at_startup`; a rotation's stale-pin window
  is unchanged (`host_key_mismatch` until the apply job's `pin_load` step loads the new pin).
- **A full revert of PR #8511 is never the rollback.** It would restore trust-on-first-use on every
  path. Every fix goes forward.

### Between merge and step 3

- **A dry run refuses at the precheck** with `verdict=git_data_host_key_unavailable reason=absent`
  (exit 5): no pin is published yet. That is expected. Run step 3; do not work around it.
- **Expected drift.** `scheduled-terraform-drift` shows a pending **replace of `hcloud_server.git_data`**
  (its `user_data` now carries the host key) plus creates of `tls_private_key.git_data_host_ssh` and
  `doppler_secret.git_data_ssh_host_key`, until step 3 applies them. Neither address is on any per-PR
  `-target` list, so no routine apply publishes a pin the live host does not carry.
- **Drift is red for this whole window, including the rung-2 gap.** While these three addresses are
  pending, a red drift verdict says nothing about anything else. Read other drift from the plan diff:
  any address other than these three is real drift. Step 3 is the deadline for this blind spot, so
  do not let the window run on.
- **The app logs `git_data_pin=absent`** at every start, and Sentry receives one
  `feature=git_data_host_key_pin op=pin_absent_store_disabled` event per process. Expected until step 3.
  Historical since step 3 (2026-09-25): PR #9096 deleted that event; an armed container without a pin
  now emits `op=pin_absent_at_startup` instead, and every erasure refuses.

### Operator-local applies enforce `host_key`

Every Terraform `connection` block that dials web-1 now sets `host_key = local.web_1_ssh_host_key`, so
an operator-local apply verifies web-1 exactly as CI does. A local apply must also export
`TF_VAR_terraform_version` equal to the workflows' `TERRAFORM_VERSION` (currently `1.10.5`), or it
re-triggers `terraform_data.web_1_host_key_probe`. If an operator-local apply fails at a
provisioner with a host-key error, the committed pin is wrong or web-1 was re-keyed: follow the H4
triage below. Do not edit the pin file to whatever the laptop sees; a re-capture follows the web-1
re-capture section.

### The rung-2 emergency-replace gap

PR #8511 changed the hash-bound git-data payload, so the rung-2 interlock refuses **every** git-data
birth and replace — an emergency one included — from its merge until the step-2 evidence PR lands.
ADR-237 records this as an accepted gap. Keep the window short: schedule the rehearsal right after
merge.

- **The break-glass path inside the gap** is the operator-local apply under the
  `OPERATOR_APPLIED_EXCLUSIONS` contract (ADR-096), with its own explicit authorization. Give it the
  same `-replace` and `-target` set as the gated replace job, so the host key rotates and the secret
  publishes with the host, and export `TF_VAR_terraform_version` as above. An operator-local apply
  runs no `pin_load` step (that arm lives inside the apply job): load the pin afterwards with
  `gh workflow run git-data-cutover.yml --ref main -f mode=redeploy -f confirm=REDEPLOY-GIT-DATA`. Read X from the published pin
  (`doppler secrets get GIT_DATA_SSH_HOST_KEY -p soleur -c prd --plain | ssh-keygen -lf -`), then read
  the startup line as in the go/no-go.
- **The known-good-tag route** under "Break-glass for the rung-2 interlock" is not a substitute. Inside
  the gap the only candidate tag predates PR #8511 (PR #8511 deleted the evidence file, so find it
  with `git log -1 --diff-filter=AM --format=%H -- apps/web-platform/infra/git-data-rung2-boot-evidence.env`;
  a plain `git log -1` returns the deletion): it boots a host with sshd's self-generated keys and
  publishes no pin, so it restores the pre-#8511 state (the app on its fallback arm, dry runs refusing
  `reason=absent`). Once a pin is published, a replace from such a tag leaves the pin not matching the
  host, and every pinned consumer fails `host_key_mismatch reason=changed`. Never use a pre-#8511 tag
  after step 3.

## The LUKS-serving render (PR1 of #8211)

PR #8564 makes the git-data render serve `/mnt/git-data` from the LUKS mapper `/dev/mapper/git-data`
at boot. There is no plaintext/LUKS toggle, no runtime repoint, and no separate cutover run that
moves the device. Why, what it costs, and which gaps are accepted: **ADR-239**. This section is only
what to do.

**The serving change is the ADR-237 step-3 replace.** It is the same `git-data-host-replace` that
publishes the host-key pin — PR #8564 adds no second replace. It runs while `GIT_DATA_STORE_ENABLED`
is off and the store holds no repository, and the fresh host comes up on the mapper.

**The #8511 rung-2 re-rehearsal is held until PR #8564 merges.** PR #8564 changes the hash-bound
payload, so it voids any evidence rehearsed for #8511 alone. Rehearsing #8511 first would buy a
rehearsal that PR #8564's merge immediately invalidates. The hold is posted on #5914; it replaces
"dispatch the rehearsal right after merge" in host-key post-merge step 2. One rehearsal on `main`,
after PR #8564 merges, covers both payloads and serves both ADR-237 post-merge step 2 and PR
#8564's own gate.

The rehearsal must read, in `boot_complete`:

```text
luks_mounted=yes fence_on_mapper=yes erasure_probe=yes plaintext_empty=yes
```

and its reboot arm must read `luks_reopen_ok action=reopened target=/mnt/git-data`. Any other
`target`, or any terminal boolean reading `no`, is a FAIL: see
[the rehearsal runbook](git-data-rung2-rehearsal.md#the-pr-8564-payload-what-the-rehearsal-must-read).

### Two reads to record before dispatching step 3

Both are linked from the replace run's summary. Neither touches a host.

1. **The flag is not `true`.** Dispatch `git-data-cutover.yml` from `main`. Before the replace it
   refuses at the precheck with:

   ```text
   verdict=git_data_host_key_unavailable reason=absent
   ```

   That line is the proof. `git-data-flag-precheck.sh` reads `GIT_DATA_STORE_ENABLED` and refuses
   `flag_already_true` **before** it reads the pin, so reaching the pin refusal means the flag was
   not `true`.

2. **The flag has never been `true`, for the CLO record.** Page back through the config log until
   the oldest entry predates the host's birth (2026-09-14):

   ```bash
   doppler configs logs -p soleur -c prd --page 1 --number 100
   doppler configs logs get <log-id> -p soleur -c prd
   ```

   Open any entry naming `GIT_DATA_STORE_ENABLED`. Record the oldest date the paging reached, so
   the record says how far back the evidence goes rather than implying it is unbounded.

### Boot order on the replace: what is already published when the poll reds

Measured against `apply-web-platform-infra.yml` and `git-data.tf`, not asserted from the plan:

- In job `git_data_host_replace`, the step `Terraform apply (git-data-host -replace)` (id `apply`)
  runs **before** the step `Poll for the git-data boot-completion signal (replace)` (id `poll`).
  `doppler_secret.git_data_ssh_host_key` carries `depends_on = [hcloud_server.git_data]` and is
  written by that apply. **So a red boot poll leaves the new pin already published to `prd`.**
- Since #8211 PR2 the pin-load is the job's own `pin_load` step, gated on the poll's `success`:
  a red boot poll skips it. The fleet then trusts the OLD pin until a redeploy — every web host's
  git fetch/push fails `host_key_mismatch`. This is exactly the failure the follower's
  `pin_published` email used to page on; now the apply run goes red with `pin_load` skipped and the
  published pin pending.
- Recovery is the standalone lever (it re-runs track.sh without touching the flag or the host):

  ```bash
  gh workflow run git-data-cutover.yml --ref main -f mode=redeploy -f confirm=REDEPLOY-GIT-DATA
  ```

### If the fresh host fails a boot check after step 3

Applies to `plaintext_unverified`, `plaintext_residue`, `luks_residue`, `fence_on_mapper=no` and
`erasure_probe=no`.

**Start with a read, never with another replace.** A second replace re-runs the same render against
the same volumes and reproduces the same FATAL, while destroying the host whose boot events are the
evidence.

1. Read the host's boot events. Better Stack carries `stage:bootstrap` with the FATAL reason;
   Sentry carries the same event through the `git_data_boot_fatal` rule:

   ```bash
   doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh \
     --since '<replace dispatch, UTC>' --grep 'FATAL'
   ```

2. Count the Art. 17 refusals opened by the window. No marker was written, so every Delete Account
   since the replace was **refused** — the deletion itself completed and nothing was left behind,
   because the store is empty, but each refusal is an Art. 17 event. Sweep the repository ids with
   the query under [Store not empty](#store-not-empty-store_not_empty) (step 3), widening its period
   to the replace dispatch, reading `extra.gitDataRepoId`, counts only, plus host-key step 5.1's
   message-text sweep for any part of the window before PR #9096.
3. **The fix is forward: PR, then rehearsal, then the evidence PR, then the replace.** That is hours
   to days. There is no shortcut, and the decision to hold or proceed is the operator's.
4. **There is no revert to a pre-PR1 tag.** Any tag without PR #8564 must also postdate PR #8511
   (see "The rung-2 emergency-replace gap"), and no rung-2 evidence exists for #8511's template
   alone — so such a tag cannot be birthed or replaced either. A pre-#8511 tag is worse still: it
   publishes no pin, and after step 3 every pinned consumer then fails `host_key_mismatch
   reason=changed`.
5. After the forward fix lands and a green replace reports `boot_complete` with every terminal
   boolean `yes`, **re-drive each swept id** and record each one on the Art. 17 record, so the
   register shows a discharge and not only a refusal.

`plaintext_residue` is the one branch that is not forward-only: the plaintext volume holds something,
it is retained and was only ever mounted read-only, so nothing has been lost. Stop, escalate to the
CLO, bump **#8571** (copy mode), and block the wipe until that decision is taken. Do not wipe either
volume — the contents are the evidence.

### 2026-09-24: the step-3 replace FATALed on a dirty journal (#5274)

Recorded, not edited into the steps above. Run 35979304442 applied cleanly and published the new pin
(`SHA256:WRk5AW6j9IHNpE9KJ3FpVZbDp4I9HerMD84LGP0uB48`); the fresh host FATALed at 09:09:30Z with
`reason=journal … has needs_recovery set` — ADR-239's accepted dirty-journal gap, because the
predecessor was destroyed while the plaintext volume was mounted read-write. Nothing was written.
The Art. 17 sweep over 09:07Z-09:32Z found no `erasure_outcome` issue. The forward fix reads the
volume through a dm snapshot and makes the rung-2 rehearsal reproduce a dirty journal (ADR-239
amendment 2026-09-24).

**The sequence, each dispatch stopping for the operator's explicit per-command go-ahead**
(`hr-menu-option-ack-not-prod-write-auth` — a menu acknowledgement is not write authority):

| # | Dispatch | Precondition | Clean means |
|---|---|---|---|
| G1 | `git-data-rung2-rehearsal.yml` `dry_run=false` (paid) | the fix PR merged | the run concludes `success`, and its evidence lands through an evidence-only PR |
| G2 | `apply-web-platform-infra.yml` `apply_target=git-data-host-replace plan_only=true` | the evidence PR merged **and** `gh issue view 8710 --json state,closedByPullRequestsReferences` shows #8710 closed by a merged PR (otherwise this rehearsal fires a production redeploy again) | the job's destroy-guard (`git_data_host_replace_gate`, `tests/scripts/lib/git-data-host-replace-gate.sh` — the single source for which addresses a replace may touch; neither volume is among them) admits the plan and the run concludes `success`, and no pin-load ran: the run's `pin_load` step is `skipped` (`gh run view <G2 run id> --json jobs --jq '.jobs[] | .steps[] | select(.id == "pin_load") | .conclusion'` — plan-only runs never reach it, and since #8211 PR2 the step is inline: no follower workflow exists to observe). For reference, run 35979304442 planned `6 to add, 1 to change, 4 to destroy` because `tls_private_key.git_data_host_ssh` and `doppler_secret.git_data_ssh_host_key` were not yet in state; with both in state the counts differ, so compare against the gate, never against that line. (Check amended 2026-09-30 by #8211 PR2: the follower is retired — the pin load is the job's own `pin_load` step.) |
| G3 | the same, real (one attempt) | G2 read clean | GO, below |
| G4 | `git-data-cutover.yml` strict dry run | G3's `boot_complete` | `role=git-data-auth verdict=ok` |

Between G1 and the evidence PR, hold every merge that touches a file the evidence hash binds: each
voids the hash and costs another paid G1 (cap: 2 per payload hash). The set is derived, not listed
— `git_data_rung2_bound_files` in `tests/scripts/lib/git-data-birth-readiness-gate.sh` prints it
(17 files on 2026-09-24: `cloud-init-git-data.yml`, the three `modules/git-data-userdata/*.tf`, and
the 13 `file()`-bound payloads, among them `git-data-bootstrap.sh`, the `git-data-gc*`,
`git-data-luks-reopen*` units and scripts, and `git-data-{provision,remove,transport-wrapper,pre-receive-placeholder}.sh`).

**Downtime.** G3 destroys the serving host: git-data serves nothing from the destroy until the new
host's `boot_complete`, and the pin redeploy that follows redeploys the web platform to load the new
fingerprint. Dispatch G3 in a low-traffic window.

**GO for G3 means all three:** Better Stack shows `git_data_pin=present fp=<G3's fingerprint>` from
a pin redeploy caused by **that** replace run (not 35979135707, which the `plan_only` rehearsal
triggered — #8710 — and not 35980551109); zero Sentry `erasure_outcome` events in the window; and G4
reads `role=git-data-auth verdict=ok`. The replace boot must also emit `boot_complete` with
`plaintext_journal=dirty plaintext_empty=yes fence_on_mapper=yes erasure_probe=yes`. A production
`plaintext_journal=clean` is **NO-GO and an incident**: the volume was measured dirty on 2026-09-24,
so a clean journal means something replayed it — a write to the retained volume.

**G3 is capped at one attempt.** A failed G3 leaves the Doppler pin naming a host that serves nothing
(harmless: nothing can use git-data until a boot writes the marker, and the next replace re-pins).
Recovery is a read first, never a second replace.

**Art. 12(3).** Sweep the refused erasures from Sentry over the window **from the start of run
35979304442** (refusals began when the predecessor was destroyed, not at the 09:09:30Z FATAL) to the
G3 marker, querying `op:git-data-bare-repo-erasure` (pre-FATAL refusals may have surfaced through the
`removeGitDataRepo threw` path rather than `erasure_outcome`), and re-drive each id by
**2026-10-24**. Record the count and the Sentry issue ids on #5914, never the ids themselves (host-key step 5.1). If G3 has not reached GO well before then,
escalate to the CLO rather than rushing G3.

### 2026-10-13: the real rotate's first boot lost the volume-attachment race (#10138)

Recorded, not edited into the steps above. `git-data-host-rotate` run 38384137515 applied (7 added,
3 changed, 7 destroyed; measured, apply log, 2026-10-13), and the fresh host's bootstrap then died at
10:37:11Z with `FATAL: plaintext_unverified reason=source — /dev/disk/by-id/scsi-0HC_Volume_106867358
does not resolve to a block device`; the boot poll ended `VERDICT=silent` after its 20 reads
(measured, same log). The attachment timings, and why they overstate guest-side latency, are in
ADR-239's 2026-10-13 amendment; they are not repeated here.

**State left behind.**

- Server 170081857 and LUKS volume 107125716 were created (measured, apply log, 2026-10-13; a
  snapshot, not a current-state read). The old server and old LUKS volume were destroyed (same).
- The rotate's own precondition read `served_repos=0` before it destroyed anything (measured, its
  step log, 2026-10-13). Nothing was read from 170081857 or volume 107125716.
- That 107125716 holds no user repository is **inferred** (the bootstrap exits before any repository
  is created and the store flag is off), 2026-10-13. Whether the rotate's `served_repos=0`
  precondition can read a host that never emitted `boot_complete` is **unverified**: check that
  before the rotate, because it either wedges (see step 4) or reads 0 without having measured.
- The d6 gate reads `d6_last_rotate_failed 38384137515` (measured, the gate's own scan, 2026-10-13);
  only a newer successful rotate carrying the `Rotate completed (d6 marker)` supersedes it.
- No claim is made about the previous key's escrow, passphrase recovery or reopening.

**The fix** (PR #10210): the bootstrap waits 300 s (a lower bound on real time) at the plaintext link and the `luks_open`
heredoc's device wait is 300 counted passes (ADR-239 amendment). After the bound the same named
FATAL fires and the plaintext-empty verification is never skipped. The poll starts after
`terraform apply` returns and apply blocks on both attachments, so a waiting boot adds only its
post-attach tail (up to 56 s in rehearsal 38356246710, measured 2026-10-13 on a boot that did not wait;
that a waiting boot costs no more is inferred from the sequencing).

**Recovery order (forward only; each dispatch needs an explicit go-ahead that names the command).**
A new server is unavoidable: `user_data` is ForceNew and runcmd is once-per-instance, so no existing
path re-runs first boot on 170081857.

1. Merge the fix PR. Editing `git-data-bootstrap.sh` and `cloud-init-git-data.yml` moves the rung-2
   payload hash, so the rotate's interlock refuses until new evidence exists.
2. Rehearsal: `gh workflow run git-data-rung2-rehearsal.yml --ref main -f confirm=REHEARSE-GIT-DATA
   -f dry_run=false` (paid; it now delays both attachments on purpose, see the rehearsal runbook).
3. The evidence-only PR (see that runbook's "After a PASS"); its description states the delay the
   run actually applied, read from the run log. Hold every merge that touches a bound file until it
   lands.
4. If the sibling gate PR for the rotate precondition (#10207) merged as drafted, its
   `stale_boot_complete` refusal needs a `boot_complete` newer than the server's creation, and
   170081857 never emitted one (inferred, 2026-10-13: its bootstrap died at the FATAL before the
   emit, and nothing was read from the host): run a plain replace first
   (`apply_target=git-data-host-replace`, `plan_only=true` before the real one). Otherwise go to 5,
   but only once the rotate's `served_repos` read for 170081857 is confirmed to be a measurement and
   not a default (see "State left behind"): until then run step 4 anyway.
5. The rotate: `apply_target=git-data-host-rotate -f confirm=ROTATE-GIT-DATA`, `plan_only=true`
   first, then the real run. It destroys LUKS volume 107125716 and re-mints the passphrase again.

A plain replace outside step 4 buys no gate benefit. The schedule coupling is tracked on #10138: if
this sequence slips past about 2026-11-05, tell the CLO.

## The wipe (DL-2, #10138 / #6897)

The `wipe` job of `git-data-cutover.yml` retires the plaintext rollback volume (Terraform `hcloud_volume.git_data`, the Hetzner volume named `soleur-git-data-store`) by detaching it and deleting it at the provider API. It has four modes (`wipe_check`, `wipe`, `wipe_finish`, `snapshot_clear`; the table under "The modes" gives their confirm tokens), every one behind the `web-platform-infra-apply` environment, and every one names the volume by its id (`volume_id`). The `cutover` job is skipped for all four.

**What a run can claim.** The only claim any wipe run, step summary, notification, record or this section makes about the end state is that the DEVICE was deleted at the provider API: the DELETE returned 204, the read-back read 404 by id and an empty list by name, and the LUKS volume was still attached to the git-data server. A `wipe_finish` that finds the volume already absent made no delete call and claims less: the volume is absent at the provider API at its read-back, and the delete outcome is in the origin run (its summary says so and names the origin run). Nothing here states that the volume was empty or held no personal data; the host verb reports only pre-detach per-type counts and fixed words (an exit-34 refusal also carries one fixed 0/1 field and two counts [superseded 2026-10-19, from the merge of the change that adds the `hk_` group only: up to three fixed 0/1 fields and four counts, see the note below], see 'Reading the exit-34 line'), and no name read from the volume ever leaves the host. Standing line, the CLO's, which the run summary carries in its own words: this run does not address provider-side snapshot or backup retention of the volume (Art. 30 PA-36(f), not measured), the served store's lock residue, the `.gc-cursor` residue, or any copy held by someone with prior access. The record PR that follows (PR-C) states the end event in the CLO's form: device (Hetzner volume id N) deleted at T by run URL; provider API delete returned 204 and read-back was 404 (for a finish that found the volume absent: absent at the read-back, delete outcome in the origin run). It adds nothing about contents. Run logs, step summaries and notification emails are as public as #6897: they carry ids, counts and fixed verdict words only. In these words `snapshot` always means the transient host-local device-mapper snapshot that the pre-detach read takes (RAM copy-on-write, removed before the run continues), never a provider-side snapshot or backup.

> **Superseded 2026-10-19, as to "an exit-34 refusal also carries one fixed 0/1 field and two counts" above, from the merge of the change that adds the `hk_` fields only:** from that merge, and only when `has_hooks_d=1`, the refusal can also carry four more fixed fields: two counts (`hk_entries`, `hk_nonfile`) and two 0/1 bits (`hk_pr_f`, `hk_pr_small`), so a line can carry up to three fixed 0/1 fields and four counts beyond the five counts. They are digits and 0/1 bits only; no name read from the volume leaves the host, and they say nothing about contents. Shape recorded, refusal stands, content unread. No run has printed them, so they are not measured; run 39136900735 carries the earlier eight-field line, which stays valid. Until that merge the sentence above is accurate as written. This note does not otherwise change the paragraph above.

**Status (2026-10-14).** The mechanism exists (PR #10294, merged 2026-10-15). No `wipe_check`, `wipe`, `wipe_finish` or `snapshot_clear` has been dispatched (newest `git-data-cutover.yml` run 2026-10-08, read 2026-10-15). Anything marked UNVERIFIED below has not run against production. Update (2026-10-18, measured): two `wipe_check` runs have since been dispatched (read-only) and both refused with `wipe_boot_layout_signal_offlist`: run 39081408368, and [run 39136900735](https://github.com/jikig-ai/soleur/actions/runs/39136900735), the first to print the `has_hooks_d`, `lf_entries` and `offlist_n` fields (see 'Reading the exit-34 line'). As of the `gh run list` read on 2026-10-18, no `wipe`, `wipe_finish` or `snapshot_clear` had been dispatched; re-read the run list before relying on this. CLO addendum 2 ([#6897 comment](https://github.com/jikig-ai/soleur/issues/6897#issuecomment-6251181879)) lifted C1 for one further `wipe_check` only; run 39136900735 is that run and spent the lift. It refused at exit 34 before `lock_residue` and `store_root_repos` printed, so neither run printed either field and the closed posting list is unchanged.

**Status (2026-10-19).** Draft PR #10523 (Ref #10138 and Ref #6897, read 2026-10-19) adds the four `hk_` shape fields to the exit-34 line. The fields exist from the merge of that change and not before; they alter the stderr text of the exit-34 refusal and add four fixed exit-33 refusal words (`hooks_shape_failed`, `hooks_shape_unparseable`, `hooks_pr_failed`, `hooks_pr_unparseable`) that, when a read of `hooks` fails, replace the exit-34 line, under the existing verdict word `wipe_boot_layout_signal_absent`. No run has printed any `hk_` field, so each is not measured. Shape recorded, refusal stands, content unread. The allowlist, the exit-34 code, the verdict map and every gate are unchanged by that change, and it dispatches nothing. From that merge the closed posting list under 'Other results that route to the CLO' is the twelve-field list there (CLO ruling L3, 2026-10-19); the 'closed posting list is unchanged' clause just above describes the 2026-10-18 reading.

**Who names a dispatch.** The owner names each exact command (`hr-menu-option-ack-not-prod-write-auth`) and approves the environment in the owner's own session. The headless `pending_deployments` approval form is NEVER valid for any wipe mode (`wipe`, `wipe_finish`, `wipe_check`, `snapshot_clear`), and an agent never approves its own dispatch: the platform enforces the `main` branch policy but not the separation of dispatching from approving (ADR-241, amendment of 2026-10-07).

### Before naming `mode=wipe`

> Before naming `mode=wipe`, #6897 carries (i) the link to a READY PR-C, (ii) the main-dispatched empty-id rehearsal evidence (PR-R #10296) or a recorded owner acceptance of a longer wedge, and (iii) the dispatch-to-merge bound. The workflow does not check these. An agent does not propose the command until each is verified.

Items the CLO holds before the dispatch (not before the build): sign-off on the wording of the record PR, sight of the host-local device-mapper snapshot procedure (the transient RAM copy-on-write listing on the git-data host, not a provider-side snapshot), the routing of any off-allowlist, non-empty or reboot dead-end result (below), and the Better Stack retention measurement recorded on #6897. Once those hold, the owner naming the command is the trigger; no further CLO approval is needed.

The bound in (iii) is a recorded commitment, not a limit any workflow measures: a working bound of one business day from dispatch to PR-C's merge, written on #6897 before the dispatch. A breach returns to the owner, who records on #6897 whether to extend it; once 2026-11-12 has passed it returns to the CLO (ADR-239, amendment 2026-10-12: a second slip returns to the CLO). No agent extends it.

### Preconditions the workflow enforces (W3), and the ones it does not

The precheck step runs in all four modes. In `wipe_check` it is report-only: it prints the verdict `wipe` would have refused with and exits 0. In `snapshot_clear` it runs as `FLAG_MODE=pin_only`, only to write the git-data host-key pin the ssh_config step requires; it evaluates no predicate and prints no variant.

**Two variants (ADR-239 Amendment 2026-10-15; takes effect on merge of #10352).** The first line the precheck prints is `wipe_variant=flip_chained|separated|none`, chosen ONLY from two reads, the flag and the stamp, never from an input or an environment value. `flip_chained` (the flag reads `true`, OR the stamp is non-empty, valid or not) is the gate in the numbered list below, unchanged. `separated` (the flag read successfully as exactly `false` or unset, AND no stamp) needs neither a flip nor the 7-day soak; it needs, instead: the run-record scan `git_data_store_dirty_scan` returns `store_clean` (`wipe_separated_store_dirty`), a `boot_complete` row newer than the current server's creation with `served_repos=0` (W5), the typed id attached to the current server (W4), and the on-host read-only count `store_root_repos=0` of the LUKS store root (`wipe_separated_store_root_populated`). A flag value outside `true|false|unset` is `none` and refuses `wipe_precondition_flag_unreadable`; a non-empty stamp that is not a valid timestamp counts as present, so it can never reach `separated`: with the flag `true` it refuses `wipe_precondition_stamp_malformed`, and with the flag `false` the first refusal is `wipe_precondition_flag_not_true`. W7b re-asserts the variant (`wipe_precondition_variant_changed expected=<v> got=<v>`): a variant that differs from the one W3 printed is always a refusal. Do not dispatch `flip`, `proof`, `rollback` or `redeploy` between a `wipe` that detached the volume and its `wipe_finish`: `wipe_finish` re-derives the variant, and a flip run that reached the flag-write step turns the run-record scan to `store_dirty` (or changes the flag), so a detached volume would wait past the 2026-11-12 outer date with no workflow path to delete it. The numbered list below describes `flip_chained`.

1. **The flag reads exactly `true`.** Unset and `off` both refuse `wipe_precondition_flag_not_true`.
2. **The stamp `GIT_DATA_LUKS_CUTOVER_AT` is present** and reads `YYYY-MM-DDTHH:MM:SSZ` as a real date (`wipe_precondition_stamp_absent`). An unreadable stamp is a read failure (`wipe_stamp_read_failed`), not a predicate.
3. **Seven days have passed since the stamp** (`wipe_precondition_soak_not_elapsed`). The floor is the pinned constant `WIPE_SOAK_FLOOR_SECONDS=604800` in `apps/web-platform/infra/git-data-flag-precheck.sh`, assigned unconditionally: no input, environment value or variable lowers it. It is relaxed only by a reviewed diff of that one line, its pin test and this number, together with an ADR-239 amendment and a CLO ruling. No bypass is prepared. The seven days are an engineering rollback-safety floor. They are not a retention period and not a statement of how long the plaintext volume will be kept.
4. **The interim stamp guard.** Because a rollback does not clear the stamp today, the precheck also reads the last 100 runs of this workflow and refuses when a `git-data rollback` run (any conclusion: a failed rollback may have changed the flag) or a legacy-titled run, dispatched from `main`, was created at or after the stamp (`wipe_precondition_rollback_after_stamp`, `wipe_precondition_legacy_run_after_stamp`); an unclassifiable title, a full list that does not reach back to the stamp, or an unreadable list refuses too. End of life of this guard: delete it once #10297 lands (the rollback arm clearing the stamp).
5. **The flag is read again** just before the credential loader (W7b); a flag that is no longer `true` refuses there.

> **Superseded 2026-10-15 (#6897), as to "the latest flip stamp this runbook allows is 2026-11-04" below:** that date binds the `flip_chained` variant only. The `separated` variant needs no flip and no soak (ADR-239 Amendment 2026-10-15); its schedule is the CTO's: the wipe PR merged by 2026-10-30, `wipe_check` green by 2026-11-02, the owner names the command by 2026-11-02, dispatch target 2026-11-05 and last 2026-11-09 (inferred), the record PR merged by 2026-11-12.

What the workflow does NOT check: the three items under "Before naming `mode=wipe`", the state of PR-C, and whether another git-data run is pending.

Schedule. The outer date is 2026-11-12 (ADR-239). With the 7-day floor, a stamp at or before 2026-11-05T00:00:00Z satisfies the floor at 2026-11-12T00:00:00Z (2026-11-12 minus 604800 s). **The latest flip stamp this runbook allows is 2026-11-04**, one day earlier, which leaves a day for the approval and the run itself. If the flip cannot be stamped by 2026-11-04, tell the CLO.

**Standing rule: never rotate after the flip.** A rotate destroys the LUKS store, which after the flip may hold the only copy of some replicated repositories ([The D6 rotate](#the-d6-rotate-dispatch-before-the-flip); [When a rotate is needed after the flip](#when-a-rotate-is-needed-after-the-flip-10175)).

**Rule for the queue:** do not dispatch while another git-data run is pending (a pending run is replaced by any newer dispatch and a wipe waiting for approval holds the web-1-swap queue: approve or reject promptly). The replacement happens in the workflow-level `git-data-state` group, which keeps one pending run. A rejected or timed-out environment approval pages as `WIPE_STATE_UNKNOWN` (the job never published an output).

### Dispatch strings

The id is the Hetzner id of the volume named `soleur-git-data-store`, read at the provider API with the read-only token (a read; the id is also the dispatch input, so the run title carries it):

```bash
doppler run -p soleur -c prd_terraform --only-secrets HCLOUD_TOKEN_READONLY -- bash -c '
  printf "header = \"Authorization: Bearer %s\"\n" "$HCLOUD_TOKEN_READONLY" \
    | curl -sS --max-time 20 -K - "https://api.hetzner.cloud/v1/volumes?name=soleur-git-data-store" \
    | jq "[.volumes[] | {id, attached_to: .server, delete_protected: .protection.delete}]"'
```

Exactly one volume must be listed. The volume's own action history is a second read with the same token (no SSH). A detach that the provider accepted shows here while the volume still lists its server, so this read, not the `server` field, says whether anything is running:

```bash
doppler run -p soleur -c prd_terraform --only-secrets HCLOUD_TOKEN_READONLY -- bash -c '
  printf "header = \"Authorization: Bearer %s\"\n" "$HCLOUD_TOKEN_READONLY" \
    | curl -sS --max-time 20 -K - "https://api.hetzner.cloud/v1/volumes/<id>/actions?sort=id:desc&per_page=5" \
    | jq "[.actions[] | {id, command, status, started, finished}]"'
```

`status` reads `running`, `success` or `error`. A `detach_volume` action reading `running` is a detach still in flight. The `actions` line of a `wipe_check` run prints only the count and the latest command word, never the status, so use this read when the question is whether anything is running. Then, one command at a time, each named by the owner:

```bash
gh workflow run git-data-cutover.yml --ref main -f mode=wipe_check -f confirm=WIPE-CHECK-GIT-DATA -f volume_id=<id>
gh workflow run git-data-cutover.yml --ref main -f mode=snapshot_clear -f confirm=CLEAR-SNAPSHOT-GIT-DATA -f volume_id=<id>
gh workflow run git-data-cutover.yml --ref main -f mode=wipe -f confirm=WIPE-GIT-DATA -f volume_id=<id>
gh workflow run git-data-cutover.yml --ref main -f mode=wipe_finish -f confirm=WIPE-FINISH-GIT-DATA -f volume_id=<id> -f origin_run=<id>
```

To find the id of the original `wipe` run when no email carried it (a lost runner, or `WIPE_STATE_UNKNOWN`), list the recent runs and match the title `git-data wipe <volume_id>`: `gh run list --workflow git-data-cutover.yml --json databaseId,displayTitle,createdAt --limit 100`. The run that detached the volume is the one whose `wipe_detach_gate` step concluded `success` (`gh run view <run id> --json jobs` lists the steps). Read a failed step with `gh run view <run id> --log-failed`, never `--log`, which prints the whole job log.

`volume_id` is 1 to 12 digits and valid only for the wipe family; `origin_run` is numeric and valid only for `wipe_finish`. Each is refused for every other mode, and a `lineage` input is refused for the wipe family.

**"Re-run failed jobs" must never be used (nor `gh run rerun`) on a wipe-family run.** A re-run is attempt 2 and is refused by the attempt-1 rule in the first step, silently: no marker is written and no email is sent. Dispatch a new run instead.

Reading a refusal: **a red run with no email means the input was refused** (a typo in the confirm token, a bad id, an `origin_run` on the wrong mode, a re-run). Nothing was called. The first step writes `mode=` last, after every refusal, so a refused input leaves `started` false and the notifier stays quiet.

### Step order, and what each mode does

The order is pinned by the census: identity read, boot-signal read, host assertion, flag re-read, credential loader, detach marker, detach, post-detach host read, provider re-read, delete marker, delete, read-back.

- **`wipe_check`** (confirm `WIPE-CHECK-GIT-DATA`) runs the front only: precheck (report-only), the provider reads (`state`, the identity checks, the volume's action history: count and latest command word), the boot-signal read, the one-session host assertion including the counts-only host-local listing (a transient device-mapper snapshot, RAM copy-on-write, removed before the run ends), and teardown. It calls no loader, no detach and no delete. Its identity line prints the plaintext, LUKS and server ids, so the id to type can be read from the run. It ends with `NOT authorization; W3 would be <variant>/<verdict>; layout listing exercised: counts only`, and prints `elapsed_s` and the days to the 2026-11-12 outer date. Hold the first run that prints the residue counts (the first `wipe_check`, or a first `wipe` that has no prior `wipe_check`) until the DPD §10.3(b) re-ruling (due by 2026-10-24, and it may be made earlier) has landed: a numeric `lock_residue` or `repos` in its run summary (public: this repository is public) is a measurement the published disclosure must be reconciled with first (CLO ruling 2026-10-15, condition C1). Run it first: it is the only way to exercise the checks under the real credentials before the destructive dispatch, and several facts are first measured by it (see "Not proven").

  > **Superseded 2026-10-18, as to "Hold the first run that prints the residue counts" for run 39136900735 only ([run](https://github.com/jikig-ai/soleur/actions/runs/39136900735), CLO addendum 2 on #6897):** addendum 2 lifted C1 for one further `wipe_check`, and that run is run 39136900735; the lift is spent. This note does not otherwise change that hold. Both prior `wipe_check` runs refused at exit 34 and printed neither `lock_residue` nor `store_root_repos`. `repos` did print (`repos=0`) in both exit-34 lines; addendum 2 item 2 lists `repos` for the one further run, and whether run 39081408368's public `repos=0` fell under C1 is the CLO's to say. Any further `wipe_check` needs a new CLO addendum (addendum 2, item 7) and the owner to name the exact command ('Who names a dispatch'). Nothing in this note authorizes dispatching any mode; `wipe`, `wipe_finish` and `snapshot_clear` stay held (addendum 2). The DPD §10.3(b) re-ruling stays due 2026-10-24.
- **`wipe`** (confirm `WIPE-GIT-DATA`) runs the same front (the host-local listing included, as in `wipe_check`; it also reads the volume's action history in W4 and prints the count and the latest command word; unlike the finish it does not refuse on a running action, which is why S2 reads the action status first), then the flag re-read, the Tier-B loader (the only loader call, with only the Tier-B token), the detach marker, one detach (the helper polls the same provider action at most 30 times, never re-sends), the post-detach host read (the mapper still serves, the by-id link is gone), a second provider read of the target, the delete marker, one delete, and the read-back. Git-data keeps serving from the LUKS volume throughout; nothing restarts.
- **`wipe_finish`** (confirm `WIPE-FINISH-GIT-DATA`) finishes a wipe that stopped between its detach and its delete. It makes zero detach calls. It verifies the origin run first (below), then reads the volume: still detached, it requires the action-history evidence below, repeats the post-detach host read, and runs the delete steps; already absent, it loads no credential, makes no delete call and runs only the read-back.

`origin_run` is **always the id of the original `mode=wipe` run** (title exactly `git-data wipe <volume_id>`, on `main`, by `workflow_dispatch`, a run of this workflow by its workflow name (a run title is free text that any workflow on `main` can set), whose `wipe_detach_gate` step concluded `success`), never a `wipe_finish` run's id, also on a second finish. The check accepts the run when that gate concluded `success`, and otherwise when its `wipe_delete_gate` step did. It does not look at the volume's state when it chooses, so for the absent branch the evidence is that the origin run reached one of those two gates: a volume deleted by something else in the meantime passes the same check. That is why the absent branch claims only that the volume is absent at the read-back, with the delete outcome left to the origin run. When the volume is still detached, the finish also reads the volume's provider action history and requires nothing running, no `attach_volume` action started at or after the origin run (`attach_after`, even when a later detach follows it), and the newest attach or detach action to be a successful `detach_volume` started at or after the origin run.

### A leftover snapshot (`snapshot_clear`)

The layout listing of `wipe_check` and `wipe` stacks a throwaway device-mapper snapshot (`git-data-pt-snap`) on the plaintext volume, backed by a loop device on a RAM copy-on-write file under `/dev/shm/tmp.<id>`, and removes it in an exit trap. A trap runs for HUP, INT, TERM and PIPE and for a normal exit; it cannot run for SIGKILL (a host out-of-memory kill, for example), so a killed listing can leave the snapshot, its mount, its loop device and its COW file behind (inferred; not observed). A leftover is safe but blocking: the next `wipe_check` or `wipe` refuses `wipe_snapshot_present` (exit 26) and nothing proceeds.

The way out is `mode=snapshot_clear` (CTO ruling 2026-10-15), dispatched by the owner naming the command (ADR-239 Amendment 2026-10-15), behind the same reviewer-gated environment as `wipe`:

```bash
gh workflow run git-data-cutover.yml --ref main -f mode=snapshot_clear -f confirm=CLEAR-SNAPSHOT-GIT-DATA -f volume_id=<id>
```

It is not called from `wipe_check`, and there is no reboot path (a reboot drops serving and invalidates the boot-row window). It reads the Hetzner identity of the typed volume (W4), then one SSH session runs the host verb's `clear` phase: the typed device is proven not LUKS and not the mapper's backing; the snapshot's origin must be the typed device and it must be non-persistent; its COW must be a loop device whose backing file is in a `/dev/shm/tmp.<id>` directory, and a mount of the snapshot, if any, must be that directory's `mnt`; no process may hold the snapshot open. Only then are the mount, the snapshot (`dmsetup remove --retry git-data-pt-snap`, a literal), the loop device and the COW file removed, in that order, every step attempted. It ends by proving the origin's write counters read `0 0` and its kernel read-only flag reads 1. After a `cleared` answer, run a fresh `wipe_check` before any `wipe`.

Blast radius (from plan A1.7b and the CTO ruling 2026-10-15, not re-measured here): a transient snapshot with a RAM copy-on-write file; the LUKS mapper and the serving path are not touched. With the store flag off the host is not meant to serve user repositories (the boot-time `served_repos=0` row is not a measurement of what is served at the moment of the clear).

### Failure states (S1 to S6)

Every recovery below is owner-authorized, never automatic. The email subject and body carry the notify word, and so does the `ci/git-data-cutover` issue; the notify job writes no step summary. The issue is a COMMENT under the newest open issue with that label, so a wipe word can sit under an older title: read the comments, not only the titles. The failing step's annotation carries the verdict word (titled `git-data-wipe` for the provider and workflow steps, and `git-data-cutover store` or `git-data-cutover access` for the host verb's words). `wipe_check` has its own word, `WIPE_CHECK_FAILED`: no volume or provider state changed, but a killed listing can leave a throwaway snapshot (see "A leftover snapshot" above); read the failing step.

| State | Notify word | Reads as | Recovery |
|---|---|---|---|
| **S1a** no marker, `started` true | `WIPE_REFUSED_BEFORE_ANY_CALL` | this run made no irreversible call; it says nothing about earlier runs | read the failing step (`gh run view <run id> --log-failed`), fix the cause, dispatch a NEW run |
| **S1b** no marker, `started` absent | `WIPE_STATE_UNKNOWN` | the runner was lost, the job timed out or was cancelled, or its environment approval was rejected or expired: UNKNOWN, never "nothing changed" | read the volume at the provider first: the volume read and the action-status read under "Dispatch strings" (or a `wipe_check` dispatch, whose first provider call prints `state plaintext=attached`, `detached` or `absent`). Attached to the git-data server **and no `detach_volume` action reading `running`**: nothing changed, fix the cause and dispatch a new run. A running `detach_volume` action: read again later (S2). Detached: S3, and find the original `wipe` run id as under "Dispatch strings". Absent: S4 or S5 |
| **S2** `phase=detach_attempted` | `DETACH_ATTEMPTED_UNCONFIRMED` | the detach POST may have been sent and accepted (a refusal inside the detach step after the marker reads the same, conservatively); the volume may be attached, detaching or detached | read the volume AND its action status (the two reads under "Dispatch strings"). Attached to the git-data server and no `detach_volume` action reading `running`: nothing changed, dispatch a new `wipe`. A `detach_volume` action reading `running`: the volume may still list its server while the detach completes, so "attached" alone does not mean nothing changed; read again later. A finish refuses `wipe_detach_in_flight` meanwhile; a plain `wipe` does not check it and would send a second detach, so wait for the action to end. Detached: S3 |
| **S3** `phase=detached` | `VOLUME_DETACHED` | the volume is detached and not deleted; the post-detach host read, the provider re-read or the delete marker did not complete. Only a `mode=wipe` run publishes this phase: a `wipe_finish` run never does | the email carries the `wipe_finish` command. In every such email `volume_id` is the digits typed (an input that was not 1 to 12 digits is never copied into the body and reads as the plain word `VOLUME_ID`: replace it). `origin_run` is the email's own run id only in the email of a `mode=wipe` run that detached the volume (the detach, detached and delete words); in any other email it reads as the plain word `ORIGIN_RUN_ID`: replace it by the id of the original `wipe` run. The `VOLUME_ALREADY_DETACHED` email always carries the plain word `ORIGIN_RUN_ID`, even from a `mode=wipe` run, because that run refused and detached nothing: replace it by the id of the wipe run that detached the volume. A plain `mode=wipe` against a detached volume REFUSES, by design (`wipe_volume_already_detached`, notify `VOLUME_ALREADY_DETACHED`, carrying the same command), and a `resume` input is not offered because it would skip the host assertion |
| **S3b** the post-detach host read gave a store verdict (the host verb exited 5 with a word other than `probe_failed`) | `STORE_NOT_SERVING_DO_NOT_FINISH` | after the detach the host verb answered that the git-data host did not read as serving from the encrypted store | **do NOT dispatch `wipe_finish` and do not delete anything.** The wrong volume may have been detached or the store is unhealthy; read the annotation word and the run log, and escalate on #6897 with the CTO. Re-attaching the volume is an owner decision recorded on #6897; no workflow re-attaches it |
| **S3c** the post-detach host read did not answer (`probe_failed` with `rc` 16, 96, 124, 141 or 255, or an argument word, or an access-gate refusal with exit 3) | `VOLUME_DETACHED` from a `mode=wipe` run; `WIPE_REFUSED_BEFORE_ANY_CALL` from a `wipe_finish` run | the volume is detached and the store was not read after the detach; the annotation is not a store verdict. The workflow sets no `refusal` for these (it greps the host verb's output for `verdict=probe_failed`, and an exit 3 is not 5) | S3: the next action is `wipe_finish` with the original `origin_run` (it repeats this read before any delete and stops there if the store does not serve). Do not re-dispatch `wipe` |
| **S4** `phase=delete_attempted` or `delete_sent` | `DELETE_ATTEMPTED_UNCONFIRMED`, `DELETE_SENT_UNCONFIRMED` | the DELETE may have been sent (or returned 204) and the read-back did not confirm | read the volume read-only; do not run detach again. Not listed at the provider (404 by id, nothing by name): dispatch `wipe_finish` with the SAME original `origin_run`. The absent branch makes no delete call; it records the read-back, and its summary says absent, with the delete outcome in the origin run. Listed and detached: dispatch `wipe_finish` (S3). Listed and attached: nothing was deleted, a plain `wipe` re-asserts everything. The email's finish command does not know the annotation word: if the failing step's word is one of S5's, do not run it |
| **S5** the read-back disagrees | `DELETE_SENT_UNCONFIRMED` (the phase is still `delete_sent`; the annotation word tells S5 from S4) | `wipe_readback_name_still_listed` (404 by id but the name still lists a volume: the typed id was not the volume the name resolves to), `wipe_readback_still_exists` (the id still answers), `wipe_readback_luks_missing` or `wipe_readback_luks_detached` (the LUKS volume is not the one attached) | **incident.** Treat as a defect in the identity read, which should have caught it. Open an incident (Breach-triage trigger), escalate to the CTO and the CLO. Never dispatch another delete until the cause is understood, and do not run the email's finish command for these words |
| **S6** `phase=deleted`, then a later failure | `VOLUME_DELETED_TEARDOWN_FAILED` | the provider API read-back confirmed the volume is no longer listed (from this run's own delete, or, for a `wipe_finish` that found it absent, as an observation with no delete call); a step after the read-back failed, or the job was cancelled or timed out after it | nothing to repeat: the read-back is recorded in the run. Confirm with one read-only look at the provider (404 by id). Do NOT re-dispatch: it would refuse at the identity read. For a finish that found the volume absent the delete outcome is in the origin run |

A `wipe_finish` publishes no phase before its delete gate (nothing in a finish writes `detached`), so a finish that fails at the origin check, the identity read, the action-history read, the host read, the loader or the provider re-read reads as S1a (`WIPE_REFUSED_BEFORE_ANY_CALL`), and the volume stays detached; one that fails after its delete gate reads as S4. Dispatch `wipe_finish` again with the SAME original `origin_run`. In an email from a `wipe_finish` run the finish command carries the plain word `ORIGIN_RUN_ID`, not that run's own id: a `wipe_finish` run's id never qualifies as `origin_run`. Only a `mode=wipe` run fills its own id (it is the origin).

**A `mode=rollback` after the detach.** The precheck (W3) runs for `wipe_finish` as well and refuses `wipe_precondition_rollback_after_stamp` for any `git-data rollback` run on `main` created at or after the stamp. A rollback dispatched once the volume is detached therefore makes every later `wipe_finish` refuse until a new flip and its 7-day soak, so the detached volume then outlives 2026-11-12 with no workflow path to delete it. Before any `mode=rollback` while a volume is detached and not deleted (S2 to S4), the owner records on #6897 that this trade is accepted and routes it to the CTO and the CLO. The guard retires with #10297.

### The wedge

After the delete and before PR-C merges, Terraform state and HCL still list `hcloud_volume.git_data` (and its attachment). Read facts, from `tests/scripts/test-git-data-wipe-wedge.sh`:

- **The drift plan shows a create of `hcloud_volume.git_data`.** `scheduled-terraform-drift.yml` plans the whole root with no `-target` and keeps reporting that create until PR-C merges. It only plans, so the effect is a drift report; it is the second reader of the wedge, and expected.
- **A refreshed-away volume plans a NEW volume id.** The id flows into the rendered `user_data` of `hcloud_server.git_data` (no `ignore_changes`), so an apply that sees the wedge would replace the live git-data host. The two jobs that can plan those addresses, `git_data_host_replace` and `git_data_host_create` in `apply-web-platform-infra.yml`, are gated and refuse (`out_of_scope`); every other apply job is targeted so its plan cannot contain them. The wedge test derives the population from `git ls-files` and is RED if any apply-capable job that can reach the wedge would pass it. The detached-but-not-deleted state (S3) has its own fixture: an attachment create, which an unguarded apply would use to re-attach the plaintext volume to the live host.
- **The cost.** Until PR-C merges, the gates refuse every web-platform apply on main that would plan the git-data host replace or the volume create, security fixes included: a fix to the rendered `user_data` of `hcloud_server.git_data` cannot ship in that window. **The replace lever stays held** for that window; this is why the dispatch-to-merge bound exists. The mitigation is the PR-C readiness precondition under "Before naming `mode=wipe`"; no workflow checks it and the bound is prose only.
- **The control is the gates, not a pause.** The retired workspaces wipe closed its delete-to-PR window by pausing both push-apply workflows and refusing unless both read `disabled_manually` (ADR-119, addendum of 2026-09-28). This wipe pauses nothing and checks no workflow state. The replacement control is the pair of plan-time gates `git_data_host_replace_gate` (job `git_data_host_replace`) and `git_data_host_birth_gate` (job `git_data_host_create`), whose refusal of both fixtures `tests/scripts/test-git-data-wipe-wedge.sh` derives and pins; the targeted apply jobs keep running because their plans cannot contain the wedge addresses.
- **A replace after the flip re-runs first boot against a populated store.** The first boot FATALs closed (`luks_residue`, forward-only): git-data stays dark with its data intact. This is true of any ForceNew replace of the git-data host after the first flip, with or without the wedge, and it is tracked as #8571 (copy mode). Nothing here promises users more than "fails closed".
- **The live host still names the deleted id** in its rendered `user_data` until its next replace. `runcmd` runs once per instance, so a reboot does not re-run the bootstrap; a manual bootstrap re-run would FATAL closed (`plaintext_unverified`, no marker).

### The reboot dead end

The host assertion binds the boot-time evidence to the device. After ANY reboot of the git-data host the evidence is stale and nothing refreshes it: the kernel read-only flag reads 0 (`wipe_ro_flag_lost`) and the host booted after the evidence row, or the row lies more than 3600 s after boot (`wipe_boot_generation_mismatch`). No new `boot_complete` row follows (`runcmd` is once per instance) and a replace cannot refresh it (the populated-store first boot refuses), so **no machine path out exists and none is prepared.** The 3600 s boot-to-row window and the H9 instance-id check are first measured by `wipe_check` (it prints `boot_to_row_s`); run it early so a dead end shows while the CLO can still be reached. If a reboot since the row blocks the layout evidence, route to the CLO: the owner records the situation on #6897 and brings an owner-supplied, recorded read (counts only) taken by a procedure the CLO has seen; no agent decides, and no input of `mode=wipe` accepts such a read. The date 2026-11-12 stays the outer bound.

Other results that route to the CLO, not to a retry: `wipe_boot_layout_signal_offlist`, `wipe_plaintext_not_empty`, `wipe_boot_field_plaintext_empty`, `wipe_boot_field_served_repos`. Post the verdict word and the counts on #6897, never a name. For an off-allowlist result (`wipe_boot_layout_signal_offlist`), post the verdict word and, copied verbatim from the `wipe-assert: rc=34` line, only these fixed fields: `top_d`, `top_f`, `top_l`, `top_o`, `repos`, `has_hooks_d` (0 or 1), `lf_entries`, `offlist_n`, `hk_entries`, `hk_nonfile`, `hk_pr_f` (0 or 1), `hk_pr_small` (0 or 1), the four `hk_` fields read only when `has_hooks_d=1`, with "an absent `hk_` group is 'not measured'; never post a 0 in its place". These are counts and 0/1 bits. The four `hk_` fields and this amended list take effect only on the merge of the change that adds them (CLO ruling L3, 2026-10-19); until a run prints the group, every `hk_` field is not measured. Never post, quote, paraphrase, hash or guess a listing name, and never any field outside this list. Policy (CLO ruling, 2026-10-18; takes effect on the merge of the change that adds the fields). The owner posts; an agent may read the line and report it to the owner but does not post it to #6897 (the owner posts the verdict word and the closed field list: CLO ruling L-5(i), 2026-10-18).

### Reading the exit-34 line

The host line for `wipe_boot_layout_signal_offlist` (host exit 34) reads `wipe-assert: rc=34 reason=offlist top_d=<n> top_f=<n> top_l=<n> top_o=<n> repos=<n> has_hooks_d=<0|1> lf_entries=<n> offlist_n=<n>`. The last three fields were added by the 2026-10-18 change (PR #10480); a run dispatched before that change prints only the first five counts. The four `hk_` fields below are added by the 2026-10-19 change (PR #10523) and exist only from its merge. Where to read it: in the run log, behind the prefix `[git-data-cutover] probe-stderr:`; the `STORE probe=` line, the annotation and the step summary carry the verdict word only, not these fields. A line that matches neither this grammar nor the group grammar below exactly (an older five-count line, an extra token, a missing field) is posted as the verdict word and the five counts only; it is never partly trusted. Inherited, 2026-10-18; the strict check (`line34_ok`) and the posting check (`line34_grammar_ok`) are functions of `apps/web-platform/infra/git-data-wipe-assert.test.sh`.

Group grammar (CLO ruling L3 and CTO ruling R4, 2026-10-19; appears only from the merge of the 2026-10-19 change, PR #10523; not measured, because no run has printed it). After `offlist_n` the line may carry one optional group of four fields, present if and only if `has_hooks_d=1`: `... offlist_n=<n>( hk_entries=<n> hk_nonfile=<n> hk_pr_f=<0|1> hk_pr_small=<0|1>)?`, where `<n>` is `[0-9]+` (digits only, no other rule). Exactly two grammars are accepted for posting. First, the eight-field line above, for either value of `has_hooks_d`; [run 39136900735](https://github.com/jikig-ai/soleur/actions/runs/39136900735) stays valid under it, and its `hk_` fields read 'not measured'. Second, the same eight fields followed by the four-field group in the order shown, only when `has_hooks_d=1`. Anything else (a partial group, a group with `has_hooks_d=0`, a reordered group, a group that breaks an invariant listed under the field definitions, an extra token) is posted as the verdict word and the five counts only. An absent group is 'not measured', never a 0.

Literal pattern (policy, 2026-10-19, conditioned on the merge of PR #10523; it is the pattern the suite's `line34_ok` and `line34_grammar_ok` both apply, an extended regular expression, matched against the text after the prefix `[git-data-cutover] probe-stderr:` and its one space; checked only against synthesized lines on 2026-10-19, not against any real run log):

```text
^wipe-assert: rc=34 reason=offlist top_d=[0-9]+ top_f=[0-9]+ top_l=[0-9]+ top_o=[0-9]+ repos=[0-9]+ has_hooks_d=([01]) lf_entries=([0-9]+) offlist_n=([0-9]+)( hk_entries=([0-9]+) hk_nonfile=([0-9]+) hk_pr_f=([01]) hk_pr_small=([01]))?$
```

Decision rule: the line matches the pattern, the group is present if and only if `has_hooks_d=1`, a printed group meets the four invariants listed under the field definitions, and the base conditions of the suite's `l34_base` hold: `offlist_n` is above 0 or `lf_entries` is above 0; `has_hooks_d=1` implies `offlist_n` of at least 1; and `offlist_n` is at most `top_d` + `top_f` + `top_l` + `top_o`. The one exception to the group rule is the already-printed eight-field line with `has_hooks_d=1` and no group, which is the first accepted grammar above (run 39136900735) and not a group fault; it still has to meet the base conditions. A line that fails a base condition is an instrument fault: post the verdict word and the five counts only, and route it to the CTO. To read the line from a run log, take the lines that carry the prefix; the second command strips a trailing carriage return, then the job and timestamp text before the prefix, and then applies the pattern, so it prints the line only if the pattern matches. A line the second command prints has passed the pattern and nothing more: it still has to pass this decision rule before it is read. The carriage-return strip is there so that a line ending in CR cannot silently fall to the fallback (the verdict word and the five counts only). It was checked on synthesized LF and CRLF lines on 2026-10-19; the real-bytes check, whether `gh run view --log` lines end in CR, has not been run:

```bash
gh run view <run-id> --log | grep -F '[git-data-cutover] probe-stderr: wipe-assert: rc=34 '
gh run view <run-id> --log | grep -F '[git-data-cutover] probe-stderr: wipe-assert: rc=34 ' | sed 's/\r$//' | sed 's/^.*\[git-data-cutover\] probe-stderr: //' | grep -E '^wipe-assert: rc=34 reason=offlist top_d=[0-9]+ top_f=[0-9]+ top_l=[0-9]+ top_o=[0-9]+ repos=[0-9]+ has_hooks_d=([01]) lf_entries=([0-9]+) offlist_n=([0-9]+)( hk_entries=([0-9]+) hk_nonfile=([0-9]+) hk_pr_f=([01]) hk_pr_small=([01]))?$'
```

An exit-33 refusal on a volume with a `hooks` directory has a different shape, `wipe-assert: rc=33 reason=<word>`, behind the same prefix. To find one of the four fixed `hooks_` words:

```bash
gh run view <run-id> --log | grep -E '\[git-data-cutover\] probe-stderr: wipe-assert: rc=33 reason=hooks_(shape|pr)_(failed|unparseable)'
```

Any other `rc=33` reason keeps its existing handling (see the symptom table); this paragraph adds nothing for it.

- `has_hooks_d`: 1 if and only if a top-level directory is named exactly `hooks` (case-sensitive; a file or a symbolic link with that name reads 0). Inherited from the script header and the code, 2026-10-18.
- `lf_entries`: the number of entries inside the top-level `lost+found` directory; 0 when it is absent or is not a directory, and 0 for a directory with no entries too (a count at one moment). A `lost+found` that is a file or a symbolic link reads 0 here and counts once in `offlist_n`, so `lf_entries=0` does not mean `lost+found` is a clean directory. Inherited from the script header and the code, 2026-10-18.
- `offlist_n`: the number of top-level entries that fail the path-typed allowlist; entries inside `lost+found` are not counted here. Inherited from the script header and the code, 2026-10-18.

**shape recorded, refusal stands, content unread.** The four `hk_` fields below describe the immediate contents of the top-level `hooks` directory by type and size metadata only, at one moment, in the transient host-local snapshot. They appear only from the merge of the 2026-10-19 change (PR #10523), and only when `has_hooks_d=1`. Each definition is policy (CTO and CLO rulings, 2026-10-19); no run has printed any of them, so every `hk_` field is not measured. No name, size value, owner, mode or content reaches the line: only digits and 0/1 bits leave the host. Beyond the allowlist arms, on the retired volume's snapshot, the top-level directory named `hooks` and the regular file named `pre-receive` directly inside it are the two names probed by the `hk_` reads, each a fixed constant; a third name, a list or a configurable name needs a new CLO ruling. The allowlist and the refusal are unchanged, and `hooks` is not accepted.

- `hk_entries`: the number of entries directly inside `hooks`, dotfiles included, not recursive. `0` reads as zero entries directly inside at one moment; it is not an emptiness reading. Policy, 2026-10-19; not measured.
- `hk_nonfile`: how many of those entries are not regular files (a directory, symbolic link, FIFO, socket, device, or another non-regular type such as a door). It is counted from the same listing as `hk_entries`, so it is never above it. A nested directory counts once at depth 1; what is below depth 1 is unread. Policy, 2026-10-19; not measured.
- `hk_pr_f`: `1` if and only if an entry named exactly `pre-receive` (case-sensitive) is a regular file directly inside `hooks`; no link is followed, so a symbolic link, a directory, a FIFO, `Pre-receive` and `pre-receive.bak` all read `0`. The bit speaks to the name and the type only. Policy, 2026-10-19; not measured.
- `hk_pr_small`: `1` if and only if that same `pre-receive` file is at most 4096 bytes (one constant, `WA_HK_PR_MAX`); the size comes from inode metadata, the file is never opened and the size is never printed. `hk_pr_small=1` implies `hk_pr_f=1`. `hk_pr_small=1` holds for any regular file of that name at or under the bound, including a zero-byte file; there is no lower bound. The bound is a coarse plausibility bound, not an identity test. Computed but not printed, 2026-10-19 (git log and the Terraform strip regex, not a run): the six source commits of the `pre-receive` script strip to 1870 to 2784 bytes, and only 2784 (the real script, stripped, rendered to a host from 2026-09-30, commit a96d123938) and 197 (the placeholder file, stripped, 2026-07-29 to 2026-09-29) were rendered to a host; the placeholder was base64-delivered at first (997 bytes decoded, unstripped, from 2026-07-01 until the strip was added on 2026-07-29); 4096 is above all three. The era of the retired volume's file is not established in the repo, so which render, if any, its file came from is not established; an unstripped copy of the real script (raw 6170 to 9325 bytes) reads `hk_pr_small=0` with `hk_pr_f=1`. A change of the value returns to the CLO. Policy, 2026-10-19; not measured.
- Invariants on any printed group: `hk_nonfile` is at most `hk_entries`; `hk_pr_small` is at most `hk_pr_f`; `hk_entries` is at least `hk_nonfile` plus `hk_pr_f`; `hk_pr_f=1` means `hk_entries` is at least 1. A group that breaks one is an instrument fault: post the verdict word and the five counts only, and route it to the CTO.

A failed read of `hooks` never produces a partial line. From the merge of the 2026-10-19 change (PR #10523), the host script refuses at exit 33 with one of four fixed words, `hooks_shape_failed`, `hooks_shape_unparseable`, `hooks_pr_failed` or `hooks_pr_unparseable`, and prints no `hk_` text; the workflow reports exit 33 under its existing verdict word `wipe_boot_layout_signal_absent`; the fixed `hooks_` word is on the probe-stderr line only. Such a refusal replaces the exit-34 line, carries no field to post, and is not an off-allowlist result: no `hk_` or other field is read from that run, route it to the CTO, and a re-dispatch is the owner's to name and still needs the CLO addendum. These words are policy (CTO ruling R5, 2026-10-19); no run has produced one.

The `hooks` reads add three exits that can replace the exit-34 line (computed from the host script and the verb, not printed by any run; policy, 2026-10-19, from the merge of PR #10523): `budget_exceeded` (host exit 16, reported by the workflow as `probe_failed rc=16`, with the fixed reason word on the probe-stderr line); `errors_count_changed_by_listing` (host exit 33, under the same verdict word `wipe_boot_layout_signal_absent`; the filesystem error count is re-read directly after the `hooks` reads); and a transport timeout (`probe_failed rc=124`, the 300 s bound with the listing). These three are not the whole set. The refusals that the host script already placed after the listing also replace the exit-34 line, on any volume: exit 33 `errors_count_unreadable`, `snapshot_status_unreadable` or `snapshot_invalid` (verdict word `wipe_boot_layout_signal_absent`); exit 36 `teardown_failed`, `snapshot_ls_failed` or `snapshot_remains` (`wipe_snapshot_teardown_failed`); exit 29 `origin_written_during_listing` (`wipe_device_written`); exit 25 `holders_unreadable_after` or `holders_after` (`wipe_device_has_holders`); exit 30 `ro_flag_lost_after` (`wipe_ro_flag_lost`); and exit 16 `stat_unreadable_after` or `getro_failed_after` (`probe_failed rc=16`). Each is a refusal: the earlier off-list finding stands, nothing is released, route it to the CTO. Each carries no field to post, and no `hk_` or other field is read from that run. A re-dispatch is the owner's to name, and a new CLO addendum is required before any `wipe_check`. The symptom table's rows for these exits keep their handling, except that any wait-and-re-dispatch advice there is subject to that CLO addendum: it is not a standing permission to re-dispatch.

| Fields | Reading the owner may post |
|---|---|
| `has_hooks_d=1 offlist_n=1 lf_entries=0`: the eight-field line without the group (run 39136900735) | the only off-list entry is a directory named `hooks`, the name the bootstrap uses; its owner and contents are unread. This is the reading of that line. It says nothing about `repositories/`: read `repos` separately (above 0 means repositories remain), because exit 34 is reported before the `repositories/` check, and lock residue is not in this line. It is not an emptiness reading and not a basis to widen the allowlist |
| `offlist_n=0 lf_entries>=1` | the refusal came from entries inside `lost+found`; the count only (the entries are unread and may be recovered file fragments; no inference about them) |
| `has_hooks_d=1 offlist_n=1 lf_entries=0 hk_entries=1 hk_nonfile=0 hk_pr_f=1 hk_pr_small=1` (a line with the group; reads only from the merge of the 2026-10-19 change (PR #10523); not measured, no run has printed it) | shape recorded, refusal stands, content unread: at one moment, in the transient host-local snapshot, a regular file named `pre-receive` of at most 4096 bytes is the only entry directly inside the directory named `hooks`; its content is unread. `hk_pr_small=1` supports no inference about identity: any regular file of that name at or under the bound reads the same, including a zero-byte file (there is no lower bound), and content identity (a hash) stays uncovered. This shape is not a condition for any acceptance of `hooks`, is not an emptiness reading, and is not a basis to widen the allowlist; the refusal stands |
| `has_hooks_d=1` with `hk_entries=0` (reads only from the merge of the 2026-10-19 change (PR #10523); not measured) | shape recorded, refusal stands, content unread: zero entries directly inside `hooks` at that moment. A count at one moment, not an emptiness reading of the volume; the directory still refuses |
| `has_hooks_d=1` with `hk_pr_f=1 hk_pr_small=0` (reads only from the merge of the 2026-10-19 change (PR #10523); not measured) | shape recorded, refusal stands, content unread: a regular file named `pre-receive` above 4096 bytes. It refutes only a comment-stripped render of the shipped script; it says nothing else about what the file is, and an unstripped copy of the real script reads the same |
| `has_hooks_d=1 offlist_n>=2` with a group (reads only from the merge of the 2026-10-19 change (PR #10523); not measured) | shape recorded, refusal stands, content unread: the `hk_` fields describe `hooks` alone and say nothing about the other off-list entries, which are unread |
| `has_hooks_d=1` with any other `hk_` values (for example `hk_entries>=2`, `hk_nonfile>=1` or `hk_pr_f=0`) | shape recorded, refusal stands, content unread: post the fields only. With `hk_nonfile>=1` a directory cannot be told from a link, FIFO or socket and depth 2 is unread; with `hk_pr_f=0` or `hk_entries>=2` nothing is known about the names of the other entries |
| any other combination | post the fields only; make no inference about which entries they are (`offlist_n=0 lf_entries=0` cannot occur with exit 34: an instrument fault, route to the CTO) |

Match every applicable row and apply all of their caveats together. Where two readings conflict, the one that leaves more unread and refuses more wins. Every row ends with the refusal standing.

- Measured 2026-10-18 (run 39081408368, read-only; the line as printed before these fields existed): `top_d=3 top_f=0 top_l=0 top_o=0 repos=0`.
- Inherited (2026-10-18, `git-data-bootstrap.sh`): the bootstrap creates a `hooks` directory beside `repositories`.
- Measured 2026-10-18 ([run 39136900735](https://github.com/jikig-ai/soleur/actions/runs/39136900735), read-only, verdict `wipe_boot_layout_signal_offlist`): `wipe-assert: rc=34 reason=offlist top_d=3 top_f=0 top_l=0 top_o=0 repos=0 has_hooks_d=1 lf_entries=0 offlist_n=1`. Read through the table in this section, row `has_hooks_d=1 offlist_n=1 lf_entries=0`: the only off-list entry is a directory named `hooks`; its owner and contents are unread. This is not an emptiness reading, the allowlist is unchanged and the refusal stands. `repos=0` is a count at one moment, in the transient host-local snapshot, of the entries directly under a top-level `repositories` directory (regular files named `.<id>.init.lock` or `.init.lock`, and an empty `lost+found` directory, excluded); it also reads 0 when no such directory is present. It is not a statement that no user repository remains and not an emptiness reading. `lock_residue` and `store_root_repos` are not in the line: exit 34 comes before the host prints them, so this run published neither. Recorded here from the public run log. Not proven: what `hooks` holds.
- Policy (CLO ruling, 2026-10-18): the allowlist is unchanged and the refusal stands. A change to the allowlist needs a CTO ruling, counts-only fixed-vocabulary evidence of what the entry holds, CLO review with a dated addendum, an ADR-239 amendment where the allowlist is part of the recorded gate, and its own CLO ruling for each new output field. The question is tracked on #6897.
- Nothing here dispatches a run or sets a date; a further `wipe_check` needs the owner to name the exact command and a new CLO addendum.
  > **Superseded 2026-10-18, as to "a further `wipe_check` needs the owner to name the exact command and a new CLO addendum" for run 39136900735 only:** the exact command was set out in CLO addendum 2, item 1 ([comment](https://github.com/jikig-ai/soleur/issues/6897#issuecomment-6251181879)), and [run 39136900735](https://github.com/jikig-ai/soleur/actions/runs/39136900735) is that further `wipe_check`; the lift in addendum 2 is spent. The sentence still binds any run after it.

### Retention of the evidence row

The boot-signal read takes the newest `boot_complete` row of the CURRENT server (strictly newer than the server's creation; another host's row is not evidence). After a flip no newer row can exist, so the row is old by construction. Measured 2026-10-14 (read-only): Better Stack `logs_retention` is 90 days on both sources; the git-data archive is at least 40 days deep and the control archive at least 62. The row the check uses is the CURRENT server's newest `boot_complete` row; a row of a replaced server, such as one dated 2026-10-11, is refused as `wipe_boot_predates_server`. The newest `boot_complete` row for the git-data host read 2026-10-14 14:34Z on 2026-10-14 (it counts only if it belongs to the current server; `wipe_check` is what shows that). At the configured 90 days that row would remain within retention until about 2027-01-12; that is the setting read on 2026-10-14, not a commitment by Better Stack or by us. **A healthy query that returns no row after that date may mean retention was exceeded** (`wipe_boot_absent`, distinct from a failed read, `wipe_boot_unreadable`): route to the CLO.

### Not proven

- The host-local device-mapper snapshot listing (RAM copy-on-write) runs in `mode=wipe_check` and `mode=wipe` (CLO, 2026-10-15: `wipe_check` exercises the layout listing so its first live run is not the destructive one; it creates a transient local snapshot and removes it). It is a port of the bootstrap's tested unit with a loopback test; a failure refuses before the loader and the detach, with nothing changed.
- H9 (the host's instance id equals the Hetzner server id), the H8 baseline (sectors written and discarded both exactly 0, kernel read-only flag 1) and the 3600 s window are first measured by `wipe_check`.
- The provider response shapes of the detach (201 with an action id), the action poll's end states and the DELETE (204) are pinned from the retired `workspaces-luks-cutover.yml` `wipe` job, not seen live; the first destructive run's fail-closed reads are their first live exercise. The read shapes (server and volume lists, the volume's action history) were pinned from a live read-only call on 2026-10-14.
- The epoch bounds are working values: the host-assertion-to-detach bound is 120 s (the Tier-B loader step took 0 to 2 s over 83 recent apply and drift runs, measured 2026-10-14, so the plan's formula lands on its 120 s floor); the re-read-to-delete bound is 60 s.
- `plaintext_empty=yes` at boot and a clean listing are evidence the gate requires; neither is a statement about what the volume held.
- The `hk_` shape fields (2026-10-19): not measured until a run prints them, and none has. From the merge of the 2026-10-19 change (PR #10523), a printed group is a count or a bit at one moment, in the transient host-local snapshot, with content unread. Content identity of `hooks/pre-receive` (a hash) is covered by no field and stays unproven, and that the retired volume's file came from the comment-stripped render of the shipped `pre-receive` script is unverified. What `hooks` holds beyond its shape stays unproven. The allowlist question stays tracked on #6897.
- What GitHub publishes for a job that was cancelled, timed out or lost its runner is not observable offline: the census simulator keeps a killed step's output file and proves only that the phase chain then reads correctly. Whether a marker written in a step that is then cancelled still reaches the notifier is first observed on a real run (cancel one `wipe_check` while it runs before the first `wipe`); an absent output always reads as `WIPE_STATE_UNKNOWN`, never as "nothing changed", so a lost marker degrades to the more conservative word. The same holds for a run cancelled while it waits for the environment approval and for the result GitHub reports for a rejected approval.

### Last-resort diagnosis (the wipe)

SSH-class and for a stuck state only; no step above depends on it. `wipe_snapshot_teardown_failed` means a host-local device-mapper snapshot named `git-data-pt-snap` (copy-on-write file in `/dev/shm`) may still exist over the retired device. Every later run then refuses (`wipe_snapshot_present` or `wipe_device_has_holders`), and nothing can be detached while it stands. Do not clear it by rebooting the host: the reboot is the dead end above. Open an incident with the CTO and have the host-side teardown done in the script's own order (unmount the snapshot, `dmsetup remove --retry git-data-pt-snap`, detach the loop device, remove the COW file), then `wipe_check` shows the device as before.

## Verdict map

| Where you are | What the run reads | What to do |
|---|---|---|
| Before the root-key apply | `verdict=git_data_root_token_absent` | Run post-merge step 1. |
| Root-key apply, a plan that is not a create of its seven addresses or a no-op | `verdict=git_data_root_key_non_additive` | Nothing is applied. A rotation or any other change is a reviewed PR that adds a typed allowlist arm for exactly its addresses (see "Rotation"). |
| Root-key apply after the fingerprint is committed, planning a create of the key | `verdict=git_data_root_key_remint_refused` | Do not re-anchor. The key's state was lost or the key deleted: open an incident (Breach-triage trigger). |
| Root-key apply, the Hetzner key object's public key is not the key in state | `verdict=git_data_root_key_fingerprint_mismatch` | Commit neither value. Open an incident (Breach-triage trigger). |
| Root-key apply, a capture step failed | `verdict=git_data_root_key_fingerprint_unreadable reason=<word>` | Nothing to commit. Re-dispatch once; a repeat is a defect in the step. |
| Root-key apply, the workflow could not read its own checkout | `verdict=git_data_root_key_anchor_unreadable` | Nothing was applied. Re-dispatch from `main`; a repeat is a defect in the workflow. |
| Before the fingerprint PR merged, or the Hetzner key object deleted | the replace or birth gate refuses `verdict=git_data_root_key_not_in_create reason=fingerprint_file_missing` or `reason=data_source_absent` | Dispatch `apply-git-data-root-key.yml` from `main`, commit its printed fingerprint, re-dispatch the replace or birth. |
| The Hetzner key object swapped, duplicated or renamed | the gate refuses `reason=fingerprint`, `reason=key_count` or `reason=name` | **Do not re-anchor.** A key object changed outside Terraform: open an incident (Breach-triage trigger). |
| A created server that does not carry exactly the default and root keys | the gate refuses `reason=server_keys` | A plan-shape defect, not a key problem. Fix the plan in a reviewed PR. |
| Token revoked, or the Doppler secret missing or malformed | `verdict=git_data_root_key_fetch_failed reason=<rc_nonzero\|empty\|not_openssh_key>` | Re-run the root-key apply if the secret is gone; a revoked token is replaced by a reviewed rotation PR. |
| **L3** — the host is down, or its private NIC or sshd is not up | `role=git-data-jump verdict=failed reason=timeout\|no_route\|connect_refused` | Read the private-NIC heartbeat; re-dispatch the replace if `down`. |
| web-1's sshd stopped permitting `direct-tcpip` | `role=git-data-jump verdict=failed reason=forward_refused` | ADR-220 D1a: the fallback needs its own amendment. |
| **L7** — the key has not been delivered yet (replace not run) | `role=git-data-auth verdict=failed reason=auth_refused` | Run post-merge step 3. |
| **L7** — after a key rotation, until the next replace | `role=git-data-auth verdict=failed reason=auth_refused` | Dispatch the replace. |
| Between the PR #8511 merge and post-merge step 3 | `verdict=git_data_host_key_unavailable reason=absent` (exit 5, precheck) | Expected: no pin is published yet. Run host-key step 3. |
| After step 3, `GIT_DATA_SSH_HOST_KEY` missing from `prd` | `verdict=git_data_host_key_unavailable reason=absent` (exit 5) | The TF-owned secret was deleted outside Terraform. Read `doppler configs logs --project soleur --config prd` for who removed it, then re-dispatch `git-data-host-replace`, which rotates and republishes. An unexplained removal is a Breach-triage trigger. |
| The published pin is not one ED25519 key line | `verdict=git_data_host_key_unavailable reason=invalid` (exit 5) | Terraform only writes a valid key, so the value was edited outside it. Same as the row above: read the config log, re-dispatch the replace, and treat an unexplained edit as a Breach-triage trigger. |
| A replace failed before the new server was created | the replace gate refuses the retry (no server to delete); state holds the new key and the old host's pin | Re-dispatch `git-data-host-create` (`git-data-birth.md`). The birth gate accepts the pin `update` only while the same plan creates `hcloud_server.git_data`. |
| The app, an Art. 17 erasure, pin fault | Sentry `erasure_outcome=unconfigured` with `detail` starting `pin_invalid:` or `pin_absent:` (match with the colon: `pin_absent` prefixes the pre-#9096 word `pin_absent_store_enabled:`, which older events carry); at boot, `op=pin_absent_at_startup` or `op=pin_invalid_at_startup` | The app's pin resolver refused before dialing: the published pin is malformed, or absent (since PR #9096, whatever the store flag says; before it, only while the flag was on). Nothing was erased. Fix the pin (re-dispatch `git-data-host-replace`, or re-load it via `git-data-cutover.yml` `mode=redeploy` if the secret is present but not loaded; for a pre-#9096 `pin_absent_store_enabled` also check the flag, see "Flag already on"), then discharge the ids as in host-key step 5: that sweep is what keeps the login page's "will be completed" promise. Once the sweep is recorded, **resolve** the Sentry issue (never archive or ignore it; see step 3 under "Store not empty"). Since #8572 `art17-erasure-incomplete` also re-pages per event on an unresolved issue, at most one email per issue per 5 minutes (refusals inside that window share one email), so an issue left open no longer swallows the next fault; resolving still marks the sweep done. That 5-minute window is also why a refusal can land unpaged around a resolve: **before** resolving, re-list the issue's events (`issues/<issue-id>/events/?full=true`, as in step 3) and confirm none is newer than the sweep's own listing; **more than 5 minutes after** resolving, run the erasure query of step 3 with `statsPeriod=1h` and treat any issue whose `lastSeen` is after the resolve as a new refusal to sweep. Since PR #9096 each `unconfigured` reason has its own issue (`git-data erasure unconfigured (<reason>): …`, tag `erasure_reason`), so query `feature:account-delete op:git-data-bare-repo-erasure erasure_reason:pin_absent` for the first event (earliest date and a count only). A destroy/recreate of the `GIT_DATA_SSH_HOST_KEY` secret runs no pin-load: load it by hand with `git-data-cutover.yml` `mode=redeploy` (`confirm=REDEPLOY-GIT-DATA`). Boot-time signals: `feature:git_data_host_key_pin op:pin_absent_at_startup` / `op:pin_invalid_at_startup`, `feature:git_data_ssh_client op:ssh_client_absent_at_startup` (since #8572 these page through `git-data-host-key-pin-fault`, keyed on the `pin_fault` tag, once that PR's two runs are green; after resolving one, run the **pin-fault query** in the next row, because a fault that recurs within the rule's 4-hour interval after a resolve does not page again. That query never sees an erasure refusal, which is untagged by design), and the Better Stack lines `git_data_pin=` and `git_data_ssh_client=`. An `unconfigured` with `ssh_client_absent:` means the image has no `ssh`: ship `openssh-client` in the runner stage (PR #9096), then sweep. Count the Art. 12(3) one-month deadline from the first `pin_absent:` event and route such events to a `clo-attestation` issue with that deadline in its title, as step 5 does for `NOT DISCHARGED`. Limit: "discharge as in step 5" works only while `GIT_DATA_STORE_ENABLED` has never been on; after the first flip it depends on #8211's per-id re-erasure path. An `unconfigured` whose `detail` starts `remove_key_absent:` is a different fault: the remove key is missing while git-data is otherwise armed (a partial birth or a half-applied rotation), and the pin is not involved. |
| The app, a replication push, pin fault (#8572) | The `git-data-host-key-pin-fault` email; Sentry `feature:worktree_lease op:git_data_replication_push pin_fault:<reason>`, message `git-data replication push pin fault (<reason>): …` (one issue per reason) | The session-end push was refused or failed on the pinned host key. `pin_absent` / `pin_invalid`: republish the pin (re-dispatch `git-data-host-replace`), or re-load it via `git-data-cutover.yml` `mode=redeploy` if the secret is present but not loaded. `ssh_client_absent`: the image has no `ssh`; ship `openssh-client` in the runner stage. `host_key_mismatch`: read only off the provision dial (`via` = `ssh` in the event; the events API returns it as `.context.via // .extra.via`, and it is not searchable). A git push's stderr is never read for host identity, since a tenant can write host-key text into it (`.git/packed-refs`). The `git-data-cutover.yml` dry-run precheck splits `alg` / `unknown` / `changed` in `_access_reason` without SSH. The match also fires on an absent or unwritable known_hosts file under `StrictHostKeyChecking=yes`, and the tag is advisory: ssh passes the remote's stderr through, so a host that already holds the pinned key can print host-key text, and anyone with the public client DSN can post a tagged event. Corroborate a page against the Better Stack line first (`--grep 'git-data replication push pin fault'`, which carries `pinFault`). **Never re-pin to the key a host presents** (see "Host-key mismatch (H4)"). **Pin-fault query** (issues with a `pin_fault` event in the last 4 h; it must print nothing once fixed): `SENTRY_ISSUE_RO_TOKEN=$(doppler secrets get SENTRY_ISSUE_RO_TOKEN -p soleur -c prd --plain); curl -fsS -H "Authorization: Bearer ${SENTRY_ISSUE_RO_TOKEN}" 'https://jikigai-eu.sentry.io/api/0/organizations/jikigai-eu/issues/?query=has%3Apin_fault&statsPeriod=4h' \| jq -r '.[] \| [.id, .count, .lastSeen, .title] \| @tsv'`. Verify without SSH, with positive evidence (silence alone never counts, see the flag-flip precondition): `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since '<redeploy time>' --grep 'git_data_pin=present fp='` shows every host loaded the expected fingerprint (a `warn` line, so Vector ships it; the `git-data replication push complete` line is `info` and never reaches Better Stack), a `git-data-cutover.yml` dry run passes the git-data-auth hop with both hops pinned (the step-4 reading above), and the pin-fault query prints nothing after the next session end. Catch-up: the replica self-heals at each workspace's next session end, which force-pushes every head and tag; commits made in the window exist only on the host until then. The rule re-pages at most every 4 h per issue; run the pin-fault query after resolving. |
| The pin read failed | `verdict=git_data_host_key_unavailable reason=<word> rc=<n>` (exit 5; the same reason words as `flag_read_failed`, e.g. `auth_invalid`, `forbidden`, `network`) | The same token and read as the flag; handle it like `flag_read_failed`. Re-dispatch once; a repeat means the `DOPPLER_TOKEN_PRD` token needs replacing. |
| The committed web-1 pin file is malformed | `verdict=web_1_host_key_invalid` (ssh_config step) | A defect in `apps/web-platform/infra/web-1-ssh-host-key.pub` on the dispatched ref. Fix it in a reviewed PR (see "Re-capturing web-1's host key"). |
| **L7 host identity** — a hop presented a key other than its pin | `role=<web\|git-data-jump\|git-data-auth> verdict=host_key_mismatch reason=changed` | Rule out L3 and L7 auth first, then follow "Host-key mismatch (H4)" below. The app's own `pin_fault=host_key_mismatch` (#8572) is read from ssh stderr, which is the same text an absent or unwritable known_hosts file produces under `StrictHostKeyChecking=yes`, so confirm with this precheck before treating it as a changed key. |
| **L7 host identity** — no pin for the alias | `verdict=host_key_mismatch reason=unknown` | A configuration bug (a typo'd `HostKeyAlias` or an empty known_hosts file), not an attack signal. Fix the workflow in a reviewed PR. |
| **L7 host identity** — the host offers no key of the pinned algorithm | `verdict=host_key_mismatch reason=alg` | web-1 must offer ECDSA-P256 and git-data ED25519. For git-data, the boot proof should have failed the replace first: read its `stage:sshd_config` events. Then follow "Host-key mismatch (H4)". |
| The `prd` read token is empty | `verdict=flag_token_absent` (exit 5) | The `DOPPLER_TOKEN_PRD` repo secret is unset or not passed to this run. Restore it, then re-dispatch. |
| The flag read failed | `verdict=flag_read_failed reason=<word>` (exit 5) | `network`: re-dispatch. `auth_invalid`, `forbidden`, `config_not_found`, `scope_mismatch`: the token behind `DOPPLER_TOKEN_PRD` is revoked, lacks `prd` read, or resolves another config; replace it, then re-dispatch. `unknown`: re-dispatch once, then open an issue. |
| The flag is already on | `verdict=flag_already_true` (exit 5) | **Incident.** See "Flag already on" below. |
| The store root is not mounted on a device | `probe=store-mounted verdict=old_store_unmounted` (exit 5) | Read the host's git-data boot events in Sentry before anything else; both volumes are retained. **Before** the step-3 replace this means the plaintext volume did not mount, and the remedy is to re-dispatch the replace. **After** it, the mapper did not mount, which is a boot FATAL: follow "If the fresh host fails a boot check after step 3" and do not re-dispatch a replace first. |
| **Configuration fault** — an unsafe configured path | `probe=config verdict=probe_failed reason=arg_root\|arg_subdir\|arg_marker\|arg_mapper\|arg_wrapper` (exit 5) | Nothing was dialed and the value was not printed. `OLD_ROOT`, `REPO_SUBDIR`, `STORE_VERIFIED`, `LUKS_MAPPER` or `TRANSPORT_WRAPPER` reached the script with an unsafe value: the workflow sets none of them, so something (a workflow `env:` or a `$GITHUB_ENV` write in an earlier step) injected it. Do not re-dispatch; find and remove the injection in a reviewed PR. |
| **Incident, served device wrong** — the store root is served by something other than the LUKS mapper | `probe=store-on-mapper verdict=store_not_on_mapper` (exit 5) | The ADR-239 render cannot produce this. The wrappers refuse on the same device check, so every erasure is refused: sweep Sentry for the Art. 17 refusals with the query under "Store not empty" (step 3), and escalate to the CLO if an Art. 12(3) deadline is at risk. Read the current instance's boot_complete line and its `stage:bootstrap` events first, then follow "If the fresh host fails a boot check after step 3". Never re-dispatch a replace before that read. |
| **Wrappers refusing now** — the bootstrap's store marker is missing, or the filesystem has no UUID | `probe=store-verified verdict=store_unverified reason=no_fs_uuid\|marker_absent` (exit 5) | Every provision, erasure and push is refusing on the host. Sweep Sentry for the Art. 17 refusals it opened, with the query under "Store not empty" (step 3), then follow "If the fresh host fails a boot check after step 3". `no_fs_uuid`: the mounted filesystem reports no UUID. `marker_absent`: the marker is missing, empty or not a file; a boot FATAL removes it, so read the boot events. |
| **Tampering signal** — the marker names another filesystem | `probe=store-verified verdict=store_unverified reason=marker_mismatch` (exit 5) | Every wrapper refuses. With a matching boot FATAL (a mapper reopened on another volume, a writer defect), route as "Wrappers refusing now". With **no** boot FATAL it is a Breach-triage trigger: open an incident first, and do **not** replace the host until the incident releases it: a replace destroys the host and rewrites the marker, which is the evidence. Host-key step 5 resumes only after the incident closes, by its step-5.3 rule. |
| **Frozen** — the freeze sentinel exists | `probe=store-verified verdict=cutover_frozen` (exit 5) | Since #8211 PR2 the sentinel carries `writer=<lineage> at=<epoch>` provenance and the cutover is its only writer/clearer. A `cutover_frozen` outside a dispatched flip is an incident (from the PROBE step it means the pre-flight found a held sentinel, which the proof refuses too, so clear it with `mode=unfreeze` and the writer's lineage, not `mode=proof`): provision, remove, the transport wrapper and pre-receive all refuse (gc does not read it). The sentinel's `writer=` names the lineage `cutover-<run_id>` — the Actions run that wrote it (a refused freeze log line already prints it; the writer is also recoverable without SSH by finding the flip run whose `freeze` step last ran: `gh run list --workflow git-data-cutover.yml --limit 20`). If that run is dead, dispatch `mode=unfreeze -f lineage=cutover-<dead run id>` — the lineage input names the sentinel to clear. If the run is only FAILED mid-window, `gh run rerun --failed <run-id>` reuses its lineage (resume arm A tolerates the sentinel). Escalate a foreign/unattributed sentinel to the CLO, because the Art. 12(3) clock runs. |
| **Store session could not be answered** — the store-verified stage | `probe=store-verified verdict=probe_failed rc=5\|6\|16\|96` (exit 5) | `rc=5`: `findmnt` could not read the store's source or its filesystem UUID; re-dispatch once, a repeat is an incident. `rc=6`: the store source is not the one the first probe read — it changed or something is mounted over it. That is not transient: open an incident, and discharge nothing until it explains the change. `rc=16`: `head` could not read the marker; re-dispatch once, a repeat is an incident. `rc=96` (the probe's `verified-only` pre-flight): the answer was empty, not a count, or carried extra lines, so nothing was proven; open an incident and discharge nothing. Other `rc` values read as in the last row below. |
| **Store session could not be answered** — the store-empty stage | `probe=store-empty verdict=probe_failed rc=3\|4\|7\|8\|9\|96` (exit 5) | Every store-verified fact held, then the count could not be taken. `rc=3`: `repositories` is a dangling symlink or not a directory. `rc=7`: it is missing (the bootstrap always creates it). `rc=8`: its containing mount is not the store root, so a second mount is hiding what lies under it. `rc=9`: `readlink`/`stat` could not resolve it. `rc=4`: `find` failed. `rc=96`: the count answer was malformed. None of these is transient and an empty store produces none of them: open an incident, and discharge nothing. |
| The store holds repositories | `probe=store-empty verdict=store_not_empty` (exit 5) | **Incident.** See "Store not empty" below. Since #8211 PR2 this counts every entry under `repositories/` (the bootstrap's `_repo_count` rule), not only `*.git`. |
| A probe could not be answered | `probe=store-mounted verdict=probe_failed rc=<n>`, or any probe's `rc=124\|255\|141` (exit 5) | `rc=124`: the 30 s bound expired; re-dispatch. `rc=255`: ssh transport failed; read the heartbeat, then re-dispatch. `rc=141`: the answer was larger than the cap. `rc=96` from store-mounted: the answer did not match the expected pattern; re-dispatch once, then open an incident. No `rc` from store-on-mapper or store-verified: the first probe left nothing to compare; re-dispatch once. The re-dispatch advice in this row does not apply to the `wipe-assert` probe (the wipe modes): read its `rc` under 'Wipe, host — the session could not be answered', and a re-dispatch of a `wipe_check` needs a new CLO addendum. |
| The pre-receive fence is not intact | `probe=fence-shape verdict=fence_not_intact reason=hooks_dir_absent\|hooks_dir_owner\|hook_absent\|hook_owner\|hooks_parent_writable\|hook_not_runnable_by_git\|hooks_path_mismatch\|transport_pin_mismatch\|hooks_wrong_source` (exit 5) | **Incident first.** A root-owned path or mount changed on git-data (before post-merge host-key step 3, on a host whose SSH key was not yet pinned, #7226). Capture the run's annotations and its `probe-stderr:` lines (`gh run view <run-id> --log`), then open an incident (Breach-triage trigger). Then dispatch `apply-web-platform-infra.yml` with `apply_target=git-data-host-replace`, which re-runs the bootstrap; the pre-cutover replace plus `GIT_DATA_LUKS_KEY` rotation (ADR-220 D6) is still required afterwards on a store that has never been flipped (after a flip the rotate is refused, see the D6 section). The bootstrap FATALs at boot on the ownership, executable and `core.hooksPath` facts; it does not check the device, the parent directory, the wrapper pin or the `git` user's access. The words:<br>`hooks_dir_absent` — the hooks directory is missing or is a symlink. A symlink survives a replace (the volume is retained), so remove it in the incident first.<br>`hooks_dir_owner` — the hooks directory is not `root:git 750`.<br>`hook_absent` — `pre-receive` is missing, a symlink, not a regular file, or not executable.<br>`hook_owner` — `pre-receive` is not `root:root 755`.<br>`hooks_parent_writable` — the hooks directory's parent is not root-owned, or is group/other-writable.<br>`hook_not_runnable_by_git` — the `git` user cannot read and execute `pre-receive` (group membership, an ACL, a denied traversal). Git would skip the hook and accept the push.<br>`hooks_path_mismatch` — the effective system `core.hooksPath` is unset or names another path.<br>`transport_pin_mismatch` — the installed transport wrapper no longer pins pushes to the serving hooks directory.<br>`hooks_wrong_source` — the hooks directory or `pre-receive` is on a different device from the store. |
| The fence probe could not be answered | `probe=fence-shape verdict=probe_failed rc=5\|16` or `reason=arg_root\|arg_source\|arg_serving\|arg_wrapper` (exit 5) | `rc=5`: `findmnt` could not resolve a fence path's device. `rc=16`: an instrument on the host failed; the `probe-stderr:` lines in `gh run view <run-id> --log` name which (`stat`, or `git config` exiting above 1). Re-dispatch once; if it repeats, dispatch `git-data-host-replace`, since an instrument failing on a bootstrapped host is itself drift. `reason=arg_root\|arg_source\|arg_serving\|arg_wrapper`: the probe was called with an empty or unsafe argument. That is a code or configuration fault: do not re-dispatch, fix the caller. Other `rc` values read as in the row above. |
| A stale invocation asking for a real mode | `verdict=real_cutover_unreconciled` (exit 5) | Nothing to do — the PR1 variable vocabulary (`DRY_RUN`/`ROLLBACK`/`CONFIRM_WIPE`) is superseded by `MODE`. Dispatch `git-data-cutover.yml` with the `mode` input instead. |
| Wrong mode/confirm pair, or a `lineage` input on a non-unfreeze mode | the confirm step exits 1 on `confirm token mismatch` / `lineage is only valid with mode=unfreeze` | `confirm` must equal the mode's token exactly; `lineage` is meaningful only under `mode=unfreeze` (it names a stranded sentinel's writer). |
| Precondition: the #8209 Tier-B seam is not seeded | `verdict=precondition_8209_open` | Set `DOPPLER_TOKEN_INFRA_PRIVILEGED` on the environment (ADR-241 R7), then re-dispatch. |
| Precondition: the pin-fault Sentry rule is not live | `verdict=pin_fault_paging_absent` | Rule 1310055 unreadable or disabled — the read is live (`SENTRY_ACTIONS_RO_TOKEN`), not inferred. Enable it or fix the token before flipping. |
| Precondition: no completed `git-data-host-rotate` | `verdict=d6_replace_stale` | Only if no run of `git-data-cutover.yml` executed the `Write GIT_DATA_STORE_ENABLED` step (store never flipped): dispatch `apply_target=git-data-host-rotate confirm=ROTATE-GIT-DATA` off `main` ([above](#the-d6-rotate-dispatch-before-the-flip)). Otherwise do NOT dispatch it (the guard refuses and a rotate would destroy the only copy): see [When a rotate is needed after the flip](#when-a-rotate-is-needed-after-the-flip-10175). A plain replace cannot discharge D6 — it re-mints no LUKS key. |
| Precondition: the newest rotate attempt did not complete | `verdict=d6_last_rotate_failed` | The newest `git-data-host-rotate` attempt (the run id is in the remedy line) failed, was cancelled or timed out after its apply began, so host and key state are uncertain, and an older success does not discharge D6. Read it with `gh run view <id> --log-failed` and the sections above, repair, and dispatch a fresh rotate; only a newer successful rotate supersedes it. The block is sticky: its only exits are a newer successful rotate or the failed run aging out of the 100-run window; re-running the failed run is a risky exit, not a safe one (a re-run that completes stamps but re-executes the destructive apply; one refused at the plan gate hides the failure from the gate), and a fresh dispatch refused at its precondition reads `skip` (inferred from the run record shape) and does not supersede it. There is no bypass input and no passphrase-loss recovery path is defined for this host, so a refused re-rotate is read from that run's precondition line, not worked around. |
| Precondition: a replace or rotate run is still going | `verdict=d6_rotate_in_flight` | A `git-data-host-replace`/`-rotate` run (id in the remedy line) is running, queued or waiting for approval, or is a non-complete run that does not list the job yet, so its target cannot be read. Re-dispatch the flip when it completes. Cancel it only if `gh run view <id> --json status` reads `waiting` (a stale approval request); never cancel an `in_progress` run, since cancelling mid-apply can leave the host destroyed. |
| Precondition: run state could not be read | `verdict=d6_run_unreadable` | `gh run list`/`gh run view` failed, returned nothing or an unparseable body, or the stamp library could not be loaded from the checkout. Nothing was concluded; run `gh run view <id> --json jobs` for the id in the remedy line to see why, then re-dispatch the flip. A listed run whose `gh run view` keeps failing strands the flip until a newer successful rotate exists; there is no bypass. |
| Precondition: a web deploy is in flight | `verdict=deploy_in_flight` | Wait for `web-platform-release.yml` to settle; a mid-flip env rebake would be an unattributed cutover. |
| Precondition: running image below the emitter floor | `verdict=live_image_stale` | `/health` reports a release older than `vars.GIT_DATA_EMITTER_FLOOR` — the `git_data_store=` emitter is not live, so a flip could not prove itself. |
| A host never reported the flag's new value | `verdict=deploy_assert_failed` | The `git_data_store=<value>` emit never landed in Better Stack within the poll window — the finalizer has already unwound; reconcile the emit path before re-dispatching. |
| The flag-write seam failed | `verdict=flag_write_credential_absent`, `flag_write_failed`, `flag_write_readback_failed`, `flag_write_value_invalid`, `flag_mode_invalid` (exit 5) | The write seam refused or its read-back disagreed — the flag state is printed in the run's own verdict line; reconcile in `prd` before re-dispatching. `nothing_to_rollback` short-circuits a rollback when the flag is already off. A **rollback** whose flag-off write landed but whose read-back failed leaves the fleet on the old env (the finalizer's rollback arm does not redeploy, and a second `mode=rollback` exits `nothing_to_rollback`): converge it with `mode=redeploy`. A **flip** whose write failed before it landed still runs the unwind (a flag-off write, then a redeploy of both web hosts, with the freeze held until it confirms, so Art. 17 erasures are refused and logged meanwhile). |
| The redeploy tracker's verdicts | `redeploy_credential_absent`, `redeploy_tool_absent`, `redeploy_tag_unresolved`, `redeploy_status_unreadable`, `redeploy_baseline_unreadable`, `redeploy_dispatch_rejected`, `redeploy_peer_fanout_degraded`, `redeploy_terminal_failure`, `redeploy_timeout` | `track.sh` fails closed: the `/health` tag must resolve, a baseline `start_ts` must exist BEFORE dispatch, `ok_peer_fanout_degraded` means a peer did not swap (mixed fleet — reconcile before proceeding), `redeploy_timeout` is the per-callsite bound. |
| The finalizer's own unwind failed | `verdict=RECOVERY_FAILED` (pages) | A partial unwind — reconcile flag state in `prd`, `git_data_store=` on both hosts, and the sentinel (unfreeze lever above) before ANY re-dispatch. |
| Bridge/key/ssh_config setup refused | `verdict=ssh_config_key_absent`, `verdict=ssh_config_path_unsafe`, `verdict=known_hosts_empty`, `verdict=doppler_token_absent`, `verdict=pin_write_failed` | Setup steps failed before any host call; each prints the missing piece. A repeat is a defect in the step, not a transient. |
| The cutover's `MODE` is not a known verb | `verdict=mode_invalid` (exit 5) | A defect or a stale caller; the verbs are `proof\|freeze\|unfreeze\|probe`. |
| A write verb ran without its lineage stamp | `verdict=lineage_absent` (exit 5) | `CUTOVER_LINEAGE` was unset or malformed — the workflow stamps `cutover-<run_id>`; an out-of-band invocation must set it explicitly. |
| Freeze found gc.service mid-run | `probe=freeze-gc-quiesce verdict=gc_active` (exit 5) | The one-shot gc was running; the freeze did not write. Wait for `git-data-gc.service` to finish (it is a timer-driven oneshot) and re-dispatch — never `systemctl stop` the service itself mid-flush. |
| Freeze found a sentinel another run wrote | `probe=freeze verdict=frozen_foreign` (exit 5) | A cutover run from another lineage holds the freeze. The sentinel's `writer=` field names `cutover-<run_id>`; if that run is dead, dispatch `mode=unfreeze -f lineage=cutover-<dead run id>` (the `lineage` input is the declared override — a fresh dispatch otherwise mints its own lineage and can only ever read the sentinel as foreign). If the writing run failed mid-window, `gh run rerun --failed <run-id>` resumes under the SAME lineage. |
| Freeze found an unparseable sentinel | `probe=freeze verdict=frozen_unattributed` (exit 5) | A sentinel with no `writer=/at=` fields is a host incident — nothing provisioned should write it. Do not remove it by hand; open an incident (Breach-triage trigger) and preserve the file as evidence. |
| A legacy lock was held mid-purge | `probe=lock-purge verdict=lock_held` (exit 5) | A provision was in flight past the sentinel check — the freeze sentinel is still written, but a `. <id>.init.lock` remained held. The purge stops rather than racing the writer; re-dispatch the mode once the provision lands, or remove the stale lock after confirming no provision holds it. |
| Unfreeze refuses the sentinel it found | `probe=unfreeze verdict=frozen_foreign` or `probe=unfreeze verdict=frozen_unattributed` (exit 5) | `frozen_foreign`: the writer lineage is not this run's — deliberate; a foreign lineage means another cutover's window. `frozen_unattributed`: the sentinel carried no provenance — a host incident, as in the freeze row. |
| The sentinel exists but cannot be READ | `probe=freeze verdict=frozen_unreadable` or `probe=unfreeze verdict=frozen_unreadable` (exit 5) | The file is present and its read failed — an I/O fault, distinct from `frozen_unattributed` (content present but unparseable). Re-dispatch once; a repeat is a host/filesystem incident on the serving volume. |
| Proof met a sentinel THIS run wrote | the `store-verified` probe reads `verdict=ok reason=resume_same_lineage` (a notice, not a refusal) | Resume arm A — `gh run rerun` on a flip that died after freezing reuses the run id, so the lineage matches and the (already-discharged) proof is skipped. Normal on a resumed flip only; on any other mode it cannot occur (a sentinel's writer is always a `cutover-<run_id>` that ran freeze). |
| Unfreeze found nothing | the `unfreeze` probe reads `verdict=ok reason=nothing_to_unfreeze` (a notice) | Convergent no-op — gc.timer is still restarted; nothing was held. |
| The sentinel could not be cleared | `verdict=FREEZE_HELD` (exit 5, a paging line — not a summary verdict) | The git-data hop (or the rm) failed while the sentinel may still be live: every store verb is refusing. This pages. First retry the clearing lever — re-dispatch `mode=unfreeze` (same lineage if the run is live; `-f lineage=cutover-<id>` when it is dead). A hop that cannot answer at all routes through the `git-data-host-replace` lever only after the incident is open — the sentinel does not survive a replace (the store device is re-created), so a replace is itself a clearing path, gated on served_repos=0. |
| The gc timer would not restart after the sentinel was cleared | `probe=unfreeze-gc-timer verdict=gc_timer_restart_failed rc=<n>` (exit **6**, after one immediate retry; notify word `GC_TIMER_STOPPED`) | The sentinel is already cleared and the store is writable; only gc stays stopped, so the verb fails loudly and nothing is stranded. The cutover is NOT unwound: the unfreeze step goes red, the probe and (in a flip) the stamp still run, the finalizer exports `gc_timer_stopped` and never `freeze_held`, and in a rollback it retries the timer once more. Recovery: re-dispatch `mode=unfreeze -f confirm=UNFREEZE-GIT-DATA` (no lineage input: the sentinel is gone). A **second consecutive** failure is a host incident, not a transient: read the host's events in Better Stack (`gc_timer=unarmed` at boot is a tolerated state that makes this repeat). `rc` 255 or 124 is transport, so the retry may succeed; another value is the unit itself. Separately, a flip whose flag write failed before it landed still runs the unwind (a flag-off write and a redeploy of **both** web hosts, bounded at 900 s; the freeze is held until the redeploy confirms, so Art. 17 erasures are refused and logged meanwhile), because the run marks the attempt before the write and cannot tell a landed write from one that did not; a failed write token then ends in `RECOVERY_FAILED` ("flag state unknown"). |
| The transactional probe could not provision | `probe=probe verdict=probe_failed reason=provision` (exit 5) | The provision wrapper refused or failed on a synthetic id post-flip — the provision path is broken under the real store, or the repositories directory is missing (the probe's store pre-flight does not check it). Read the remove-retry line and the host's provision events; do not re-dispatch the flip. |
| The transactional probe's push was refused | `probe=probe verdict=fenced_push_failed` (exit 5) | The CAS fence rejected a conforming push (valid `lease-gen`/`worktree-id`), or the push path broke. The store is populated but unfenceable — an incident; the probe's cleanup retry already ran. |
| The transactional probe could not finish | `probe=probe verdict=probe_failed reason=<repo_absent_after_provision\|scratch\|ref_not_landed>` (exit 5) | `repo_absent_after_provision`: the wrapper claimed success but no repo exists. `scratch`: the temp scratch setup failed. `ref_not_landed`: the push ran but the ref never landed — the fence accepted bytes the repo does not hold. All are host incidents. |
| The probe's erasure failed, or left the repo | `probe=probe verdict=remove_failed` or `probe=probe verdict=residue_left` (exit 5) | `remove_failed`: the remove wrapper errored mid-probe; the synthetic id may persist. `residue_left`: remove exited 0 but `<id>.git` still exists — the erasure path lies. Both are incidents; the residual id `cutover-probe-<run>` must be removed before the next proof (it trips `store_not_empty`). |
| The fresh host could not verify the retained plaintext volume | Better Stack / Sentry `stage:bootstrap` `FATAL: plaintext_unverified reason=<mount\|source\|journal\|umount\|snapshot>` | Since 2026-09-24 (#5274) the volume is set kernel read-only and read through a throwaway dm snapshot, never mounted itself. `source` = the device is not the plaintext volume (not a block device, LUKS, has holders or no sysfs entry, its device number changed, the snapshot's origin is another device) or the mount is not the snapshot, or `repositories` on the snapshot is not a real directory; `snapshot` = the read-only flag or the snapshot apparatus failed (journal geometry, loop, `dmsetup create`, an invalidated COW, a previous run's snapshot still present, unreadable sector counters); `mount` = the snapshot did not mount or its tree is unreadable; `journal` = the journal did not replay cleanly into the snapshot (still needs recovery, `with errors`, `errors_count` after replay differs from the volume's historical error count, or it moved during the count); `umount` = a transient device could not be torn down. **One `snapshot` FATAL is an incident, not a refusal:** `… was written or discarded (sectors a b -> c d)` means the retained volume's written- or discarded-sector counters moved during the read — open an incident (Breach-triage trigger) and route to the CLO; every other FATAL here wrote nothing. The FATAL detail carries `kernel=<overflow\|jbd2\|ext4-error\|none> cow=<used/total>`. No store marker exists, so every erasure refuses. A repeated journal-class FATAL on the production volume routes to the #8571 wipe decision and the CLO, never to another replace. Follow "If the fresh host fails a boot check after step 3". |
| The retained plaintext volume holds repository entries | `FATAL: plaintext_residue count=<n>` | **Stop.** The data is read-only on a retained volume. Escalate to the CLO, bump #8571 (copy mode) and block the wipe. Do not wipe or replace. See the residue paragraph in "If the fresh host fails a boot check after step 3". |
| The LUKS volume itself holds repository entries | `FATAL: luks_residue count=<n>` | An adopted volume carries content this register has not recorded. No marker is written and the host serves nothing. Treat it as "Store not empty": open an incident and route it to the CLO before any erasure or wipe. |
| The pre-receive fence did not land on the mapper | `FATAL: fence_on_mapper=no`, and `boot_complete` `fence_on_mapper=no` | The hooks landed under the mountpoint instead of on the serving device, so a push would run an unfenced hook. No marker is written. Forward fix; follow "If the fresh host fails a boot check after step 3". |
| The boot erasure self-probe failed | `FATAL: erasure_probe=no`, and `boot_complete` `erasure_probe=no` | The bootstrap removed the marker before the FATAL, so the Art. 17 path is fail-closed rather than silently broken. Forward fix, and sweep and re-drive the refused ids; follow "If the fresh host fails a boot check after step 3". |
| **Wipe family** — the confirm step refused the input | a red run with NO email; the annotation reads `confirm token mismatch`, `volume_id must be 1 to 12 digits`, `origin_run must be the numeric id`, `origin_run is only valid with mode=wipe_finish`, `lineage is only valid with mode=unfreeze` or `a wipe-family run cannot be re-run` | Nothing was called and `started` stayed false. Fix the input and dispatch a NEW run; never "Re-run failed jobs" ([The wipe](#the-wipe-dl-2-10138--6897)). |
| **Wipe, precheck** — the flag, the stamp or the soak | `wipe_precondition_flag_not_true`, `wipe_precondition_stamp_absent`, `wipe_precondition_stamp_malformed`, `wipe_precondition_flag_unreadable`, `wipe_precondition_variant_changed` (W7b; the line carries `expected=` and `got=`), `wipe_precondition_variant_unreadable` (the precheck printed no `wipe_variant` line), `wipe_separated_store_dirty`, `wipe_separated_cutover_in_flight`, `wipe_separated_scan_unreadable` (the separated variant's run-record scan), `wipe_separated_store_root_populated`, `wipe_separated_store_root_unreadable` (the on-host store-root count), `wipe_precondition_soak_not_elapsed` (the line carries `floor_days` and `elapsed_s`), `wipe_stamp_read_failed` (the same cause words as `flag_read_failed`); in `wipe_check` the same word appears as `would_refuse=<word>` and the run continues | Nothing was called. Wait out the 7-day floor (the pinned constant is relaxed only by an ADR-239 amendment plus a CLO ruling), or fix the flag or the stamp; a read failure is handled like `flag_read_failed`. |
| **Wipe, precheck** — a rollback or legacy run after the stamp | `wipe_precondition_rollback_after_stamp`, `wipe_precondition_legacy_run_after_stamp`, `wipe_precondition_run_title_unparseable`, `wipe_precondition_run_list_unreaching`, `wipe_precondition_run_list_unreadable`, `wipe_runs_bad_args` | The interim stamp guard: a rollback (any conclusion) or a legacy-titled run on `main` after `GIT_DATA_LUKS_CUTOVER_AT` means the stamp no longer proves a soak. Escalate on #6897 and #10297 (the guard retires when the rollback arm clears the stamp). `unreaching` and `unreadable`: the run list could not prove the window; re-dispatch once. |
| **Wipe finish** — the origin run does not qualify | `wipe_origin_run_unreadable`, `wipe_origin_run_title_mismatch`, `wipe_origin_run_workflow_mismatch`, `wipe_origin_run_not_main`, `wipe_origin_run_not_dispatch`, `wipe_origin_run_gate_not_success` | `origin_run` must be the original `mode=wipe` run (title exactly `git-data wipe <volume_id>`, a run of this workflow by name, `main`, `workflow_dispatch`, and its step `wipe_detach_gate` concluded `success`, or else its step `wipe_delete_gate` did). A `wipe_finish` run's own id never qualifies. Nothing was called. |
| **Wipe, tokens** — a provider token is missing or unusable | `wipe_readonly_token_absent`, `wipe_readonly_token_unusable`, `wipe_write_token_absent`, `wipe_write_token_unusable` | The read-only token `HCLOUD_TOKEN_READONLY` (from `prd_terraform`) or the Tier-B write token (from the loader) was empty or malformed. There is NO fall-back from one to the other. Nothing was sent; fix the secret and dispatch a new run. |
| **Wipe, identity** — the typed id is not the target | `wipe_volume_id_shape`, `wipe_volume_id_mismatch`, `wipe_target_is_luks`, `wipe_volume_count`, `wipe_luks_count`, `wipe_server_count` | The typed id must be the one volume the API lists under `soleur-git-data-store`, never the LUKS volume, with exactly one `soleur-git-data` server and one LUKS volume. Nothing was sent. `wipe_volume_id_mismatch` and `wipe_target_is_luks` are mistyped or stale ids: re-read the id and `wipe_check` again. Counts other than one are an incident to understand before any dispatch. |
| **Wipe, identity** — the volume is not in the expected place | `wipe_not_attached_to_current_host`, `wipe_volume_already_detached`, `wipe_volume_not_detached`, `wipe_label_mismatch`, `wipe_delete_protected`, `wipe_target_changed` | `wipe_volume_already_detached` (plain `wipe`): the volume is already detached, so this run detached nothing; notify `VOLUME_ALREADY_DETACHED` carries the finish command with the plain word `ORIGIN_RUN_ID` for the id of the wipe run that detached it (S3). `wipe_volume_not_detached` (`wipe_finish`): it is still attached, nothing was detached; a plain `wipe` is the path. `wipe_not_attached_to_current_host`: attached to another server, or the LUKS volume is not on the git-data server: stop. `wipe_label_mismatch`, `wipe_delete_protected`: not the volume this run was built for (a lifted protection is a Terraform change of its own, never lifted here). `wipe_target_changed`: the second provider read disagrees with the first; nothing was deleted. |
| **Wipe, provider reads** — a read could not be answered | `wipe_server_unreadable`, `wipe_luks_unreadable`, `wipe_volume_unreadable`, `wipe_protection_unreadable`, `wipe_actions_unreadable`, `wipe_clock_unreadable` (each prints the HTTP code or `shape`) | The answer was not the pinned shape (or the call failed); fail-closed. Re-dispatch once; a repeat is a defect or a provider incident. |
| **Wipe, finish** — the volume's action history | `wipe_detach_in_flight`, `wipe_detach_not_evidenced` (names `no_detach`, `attach_after`, `status_not_success` or `started_before_origin`) | `in_flight`: a provider action is still running; read again later. `not_evidenced`: the history does not show a successful detach started at or after the origin run, or shows any attach started at or after it (`attach_after`, also for the sequence detach, attach, detach). Nothing was called; record on #6897, the owner decides (a re-attach and re-detach after the origin run is not read as the origin's detach). |
| **Wipe, epoch** — the evidence is too old, or the record is wrong | `wipe_assertion_stale` (names `expired`, `future`, `unstamped`, `w7_unstamped` or `w4_expired`), `wipe_record_absent`, `wipe_record_invalid`, `wipe_record_volume_mismatch` | The host assertion is bounded to the detach and the provider re-read to the delete, and the verdict record is one file in the job's temp dir. A refusal in the marker step (the checks run first) writes nothing and reads as `WIPE_REFUSED_BEFORE_ANY_CALL`. The same bound is checked again inside the detach and the delete step, after their marker: a stale record caught there reads as `DETACH_ATTEMPTED_UNCONFIRMED` or `DELETE_ATTEMPTED_UNCONFIRMED` although nothing was sent (conservative), so read the volume first (S2, S4). Dispatch a new run; if the loader is repeatedly slower than the bound, that is a measurement for the CTO, not a bound to raise inline. |
| **Wipe, boot signal** — the evidence row | `wipe_boot_unreadable`, `wipe_boot_absent`, `wipe_boot_predates_server`, `wipe_boot_field_luks_mounted`, `wipe_boot_field_fence_on_mapper`, `wipe_boot_field_erasure_probe`, `wipe_boot_field_plaintext_empty`, `wipe_boot_field_served_repos`, `wipe_boot_field_plaintext_volume` | `unreadable`: the Better Stack read failed or a row was malformed; re-dispatch once. `absent`: the read answered and no row exists; after about 2027-01-12 (90 days from a row of 2026-10-14) that may mean retention was exceeded: route to the CLO ([Retention](#the-wipe-dl-2-10138--6897)). `predates_server`: the newest row belongs to an older server. `wipe_boot_field_<name>`: that field is not as required; `plaintext_empty` and `served_repos` are a STOP routed to the CLO, never a retry. `erasure_probe` is the boot self-probe of the repository-removal path on a synthetic id; it is not a statement about the retired volume. |
| **Wipe, host** — the store is not what it should be | the host verb refuses with one of the store words that the rows above define (the store root is not on the mapper, the freeze sentinel is held, or the store marker is missing, unbound or mismatched), or `wipe_mapper_read_failed`, `wipe_store_root_unreadable`, `wipe_device_still_attached` | The store words mean what their own rows above say. After the detach, a host verb refusal in that step with exit 5 and a word other than `probe_failed` (these words and the store words above) sets the job output `refusal` to `store_not_serving`, and the notify word is `STORE_NOT_SERVING_DO_NOT_FINISH`: do NOT finish, delete nothing, escalate on #6897 (S3b). `probe_failed` (the read did not answer) and an access refusal (exit 3) set no refusal: see the row "Wipe, host — the session could not be answered" and S3c. |
| **Wipe, host** — the device is not the retired volume | `wipe_device_absent`, `wipe_device_not_block`, `wipe_device_is_luks_backing`, `wipe_device_luks_or_unknown`, `wipe_luks_identity_mismatch` | The by-id device of the typed id is missing, not a block device, the LUKS mapper's backing device, LUKS or of unknown type, or the LUKS volume is not the mapper's backing. **Stop.** Nothing was sent. These are wrong-volume signals: escalate on #6897 before any retry. |
| **Wipe, host** — the device is in use or was written | `wipe_device_mounted`, `wipe_device_has_holders`, `wipe_snapshot_present`, `wipe_device_open`, `wipe_device_active`, `wipe_device_written`, `wipe_ro_flag_lost` | The retired device must be unmounted, held by nothing, with no leftover host-local device-mapper snapshot or open handle, quiescent, never written since enumeration (written and discarded sectors both exactly 0 over 2 s) and kernel read-only. `wipe_ro_flag_lost` after a host reboot is the [reboot dead end](#the-wipe-dl-2-10138--6897): route to the CLO. `wipe_snapshot_present` or `wipe_device_has_holders` after a failed run: see Last-resort diagnosis in the wipe section. `snapshot` in these words always means the transient host-local device-mapper snapshot, never a provider-side snapshot or backup. |
| **Wipe, host** — the instance or the boot generation | `wipe_instance_mismatch`, `wipe_boot_generation_mismatch` | `wipe_instance_mismatch`: the host's instance id is not the Hetzner server id (H9, UNVERIFIED until `wipe_check` has run). `wipe_boot_generation_mismatch`: the host booted after the evidence row (`host_booted_after_row`) or the row is outside the 3600 s boot window (`row_outside_window`): the reboot dead end, route to the CLO. |
| **Wipe, host** — the listing | `wipe_boot_layout_signal_absent`, `wipe_boot_layout_signal_offlist`, `wipe_boot_layout_signal_unparseable`, `wipe_snapshot_teardown_failed`, `wipe_plaintext_not_empty` | The listing (`mode=wipe_check` and `mode=wipe`) reads a host-local read-only device-mapper snapshot (RAM copy-on-write) and reports per-type counts; it could not be taken (`absent`; the same word carries a failed read of the top-level `hooks` directory, from the merge of the 2026-10-19 change (PR #10523), which adds the four `hooks_` words that are on the probe-stderr line only: a failed read of `hooks` after an off-list entry was already seen; refusal stands, route to the CTO, do not treat as clear), found an entry outside the path-typed allowlist (`offlist`: the verdict word and the closed field list of 'Reading the exit-34 line', route to the CLO), could not be parsed (`unparseable`), or found content under `repositories/` (`wipe_plaintext_not_empty`: STOP, route to the CLO, bump #8571). `wipe_snapshot_teardown_failed` outranks every other word: the host-local snapshot may still stand; do not re-dispatch. |
| **Wipe, host** — the session could not be answered | `probe_failed` with `rc=16`, `rc=96`, `rc=124`, `rc=141` or `rc=255`, or an argument word beginning `arg_` | `16`: an input, read or instrument failed on the host (the `wipe-assert:` stderr line names a fixed reason). `96`: the answer did not match the phase's fixed shape. `124`: the bound expired (300 s with the listing, 240 s for `clear`, 90 s otherwise); the local timeout does not signal the remote, so wait about two minutes before re-dispatching, because a still-running listing can leave its host-local snapshot standing (a later run then refuses `wipe_snapshot_present`; see Last-resort diagnosis). `141`: the answer was larger than the cap. `255`: the ssh transport failed. **Before the detach (the pre-detach read): nothing was sent;** re-dispatch once, then escalate. **After the detach: the volume IS detached,** this is S3c (the email reads `VOLUME_DETACHED` from a `mode=wipe` run), and the right action is `wipe_finish` (it repeats the read before any delete), not a plain re-dispatch of `wipe`. A wait-and-re-dispatch or "re-dispatch once" in this row is not a standing permission: after a refusal that replaced the exit-34 line (see 'Reading the exit-34 line'), a new CLO addendum is required before any `wipe_check`. |
| **Wipe, loader** — the Tier-B credentials | the loader step is red, or `wipe_loader_not_tier_b` | Raised before the detach marker, so nothing was sent (`WIPE_REFUSED_BEFORE_ANY_CALL`). The loader runs once with only the Tier-B token; a missing token fails closed. Dispatch a new run after fixing the environment secret. |
| **Wipe, detach** — the provider refused or did not confirm | `wipe_detach_rejected` (a 4xx), `wipe_detach_not_confirmed` (the POST outcome, the poll or the final server check was unconfirmed; the poll follows the one accepted action for up to 90 reads or 240 s, whichever ends first, and never sends the POST again) | `rejected`: the provider answered 4xx, read the volume (S2). `not_confirmed`: the detach may have been accepted and the helper never re-sends. The phase is `detach_attempted`: notify `DETACH_ATTEMPTED_UNCONFIRMED` (S2). |
| **Wipe, delete** — the provider refused or did not confirm | `wipe_delete_not_found`, `wipe_delete_rejected`, `wipe_delete_unconfirmed` | `not_found` (404 at the DELETE): the provider API does not list that id (deleted by something else, or the id is wrong); read first (S4, S5). `rejected` (4xx, 423 while attached): not deleted. `unconfirmed`: the DELETE may have taken. The phase is `delete_attempted`: notify `DELETE_ATTEMPTED_UNCONFIRMED` (S4). |
| **Wipe, read-back** — the end event disagrees | `wipe_readback_unreadable`, `wipe_readback_still_exists`, `wipe_readback_name_still_listed`, `wipe_readback_luks_missing`, `wipe_readback_luks_detached` | The read-back needs 404 by id, nothing listed by name and the LUKS volume still the one attached. `unreadable`: re-read read-only (S4). The other four are S5, an incident: never dispatch another delete until the cause is understood. |
| **Wipe, helper** — setup | `wipe_library_missing`, `wipe_scratch_unavailable`, `wipe_usage` | The helper could not load its bearer library or a scratch file, or was called with a wrong verb or option. A defect in the step or the checkout, not a transient. |
| **Wipe, notification** — no marker was written | `WIPE_REFUSED_BEFORE_ANY_CALL`, `WIPE_STATE_UNKNOWN`, `WIPE_CHECK_FAILED` | S1a, S1b and the `wipe_check` failure (no volume or provider state changed; a killed listing may leave a throwaway snapshot, see `snapshot_clear`) ([failure states](#the-wipe-dl-2-10138--6897)). `WIPE_STATE_UNKNOWN` also covers an unrecognised phase value, a rejected or expired environment approval and a lost runner. No wipe word carries the unfreeze remedy. |
| **Wipe, leftover snapshot** — `snapshot_clear` or a `wipe_check` that met a leftover | `wipe_snapshot_not_ours` (the leftover does not match what the listing makes: another origin, a persistent snapshot, a mount or COW outside the pinned directory, or two mounts), `wipe_snapshot_present` (a leftover blocks a `wipe_check` or `wipe`), `wipe_device_open` (a process holds the snapshot open), `wipe_snapshot_teardown_failed` (a removal step failed) | On a refusal of `wipe_snapshot_not_ours` or `wipe_device_open` nothing was removed; after `wipe_snapshot_teardown_failed` some removal steps may have run and the snapshot may still stand (do not re-dispatch `wipe`; dispatch `snapshot_clear` once). `snapshot_clear` answers `absent` when the snapshot name is gone; an orphaned loop device or RAM copy-on-write file left by a run killed between two of its steps is not reported (RAM only; it does not block `wipe_check`). `wipe_snapshot_present` is cleared by an owner-named `snapshot_clear`; `wipe_snapshot_not_ours` is not: escalate to the owner with the run log; this runbook never removes that snapshot. |
| **Wipe, notification** — a marker was written | `DETACH_ATTEMPTED_UNCONFIRMED`, `VOLUME_DETACHED`, `DELETE_ATTEMPTED_UNCONFIRMED`, `DELETE_SENT_UNCONFIRMED`, `VOLUME_DELETED_TEARDOWN_FAILED` | S2, S3, S4 (twice) and S6. The first two and the delete words carry the `wipe_finish` command; its `origin_run` is the original `wipe` run (the plain word `ORIGIN_RUN_ID` in any email but a `mode=wipe` run's, whose own id is the origin). |
| **Wipe, notification** — a `snapshot_clear` run failed | `SNAPSHOT_CLEAR_FAILED` | No volume was detached or deleted. Read the failing step in the run log; a leftover may still be present. |
| **Wipe, notification** — a refusal after the detach, or an already-detached volume | `STORE_NOT_SERVING_DO_NOT_FINISH`, `VOLUME_ALREADY_DETACHED` | S3b: do NOT dispatch `wipe_finish`; escalate. `VOLUME_ALREADY_DETACHED`: this run detached nothing; if a wipe run detached the volume, finish with the command in the email after replacing `ORIGIN_RUN_ID` by that run's id. |

L3 and L7 are different faults: L3 is reachability (NIC, sshd, host), L7 is authorization (the key).
Read the private-NIC heartbeat before treating an L7 verdict as a key problem.

### Host-key mismatch (H4)

A host-key failure is its own verdict, `host_key_mismatch`, and never a timeout. Triage it only after
the lower layers, in this order:

1. **H1, L3 admission.** The bridge reports `ci_ssh_access_denied` or `ci_ssh_liveness_*`: Cloudflare
   Access or the tunnel, not the pin.
2. **H2, L3 private network.** The git-data hop times out: read the private-NIC heartbeat. A key
   mismatch never produces a timeout.
3. **H3, L7 auth.** `reason=auth_refused` means the wrong CI or root key; the pins do not touch it.
4. **H4, L7 host identity.** Likely causes, in order:
   - **(a) web-1's committed pin was captured wrong** (`role=web`, or a bad web-1 line surfacing under
     `role=git-data-auth`, below). Remedy: a re-capture PR (see "Re-capturing web-1's host key").
   - **(b) git-data was re-keyed outside the gated replace job,** so the published pin is not the key
     the host serves. Remedy: dispatch `git-data-host-replace`, which rotates the key, republishes the
     pin and redeploys the app.
   - **(c) a real impersonation.**

**Role attribution caveat.** The jump hop's `ProxyCommand` ssh shares stderr with the outer ssh, so a
bad web-1 key can surface as `role=git-data-auth`. The `role=web` probe runs first, and both
known_hosts lines come from one writer, so read the first failing role. The `workspaces-luks-*`
workflows name no verdict: their log shows ssh's raw error output and the run fails.

**Escalation.**

- **Never re-enable trust-on-first-use** on any path, and never edit the pin to whatever the host
  currently presents without the re-capture procedure.
- If neither (a) nor (b) explains the mismatch, treat it as (c): open an incident (`/soleur:incident`)
  and follow [breach-notice triage](../../../legal/recommended-tools.md#breach-notice-triage). The
  72-hour clock starts there.
- If (a) is still unfixed **21 days** after it was found, escalate to the CLO: the daily at-rest
  encryption verdict behind a published Article 32 claim has been failing closed for that long, and
  the claim-decay window is 30 days.

In the app, the same mismatch surfaces as the Art. 17 erasure outcome `erasure_outcome=host_key_mismatch`
(paging through the existing `art17_erasure_incomplete` rule). Its first remedy is (b)'s redeploy half:
the app holds a stale or wrong pin. Load it with the standalone lever —
`gh workflow run git-data-cutover.yml --ref main -f mode=redeploy -f confirm=REDEPLOY-GIT-DATA` —
then re-read the Better Stack `git_data_pin=present` line.

### Store not empty (`store_not_empty`)

The store was assumed empty by construction (ADR-220 D4, #6976): the flag has never been on, so no
repository should exist. A non-empty store breaks that assumption. Since ADR-239 the dry run measures
the served LUKS store, so the entries are there; a deleted user's repository may remain on it. The
retained plaintext volume is covered by the boot's `plaintext_empty` count, not by this verdict.

1. Open an incident (`/soleur:incident`) and route it to the CLO for an Art. 33 assessment.
2. **Do not replace the host and do not wipe either volume.** The store's contents are the evidence,
   and the Art. 17 question is about them.
3. Pull the repository ids whose erasure may not have completed from Sentry: every event tagged
   `feature:account-delete op:git-data-bare-repo-erasure` carries the id in `extra.gitDataRepoId`.
   Read that field, not `userId`: `extra.userId` is pseudonymized by policy (ADR-029), so it returns
   `no-user-id` or a hash, never the repository name. Whatever the `erasure_outcome`, **resolve**
   these issues once swept, never archive or ignore them: Sentry fires no trigger on an archived or
   ignored issue, so every later refusal that groups into it would be silent (#8572). For any window reaching back before PR #9096,
   the tag query cannot see Error-path reports (#8629): also run host-key step 5.1's message-text
   sweep. The issue's event listing returns each event in
   full, `extra` included (token and host as in `scripts/sentry-issue.sh`):

   ```bash
   SENTRY_ISSUE_RO_TOKEN=$(doppler secrets get SENTRY_ISSUE_RO_TOKEN -p soleur -c prd --plain)
   curl -fsS -H "Authorization: Bearer ${SENTRY_ISSUE_RO_TOKEN}" \
     'https://jikigai-eu.sentry.io/api/0/organizations/jikigai-eu/issues/?query=feature%3Aaccount-delete%20op%3Agit-data-bare-repo-erasure&statsPeriod=90d' \
     | jq -r '.[].id'
   # for each issue id:
   curl -fsS -H "Authorization: Bearer ${SENTRY_ISSUE_RO_TOKEN}" \
     "https://jikigai-eu.sentry.io/api/0/organizations/jikigai-eu/issues/<issue-id>/events/?full=true" \
     | jq -r '.[] | [.dateCreated, (.tags[]? | select(.key == "erasure_outcome") | .value) // "-", (.context.gitDataRepoId // .extra.gitDataRepoId // "no-repo-id")] | @tsv'
   ```

4. Attach the list to the incident. Whether and how each repository is erased is the incident's
   decision, taken with the CLO.

### Flag already on (`flag_already_true`)

`GIT_DATA_STORE_ENABLED=true` in `prd` while the store is still on the plaintext volume means user
repositories may now be written there unencrypted (Article 30 PA-2 (g)(17)).

1. Set the flag off in Doppler `prd`, verify it with a separate read, then redeploy the web container.
   Doppler values are baked into the container at start, so the flag stays on until the redeploy
   (learning `2026-05-19-doppler-env-hot-reload-limitation.md`):

   ```bash
   doppler secrets set GIT_DATA_STORE_ENABLED=false -p soleur -c prd --no-interactive > /dev/null
   doppler secrets get GIT_DATA_STORE_ENABLED -p soleur -c prd --plain   # must print: false
   gh workflow run web-platform-release.yml -f bump_type=patch            # redeploys current main
   ```

2. Open an incident (`/soleur:incident`) and route it to the CLO: find who or what set the flag, and
   treat any repository written while it was on as the "Store not empty" case above.
3. Re-dispatch the dry run only after the release run's deploy has finished; it must clear the flag
   precheck.

## The boot reopen failed: `stage:luks_reopen` (#8210)

A `stage:luks_reopen level:fatal` event means the git-data host booted and
`git-data-luks-reopen.service` could not reopen `/dev/mapper/git-data`. The store is absent
until this is resolved: the fstab line is `nofail`, so the host itself is up and answering on
:22 with nothing mounted. The event carries the phase that failed as `action=`, plus
`result=` / `rc=` / `code=` / `restarts=` read from the unit itself, and the script's stderr as
`detail` (capped at 180 chars by the emitter, after its redaction passes).

**Key on `action=` first.** The table below has one row per value the script and its reporter can
emit. Every check is off-host — a Doppler CLI read, a Hetzner API read or a Sentry query — because
this host ships no journal and has no SSH fallback.

| `action=` | Probable cause | Off-host check | Lever |
|---|---|---|---|
| `config` | `GIT_DATA_LUKS_DEV` or `GIT_DATA_DOPPLER_CONFIG` absent or malformed in `/etc/default/git-data-doppler` | The rendered payload: `bash apps/web-platform/infra/git-data-userdata-budget.sh /tmp/r.yml >/dev/null && grep -A8 'path: /etc/default/git-data-doppler' /tmp/r.yml` | A payload/tfvars defect — both values are template-rendered. Fix the payload, then `git-data-host-replace`. |
| `key` | `GIT_DATA_LUKS_KEY` was not injected: renamed, deleted, or the token lost the config | `doppler secrets --project soleur --config prd_git_data --only-names` | Re-create the secret under its NAME with the SAME value: `doppler configs logs rollback <log_id> --project soleur --config prd_git_data`, with the id from the `configs logs` read (Doppler logs every rename and delete, so the entry is there). No workflow re-converges it: `doppler_secret.git_data_luks_key` is in the CREATE job's `-target` set only, and `manual-rerun` does not carry it. Never a replace — a replace re-runs first boot, which needs the same key. |
| `device` | The LUKS volume is not attached, or did not appear within 30 s | `doppler run -p soleur -c prd_terraform -- sh -c 'curl --disable --noproxy "*" -sS -H "Authorization: Bearer $HCLOUD_TOKEN" https://api.hetzner.cloud/v1/servers?name=soleur-git-data' \| jq '.servers[0].volumes'` against `git_data_luks_volume_id` in the git-data tfvars | `POST /v1/volumes/{volume_id}/actions/attach` with `{"server": <server_id>}` under the same token (Hetzner re-attaches in place; no Terraform address re-creates `hcloud_volume_attachment.git_data_luks` short of a replace), then the timer's next ladder re-runs the reopen — or replace. |
| `header` | The pinned device is not a LUKS header — wrong volume, or a damaged one | The same volume-id read as `device` | **DO NOT REPLACE.** The birth heredoc formats a blank device, so a replace against a damaged or wrong volume destroys the only copy. This is the ADR-115 second-blocker class; the lever is what ADR-068 names as the durable rehydration source — GitHub (every bare repo is a mirror of a user remote, `ensure-workspace-repo.ts`) — re-provisioned onto a recreated volume. **No automated route for that exists yet**; it is a #8211 deliverable, and until it lands the honest state is "store unavailable, data intact upstream, do not replace". |
| `open` | `luksOpen` refused the passphrase — a mis-rotation | `doppler configs logs --project soleur --config prd_git_data` (the config audit log: when a secret last changed; `doppler activity` takes no `--project`) for when the secret last changed | **DO NOT REPLACE.** `doppler configs logs rollback <log_id> --project soleur --config prd_git_data` with the id from the logs read — and only if the change was out-of-band: `doppler_secret.git_data_luks_key` is Terraform-managed (`git-data-luks.tf`), so a `-replace=random_password.git_data_luks` rotation re-converges to the NEW value on the next create-path apply. A replace with the wrong passphrase dies at the birth heredoc's `luks_open` and leaves the host dark. |
| `identity` | The mapper is open but backed by a device other than the pin — a stale pin after a volume swap | `GET /v1/servers/{id}` attached volume ids vs the pin | Correct the pin in the payload, then replace. A host-config change is delivered by replace, never in place. |
| `target` | `/etc/fstab` names the mapper zero times or more than once — a bad #8211 cutover | The rendered payload's fstab line, as for `config` | A payload defect. Fix, then replace. |
| `mount` | The mount unit failed. `detail` carries the mount unit's journal tail | Read `detail` | `wrong fs type … bad superblock` is **filesystem damage**: the lever is the GitHub rehydration route named in the `header` row, NOT a replace. If `detail` reads `result=timeout` with the mount journal EMPTY, read the `luks_reopen_ok` rows first: a forced full e2fsck (`pass=2`) on a large error-flagged volume can exceed `TimeoutStartSec=300` while PID 1's mount completes, and the next attempt then reads `noop` — silently, so the fatal is never contradicted. A unit/payload defect is a payload fix plus a replace. |
| `identity-mount` | The target is mounted from something that is not the mapper | Read `detail` — it names the actual source | Same split as `mount`: damage → the GitHub rehydration route (not yet automated); payload defect → fix and replace. |
| `emit` | The store is OPEN AND MOUNTED — this row is not a store fault. The success emitter returned a STRUCTURAL rc (2, or 126/127 = absent/not executable) after a real reopen; a transient rc=1 is tolerated and never reaches here. **This row is DARK by construction**: the reporter ships through the same emitter, so no `action=emit` event can arrive. The unit exits 3 and `RestartPreventExitStatus=3` keeps it `failed` (a retry would take the silent noop branch and erase the fault). | What an agent sees: at birth, `luks_reopen_unit=no` in `boot_complete` (the boolean requires `ActiveState=active`); after a reboot, the ABSENCE of a `luks_reopen_ok` row where one is due, with no `luks_reopen` fatal either | A payload defect in the emitter, and an urgent one: every LATER failure on this host would be silent too. Fix the payload, then replace. Do NOT touch the volume — the data path is healthy. |
| `unit` | The script never ran: `doppler run` failed, exec failed, or the unit hit its start timeout. Key on `result=` (`exit-code` / `timeout` / `signal` / `start-limit-hit`) and `rc=`; `detail` carries the doppler CLI's own error line | `doppler configs --project soleur` (the config exists) and `doppler configs logs --project soleur --config prd_git_data` (the config audit log: when a secret last changed; `doppler activity` takes no `--project`) (when the token was last used) — both read-only CLI reads needing no host access | A token/config fault is corrected in Doppler; no replace. A `timeout` against a healthy Doppler is a slow boot, which the bounded restarts cover — `restarts=` on the next success row records that it recovered. **An ABSENT `/etc/default/git-data-doppler` lands here, not on `config`:** the unit's `EnvironmentFile=-` makes a missing file a no-op rather than an error, so `DOPPLER_TOKEN` is unset and `doppler run` dies before the script reaches a phase. The off-host check is the same rendered-payload read as the `config` row — a `write_files` entry that failed to render leaves no file at all. |
| `reopened` | Not a failure. The mapper was closed and is now open and mounted — the ordinary post-reboot success | — | None. Emitted at `info` on `luks_reopen_ok`; `restarts=` says whether a transient blip was absorbed |
| `mounted` | Not a failure. The mapper was already open and the target was not mounted — a retry after a failed mount job | — | None, unless it repeats: a mapper open with the target unmounted at every boot means the mount unit is failing for another reason |
| `noop` | Not a failure. Open and mounted already — the birth case, where the runcmd heredoc has just done both | — | None; this path emits nothing at all. In a REHEARSAL after a reset it is a FAIL (see below) |

**Success and no-op rows.** `action=reopened` (the mapper was closed and is now open and mounted)
and `action=mounted` (it was open, the target was not mounted) are emitted at `info` on stage
`luks_reopen_ok`, which is deliberately routed by NO Sentry rule — the fatal router has no
`level` condition, so routing it would page on every healthy reboot. `action=noop` (open and
mounted already, the birth case) emits nothing at all. Read the success rows with:

```bash
doppler run -p soleur -c prd -- bash scripts/sentry-issue.sh --host-events soleur-git-data --stage luks_reopen_ok \
  --start 2026-09-18T00:00:00 --end 2026-09-19T00:00:00
```

**In the rehearsal, `noop` and `mounted` after a reset are a FAIL, not a pass.** A mapper cannot
survive a hard power cycle, so the rung-2 reboot arm treats either as the probe or the host
lying. Only `reopened` releases the evidence.

**Event counts, so a repeat does not read as a new fault.** One exhausted restart ladder produces
exactly ONE `luks_reopen` fatal — and that is because `git-data-luks-reopen.service` carries
`RestartMode=direct`, not a default. Measured on systemd 261 at review: under the default
`RestartMode=normal` the unit transits `failed` before EVERY auto-restart and `OnFailure=` fires
on each attempt plus the terminal `start-limit-hit` — six events per ladder, and a transient
Doppler blip that recovered on attempt 2 still paged a fatal on a healthy host. With `direct` the
reporter runs once, at convergence, with `Result=start-limit-hit` and `NRestarts=<n>`.

**A host that stays broken repeats ONCE AN HOUR, not four times, and that is deliberate.** A
`git-data-luks-reopen.timer` tick inside the still-open `StartLimitIntervalSec=1h` window is
refused on an already-`failed` unit and fires NOTHING (`failed → failed` is not a transition;
measured). The first tick at or after the window closes re-runs a full ladder: one fatal, ~6
Doppler calls, then quiet until the next window. So expect roughly 20–24 events a day while the
store stays closed, collapsed by Sentry into one issue (the reporter's message is constant and
the emitter sets no fingerprint, so tags do not split it — which also means different `action=`
values share the issue: read the FIRST event's `action=`). Recovery from a vendor outage is
therefore bounded by that hour, not by the 15-minute tick: a 20-minute outage self-heals at the
first tick after 60 minutes from the ladder's first attempt. An earlier revision of this
paragraph claimed ~96 evenly spaced fatals a day; the timer file records the correction too.

The inherited gc-failure shape can double-emit only when `doppler run` succeeds and the emitter
itself then exits non-zero (its rc 1, a failed POST): the reporter's `|| "$@"` arm re-runs the
emitter once without the Doppler-injected Better Stack token. That is a bounded retry on the
failure path, not a second fault. A reopen that stays broken produces THREE events per weekly gc
tick, one root cause: the reopen's own fatal, gc's unit failure, and gc's mountpoint fatal.

## Liveness heartbeat (#9438)

The git-data host runs its own feeder (`git-data-liveness.timer`, every 60 s). It pings a dedicated
Better Stack heartbeat, `soleur-git-data-host-prd`, only when its own checks pass; the page is the
beat's ABSENCE. It says why it withheld through the existing emitter (`stage=liveness`, level
`info`, message prefix `SOLEUR_GIT_DATA_LIVENESS`), readable without a login to the host.
Decision record: ADR-283.

**What each signal proves.** `soleur-git-data-prd` (fed by the web hosts) proves only that some web
host can open a TCP connection to the port; it stays green while the disk is full or the store is
closed. `soleur-git-data-host-prd` proves host and store health: sshd answers on loopback, the store
is mounted read-write from the LUKS mapper, its root directory lists and one uncached block of the
mapper reads, bytes and inodes are under 90 %, and the LUKS reopen and nftables units are loaded and
have not failed. Neither proves that a
particular git operation or an erasure call succeeds on a healthy host: the erasure path keeps its
own `unreachable` and `erasure_outcome` reporting. The live reconcile
(`bun plugins/soleur/scripts/reconcile-live-heartbeats.ts`) proves only that the monitor EXISTS; that
the feeder is alive is the soak read below.

**The monitor is born paused and armed only after a measured beat (ADR-117).** The merge of the
payload PR creates the paused monitor and its Doppler secret (two production writes by the ordinary
per-merge apply) and nothing else: no host carries the feeder until the owner's replace. Every step
below that writes (the rehearsal dispatch, the replace, the arm) is the owner's per-step
authorization; a menu answer is not authorization.

### Order

1. **Payload PR merges.** From this point until step 3, `main` carries no valid rung-2 evidence (the
   payload PR deletes the voided attestation file), so every git-data birth and replace refuses,
   an emergency replace included. Owner: the owner. Recommended cap: dispatch the rehearsal within
   two working days. The only way through the gap is
   [Break-glass for the rung-2 interlock](#the-rung-2-emergency-replace-gap).
2. **Rehearsal dispatch on `main`** (`--ref main`, `dry_run=false`), see
   [the rung-2 two-PR sequence](git-data-rung2-rehearsal.md#changing-the-payload-the-two-pr-sequence).
3. **Evidence-only PR** (one file, nothing else in the commit).
4. **Pre-replace read (read-only, owner-authorized):** the monitor reads `paused`, and the secret
   exists. The status read is the one used in the private-NIC readiness read above, with this
   monitor's name:
   `curl -fsS -H "Authorization: Bearer $(doppler secrets get BETTERSTACK_API_TOKEN_READONLY --plain -p soleur -c prd_terraform)" 'https://uptime.betterstack.com/api/v2/heartbeats?per_page=250' | jq '.data[] | select(.attributes.name == "soleur-git-data-host-prd") | {id, status: .attributes.status, paused: .attributes.paused}'`.
   (This curl form puts the token in curl's argv. The `--status` command in step 7 reads the same
   fields without that exposure and is the better read; use it for this step too if you can.)
   The secret check never prints the value (`--only-names` prints a bordered table, so the read asks
   for JSON and tests the key):
   `doppler secrets --only-names --json -p soleur -c prd_git_data | jq -e 'has("GIT_DATA_HOST_HEARTBEAT_URL")'`
   (or the payload PR's merge-time apply run read `success`). If the secret is absent the new host
   boots into `url_unavailable` and heals on its next tick once the secret exists, with no second
   replace.
5. **Host replace with key rotation** (ADR-220 D6). This is the replace the cutover already
   requires, so this change adds none. For the first replace the monitor was paused, so it paged nothing.
   Since the 2026-10-12 arm it is live: a later replace pages about 6 minutes in (period 60 s plus grace
   300 s). Do not pause it by hand to avoid that: a paused armed monitor reads as `fed-but-paused` to the
   nightly reconcile. If a replace needs a pause, say so on #9438 and re-arm with `--arm-one` afterwards;
   steps 4 and 7 apply again only if the monitor is found paused.
6. **Pre-arm soak read** (owner-authorized: it uses the Better Stack query token). The host's events
   land in the git-data Better Stack source, NOT the default table the query script reads, so the
   tables are pinned (the same pin the boot-poll read above uses). `$A` is the replace run's
   boot-trail anchor epoch (`boot-trail anchor: <epoch>` in the replace run's log, as in that
   read), which keeps rows from an earlier host out of the window; the `host_name` and `config`
   predicates keep a rehearsal host's rows out too. Each output row starts with its timestamp, so
   the span and the age below are read off it:

   ```bash
   A=$(gh run view <replace-run-id> --log | sed -nE 's/.*boot-trail anchor: ([0-9]+) .*/\1/p' | head -1)
   doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh \
     --table t520508_soleur_git_data_prd_logs --table-s3 t520508_soleur_git_data_prd_s3 \
     "SELECT dt, raw FROM (SELECT dt, raw FROM remote(\$BS_TABLE) UNION ALL SELECT dt, raw FROM s3Cluster(primary, \$BS_TABLE_S3) WHERE _row_type = 1) WHERE dt > fromUnixTimestamp($A) AND JSONExtractString(raw,'stage') = 'liveness' AND JSONExtractString(raw,'host_name') = 'soleur-git-data' AND JSONExtractString(raw,'config') = 'prd_git_data' ORDER BY dt FORMAT JSONEachRow" \
     | jq -r '"\(.dt) " + (.raw | fromjson | "\(.state) \(.code) config=\(.config) root_pct=\(.root_pct)")'
   ```

   Required: at least four `<dt> ok ok config=prd_git_data` rows whose first and last `dt` are at
   least 30 minutes apart, and no other state after the first `ok`. An `ok ok:last_good` row is a
   healthy beat sent from the last-tried URL rather than a fresh fetch; the soak is not satisfied
   while it appears. The 30-minute floor is the owner's to
   lengthen, knowing that a longer soak widens the replace-to-flip interval ADR-220 D6 wants short.
   An empty result is not a pass: it means the feeder is not armed or not ticking (see "no events"
   below).
7. **Arm** (owner-authorized): unpause the monitor and require a real `up` transition; roll back to
   paused otherwise. Use `arm-heartbeats.sh --arm-one` (#9980), never a by-hand unpause: a manual
   unpause has no rollback if no beat follows. Run every command below from the repository root in a
   clean shell, and never while an apply is in flight (this monitor is not in the per-merge arm list,
   but nothing serializes the two). The token is read by `doppler run` into the child's environment
   only, and `--only-secrets` limits what `doppler` injects to that one secret. The inner `bash` is
   started with its trace and startup-file variables removed (`env -u SHELLOPTS -u BASH_ENV -u BASHOPTS`)
   and with `--noprofile --norc`, so the variables a caller exported cannot trace the wrapper that
   first binds the token; an exported shell function is not removed by that, which is why this runs in
   a clean shell. The script itself puts the bearer on curl's stdin config and refuses to run under
   `bash -x` (rc 78). Do not wrap any command in `set -x`, and do not fetch a token with
   `doppler secrets get --plain` into a variable.

   Before arming, `--status` must read `paused=true status=paused` (anything else means someone or
   something already changed the monitor: stop and read why). Substitute `<id>` with the DIGITS the
   step-4 read printed, nothing else. Give the arm a caller timeout of at least 300 s (it spends up to
   about 150 s polling, 235 s worst case, plus the name resolution), and give it a books path you will
   still know if the terminal is lost:

   ```bash
   # 1. Read-only state of the one monitor (read scope is enough):
   doppler run --only-secrets BETTERSTACK_API_TOKEN_READONLY -p soleur -c prd_terraform -- \
     env -u SHELLOPTS -u BASH_ENV -u BASHOPTS bash --noprofile --norc -c \
     'BS_TOKEN="$BETTERSTACK_API_TOKEN_READONLY" exec bash apps/web-platform/infra/arm-heartbeats.sh --status soleur-git-data-host-prd'
   # 2. The arm (WRITE scope; --id is the id the step-4 read printed: a pin read in a separate step, so a
   #    changed or transposed monitor shows as a mismatch rather than being armed):
   doppler run --only-secrets BETTERSTACK_API_TOKEN -p soleur -c prd_terraform -- \
     env -u SHELLOPTS -u BASH_ENV -u BASHOPTS bash --noprofile --norc -c \
     'ARMED_UNCONFIRMED="$HOME/.arm-one-books" BS_TOKEN="$BETTERSTACK_API_TOKEN" exec bash apps/web-platform/infra/arm-heartbeats.sh --arm-one soleur-git-data-host-prd --id <id from step 4>'
   ```

   `--status` prints `name= id= paused= status= period= grace=` and exits 0 only when exactly one
   heartbeat carries that exact name. `--arm-one` makes the same exact-name resolution, refuses a
   collision or an `--id` that differs from the resolved id (an empty `--id` refuses too), refuses when
   its fixed 150 s deadline exceeds the monitor's own `period + grace - 40`, refuses a books path that
   is not absent or a readable, writable regular file, writes the monitor's id to the books BEFORE the
   unpause request, then unpauses, polls `status` for `up`, and rolls back to paused if no beat lands.
   Its LAST output line is the verdict, `arm-one-result name= id= outcome= rc=` (`id=none` unless
   exactly one monitor matched). Argument, environment and destination refusals print one `::error::`
   line and no verdict, and nothing was changed. Paste the verdict line, and the `--status` read taken
   AFTER it (which must say `status=up`), on #9438 for the record PR.

   Read the OUTCOME, not only the exit code (`rollback-failed` and `unpause-unknown` are rc 1; an
   `unpause-recovered` is rc 1; `rolled-back` is rc 2):

   | outcome | exit | meaning | next step |
   |---|---|---|---|
   | `armed` | 0 | a real beat landed in this run | read `--status`; it must say `status=up`; paste both on #9438. If the books file is yours and still lists the id, the script says so: remove only that line |
   | `already-up` | 0 | the monitor was already `up`; nothing was unpaused (a stale line for it is removed from the books) | counts toward the soak ONLY if the books file was empty or absent and the pre-arm read said `paused=true`; otherwise an earlier run was interrupted, so read why before recording anything |
   | `live-not-up` | 1 | the monitor is live but `down`, `pending` or otherwise not `up`: NOT armed by this run | re-read `--status` after 60-120 s (`pending` right after an unpause is normal). If it reaches `up`, paste that read as an already-live monitor, not as this run's measurement; if it stays not-`up`, pause it in Better Stack and record it on #9438 |
   | `rolled-back` | 2 | no beat within the deadline; the monitor is back to paused | the soak is not satisfied and the flip stays blocked: read the host's `liveness` events (step 6 query). If the books file still lists the id, the rollback is not recorded as clean: run the recovery below |
   | `failed` | 1 | nothing is left live by this run: a refused collision, pin, ceiling or books path, an unreadable list or monitor, a definite 4xx on the unpause, or every status read failing (rolled back) | read `--status`; it must say `paused=true`. If it does not (a gate read that never answered can hide a live monitor), run the recovery below |
   | `unpause-unknown` | 1 | the unpause request failed ambiguously (5xx or no reply) and could not be settled; its id IS on the books | wait 60-120 s and read `--status`: `paused=true` means remove that id's line (delete the file only if it lists nothing else); anything else means run the recovery below |
   | `unpause-recovered` | 1 | an unpause reply was lost, the monitor went live and was rolled back to paused | read `--status` (it must say `paused=true`); investigate the API error |
   | `rollback-failed` | 1 | the monitor is LIVE and unfed and its re-pause failed; its id is on the books | run the recovery below at once |
   | `refused` | 1 | the run stopped at the token, name resolution, pin or ceiling | nothing was changed |
   | none (rc 78) | 78 | refused to run under xtrace | rerun without `-x` and without `SHELLOPTS` set |

   A harness timeout, Ctrl-C or a closed terminal after the `arm-one books:` line printed is an
   INTERRUPTION, whatever the exit code the harness reports: a timeout counts the name resolution as
   well, and no verdict line follows. Treat it as `unpause-unknown`.

   Recovery. It needs the SAME write-scope token as the arm, and the books path is the one you gave
   (`$HOME/.arm-one-books`), or the one printed on the `arm-one books:` line. Read `--status` FIRST and
   decide before running anything, because the sweep re-pauses every id the file lists:

   - `paused=true`: nothing is live. Remove only that id's line from the books file (delete the file only if it lists nothing else, and only if it is yours and private); do not sweep.
   - `status=up` (a real beat landed before the interruption, or after a failed re-pause: record it as an
     already-live monitor, not as this run's measurement): the monitor is armed. Record the read on
     #9438, remove only that id's line from the books (other ids on a shared file may be live and
     unfed), and do NOT sweep.
   - anything else (live and not up): inspect the file first (a stale id left by an earlier run would be re-paused too), then run the sweep.

   Never run two `--arm-one` at once, and never against a books file another run is using: each rewrites the
   file when it finishes and a concurrent append can be lost.

   ```bash
   doppler run --only-secrets BETTERSTACK_API_TOKEN -p soleur -c prd_terraform -- \
     env -u SHELLOPTS -u BASH_ENV -u BASHOPTS bash --noprofile --norc -c \
     'ARMED_UNCONFIRMED="$HOME/.arm-one-books" BS_TOKEN="$BETTERSTACK_API_TOKEN" exec bash apps/web-platform/infra/arm-heartbeats.sh --sweep'
   ```

   After the sweep read `--status` again. If it still says `paused=false`, re-pause the monitor in
   Better Stack (Heartbeats, the id, Pause) and record the failure on #9438; the flip stays blocked.
   The READONLY token reading `--status` but returning a 403 on `--arm-one` is the expected result of
   passing the wrong secret name. This is the first read of `period` and `grace` from the live list
   endpoint; if either is absent the arm refuses.
8. **Record PR** removes `arming_pending` from the manifest row, ticks the precondition above with
   the run ids and times, refreshes the Better Stack ledger row, and cites one Better Stack incident
   delivered to the Slack channel since ADR-260 (read-only proof that the account route delivers;
   the incident link comes from the Uptime API incidents list, `GET /api/v2/incidents`).
   It touches no hash-bound input, so the step-3 evidence stays valid. It carries `Closes #9438`.
9. **Flip-time re-read** (owner-authorized). At the flip dispatch the precondition is read again:
   the step-4 status read shows `up`, and the step-6 query (with `$A` from the CURRENT host's
   replace run, and `AND dt > now() - INTERVAL 15 MINUTE` added to its WHERE clause so the output is
   bounded) shows at least one `ok` row. No row means the feeder has been silent for 15 minutes.

If the soak fails, a `miss` code on a healthy fresh host is a payload defect: fix forward through
the two-PR sequence (the thresholds are hash-bound). Only the owner can accept a known-benign miss,
by a recorded waiver comment on #9438; an agent never waives. A failed arm rolls the monitor back to
paused and the flip stays blocked.

### Reading an event

Every event carries `state`, `code`, `root_pct` (report-only, never gating) and `config`. A
`state=ok` summary lands every 10 minutes while healthy, which is also the proof the feeder is still
ticking: a healthy feeder and a dead timer both produce no `miss` rows, but only the healthy one
produces `ok` summaries, so a missing summary is evidence a human can read in Better Stack (the
event is unrouted by design: nothing pages on its absence, the heartbeat does). A persistent miss
re-emits at most every 30 minutes, and a changed code re-emits at once. A `miss` code may be a
comma-joined list (`ssh_no_banner,disk_full`): read each element on its own.

| `state` / `code` | Meaning | Action |
|---|---|---|
| `ok` / `ok` | every check passed and the ping was accepted | none |
| `miss` / `ssh_no_banner` | nothing on loopback port 22 answered with an `SSH-` banner within 5 s | the host is up but sshd is not; git-data is excluded from the reboot primitive, so replace is the remedy (see the rung-2 gap section above before dispatching one) |
| `miss` / `store_unmounted` | `/mnt/git-data` is an existing directory but not a mountpoint (`mountpoint` exits 32; the dependent store checks are skipped) | read the reopen section for `stage:luks_reopen` |
| `miss` / `store_not_mapper` | the store is not served from `/dev/mapper/git-data` | treat as a plaintext-serving fault: stop, do not flip |
| `miss` / `store_readonly` | the store is mounted without `rw` (a journal abort or `errors=remount-ro`) | the volume is up and refusing every push and erasure: replace is the remedy; do not flip |
| `miss` / `store_unreadable` | the store root does not list, or one uncached block of the mapper cannot be read (the device read fails behind a present mount) | as `store_readonly` |
| `miss` / `disk_full` | bytes used at or above 90 % | growing the volume is a Terraform change through the normal apply path; reclaim is the weekly gc timer |
| `miss` / `inodes_full` | inodes used at or above 90 % (the binding limit, about 55 to 60 % of bytes) | as above |
| `miss` / `unit_failed:<name>` | the LUKS reopen or the nftables unit is `failed` | a failed unit stays `failed` until its next successful run: about 17 minutes after a transient failure, and up to about 1h15 after an exhausted reopen ladder (the unit's start-limit window refuses timer ticks). The miss is real for that whole time |
| `miss` / `unit_missing:<name>` | the unit does not exist, is masked, errored or has a bad setting (`LoadState` is anything but `loaded`) | payload drift: the host is missing a security unit; replace is the remedy |
| `miss` / `unmeasured:<check>` | a gating measurement could not be read or hung past its 2 s cap (`mountpoint`, `mount_source`, `df_bytes`, `df_inodes`, `units`) | an unreadable instrument withholds the beat and is never read as healthy; if it persists across two `ok`-summary intervals, treat it as a host fault and replace. A process stuck in uninterruptible sleep on a dead device survives the cap, so the tick is ended by the unit timeout and emits nothing: silence plus an absent heartbeat is that case |
| `ping_fail` / `ping_fail` | the checks passed, Better Stack rejected the ping twice | a vendor or egress fault, distinct from a host fault; the URL is kept as a last-tried fallback and the next tick re-reads the secret first |
| `ok` / `ok:last_good` | the ping succeeded from the last-tried URL because the secret fetch returned nothing | run the step-4 secret check: if the secret exists the host cannot reach Doppler (replace if it persists); a rotated secret whose old URL the vendor still accepts feeds the OLD monitor, so delete the old heartbeat when rotating |
| `url_unavailable` / `url_unavailable` | no valid URL in the production config: an absent secret, an empty answer, a malformed value, an unreadable config name, OR a Doppler fetch that failed or timed out with an empty cache | run the step-4 secret check first. Absent: create the secret (the next tick heals). Present: the host cannot reach Doppler, so replace if it persists. The monitor pages once armed |
| `disarmed` / `disarmed` | a non-production config with the secret absent (a rehearsal host) | none: checks still run and report, no ping by design |
| (no events) | no `liveness` rows since the boot-trail anchor | the soak is not satisfied and nothing is "healthy": the feeder never armed, the timer is dead or the emit path is down. Read the arm item's own event with the step-6 query, `stage` changed to `liveness_timer` (a `liveness_timer=unarmed` row), and the web-fed `soleur-git-data-prd` state; if both are fine, replace |
| `liveness_timer=unarmed` | `systemctl enable --now git-data-liveness.timer` failed at first boot (an `info` event on stage `liveness_timer`) | the feeder never ran on this host: replace |

`git-data-gc.service` is deliberately NOT a gating unit: whether a failed weekly maintenance run
should page is a policy decision that stays on #8093.

## Sharp edges

- **A pending approval holds `git-data-state`.** A cutover or root-key apply run waiting for its
  environment approval holds the group. A replace dispatched meanwhile waits while holding
  `terraform-apply-web-platform-host`, which stalls web-platform applies. Approve, reject or cancel the
  pending run before you dispatch a replace.
- **A newer queued run cancels an older pending one (#8167).** GitHub keeps one pending run per
  concurrency group. A run that ends `cancelled` without executing a step was displaced, not refused.
  Re-dispatch it once the group's current holder has finished.
- **A re-run asks for approval again.** The environment sits on the job that reads the key.
- **The reporter's own failure is dark, and that is inherent to a host with no journal off-box.**
  If both of `git-data-luks-reopen-failure.service`'s arms fail (Sentry and Better Stack both
  unreachable from the host), that ladder's fatal is lost; the next hourly ladder re-emits, and a
  later success lands `luks_reopen_ok restarts=<n>`. A host with the store closed AND both sinks
  unreachable is dark until one recovers — as is every other git-data EVENT (gc's mountpoint fatal
  uses the same emitter; the web-side probe checks TCP :22 only). The host's own liveness heartbeat
  is the exception that does not depend on the sinks: it pages on ABSENCE
  ([Liveness heartbeat](#liveness-heartbeat-9438)).

## Rotation

The root-key root is additive-only, with no exception and no rotation input. **Any rotation, of the read
token or of the key, is a reviewed PR** that adds a typed allowlist arm naming exactly the addresses it
replaces. A key rotation's PR also lifts `prevent_destroy` on those addresses and accounts for the
re-mint refusal, which blocks a create of the key while the fingerprint file is committed. Then:

1. dispatch `apply-git-data-root-key.yml` from `main`;
2. for the key, a new fingerprint PR commits the printed value;
3. for the key, dispatch `git-data-host-replace`. Until then, dry runs read `reason=auth_refused`.

**git-data's SSH host key rotates on every replace (ADR-237).** The gated replace job re-mints
`tls_private_key.git_data_host_ssh` with the host and republishes `GIT_DATA_SSH_HOST_KEY`; the birth
job mints and publishes it the same way. When that apply run completes with the job and its apply
step both green, the job's `pin_load` step (#8211 PR2 — it replaces the retired
`git-data-pin-redeploy.yml` follower) runs track.sh: a same-version `/hooks/deploy` swap that
makes the running app re-read `prd`, so the new pin loads within minutes, not a release cycle.
No step outside Terraform copies the pin, and no separate rotation input exists. If the pin load
fails (the step goes red), re-run it with
`gh workflow run git-data-cutover.yml --ref main -f mode=redeploy -f confirm=REDEPLOY-GIT-DATA`.
Until it succeeds, erasures page
with `erasure_outcome=host_key_mismatch` from the second rotation on, and with the store on,
replication pushes and fetches fail too.

web-1's host key does not rotate: it is a committed pin, changed only by the re-capture procedure below.

## Re-capturing web-1's host key

web-1 cannot be replaced (the replace gate refuses it until #6931) and ignores cloud-init changes, so
its host key is a committed pin: `apps/web-platform/infra/web-1-ssh-host-key.pub`, `#` header lines
(capture method, UTC date, `SHA256:` fingerprint) and exactly one `ecdsa-sha2-nistp256` key line.
ECDSA-P256 is required because Terraform's SSH client negotiates it (ADR-237). Re-capture only when
web-1's key has legitimately changed (a web-1 rebuild once #6931 lands) or the committed capture was
wrong (H4 cause (a)).

1. From a machine whose egress IP is in `ADMIN_IPS` (if it is not, type `/soleur:admin-ip-refresh` in Claude Code first),
   run `scripts/capture-web-1-host-key.sh <web-1 public IPv4>`. It scans web-1's public port 22
   directly, outside Cloudflare, prints the fingerprint, cross-checks it against your own known_hosts
   entry for that IP if one exists, and writes the pin file with its header. It refuses to run in CI,
   and it refuses when your known_hosts entry differs from the scanned key: investigate that (H4)
   before pinning anything.
2. Open a PR with the new file. The PR body names the capture vantage (the egress IP class, not a
   secret), the UTC date, the fingerprint in the file header, and the cross-check result. The file has
   a CODEOWNERS row, which is advisory only (ADR-237: code-owner review is not enforced on `main`), so
   the reviewer compares the fingerprint independently.
3. Before merge, dispatch `workspaces-luks-verify.yml --ref <branch>`: a strict pass through Cloudflare
   is the second, independent observation of the new key. It must end `success`.
4. After merge, the merge-triggered apply re-runs `terraform_data.web_1_host_key_probe` (its trigger
   hashes the pin) and must end `success`.

Never source a pin from `ssh-keyscan` in a CI path, and never loosen host-key checking to get a run
through.

## Re-capturing web-2's host key (#9151)

web-2 is cattle — replacement legitimately changes its host key, and unlike web-1 there is no
replace gate to wait for. Its pin is `apps/web-platform/infra/web-2-ssh-host-key.pub`, same shape
as web-1's (header lines + exactly one `ecdsa-sha2-nistp256` line), consumed ONLY by
`terraform_data.deploy_pipeline_fix_web2` and `local.web_2_ssh_host_key`.

1. From a machine whose egress IP is in `ADMIN_IPS`, run
   `scripts/capture-web-2-host-key.sh <web-2 public IPv4>` (web-2's public :22 — never through
   Cloudflare, never from CI). It scans directly, fingerprints, cross-checks your known_hosts, and
   rewrites the pin file atomically.
2. Open a PR with the new file; the body names the capture vantage, UTC date, and fingerprint.
3. After merge, the `web-2-ssh-host-key.pub` path entry in `apply-deploy-pipeline-fix.yml`
   auto-fires the apply: the bastion forward + `deploy_pipeline_fix_web2` re-dial web-2 against
   the new pin. A green run is the second observation; a host-key failure is a re-capture PR or
   breach triage, never a loosened check (ADR-237).

## What users see

### During a replace

- **Web requests: nothing.** With `GIT_DATA_STORE_ENABLED` off, provision, replicate and fetch return
  before touching git-data (`apps/web-platform/server/git-data-replication.ts`).
- **Settings → Delete Account completes**, but each deletion during the window can wait up to the
  30 s `execFile` timeout in `removeGitDataRepo` and logs an Art. 17 erasure-failure Sentry event
  (`feature:account-delete`, `op:git-data-bare-repo-erasure`). No repository exists yet, so nothing is
  left behind. These events are expected for the window, and only for the window: one outside a replace
  window is a real finding.
- The `soleur-git-data-prd` heartbeat reads `down` for the window. Once armed, the host-originated
  `soleur-git-data-host-prd` heartbeat pages about six minutes into a planned replace (period 60 s
  plus grace 300 s): announce the window first. Page, then auto-resolve after the new host's first
  ticks, is the normal shape. An incident still open after the new host's boot plus two ticks is a
  failed replace.

### The blocked-recovery window (from the #8189 merge until the fingerprint PR lands)

Both host-creating gates now call the root-key arm, and the arm refuses without the committed
fingerprint. So from the merge of #8189 until the fingerprint PR merges, **every git-data replace and
birth refuses** with `reason=fingerprint_file_missing` or `reason=data_source_absent`. If the git-data
host fails inside that window, it stays down until post-merge steps 1 and 2 are done.

- Web requests still see nothing, for the reason above.
- **Delete Account completes**, but each deletion waits up to the 30 s `execFile` timeout and logs an
  Art. 17 erasure-failure event (`op:git-data-bare-repo-erasure`). **Those events are expected in this
  window** while the host is down. No repository exists, so nothing is left behind.
- Keep the window short: run post-merge steps 1 and 2 back to back.

**Break-glass for the rung-2 interlock (#8210).** `git_data_host_replace` calls
`git_data_rung2_rehearsal_gate`, which binds the landed evidence to a hash of the cloud-init
template, the render module and every payload it binds — **at the dispatched ref** — and reads
the evidence's commit provenance (so the job checks out with `fetch-depth: 0`; a shallow clone
HOLDs). An emergency replace is therefore refused whenever `main` has drifted since the last
rehearsal, including when the host is already down. The route:

1. Find the candidate: **the last commit that touched the evidence file**,
   `git log -1 --diff-filter=AM --format=%H -- apps/web-platform/infra/git-data-rung2-boot-evidence.env`
   (`--diff-filter=AM` skips a commit that deleted the file, as PR #8511 did), or any
   descendant of it up to the next change of a bound file. (Not the template's own log: those
   commits are where the template CHANGED, and by Guard 4 the evidence for a template always lands
   in a LATER, evidence-only commit — at every SHA that log prints the in-tree evidence is the
   previous one and the gate refuses with STALE EVIDENCE.)
2. `gh workflow run --ref` takes a **branch or tag name**, not a SHA: push a tag at that commit
   (`git tag rung2-known-good-<date> <sha> && git push origin rung2-known-good-<date>`), then
   dispatch `git-data-host-replace` with `--ref rung2-known-good-<date>`.
3. The ref must itself CARRY the interlock and the full-history checkout (i.e. be at or after the
   #8210 merge); a pre-#8210 ref has no interlock in its workflow, so dispatching one would be a
   bypass, which this paragraph does not license.

That ref is not a weaker payload — it is precisely the payload a rehearsal booted and reset. No
PR, no SSH, no gate edit; one tag push. Re-rehearse and land evidence for the newer payload
afterwards; do not carry the tag forward as a standing dispatch source.

**Escape hatch.** If the root-key apply cannot succeed (for example a provider or Doppler failure the
dispatch cannot get past) and a recovery replace is needed, the route is **a reviewed PR** that reverts
the `git_data_root_key_arm` call in both gates (`git-data-host-replace-gate.sh` and
`git-data-host-birth-gate.sh`), together with the suites that pin those calls. A replace after that
merge creates the host without the root key: git transport works, and dry runs read
`reason=auth_refused` until a PR restores the arm and the post-merge order runs. Do not bypass the gate
any other way.

## Breach-triage trigger

Open an incident (`/soleur:incident`) and route it to the CLO for an Art. 33 assessment when any of
these is seen:

- a run log or artifact showing root-key material;
- any workflow run, on any branch, that received `DOPPLER_TOKEN_GIT_DATA_ROOT` outside the `cutover`
  job of `git-data-cutover.yml`, including a callee that received it through `secrets: inherit`
  (`reusable-release.yml` receives every repo secret from `web-platform-release.yml` and
  `version-bump-and-release.yml`) and then referenced it;
- an unexplained change to the Hetzner key labelled `soleur-role=git-data-root`, or a create gate
  refusing `reason=fingerprint`, `reason=key_count` or `reason=name`;
- a root-key apply refusing `verdict=git_data_root_key_fingerprint_mismatch` or
  `verdict=git_data_root_key_remint_refused`;
- a dry run refusing `verdict=store_not_empty` or `verdict=flag_already_true` (remedies under the
  verdict map);
- a dry run refusing `verdict=store_not_on_mapper`, `verdict=cutover_frozen`, or
  `verdict=store_unverified reason=marker_mismatch` with no matching boot FATAL;
- a `git-data-root-key` state object or `soleur-git-data-root` Doppler access that no dispatch explains.

Before any repository exists, a leaked root key already reaches the host's own Doppler token
(`prd_git_data`, #6167). Once repositories exist, a leak is likely an Art. 33 event (ADR-220 D4).

## Multi-host DNS rewire

Not part of the read-only proof. `cloudflare_record.app` (`dns.tf`) stays single-host until the
ADR-068 Phase-3 GA flip, which also brings the out-of-band second web host into rotation (ADR-143 D2).
That rewire is sequenced by #8211 together with the real cutover; the design constraint stays recorded
in the `dns.tf` header.

## After the real cutover (owned by #8211)

These stay recorded for the rebuild; none applies to the read-only proof.

- **Verification (observability only).** Sentry `feature:control_plane_route level:error` = 0 (after
  confirming healthy placement events exist), `feature:worktree_lease level:error` = 0,
  `feature:git-data-authz cross_tenant:true` = 0 (a `level:warning` tag). Since #8572,
  `feature:worktree_lease level:error` also counts push **pin faults** (`pin_fault:*`), which were
  invisible to it before: the Error-path push report reached Sentry as `feature=pino-mirror`. Every
  **other** push failure (a fence reject, a transport error, a timeout) still arrives that way and
  stays invisible to this query (#8629), so also read Better Stack:
  `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since '<window start>' --grep 'git-data replication push failed'`
  must print nothing. The `soleur-git-data-prd`
  heartbeat reads `up` through the API read above.
- **Backstop: `origin` is a strict subset of git-data.** `replicateToGitData` force-pushes all refs,
  while `syncPush` commits only `knowledge-base/**` and reroutes protected pushes. After any rollback, do
  not decommission the LUKS volume until git-data-only writes are reconciled.
- **Soak follow-through (gates GA close).** ≥7 days with zero fence false-rejects, zero cross-tenant
  denials and zero `control_plane_route` failures, via
  `scripts/followthroughs/phase3-ga-soak-5274.sh` and a `follow-through` tracker
  (`followthrough-convention.md`), whose directive carries `secrets=SENTRY_AUTH_TOKEN`. When it closes,
  ADR-068 moves `adopting` → `accepted`.

## References

- Dispatch workflows: `.github/workflows/git-data-cutover.yml`, `.github/workflows/apply-git-data-root-key.yml`
- Script: `apps/web-platform/infra/git-data-cutover.sh`; flag precheck: `apps/web-platform/infra/git-data-flag-precheck.sh`
- The wipe (#10138): `apps/web-platform/infra/git-data-wipe.sh` (provider API half), `apps/web-platform/infra/git-data-wipe-assert.sh` (host half, sent over `MODE=wipe_assert`), `scripts/lib/git-data-wipe-runs.sh`, `scripts/lib/git-data-boot-signal-poll.sh`, `tests/scripts/test-git-data-wipe-wedge.sh`; ADR-239 (DL-2), ADR-241 amendment 2026-10-14
- Root-key Terraform root: `apps/web-platform/infra/git-data-root-key/`
- Create-gate arm: `tests/scripts/lib/git-data-root-key-arm-gate.sh`
- ADR-220 (access and credential), ADR-068 (cutover design), ADR-149 (birth route)
- ADR-237 (SSH host keys are pinned); web-1 pin: `apps/web-platform/infra/web-1-ssh-host-key.pub`; capture: `scripts/capture-web-1-host-key.sh`; known_hosts writer: `.github/actions/cf-tunnel-ssh-bridge/write-known-hosts.sh`; redeploy: `.github/actions/dispatch-web-redeploy/track.sh` (inline `pin_load` step in the apply jobs; standalone lever `git-data-cutover.yml` `mode=redeploy`)
- Soak script: `scripts/followthroughs/phase3-ga-soak-5274.sh`
- Convention: `knowledge-base/engineering/operations/runbooks/followthrough-convention.md`
