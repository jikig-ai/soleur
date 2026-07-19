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

- [ ] 2.1 Capture via `touch -r "$MOUNT" "$ref"` (reference file beside the `mktemp`s at `:451`)
      — NOT a `stat`/`touch -d` string round-trip. No in-tree precedent; novel pattern.
- [ ] 2.2 Restore via `touch -r "$ref" "$MOUNT"` after the unlink
- [ ] 2.3 **Read back and compare** (`stat -c %y` pre vs post); mismatch ⇒
      `emit_drift g4_root_mtime_restore_skew` + `die`. Makes `probe_restored` measured.
- [ ] 2.4 `[ ! -e "$probe" ] || die` between unlink and restore
- [ ] 2.5 Depth-1 listing fingerprint pre-probe + post-unlink; die on mismatch
- [ ] 2.6 Restore on `die` sites `:464`, `:470`, `:476` — NOT the `rm` lines. `:456` needs no
      restore (nothing created); add an explicit comment saying so.
- [ ] 2.7 Declare-then-assign (`local mt; mt="$(...)"`) — `local x="$(cmd)"` masks exit status
      in a no-`-e` shell. Precedent `:462`, `:468`.
- [ ] 2.8 Add `touch` to the existing instrument preflight loop at `:1019-1025` (not inline)
- [ ] 2.9 Comment at `:229`: C1's flag set (no `--atimes`/`--crtimes`) is load-bearing here
- [ ] 2.10 Comment: record the in-bracket bare-`touch` residual as an OPEN blind spot
- [ ] 2.11 Comment: record why relocation is rejected (positive control at `:467`; reusing an
      existing path would mask a straggler via the `:472` filter)
- [ ] 2.12 Confirm Phase 1 harness now GREEN

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
- [ ] 5.7b m19 in-bracket create+delete pair caught by the listing fingerprint
- [ ] 5.7c m20 truncating restore caught by the read-back guard
- [ ] 5.7d m21 failed unlink blocks the restore
- [ ] 5.7e At least half the mutations authored by an agent that did NOT write the assertions
- [ ] 5.7f GNU-vs-uutils capability probe; SKIP cleanly on uutils (precedent:
      `plugins/soleur/skills/git-worktree/test/stale-lock-sweep.test.sh:28-29`)
- [ ] 5.7g Audit harness for `producer | grep -q` under `pipefail` (SIGPIPE flake class) —
      prefer herestrings or `grep -c`
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
