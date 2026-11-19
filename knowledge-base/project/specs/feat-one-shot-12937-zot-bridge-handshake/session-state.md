# Session State

## Plan Phase

- Plan file: /data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-12937-zot-bridge-handshake/knowledge-base/project/plans/2026-11-19-fix-zot-bridge-tunnel-hosts-after-zone-move-plan.md
- Status: complete

### Errors

- Plan-write hook flagged Phase 0 dashboard-only wording; resolved with iac-routing-ack marker and lint-infra-ignore block.
- gh run view --log-failed truncated; raw log fetched via REST. dig absent; DNS checks via DoH.
- Architecture reviewer first returned no findings text; re-asked.
- Plan review and deepen found and fixed: registry token never reaching Doppler, discoverability probe failing preflight, concurrent release re-runs colliding on the draft tag, unrepointed census and ci_ssh_token_replace consumers.

### Decisions

- Root cause: soleur.ai zone moved to the Soleur Cloudflare account about 16:24Z 2026-11-18; registry./ssh. are scanner A records (CF Error 1000), deploy. is NXDOMAIN; tunnel and Access apps remain in the old account and cfargotunnel CNAMEs route only within one account. zot and the tunnel are healthy.
- The 16:33Z supabase-ref-resolver failure is the same incident; no issue filed.
- Fix: CTO Option A, re-home only the tunnel slice into the Soleur account as new _soleur Terraform addresses, then replace web-2 to re-bake the connector.
- Visibility: classifier gains host-nxdomain, edge-error-NNNN, tunnel-down; SOLEUR_ZOT_BRIDGE marker; tunnel-zone authority drift step.
- PR uses Ref 12937 and Ref 12931; issue closed after prod serves the new SHA.

### Components Invoked

- soleur:plan, soleur:plan-review, soleur:deepen-plan; learnings-researcher, repo-research-analyst, functional-discovery, soleur:engineering:cto, soleur:operations:coo, dhh/kieran/code-simplicity reviewers, architecture-strategist, security-sentinel, observability-coverage-reviewer, terraform-architect, spec-flow-analyzer.

## Operator Constraints

- constraint: Diagnose first by self-pulling telemetry, registry host Better Stack rows for zot and cloudflared.
- constraint: Once the bridge is back, re-run the failed push runs for 5d4851f7af and 52bf12cc5b, then run postmerge for the 5d4851f7af merge.
- constraint: Follow-ons 12863 and 12920 are not in this PR.

## Technical Rulings

- cto_spawns=2
