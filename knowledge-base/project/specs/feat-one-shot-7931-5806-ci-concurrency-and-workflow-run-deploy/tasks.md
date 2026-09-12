# Tasks — CI concurrency key, aggregator diagnosis, and the workflow_run deploy gate

Derived from `knowledge-base/project/plans/2026-09-09-chore-ci-concurrency-and-workflow-run-deploy-plan.md`
(post-plan-review). Closes #7931 and #5806. Part 3 of #7931 (LPT) is **deferred** — see plan
§Deferrals.

Phases are ordered so the deploy gate is never left measuring a quantity that no longer exists, and
so each commit is independently revertible in this order.

---

## 1. Preconditions (no behaviour change)

- [ ] 1.1 Grep every `*.test.sh` / `*.test.ts` for assertions on the literals about to change:
      `git grep -nE "github\.workflow.*github\.ref|Aggregate shard results|\bawait-ci\b|\bCEILING_S\b|shard: \[" -- '*.test.sh' '*.test.ts' 'scripts/' 'plugins/'`.
      Add every hit to the edit set before touching a workflow. Bound `CEILING_S` on the left — the
      four `IN_FLIGHT_CEILING_S` hits in `apps/web-platform/infra/ci-deploy*.test.sh` are a
      different constant.
- [ ] 1.2 Verify each prescribed glob matches ≥1 real file (`git ls-files | grep -E …`).
- [ ] 1.3 Re-probe the next-free ADR ordinal across **all** `origin/*` refs. ADR-213 is already
      claimed on a pushed branch; ADR-214 is provisional.
- [ ] 1.4 Confirm `bash scripts/test-all.sh --enumerate scripts` runs; record the live suite count.
- [ ] 1.5 Confirm `TEST_TIMING_LOG` is bound in no workflow (`git grep -n TEST_TIMING_LOG -- .github/`).
- [ ] 1.6 On a scratch branch, delete the `await-ci` job and run
      `bash scripts/prod-version-drift-check.test.sh` to capture B8e's and B9's exact failure text
      before writing Phase E. Both are certain reds.

## 2. Phase A — premise correction (docs only)

- [ ] 2.1 Rewrite `ci.yml`'s `NOTE ON DISPATCH — RETRACTED TWICE` block as a third revision that is
      the measurement, not a mechanism: the 20%/80% cohort split, queue median 393s / max 1245s,
      4s free-run dispatch, 332s/1708s within-run spread, and the reproduction command. State that
      revisions 1 and 2 were each right about a different cohort.
- [ ] 2.2 Amend ADR-212 `Consequences → Named residual`: replace "the queue is the dominant term"
      with the population statistic; correct the "would break the audit trail" clause.
- [ ] 2.3 Do **not** edit ADR-208. Record the mis-citation in the PR body.

## 3. Phase B — the `test` aggregator names the measured cause

- [ ] 3.1 RED first: add `plugins/soleur/test/ci-test-aggregator-diagnosis.test.sh`, extracting and
      executing the `Aggregate shard results` `run:` body over synthetic `needs.*.result` triples
      (the pattern `scripts/prod-version-drift-check.test.sh` already uses).
- [ ] 3.2 Replace the bare `echo "$shard: $result" >&2` with the five-arm branch over the result
      triple (FAILED / SUPERSEDED / STOPPED ALONE / CANCELLED-unknown / SKIPPED). No checkout, no
      `gh api`, no new script, no `0.98` constant.
- [ ] 3.3 Make `SUPERSEDED` event-conditional — it is structurally unreachable on `main` after
      Phase D.
- [ ] 3.4 Keep every non-success leg setting `fail=1` and the job exiting 1.
- [ ] 3.5 Rewrite the stale `#7902 AC5` byte-unchanged comment above `timeout-minutes: 10`.
- [ ] 3.6 Guard 6 rows, including the `push`-fixture SUPERSEDED row and the never-swallow row.

## 4. Phase C — timing collection (LPT deferred)

- [ ] 4.1 Bind `TEST_TIMING_LOG` on each `test-scripts` leg; upload one artifact per shard.
- [ ] 4.2 File the LPT deferral issue carrying the six designed mutation rows and the three
      constraints (no-arg `_shard_selects`; `skip_suite` label parity; CI-only bootstrap), plus the
      K=5 alternative.
- [ ] 4.3 Do **not** re-simulate K in this PR — three new glob-discovered suites shift every ordinal.
- [ ] 4.4 Confirm `scripts-shard-totality*.sh` are **unedited** and still green.

## 5. Phase D — the concurrency key

- [ ] 5.1 Change `concurrency.group` to
      `${{ github.workflow }}-${{ github.event_name == 'pull_request' && github.ref || github.sha }}`.
      Leave `cancel-in-progress` byte-unchanged.
- [ ] 5.2 Rewrite the block comment: what the key means, that nothing is cancelled under either key,
      that the audit trail is preserved, that the change is semantic, and what `merge_group` and
      `workflow_dispatch` now get.
- [ ] 5.3 Add `plugins/soleur/test/ci-concurrency-key.test.sh` (Guard 1: 3 rows + harness rows,
      including the `merge_group` must-pass row).
