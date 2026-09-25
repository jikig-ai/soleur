# Tasks — fix(ci): refuse off-main vinngest-v* tags (#8747)

Plan: `knowledge-base/project/plans/2026-09-24-fix-inngest-bootstrap-tag-ancestry-gate-plan.md` (deepened 2026-09-24).

## Phase 1 — RED (tests first)

- [x] 1.1 Fixtures in `.github/scripts/test/test-bump-inngest-bootstrap-pin.sh`: add `seed_tag_at <tag> <rev> [--annotate]`; `MOCK_CRANE_LOG` in the crane stub, `reset_state`, `run_bump`; `run_bump` passes `--signed-commit`.
- [x] 1.2 Bump behaviour rows B1–B11 + B7a (verified constructions: B7 = deleted intermediate loose object, B8 = `refs/vinngest-vX.Y.Z` shadow, B9 = `file://` depth-1 clone with the tag on main HEAD). Every refusal row asserts `::error::ancestry:`, an empty crane log, an empty gh log, and no origin pin branch; every fixture asserts its own precondition.
- [x] 1.3 Inline-step harness I1–I9: slice the refusal step's `run:` body from the YAML by step name, and run it in fixture clones that have `refs/remotes/origin/main`.
- [x] 1.4 Shape asserts S1–S8 (job-key slice, comment-stripped); raise `MIN_ASSERTIONS`.
- [x] 1.5 `apps/web-platform/infra/inngest-bootstrap-mirror-only.test.sh`: exact-string `if: ${{ !inputs.mirror_only }}` on the refusal step; no `if:` on `Record the built commit`; the two-job set assert is unchanged.
- [x] 1.6 Run both suites; confirm they fail for the expected reasons.

## Phase 2 — GREEN

- [x] 2.1 `.github/scripts/bump-inngest-bootstrap-pin.sh`: `target_on_main` (explicit `refs/tags/…^{commit}`, shallow refusal unless the output is exactly `false`, rc 0/1/other kept distinct) placed after `TARGET` and before `crane`; required `--signed-commit` (40-hex, else `args`) that must equal the tag's commit when `SIGNED_TAG == TARGET`; header INPUTS and stage list `args|resolve|ancestry|rewrite|push|pr`.
- [x] 2.2 `.github/workflows/build-inngest-bootstrap-image.yml`: dispatch checkout `ref: format('refs/tags/{0}', inputs.ref)` plus `fetch-depth: 0`; `Record the built commit` step (no `if:`) feeding `build.outputs.commit`; refusal step after `Resolve image tag` (`if: ${{ !inputs.mirror_only }}`, env-only inputs, no `${{` in the body); `--signed-commit` passed to the bump; correct the "always read from the default branch" comment here and in `test-inngest-bootstrap-tag-guard.sh`.
- [ ] 2.3 Run the two suites, `run-all.sh`, `test-inngest-bootstrap-tag-guard.sh` and `cloud-init-inngest-bootstrap.test.sh` (AC6 and GuardA must be unchanged and green).
- [x] 2.4 Apply Guard 1 row 2 and Guard 2 rows 2, 6 and 7 once locally; record the failing assert for each in the PR body.

## Phase 3 — Record the decision

- [x] 3.1 ADR-232: add §7 (both gates, bump authority plus caveat, `--signed-commit`, `mirror_only` not refused, not a secret boundary — never admit the bump job via a tag-pattern policy, old-main-commit residual); add `ancestry` to §6; rewrite Context "cannot disagree", §2, and the Consequences drift-window claim; amendment note; #8782 sequencing; two Alternatives rows.
- [x] 3.2 `model.c4`: add the `ancestry` clause to the `github -> soleurMarketplace` edge; run `c4-count-parity`, `c4-model-freshness`, `c4-code-syntax`, `c4-render`.
- [x] 3.3 `inngest-server.md` §Bootstrap-image release: tag on main after merge (with the delete command), the automated bump, the carrier-changing PR flow, rollback by re-cut.

## Phase 4 — Follow-through

- [x] 4.1 Comment on #6766 (the incident, plus the required-check deadlock warning before #4326).
- [x] 4.2 Comment on #4326 (the next PR; dispatch-from-main shape).
- [x] 4.3 Comment on #8209 (a main-only environment refuses tag-push bump runs; never use a tag-pattern policy).
- [ ] 4.4 Link #8780, #8781 and #8782 from the PR body.

## Post-merge (pipeline-executed, immediately)

- [ ] 5.1 Cut `vinngest-v1.1.40` on the squash-merge commit. If #8209 already gated the bump job with `environment: infra-privileged`, dispatch the build from `main` with `inputs.ref=vinngest-v1.1.40` instead of relying on the push run.
- [ ] 5.2 Watch the run: `verdict=on-main`; the bump reports `result=opened` (auto-merge armed only if `mirror_status=ok`, otherwise verify zot and merge per ADR-232 §5).
- [ ] 5.3 After the bump merges: pin is `v1.1.40`, the tag is an ancestor of `origin/main`, AC6 and GuardA are green.
- [ ] 5.4 Pick up #8782 in the next session.
