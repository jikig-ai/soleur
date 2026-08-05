# Tasks — fix: `registry-userdata-budget.sh` measures a payload Terraform never stores

Plan: `knowledge-base/project/plans/2026-08-05-fix-registry-userdata-budget-measures-unstripped-render-plan.md`
Closes: #7299 · Branch: `feat-one-shot-7299-registry-userdata-over-cap` · PR: #7300

## Phase 1 — Fix the measurer

- [x] 1.1 Write the failing assertion first: a check that the script's stored-byte figure matches
      the stripped render (currently 36,404 vs the true 9,404) — RED before the fix.
- [x] 1.2 Add a fail-closed extractor for `registry_rationale_strip` in
      `apps/web-platform/infra/registry-userdata-budget.sh`, reading from `zot-registry.tf`.
      Anchored on the assignment, exactly-one match, must be a slash-delimited `(?m)` literal.
      Exit 2 with a named diagnostic on any violation.
- [x] 1.3 Emit the extracted expression into the scratch `locals` block; wrap the render as
      `replace(local.rendered, local.registry_rationale_strip, "")` before `base64gzip`.
- [x] 1.4 Report raw / stripped / stored / cap / headroom in human output; add the stripped
      figure to `--json` additively (existing keys keep their meaning).
- [x] 1.5 Correct the false header claims (script lines 3-4, 21-26): the render mirrors
      `zot-registry.tf` *including* the strip, which is extracted rather than copied.
- [x] 1.6 Verify: `bash apps/web-platform/infra/registry-userdata-budget.sh` → exit 0,
      headroom ≥ 20,000 B. (AC1)

## Phase 2 — Restore the ONE COPY invariant

- [x] 2.1 Update the strip rationale block in `apps/web-platform/infra/zot-registry.tf`
      (~lines 383-386) to name **both** extractors: the TS size test and the budget script.
- [x] 2.2 Add the one-line reason the invariant is fragile (a future consumer that *restates*
      the expression re-opens this defect).
- [x] 2.3 Confirm no `registry-render-strip-parity.test.sh` is added — the plan rejects it
      (one declaration + two extractors = nothing to keep equal).

## Phase 3 — Un-red the job (promotion to required BLOCKED — see plan Phase 3)

- [x] 3.1 Remove `continue-on-error: true` from the `registry-userdata-budget` job.
- [x] 3.2 Register `registry-userdata-budget.test.sh` as a step in the same job, so the
      CI-registered infra runner discovers it. (AC12)
- [x] 3.3 ~~Add the context to `infra/github/ruleset-ci-required.tf`.~~ **DESCOPED.** The
      workflow is `paths:`-filtered, so on a docs-only PR it never triggers and a required
      context would never report — deadlocking every non-infra PR. `if: always()` does not
      help; only dropping the paths filter does, which is tracked in #6480. File a follow-up
      instead. (AC9 now asserts the file is unchanged.)
- [x] 3.4 Correct the stale rationale comment, which asserts a live breach that does not exist,
      and record that promotion is gated on #6480 rather than declined.

## Phase 4 — Run Infra Validation on main pushes

- [x] 4.1 Add a `push:` trigger on `main` to `.github/workflows/infra-validation.yml` with the
      same `paths:` set as the existing `pull_request:` block.
- [x] 4.2 Verify the `plan` job stays PR-only or credential-gated — nothing needing
      `prd_terraform` may widen onto the push event.

## Phase 5 — Verification gates

- [x] 5.1 Fail-closed proof: scratch copy of `zot-registry.tf` with the strip deleted → script
      exits 2; with it duplicated → exits 2. (AC4)
- [x] 5.2 `bun test plugins/soleur/test/cloud-init-user-data-size.test.ts` → 38 pass, 0 fail
      (unchanged). (AC5)
- [ ] 5.3 `bash scripts/test-all.sh` green — full suite, catches orphan infra suites. (AC6)
- [x] 5.4 `actionlint .github/workflows/infra-validation.yml` clean; edited `run:` snippets
      parse under `bash -c`. (AC7)
- [x] 5.5 `terraform fmt -check apps/web-platform/infra/zot-registry.tf` clean. (AC8 — retargeted
      from `infra/github/`, which Phase 3's descope leaves untouched.)
- [x] 5.6 Assert the strip expression appears exactly once as an assignment repo-wide. (AC3)

## Phase 6 — Ship

- [ ] 6.1 PR body states the premise correction plainly, including the precision note (stock,
      not `user_data`, is the real replace constraint — #6460/#7287).
- [ ] 6.2 `Closes #7299`.
- [ ] 6.3 Comment on #7299 with the measured figures so the "cannot be re-provisioned" claim is
      not left standing for a future operator mid-incident.
- [ ] 6.4 `/review` → `/compound` → `/ship`.
