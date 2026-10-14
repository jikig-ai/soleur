# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-07-09-feat-zot-mirror-fallback-rate-sentry-alarm-plan.md
- Status: complete

### Errors
None. All premise-validation checks passed and both deepen-plan research agents completed successfully.

### Decisions
- Premises verified (hr-verify-repo-capability-claim-before-assert): `apps/web-platform/infra/sentry/issue-alerts.tf` exists (20 rules); the `feature:supply-chain op:image-pull registry:"ghcr-fallback"` marker is emitted from `ci-deploy.sh:562-564` (`registry_pull_event`, level=warning).
- Scope reconciled beyond the issue's literal ask: the runbook `zot-registry-revert.md` specifies an aggregate alarm over THREE runtime signals (`ghcr-fallback` OR `inngest_ghcr_fallback` OR `zot-gate-degraded`), not just the one the issue names — plan covers all three (+ a 4th app-boot breadcrumb).
- Primary mechanism = `sentry_metric_alert` (aggregate), not `sentry_issue_alert`: issue-alert `event_frequency` is per-issue-group + fingerprint-fragmented, so a distributed 2+2+1 outage pages zero groups at 3/1h. Issue-alert kept as documented fallback. Fixed a silent-no-op query bug (`event.type:error` excludes these level:warning/default store events).
- Corrected stale repo knowledge: `event_frequency` IS in the beta2 `conditions_v2` schema (verified against cached provider binary) — the issue-alerts.tf:838 + ADR-062:120 "no verified support" comments are false; Phase-0 probe is network-free.
- Two extra gaps folded in: Branch B must also edit `destroy-guard-filter-sentry.jq` (P1 — silent destroy-guard bypass for the new array-of-blocks type); main app-image fresh-boot pull emits no fallback breadcrumb (P2) → Phase 1b adds `stage:app_ghcr_fallback` emit. Second deliverable (inngest-bootstrap mirror Slack signal) mirrors the reusable-release.yml PR-#6276 pattern.

### Components Invoked
- Skill soleur:plan
- Skill soleur:deepen-plan
- Agent Explore (provider-schema verification)
- Agent soleur:engineering:review:architecture-strategist (alarm-design review)

## Work Phase 0 — Provider-schema + dataset probe (DONE)

- **Branch decision: A (sentry_issue_alert + event_frequency)** — ruled by the `soleur:engineering:cto`
  agent (see decision-challenges.md). Branch B (metric alert) rejected: no resolvable numeric notify
  target in the Sentry TF root + CI-only auth token → unverifiable/pages-nobody risk.
- **Provider schema probed network-free** via the sibling worktree's cached
  `jianyuan/sentry@0.15.0-beta2` binary + a scratch-dir filesystem_mirror. Confirmed: `event_frequency`
  IS in `sentry_issue_alert.conditions_v2` (repo comments at issue-alerts.tf:838-839 / ADR-062:120-121
  are stale). `sentry_metric_alert.trigger.action` requires a concrete numeric target (no symbolic
  fallthrough) — the disqualifier for Branch B.
- **Emit tags frozen:** `ci-deploy.sh:562` `registry_pull_event` → `{feature:"supply-chain", op:"image-pull",
  registry:"ghcr-fallback", image}` (level warning); `ci-deploy.sh:590` `zot_gate_degraded_event` →
  `{feature:"supply-chain", op:"image-pull", registry:"zot-gate-degraded", zot_gate_reason}` (warning);
  `cloud-init.yml:650` `soleur-boot-emit inngest_ghcr_fallback warning` → `{stage:"inngest_ghcr_fallback",...}`
  (NO feature/op). Phase-1b adds `cloud-init.yml:~496` `soleur-boot-emit app_ghcr_fallback warning`.
- **frequency = 23** (free; taken: 5,10-22,30,60-62).
- **Filter design:** `filter_match="any"` over the 4 tag-values (the inngest/app boot events carry no
  feature/op, so an "all" on feature+op would exclude them).
- **Guard parity (Branch A):** scope-guard allowlist already keys on TYPE `sentry_issue_alert`; counter-test
  has no exact-count assertion; jq clause drops CREATEs. → ONLY the `-target` line needed.
