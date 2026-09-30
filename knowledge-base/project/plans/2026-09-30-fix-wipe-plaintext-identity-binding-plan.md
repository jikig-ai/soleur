---
title: "fix(infra): bind the plaintext wipe and Guard 5 to the recorded plaintext device, not a label no artifact wrote (#6604 step 7 fix-forward)"
date: 2026-09-30
slug: fix-wipe-plaintext-identity-binding
branch: feat-one-shot-6604-wipe-plaintext-identity
issue: 6604
closes: []
refs: [6604, 6588, 9163]
type: fix
priority: p1
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
---

# fix(infra): bind the plaintext wipe and Guard 5 to the recorded plaintext device (#6604 step 7 fix-forward)

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed). (No spec exists for this branch.)

## Overview

PR A (#9163, merged 2026-09-30 as `403487494d`) added the `CONFIRM_WIPE` mode to
`apps/web-platform/infra/workspaces-cutover.sh`. Its read-only rehearsal (run `36710773788`,
`dry_run=true`) refused:

```text
SOLEUR_WORKSPACES_LUKS_WIPE ... result=refused arm=first_wipe volume_id=105149570 reason=wipe_target_label_mismatch label=none
```

Every other W0–W6 check passed: the `HC_Volume_105149570` serial, the size, not the mapper backing, no
holders, unmounted, ext4, and the header and escrow checks W3–W5.

One false premise causes the refusal: that web-1's retained plaintext volume carries the filesystem
label `workspaces_plain`. **No production artifact writes that label.** `soleur-host-bootstrap.sh`
labels only `workspaces_luks`, and no `e2label` or `tune2fs -L` runs outside tests. The only writer is
the loopback suite's own fixture (`new_plain`: `mkfs.ext4 -L workspaces_plain`). That fixture is why
PR A's real-device rows stayed green on a premise production never met.

Two defects share the premise:

1. **W6 (wipe identity).** On the `first_wipe` arm, `wipe_plaintext()` requires
   `blkid -p -s LABEL` to equal `workspaces_plain`.
2. **Guard 5 (the "plaintext gone" witness).** `_plaintext_label_present` / `_plaintext_gone` are used
   by `rollback()` and `assert_rollback_not_post_cutover()`. The inline `gone_guard` sits in the
   dead-man fire string. All of them treat a missing `/dev/disk/by-label/workspaces_plain` as "the
   plaintext is gone". That link has never existed on web-1. So today, **pre-wipe**, every one of
   those sites wrongly reads "gone" and refuses.

   Also dead: `rollback()`'s first remount attempt (`mount /dev/disk/by-label/workspaces_plain`) and
   the dead-man's `${dev:-/dev/disk/by-label/workspaces_plain}` fallback.

**The fix replaces the label with the identity the cutover actually recorded.** That is
`PLAINTEXT_DEV`, the plaintext's `findmnt -no SOURCE`. The cutover's rollback-rehearsal step
persisted it, and that step is its only writer.

- **W6** binds the target to that record.
- **Guard 5's physical witness** becomes: `$MOUNT` is on the mapper **and** the recorded device is
  not an intact plaintext copy. Not intact means unrecorded, resolving to the mapper, or
  `blkid -p -s TYPE` is not `ext4`.
- **The dead-man fire** carries the same test inline (`/bin/sh`, no helpers).
- **`arm_dead_man`** now refuses to arm a backstop that has no valid record to restore from.

The rehearsal row keeps `label=` as **observed evidence** and gains `plaintext_dev=`.

This is a narrow fix-forward, not a redesign. No `.tf`, no dispatch and no prod writes happen in this
PR. After merge, the read-only rehearsal is re-run. The destructive dispatch still needs its own
per-command go-ahead. Refs #6604 #6588; neither is closed by this PR.

## Research Reconciliation — Spec vs. Codebase

| Claim (task / PR A) | Reality (verified) | Plan response |
|---|---|---|
| The retained plaintext carries `LABEL=workspaces_plain` | No production producer exists (see Overview). The rehearsal observed `label=none`. | Remove the premise from code and docs. `label=` stays on the row as evidence only. |
| `PLAINTEXT_DEV` is the plaintext's mount source | The rollback-rehearsal step runs `plain_dev="$(findmnt -no SOURCE "$MOUNT")"; persist_state PLAINTEXT_DEV "$plain_dev"`. That is the ONLY writer, and it runs before `arm_dead_man` in the same run. | Bind W6 and Guard 5 to it. |
| On web-1 it is `/dev/sdb` | `/dev/sdb` comes from the 2026-07-20 dead-man postmortem (`mount_source=/dev/sdb`), not from the state file. The value the 2026-07-23 re-cut recorded is **unverified**. #9179 measured `reboot-required=yes`, so web-1 had not rebooted as of that PR. The task states it has not rebooted since. | Nothing in the plan hardcodes `/dev/sdb`. The rehearsal row prints the record, and a mismatch fails closed with diagnostic fields (see Risks). |
| `PLAINTEXT_DEV` can never be the mapper | The rehearsal step runs after `prepare_staging_target`, which refuses a cut-over host. The wipe suite's S6 row pins that ordering. | Defend anyway: resolving to the mapper reads as "gone", and `arm_dead_man` refuses it. Cheap, and it covers an S6 regression. |
| The fire must stay "self-contained" | The fire already resolves `cryptsetup` and `mount` by bare name under `systemd-run`; the 2026-07-20 fire ran them live. "Self-contained" means no script helpers. | Inline `blkid`, with its absolute path baked at arm time (`command -v blkid`). |
| No edits needed to the workflow or to T12/T12b/T12c | The workflow parses only `plaintext_only=` and `io_max=`. T12/T12b/T12c grep unit names and `if mount [^;]*; then`. | Keep the `if mount <src> <mnt>; then` shape. |

## Research Insights

**Premise Validation.**

- #6604 and #6588 are OPEN.
- `403487494d` is PR A (#9163) on main.
- Run `36710773788` log (read-only `gh run view --log`): `arm=first_wipe (signature=ext4 …)`, then
  `reason=wipe_target_label_mismatch label=none`, then `outcome=dry_run mode=wipe`.
- Every cited symbol exists on `origin/main`.
- "web-1 has not rebooted since" cannot be verified without prod access. The re-run rehearsal is its
  verification (see Risks).

**Property List.**

- P1: the first-wipe zero targets exactly the device the cutover recorded as the plaintext's mount
  source. This is in addition to W1's pinned by-id path and W6's serial, size, path, major:minor,
  holders and mount checks.
- P2: on web-1 today (pre-wipe, unlabelled ext4), the rehearsal reaches `rehearsal_ok`.
- P3: `rollback()`, `ROLLBACK` mode and the dead-man fire unmount the mapper only when the recorded
  device is still an intact ext4 that is not the mapper. A stale record (kernel-name drift) reads as
  "gone". That is fail-closed, and the refusal now prints evidence to tell drift from a real wipe.
- P4: no code path depends on a filesystem label that no artifact writes.
- P5: the dead-man is never armed without a record it could restore from.

**Cut List (reviewed and not done).**

- A new `PLAINTEXT_BYID` or fs-UUID state key → P1 is already covered by W1's pin plus W6's serial.
  A new key would need a cutover re-run, which is impossible post-cutover.
- A binding on the `re_zero` arm → resume is already bound by the persisted marker and the serial,
  and a binding could strand a resumed zero.
- A permanent census suite row for the deleted token → one pre-merge AC grep is enough (DHH and
  simplicity).
- A second implementation-parity row and production-predicate unit rows → the seam now only
  *prints* the blkid TYPE; the decision logic lives in `_plaintext_gone` (stub-tested) and the fire
  (G5d-executed); real blkid is exercised by LW-P2/LW-P3.
- Dropping the `label=` evidence or the fire's physical arm (DHH and simplicity) → the operator
  specified both. Kept, and recorded in `decision-challenges.md`.

**Institutional learnings applied.**

- `2026-09-28-a-dead-label-route-and-an-end-sample-that-reread-its-start.md`: a label with no
  producer. Grep for the producer before trusting a consumer.
- `2026-09-02-i-built-a-host-discriminator-out-of-an-absence-and-fixtured-the-absence.md`: PR A's
  fixture did exactly that. The new witness asserts a positive type.
- `2026-09-24-i-parked-a-fix-for-a-cause-i-never-tested-and-my-stubs-could-not-see-the-device.md`:
  stubs must see which device they were handed. The new seam records its argument.
- `2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md`: every guard
  gets must-PASS rows.

**Conventions.**

- Seams read no environment (wipe suite S5).
- Every `_wipe_refuse` slug needs an asserting RED row (C1) and a runbook verdict row (C2).
- Floors are raised to the measured count.
- Suites never pipe into an assertion predicate.
- `cq-cite-content-anchor-not-line-number`.

## Implementation Phases

### Phase 1 — RED first (`cq-write-failing-tests-before`)

Write the Test Scenarios rows and confirm they fail on today's tree for the stated reason:

- G1-P1 refuses with `wipe_target_label_mismatch`;
- G5d-H2 refuses pre-wipe on an intact, unlabelled plaintext;
- G5b-H1's seam-argument assertion fails (there is no such seam yet).

### Phase 2 — `workspaces-cutover.sh`

1. **Delete the premise.** Remove `PLAINTEXT_LABEL=` and its comment block, and
   `_plaintext_label_present()` and its comment.
2. **New seam `_plaintext_dev_type()`**, where `_plaintext_label_present` was. It reads only `$1`,
   so S5 covers it.

   ```bash
   # _plaintext_dev_type <dev> — the blkid TYPE of the device a rollback would remount (the recorded
   # PLAINTEXT_DEV), or nothing (unrecorded, absent, zeroed). Identity is the cutover's recorded mount
   # source, not a filesystem label: no artifact labels the retained plaintext (ADR-119, 2026-09-30
   # correction). A SEAM: it reads no environment, only its argument. KEEP IN SYNC with the inline copy
   # in arm_dead_man's gone_guard.
   _plaintext_dev_type() { [ -n "${1:-}" ] || return 0; blkid -p -s TYPE -o value "$1" 2>/dev/null || true; }
   ```

3. **`_plaintext_gone`.** The marker arm is unchanged. The physical arm becomes:

   ```bash
   local pdev; pdev="$(read_state PLAINTEXT_DEV)"
   PLAINTEXT_DEV_SEEN="${pdev:-none}"; PLAINTEXT_DEV_TYPE="$(_plaintext_dev_type "$pdev")"
   if [ "$(findmnt -no SOURCE "$MOUNT" 2>/dev/null || true)" = "$MAPPER" ]; then
     if [ -z "$pdev" ] || [ "$pdev" = "$MAPPER" ] \
        || [ "$(readlink -f -- "$pdev" 2>/dev/null)" = "$(readlink -f -- "$MAPPER" 2>/dev/null)" ] \
        || [ "$PLAINTEXT_DEV_TYPE" != ext4 ]; then
       PLAINTEXT_GONE_WHY=plaintext_dev_gone; return 0
     fi
   fi
   ```

   - The header comment says the physical arm reads the state file for *which* device to probe, and
     that a lost record reads as "gone". That refusal is fail-closed but strands a still-intact
     plaintext as a rollback source (see Risks).
   - Both refusal log lines, in `rollback()` and in `assert_rollback_not_post_cutover()`'s
     `_rollback_refuse` message, append
     `recorded=$(_vscrub "$PLAINTEXT_DEV_SEEN") recorded_type=${PLAINTEXT_DEV_TYPE:-none}`. With no
     marker, `recorded_type=crypto_LUKS` or `other` means a stale record, not a wipe.
   - Update the comment in `assert_rollback_not_post_cutover` that says "the plaintext label gone".
4. **`rollback()` remount.** Replace the by-label-then-`PLAINTEXT_DEV` pair with the existing second
   arm alone, `mount "$(read_state PLAINTEXT_DEV)" "$MOUNT" 2>/dev/null || true`. Its comment becomes
   "its recorded mount source, never the mapper". The #9098 C source check after it is unchanged.
5. **`arm_dead_man`.** Changes, in order:

   1. **Validate before anything else**, which is pre-freeze and has no side effects. After
      `dev="$(read_state PLAINTEXT_DEV)"`:

      ```bash
      blkid_bin="$(command -v blkid 2>/dev/null || true)"
      case "$dev" in ""|*[!A-Za-z0-9/_.:-]*) dev_bad=1 ;; *) dev_bad=0 ;; esac
      [ "$dev" = "$MAPPER" ] && dev_bad=1
      if [ "$dev_bad" = 1 ] || [ -z "$blkid_bin" ]; then
        _deadman_row "result=arm_refused reason=plaintext_dev_unrecorded detail=$(_deadman_detail "${dev:-empty}")"
        emit_drift deadman_arm_failed
        die "no valid recorded plaintext device (PLAINTEXT_DEV='$(_vscrub "$dev")', blkid='${blkid_bin:-absent}') — a dead-man armed now could unmount \$MOUNT and restore nothing. Refusing to arm; nothing is frozen (runbook: deadman_arm_failed)"
      fi
      ```

      `$dev` is now non-empty and charset-safe (no quote or space), so it is baked **unquoted**, like
      the existing mount clause. That removes the quote-escaping hazard entirely.
   2. **The physical clause of `gone_guard`** becomes
      `{ [ "$(findmnt …)" = ${MAPPER} ] && [ "$(${blkid_bin} -p -s TYPE -o value ${dev} 2>/dev/null)" != ext4 ]; }`,
      escaped like the existing `\"\$(findmnt …)\"`. Add a `KEEP IN SYNC with _plaintext_dev_type /
      _plaintext_gone` comment.
   3. **The mount clause** `mount ${dev:-/dev/disk/by-label/workspaces_plain} ${MOUNT}` becomes
      `mount ${dev} ${MOUNT}`. T12b's `if mount [^;]*; then` shape is kept.
   4. Rewrite the `#6604 step 7` comment block to say "the recorded plaintext device no longer an
      intact ext4".
6. **W6 in `wipe_plaintext()`** (`first_wipe` only). Replace the label equality:

   ```bash
   label="n/a"; pdev="n/a"
   if [ "$WIPE_ARM" = first_wipe ]; then
     label="$(blkid -p -s LABEL -o value "$real" 2>/dev/null || true)"; label="${label:-none}"   # observed evidence only
     pdev="$(read_state PLAINTEXT_DEV)"
     [ -n "$pdev" ] && [ "$(readlink -f -- "$pdev" 2>/dev/null)" = "$real" ] || _wipe_refuse wipe_target_not_recorded_plaintext \
       "the target resolves to '$real', but the plaintext mount source this cutover recorded (PLAINTEXT_DEV) is '$(_vscrub "${pdev:-<unrecorded>}")' — the zero may only hit the device the cutover itself took the copy from" \
       "target=$real" "recorded=$(_vscrub "${pdev:-none}")" "recorded_real=$( [ -n "$pdev" ] && readlink -f -- "$pdev" 2>/dev/null || echo none)"
     pdev="$(_vscrub "$pdev")"
   fi
   ```

   - Add `pdev` to the `local` list. `label` is already there.
   - Add `"plaintext_dev=$pdev"` next to `"label=$label"` on the `rehearsal_ok` row.
   - The W7 comment "(its fire command remounts the plaintext by label)" becomes "by its recorded
     `PLAINTEXT_DEV`".
7. **Post-edit.** `workspaces_plain` appears nowhere in the script. The rationale comments name "a
   filesystem label" generically.

### Phase 3 — seams and suites

- **`workspaces-luks-harness.sh`.**
  - Replace the `_plaintext_label_present` override with a seam that records its argument:
    `_plaintext_dev_type() { rec "SEAM _plaintext_dev_type ${1:-}"; [ -n "${1:-}" ] || return 0; printf "%s" "${PLAINTEXT_DEV_TYPE-ext4}"; }`.
    The body is written with double quotes because it sits inside the single-quoted `bash -c`.
  - Knob: `PLAINTEXT_LABEL_ABSENT=1` becomes `PLAINTEXT_DEV_TYPE=<type>`. The default is `ext4`,
    i.e. intact. Update the knob documentation block.
  - `run_case` seeds `PLAINTEXT_DEV=/dev/sdz9` into `$STATE/state` by default (`/dev/sdz9` is the
    suites' plaintext source). `PLAINTEXT_DEV_UNSEEDED=1` opts out. This is production-faithful:
    every real pre-freeze run has persisted it. Without the seed, `arm_dead_man` refuses and every
    pre-wipe rollback reads "gone".
- **`workspaces-luks-wipe.test.sh`.**
  - Delete the stub world's `_plaintext_label_present` override. It is dead code: `wipe_plaintext`
    never calls `_plaintext_gone`.
  - `blkid` `LABEL` defaults to empty (rc 2). `dumpe2fs` prints `Filesystem volume name:   <none>`.
  - `run_wipe`'s default seed gains `PLAINTEXT_DEV=$TGT_BLK`.
  - The happy-path field list uses `label=none` and `plaintext_dev=$TGT_BLK`.
  - Replace the W6 label refusal row with the G1 rows.
  - S5: swap the seam name in both regexes, and drop the `PLAINTEXT_LABEL` allowance and `pl_lit`.
  - Rework G5b/G5c/G5d per Test Scenarios.
  - Raise `WIPE_MIN_PASS` from 143 to the measured count.
- **`workspaces-luks-freeze.test.sh`.**
  - T35/T42b: `has '^mount /dev/disk/by-label/workspaces_plain '` becomes
    `has '^mount /dev/sdz9[[:space:]]'` (the harness default seed).
  - Add arm rows A1 and A4 (Test Scenarios).
  - Raise `FREEZE_MIN_PASS` from 170 to the measured count.
- **`luks-monitor.test.sh`.** Add `"result=arm_refused reason=plaintext_dev_unrecorded"` to the
  `_deadman_row` census list.
- **`workspaces-luks-loopback.test.sh`.**
  - `new_plain` formats **unlabelled** (production-faithful); update its comment.
  - `seed_state` appends `PLAINTEXT_DEV=$WP_DEV` *before* its optional `$1` line, so a caller's line
    wins.
  - Any real `arm_dead_man` call gets a seeded record.
  - Add LW-P1..LW-P3.

### Phase 4 — docs (same PR)

- **Runbook `workspaces-luks-cutover-6604.md`.**
  - **Step 7b expected row.** Replace `label=workspaces_plain` with
    `label=<observed; none on web-1> plaintext_dev=<as printed; must resolve to target=>`. Add one
    line: if a C15 reboot happened after the 2026-07-23 cutover, the record may name a different
    kernel device, and the rehearsal refuses (below).
  - **Verdict table.** Drop `wipe_target_label_mismatch` and add:

    ```text
    | `wipe_target_not_recorded_plaintext` | No | No | The first-wipe target is not the device this cutover recorded as the plaintext's mount source. Compare `target=` with `recorded=`/`recorded_real=`: `none` = the record is missing; a different device = kernel-name drift after a reboot (then `rollback()` and the dead-man's remount source is stale too — do not dispatch `rollback=true` or a cutover either). Nothing was written. Do NOT append `PLAINTEXT_DEV=` to the state file by hand: the record is evidence of what the cutover took the copy from, and a hand-written value is not. Halt and escalate; the remedy is a reviewed fix-forward PR (a serial-anchored record step), not a host edit. | End the pause (above) |
    ```

  - **`wipe_deadman_armed` row.** Rewrite it in full. After this fix, a dead-man fire on this host
    *restores*: it would remount the stale 2026-07-23 plaintext over `/mnt/data`. The W7 refusal is
    therefore the only protection. Keep "halt and escalate — do not let it fire".
  - **"After Sequence step 7 there is no rollback".** Rewrite the paragraph and the two
    `refused_plaintext_wiped` failure-signal rows (the `rollback()` one and the dead-man one) with the
    new witness. They should say: "the wipe was begun (marker; the copy may be partly or wholly
    zeroed), or the mapper is mounted and the recorded `PLAINTEXT_DEV` is not an intact ext4. With no
    marker, read `recorded_type=`: `crypto_LUKS`/other means a stale record, not a wipe — escalate.
    An intact plaintext with no `blkid` on PATH also lands here."
  - **Rollback section.** Add one sentence: an acknowledged pre-wipe `rollback=true` remounts the
    plaintext read-write, and the wipe's W9 provenance gate then refuses
    (`wipe_plaintext_written_after_cutover`).
  - **`deadman_arm_failed` / `arm_refused` row.** Add `reason=plaintext_dev_unrecorded`: no valid
    record or no `blkid`. Nothing was frozen.
- **ADR-119** (the 2026-09-28 wipe addendum). Two sentence swaps, no new ADR:
  - "hypervisor `ID_SERIAL` + the `workspaces_plain` label (W6)" becomes "… + the cutover's recorded
    plaintext mount source `PLAINTEXT_DEV` (W6; the label premise was false — no artifact labels the
    retained plaintext, corrected 2026-09-30)".
  - "`/mnt/data` on the mapper with the plaintext label gone (the physical witness does not depend on
    the state file)" becomes "`/mnt/data` on the mapper with the recorded `PLAINTEXT_DEV` unrecorded,
    resolving to the mapper, or no longer ext4 (a lost record reads as gone: it refuses)".
- **`knowledge-base/legal/audits/workspaces-plaintext-destruction-record.md`.**
  - The field `format / label` becomes `format / observed label / recorded mount source`, with source
    "the rehearsal row's `label` and `plaintext_dev`".
  - Its value stays a `(fill …)` placeholder. It is filled only post-merge, from the row.
- **Out of scope, do not edit:**
  - the postmortem's `${dev:-/dev/disk/by-label/workspaces_plain}` quote (historical);
  - `knowledge-base/project/specs/archive/**` and `plans/archive/**`;
  - `luks-monitor-install.test.sh`'s `LABEL=workspaces_plain` fstab line, which is a synthesized
    redaction fixture. web-1's real `/mnt/data` line is the #9179 mapper pin.

## Files to Edit

- `apps/web-platform/infra/workspaces-cutover.sh`
- `apps/web-platform/infra/workspaces-luks-harness.sh`
- `apps/web-platform/infra/workspaces-luks-wipe.test.sh`
- `apps/web-platform/infra/workspaces-luks-freeze.test.sh`
- `apps/web-platform/infra/workspaces-luks-loopback.test.sh`
- `apps/web-platform/infra/luks-monitor.test.sh`
- `knowledge-base/engineering/operations/runbooks/workspaces-luks-cutover-6604.md`
- `knowledge-base/engineering/architecture/decisions/ADR-119-luks-at-rest-for-the-live-workspaces-volume.md`
- `knowledge-base/legal/audits/workspaces-plaintext-destruction-record.md`

## Files to Create

None.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` returned no bodies naming a file above.

## User-Brand Impact

**If this lands broken, the user experiences:**

- **Wrong target.** W6 admits the wrong device and `blkdiscard -z` zeroes the LUKS volume's backing
  device. That destroys the ONLY copy of every user's workspace: source, branches and
  `refs/checkpoints/*`. The binding added here is additive to the pin, serial, size, path,
  major:minor, holders and mount checks, and the zero stays behind a separate go-ahead.
- **Wrong "gone" verdict.**
  - Read as "intact" when the plaintext is gone: rollback or a dead-man fire unmounts the mapper and
    every workspace goes offline, with nothing to remount.
  - Read as "gone" when the plaintext is intact (today's bug): a needed rollback is refused.
- **A dead-man armed with no restorable record.** A fire mid-freeze would unmount the live plaintext
  and restore nothing (P5 closes this).

**If this leaks, the user's data is exposed via:** a plaintext copy of every workspace stays on an
unencrypted Hetzner volume while the wipe remains blocked. That contradicts the privacy policy's
encryption-at-rest claim (#6588).

**Brand-survival threshold:** single-user incident.

CPO plan-time sign-off (2026-09-30): **yes, conditional**. All conditions are folded in:

- the serial stays a hard gate;
- wrong-device and letter-drift rows exist (G1-R2, G5b-D);
- any ambiguity refuses;
- the destructive dispatch keeps its per-command go-ahead;
- `soleur:engineering:review:user-impact-reviewer` runs at review.

## Guard Contract

### Guard 1 — W6 recorded-plaintext binding

**Property.** On the `first_wipe` arm the zero proceeds only if the target's canonical path equals the
canonical path of the LAST recorded `PLAINTEXT_DEV`.

**Assembly.**

- One chokepoint: `wipe_plaintext()` W6, `first_wipe` arm, between the serial check and W6b. The
  `$real` it binds is what W6b, W8, W9 and the act's `wipe_target_changed` re-check consume.
- One writer: the rollback-rehearsal step's `persist_state PLAINTEXT_DEV`.
- One reader: `read_state` (`tail -1`).

**Mutation matrix.**

| # | Mutation | Row that must go RED |
|---|---|---|
| M1 | Delete the binding | G1-R2 (record = the LUKS backing) reaches `rehearsal_ok` |
| M2 | Treat an empty record as pass | G1-R1 (unrecorded) reaches `rehearsal_ok` |
| M3 | Own dispatch: gate the binding on `re_zero` instead of `first_wipe` | G1-R1 and G1-R2 reach `rehearsal_ok` |
| M4 | Second member: read the FIRST `PLAINTEXT_DEV=` line (`grep … \| head -1`) | G1-R3 (first line = target, last line = LUKS) reaches `rehearsal_ok` |
| M5 | Compare the record unresolved (drop `readlink -f`) | G1-P2 (record is a symlink alias of the target) refuses |
| M6 | Re-introduce a label requirement | G1-P1 (the production reproduction) refuses |

**Harness rows.**

- H1 (suite edit → RED): restoring the stub's `LABEL` default to a label makes G1-P1 vacuous. G1-P1
  therefore asserts `label=none` on the row.
- H2 (must-PASS, non-canonical): G1-P2's symlink alias.

**Anchor.** The record was written on-host by the 2026-07-23 cutover run, outside any commit. The pin
and the serial are anchored by the Hetzner API (preflight).

### Guard 2 — Guard 5 physical witness and the dead-man arm

**Property.** With `$MOUNT` on the mapper and no wipe marker, `rollback()`, `ROLLBACK` mode and the
dead-man fire tear down the mapper only if the recorded `PLAINTEXT_DEV` is non-empty, is not the
mapper, and reads `blkid TYPE=ext4`. The dead-man is armed only with such a record, charset-safe, with
`blkid` resolvable.

**Assembly.**

- Consumers: `rollback()` line 1 and `assert_rollback_not_post_cutover()` line 1, both through
  `_plaintext_gone`, plus `arm_dead_man`'s arm validation and its `gone_guard` spliced into the fire.
- Implementations of the ext4 test: `_plaintext_gone` using the `_plaintext_dev_type` seam, and the
  fire's inline `${blkid_bin}` clause. Each carries a keep-in-sync comment.
- Census (comment-stripped): 2 `if _plaintext_gone;` call sites, 1 `_plaintext_dev_type "$pdev"`
  call, and 1 `${gone_guard}` splice.

**Mutation matrix.**

| # | Mutation | Row that must go RED |
|---|---|---|
| M1 | Drop the `!=`/`-z` logic (the physical arm never fires) | G5b-R1 (type none) refuses → rolls back |
| M2 | Physical arm treats any non-empty type as intact | G5b-D (`crypto_LUKS`) rolls back |
| M3 | Wrong key or empty argument passed to the seam | G5b-H1's `SEAM _plaintext_dev_type /dev/sdz9` assertion |
| M4 | Drop the mapper-identity clause | G5b-M (record = `$MAPPER`, type ext4) rolls back |
| M5 | Fire: drop the blkid clause | G5d-R2 (mapper, type none) tears down |
| M6 | Own dispatch: `${gone_guard}` not spliced | G5d-R1 (marker) tears down |
| M7 | Second member: remove `assert_rollback_not_post_cutover`'s copy while `rollback()` keeps its own | the G5 `mode=rollback` rows (outcome slug changes) |
| M8 | Arm validation removed | A1 (unrecorded) and A2 (`x'; logger INJECTED; '`) arm; A2's fire runs `INJECTED` |

**Harness rows.**

- H1: flipping the harness seed default to UNSEEDED drives T5, T6 and T35 RED. Verify once.
- H2 (must-PASS, non-canonical): G5d-H2, where the mapper is mounted and the record is an intact ext4
  reached as a real block device, restores.

**Anchor.** None: the predicate reads live device state, not a stored value.

## Observability

Layers as in PR A:

- **workflow run log** (layer 6);
- **vector → Better Stack** (layer 3, the `luks-monitor` tag);
- **Sentry** through `emit_drift`. A rehearsal refusal emits at `warning`.

```yaml
liveness_signal:
  what: SOLEUR_WORKSPACES_LUKS_WIPE rows (result=rehearsal_ok|refused) now carrying plaintext_dev= and the observed label=; refusals carry reason=wipe_target_not_recorded_plaintext with target=, recorded=, recorded_real=
  cadence: per dispatch (the read-only rehearsal is re-run after merge)
  alert_target: the failed-run view (layer 6) and the Sentry issue alert on op=workspaces-luks-drift
  configured_in: apps/web-platform/infra/workspaces-cutover.sh (emit_wipe, _wipe_refuse, emit_drift, _deadman_row)
error_reporting:
  destination: Sentry via workspaces_luks_emit (emit_drift) plus the workflow run log
  fail_loud: result=refused reason=<slug> before die; the rollback refusal log carries recorded= and recorded_type=; arm refusals print result=arm_refused reason=plaintext_dev_unrecorded and emit deadman_arm_failed
failure_modes:
  - mode: the record no longer names the target (unrecorded, or kernel-name drift after a reboot)
    detection: result=refused reason=wipe_target_not_recorded_plaintext target=<real> recorded=<value|none> recorded_real=<path|none> in the run log
    alert_route: Sentry workspaces_luks_drift (warning on a rehearsal, fatal on a real run) plus the failed run
  - mode: Guard 5 refuses because the recorded plaintext is not intact (a wipe, or a stale record)
    detection: EMIT_DRIFT rollback_refused_plaintext_wiped with recorded_type= in the log; the dead-man row result=fail reason=refused_plaintext_wiped
    alert_route: Sentry rollback_refused_plaintext_wiped; Better Stack dead-man rows
  - mode: dead-man arm refused for lack of a valid record or blkid
    detection: _deadman_row result=arm_refused reason=plaintext_dev_unrecorded
    alert_route: Sentry deadman_arm_failed
logs:
  where: GitHub Actions run logs for workspaces-luks-cutover.yml; web-1 syslog tag luks-monitor -> vector -> Better Stack
  retention: Actions 90 days; Better Stack per source retention
discoverability_test:
  command: grep -c -e '_wipe_refuse wipe_target_not_recorded_plaintext' apps/web-platform/infra/workspaces-cutover.sh
  expected_output: "1"
```

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `grep -c 'workspaces_plain' apps/web-platform/infra/workspaces-cutover.sh` → `0`.
      `git grep -n 'wipe_target_label_mismatch' -- . ':!knowledge-base/project/plans' ':!knowledge-base/project/specs'`
      prints nothing. The three pre-edit hits (script W6, wipe suite, runbook) are all edited.
- [ ] `git grep -n -i -e 'plaintext label' -e 'label gone' -e 'label_absent' -e 'PLAINTEXT_LABEL' -e '_plaintext_label_present' -- apps/web-platform/infra knowledge-base/engineering knowledge-base/legal`
      prints nothing, except the ADR-119 "corrected 2026-09-30" clause and the untouched postmortem.
- [ ] Comment-stripped census (`grep -vE '^[[:space:]]*#' apps/web-platform/infra/workspaces-cutover.sh | grep -c …`):
  - `persist_state PLAINTEXT_DEV` → `1`;
  - `if _plaintext_gone;` → `2`;
  - `_plaintext_dev_type "$pdev"` → `1`;
  - `${gone_guard}` → `1`.
- [ ] Wipe suite C1 (floor ≥25) and C2 pass, with `wipe_target_not_recorded_plaintext` in and
      `wipe_target_label_mismatch` out. C3 still passes.
- [ ] These exit 0: `bash apps/web-platform/infra/workspaces-luks-wipe.test.sh` (run unprivileged,
      outside `disk`), `workspaces-luks-freeze.test.sh`, and `luks-monitor.test.sh`.
      `WIPE_MIN_PASS` is raised from 143 to the measured count, and `FREEZE_MIN_PASS` from 170 to the
      measured count.
- [ ] `sudo bash apps/web-platform/infra/workspaces-luks-loopback.test.sh` exits 0, locally or in the
      `infra-validation.yml` loopback job, including LW-P1..LW-P3.
- [ ] Each mutation in the two Guard Contract matrices was applied once and drove its named row RED.
      Record them in the PR body as a `mutation | row | observed` table.
      `python3 scripts/lint-guard-contract.py <this plan>` → exit 0.
- [ ] `shellcheck` is clean on the edited scripts, and `bash -n` passes on each suite.
- [ ] Runbook, ADR-119 and destruction-record edits match Phase 4, and the destruction-record value
      is still a `(fill …)` placeholder.
- [ ] `git diff --name-only origin/main...HEAD | grep -cE '\.tf$|^\.github/workflows/|cloud-init'` → `0`.

### Post-merge

- [ ] Automation (read-only, ungated under the ADR-119 rehearsal authorization): dispatch
      `gh workflow run workspaces-luks-cutover.yml -f confirm=WIPE-PLAINTEXT-USER-DATA-AP-009 -f wipe_plaintext=true -f expected_plaintext_volume_id=105149570`
      (`dry_run` defaults to true) and arm a watch on the run (`hr-dispatch-async-must-arm-watch`).
      **Expected:** one `result=rehearsal_ok arm=first_wipe volume_id=105149570` row with
      `label=none`, and a `plaintext_dev=` that resolves to `target=`.
      **Fails closed:** `wipe_target_not_recorded_plaintext` means the record is missing or has
      drifted. Halt per the runbook row.
- [ ] The destructive dispatch is **not** part of this PR's follow-through. It needs its own
      per-command go-ahead (`hr-menu-option-ack-not-prod-write-auth`).

## Test Scenarios

**Wipe suite, stubbed.** Rows use the `run_wipe` default seed. Rows that need a path under
`$W_CASE_DIR` build it with `PRE_INV` (for example `ln -s …; persist_state PLAINTEXT_DEV …`), because
`$W_CASE_DIR` is allocated inside `run_wipe`.

- **G1-P1 (production reproduction; RED today).** Unlabelled target, record = `$TGT_BLK` →
  `rehearsal_ok first_wipe` with `label=none plaintext_dev=$TGT_BLK`.
- **G1-P2 (must-PASS alias).** `PRE_INV` symlinks `$W_CASE_DIR/alias` → `$TGT_BLK` and records the
  alias → `rehearsal_ok`.
- **G1-R1.** `SEED_STATE=CANARY_OK=1:$UUID_LIVE` (no record) → refuses
  `wipe_target_not_recorded_plaintext recorded=none`. Nothing is zeroed, no marker is written, and
  the headers are shredded.
- **G1-R2 (wrong device / letter drift).** `PRE_INV` symlinks `$W_CASE_DIR/dev/sdb` → `$LUKS_BLK` and
  records it → the same refusal, with `recorded_real=<LUKS real>`. The serial check still passes, so
  this isolates the binding.
- **G1-R3 (last wins).** `PLAINTEXT_DEV=$TGT_BLK` then `PLAINTEXT_DEV=$LUKS_BLK` → refuses.
- **G1-H3 (resume unaffected).** The `re_zero` arm with no record proceeds past W6.

**Guard 5 through the harness `run_case`.** The default seed is `PLAINTEXT_DEV=/dev/sdz9`.

- **G5b-H1.** Mapper mounted + ack + default type `ext4` → the rollback runs, and the calls include
  `SEAM _plaintext_dev_type /dev/sdz9`.
- **G5b-R1.** `PLAINTEXT_DEV_TYPE=` → refused before any umount. The log carries
  `why … plaintext_dev_gone` and `recorded_type=none`.
- **G5b-D.** `PLAINTEXT_DEV_TYPE=crypto_LUKS` → refused, and the log carries `recorded_type=crypto_LUKS`
  (the drift evidence).
- **G5b-U.** `PLAINTEXT_DEV_UNSEEDED=1` → refused with `recorded=none`.
- **G5b-M.** `persist_state PLAINTEXT_DEV "$MAPPER"` with type `ext4` → refused.
- **G5c.** The existing WIPED-marker row. The physical row uses `PLAINTEXT_DEV_TYPE=`, and the H1 row
  uses the defaults.
- **G5d** runs the captured fire string, re-armed per row through `g5d_arm <record>`. `G5D_BIN` gains
  its own `blkid` script that prints `$G5D_TYPE` (empty → rc 2), passed through `g5d_fire`'s `env`.
  - R1: marker → refuse (existing).
  - R2: mapper + record `$TGT_BLK` + `G5D_TYPE=` → refuse; no umount, close or mount.
  - **H2: mapper + record `$TGT_BLK` + `G5D_TYPE=ext4` → the restore runs, with
    `mount $TGT_BLK <mnt>`. This is the pre-wipe web-1 shape and proves the bug is fixed.**
  - H1: plaintext mounted, no marker → the restore runs (existing).
  - Delete the old "markerless, label gone" row.
- **Arm rows** (freeze suite or G5d harness):
  - A1: `PLAINTEXT_DEV_UNSEEDED=1` → `arm_refused reason=plaintext_dev_unrecorded`, and no
    `systemd-run` in the calls.
  - A2: record `x'; logger INJECTED; '` → refused; no `systemd-run`.
  - A3: record = `$MAPPER` → refused.
  - A4: `BLKID_ABSENT=1` → refused.

**Freeze T35/T42b.** Rollback mounts the seeded record: `^mount /dev/sdz9[[:space:]]`.

**Loopback session W** (real devices, real blkid). Each probe first calls `seed_state`, so no wipe
marker is present.

- LW-P1: LW1a now runs on an **unlabelled** ext4 loop with the record = the loop →
  `rehearsal_ok label=none plaintext_dev=<loop>`.
- LW-P2: the real `_plaintext_gone`, with `WL_MOUNT` on the mapper and the record = the intact loop
  → not gone (rc 1).
- LW-P3: after LW1's real zero, with `seed_state` re-run, the same probe → gone
  (`why=plaintext_dev_gone`).

## Domain Review

**Domains relevant:** Engineering, Product (sign-off), Legal (one record field)

### Engineering

**Status:** reviewed. The CTO assessment and the devex panel folded in:

- the drift residual and the recovery wording;
- the dead-man row rewrite;
- the rationale and keep-in-sync comments;
- the non-hardcoded expected value.

### Legal

**Status:** reviewed (inline). A single destruction-record field changes, from an asserted label to
the recorded identity. The value stays unfilled until the row exists. Lawful basis, retention and the
Art. 17 `plaintext_only` accounting are untouched.

### Product/UX Gate

Not applicable. No UI surface is touched (tier NONE). The CPO sign-off is in User-Brand Impact.

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-119's 2026-09-28 addendum with the two sentence swaps in Phase 4. No new ADR is needed: this
corrects a false premise inside an existing decision.

### C4 views

No impact.

- `git grep -c workspaces_plain` over `knowledge-base/engineering/architecture/diagrams/{model,views,spec}.c4`
  exits 1.
- The change adds no actor, system, container or relationship. The only "labels" mention there is the
  `github -> hetzner` edge's Hetzner API labels-PUT probe, which is unrelated.

## Risks

- **Kernel-name drift (`/dev/sdX` after a reboot). This is the main residual.**
  - `PLAINTEXT_DEV` is a kernel name. If web-1 rebooted after 2026-07-23 (for example the C15 proof
    reboot), the record may now name another device. W6 then refuses, and Guard 5 reads "gone": both
    fail closed. The refusal rows print `recorded_real=` / `recorded_type=` to tell drift from a
    wipe.
  - There is deliberately no host-side re-record path. Recovery is a reviewed fix-forward. File it
    only if the post-merge rehearsal shows drift.
  - Pre-wipe, a *different ext4* volume taking the recorded name would let rollback mount a foreign
    filesystem. This is not new exposure: rollback already mounted `PLAINTEXT_DEV`.
  - The sequencing of the C15 proof relative to the wipe is recorded as a decision challenge in
    `decision-challenges.md`.
- **Lost state file.** Guard 5 then refuses every rollback on a mapper mount, and W3 already refuses
  the wipe (`wipe_canary_ok_absent`). This is fail-closed, but it strands a still-intact plaintext as
  a rollback source. Accepted, since rollback's only remount source is that record.
- **A BEGUN marker with the plaintext still intact** (early `blkdiscard` failure, or `gate_rc=97`).
  Rollback stays refused (PR A design, unchanged). Recovery is re-dispatch of the wipe (`re_zero`),
  not rollback. The runbook wording says "the copy may be partly or wholly zeroed".
- **This fix re-enables two paths the bug refused.**
  - An acknowledged pre-wipe `ROLLBACK`. That is by design of the ack, and W9 then refuses the wipe.
  - A pre-wipe dead-man fire on the mapper. W7 refuses the wipe while a dead-man is armed, and the
    runbook row now says so explicitly.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, holds only `TBD`/`TODO`/placeholder text, or
  omits the threshold fails `deepen-plan` Phase 4.6.
- The wipe suite's C3 finds PR A's plan by `*feat-workspaces-plaintext-volume-wipe-plan.md`. This
  plan's filename deliberately does not match it.
- `seed_state` in the loopback suite must write its default `PLAINTEXT_DEV=$WP_DEV` before the
  caller's `$1`. The caller's line then wins (`read_state` is last-wins), which G1-R3's logic relies
  on.
- The harness seam is inside a single-quoted `bash -c` body, so write it with no apostrophes.
- Bake `${dev}` unquoted only because arm validation guarantees `[A-Za-z0-9/_.:-]+`. Never relax the
  charset without re-adding quoting and the A2 injection row.
- Do not edit the postmortem or anything under `archive/`.
