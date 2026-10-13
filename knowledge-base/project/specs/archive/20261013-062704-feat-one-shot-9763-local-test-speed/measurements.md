# Measurements — #9763

Source: `scripts/suite-durations.tsv` committed weights (idle-machine measured, floor rows = first-run estimates).

## 20 slowest registered suites (ms)

| rank | suite | ms |
|---:|---|---:|
| 1 | scripts/test-all-affected | 311400 |
| 2 | scripts/lint-orphan-test-suites-mutations-b | 297408 |
| 3 | scripts/lint-orphan-test-suites-mutations-a | 258165 |
| 4 | tests/scripts/betterstack-roundtrip-latency | 165660 |
| 5 | scripts/cf-tunnel-liveness-gate-mutations | 161761 |
| 6 | plugins/soleur/skills/agent-browser/test/playwright-mcp-redact-proxy.test.sh | 155155 |
| 7 | scripts/test-contention | 137730 |
| 8 | tests/scripts/git-data-birth-readiness-gate | 134314 |
| 9 | scripts/test-all-infra-coverage-notice | 128451 |
| 10 | scripts/orphan-process-reaper-mutations | 113367 |
| 11 | plugins/soleur/test/operator-ack-guard.test.sh | 109036 |
| 12 | plugins/soleur/test/monitor-pr-checks.test.sh | 102640 |
| 13 | plugins/soleur/test/operator-script.test.sh | 98487 |
| 14 | tests/scripts/sentry-alert-live-fidelity | 90442 |
| 15 | scripts/audit-suite-reads | 73102 |
| 16 | scripts/web2-rebirth | 72000 |
| 17 | scripts/test-affected-kb-consumers | 68386 |
| 18 | plugins/soleur/test/hook-input-classification-mutation.test.sh | 64455 |
| 19 | tests/scripts/no-tofu-ssh-mutation | 61019 |
| 20 | scripts/check-web-host-escrow-config | 61002 |


AC-4 probe: staged docs-only measurement

## AC-4 idle-machine `--affected` wall-clock (2026-10-09)

Two docs-only arms measured via `--affected --affected-scope=staged` on the idle host:

| diff | wall-clock | result |
|---|---|---|
| `README.md` only (pure docs) | **4.40 min** | 111/595 passed, 0 failed |
| `knowledge-base/` spec file | 5.7 min | 111/595 passed, 1 failed (pre-baseline-fix kb-consumers argv-code rows — expected demotion-round triage, fixed by `--write-baseline`) |

The kb arm legitimately selects `scripts/test-affected-kb-consumers` (~65 s) — its declared
`knowledge-base/` edge is the honest subject for a suite whose verdict reads the kb tree.
Baseline before this change: ~25 min observed on PR #9751 (the issue's motivating number).
