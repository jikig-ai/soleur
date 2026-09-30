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

## Enhancement Summary

**Deepened on:** 2026-09-30.

**Sections enhanced:** Phase 2 (script design), Phase 3 (suites), Guard Contract, Test Scenarios,
User-Brand Impact, Observability, Risks, Acceptance Criteria.

**Agents used:**

- Plan phase: CTO, CPO (sign-off), the ADR-083 advisor, a sharp-edges catalogue pass, DHH, Kieran,
  code-simplicity, architecture-strategist, spec-flow, and a CTO devex pass.
- Deepen phase: security-sentinel, user-impact-reviewer, test-design-reviewer,
  observability-coverage-reviewer, and a verify-the-negative / post-edit self-audit pass.

The deepen skill says to run every discovered agent. That fan-out was narrowed to the reviewers
relevant to a bash infra fix-forward, which had already passed an 11-agent plan panel. This note
discloses the narrowing.

### Key Improvements

1. **One shared record validator, used at every reader.** `_plaintext_dev_valid` requires `/dev/`,
   a strict charset, and rejects `..` and `//`. It closes option injection into `mount` and `blkid`,
   and non-device or NFS-shaped values, at W6, in `_plaintext_gone`, in `rollback()` and in
   `arm_dead_man` (security P1-1).
2. **`arm_dead_man` refuses to arm without a restorable record.** A restorable record is one that is
   valid, is not the mapper by `readlink -f`, is a block device carrying ext4, and has `blkid`
   resolvable from a fixed root-owned path list, never from `command -v`. Otherwise it dies
   pre-freeze with a discriminating `detail=` (advisor, spec-flow, architecture, security).
3. **The fire and the rollback refusals now discriminate.** They print `why=marker|plaintext_dev_gone`,
   `recorded=` and `recorded_type=` (incl. `blkid_unavailable`), and the fire's restore rows print
   `mount_source=`. Stale-record drift can no longer page as "wiped" (observability P1-2 / P2-3/4).
4. **The test design is hardened.**
   - Stubs check their argv.
   - A writer→reader row covers the rehearsal step.
   - Arm rows are modelled on T33 (`DRY_RUN=0`).
   - A must-PASS `label=other` row is added.
   - The resume row uses a *wrong* record.
   - The mutation battery gets a pristine control and function-scoped edits.
5. **Defects fixed:**
   - a knob/global name collision (`PLAINTEXT_DEV_TYPE` → the harness knob `PLAINTEXT_DEV_FSTYPE`);
   - a `set -u` unbound variable on the marker arm;
   - an LW1a assertion that the new seed would break;
   - a vacuous "loopback arm" step (the loopback suite never arms).

### New Considerations Discovered

- **The fix makes a pre-wipe dead-man fire restore.** Such a fire would remount the stale 2026-07-23
  plaintext over live LUKS. The W7 refusal and S6 are now the only protections, and the runbook says
  so.
- **The C15 reboot ordering versus the wipe decides whether `PLAINTEXT_DEV` still names the plaintext.**
  This is recorded as decision challenge DC-3.
- **A second `ROLLBACK=1` on a non-mapper mount with a drifted record** still unmounts the live
  plaintext before its remount fails. This is pre-existing and recorded as DC-4.

## Overview

