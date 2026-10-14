---
title: "fix(infra): stop the G4 probe perturbing the transfer root that C1 certifies"
date: 2026-07-20
type: fix
issue: 6733
branch: feat-one-shot-6733-c1-verify-root-mtime-tolerance
lane: single-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# fix(infra): stop the G4 probe perturbing the transfer root that C1 certifies

**Issue:** #6733 · **Surface:** `apps/web-platform/infra/workspaces-cutover.sh`

> **Direction change from the issue brief.** The brief prescribed narrowing C1 to tolerate
> the `./` mtime diff. Measurement shows the diff is **caused by the cutover script itself**,
> so no tolerance is needed and C1 stays fail-closed. Recorded as a User-Challenge in
> `knowledge-base/project/specs/<branch>/decision-challenges.md` (ADR-084) for operator
> review; `ship` surfaces it in the PR body and as an `action-required` issue.

## Enhancement Summary

**Deepened:** 2026-07-20 · **Passes:** plan-review (Kieran, spec-flow), learnings-researcher,
data-integrity-guardian (precedent-diff gate), local measurement.

### Key improvements over the first draft

1. **The approach was inverted by measurement.** The draft narrowed C1 per the issue brief.
   spec-flow found — and I independently confirmed in the source and by reproduction — that the
   diff is caused by the script's own G4 probe. C1 is now left untouched.
2. **`touch -r` replaces the `stat`/`touch -d` round-trip**, and a **read-back guard** makes the
   restore *measured* rather than *asserted* (a truncating `touch` exits 0 and would otherwise
   pass silently).
3. **`die`-site line numbers corrected** — the draft cited the `rm` lines (`:463/:469/:473`);
   the real sites are `:456/:464/:470/:476`, and `:456` needs no restore.
4. **In-bracket blind spot named honestly** instead of claimed closed. A depth-1 listing
   fingerprint covers the create+delete case; the bare-`touch` case stays recorded as open.
5. **Battery grown 18 → 21 cases** and required to be *half-authored by an independent agent* —
   a self-graded battery measures its author's imagination, not the suite.
6. **Sibling-suite list corrected** from `header/staging/luks` (which pin none of the changed
   literals) to `verify/freeze/loopback` (which do).

### Open items carried forward

- Byte-loss window **after** C1 (`git fsck` across 8 workspaces, before `umount`) — pre-existing,
  scoped out, needs its own issue.
- In-bracket bare-`touch` by a foreign writer — uncovered residual, recorded in-code.

## Overview

Every `/workspaces` LUKS cutover safe-aborts on one itemize line:

```
DIFF .d..t...... ./
```

Zero files differ — position 2 `d` (directory), position 5 `t` (mtime), all content
positions clean, path `./` (the transfer root itself). Because C1 is fail-closed, the
cutover has never completed and 8 production workspaces remain **unencrypted at rest** —
the exposure #6588 exists to close.

**C1 was right every time.** The script's own G4 quiescence probe creates and removes a
depth-1 entry inside the rsync transfer root, between the last write pass and the verify.
That is a net-zero listing change: it advances the root directory's mtime and nothing else,
which is exactly the reported signature.

## Mechanism (measured, reproduced, and fix-validated)

`assert_mount_quiesced` opens its probe **inside `$MOUNT`** and unlinks it:

```bash
# workspaces-cutover.sh:449,454,473
probe="$MOUNT/.luks-g4-probe.$$"
exec 9>"$probe"                    # :454  creates the entry
rm -f "$lout" "$lerr" "$probe"     # :473  removes it
```

and the main body calls it between pass-2 and the verify:

```
:1416  pass-2 delta rsync            (last write to $STAGING)
:1428  assert_mount_quiesced pre-verify
:1430  drop_caches
:1437  verify_byte_identity "$MOUNT" "$STAGING"
```

`$MOUNT` **is** the rsync transfer root, so `./` is `$MOUNT`.

