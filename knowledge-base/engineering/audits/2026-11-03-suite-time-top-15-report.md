# Top-15 suite-time report — 2026-11-03

Epic #11556 Lever A item 2 (pre-staging for the next Lever-A slice ahead of #11954's first `wallclock-p90-watch` report, Fri 2026-11-06 09:07 UTC).

## Method

Sample: last 5 green `merge_group` `ci.yml` runs (canonical full-matrix surface — `scripts/watch-shard-legs.sh`/`watch-shard-balance-11564.sh` convention: push runs elide the shards job under push-dedupe, PR runs select a reduced battery and are a different distribution). Runs: 41693754894, 41685524714, 41678029255, 41677528300, 41668436219.

```bash
gh run list --workflow ci.yml --event merge_group -L 15 \
  --json databaseId,conclusion --jq '.[] | select(.conclusion=="success") | .databaseId' | head -5
gh run download <rid> -R jikig-ai/soleur -p 'suite-timings-scripts-*' -D <dir>
# concat */suite-timings.tsv, drop __run_boundary_* sentinels, median per label, rank desc
```

Artifacts live 14 days; 11 `suite-timings-*` artifacts per run; 726 distinct labels, n=5 samples each.

## Ranked table (median over 5 green merge_group runs)

| # | Suite (label) | Median | Leg | Committed price | Δ vs price | Cause class | Evidence |
|---|---|---|---|---|---|---|---|
| 1 | `plugins/soleur/test/ci-pr-affected-replay-a` | **1280.4s** | 2 | 1033.1s (measured) | +24% | fixture-build + per-row harness spawn — 5223-line suite replaying the audit over git-init fixture repos and the live tree; leg `-a` carries the heaviest `--rows` range | `plugins/soleur/test/ci-pr-affected-replay.test.sh:62-75` (row-range registration ×3) |
| 2 | `plugins/soleur/test/ci-pr-affected-replay-b` | 465.1s | 7 | 399.4s | +16% | same harness, lighter row range | same file |
| 3 | `plugins/soleur/test/ci-head-verdict.test.sh` | 449.8s | 5 | 276.0s | **+63%** | per-row fixture matrix — every verdict state fabricated via `mkrow`/`addtest`/`addrun` over stub `gh` | `ci-head-verdict.test.sh:241-387` (V4/V7/V9/V10/V15/V26 row loops) |
| 4 | `plugins/soleur/test/ci-pr-affected-replay-c` | 444.4s | 4 | 326.2s | +36% | same harness, lighter row range | same file |
| 5 | `plugins/soleur/test/real-sdk-ask-probe-workflow.test.sh` | 391.7s | 7 | 257.0s | **+52%** | per-row python/harness spawn over workflow-shape assertions + probe-job emulation (`npm ci` contract checks) | `real-sdk-ask-probe-workflow.test.sh:519-990` |
| 6 | `scripts/test-all-group-affected` | 349.5s | 6 | **3.2s — STALE** | ~109× | nested runner — drives `test-all.sh` machinery itself; committed price predates suite growth | `test-all-group-affected.test.sh` (621 lines, no sleeps) |
| 7 | `.claude/hooks/git-commit-secret-scan.test.sh` | 297.1s | 4 | **6.9s — STALE** | ~43× | sheer breadth — 4566 lines of deny/allow cases, subprocess per assertion | `git-commit-secret-scan.test.sh` (4566 lines; 15 `sleep` lines incl. timeout waits) |
| 8 | `plugins/soleur/test/monitor-pr-checks.test.sh` | 273.9s | 6 | 245.1s | +12% | `gh api` stub-harness per state row | `monitor-pr-checks.test.sh:115-464` |
| 9 | `scripts/followthroughs/ci-draft-light-soak-9728` | 273.8s | 3 | 104.5s | **+162%** | soak-probe loop — enumerates/reads large run sets (API-shape walk) | `ci-draft-light-soak-9728.test.sh` (821 lines) |
| 10 | `scripts/test-all-infra-coverage-notice` | 262.8s | 4 | 163.6s | +61% | nested runner over infra suite census | `test-all-infra-coverage-notice.test.sh` (979 lines) |
| 11 | `scripts/followthroughs/ci-push-dedupe-soak-9512` | 254.6s | 5 | 87.9s | **+190%** | soak-probe loop over dedupe units | `ci-push-dedupe-soak-9512.test.sh` (671 lines) |
| 12 | `plugins/soleur/test/destructive-command-guard-mutation.test.sh` | 235.5s | 4 | 142.1s | +66% | per-mutant harness — loops mutant IDs through the guard | `destructive-command-guard-mutation.test.sh:437-507` |
| 13 | `scripts/check-web-host-escrow-config` | 231.2s | 5 | 144.6s | +60% | API/probe walk over host config | `check-web-host-escrow-config.test.sh` (527 lines) |
| 14 | `tests/scripts/git-data-birth-readiness-gate` | 218.7s | 7 | 159.6s | +37% | real HTTP probes (`curl --max-time 20` per gate case) | `tests/scripts/lib/git-data-birth-readiness-gate.sh:1093-1143` |
| 15 | `plugins/soleur/skills/agent-browser/test/playwright-mcp-redact-proxy.test.sh` | 183.1s | 6 | 153.8s | +19% | browser/proxy startup per case | `playwright-mcp-redact-proxy.test.sh` (1615 lines) |