PR A (#9163, merged 2026-09-30 as `403487494d`) added the `CONFIRM_WIPE` mode to
`apps/web-platform/infra/workspaces-cutover.sh`. Its read-only rehearsal (run `36710773788`,
`dry_run=true`) refused:

```text
SOLEUR_WORKSPACES_LUKS_WIPE ... result=refused arm=first_wipe volume_id=105149570 reason=wipe_target_label_mismatch label=none
```

Every other W0–W6 check passed: the `HC_Volume_105149570` serial, the size, not the mapper backing, no
holders, unmounted, ext4, and the header and escrow checks W3–W5.

**The cause is one false premise:** that web-1's retained plaintext volume carries the filesystem
label `workspaces_plain`.

- No production artifact writes that label. `soleur-host-bootstrap.sh` labels only `workspaces_luks`,
  and no `e2label` or `tune2fs -L` runs outside tests.
- The only writer is the loopback suite's own fixture (`new_plain`: `mkfs.ext4 -L workspaces_plain`).
  That fixture is why PR A's real-device rows stayed green on a premise production never met.

**Two defects share the premise.**

1. **W6 (wipe identity).** `wipe_plaintext()` requires `blkid -p -s LABEL` to equal `workspaces_plain`
   on the `first_wipe` arm.
2. **Guard 5 (the "plaintext gone" witness).** These sites treat a missing
   `/dev/disk/by-label/workspaces_plain` as "the plaintext is gone":
   - `_plaintext_label_present` / `_plaintext_gone`, used by `rollback()` and
     `assert_rollback_not_post_cutover()`;
   - the inline `gone_guard` in the dead-man fire string.

   That link has never existed on web-1, so today, **pre-wipe**, they all read "gone" and refuse.

Also dead: `rollback()`'s first remount attempt (`mount /dev/disk/by-label/workspaces_plain`) and the
dead-man's `${dev:-/dev/disk/by-label/workspaces_plain}` fallback.

**The fix replaces the label with the identity the cutover actually recorded.** That identity is
`PLAINTEXT_DEV`, the plaintext's `findmnt -no SOURCE`. The cutover's rollback-rehearsal step persisted
it, and that step is its only writer.

- **W6** binds the target to that record.
- **Guard 5's physical witness** becomes: `$MOUNT` is on the mapper **and** the recorded device is not
  an intact plaintext. Not intact means invalid or unrecorded, resolving to the mapper, or
  `blkid -p -s TYPE` is not `ext4`.
- **The dead-man fire** carries the same test inline (`/bin/sh`, no helpers).
- **`arm_dead_man`** refuses to arm a backstop that has no restorable record.
- **The rehearsal row** keeps `label=` as **observed evidence** and gains `plaintext_dev=`.

**Scope.**

- This is a narrow fix-forward, not a redesign.
- No `.tf`, no dispatch, no prod writes.
- After merge, the read-only rehearsal is re-run. The destructive dispatch still needs its own
  per-command go-ahead.
- Refs #6604 #6588 (neither is closed).

## Research Reconciliation — Spec vs. Codebase

| Claim (task / PR A) | Reality (verified) | Plan response |
|---|---|---|
| The plaintext carries `LABEL=workspaces_plain` | No production producer exists. A repo-wide grep for `e2label`, `tune2fs -L`, `mkfs -L` and `LABEL=workspaces` finds only test fixtures. The rehearsal observed `label=none`. | Remove the premise. `label=` stays as evidence only. |
| `PLAINTEXT_DEV` = the plaintext mount source | The rollback-rehearsal step (`plain_dev="$(findmnt -no SOURCE "$MOUNT")"; persist_state PLAINTEXT_DEV "$plain_dev"`, under `DRY_RUN != 1`) is the ONLY writer, and it runs before `arm_dead_man` in the same run. | Bind W6 and Guard 5 to it. |
| On web-1 it is `/dev/sdb` | `/dev/sdb` comes from the 2026-07-20 postmortem (`mount_source=/dev/sdb`), not the state file. #9179 measured `reboot-required=yes` (not yet rebooted then). The task says web-1 has not rebooted since. | Nothing hardcodes `/dev/sdb`. The rehearsal row prints the record, and drift fails closed with diagnostics. |
| `PLAINTEXT_DEV` can never be the mapper | The rehearsal runs after `prepare_staging_target` (which refuses a cut-over host). The S6 row pins this. | Defend anyway (a `readlink -f` equality reads as gone, and the arm refuses). |
| The fire must stay "self-contained" | It already runs `cryptsetup`/`mount` by bare name under `systemd-run` (2026-07-20 fire). | Inline `blkid` by an absolute path from a fixed root-owned list, baked at arm time. |
| The workflow and T12/T12b/T12c need edits | The workflow parses only `plaintext_only=`/`io_max=`. T12b greps `if mount [^;]*; then`. | No edits there. Keep the `if mount <src> <mnt>; then` shape. |
| The loopback suite arms the dead-man | It never does: L7 only extracts `arm_dead_man`'s pre-clear lines with awk. | No loopback arm seeding. The new arm code must not add a line starting with `}`, nor a new dead-man-unit stop/reset-failed line, because either would change L7's extraction. |

## Research Insights

**Premise Validation.**

- #6604 and #6588 are OPEN.
- `403487494d` is PR A (#9163, MERGED). #9179 and #9098 are MERGED.
- Run `36710773788`'s log confirms that W0–W6 passed up to the label check.
- "Not rebooted since" cannot be checked read-only. The post-merge rehearsal is its verification.

**Property List.**

- P1: the first-wipe zero targets exactly the device the cutover recorded as the plaintext's mount
  source. This is additional to W1's by-id pin and W6's serial, size, path, major:minor, holders and
  mount checks.
- P2: on web-1 today (pre-wipe, unlabelled ext4) the rehearsal reaches `rehearsal_ok`.
- P3: with `$MOUNT` on the mapper, `rollback()`, `ROLLBACK` mode and the dead-man fire tear the mapper
  down only if the recorded device is valid, is not the mapper, and reads `ext4`. Otherwise they refuse
  with evidence that distinguishes a wipe from a stale record.
- P4: no code path depends on a filesystem label that no artifact writes.
- P5: the dead-man is never armed without a record that is valid, not the mapper, and an ext4 block
  device, with `blkid` resolvable from a fixed path.

**Cut List (reviewed and not done).**

- **A new `PLAINTEXT_BYID` / fs-UUID / serial state key.** P1 is covered by the pin plus the serial.
  A new key needs a cutover re-run, which is impossible post-cutover.
- **The binding on `re_zero`.** It could strand a resume, which is already bound by the marker and the
  serial.
- **A permanent census suite row, and parity or unit rows for a one-line seam.** One AC grep is
  enough, plus behavioural rows.
- **An arm refusal when `$MOUNT` is already the mapper.** S6 pins that arming is unreachable there,
  and adding it churns ~49 freeze-suite arm call sites.
- **Requiring the record to equal the live `$MOUNT` source at arm time.** It needs harness
  `findmnt`-per-row churn, and the arm is in the same run right after the writer.
- **Validating the other baked fire values** (`MOUNT`, `STAGING`, `CONTAINER` …). This is
  pre-existing and out of scope. It is noted in Risks.
- **Dropping `label=` evidence, or the fire's physical arm.** The operator specified both. They are
  kept and recorded as DC-1/DC-2.

**Institutional learnings applied.**

- `2026-09-28-a-dead-label-route-and-an-end-sample-that-reread-its-start.md`: grep for the producer.
- `2026-09-02-i-built-a-host-discriminator-out-of-an-absence-and-fixtured-the-absence.md`: use a
  positive type, not an absence.
- `2026-09-24-i-parked-a-fix-for-a-cause-i-never-tested-and-my-stubs-could-not-see-the-device.md`:
  every new stub checks its argv or device.
- `2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md`: must-PASS
  rows for every guard.

**Conventions.**

- Seams read no environment (S5).
- Every `_wipe_refuse` slug has a RED row (C1) and a runbook row (C2).
- Floors are raised to the measured count.
- No piping into assertion predicates.
- `cq-cite-content-anchor-not-line-number`.

**Measured facts** (deepen pass, GNU coreutils 9.11 / util-linux 2.42.3):

- `readlink -f /dev/<missing-leaf>` prints the path with rc 0.
- `readlink -f ""` and a missing parent print nothing with rc 1, so two failures compare equal. In
  `_plaintext_gone` that reads as "gone" (fail-closed). It cannot pass W6, because `$real` is
  non-empty there.
- `blkid -p -s TYPE -o value ""` or a missing path prints nothing with rc 2.
- `blkid -p -s LABEL -o value <unlabelled ext4>` prints nothing with **rc 0**.

## Implementation Phases

### Phase 1 — RED first (`cq-write-failing-tests-before`)

Write the Test Scenarios rows. Confirm each is RED on today's tree **for the stated reason**:

- G1-P1 (with `W_LABEL=` explicit) refuses `wipe_target_label_mismatch`;
- G5d-H2 refuses pre-wipe;
- G5b-H1's `SEAM _plaintext_dev_type /dev/sdz9` assertion fails (no seam yet);
- A1 arms (no validation yet).

### Phase 2 — `workspaces-cutover.sh`

1. **Delete the premise.** Remove `PLAINTEXT_LABEL=`, `_plaintext_label_present()` and their comment
   blocks.
2. **Validator and seams** (where `_plaintext_label_present` was):

   ```bash
   # _plaintext_dev_valid <v> — syntax only: an absolute /dev path of [A-Za-z0-9/_.:-] with no `..`/`//`.
   # Every reader of the recorded PLAINTEXT_DEV calls this first: the value is baked unquoted into the
   # root dead-man fire and passed to mount/blkid, so a leading `-`, a non-device or NFS-shaped string,
   # or a quote must never reach them. Pure: reads nothing but its argument.
   _plaintext_dev_valid() {
     local LC_ALL=C d="${1:-}"
     case "$d" in /dev/?*) ;; *) return 1 ;; esac
     case "$d" in *[!A-Za-z0-9/_.:-]*|*..*|*//*) return 1 ;; esac
     return 0
   }
   # _plaintext_blkid_bin — blkid from a fixed root-owned list, never `command -v` (a PATH-resolved or
   # function name baked into the unattended root fire is an exec primitive). SEAM; reads no environment.
   _plaintext_blkid_bin() { local b; for b in /usr/sbin/blkid /sbin/blkid /usr/bin/blkid /bin/blkid; do [ -x "$b" ] && { printf '%s' "$b"; return 0; }; done; return 0; }
   # _plaintext_dev_type <dev> — the blkid TYPE of the recorded plaintext (the device rollback remounts):
   # `ext4` = intact; empty = unrecorded/absent/zeroed; `blkid_unavailable` = cannot tell. Identity is the
   # cutover's recorded mount source, not a filesystem label — no artifact labels the retained plaintext
   # (ADR-119, corrected 2026-09-30). SEAM; reads only its argument.
   # KEEP IN SYNC with arm_dead_man's inline gone_guard.
   _plaintext_dev_type() {
     local b; [ -b "${1:-}" ] || return 0
     b="$(_plaintext_blkid_bin)"; [ -n "$b" ] || { printf blkid_unavailable; return 0; }
     "$b" -p -s TYPE -o value "$1" 2>/dev/null || true
   }
   ```

3. **`_plaintext_gone`.**
   - First statement: `PLAINTEXT_GONE_WHY=""; PLAINTEXT_DEV_SEEN=""; PLAINTEXT_DEV_TYPE=""`. This
     avoids an unbound variable under `set -u` on the marker arm. The marker arm is otherwise
     unchanged. It is written as `PLAINTEXT_GONE_WHY=marker`.
   - The physical arm:

     ```bash
     if [ "$(findmnt -no SOURCE "$MOUNT" 2>/dev/null || true)" = "$MAPPER" ]; then
       pdev="$(read_state PLAINTEXT_DEV)"; PLAINTEXT_DEV_SEEN="${pdev:-none}"
       # readlink equality, NOT _same_dev: _same_dev returns "different" when readlink fails or the mapper
       # is not a block device — the wrong direction here, where unknown-or-same must read as gone.
       if ! _plaintext_dev_valid "$pdev" \
          || [ "$(readlink -f -- "$pdev" 2>/dev/null)" = "$(readlink -f -- "$MAPPER" 2>/dev/null)" ]; then
         PLAINTEXT_GONE_WHY=plaintext_dev_gone; PLAINTEXT_DEV_TYPE=invalid; return 0
       fi
       PLAINTEXT_DEV_TYPE="$(_plaintext_dev_type "$pdev")"
       [ "$PLAINTEXT_DEV_TYPE" = ext4 ] || { PLAINTEXT_GONE_WHY=plaintext_dev_gone; return 0; }
     fi
     ```

     `pdev` is declared `local`. The header comment says:
     - the physical arm reads the state file for *which* device to probe;
     - a lost or invalid record reads as "gone";
     - that is fail-closed, but it strands a still-intact plaintext as a rollback source (Risks).
   - **Neutral, discriminating refusals.** Three sites change:
     - `rollback()`'s refusal `log`;
     - `assert_rollback_not_post_cutover()`'s `_rollback_refuse` message;
     - the `ROLLBACK REFUSED` `die`.

     Their wording becomes "no intact recorded plaintext to remount (why=…) — a wipe began, OR the
     record is stale/unreadable; read recorded_type". Each carries
     `why=$PLAINTEXT_GONE_WHY recorded=$(_deadman_detail "${PLAINTEXT_DEV_SEEN:-none}") recorded_type=$(_deadman_detail "${PLAINTEXT_DEV_TYPE:-none}")`.
     `_deadman_detail` maps `=` to `_`, so no field can be forged.
   - **Off-host row.** Append the same three fields, *after* the existing ones, to the
     `result=cutover_aborted outcome=refused_plaintext_wiped` row. Existing fixed-substring asserts
     still match. `emit_drift` carries only the slug, so this row is the Better Stack evidence.
   - Update the `assert_rollback_not_post_cutover` comment that says "the plaintext label gone".
4. **`rollback()` remount.** Replace the by-label-then-record pair with:

   ```bash
   pdev="$(read_state PLAINTEXT_DEV)"
   if _plaintext_dev_valid "$pdev"; then mount "$pdev" "$MOUNT" 2>/dev/null || true; fi   # never an option-shaped record
   ```

   The #9098 C source check after it is unchanged, and pages `rollback_remount_failed` on any miss.
   The comment becomes "its recorded mount source, never the mapper".
5. **`arm_dead_man`.** Changes, after `dev="$(read_state PLAINTEXT_DEV)"`, which already runs after
   the `DRY_RUN=1` early return:
   1. **Validation.** It is pre-freeze and has no side effects.
      - Use no brace group whose `}` starts a line, and add no new dead-man-unit stop/reset-failed
        line. The loopback L7 awk extraction keys on both.
      - Add `blkid_bin why_bad` to `local`.

      ```bash
      blkid_bin="$(_plaintext_blkid_bin)"; why_bad=""
      if [ -z "$blkid_bin" ]; then why_bad="blkid_absent"
      elif ! _plaintext_dev_valid "$dev"; then why_bad="record_invalid:${dev:-empty}"
      elif [ "$(readlink -f -- "$dev" 2>/dev/null)" = "$(readlink -f -- "$MAPPER" 2>/dev/null)" ]; then why_bad="record_is_mapper:$dev"
      elif [ "$(_plaintext_dev_type "$dev")" != ext4 ]; then why_bad="record_not_ext4:$dev"
      fi
      if [ -n "$why_bad" ]; then
        _deadman_row "result=arm_refused reason=plaintext_dev_unrecorded detail=$(_deadman_detail "$why_bad")"
        emit_drift deadman_arm_failed
        die "no restorable recorded plaintext device ($(_vscrub "$why_bad")) — a dead-man armed now could unmount \$MOUNT and restore nothing. Refusing to arm; nothing is frozen (runbook: deadman_arm_failed)"
      fi
      ```

      After this, `$dev` and `$blkid_bin` are charset-safe absolute paths. They are baked
      **unquoted**, like the existing mount clause, so there are no quoting layers.
   2. **Split `gone_guard`** into two `if`s, both before any stop, umount or close. Keep the existing
      fixed prefix `… result=fail reason=refused_plaintext_wiped`, which the luks-monitor census
      matches as a substring.
      - The marker `if` logs `… why=marker` and exits.
      - The physical `if` computes `t=$(${blkid_bin} -p -s TYPE -o value ${dev} 2>/dev/null)`. When
        `[ "$(findmnt -no SOURCE ${MOUNT} …)" = ${MAPPER} ] && [ "$t" != ext4 ]`, it logs
        `… why=plaintext_dev_gone recorded=${dev} recorded_type=${t:-none}` and exits.

      `$t` is an sh variable, so escape it as `\$t` and use double-quoted logger text for that row.
      Add a `KEEP IN SYNC with _plaintext_dev_type / _plaintext_gone` comment. Verify by running the
      captured string through `sh -n` and G5d, not by reading the source.
   3. **Mount clause.** `if mount ${dev:-/dev/disk/by-label/workspaces_plain} ${MOUNT}; then` becomes
      `if mount ${dev} ${MOUNT}; then`, keeping T12b's shape. Append `mount_source=${dev}` to both the
      `result=ok reason=plaintext_remounted` and `result=fail reason=remount_failed` rows.
   4. Rewrite the `#6604 step 7` comment block: "the recorded plaintext device no longer an intact
      ext4". Also state that after this fix a pre-wipe fire on a cut-over host *restores* the stale
      copy, which is why S6 and W7 matter.
