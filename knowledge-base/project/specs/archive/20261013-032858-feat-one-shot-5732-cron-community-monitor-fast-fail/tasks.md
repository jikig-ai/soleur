---
issue: 5732
branch: feat-one-shot-5732-cron-community-monitor-fast-fail
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-30-fix-cron-community-monitor-fast-fail-plan.md
---

# Tasks — fix cron-community-monitor daily `error` fast-fail (#5732)

> **CLOSED 2026-06-30 — Phase 0 VERDICT: H-C (no code fix).** The fast-fail was
> Anthropic credit exhaustion, resolved by the operator's 2026-06-29 top-up. Live
> post-top-up fire's clone succeeded + produced real digests `#5737`/`#5740` →
> H-B (codeload egress) and H-A (disk, GC healthy) both REFUTED. Monitor already
> `active`/unmuted (Phase 1 N/A). Phases 2/3/4 not shipped (no executing failure
> path to fix). See plan "Phase 0 Finding". Residual `missed` check-in = #5728's
> delivery class (closed/fixed `b1c560dad`).

## Phase 0 — Evidence gate (DONE — verdict recorded)

Decision tree: 0.2 `duration_ms` forks credit-ran (H-C) vs pre-eval; 0.3/0.4 clone-stderr + 0.7 GC health fork H-B (codeload egress) vs H-A (disk).

- [x] 0.1 Fired `cron/community-monitor.manual-trigger` (allowlisted via EXPECTED_CRON_FUNCTIONS) at 06:59:37Z; HTTP 202 `manual-api`. Clone succeeded, `claude-eval spawned`.
- [x] 0.2 Pulled `routine_runs` 06-22→06-30 (Doppler `prd` `DATABASE_URL_POOLER`, transient node+pg): 8 `completed` rows, `duration_ms` 241–387 ms, `error_summary = null`. Post-top-up fire produced no ~300 ms row → eval ran. **Primary fork = H-C.**
- [x] 0.3 Queried Sentry by `op:` TAG: `op:setup-ephemeral-workspace` ABSENT (HTTP 200 empty) → refutes H-B (no clone-stderr exception). No `No space left on device` event.
- [x] 0.4 Better Stack: `claude-eval spawned` for the fresh fire; no `git clone failed`, no `credit balance`. (Older window aged out — ~1 h hot retention.)
- [x] 0.5 No `CRON_WORKSPACE_ROOT` low-disk WARN; recovered clone succeeded.
- [x] 0.7 `cron-workspace-gc` HEALTHY 06-13→06-30 (clean 6 h cadence, 56 `completed` rows) → **refutes H-A**.
- [x] 0.6 **Verdict recorded: H-C** (credit, resolved 06-29). The setup catch (`:356`) does NOT execute on the recovered fire. **Gate satisfied.**

## Phase 1 — Sentry monitor un-mute/re-enable — N/A

- [x] 1.1 `GET …/monitors/scheduled-community-monitor/` → `status=active, isMuted=false`. No action needed.
- [x] 1.2 N/A — monitor not disabled/muted.

## Phase 2 — Conditional fix (branch on Phase 0) — N/A (H-C)

- [x] 2.B N/A — H-B refuted (live clone succeeded; codeload allowlist gap latent, not the cause).
- [x] 2.A N/A — H-A refuted (GC healthy; no ENOSPC).
- [x] 2.C **H-C: no code fix.** Recovery confirmed by digests `#5737`/`#5740`; #5674 top-up resolved it.

## Phase 3 — Observability hardening — NOT SHIPPED (gated out)

- [x] 3.1 Not shipped — Phase 0 shows the setup catch (`:356`) does NOT execute on the recovered fire; shipping `errorSummary` threading would harden a dormant path (the headline wrong-layer risk). Left for a future change driven by a live failure on that path.

## Phase 4 — Regression test — NOT SHIPPED

- [x] 4.x Not shipped — the regression test targets the fast-fail path, which no longer executes post-top-up. No reproducible failure to gate.

## Close-out

- [x] 5.1 Soak re-point SKIPPED — the existing `community-monitor-checkin-soak-5728.sh` measures DELIVERY (zero `missed`/`timeout`, explicitly ignores `error`); it does not express #5732's `error`/digest-generation concern and is #5728's active soak. Recovery is verified by the digest issues; the Sentry cron monitor auto-pages on any `error` regression. No new probe (plan simplicity caveat).
- [x] 5.2 Knowledge-base-only PR (this investigation record) `Closes #5732`; recovery already verified pre-merge (digests producing).
