# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-09-chore-ci-concurrency-and-workflow-run-deploy-plan.md
- Status: complete
- Plan artifact: recovered (selector=branch)

### Errors
- The planning subagent terminated early on an Anthropic **session rate limit** (HTTP 429,
  `claude-opus-5`, resets 19:00 Europe/Paris) while emitting its Session Summary. Planning itself
  had already finished: the plan carries `## Acceptance Criteria`, `## Test Scenarios` and
  `## Plan Review Revisions`, and was committed as `91ca86bc9`. Recovered from disk per the
  one-shot partial-artifact contract; planning was NOT re-spent.
- Scope verified clean: `git diff origin/main...HEAD --name-only` is confined to
  `knowledge-base/project/{plans,specs}/` plus the hook-generated `knowledge-base/INDEX.md`.
  No workflow, source or ADR file was touched by the planning phase.

### Decisions
- **D1 — concurrency key changes, justified on semantics not wall clock.** Per-SHA grouping on
  `main` makes the gated quantity a property of the SHA being gated. The queue binds on only 20%
  of runs, so the speed framing was rejected; `cancel-in-progress` is unchanged and nothing is
  cancelled on `main` under either key.
- **D2 — `release` stays on `push`; only the deploy chain moves to `workflow_run`.** `release`
  beat `await-ci` in 14/14 runs, so `max(release, CI)` is empirically already `CI`. Every
  `needs.release.*` predicate must be reconstructed at EQUAL STRENGTH (job conclusion, never the
  existence of a release object) or #5806 does not ship in this shape — declared a stop condition.
  `resolve-target` is a five-state machine, not a lookup, because `workflow_run` inherits neither
  of the two existing path gates.
- **D3 — LPT is DEFERRED** (#7931 part 3). Not a drift-story failure: LPT does not deliver the
  property it was chosen for (a duration refresh re-rolls other labels), and `_shard_selects`
  cannot compute it — it is called once per streaming registration and cannot see the live set at
  first call. Parts 1+2 ship; Phase C still lands the `TEST_TIMING_LOG` binding so the next attempt
  has CI-measured data. The one-line K=5 alternative (K=3 -> 20.73 min, K=5 -> 10.77 min) goes in
  the deferral issue.
- **D5 — Phase D removes the ordering guarantee Phase E's P6 depends on.** Neither issue
  anticipates this. Mitigated by a monotonic-version precondition on `deploy` (refuse the swap when
  the resolved version is `<=` the live version) — explicitly NOT the rejected ADR-072 Phase C
  git-ancestry guard.
- **D4 — ADR-212's creep detector is relocated, not deleted.** Soft ceiling derived from
  `DRIFT_SUSTAINED_THRESHOLD_MIN` (already CI-asserted by B9), not from a fresh unowned constant.
  `CI_BUDGET_MIN = 72` and `CI_DECLARED_PATH = 70` were conflated in an earlier revision and are
  now pinned to separate subjects.
- **#5806 item 4** (gate the "v0.X.Y released!" announcement on deploy-success) is deferred on
  MECHANISM but filed at **P2 with a dated trigger**, because the topology change makes the
  misleading-announcement scenario *easier* to hit silently.

### KNOWN STALE ROW — carry into work
`## Files to Edit` still lists `scripts/test-all.sh` -> "`_shard_selects` body -> LPT with
round-robin fallback (C)". That row was NOT updated when plan review deferred LPT in Decision 3.
The sibling row for `scripts-shard-totality*` WAS updated ("not edited — Guard 2 withdrawn with the
LPT deferral"), which confirms the miss. **Decision 3 governs: do NOT implement LPT.** Phase C is
`TEST_TIMING_LOG` binding + artifact upload only. Fix the stale row as part of Phase C.

### Components Invoked
- soleur:plan, soleur:deepen-plan (plan-review revisions are recorded in the plan's
  `## Plan Review Revisions` section)

## Collision Gate (Step 0a.5)
- #7931 OPEN, #5806 OPEN; both `closedByPullRequestsReferences` empty.
- Merged PRs surfaced by the linked/body probes are cited PREDECESSORS: #7907 closes 7902,
  #5798 closes 5795. Neither closes a target.
- Scope confirmed undone in code on `origin/main`, not inferred: `ci.yml:38` is still
  `group: ${{ github.workflow }}-${{ github.ref }}`; `ci.yml:1182` is still the bare
  `echo "$shard: $result" >&2`; `web-platform-release.yml:103` still defines `await-ci`.
- Plan frontmatter `closes: [7931, 5806]` matches the gated set — no re-target, so the
  post-planning re-probe is satisfied.