6. **W6 in `wipe_plaintext()`** (`first_wipe` only). Replace the label equality:

   ```bash
   label="n/a"; pdev="n/a"
   if [ "$WIPE_ARM" = first_wipe ]; then
     label="$(blkid -p -s LABEL -o value "$real" 2>/dev/null || true)"; label="${label:-none}"   # observed evidence only
     pdev="$(read_state PLAINTEXT_DEV)"
     { _plaintext_dev_valid "$pdev" && [ "$(readlink -f -- "$pdev" 2>/dev/null)" = "$real" ]; } \
       || _wipe_refuse wipe_target_not_recorded_plaintext \
         "the target resolves to '$real', but the plaintext mount source this cutover recorded (PLAINTEXT_DEV) is '$(_vscrub "${pdev:-<unrecorded>}")' — the zero may only hit the device the cutover itself took the copy from" \
         "target=$real" "recorded=${pdev:-none}" "recorded_real=$(readlink -f -- "$pdev" 2>/dev/null || echo none)"
   fi
   ```

   - `emit_wipe` scrubs every field through `_wv`.
   - Add `pdev` to `local`.
   - Add `"plaintext_dev=$pdev"` next to `"label=$label"` on `rehearsal_ok`.
   - The W7 comment "(its fire command remounts the plaintext by label)" becomes "by its recorded
     `PLAINTEXT_DEV`".
