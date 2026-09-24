---
title: "fix(infra): count the git-data plaintext tree through a dm snapshot so a dirty journal no longer blocks boot"
date: 2026-09-24
slug: fix-git-data-plaintext-dirty-journal-dm-snapshot
branch: feat-one-shot-git-data-dirty-journal-dm-snapshot
issue: 5274
type: fix
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
draft_pr: 8711
related: [5274, 5914, 8211, 8710, 8209, 8571]
---

## Overview

The git-data host's store-verify step refuses to count the retained plaintext volume when its ext4
journal is dirty, so a host replace that follows an unclean predecessor shutdown never reaches
boot_complete. This plan replaces that refusal with a count taken through a throwaway
device-mapper snapshot, so the journal replays into disposable copy-on-write space and the
retained volume is never written.

**What happened (measured 2026-09-24).** ADR-237 post-merge step 3 (`git_data_host_replace`, run
35979304442) applied cleanly (6 added, 1 changed, 4 destroyed) and put the new pin fingerprint
`SHA256:WRk5AW6j9IHNpE9KJ3FpVZbDp4I9HerMD84LGP0uB48` into Doppler `prd`
`GIT_DATA_SSH_HOST_KEY`. The boot poll ran 20/20 with no `boot_complete`: host `soleur-git-data`
FATALed at 09:09:30Z (Sentry `stage:bootstrap`) with
`FATAL: plaintext_unverified reason=journal /dev/disk/by-id/scsi-0HC_Volume_106867358 has needs_recovery set; its tree was not counted`.
That is exactly the gap ADR-239 §Consequences accepted: the predecessor was destroyed while the
plaintext volume was mounted read-write, so the journal is dirty, and the bootstrap only tried a
`ro,noload` mount. Nothing was written. There is no `/etc/git-data/store-verified` marker, so every
store-acting script and every git-data erasure refuses (Art. 17 sweep 09:07Z-09:32Z: zero Sentry
`erasure_outcome` issues).

**The fix, in runbook order:** this PR (code + tests + ADR amendment + rehearsal that reproduces a
dirty journal) -> rung-2 rehearsal dispatch -> evidence-only PR -> `plan_only` replace rehearsal ->
real replace. **No production dispatch is authorised by this plan**; each one stops the pipeline
for the operator's explicit per-command go-ahead (see `## Operator-gated dispatches`).

**Do not run another `git-data-host-replace` until this fix and its rung-2 evidence are merged.**

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

## Research Insights

### Premise Validation

- #5274 OPEN, #5914 OPEN (latest comment records the 2026-09-24 replace and the plan_only-triggered
  redeploy), #8710 OPEN ("git-data-pin-redeploy: source-run-gate treats a plan_only
  git-data-host-replace rehearsal as a pin rotation"), #8209 OPEN, PR #8711 OPEN draft. No cited
  blocker is already resolved.
- `apps/web-platform/infra/git-data-bootstrap.sh` store-verify unit exists between the sentinels
  `# ---- BEGIN store-verify unit ----` / `# ---- END store-verify unit ----`; the plaintext check is
  the `_pt_id` block (mount `-o ro,noload,nosuid,nodev,noexec`, `dumpe2fs -h` needs_recovery check
  -> `reason=journal`). Premise holds: a dirty journal is FATAL by design today.
- ADR corpus: ADR-239 Decision 2 prescribes the `ro,noload` mount and its Consequences accept the
  dirty-journal gap; Alternatives row D rejects keeping the volume mounted ro for the host lifetime
  (not proposed here). No ADR rejects a dm-snapshot read. The proposed mechanism amends ADR-239
  rather than contradicting a rejected alternative.
- Capability claims verified: `cryptsetup` (in the cloud-init `packages:` list) Depends on
  `dmsetup` on Ubuntu noble (packages.ubuntu.com/noble/cryptsetup); `losetup`/`blockdev` are
  util-linux/mount (required priority); `dumpe2fs` (e2fsprogs) already runs on the production path.
  `dumpe2fs -h` on e2fsprogs 1.47 prints `Total journal blocks:` and `Block size:` (measured locally
  on a 10 GiB image: 16384 blocks x 4096 = 64 MiB journal).

### Property List (Phase 0.6b)

- **P1** A fresh git-data host whose retained plaintext volume has a dirty ext4 journal reaches
  `boot_complete` if and only if the *post-replay* tree holds zero `repositories/` entries.
- **P2** The retained plaintext volume receives zero writes during and after verification: the
  kernel read-only flag is set on it before any mount, dm table or write-capable open (the
  read-only `cryptsetup isLuks` probes in §1 and in the unit legitimately precede it), and journal
  replay lands only in disposable COW space.
- **P3** The counted tree is the post-replay tree, never the stale on-disk tree (a `noload` read can
  miss an entry that exists only in the journal).
- **P4** Every failure is a named `FATAL: plaintext_unverified reason=<word>` or
  `FATAL: plaintext_residue count=<n>` at `stage=bootstrap`, and no marker is written.
- **P5** No transient device (snapshot, loop, tmpfs) survives the unit on any exit path; a teardown
  failure is a named FATAL, never a silent leak.
- **P6** Rung-2 evidence proves the dirty-journal case was actually booted, so a rehearsal whose
  seed failed to dirty the journal cannot produce releasing evidence.
