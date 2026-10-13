---
title: "git-data cutover PR2: the real modes — flip, flag-off-only rollback, same-version redeploy, in-container proof"
date: 2026-09-29
issue: 8211
related_issues: [8101, 8549, 8572, 8573, 8209, 5914, 6897, 9066, 8634]
branch: feat-8211-pr2-real-modes
lane: cross-domain
status: drafted
parent_plan: knowledge-base/project/plans/2026-09-22-feat-git-data-cutover-real-modes-plan.md
---

## Overview

The PR2 plan pass promised by `2026-09-22-feat-git-data-cutover-real-modes-plan.md` §Phase B.
PR1 is done: git-data serves `/mnt/git-data` from the LUKS mapper `/dev/mapper/git-data` at
birth (ADR-239, accepted 2026-09-27); the read-only `proof` mode is live and refusing
`real_cutover_unreconciled`. This plan rebuilds the real modes the proof guards: the flag flip
(`GIT_DATA_STORE_ENABLED` on every web host), a rollback that can only take the flag back off,
the same-version redeploy that carries the flip, the in-container `git_data_store=` startup
line, the freeze writer and proof-before-freeze ordering, the `pin_fault_paging_absent`
live-rule check, the `GIT_DATA_LUKS_CUTOVER_AT` ledger write, and the ADR-220 D6 fresh replace +
ADR-237 amendment. It also carries the #8101 remainder (hooks copy + post-copy fence readback +
wrapper mapper assertion, hash-bound payload) and the #9066 cutover lock-file fix, and closes
#8549 (`git-data-pin-redeploy.yml` replaced by the same-version mechanism).

**The merge of this PR ships code only.** The flip itself remains an operator dispatch of the
gated `git-data-cutover.yml` on `main` after this plan's precondition list passes — the plan
must never read as "merge flips the flag."

## Research Insights

**Property List** (what the design must preserve — each traceable to a named source):

- The proof stays read-only and stays FIRST: a real-mode request that cannot reach its
  preconditions still leaves an empty remote timeline.
- `gd_capture` bounds stay on every remote read (30 s / 4096 B / anchored full-match); new
  reads join that census, they do not bypass it.
