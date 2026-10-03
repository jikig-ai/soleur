# Tasks: switch the App-token release jobs to the narrow Doppler source (PR-2 of 2)

Plan: `knowledge-base/project/plans/2026-10-03-security-switch-app-token-release-jobs-to-infra-app-doppler-token-plan.md`
Issue: 9321 (this PR carries `Closes #9321`).

Standing constraints: no production writes by the pipeline (no dispatch of a release or infra workflow, no Doppler or GitHub-secret write); never print a secret value; CI is the test gate; the PR edits `.github/workflows` and `.github/actions`, so it is NOT merged, NOT auto-merged and NOT admin-merged by the pipeline; out of scope: GHCR retirement and the legal cluster (`cla.yml`, legal documents); no `#N` of a closed issue in any commit or PR text; touch no `.tf` file and no `apps/web-platform/**` path.

## 1. Tests and guards first (RED against current main)

- 1.1 `.github/scripts/test/test-mint-inngest-bootstrap-tag.sh`: new step name and secret in the `find`/`exact` rows and the name-dependent rows `step-order`, `h2-env-mapping`, `h1b-keyset-load-bearing` (a naive swap of names alone leaves 24 failures, including the composite-section rows the stub drives); composite stub with a per-run expected project (default narrow) and rows for default, `doppler-project: soleur-infra-privileged`, and an unlisted value refused before any call; default-flip mutation row; `comp.scoped:notice` with the trailing `source=` field; `no-broad-tier-b` row plus explicit `grep -q '^BAD no-broad-tier-b '` assertions; update the `g3.wf:row-count` pin (39 -> 40); reword stale prose (lines near 1351, 1357, 1482-1492); raise `MIN_ASSERTIONS` to the measured count.
- 1.2 `.github/scripts/test/test-bump-inngest-bootstrap-pin.sh`: `g2.action:doppler-config` needle, `g2m.control:clean` and `h2-env-mapping` follow the rename, S17, S18, S24 (tests `DOPPLER_TOKEN_INFRA_APP`), new S25, mutation rows with the new secret name (`script-env-extra-token` names `INFRA_APP`), new `mint-broad-tier-b` row; raise `MIN_ASSERTIONS`.
- 1.3 `tests/scripts/test-apply-github-infra-mint-shape.sh`: pin `doppler-project: soleur-infra-privileged` (and keep the broad `doppler-token` pin), add `project-dropped` row, reword the header, `MIN_ASSERTIONS` 8 -> 9.
- 1.4 `tests/scripts/test-infra-privileged-tier-census.sh`: enlarge the compliant BASE fixture (composite + release-shaped caller + loader-calling caller); write G7f mutation rows M1-M7 and M2b and harness rows H1/H2 and measure each RED BEFORE writing the check; implement G7f; add `G7f` to `G7_ROW_IDS`; raise `CENSUS_ROWS` (41 -> 42), `MUTANT_FLOOR` (exact), `FLOOR` to measured counts with dated comments; re-measure G1a, G4e, G6n, G7c-e on the enlarged fixture; run the WHOLE census.

## 2. Production edits (GREEN)

- 2.1 `.github/actions/mint-infra-app-token/action.yml`: optional `doppler-project` input (default `soleur-infra-app`, validated against exactly the two literals before any Doppler call); reads use the validated project and `--config prd`; error strings name the source used; "not readable" messages append the static runbook pointer; `::notice` gains `source=`; description and input text rewritten; add a short comment beside the pinned `default:` line.
- 2.2 `.github/workflows/build-inngest-bootstrap-image.yml` (job `bump-cloud-init-pin` only) and `.github/workflows/mint-inngest-bootstrap-tag.yml`: comments, step name `Verify DOPPLER_TOKEN_INFRA_APP present`, env, error text, `with: doppler-token`. Do not touch the probe-gate window or any carrier, pin or Dockerfile-heredoc line.
- 2.3 `.github/workflows/apply-github-infra.yml`: add `doppler-project: soleur-infra-privileged` to the mint step only.

## 3. Architecture record, runbook, C4

- 3.1 ADR-241: amend D11 in place, Status bullet and Statuses row to `adopting`, "Ordering with D10" dated note, one Amendment-log entry listing the superseded statements.
- 3.2 ADR-232: one dated marker at the "recorded deferral" sentence.
- 3.3 Runbook `infra-credential-tiers-8209.md`: release-job rows, third-caller note, dated follow-on notes, R-step-2 gate note, §Release-job App source (cause-to-stage table, exact proof command and evidence list, ordered rollback, rotation addendum).
- 3.4 `inngest-server.md` recovery row.
- 3.5 `model.c4`: both `github -> doppler` sentences and the `github -> soleurMarketplace` sentence (and any other the re-grep finds); regenerate `model.likec4.json`; run `c4-count-parity` and `c4-model-freshness`.
- 3.6 Residual greps (old step name, old error text) return nothing outside archived and historical files.

## 4. Verify and open

- 4.1 Run locally: the three edited suites, the bump suite, the census, the two C4 tests, `lint-infra-no-human-steps.py` on changed markdown, and the Decide dry-run (`bash .github/scripts/mint-inngest-bootstrap-tag.sh --dry-run`); record `result=`/`reason=`.
- 4.2 Create the post-merge proof tracker issue (command, evidence list, decision tree; milestone from the roadmap); link it from the PR body.
- 4.3 PR body: `Closes #9321`, landing-order statement, timestamped names-and-counts evidence and read-only verification reads, the operator's READY_FOR_PR2 report quoted from the brief, the dry-run result, note that the diff includes the already-cherry-picked bootstrap fix, the operator hand-off block (rebase and re-measure floors, re-run dry-run and listings and the bootstrap `verify` stage, then merge; then the proof dispatch).
- 4.4 Mark ready; wait for CI green; do NOT merge, enable auto-merge or admin-merge.
