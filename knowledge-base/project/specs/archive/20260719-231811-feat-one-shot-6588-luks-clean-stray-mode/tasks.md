# Tasks — CLEAN_STRAY mode for the workspaces-luks cutover (Ref #6588)

Plan: `knowledge-base/project/plans/2026-07-19-feat-workspaces-luks-clean-stray-mode-plan.md`
Lane: single-domain · Threshold: single-user incident

## Phase 0 — Preconditions (verify, do not assume)

- [ ] 0.1 Confirm the stray guard still precedes the `DRY_RUN` short-circuit in `prepare_staging_target`.
- [ ] 0.2 Confirm T4c's `run_case` invokes `prepare_staging_target` only.
- [ ] 0.3 Read `workspaces-luks-harness.sh`'s `rm` passthrough recorder; fix the `$STAGING`-scoped assertion shape for new tests.
- [ ] 0.4 Confirm `clean_stray()`'s required position above the `BASH_SOURCE` sourcing guard.
- [ ] 0.5 Re-confirm `verify_byte_identity()` hardcodes `--delete` and `die()`s (the premise behind D3). If changed, revisit D3 before coding.
- [ ] 0.6 Run the Phase 1.7.5 open-code-review overlap query against the four files to edit.

## Phase 1 — RED: tests for clean_stray()

All refusal assertions use `nhas "^rm -rf $WORKSPACES_STAGING"`, never bare `^rm `.

- [ ] 1.1 T4d — happy path deletes; fixture includes a dotfile, asserted removed.
- [ ] 1.2 T4e — `$STAGING` is a mountpoint → refuse, no rm.
- [ ] 1.3 T4f — top-level entry absent from `$MOUNT` → `clean_stray_not_subset`, no rm.
- [ ] 1.4 T4g — `CLEAN_STRAY=1` + `DRY_RUN=1` → refuse, no rm.
- [ ] 1.5 T4h — `CLEAN_STRAY=1` + `ROLLBACK=1` → `clean_stray_mode_conflict`, no rm, no rollback.
- [ ] 1.6 T4i — `_same_dev($MOUNT,$STAGING)` → refuse, no rm.
- [ ] 1.7 T4j — already-empty `$STAGING` → `already_clean`, exit 0, no rm.
- [ ] 1.8 Confirm T4c still passes, byte-identical.

## Phase 2 — GREEN: clean_stray() + mode blocks

- [ ] 2.1 FR1 — `CLEAN_STRAY` env default; `clean_stray()` above the BASH_SOURCE guard; mode block in ROLLBACK's slot.
- [ ] 2.2 FR2 — mutual-exclusion refusal before both mode blocks.
- [ ] 2.3 FR3 — DRY_RUN conflict refusal naming the remedy.
- [ ] 2.4 FR4/FR5 — mountpoint, non-empty, `already_clean`, `$MOUNT` health, `_same_dev` predicates.
- [ ] 2.5 FR6 — top-level subset check (no `verify_byte_identity()` call).
- [ ] 2.6 FR7 — AP-009 banner + magnitude under `SOLEUR_WORKSPACES_LUKS_CLEAN_STRAY`, before the first rm.
- [ ] 2.7 FR8 — dotfile-inclusive `find -mindepth 1 -maxdepth 1 -exec rm -rf {} +`.
- [ ] 2.8 FR9 — post-deletion emptiness assertion + terminal marker.

## Phase 3 — Workflow

- [ ] 3.1 FR10 — `clean_stray` input, description naming AP-009 + the `dry_run=false` requirement.
- [ ] 3.2 FR11 — pre-gate validation step (clean_stray+dry_run, clean_stray+rollback).
- [ ] 3.3 FR12 — conditional confirm token `DELETE-STRAY-USER-DATA-AP-009`.
- [ ] 3.4 FR13 — split into ungated `probe` job + gated `delete` job (`needs: probe`); probe writes banner + magnitude + subset result to `$GITHUB_STEP_SUMMARY`.
- [ ] 3.5 FR14 — correct all three `dry_run`-as-mode-proxy expressions (environment, loopback gate `if:`, Hetzner volume lookup).
- [ ] 3.6 `.env` printf plumb for `CLEAN_STRAY`; omit `WORKSPACES_LUKS_DEV` on the clean_stray arm.
- [ ] 3.7 FR17 — Cutover summary reports mode + magnitude + subset result.
- [ ] 3.8 FR16 — refresh the header comment block and the `dry_run` COVERS/does-NOT-cover description.

## Phase 4 — ADR

- [ ] 4.1 FR15 — ADR-119 `## Addendum (2026-07-19): the stray-copy carve-out (CLEAN_STRAY, #6588)` with the ADR-055-shaped AP-009 deviation bullet.
- [ ] 4.2 Read all three `.c4` files and confirm the "no C4 impact" enumeration; correct the plan if contradicted.
- [ ] 4.3 Confirm `principles-register.md` is NOT edited (D5).

## Phase 5 — Verification

- [ ] 5.1 FR16 test-comment sentence near T4.
- [ ] 5.2 Full staging suite + loopback suite green.
- [ ] 5.3 AC2–AC8 pre-merge checks.
- [ ] 5.4 Invoke `/soleur:gdpr-gate` against the deletion path and marker emit.
- [ ] 5.5 PR body: AP-009 deviation statement, the three gate corrections called out, `Ref #6588` (never `Closes`).
