# Tasks — feat(encryption-posture): Layer B live-reconcile measure-then-scope DEFER (#6902)

Derived from `knowledge-base/project/plans/2026-07-24-feat-encryption-posture-layer-b-reconcile-skeleton-plan.md`.
Scope: **near-total DEFER**. Deliverables = ADR-141 + a Layer A coverage floor + a Layer B tracking
issue. NO cron, NO reconcile script, NO Sentry monitor, NO IaC.

## Phase 0 — Preconditions (verify, do not assume)

- [ ] 0.1 Re-confirm the measurement: `grep -c '"live_verification": "available"' scripts/encryption-posture-ledger.json` == 1 (address `hcloud_volume.workspaces_luks`).
- [ ] 0.2 Re-confirm `lint-encryption-posture.py --json` is hermetic + emits the committed ledger (scripts/lint-encryption-posture.py:54, 1006-1012) — i.e. no runner-reachable live signal.
- [ ] 0.3 `git fetch origin main` and re-derive next-free ADR ordinal (`ls knowledge-base/engineering/architecture/decisions | grep -oE 'ADR-[0-9]+' | sort -t- -k2 -n | tail -1`); provisional ADR-141 may collide.
- [ ] 0.4 Identify the Layer A test runner/convention for `scripts/lint-encryption-posture.py` (`ls scripts/*.test.* ; grep -rn 'lint-encryption-posture' scripts/ tests/ 2>/dev/null`) so the new fixture test lands where the runner collects it.

## Phase 1 — ADR-141 (the durable deliverable)

- [ ] 1.1 Write ADR-141 via `/soleur:architecture`: DEFER verdict; host-probe-vs-runner-reconcile distinction; `--json`-is-design-time (static-file) analysis; overlap with luks-monitor.sh + terraform-drift; arm trigger (#6894/#6895/#6897 land a runner-reachable signal); ADR-033 substrate note (ride existing job if/when built); provider-managed rows structurally out of reach. `status: adopting`.
- [ ] 1.2 If the ordinal renumbered, sweep the plan + tasks.md + all ACs naming the ordinal.
- [ ] 1.3 C4: confirm no `.c4` edit is needed (no cron/monitor added → `github -> sentry` counts unchanged); cite the enumeration in the plan (already done).

## Phase 2 — Layer A coverage floor (RED then GREEN)

- [ ] 2.1 Write failing tests first (`cq-write-failing-tests-before`) with SYNTHESIZED fixtures (`cq-test-fixtures-synthesized-only`): (a) all-`unavailable` ledger → `--repo-sweep` FAILs with the new floor line + non-zero exit; (b) ≥1-`available` ledger → PASSES.
- [ ] 2.2 Extend `scripts/lint-encryption-posture.py` `check_positive_work_floor` (or a sibling check) with the ≥1-`live_verification:available` floor + a `FAIL: ... at least one live_verification:available store required ...` line. Keep it hermetic (reads only the loaded ledger; no network/gh/host).
- [ ] 2.3 Green the new tests AND confirm `--repo-sweep` still PASSES against the real committed ledger (1 available row).

## Phase 3 — Verification

- [ ] 3.1 `python3 scripts/lint-encryption-posture.py --repo-sweep` PASSES on the real ledger.
- [ ] 3.2 Full Layer A test battery green (the new fixtures + the existing MB-* battery unaffected).
- [ ] 3.3 Assert the diff introduces NO `.tf`, NO workflow, NO cron, NO Inngest fn, NO `sentry_cron_monitor` (near-total DEFER invariant).

## Phase 4 — Deferral tracking

- [ ] 4.1 File the Layer B tracking issue (milestone from roadmap.md): what (armed per-row live reconcile + find-or-update-by-title + optional ride on scheduled-terraform-drift.yml + dedicated Sentry monitor), why deferred (1/14; no runner-reachable live signal; overlap), re-eval criteria (an emitter lands a runner-reachable signal), blockers #6894/#6895/#6897.
- [ ] 4.2 Do NOT file new emitter issues (#6894/#6895/#6897 already OPEN) — reference as blockers.
- [ ] 4.3 Confirm `decision-challenges.md` is present for `ship` to render + file as `action-required`.
