# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-07-23-fix-readyz-loopback-peer-gate-container-403-plan.md
- Status: complete

### Errors
None. (deepen-plan's parallel review-agent fan-out was unavailable to the subagent — Task tool not exposed — so the deepening/precedent-diff/verify-the-negative/implementation-realism checks ran directly against the code; all five deepen-plan gates passed.)

### Decisions
- Approach A (docker exec probe) chosen over widening the peer gate. Under docker userland-proxy=true, off-host traffic through the published port also presents as bridge gateway 172.17.0.1, so widening isLoopbackPeer would collapse the off-host boundary to the attacker-controlled Host header. Approach A changes zero lines of the trust boundary (readiness.ts/loopback.ts), preserving the off-host 403 by construction.
- The three probe sites collapse to one shared helper: wl_probe_readyz (workspaces-luks-emit.sh:135), fixed centrally via a WL_READYZ_CONTAINER default.
- Preconditions verified: curl is in the container image (Dockerfile:89); docker exec soleur-web-platform is established precedent (ci-deploy.sh:413).
- Tests: vitest unit case asserting bridge-gateway peer 172.17.0.1 -> 403; $CALLS transport assertion in freeze/monitor shell suites asserting docker exec soleur-web-platform curl.
- No new ADR / no C4 impact; threshold = single-user incident (requires_cpo_signoff: true); no Closes #6812 — incident stays open until cutover re-run and certified.

### Components Invoked
- Bash, Read, Skill: soleur:plan, Skill: soleur:deepen-plan, Write/Edit
