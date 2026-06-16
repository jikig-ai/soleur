# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-06-16-fix-web-platform-restart-churn-plan.md
- Status: complete

### Errors
- Two plan-write attempts initially BLOCKED by PreToolUse hooks, both resolved without rework: (1) IaC-routing gate on `systemctl enable --now` prose — resolved via `<!-- iac-routing-ack: plan-phase-2-8-reviewed -->` opt-out (all systemctl/cloud-init/docker-run changes route through cloud-init + terraform_data remote-exec, mirroring resource_monitor_install); (2) Worktree-write guard rejected bare-root path — resolved by writing to explicit .worktrees/ path.
- All four deepen-plan hard gates (4.6 User-Brand Impact, 4.7 Observability, 4.8 PAT-shaped var, 4.9 UI-wireframe) PASSED.

### Decisions
- Root cause (with evidence): prod container runs `docker run --restart unless-stopped` with NO `--memory` cap on an 8GB cx33 host → heavy concurrent crons drive HOST OOM → kernel kills Node → auto-restart churn. The firewall DOCKER-USER flush is a downstream SYMPTOM, not a cause; the 2026-06-13 egress fix handled the orthogonal LB-rotation drop.
- Three-deliverable fix with independent ACs: (A) cgroup --memory/--memory-swap/--init cap converting host-OOM to deterministic container-OOM; (B) host systemd-timer container-restart-monitor.sh (modeled on resource-monitor.sh) classifying deploy-vs-crash-vs-OOM; (C) uncaughtException/unhandledRejection handlers + RestartCount/oom_killed exposed via no-SSH /hooks/deploy-status webhook.
- Extend, don't rebuild: extends resource-monitor.sh, cat-deploy-state.sh, vector.toml, sentry/issue-alerts.tf.
- Deepen hardened: .State.OOMKilled is false-negative under cgroup v2 for child-cgroup (bwrap) kills → monitor reads memory.events oom_kill counter + exit-137 + journald; Sentry handlers use close(2000) not flush() and avoid GlobalHandlers double-report; sentry_issue_alert HCL pinned to jianyuan/sentry@0.15.0-beta2 with unique frequency + -target= allowlist entry.
- Threshold = single-user incident (requires_cpo_signoff: true); verification no-SSH via Sentry stats API (Server-startup frequency drop to ≤1/day over 72h).

### Components Invoked
- Skills: soleur:plan, soleur:deepen-plan
- Agents: repo-research-analyst, learnings-researcher, functional-discovery, spec-flow-analyzer (plan); Explore ×2, best-practices-researcher, framework-docs-researcher (deepen)
- Gates: network-outage L3→L7 checklist, IaC-routing (2.8), Observability (2.9/4.7), User-Brand Impact (4.6), PAT-shaped-var (4.8), UI-wireframe (4.9), scheduled-job precedent (4.4)
