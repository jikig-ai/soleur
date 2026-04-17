# fix(ci): bump web-platform-release `Verify deploy script completion` timeout from 120s to 300s

**Issue:** [#2519](https://github.com/jikig-ai/soleur/issues/2519)
**Branch:** `feat-one-shot-2519`
**Worktree:** `.worktrees/feat-one-shot-2519/`
**Date:** 2026-04-17
**Type:** Bug fix (CI / polling window)
**Scope:** Single file, 1-line env value edit (and a brief comment refresh)
**Related:** #2205 (named-bounds introduction), #2214 (non-JSON body guard at this same step), #2199 (lock_contention state), #968 (async webhook migration — established the 300s health-check window), #2226 (predecessor fix to the same `Verify deploy script completion` step)

## Enhancement Summary

**Deepened on:** 2026-04-17
**Scope:** Targeted (trivial single-file 1-line env value edit; full multi-agent fan-out is YAGNI here).
**Research surfaces consulted:**

- `.github/workflows/web-platform-release.yml` (full file read — all poll loops, all step env configs, concurrency group)
- `apps/web-platform/infra/ci-deploy.sh` (state-file write ordering, flock semantics, EXIT trap behavior)
- AGENTS.md rules `wg-after-a-pr-merges-to-main-verify-all`, `cq-ci-steps-polling-json-endpoints-under`, `cq-deploy-webhook-observability-debug`
- Learning `2026-03-21-async-webhook-deploy-cloudflare-timeout.md` (establishes why the health-poll step uses 30 × 10 = 300s — "Docker image pull + container restart routinely takes 60-180 seconds")
- Learning `2026-04-15-signed-get-verify-step-tolerate-non-json-bodies.md` (the most recent prior fix to this exact step — #2214/#2226)
- Learning `2026-03-20-ci-deploy-reliability-and-mock-trace-testing.md` (skip_deploy preservation pattern — N/A here since we only touch env vars)
- `git log` on `.github/workflows/web-platform-release.yml` (20 most recent commits — no prior PR has raised `STATUS_POLL_MAX_ATTEMPTS` in response to a real timing incident)
- `gh issue list --label code-review --state open` + jq overlap check on the file path (0 matches)
- Local `actionlint` invocation on the pre-edit file (clean)

### Key Validations from Research

1. **The 300s ceiling has prior art and is principled, not arbitrary.** The downstream `Verify deploy health and version` step already uses 30 attempts × 10s interval = 300s. That value was chosen in #968 (async webhook migration) specifically because "Docker image pull + container restart routinely takes 60-180 seconds" (per the 2026-03-21 learning). The verify-completion step reads a state file that `ci-deploy.sh` writes AFTER pull + canary + health + promote, which can take the same 60-180s range. A 120s ceiling is tighter than the worst-case runtime of the very thing it is supposed to observe — it was always going to produce false negatives under real load. Aligning to 300s eliminates that class.

2. **Choosing MAX_ATTEMPTS=60, INTERVAL_S=5 (over INTERVAL_S=10) is load-bearing.** Keeping the 5s interval preserves fail-fast detection of early non-zero exits. `ci-deploy.sh` writes terminal state (`insufficient_disk_space` at line 225, `lock_contention` at line 210, `unhandled` via EXIT trap at line 96) within seconds. The verify step's `*)` case exits 1 on any non-`-1`/`-2`/`-3`/`0` exit code. A 5s interval catches these ~5s after they happen; a 10s interval would double that window for no benefit, since the 300s-ceiling story is driven by worst-case pull+start, not by throttling curl.

3. **No retry or protocol change is needed beyond the ceiling bump.** The issue body suggested a secondary "graceful retry after lock clears" fix. The `flock -n` + `lock_contention` + state-file path in `ci-deploy.sh` is already correct: a loser writes `lock_contention` via `final_write_state` (line 210) with a non-`-1`/`-2`/`-3`/`0` exit code, which the verify step's `*)` case correctly reports as a failure. The rerun false-negative in run 24583922171 happened specifically because the original attempt's verify step timed out (producing a failed workflow), which triggered the human `gh run rerun --failed`, which POSTed a fresh deploy. If the original verify step had succeeded under a 300s ceiling, the rerun would never have fired. Fix the ceiling → the rerun class disappears. Adding lock-aware retry logic is redundant and adds surface area.

4. **The existing jq-e guard (#2214) still works.** The guard at lines 127-131 will still correctly skip cold-start / non-JSON responses without being affected by the MAX_ATTEMPTS bump. The bump simply gives the loop more chances to see a valid JSON `exit_code=0, tag=vX.Y.Z` response.

5. **No shellcheck / actionlint risk.** Changing an integer env value does not introduce lint findings. Verified: `actionlint` on the current file exits clean; the edit only changes `24` to `60`.

6. **No code-review issue overlap.** `gh issue list --label code-review --state open` + `jq '.body | contains(".github/workflows/web-platform-release.yml")'` returned 0 matches — no fold-in, no acknowledgment, no defer needed.

7. **No cross-workflow sweep needed.** The issue is specific to this step. No other workflow uses `STATUS_POLL_*` env vars (`grep` confirms — the constants are not shared). The downstream `HEALTH_POLL_*` bounds are intentionally separate and already correct.

### New Considerations Discovered

- **Add a one-line cross-reference to the new 300s rationale in the comment block.** Reviewers should be able to scan the comment and see why 300s, not 120s, and why INTERVAL_S stays at 5. Added to the acceptance criteria.
- **Acceptance criterion: dynamic-window error message is self-updating.** Line 162's `$((STATUS_POLL_MAX_ATTEMPTS * STATUS_POLL_INTERVAL_S))s` will read "300s" after the bump — confirmed at read time. No string literal edit needed.
- **Post-merge verification must be passive.** The plan already notes "do NOT trigger `gh workflow run web-platform-release.yml` synthetically." The workflow is triggered by tag push / reusable release — synthetic dispatch would fail because it expects release-context inputs. Piggyback on the next organic release.
- **No Sentry alert needed for verify-step timeouts.** The `::error::` annotation is already picked up by the post-merge monitor. Adding Sentry is a separate observability decision (cq-silent-fallback-must-mirror-to-sentry does not apply — this is a workflow step annotation, not a server-side silent fallback).

## Overview

The `Verify deploy script completion` step in `.github/workflows/web-platform-release.yml` polls the `/hooks/deploy-status` endpoint to confirm `ci-deploy.sh` finished for the current tag. The current bounds — `STATUS_POLL_MAX_ATTEMPTS=24`, `STATUS_POLL_INTERVAL_S=5` — give a **120s** window.

On run 24583922171 (merge `d40061bb`, PR #2500), the production deploy completed successfully (`/health` uptime 28s confirms), but ci-deploy.sh took longer than 120s to report completion via the state file. The verify step exited with "ci-deploy.sh did not report completion for v0.43.0 within 120s." A subsequent `gh run rerun --failed` then POSTed another deploy to `/hooks/deploy`, which spawned a second ci-deploy.sh that failed `flock -n` and wrote `lock_contention` — producing a second false-negative failure for what was in fact a healthy deploy.

**Root cause:** The 120s ceiling is tighter than the deploy's realistic worst-case. The subsequent step in the same workflow (`Verify deploy health and version`) already uses a 300s window (`HEALTH_POLL_MAX_ATTEMPTS=30`, `HEALTH_POLL_INTERVAL_S=10`). Aligning the verify-completion step to the same 300s ceiling removes the false-negative class without weakening the failure signal.

**Fix:** Change `STATUS_POLL_MAX_ATTEMPTS` from `24` to `60` (keeping `STATUS_POLL_INTERVAL_S` at 5s → 300s total). This chosen over raising the interval to 10s because keeping a 5s interval preserves faster detection when ci-deploy.sh writes a non-zero exit code early (e.g., `insufficient_disk_space`, `unhandled` traps) — we still want to fail fast on real errors.

Per AGENTS.md rule `wg-after-a-pr-merges-to-main-verify-all`, a failing release workflow must be investigated every time. Chronic false-negative timeouts erode that signal.

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Codebase reality | Plan response |
|---|---|---|
| `STATUS_POLL_MAX_ATTEMPTS=24`, `STATUS_POLL_INTERVAL_S=5` | Confirmed at `.github/workflows/web-platform-release.yml:101-102`. Total ceiling = `MAX_ATTEMPTS * INTERVAL_S` computed at line 162. | Edit line 101 only (bump to 60). No interval change. |
| Retry (`gh run rerun --failed`) failed with `reason=lock_contention, tag=v0.43.0` because original ci-deploy.sh still held the lock | Confirmed `ci-deploy.sh` uses `flock -n 200` (`apps/web-platform/infra/ci-deploy.sh:205-212`); losers write `lock_contention` via `final_write_state`. | Bumping verify-completion window to 300s means the original attempt would have reported success before a retry was attempted. Secondary graceful-retry logic is NOT added — see "Alternative approaches" below. |
| Actual deploy succeeded; failure was verification-timeout false negative | Confirmed: `/health` showed v0.43.0, uptime 28s at the time of the failed workflow. | Fix is bounds-only, not protocol. |
| Proposed: bump MAX_ATTEMPTS to 60 **OR** interval to 10 | Both land at ≥ 240s. Downstream health-check step already uses 30 × 10 = 300s. | Choose MAX_ATTEMPTS=60 (300s at 5s intervals) — matches the health step's ceiling while preserving 5s granularity for fail-fast on early non-zero exits. |

No spec/codebase divergences. The issue description is accurate and complete.

## Open Code-Review Overlap

None. No open `code-review` issues touch `.github/workflows/web-platform-release.yml` as of this plan. (Verified via `gh issue list --label code-review --state open` + `jq .body | contains(...)` on the file path.)

## Implementation

### Files to edit

- `.github/workflows/web-platform-release.yml` — 1 line value change (line 101), optional 1-line comment update above it to document the reasoning.

### Files to create

- None.

### The Change

At `.github/workflows/web-platform-release.yml:100-102`, update:

```yaml
          # Named poll bounds (#2205). Total window = MAX_ATTEMPTS * INTERVAL_S.
          STATUS_POLL_MAX_ATTEMPTS: 24
          STATUS_POLL_INTERVAL_S: 5
```

To:

```yaml
          # Named poll bounds (#2205, #2519). Total window = MAX_ATTEMPTS * INTERVAL_S.
          # Raised from 24 (120s) to 60 (300s) after run 24583922171 hit a
          # false-negative timeout during a healthy v0.43.0 deploy. Aligns with
          # the downstream Verify-deploy-health step's 300s ceiling (line 169-170).
          # Kept INTERVAL_S=5 to preserve fail-fast on early non-zero exits
          # (e.g., insufficient_disk_space, unhandled traps).
          STATUS_POLL_MAX_ATTEMPTS: 60
          STATUS_POLL_INTERVAL_S: 5
```

No other changes. The existing error message (line 162: `ci-deploy.sh did not report completion for v$VERSION within $((STATUS_POLL_MAX_ATTEMPTS * STATUS_POLL_INTERVAL_S))s`) already recomputes the total window dynamically — no string edit needed.

## Alternative Approaches Considered

| Approach | Pros | Cons | Decision |
|---|---|---|---|
| **Chosen: MAX_ATTEMPTS=60, INTERVAL_S=5 (300s)** | Simple 1-line edit; aligns with health-check step; preserves 5s granularity for fail-fast | Doubles ceiling | **Chosen** |
| MAX_ATTEMPTS=24, INTERVAL_S=10 (240s) | Fewer curl calls (24 vs 60) over the window | Slower fail-fast on real errors; 240s < 300s health-check window (misaligned) | Rejected |
| MAX_ATTEMPTS=48, INTERVAL_S=5 (240s) | Compromise window | No principled reason for 240 over 300; misaligns with health-check | Rejected |
| Add graceful retry after timeout (poll one more time for lock_contention cleared) | Handles the rerun edge case gracefully | Materially more code (lock-state parsing, extra wait); the 300s bump alone removes the triggering case; YAGNI | Rejected (not built; `ci-deploy.sh`'s `flock -n` already writes a clean `lock_contention` state which the existing verify step detects via the `*)` case and exits 1 — correct behavior for the rerun path, just not useful for single-runs) |
| Switch from polling to SSE / webhook callback | Eliminates polling entirely | Materially more infra; `adnanh/webhook` does not natively push callbacks; out of scope | Deferred (no ticket filed — not justified by this signal) |

## Acceptance Criteria

- [ ] `.github/workflows/web-platform-release.yml:101` reads `STATUS_POLL_MAX_ATTEMPTS: 60`.
- [ ] `STATUS_POLL_INTERVAL_S` remains `5`.
- [ ] Comment block above the env vars documents the change, references `#2519`, and notes alignment with the downstream health-check step.
- [ ] `actionlint` passes (locally and via lefthook pre-push).
- [ ] `yamllint` passes if configured.
- [ ] No other steps / workflows are modified.
- [ ] Post-merge: the next release workflow run (triggered by merge of this PR or the next PR after it) completes the `Verify deploy script completion` step under the new ceiling with HTTP 200 + `exit_code=0` + `tag=vX.Y.Z` match — verified via `gh run view <run-id> --log` on the job.
- [ ] Post-merge verification uses `gh workflow run web-platform-release.yml` only if no organic release triggers happen soon; else piggyback on the natural next release.

## Test Strategy

**No new unit tests.** The change is a 1-line CI env value. The existing unit tests for `ci-deploy.sh` (`apps/web-platform/infra/ci-deploy.test.sh`) cover the state-file protocol that the verify step consumes; they are unaffected.

**CI validation:**

1. `actionlint` on `.github/workflows/web-platform-release.yml` (runs automatically via lefthook pre-push and `.github/workflows/ci.yml` if present).
2. `yamllint` if configured.

**Production validation (post-merge, per AGENTS.md `wg-after-a-pr-merges-to-main-verify-all`):**

1. Watch the release run triggered by the merge of this PR.
2. Confirm the `Verify deploy script completion` step reports `ci-deploy.sh completed successfully for v$VERSION` and exits 0 within the new 300s ceiling.
3. Confirm the downstream `Verify deploy health and version` step also passes (unrelated to this change, but confirms the bump didn't shift timing for the rest of the pipeline).

## Risks

- **Longer worst-case hold on the workflow runner.** If ci-deploy.sh genuinely hangs (never writes a terminal state), this step will now block for 300s instead of 120s. This is acceptable because:
  - `ci-deploy.sh` has an EXIT trap at line 96 that writes `"unhandled"` on any non-zero exit, so a real crash surfaces as `EXIT_CODE != 0` and the verify step's `*)` case exits 1 immediately (< 5s after the crash given INTERVAL_S=5).
  - Terminal-state writes for `lock_contention` (line 210), `insufficient_disk_space` (line 225), and `unhandled` (EXIT trap) all go through `final_write_state`, which touches `${STATE_FILE}.final` — caught on the next `/hooks/deploy-status` poll within 5s.
  - A hanging ci-deploy.sh is already a Sentry-worthy incident — spending 3 minutes to confirm it is cheap relative to the false-negative noise we're eliminating.
  - Observed runtime reference: the 2026-03-21 async-webhook learning documents Docker pull + container restart at 60-180s. ci-deploy.sh's full path (prune + pull + canary + health + promote + state-write) realistically reaches 120-240s on the current web-platform server for a cold cache. 300s gives a 25-150% safety margin; 120s gives 0-100% and was demonstrably insufficient on run 24583922171.
- **None for the retry path.** The rerun behavior is unchanged: `gh run rerun --failed` still re-POSTs to `/hooks/deploy`, which still fails `flock -n` if a deploy is in flight. The fix simply makes reruns rare because the first attempt will almost always complete within 300s.
- **No regression risk for other steps.** The change is an env value on one step. No other step in the workflow reads `STATUS_POLL_*` (confirmed via grep of the workflow file). The adjacent `Verify deploy health and version` step reads `HEALTH_POLL_*` — a separate namespace.
- **No Cloudflare edge timeout risk.** The `/hooks/deploy-status` endpoint is GET + signed, responds in < 1s (adnanh/webhook reads a JSON state file), and is well inside the Cloudflare 120s per-request limit. Each poll is an independent short request — the 300s window is wall-clock, not per-request.

## Rollback Plan

Trivial. Revert the line-101 value to `24` and push a follow-up commit. No state migrations, no infra changes.

## Non-Goals

- **Do not change `HEALTH_POLL_*` bounds.** The health-check step is already at 300s and has not exhibited the false-negative pattern.
- **Do not add Sentry alerting for verify-step timeouts.** The `::error::` line already surfaces in the GitHub Actions UI and triggers the post-merge monitor; adding Sentry is a separate observability decision out of scope here.
- **Do not refactor `ci-deploy.sh` lock semantics.** The `flock -n` + `lock_contention` protocol is correct for protecting production from concurrent deploys. The rerun failure is a consequence of the verify-step false negative, not a lock bug.

## Files to Edit

- `.github/workflows/web-platform-release.yml` (lines 100-102)

## Files to Create

- None.

## Domain Review

**Domains relevant:** none (infrastructure/tooling change — CI polling window tuning only; no user-facing surface, no product decisions, no legal/finance/content implications).

No cross-domain implications detected — infrastructure/tooling change.

## Resume Prompt

```text
Resume prompt (copy-paste after /clear):
/soleur:work knowledge-base/project/plans/2026-04-17-fix-verify-deploy-step-timeout-plan.md. Branch: feat-one-shot-2519. Worktree: .worktrees/feat-one-shot-2519/. Issue: #2519. Plan ready for implementation — single-line env value change in .github/workflows/web-platform-release.yml (STATUS_POLL_MAX_ATTEMPTS 24→60).
```