- The `prd` read token never shares a process with host bytes (precheck step isolation stays).
- Flag-off rollback mutates the flag and nothing else; the store device is never touched.
- Same-version redeploy acceptance keys on a deployment frame newer than the flag write —
  `head_sha` cannot express "same SHA, newer deploy" (PR1 plan, #5955 wedge).
- Wrapper assertions verify the installed host payload, not the committed source.
- `removeGitDataRepo` stays deliberately ungated (the key's presence arms erasure).
- Freeze is a file the payload owns, not a systemd unit call (the falsified mechanism).

**Cut List** (mechanisms considered and refused):

- A plaintext fallback path in rollback — resurrects the deleted layout; refused by design.
- A parallel new redeploy action — `dispatch-web-redeploy/` exists; rebuild `track.sh`.
- systemd freeze/reload units — they never existed; that is the defect this issue fixes.
- A per-repo `core.hooksPath` tolerance — refused outright; the pinned fence must hold.
- Reusing `DOPPLER_TOKEN_WRITE` for the flag write — it is `prd_terraform`-scoped by design;
  the flag write waits on the #8573 seam, never a scope widener.
- A vector agent on git-data sized like the web host's — the shipper is scoped to the
  git-data units only (the payload token already reaches the host unused).

## Domain Review

### Operations / Infrastructure (BLOCKING, satisfied)

This plan IS the infrastructure change; all gates in §Preconditions are operations-sourced.
Terraform-adjacent workflow code (`apps/web-platform/infra/*.sh`, `.github/workflows/`) —
`hr-every-new-terraform-root` N/A (no new root); the dispatch envelope keeps the
`web-platform-infra-apply` environment gate and `git-data-state` concurrency.

### Legal / Compliance (ADVISORY → routed)

F1 register markers and the ADR-239 retention-end amendment are legal wording — produced by
the CLO agent, append-only (established 2026-09-29 in this session's PR #9206).

## User-Brand Impact

**Brand-survival threshold: single-user incident.** git-data holds every connected user's
repositories; a cutover defect that loses or corrupts a workspace is an existential incident
for that user even at alpha scale. Every destructive or serving-adjacent step is gated on a
verdict, and the ordering invariants (flag-off before any recovery mutation, freeze before
store writes, proof before freeze) exist because the operator cannot watch the store mid-flight.

## What PR2 refuses to do

- No plaintext-serving rollback. After the flag goes off there is no repoint; a rollback mode
  that touched mounts would resurrect exactly the layout ADR-239 deleted.
- No new redeploy machinery. `.github/actions/dispatch-web-redeploy/` exists; PR2 rebuilds its
  `track.sh` on the same-version mechanism in `apply-deploy-pipeline-fix.yml` ("Redeploy to
  same version" step) instead of minting a parallel action.
- No systemd reload/freeze on unit names that do not exist — the failure that falsified the
  deleted implementation. Freeze is a file (`$MOUNT_ROOT/.cutover-freeze`) written and probed by
  this payload, not a unit call.
- No flag write without the dedicated write credential (#8573): `verdict=flag_write_credential_absent`.
- No flip before the ADR-220 D6 fresh replace: `verdict=d6_replace_stale`.
- No flip while the store holds repositories: `verdict=store_populated`.

## Preconditions the real modes enforce (in order, each a named verdict)

| Order | Check | Verdict on failure | Source |
|---|---|---|---|
| 1 | `git-data-flag-precheck.sh` flag read + `GIT_DATA_SSH_HOST_KEY` pin shape (existing step) | `flag_read_failed`, `git_data_host_key_unavailable` | #8189 D-3, ADR-237 |
| 2 | #8209 Tier-B credentials present (env secret `DOPPLER_TOKEN_INFRA_PRIVILEGED` resolves, `source=tier_b`) | `precondition_8209_open` | ADR-241 |
| 3 | App-side SSH client present in the deployed image (`git_data_ssh_client=present`) | `precondition_5914_open` | #5914 / PR #9096 |
| 4 | Pin published and well-formed (host key fingerprint) | `pin_absent` | ADR-237 / #7226 |
| 5 | Live Sentry rule `git-data-host-key-pin-fault` (id 1310055) enabled, exact `in` set {host_key_mismatch, pin_absent, pin_invalid, ssh_client_absent}, owner-email fallback, live-fidelity match — **read the rule, do not infer** | `pin_fault_paging_absent` | #8572, ADR-220 2026-09-28 |
| 6 | Flag-write credential present (#8573's agreed interface) | `flag_write_credential_absent` | #8573 |
| 7 | D6 fresh replace run within the freshness window + `GIT_DATA_LUKS_KEY` rotated + per-id re-erasure run on the replaced host | `d6_replace_stale` | ADR-220 D6 |
| 8 | `served_repos=0` (re-asserted immediately before any store-affecting step) | `store_populated` | plan table |
| 9 | TOFU arm absent in the deployed build (informational; `git_data_pin` present is the check) | source-tree warning only | #5914 |

## Failure-state matrix (the contract every mode satisfies)

The modes are specified per state, not per happy path. `flag` = GIT_DATA_STORE_ENABLED in
`prd`; `freeze` = `$MOUNT_ROOT/.cutover-freeze`; `deployed` = the live image generation.

| state | proof | flip | rollback |
|---|---|---|---|
| flag≠true, no freeze | clear | proceeds | `verdict=nothing_to_rollback` (exit 0) |
| flag==true, no freeze | refuses `flag_already_true` | resume arm B: skip write, redeploy+assert | proceeds (expected entry) |
| flag≠true, freeze held | `cutover_frozen` with writer/age classification | `frozen_foreign` refusal unless sentinel writer is this lineage → resume arm A | refuses until `unfreeze` clears it |
| flag==true, freeze held | `cutover_frozen` classified | resume arm A: mid-window resume | proceeds; clears freeze as its last step when the sentinel's writer is this lineage |

`unfreeze` mode: verifies the sentinel's recorded writer lineage + timestamp, then removes it
and restarts `git-data-gc.timer`; refuses a sentinel with no parseable provenance
(`frozen_unattributed` — a freeze nobody wrote is a host incident, not a cleanup target).
A leaked freeze otherwise bricks every future replace (the bootstrap's erasure probe invokes
`git-data-remove.sh`, which refuses on the sentinel → `erasure_probe=no` → boot FATAL), so the
clearing lever is load-bearing, not optional.

## Implementation phases

### Phase P0 — hash-bound payload (#8101 closeout + #9066 + fence at birth)

- **The real `git-data-pre-receive.sh` ships in the userdata payload map** — added to
  `modules/git-data-userdata/main.tf` beside the placeholder and planted by the bootstrap's
  existing step 5 **at birth**, not copied over SSH at flip time. Rationale: the flip's own
  `d6_replace_stale` precondition means a replace (cloud-init + bootstrap re-run) always
  precedes the flip, and anything installed out-of-band is reverted to the reject-all
  placeholder by the *next* routine replace — a silent total replication outage (the ADR-239
  state-doesn't-survive-replace class, one level down). Semantic ruling (recorded): the real
  hook accepts CAS-conforming pushes; before the flag flips no path holds the transport
  credential to make one, so the placeholder's deny-all posture is preserved in substance.
  Budget: the ~7 KB hook against the 32,768 B user_data cap is measured by
  `git-data-userdata-budget.sh` before merge. Fallback if the budget fails: stage the real
  hook at a non-serving root-owned path via the same payload; the flip then runs a local
  `install` — still no bytes over the wire. The SHA-256 content arm compares against the
  *rationale-stripped* copy (what the render delivers), not the committed file.
- **`served_repos=0` parity**: the proof's store-empty predicate and the bootstrap's
  `_repo_count` already match byte-for-byte (`.*.init.lock`, `lost+found` excluded) — the suite
  pins parity, and the predicate updates *with* the #9066 lock rename below.
- **#9066**: the per-repo `.<workspace_id>.init.lock` is replaced by a **constant-name shared
  lock** (`.init.lock` at the store root — no subject identifier; unlink-on-release is the
  measured fd-reuse race the wrappers' comments refuse). Init operations serialize — they are
  rare and their critical section is `git init --bare` + marker writes. All exclusion sites
  (`_repo_count`, the proof's find, the suites' literal pins) move together. The flip's purge
  step counts then removes the legacy `.<id>.init.lock` residue *inside the freeze window*,
  after asserting no flock is held on each (an in-flight provision holds the lock past the
  sentinel check — the measured race), and excludes `.boot-probe-0.init.lock`.
- **`core.hooksPath` per-repo refusal: CUT** (recorded in the Cut List). Command-line
  `-c core.hooksPath=` dominates repo config through the only ssh-exposed git path, and the
  check is vacuous while `served_repos=0` — it becomes meaningful post-population, tracked by
  #8571.
- **Installed-not-source assertion**: the proof's fence probe asserts the *installed*
  host-side payload carries the gate lines (it already greps the host's installed wrapper).
- **Mount resolution uses the existing idioms**: `findmnt -T` (ancestor resolution) and
  `stat -c %m`, not a hand-rolled walk.
- **git-data-emit call sites, not a journald shipper**: `git-data-emit` is the
  register-recorded redaction boundary (source 2734275); raw journald shipping would leak
  `workspace_id` (= `auth.users.id`) the wrappers echo to stderr — a new GDPR surface
  contradicting the register's mitigation entry. The payload adds `git-data-emit` calls to the
  wrappers' verdict/failure paths (and OnFailure emit units where the gc/reopen precedent
  fits). Blanket journald coverage is explicitly out of scope; if ever required it carries
  its own register entry + redaction review.

### Phase P1 — the flip mode (workflow-level orchestration, script-level probes)

`git-data-cutover.sh` reads no secret store (its contract stands: "NO DOPPLER"). The flag
write is therefore a **workflow step**, not a script verb — the freeze lifetime spans steps,
so unwind is an `if: always()` finalizer step reconciling flag/freeze/gc from progress
markers, not a per-process EXIT trap (a runner kill never runs it). Ordered:

1. Mode-aware flag precheck: flip requires flag≠true; flag==true routes to resume arms.
   Flag writes pipe the value over stdin and discard the CLI's stdout (the
   `cutover-inngest.sh` idiom — otherwise doppler prints the whole `prd` config into the log).
2. Precondition chain — `tier_b_credential_absent`, `ssh_client_absent`, `pin_absent`,
   `pin_fault_paging_absent`, `flag_write_credential_absent`, `d6_replace_stale`,
   `store_populated` — each verdict emits a `remedy:` line naming the clearing action (the
   script's established convention).
3. `live_image_stale` precondition: the running `/health` version on every web host is ≥ the
   release carrying (a) the #5914 TOFU removal and (b) the `git_data_store=` emitter —
   deploys lag merges; a flip against a pre-emitter image cannot prove itself.
4. `deploy_in_flight` precondition: no `web-1-swap` member run in-flight/queued (the flag
   write converts any concurrent env-rebaking deploy into an unattributed cutover).
5. Assert `systemctl is-active git-data-gc.service` inactive (stop ≠ quiesce for an in-flight
   oneshot), then `systemctl stop git-data-gc.timer` (note: `Persistent=true` means a restart
   straddling Sun 03:20 UTC fires the missed run immediately — anticipated, not discovered).
6. Write `.cutover-freeze` with writer identity + UTC timestamp content. Wrappers keep their
   `[ -e ]` check — provenance is read by the *orchestrator* (resume/clear decisions) and the
   proof's `cutover_frozen` classification, never by the fail-closed readers.
   **(DHH's plan-review challenge — the freeze protects a race that cannot exist on an empty
   store: provision/push are flag-gated and unrestarted containers can't see the flag; its
   only live effect mid-window is converting no-op ungated erasures into refusals, and a leak
   is a boot-FATAL landmine. Recorded as a User-Challenge; kept per the operator's stated
   scope — the ordering invariants and the clearing lever above are what make it safe to
   keep. ADR-239's amendment names the freeze writer as PR2 remainder; the plan records both
   sides for the operator's ruling.)**
7. Write `GIT_DATA_STORE_ENABLED=true` through the #8573 credential seam
   (`verdict=flag_write_credential_absent` if absent — never `DOPPLER_TOKEN_WRITE`, which is
   `prd_terraform`-scoped).
8. Read the `/hooks/deploy-status` baseline (PRIOR_START) **after** the flag write — the
   baseline must postdate the write for "frame newer than flag write" to hold.
9. Same-version redeploy (P2) with `peers` covering web-1+web-2; accept `ok` only —
   `ok_peer_fanout_degraded` means a host did not take the swap and fails the flip.
10. Per-host `git_data_store=` assertion via Better Stack readback keyed on `host_name`
    (`scripts/betterstack-query.sh --grep` — the established `git_data_pin=` idiom): web-2 has
    no pinned SSH ingress and `/hooks/deploy-status` reports only the receiving host, so the
    per-host log assertion is the load-bearing check, not a convenience.
11. Unfreeze + restart `git-data-gc.timer` — BEFORE the positive probe (a frozen store refuses
    every verb; the probe cannot run inside the freeze window).
12. Positive replication probe: provision + fenced push + remove with a synthetic id on the
    `boot-probe-0` precedent, transactional, leaving zero residue (anything else re-creates
    the #9066 class and trips `served_repos` for the next run).
13. Write `GIT_DATA_LUKS_CUTOVER_AT` — last, recording a *proven* cutover (it anchors the
    #6897 ledger re-derivation and `lb-weight-gate` Condition B).

On any post-flag-write failure the unwind runs in-band and is **total**: flag off →
same-version redeploy → per-host `git_data_store=` off-lines → unfreeze → gc restart.
`FREEZE_HELD` is reserved for the case the git-data hop itself is dead, and carries a page
path — a summary line alone is not observability.

### Phase P2 — same-version redeploy (repoint `track.sh`, retire the follower)

- `.github/actions/dispatch-web-redeploy/track.sh`: swap the dispatch arm from
  `gh workflow run web-platform-release.yml -f bump_type=patch` to the
  `apply-deploy-pipeline-fix.yml` mechanism ("Redeploy to load applied profile" step) — POST
  `deploy web-platform <image> v<running>` to `/hooks/deploy` with the
  `web-hosts-fanout-parity.test.sh`-pinned peers literal (`web_hosts` has no Terraform output
  and the job installs no terraform), then poll `/hooks/deploy-status` for a frame
  `component=web-platform && tag==TARGET && start_ts > PRIOR_START` (host-clock comparison —
  never runner-side `created_at`; no GitHub Actions run exists on this path at all).
  `lock_contention`/`adr027_prod_already_running` non-terminal; terminal set is `ok` only.
- **Delete `git-data-pin-redeploy.yml` + `source-run-gate.sh` + its suites + every
  reference** (runbook ×~12, CODEOWNERS, `terraform-target-parity.test.ts` rows,
  `tests/scripts/test-dispatch-web-redeploy.sh` rewritten for the new mechanism). The
  follower's raison d'être — a 70-minute release poll can't sit inside the apply lock —
  evaporates when the poll is minutes; the pin-load arm moves **inline into
  `apply-web-platform-infra.yml`'s git-data job after the boot poll** (the apply job already
  holds the `prd_terraform` token carrying `WEBHOOK_DEPLOY_SECRET` + CF-Access creds), so
  every future replace reloads the pin synchronously. A `redeploy` mode on
  `git-data-cutover.yml` provides the manual recovery lever. This closes the pin-staleness
  window a bare retirement would open (every post-flip replace would strand the app on the
  old pin → all replication + erasure traffic fails `host_key_mismatch`).

### Phase P3 — rollback mode (flag-off only) + rehearsal

- `rollback`: expected entry is flag==true (precheck is mode-aware); writes flag off →
  same-version redeploy → per-host off-lines via Better Stack → clears the freeze if the
  sentinel's provenance is this lineage → gc restart. Refuses any mount/volume/plaintext step
  explicitly (`rollback_plaintext_refused`). Recovery accounting verbatim:
  `recovery_warn`, `RECOVERY_FAILED`, `FREEZE_HELD`. Consequence note (recorded): state
  written under flag-on (NVMe worktrees + git-data commits that never reached GitHub) does
  not come back to `/workspaces` — rollback restores the *switch*, not data location.
- **Rehearsal is two dispatches, not a mode**: flip → verify → rollback → verify. A flag-on
  rehearsal on the real fleet is OPT-IN with named contamination consequences: any real
  session end during the window pushes a real repo → `served_repos` breaks the next flip AND
  voids the wipe's "never held a repository" evidence. If run: synthetic-id probe only,
  `served_repos=0` asserted at entry AND exit, per-id re-erasure of anything that landed,
  `GIT_DATA_LUKS_CUTOVER_AT` never written.

### Phase P4 — D6 fresh replace + rotation (operator-dispatched, cutover-verified)

- New apply target `git-data-host-rotate` in `apply-web-platform-infra.yml`: a single
  `-replace` set — `random_password.git_data_luks` + `doppler_secret.git_data_luks_key` +
  `hcloud_volume.git_data_luks` + attachment + `hcloud_server.git_data` (+NIC/firewall) —
  because the LUKS key can only rotate *with* a fresh volume (a rotated passphrase against the
  retained volume can never `luksOpen` — the birth gate's `luks_orphan_mint` arm documents
  the failure). The replace gate gains a typed arm admitting exactly this set (today it
  refuses `luks_passphrase_touched`/`luks_volume_destroyed`). `served_repos=0` is asserted
  immediately before — the volume delete is irreversible.
- The cutover does NOT orchestrate the replace (self-deadlock: `git-data-state` is held by
  the cutover run and required by the replace job). `d6_replace_stale` is a **read**: latest
  `git-data-host-replace|rotate` run whose apply concluded `success` (the run record is the
  stamp; `source-run-gate.sh`'s parse pattern is the precedent) plus key-rotation proof
  (Doppler `updated_at` on `GIT_DATA_LUKS_KEY`, or the rotate job's own marker).
- ADR amendments via the mandated agents: ADR-237 D6 (the `workflow_run` follower is retired —
  its pin-load duty moves inline), ADR-220 D6 wording, ADR-239 dated amendment (freeze-writer
  disposition + #9066 retention end). Register F1 markers via CLO agent, append-only.

### Phase P5 — tests

- Mode/state matrix coverage: every (flag × freeze × mode) cell + resume arms; `flag_already_true`
  on proof, accepted on rollback, resume-routed on flip.
- Redeploy suite rewritten for the webhook mechanism: `start_ts > PRIOR_START` acceptance,
  `peers` payload, `ok`-only terminal set, stale-frame rejection.
- Payload arms: real-hook render bind + bootstrap plant order; emit call sites present;
  lock-name parity across `_repo_count`/proof/suites; freeze provenance format.
- Workflow tests: credential census (each new secret named in exactly one step),
  `web-1-swap` membership, `timeout-minutes` ≥ the drain budget, `if: always()` finalizer.
- Suites register per convention — `apps/web-platform/infra/**/*.test.sh` self-registers via
  the glob runner; `scripts/test-all.sh` covers only non-infra suites.

## Operator sequence after merge

1. Merge this PR; the real modes exist on `main` but every precondition still stands.
2. **Wait for the PR2 image to be serving**: the merge's deploy arm must conclude and
   `/health` must report the merge SHA on both web hosts (the `git_data_store=` emitter is
   app code — a same-version redeploy replays the same tag).
3. **Rung-2 re-rehearsal + evidence PR** (mandatory): every payload edit invalidates the
   hash-bound evidence — `git-data-rung2-rehearsal.yml` from `main`, `dry_run=false`, then the
   evidence-only PR. Without it `git-data-host-replace` is HELD (stale evidence) and the D6
   step below refuses.
4. `proof` dispatch — store state unchanged.
5. **D6 `git-data-host-rotate`** dispatch on `main` — host + LUKS key + volume together;
   boot evidence read (`boot_complete`, `luks_mounted=yes`, `fence_on_mapper=yes` — now the
   REAL fence, and the emit call sites live); the inline pin-load redeploy arm proves itself
   here for the first time.
6. `proof` again — post-replace readback.
7. Optional rehearsal (two dispatches, contamination caveats in P3).
8. **Gated flip dispatch** — per-step authorization; ~80-min drain budget inside a ≥120-min
   job; verify `git_data_store=` on both hosts via Better Stack + the transactional probe.
9. Soak ≥ 7 days → wipe PR (owns retiring the flip/rollback machinery as durable-for-once
   code) → #6897 git-data half.

## Consequences named (not bugs — states the plan accepts)

- **Worktree-root stranding**: `isGitDataStoreEnabled()` also moves `getWorkspaceWorktreeRoot`
  from `/workspaces/<id>` (persistent volume) to `/var/lib/soleur/worktrees/<id>` (NVMe).
  Post-flip every existing workspace takes the fresh-graft path — GitHub tip + empty overlay;
  local-only state (uncommitted files, unpushed branches) is stranded-but-retained on
  `/workspaces`, invisible to the app. At current scale the divergence is near-nil, but the
  pre-flip sequence gains a drain+reconcile step: quiesce sessions, reconcile workspaces to
  GitHub (or snapshot), then proceed. Rollback strands flag-on-era state symmetrically — the
  erasure-only arm (`removeGitDataRepo` ungated) keeps deletes working either way.
- **`GIT_DATA_STORE_ENABLED` is "true" in config-space the instant the Doppler write lands** —
  every future container start picks it up. That is exactly why the `deploy_in_flight` +
  `web-1-swap` preconditions exist and why a wedged flip's unwind must attempt flag-off before
  reporting.
- The emit-only observability decision means uncovered journald stays on-box (a deliberate,
  register-consistent boundary).

## Credential surface added to the cutover job (each named, one step each)

- #8573 flag-write token (TBD by #8573's seam — `flag_write_credential_absent` until then)
- `WEBHOOK_DEPLOY_SECRET` + CF-Access creds (`prd_terraform`-resident, already in the bridge
  step's config) — the same-version POST
- `SENTRY_ACTIONS_RO_TOKEN` — the single-rule GET (read-only; the write-capable
  `SENTRY_IAC_AUTH_TOKEN` never enters this job)
- Better Stack query token for the `git_data_store=`/`git_data_pin=` readback

The workflow header's "No write-scoped token is referenced" and "mutates nothing on web-1"
lines are rewritten in the same edit that adds these.

## Files to Edit (payload arm — hash-bound)

- `apps/web-platform/infra/git-data-cutover.sh` — real modes (flip / rollback / unfreeze /
  redeploy), the precondition chain, freeze writer + provenance, mode-aware dispatch.
- `apps/web-platform/infra/git-data-flag-precheck.sh` — mode-aware verdicts + write-path
  read-back + `flag_write_credential_absent`.
- `apps/web-platform/infra/git-data-provision.sh`, `git-data-remove.sh`,
  `git-data-transport-wrapper.sh`, `git-data-pre-receive.sh` — #9066 constant-name lock,
  emit call sites, pre-receive becomes a render-delivered payload.
- `apps/web-platform/infra/git-data-bootstrap.sh` — plants the real pre-receive (step 5 arm),
  `_repo_count` exclusion update.
- `apps/web-platform/infra/cloud-init-git-data.yml` — payload staging for the real hook;
  emit units for the wrappers.
- `modules/git-data-userdata/main.tf` (or its in-repo path) — payload map gains the real hook.
- `apps/web-platform/infra/git-data-userdata-budget.sh` — re-measure the 32,768 B cap.
- `apps/web-platform/infra/git-data-luks.tf`,
  `tests/scripts/lib/git-data-host-replace-gate.sh`,
  `.github/workflows/apply-web-platform-infra.yml` — the `git-data-host-rotate` typed gate arm
  + inline pin-load same-version arm in the git-data job.
- `.github/workflows/git-data-pin-redeploy.yml`, `.github/actions/dispatch-web-redeploy/` —
  `track.sh` rebuilt on the webhook mechanism; the follower workflow + `source-run-gate.sh`
  deleted; `tests/scripts/test-dispatch-web-redeploy.sh` rewritten; reference sweep
  (CODEOWNERS, `terraform-target-parity.test.ts`, runbook mentions).
- `.github/workflows/git-data-cutover.yml` — mode inputs, the write/finalize steps,
  `web-1-swap` job membership on the deploy-wait job, `timeout-minutes` ≥120, credential
  census + header rewrite.
- `apps/web-platform/server/git-data-replication.ts` (or `index.ts` startup arm) — the
  `git_data_store=` warn-level line beside `logGitDataHostKeyPinAtStartup`; test twins
  (`git-data-host-key-pin.test.ts`, `server-index-boot-pin-line.test.ts`).
- `knowledge-base/engineering/architecture/decisions/ADR-220-*.md`,
  `ADR-237-*.md`, `ADR-239-*.md` — dated amendments.
- `knowledge-base/legal/article-30-register.md` — F1 marker flips (via CLO agent output,
  append-only).
- `knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md` — verdict
  table rows, the real operator sequence, the replace-time fence note.
- `scripts/encryption-posture-ledger.json` — `reevaluate_when` update.
- `tests/scripts/test-infra-privileged-tier-census.sh` — if any secret's tier placement
  changes.

## Files to Create

- `knowledge-base/project/specs/feat-8211-pr2-real-modes/tasks.md` (this pass's tasks).
- The #8573 flag-write seam script (if #8573's interface is a script) + suite.
- `apps/web-platform/infra/git-data-cutover-real-modes.test.sh` (or extension of the existing
  cutover suite) covering every verdict and ordering.
- The single-rule Sentry GET probe (destination-pinned transport pattern) + suite.

## Acceptance criteria

- [ ] AC1: `git-data-cutover.sh` modes `proof`, `flip`, `rollback`, `unfreeze` (+ `redeploy`
  recovery lever); every precondition above is a named verdict with a `remedy:` line and a
  test; the mode↔env mapping is stated and `CONFIRM_WIPE` still refuses.
- [ ] AC2: rollback writes the flag off before any other mutation, refuses plaintext-serving
  steps explicitly, and clears a same-lineage freeze as its last step.
- [ ] AC3: `track.sh` POSTs `/hooks/deploy` with the parity-pinned peers literal; polls
  `/hooks/deploy-status` `start_ts > PRIOR_START` read after the flag write; accepts `ok` only.
- [ ] AC4: per-host `git_data_store=` (and `git_data_pin=`/`git_data_ssh_client=` on the same
  check) asserted via Better Stack keyed on `host_name` for every `var.web_hosts` member —
  a Doppler-only "true" fails the flip.
- [ ] AC5: `.cutover-freeze` carries writer+timestamp; the proof's `cutover_frozen` classifies
  by content; `unfreeze` clears only same-lineage sentinels (`frozen_unattributed` refuses);
  freeze-write happens only with gc.timer stopped AND `git-data-gc.service` inactive.
- [ ] AC6: `pin_fault_paging_absent` = a single-rule GET on rule 1310055 under
  `SENTRY_ACTIONS_RO_TOKEN` asserting enabled + exact `in` set + owner-email action; a real
  page is fired once as an operator step before the gated dispatch (delivery evidence, not
  rule shape).
- [ ] AC7: the real `git-data-pre-receive.sh` is planted at birth by the render (payload map +
  bootstrap step), SHA-256-verified against the stripped copy; a routine replace after merge
  serves the real fence — asserted in the replace's boot evidence.
- [ ] AC8: `GIT_DATA_LUKS_CUTOVER_AT` written only after unfreeze + probe success.
- [ ] AC9: `git-data-emit` call sites cover the wrappers' verdict/failure paths; the render
  stays under the 32,768 B userdata budget (measured); the shipper premise correction is
  recorded (the token feeds `git-data-emit`, source 2734275).
- [ ] AC10: ADR-237 D6 + ADR-220 D6 + ADR-239 dated amendments land via the mandated agent
  forks (CLO for legal wording); dated records append-only; the register F1 markers ride the
  CLO's output.
- [ ] AC11: the job's `timeout-minutes` ≥ the drain budget (≥120); `if: always()` finalizer
  reconciles flag/freeze/gc from progress markers; `web-1-swap` membership is job-level on
  the deploy-wait job; `deploy_in_flight` precondition present.
- [ ] AC12: #9066 — constant-name lock; exclusion predicates moved in lockstep; residue purge
  is count-then-remove inside the freeze window with flock-held assertion; `boot-probe-0`
  excluded.
- [ ] AC13: the #8573 credential seam's interface is named; the flag write pipes stdin and
  discards stdout; no write-scoped token other than the flag-write credential appears in the
  job.
- [ ] AC14: `git-data-pin-redeploy.yml` + `source-run-gate.sh` deleted with the full
  reference sweep (runbook, CODEOWNERS, parity suites); the inline pin-load arm in
  `apply-web-platform-infra.yml` fires on every git-data replace/birth apply.
- [ ] AC15: drain+reconcile step exists in the operator sequence; the runbook's verdict table
  gains a row per new verdict; `encryption-posture-ledger.json`'s `reevaluate_when` is updated.
- [ ] AC16: all suites registered per convention; `LEFTHOOK_EXCLUDE=bun-test,plugin-component-test`;
  CI green on the exact head SHA before merge; plan-review panel findings applied.