7. **Post-edit.** `workspaces_plain` appears nowhere in the script. The rationale comments name "a
   filesystem label" generically.

### Phase 3 — seams and suites

- **`workspaces-luks-harness.sh`** (inside the single-quoted `bash -c` body, so no apostrophes):
  - Seams:

    ```bash
    _plaintext_dev_type() { rec "SEAM _plaintext_dev_type ${1:-}"; [ -n "${1:-}" ] || return 0; printf "%s" "${PLAINTEXT_DEV_FSTYPE-ext4}"; }
    _plaintext_blkid_bin() { [ "${BLKID_ABSENT:-}" = "1" ] && return 0; printf "%s" "${BLKID_BIN_PATH:-blkid}"; }
    ```

    The knob is **`PLAINTEXT_DEV_FSTYPE`**, not `PLAINTEXT_DEV_TYPE`. That name is the script's
    global, and a shared name would be clobbered.
  - The default seed goes after `source "$CUTOVER"` and before `eval "$INVOCATION"`:
    `[ "${PLAINTEXT_DEV_UNSEEDED:-}" = 1 ] || persist_state PLAINTEXT_DEV /dev/sdz9`. An invocation's
    own `persist_state` wins, because reads are last-wins.
  - Replace the `PLAINTEXT_LABEL_ABSENT` knob documentation with `PLAINTEXT_DEV_FSTYPE` /
    `PLAINTEXT_DEV_UNSEEDED` / `BLKID_BIN_PATH`.
- **`workspaces-luks-wipe.test.sh`.**
  - Delete the stub world's dead `_plaintext_label_present` override.
  - The `blkid` `LABEL` default is empty with **rc 0** (measured).
  - `dumpe2fs` prints `<none>`. That is cosmetic, because the script never parses it.
  - `run_wipe`'s default seed gains `PLAINTEXT_DEV=$TGT_BLK`.
  - The happy-path field list uses `label=none plaintext_dev=$TGT_BLK`.
  - Replace the W6 label refusal row with the G1 rows.
  - S5: add `_plaintext_blkid_bin` and `_plaintext_dev_type` to both seam regexes. Drop the
    `PLAINTEXT_LABEL` allowance and `pl_lit`. `seam_n` becomes 6.
  - G5d:
    - The instrument guard becomes `[ -z "$G5D_FIRE" ] || ! grep -qF 'blkid' <<<"$G5D_FIRE"` → INSTRUMENT
      fail.
    - `g5d_arm <record> [env]` re-arms per row and rebinds **both** `G5D_FIRE` and `G5D_STATE`.
    - `G5D_BIN/blkid` is its own script. It logs its argv. It exits 64 with `blkid-unexpected` unless
      the argv is exactly `-p -s TYPE -o value $G5D_EXPECT_DEV`. Otherwise it prints `$G5D_TYPE`, and
      exits rc 2 when that is empty. Arm with `BLKID_BIN_PATH=$G5D_BIN/blkid`.
    - The `findmnt` stub requires `-no SOURCE <mnt>`.
  - Rename every row title or comment that says "label" (G5b/G5c/G5d). The AC grep covers
    `apps/web-platform/infra`.
  - Raise `WIPE_MIN_PASS` from 143 to the measured count.
- **`workspaces-luks-freeze.test.sh`.**
  - T35/T42b: `has '^mount /dev/disk/by-label/workspaces_plain '` becomes
    `has '^mount /dev/sdz9[[:space:]]'`. Add the same assert to T5, so the seed is pinned.
  - Add arm rows A1–A6.
  - Raise `FREEZE_MIN_PASS` from 170 to the measured count.
- **`luks-monitor.test.sh`.** Add `"result=arm_refused reason=plaintext_dev_unrecorded"` to the
  `_deadman_row` census.
- **`workspaces-luks-loopback.test.sh`.**
  - `new_plain` formats **unlabelled**; update its comment.
  - `seed_state` appends `PLAINTEXT_DEV=$WP_DEV` *before* its optional `$1`, so a caller's line wins.
  - LW1a's marker assertion becomes `! grep -qE '^PLAINTEXT_WIPE(_BEGUN|D)=' …`, because the seed now
    writes `PLAINTEXT_DEV=`.
  - Add LW-P1..LW-P4, ordered before `new_plain lw4`.
  - No arm seeding: this suite never arms.

### Phase 4 — docs (same PR)

