---
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Feature: Reconcile Remaining Non-Cutover Gates for ADR-068 Phase-3 GA

## Problem Statement

Epic #11181 remains open while its body checkboxes lag behind merged PRs and issue comments. The remaining work is already bounded by existing plans and operator holds; a new architecture or product design is not needed. This spec consolidates the non-cutover sequence without authorizing credential changes, infrastructure applies, or the cutover.

## Goals

- Preserve web-2's structural exclusion from app serving until the cutover gates pass.
- Keep the operator-reserved `CF_API_TOKEN` widen and the fresh staging-dispatch authorization explicit.
- Record the post-widen scope-ledger/ADR-130 follow-up only after the permissions are true.
- Keep AC4, the drained-host reboot, and AC11 soak with the cutover track.

## Non-Goals

- Do not widen tokens, read credential values, dispatch workflows, apply Terraform, reboot a host, or change LB weight.
- Do not implement new multi-host routing or re-open ADR-068's settled architecture.
- Do not change legal records as part of the widen or staging work; preserve PA-2's drafted prior notice and PA-36's pre-cutover gates.
- Do not start the seven-day soak or change ADR-068 from `adopting` to `accepted` before cutover.

## Functional Requirements

### FR1: Preserve the serving boundary

Keep web-2 absent from `default_pool_ids` and at serving weight 0 until the current `lb-weight-gate.sh` conditions and the separate on-host runtime-bind probe pass. A shape-only gate pass is not weight-flip authorization; do not conflate its prerequisites with AC11's separate seven-day GA soak.

### FR2: Preserve the operator-owned widen sequence

The operator performs the baseline `cf-token-scope --profile default-token` check, appends the ruled Zone and Account Load Balancing Edit permissions to the existing `CF_API_TOKEN`, and requires `--expect-lb-scopes` to pass. This spec does not execute the widen.

### FR3: Record only verified token scope

After the widen is verified, the consuming engineering PR updates the `cf_api_token` scope description in `apps/web-platform/infra/variables.tf` and the ADR-130 note, following archived task F1.

### FR4: Gate staging dispatch separately

Run the Part-2 throwaway-hostname continuity probe after the widen. The `apply-web-platform-infra.yml` staging dispatch requires fresh, named authorization; the existing delegation does not cover it.

### FR5: Verify runtime binding before any weight change

The cutover flow must pass the separate on-host runtime-bind probe in addition to LB shape and deep-readiness checks. The INFO-level listener-start message is filtered from the Better Stack app-container stream, so a missing log row is not evidence that the listener is absent.

## Technical Requirements

### TR1: Maintain fail-closed cutover controls

Keep the current `createProxyServer` fail-closed bind and peer-allowlist checks, `handleReadyzRequest` requirements, and `lb-weight-gate.sh` cutover/soak conditions unchanged in this scope.

### TR2: Keep legal activation gates in force

Before `GIT_DATA_STORE_ENABLED` is activated, resolve the existing PA-36 lawful-basis/controller characterization, rights/deletion, and Hetzner backup-retention requirements. No new processing activity or recipient is introduced by the pre-cutover widen and staging probe.
