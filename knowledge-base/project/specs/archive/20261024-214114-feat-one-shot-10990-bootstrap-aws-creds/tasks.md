# Tasks — fix: bootstrap scripts read-only prd_terraform AWS_* (issue #10990)

Plan: `knowledge-base/project/plans/2026-10-24-fix-bootstrap-state-write-aws-creds-plan.md`

## Phase 1 — Script cred-leg fixes

- [ ] 1.1 `apps/cla-evidence/infra/bootstrap.sh` — repoint `STATE_KEY`/`STATE_SEC`
      from `doppler secrets get AWS_* -p soleur -c prd_terraform` to
      `doppler secrets get TF_STATE_AWS_* -p soleur-infra-privileged -c prd`
      with `|| { red ...; exit 1; }` arms; update the comment block; keep
      `CF_ACCOUNT_ID` on `prd_terraform` and keep `tf_env` unchanged.
- [ ] 1.2 `apps/web-platform/scripts/bootstrap-live-verify.sh` — same swap for
      both `doppler secrets get` legs (update `::error::` source names), keep
      the empty check, update the surrounding comment + header step-1
      description (`:11-12`), and adopt the nested loader on the apply leg:
      `doppler run -p soleur-infra-privileged -c prd --name-transformer tf-var
      -- doppler run -p soleur -c prd_terraform --name-transformer tf-var
      --preserve-env -- terraform -chdir=... apply ...`
- [ ] 1.3 `bash -n` both scripts (AC8); confirm the
      `bootstrap-live-verify|seed-live-verify` negative CI grep still returns
      zero (AC7).

## Phase 2 — Prescribing-prose fix

- [ ] 2.1 `plugins/soleur/skills/plan/references/plan-sharp-edges.md` line-140
      entry — split the triplet into read invocations (`prd_terraform` pair
      stays valid) vs write invocations (`export AWS_*` from `TF_STATE_AWS_*`
      in `soleur-infra-privileged/prd` + nested loaders), one-line pointer to
      `infra-credential-tiers-8209.md` §Local Terraform invocation (AC6).

## Phase 3 — Guard limb

- [ ] 3.1 `tests/scripts/test-infra-privileged-tier-census.sh` — add the AC7b
      `.sh` state-writer limb per the plan's Guard Contract: filesystem walk
      of `*.sh` under `IPT_REPO_ROOT`, state-write classification on the
      invocation token set, population floor `>= 2` (the two armed files),
      all-or-none pair assertion, read-only exemption.
- [ ] 3.2 Add the mutation-battery rows 1-7 per the plan's matrix (buggy-shape
      fixture RED, dispatch floor, second member, half-set, harness row,
      read-only PASS control, compliant PASS).
- [ ] 3.3 Run `bash tests/scripts/test-infra-privileged-tier-census.sh` green
      with the fixed tree (AC4/AC5).

## Phase 4 — Verification

- [ ] 4.1 Run every AC command in the plan's `## Acceptance Criteria`.
- [ ] 4.2 `bash scripts/test-all.sh --print-selection` shows the census suite
      selected by this diff, or run the `scripts` group (AC9).
- [ ] 4.3 Commit; PR body `Closes #10990` (code fix, not ops-remediation —
      `Closes` is correct here).