- **Runbook `workspaces-luks-cutover-6604.md`.**
  - **Step 7b expected row.** Replace `label=workspaces_plain` with
    `label=<observed; none on web-1> plaintext_dev=<as printed; must resolve to target=>`.
    - Add a line: if a reboot (e.g. C15) happened after 2026-07-23, the record may name another
      device and the rehearsal refuses (below).
    - Add a line: read and record `plaintext_only=` and each `plaintext_only_name` row *before* the
      destructive dispatch is authorised. This is unchanged PR A policy, restated.
  - **Verdict table.** Drop `wipe_target_label_mismatch` and add:

    ```text
    | `wipe_target_not_recorded_plaintext` | No | No | The first-wipe target is not the device this cutover recorded as the plaintext's mount source. Compare `target=` with `recorded=`/`recorded_real=`: `none` = the record is missing or invalid; a different device = kernel-name drift after a reboot (then `rollback()`'s and the dead-man's remount source is stale too — do not dispatch `rollback=true` or a cutover either). Nothing was written. Do NOT append `PLAINTEXT_DEV=` to the state file by hand: the record is evidence of what the cutover took the copy from, and a hand-written value is not. Halt and escalate; the remedy is a reviewed fix-forward PR (a serial-anchored record step), not a host edit. | End the pause (above) |
    ```

  - **`wipe_deadman_armed` row.** Rewrite it in full. After this fix, a dead-man fire on this host
    *restores*: it would remount the stale 2026-07-23 plaintext over `/mnt/data`. The W7 refusal is
    therefore the only protection. Keep "halt and escalate — do not let it fire".
  - **The "After Sequence step 7 there is no rollback" paragraph and the two `refused_plaintext_wiped`
    rows** (the `rollback()` one and the dead-man one). Rewrite them to say the refusal fires when:
    - the wipe began (`why=marker`; the copy may be partly or wholly zeroed; recovery is re-dispatch
      of the wipe on `re_zero`, not rollback), OR
    - the mapper is mounted and the recorded `PLAINTEXT_DEV` is not an intact ext4
      (`why=plaintext_dev_gone`).

    Then read `recorded_type=`:
    - `none` = zeroed or absent;
    - `crypto_LUKS` or another type = a stale record (drift), not a wipe — escalate;
    - `blkid_unavailable` or `invalid` = cannot tell — escalate.
  - **Rollback section.** Add one sentence: an acknowledged pre-wipe `rollback=true` remounts the
    plaintext read-write, and W9 then refuses the wipe (`wipe_plaintext_written_after_cutover`).
  - **`deadman_arm_failed` / `arm_refused` row.** Add `reason=plaintext_dev_unrecorded`.
    `detail=` is one of `blkid_absent`, `record_invalid:`, `record_is_mapper:` or `record_not_ext4:`.
    Nothing was frozen.
- **ADR-119** (the 2026-09-28 addendum; two sentence swaps, no new ADR):
  - "hypervisor `ID_SERIAL` + the `workspaces_plain` label (W6)" becomes "… + the cutover's recorded
    plaintext mount source `PLAINTEXT_DEV` (W6; the label premise was false — no artifact labels the
    retained plaintext, corrected 2026-09-30)".
  - "`/mnt/data` on the mapper with the plaintext label gone (the physical witness does not depend on
    the state file)" becomes "`/mnt/data` on the mapper with the recorded `PLAINTEXT_DEV` invalid,
    resolving to the mapper, or no longer ext4 (a lost record reads as gone: it refuses)".
- **`knowledge-base/legal/audits/workspaces-plaintext-destruction-record.md`.**
  - The field becomes `format / observed label / recorded mount source`, with source "the rehearsal
    row's `label` and `plaintext_dev`".
  - The value stays a `(fill …)` placeholder, filled post-merge from the row.
- **Do not edit:**
  - the postmortem (historical);
  - anything under `archive/`;
  - `luks-monitor-install.test.sh`'s synthesized `LABEL=workspaces_plain` fstab fixture. Web-1's real
    line is the #9179 mapper pin.

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

- **Every workspace owner: sole-copy loss.** W6 admits the wrong device, and `blkdiscard -z` zeroes
  the LUKS backing. That destroys the only copy of every workspace: source, branches and
  `refs/checkpoints/*`.
  - *Mitigation:* the binding is additive to the pin, serial, size, path, major:minor, holders and
    mount checks. The zero stays behind a separate go-ahead.
- **App user: workspaces offline.**
  - A wrong "intact" verdict lets rollback or a fire unmount the mapper with nothing valid to remount.
    *Mitigation:* validator, mapper-alias and ext4 checks in `_plaintext_gone` and the fire.
  - A dead-man armed with no restorable record would, mid-freeze, unmount the live plaintext and
    restore nothing. *Mitigation:* P5 arm validation.
- **Workspace owner: stale data served.** After this fix a pre-wipe fire *restores* the 2026-07-23
  plaintext over live LUKS, which hides every later write.
  - *Mitigation:* S6 (arming is unreachable on a cut-over host), W7, and the rewritten
    `wipe_deadman_armed` row.
- **Workspace owner: a foreign filesystem at `/mnt/data`.** After a reboot, another ext4 whole-disk
  volume could inherit the recorded kernel name.
  - *Mitigation:* web-1 carries exactly two volumes (plaintext and LUKS) plus a partitioned root disk
    whose whole-disk node has no TYPE, so this needs a third attached volume. The record is also
    `readlink`-bound (Risks).
- **Operator: a needed rollback refused.** A wrong "gone" verdict does this (today's bug). Refusals
  now print `recorded_type=` to tell drift from a wipe.

**If this leaks, the user's data is exposed via:** a plaintext copy of every workspace on an
unencrypted Hetzner volume, while the wipe stays blocked (for example by drift). That contradicts the
privacy policy's encryption-at-rest claim (#6588). The drift remedy is a named fix-forward (runbook
row), and the sequencing choice is DC-3.

**Scoped out (unchanged PR A policy):** losing plaintext-only workspaces is gated by W9 provenance
plus the operator's `plaintext_only=` review. This PR does not change it.

**Brand-survival threshold:** single-user incident.

CPO plan-time sign-off (2026-09-30): **yes, conditional**. All conditions are folded in:

- the serial stays a hard gate;
- wrong-device and letter-drift rows (G1-R2, G5b-D, G5d-D);
- any ambiguity refuses;
- the destructive dispatch keeps its per-command go-ahead;
- `soleur:engineering:review:user-impact-reviewer` runs at review.

## Guard Contract

### Guard 1 — W6 recorded-plaintext binding

**Property.** On the `first_wipe` arm the zero proceeds only if the LAST recorded `PLAINTEXT_DEV` is
valid and its canonical path equals the target's.

**Assembly.**

- One chokepoint: `wipe_plaintext()` W6, `first_wipe` arm, between the serial check and W6b. Its
  `$real` is what W6b, W8, W9 and the act's `wipe_target_changed` re-check consume.
- One writer: the rollback-rehearsal step's `persist_state PLAINTEXT_DEV`, covered by the W-row.
- One reader: `read_state`, last-wins.

**Mutation matrix.** Each edit is scoped to the named function.

| # | Mutation | Row that must go RED |
|---|---|---|
| M1 | Delete the binding | G1-R2 (record = LUKS backing) reaches `rehearsal_ok` |
| M2 | Drop `_plaintext_dev_valid` from W6 | G1-R4 (record `-o`) reaches the readlink compare and is not refused for the right reason (assert `recorded=-o` + slug) |
| M3 | Own dispatch: gate the binding on `re_zero` | G1-R1/R2 reach `rehearsal_ok`, and G1-H3 (re_zero + wrong record) refuses |
| M4 | Second member: read the FIRST `PLAINTEXT_DEV=` line | G1-R3 (first = target, last = LUKS) reaches `rehearsal_ok` |
| M5 | Compare the record unresolved (drop `readlink -f` in W6 only) | G1-P2 (record is a symlink alias) refuses |
| M6 | Re-introduce any label requirement | G1-P1 (`W_LABEL=`) and G1-H2 (`W_LABEL=other`) refuse |
| M7 | The writer persists `$MAPPER` (or `$MOUNT`) | The W-row (the last state line must be the plaintext source) |

