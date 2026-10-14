---
title: "Counsel review audit — #5274 / PR #8711 (git-data plaintext count reads the retained volume through a dm snapshot: PA-36 (g) two MECHANISM-ONLY supersede markers and one boot_complete addendum)"
type: counsel-review
date: 2026-09-24
issue: 5274
pr: 8711
head_reviewed: 9ace7e8657
status: SIGNED-OFF (CLO-agent-attested, Soleur-as-tenant-zero v1)
signed_off_at: 2026-09-24
signed_off_by: "CLO agent (attestation authority for the Soleur-as-tenant-zero v1 posture; the operator retains an optional veto)"
disposition: "DISCHARGED. Three corrections were applied in-cell by the CLO agent before sign-off (E1–E3 below), all to text this PR inserts; no pre-existing marker was rewritten. One artifact in scope: knowledge-base/legal/article-30-register.md, PA-36 (g). The diff to it is three insertions: a [Superseded 2026-09-24 (#5274), as to MECHANISM ONLY] marker under (1), a second one under (2)(ii), and a [2026-09-24 ADDENDUM (#5274)] recording the boot_complete field plaintext_journal. All three are conditioned on the merge of PR #8711. It touches no Status cell, no docs/legal/** file and no Eleventy mirror. Every implementation claim was checked against the shipped code: git-data-bootstrap.sh (the plaintext-count unit, log(), the marker writer, the boot_complete emit), cloud-init-git-data.yml, git-data.tf, git-data-plaintext-snapshot-loopback.test.sh, the infra-validation.yml step and the ADR-239 amendment 2026-09-24. The plan was not the source. Three phrases were inaccurate. (E1) The register said the kernel read-only flag 'lasts for that boot'; a detach also drops it. (E2) It said 'same … data the former mount already read'; the former noload mount skipped the journal, and reading the journal is the point of the change. (E3) It gave an exhaustive-reading list of what FATAL detail carries and said 'never … directory names'; FATAL detail also carries device paths, including the private mount directory, and error counts. The mechanism-only characterisation holds: same purpose, host, processor (Hetzner) and volume; no new recipient, transfer or retention class. The COW-in-RAM disclosure is accurate, including the teardown-failure case. No published legal document needs a change. No Art. 33/34 event."
blocking_findings: []
applied_corrections:
  - "E1 — (1) marker: 'an in-memory flag that lasts for that boot' → 'an in-memory flag that a reboot or a detach of the volume drops' (code comment above the unit: 'a reboot or a detach/reattach drops it'; ADR-239 amendment: 'lost on reboot and on detach/reattach'). The old wording overstated the backstop."
  - "E2 — (2)(ii) marker: 'within the same purpose, host, processor and data the former mount already read' → 'within the same purpose, host and processor and on the same volume the former mount read (the replay also reads that volume's own journal, which `noload` skipped; no new category of data)'. The former `mount -o ro,noload` did not read the journal. The new mechanism reads it by design (ADR-239 alternative J: noload 'can miss an entry that exists only in the journal')."
  - "E3 — (2)(ii) marker: 'FATAL detail carries a classifier word (…), device-mapper status numbers and sector counts, never kernel log lines or directory names' → 'FATAL detail carries device paths, a classifier word (…), device-mapper status numbers, error counts and sector counts, never kernel log lines or any name read from the volume'. The reason=umount and reason=source messages print $_pt_mnt, a /dev/shm/tmp.* directory. The reason=journal messages print errors_count values. The privacy-relevant guarantee is that no name read from the volume leaves the host, and the new wording now states exactly that."
optional_precision_notes:
  - "O1 — 'the host has no swap' (the (2)(ii) marker and ADR-239) is a configuration fact, not a runtime assertion. cloud-init-git-data.yml has no swap module, mkswap or swapon, and the bootstrap's own comments call it a 'no-swap box'. Nothing in the unit refuses to run if swap is present. If swap is ever added to this host, tmpfs pages of the COW could reach disk and the 'never written to disk' sentence would become false. This is listed as a re-evaluation trigger, not a condition."
  - "O2 — '(seconds)' for the COW's lifetime is a characterisation, not a bound. dmsetup create and remove carry 60 s timeouts, but the mount (which runs the journal replay) and the count do not. For a data=ordered journal on a volume of this size, seconds is the realistic order. Non-blocking."
  - "O3 — On a teardown failure, the file is not the only thing that can remain: the read-only snapshot mount can too, under a root-only 0700 mktemp directory in /dev/shm. It exposes the same post-replay tree to root on the same host. The FATAL text says 'the snapshot apparatus may still be live'. The register's paragraph is scoped to the COW file and is accurate as scoped. The residual is the same data on the same host with no new recipient. Non-blocking."
  - "O4 — The (2)(ii) marker's list of refusals ('a LUKS device, one with holders, or a snapshot left by a previous run') leaves out 'or no sysfs entry', which the code also refuses (reason=source). It also does not repeat the device-number re-checks or the `dmsetup deps` check, which 'pins its device number' summarises. These are omissions of additional fail-closed checks, not over-claims. Non-blocking."
