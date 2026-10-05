# Tasks: fix #8710 — pin-redeploy gate keys on the apply step

Plan (v3, deepened): `knowledge-base/project/plans/2026-09-24-fix-pin-redeploy-gate-keys-on-apply-step-plan.md`.
Constraint: no workflow dispatch of any kind. Verification is the hermetic suite, the parity test
and read-only `gh run view` calls.

## Phase 1: Setup

- [x] 1.1 Re-read `source-run-gate.sh`, the G rows of `tests/scripts/test-dispatch-web-redeploy.sh`,
  and the `git-data-pin-redeploy.yml` describe block of `plugins/soleur/test/terraform-target-parity.test.ts`.
- [x] 1.2 Copy the two apply-step names byte-for-byte from `apply-web-platform-infra.yml` (the replace
  name contains U+2014).

## Phase 2: RED first

- [x] 2.1 Rewrite `_gjobs` to emit per-job `status`, `conclusion` and measured-shape `steps[]`.
- [x] 2.2 Parameterise `_mutant` / `_mut_row` with the source script (`$TRACK` for existing rows).
- [x] 2.3 Add G9 and G9b; run them against
  `git show origin/main:.github/actions/dispatch-web-redeploy/source-run-gate.sh` and record the RED
  output for the PR body (AC2).
- [x] 2.4 Add G1 (decoy, non-canonical must-PASS), G2, G3b, G10, G11, G12, G14, G15, G16, G18, G19,
  G20, G21; delete G4 and G8 (their assertions move to G12); keep G3 (plus its new negative
  assertions), G5, G6, G7. Every row asserts its own `verdict=` token.
- [x] 2.5 Add PT1, PT2, PT3 (`applyStepParity`) with their in-test mutated-YAML cases.

## Phase 3: Core implementation

- [x] 3.1 Rewrite `source-run-gate.sh` to the v3 rule (order 1, 1b, 4, 2, 3, 5a/5b).
  - [x] 3.1.1 `A` allowlist (else `unrecognized`), numeric `N`, never print an API name.
  - [x] 3.1.2 Distinct `verdict=` tokens on the same line as `in run <id>` and the per-job tokens.
  - [x] 3.1.3 Emit `proceed`, `source_job`, `pin_published` on every non-exit path.
  - [x] 3.1.4 5a replace-job warning names the runbook section "If the fresh host fails a boot
    check after step 3"; birth-job warning names the no-`source_run_id` dispatch as the only recovery.
  - [x] 3.1.5 Header comment carries the table and cites ADR-237 D2; each mutation site one unique line.
- [x] 3.2 Add mutation rows 1–10 over the gate; list the GH loop rows (AC6).
- [x] 3.3 `git-data-pin-redeploy.yml`: new `pin_published` email step; one no-`source_run_id`
  sentence in the failure email body and the header `Recovery:` comment; update the parity test's
  secrets list to two `secrets.RESEND_API_KEY` occurrences.
- [x] 3.4 ADR-237: the D2 / first-Consequences narrowing, the apply-step display-name bullet, the
  pin-lag red-job case.
- [x] 3.5 Runbook `git-data-luks-cutover-5274.md`: step-3 GO caveat, the "Boot order on the
  replace" bullet, the four recovery sites, the §2026-09-24 runbook row G2 cell (T-R1).

## Phase 4: Testing

- [x] 4.1 `bash tests/scripts/test-dispatch-web-redeploy.sh`.
- [x] 4.2 `bun test plugins/soleur/test/terraform-target-parity.test.ts`.
- [x] 4.3 `bash tests/scripts/test-infra-privileged-tier-census.sh`.
- [x] 4.4 Read-only real-run check (AC5): `SOURCE_RUN_ID=<id> bash .github/actions/dispatch-web-redeploy/source-run-gate.sh`
  for 35979044625, 35979304442, 34822248580, 34836141887; record outputs for the PR body.
- [x] 4.5 `scripts/test-all.sh --capacity` before any commit that stages a `.ts` file.
- [x] 4.6 `npx markdownlint-cli2` on every edited `.md`.

## Phase 5: Ship

- [ ] 5.1 PR body: first line "Merging this alone mutates nothing in production"; `Closes #8710`;
  Ref #5274, #5914, #8760; AC2 and AC5 outputs; render `decision-challenges.md`.
- [ ] 5.2 Merge only when every context in
  `scripts/ci-required-ruleset-canonical-required-status-checks.json` is `success` by name on the
  exact head SHA; normal auto-merge; on a `main` livelock, stop and hand the merge to the operator.
- [ ] 5.3 On conflicts in `scripts/guard-vacuity-floor.test.sh` `PROMOTED_FILES`, resolve as a
  union; re-derive baselines and floors after every merge. Do not edit the #8634 audit.