**Harness rows.**

- H1 (suite edit → RED): drop `W_LABEL=` from G1-P1 *and* restore the stub's label default. G1-P1's
  `label=none` assertion goes RED.
- H2 (must-PASS, non-canonical): G1-P2 (alias) and G1-H2 (`label=other`).

**Anchor.** The record was written on-host by the 2026-07-23 cutover run, outside any commit. The pin
and serial are anchored by the Hetzner API (preflight).

### Guard 2 — Guard 5 physical witness and the dead-man arm

**Property.** With `$MOUNT` on the mapper and no wipe marker, `rollback()`, `ROLLBACK` mode and the
fire tear the mapper down only if the recorded `PLAINTEXT_DEV` is valid, not the mapper (by
`readlink -f`), and reads `blkid TYPE=ext4`. The dead-man arms only with such a record and a `blkid`
from the fixed list.

**Assembly.**

- Consumers:
  - `rollback()` line 1 and `assert_rollback_not_post_cutover()` line 1, via `_plaintext_gone`;
  - `arm_dead_man`'s validation;
  - its split `gone_guard` spliced into the fire.
- Two implementations of the ext4 test: `_plaintext_dev_type` (seam) and the fire's inline
  `${blkid_bin}` clause. Each carries a keep-in-sync comment.
- Census, comment-stripped:
  - 2 `if _plaintext_gone;` call sites;
  - 1 `_plaintext_dev_type "$pdev"` in `_plaintext_gone`, plus 1 in `arm_dead_man`;
  - 1 `${gone_guard}` splice.

**Mutation matrix.** Each edit is function-scoped. Only rc=1 counts as caught, and the pristine tree
must pass first.

| # | Mutation | Row that must go RED |
|---|---|---|
| M1 | Physical arm never fires (drop the `!= ext4` return) | G5b-R1 (fstype none) rolls back |
| M2 | Physical arm treats any non-empty type as intact | G5b-D (`crypto_LUKS`) and G5b-B (`blkid_unavailable`) roll back |
| M3 | Wrong key or empty argument to the seam | G5b-H1's `SEAM _plaintext_dev_type /dev/sdz9` assertion |
| M4 | Drop the mapper-identity clause | G5b-M (record = `$MAPPER`, fstype ext4) rolls back; LW-P4 (record = real `dm-N`) reads intact |
| M5 | Drop `_plaintext_dev_valid` in `_plaintext_gone` | G5b-V (record `-o`, fstype ext4) rolls back |
| M6 | Fire: drop the physical `if` | G5d-R2 / G5d-D tear down |
| M7 | Fire: bake the wrong device into the blkid clause | G5d-H2 (the blkid stub exits 64 `blkid-unexpected`) |
| M8 | Own dispatch: `${gone_guard}` not spliced | G5d-R1 (marker) tears down |
| M9 | Second member: remove `assert_rollback_not_post_cutover`'s copy (keep `rollback()`'s) | the G5 `mode=rollback` rows (the outcome slug changes) |
| M10 | Arm: drop `blkid_absent` / `record_invalid` / `record_is_mapper` / `record_not_ext4`, one per clause | A4 / (A1, A2, A6) / A3 / A5 respectively. Under the `record_invalid` mutant, A2's fire, run via the G5d runner, runs `logger INJECTED` |

**Harness rows.**

- H1: flipping the harness seed to UNSEEDED drives T5 (seed-pinned mount), T35, T42b and G5b-H1 RED.
  Record the list when first run.
- H2 (must-PASS, non-canonical): G5d-H2 (mapper + intact ext4 record → restores, with
  `mount_source=`) and LW-P2 (real blkid, intact).

**Anchor.** None: the predicate reads live device state.

## Observability

- **Layer 6, workflow run log:** host stdout streams through the CF-tunnel SSH bridge; `die` produces
  `::error::`.
- **Layer 3, vector → Better Stack:** the `luks-monitor` syslog tag, Source 4 `host_scripts_journald`.
  It covers `emit_wipe`, `_deadman_row` and the fire rows, and no new tag is added.
- **Sentry:** `emit_drift` (the slug only) through `workspaces-luks-emit.sh`'s direct envelope. This is
  additive and not a layer citation.

```yaml
liveness_signal:
  what: SOLEUR_WORKSPACES_LUKS_WIPE rows (result=rehearsal_ok|refused) carrying plaintext_dev= and observed label=; refusals carry reason=wipe_target_not_recorded_plaintext target= recorded= recorded_real=
  cadence: per dispatch (the read-only rehearsal is re-run after merge)
  alert_target: layer 6 failed-run view; layer 3 luks-monitor rows; Sentry op=workspaces-luks-drift
  configured_in: apps/web-platform/infra/workspaces-cutover.sh (emit_wipe, _wipe_refuse, emit_drift, _deadman_row, the dead-man fire string)
error_reporting:
  destination: layer 6 (run log, ::error:: from die) and layer 3 (vector luks-monitor tag); Sentry via emit_drift slugs
  fail_loud: result=refused reason=<slug> before die; arm refusal result=arm_refused reason=plaintext_dev_unrecorded detail=<cause>; rollback refusals and the cutover_aborted outcome row carry why= recorded= recorded_type=; fire rows carry why=, recorded_type= and mount_source=
failure_modes:
  - mode: the record no longer names the target (missing, invalid, or kernel-name drift)
    detection: layer 6 run log row result=refused reason=wipe_target_not_recorded_plaintext target= recorded= recorded_real=; layer 3 same row via luks-monitor tag
    alert_route: Sentry workspaces_luks_drift (warning on a rehearsal, fatal on a real run) plus the failed run
  - mode: Guard 5 refuses (a wipe began, or a stale/unreadable record)
    detection: layer 6 (ROLLBACK dispatch log with why=/recorded_type=) and layer 3 (cutover_aborted outcome=refused_plaintext_wiped row with why=/recorded=/recorded_type=; unattended dead-man row result=fail reason=refused_plaintext_wiped why= recorded_type=)
    alert_route: Sentry rollback_refused_plaintext_wiped; Better Stack dead-man rows
  - mode: dead-man arm refused (no restorable record, or no blkid)
    detection: layer 6 (die) and layer 3 (_deadman_row result=arm_refused reason=plaintext_dev_unrecorded detail=)
    alert_route: Sentry deadman_arm_failed
logs:
  where: GitHub Actions run logs for workspaces-luks-cutover.yml; web-1 syslog tag luks-monitor -> vector -> Better Stack
  retention: Actions 90 days; Better Stack per source retention
discoverability_test:
  command: grep -c -e '^[^#]*_wipe_refuse wipe_target_not_recorded_plaintext' apps/web-platform/infra/workspaces-cutover.sh
  expected_output: "1"
```

