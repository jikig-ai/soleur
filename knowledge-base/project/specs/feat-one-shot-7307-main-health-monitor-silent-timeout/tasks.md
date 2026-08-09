---
issue: 7307
branch: feat-one-shot-7307-main-health-monitor-silent-timeout
pr: 7371
lane: cross-domain
plan: knowledge-base/project/plans/2026-08-09-fix-main-health-monitor-silent-timeout-plan.md
---

# Tasks — fix main-health-monitor (#7307)

Derived from the finalized (post-review) plan. Phase order is load-bearing: measurement precedes
sizing, and the exit-code fix precedes arming the filer.

## Phase 0 — Preconditions

- [ ] 0.1 `gh workflow list --all | grep -i "Main Health Monitor"` — confirm the workflow exists on
      the default branch, which is what makes pre-merge `--ref` dispatch legal.
- [ ] 0.2 `gh issue list --label ci/main-broken --state open` — must be empty before any dispatch,
      or a green measurement run will close a real tracker.
- [ ] 0.3 Read the committed toolchain table in `apps/web-platform/infra/run-registered-suites.sh`
      (per-tool counts: docker 2, terraform 5, python3 5, cloud-init 1, jq 3) and the paragraph
      above it on silent PASS. Derive the Phase 4 install list from it — do not hardcode.
- [ ] 0.4 `bash apps/web-platform/infra/run-registered-suites.sh --list | grep -c '\.test\.sh'` —
      record the live suite count; never cite a literal.

## Phase 1 — Measure (before sizing, before arming the filer)

- [ ] 1.1 Apply ONLY: the Phase 2 pipefail guard, the Phase 4 infra step + toolchain, and a
      provisional absurd ceiling (tests 90 / infra 40 / job 140). Push.
- [ ] 1.2 `gh workflow run main-health-monitor.yml --ref feat-one-shot-7307-main-health-monitor-silent-timeout`
- [ ] 1.3 Record **job-level** durations via `gh run view <id> --json jobs`, split per step
      (`tests` and `infra` separately — Phase 3 sizes them independently). Repeat once for n=2.
- [ ] 1.4 Read the run's epilogue: confirm `=== N/N suites passed ===` with zero failures and that
      the toolchain assertion passed. **Gate: do not proceed to 2.4 until this is green** (R1/H8).

## Phase 2 — Make failures reportable (do first)

- [ ] 2.1 Add a `Reset test output capture` step: `run: ': > /tmp/test-output.txt'`.
- [ ] 2.2 Rewrite the test step with the house idiom — `set +e` / pipeline into `tee -a` /
      `rc=${PIPESTATUS[0]}` / `set -e` / `exit "$rc"`. Nothing between the pipeline and the read.
- [ ] 2.3 Harden the summary read on **emptiness, not existence**:
      `if [[ -s /tmp/test-output.txt ]]; then SUMMARY=$(tail -30 …); else SUMMARY="(no test output…)"; fi`
- [ ] 2.4 Filer `== 'failure'` → `!= 'success'`; closer stays `== 'success'`.
- [ ] 2.5 Drop `--milestone` from `gh issue create`; set it after via
      `gh issue edit … || echo "::warning::milestone not set"`.
- [ ] 2.6 Branch the issue body on whether the capture contains a `[FAIL]` marker; include the
      `outcome` value verbatim in both shapes.
- [ ] 2.7 Add the `Record step outcomes` step (`if: always()`) writing `tests=` / `infra=` to
      `$GITHUB_STEP_SUMMARY` — without it the outcomes are unreadable after the fact.

## Phase 3 — Size the ceilings

- [ ] 3.1 Apply the rule: `roundup5(x) = 5*ceil(x/5)`; minutes fractional to 2dp;
      `tests_step = max(30, roundup5(tests_max*1.5))`; `infra_step = max(10, roundup5(infra_max*1.5))`;
      `job = tests_step + infra_step + 5 + 10`. **Job dominates the SUM, not the max.**
- [ ] 3.2 Confirm `job <= 120` (6h cadence).
- [ ] 3.3 Write the in-file budget comment with measured run IDs, per-step durations, the rule,
      and the **worked arithmetic** for every `timeout-minutes` in the file. State that 1.5x and
      the floors are arbitrary slack (public repo, free minutes), not a variance estimate.
      State that the #7307 band is censored data and must not be reused.

## Phase 4 — Cover the infra suites

