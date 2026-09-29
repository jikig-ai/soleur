---
title: "Counsel re-attestation — #8634 / PR #8564 (ADR-239 removes the repoint step: row D5 of the #8189 counsel review is superseded; the PA-36 §(g)(1) / PA-2 §(g)(17) activation test was first met in production on 2026-09-25 — the register-marker flip and this file's breach-register waiver stay OPEN)"
type: counsel-review
date: 2026-09-29
issue: 8634
related_issues: [8189, 8211, 8043, 5274, 6897, 8572]
pr: 8564
parent_review: knowledge-base/legal/audits/2026-09-counsel-review-8189.md
adr: knowledge-base/engineering/architecture/decisions/ADR-239-git-data-serves-from-luks-at-birth.md
brand_survival_threshold: single-user incident
status: SIGNED-OFF (CLO-agent-attested, Soleur-as-tenant-zero v1)
signed_off_at: 2026-09-29
signed_off_by: "CLO agent (attestation authority for the Soleur-as-tenant-zero v1 posture; the operator retains an optional veto)"
disposition: "DISCHARGED as to the D5-supersession record, with OPEN follow-ups recorded (none blocks this file). Row D5 of 2026-09-counsel-review-8189.md attested 'the repoint is now the real cutover's repoint step (#8211)' — corrected in that review's own C4 to future tense ('the repoint will be a step of the rebuilt cutover (#8211, open), which does not exist yet'). PR #8564 (merged b91dcf219, 2026-09-23) authored ADR-239, which removes the repoint mechanism entirely: the render serves /mnt/git-data from the LUKS mapper /dev/mapper/git-data at birth, with no plaintext/LUKS selector and no runtime repoint, and the serving-device change rides an ordinary git_data_host_replace. D5's forward claim, in both its original and its C4-corrected form, is superseded. The dated parent file is not edited; this file is the correction, which is the append-only convention the issue prescribes and the one PR #8564 already applied inside article-30-register.md. Nothing here is conditioned on a pending merge: the superseding event is a past fact (merge 2026-09-23; ADR-239 flipped to accepted 2026-09-27)."
blocking_findings: []
corrections_to_parent_review:
  - "2026-09-counsel-review-8189.md row D5 ('Deletion holds; \"is now\" asserts a step that does not exist → C4'), and condition C4's replacement sentence itself ('the repoint will be a step of the rebuilt cutover (#8211, open), which does not exist yet'): superseded as to the forward claim. The rebuilt cutover carries no repoint step — there is no step for the claim to refer to. The parent file is not edited; this record is the correction."
attests:
  - "This file's record that D5's forward claim is superseded by ADR-239, verified against the code at branch head (symbols cited under ## Drift table)"
  - "The CLO determination ADR-239 twice delegates to this issue: when the register's own §(g)(1)/§(g)(17) activation test was first met in production — 2026-09-25, on the evidence under ## The delegated determination"
does_not_attest:
  - "ADR-239 itself, ADR-068's supersession marker, ADR-220's D6 amendment, the runbooks, and the engineering records cited for the sequence of events (engineering records, relied on, not certified)"
  - "knowledge-base/legal/article-30-register.md's 2026-09-23 (#8211) and 2026-09-24 (#5274) in-cell markers in PA-36 §(g)(1) and §(g)(2) — read for consistency (consistent); they were attested in the PRs that added them"
  - "The correctness of the code controls themselves; counsel attests the record's statements about them"
open_follow_ups_not_blocking:
  - "F1 — article-30-register.md: PA-36 §(g)(1) and PA-2 §(g)(17) still read DRAFTED / NOT-YET-ACTIVE although the activation test they name was first met 2026-09-25. An in-cell Superseded-dated marker flipping them is the next register PR. Understating a live control is the safe direction (precedent: 2026-09-counsel-reattestation-5914.md, activation vs marker lag), so this does not block."
  - "F2 — The same follow-up should supersede, in-cell, the clause inside the 2026-09-15 (#8189) marker that still reads 'the repoint will be a step of the rebuilt cutover (#8211, open)', and re-derive the ledgered plaintext exception #6897 (expires 2026-10-22): its premise — repositories sitting unencrypted on the plaintext volume until a repoint — no longer exists as a serving path."
  - "F3 — This file matches the breach register's determination-shaped producer pattern (it cites Art. 33/34). It therefore needs the usual NOT_TRANSCRIBED waiver in BOTH copies — scripts/lint-legal-registers.sh and breach-register.md's §Excluded records table — plus the 'nineteen rows' restatement in that section's preamble. Recording a supersession of a dated attestation assesses no fact pattern and makes no Art. 4(12) determination: same class as the #8189 row's waiver."
  - "F4 — Optional: a compliance-posture.md row naming this record (the #8248 O5 precedent: recommended, not conditioned)."
