# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-10-07-chore-inngest-probe-dead-probe-heartbeat-plan.md
- Status: complete
- Plan artifact: complete (selector=branch; written fresh this run)

### Errors
- iac-plan-write-guard denied the first two Write calls ("manual-install / operator-driven
  framing"): the drafts described repo conventions using the literal token `out-of-band` and a
  `... the Better Stack UI` phrasing that matched the vendor-dashboard regex family. Fixed by
  rephrasing — no manual step was ever prescribed; the plan routes everything through Terraform +
  the per-merge push-apply. Content verified against the guard's own regex set before the final
  write.
- Harness limitation (disclosed): no Task/Skill tool exists in this subagent harness — research
  fan-outs, domain sweep, advisor consult (plan Step 4.5), and the plan-review panel were
  executed inline by the pipeline runner rather than spawned subagents. Findings are recorded in
  the plan's Enhancement Summary; the review phase runs the same way (sequential-fallback).

### Decisions
- Mirror DP-10 verbatim on the TF side: `betteruptime_heartbeat.inngest_server_probe`
  (period=3600, grace=1800 — hourly emission cadence) + `doppler_secret.inngest_server_probe_heartbeat_url`
  (soleur/prd, `INNGEST_SERVER_PROBE_HEARTBEAT_URL`), born `paused = true` +
  `ignore_changes = [paused]`.
- Deliver via the per-merge `-target=` allow-list (#8754 git_data_prd precedent), NOT
  `OPERATOR_APPLIED_EXCLUSIONS` — the push-apply is the delivery path and postmerge verifies it.
- Manifest row: `arming = "external-probe"`, `feeder.kind = "none"` +
  `url_secret = "INNGEST_SERVER_PROBE_HEARTBEAT_URL"` + `tracking_issue` + `arming_pending`.
- Feeder + arming deferred to a tracking issue (filed in the work phase): recommended shape is a
  warehouse-verifying external pusher (covers emitter + Vector + sink), NOT a host-side push
  (needs OCI re-bake + host replace, #6780) nor a sweeper-enrolled script bound to a closing
  tracker.
- model.c4 `inngestRedis` description freshened — it already names #8516 as the open gap.

### Components Invoked
- soleur:one-shot (pipeline), soleur:plan (inline), soleur:deepen-plan (inline gate pass),
  plan-review standing checks (inline), lint-guard-contract.py, worktree-manager.sh,
  pipeline-tally.sh
