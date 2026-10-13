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
      <!-- SUPERSEDED 2026-08-12 (#7440): this was a ONE-SHOT verification that the measurer fix
      had landed — that the corrected reading was ~23.4 kB rather than the phantom -3,636 B. It
      was later transcribed verbatim into a standing regression arm in
      registry-userdata-budget.test.sh, where it silently became a permanent capacity ceiling
      nobody decided on, rationing every future feature on this host to 3,360 B. Do NOT re-derive
      20,000 as policy from this line. The repo's actual headroom policy is 8,000 B, stated once
      as REGISTRY_GZIP_BUDGET < HETZNER_CAP - 8_000 in
      plugins/soleur/test/cloud-init-user-data-size.test.ts; the bash gate now derives its floor
      from that constant. See ADR-185. -->

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

## Phase 5.5 — Review fixes (10-agent panel; all fixed inline, none filed as scope-out)

- [x] 5.5.1 **P1** Assert the strip is APPLIED, not just declared. Unwiring `replace(` left the
      gate reporting 9,408 B / exit 0 on a tree storing 36,404 B. Three agents converged;
      ADR-152 already recorded it as measured ("Assert on the RENDER EXPRESSION").
- [x] 5.5.2 **P1** Add a 4,000 B plausibility floor + `#cloud-config`-survives assertion. Every
      numeric arm was a ceiling, so an over-broad strip reported MAXIMUM headroom for a payload
      that boots a dark host.
- [x] 5.5.3 **P1** `length()` counts graphemes, not bytes, against a byte cap; the comment
      blaming a ~300 B delta on console re-escaping was false (that WAS the UTF-8 delta).
- [x] 5.5.4 **P1** `terraform` absent exited 0 — the last measure-nothing-report-green path.
      Fails closed in CI in both the script and the suite.
- [x] 5.5.5 **P1** `detect-changes` push base `HEAD^1` → `github.event.before`: a multi-commit
      or admin push with a docs-only tip yielded `DIRS=[]` and a green run validating nothing.
- [x] 5.5.6 **P1** Suite rebuilt to 16 checks: adds the two missing mutation arms, the stored
      floor, an assertion on `cap` (nothing read it), and a cross-check against the TS model's
      extracted bounds (implements AC2). `checks < 8` → `EXPECTED_CHECKS` equality.
- [x] 5.5.7 Over-cap message now discriminates broken-regex from payload growth.
- [x] 5.5.8 stderr re-checked after the last console call; `raw`/`stripped` emptiness guarded.
- [x] 5.5.9 Heartbeat stubs 24 → 64 chars so "stubs are upper bounds" is true by construction.
- [x] 5.5.10 ADR-096: byte cap retracted as a live blocker, including in the ROLLBACK procedure.
- [x] 5.5.11 ADR-152: byte-exact-measurement gap marked closed.
- [x] 5.5.12 Four false comments corrected (`^`-anchor claim, #7283 timeline, run-registered-suites
      derivation, "distinct value is byte-exact"). #7282 → PR #7283 provenance.
- [x] 5.5.13 `notify-main-failure` job added — the push-on-main trigger had no consumer, which
      would have reproduced this PR's own defect one layer up.
- [x] 5.5.14 `deploy-script-tests` timeout 8 → 12, re-derived as its comment mandates (measured
      384–501 s against a 480 s ceiling: already cancelling 14% of runs).
- [x] 5.5.15 Plan swept — 7 sections still described the descoped Phase 3 design.
- [x] 5.5.16 Filed #7307 (main-health-monitor dark). Corrected #7302's false #6480 dependency.
- [x] 5.5.17 Mutation-proven with a green control: understated bytes, swapped cap, reverted strip
      application, and neutered dispatch all now red.

## Phase 6 — Ship

- [ ] 6.1 PR body states the premise correction plainly, including the precision note (stock,
      not `user_data`, is the real replace constraint — #6460/#7287).
- [ ] 6.2 `Closes #7299`.
- [ ] 6.3 Comment on #7299 with the measured figures so the "cannot be re-provisioned" claim is
      not left standing for a future operator mid-incident.
- [ ] 6.4 `/review` → `/compound` → `/ship`.
