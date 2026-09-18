---
title: "Phase 0.5b measurements — ADR-142 additive blue-green LUKS apparatus"
date: 2026-09-18
branch: feat-one-shot-adr142-inngest-aof-luks-bluegreen
---

# Phase 0.5b measurements

The plan (`## Research Insights` → *Vendor semantics, verified rather than assumed*) lists three
behaviours documentation could not settle and assigns them to Phase 0. Phase 0 recorded none of
them — the PR body was still the auto-created stub and the spec directory held only `tasks.md`.
This file is where they live, because the resolver and the cutover script are built on them.

All three were measured on 2026-09-18 on the operator workstation against a **real** LUKS2
dm-crypt mapping (`omarchy_root` on `nvme0n1p5`), not a fixture. The Inngest host itself cannot be
reached for this: it has no SSH and no inbound channel.

## 1. Does `blkid -p` require root? — YES, and it fails *into* the blank code

```
$ id -un; id -u
jean
1000
$ ls -la /dev/nvme0n1p5
brw-rw---- 1 root disk ...
$ blkid -p -o value -s TYPE /dev/nvme0n1p5; echo "rc=$?"
blkid: error: /dev/nvme0n1p5: Permission denied
rc=2
$ blkid -o value -s TYPE /dev/nvme0n1p5; echo "rc=$?"
rc=0
```

**Unprivileged `blkid -p` returns rc 2 — the same code as "no signature found" — on a device that
carries a LUKS2 header.** Unprivileged cached `blkid` is worse: rc 0 with empty output.

The live `#7695` stage's policy is "accept rc 0 or 2; an EMPTY type is positive proof of blankness,
route it to `luksFormat`". Under that policy, an unprivileged probe reads a populated store as
blank and selects the one destructive, unrecoverable arm. The `Permission denied` goes to stderr,
which the stage discards with `2>/dev/null`.

**What it decides.** "The probe could measure" must be *asserted*, not assumed. Every script that
routes on a `blkid` result asserts `id -u == 0` before the first probe and refuses otherwise. Today
every consumer happens to run as root (cloud-init `runcmd`, the boot-reopen unit, the cutover root
oneshot), so nothing is exposed yet — but that is a fact about the callers, and this change adds
readers.

## 2. The authoritative read of a mapper's backing device — sysfs `slaves/`

```
$ readlink -f /dev/mapper/omarchy_root
/dev/dm-0
$ ls /sys/class/block/dm-0/slaves
nvme0n1p5
$ cat /sys/class/block/dm-0/dm/name
omarchy_root
$ cut -c1-12 /sys/class/block/dm-0/dm/uuid
CRYPT-LUKS2-
$ lsblk -nro PKNAME /dev/mapper/omarchy_root     # returned EMPTY
```

`/sys/class/block/<dm-N>/slaves/` names the kernel device underneath the mapping, is readable
unprivileged, and has no cache. `dm/name` names the mapping and `dm/uuid` carries a `CRYPT-LUKS`
prefix for a dm-crypt mapping. `lsblk -nro PKNAME` against the `/dev/mapper/` path returned
**empty** in the same session, so it is not used.

**What it decides.** The resolver's positive control (task 3.4) resolves both links through sysfs:
`findmnt -no SOURCE <mount>` must be the expected mapper, and that mapper's single `slaves/` entry
must equal `basename "$(readlink -f <by-id path>)"`. Neither link alone proves which block device
sits under a path.

## 3. Does starting Redis on a copy mutate it? — settled by design, not re-measured here

The plan's Fork C already deleted the canary that would have started Redis on the copy, on the
grounds that it mutates the copy. With that mechanism gone the question no longer gates anything,
so it was not re-measured. Recorded so the gap is visible rather than implied closed.

## Phase 0 facts carried in from the resume brief (measured 2026-09-17, not re-derived)

| Task | Reading |
| --- | --- |
| 0.1 user_data budget | stored 10888 B / cap 32768 B, headroom 21880 B (comment-strip 91997 → 30614 **before** gzip) |
| 0.2 ADR ordinal | highest is ADR-224; ADR-142 is amended, no new ordinal claimed |
| 0.3 cutover environment | `github_repository_environment.inngest_cutover` reviewers = `["deruelle"]`, non-empty |
| 0.5 probe row | host `hetzner-166317708`, `host_role=dedicated`, `probe_schema=8`, `data_mount_devid=scsi-0HC_Volume_106261946` |
| 0.6 stop gate | `redis_keys=442` (expires=431) — **not zero**, so the additive build is the right instrument and ADR-199 G13 refuses the recut permanently |

0.4 (`INNGEST_CUTOVER_FLIP`) is not recorded in the brief and is not re-read here: reading it is a
credentialed production read, and the value that matters is the one at dispatch time, which the
`inngest_host_replace` preflight added in #8252 now reads and warns on.