art_33_triggered: false
art_34_triggered: false
re_evaluation_triggers: "(1) Any proposal to set GIT_DATA_STORE_ENABLED: a hard block until #8211's remaining real-modes work lands — the flip, the flag-off-only rollback, the same-version redeploy, the per-host git_data_store= startup line, the ADR-220 D6 fresh replace with LUKS key and volume rotation, the ADR-237 amendment, a freeze writer, and pin-fault paging (#8572). Inherited from the parent's trigger set, unchanged. (2) The F1/F2 register markers land: re-read this attestation against their wording; a marker that claims the measure was active BEFORE 2026-09-25, or claims it on the flag flip rather than the mount read, falsifies what this file records. (3) Any production boot of hcloud_server.git_data emitting stage:boot_complete without luks_mounted=yes and fence_on_mapper=yes: the delegated determination re-opens, because the read it rests on would no longer be current. (4) Standing external-counsel triggers: first arm's-length workspace owner, any EEA-out owner, any regulated-industry owner."
---

# Counsel re-attestation: #8634 / PR #8564 (ADR-239 removes the repoint)

This file discharges issue #8634. It names row D5 of
`knowledge-base/legal/audits/2026-09-counsel-review-8189.md` and records that its forward claim is
superseded by ADR-239. The dated parent is an append-only attestation and is **not edited** — the
same discipline the Article 30 register follows, and the reason PR #8564 added Superseded markers
there rather than editing entries in place. The CLO agent is the v1 attestation authority; the
operator holds an optional veto. Everything here is draft material requiring professional legal
review; external counsel re-review is reserved for the triggers above.

Nothing in this file is conditioned on a pending merge: PR #8564 merged 2026-09-23 as `b91dcf219`,
and ADR-239's status flipped to `accepted` by its own 2026-09-27 amendment. The superseding event is
a past fact on both counts.

## What row D5 attested

D5 verified the PA-36 §(g)(1) marker PR #8206 added to `article-30-register.md`. Its checked claim,
as the row states it:

> §(g)(1) marker: `repoint_luks_mount` deleted with the cutover body; "the repoint is now the real
> cutover's repoint step (#8211)"

