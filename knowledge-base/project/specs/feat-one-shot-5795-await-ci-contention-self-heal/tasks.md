---
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-30-fix-await-ci-adaptive-wait-deploy-self-heal-plan.md
issue: 5795
---

# Tasks: Adaptive CI-signal wait for the prod deploy gate (#5795)

Derived from `2026-06-30-fix-await-ci-adaptive-wait-deploy-self-heal-plan.md`. Verify the live
constants (ceiling, timeout) and ADR ordinal at write time — do not freeze plan estimates.

## Phase 1: Setup & measurement

- [ ] 1.1 Read `.github/workflows/web-platform-release.yml` (`await-ci` 48-107, `migrate` 109-128, `deploy` 282-575) and `ci.yml:418` (`test` aggregator) to ground the edit.
- [ ] 1.2 Measure realistic worst-case CI-under-contention duration: `gh run list --workflow=ci.yml --branch main --limit 50 --json createdAt,updatedAt,conclusion` → size the ceiling to exceed observed p100 + margin. Record the chosen `MAX_ATTEMPTS`/`INTERVAL_S`/`timeout-minutes` and the data they came from.
- [ ] 1.3 Confirm next-free ADR ordinal: `git ls-files | grep -i 'ADR-072'` (bump if taken; corpus has duplicate ordinals).

## Phase 2: Core implementation — `web-platform-release.yml`

### Phase A — adaptive `await-ci` (core)
- [ ] 2.1 Evaluate the `test` check-run verdict at the TOP of each loop iteration (success→exit 0; non-success→exit 1). [AC2, AC4]
- [ ] 2.2 Replace the fixed-window "missing⇒timeout" with ci.yml-run liveness: query `actions/workflows/ci.yml/runs?head_sha=$SHA&event=push&per_page=20`, select max-`created_at` run, keep waiting while `status != completed` (blocklist, NOT an allowlist of queued|in_progress). [AC1]
- [ ] 2.3 Add the bounded post-completion reconciliation grace (`RECONCILE_ATTEMPTS`) for the ci-completed-but-`test`-check-run-lagging race. [AC3]
- [ ] 2.4 Retry-guard the runs query (`if ! resp=$(gh api …)`) so a transient error `continue`s and never satisfies `total_count==0` (replaces the current `|| echo "0"`); guard `jq '.workflow_runs[0]'` null via `total_count`/array-length first. [AC6]
- [ ] 2.5 Preserve the existing cancelled-shadow check-run selector (`sort_by(.started_at)|last`) and the 60s grace + zero-run fast-fail. Select the run via `per_page=1` + `event=push`. (Do NOT add a stale-attempt timestamp-reconciliation branch — cut as YAGNI.)
- [ ] 2.6 Raise `MAX_ATTEMPTS`/ceiling AND the job `timeout-minutes` together so `timeout-minutes*60 > (MAX_ATTEMPTS + RECONCILE_ATTEMPTS)*INTERVAL_S + INTERVAL_S`; no unbounded inner retry loop. Add an inline YAML comment at the ceiling constants ("do NOT lower without re-reading ADR-072"). [AC5]

### Phase B — gate `migrate` on `await-ci` (with `always()`)
- [ ] 2.7 `migrate.needs: [release, await-ci]`; `migrate.if` MUST lead with `always() &&` then `needs.release.outputs.version != '' && (needs.await-ci.result == 'success' || (github.event_name == 'workflow_dispatch' && needs.await-ci.result == 'skipped')) && (github.event_name != 'workflow_dispatch' || !inputs.skip_deploy)`. Document the corrected serialize-after-await-ci tail cost (NOT "no net cost") + the residual verify-doppler-secrets window in the job comment. [AC7]
- [ ] 2.7b Verify no fail-open: on push fail-closed await-ci, migrate→skipped and deploy stays blocked by its own `needs.await-ci.result=='success'`; on dispatch, await-ci skipped is tolerated. [AC8]

### Phase C — REJECTED (do NOT implement)
- [ ] 2.8 (none) Superseded-SHA guard rejected by deepen-plan review; out-of-order risk named in PR body + folded into the option-3 issue (Task 5.2). [AC9]

### Phase E — observability + fail-closed notification
- [ ] 2.9 Add an elapsed-seconds field (NEW distinct token, e.g. `elapsed_s=`, absent elsewhere in the file) to every `await-ci` poll line + a `::warning::` ("past 900s") when elapsed crosses the prior 900s threshold. Verify AC against the EXTRACTED await-ci step body, not a file-wide grep. [AC10]
- [ ] 2.10 Add a `notify-gated` job (`if: always() && needs.await-ci.result == 'failure'`) that posts "deploy gated — CI not green for <sha>, prod NOT updated" via the existing notification channel. [AC10b]

## Phase 3: Architecture record
- [ ] 3.1 Create `ADR-072` (or next-free) via `/soleur:architecture` with `## Decision` / `## Alternatives Considered` (options 1/2/3) / `## Consequences` (held-runner trade-off, migrate-gating, deferred option-3, residual >ceiling cliff). [AC11]
- [ ] 3.2 Confirm no `.c4` edit needed (enumeration in plan; `github` system + `engine -> github` edge already model the surface). [plan §Architecture Decision]

## Phase 4: Verification
- [ ] 4.1 `actionlint .github/workflows/web-platform-release.yml` passes. [AC12]
- [ ] 4.2 Extract the `await-ci` `run:` body → `bash -n` via `bash -c "$(extracted)"` (NOT on the `.yml`); optional `shellcheck`. [AC12]
- [ ] 4.3 Dry-run the loop branch decisions against synthesized jq fixtures for every spec-flow case (queued/waiting→wait; success→exit0; failure-while-in_progress→exit1; completed+test-missing→grace→fail-closed; completed/success+test-lag→grace→exit0; api-error→retry; empty array→guarded). [plan §Test Scenarios]
- [ ] 4.4 Arithmetic check `timeout-minutes*60 > MAX_ATTEMPTS*INTERVAL_S + INTERVAL_S`. [AC5]

## Phase 5: Post-merge / deferred
- [ ] 5.1 PR body uses `Closes #5795`. [AC14]
- [ ] 5.2 File the option-3 (`workflow_run: completed` deploy trigger) tracking issue with labels `domain/engineering` + `type/chore` + `priority/p3-low` and re-evaluation criteria. [AC15]
- [ ] 5.3 (read-only) After the next CI-under-contention squash-merge, `gh run view <release-run-id> --job await-ci` confirms await-ci waited past 900s then succeeded. [AC16]
