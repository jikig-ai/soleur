# Tasks: fix(ci): gate deploy job on Docker build success

## Phase 1: Add docker_pushed output to reusable-release.yml

- [ ] 1.1 Add `id: docker_build` to the "Build and push Docker image" step
- [ ] 1.2 Add `id: docker_login` to the "Docker login" step
- [ ] 1.3 Add a new step "Set docker_pushed output" after Docker build that sets `pushed=true` only when `steps.docker_build.outcome == 'success'`
- [ ] 1.4 Add `docker_pushed` to the job-level `outputs:` block with fallback `|| 'false'`
- [ ] 1.5 Add `docker_pushed` to the workflow-level `outputs:` block with description

## Phase 2: Fix Docker build step condition for retry

- [ ] 2.1 Change Docker login step condition from `steps.create_release.outputs.released == 'true'` to `steps.version.outputs.next != ''`
- [ ] 2.2 Change Docker build step condition from `steps.create_release.outputs.released == 'true'` to `steps.version.outputs.next != ''`

## Phase 3: Gate deploy on docker_pushed in caller workflows

- [ ] 3.1 In `web-platform-release.yml`, replace `needs.release.outputs.version != ''` with `needs.release.outputs.docker_pushed == 'true'` in deploy job condition
- [ ] 3.2 In `telegram-bridge-release.yml`, replace `needs.release.outputs.version != ''` with `needs.release.outputs.docker_pushed == 'true'` and add `always()` in deploy job condition

## Phase 4: Verification

- [ ] 4.1 Review all three workflow files for YAML syntax correctness
- [ ] 4.2 Verify the `docker_pushed` output flow: step output -> job output -> workflow output -> caller `needs.release.outputs.docker_pushed`
- [ ] 4.3 Trace the retry path: idempotency skip -> `released` is false -> Docker build condition uses `version.outputs.next != ''` -> Docker build runs -> `docker_pushed` set -> deploy fires
- [ ] 4.4 Trace the failure path: Docker build fails -> `docker_pushed` is `'false'` (default) -> deploy condition is false -> deploy skipped