## Findings

1. **`ci-pr-affected-replay-a` is the outlier by 2.7×** — 21.3 min median, leg 2. The suite is already `--rows`-split 3 ways; leg `-a` simply carries the heaviest range. This is the same suite that dominated the atomic-S4 legs fixed in #11562 — the split helped (`-b`/`-c` are 465/444s) but `-a` remains the battery's pace-setter. Remedy sketch: re-split the `-a` range (a 4th leg), or bound the fixture corpus the `-a` rows build.
2. **Two committed prices are stale by an order of magnitude** — `scripts/test-all-group-affected` priced 3.2s vs 349.5s measured (~109×), `git-commit-secret-scan.test.sh` priced 6.9s vs 297.1s (~43×). Stale prices corrupt the shard-balance math the same way an unmeasured `floor` row does — the watch already treats `floor` as a finding; a wrong-but-present price is worse because it looks measured. Remedy: refresh `suite-durations.tsv` for the two rows and add a price-vs-measure drift check to the existing balance watch.
3. **Soak suites are a rising class** — `ci-draft-light-soak` +162%, `ci-push-dedupe-soak` +190% vs price. Soak probes enumerate and read large run sets; their cost grows with history. Remedy: bound the read window (e.g. last N runs/days) or paginate to a cap.
4. **No sleep-wait or lock-contention class dominates** — the top-15's cost is fixture-build/spawn-per-case and soak-API-walk shapes, plus one real-HTTP suite. The epic's hypothesized causes (sleep-based waits, shared-lock contention) are absent from the top 15; repeated tool installs appear only as `npm ci` contract assertions, not live installs.
5. **Caveat — `merge_group` medians ≠ PR-surface medians** — per the Oct-29 learning, PR runs select a reduced battery; this table prices the canonical full-matrix surface, which is also what `wallclock-p90-watch` reports on.

## Postscript 2026-11-08 — `ci-pr-affected-replay-a` is retired as pace-setter (#12015)

The `-a` outlier this report prices was measured pre-retirement. PR #12296 (merged 2026-11-07T13:45Z) removed the 129 `row_ow_*` gated sites — ordinals 1-129 of the then-602-site file, ~993s of arm `-a`'s gated work per the committed site-cost measurement. Post-retirement green `merge_group` suite-timings (runs 42447940669, 42442159415, 42439386564): `-a` medians ~160s — now the **fastest** arm — vs `-b` ~226s and `-c` ~166s. A guarded three-arm site-cost reading on tree `f0c3bb8656` (476-site file) agrees: gated site seconds a=98.8, b=188.6, c=136.5. Neither remedy sketched above (4th `--rows` leg, fixture-corpus bound) is warranted; evidence record: `knowledge-base/project/specs/feat-one-shot-12015-replay-a-pacer/measurements.md`. Arm `-b` (~226s) is the mildest of successors if a future pace-setter emerges.

## Pre-staged next slice (filed as issues)

- `ci-pr-affected-replay-a`: 4th leg or fixture-corpus bound (the 21-min pace-setter).
- `suite-durations.tsv`: refresh the two stale prices + a price-vs-measure drift arm on the shard-balance watch.
- Soak-window bound for the two rising followthrough soaks.