attests:
  - "knowledge-base/legal/article-30-register.md — PA-36 (g), the three 2026-09-24 insertions added by PR #8711 ONLY, as corrected by E1–E3"
does_not_attest:
  - "knowledge-base/engineering/architecture/decisions/ADR-239-git-data-serves-from-luks-at-birth.md (engineering record; relied upon, and consistent with the register after E1–E3)"
  - "The runbooks, the rung-2 rehearsal workflow and its seed script (engineering records)"
  - "git-data-bootstrap.sh, cloud-init-git-data.yml and the loopback suite themselves as technical controls (counsel attests what the register says about them, not whether they are correct)"
art_33_triggered: false
art_34_triggered: false
re_evaluation_triggers: "(a) Any swap configured on the git-data host (O1): the 'never written to disk' sentence fails. (b) Any change that sends kernel logs or journald off this host (today git-data runs no Vector agent): re-check that no ext4 message can carry a name read from the volume. (c) Moving the COW off /dev/shm, or making the snapshot persistent (the `N` table flag). (d) The plaintext volume ever being mounted directly, or made writable: (g)(1)'s 'never mounted' and D2 fail. (e) The plaintext volume reformatted with data=journal or a block size below 4 KiB: the COW could then hold file content, not only metadata, and the 'replayed filesystem metadata' sentence must be re-measured. (f) PR #8711 closing unmerged: all three insertions are merge-conditioned and must then be marked as never having fired. Standing external-counsel triggers unchanged: first arms-length user, EEA-out, regulated industry."
---

# Counsel review audit — #5274 / PR #8711 (git-data plaintext count through a dm snapshot)

