# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-07-09-fix-inngest-web-host-pg-pool-cap-plan.md
- Status: complete

### Errors
None. (Subagent noted a concurrent pipeline co-editing the plan file; verified on-disk state is consistent — revert language decoupled, only one PR #6265 exists for this branch/issue, no divergence.)

### Decisions
- Root-cause model: `--postgres-max-open-conns` is per-pool (not total); worst-case total = P × open. Fix bounds total via conservative fixed flags `open=5 idle=2 idle-time=1min`, safe for any P ≤ 4 (4×5=20 < pool_size 30 − headroom). Ships without gating on a live prod measurement (measurement is confirmatory). UNIT CORRECTION: `--postgres-conn-max-idle-time` is an IntFlag in MINUTES (verified vs inngest v1.19.4), NOT seconds — plan's "SECS=30" would have set 30 MINUTES (worse than default); corrected to 1.
- `default_pool_size` 30→15 revert (#5562) DECOUPLED and re-scoped out — its premise ("cap holds total under 15") is falsified by the per-pool model. Keep 30; recorded as a User-Challenge in decision-challenges.md + follow-up issue. Removes the PATCH-workflow prod-write surface entirely.
- op=execute pool pre-check runs BEFORE the 2.0 registry probe; gates on readiness-baseline + burst-headroom (not the 80% alert line); fails closed on EMAXCONNSESSION / 401 / non-JSON / empty / curl-fail.
- ADR-104 authored (status: adopting) recording the per-pool footprint model + idle-drain lever + keep-30 posture.
- Sentinel-first ordering load-bearing: `--postgres-max-open-conns` must stay FIRST in BACKEND_FLAGS (inngest.test.sh:242 anchor).

### Components Invoked
- soleur:plan, soleur:deepen-plan (via isolated general-purpose subagent)
- framework-docs-researcher, spec-flow-analyzer, scoped strong-model advisor (fable), repo-research, learnings-researcher (folded into deepen)