Reproduced locally with `rsync 3.4.1`, the script's exact verify invocation, and a fixture
whose shape is derived from the production layout (infra dirs at depth 1, user identity at
depth 2 — per the 2026-07-19 learning's fixture rule):

| Step | Verify output |
|---|---|
| immediately after pass-2 | *(clean)* |
| after running the G4 probe **verbatim** | `.d..t...... ./` |
| after the probe **with root-mtime save/restore** | *(clean)* |

**This explains the decisive observation from run 29706401639 directly.** The diff appeared identically
on the wrong device and the right device because the probe perturbs `$MOUNT` — the **source**
side, identical in both runs. The device was never the variable, which is why the diff could
not discriminate device identity.

**Timeline corroborates.** The pre-verify re-assert landed in `ca85c30bc` (2026-07-19 18:25
CEST, #6701), before run 29706401639 (22:37Z) — the run cited as reproducing the diff on a
provably correct device.

**Explicitly falsified hypotheses** (each reproduced, each clean):

- *`lost+found` from `mkfs.ext4` being `--delete`d in pass 2 moves the root mtime* —
  **REFUTED.** A fresh-DST fixture with `lost+found` run through the real two-pass sequence
  verifies clean; rsync's final dir-time fixup covers the root.
- *A deep write between pass 2 and the verify* — **REFUTED as this signature.** It emits a
  content-flagged line (`>fcst...... workspaces/ws-a/file.txt`), not `./`.
- *An external unquiesced writer* — **not required to explain the observation.** The script's
  own probe is sufficient and is on the call path. Phase 2's telemetry keeps the question
  answerable if a *residual* root perturbation ever survives the fix.

**Scope limit stated honestly:** this accounts for runs carrying #6701. The earlier aborts
(29676585829 / 29676994044) predate both the pre-verify re-assert and the itemized
diagnostic, so they carry no itemize evidence and this plan does not claim to explain them.

## Research Reconciliation — in-tree comment vs reality

| Claim in tree | Reality | Plan response |
|---|---|---|
| §"Staging-target preparation" (anchor: *"The 2026-07-19 freeze (run 29695998561) safe-aborted on C1 with a single `.d..t...... ./` diff"*) attributes the diff to the copy landing on the **wrong block device** | That mkfs defect was real and is fixed (merged 2026-07-19 19:12 CEST). Run 29706401639 carried the fix — `mkfs.ext4` ran, mount succeeded, `result=ok reason=prepared` — and produced the **identical** diff on a provably correct device. Same diff both ways ⇒ not diagnostic of device identity. The measured cause is the G4 probe | Rewrite the attribution (Phase 3) |
| §C1 verify header: *"NO itemize code is narrowed away"* | Still true, and this plan keeps it true | No change — reinforce |

The comment's invariant — *"a gate that certifies a path must first anchor that path to its
intended device"* — remains **true and load-bearing**. Only the attribution of this itemize
code is falsified. Keep the invariant; correct the attribution. Add the generalised lesson:
**a gate that certifies a tree must not perturb that tree.**

## User-Brand Impact

**If this lands broken, the user experiences:** either the cutover keeps aborting and their
source stays unencrypted at rest indefinitely, or — if the gate were weakened instead of the
probe fixed — a DST that is not byte-identical is certified, `/mnt/data` is repointed onto
it, and the delta is **silently lost** when the plaintext volume is released.

**If this leaks, the user's source code is exposed via:** an unencrypted `/workspaces` volume
on web-1's disk, for as long as C1 keeps false-aborting.

**Brand-survival threshold:** `single-user incident`.

**Why this fix is the low-risk one:** it removes the false abort **without touching the gate**.
C1 keeps rejecting every difference it rejects today.

## Non-Goals

- **No C1 narrowing. No tolerance. No `--omit-dir-times`.** The gate is correct.
- **Do NOT relocate the probe one level deeper.** At depth 2 it emits
  `.d..t...... workspaces/` — a real difference C1 must still reject.
- **Do NOT re-dispatch the cutover workflow.** Each attempt costs ~90s of production
  downtime; the operator dispatches it.

## Implementation Phases

### Phase 0 — Reproduction harness (lands first, as its own artifact)

`apps/web-platform/infra/workspaces-luks-verify-root-mtime.test.sh`: build the fixture,
run the script's **exact** verify invocation, and assert the three measured rows of the
mechanism table — clean after pass-2, `.d..t...... ./` after the probe, clean after the fix.
This is the RED test: it fails against today's script.

**Non-degeneracy floor (mandatory):** the suite fails loudly if it ran zero assertions. Per
the 2026-07-19 learning, a suite that silently runs nothing reports green.

### Phase 1 — Make the G4 probe non-perturbing

In `assert_mount_quiesced`, capture the root's mtime before `exec 9>"$probe"` and restore it
after the probe is unlinked.

**Use `touch -r`, not a `stat`/`touch -d` string round-trip.** Capture into a reference file
alongside the existing `mktemp`s at `:451` (`touch -r "$MOUNT" "$ref"`), restore with
`touch -r "$ref" "$MOUNT"`. This eliminates the format assumption, the locale dependency, the
quoting hazard and the date parser entirely. **No precedent exists in-tree** (`git grep 'touch -r'`
→ zero hits; every in-tree `stat` is whole-second `%Y`; every `touch -d` is test-fixture
aging) — the pattern is novel, which is itself a reason to prefer the primitive with the
fewest moving parts.

**Verify the restore by reading it back — do not assume it (P0).** A `touch` that exits 0 but
writes a *truncated* timestamp is not a failure exit, so an exit-status-only guard passes while
the root stays perturbed — reintroducing this bug invisibly, which is precisely what this plan
says must not happen. Read back and compare:

```bash
post="$(stat -c %y -- "$MOUNT")"
[ "$post" = "$pre" ] || { emit_drift g4_root_mtime_restore_skew; die "..."; }
```

This makes `probe_restored=yes` **measured rather than asserted**, and it catches truncation
from any source — GNU-vs-uutils `touch -d` parser differences, coarser filesystem granularity,
or a future primitive swap. It also makes the `%y`-vs-`%Y` precision argument moot at runtime
(m17 still pins it at the harness level).

**Exit paths.** The `die` sites are `:456`, `:464`, `:470`, `:476` — **not** the `rm` lines
(`:463`, `:469`, `:473`), which an earlier draft of this plan miscited. `:456` needs **no**
restore: `exec 9>` failed, so nothing was created. Add an explicit comment there so the
omission is deliberate rather than apparent. The other three require the restore.

**Order the restore after a positive unlink check.** `rm -f "$probe"` is unchecked at all three
sites. If it fails (EPERM, immutable, EROFS), restoring the mtime yields a root that *asserts*
"unchanged" while still carrying the entry. C1 still catches it (`>f+++++++++ .luks-g4-probe.NNN`),
so this is not fail-open — but require `[ ! -e "$probe" ] || die` between unlink and restore so
the ordering is load-bearing rather than incidental.

**Fail-closed, in a shell with no `-e`.** `workspaces-cutover.sh:32` is `set -uo pipefail` with
**no `-e`**. Two specific traps:

- `local mt="$(stat ...)"` **masks the exit status** — `local` returns 0 regardless, so a failed
  `stat` never reaches the `die`. Use the in-tree precedent two lines from the edit site
  (`:462`, `:468`): declare first, assign second (`local mt; mt="$(...)"`).
- Instrument availability belongs in the **existing batch preflight at `:1019-1025`**, which
  already loops over required tools (including `stat`) with this exact rationale. Extend that
  loop with `touch` — do not add an ad-hoc inline check. `ensure_lsof` (`:312`) and `ensure_aws`
  (`:95`) are the sibling forms.

Per the 2026-07-19 learning's unifying question: *if this instrument were unavailable, does the
guard REFUSE or PROCEED?* It must refuse.

**GNU-vs-uutils capability preflight (Phase 0).** Prod is Debian GNU; the local harness may be
uutils, where `%y` ns fidelity and `touch -d`/`touch -r` ns handling differ. A green local
harness is not evidence for prod. Gate the harness on a runtime GNU-capability probe and SKIP
cleanly when absent — precedent: `plugins/soleur/skills/git-worktree/test/stale-lock-sweep.test.sh:28-29`.
The read-back guard above makes prod self-checking regardless.

**Why the probe cannot simply be relocated.** Two candidates, both rejected, recorded here so
nobody adopts them later:

- *Move the fd outside `$MOUNT`* — defeats G4's positive control, which exists to prove
  `lsof +D "$MOUNT"` actually scanned the mount (`:467`).
- *Hold a read-only fd on a file that already exists under `$MOUNT`* — zero perturbation (read
  bumps only atime, and C1 at `:229` compares neither atime nor ctime), **but** the holder
  filter at `:472` is `grep -vF -- "$probe"`, so reusing a real path would mask a genuine
  straggler holding that same file. This is a stronger reason for rejection than the first and
  belongs in the function comment.

**Depth-1 listing fingerprint (closes most of the in-bracket blind spot).** The restore
necessarily overwrites any root-mtime move that happened *inside* the bracket, including a
foreign create+delete pair — structurally identical to the probe's own. Capture a sorted,
hashed depth-1 listing before `exec 9>` and re-check it after the unlink; die on mismatch.
This catches the create/delete-pair and rename cases the mtime restore would erase. A bare
`touch "$MOUNT"` by a foreign writer inside the bracket remains **uncovered** — record that
residual honestly in the function comment rather than claiming the class is closed.

**Pin the C1 flag set as load-bearing.** The restore bumps the root's ctime twice. That is
harmless only because C1 at `:229` omits `--atimes`/`--crtimes`. Add a one-line comment at
`:229` recording that the flag set is load-bearing for the G4 restore — otherwise a future
`--crtimes` addition silently re-breaks this with the identical `.d..t...... ./` signature.

### Phase 2 — Root-mtime telemetry (keeps the question answerable after the fix)

Emit, bracketing the probe **and** immediately before the verify:

```
SOLEUR_WORKSPACES_LUKS_ROOT_MTIME feature=workspaces-luks op=workspaces-luks-root-mtime \
  src_pre_probe=<ns> src_post_probe=<ns> src_pre_verify=<ns> dst_pre_verify=<ns> \
  probe_restored=<yes|no> src_moved_after_probe=<yes|no> host=<host>
```

Two distinct questions, two distinct fields — not one boolean (`§2.9.2`):

- `probe_restored` — did the Phase 1 fix do its job?
- `src_moved_after_probe` — did **anything else** perturb the root after the probe? This is
  the residual-unquiesced-writer signal the fix must not blind. It stays fail-closed at C1.

`stat` failure emits `unknown`, never a silent default. Comparisons use ns precision.

**Do not route these through `emit_drift` alone.** The script already documents that
`emit_drift` "returns 0 silently when the Sentry DSN cannot be resolved, which is exactly the
FIRST-cutover case" — i.e. exactly this run. Mirror the in-tree emitter convention: bare `echo`
at column 0 + `logger -t "$LUKS_LOG_TAG"` first (the `emit_staging_target` / `emit_freeze_holders`
shape), with `emit_drift` as a best-effort second channel.

### Phase 3 — Correct the falsified in-tree comment

Rewrite the wrong-device attribution per the Research Reconciliation table: state what run
29706401639 proved, name the G4 probe as the measured cause, and record that the itemize
vocabulary cannot express "correct copy, wrong target" — which is why the device anchoring
(`_same_dev`, `prepare_staging_target`) exists and remains load-bearing. Preserve the
invariant; correct the attribution; add *a gate that certifies a tree must not perturb it*.

### Phase 4 — Mutation battery (the primary deliverable)

Two obligations: prove the fix works, and prove **C1 still rejects everything it rejects
today**. All icodes below are **measured**, not predicted.

**(a) C1 non-regression** — mutate the destination, assert C1 REJECTS each:

| # | Mutation | Measured verify output |
|---|---|---|
| m1 | content byte change, same size | `>fcs....... workspaces/ws-a/file.txt` |
| m2 | size change | `>fcst...... plugins/p.conf` |
| m3 | permission change | `.f...p..... workspaces/ws-a/file.txt` |
| m4 | **non-root** directory mtime change | `.d..t...... workspaces/` |
| m5 | deleted file | `>f+++++++++ plugins/p.conf` + `.d..t...... plugins/` |
| m6 | added file | `*deleting …/rogue.txt` + `.d..t...... workspaces/ws-a/` |
| m7 | owner/group change | **UNMEASURED** — see note |
| m8 | file replaced by directory | `.d..t...... plugins/` + `>f+++++++++ plugins/p.conf` |
| m9 | symlink swap | `.d..t...... workspaces/ws-a/` + `>f+++++++++ …/file.txt` |
| m10 | xattr change | **UNMEASURED** — see note |
| m11 | rogue entry added at **DST root** | `*deleting rogue` + `.d..t...... ./` |
| m12 | infra dir deleted from **DST root** | `.d..t...... ./` + `cd+++++++++ redis/` |

**m4 is the sharpest case:** identical icode to the previously-proposed tolerance, different
path. It is the case a blanket `--omit-dir-times` or a loose icode match would have swallowed
— retained as a permanent guard against re-introducing that shortcut.
**m11/m12 matter** because they carry the `./` line *plus* a companion: they prove C1 still
rejects when the root line is present, which is precisely what a tolerance would have eroded.

**(b) Probe-fix cases:**

| # | Case | Must |
|---|---|---|
| m13 | G4 probe runs between pass-2 and verify, **fix applied** | verify CLEAN |
| m14 | G4 probe runs, **fix reverted** (mutation) | verify emits `.d..t...... ./` — the RED case |
| m15 | probe `die` path taken (`g4_probe_blind`) | root mtime still restored |
| m16 | `stat`/`touch` unavailable | probe **refuses** (dies), never proceeds silently |
| m17 | `%Y`-precision restore instead of `%y` (mutation) | still emits `.d..t...... ./` — pins the precision requirement |
| m18 | a residual SRC-root perturbation **after** the probe | C1 still REJECTS, `src_moved_after_probe=yes` |
| m19 | a create+delete pair **inside** the probe bracket | the depth-1 listing fingerprint dies; the restore must not silently absorb it |
| m20 | `touch -r` truncates the restore (simulated coarse granularity) | read-back guard dies with `g4_root_mtime_restore_skew` |
| m21 | `rm -f "$probe"` fails, restore would run anyway | `[ ! -e "$probe" ] || die` fires before the restore |

**Applying the 2026-07-19 learning (mandatory, not optional):**

- **Landing assertions.** Every mutation compares against a **pristine backup**, not `HEAD`
  (the worktree is dirty during the run). A baseline-identical result is a **null** result
  wearing a green result's clothes and must report UN-RUN, not caught.
- **Mutate the SUT, not only the data.** m14/m17 mutate the fix itself. Additionally assert
  **call order against the file** (`grep -n` line comparison, loud on missing anchors) — the
  restore must sit after the unlink and before the function returns. Data-only mutations
  cannot catch a misordered restore; this is the learning's §2 class verbatim.
- **Entrypoint coverage.** Assert the fix is reached through the real `assert_mount_quiesced`
  call path, not only a directly invoked helper. Note `verify_byte_identity` is documented as
  callable only outside a subshell (`die`'s `exit 1` must reach the EXIT trap) — the harness
  must respect that seam.
- **m7/m10 are UNMEASURED.** `chgrp` to the same group and `setfattr` were both no-ops in the
  local sandbox. Do **not** encode a predicted icode. Either establish them in the harness
  (distinct group; xattr-capable fs) or record them explicitly as UNMEASURED. An
  asserted-but-unmeasured icode is the false-result class the learning names.
- **Hostile filenames.** `%n` carries user workspace filenames and the tree already has
  `_vscrub` because that channel is treated as hostile. Add a fixture with a newline-bearing
  filename and assert the diagnostic and the battery both behave.
- **Run the suites that pin the changed literals.** `scripts/test-all.sh` does **not** cover
  `apps/web-platform/infra/` (gated via `infra-validation.yml`), so a green full-suite run is
  **not** evidence. Grepped for the changed literals — the three suites that pin them are:
  `workspaces-luks-verify.test.sh` (14 hits), `workspaces-luks-freeze.test.sh` (7),
  `workspaces-luks-loopback.test.sh` (7). `freeze` pins `assert_mount_quiesced` and is the
  one most likely to go RED on the probe change.

## Observability

```yaml
liveness_signal:
  what: SOLEUR_WORKSPACES_LUKS_ROOT_MTIME (probe_restored, src_moved_after_probe)
  cadence: once per cutover dispatch
  alert_target: Better Stack via logger -t luks-monitor
  configured_in: apps/web-platform/infra/workspaces-cutover.sh
error_reporting:
  destination: Sentry via emit_drift; Better Stack via LUKS_LOG_TAG
  fail_loud: true — an unreadable mtime or failed restore dies; never proceeds
failure_modes:
  - mode: probe perturbs the root and the restore silently fails
    detection: probe_restored=no
    alert_route: emit_drift -> Sentry
  - mode: a writer other than the probe perturbs the root after pass-2
    detection: src_moved_after_probe=yes AND C1 aborts fail-closed
    alert_route: run log + Better Stack + SOLEUR_WORKSPACES_LUKS_VERIFY_DIFF
  - mode: stat/touch unavailable
    detection: probe_restored=unknown and the run dies
    alert_route: emit_drift -> Sentry
logs:
  where: workflow run log + Better Stack (luks-monitor tag)
  retention: per existing Better Stack policy
discoverability_test:
  command: gh run view <id> --log | grep SOLEUR_WORKSPACES_LUKS_ROOT_MTIME
  expected_output: one row with probe_restored=yes and src_moved_after_probe=no
```

## Downtime & Cutover

**This change introduces no downtime of its own.** It edits a shell script; it does not touch a
serving host, a hot table, or the router. No reboot, no replace, no lock-taking DDL.

**Effect on the cutover's existing downtime envelope:** strictly reducing. The cutover holds a
freeze (~90s) that is operator-dispatched and pre-existing. Today every dispatch pays that
freeze and then **safe-aborts at C1**, so the downtime is spent for nothing and must be paid
again on the next attempt. This fix makes the first post-merge dispatch able to complete, which
removes the repeat-attempt cost rather than adding any.

**Cutover path:** unchanged — the script's existing freeze → copy → verify → repoint sequence,
with rollback, the dead-man timer, and C1 all intact. Per-stage verification and rollback are
already implemented and are not modified by this plan.

**Residual availability risk:** none introduced. The one pre-existing window this plan does not
close (writers landing in `$MOUNT` between C1 and `umount`, during the multi-minute `git fsck`
pass) is recorded in the Risks table and deferred to its own issue.

## Architecture Decision (ADR/C4)

**No ADR.** This fixes an instrumentation defect within an already-recorded architecture
(#6588 LUKS cutover lineage); no ownership, substrate, or trust-boundary change.

**C4:** no impact. All three model files (`model.c4`, `views.c4`, `spec.c4`) were checked for
the feature's external human actors (none — no new role), external systems/vendors (none —
Better Stack and Sentry edges already modeled via existing observability emitters),
containers/data stores (the `/workspaces` volume is already modeled), and actor↔surface access
relationships (unchanged). Nothing to add.

## Domain Review

**Domains relevant:** none beyond engineering — infrastructure integrity fix, no user-facing
surface, no regulated-data processing change, no new vendor.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` returned no issue body referencing
`workspaces-cutover.sh` or `workspaces-luks-verify`.

## Acceptance Criteria

### Pre-merge

- [ ] **AC1** Phase 0 harness reproduces `.d..t...... ./` against **today's** script (RED),
      and clean after the fix (GREEN).
- [ ] **AC2** m1–m12 each REJECT. C1's predicate is **unchanged** — verified by diffing
      `verify_byte_identity` and asserting no change to the `diff_n` gate.
- [ ] **AC3** m4 rejects — the case a tolerance or `--omit-dir-times` would have swallowed.
- [ ] **AC4** m11/m12 reject — C1 still rejects when the `./` line is present.
- [ ] **AC5** m13 clean; **m14 (fix reverted) emits the diff** — the battery is non-vacuous.
- [ ] **AC6** m15: root mtime restored on every `die` path, not only the clean path.
- [ ] **AC7** m16: `stat`/`touch` unavailable ⇒ the probe **dies**; it never proceeds.
- [ ] **AC8** m17: a `%Y`-precision restore still emits the diff — pins ns precision.
- [ ] **AC9** m18: a residual post-probe root perturbation still aborts C1, with
      `src_moved_after_probe=yes`.
- [ ] **AC10** Call-order assertion against the file: the restore sits after the unlink,
      loud if either anchor is missing.
- [ ] **AC11** Every mutation carries a landing assertion against a pristine backup;
      baseline-identical reports UN-RUN, not caught.
- [ ] **AC12** Both suites carry a non-degeneracy floor (zero assertions = loud fail).
- [ ] **AC13** m7/m10 are measured or explicitly recorded UNMEASURED — no predicted icode.
- [ ] **AC14** The falsified wrong-device attribution is corrected; the device-anchoring
      invariant is preserved.
- [ ] **AC15** `shellcheck` clean; `workspaces-luks-verify`, `workspaces-luks-freeze` and
      `workspaces-luks-loopback` suites all green.
- [ ] **AC18** The restore is **read back and compared** (`stat -c %y` before vs after); a
      truncating `touch` dies with `g4_root_mtime_restore_skew`. `probe_restored` is measured,
      not asserted (m20).
- [ ] **AC19** `[ ! -e "$probe" ] || die` sits between unlink and restore (m21).
- [ ] **AC20** Depth-1 listing fingerprint captured pre-probe and re-checked post-unlink;
      an in-bracket create+delete pair dies (m19).
- [ ] **AC21** No `local x="$(cmd)"` in the new code — declare-then-assign, per the `:462`/`:468`
      precedent. Grep the diff to confirm.
- [ ] **AC22** `touch` added to the existing instrument preflight loop at `:1019-1025` — not an
      ad-hoc inline check.
- [ ] **AC23** Telemetry emits via `echo` + `logger -t "$LUKS_LOG_TAG"` first; `emit_drift` is
      best-effort second (it returns 0 silently when the DSN is unresolvable — the first-cutover
      case).
- [ ] **AC24** Comment at `:229` records that C1's flag set (no `--atimes`/`--crtimes`) is
      load-bearing for the G4 restore.
- [ ] **AC25** Comment at `:456` records that no restore is needed there (nothing was created).
- [ ] **AC26** At least half the mutation battery is authored by an agent that did **not** write
      the assertions. A self-graded battery measures the author's imagination, not the suite.
- [ ] **AC27** The in-bracket bare-`touch` residual is recorded in the function comment as an
      open blind spot — not claimed closed.
- [ ] **AC16** `decision-challenges.md` (UC-1) exists and is rendered by `ship` into the PR
      body plus an `action-required` issue.

### Post-merge (operator)

- [ ] **AC17** Operator dispatches the cutover. The run emits
      `SOLEUR_WORKSPACES_LUKS_ROOT_MTIME` with `probe_restored=yes`,
      `src_moved_after_probe=no`, and C1 passes.
      *Automation: not feasible because each dispatch costs ~90s of production downtime on
      live user data and is an operator-authorized freeze
      (`hr-menu-option-ack-not-prod-write-auth`).*

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| The restore silently fails, reintroducing the bug invisibly | Fail-closed `die` + `probe_restored` telemetry (AC7) |
| `%Y` truncation leaves a sub-second skew | ns precision mandated; m17 pins it (AC8) |
| Restore missed on a `die` path | AC6 covers all three `die` paths |
| Relocating the probe defeats G4's positive control | Phase 1 evaluates and records why relocation is rejected |
| Battery is vacuous (the 2026-07-19 class) | SUT mutation (m14/m17), call-order assertion, landing assertions, non-degeneracy floors, entrypoint coverage |
| A different writer perturbs the root **outside** the probe bracket | Its mtime move survives the restore and still aborts C1 (m18, AC9) |
| A different writer perturbs the root **inside** the bracket — its evidence is stamped over by the restore | **Real residual blind spot.** Listing-changing writes still emit their own itemize line, but the two root-mtime-only shapes (a bare `touch "$MOUNT"`, or a create+delete pair structurally identical to the probe) are erased. `src_moved_after_probe` cannot see this — post-restore and pre-verify are equal by construction. Mitigated by the depth-1 listing fingerprint (Phase 1, m19); the bare-`touch` case remains uncovered and is recorded honestly in the function comment rather than claimed closed |
| Byte-loss window **after** C1 (`git fsck` across 8 workspaces takes minutes, before `umount`) | Pre-existing and out of scope; recorded here so the Risks table does not over-claim that C1 covers the whole cutover. File a follow-up issue |
| Sibling suite pins a changed literal | `test-all.sh` does not cover `infra/`; three pinning suites named and run (AC15) |

## Sharp Edges

- `scripts/test-all.sh` does **not** cover `apps/web-platform/infra/`. A green full-suite run
  is **not** evidence for this change.
- `workspaces-cutover.sh` is `set -uo pipefail` with **no `-e`**. A failed `stat`/`touch` does
  not abort by itself — validate explicitly or the fix fails open.
- `stat -c %Y` truncates to whole seconds; ext4 stores ns. Use `%y`.
- Do **not** move the G4 probe one level deeper — at depth 2 it emits
  `.d..t...... workspaces/`, which is m4 and must keep rejecting.
- `verify_byte_diff` is a **reason string** passed to `emit_verify_diff`, not a function.
  The function is `verify_byte_identity`.
- The C1 predicate is deliberately untouched. Any future change to it must re-run the full
  m1–m12 battery.
