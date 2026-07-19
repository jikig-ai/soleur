# Tasks — fix C1 false abort (#6733)

Plan: `knowledge-base/project/plans/2026-07-20-fix-c1-verify-root-mtime-tolerance-plan.md`

> **Direction change:** the diff is caused by the script's own G4 probe. C1 is **not**
> narrowed. See `decision-challenges.md` (UC-1).

## Phase 1 — Reproduction harness (RED first)

- [ ] 1.1 Create `apps/web-platform/infra/workspaces-luks-verify-root-mtime.test.sh`
- [ ] 1.2 Fixture derived from production layout (infra at depth 1, user identity at depth 2)
- [ ] 1.3 Assert: clean after pass-2
- [ ] 1.4 Assert: `.d..t...... ./` after the G4 probe runs verbatim (RED vs today's script)
- [ ] 1.5 Add non-degeneracy floor (zero assertions = loud fail)
- [ ] 1.6 Evaluate relocating the probe fd outside `$MOUNT`; record why rejected if G4's
      positive control requires it under `$MOUNT`

## Phase 2 — Make the G4 probe non-perturbing

- [ ] 2.1 Capture root mtime at ns precision (`stat -c %y`) before `exec 9>"$probe"`
- [ ] 2.2 Restore (`touch -d`) after the unlink, on the clean path
- [ ] 2.3 Restore on all three `die` paths (`:463` g4_probe_failed, `:469` g4_probe_blind,
      `:473` holders)
- [ ] 2.4 Fail-closed: unreadable mtime or failed restore ⇒ `die` (no `-e` in this script)
- [ ] 2.5 Confirm Phase 1 harness now GREEN

## Phase 3 — Root-mtime telemetry

- [ ] 3.1 Emit `SOLEUR_WORKSPACES_LUKS_ROOT_MTIME` with `src_pre_probe`, `src_post_probe`,
      `src_pre_verify`, `dst_pre_verify`
- [ ] 3.2 Two distinct fields: `probe_restored` and `src_moved_after_probe`
- [ ] 3.3 `stat` failure emits `unknown`, never a silent default
- [ ] 3.4 ns-precision comparisons

## Phase 4 — Correct the falsified in-tree comment

- [ ] 4.1 Rewrite the wrong-device attribution in §"Staging-target preparation"
- [ ] 4.2 Name the G4 probe as the measured cause; cite run 29706401639
- [ ] 4.3 Preserve the device-anchoring invariant; add "a gate that certifies a tree must
      not perturb it"

## Phase 5 — Mutation battery (primary deliverable)

- [ ] 5.1 C1 non-regression m1–m12 (destination mutations) — all REJECT
- [ ] 5.2 m4 (non-root dir mtime) rejects — guards against `--omit-dir-times` regression
- [ ] 5.3 m11/m12 reject — `./` line present, still rejected
- [ ] 5.4 m13 clean (fix applied) / m14 emits diff (fix reverted) — non-vacuity
- [ ] 5.5 m15 restore on `die` paths; m16 instrument-unavailable refuses
- [ ] 5.6 m17 `%Y`-precision mutation still emits the diff
- [ ] 5.7 m18 residual post-probe perturbation still aborts C1
- [ ] 5.8 Landing assertions vs pristine backup; baseline-identical ⇒ UN-RUN
- [ ] 5.9 Call-order assertion against the file (`grep -n`, loud on missing anchors)
- [ ] 5.10 Entrypoint coverage via the real `assert_mount_quiesced` path
- [ ] 5.11 m7/m10 measured or recorded UNMEASURED — no predicted icodes
- [ ] 5.12 Hostile-filename fixture (newline-bearing)

## Phase 6 — Verification

- [ ] 6.1 `shellcheck` clean
- [ ] 6.2 Run `workspaces-luks-verify`, `workspaces-luks-freeze`, `workspaces-luks-loopback`
      (the three suites pinning changed literals; `test-all.sh` does NOT cover `infra/`)
- [ ] 6.3 Confirm C1's `diff_n` gate is byte-unchanged
- [ ] 6.4 Verify all ACs
