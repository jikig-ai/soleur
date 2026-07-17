# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-07-17-fix-6604-workspaces-luks-cutover-plan.md
- Status: complete

## Work Phase — complete (5 commits)
- Gate (AC20): workspaces-luks-cutover-gate.sh + 16 mutation-proven fixtures, registered in test-all.sh.
- Phase 1 (AC14/AC6b/AC16): /mnt/data pinned by volume-ID + nofail + dedupe; baked luks-monitor DSN; AC6b re-point; git-data glob doc; size re-baseline 21,900→22,200.
- Phase 2 (AC15/AC20a/AC20b): workspaces-luks-emit.sh (DP-8 feature/op tags, DP-9 baked-DSN-first); luks-monitor.{sh,service,timer} daily probe; vector tag; sentry_issue_alert.workspaces_luks_drift; betteruptime_heartbeat.workspaces_luks + URL secret; baked structural gate (crypttab+RequiresMountsFor+chattr); workspaces-luks-verify.yml; luks-monitor.test.sh (14 assertions).
- Phase 3-4 (AC20/AC20b): apply_target=workspaces-luks-cutover job (gate-guarded first-provision, web-1-swap); workspaces-luks-cutover.yml (environment-gated, C19 sign-off); workspaces-cutover.sh (host-side EXIT trap DP-6, escrow-after-prepare R7, itemized verify C1, host canary C13). Registered in stock-preflight-coverage + heartbeat-manifest.
- Phase 5: workspaces-luks-soak-6604.sh (read-only verify-completion, DP-4/DP-5); runbook.
- Regression green: workspaces-luks 26/26, target-parity 56, stock-preflight 9, heartbeat-parity 19, observability 93, cloud-init size 26, tsc clean.
- Deviation noted: the drift sentry alert lives in issue-alerts.tf (canonical declarative home, matching byok/kb siblings), NOT configure-sentry-alerts.sh (auth-scoped). Post-merge AC21-AC30 are dispatch-run gates (specified, not executed in-PR).

### Errors
None. (One Explore agent hit a transient server overload mid-run; its scope — additive-volume TF, ADR status, exclusion list — was re-gathered via direct file reads, no coverage lost.)

### Decisions
- Re-scoped parent #6588 plan to the #6604 infra-cutover deliverable, re-verified against origin/main. #6593 already shipped the additive volume, the A1–A11 drift guard, ADR-119 (status: adopting), the C4 model element+edge, and all five workspaces_luks OPERATOR_APPLIED_EXCLUSIONS — those are regression ACs, not #6604 work. The issue's "ADR-118" is a mis-citation; the LUKS ADR is ADR-119.
- The old plaintext volume is protected by the cutover gate (old_volume_touched==0), NOT prevent_destroy (#6593 deliberately omitted it — fails the whole for_each plan). AC20 rewritten accordingly.
- Two-artifact design (terraform-architect validated as precedent-exact): apply_target=workspaces-luks-cutover job in apply-web-platform-infra.yml (create+attach, gate-lib-guarded, web-1-swap concurrency) + a separate workspaces-luks-cutover.yml freeze orchestration mirroring git-data-cutover.yml. C1–C19 folded into phases/ACs.
- Deepen pass (4 lenses) surfaced 4 P1s fixed in-body (DP-1…DP-11): cutover gate would abort its own first apply (first-provision, not host-replace); Phase-5 "retire old block" fatal for for_each volume (→ key-set narrowing); soak "fold remediation before exit 0" impossible under env -i sweeper (→ read-only verify-completion soak + separate environment-gated destructive dispatch); three C19-class no-exit states (→ host-side EXIT trap + persisted freeze state + dead-man rollback).
- The legal PR (AC1–AC10 + present-tense LUKS flip) is explicitly PR 3, out of scope — opened only after canary passes; #6604 carries zero doc changes.

### Components Invoked
- Skill: soleur:plan → Skill: soleur:deepen-plan
- 4 Explore agents; 4 deepen lenses (terraform-architect, spec-flow-analyzer, observability-coverage-reviewer, code-simplicity-reviewer)
- Mechanical deepen gates 4.5–4.9 + verify-the-negative sweep
- git commit 87fd19202 (plan + tasks.md)
