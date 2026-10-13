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

## Work Phase (2026-07-21)

- Status: Phases 0–7 complete. Suites green. AC1/AC12 deferred (see below).

### THE HEADLINE — the cutover context below is SUPERSEDED

The Phase 2 ground-truth dispatch (run `29801673645`) returned
`FAIL (mount_not_mapper): mount_source=/dev/sdb`. **`/mnt/data` is the raw plaintext volume, not the
LUKS mapper.** The 2026-07-20 cutover landed, served ~27 minutes, aborted at `app_canary` on a CF
521 — which is *before* `disarm_dead_man` — and its dead-man timer then remounted the retained
plaintext at 22:42:13 UTC. Encryption at rest is not in effect; ~27 min of sole-copy writes are
stranded on the LUKS volume; nothing paged for ~6 hours. Filed **#6812** (P0).

The "Cutover context" section below was TRUE when written at 22:20 UTC and became false at 22:42.
Do not read it as current state. Evidence chain: cutover run `29782780158` (abort at 22:14:50.89),
Better Stack journald `OK: /mnt/data is LUKS-backed` at 22:18:19 then
`workspaces-luks-deadman.service: Failed with result 'exit-code'` at 22:42:13, verify run
`29801673645` at 04:36 today.

### Operator decisions (recorded on #6812)

1. **Accept the 27-minute loss and re-cut.** Live plaintext is authoritative; the stranded writes
   are deliberately discarded. Irreversible once the re-cut luksFormats that device.
2. **Finish Phases 3–7 and merge without AC1.** The re-cut must run with these fixed probes — a
   re-cut on the old code would hit the same 521 race and re-arm the same dead-man.

Sequence: merge this PR → dispatch `workspaces-luks-cutover.yml` (`dry_run=false`, env-gated) →
dispatch verify with `-f seed_workspace_count=<C1 total>` to satisfy the deferred AC1.

### Errors

None affecting the deliverable. Two self-caught defects worth naming:

- **My own test suite was fail-open.** Sourcing the harness into `luks-monitor.test.sh` silently
  overrode its `ok()`/`no()` with the harness's, which report into different counters than the
  summary and exit gate read — a failing behavioural case would have printed FAIL and exited 0.
  Caught by noticing the pass count did not move; fixed and mutation-verified (breaking a case now
  exits 1), with a canary pinning the accounting.
- **Harness sequence knobs degraded to "always the first value."** The SUT reads the curl stub
  through a command substitution (a subshell), so the index increment was discarded. Every sequenced
  fixture silently never advanced. Caught by T23a failing with 29 sleeps where it wanted 2; fixed by
  file-backing the counters.

### Decisions

Seven, in `decision-challenges.md` (3 from plan phase, 4 from work). The load-bearing ones:
readyz answers **503** not `200+ready:false`, so it retries only on unclassifiable responses;
the inventory baseline is written by the same counter that reads it, not the fsck gate's `total`;
`model.c4`/ADR-119 record plaintext-at-rest as **current** rather than "correcting" it to a claim
that is now false; and the cutover sources its **shipped** emit helper, without which the authorized
re-cut would die on `command not found` at its last gate.

### Verification

397 assertions green across 7 workspaces-luks infra suites (freeze 76, staging 152, luks-monitor 25,
verify 14, cutover-workflow 42, header 62, workspaces-luks 26). 8/8 mutations killed against the
retry, classifier and harness-index assertions. C4 23/23.

## Cutover context (SUPERSEDED — accurate only as of 2026-07-20 22:20 UTC; see Work Phase above)
The live cutover (run 29782780158, 2026-07-20 22:10-22:14 UTC) SUCCEEDED at the infrastructure level: `/mnt/data` is `crypto_LUKS` on `/dev/mapper/workspaces`, escrow ok, header readable, C1 differential clean. No rollback fired — correctly, because `CANARY_OK=1` was set by the host canary. This PR is a probe-code fix only; it must not re-run or roll back the cutover.
