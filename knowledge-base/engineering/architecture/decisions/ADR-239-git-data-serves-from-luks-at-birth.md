---
title: "ADR-239: git-data serves its store from LUKS at birth"
status: accepted
date: 2026-09-23
issue: 8211
supersedes: []
amends:
  - ADR-068
  - ADR-220
tags: [git-data, luks, cutover, erasure, article-17, cloud-init, terraform, security]
---

# ADR-239: git-data serves its store from LUKS at birth

## Status

`adopting`. Authored by PR #8564 (PR1 of #8211). It flips to `accepted` when a **production**
instance of `hcloud_server.git_data` emits `stage:boot_complete` reading
`luks_mounted=yes fence_on_mapper=yes erasure_probe=yes`. A rung-2 rehearsal reading the same
values is a precondition for the replace that produces that boot, not a substitute for it: the
rehearsal boots the same template on a different host, against a freshly formatted plaintext
volume.

## Context

ADR-068's 2026-07-27 addendum decided **D10 — born-on-LUKS rejected**, on the ground that
"revisiting it would rewrite a cutover path that is already built and tested for a host that does
not exist yet". Neither half of that ground survives:

- The path was **deleted**. #8189 removed the rsync / freeze / repoint / flag-flip / rollback /
  wipe body from `git-data-cutover.sh`, leaving a read-only proof. ADR-220's Context records that
  it had never run before that PR's branch dry run.
- It was never **tested** against anything. Its freeze and reload steps called systemd units that
  exist on neither host, and a second run after a repoint could rsync a store onto itself.