- [ ] 4.1 Install the toolchain: `hashicorp/setup-terraform` (same pinned SHA as
      `infra-validation.yml`), `sudo apt-get install -y -qq cloud-init`, plus anything else the
      Phase 0.3 table names. (docker/python3/jq are preinstalled on the hosted runner.)
- [ ] 4.2 Add the `Assert infra toolchain present` step (`command -v terraform && … && docker info`),
      **ordered before** the infra step. Without it, absent tools self-skip exit 0 and the runner
      prints PASS — a green over missing coverage.
- [ ] 4.3 Add the `id: infra` step with `TEST_GROUP: infra`, its own ceiling, and the same
      `set +e` / `PIPESTATUS` / `exit` idiom, piping to `tee -a`.
- [ ] 4.4 Widen the filer to `tests != success || infra != success`; tighten the closer to
      `tests == success && infra == success`.
- [ ] 4.5 **Invariant:** `steps.infra` appears at exactly 3 sites (filer, closer, heartbeat) or 0.
      Never a partial set — an absent step context is a null dereference, not a no-op.

## Phase 5 — External liveness (gap E)

- [ ] 5.1 Add `sentry_cron_monitor.main_health_monitor` to
      `apps/web-platform/infra/sentry/cron-monitors.tf`: crontab read from
      `cron-main-health-monitor.ts`, `checkin_margin_minutes = 60`, `max_runtime_minutes = 15`
      (decorative under single-heartbeat — do NOT couple it to the job ceiling),
      `failure_issue_threshold = 1`, `recovery_threshold = 1`, `timezone = "UTC"`.
- [ ] 5.2 Add the terminal `Sentry check-in (final)` step (`if: always()`, `continue-on-error: true`)
      using `./.github/actions/sentry-heartbeat`, slug `main-health-monitor`.
- [ ] 5.3 **Land 5.1 and 5.2 in ONE commit** — `prod-version-drift-check.test.sh` B10g asserts
      slug parity in one direction, `sentry-monitors-audit.sh` in the other.

## Phase 6 — Concurrency

- [ ] 6.1 `cancel-in-progress: true` → `false`.

## Phase 7 — Verification (all pre-merge)

- [ ] 7.1 AC1 — dispatch with a failing shim: summary shows `tests=failure`, issue filed, nothing closed.
- [ ] 7.2 AC2 — clean dispatch: `tests=success`, nothing filed, open tracker closed.
- [ ] 7.3 AC3 — filer survives BOTH no-output shapes: file absent, and file present-but-empty
      (the shape a timeout actually produces).
- [ ] 7.4 AC4 — filer survives a bad milestone and emits the `::warning::`.
- [ ] 7.5 AC5/AC6 — budget comment carries run IDs, per-step durations, worked arithmetic for every
      `timeout-minutes`, and labels the #7307 band as censored.
- [ ] 7.6 AC7 — `job >= tests_step + infra_step + 15` and `job <= 120`.
- [ ] 7.7 AC8 — toolchain assertion passed; log shows `IS covered above`, no
      `SKIPPED (diff does not touch`.
- [ ] 7.8 AC9 — `grep -c 'steps\.infra' .github/workflows/main-health-monitor.yml` is 3 (or 0 if no
      `id: infra` step). Any other count is a reject.
- [ ] 7.9 AC10 — timeout body differs from red-suite body; both carry the `outcome` value.
- [ ] 7.10 AC11 — `terraform validate` in `apps/web-platform/infra/sentry/`;
      `bash scripts/prod-version-drift-check.test.sh` passes (B10g); both edits in one commit.
- [ ] 7.11 AC12 — `python3 scripts/lint-workflow-errexit-capture.py` → clean, rc 0.
- [ ] 7.12 AC13 — crontab matches `cron-main-health-monitor.ts`.
- [ ] 7.13 AC14 — `timeout 120 actionlint .github/workflows/main-health-monitor.yml`, no new finding.
- [ ] 7.14 AC15 — `bash scripts/test-all.sh > /tmp/out.log 2>&1; echo $?` = 0.
      **Redirect + `$?`, never a pipe.**
- [ ] 7.15 AC16 — `git diff origin/main` contains no leftover shim.

## Phase 8 — Ship

- [ ] 8.1 Capture the learning under `knowledge-base/project/learnings/` (directory + topic only;
      pick the date at write time): the engine-reads-the-exit-code class, why the existing errexit
      linter correctly does not cover it, and censored-series reasoning.
- [ ] 8.2 PR body: `Closes #7307`.
