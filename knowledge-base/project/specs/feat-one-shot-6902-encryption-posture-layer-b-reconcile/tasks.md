# Tasks — feat(encryption-posture): Layer B live-reconcile disarmed skeleton (#6902)

Derived from `knowledge-base/project/plans/2026-07-24-feat-encryption-posture-layer-b-reconcile-skeleton-plan.md`.
Scope: DISARMED measure-then-arm skeleton. Armed reconcile + dedicated Sentry monitor DEFERRED.

## Phase 0 — Preconditions (verify, do not assume)

- [ ] 0.1 Re-run the coverage measurement: `grep -c '"live_verification": "available"' scripts/encryption-posture-ledger.json` == 1; the address is `hcloud_volume.workspaces_luks`.
- [ ] 0.2 Confirm `python3 scripts/lint-encryption-posture.py --json` emits the full ledger and exits 0 (the single-parser contract).
- [ ] 0.3 Confirm the repo test runner + its discovery globs for the new test file (`grep -E 'include|testMatch' apps/web-platform/vitest.config.ts` or the plugin test convention `ls plugins/soleur/test/`); pick the test path that the runner actually collects.
- [ ] 0.4 `git fetch origin main` and re-derive the next-free ADR ordinal (`ls knowledge-base/engineering/architecture/decisions | grep -oE 'ADR-[0-9]+' | sort -t- -k2 -n | tail -1`) — provisional ADR-141 may collide.
- [ ] 0.5 Confirm the ADR-033 prefer-inngest hook does NOT fire on EDITING an existing `scheduled-*.yml` (adding a job), only on CREATE (verify per deepen verify-the-negative finding).

## Phase 1 — ADR-141 (architecture decision — plan deliverable)

- [ ] 1.1 Write ADR-141 via `/soleur:architecture`: DISARMED verdict; host-probe-vs-runner-reconcile distinction; ride-existing-workflow (ADR-033) + cadence-coupling acceptance; set-equality gate design; arm sequencing behind #6894/#6895/#6897; provider-managed rows structurally out of runner reach. `status: adopting`.
- [ ] 1.2 If the ordinal renumbered from 141, sweep the plan + this tasks.md + all ACs naming the ordinal.

## Phase 2 — Reconcile probe (RED then GREEN)

- [ ] 2.1 Write failing tests first (`cq-write-failing-tests-before`) with SYNTHESIZED ledger fixtures (`cq-test-fixtures-synthesized-only`): equal arm (1 avail + 13 unavail → DISARMED exit 0); shrank arm (baseline member missing → REGRESSION ::error:: exit non-zero); grew arm (superset → ARM_READY exit 0); incomparable-overlap (adds AND removes → routes to REGRESSION, not ARM_READY — per spec-flow finding); crash/abnormal-rc → error path (rc-normalization); the `--json` (not `--report --json`) shell-out literal.
- [ ] 2.2 Implement `plugins/soleur/scripts/reconcile-encryption-posture.ts`: shell out to `python3 scripts/lint-encryption-posture.py --json`; parse; compute `ACTUAL_AVAILABLE` set; compare to pinned `EXPECTED_AVAILABLE = {"hcloud_volume.workspaces_luks"}`; emit the mandatory verdict line `SOLEUR_ENCRYPTION_POSTURE_RECONCILE_{DISARMED|REGRESSION|ARM_READY} ...`; exit codes per arm; no GitHub API / no network in the disarmed path.
- [ ] 2.3 Normalize any abnormal exit (crash/OOM 137 / SIGSEGV 139 / timeout 124) to the error path (mirror `reconcile-live-heartbeats.ts` rc-normalization) so a crash never exits 0 before the verdict line.
- [ ] 2.4 Green the suite.

## Phase 3 — Workflow wiring

- [ ] 3.1 Add the `encryption-posture-reconcile` job to `.github/workflows/scheduled-terraform-drift.yml`: rides the existing dispatch (no `schedule:`/new `on:`); runs the reconcile; captures stdout+stderr; asserts the mandatory verdict line is PRESENT (positive control — a silently-skipped reconcile fails, not greens).
- [ ] 3.2 Route hard failure (rc != 0) to `::error::` + a `./.github/actions/notify-ops-email` step (mirror the drift job's email path). No `monitor-slug:` heartbeat step (dedicated Sentry monitor deferred).
- [ ] 3.3 Confirm `sentry-monitor-iac-parity.test.ts` stays green with no new monitor (the job adds no `monitor-slug:`).

## Phase 4 — Verification & docs

- [ ] 4.1 `python3 scripts/lint-encryption-posture.py --repo-sweep` PASSES (no `.tf` store added).
- [ ] 4.2 Typecheck: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (if the script is TS under that package) — else the plugin's typecheck path.
- [ ] 4.3 Full test suite green for new/edited files.
- [ ] 4.4 Confirm the plan's `## Decision Challenges` are captured in `decision-challenges.md` for `ship` to render + file as `action-required`.

## Phase 5 — Deferral tracking

- [ ] 5.1 File the Layer B armed-reconcile tracking issue (milestone from roadmap.md): what (armed per-row reconcile + find-or-update-by-title + dedicated Sentry monitor + parity coverage), why deferred (1/14 measurable; overlap), re-eval criteria (arm when runner-reconcilable coverage grows past baseline — the `grew`/ARM_READY signal), blockers #6894/#6895/#6897.
- [ ] 5.2 Do NOT file new emitter issues (#6894/#6895/#6897 already OPEN) — reference them as blockers.
