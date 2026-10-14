# Tasks: feat-one-shot-6612-sentry-terraform-drift

Plan: `knowledge-base/project/plans/2026-09-24-chore-sentry-root-scheduled-terraform-drift-leg-plan.md`
(v2, post plan-review). Closes #6612. This is a separate PR. Do not bundle it with #4781 / PR #8654 or
#8630.

## Phase 1: Setup (RED)

- [ ] 1.1 Create `plugins/soleur/test/terraform-drift-sentry-leg.test.sh`:
  - python-yaml extraction of the `plan` step and the `Prepare email content` step, with an extraction
    floor;
  - run under `bash --noprofile --norc -e` (no pipefail, the way Actions runs it);
  - PATH stubs:
    - `terraform` records argv plus SET/UNSET flags (`SENTRY_AUTH_TOKEN`, `TF_VAR_sentry_auth_token`,
      `DOPPLER_TOKEN`, `TF_LOG`), never values, and optionally echoes the token to stderr (for B8);
    - `doppler` exits 97 on the Sentry leg;
    - `gh` copies `--body-file` for the behavioural I1/I2 rows.
- [ ] 1.2 Rows S1–S5 (S1 requires all three matrix entries), B1–B5, B7, B8 (token scrub), E1–E2,
  behavioural I1–I2, H1, and the conditional R1–R4 real-terraform arm
  (`terraform_data` with a local backend).
- [ ] 1.3 Anti-vacuity floor set to the literal assertion count, with a comment.
- [ ] 1.4 Confirm the suite is RED on the unmodified workflow.

## Phase 2: Core Implementation (GREEN)

- [ ] 2.1 Matrix: append `- apps/web-platform/infra/sentry`, with a comment block covering #6612,
  ADR-031, the auth choice, and full-root planning.
- [ ] 2.2 Plan step `env`: add
  `SENTRY_IAC_AUTH_TOKEN: ${{ matrix.directory == 'apps/web-platform/infra/sentry' && secrets.SENTRY_IAC_AUTH_TOKEN || '' }}`.
- [ ] 2.3 Plan step `run`: add a Sentry arm that is
  - an empty-secret `::error::sentry_iac_token_absent` guard, then
  - `env -u DOPPLER_TOKEN -u DOPPLER_PROJECT -u DOPPLER_CONFIG -u TF_LOG -u TF_LOG_PROVIDER
    SENTRY_AUTH_TOKEN="$SENTRY_IAC_AUTH_TOKEN" terraform plan -detailed-exitcode -no-color -input=false`,
    then `PLAN_OUTPUT=${PLAN_OUTPUT//"$SENTRY_IAC_AUTH_TOKEN"/***}`.

  The existing Doppler path moves into `else`, unchanged except for indentation. The matrix comment
  must not spell `secrets.SENTRY_IAC_AUTH_TOKEN`, because S2 expects exactly 1. Everything stays inside the `set +e` bracket.
  No retry.
- [ ] 2.4 Drift-issue step:
  - add `MATRIX_DIR` to the step env;
  - when the directory is the Sentry root, replace remediation step 2 with the check-in-flight-apply
    text and `gh workflow run apply-sentry-infra.yml --ref main -f reason="..."`. Write it with a
    QUOTED heredoc (`cat <<'EOF'`), never `echo "…"`, because the backticks would execute;
  - leave other stacks byte-identical.
- [ ] 2.5 Email snippet: `grep -v ': Refreshing state\.\.\.' … | head -c 4000 | sed …` (all legs).
  Also add `STACK_NAME: ${{ steps.plan.outputs.stack_name || matrix.directory }}` to that step's env.
- [ ] 2.6 Anchor T3 in `plugins/soleur/test/terraform-drift-step-order.test.sh` with an exact-line match
  and make `WF` overridable. Mutation-verify it on a sandbox copy with the main-root entry deleted.
- [ ] 2.7 Update the leg-set comments at lines 1–4 (the file header), ~150–157, ~566–577, ~965–970
  and ~1769–1774. Afterwards
  `grep -nE '2-leg|two-leg'` must print nothing.

## Phase 3: Docs and ADR

- [ ] 3.1 ADR-031: append an amendment (2026-09-24, #6612) of about 20 lines before `## Consequences`.
  It covers what changed, the divergence paths, the `use_lockfile` consequence, auth, routing (with
  the >3-errors-in-30-days exit criterion), blind spots, the tiering note (cite the issue from 4.6)
  and the full ADR-033 filename. Append-only: `git diff --numstat "$(git merge-base origin/main HEAD)"`
  must show 0 deleted lines.
- [ ] 3.2 Sentry README:
  - replace the §Drift detection "Everything else…" paragraph with the third detector, using the
    `-f reason=` remediation;
  - add the note on the backend-creds sentence.
- [ ] 3.3 `scheduled-sentry-alert-drift.yml` header: replace the "WHY NOT ADD … INSTEAD" paragraph
  with a short note that the two workflows complement each other. Do not claim the muting concern
  is resolved. Comment only.
- [ ] 3.4a C4: add the clause "…and `scheduled-terraform-drift.yml`'s sentry leg plans the same root
  READ-ONLY twice daily…" to the `github -> sentry` edge in `model.c4`. Then run
  `bash scripts/regenerate-c4-model.sh`, `c4-model-freshness.test.sh` and `c4-count-parity.test.sh`.
- [ ] 3.4 Post-mortem `sentry-iac-delete-path-silent-noop-postmortem.md`: set the #6612 row status to
  `closed by PR #<N>`.

## Phase 4: Testing and gates

- [ ] 4.1 Run the new suite with terraform on PATH, then quote the `R-arms: ran` line in the PR body.
- [ ] 4.2 Run the step-order, token-drift-workflow-causes, terraform-target-parity and c4-count-parity
  suites, plus `tests/scripts/test-sentry-alert-drift-workflow.sh`, lint-orphan-test-suites,
  actionlint, and lint-guard-contract on the plan.
- [ ] 4.6 File the ADR-241 tiering-gap issue (labels `domain/engineering`, `type/security`) and cite
  it in the ADR amendment.
- [ ] 4.3 Before EVERY push, run
  `python3 scripts/lint-skill-body-budget.py --base "$(git merge-base origin/main HEAD)"` and
  `bash scripts/lint-diagnosis-claims.sh`.
- [ ] 4.4 PR body:
  - the first line answers "does merging mutate production?" (no);
  - `Closes #6612`;
  - the not-bundled statement;
  - the run 35903124451 divergence citation;
  - the DC-1 and DC-2 decision challenges.
- [ ] 4.5 AC-B: this PR's `plan_pr` log shows `No changes. Your infrastructure matches`.

## Phase 5: Post-merge proof

- [ ] 5.1 Wait for the post-merge `apply-sentry-infra.yml` run. Avoid 06:00 and 18:00 UTC ±30 min.
  Fire `trigger.sh --event cron/terraform-drift.manual-trigger` via `soleur:trigger-cron`.
- [ ] 5.2 Poll with Monitor's until-loop for a completed soleur-ai[bot] run after the merge. Confirm the
  job `drift-check (apps/web-platform/infra/sentry)` exists.
- [ ] 5.3 Grep the executed lines in the log:
  - `No drift detected in web-platform/sentry` appears exactly once;
  - there are 0 hits for `##\[error\]Terraform plan failed in web-platform/sentry`,
    `##\[error\]sentry_iac_token_absent` and `failed to perform health check`.
- [ ] 5.4 Admin-merge ONLY with operator approval.
