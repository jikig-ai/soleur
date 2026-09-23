# Tasks: fix doppler_project.infra_privileged description cap (Ref #8209)

Plan: `knowledge-base/project/plans/2026-09-23-fix-infra-privileged-doppler-description-cap-plan.md`

## Phase 1: Setup

- [ ] 1.1 Re-read `apps/web-platform/infra/infra-privileged-environment.tf` at
  `resource "doppler_project" "infra_privileged"` and re-measure the current description (273).
- [ ] 1.2 Re-derive the live counts the plan quotes (79 `doppler_*` resource blocks in 30 files, 4
  descriptions, max 245 bytes after the fix) with the plan's grep, not from memory.

## Phase 2: The string (its own commit, first, so it can ship alone if the guard stalls)

- [ ] 2.1 Replace the description with the plan's 228-character string.
- [ ] 2.2 Update the comment above it: it names the lint, and drops the `(see doppler_project.inngest)` pointer.
- [ ] 2.3 Move the dropped clause (the read token is an environment secret on main-only
  environments) into the `--- The Tier-B Doppler project ---` comment block.
- [ ] 2.4 Commit the string fix alone.

## Phase 3: Guard, RED first

- [ ] 3.1 Write `scripts/lint-doppler-description-length.test.sh` from Guard 1's mutation matrix
  (rows 1-14, H1, H2, H4) using the data-driven `row` helper. The suite needs:
  - a call-site counter written literally as `cases=$((cases + 1))`;
  - a helper self-test that resets `PASS` and `FAIL` afterwards;
  - `PASS + FAIL == cases`;
  - a literal `MIN_CASES` on the line above a multi-line floor `if` that prints `[FATAL] assertion floor`.
- [ ] 3.2 Run it and confirm the RED rows are RED (the lint does not exist yet).
- [ ] 3.3 Write `scripts/lint-doppler-description-length.py` with:
  - current-header attribution, skipping blank lines;
  - a fail-closed orphan `description`;
  - raw UTF-8 bytes;
  - the unescaped-template regex;
  - remediation text in each FAIL;
  - vacuity on zero headers or zero descriptions.
- [ ] 3.4 The suite is green. The lint in fixture mode on `origin/main`'s
  `infra-privileged-environment.tf` FAILs naming `273`, and the live run prints `OK:` with
  `4 description(s) measured, max 245/255 bytes`.
- [ ] 3.5 Register the `-live` and `-unit` `run_suite` lines in `scripts/test-all.sh` next to
  `scripts/lint-infra-no-human-steps`.

## Phase 4: Local verification

- [ ] 4.1 `bash scripts/guard-vacuity-floor.test.sh` passes, and `covered` and `floor fires` are each
  exactly one higher than on `origin/main`. `PROMOTED_FILES` is unchanged (on a rebase conflict,
  resolve it as the union).
- [ ] 4.2 `terraform -chdir=apps/web-platform/infra fmt -check`.
- [ ] 4.3 `python3 scripts/lint-guard-contract.py` on the plan, and markdownlint on the plan and this file.
- [ ] 4.4 No `.ts` staged. If one becomes necessary, `scripts/test-all.sh --capacity` runs first.

## Phase 5: Ship and merge gate

- [ ] 5.1 The PR body's first line says that merging creates the `soleur-infra-privileged` Doppler
  project and its `prd` environment through the push apply. The body says `Ref #8209`, not Closes.
- [ ] 5.2 Admit the merge only when every context in
  `scripts/ci-required-ruleset-canonical-required-status-checks.json` is `success` by name on the
  exact head SHA. Read the latest run per name (the plan's Phase 4 block): `comm -23` prints nothing,
  and the derived positive count holds.

## Phase 6: Post-merge verification (read-only, pipeline-executed)

- [ ] 6.1 The `apply` **job** (not only the run) on the merge SHA concludes `success`. Wait for it
  with a Monitor until-loop.
- [ ] 6.2 Its plan creates only `doppler_project.infra_privileged`,
  `doppler_environment.infra_privileged_prd`, and the #8202 pair (plus any concurrently merged PR's
  own addresses), with no destroy or replace, and no `doppler_secret.github_app_*` lines.
- [ ] 6.3 `doppler projects get soleur-infra-privileged` resolves, and `doppler configs -p soleur-infra-privileged` lists `prd`.
- [ ] 6.4 All four Tier-B environments read `custom=true` and `["main"]`.
- [ ] 6.5 Comment on #8209 with the green run link and the O0 state, one line per resource, and note
  that O2 is unblocked and that ADR-237 step 1 holds for every post-fix run.
