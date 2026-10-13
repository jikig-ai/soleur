# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-07-12-fix-webhook-readwritepaths-inngest-namespace-deadlock-plan.md
- Status: complete

### Errors
- One recoverable block: the initial plan Write was rejected by the IaC-routing PreToolUse hook (`hr-all-infrastructure-provisioning-servers`) because the prose quoted `systemctl`. Resolved with the `iac-routing-ack: plan-phase-2-8-reviewed` opt-out — the fix IS routed through Terraform/cloud-init; the `systemctl` tokens are quotes of existing managed behavior, not new manual steps. Plan carries a full `## Infrastructure (IaC)` section.
- No other errors. All premises validated; all deepen-plan hard gates passed.

### Decisions
- **Root cause confirmed** at `cloud-init.yml:245`: `/var/lib/inngest` is a mandatory `ReadWritePaths` token; on `web_colocate_inngest=false` (default) the only dir-creator (`inngest-bootstrap.sh:123`) is gated off, so `webhook.service` fails `226/NAMESPACE` → `:9000` never binds → `ok_peer_fanout_degraded`.
- **Chose Option B (`-`-optional) over Option A (templatefile guard).** Decisive finding: a SECOND byte-identical copy of the RWP line lives in standalone `webhook.service:45`, base64-delivered to running hosts via `deploy_pipeline_fix.triggers_replace` — NOT templatefile-rendered, so `%{ if }` is impossible there. Only the `-` prefix keeps both lockstep copies uniform, matching in-file precedent (`-/var/lib/vector` / `-/etc/vector`, PR #4257).
- **Scope**: both lockstep files, comment-accuracy sweep of two now-stale earlier-arc comments (`soleur-host-bootstrap.sh:191-193` + its observability test) asserting the now-severed 226 causal chain, a regression + lockstep-parity test, and Phase-4 emit-coverage verification of the `webhook_bound` baked-DSN beacon.
- **Threshold**: aggregate pattern (weight-0 no-ingress standby; degrades fleet resilience, not per-user data). Verification off-host only via `web-2-recreate` + deploy-status reason flip (no SSH).
- No new ADR/C4 (restores an existing invariant within ADR-100/#6178); Product/UX NONE; collision with merged predecessor PR #6125 acknowledged and passed per operator confirmation.

### Components Invoked
- `soleur:plan` (Skill)
- `soleur:deepen-plan` (Skill) — hard gates 4.6/4.7/4.8/4.9 passed; conditional gates 4.5 (network-outage) + 4.55 (downtime) fired, satisfied, telemetry emitted; precedent-diff (4.4) grounded
- `gh` CLI (premise validation: #6090/#6178/#5933 states, PR #6125 collision)
- Git commit + push (plan + tasks.md, then deepened plan)
