# Tasks: closing change for the web-2 LUKS rebirth (#9372)

> **Superseded in part (review phase, 2026-10-06):** the first design counted a create of BOTH web-class addresses, read 2 over `passphrase-create.json` and recommended a "reviewed import" recovery. The shipped design counts the passphrase alone, reads 1 over `passphrase-create-password-only.json`, and retracts the import recovery (not a verified route). See the plan's "Review-Phase Amendments" and `decision-challenges.md` items 4 and 5.

Plan: `knowledge-base/project/plans/2026-10-06-feat-web2-luks-rebirth-closing-change-plan.md`
Hard limits: no dispatch (plan-only or real), no Terraform apply, no Doppler write, no token mint, no Hetzner write. `Ref #9372`, never `Closes`.

## Phase 1: Tests first (RED)

- 1.1 In `tests/scripts/test-destroy-guard-counter-web-platform.sh`: flip T64d to must-HALT; re-baseline T64e and T64j and T64m (create counts 1 at the two web-class addresses and their index/module spellings, 0 at the other four); add a test-side literal `WL_CREATE_HALT` list.
- 1.2 Add the Guard 1 rows (per-address, `["create","delete"]` shape, must-stay-legal inngest and web-1 create, no-op, suite-side harness row) and raise the assertion floor by exactly the rows added.
- 1.3 Rework T64g and T60i (drop the vacuous `first create` token; require `CREATE` and the retired-route/recovery phrase from the first emission only).
- 1.4 Run the suite; confirm the new rows are RED on the unmodified filter.

## Phase 2: The filter and the HALT text

- 2.1 `tests/scripts/lib/destroy-guard-filter-web-platform.jq`: add `luks_passphrase_create_halt_addrs` and the `create` arm via `luks_passphrase_base`; rewrite the "first create is legal" comments.
- 2.2 `.github/workflows/apply-web-platform-infra.yml`: HALT block text only (CREATE for the two addresses; retired route; recovery by a reviewed import). Check `workflow-file-size.test.ts`.
- 2.3 Re-run the destroy-guard suite green; confirm `jq ... passphrase-create.json` reads 2.

## Phase 3: Retirement

- 3.1 Delete `.github/workflows/apply-web-escrow-create.yml`, `apps/web-platform/infra/web-escrow-create-workflow.test.sh`, `scripts/web-escrow-create-names.sh`.
- 3.2 Remove the suite bound in `run-registered-suites.sh`, the rows in both TSVs (prefer `regenerate-shard-manifest.py --group infra --incremental --write`), and the `PROMOTED_FILES` paragraph and alternative in `guard-vacuity-floor.test.sh`.
- 3.3 `plugins/soleur/test/terraform-target-parity.test.ts`: drop the list entry and comment, `EXEMPT_PAIR_WORKFLOW`, the exemption in the "NO other workflow FILE" row and the create-only-shape row; census 5 to 4.
- 3.4 Run the parity, suite-registration, vacuity-floor and workflow-file-size gates.

## Phase 4: Records

- 4.1 `model.c4` clause on the `doppler -> hetzner` edge; regenerate `model.likec4.json` with `scripts/regenerate-c4-model.sh`; run c4 freshness, count-parity, canonical.
- 4.2 ADR-263: one dated, merge-conditioned superseded blockquote after the D9 "First-create legality ends" paragraph.
- 4.3 `web-host-birth.md` and `web-host-replace.md`: delete Step 0a and the inline references; re-home the still-valid content into Step 0 (live preflight gate, R2 mint on #9377, push-apply enable window, no-creation-route recovery sentence). `grep 'Step 0a'` returns nothing.
- 4.4 `web2-luks-rebirth-9372.md`: item 1 landed marker, item 2 order and commands, rows 2, 4, 5, 6 per the plan.
- 4.5 `apply-web-platform-infra-job-rationale.md`: dated marker on the "`create` stays legal" sentence.
- 4.6 `scripts/followthroughs/web2-luks-live-6931.sh`: header comment documents the pre-set `earliest=2026-10-18T00:00:00Z`.
- 4.7 `scripts/web2-rebirth.sh`: header and NOT-met message strings only.

## Phase 5: Real-tree flip row

- 5.1 `scripts/web2-rebirth.test.sh`: add the real-tree `flip-precondition yes` row (MET), rename the stale "create exempt today" rows, add a sandbox `real absent` row.
- 5.2 Run the rebirth gate, rebirth script, rebirth workflow and follow-through suites.

## Phase 6: Sweep and gates

- 6.1 Straggler grep per AC1 allowlist; `git diff origin/main -- scripts/encryption-posture-ledger.json knowledge-base/legal/` empty; no `*.tf` and no pipeline-fix trigger file in the diff.
- 6.2 `lint-guard-contract.py`, `lint-encryption-posture.py`, `check-adr-ordinals.sh`, `lint-infra-no-human-steps.py`, markdown lint.

## Phase 7: Tracking and handoff

- 7.1 File the one tracking issue (ledger-flip prerequisites, with the widen-the-HALT checklist line) with a milestone.
- 7.2 PR body: lead with the item-3 User-Challenge; `Ref #9372`; say the #6931 directive is edited after merge; list what was re-homed from Step 0a; cite the latest green `scheduled-terraform-drift` run; no kill-switch token line.
- 7.3 Post-merge: confirm the merge-fired push-apply is green with "No changes"; edit #6931's `earliest=` to `2026-10-18T00:00:00Z` by read-modify-write (one directive, one match); comment on #9372.
