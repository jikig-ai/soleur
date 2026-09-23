---
title: "ADR-239: git-data serves its store from LUKS at birth"
status: adopting
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
- **The dirty-journal `noload` gap is real and accepted.** The rung-2 rehearsal's plaintext volume
  is freshly formatted, so it never boots the production case: a volume last mounted read-write by
  a destroyed host, with a dirty ext4 journal. If `mount -o ro,noload` then refuses it, step 2
  fails closed as `plaintext_unverified` on the first production boot the rehearsal could not
  reproduce. The failure is safe — read-only, data retained, no marker written — and its recovery
  is written down, but the rehearsal cannot pre-empt it.
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