The probe proves that the refusal site exists as code, not as a comment. The live verification is the
post-merge rehearsal row (Acceptance Criteria).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `grep -c 'workspaces_plain' apps/web-platform/infra/workspaces-cutover.sh` → `0`.
      `git grep -n 'wipe_target_label_mismatch' -- . ':!knowledge-base/project/plans' ':!knowledge-base/project/specs'`
      prints nothing.
- [ ] `git grep -n -i -e 'plaintext label' -e 'label gone' -e 'label_absent' -e 'PLAINTEXT_LABEL' -e '_plaintext_label_present' -- apps/web-platform/infra knowledge-base/engineering knowledge-base/legal`
      prints nothing, except ADR-119's "corrected 2026-09-30" clause and the untouched postmortem.
- [ ] Comment-stripped census (`grep -vE '^[[:space:]]*#' apps/web-platform/infra/workspaces-cutover.sh | grep -c …`):
  - `persist_state PLAINTEXT_DEV` → `1`;
  - `if _plaintext_gone;` → `2`;
  - `_plaintext_dev_type "` → `2` (the physical arm plus the arm validation);
  - `${gone_guard}` → `1`;
  - `command -v blkid` inside `arm_dead_man` → `0`.
- [ ] Wipe suite C1 (floor ≥25) and C2 pass, with `wipe_target_not_recorded_plaintext` in and
      `wipe_target_label_mismatch` out. C3 still passes. S5 counts 6 seams.
- [ ] These exit 0 on the edited tree: `bash apps/web-platform/infra/workspaces-luks-wipe.test.sh`
      (unprivileged, outside `disk`), `workspaces-luks-freeze.test.sh`, and `luks-monitor.test.sh`.
      `WIPE_MIN_PASS` is raised from 143, and `FREEZE_MIN_PASS` from 170, to the measured counts.
- [ ] `sudo bash apps/web-platform/infra/workspaces-luks-loopback.test.sh` exits 0, locally or in the
      `infra-validation.yml` loopback job, including LW1a (the new assertion) and LW-P1..LW-P4.