So D10 defends a design that no longer has an implementation, and the rebuild (#8211) is free to
choose its mechanism rather than inherit one.

Three further facts fix that choice:

1. **The store has never held a repository.** `GIT_DATA_STORE_ENABLED` has never been `true`, and
   the flag is the sole write gate. There is nothing to copy, so the copy machinery buys nothing
   at this cutover — it buys something only at the first rotation of a *populated* store.
2. **A fixed mapper assertion is incompatible with a plaintext-serving host.** #8101 item 2 asks
   the store-acting wrappers to assert `/dev/mapper/git-data`. Erasure is deliberately not
   flag-gated, so on a host still serving the plaintext volume that assertion would refuse every
   Art. 17 Delete Account. The assertion is only correct if the layout and the wrappers arrive in
   the same render.
3. **A runtime repoint is not durable.** ADR-220 D6 assumed the serving device moves inside a
   cutover run. `user_data` is `ForceNew`; a mount moved by a script does not survive the next
   `git_data_host_replace`, and an in-place host config change is barred by
   `hr-prod-host-config-change-immutable-redeploy`.

The CTO ruled for option **B-lite**: one immutable, cloud-init-rendered serving layout, no
selector, no toggle.

## Decision

1. **The render always mounts `/dev/mapper/git-data` at `/mnt/git-data`.** There is no
   plaintext/LUKS mode selector, no interlock and no transition guard. The mapper's fstab entry
   carries that target, and the reopen unit accepts no other.
2. **The plaintext volume is read once per instance and never mounted after that.** When
   `git_data_volume_id` is non-empty the bootstrap mounts it `ro,noload` at a private `mktemp -d`
   path, checks that the mount's SOURCE resolves to the by-id device, counts every entry under
   `repositories/`, unmounts and removes the directory. A failed mount or a wrong source is FATAL
   `plaintext_unverified`; a non-zero count is FATAL `plaintext_residue count=<n>`. The volume is
   retained and was never writable.

   > **Amended 2026-09-24 (#5274):** the plaintext volume is no longer mounted. It is set kernel
   > read-only and read through a throwaway dm snapshot; see
   > [Amendment 2026-09-24](#amendment-2026-09-24--the-dirty-journal-gap-is-closed-5274-5914).
3. **Every store-acting script asserts the device and a positive marker.**
   `git-data-provision.sh`, `git-data-remove.sh`, `git-data-transport-wrapper.sh` and
   `git-data-gc.sh` refuse, fail-closed and named, unless `findmnt` is on PATH,
   `findmnt -n -o SOURCE --mountpoint /mnt/git-data` **equals** `/dev/mapper/git-data` by string
   comparison, and `/etc/git-data/store-verified` holds the mapper filesystem's UUID. The marker is
   positive, not a residue flag: a script refuses until the bootstrap has proved the layout, rather
   than proceeding until something marks the host bad.
4. **The serving change rides the next ordinary replace.** It reaches production at ADR-237's
   post-merge step 3 `git_data_host_replace`, while the flag is off and the store is empty. No new
   replace is introduced; no separate cutover run moves the device.

## Consequences

- **Tier-2 rollback to plaintext no longer exists** (CTO condition 5). After PR1 there is no
  plaintext serving layout to return to, and after the flip (PR2) rollback is **flag-off only** —
  data stays on LUKS. PR2's rollback refuses a plaintext path explicitly. This is a capability the
  project had on paper and gives up deliberately: its only property was a rollback to a store that
  had never held data, paid for with a selector, an interlock, a transition guard and a guard
  suite.
- **Copy mode is deferred to #8571.** Freeze, rsync and repoint are the mechanism a *populated*
  store needs at a key rotation. Nothing in PR1 or PR2 provides it, and the first rotation against
  a populated store is blocked on that issue.
- **CTO condition 1 is met on the host, not in the replace job (accepted deviation).** The
  condition asked the replace job to prove the store empty before the serving change. It is met
  instead by the bootstrap's read of the real volume (decision 2) plus two reads the operator
  records in the runbook before dispatching step 3: the cutover dry run's precheck refusal
  `verdict=git_data_host_key_unavailable reason=absent`, which proves the flag is not `true`
  because `flag_already_true` is refused earlier in the same script, and a paged
  `doppler configs logs` read establishing the flag has never been true. The on-host check is the
  stronger of the two — it reads the device that will serve, fails closed, and runs before any
  erasure can be answered — and it keeps a `prd` token out of `apply-web-platform-infra.yml`, the
  file #8209 is redesigning. The CTO accepted this on devex review.
- **A failed step-3 replace has a forward-only recovery, and an Art. 17 window.** If the fresh host
  ends in any boot FATAL, the marker is never written, so every Delete Account is refused. The
  account deletion itself still completes and each refusal is a logged Art. 17 event
  (Sentry `op:git-data-bare-repo-erasure`). Nothing is left behind, because the store is empty. The
  fix is forward — PR, rehearsal, evidence PR, replace — and takes hours to days; the refused
  workspace ids are swept from Sentry and re-driven afterwards. **There is no revert to a pre-PR1
  tag:** any such tag must postdate #8511, and no rung-2 evidence exists for #8511's template
  alone. Recovery is a read first, never another replace. The recovery procedure is in
  `git-data-luks-cutover-5274.md`.
- ~~**The dirty-journal `noload` gap is real and accepted.** The rung-2 rehearsal's plaintext volume
  is freshly formatted, so it never boots the production case: a volume last mounted read-write by
  a destroyed host, with a dirty ext4 journal. If `mount -o ro,noload` then refuses it, step 2
  fails closed as `plaintext_unverified` on the first production boot the rehearsal could not
  reproduce. The failure is safe — read-only, data retained, no marker written — and its recovery
  is written down, but the rehearsal cannot pre-empt it.~~ **Closed 2026-09-24** — it happened
  exactly as described (see the amendment below), and both halves are now answered: the count reads
  a dirty journal, and the rehearsal reproduces one.
- **The wipe branch needs a rehearsal of its own.** Emptying `git_data_volume_id` selects a render
  branch no rehearsal has booted. The wipe PR therefore carries its own rung-2 rehearsal with an
  empty volume id, declared under `RUNG2_VAR_DIVERGENCE`.
- **`erased` means unlinked, not destroyed.** `git-data-remove.sh` unlinks the bare repository.
  Its blocks stay readable to a holder of the `GIT_DATA_LUKS_KEY` until the key and the volume are
  rotated, which ADR-220 D6 defers to PR2. The Art. 30 register says so at PA-36 (g)(2).
- **Every payload is hash-bound.** The layout change is a template change, so the rung-2 interlock
  voids the existing evidence and refuses every git-data birth and replace from PR1's merge until a
  fresh rehearsal and its evidence-only PR land. That window is shared with #8511's, because the
  #8511 re-rehearsal is held until PR1 merges (recorded on #5914): one paid rehearsal covers both
  payloads.
- **ADR-068 D10 is superseded** and ADR-220 D6's runtime repoint is withdrawn; both carry dated
  amendments pointing here. ADR-237 D6 is amended in PR2, when the fresh replace it describes is
  built.

## Alternatives considered

| # | Alternative | Why not |
|---|---|---|
| A | Rebuild the runtime rsync and repoint as #8211 originally scoped | Not replace-durable, and an in-place host config change. It copies nothing on the first run, because the store is empty. The CTO ruled against it. |
| B | A plaintext/LUKS mode selector, with a luks-mode interlock, a PR2 transition guard and a tier-2 rollback | Its only property is a rollback to a plaintext store that never held data. It costs a selector file or variable, an interlock, a guard and a second render branch. Cut to B-lite. |
| C | A hybrid of A and B | Machinery with nothing to run on. |
| D | Keep the plaintext volume mounted read-only for its lifetime | Its only use is a one-time count. A temporary bootstrap mount removes a permanent path the store-acting scripts could otherwise reach. |
| E | A residue marker the scripts refuse on | It fails **open** during the bootstrap window: the wrappers and `authorized_keys` land in `write_files`, before `runcmd`, so an erasure arriving mid-bootstrap would be answered. The positive `store-verified` marker fails closed. |
| F | Prove emptiness with the existing dry run's `store_not_empty` probe instead of on the host | Before step 3 the dry run refuses at the precheck for want of a pin, so its store probes never run. Verified against `git-data-flag-precheck.sh`. |
| G | A replace-job step that reads the `prd` flag (CTO condition 1 as written) | Needs a `prd` token in `apply-web-platform-infra.yml`, the file #8209 is redesigning. The CTO accepted the on-host check instead. |
| H | Ship PR1 and PR2 as one PR | Pushes the hash-bound half past the #8511 rehearsal, costing a second paid rehearsal and widening the emergency-replace gap. |
| I | (2026-09-24) Mount the plaintext volume rw once so ext4 replays its journal | Writes the retained volume; violates D2 ("never writable"). |
| J | (2026-09-24) Keep `noload` (or `debugfs -c`) and count the stale on-disk tree | Can miss an entry that exists only in the journal — the reason the FATAL existed. The loopback suite's arm C builds exactly that entry. |
| K | (2026-09-24) `e2fsck` a full copy of the volume | A volume-sized copy on a 4 GB host with no spare disk. |
| L | (2026-09-24) A second, throwaway host that repairs the volume's filesystem before the count | Rejected: the repair writes the volume, it adds a path outside the replace, and it is not replace-durable. |
| M | (2026-09-24) Use the snapshot only when `needs_recovery` is set | Two code paths, and the clean one would be the only one the old rehearsal booted. |

## Amendment 2026-09-24 — the dirty-journal gap is closed (#5274, #5914)

**Motivating event.** ADR-237 post-merge step 3 (`git_data_host_replace`, run 35979304442) applied
cleanly and the fresh host FATALed at 09:09:30Z:
`plaintext_unverified reason=journal … has needs_recovery set; its tree was not counted`. The
predecessor was destroyed while the plaintext volume was mounted read-write, so its journal was
dirty — the accepted gap above, on the first production boot. Nothing was written; no marker; every
Art. 17 erasure refused until a later boot writes one.

**Decision 2 now reads the volume through a non-persistent dm snapshot.** The bootstrap resolves the
by-id link to its block device and records its device number, re-checking it (through both the link
and the node) before `--setro`, before `dumpe2fs` and before the dm table, and requiring the
snapshot's `dmsetup deps` to name it — a kernel name like `sdX` is reused after a detach, so the
name alone pins nothing. It refuses a LUKS device, a device with holders or no sysfs entry, and a
snapshot left over from a previous run (never removed automatically). It reads the device's
written- and discarded-sector counters from `/sys/dev/block/<maj:min>/stat`, sets the device kernel
read-only (`blockdev --setro`, read back) before any mount, dm table or write-capable open, stacks a
dm `snapshot` target on it (which opens its origin read-only) with a copy-on-write file on
`/dev/shm` sized from the journal geometry, and mounts the **snapshot** read-only **without**
`noload`, so the journal replays into the COW and the counted tree is the post-replay tree. It then
requires the mount SOURCE to be the snapshot; the snapshot superblock to no longer need recovery
and not read `with errors`; ext4's `errors_count` after replay to equal the origin superblock's
historical `FS Error count` (so a volume that once logged an error is not a permanent FATAL, but
mount or replay adding one is), and not to move across the count (ext4 readdir skips a
checksum-failed directory block with only a log line); `repositories` to be absent or a real
directory (a symlink is never followed — on the snapshot it would resolve against the host root);
and the snapshot not to be `Invalid` before or after the count. After teardown the origin's
sector counters must be unchanged. Teardown is collect-then-exit, with `udevadm settle` and the
`dmsetup` calls time-bounded. Every failure is a named
`FATAL: plaintext_unverified reason=source|snapshot|mount|journal|umount` (`snapshot` is the one new
word); `plaintext_residue count=<n>` is unchanged. `boot_complete` gains the informational
`plaintext_journal=dirty|clean|absent`. Separately, the cloud-init LUKS stage refuses to run when
the LUKS and plaintext volume ids are equal, because a mis-wired id would `luksFormat` the retained
volume before the bootstrap ever sets it read-only.

**D2 ("never writable") still holds, and the kernel read-only flag is a stated backstop, not the
proof.** With the origin kernel-read-only, ext4 refuses to replay a journal onto it
(`write access unavailable, cannot proceed`) — the loopback suite's negative control measures this
on the CI kernel — and `write(2)` on the node gets `EPERM`. But the flag is an in-memory, per-boot
property, lost on reboot and on detach/reattach, and it is not a bio-level barrier: in Linux v6.8
`bio_check_ro` only warns, once per device, and it cannot stop a writer that opened the device
before `--setro`. Two checks carry the proof instead. At runtime, the unit's before/after comparison
of the origin's written- and discarded-sector counters (empty flushes, which the snapshot target
sends to its origin, move neither). In CI, the loopback suite's sha256 of the origin's backing file
before and after every arm, plus a mutant arm that writes one origin sector and must FATAL.

**The COW is in RAM on purpose.** It holds replayed filesystem metadata — directory entries, which
name workspaces — so nothing of it may land on the root disk (the host has no swap). It lives only
for the count and is deleted at teardown. If teardown itself fails, the boot ends FATAL
`reason=umount` with no marker, and the COW file can remain in RAM until that host reboots or is
replaced; it is never written to disk or transmitted.

**The rehearsal now reproduces the production case.** The rung-2 rehearsal boots three times on one
address. A seed mounts the plaintext volume read-write, creates a `repositories/` probe and syncs it
home, removes it with an fsync only (so the removal lives only in the journal), and powers off
without unmounting. The payload (boot #1) can PASS only on
`plaintext_volume=present plaintext_journal=dirty` with a count of 0 — and a read that did not
replay the journal would have counted the probe and FATALed `plaintext_residue count=1`. A replace
(boot #2) adopts a LUKS volume a predecessor formatted and abandoned mounted, and must read the
journal dirty again, which shows no replay reached the volume (only a replay clears
`needs_recovery`); that nothing else was written is what the sector-counter gate and the loopback
hash show. Details: `git-data-rung2-rehearsal.md`.

Status stays `adopting`; the flip rule above is unchanged, and it is also the rule that proves this
amendment in production.

## Amendment 2026-09-27 — the proof reads the LUKS-served store (#8211 PR2, proof half)

**What changed.** The read-only dry run in `git-data-cutover.sh` asked the pre-PR1 question ("is the
store still on a plaintext device?"), so after replace run 36118115758 every run refused
`already_cut_over` before it reached the emptiness count. The store probes now read the layout this
ADR renders:

- **The polarity is inverted.** `probe=store-on-mapper` refuses any served device other than
  `LUKS_MAPPER` (`store_not_on_mapper`), because D1 says the render never serves one.
  `already_cut_over` is retired.
- **A pass rests on D3's evidence, read at one instant.** One ssh session reports two probes.
  `probe=store-verified`: the store is still served by that device (`findmnt --mountpoint`, the
  wrappers' own query), the freeze sentinel is absent (read first), the filesystem has a UUID, and the
  wrappers' marker holds that UUID on its first line. `probe=store-empty`: `repositories/`'s
  containing mount is the store root (the wrappers' `stat -c %m` check), and it holds no entry except
  the lock dotfiles and `lost+found` — the bootstrap's own `_repo_count` rule, not only `*.git`.
  Reading everything in one session removes the window in which a mapper could be reopened on another
  volume between reads.
- **Never stricter than the wrappers.** A `store_unverified` means every wrapper refuses now;
  `cutover_frozen` means provision, remove, the transport wrapper and pre-receive do (gc does not read
  the sentinel). The probes read as root while the wrappers run as git, so a permission fault can make
  the wrappers refuse where the proof passes; the git-user path is attested by `boot_complete
  erasure_probe=yes` and the fence probe's `runuser` checks, not by this proof.
- **Configuration is checked before anything is printed or dialed** (`probe=config`).
- **It makes no encryption claim:** when encryption at rest became active for the Art. 30 register
  is #8634's determination.
- **The ADR-237 addendum's "making the proof read `already_cut_over` as a pass" is discharged by
  rebuilding the probes, not by passing that verdict.**
- **The `DRY_RUN=1` probe chain is the `proof`** the rest of PR2 builds on, and it keeps
  `store_not_empty`.

**What remains of PR2, on #8211:** the flip; the flag-off-only rollback; the same-version redeploy;
the in-container `git_data_store=` startup line on every web host (the per-host proof); the ADR-220 D6
fresh replace with its LUKS key and volume rotation; the amendment to ADR-237 that the fresh replace
needs (this ADR and the PR1 plan call it "ADR-237 D6", but ADR-237 has decisions 1 to 5 only); a freeze
writer; and pin-fault paging (#8572). The real modes keep refusing `real_cutover_unreconciled`.
**Forward coupling:** the proof refuses `cutover_frozen`, so when the flip gains a freeze writer it
must run the proof before it acquires the freeze, or pass the proof an expected-frozen parameter.

Status stays `adopting` under its unchanged flip rule; the flip is recorded alongside the ADR-220 D1b
docs PR, which reads the current instance's `boot_complete`.

## Amendment 2026-09-27 — accepted (#8211 PR2, post-merge)

- **The flip rule in Status is met in production.** `hcloud_server.git_data` (Hetzner id
  `167392038`, created 2026-09-25T09:24:32Z by replace run
  [36118115758](https://github.com/jikig-ai/soleur/actions/runs/36118115758)) emitted
  `stage:boot_complete` at 2026-09-25T09:25:30Z reading `luks_mounted=yes fence_on_mapper=yes
  erasure_probe=yes`. The query is the runbook's host-key step 5 (b), filtered to `host_name`
  `soleur-git-data` (rehearsal hosts report `soleur-git-data-rehearsal-<run>`), with the raw row
  printed. The raw row and the Hetzner read are recorded on #8211 (issuecomment-5860128868).
- **It is the current instance.** Re-read on 2026-09-27: the Hetzner API returns that one server,
  same id and creation time, and Better Stack holds that one `boot_complete` row since the replace.
  A newer create would change the id, and an in-place rebuild would add a row.
- **The rung-2 precondition in Status was met before that replace.** Rehearsal run
  [36029201848](https://github.com/jikig-ai/soleur/actions/runs/36029201848) (2026-09-24, `main`,
  `success`) is bound by the committed evidence
  `apps/web-platform/infra/git-data-rung2-boot-evidence.env` (`Rehearsal host :
  soleur-git-data-rehearsal-36029201848`, PR #8751). The replace gate refuses without it.
- **The same row proves the 2026-09-24 amendment in production:** it also reads
  `plaintext_journal=dirty plaintext_empty=yes`. That amendment named this flip rule as its
  production proof.
- **What `accepted` does not change.** `GIT_DATA_STORE_ENABLED` stays off. The flip, the flag-off
  rollback, the same-version redeploy and the ADR-220 D6 fresh replace remain on #8211. When
  encryption at rest became active for the Art. 30 register stays #8634's determination.

Dated text above is not rewritten; the Status paragraph keeps the rule this amendment records as met.

## Amendment 2026-09-30 — PR2 implementation: freeze writer, lock migration, real-hook delivery

The forward-coupling sentence in the 2026-09-27 amendment is resolved and the remaining PR2 items
landed:

- **The freeze sentinel gained a writer.** `MODE=freeze` writes `/mnt/git-data/.cutover-freeze`
  carrying `writer=<lineage> at=<epoch>` provenance (the lineage's `^[A-Za-z0-9._-]{1,64}$` shape,
  `CUTOVER_LINEAGE`=`cutover-<run_id>`), only after `git-data-gc.service` is measured quiesced
  (`systemctl show`, not `is-active`) and `git-data-gc.timer` is stopped. `MODE=unfreeze` clears
  ONLY a same-lineage sentinel — a foreign or unparseable sentinel refuses (`frozen_foreign` /
  `frozen_unattributed` in the runbook verdict map), because a sentinel that no live run wrote is a
  host incident, not cleanup. The proof still refuses `cutover_frozen`, so the flip orders proof
  BEFORE freeze; inside the window the store verbs refuse, which is the freeze's whole function.
- **`FREEZE_HELD` pages.** A sentinel that cannot be cleared (hop down mid-unfreeze) emits a
  dedicated paging line rather than folding into a summary verdict — a stranded freeze bricks the
  erasure path.
- **#9066's legacy-lock residue is bound to the freeze window.** The `. <id>.init.lock` files
  (which carry `auth.users.id` on the store) are purged inside `MODE=freeze`, excluding the new
  shared `.init.lock` name and the bootstrap's `.boot-probe-0.init.lock`; a held lock refuses
  (`lock_held`) rather than racing an in-flight provision.
- **The real fence hook delivers at birth.** `git-data-pre-receive.sh` (the CAS-fencing hook) is
  bound into the cloud-init payload and installed root-owned from a staged file — the reject-all
  placeholder is superseded (kept for fixtures only), and every host born after this lands fences
  from first boot. ADR-149's git-UID-channel prohibition is preserved: delivery is the
  root-side cloud-init path, never a git-shell channel.
- **The transactional probe (`MODE=probe`) closes the flip.** Provision → CAS-fenced push →
  ref-landed → remove → zero-residue assert, each failure mode with its own verdict
  (`fenced_push_failed`, `remove_failed`, `residue_left`, `probe_failed reason=provision|scratch|
  repo_absent_after_provision|ref_not_landed`).

## References

- Plan: `knowledge-base/project/plans/archive/20261013-051752-2026-09-22-feat-git-data-cutover-real-modes-plan.md`
- Decision challenges (DC-1, DC-2):
  `knowledge-base/project/specs/archive/20261013-051752-feat-one-shot-8211-git-data-cutover-real-modes/decision-challenges.md`
- Runbooks: `knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md`,
  `git-data-rung2-rehearsal.md`
- Art. 30 register: `knowledge-base/legal/article-30-register.md` PA-36 (g)(1)-(2), PA-2 (g)(17)
- [ADR-068](./ADR-068-multi-host-workspaces-shared-git-data-lease-coordinator.md) (D10, superseded
  here), [ADR-220](./ADR-220-git-data-root-access-via-web-1-jump-and-a-dedicated-terraform-minted-key.md)
  (D6, amended here), [ADR-237](./ADR-237-ssh-host-keys-are-pinned.md) (the step-3 replace that
  carries the serving change),
  [ADR-149](./ADR-149-git-data-host-birth-route-and-readiness-interlock.md) (the birth route and
  the rung-2 gate)
- Issues: #8211, #8101, #8549, #5274, #6897, #8571, #8572, #8573, #8209, #5914

## Amendment 2026-10-02 — the transactional probe also runs after a rollback (#8211)

- **Decision unchanged; one verification added.** Rollback remains flag-off only and never touches a mount or
  volume. After its unfreeze succeeds, `git-data-cutover.yml` now runs the same transactional probe the flip ends
  with (provision, fenced push and remove with a synthetic id, zero residue). It is the CPO condition recorded
  on #8211: the rollback is shown to leave erasure working. A failed probe fails the run red AFTER the unwind
  and is reported by the `notify-failure` job; it never changes what the rollback itself did.
- **What the probe proves, and what it does not.** It exercises the host wrappers through the CI root key. It
  does not exercise the app's own erasure path in the redeployed web container, so the runbook pairs the
  rehearsal with an app-path signal. A re-dispatched rollback exits `nothing_to_rollback` and does not re-run
  the probe; `mode=proof` is the read-only re-verification, and no finalizer cleans a synthetic repository a
  failed probe left behind (tracked in the deferred-items issue).

Plan: `knowledge-base/project/plans/archive/20261003-090828-2026-10-02-feat-git-data-cutover-residual-real-mode-gaps-plan.md`.

## Amendment 2026-10-09 — plaintext-volume retention end and lock-name status (#9066)

- **The lock name carries no subject id: already true on main; no payload change.** Since PR #9226 both
  wrappers open one shared `${REPO_ROOT}/.init.lock`, so a completed erasure and a "not present" erasure leave
  no file named for the user. The rung-2 boot evidence for that exact payload is current
  (`RUNG2_TEMPLATE_SHA256` equals the hash of the tree), so this amendment edits no hash-bound file, and the
  two-PR payload sequence has already run for this change. A new check in the wrappers' unbound test files pins
  the property for the repo root: after an erasure, a provision or a refusal, no entry under the repo root
  other than `<id>.git` carries the workspace id in its name, its content or a symlink target.
- **What was already written is a different question.** A plain `git_data_host_replace` (its
  both-volumes-preserved assert passed) ran on 2026-10-08 as workflow run 37846545572 from head `d0b5d2e35b`,
  which contains #9226, so erasures since then are expected to write only the shared lock; that was read from
  the run and its head, not from the host. Both volumes were preserved across that replace. Any per-id
  `.<id>.init.lock` files from earlier erasures therefore remain where they were written: on the retained
  plaintext volume for erasures from host birth (2026-09-14) until that host was destroyed on 2026-09-24 by
  replace run 35979304442 (its replacement refused to serve, so nothing served between), and on the LUKS-served
  store for erasures from the first LUKS-serving host (replace run 36118115758, 2026-09-25, recorded in the
  2026-09-27 amendment) until the 2026-10-08 replace. No count sees them (the counters skip
  `.*.init.lock`), so whether any exist is not measured. The in-freeze purge (2026-09-30 amendment) will remove
  the served-store ones when a freeze window runs; none has run, and neither the purge nor any other removal is
  taken by this amendment. That amendment's binding of the residue to the freeze window is narrowed here to the
  served store; the plaintext-volume limb is separate and ends as below.
- **Retention end for the plaintext volume.** The residue on `hcloud_volume.git_data` ends when that volume is
  destroyed by the DL-2 destructive wipe (#6897). The wipe PR must include the destroy of the volume itself:
  emptying `git_data_volume_id` alone leaves the volume, and the Hetzner volume delete, recorded in that PR's
  evidence, is the end event. D2 ("never writable") holds until the volume is destroyed, so there is no
  zeroing write and no purge in place: the volume is never mounted to remove the files. **Target: 2026-10-22**,
  the ledger `expires_on` for this store and two days before the 2026-10-24 date in the issue. Hetzner-side
  snapshot retention of the volume remains unmeasured (Art. 30 PA-36 (f)), so this records an end for the
  device and claims nothing about copies of it.
- **A second id-bearing file the repo-root check cannot see: the gc cursor.** `git-data-gc.sh` writes the
  basename of the last repo it completed (`<id>.git`) to `.gc-cursor` at the mount root, one level above the
  repo root, and a later run that completes a repo overwrites it. The timer is nominally weekly (Sunday 03:20), but a
  run that skips, fails or finds the store unverified leaves the old value, and `MODE=freeze` stops the timer,
  so after an erasure the erased id can remain there until a later run completes a repo, and indefinitely if
  no repo remains on the store to be completed. Whether a stale cursor also sits on the plaintext volume is not
  measured. Neither the new check nor the in-freeze purge covers it. Closing it changes a hash-bound
  payload (`git-data-gc.sh`, or the remove wrapper clearing a matching cursor), so it needs the rung-2
  two-PR sequence and is not part of this change; it is recorded on #9066.
- **The date is a target, not a fact.** The wipe body was deleted from `git-data-cutover.sh` in #8189 (landed
  via PR #8206) and does not exist on main. It will be a hash-bound PR with a rung-2 rehearsal of its own (see
  the Consequences bullet on the wipe branch), and it is gated by the flip chain (#8573, #8609, #8209 and a fresh
  replace). **If the date will pass with the volume present, this amendment is re-opened together with the ledger
  exception and the CLO before 2026-10-23, the first day the ledger lint fails; the date is not extended
  quietly.** Until the volume is deleted, the files remain readable to anyone holding the volume or a snapshot of
  it. The lint warns inside 14 days of `expires_on` and fails CI after it.

> **Superseded 2026-10-15 (#6897): "it is gated by the flip chain" no longer holds for the separated wipe variant; see Amendment 2026-10-15 below. The flip chain still gates the flip-chained variant.**

- **Inputs for the CLO re-ruling.** The issue sets the trigger: if the fix and the served-store purge slip past
  2026-10-24, the CLO re-rules on the DPD §10.3(b) disclosure. The re-ruling needs the state of four things: the
  wipe (done, with Hetzner delete evidence, or slipped), the served-store purge (run, with its count, or not),
  the flip (slipped, so the wipe, which is gated behind it, has not been reached), and the gc cursor (fixed by a
  hash-bound payload change, declined by the owner, or still open).

Alternatives considered and rejected: purging the files in place by mounting the volume (violates D2); a
standalone dated purge (needs the same writable mount); extending the date without re-opening this ADR
(storage limitation; the ledger records `expires_on` as deliberately not extended).

Plan: `knowledge-base/project/plans/archive/20261013-062704-2026-10-09-fix-git-data-lock-no-subject-id-9066-plan.md`.

## Amendment 2026-10-09 — the gc timer is not a cutover precondition; the probe verifies first; the unwind marks the attempt (#9439)

Three contracts this ADR states in prose changed, all runner-side (`git-data-cutover.sh`, `git-data-cutover.yml`); no
hash-bound host payload moved.

- **`mode_unfreeze` has a hard post-condition: the gc timer is started.** After the sentinel is cleared it starts
  `git-data-gc.timer`, with one immediate retry (no sleep), and exits **6** (`gc_timer_restart_failed`) if both
  attempts fail. The sentinel is already gone at that point, so the workflow treats this as degraded housekeeping, not
  a switch-back trigger: the unfreeze step goes red, the replication probe and the cutover stamp still run (they key on
  "the sentinel was cleared", not "unfreeze succeeded"), the finalizer does not unwind a flip it would otherwise call
  concluded, and notify carries `GC_TIMER_STOPPED` (one new job output, `gc_timer_stopped`) rather than `FREEZE_HELD`.
  The freeze still fences the store whenever the finalizer does unwind, because the timer is never started before the
  sentinel clear (`git-data-gc.sh` does not read the sentinel). This refines the 2026-10-02 sentence that the probe runs
  "after its unfreeze succeeds" to "after the sentinel is cleared". Accepted cost: the stamp can be written with gc
  stopped; it anchors the ledger on data location, which gc does not affect. Ruled by the CTO agent after three review
  seats showed the earlier fatal-and-unwind default orphaned writes through a writable-store window and repeated on a
  standing cause (`gc_timer=unarmed` at boot is documented as tolerated).
- **The probe verifies the store before it provisions.** `mode_probe` runs the proof's mount, mapper and store-verified
  checks first (`STORE_SOURCE` is read from the mount, never assumed), in a `verified-only` form: the marker, the UUID
  and ANY held sentinel (a probe has no resume arm A), and not the repositories directory or the entry count, so a
  rollback probing a store a live flip has filled is not refused. A booting host reads as its store verdict
  (`old_store_unmounted`, `store_not_on_mapper`, `store_unverified`, `cutover_frozen`) instead of
  `probe_failed reason=provision`, and nothing is pushed or removed against it. A missing repositories directory still
  surfaces later as `probe_failed reason=provision`.
- **The flip unwind keys on "a flag write was attempted".** The `flag_write` step touches `flag_write_attempted` before
  the write runs (mirroring `freeze_held`), and the finalizer's flip arm switches the flag off on `flag_written` or
  `flag_write_attempted`. A write that lands and then fails its read-back is therefore unwound. The cost is stated in
  the runbook: a transient `flag_write_failed` that never landed also runs the unwind (a flag-off write and a
  both-host redeploy). Rollback conditions are unchanged.

The 2026-10-02 sentence that `mode=proof` is the read-only re-verification refines the same way: the proof re-verifies the
STORE only, and no mode re-runs the rollback's erasure probe, so a green proof is not evidence that erasure works.

Still open, tracked rather than fixed here (follow-up tracker #9897): a probe or stamp failure after the
sentinel clear unwinds through a writable window (pre-existing); flip resume arm B never unwinds the flag; a rollback whose
flag-off write landed but whose read-back failed leaves the fleet on the old env (`mode=redeploy` converges it). One live-only
assumption: the probe `if:` reads the unfreeze step's `gc_timer_failed` output after the step exited non-zero; that is documented
runner behaviour and is checked by the first real dispatch, not by any offline suite.

Plan: `knowledge-base/project/plans/archive/20261009-234236-2026-10-09-fix-git-data-cutover-residual-state-matrix-gaps-plan.md`.

## Amendment 2026-10-12 — plaintext-volume retention end re-opened (#6897)

The 2026-10-09 amendment set 2026-10-22 as the target for destroying `hcloud_volume.git_data` and said that if the date will pass with the volume present, this ADR is re-opened with the ledger exception and the CLO before 2026-10-23. This amendment is that re-opening. **The 2026-10-22 target will be missed.** The residue on the volume is understood to include erased-user identifiers (the lock residue is unmeasured, below), so holding the volume past the target is a storage-limitation (Art. 5(1)(e)) overrun against our own stated date once the date passes, and this amendment records it as one rather than as a schedule change.

**New date: 2026-11-12, at the latest.** The ledger row `hcloud_volume.git_data` is renewed to that date (tracking #6897). The date is bound to the flip chain, not to a calendar: a second slip past it re-opens this ADR again and goes back to the CLO. It is not rolled quietly. The CLO's final re-ruling is due 2026-10-24; this amendment is provisional until then. No published legal wording changes in this PR (the hold on privacy-policy and DPD wording stays).

> **Superseded 2026-10-15 (#6897): "bound to the flip chain" no longer holds for the separated wipe variant; the 2026-11-12 date is unchanged. See Amendment 2026-10-15 below.**

**State as measured (Hetzner API read-only and Better Stack, 2026-10-12; none of it read from a host):**

- **Wipe** — not done. Volume 106867358 is attached to server 169724272 next to the LUKS volume 107102614. The wipe body was deleted in #8189 and does not exist on main.
- **Rotate** — `git-data-host-rotate` run 38140050880 (2026-10-11) applied: per its apply log it destroyed the previous LUKS store volume (106867359) and server (169437185), re-created the LUKS passphrase resource, and created server 169724272 with LUKS volume 107102614. The job concluded `failure`: the post-apply both-volumes-preserved assert reported `hcloud_volume.git_data_luks shows 1 delete/forget action(s)` on the replace the rotate arm intends. The cutover flip gate requires that job to have succeeded, so it cannot be satisfied while the assert stands. The fix is tracked at #10137 (separate PR); no re-dispatch is part of this amendment.
- **Flip** — not done. `git_data_store=disabled` on every web container sampled (latest 2026-10-12); #8209, #8609 and #8573 are open.
- **Served-store purge, gc cursor, id-bearing `.<workspace_id>.init.lock` residue since 2026-09-14, Hetzner snapshot retention** — unmeasured. Nothing is claimed about their absence or about copies of the volume.
- **Serving path** — web-1's `luks-monitor` reported `/mnt/data` as LUKS-backed (`mount_source=/dev/mapper/workspaces`, `workspace_count=9`) at 2026-10-12T12:28Z; with the flag disabled, workspaces are served from that volume and not from the git-data host. This says nothing about web-2.

**Owner:** the operator, via #8211 and #6897. **Blocker chain:** the rotate-arm assert fix (#10137), then a fresh rotate dispatch that the operator authorises by naming the command, then #8209, #8609 and #8573, then a hash-bound wipe PR with its own rung-2 rehearsal, then the wipe itself, which the operator authorises by naming the command.

> **Superseded 2026-10-15 (#6897): this blocker chain (#8209, #8609, #8573 before the wipe) applies only to the flip-chained variant; none of them gates the separated variant (Ruled by CTO agent, 2026-10-15). The rotate steps in it are done (measured 2026-10-14). See Amendment 2026-10-15 below.**

Rule for the horizon: moving the ledger `expires_on` of `hcloud_volume.git_data` past 2026-11-12 requires a CLO re-ruling linked on #6897 first; a one-line date bump is not a renewal. This is a review-time rule: the lint treats `expires_on` as a clock only and does not enforce the cap.

## Amendment 2026-10-13 — no workflow rotate after the first flip attempt (#10175)

**Decision.** `git-data-host-rotate` is refused once any run of `git-data-cutover.yml` has executed the
`Write GIT_DATA_STORE_ENABLED` step (any conclusion other than skipped, in any attempt). After a flip the LUKS volume
may hold the only copy of the replicated repositories, and the rotate's emptiness check read a once-per-boot row that
a flipped store never refreshes. The guard reads run records, not the flag and not the cutover stamp (the stamp
survives a rollback, and rollback is flag-off only, so a rollback does not make the store clean). It needs no prd
Doppler token in the apply workflow (alternative G above stands). It proves the history is complete by pinning two
post-seam runs that must stay listed and readable: run records can be deleted (the retention horizon is unknown: run
records 196 days old are still listed today) and GitHub strips step lists at about 170 days, so the guard fails closed
by about 2027-03-18 at the latest until a PR re-baselines the pins (and, because the scan reads every listed run, until any
older post-seam run whose step list was stripped is deleted or attested; the standing policy is tracked in #10216). A second layer requires the newest `boot_complete` row to be newer than the current
server's creation. Ruled by CTO agent, 2026-10-13 (CPO sign-off with conditions; CLO: no Art. 17/32 conflict while it
guards only the automated rotate, with a key-compromise break-glass).

**Consequences.** From the first flip there is no in-workflow route to rotate `GIT_DATA_LUKS_KEY`: a suspected
key compromise is an owner-run break-glass (a reviewed PR that lifts the guard for one dispatch, owner and CLO
reviewing), and the accepted Art. 17 residue (erased means unlinked) is re-evaluated by 2026-11-12 with the
plaintext-volume outer retention. The exits are #8571 (copy mode) for a populated store and #10211 (a live
"store measured empty" marker). The guard does not defend against a hostile owner, a flag set outside the workflow, or
a re-run of a rotate run that predates it (the owner deletes those run records). Follow-ups: #10216.

## Amendment 2026-10-13 — first boot may precede the volume attachments (#10138)

**Context (measured 2026-10-13: the apply log of run 38384137515 and Sentry; nothing was read from a
host).** Cloud-init first boot starts when the server is created; Hetzner attaches block volumes
afterwards as separate actions. Terraform recorded the LUKS attachment finishing 65 s and the
plaintext one 125 s after server create. Those are API-completion times, not the moment the guest
first saw each device. The bootstrap ran at 10:37:11Z, and a FATAL in the `luks_open` heredoc aborts
the concatenated runcmd script (read from the template, 2026-10-13), so by inference the heredoc had
already found, formatted and opened the LUKS device 7 s before Terraform recorded that attachment
finishing: the figures overstate guest-side latency, and this incident does not by itself show that
the heredoc's 30 to 300 raise was needed (it is kept as insurance). Sentry shows the bootstrap's plaintext check dying at
10:37:11Z, about 70 s before the plaintext attachment completed at 10:38:19Z: it resolved the by-id
link once and exited at the named FATAL `plaintext_unverified reason=source`. Four earlier boots
(runs 38140050880, 36118115758, and the seed and payload phases of 38356246710) attached both
volumes in 17-33 s as Terraform recorded them, so the race was latent. The boot was fail-closed and
wrote no marker (inferred from the code order, not read from a host); that nothing was served
rests on the store flag being off (inherited from #10175, 2026-10-13).

**Decision.** Waiting for an attachment is part of proving a layout. The bootstrap waits at the
plaintext link for 300 s: 30 passes of `sleep 10`, counted and never read from the clock (so 300 s is a
lower bound; each pass's probes add to it), a literal rather than a seam. The `luks_open` heredoc's device wait is 300 counted passes of
`sleep 1`, followed by one `udevadm settle` before the single-shot probes that gate `luksFormat`.
The wait changes WHEN the device is resolved, never what is checked: after the bound the same named
FATAL fires, the plaintext-empty verification is never skipped, and the device number is still
pinned and re-checked before `--setro`. A FATAL inside the heredoc aborts the concatenated runcmd
script, so the bootstrap never runs after it (read from the template, 2026-10-13). The bootstrap's
own LUKS discovery is unchanged: it runs only when the store is not yet mounted, which the heredoc
has already ensured on a first boot. The rung-2 rehearsal now delays both attachments on purpose
(LUKS by floor(delay/2) s, plaintext by the full delay; the workflow sets 150), so the paid run
exercises the heredoc wait and the bootstrap wait. One rehearsal at 150 s does not prove the 300 s
bound, and that a PASS implies the wait ran is an inference: no `boot_complete` field records it.

**Consequences.** The payload hash moves, so the committed rung-2 evidence is stale until a fresh
rehearsal and an evidence-only PR land, and the rotate's own interlock refuses until then. This
amendment does not change the status line, the retention date or any legal wording, and makes no
claim about key escrow. The recovery order and the half-rotated host are in the runbook entry of
the same date.

## Amendment 2026-10-14 — pointer: the empty-id rehearsal moved to PR-R, and the wipe mechanism PR is not hash-bound (#10138)

Appended; nothing above is edited. The Consequences bullet "The wipe branch needs a rehearsal of its own" and the 2026-10-12 amendment's blocker chain ("a hash-bound wipe PR with its own rung-2 rehearsal, then the wipe itself") describe a sequence that the built work does not follow, by a CTO ruling of 2026-10-14 (`knowledge-base/project/specs/archive/20261015-113544-feat-one-shot-10138-git-data-wipe-body/decision-challenges.md`, row "PR-W scope").

- **The wipe mechanism PR (#10294) is not hash-bound.** It adds a workflow job, a runner-side Hetzner helper and a host verb that the runner sends over stdin (`git-data-cutover.sh` `MODE=wipe_assert`, `git-data-wipe-assert.sh`). None of them is part of the rendered `user_data` or of a `file()`-bound payload, so the rung-2 template hash does not move and this PR carries no rehearsal.
- **The empty-id rung-2 rehearsal moved to PR-R (#10296).** The render branch selected by an empty `git_data_volume_id` is first rendered by the record PR (PR-C) that removes `hcloud_volume.git_data`, so the rehearsal binds PR-C only. PR-R must merge before PR-C, not before the wipe, and should be on `main` before the wipe is dispatched because it needs a paid host. The requirement that the branch be rehearsed before it can reach the live host is unchanged; where it lives is what moved.
- **What the owner records before the dispatch.** The runbook ("The wipe", "Before naming `mode=wipe`") has #6897 carry the link to a READY PR-C, the main-dispatched empty-id rehearsal evidence (PR-R) or a recorded owner acceptance of a longer wedge, and the dispatch-to-merge bound. The alternative to the evidence is the CTO's wording of that ruling, not an addition of this note, and no workflow checks any of the three.
- **Unchanged.** The 2026-11-12 outer date, the CLO re-ruling due 2026-10-24, and the rule that moving the ledger `expires_on` past 2026-11-12 needs a CLO re-ruling linked on #6897.

## Amendment 2026-10-15 — the plaintext-volume wipe is separated from the flip chain (#6897, #10138)

Appended; nothing above is edited, and the three sentences it supersedes carry a marker directly beneath them. Takes effect when the carrying PR (#10352) merges, and #10352 was gated on the CLO re-attestation (task A.11, CTO ruling 2026-10-15 on the PR topology), recorded 2026-10-15; #10294 (the wipe mechanism) merged 2026-10-15T12:32:44Z, a8dffdedd5 (read from GitHub), and did not activate it. Until #10352 merges, the chained gate in the Amendments of 2026-10-09 and 2026-10-12 is the operative text.

Ruled by CTO agent, 2026-10-15 (separability, replacement predicates, schedule; follow-up ruling on the leftover-snapshot clear and the post-flip barrier). Ruled by CLO agent, 2026-10-15; v1 internal attestation, re-attested as final 2026-10-15 (A.11) (the soak is not a legal gate for the separated variant; evidence record; notice dates). Both rulings are posted on #10138 and recorded in `knowledge-base/project/specs/feat-one-shot-10138-git-data-wipe-body/decision-challenges.md`.

**Decision.** The wipe of `hcloud_volume.git_data` has two variants, chosen in-session from reads and never by an input:

- **`flip_chained`** (flag `GIT_DATA_STORE_ENABLED` is `true`, or the stamp `GIT_DATA_LUKS_CUTOVER_AT` is present): today's gate unchanged: flag true, stamp present, 7-day soak (`WIPE_SOAK_FLOOR_SECONDS=604800`, pinned), stamp newer than the last rollback. There is no soak-less fall-through after a flip.
- **`separated`** (flag read successfully and exactly `false` or unset, AND stamp absent): (1) `git_data_store_dirty_scan` returns `store_clean` (run records, with the current run's attempt excluded); (2) the newest `boot_complete` for `soleur-git-data` is newer than the current server's creation with `served_repos=0`; (3) the typed volume id is attached to the current server; (4) the on-host read-only count `store_root_repos=0` of the LUKS store root. Anything else refuses with a named verdict.

Unchanged for both: typed volume id equal to what Hetzner names, same-session host reads, the Hetzner re-read before the delete, the ID-pinned delete, the 404 read-back as the end event, the reviewer-gated environment (one reviewer; self-approval not prevented, #10343 item 2, reported 2026-10-15; not a separation-of-duties claim), Tier-B token containment, and the rule that the owner names the exact command.

**Why.** Rollback to the plaintext volume no longer exists (Consequences bullet 1, inherited) and the volume is never mounted writable (D2, policy), so the flip status does not decide whether destroying it loses served data. The flip chain (#8573, #8609, #8209, then a flip, then a 7-day soak) cannot finish before 2026-11-12 (CTO schedule, inferred), and each extra retention day is an Art. 5(1)(e) overrun against our own stated date (policy, CLO). The CLO ruled on 2026-10-13 that the destroy should be separated if it can be.

**Alternatives considered.** (a) Keep the chained gate only: rejected, it cannot meet 2026-11-12 (inferred). (b) Drop the soak for every variant: rejected, a flip leaves the store populated and the soak is the engineering gate for that case. (c) Scan alone as the separated barrier: rejected by the CTO follow-up ruling, because after a flip with a failed probe and a rollback the flag is false and (once #10297 lands) the stamp is absent, and the scan reads run records only; the on-host count is the second, independent barrier.

**State as measured (read-only, 2026-10-15; the 2026-10-12 read of server 169724272 and LUKS volume 107102614 is a past measurement and those ids no longer exist).** Volume 106867358 (`soleur-git-data-store`, created 2026-09-14, no delete protection) is attached to server 170370833 beside LUKS volume 107140231 (created 2026-10-14T14:51:26Z). The newest `boot_complete` for `soleur-git-data` is 2026-10-14 14:52:17Z: `served_repos=0 plaintext_empty=yes plaintext_volume=present plaintext_journal=dirty`. That row is boot-time only: `plaintext_empty=yes` means no repository entry at boot, not no residue.

**Residuals (recorded on #6897, comment 6188355137, 2026-10-15; told to the CLO and attested as labelled, A.11, 2026-10-15).** (1) The run-record scan does not see a flag set by hand in Doppler; the on-host count shows the LUKS store holds no repositories at that moment, not that the flag never flipped (CTO, inferred). (2) The soleur-ai runtime App key residual of #8609 (ADR-241 D2) applies to every Tier-B consumer, including the `wipe` job (inherited from #8609, measured there 2026-09-22). (3) Erased-user `.<id>.init.lock` and `.gc-cursor` residue on the plaintext volume, and any Hetzner snapshot or backup retention, are unmeasured (inherited, Amendment 2026-10-09); the 404 read-back is the end event for the device only. (4) An untrappable kill during the `wipe_check` listing can leave the throwaway `git-data-pt-snap` until an owner-named `snapshot_clear` dispatch (CTO, inferred).

**Unchanged.** The 2026-11-12 outer date; a second slip goes back to the CLO; moving the ledger `expires_on` past 2026-11-12 needs a CLO re-ruling linked on #6897; the CLO re-ruling due 2026-10-24 concerns DPD §10.3(b) and the #10136 items and does not gate this amendment, whose wording was re-attested as final on 2026-10-15 (A.11). Nothing here claims reopen, passphrase-loss recovery (#9948), re-escrow (#9949), the state-restore substrate (#7992), or emptiness for web-2.
