# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-07-14-feat-web-host-vector-log-shipping-boot-observability-plan.md
- Status: complete

### Errors
- spec-flow-analyzer initial mis-path (soleur:engineering:product:… not found); re-launched at soleur:product:spec-flow-analyzer. No blocking errors; all deepen halts (4.6 User-Brand, 4.7 Observability, 4.8 PAT, 4.9 UI-wireframe) passed.

### Decisions
- Scope = build, not fix: fresh web hosts ship no logs post-ADR-100 cutover; decouple the Vector log-shipper to all web hosts. Architecture = amend ADR-082 + Consequences back-ref in ADR-100; C4 = hetzner->betterstack edge (no views.c4 change).
- Zero-downtime apply: immutable-redeploy channel (ignore_changes=[user_data,image]); web-2 via guarded no-SSH web-2-recreate -replace (warm standby); web-1 never force-replaced. Brand-survival = single-user incident (requires_cpo_signoff).
- No new secret: BETTERSTACK_LOGS_TOKEN already in soleur/prd.
- Review corrections applied: (P0) web vector.service missing DOPPLER_TOKEN -> EnvironmentFile=/etc/default/webhook-deploy; (P1) Dockerfile COPY-lockstep; (P1) retired per-host uptime page (#5933) -> new Sentry stage-tagged issue-alert; (P1) build->deploy-web-1->recreate ordering explicit; (P1) web-1 blind-origin gap -> ADR-068 blue-green promote + follow-through issue.
- host_name = TF-injected per-host (not runtime $(hostname)); terminal-block trap armed at ~L731 with mutable stage= var + explicit emit.

### Components Invoked
soleur:plan -> soleur:deepen-plan; Explore x4 + learnings-researcher; Phase 4.5 scoped advisor (opus); deepen review panel: architecture-strategist + observability-coverage-reviewer + spec-flow-analyzer.