- [ ] Mutation battery:
  - the pristine tree passes first;
  - each Guard 1 M1–M7 and Guard 2 M1–M10 edit is applied **inside its named function** (the diff hunk
    is checked to fall in that function's range) and gives rc=1 with its named row RED;
  - rc ≥2 is treated as instrument failure;
  - the result is a `mutation | function | row | rc` table in the PR body;
  - `python3 scripts/lint-guard-contract.py <this plan>` → exit 0.
- [ ] `shellcheck` is clean on the edited scripts, `bash -n` passes on each suite, and the captured fire
      string passes `sh -n` (G5d).
- [ ] The runbook, ADR-119 and destruction-record edits match Phase 4. The record value is still
      `(fill …)`.
- [ ] `git diff --name-only origin/main...HEAD | grep -cE '\.tf$|^\.github/workflows/|cloud-init'` → `0`.

### Post-merge

- [ ] Automation (read-only, ungated under the ADR-119 rehearsal authorization): dispatch
      `gh workflow run workspaces-luks-cutover.yml -f confirm=WIPE-PLAINTEXT-USER-DATA-AP-009 -f wipe_plaintext=true -f expected_plaintext_volume_id=105149570`
      (`dry_run` defaults to true) and arm a watch on the run (`hr-dispatch-async-must-arm-watch`).
  - **Expected:** one `result=rehearsal_ok arm=first_wipe volume_id=105149570` row with `label=none`,
    and a `plaintext_dev=` that resolves to `target=`. Record `plaintext_only=`.
  - **Fails closed:** `wipe_target_not_recorded_plaintext` means the record is missing or has drifted.
    Halt per the runbook row.
- [ ] The destructive dispatch is **not** part of this PR's follow-through. It needs its own
      per-command go-ahead (`hr-menu-option-ack-not-prod-write-auth`).

## Test Scenarios

### Wipe suite, stubbed (`run_wipe`)

Paths under `$W_CASE_DIR` are built with `PRE_INV` (for example `ln -s …; persist_state
PLAINTEXT_DEV …`), because the directory is allocated inside `run_wipe`. G1 refusals assert the slug
plus `! state_has PLAINTEXT_WIPE_BEGUN`, `hdrs_gone`, and the row's evidence fields.

- **G1-P1 (production reproduction; RED today).** `W_LABEL=` explicit, record `$TGT_BLK` →
  `rehearsal_ok first_wipe` with exactly `label=none plaintext_dev=$TGT_BLK`.
- **G1-P2 (must-PASS alias).** `PRE_INV` records a symlink to `$TGT_BLK` → `rehearsal_ok`.
- **G1-H2 (must-PASS, label is evidence).** `W_LABEL=other` + a matching record → `rehearsal_ok label=other`.
- **G1-R1.** `SEED_STATE=CANARY_OK=1:$UUID_LIVE` (no record) → refuses with `recorded=none`.
- **G1-R2 (wrong device / letter drift).** `PRE_INV` symlinks `$W_CASE_DIR/dev/sdb` → `$LUKS_BLK` and
  records it → refuses with `recorded_real=<LUKS real>`. The serial still passes, which isolates the
  binding.
- **G1-R3 (last wins).** `PLAINTEXT_DEV=$TGT_BLK` then `PLAINTEXT_DEV=$LUKS_BLK` → refuses.
- **G1-R4 (option-shaped record).** Record `-o` → refuses with `recorded=-o`.
- **G1-H3 (resume unaffected).** The `re_zero` arm with a *wrong* record (`$LUKS_BLK`) → reaches
  `wiped re_zero`.

### Harness `run_case` (freeze / wipe G5 sections)

The default seed is `PLAINTEXT_DEV=/dev/sdz9`.

- **W-row (writer→reader).**
  - Extract the rollback-rehearsal block by awk, from `step "rollback rehearsal` to its `fi`.
  - Run it with `DRY_RUN=0 PLAINTEXT_DEV_UNSEEDED=1 FINDMNT_MOUNT_SRC=/dev/sdzX`.
  - The last state line must be `PLAINTEXT_DEV=/dev/sdzX`.
- **G5b rows.** Each has the mapper mounted and the ack set, and asserts the `REFUSED (plaintext_dev_gone)`
  text plus `recorded_type=` in the output and in the `cutover_aborted` row:
  - **H1:** default → the rollback runs, with `SEAM _plaintext_dev_type /dev/sdz9` in the calls.
  - **R1:** `PLAINTEXT_DEV_FSTYPE=` → refused, `recorded_type=none`.
  - **D:** `PLAINTEXT_DEV_FSTYPE=crypto_LUKS` → refused, `recorded_type=crypto_LUKS`.
  - **B:** `PLAINTEXT_DEV_FSTYPE=blkid_unavailable` → refused.
  - **U:** `PLAINTEXT_DEV_UNSEEDED=1` → refused, `recorded=none`, `recorded_type=invalid`.
  - **M:** `persist_state PLAINTEXT_DEV "$MAPPER"` with fstype ext4 → refused.
  - **V:** `persist_state PLAINTEXT_DEV -o` → refused.
- **G5c.** The WIPED-marker row, the `PLAINTEXT_DEV_FSTYPE=` row, and H1 on defaults.
- **G5d** (the captured fire, via `g5d_arm <record>` per row with `BLKID_BIN_PATH=$G5D_BIN/blkid`):
  - R1: marker → refuse with `why=marker`.
  - R2: mapper + `$TGT_BLK` + `G5D_TYPE=` → refuse, `why=plaintext_dev_gone recorded_type=none`; no
    umount, close or mount.
  - D: mapper + `$TGT_BLK` + `G5D_TYPE=crypto_LUKS` → refuse, `recorded_type=crypto_LUKS`.
  - **H2: mapper + `$TGT_BLK` + `G5D_TYPE=ext4` → the restore runs (`mount $TGT_BLK <mnt>`),
    `result=ok … mount_source=$TGT_BLK`, and the logged blkid argv names `$TGT_BLK`. This is the
    pre-wipe web-1 shape.**
  - H1: plaintext mounted, no marker → the restore runs.
  - Delete the old "markerless, label gone" row.
- **Arm rows A1–A6** (modelled on T33): `DRY_RUN=0; arm_dead_man; echo PAST_ARM` → `died`,
  `markerF "$DM result=arm_refused reason=plaintext_dev_unrecorded"`,
  `has '^EMIT_DRIFT deadman_arm_failed$'`, `! outF PAST_ARM`, `nhas '^systemd-run '`, and no dead-man
  timer stop recorded in the calls (the T33 negative assert).

  | Row | Record / setting | Expected `detail=` |
  |---|---|---|
  | A1 | unseeded | `record_invalid:empty` |
  | A2 | `x;logger INJECTED` | `record_invalid:` |
  | A3 | `$MAPPER` | `record_is_mapper:` |
  | A4 | `BLKID_ABSENT=1` | `blkid_absent` |
  | A5 | `PLAINTEXT_DEV_FSTYPE=crypto_LUKS` | `record_not_ext4:` |
  | A6 | `-o` | `record_invalid:` |

- **Freeze T5/T35/T42b.** Rollback mounts the seeded record: `^mount /dev/sdz9[[:space:]]`.

### Loopback session W (real devices, real blkid)

Each probe first runs `seed_state`, so no wipe marker is present. Each echoes
`why=$PLAINTEXT_GONE_WHY`.

- LW-P1: LW1a on an **unlabelled** loop, with the record = the loop →
  `rehearsal_ok label=none plaintext_dev=<loop>`.
- LW-P2: the real `_plaintext_gone`, with `WL_MOUNT` on the mapper and the record = the intact loop →
  rc 1 (not gone).
- LW-P3: after LW1's real zero → rc 0, `why=plaintext_dev_gone`.
- LW-P4: the record = `readlink -f $MAPPER` (the real `dm-N`) → rc 0. This kills Guard 2 M4.

## Domain Review

**Domains relevant:** Engineering, Product (sign-off), Legal (one record field)

### Engineering

**Status:** reviewed. The CTO assessment and devex panel, plus the deepen security, observability,
test-design and user-impact reviewers, are folded in.

### Legal

**Status:** reviewed inline. One destruction-record field changes, from an asserted label to the
recorded identity, and its value stays unfilled until the row exists. Lawful basis, retention and the
Art. 17 `plaintext_only` accounting are untouched.

### Product/UX Gate

Not applicable. No UI surface is touched, so the tier is NONE. The CPO sign-off is in User-Brand
Impact.

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
  - If web-1 rebooted after 2026-07-23 (for example the C15 proof reboot), the record may now name
    another device.
  - Then W6 refuses, and Guard 5 reads "gone". Both fail closed, and both print
    `recorded_real=` / `recorded_type=` evidence.
  - There is deliberately no host-side re-record path. The remedy is a reviewed fix-forward, filed only
    if the rehearsal shows drift.
  - Sequencing is DC-3.
- **A foreign ext4 inheriting the recorded name** would let rollback or a fire mount it pre-wipe.
  - The old label bug made that unreachable; this fix makes it reachable again.
  - It needs drift *and* a third attached ext4 whole-disk volume, because web-1 has exactly two volumes
    plus a partitioned root.
  - It is accepted, and stated in the runbook row.
- **A second `ROLLBACK=1` on a non-mapper mount with a drifted record.** `rollback()` unmounts the live
  plaintext, then its remount fails (`rollback_remount_failed`).
  - This is pre-existing: the record fallback already existed.
  - Invalid records are now never mounted, but a *valid* drifted one still unmounts first.
  - A pre-umount remount-source check for the non-mapper case is DC-4, because it widens the stated
    predicate.
- **A lost state file.** Guard 5 refuses every rollback on a mapper mount, and W3 refuses the wipe.
  This is fail-closed, but it strands a still-intact plaintext as a rollback source. Accepted.
- **A BEGUN marker while the plaintext is still intact** (an early `blkdiscard` failure, or
  `gate_rc=97`). Rollback stays refused, which is PR A's design. Recovery is a `re_zero`
  re-dispatch, and the runbook wording says so.
- **This fix re-enables two paths the bug refused:**
  - an acknowledged pre-wipe `ROLLBACK`, after which W9 then refuses the wipe;
  - a pre-wipe fire on the mapper, which W7 and S6 guard, and the runbook row now says so.
- **Other values baked into the fire are unvalidated.** `MOUNT`, `STAGING`, `CONTAINER`,
  `STATE_FILE` and `LUKS_LOG_TAG` come from `WORKSPACES_*` overrides. This is pre-existing and out of
  scope, and needs no new issue: the same `.env` threat class is already accepted for the cutover's
  other env inputs.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, holds only `TBD`/`TODO`/placeholder text, or
  omits the threshold fails `deepen-plan` Phase 4.6.
- The wipe suite's C3 finds PR A's plan by `*feat-workspaces-plaintext-volume-wipe-plan.md`. This
  plan's filename deliberately does not match it.
- The harness knob is `PLAINTEXT_DEV_FSTYPE` and the script global is `PLAINTEXT_DEV_TYPE`. Never
  unify them, because sourcing would clobber the knob.
- Do not reuse `_same_dev` for the mapper-identity clause. It fails in the "different" direction.
- `arm_dead_man` edits must not add a line starting `}` or a new dead-man-unit stop/reset-failed
  line. The loopback L7 awk extraction keys on both.
- `seed_state` (loopback) writes its `PLAINTEXT_DEV=$WP_DEV` before the caller's `$1`, so the caller
  wins.
- `${dev}` and `${blkid_bin}` are baked unquoted only because arm validation guarantees a safe charset.
  Never relax the validator without re-adding quoting and rows A2/A6.
- Do not edit the postmortem or anything under `archive/`.
