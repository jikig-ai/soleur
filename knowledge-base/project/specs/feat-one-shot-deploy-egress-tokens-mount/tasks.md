# Tasks - fix: deploy-started web container lacks the egress-tokens mount and reaper flag

Plan: `knowledge-base/project/plans/2026-10-19-fix-deploy-egress-tokens-mount-plan.md`
Closes #10457 (in the PR body, not the title).

## Phase 1 - RED tests (no production change)

- 1.1 Add K24a-d "declared member missing" kill rows to `apps/web-platform/infra/docker-run-tuple.test.sh` (members the tuples already carry; expect `MISSING_DECLARED` plus file/tuple needle)
- 1.2 Add the independent prod-has assertion (mount + REAPER on the prod line) to `apps/web-platform/infra/ci-deploy.test.sh` (mock docker `DOCKER_RUN_ARGS:` lines, distinguished by `--name`)
- 1.3 Run both suites; record the RED output lines

## Phase 2 - checker arm

- 2.1 `docker-run-tuple.py`: record volumes, env names, ports in `Record` via `check_value`
- 2.2 Add `check_declared(app_sites)` (skip failed-tokenization sites); register in `run_checks`; add `HINTS["MISSING_DECLARED"]` and the docstring token
- 2.3 Re-run: K24 rows GREEN

## Phase 3 - spec state change

- 3.1 `TUPLES["prod"]`: `volumes = _VOLS | {token mount}`, `env` gains `SOLEUR_EGRESS_REAPER: {"1"}`; canary unchanged
- 3.2 Confirm real-tree rows (C1-C3) and 1.2 are RED with `MISSING_DECLARED` naming the prod mount and REAPER

## Phase 4 - the fix

- 4.1 `ci-deploy.sh` prod `docker run` only: add `-e SOLEUR_EGRESS_REAPER=1 \` and `-v /var/lib/soleur/egress-tokens:/var/lib/soleur/egress-tokens \` with a short comment (literal strings, no variables)
- 4.2 Re-run both suites GREEN; canary run byte-unchanged

## Phase 5 - remaining rows

- 5.1 K25a-c (prod/first-boot drop mount, drop REAPER), K26a (canary gains REAPER)
- 5.2 P12 (reordered + `--env` spelling)
- 5.3 H1 stub `declared` over K24a-d and K25a-c
- 5.4 Bump `MIN_ROWS` to the measured literal; confirm `EXPECTED_POSTURE` (`e959fc801d99`) unchanged in `docker-run-tuple.test.sh` and `test/docker-run-tuple-posture.test.ts`

## Phase 6 - docs

- 6.1 Amend ADR-278 "Canary isolation" bullet (one sentence; reword "second consumer")

## Phase 7 - verify and ship

- 7.1 Run: `docker-run-tuple.test.sh`, `ci-deploy.test.sh`, `sandbox-masked-proc-docker.test.sh` (static arms), `test/docker-run-tuple-posture.test.ts`, `scripts/guard-vacuity-floor.test.sh`, `lib/mutation-scorer-consumers.test.sh`, `plugins/soleur/test/c4-count-parity.test.sh`
- 7.2 Revert-only-the-prod-lines check: checker RED with `MISSING_DECLARED`
- 7.3 `git diff --name-only origin/main` within the allowed set (no cloud-init, server.tf, sandbox config, audit rollup)
- 7.4 Open PR (`Closes #10457`, "replaces filing an issue", Delivery); STOP before merge for the user's explicit go-ahead
- 7.4a Threshold is single-user incident (CTO R5): add a test proving the sandbox config's denyRead covers the egress token dir for every session (existing sandbox-config tests; read `agent-runner-sandbox-config.ts` ~L445-500 first), and run `user-impact-reviewer` at review
- 7.5 Post-deploy: absence assertion (`scripts/betterstack-assert-absence.sh`, positive control) and Sentry zero `web-egress-forwarder-spawn` events
- 7.6 Post-deploy: from a sandboxed Bash session in the canary workspace, confirm list and read of `/var/lib/soleur/egress-tokens` are denied (CTO R5 flip condition); report the result in the PR
