# Tasks: close the tf-var rebind path in apply-github-infra (#9362)

Plan: knowledge-base/project/plans/2026-10-10-fix-github-ruleset-required-check-integration-id-rebind-plan.md

## Phase 1: failing checks first

- 1.1 Extend tests/scripts/test-apply-github-infra-mint-shape.sh with Guard 2 checks in check.py and rows (wrapper re-added, DOPPLER_TOKEN on wrong step, secrets download, no apply job, gate step missing/misordered/relative path/no pipefail); raise MIN_ASSERTIONS.
- 1.2 Add the gate-script section: fixtures built with jq from tests/scripts/fixtures/tfplan-real-ruleset-baseline.json and both canonical files; rows for rebound id (first and last), renamed/dropped/added context, absent address, null after, empty set, empty stdin, no args, malformed canonical, no-op with rebound after, null id; must-PASS rows; stub-exits-0 harness row.
- 1.3 Run the suite and confirm the new rows are RED.

## Phase 2: gate script

- 2.1 Create scripts/verify-ruleset-required-checks.sh (read stdin first, shared projection, whole-set compare, exit 0/1/2, jq stderr to /dev/null, no set -x).
- 2.2 Run the suite; gate-script rows green.

## Phase 3: workflow

- 3.1 Rewrite the header comment (no literal tf-var transformer flag).
- 3.2 Delete the four doppler run prefixes and the unused DOPPLER_TOKEN env on the import, plan and apply steps.
- 3.3 Insert the Gate planned required-check bindings step between plan and apply (absolute GITHUB_WORKSPACE paths, pipefail, two invocations).
- 3.4 Run the mint-shape, census (tests/scripts/test-infra-privileged-tier-census.sh), destroy-guard, canonical-parity, audit, marketplace-drift and shell-trace lint targets.

## Phase 4: ownership and record

- 4.1 CODEOWNERS rows: new script, CLA canonical, mint-shape suite.
- 4.2 Add the script, shared lib and both canonicals to the mint-shape AFFECTED array in scripts/lib/test-affected-paths.sh; run scripts/lint-orphan-test-suites.sh.
- 4.3 ADR-241 dated amendment entry and cross-reference from the 2026-10-01 bullet; run c4-count-parity.
- 4.4 File the follow-up issue (drift leg, PR plan job, infra/github/README.md recipe).

## Phase 5: ship

- 5.1 PR body: first line "No apply runs on merge ...", Refs #9362 #8209 #8609, milestone/priority note.
- 5.2 Owner review (CODEOWNERS), then arm auto-merge once and poll read-only. No --admin, no dispatch, no push after arming.
