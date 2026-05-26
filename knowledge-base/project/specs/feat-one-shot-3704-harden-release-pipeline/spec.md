---
lane: "single-domain"
issue: 3704
related_issues: ["#2207", "#2276", "#2529", "#3398", "#3408"]
---

# Spec — Harden Web Platform Release Pipeline (#3704)

Source-of-truth plan: [`knowledge-base/project/plans/2026-05-12-fix-harden-web-platform-release-pipeline-3704-plan.md`](../../plans/2026-05-12-fix-harden-web-platform-release-pipeline-3704-plan.md).

## Functional Requirements

- **FR1** — `ci-deploy.sh` invocations spawned by adnanh/webhook MUST be terminated by the OS after 900s wall-clock, regardless of which on-server primitive is hanging (`docker pull`, `docker exec bwrap`, `curl`, `canary-bundle-claim-check.sh`).
- **FR2** — On wall-clock-induced termination, the deploy state file MUST be updated atomically with `exit_code=124 reason=timeout` so the `Verify deploy script completion` polling step sees a terminal non-running state and exits 1 with a precise reason.
- **FR3** — flock on `/var/lock/ci-deploy.lock` MUST be released after termination so the next deploy can proceed without operator intervention.
- **FR4** — The 900s server-side ceiling MUST equal the workflow's `IN_FLIGHT_CEILING_S` (today 900s). Drift between the two surfaces is a P0 follow-up.
- **FR5** — Existing success path is untouched: healthy deploys (~120-180s) MUST exit 0 unchanged.

## Test Requirements

- **TR1** — Unit test for the new `ci-deploy-wrapper.sh` (mock `systemd-run` to `exec "$@"`); verifies env-var forwarding contract.
- **TR2** — Unit test for the new `TERM`/`INT` trap in `ci-deploy.sh`; verifies state file shows `exit_code=124 reason=timeout` after `kill -TERM`.
- **TR3** — `terraform validate apps/web-platform/infra/` passes.
- **TR4** — `bash apps/web-platform/infra/ci-deploy.test.sh` passes (existing tests + new SIGTERM scenario).

## Non-Goals

- Operator action to unstick current prod (manual SSH kill + re-trigger). Tracked separately as ops remediation.
- Refactor of webhook → ci-deploy invocation to a templated systemd `oneshot` unit. Documented in Alternatives table; not in scope.
- Cross-component (non-web-platform) deploy hardening.

## Implementation Direction

See plan, "Implementation Phases" section.
