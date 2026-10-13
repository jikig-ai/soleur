# Tasks: feat-one-shot-9879-luks-sole-copy-protection

Plan: knowledge-base/project/plans/2026-10-10-infra-protect-inngest-luks-sole-copy-plan.md

## Phase 0 — Prove delivery (read-only)

- 0.1 Apply the Phase 1 edit in the worktree (no commit yet).
- 0.2 Use Terraform 1.10.5 (the workflow pin). Extract the per-merge `-target` list (188 entries) from `apply-web-platform-infra.yml`; get the user's decision to pull the two privileged-tier variables (`cf_api_token_r2`, `doppler_token_tf` from `soleur-infra-privileged/prd`); run a read-only plan (`-lock=false`, read-only Hetzner token asserted, no fallback, throwaway ssh public key), NO volume target. Raw plan and JSON stay in the scratchpad.
- 0.3 Assert: one volume in-place update, no other update, no add/destroy, no web-1/web-2/git_data/rehearsal address, `hcloud_server.inngest` absent. If the volume is absent from the plan, STOP and re-plan.
- 0.4 Replay the destroy-guard jq and the per-merge halt logic over the plan JSON (scratchpad); write `specs/feat-one-shot-9879-luks-sole-copy-protection/apply-plan-output.md` as a jq PROJECTION only (address, actions, `delete_protection` before/after); grep staged files for the live key hash, `prior_state`, `sensitive_values`, `dp.st.`, 64-char tokens; delete the scratch plan files.

## Phase 1 — Terraform pins

- 1.1 `inngest-redis-luks.tf`: volume `delete_protection` + `lifecycle { prevent_destroy }`; pair `prevent_destroy`; attachment unchanged plus explanatory comment; fix stale header comment; comments never spell the `delete_protection = true` literal.
- 1.2 `inngest-host.tf`: `prevent_destroy` on `doppler_project.inngest` and `doppler_environment.inngest_prd`.
- 1.3 `terraform fmt -check`, `terraform validate`.

## Phase 2 — Guards (matrices first)

- 2.1 Record `workspaces-luks.test.sh` pass count and floor; check no B4 row edits `strip_comments` via the suite text.
- 2.2 Extract the lexer to `tests/scripts/lib/hcl-effective-text.sh`; source it from `workspaces-luks.test.sh`; counts identical; neuter-the-library reds both.
- 2.3 Write `inngest-luks-sole-copy.test.sh` (Guard 1, 12 mutation rows, must-PASS rows, floors); register in `suite-shard-legs.tsv` and `suite-durations.tsv`; run `lint-orphan-test-suites.sh` and `guard-vacuity-floor.test.sh`.
- 2.4 Extend B5/B6 in `terraform-target-parity.test.ts` (Guard 2 expected-set literal, `-replace`/`-destroy`/taint/state spellings).
- 2.5 Census: extend `G4_PROTECTED`, derive `G4H_SOLE_COPY`, add `moved_blocks` collector, add G4h (Guard 3) with the App-identity must-PASS row, update presence list and exact row-count floor/ceiling.

## Phase 3 — Sanctioned path

- 3.1 Build the host-replace gate fixture from the Phase 0 projection (synthesized document shape; no raw plan JSON committed); add the PASS (volume no-op) and ABORT `luks_volume_touched` (volume update) rows to `test-inngest-host-replace-gate.sh`.
- 3.2 Run the existing gate suites unchanged.

## Phase 4 — Records

- 4.1 New ADR (probe `origin/*` for the next free ordinal now and before merge); ADR-142 pointer addendum; ADR-263 divergence note.
- 4.2 Runbook section in `inngest-luks-cutover-6894.md` (ADR link, wrapped read-back command, unprotect two-step, no erase path, replace-after-apply, `manual-rerun`, no untargeted apply, revert recipe output).
- 4.3 Ledger row text; `model.c4` description; regenerate `model.likec4.json`; C4 count-parity and syntax/render tests.
- 4.4 Article 30 TOM + (e) pointer; compliance-posture bracket; do not touch the attested audit files.
- 4.5 Execute the revert recipe once in a scratch detached worktree and record the output.
- 4.6 Verify #9927 matches the plan (items 1-10).
- 4.7 Verify the "reminders re-armable from Postgres" claim and record who tells users after a total loss; record required-check and CODEOWNERS coverage of the pin files (read-only) in the ADR.
- 4.8 Runbook: break-glass (one `change_protection` call, per-command go-ahead, re-protect same session), and the override of the drift issue's local-apply text.

## Phase 5 — Gate

- 5.1 Full targeted battery (`TEST_GROUP=affected`); CI is the authority.
- 5.2 Surface `apply-plan-output.md` to the user; obtain an explicit per-command go-ahead; confirm no `[skip-web-platform-apply]` marker.
- 5.3 PR body first line states the production effect; `Closes #9879`; `Ref` for others; Generated-with line; commit trailer.
- 5.4 After merge: `soleur:postmerge` read-back (`protection.delete` true) and drift check on the named addresses.
