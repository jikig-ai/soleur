Deferred follow-up from #12626 / PR #12654 (epic #11556 lever A). Deliberately not filed at ship time.

Mandated-By: epic #11556 AC chain — `knowledge-base/project/plans/2026-11-12-ci-epic-11556-ac-chain-followthrough-plan.md` §2; ruling precedent in `knowledge-base/project/specs/feat-one-shot-12626-webplat-monitor-timeout/decision-challenges.md` (the dedicated-leg split was ruled over a per-shard timeout bump; the applicability classifier was named as the follow-up).

## Problem

PR #12654 moved the three web-platform mutation batteries off `test-web-platform` legs into a dedicated 3-leg matrix job `test-webplat-mutations` (ci.yml). The job runs unconditionally on every event that fans out `test-scripts`-style legs — including knowledge-base-only PRs, where it pays ~3 × 25–30 leg-minutes of runner time for zero signal (the mutation subjects are runner/workflow/table surfaces no markdown row can reach).

This is the same skip-safely shape #9729 solved for the shard-totality battery with `scripts/ci-shard-totality-classify.sh`.

## Scope

Two items, one issue:

1. **In-job applicability classifier for `test-webplat-mutations`.** A step that emits `run_battery=true|false`; the mutation matrix legs execute only on `true`, and the job stays `success` on a safe skip so the `test` aggregator is unchanged.
2. **The deferred `--rows` split of `approval-guard1-mutation`.** It was the dominant leg (1493 s post-split vs ~235/349 s for the other two); the merge left row-level splitting as follow-up. Re-price from fresh `suite-timings` artifacts before deciding whether the split is still warranted — the classifier may shrink the paid surface enough that the split stops mattering.

## Classifier contract (modelled on `ci-shard-totality-classify.sh`)

- **Base-sourced:** CI judges by the BASE ref's copy (`git show`), so a PR cannot weaken the gate it is judged by.
- **Fail-closed allowlist, never a denylist.** Initial allowlist = the #9729 precedent shape: `pull_request` event only, non-empty `git diff --raw` row set, every row well-formed, status A/M with `100644` new mode, path = markdown under `knowledge-base/` or a root-level `*.md`. A markdown file is a mutation subject of nothing.
- **Everything else runs all batteries:** any other path, any non-doc row grammar, empty diff, unknown argv (non-zero, never a fabricated skip), and every non-`pull_request` event (`merge_group`, `push`, `workflow_dispatch`, `schedule` — the full-battery authority per ADR-276).
- **Recorded skip notice:** the job prints a `SKIP <reason>` line the health monitor can enumerate; a silent skip is indistinguishable from a dropped leg (the exact defect the 18-leg census in `EXPECTED_LEGS` exists to catch — reconcile the two before landing).
- **Reuse vs sibling:** prefer extending `ci-shard-totality-classify.sh` (a `--job test-webplat-mutations` mode or a shared lib) only after checking the parity-suite implications — `plugins/soleur/test/ci-shard-totality-skip.test.sh` pins the byte-duplicated row-parse block against `ci-e2e-classify.sh`, so a third consumer either joins the parity pin or forks a documented sibling.
- **Census before widening:** before any allowlist widening, enumerate the mutation-subject path set (the runner, shard tables, ci.yml/main-health-monitor.yml surfaces the batteries mutate) and prove the widened rows cannot reach it.

## Acceptance

- `test-webplat-mutations` skips (green, with recorded notice) on a markdown-only PR; runs in full on a mixed PR, an empty-diff event, `merge_group`, `push`, and `workflow_dispatch`.
- The `test` aggregator's conclusion and leg-count contract are unchanged under both arms.
- Fixture suite covers: doc-only → skip; script-row-under-knowledge-base → run; unknown path → run; mode-irregular row → run; non-PR event → run; broken classifier argv → non-zero.
- If the `approval-guard1` re-price still shows the leg over the ~20 min internal goal after classifier savings, file (or land) the `--rows` split as part of this issue.

Ref #11556 Ref #12626 Ref #9729
