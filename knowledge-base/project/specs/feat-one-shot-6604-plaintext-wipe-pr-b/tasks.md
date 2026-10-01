---
title: "Tasks — PR B convergence after web-1's plaintext /workspaces wipe (#6604 step 7)"
plan: knowledge-base/project/plans/2026-10-01-feat-workspaces-plaintext-wipe-pr-b-convergence-plan.md
branch: feat-one-shot-6604-plaintext-wipe-pr-b
lane: cross-domain
---

# Tasks — PR B convergence (#6604 step 7)

The plan is the source of truth; these tasks follow its phases. **PR B stays a DRAFT** — the plan's
`## Operator Holds` section governs readiness and merge. Nothing here is a production write.

## 1. Setup

- 1.1 Record the draft base SHA (`git merge-base HEAD origin/main`) for the PR body.
- 1.2 Re-read the KEEP / REMOVE inventory in the plan's Relevant files against the live tree; census
  every removed helper for non-wipe callers.

## 2. RED first

- 2.1 Guard B1 rows (tombstone; `run_case` + MAIN_PREFIX; `CONFIRM_WIPE=1` with `DRY_RUN=0` and `1`,
  `CONFIRM_WIPE=true`, `" 1"`; rc ≠ 0, no `EMIT_DRIFT`, exactly one row) in the suite that will become
  `workspaces-luks-rollback-refusal.test.sh`.
- 2.2 Guard B3 rows (job set; Hetzner-write census over every step, method tokens near `/volumes` and
  `/actions/…`; step-count floor) in `workspaces-luks-cutover-workflow.test.sh`.
- 2.3 Guard B4 rows (`for_each` excludes web-1 via range-scoped sed; sentinel; `prevent_destroy` +
  `delete_protection` incl. the `= false` rows) in `workspaces-luks.test.sh`; raise its cardinality floor.
- 2.4 Confirm each is RED for the stated reason; record the output for the PR body.

## 3. Core implementation

- 3.1 `workspaces-cutover.sh`: delete the wipe section and the mode body; add the tombstone (fires on
  any `CONFIRM_WIPE` other than unset/`0`; no `emit_drift`, own row, `trap - EXIT`, `die`); remove `cleanup()`'s `CONFIRM_WIPE` arm together with
  the `mode`/`begun` locals and their uses; update the `RUN_COMPLETE` header and historical comments.
- 3.2 `workspaces-luks-cutover.yml`: remove the wipe inputs, env, preflight wiring, `api` step,
  `cutover` job-level `if:`, `.env` lines, summary arms and the `wipe` job; keep `cutover`'s
  `environment:` byte-identical and first.
- 3.3 `git rm` the forget workflow and its suite; drop the suite from `scripts/guard-vacuity-floor.test.sh`
  (last `PROMOTED_FILES`); update census/parity comments.
- 3.4 `server.tf`: `locals.plaintext_workspaces_hosts`, both `for_each`s, web-1 sentinel; leave the
  volume `name` expression untouched. `workspaces-luks.tf`: `delete_protection = true` +
  `lifecycle { prevent_destroy = true }` on `hcloud_volume.workspaces_luks`; comments.
- 3.5 Stale-premise text sweep (AC-B6: "live plaintext" and "NO prevent_destroy" — recut/cutover/
  inngest-recut/web-host-replace gate headers, `apply-web-platform-infra.yml` messages, the recut job
  header and `confirm` input description, `apply-deploy-pipeline-fix.yml` comment, the
  `test-workspaces-luks-cutover-gate.sh` header, ADR-148 note). Record the #6931 ordering trap
  (lift `delete_protection` before removing `prevent_destroy`) in the resource comment.
- 3.6 File the pre-existing issue: the `cutover` job's write-token fallback and the possibly-unused
  environment secret (plan "Pre-existing, filed not fixed"); reference it in the PR body.

## 4. Testing

- 4.1 Commit A: `git mv workspaces-luks-wipe.test.sh workspaces-luks-rollback-refusal.test.sh`.
  Commit B: strip to Guard 5 (G5, G5b-*, G5c, G5d-*, G1-W → G5-W, F6, F7, F11, S5 re-scoped, S6) + Guard
  B1; keep `harness_blockdev`/`$TGT_BLK`, `$DM`, `$PIN`, the scratch dir (renamed in one edit); drop
  `LUKS_BLK`, `WIPE_STUBS`, tripwires, `run_wipe`; pin the floor at the exact measured count.
- 4.2 Loopback: Session W → Session G5 (LW-P2/P3/P4; P3 re-seeded by `dd … oflag=direct conv=fsync`
  on the loop device, magic asserted before, `dd` rc and `blkid -p` rc 2 after, backing file checked
  under `$TMPROOT`; trim the required-binary list); re-measure `fixture-relative-assert.baseline.txt`.
- 4.3 Workflow suite: invert/delete wipe rows; re-pin `WF_MIN_ASSERTIONS`.
- 4.4 Freeze T43 → 3; staging T4h-c gains its `EMIT_DRIFT clean_stray_mode_conflict` assertion;
  `luks-monitor.test.sh` drops `wipe_aborted` (mind its `outcome=${o}([;[:space:]]|$)` pattern vs the
  tombstone's quoted literal) and follows the cleanup row pattern; a `cleanup()` abort row has no `mode=`.
- 4.4b Workflow census (B3): whole-step scan, quoted methods, `--request=`, `hcloud volume`, a job-level
  `if:` row, exact step floor.
- 4.4c `bash -n` the plan's release-check block.
- 4.5 Run every suite in AC-B1..B7 (incl. `test-workspaces-luks-cutover-gate.sh` unchanged at 34,
  `test-destroy-guard-counter-web-platform.sh`, `lint-encryption-posture.py`, C4 suites,
  `terraform fmt -check` + `validate`, `actionlint`, `lint-infra-no-human-steps.py --changed`).

## 5. Records

- 5.1 Destruction record: fill rehearsal/baseline/cutover-log fields (labelled "at rehearsal
  36769782488"); `PENDING-EVIDENCE(<field>)` for the rest, including the two pre-filled result rows;
  `plaintext_only_count`; sentinel consequence; durability limits; status stays `template`.
- 5.2 ADR-119 addendum (status stays `adopting`); ADR-241 D2 note.
- 5.3 Legal registers per the CLO wording constraints (PA-1 (g)(17), PA-2 (g)(21), the full 6588 audit
  sweep, NFR Compute row); never `docs/legal/**` or the 8248 audit.
- 5.4 `expenses.md`, `apply-web-platform-infra-job-rationale.md`, runbook step 7 / Sequence 0 /
  abort-triage row, encryption-posture ledger row (prose fields only; `store` byte-exact).
- 5.5 `model.c4` three descriptions; `bash scripts/regenerate-c4-model.sh`; C4 suites.
- 5.6 Draft-time CLO audit `knowledge-base/legal/audits/2026-10-counsel-review-6604.md` with
  `status: BLOCKED (evidence pending)`.

## 6. Ship to the hold

- 6.1 Push; PR body from the plan's template (merge-alone answer first, base SHA, hold, resume prompt);
  labels `semver:patch`, `app:web-platform`, `blocked`.
- 6.2 STOP. Do not run `gh pr ready` or `gh pr merge`. The release is the plan's
  `## Resume After the Hold`, in a later session.
