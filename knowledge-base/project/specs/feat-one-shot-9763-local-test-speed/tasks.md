# Tasks — #9763 local test speed / pyramid alignment

## Phase 1 — Tier split (FR-1, FR-2)

- [ ] 1.1 `scripts/lib/test-affected-paths.sh`: add `CI_HEAVY_SUITES` — the 29 always-on labels with committed weight > `LOCAL_FAST_CAP_MS=10000` (derived from `suite-durations.tsv`, listed verbatim); move them out of `ALWAYS_ON_SUITES`; add own-file fallback (suite file touched → runs) and consumed-edge fallback where a subject array exists in `test-relevance-paths.sh`.
- [ ] 1.2 `scripts/test-all.sh`: `[skip] (ci-tier)` decline class in the affected epilogue — skipped heavy suite reads as tiered with its reason (runs in CI / `--full`).
- [ ] 1.3 Verify `--print-selection` on a docs-only diff: 29 ci-tier declines, `always_on` ≤130; on a diff touching `plugins/soleur/test/operator-ack-guard.test.sh`: that suite selected via own-file arm.

## Phase 2 — Budget ratchet (FR-4)

- [ ] 2.1 New `scripts/test-all-fast-tier-budget` (shell, sub-second): asserts every `ALWAYS_ON_SUITES` label has committed weight ≤ 10 s and Σ weights ≤ 300 s; registered ALWAYS_ON + run_suite registration; follows `test-helpers.sh` conventions (set -euo pipefail, counters, anti-vacuity floor where applicable).
- [ ] 2.2 Mutation matrix M1–M6 per Guard Contract; record verdicts in spec dir.
- [ ] 2.3 Register the suite in `suite-shard-legs.tsv`/`suite-durations.tsv` via `regenerate-shard-manifest.py --incremental --write` and in the affected index (registration edge).

## Phase 3 — Docs + evidence (FR-3, FR-5)

- [ ] 3.1 `plugins/soleur/skills/ship/SKILL.md` Phase 4 + `battery-owed.sh` verdict text: local battery = fast tier (always-on = sub-10-s ratchets); `--full` = complete local run; CI = merge gate. Byte-frugal — work/SKILL.md sits at ~9 B headroom under the 362 KB ceiling; ship/SKILL.md has its own ceiling to check.
- [ ] 3.2 AC-1: 20-slowest table (ms) from `suite-durations.tsv` — write to spec `measurements.md` + post on #9763.
- [ ] 3.3 AC-4: real `bash scripts/test-all.sh --affected` wall-clock on a docs-only diff on the idle machine — before/after numbers recorded (before = committed-weight sum ≈1298 s + edges; after = measured).
- [ ] 3.4 AC-2/AC-3: write the budget (target <5 min; per-suite cap 10 s committed weight) and the four proposal dispositions to the issue.

## Phase 4 — Sweep

- [ ] 4.1 Consumers of `ALWAYS_ON_SUITES` unaffected/green: `test-affected-derive` parity, `fanout-suite-scope`, `suite-exit-class-parity`, `orphan-lint`, `guard-vacuity-floor`, `test-all-affected` mutation battery.
- [ ] 4.2 AC sweep + tasks/plan checkboxes.

Budget: ~250 lines / ~6 files.
