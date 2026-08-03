# ADR-161 — A birth filesystem may only carry features the target image's kernel can mount

- **Status:** Accepted
- **Date:** 2026-08-03
- **Issue:** #7204
- **Related:** [ADR-149](./ADR-149-git-data-host-birth-route-and-readiness-interlock.md) (the birth
  route and its interlocks — this ADR records the filesystem decision that route creates),
  [ADR-147](./ADR-147-boot-stage-diagnostics-live-in-baked-host-scripts.md) — specifically its own
  2026-07-27 addendum §"The divergence that matters: git-data-emit ships INSIDE `user_data`",
  which is the actual carve-out this ADR extends,
  [ADR-152](./ADR-152-strip-rationale-comments-from-git-data-injected-scripts-at-render-time.md) (the
  premise that git-data has no bake path — NOT itself a diagnostics carve-out),
  [ADR-068](./ADR-068-multi-host-workspaces-shared-git-data-lease-coordinator.md) (the store this filesystem backs),
  `apps/web-platform/infra/cloud-init-git-data.yml` (`STAGE=luks_open`),
  `apps/web-platform/infra/git-data-birth-fs-fingerprint.txt` (the classified allowlist)

> **Ordinal.** THREE collisions while this branch was open. Provisionally 158 at plan time;
> 158 -> 159 after `ADR-158-kb-file-tree-host-is-a-derived-value.md` landed on `origin/main`;
> then 159 -> **161** at review time after `ADR-159-delivery-is-not-activation.md` (PR #7146)
> ALSO landed on main, and 160 turned out to be claimed by unmerged sibling branch
> `feat-one-shot-7159-doppler-prd-read-token-coverage`. 161 was verified free against both
> `origin/main` and every remote branch, not merely against main's maximum — checking only
> main is what let the second collision through. Renumbered MINE, never main's: applied only
> to this feature's own artifacts, and deliberately NOT to the plan lines that use a blanket
> `s/ADR-158/.../g` as the worked example of the sweep this rule forbids.

## Context

`soleur-git-data` will hold every connected user's source code. It has never been born. Its
birth is gated on a rung-2 boot rehearsal, and that rehearsal died three times.

The cause was in the birth itself. `cloud-init-git-data.yml` created the store with:

```
mkfs.ext4 -q -O quota,project /dev/mapper/git-data
```

That sets the ext4 `quota` RO_COMPAT superblock feature. On **every** subsequent mount,
`ext4_fill_super` calls `ext4_enable_quotas()` whenever `ext4_has_feature_quota(sb)` holds
(v6.8 `fs/ext4/super.c:5567`) — gated on the feature bit **alone**, never on the mount options,
so the template's deliberate decision not to pass `prjquota` never mattered. That reaches
`find_quota_format(QFMT_VFS_V1)`, which returns `NULL` when no quota format is registered and
`request_module()` cannot load one; `dquot_load_quota_sb` then returns `-ESRCH`, `mount(8)`
prints `mount(2) system call failed: No such process` and exits 32, and the stage's trap fires.

Ubuntu builds that format as a **module** (`CONFIG_QFMT_V2=m` on amd64; `CONFIG_QUOTA=y`), so
`quota_v2.ko` must exist on disk — and it ships only in `linux-modules-extra-*-generic`, which
the Ubuntu 24.04 server cloud image does not install. Manifest
`ubuntu-24.04-server-cloudimg-amd64.manifest`, 664 packages, re-fetched 2026-08-03: kernel
`6.8.0-136-generic`, `linux-image-virtual` and `linux-modules-6.8.0-136-generic` present,
`linux-modules-extra-*` **absent**, the `quota` userspace package **absent**.

The fleet provides a natural experiment. The two production LUKS stores that mount successfully
on this same image — `cloud-init-registry.yml` (the zot store) and `workspaces-cutover.sh`
(`/workspaces`) — both `mkfs.ext4 -q` with no quota features. git-data was the only store that
set them, and the only one that failed at mount.

**The decision was never recorded anywhere.** It lived in a code comment (`#6982 W5/R31`) whose
stated rationale — that the flags are migration-forcing, so they must ship at birth — was
itself false, and it was pinned by a test (`git-data-luks.test.sh` B16) whose first mutation arm
was literally `s/-O quota,project/-O project/`: the correct fix, encoded as the drift to catch.
A migration-forcing choice on the store that will hold every user's source code deserves an ADR.
This is it.

## Decision

**The git-data birth filesystem is created with only features the target image's kernel can
honour.** Concretely:

```
mkfs.ext4 -q -O project /dev/mapper/git-data
```

The governing invariant, stated so it outlives this particular flag:

> The birth filesystem's **mount** must depend on no kernel module that is absent from the
> target image.

`project` satisfies it. `ext4_enable_quotas()` is gated on the quota bit, not on `project`, so
`project` alone loads no module. The only project-related mount refusal in `super.c` sits under
`#if !IS_ENABLED(CONFIG_QUOTA) || !IS_ENABLED(CONFIG_QFMT_V2)`, and `IS_ENABLED()` is true for
`=m`, so on this kernel that block is compiled out.

**Project-quota enforcement is deferred**, and deferred honestly: `-O project` gives the
project-ID inode field, not enforcement. Enforcement additionally needs the `quota` feature, the
`quota` userspace package (absent from the image) and a `quotacheck` pass. Re-adding it is a real
future cost — see Consequences.

### The premise correction, recorded because it is why the defect existed

B16's comment and the template's comment both asserted the feature set was **migration-forcing**:
"adding it later needs a replace PLUS an rsync of every user's objects". `tune2fs(8)` sets and
clears both features on an unmounted filesystem, so that was false — and **that false belief is
why an unmountable feature set was pinned onto a store that did not yet exist.** Recording the
decision change without the premise correction would leave the reasoning that produced the bug
intact for the next author.

But the correction has a sting, measured rather than assumed (see Alternatives (b)): `tune2fs`
is not the free later-addition path it appears to be either. So the honest statement is narrower
than "the flags are addable later": **`quota` is addable later; `project` is not addable without
also adding `quota`** — and adding `quota` on this image is what makes the volume unmountable.

**What this does NOT establish, corrected at review.** An earlier revision of this ADR argued
that (a) beats (c) because (c) "discards `project` permanently". That is refuted by this ADR's
own measurement table two paragraphs below: `tune2fs -O project` on a plain filesystem succeeds
(rc=0). From state (c), `project` is one offline command away — not permanent. And the argument
is self-defeating in the scenario it was built for: the only future in which `project` is
*wanted* is one in which enforcement is possible, which requires an image whose kernel can mount
`quota` — which is exactly the future in which (c)'s upgrade path is open.

The honest, much smaller residual advantage of (a): it buys free optionality on the project-ID
inode field at **measured-zero present cost**, and it avoids a future maintainer reaching for the
`tune2fs` path and bricking the mount. That is enough to select it. It is not a claim that (c)
forecloses anything permanently.

## Alternatives Considered

The canonical five-candidate set. Every candidate carries its Phase-0 disposition; measurements
were run 2026-08-03 in `ubuntu:24.04` (e2fsprogs 1.47.0 — the image's own version) on a 10G
sparse file, and under a privileged container over a real loop device for the mount arms.

| # | Candidate | Measured | Disposition |
|---|---|---|---|
| **(a)** | `mkfs.ext4 -q -O project` | features `… metadata_csum project`, **no `quota`**; mounts rc=0, write canary OK | **SELECTED** |
| (b) | `tune2fs -O quota` / `-O project` as a later-addition path | `tune2fs -O quota` on a project-only fs → rc=0 but **`project` CLEARED**. `tune2fs -O project` on a plain fs → rc=0 and **`quota` ADDED implicitly** | **REJECTED as a fix; recorded as an operational hazard.** Adding `project` later would set the exact bit that makes the volume unmountable |
| (c) | `mkfs.ext4 -q` (sibling parity) | features `… metadata_csum`, neither flag; mounts rc=0 | **REJECTED in favour of (a), on a narrow margin.** Equally safe, simpler, and matches the two working siblings. (a) wins only because it buys the project-ID field at measured-zero present cost and keeps a future maintainer away from the `tune2fs -O project` path, which per (b) re-bricks the mount. NOT because (c) forecloses `project` permanently — it does not (see Decision) |
| (d) | keep `quota,project` + `mount -o noquota` | mount returned rc=0 — **on a kernel that HAS `quota_v2`**, so the probe cannot discriminate "the option escaped the enable path" from "the enable path ran and succeeded" | **REJECTED** on the feature-bit argument. `ext4_enable_quotas()` is gated on the bit, not the options; upstream changed quota mount options to be *ignored* when the feature is set. The rc=0 is recorded as **non-discriminating**, not as a pass |
| (e) | keep `quota,project` + `apt-get install linux-modules-extra-$(uname -r)` at boot | not run | **REJECTED a priori** by criterion **(ii)** — it buys a capability that is unusable anyway (no `quota` userspace, no `prjquota` mount option) — and by **(iii)**, since it *satisfies* the image's module set rather than removing the dependency, so its correctness stays hostage to the image |

### The selection rule, and how criterion (c) was discharged

A candidate had to **(i)** produce a filesystem whose mount does not depend on `quota_v2`,
**(ii)** preserve the most future capability at zero present cost, and **(iii)** be correct
**whether or not** the assumption "Hetzner's `ubuntu-24.04` is the stock Canonical cloud image"
holds. (Deliberately numbered (i)-(iii): an earlier revision lettered them (a)-(c), colliding
with the candidate labels in the table above, and then mis-cited (e)'s rejection to the wrong
one.)

**Criterion (iii) is discharged BY CONSTRUCTION, not by a mount observation, and this ADR must
not claim otherwise.** Every mount probe available runs in a container, which shares the host kernel —
and this host's kernel *has* `quota_v2`. A green mount there cannot distinguish "needs no module"
from "the module happened to be present". So (iii) is discharged as a feature-bit argument read out
of `fs/ext4/super.c`, with mount rc demoted to a sanity signal.

A container-side simulation was considered and **rejected on inspection**: `find_quota_format`
reaches the loader via `request_module()` → `call_usermodehelper`, which runs in the **init
namespace**, so a container's `/etc/modprobe.d` is never consulted. This was then observed
directly — inside the container `/lib/modules/$(uname -r)` contained no `quota_v2` at all and the
arms still mounted, because the *host's* module loaded. Simulating the target needs a VM.

## Relationship to ADR-147 and ADR-152

[ADR-147](./ADR-147-boot-stage-diagnostics-live-in-baked-host-scripts.md) freezes boot-stage
diagnostic-capture logic in **baked host-scripts**, so that the diagnostic path is versioned with
the image rather than with `user_data`. The change accompanying this ADR adds capture logic
(a stage detail file, an ordered `dmesg` + stderr capture) to `user_data`, which is in tension
with that rule on its face.

The tension resolves through [ADR-152](./ADR-152-strip-rationale-comments-from-git-data-injected-scripts-at-render-time.md):
git-data has **no baked image**. It is a cloud-init-only host with no `remote-exec` provisioner and
no host-scripts bake step, so ADR-147's vehicle does not exist here. This ADR therefore **extends
ADR-152's carve-out** rather than contradicting ADR-147: for git-data specifically, boot-stage
diagnostics live in `user_data` because there is nowhere else for them to live, and the cost is
paid against the 32 KB `user_data` ForceNew cap. **Delta, because a cap is only legible as a
delta:** ADR-152 recorded `stored=20456`; `origin/main` is `22772`; after this change
`stored=25872 / cap=32768`, headroom **6896**. The review pass that added this table also
collapsed ~2 KB of duplicated rationale prose out of the template — ADR-152 strips comments
only from the nine injected `write_files` scripts, NOT from the inline `runcmd`, so comments
in this template are NOT free and the belief that they are is what consumed the headroom.
If git-data ever gains a baked image, the capture logic moves and this carve-out retires.

### ADR-147's other three constraints, checked rather than assumed

ADR-147 freezes **four** cross-consumer constraints, not one. The section above addresses only
LOCATION, so the remaining three are recorded here — "ADR-147's vehicle does not exist here"
must not be read as "ADR-147 does not bind git-data", which is false for three of its four.

| ADR-147 constraint | Status under this change |
|---|---|
| Location (diagnostics in baked host-scripts) | The carve-out above — git-data has no bake path |
| **Stage names are frozen** (they are alert filter values) | **Live and respected.** `apps/web-platform/infra/sentry/issue-alerts.tf` filters `value = "luks_open"`. This change does not rename the stage, so the alert keeps matching. Renaming it would silently unhook the alert |
| Single emitter, so the redaction guarantee is structural | Respected — the new `dmesg`/stderr capture is an unbounded-content SOURCE, but it reaches the wire only through `git-data-emit`, whose `_devalue` + `_clean` chain is unchanged. That matters here specifically: this host's repo paths are `<workspace_id>.git` and `workspace_id === auth.users.id`, which is why the bare-UUID rule exists |
| No shared cross-stage buffer | Respected — `/run/git-data-luks-stage.log` is per-stage, read only by `luks_err`, and mode 0600 |

## Consequences

**Good.**
- The birth can succeed. This was the only mechanical blocker on the rung-2 rehearsal, which is
  the only route that can produce the evidence the birth gate requires.
- The invariant is now guarded at two layers with **AP-018's SHAPE, and its defining clause
  explicitly NOT satisfied** — AP-018 says the static layer is "never coverage-bearing", and here
  it is, on any machine without docker. Stated as a deviation rather than filed under the bare
  label. **R1** in
  `git-data-runcmd-rehearsal.test.sh` is authoritative — it creates the filesystem and classifies
  the resulting superblock against a committed allowlist — and **B16** in `git-data-luks.test.sh`
  is a static pre-filter over R1's preconditions. With the caveat that makes it honest: the rung-1
  suite self-skips without docker, so **on a docker-less machine B16 is the only coverage there
  is**. CI is the only environment where both run. R1 is authoritative *when it runs*.
- The allowlist is fail-closed against the *class*, not just this flag. A future feature that
  introduces a mount-time module dependency fails R1 as "unclassified — classify it before
  shipping", rather than sailing through a one-entry denylist.

**Bad, and load-bearing.**
- **Selecting (a) is what puts a silent capability loss on the map.** From the *selected* state,
  the plausible "add enforcement later" move is `tune2fs -O quota` — measured to CLEAR `project`
  while also setting the unmountable bit. (c) has no such trap. This is the cost of (a)'s
  optionality and is recorded so the next author meets it here rather than on a dark host.
- **Project-quota enforcement is not available and is not cheap to add.** Because `tune2fs -O
  project` implicitly sets `quota`, the store cannot gain enforcement by an offline `tune2fs` on
  this image: doing so would make it unmountable. Enforcement requires the image to ship
  `linux-modules-extra` (or a kernel with `CONFIG_QFMT_V2=y`) **and** the `quota` userspace
  package, and only then a `tune2fs` + `quotacheck`. Tracked as a follow-up, not assumed free.
- The fixture carries a provenance expiry that must be re-measured against the **real** image's
  e2fsprogs when the host is actually born — the current baseline is measured in `ubuntu:24.04`,
  which is an inference about the image, not an observation of it.

**Neutral.**
- The feature allowlist is deliberately **not** a set-equality fingerprint. Measured: the same
  `mkfs -O project` differs by two features (`orphan_file`, `metadata_csum_seed`) across one
  e2fsprogs patch release, and `ubuntu:24.04` is a moving tag. Equality would red on a benign
  bump, and the remedy an author reaches for is "refresh the fixture" — training exactly the
  rubber-stamping the guard exists to prevent.

## What would falsify this

If Hetzner's `ubuntu-24.04` image turns out to ship `linux-modules-extra` after all, the *mechanism*
recorded here would be wrong — but the decision would not change, because (a) removes the module
dependency rather than satisfying it. The first real evidence either way is the rung-2 rehearsal
against the corrected template, which is a separate operator dispatch and is deliberately not
performed by the PR that carries this ADR.