Verdict: **deletion holds; "is now" asserts a step that does not exist → C4**. C4 rewrote the
register marker's forward half to the future tense — "the repoint will be a step of the rebuilt
cutover (#8211, open), which does not exist yet" — so the sentence that landed already conceded the
step was unbuilt. What neither form anticipated is that the rebuilt design would carry **no repoint
step at all**.

## What supersedes it — the ADR-239 mechanism

ADR-239 (`knowledge-base/engineering/architecture/decisions/ADR-239-git-data-serves-from-luks-at-birth.md`,
authored in PR #8564) reverses ADR-068 D10 and withdraws ADR-220 D6's runtime repoint. Its four
decisions, as verified against the code at this branch:

1. **LUKS mapper at birth.** The render always mounts `/dev/mapper/git-data` at `/mnt/git-data` —
   `cloud-init-git-data.yml` writes the fstab line `/dev/mapper/git-data /mnt/git-data ext4
   defaults,nofail 0 2` and mounts the mapper there. There is no plaintext/LUKS mode selector, no
   interlock, no transition guard.
2. **The retained plaintext volume is never mounted.** As amended 2026-09-24 (#5274),
   `git-data-bootstrap.sh` sets the device kernel read-only (`blockdev --setro`, read back), stacks a
   non-persistent dm `snapshot` whose copy-on-write file lives on `/dev/shm`, mounts the snapshot
   read-only, counts every entry under its `repositories/`, and tears it down. Any failure is a
   named `FATAL: plaintext_unverified`; a non-zero count is `FATAL plaintext_residue`. The volume is
   retained and never writable.
3. **A positive marker gates every store-acting script.** `git-data-remove.sh`,
   `git-data-provision.sh`, `git-data-transport-wrapper.sh` and `git-data-gc.sh` refuse fail-closed
   unless `findmnt -n -o SOURCE --mountpoint` equals `STORE_DEVICE` (`/dev/mapper/git-data`) by
   string equality and `STORE_VERIFIED` (`/etc/git-data/store-verified`) holds the mapper
   filesystem's UUID. The marker's only writer is `git-data-bootstrap.sh`, once per instance.
4. **Replace-durable serving.** The serving change rides the next ordinary `git_data_host_replace`
   (ADR-237 post-merge step 3); `user_data` is `ForceNew`, so no in-place repoint could survive a
   replace anyway — a runtime repoint was never durable. `git-data-luks-reopen.sh` re-attaches the
   mapper on reboot and dies unless fstab names `/mnt/git-data` as the mapper's single target.

So there is no repoint step for D5's claim to refer to — not in a cutover run (`git-data-cutover.sh`
is now a read-only proof that refuses `real_cutover_unreconciled` before any remote call), and not
in the host lifecycle.

## The mechanism in production

ADR-239's flip rule is met, recorded by its 2026-09-27 amendment: `hcloud_server.git_data` (Hetzner
id 167392038, created 2026-09-25T09:24:32Z by replace run 36118115758) emitted `stage:boot_complete`
at 2026-09-25T09:25:30Z reading `luks_mounted=yes fence_on_mapper=yes erasure_probe=yes`, and the
same row reads `plaintext_journal=dirty plaintext_empty=yes`. The rung-2 precondition was rehearsal
run 36029201848, bound by `apps/web-platform/infra/git-data-rung2-boot-evidence.env`. The production
host has served its store from the mapper since that boot.

## The delegated determination: when encryption at rest became active

ADR-239 twice defers to this issue ("when encryption at rest became active for the Art. 30 register
is #8634's determination" — the 2026-09-27 amendments). Determination, on the register's own rule:

- **The rule.** PA-36 §(g)(1) and its authoritative twin PA-2 §(g)(17): the measure is active "only
  when `findmnt` reads `/dev/mapper/git-data` as the source of `/mnt/git-data` on the production
  host" — by the register's own words, NOT at the `GIT_DATA_STORE_ENABLED` flip. The register also
  records that under the new render `luks_mounted=yes` attests the mapper serves `/mnt/git-data`.
- **The read.** It was first satisfied at **2026-09-25T09:25:30Z**. `git-data-bootstrap.sh`'s own
  `findmnt -n -o SOURCE --mountpoint /mnt/git-data` equality gate ran on that boot — the
  `store-verified` marker it wrote exists only if that read returned `/dev/mapper/git-data` —
  corroborated by `luks_mounted=yes`, `fence_on_mapper=yes` and `erasure_probe=yes` in the same
  `boot_complete` row, and by the host's continued identity (the 2026-09-27 re-read returns the same
  server id and creation time).
- **The bound.** This is a device-level TOM activation under the register's stated test. PA-36 the
  processing activity stays **declared, not live**: `GIT_DATA_STORE_ENABLED` remains off, the store
  holds no repository, and no present-tense claim about user data follows from this determination.
  Whether the marker wording reads "active" or "in force, unexercised" is for F1's drafting; what is
  not open is that the NEGATIVE premise — repositories sitting unencrypted on a plaintext serving
  device until a repoint — is falsified as a serving path.

## What stays OPEN

- **#8211's remaining real-modes work** (ADR-239's own list): the flag flip; the flag-off-only
  rollback; the same-version redeploy; the per-host `git_data_store=` startup line; the ADR-220 D6
  fresh replace with LUKS key and volume rotation; the ADR-237 amendment; a freeze writer; and
  pin-fault paging (#8572). The real modes keep refusing `real_cutover_unreconciled`.
- **`GIT_DATA_STORE_ENABLED` stays off.** The store is empty; the flag is the sole write gate; a
  flip before #8211's preconditions is a hard block (re-evaluation trigger (1)).
- **F1–F4** in frontmatter: the PA-36 §(g)(1)/PA-2 §(g)(17) DRAFTED→active marker (the cells now
  understate a live control — safe direction), superseding the "repoint will be a step" clause
  inside the 2026-09-15 marker, re-deriving the #6897 exception, and this file's own
  breach-register waiver pair.

## Drift table

| # | Claim | Checked against (by symbol, not line) | Verdict |
|---|---|---|---|
| D1 | `repoint_luks_mount` is absent from the git-data cutover | `git-data-cutover.sh` — `grep -c repoint_luks_mount` → 0; it survives only in `workspaces-cutover.sh` (the web-1 /workspaces cutover, a different host's mechanism) and in `git-data-luks.test.sh`'s retired-step mutation arm — not a defect | **Holds** |
| D2 | The render serves `/mnt/git-data` from the mapper at birth | `cloud-init-git-data.yml`: the fstab append `/dev/mapper/git-data /mnt/git-data ext4 defaults,nofail 0 2`, `mount /dev/mapper/git-data /mnt/git-data` in the LUKS stage, `luksOpen` in runcmd | **Holds** |
| D3 | Wrappers refuse unless the mapper serves the mount and the marker holds its UUID | `STORE_DEVICE`/`STORE_VERIFIED`/`findmnt -n -o SOURCE --mountpoint` blocks in `git-data-remove.sh`, `git-data-provision.sh`, `git-data-transport-wrapper.sh`, `git-data-gc.sh` | **Holds** |
| D4 | No repoint path survives in the host lifecycle | `git-data-luks-reopen.sh` dies unless the mapper's single fstab target is `/mnt/git-data`; `user_data` is `ForceNew` on `hcloud_server.git_data` (`git-data.tf`); `git-data-cutover.sh` refuses `real_cutover_unreconciled` before dialing | **Holds** |
| D5 | The plaintext volume is never mounted (post-#5274 mechanism) | `git-data-bootstrap.sh`: `blockdev --setro`, dm `snapshot` on `/dev/shm` COW, snapshot-mount count, sector-counter before/after gate; ADR-239's 2026-09-24 amendment | **Holds** |
| D6 | Production serves from the mapper since 2026-09-25 | ADR-239 2026-09-27 amendment: run 36118115758, host 167392038, `boot_complete` `luks_mounted=yes fence_on_mapper=yes erasure_probe=yes plaintext_journal=dirty plaintext_empty=yes`; #8211 issuecomment-5860128868 | **Holds (as recorded in the ADR; the live reads are the ADR's, not re-run here)** |
| D7 | The flag stays off; the store stays empty | `plaintext_empty=yes` on the same row; `GIT_DATA_STORE_ENABLED` never `true` (ADR-239 Context; the bootstrap count and `store-empty` probe agree) | **Holds** |

## Scope and limit check

- **Append-only respected.** `git diff --stat origin/main...HEAD` touches only this new file.
  `2026-09-counsel-review-8189.md`, `article-30-register.md` and `breach-register.md` are unmodified
  in this change; F1–F3 are queued for the follow-up, not silently applied here.
- **The public surface is not engaged.** No `docs/legal/**` or `plugins/soleur/docs/pages/legal/**`
  path is touched; the five #7387 gates do not fire.
- **No past-tense claim about an unmerged change.** The superseding merge (2026-09-23) and the
  ADR-239 flip (2026-09-27) are both past facts; no statement here fires on a pending PR.
- **Citations by symbol, never by line** (`STORE_DEVICE`, `store-verified`, `findmnt --mountpoint`,
  `real_cutover_unreconciled`, `luks_mounted=yes`), per the standing rule — a later edit cannot move
  a line number under a signed record.
- **No Art. 33/34 duty arises.** A supersession record about an empty store and a device-level
  control assesses no fact pattern: nothing was destroyed, lost, altered, disclosed or accessed.

## Disposition

**DISCHARGED** as to the D5-supersession record. The correction to
`2026-09-counsel-review-8189.md` is complete in this file: D5's forward claim — in its original form
and in the future tense C4 substituted — is superseded by ADR-239's mechanism (LUKS mapper at birth;
replace-durable serving; no repoint step anywhere in the design). The delegated Art. 30 activation
determination is made above (test first met 2026-09-25T09:25:30Z). Follow-ups F1–F4 stay OPEN on the
record; none blocks this attestation, and the operator retains an optional veto.

## Verification commands (re-runnable from the worktree)

- `grep -c repoint_luks_mount apps/web-platform/infra/git-data-cutover.sh` → 0 (D1).
- `grep -n '/dev/mapper/git-data /mnt/git-data' apps/web-platform/infra/cloud-init-git-data.yml` → the fstab append (D2).
- `grep -n 'STORE_DEVICE\|store-verified' apps/web-platform/infra/git-data-remove.sh apps/web-platform/infra/git-data-provision.sh apps/web-platform/infra/git-data-gc.sh apps/web-platform/infra/git-data-transport-wrapper.sh` → the wrapper gates (D3).
- `grep -n 'real_cutover_unreconciled\|store-on-mapper' apps/web-platform/infra/git-data-cutover.sh` → the read-only proof (D4).
- `grep -n 'mnt/git-data' apps/web-platform/infra/git-data-luks-reopen.sh` → the single-target refusal (D4).
- `git status --porcelain` → only this file is added (append-only).
- `gh issue view 8634 --json state` → OPEN until the lead closes it on merge; `gh issue view 8211 --json state` → OPEN.