- **P7** No production workflow dispatch occurs without the operator's per-command go-ahead, and the
  `plan_only` rehearsal does not fire a production redeploy (#8710 fixed first).
- **P8** The exact state G3 will boot into — a LUKS volume already formatted by a predecessor that
  was destroyed while the mapper was mounted (the adopt arm of the cloud-init LUKS stage, never yet
  booted on a first boot) plus a dirty plaintext journal — is rehearsed before G3. (Added from the
  CTO review: today's failed host already formatted the production LUKS volume.)

### Cut List (Phase 0.6b)

- *Restore the plaintext device to rw after the count* -> buys no property: nothing on the host
  writes the plaintext volume later (the wipe is a terraform-side `git_data_volume_id` removal,
  ADR-239 §Consequences "The wipe branch"; runbook research found no on-host write). Restoring
  would weaken P2. **Cut: the ro flag stays for the host lifetime.**
- *Gate-side enforcement in `tests/scripts/lib/git-data-birth-readiness-gate.sh` of the journal
  state* -> P6 is already bought by making the capture script refuse PASS without it; the gate
  already refuses anything but `RUNG2_BOOT_REHEARSAL=PASS`. **Cut.** (The replace arm's own verdict
  key is a different matter: it follows whatever the gate does for `RUNG2_REBOOT_REOPEN`.)
- *A separate seed server resource* -> P6 is bought more faithfully by booting a seed render on the
  same `hcloud_server.rehearsal` address and replacing it with the payload render, which is the
  production event (a replace of a host that had the volume mounted rw). **Cut.**
- *A branch that uses the snapshot only when needs_recovery is set* -> two code paths, one of which
  the rehearsal would not boot. **Cut: one path, always through the snapshot.**
- *Plan-review cuts (DHH + code-simplicity, both panels firing on the same scope -> delete, not
  fix):* the MemAvailable refusal, the `command -v` loop, `modprobe`, the name-exists probe, the
  origin maj:min check, the snapshot-name seam, a dedicated tmpfs mount, the `readonly`/`teardown`
  reason words, a separate `replace` plan-shape mode, the `RUNG2_*PLAINTEXT_JOURNAL` evidence keys,
  the birth-readiness-gate edit, and PASS on `plaintext_volume=absent`. Each is covered by an
  existing mechanism named in Phase 2/3.
- *A seed that also luksFormats the LUKS volume to reach the adopt arm (P8)* -> duplicates the
  cloud-init format logic in a rehearsal-only file, so the adopt arm would be tested against a
  header the production stage did not write. **Cut in favour of a second payload boot via
  `terraform apply -replace`**, where the real payload formats and the real payload adopts.

### Relevant files (current state)

| Path | Role |
|---|---|
| `apps/web-platform/infra/git-data-bootstrap.sh` (store-verify unit, `_pt_id` block) | the check being replaced |
| `apps/web-platform/infra/git-data-bootstrap-store-verify.test.sh` | non-root stub harness; extracts the unit by sentinel; rows S6 (`ro,noload` literal), R1 (mount opts), R4 (dirty journal FATAL); `MIN_ASSERTIONS=90` floor |
| `apps/web-platform/infra/inngest-redis-luks-loopback.test.sh`, `workspaces-luks-loopback.test.sh` | precedent for a root-only real-device suite run as `sudo bash` in `infra-validation.yml`, exits non-zero with `LOOPBACK_UNAVAILABLE`, exempted in `.github/scripts/test/test-infra-suite-registration.sh` (#7076) |
| `apps/web-platform/infra/cloud-init-git-data.yml` `packages:` | git, util-linux, cryptsetup, curl, nftables |
| `apps/web-platform/infra/rung2-rehearsal/{main,rehearsal,variables}.tf` | fresh plaintext + LUKS volumes, `hcloud_server.rehearsal` (`user_data = base64gzip(module.git_data_userdata.rendered)`), `hcloud_volume_attachment.rehearsal{,_luks}` (`automount = false`) |
| `.github/workflows/git-data-rung2-rehearsal.yml` | plan -> additive-only guard ("destroys nothing", inline jq) -> apply -> capture -> settle -> Hetzner API hard reset -> reopen probe -> teardown |
| `scripts/followthroughs/git-data-rung2-evidence-capture.sh` | `_TERMINAL` field list; HOSTROWS SQL selects `plaintext_empty` but not `plaintext_volume` |
| `apps/web-platform/infra/git-data-emit.test.sh`, `tests/scripts/test-git-data-boot-signal-poll.sh`, `scripts/followthroughs/git-data-birth-emitter-6982.sh`, `tests/scripts/test-git-data-rung2-evidence-capture.sh` | every enumeration of the `boot_complete` field set (NON_TERMINAL / G2_INFORMATIONAL / `_asserted_keys`) — a new field must be swept through all of them (`hr-type-widening-cross-consumer-grep`) |
| `.github/actions/dispatch-web-redeploy/source-run-gate.sh` + `tests/scripts/test-dispatch-web-redeploy.sh` | #8710's defect: the gate keys on the source job's `success`, which a `plan_only` run also reaches |
| `knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md` §Verdict map row "could not verify the retained plaintext volume" (`reason=<mount\|source\|journal\|umount>`), §"If the fresh host fails a boot check after step 3" | reason vocabulary + recovery text |
| `apps/web-platform/infra/git-data-userdata-budget.sh` | 22,284 B stored / 32,768 B cap (10,484 B headroom, measured by research) |

### Kernel/ext4 facts the design rests on (to be re-proven by the loopback suite, not trusted)

- ext4 replays a dirty journal on a **read-only** mount whenever the block device is writable, and
  refuses (`write access unavailable, cannot proceed`) when the device is read-only; `noload` skips
  replay and shows the stale on-disk tree. Hence: origin read-only, snapshot writable, mount the
  snapshot without `noload`.
- The dm `snapshot` target opens its **origin read-only** (only `snapshot-merge` opens it for
  write), so a snapshot can be stacked over a `blockdev --setro` device; all writes go to the COW
  device. Non-persistent COW (`N`) keeps the exception table in memory.
- After replay on a ro mount, ext4 clears `needs_recovery` and commits the superblock **to the
  snapshot**; `dumpe2fs -h /dev/mapper/<snap>` then shows no `needs_recovery`, while the origin
  still does.
- Replay writes at most the journal's logged blocks plus orphan cleanup and the superblock, so a COW
  of `Total journal blocks x Block size + 64 MiB` bounds it (128 MiB for the production 10 GB
  volume). A COW overflow invalidates the snapshot (I/O errors, `dmsetup status` reads `Invalid`),
  which must surface as a named FATAL, never as a short count.

### Institutional learnings applied

- `2026-07-24-guest-luks-store-must-gate-consumer-on-mount-...`: assert the mount SOURCE by
  equality, and make guards anchor on the halt (`exit 1`) — a presence grep passes a fall-through.
- `2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-...` / `2026-08-13-every-guard-i-shipped-was-satisfiable-...`:
  mutation rows written before the guard; must-PASS rows that are not the canonical fixture.
- `2026-08-20-the-channel-was-silent-on-the-path-it-was-built-for.md`: an ORDER property (setro
  before any open) needs a REORDER row, not a delete row.
- `2026-07-03-pass-is-not-proof-...`: a rehearsal that never produced the dirty state must not
  PASS; the payload itself must measure and emit the origin's journal state (P6).
- `2026-07-07-immutable-redeploy.md`: `-target` omits dependents; phase B of the rehearsal must
  replace the attachments with the server, which terraform's normal (untargeted) replace does.
- `2026-09-23-every-fix-i-shipped-to-close-a-defect-carried-the-same-defect.md`: record every CI
  failure between commits in session-state; test the fix against the scope it claims.
- `2026-07-03-cloud-init-32kb-cap-...`: re-measure `git-data-userdata-budget.sh` after the
  bootstrap grows (comments are render-stripped, ADR-152).

### CLAUDE.md / constraint conventions carried

- Admin-merge only when every required context in
  `scripts/ci-required-ruleset-canonical-required-status-checks.json` is present AND `success` by
  name on the exact head SHA (count them). Resolve `PROMOTED_FILES` conflicts in
  `scripts/guard-vacuity-floor.test.sh` as a union. Re-derive baselines, floors and byte budgets
  after every merge. Run `scripts/test-all.sh --capacity` before any commit that stages `.ts`. A new
  repo-global `-live` suite goes into `ALWAYS_ON_SUITES` in `scripts/lib/test-affected-paths.sh`
  (the new loopback suite is **not** `-live`: it is a root-only CI suite following the loopback
  precedent). Do not edit the append-only PR1 counsel-review audit.

## Research Reconciliation — Spec vs. Codebase

| Claim | Reality | Plan response |
|---|---|---|
| "Confirm the cloud-init package set provides dmsetup" | not listed; arrives only as a Depends of `cryptsetup` | add `dmsetup` explicitly to `packages:` and assert `command -v` in the unit (reason=snapshot) |
| "whether later steps (LUKS format/copy/wipe) need the plaintext device rw" | bootstrap never writes it; copy mode is deferred to #8571; the wipe is terraform-side | keep `--setro` for the host lifetime (Cut List) |
| "the rung-2 rehearsal harness" has scenario cases | it has none: one fresh-volume boot, guards are static preconditions | add a seed phase + evidence-side P6 check instead of a case matrix |
| Research agent: "no pre-filter on reason words downstream" | runbook verdict-map row enumerates `<mount\|source\|journal\|umount>` | extend the row with the new words |

## Decision on #8710 (in scope or not)

**Separate PR, sequenced before the `plan_only` rehearsal dispatch (step 4), not folded in.**

- It touches disjoint files (`.github/actions/dispatch-web-redeploy/source-run-gate.sh` +
  `tests/scripts/test-dispatch-web-redeploy.sh`); folding it in widens the review surface of a
  hash-bound payload PR whose merge voids rung-2 evidence anyway.
- It is only needed before the `plan_only` dispatch, which is at least two merges away (this PR and
  the evidence PR), so a parallel PR costs no calendar time and can merge while the rung-2
  rehearsal runs.
- The rung-2 rehearsal (`git-data-rung2-rehearsal.yml`) does not dispatch the pin redeploy, so the
  rehearsal of this PR is not affected by #8710.
- **Hard precondition, not a hope:** the step-4 operator prompt must include
  `gh issue view 8710 --json state,closedByPullRequestsReferences` showing it closed by a merged PR.
  If #8710 is still open at step 4, the pipeline stops there. This plan files no new issue for it
  (it is already tracked).
- **Start it now, in parallel with this PR** (CPO, spec-flow): its cost is zero only if it is already
  under way when G1 finishes. It touches nothing `RUNG2_TEMPLATE_SHA256` binds, so merging it does not
  void evidence. Its PR must carry a test row proving a **real** (non-`plan_only`) replace still
  fires the pin redeploy, because G3's GO depends on that redeploy (architecture review).

## Operator-gated dispatches

This plan authorises **no** production `workflow_dispatch`, `terraform apply`, or Doppler write.
The pipeline stops before each row below and asks for an explicit per-command go-ahead
(`hr-menu-option-ack-not-prod-write-auth`: a menu option acknowledgement is not write authority).

| # | Dispatch | When | Why gated |
|---|---|---|---|
| G1 | `git-data-rung2-rehearsal.yml` (paid, prod Hetzner project, scratch Doppler config) | after this PR merges | spends a paid host in the production cloud account |
| G2 | `apply-web-platform-infra.yml` `apply_target=git-data-host-replace plan_only=true` | after the evidence PR merges AND #8710 is closed by a merged PR | #8710 showed it can fire a production redeploy |
| G3 | `apply-web-platform-infra.yml` `apply_target=git-data-host-replace` (real) | after G2 reads clean | destroys and recreates the host holding every user's source store |
| G4 | `git-data-cutover.yml` strict dry run | after G3's boot_complete | reads production; part of the GO read |

**Art. 12(3) deadline.** Every Delete Account whose git-data erasure was refused in this window must
be re-driven by **2026-10-24** (one month from the first refusal). If G3 has not reached GO well
before then, escalate to the CLO rather than rushing G3. A refused erasure does not block the
deletion itself (`account-delete.ts` records `gitDataErasurePending` and continues), and no user's
repository is on the host yet, so there is no pressure to shortcut a gate.

**G1 failure handling (cap: 2 paid runs per payload hash; a named FATAL always needs a code PR, never
a re-run):**

| G1 outcome | Operator action |
|---|---|
| seed off-poll timeout | read the `stage=seed_*` rows; fix the seed script in a PR |
| payload FATAL `reason=snapshot` / `mount` / `journal` / `source` | code PR; if it is the kernel mechanism itself, the Phase 0 decision point |
| capture #1 PASS, replace arm FAIL | read boot #2's fatal row; the adopt arm is the suspect; code PR |
| teardown did not complete | dispatch `git-data-rung2-rehearsal.yml` with `teardown_only=true` (also operator-gated) |
| TRANSIENT (source-liveness anchor silent) | one re-dispatch, counted against the cap |

**Between G1 and the evidence PR, hold every merge that touches `git-data-bootstrap.sh`,
`cloud-init-git-data.yml` or `modules/git-data-userdata/`** — each voids the evidence hash and costs
another paid G1. Before merging the evidence PR, compare its `RUNG2_TEMPLATE_SHA256` against a fresh
computation on `origin/main` (the gate does this at dispatch; do it before merge too).

**G2 "reads clean" means:** the plan replaces exactly `hcloud_server.git_data`,
`hcloud_server_network.git_data`, `hcloud_volume_attachment.git_data`,
`hcloud_volume_attachment.git_data_luks`, `tls_private_key.git_data_host_ssh`, updates
`hcloud_firewall_attachment.git_data` and `doppler_secret.git_data_ssh_host_key`, and touches neither
volume; and `gh run list --workflow=git-data-pin-redeploy.yml --created ">=<G2 start>"` shows no run
triggered by it.

**G3 is capped at one attempt.** A failed G3 leaves Doppler `GIT_DATA_SSH_HOST_KEY` pinned to a host
that serves nothing — as today; harmless, because nothing can use git-data until a boot writes the
marker, and the next replace re-pins it. Recovery is a read first (Sentry `stage:bootstrap`, the
boot-signal poll), never a second replace.

**GO for G3 means all three:** Better Stack shows `git_data_pin=present fp=<G3's fingerprint>` from
a pin redeploy caused by **that** replace run (not 35979135707, which the plan_only rehearsal
triggered, and not 35980551109); zero Sentry `erasure_outcome` events in the window; and the G4 dry
run reads `role=git-data-auth verdict=ok`. The replace boot must also emit `boot_complete` with
`plaintext_journal=dirty plaintext_empty=yes fence_on_mapper=yes erasure_probe=yes`. A production
`plaintext_journal=clean` is **NO-GO and an incident**: the production volume was measured dirty on
2026-09-24, so a clean journal means something replayed it — a write to the retained volume.

## Implementation Phases

### Phase 0 — Prove the mechanism on a real kernel first (first commit, before any other code)

The whole design rests on one kernel fact: a dm `snapshot` target can be stacked on an origin that
`blockdev --setro` has made read-only. Source reading supports it — in Linux v6.8
`drivers/md/dm-snap.c` `snapshot_ctr` opens the origin with `blk_mode_t origin_mode =
BLK_OPEN_READ`, upgraded to `BLK_OPEN_WRITE` only for `snapshot-merge` (fetched 2026-09-24 via
`gh api repos/torvalds/linux/contents/drivers/md/dm-snap.c?ref=v6.8`, lines 1245/1255/1276). Source is
not a measurement, so the **first commit of `soleur:work`** is the loopback suite's two controls
alone (Phase 1.2: the negative control plus arm B), pushed so `infra-validation.yml` runs them on
the runner kernel **before** the guard contract, the bootstrap change and the ADR text are written
against the assumption. The production-image kernel is proven only by G1 (payload boot #1).

**Decision point if the mechanism fails** (runner controls exit 2, or G1 FATALs `reason=snapshot`
on the image): stop, do not loop PR -> G1. Return to ADR-239's alternatives with the CTO and CLO.
The fallback candidate is the same snapshot **without** `--setro` (dm-snapshot still opens the origin
read-only; the loopback sha256 anchor still proves nothing was written) — it weakens the
"kernel-enforced" wording of the ADR amendment, not P2. Deadline for that decision: well before the
Art. 12(3) date in `## Operator-gated dispatches`.

### Phase 1 — Tests first (RED)

1.1 **Stub harness** `apps/web-platform/infra/git-data-bootstrap-store-verify.test.sh` (non-root):

- New stubs: `blockdev` (`--setro` records, `--getro` answers from a fixture file, `--getsz`),
  `dmsetup` (`create`/`status`/`remove`, each logged; failure and `Invalid` toggles), `losetup`,
  `cryptsetup` (`isLuks` false unless a `pt_is_luks` fixture exists), `udevadm`. The `mount` stub
  records the SOURCE argument and copies `ptsrc/` into the target for the snapshot mount. `dumpe2fs`
  answers per device: origin (`dumpe2fs_dirty` toggles needs_recovery) and snapshot
  (`snap_still_dirty` toggles it), and prints `Total journal blocks:` / `Block size:`. The COW
  directory needs no seam: `mktemp -d -p /dev/shm` works unprivileged. **No new environment seam is
  added** — every env var the bootstrap honours must also be stripped by cloud-init's `env -u` list
  under `doppler run` and enumerated in `git-data-store-device-census.test.sh` row C2 (architecture
  review); if implementation finds a seam unavoidable, both lists are edited in the same commit.
- Rewrite rows: S6 (`ro,noload` literal) -> the snapshot mount is
  `-o ro,errors=remount-ro,nosuid,nodev,noexec` with **no** `noload`, and its source is
  `/dev/mapper/git-data-pt-snap`; R1 accordingly. R4 changes meaning:
  - R4a dirty origin + empty tree -> PASS, marker written, `plaintext_journal=dirty`.
  - R4b dirty origin + `repositories/ws-1.git` -> `FATAL: plaintext_residue count=1`, no marker.
  - R4c snapshot still dirty after mount -> `reason=journal`, no marker, no residue verdict.
- New rows, each asserting the FATAL word, marker absent, and teardown complete:
  - `reason=source` when the plaintext device `isLuks` (and `--setro` was never called);
  - `reason=snapshot` when `--setro` fails, when `--getro` reads back 0, when the journal geometry
    cannot be parsed, when `losetup` fails, when `dmsetup create` fails (this covers a name already
    taken — the teardown must not remove a device this run did not create), and when `dmsetup
    status` reads `Invalid`;
  - `reason=umount` when the snapshot unmount, `dmsetup remove`, or `losetup -d` fails.
- **Order row (REORDER, P2):** in `calls.log`, `cryptsetup isLuks` precedes `blockdev|--setro`, which
  precedes the first `dmsetup|create` and the first `mount`.
- **Teardown row (P5):** on every FATAL arm after acquisition, `calls.log` shows `umount` (if
  mounted) -> `dmsetup remove` -> `losetup -d`, in that order, even when an earlier step failed; and
  never `blockdev --setrw`.
- Encode the Guard 1 mutation self-tests in the existing M-row style (landed-check + instrument
  self-test). Re-derive `MIN_ASSERTIONS` from the new measured call-site count; do not guess it.

1.2 **Root loopback suite** — new
`apps/web-platform/infra/git-data-plaintext-snapshot-loopback.test.sh`, following
`inngest-redis-luks-loopback.test.sh`: an instrument self-test, a non-zero exit with
`LOOPBACK_UNAVAILABLE`, every setup step rc-checked, a refusal if the SUT's fixed dm name already
exists, and no piping into a predicate. It extracts the plaintext sub-block of the store-verify unit
(new inner sentinels `# ---- BEGIN plaintext-count unit ----` / `# ---- END plaintext-count unit ----`,
nested inside the store-verify sentinels and spanning the real `_repo_count` definition through the
end of the `_pt_id` block, so arm C tests the real counter, not a copy) and runs it as root against
real loop devices through the `GIT_DATA_PLAINTEXT_DEV` seam. `log()` comes from a prelude copied out
of the script, as the stub harness already does. **Each arm runs the unit in a child `bash`** (the
unit `exit`s and sets `trap … EXIT`); the parent performs the leak and hash checks.

- **Negative control (backs the ADR claim):** after `blockdev --setro` on a dirty origin loop, a
  direct `mount -o ro` of the origin is refused by ext4 (`write access unavailable`). If the control
  does not hold, the suite exits 2 (instrument), not 1.
- **Arm A, clean:** fresh ext4 image, empty `repositories/` -> count 0, `plaintext_journal=clean`.
- **Arm B, dirty and empty (also the positive control):** mount the image rw, write a file outside
  `repositories/`, `mkdir`+`rmdir` inside it, then issue `EXT4_IOC_SHUTDOWN` with
  `EXT4_GOING_FLAGS_LOGFLUSH` (python3 `fcntl.ioctl(fd, 0x8004587D, struct.pack('I', 1))`; verify the
  ioctl number against the runner's `linux/ext4.h`/`xfs_fs.h` before relying on it, else fall back to
  `xfs_io -x -c 'shutdown -f'`), then umount. Expect PASS, count 0, `plaintext_journal=dirty`. Its
  first assertions: the snapshot superblock is clear of needs_recovery while the origin still has it.
- **Arm C, dirty with residue (the discriminating arm, P3):** as B, but `repositories/ws-1.git` is
  created immediately before the shutdown. **Assert the precondition, don't assume it:**
  `debugfs -c -R 'ls /repositories'` on the image (catastrophic mode ignores the journal) does NOT
  list `ws-1.git`. The unit must still report `plaintext_residue count=1`. If the precondition fails,
  the arm aborts as an instrument failure (exit 2), never green.
- **Arm D, COW overflow:** arm C with the COW-size constant rebound tiny **in the extracted copy**
  (the loopback precedent's rebinding, with a landed-check that the substitution happened — not an
  env seam). Expect a named FATAL (pin the word the kernel actually produces, `snapshot` or
  `mount`) and no marker.
- **Every arm asserts:**
  - the origin image `sha256sum` is byte-identical before and after (P2);
  - `blockdev --getro` on the origin loop reads `1` after the unit;
  - no `git-data-pt-snap` device remains, `losetup -a` holds no COW loop, and nothing remains under
    the COW parent (P5);
  - for B and C, dumpe2fs on the origin still shows needs_recovery.
- The arms run back-to-back in one process, so a leak from one arm reds the next (the second-member
  row).
- Register it as `sudo bash apps/web-platform/infra/git-data-plaintext-snapshot-loopback.test.sh`
  inside a multi-line `run: |` block in `.github/workflows/infra-validation.yml`, next to the inngest
  loopback step, and add its exemption entry to `.github/scripts/test/test-infra-suite-registration.sh`
  (same wording as the two loopback entries, #7076).
- Run `scripts/lint-orphan-test-suites.sh` and the suite census (`scripts/lib/test-affected-paths.sh`)
  and add whatever entry they demand. The suite is not `-live` and needs no `ALWAYS_ON_SUITES` entry.

1.3 **Plan-shape script test** — new `tests/scripts/test-git-data-rung2-plan-shape.sh` for
`scripts/git-data-rung2-plan-shape.sh` (Guard 3).

1.4 **Evidence capture test** — extend `tests/scripts/test-git-data-rung2-evidence-capture.sh`
(Guard 2 rows).

1.5 **Field sweep tests** — add `plaintext_journal` to the informational/non-terminal enumerations
in:

- `apps/web-platform/infra/git-data-emit.test.sh` (`_asserted_keys`, `NON_TERMINAL`);
- `tests/scripts/test-git-data-boot-signal-poll.sh` (`G2_INFORMATIONAL`, plus a row proving the
  poll does not gate on it);
- the store-verify trailer.

Run each suite and confirm it is RED for the right reason before Phase 2.

### Phase 2 — Bootstrap change (GREEN)

Replace the `_pt_id` block of the store-verify unit with (shape, not final code):

```bash
_pt_id="${GIT_DATA_PLAINTEXT_VOLUME_ID:-}"
_plaintext_journal=absent
if [ -n "$_pt_id" ]; then
  _plaintext_volume=present
  [[ "$_pt_id" =~ ^[0-9]+$ ]] || { log "FATAL: plaintext_unverified reason=source — …"; exit 1; }
  _pt_dev="${GIT_DATA_PLAINTEXT_DEV:-/dev/disk/by-id/scsi-0HC_Volume_$_pt_id}"
  _pt_snap=git-data-pt-snap                        # fixed; never "git-data" (the LUKS mapper)
  ! cryptsetup isLuks "$_pt_dev" 2>/dev/null || { log "FATAL: plaintext_unverified reason=source — $_pt_dev is a LUKS device"; exit 1; }
  # (P2) READ-ONLY FIRST, before anything opens the device; read back; never restored.
  blockdev --setro "$_pt_dev" && [ "$(blockdev --getro "$_pt_dev" 2>/dev/null)" = 1 ] \
    || { log "FATAL: plaintext_unverified reason=snapshot — $_pt_dev could not be made read-only"; exit 1; }
  _pt_sb="$(dumpe2fs -h "$_pt_dev" 2>/dev/null)" || { log "FATAL: plaintext_unverified reason=journal — …"; exit 1; }
  # origin journal state -> _plaintext_journal=dirty|clean (informational; a dirty journal is no longer FATAL)
  # COW bytes = Total journal blocks * Block size + 64 MiB; unparseable -> reason=snapshot
  _pt_dir="$(mktemp -d -p /dev/shm)"               # 0700, RAM-only; the COW file size bounds writes
  _pt_mnt="$_pt_dir/mnt"; mkdir "$_pt_mnt"
  trap _pt_release EXIT                            # state flags: _pt_loop _pt_snap_up _pt_mounted
  truncate -s "$_pt_cow_bytes" "$_pt_dir/cow" && _pt_loop="$(losetup --find --show "$_pt_dir/cow")" || …reason=snapshot
  _pt_sz="$(blockdev --getsz "$_pt_dev")" && [[ "$_pt_sz" =~ ^[1-9][0-9]*$ ]] || …reason=snapshot
  dmsetup create "$_pt_snap" --table "0 $_pt_sz snapshot $_pt_dev $_pt_loop N 8" || …reason=snapshot
  _pt_snap_up=1                                    # set ONLY after a successful create
  mount -o ro,errors=remount-ro,nosuid,nodev,noexec "/dev/mapper/$_pt_snap" "$_pt_mnt" || …reason=mount   # NO noload: replay into COW
  # SOURCE equality against /dev/mapper/$_pt_snap (realpath both sides) -> reason=source
  # post-replay: dumpe2fs -h /dev/mapper/$_pt_snap must NOT show needs_recovery -> reason=journal
  _pt_n="$(_repo_count "$_pt_mnt")" || …reason=mount   # the unit runs under pipefail (asserted)
  # dmsetup status "$_pt_snap" must not read Invalid -> reason=snapshot
  _pt_release; trap - EXIT
  [ "$_pt_n" -eq 0 ] || { log "FATAL: plaintext_residue count=$_pt_n — the plaintext volume still holds repositories/ entries"; exit 1; }
fi
_plaintext_empty=yes
```

- `_pt_release` tears down in reverse acquisition order, each step guarded by its state flag and
  idempotent. The order is:
  1. `umount "$_pt_mnt"`;
  2. `udevadm settle`;
  3. `dmsetup remove --retry "$_pt_snap"`, with a bounded retry, because udev's blkid probe can hold
     the new device briefly;
  4. `losetup -d "$_pt_loop"`;
  5. `rm -rf` of the `/dev/shm` directory.

  The first three failures are `reason=umount`. It starts with `trap - EXIT` (the success path calls
  it while the trap is armed, and a teardown `exit 1` would otherwise run it twice), clears each
  state flag only after that step succeeds, and writes `udevadm settle || true` (`set -e` applies
  inside a trap handler). **It attempts every step, records the first failure, and exits once at
  the end.** It never `exit`s mid-trap: the current `_pt_release` does,
  and under `set -e` that would skip the later steps and leak the dm and loop devices (CTO R4). It
  never calls `blockdev --setrw`. A teardown FATAL leaves no marker, because the marker writer comes
  later in the unit.
- Reason vocabulary after this change: `source | snapshot | mount | journal | umount`. `snapshot`
  is the one new word; the text after the em-dash names the failed step. `plaintext_residue
  count=<n>` is byte-unchanged.
- **Cut from the first draft (plan review):**
  - the MemAvailable refusal (the COW file's size bounds its RAM, and overflow is the named `Invalid` FATAL);
  - the `command -v` tool loop and `modprobe` (a missing tool or module fails the call that needs it: dm core `request_module`s the target);
  - the name-exists probe and the origin maj:min check (`dmsetup create` refuses a taken name, and dmsetup resolves the path it was given);
  - the snapshot-name seam;
  - a dedicated tmpfs mount (`/dev/shm` is already RAM);
  - the `readonly`/`teardown` reason words.
- `errors=remount-ro` on the snapshot mount overrides whatever `Errors behavior:` the superblock
  carries, so a COW overflow mid-replay becomes a named FATAL instead of a boot-time panic (CTO R7;
  record the production volume's actual `Errors behavior:` from G1's dumpe2fs, don't assume it).
- Emit `plaintext_journal=${_plaintext_journal}` (`dirty|clean|absent`) as an informational field
  in the `boot_complete` call at §8.
- Update the §7b comment block and the header of the store-verify test (PROPERTY paragraph) to
  describe the snapshot read. Comments are render-stripped (ADR-152); re-measure the stored bytes
  with `git-data-userdata-budget.sh`.
- `apps/web-platform/infra/cloud-init-git-data.yml` `packages:` gains `dmsetup`. It is listed
  explicitly rather than relying on `cryptsetup`'s Depends.

### Phase 3 — Rung-2 rehearsal reproduces a dirty journal, then the adopted-LUKS replace

- `apps/web-platform/infra/rung2-rehearsal/variables.tf`: `variable "rehearsal_phase"` (string,
  validation `seed|payload`, **no default**, so a run cannot silently skip the seed).
- New `apps/web-platform/infra/rung2-rehearsal/seed-dirty-journal.sh`. It is rehearsal-only and
  never in the production module. It is rendered with `templatefile` from the plaintext volume id,
  the Better Stack ingest URL and token (already rendered into the payload's user_data), and a
  distinct host label `<rehearsal-host>-seed`. It does, in order:
  1. waits for the by-id device (bounded);
  2. `mount -o rw` it at `/mnt/seed`, with no `noload`, to reproduce the predecessor's state;
  3. writes a marker file **outside** `repositories/`, runs `mkdir -p repositories`, then
     `mkdir`/`rmdir` one probe entry inside it;
  4. runs `sync -f`;
  5. only then runs `echo o > /proc/sysrq-trigger` (immediate power-off, no unmount).

  It asserts nothing about `needs_recovery`: that flag is always set while an ext4 is mounted rw, so a
  seed-side check proves nothing. The proof is boot #1 reporting `plaintext_journal=dirty`. Because
  `templatefile` treats `${…}` and `%{` as its own syntax, every shell expansion in the seed is
  written `$${…}` (or the file is rendered with `replace(file(…), "@@VOLUME_ID@@", …)`); a
  rehearsal-test row renders it and runs `bash -n` on the result.

  It emits one fail-soft Better Stack line per step (`stage=seed_<step>`), so a seed that stalls is
  diagnosable without SSH. Any failed step leaves the host running, so the workflow's bounded poll
  times out and the run FAILs. It never touches the LUKS volume.
- `rehearsal.tf`: `hcloud_server.rehearsal.user_data = var.rehearsal_phase == "seed" ?
  base64gzip(templatefile("${path.module}/seed-dirty-journal.sh", {…})) :
  base64gzip(module.git_data_userdata.rendered)`. Attachments are unchanged.
  - The payload phase therefore replaces `hcloud_server.rehearsal` (user_data is ForceNew) and both
    `hcloud_volume_attachment`s (server_id is ForceNew), and updates
    `hcloud_firewall_attachment.rehearsal`. That is Terraform's ordinary replace: it detaches the
    volumes from the powered-off seed, which is the production sequence (the advisor confirmed
    `rehearsal.tf` carries no `ignore_changes` on user_data).
  - `git-data-rung2-rehearsal.test.sh` has no rows pinning the `user_data` expression today. Add
    rows pinning three things:
    - the payload arm is the unmodified module render;
    - the seed file references only the plaintext volume id, never the LUKS volume;
    - the seed does `sysrq o` and never `umount`.
- New `scripts/git-data-rung2-plan-shape.sh <plan.json> <additive|host-only>` replaces the inline
  "creates ONLY rehearsal addresses and destroys nothing" jq in the workflow, with the same
  deny-list-the-inert-verbs semantics.
  - `additive` (seed phase) is today's rule.
  - `host-only` (payload phase and replace arm) admits only these non-create/read/no-op changes:
    - `replace` (delete+create, in either order) of exactly `hcloud_server.rehearsal`,
      `hcloud_volume_attachment.rehearsal` and `hcloud_volume_attachment.rehearsal_luks`;
    - `update` of `hcloud_firewall_attachment.rehearsal`;
    - `replace` of `tls_private_key.rehearsal_host_ssh` (replace arm only) and whatever its
      dependents change (`hcloud_server.rehearsal` user_data is already admitted).

    It also requires that those replaces are present. Any change to either volume reds, and so does
    any change to any other address. A fresh plaintext volume would make the seed vacuous; a fresh
    LUKS volume would skip the adopt arm.
- `.github/workflows/git-data-rung2-rehearsal.yml`, in order:
  1. plan (`-var rehearsal_phase=seed`) -> shape `additive` -> apply;
  2. **poll the Hetzner API** `GET /v1/servers/<id>` until `.server.status == "off"` (bounded, ~10
     min; on timeout, FAIL with an annotation pointing at the `stage=seed_*` rows);
  3. plan (`-var rehearsal_phase=payload`) -> shape `host-only` -> apply;
  4. capture #1 (existing; the window starts at the step-3 apply);
  5. the existing settle / reset / reopen probe;
  6. **replace arm (P8), only if capture #1 and the reopen probe passed:**
     `terraform plan -replace=hcloud_server.rehearsal -replace=tls_private_key.rehearsal_host_ssh
     -var rehearsal_phase=payload` (mirroring production's `-replace` pair of
     `hcloud_server.git_data` + `tls_private_key.git_data_host_ssh`) -> shape `host-only` -> apply
     -> capture #2. Capture #2's window (and its `RUNG2_SENTRY_SINCE`) is a timestamp **stamped
     immediately before the replace apply**, and the capture refuses if that stamp is missing
     (AP-027: the host name is reused across seed, boot #1, reboot and boot #2). A stray boot-#1 row
     inside the window can only turn a PASS into a FAIL, never the reverse. Stated gap: the rehearsal
     root has no private network and no Doppler host-key secret, so those two production replace
     targets are not rehearsed;
  7. upload the evidence artifact, **moved after capture #2**. Its `if:` adds
     `replace_rc == '0'` to the existing `capture_rc`/`reboot_rc` conditions, the same enforcement
     the reboot arm already uses (#8210). No releasing evidence can exist without the adopted-LUKS
     boot passing, and `git-data-birth-readiness-gate.sh` needs no change, because it reads neither
     reboot nor replace keys;
  8. teardown. Destroy steps pass `-var rehearsal_phase=payload`.
  - **Step ids and windows (Kieran):** the three applies get distinct ids (`apply_seed`, `apply`,
    `apply_replace`). Capture #1, reset and the reopen probe keep reading `steps.apply.outputs.host`,
    and capture #2 reads `steps.apply_replace.outputs.host`. The replace arm writes a **separate**
    `RUNG2_REPLACE_SINCE` and passes it through a new capture flag. It must not rewrite
    `RUNG2_SENTRY_SINCE` (in `GITHUB_ENV` the last write wins, which would narrow boot #1's Sentry
    cross-check) and must not reuse `--reboot-since`, which switches the capture's mode.
  - **How P8 is enforced:** the birth-readiness gate reads neither `RUNG2_REBOOT_REOPEN` nor
    `RUNG2_REPLACE_BOOT`; it requires only `RUNG2_BOOT_REHEARSAL`, `EVIDENCE_URL`,
    `TEMPLATE_SHA256`, `VAR_DIVERGENCE` and `SENTRY_CROSSCHECK`. Enforcement comes from three places:
    - the upload `if:` (step 7);
    - the gate's refusal of a run that did not succeed (`RUN_NOT_SUCCESS`);
    - the gate's refusal of a run with no evidence artifact (`RUN_NO_EVIDENCE_ARTIFACT`).

    A replace-arm FAIL therefore leaves no releasable evidence. That is the same mechanism the reboot
    arm relies on. The runbook says so plainly.
  - **Time budget:** the job is `timeout-minutes: 60` today with ~55 min worst case. The new
    sequence adds a seed apply, the off-poll, a second apply, a replace apply and a second capture.
    Compute the worst case from each step's own bound and write it into the workflow header. Extend
    the rehearsal test's budget check, which today reads only the first step-level
    `timeout-minutes` and the first reset loop, so that it sums every step-level timeout and
    deadline. Then
    move teardown and the "no rehearsal host survives" assertion into a separate job with
    `needs: rehearse` and `if: always()`, so a timed-out rehearsal still tears down its paid hosts.
    The existing `teardown_only` recovery input stays as the manual fallback.
  - Boot #1 takes the fresh-format arm of the LUKS stage and is then hard-reset mid-mount by the
    reboot arm. Boot #2 therefore adopts a LUKS volume that a predecessor formatted and abandoned
    mounted, against a plaintext volume that boot #1 read. If P2 holds, boot #1 did not clean that
    volume, so boot #2 must again report `plaintext_journal=dirty`: that is the real-image proof of
    P2. The dry-run arm plans the seed phase only.
  - Rationale goes to `knowledge-base/engineering/operations/runbooks/git-data-rung2-rehearsal.md`,
    not the workflow (ADR-231). Re-measure the workflow's bytes.
- `scripts/followthroughs/git-data-rung2-evidence-capture.sh`:
  - the HOSTROWS SQL selects `plaintext_volume` and `plaintext_journal`;
  - PASS additionally requires `plaintext_volume=present` AND `plaintext_journal=dirty`, both by
    exact string match. The rehearsal root always renders the volume id, so `absent` means a broken
    render, not a pass. The future wipe PR's rehearsal (volume id empty) amends this rule in its own
    PR, as ADR-239 already requires;
  - a second invocation (the replace arm) appends `RUNG2_REPLACE_BOOT=PASS|FAIL`, as the reboot arm
    appends `RUNG2_REBOOT_REOPEN`. No `RUNG2_PLAINTEXT_JOURNAL` key: PASS already means `dirty`.
- `scripts/followthroughs/git-data-birth-emitter-6982.sh`: add `plaintext_journal` to its
  informational list.

### Phase 4 — ADR-239 amendment, runbooks, C4 check

- `ADR-239`: add `## Amendment 2026-09-24 — the dirty-journal gap is closed (#5274, #5914)`:
  Decision 2 now reads the plaintext volume through a non-persistent dm snapshot: the by-id device is
  set read-only by the kernel before anything opens it and stays read-only for the host's
  lifetime; ext4 replays the journal into a COW file on `/dev/shm` (RAM); the counted tree is the
  post-replay tree. **D2 "never writable" still holds and is now enforced by the kernel's ro flag, not only by
  mount options** — with the origin kernel-ro, even a mistaken direct `ro` mount of it cannot replay
  the journal (ext4 refuses: write access unavailable). Record that the COW is in RAM on purpose: it
  holds replayed plaintext metadata (repository and file names) and must leave nothing on disk.
  Strike-through (not delete) the "dirty-journal `noload` gap is real and
  accepted" consequence with a pointer to the amendment; record the 2026-09-24 FATAL as the
  motivating event. Add Alternatives rows: (I) mount rw and let the journal replay on the volume
  — writes the retained volume, violates D2; (J) `debugfs -c`/`noload` count — reads the stale
  tree, can miss journal-only entries (the reason the FATAL existed); (K) `e2fsck` on a full copy —
  a volume-sized copy on a 4 GB host; (L) attach to a throwaway host and fsck there — writes the
  volume and adds an operator path; (M) snapshot only when dirty — a second path the rehearsal
  would not boot. Status stays `adopting`.
- `git-data-luks-cutover-5274.md`: verdict-map row reason set becomes
  `<mount|source|journal|umount|snapshot>`; replace "`reason=journal` is the known dirty-journal gap
  the rehearsal cannot reproduce" with the new meaning (`journal` = the journal did not replay
  cleanly into the snapshot; `snapshot` = the read-only flag or the snapshot apparatus failed;
  `umount` = a transient device could not be torn down; all are read-only, nothing written, no
  marker). Add a dated note under "If the
  fresh host fails a boot check after step 3" recording the 2026-09-24 event and the forward fix,
  and the G1-G4 sequence with the GO definition and the #8710 precondition.
- `git-data-rung2-rehearsal.md`: document the seed -> payload -> replace run, the off-poll, the
  `stage=seed_*` rows, the `host-only` admission set, the time budget and the teardown job,
  `RUNG2_REPLACE_BOOT`, the G1 failure table and the 2-run cap. Note that every future rehearsal now
  pays for two extra boots (seed + replace), re-evaluated when #8571's wipe empties the volume id.
- `ADR-149` (birth route and rung-2 gate): one dated pointer line to the ADR-239 amendment and the
  new rehearsal shape.
- C4: edit the `gitDataStore` description in `model.c4` (see `## Architecture Decision (ADR/C4)`).

### Phase 5 — Verify, budgets, ship

- Run: the store-verify suite, `git-data-rung2-rehearsal.test.sh`, `git-data-emit.test.sh`,
  `test-git-data-boot-signal-poll.sh`, `test-git-data-rung2-evidence-capture.sh`,
  `test-git-data-rung2-plan-shape.sh`, `test-infra-suite-registration.sh`,
  `git-data-render-strip-parity.test.sh`, `git-data-userdata-budget.sh`,
  `plugins/soleur/test/c4-count-parity.test.sh`, `scripts/guard-vacuity-floor.test.sh`,
  `scripts/lint-guard-contract.py` over this plan, and `scripts/test-all.sh` (affected). The
  loopback suite runs only in CI (no local passwordless sudo) — its first CI run is its RED/GREEN
  evidence; record that in session-state.
- Re-derive floors (`MIN_ASSERTIONS`), vacuity baselines and byte budgets after every merge from
  `main`.
- Ship stops at the merge gate; then the pipeline stops at G1.

## Files to Edit

- `apps/web-platform/infra/git-data-bootstrap.sh`
- `apps/web-platform/infra/git-data-bootstrap-store-verify.test.sh`
- `apps/web-platform/infra/cloud-init-git-data.yml`
- `apps/web-platform/infra/git-data-emit.test.sh`
- `apps/web-platform/infra/rung2-rehearsal/rehearsal.tf`
- `apps/web-platform/infra/rung2-rehearsal/variables.tf`
- `apps/web-platform/infra/git-data-rung2-rehearsal.test.sh`
- `.github/workflows/git-data-rung2-rehearsal.yml`
- `.github/workflows/infra-validation.yml`
- `.github/scripts/test/test-infra-suite-registration.sh`
- `scripts/followthroughs/git-data-rung2-evidence-capture.sh`
- `scripts/followthroughs/git-data-birth-emitter-6982.sh`
- `tests/scripts/test-git-data-rung2-evidence-capture.sh`
- `tests/scripts/test-git-data-boot-signal-poll.sh`
- `apps/web-platform/infra/git-data-store-device-census.test.sh` — only if a new env seam proves unavoidable (then also the `env -u` list in `cloud-init-git-data.yml`); none is planned
- `plugins/soleur/test/preflight-discoverability-test.test.ts` — bump `BASELINE_DECLARED_PROBES` (24 today) with its PLACEMENT/TRUTH/NO-SUBSTITUTE entry, because this plan's `discoverability_test` declares `credentials_required`
- `knowledge-base/engineering/architecture/diagrams/model.c4` — `gitDataStore` description
- `knowledge-base/engineering/architecture/decisions/ADR-149-git-data-host-birth-route-and-readiness-interlock.md` — one dated pointer line
- `scripts/lib/test-affected-paths.sh`, `scripts/suite-shard-legs.tsv`, `scripts/guard-vacuity-floor.test.sh` (only if the suite census / vacuity floor requires an entry — union on conflict)
- `knowledge-base/engineering/architecture/decisions/ADR-239-git-data-serves-from-luks-at-birth.md`
- `knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md`
- `knowledge-base/engineering/operations/runbooks/git-data-rung2-rehearsal.md`
- `scripts/encryption-posture-ledger.json` (only if `lint-encryption-posture.py` requires a row for the transient COW)

## Files to Create

- `apps/web-platform/infra/git-data-plaintext-snapshot-loopback.test.sh`
- `apps/web-platform/infra/rung2-rehearsal/seed-dirty-journal.sh`
- `scripts/git-data-rung2-plan-shape.sh`
- `tests/scripts/test-git-data-rung2-plan-shape.sh`

Out of this PR: `apps/web-platform/infra/git-data-rung2-boot-evidence.env` (regenerated only by the
evidence-only PR after G1), and #8710's files (separate PR).

## Open Code-Review Overlap

2 open scope-outs touch these files (76 open `code-review` issues scanned):

- #7098 (audit `run:` bodies whose `set` omits `-e`; names `git-data-rung2-rehearsal.test.sh`) —
  **Acknowledge.** A repo-wide lint-shaping audit, not this fix. The new workflow steps this plan adds
  use `set -euo pipefail` explicitly, so they add nothing to #7098's population.
- #7942 (two `*.mutation.sh` batteries run in no gate; names `infra-validation.yml`) —
  **Acknowledge.** Different suites (`plugins/soleur/test/`); this plan only adds one `sudo bash`
  step, which runs in a gate.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing visible today — the user's account deletion
completes (`account-delete.ts` treats a refused git-data erasure as non-blocking and records
`gitDataErasurePending`), only a record of the git-data step is left to re-run, and no user's
repository is on that host yet. It becomes user-visible when the store is enabled: repository
provisioning stays blocked. The worst case is a wrong count that lets a host serve while the retained
plaintext volume still holds a repository, or a write that damages the only plaintext copy.

**If this leaks, the user's data is exposed via:** the replayed plaintext metadata (directory
entries, which name workspaces) sitting in a tmpfs COW on the git-data host during the count; a
leaked or lingering `/dev/mapper/git-data-pt-snap` exposing the plaintext volume read-only to root;
or a write to the retained volume destroying the only plaintext copy.

**Brand-survival threshold:** single-user incident

- CPO sign-off required at plan time before `soleur:work` (carried from the #8211 plan's threshold).
- `soleur:engineering:review:user-impact-reviewer` runs at review time.
- Mitigations: the store has never held a repository (`GIT_DATA_STORE_ENABLED` never true); the
  kernel ro flag makes P2 hold even if a later line misbehaves; the COW is RAM-only and destroyed at
  teardown; every failure is fail-closed with no marker.

## Acceptance Criteria

### Pre-merge (this PR)

- [ ] AC1 `git-data-bootstrap-store-verify.test.sh` passes with the new rows; each Guard 1 mutation
      self-test reports the mutant landed and the verdict flipped; `MIN_ASSERTIONS` re-derived.
- [ ] AC0 (Phase 0) The first pushed commit's `infra-validation.yml` run shows the loopback negative
      control and arm B green on the runner kernel, before the bootstrap change is committed.
- [ ] AC2 In the comment-stripped unit body, `blockdev --setro` precedes the first `dmsetup create`
      and the first `mount` by line, and the stub run's `calls.log` shows the same order.
- [ ] AC3 In the comment-stripped unit body (`UNIT_BODY`, since the rewritten comments will mention
      noload) no `noload` token remains; the only mount's options are exactly
      `ro,errors=remount-ro,nosuid,nodev,noexec` and its source is `/dev/mapper/$_pt_snap`; no
      `blockdev --setrw` appears anywhere in the bootstrap.
- [ ] AC4 The loopback suite runs in `infra-validation.yml` as `sudo bash …` and passes all arms on
      the CI runner; arm C's precondition (`debugfs -c` does not list `ws-1.git`) held and the unit
      still reported `plaintext_residue count=1`; the origin sha256 is unchanged in every arm; no dm
      device, COW loop or `/dev/shm` directory survives any arm.
- [ ] AC5 Every FATAL in the unit matches `plaintext_unverified reason=(source|snapshot|mount|journal|umount)`
      or is the unchanged `plaintext_residue count=$_pt_n` line (grep the unit; count equals the
      stub harness's enumerated FATAL rows).
- [ ] AC6 `boot_complete` carries `plaintext_journal`; every enumeration listed in Phase 1.5 names it
      as informational; the boot-signal poll test proves it never gates.
- [ ] AC7 `cloud-init-git-data.yml` lists `dmsetup`; `git-data-userdata-budget.sh` passes and the new
      stored-byte figure is recorded in the PR body.
- [ ] AC8 `test-git-data-rung2-plan-shape.sh` passes, including the rows that red on any change to
      either volume in `host-only` mode; the workflow calls the script at all three plan steps and
      no inline shape jq remains.
- [ ] AC9 `test-git-data-rung2-evidence-capture.sh` shows PASS refused for `plaintext_volume=absent`
      and for `present` with `plaintext_journal` in {`clean`, empty, `Dirty`}, and allowed only for
      `present`+`dirty`; the replace-arm invocation appends `RUNG2_REPLACE_BOOT` and reads its own
      `RUNG2_REPLACE_SINCE` without altering `RUNG2_SENTRY_SINCE`.
- [ ] AC9b The workflow's evidence upload sits after capture #2 and its `if:` requires
      `replace_rc == '0'`; teardown runs in a separate `if: always()` job; the workflow header states
      the recomputed worst-case budget and the rehearsal test's budget check sums every step bound.
- [ ] AC10 `git-data-rung2-rehearsal.test.sh` passes with rows pinning the phase variable (no
      default), the payload arm as the unmodified module render, and the seed's `sysrq o` / no
      `umount` / plaintext-only shape.
- [ ] AC11 ADR-239 carries the dated amendment and the new alternatives rows; ADR-149 carries its
      pointer; the runbook verdict row lists `<mount|source|journal|umount|snapshot>`;
      `git-data-rung2-rehearsal.md` documents the seed -> payload -> replace run, the G1 failure
      table and the 2-run cap.
- [ ] AC12 `model.c4`'s `gitDataStore` description no longer says the plaintext volume is "mounted
      read-only" or that the live host "still serves PLAINTEXT"; `c4-count-parity.test.sh`,
      `c4-code-syntax.test.ts`, `c4-render.test.ts`, `lint-guard-contract.py` (this plan),
      `guard-vacuity-floor.test.sh` and `preflight-discoverability-test.test.ts` pass.
- [ ] AC13 Merge only when every context in
      `scripts/ci-required-ruleset-canonical-required-status-checks.json` is present and `success`
      by name on the exact head SHA (counted, the count stated in the merge note).

### Post-merge (operator-gated; the pipeline stops before each)

- [ ] AC14 (G1) With the operator's go-ahead, the rung-2 rehearsal PASSes with the seed phase
      reaching `off`, payload boot #1 reading `plaintext_volume=present plaintext_journal=dirty
      plaintext_empty=yes fence_on_mapper=yes erasure_probe=yes`, no fatal, the reboot reopen arm
      PASS, and replace boot #2 (adopted LUKS) reading the same values with
      `plaintext_journal=dirty` again (P2 on the real image); its evidence file lands through an
      evidence-only PR.
- [ ] AC15 (G2) Before the `plan_only` dispatch, #8710 is closed by a merged PR (read, not assumed);
      with the operator's go-ahead the `plan_only` run reads clean and fires no pin redeploy.
- [ ] AC16 (G3/G4) With the operator's go-ahead per dispatch: GO as defined in
      `## Operator-gated dispatches` (fingerprint from a redeploy caused by that replace, zero
      Sentry `erasure_outcome`, strict dry run `role=git-data-auth verdict=ok`), and the replace boot
      reads `plaintext_journal=dirty plaintext_empty=yes`. ADR-239 flips to `accepted` only on that
      production boot (its own status rule). Then the refused Art. 17 erasures are swept from Sentry
      over the window **from the start of run 35979304442** (not the 09:09:30Z FATAL: refusals
      began when the predecessor was destroyed) **to the G3 marker**, querying
      `op:git-data-bare-repo-erasure` (pre-FATAL refusals may have surfaced through the
      `removeGitDataRepo threw` path, not `erasure_outcome`), and re-driven per the runbook by
      2026-10-24; the sweep result (count, ids re-driven) is recorded on #5914.

## Test Scenarios

| # | Given | When | Then |
|---|---|---|---|
| T1 | clean origin, empty tree | unit runs | PASS, `plaintext_journal=clean`, marker written |
| T2 | dirty origin, empty post-replay tree | unit runs | PASS, `plaintext_journal=dirty`, origin unchanged |
| T3 | dirty origin, entry only in the journal | unit runs | `plaintext_residue count=1`, no marker |
| T4 | plaintext device is LUKS | unit runs | `reason=source`, setro never called |
| T5 | `--setro` fails / `--getro` reads 0 | unit runs | `reason=snapshot`, no dm device created |
| T6 | snapshot name already exists | unit runs | `reason=snapshot` (create refused), existing device untouched |
| T7 | COW overflow | unit runs | `reason=snapshot` or `reason=mount` (pinned), no marker |
| T8 | snapshot still needs_recovery after mount | unit runs | `reason=journal` |
| T9 | `dmsetup remove` fails | teardown | `reason=umount`, `losetup -d` still attempted, no marker |
| T10 | payload plan changes `hcloud_volume.rehearsal` | plan-shape `host-only` | refused |
| T11 | seed never powers off | workflow poll | FAIL, bounded, names the seed |
| T12 | payload emits `plaintext_journal=clean` with volume present, or `plaintext_volume=absent` | capture | not PASS |
| T13 | replace boot #2 reports `plaintext_journal=clean` | capture #2 | `RUNG2_REPLACE_BOOT=FAIL` (boot #1 wrote to the volume) |
| T14 | replace phase plan recreates the LUKS volume | plan-shape `host-only` | refused |
| T15 | the rehearsal job hits its timeout | teardown job | runs anyway (`if: always()`), no host survives |

## Domain Review

**Domains relevant:** Engineering, Legal (assessed inline), Product (NONE)

### Engineering

**Status:** reviewed (soleur:engineering:cto)
**Assessment:** Sound, go. Risks folded into this plan: R1 dm snapshot over a kernel-ro origin is
unproven until the loopback positive/negative controls run (Phase 1.2); R2 runner kernel is not the
Hetzner kernel, so rung-2 remains the production-kernel proof; R3 udev can hold the new device ->
`udevadm settle` + bounded `dmsetup remove --retry`; R4 the existing trap `exit`s mid-teardown ->
collect-then-exit teardown; R5 duplicate by-uuid symlink is cosmetic; R6 RAM -> bounded by the
COW file's own size (the MemAvailable refusal was cut at plan review); R7 superblock `errors=panic` -> explicit `errors=remount-ro`; R8 consumer sweep of the new
field and reason words. Seed-as-replace endorsed over a separate or API-created seed. #8710 as a
separate PR, blocking only G2. Missing items added: kernel-ro note in the ADR amendment, explicit
`dmsetup` package, and the adopted-LUKS arm (P8, replace arm).

### Legal

**Status:** reviewed (inline)
**Assessment:** No new processing activity, recipient or retention: the same host reads the same
volume it already read; the replayed metadata lives in RAM for the duration of the count and is
destroyed. The fix shortens the Art. 17 refusal window ADR-239 accepted. The Art. 30 register
(PA-36 (g)) does not name the `noload` mechanism, so no register edit. `soleur:gdpr-gate` is run
because the threshold is `single-user incident` (trigger b).

**gdpr-gate result (2026-09-24, advisory, not legal review):** no Files-to-Edit/Create path matches
the canonical regulated-data regex; none of the five v1 checks fire (no schema column, no FK to
`users`, no new vendor — Hetzner/Better Stack/Sentry are existing processors — no Art. 9 column).
One **Suggestion** (Art. 17 / Art. 32): the Art. 17 refusal window that opened at 09:09:30Z stays
open until G3's marker is written; the runbook's existing "sweep the refused ids from Sentry
(`op:git-data-bare-repo-erasure`) and re-drive them" step must run after G3 — AC16 references it.
No `compliance/critical` finding; nothing written to `compliance-posture.md`.

### Product/UX Gate

Not applicable — no user-facing surface (infra/bootstrap only). No UI file in either Files list.

## Infrastructure (IaC)

### Terraform changes

- `apps/web-platform/infra/rung2-rehearsal/variables.tf`: `rehearsal_phase` (string, `seed|payload`,
  no default). `rehearsal.tf`: conditional `user_data` (seed template or module render); the replace
  arm adds `-replace=tls_private_key.rehearsal_host_ssh` at plan time. No new resources, providers or sensitive
  variables. The production root (`git-data.tf`) is untouched; the production render changes only
  through `git-data-bootstrap.sh` and `cloud-init-git-data.yml` (the module's `file()`-bound
  payload), which is hash-bound by the rung-2 interlock.

### Apply path

(b) cloud-init + idempotent bootstrap: the production host receives the change only through the
next `git_data_host_replace` (G3) — `hr-prod-host-config-change-immutable-redeploy`; no in-place
patch, no SSH. Blast radius of G3: the git-data host is destroyed and recreated; both volumes are
retained; the store is empty and the flag is off.

### Distinctness / drift safeguards

The rehearsal root keeps its distinct state key; the payload plan-shape admission set is exact; the
seed render lives only in the rehearsal root and cannot reach the production module (the
root-purity rows in `git-data-rung2-rehearsal.test.sh` extend to it).

### Vendor-tier reality check

Hetzner: two extra short-lived boots of the rehearsal server type per rehearsal (the seed and the
replace boot), same project quota; the hard power-off is guest-side `sysrq`, and the off-poll reads
the existing API. Cap: 2 paid G1 runs per payload hash.

## Architecture Decision (ADR/C4)

### ADR

Amend **ADR-239** (Decision 2 + Consequences + Alternatives), dated 2026-09-24, status stays
`adopting`. No new ADR: the decision (read once, never writable, fail closed) is unchanged; the
mechanism that reads it changes.

### C4 views

One description edit, no structural change. `model.c4` `gitDataStore` (line ~292) says the retained
plaintext volume "is mounted read-only once per instance" (now: set kernel read-only and read
through a throwaway snapshot, which is what gets mounted) and "Until that replace the live host
still serves the PLAINTEXT…" (stale since the 2026-09-24 replace destroyed that host). Both clauses
are rewritten (architecture review). Checked against all three files: no new external actor
(the seed host is rehearsal-only and outside the production model), no new external system (Hetzner
and Better Stack edges exist), no new container or store beyond a transient in-host tmpfs, no
access-relationship change, no edge cardinality moves. `views.c4` and `spec.c4` carry no
plaintext-volume element. Backed by a green `plugins/soleur/test/c4-count-parity.test.sh` run plus
the c4 syntax/render tests (AC12).

### Sequencing

The amendment describes the target state at merge; "gap closed" is proven in production only at
AC16, which is also ADR-239's existing accept rule.

## Encryption Posture

```yaml
at_rest:
  - store: hcloud_volume.git_data (retained plaintext ext4, production)
    mechanism: plaintext-exception (existing, ledgered by ADR-239 / encryption-posture-ledger.json)
    evidence: unchanged by this PR; now additionally set kernel read-only (blockdev --setro) at first boot and never made writable
    defends_against: accidental or journal-replay writes to the retained volume from the git-data host
    does_not_defend: disclosure of its (empty) contents to a holder of the Hetzner project or root on the host; the ro flag resets on reattach/reboot (nothing re-mounts it after boot)
    disclosed_as: ADR-239 amendment 2026-09-24
    live_verification: boot_complete plaintext_volume=present plaintext_journal=<v> plaintext_empty=yes (Better Stack)
  - store: transient COW for the plaintext snapshot (a sparse file under /dev/shm on the git-data host, RAM only)
    mechanism: plaintext-exception (volatile memory, lifetime = the count, destroyed at teardown)
    evidence: loopback suite asserts no /dev/shm directory, loop or dm device survives any arm
    defends_against: persistence of replayed plaintext metadata on the root disk
    does_not_defend: root on the host reading it during the count window; memory is not encrypted; a teardown FATAL leaves it in RAM until reboot (named FATAL, no marker)
    disclosed_as: ADR-239 amendment 2026-09-24
    live_verification: a lingering device is a named FATAL reason=teardown at stage=bootstrap
  - store: hcloud_volume.rehearsal (rung-2 plaintext, throwaway)
    mechanism: plaintext-exception (synthetic data only; destroyed at teardown)
    evidence: seed writes a marker and a probe entry, no user data
    defends_against: n/a beyond synthetic content — rehearsal-only
    does_not_defend: nothing user-derived is ever on it
    disclosed_as: git-data-rung2-rehearsal.md
    live_verification: the workflow's "Assert no rehearsal host survives" step
in_transit:
  - connection: none new (the snapshot is host-local; the seed host emits nothing)
    tls: n/a
    cert_verification: on
    does_not_defend: n/a — no new connection
    disclosed_as: this section
exception:
  justification: the plaintext volume is the pre-cutover store the cutover retires; the COW is volatile memory (/dev/shm) needed to read it without writing it
  tracking_issue: "#8571"
  reevaluate_when: the wipe PR empties git_data_volume_id
  expires_on: 2026-12-31
```

## Guard Contract

### Guard 1 — the plaintext volume is read through a snapshot and never written

**Property.** No code path in the store-verify unit writes, or makes writable, the retained
plaintext device; its kernel read-only flag is set before any mount, dm table or write-capable open
of it; and the tree it counts is the post-journal-replay tree.

**Assembly.** The single `_pt_id` block of the store-verify unit (the only site that opens the
plaintext device), its `_pt_release` trap, and the inner `plaintext-count` sentinels that both the
stub harness and the loopback suite extract; no other bootstrap line references
`GIT_DATA_PLAINTEXT_*` (a static row asserts that count, so a second opener reds).

**Mutation matrix.**

| # | Mutation | Must go RED in |
|---|---|---|
| 1 | delete `blockdev --setro` | stub (order/presence row), loopback (`--getro` = 0 after unit) |
| 2 | REORDER: move `--setro` after `dmsetup create` | stub `calls.log` order row, static line-order row |
| 3 | mount `$_pt_dev` instead of the snapshot | stub mount-source row; loopback arm B/C (`reason=mount`) |
| 4 | re-add `noload` to the snapshot mount | loopback arm C (count 0 instead of residue) |
| 5 | drop the post-replay needs_recovery check | stub R4c |
| 6 | drop `dmsetup remove` from `_pt_release` | loopback leak row; stub teardown-order row |
| 7 | add a second plaintext opener after a compliant first (e.g. `dumpe2fs`-then-`mount` of `$_pt_dev` later) | static "only one opener" count row |
| 8 | harness dispatch: extraction yields zero lines | X-row floor / LOOPBACK_UNAVAILABLE non-zero exit |

**Harness rows.** RED: a harness edit that skips the shutdown ioctl (image clean) must abort arm C
on its precondition, not pass. Must-PASS (non-canonical, permitted): arm A (clean journal) passes;
a snapshot name supplied through the seam passes.

**Anchor.** The loopback suite recomputes the origin sha256 itself; nothing stored in the repo is
compared, so no single diff can edit both the value and the thing.

### Guard 2 — rung-2 evidence cannot PASS without the dirty-journal boot

**Property.** `git-data-rung2-evidence-capture.sh` writes `RUNG2_BOOT_REHEARSAL=PASS` only when the
payload's `boot_complete` reports `plaintext_volume=present` and `plaintext_journal=dirty`.

**Assembly.** The capture script's PASS decision (the `_TERMINAL` loop and the final PASS branch)
and the HOSTROWS SQL select list — the only producer of the evidence file.

**Mutation matrix.**

| # | Mutation | Must go RED in |
|---|---|---|
| 1 | delete the journal condition | test row `present+clean -> not PASS` |
| 2 | match with a substring (`*dirty*`) | test row `present+notdirty` / `Dirty` -> not PASS |
| 3 | drop `plaintext_journal` from the SQL select | test row: field absent -> not PASS |
| 3b | accept `plaintext_volume=absent` as a pass | test row: `absent` -> not PASS |
| 4 | a second boot_complete row (reboot arm) with `clean` after a compliant first | test row: the PASS decision reads the phase-B boot row, not an arbitrary row |

**Harness rows.** RED: a fixture row generator that never emits the field must fail the suite's own
floor. Must-PASS (non-canonical, permitted): `present+dirty` with the fields in a different JSON
key order and extra unrelated fields present.

**Anchor.** The evidence file is written only by the capture run and merged by an evidence-only PR a
human reads (existing interlock).

### Guard 3 — the payload phase replaces only the host, never the dirtied volume

**Property.** In `host-only` mode (payload phase and replace arm) the rehearsal plan changes nothing
but a replace of `hcloud_server.rehearsal`, its two volume attachments and (replace arm)
`tls_private_key.rehearsal_host_ssh`, and an update of its firewall attachment — never either
volume, and the host replace must be present; in `additive` mode (seed phase) it is additive-only.

**Assembly.** `scripts/git-data-rung2-plan-shape.sh` is the single chokepoint; the workflow calls it
for both phases (a static row asserts two call sites and no leftover inline jq guard).

**Mutation matrix.**

| # | Mutation | Must go RED in |
|---|---|---|
| 1 | `host-only` plan replaces `hcloud_volume.rehearsal` | test: refused |
| 1b | `host-only` plan replaces `hcloud_volume.rehearsal_luks` | test: refused (would skip the adopt arm) |
| 2 | `host-only` plan `forget`s an address | test: refused (deny-list the inert verbs) |
| 3 | `additive` mode admits a replace | test: refused |
| 4 | a second, unlisted replace after the admitted set | test: refused |
| 5 | unparseable plan JSON | test: refused (fail closed) |

**Harness rows.** RED: a fixture plan with zero resource_changes must not read as clean in the
payload phase (the admitted replace set must be present). Must-PASS: the admitted set in a
different JSON order.

**Anchor.** The admission set is a literal in the script, reviewed with it; the payload's own
`plaintext_journal=dirty` (Guard 2) independently attests the volume was not swapped.

## Observability

```yaml
liveness_signal:
  what: stage:boot_complete from git-data-bootstrap.sh carrying plaintext_volume, plaintext_journal, plaintext_empty
  cadence: once per host birth/replace (and once per rung-2 rehearsal payload boot)
  alert_target: the boot-signal poll in apply-web-platform-infra.yml (replace) and git-data-rung2-evidence-capture.sh (rehearsal); Sentry stage:bootstrap fatal pages the operator
  configured_in: apps/web-platform/infra/git-data-bootstrap.sh §8, scripts/followthroughs/git-data-rung2-evidence-capture.sh
error_reporting:
  destination: Sentry (stage:bootstrap, level fatal) and Better Stack git-data logs, via log() FATAL routing to git-data-emit
  fail_loud: true — every failure is a named FATAL and exits 1 before the marker writer
failure_modes:
  - {mode: kernel ro flag not set or not read back, or the snapshot apparatus failed (journal geometry, loop, dmsetup create incl. a taken name, invalid COW), detection: "FATAL plaintext_unverified reason=snapshot — <step>", alert_route: Sentry stage:bootstrap}
  - {mode: journal did not replay cleanly into the snapshot, detection: "FATAL plaintext_unverified reason=journal", alert_route: Sentry stage:bootstrap}
  - {mode: snapshot mount failed or tree unreadable, detection: "FATAL plaintext_unverified reason=mount", alert_route: Sentry stage:bootstrap}
  - {mode: mount source or origin identity mismatch, detection: "FATAL plaintext_unverified reason=source", alert_route: Sentry stage:bootstrap}
  - {mode: transient device could not be torn down (umount, dmsetup remove, losetup -d), detection: "FATAL plaintext_unverified reason=umount — <step>", alert_route: Sentry stage:bootstrap}
  - {mode: plaintext volume holds repositories after replay, detection: "FATAL plaintext_residue count=<n>", alert_route: Sentry stage:bootstrap; runbook routes to CLO}
  - {mode: rehearsal seed never dirtied the journal or stalled, detection: "capture refuses PASS (plaintext_journal != dirty); seed off-poll timeout with Better Stack stage=seed_<step> rows", alert_route: rung-2 workflow run red + step summary}
  - {mode: adopted-LUKS replace boot fails in rehearsal, detection: "RUNG2_REPLACE_BOOT=FAIL; evidence artifact not uploaded; gate RUN_NOT_SUCCESS", alert_route: rung-2 workflow run red}
logs:
  where: Better Stack source t520508_soleur_git_data_prd_logs (+ s3 archive), Sentry project web-platform
  retention: Better Stack plan retention (30 d hot + s3 archive), Sentry default
discoverability_test:
  command: "bash scripts/betterstack-query.sh --since 30d --grep boot_complete"
  expected_output: "plaintext_journal"
  credentials_required: "Better Stack ClickHouse read connection (BETTERSTACK_QUERY_HOST/USERNAME/PASSWORD in Doppler soleur/prd_terraform) — boot_complete is stored only in Better Stack Logs and Sentry; no unauthenticated endpoint exposes a private-network host's boot state"
```

## Plan Review Revisions (2026-09-24)

Panel: DHH, Kieran, code-simplicity, architecture-strategist, spec-flow-analyzer, CPO (sign-off),
plus the Step 4.5 advisor consult and the Phase 2.5 CTO assessment. All findings applied were
Mechanical (correctness, simplification, blast radius, flow gaps); no Taste or User-Challenge
finding changes the operator's stated direction. The adopted-LUKS replace arm (P8) is an addition to
the brief, endorsed by CTO, CPO and simplicity, and is recorded in
`knowledge-base/project/specs/feat-one-shot-git-data-dirty-journal-dm-snapshot/decision-challenges.md`
so the operator sees it.

- **Advisor:** prove the kernel mechanism first (Phase 0 + AC0), with a named fallback. The kernel
  source (v6.8 `dm-snap.c`, origin opened `BLK_OPEN_READ`) is cited, but it does not substitute for
  the measurement.
- **Simplification (DHH + simplicity):** about ten mechanisms were cut; see the Cut List. There is
  now one new reason word (`snapshot`), and the COW sits in `/dev/shm` instead of a dedicated tmpfs.
  The plan-shape script has two modes. Capture PASS requires `present`+`dirty`, and there is no
  gate edit.
- **Kieran:**
  - P2 is reworded (read-only `isLuks` probes precede `--setro`).
  - `_pt_sz` gets its own checked line.
  - The trap is idempotent and collect-then-exit.
  - The mount-option string is pinned and grepped over the comment-stripped body.
  - Each loopback arm runs in a child bash against the real `_repo_count`.
  - `templatefile` escaping is handled.
  - The meaningless seed-side needs_recovery check is dropped.
  - Workflow step ids and windows are distinct, including `RUNG2_REPLACE_SINCE`.
  - The time budget is summed over every step.
  - Two false claims about existing files are corrected.
- **Architecture:**
  - No new env seams (otherwise the `env -u` list and census C2 would need them too).
  - The replace arm mirrors production's `tls_private_key` `-replace`.
  - Capture #2's window is stamped before the apply.
  - The evidence upload moves after capture #2, with `replace_rc`.
  - The `model.c4` description is corrected.
  - ADR-149 gets a pointer.
  - The hash-binding facts are stated.
- **Spec-flow:**
  - The job timeout gets a separate `if: always()` teardown job.
  - G1 gets a failure table and a 2-run cap.
  - A fallback decision point is added.
  - Hash-voiding merges are held between G1 and the evidence PR.
  - The sweep window starts at the replace run.
  - "G2 clean" is defined.
  - A production `clean` journal means NO-GO.
  - G3 is capped at one attempt.
- **CPO (sign-off: yes, conditional, conditions applied):**
  - The User-Brand Impact wording is corrected: deletion completes, and no repository is on the host.
  - The Art. 12(3) deadline is 2026-10-24.
  - The sweep queries `op:git-data-bare-repo-erasure`.
  - #8710 starts now, in parallel.

## Alternative Approaches Considered

| Alternative | Why not |
|---|---|
| Mount the plaintext volume rw once so ext4 replays the journal | Writes the retained volume; violates ADR-239 D2 |
| Keep `noload`, count the stale tree | Can miss journal-only entries — the exact reason the FATAL exists (arm C proves it) |
| `e2fsck` a full image copy | A volume-sized copy (10 GB+) on a 4 GB host with no spare disk |
| Attach the volume to a throwaway host and fsck it | Writes the volume and is not replace-durable |
| COW on a root-disk file | Persists replayed plaintext metadata on the root disk; `/dev/shm` keeps it volatile |
| Snapshot only when needs_recovery is set | Two paths; the clean path would be the only one rehearsed |
| Separate seed server resource / API-created seed | New addresses and a destroy-admission set; the same-address replace mirrors production |
| Fold #8710 into this PR | Disjoint files; widens a hash-bound payload PR; not needed until G2 |

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the
  threshold will fail `deepen-plan` Phase 4.6.
- `blockdev --setro` on a by-id **symlink** acts on the resolved `/dev/sdX`; the LUKS-discriminator
  (`cryptsetup isLuks`) must run first so a mis-rendered id can never set the LUKS volume
  read-only under the live mapper.
- The snapshot carries the plaintext filesystem's UUID; while it exists udev may point
  `/dev/disk/by-uuid/<uuid>` at it. Nothing on the host mounts by that UUID; teardown restores it.
  Use `udevadm settle` + `dmsetup remove --retry` (udev's blkid probe can briefly hold the device).
- The COW file's size is the only bound on replay writes and on the RAM `/dev/shm` spends on them;
  a parse failure of `Total journal blocks`/`Block size` is `reason=snapshot`, never a default.
  Raising `var.git_data_volume_size` grows the journal and the COW; re-check the sizing then.
- **Does merging THIS alone mutate production? No.** The merge touches `apps/web-platform/infra/**`,
  so `apply-web-platform-infra.yml`'s push arm fires. But its `-target` set reaches no git-data
  address: `hcloud_server.git_data` is replaced only by the `git-data-host-replace` dispatch (G3).
  That dispatch is also HELD by the rung-2 interlock from this merge until the evidence PR lands,
  because this PR changes the hash-bound payload. `rung2-rehearsal/**` is excluded from the push
  trigger. The PR body's first line states this.
- This plan's `discoverability_test` declares `credentials_required`, which moves the repo-global
  `BASELINE_DECLARED_PROBES` ratchet in `plugins/soleur/test/preflight-discoverability-test.test.ts`
  (24 today). Bump it in the same PR; no file-scoped suite selection reaches it.
- The seed's shell is rendered by `templatefile`: every `${…}`/`%{` meant for bash must be escaped,
  or the render fails at plan time (or silently substitutes).
- The capture's Better Stack window must start at the **phase-B** apply, or a phase-A artefact could
  be read (the seed emits nothing, but the window is the guard).
- The loopback suite cannot run locally without passwordless sudo; do not "skip" it — its first CI
  run is the evidence.
- `modprobe dm-snapshot` depends on the pinned image shipping the module (`linux-modules`, not
  `-extra`); the rung-2 payload boot is what proves it on the real image.