- [ ] 5.4 Re-derive **no** ceiling — record why (D.4). Do not lower `CEILING_S`.

## 6. Phase E — the `workflow_run` deploy gate

- [ ] 6.1 Add `on: workflow_run: {workflows: ["CI"], types: [completed], branches: [main]}`.
- [ ] 6.2 Add `resolve-target` on the `workflow_run` **and** `workflow_dispatch` arms. Outputs:
      `head_sha`, `version`, `tag`, `docker_pushed`, `mirror_verified`, `released`, `should_deploy`,
      `skip_reason`. Apply the event filters, the `^[0-9a-f]{40}$` check, and the five-state release
      resolution. Pin the lookup to `?event=push&head_sha=<sha>` and exclude `github.run_id`.
- [ ] 6.3 Convert all **ten** broken context consumers: the 9 `${{ github.sha }}` sites plus
      `live-verify`'s `BEFORE_SHA: ${{ github.event.before }}` (which does not exist on
      `workflow_run`). Do not filter on `github.ref` — it is vacuous under this trigger.
- [ ] 6.4 Rehome `verify-doppler-secrets`, `migrate`, `verify-migrations`, `deploy`, `live-verify`
      onto the new arm. Delete `await-ci` and `notify-slow-ci`.
- [ ] 6.5 Specify `notify-gated`'s new `if:` verbatim on `conclusion != 'success'` plus the two
      failure skip-reasons; the clean-skip states must not fire it.
- [ ] 6.6 Split the run-outcome notification into `release-outcome` (push arm) and `deploy-outcome`
      (`workflow_run` arm); remove `R_AWAIT_CI` from the `env:` block
      (`scripts/lint-workflow-step-env-refs.test.sh` B1e asserts on its shape).
- [ ] 6.7 Update `apps/web-platform/infra/web-1-swap-concurrency-parity.test.sh` in lockstep — it
      asserts the total `group: web-1-swap` count `== 8` plus release-job membership.
- [ ] 6.8 Preserve the `workflow_dispatch` escape hatch: keep the `skip_deploy` conjunct
      byte-for-byte on both jobs; rewrite the `allow_unmirrored_reason` note (it currently says the
      override bypasses `await-ci`).
- [ ] 6.9 Implement the release-appearance wait as a **liveness poll** on the release run's status
      (no ceiling, no `RELEASE_WAIT_S`).
- [ ] 6.10 Implement the relocated soft-ceiling warning on `resolve-target` (never on `deploy`,
      which may not check out). Derive from `DRIFT_SUSTAINED_THRESHOLD_MIN` minus the three
      downstream ceilings; assert `CI_DECLARED_PATH <= CI_BUDGET_MIN`.
- [ ] 6.11 Add the monotonic-version precondition on `deploy` (Decision 5).
- [ ] 6.12 Rewrite `plugins/soleur/test/await-ci-ceiling-invariants.test.sh` in the **same commit**;
      rename to match the new subject and sweep every citation of the old name (`ci.yml`, the
      learning file; leave archived plans). Keep `MIN_ROWS >= 14` as a computed floor.
- [ ] 6.13 Rewrite B8e's `DEPLOY_NEEDS_CLOSURE` pin and B9's critical-path extraction for the
      cross-run topology; reconcile the stale `max(release 60, await-ci 60) … = 195` comment in
      `web-platform-release.yml`.
- [ ] 6.14 Sweep the run-doubling consumers (Guard 8): `plugins/soleur/skills/postmerge/SKILL.md`,
      `scripts/watch-live-verify-pass.sh`, `plugins/soleur/skills/ship/SKILL.md` (its admin-merge
      guidance **inverts**), the admin-merge learning file, and the `apps/web-platform/Dockerfile`
      comment.
- [ ] 6.15 Add `plugins/soleur/test/workflow-run-deploy-invariants.test.sh` (Guards 3, 4, 5, 7, 8)
      with the full fixture set, including the docs-only-push must-PASS row.

## 7. Phase F — ADR, C4, deferrals

- [ ] 7.1 Write ADR-214 (re-probe the ordinal first).
- [ ] 7.2 Amend ADR-072 (option 3 adopted, fail-open closed) and ADR-212 (Decision 4 relocated).
- [ ] 7.3 Run `bash plugins/soleur/test/c4-count-parity.test.sh`; fix any moved count in the same
      commit. No `.c4` element/relationship/view edit is expected.
- [ ] 7.4 File the deferral issues (LPT; #5806 item 4 at **P2** with a dated trigger) and post the
      reciprocal note on #7942.
- [ ] 7.5 Enrol `scripts/followthroughs/ci-concurrency-cohort-7931.sh` with the
      `soleur:followthrough` directive and the `follow-through` label.

## 8. Verification

- [ ] 8.1 All pre-merge ACs (AC1–AC19) green.
- [ ] 8.2 Full battery at `/ship` Phase 4 (ADR-183).
- [ ] 8.3 Post-merge AC-P1..AC-P10 executed as `gh api` queries by the pipeline.
- [ ] 8.4 Render `decision-challenges.md` into the PR body and file the `action-required` issue.
