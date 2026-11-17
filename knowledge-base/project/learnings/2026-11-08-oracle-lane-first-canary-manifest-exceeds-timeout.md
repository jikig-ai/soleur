# Learning: the first live oracle-lane canary proved the lane's `if:`/`ORACLE-ONLY-SKIP` mechanics — and killed itself on a wall-clock bound nobody measured

## Problem

Activation of the oracle-only fast lane (#12156 → unlock PR #12300 → canary PR #12382) went green on every designed check except one: `oracle-index-check` — the lane's own validation leg — was `cancelled` after running its serial manifest for 29m53s against `timeout-minutes: 30`. The `test` aggregate went `failure` (a skipped/cancelled oracle leg is never tolerated on `pull_request`), and `CI_ORACLE_LANE` was deleted per the prescribed rollback. Every executed manifest case printed `[ok]`; only 5 of the 15 committed suites in `scripts/ci-oracle-lane-suites.txt` finished.

## Solution

- Roll back first, file second: `gh variable delete CI_ORACLE_LANE` restores the dark state (oracle-selection job skipped, full battery gates) at zero runner cost; defect filed as #12393. A `gh run rerun` on the same SHA then re-executes under the dark path — the `if:`/`needs.outputs` conditions re-evaluate against the absent variable, no empty commit needed.
- Re-activation gate (in #12393 and the runbook): shrink the manifest's serial runtime under the bound (matrix of legs, or cut the ~11 s/case mutation-matrix cost) or raise `timeout-minutes` only with evidence the runner stays inside it; then re-arm and re-canary.

## Key Insight

A lane's validation leg is itself subject to the resource bound it was sized against by estimate. The `ci.yml` comment estimated "~10-20 min the oracle/selector batteries measure together"; the first real serial run measured ~3x that (mutation-matrix cases ~11 s each). An activation canary exists precisely to catch this class: the mechanics (`if:` conjuncts, aggregator tolerance, `would_skip` telemetry) were all proven green in the same run that proved the leg structurally unbounded. "Cancelled" is a third verdict, not a pass and not a classic red — for an activation canary it fails the settle-green criterion and triggers the same rollback.

## Session Errors

1. **`gh issue create` refused: missing `--milestone` and a filing exit (`meta/machinery` label / User-Impact+Fix-Size / Mandated-By).** Recovery: added `--milestone "Post-MVP / Later" --label meta/machinery` and re-issued. **Prevention:** compose the filing with milestone + a filing exit on first issue-create in this repo.
2. **Job logs `BlobNotFound` while the job is in-flight.** Recovery: waited for completion, then fetched. **Prevention:** `gh api .../jobs/<id>/logs` only after `status=completed`; use `steps[]` for in-flight progress.
3. **Transcript-ordering confusion about whether a pushed commit existed.** Recovery: resolved via `git reflog <branch>` + `git log`, not transcript order — subagent notifications reorder visible output. **Prevention:** when a git state claim matters, read `git log`/`reflog`/`ls-remote`, never infer from print order.

## Tags

category: workflow-issues
module: ci / oracle-lane