This file is the evidence for the ship Phase 5.5 Counsel-Review CLO-Attestation Gate on PR #8711
(issue #5274). The PR's plan declares `brand_survival_threshold: single-user incident`, and the
diff touches `knowledge-base/legal/article-30-register.md`. The CLO agent is the v1 attestation
authority; the operator holds an optional veto. The earlier `2026-06-counsel-review-5274.md`
covers a different PR of the same epic and was not edited.

## Scope and limit check

- **Three insertions, one cell.** `git diff origin/main...HEAD -- knowledge-base/legal/` touches
  one line of `article-30-register.md`: PA-36 (g). It adds a MECHANISM-ONLY supersede marker after
  (1)'s 2026-09-23 sentence, a second one after (2)(ii), and an ADDENDUM after the boot erasure
  self-probe paragraph. The older text is only superseded by marker, never rewritten, and the
  2026-09-23 (#8211) markers are untouched.
- **Merge-conditioned, as required.** Each insertion reads "fires on the merge of PR #8711". None
  is written in the past tense about a change this PR itself lands.
- **The NEGATIVE item stays negative.** The (1) marker restates that (1)'s NEGATIVE character and
  its DRAFTED / NOT-YET-ACTIVE status are unchanged, and that the marker asserts no encryption at
  rest today.
- **No published surface.** Nothing under `docs/legal/` or `plugins/soleur/docs/pages/legal/` is
  in the diff. A search of both trees for `noload`, `device-mapper`, `plaintext volume` and
  `snapshot` finds only unrelated "DPA snapshot" references. The published Privacy Policy, GDPR
  Policy and Data Protection Disclosure do not describe the git-data plaintext-count mechanism at
  any level of detail this change would falsify.

## Mechanism-only determination

| Axis | Before (PR #8564) | After (PR #8711) | Changed? |
|---|---|---|---|
| Purpose | Prove the retained plaintext volume holds zero `repositories/` entries before the store-verified marker | Same | No |
| Host | `soleur-git-data` (`hcloud_server.git_data`) | Same. The COW is under `/dev/shm` on that host | No |
| Processor | Hetzner Online GmbH | Same. The only new component is the `dmsetup` package, which has no data flow | No |
| Data read | The volume's on-disk tree via `mount -o ro,noload` (journal skipped) | The same volume's post-replay tree: on-disk tree plus its own journal | Same volume and same category (repository directory entries, which name workspaces). The journal is additionally read, now disclosed by E2 |
| Recipients of output | `boot_complete` / FATAL to Sentry and Better Stack ((d)) | Same, plus the informational `plaintext_journal`, a filesystem-state word that is not personal data | No new recipient |
| Transfers | None (EU, `nbg1`/`fsn1`) | None | No |
| Retention | Transient mount, unmounted immediately | Transient COW in RAM for the count, deleted at teardown; on teardown failure it stays in RAM until reboot or replace (disclosed) | No new class: a transient in-memory copy on the same host, never persisted and never transmitted |

**Determination: mechanism-only.** No Art. 30(1) field changes other than the (g) TOM description.
No Privacy Policy, DPD or GDPR Policy entry is engaged, because no processing activity, legal
basis, recipient or retention period changes.

## Drift table

| # | Claim added | Checked against | Verdict |
|---|---|---|---|
| D1 | (1): from the merge `hcloud_volume.git_data` is never mounted | Plaintext-count unit: the only `mount` targets `/dev/mapper/git-data-pt-snap`. cloud-init writes no fstab line for the plaintext id and carries the "never mounts it either" comment. `git-data.tf` attachment `automount=false` | **Holds** |
| D2 | (1): `blockdev --setro`, read back; "an in-memory flag that lasts for that boot" | Unit: `blockdev --setro` then `--getro` must equal 1. Comment: "a reboot or a detach/reattach drops it". ADR-239: "lost on reboot and on detach/reattach" | **Imprecise (over-states the backstop). Corrected (E1)** |
| D3 | (1): the flag is a backstop; the proof is the before/after written- and discarded-sector comparison, which fails the boot on any change | `_pt_wstat` reads sysfs stat fields 7 and 14 from `/sys/dev/block/$_pt_devno/stat` before `--setro` (`_pt_w0`) and after `_pt_release` (`_pt_w1`). Any inequality → FATAL reason=snapshot | **Holds** |
| D4 | (1): in CI, the before/after hash of the origin in the loopback suite | `origin_sha` hashes the backing file for every arm. Arm W is a write mutant that must FATAL. `infra-validation.yml` runs the suite as root with a 10-minute bound. The suite does not skip silently (it exits non-zero without the device layer) | **Holds** |
| D5 | (1): no fstab line for either; nothing mounts the volume after boot | As D1. The marker-writer comment reads "nothing mounts the plaintext volume after boot" | **Holds** |
| D6 | (2)(ii): resolves the by-id link and pins the device number; refuses LUKS, holders, a leftover snapshot | `realpath -e`, `stat -L -c '%t:%T'`, `_pt_same` re-checked 3×, `dmsetup deps` must name `$_pt_devno`. `cryptsetup isLuks`; `dmsetup info git-data-pt-snap`; `holders` non-empty or absent → FATAL | **Holds** (O4: omits the no-sysfs refusal) |
| D7 | (2)(ii): records counters, then `--setro`, then stacks a non-persistent snapshot with the COW as a file under `/dev/shm` | Order in the unit is `_pt_w0`, then `--setro`, then `mktemp -d -p /dev/shm`, `truncate`, `losetup`, and `dmsetup create … snapshot $_pt_dev $_pt_loop N 8` (`N` = non-persistent) | **Holds** |
| D8 | (2)(ii): "(RAM; the host has no swap)" | `/dev/shm` is tmpfs. No `mkswap`, `swapon` or swap module in `cloud-init-git-data.yml`. The bootstrap comments say "no-swap box" | **Holds as configuration** (O1: not asserted at runtime) |
| D9 | (2)(ii): mounts the SNAPSHOT read-only without `noload`, so the journal replays into the COW | `mount -o ro,errors=remount-ro,nosuid,nodev,noexec /dev/mapper/git-data-pt-snap` has no `noload`. Loopback M1: the origin keeps `needs_recovery`, and its sha is unchanged | **Holds** |
| D10 | (2)(ii): acceptance requires source = snapshot; no `needs_recovery`; not `with errors`; `errors_count` after replay = historical count and unchanged across the count; `repositories` absent or a real directory, never followed; snapshot not invalidated | `findmnt` source compared by `realpath` equality. `_pt_has_nr` on the snapshot superblock. `Filesystem state: … with errors` → FATAL. `_pt_e0 = _pt_eh` (from `FS Error count`, default 0), `_pt_e1 = _pt_e0`. `_repo_count` classifies with `find -printf '%y'` (a link gives rc 2 → FATAL reason=source). `_pt_valid` runs before and after the count | **Holds** (the "historical count, not 0" adaptation is correctly stated) |
| D11 | (2)(ii): the snapshot, loop and COW are removed; the volume's counters must be unchanged | `_pt_release`: umount → `dmsetup remove` → `losetup -d` → `rm -f cow`, collect-then-exit. The `_pt_w1` comparison follows | **Holds** |
| D12 | (2)(ii): any failure is a named `FATAL: plaintext_unverified` (source/snapshot/mount/journal/umount) at `stage=bootstrap`; no marker; `plaintext_residue` unchanged | Every exit in the unit is one of those five reasons, or `plaintext_residue count=` for a non-zero count. `log()` routes `FATAL:*` to `git-data-emit … bootstrap fatal`. The marker is deleted at the top (`rm -f "$STORE_VERIFIED"`) and written only after the unit and step 3 | **Holds** |
| D13 | (2)(ii): the COW holds replayed filesystem metadata, including directory entries | The predecessor mounted the volume `ext4 defaults,nofail` (`b91dcf219b^:cloud-init-git-data.yml`), so data=ordered and the journal holds metadata only. `hcloud_volume.git_data` has `format = "ext4"` (Hetzner mkfs, 4 KiB blocks at this size), so the 8-sector chunk equals the block and no neighbouring data block is copied. Reads through the snapshot do not populate the COW | **Holds** (trigger (e) if formatting or journaling mode ever changes) |
| D14 | (2)(ii): the COW exists only on the git-data host, only for the count, is deleted at teardown; on teardown failure the boot ends `reason=umount` without a marker and the file can remain in RAM until reboot or replace | `_pt_release` sets `_first` on any failed step and exits `FATAL … reason=umount`. `rm -f cow` is skipped while the snapshot is still mounted. If `dmsetup remove` fails, the loop keeps the inode open, so the content stays in tmpfs even though the name may be unlinked. tmpfs clears on reboot | **Holds** (O3: the snapshot mount can also remain) |
| D15 | (2)(ii): never written to disk, never transmitted | tmpfs with no swap (D8). The git-data host runs no Vector agent ("no journald tag on this host ships anywhere", cloud-init comment and `server.tf` delivers `vector.toml` to the web host only). The only off-box paths are `git-data-emit` and on_err's runcmd detail file | **Holds** |
| D16 | (2)(ii): FATAL detail carries a classifier word, dm status numbers and sector counts, "never kernel log lines or directory names"; the count discards `find`'s stderr | `_pt_klass` emits one of four words. `_pt_diag` emits `dmsetup status` field 4 (`used/total` or `Invalid`). Both `find` calls use `2>/dev/null`. But the FATAL texts also carry `$_pt_dev`, `$_pt_link`, `$_pt_mnt` (a `/dev/shm/tmp.*` directory) and `errors_count` values | **Imprecise (list read as exhaustive; "directory names" contradicted by `$_pt_mnt`). Corrected (E3)**. No name read from the volume reaches any message |
| D17 | (2)(ii): "same purpose, host, processor and data the former mount already read" | The former mechanism was `mount -o ro,noload`, which does not read the journal. The new mechanism replays it. ADR-239 alternative J rejects noload because it "can miss an entry that exists only in the journal" | **Inaccurate. Corrected (E2)**. Same volume and category, with the journal additionally read |
| D18 | Addendum: `boot_complete` carries `plaintext_journal` (`dirty`/`clean`/`absent`), informational, not personal data, to the two recipients in (d) | `_plaintext_journal=absent` by default. It is set from `dumpe2fs -h` on the origin before the snapshot. It is emitted in the `boot_complete` call beside `plaintext_volume`. No branch of the unit tests its value. (d) names Sentry and Better Stack, and the preceding sentence of (g) says "readable in Better Stack and Sentry" | **Holds** |
| D19 | Cross-record: the cloud-init LUKS-id ≠ plaintext-id guard (ADR-239) | Not claimed in the register. Recorded here only as a supporting control: it refuses to `luksFormat` the retained volume | n/a (not a register claim) |

## Findings

- **F1 (E2) is the substantive one.** The mechanism-only justification is the load-bearing sentence
  of the (2)(ii) marker, and it said the new read covers the same data "the former mount already
  read". The whole reason for the change is that the former read did not see the journal. The
  corrected sentence keeps the determination and states the delta: the same volume, its own journal
  now also read, no new category. The error ran in the under-disclosure direction, so it was
  corrected before sign-off rather than noted.
- **F2 (E1) and F3 (E3) are precision fixes in the over-claim direction.** E1 stops the register
  from implying the kernel read-only flag outlives a detach. E3 stops it from implying FATAL detail
  carries only four kinds of token, and moves the "never" from "directory names", which the
  private mount directory contradicts, to "any name read from the volume", which is the actual
  guarantee and is verified.
- **F4. No Art. 33/34 analysis is needed.** The motivating event (step-3 replace FATAL at
  09:09:30Z, `plaintext_unverified reason=journal`) was a fail-closed refusal. Nothing was written
  to the volume, no data left the host, and every refused Art. 17 erasure is logged under
  `op:git-data-bare-repo-erasure`, as (g) already records. No Art. 4(12) event.
- **F5. The published documents are unaffected.** They disclose Hetzner as the host processor and
  the git-data store's existence at the level of processing activity. They say nothing about how
  the bootstrap proves the plaintext volume empty.

## Verification commands (re-runnable from the worktree)

- `git diff origin/main...HEAD -- knowledge-base/legal/` → one line changed (PA-36 (g)), three insertions.
- `sed -n '/BEGIN plaintext-count unit/,/END plaintext-count unit/p' apps/web-platform/infra/git-data-bootstrap.sh | grep -c 'FATAL: plaintext_unverified reason=\(source\|snapshot\|mount\|journal\|umount\)'` → every FATAL in the unit uses one of the five reasons (D12).
- `sed -n '/BEGIN plaintext-count unit/,/END plaintext-count unit/p' apps/web-platform/infra/git-data-bootstrap.sh | grep -n 'mount -o'` → a single mount, of `/dev/mapper/$_pt_snap`, with no `noload` (D1, D9).
- `git show b91dcf219b^:apps/web-platform/infra/cloud-init-git-data.yml | grep -n "scsi-0HC_Volume_.*ext4"` → `defaults,nofail`, so data=ordered (D13).
- `grep -n 'mkswap\|swapon' apps/web-platform/infra/cloud-init-git-data.yml` → no match (D8, O1).
- `grep -n -i 'vector' apps/web-platform/infra/cloud-init-git-data.yml` → comment only: "git-data runs no Vector agent" (D15).
- `grep -n 'plaintext_journal' apps/web-platform/infra/git-data-bootstrap.sh` → default `absent`, set from the origin's `dumpe2fs`, emitted in `boot_complete` (D18).
- `grep -rln -i 'noload\|device-mapper\|plaintext volume' docs/legal plugins/soleur/docs/pages/legal` → no match (F5).
- `bash scripts/lint-legal-registers.sh` → `=== lint-legal-registers: all assertions passed ===`.

## Correction record

Applied 2026-09-24 by the CLO agent, in-cell, to text inserted by this PR only. The cell stays on
one line; the file's line count is unchanged (777). No older marker was touched.

- **E1**, PA-36 (g)(1), 2026-09-24 marker: "an in-memory flag that lasts for that boot" → "an
  in-memory flag that a reboot or a detach of the volume drops".
- **E2**, PA-36 (g)(2)(ii), 2026-09-24 marker: "within the same purpose, host, processor and data
  the former mount already read;" → "within the same purpose, host and processor and on the same
  volume the former mount read (the replay also reads that volume's own journal, which `noload`
  skipped; no new category of data);".
- **E3**, PA-36 (g)(2)(ii), 2026-09-24 marker: "FATAL detail carries a classifier word (`overflow`,
  `jbd2`, `ext4-error`, `none`), device-mapper status numbers and sector counts, never kernel log
  lines or directory names," → "FATAL detail carries device paths, a classifier word (`overflow`,
  `jbd2`, `ext4-error`, `none`), device-mapper status numbers, error counts and sector counts,
  never kernel log lines or any name read from the volume,".

**Waiver.** This review cites Art. 33/34 and Art. 4(12) only to record that no trigger exists, so
it matches the `lint-legal-registers.sh` (c) producer pattern. Following the #8043, #8189, #8205,
#8248 and #7226 precedent, it carries a `NOT_TRANSCRIBED` entry in `scripts/lint-legal-registers.sh`
and a matching row in `breach-register.md`'s Excluded records table. The (d) parity assertion
requires both. Result after both edits: `lint-legal-registers: 11 assertion(s), 0 failed
(registers=5 rows=8 produced=29 waived=23 waiver-parity=ok)`.
