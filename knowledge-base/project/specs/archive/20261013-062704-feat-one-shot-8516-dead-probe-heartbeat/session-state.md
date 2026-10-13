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
  fan-outs, domain sweep, advisor consult (plan Step 4.5), the plan-review panel, and the
  review 8-seat panel were executed inline by the pipeline runner rather than spawned subagents.
  Recorded as `Reviewed-Coverage: inline-fallback 0/8 agents` on the branch trailer + evidence
  issue #9705.
- Mutation spot-check revert used `git checkout <file>` against an UNCOMMITTED implementation —
  restored HEAD and wiped the edits; re-applied. Learning filed:
  `knowledge-base/project/learnings/workflow-issues/git-checkout-revert-wipes-uncommitted-work-20261007.md`.
- emit-review-trailer.sh first run omitted --agents-*/--mode → `Reviewed-Coverage: unknown`;
  superseded by soft-reset + re-emit + `--force-with-lease` (trailer commit had been pushed).
- gh issue create filing gate: `--milestone` is mandatory and `Mandated-By:` accepts only
  (hr|wg)- prefixed rule ids — review-evidence issue #9705 exited via `--label meta/machinery`.
- bun does not resolve `apps/web-platform/test/*` paths from repo root — the app package's tests
  run under vitest (`./node_modules/.bin/vitest run test/...` inside apps/web-platform).

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
