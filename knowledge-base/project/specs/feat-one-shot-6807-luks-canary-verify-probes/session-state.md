# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-07-21-fix-luks-canary-retry-and-verify-readyz-plan.md
- Status: complete

### Errors
None. Two mid-planning premise corrections were made and recorded rather than silently absorbed:
- The brief dated the prior canary-endpoint fix to 2026-06; it actually landed 2026-07-19 (`ca85c30bc` / PR #6701) — one day before the cutover, which is *why* the sweep was thin.
- The brief stated the verify breakage also broke the soak drift check. It does not: `workspaces-luks-soak-6604.sh:46-48` reads Sentry, the heartbeat, and ADR status directly and never invokes the verify workflow.

Both corrections were verified against the code and posted back to #6807 as a correction comment.

### Decisions
- **`readyz ready=true` proves a floor, not an inventory.** `workspaces_populated` is `countWorkspaceDirsAt(root) > 0` (`readiness.ts:81`), so a cutover preserving 1 of 8 sole-copy workspaces returns `ready=true`. The first draft repeated — one hop later — the exact overclaim the issue was filed about. A separate host-side **inventory count** now carries that claim, with exclusions mirrored from `session-metrics.ts` and a parity fixture.
- **The count assertion runs host-side in `luks-monitor.sh`, not runner-side.** One placement closes four findings: it binds the value (a prefix grep passes on `count=1` as on `=8`), fails closed when the baseline is absent (`WORKSPACES_COUNT` does not exist on the host today), keeps SSH stderr off the runner, and makes `emit_drift` reachable.
- **Reverted an earlier decision to introduce a distinct Sentry `op`.** `workspaces-luks-drift` is the sole paging op of nine under this feature (`issue-alerts.tf:1704-1740`, `filter_match="all"`); a new op would page nobody and be invisible to the wipe gate. De-conflation moved to exit codes and `::error::` text instead.
- **Kept the readyz flag default-OFF.** `luks-monitor.service:5`'s `RequiresMountsFor=/mnt/data` makes the daily unit *inert* in the reboot hazard, so default-ON buys no coverage there. Recorded as a Sharp Edge so the wrong answer isn't re-derived.
- **Probe-first restructure.** The ground-truth question (is the repointed volume actually populated?) is answered in Phase 2 via a pre-merge `--ref` dispatch, with an explicit STOP condition distinguishing a capacity fault from a data-recovery incident.

Two blockers surfaced that would have failed at implementation: `luks-monitor.sh` has no sourced-detection guard (making the planned test seam impossible), and `sleep` is unstubbed in the harness (a wall-clock retry loop would spin hot in an at-budget CI job).

### Components Invoked
`soleur:plan`, `soleur:deepen-plan` · plan-review panel: kieran-rails-reviewer, architecture-strategist, spec-flow-analyzer, code-simplicity-reviewer, plus a strong-model advisor consult · deepen passes: test-design-reviewer, observability-coverage-reviewer, user-impact-reviewer, Explore (precedent-diff / verify-the-negative / post-edit self-audit), Explore (learnings research) · mechanical gates 4.4–4.9

## Cutover context (do not re-litigate)
The live cutover (run 29782780158, 2026-07-20 22:10-22:14 UTC) SUCCEEDED at the infrastructure level: `/mnt/data` is `crypto_LUKS` on `/dev/mapper/workspaces`, escrow ok, header readable, C1 differential clean. No rollback fired — correctly, because `CANARY_OK=1` was set by the host canary. This PR is a probe-code fix only; it must not re-run or roll back the cutover.
