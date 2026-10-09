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

- Plan: `knowledge-base/project/plans/2026-09-22-feat-git-data-cutover-real-modes-plan.md`
- Decision challenges (DC-1, DC-2):
  `knowledge-base/project/specs/feat-one-shot-8211-git-data-cutover-real-modes/decision-challenges.md`
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
- **What was already written is a different question.** `git_data_host_replace` ran on 2026-10-08 (workflow
  run 37846545572, head `d0b5d2e35b`, which contains #9226), so erasures since then are expected to write only
  the shared lock; that was read from the run and its head, not from the host. Both volumes were preserved
  across that replace. Per-id `.<id>.init.lock` files from earlier erasures therefore remain where they were
  written: on the retained plaintext volume for erasures before PR #8564 (host birth, 2026-09-14), and on the
  LUKS-served store for erasures after #8564 and before the replace. No count sees them (the counters skip
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
  repo root, and a later run that completes a repo overwrites it. The timer is weekly (Sunday 03:20), so after
  an erasure the erased id can remain there for up to a week, and indefinitely if no repo remains on the store
  to be completed. Neither the new check nor the in-freeze purge covers it. Closing it changes a hash-bound
  payload (`git-data-gc.sh`, or the remove wrapper clearing a matching cursor), so it needs the rung-2
  two-PR sequence and is not part of this change; it is recorded on #9066.
- **The date is a target, not a fact.** The wipe body was deleted from `git-data-cutover.sh` in #8189 (landed
  via PR #8206) and does not exist on main. It will be a hash-bound PR with a rung-2 rehearsal of its own (see
  the Consequences bullet on the wipe branch), and it is gated by the flip chain (#8573, #8609, #8209 and a fresh
  replace). **If the date will pass with the volume present, this amendment is re-opened together with the ledger
  exception and the CLO before 2026-10-23, the first day the ledger lint fails; the date is not extended
  quietly.** Until the volume is deleted, the files remain readable to anyone holding the volume or a snapshot of
  it. The lint warns inside 14 days of `expires_on` and fails CI after it.
- **Inputs for the CLO re-ruling.** The issue sets the trigger: if the fix and the served-store purge slip past
  2026-10-24, the CLO re-rules on the DPD §10.3(b) disclosure. The re-ruling needs the state of three things: the
  wipe (done, with Hetzner delete evidence, or slipped), the served-store purge (run, with its count, or not),
  and the flip (slipped, so the wipe, which is gated behind it, has not been reached).

Alternatives considered and rejected: purging the files in place by mounting the volume (violates D2); a
standalone dated purge (needs the same writable mount); extending the date without re-opening this ADR
(storage limitation; the ledger records `expires_on` as deliberately not extended).

Plan: `knowledge-base/project/plans/2026-10-09-fix-git-data-lock-no-subject-id-9066-plan.md`.
