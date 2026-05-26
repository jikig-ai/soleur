---
spec: feat-one-shot-3508-shared-log-rotation
plan: knowledge-base/project/plans/2026-05-10-feat-shared-log-rotation-primitive-plan.md
issue: 3508
---

# Tasks: Shared Log Rotation Primitive

## 0. Pre-flight & Branch Reconcile

- 0.1 Verify PR #3495 state (`gh pr view 3495 --json state,mergedAt`).
- 0.2 Run code-review overlap grep against open `code-review`-labeled issues for each Files-to-Edit path.
- 0.3 Reconcile `.gitignore` state (pre-#3495 wildcards vs post-#3495 broad wildcards) — record in spec.md.
- 0.4 Decide whether Phase 2 wires `agent-token-tee.sh` (only if #3495 has merged) or defers it to fast-follow.

## 1. Shared Rotator Helper

- 1.1 Create `.claude/hooks/lib/log-rotation.sh` with `rotate_if_needed` API (size + age thresholds, atomic rename, flock-x, kill-switch, repo-root override).
- 1.2 Honor env vars: `LOG_ROTATION_DISABLE`, `LOG_ROTATION_SIZE_BYTES`, `LOG_ROTATION_AGE_DAYS`, `LOG_ROTATION_FLOCK_TIMEOUT_S`, `LOG_ROTATION_REPO_ROOT`.
- 1.3 Repo-root resolution via `cd -P / pwd -P` mirroring `incidents.sh:33` and `skill-invocation-logger.sh:40`.
- 1.4 `bash -n` and `shellcheck` clean.

## 2. Wire All Three Sinks (Failing-test-first)

- 2.1 Write failing test `log-rotation.test.sh` T1-T12 BEFORE wiring (`cq-write-failing-tests-before`).
- 2.2 Edit `.claude/hooks/lib/incidents.sh` — insert `rotate_if_needed` call between file-creation guard (line 83) and jq line construction (line 86).
- 2.3 Edit `.claude/hooks/skill-invocation-logger.sh` — same insertion between line 60 and line 62.
- 2.4 Edit `.claude/hooks/agent-token-tee.sh` — same insertion (conditional on #3495 merge state).
- 2.5 Confirm aggregator `AGGREGATOR_ROTATE=1` path retained as defense-in-depth (no edit to `scripts/rule-metrics-aggregate.sh`).

## 3. .gitignore Reconcile (Conditional)

- 3.1 If pre-#3495 state: broaden patterns to `.session-tokens*`, `.skill-invocations*`, `.rule-incidents*`.
- 3.2 If post-#3495 state: skip — already broad.
- 3.3 Verify `git check-ignore` on each rotation suffix returns 0.

## 4. Tests

- 4.1 T1: No rotation when below thresholds.
- 4.2 T2: Rotates on size threshold.
- 4.3 T3: Rotates on age threshold.
- 4.4 T4: Configurable thresholds via env.
- 4.5 T5: Atomic-rename failure leaves active intact.
- 4.6 T6: Concurrent writer + rotator does not tear lines (100-line bg writer).
- 4.7 T7: Kill-switch `LOG_ROTATION_DISABLE=1` short-circuits.
- 4.8 T8: Existing archive — collision suffix appends.
- 4.9 T9: Subshell-reassignment trap inspection (Sharp Edge from `2026-04-18`).
- 4.10 T10: Survives missing `flock` (macOS dev).
- 4.11 T11: Survives missing `gzip`.
- 4.12 T12: Schema invariant — archive `.gz` decompresses to valid JSONL.
- 4.13 T13: `incidents.test.sh` 1000-call rotation integration.
- 4.14 T14: `skill-invocation-logger.test.sh` 1000-call rotation integration.
- 4.15 T15: `agent-token-tee.test.sh` 1000-call rotation integration (conditional).
- 4.16 T16: `rule-metrics-aggregate.test.sh` aggregator's `AGGREGATOR_ROTATE=1` path still works against pre-rotated empty file.

## 5. Documentation

- 5.1 Update `.claude/hooks/README.md` `## Rotation` section — describe per-write helper, aggregator's defense-in-depth role, env-var configuration.
- 5.2 Add `## Library API` subsection documenting `rotate_if_needed`.
- 5.3 Capture learning at `knowledge-base/project/learnings/<topic>.md` — design decisions (atomic-rename vs cat-truncate, per-write vs per-cron, source vs exec, macOS flock).

## 6. PR & Ship

- 6.1 Verify `Closes #3508` only on its own body line.
- 6.2 Run `bash scripts/rule-metrics-aggregate.test.sh` — green.
- 6.3 Run `bash .claude/hooks/log-rotation.test.sh` — green.
- 6.4 Run `bash .claude/hooks/incidents.test.sh` — green.
- 6.5 Run `bash .claude/hooks/skill-invocation-logger.test.sh` — green.
- 6.6 If applicable: `bash .claude/hooks/agent-token-tee.test.sh` — green.
- 6.7 `/soleur:compound` before commit per `wg-before-every-commit-run-compound-skill`.
- 6.8 `/soleur:ship`.
