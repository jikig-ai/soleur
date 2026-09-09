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

## Phase 0 preconditions — RE-DERIVED, two plan corrections

- **ADR ordinal: the plan's `ADR-214` is CLAIMED.** Phase 0.3's all-refs probe (not just `ls` over
  `main`) shows ADR-213 taken by the pushed branch `feat-one-shot-7946-7947-sentry-org-token-and-
  snapshot-redaction` and ADR-214 by `feat-one-shot-7898-7055-credfwd-plugins-bs-pin-byok-fixture`.
  **The free ordinal is ADR-215**, and that is what the shipped comments cite.
- **Live suite count is 386 registrations**, not the 376 `ci.yml`'s K-table stanza states
  (`bash scripts/test-all.sh --enumerate scripts`). This PR adds 2 more, taking it to 388. K is
  NOT re-simulated here (Phase C.3), so the stale figure is carried into the deferral issue rather
  than propagated as current.
- **Phase 0.5 confirmed:** `TEST_TIMING_LOG` was bound in NO workflow, so Phase C's premise holds.
- **Phase 0.1 surfaced no new Files-to-Edit entries.** `IN_FLIGHT_CEILING_S`
  (`ci-deploy-wrapper.test.sh`, `ci-deploy.test.sh`) is the `deploy` job's poll-window constant,
  unrelated to `await-ci`'s `CEILING_S`, and survives rehoming unchanged.
  `scripts-shard-totality-mutations.sh` pins `shard: ["1/3",...]`, which C.3 leaves alone.
  `TC_RUNTIME_CEILING_S` in `scripts/lib/test-contention.sh` is a third, unrelated constant.

## Measurement re-derivation (Phase A.1) — the plan's figures do NOT fully reproduce

Re-ran §Measurement's own command before writing its numbers into a comment that has been
retracted TWICE. Result over the plan's stated window (2026-09-07T09:02Z .. 2026-09-09T14:22Z):

| figure | plan | re-derived | verdict |
|---|---|---|---|
| population | 35 | **29** | differs |
| occupied cohort n | 7 (20%) | 7 (**24%**) | n exact; % differs via denominator |
| occupied first-job | med 460s max 1249s | med 460s max 1249s | **exact** |
| occupied queue | med 393s max 1245s | med 393s max 1245s | **exact** |
| occupied time-to-test | med 2438s max 3365s | med 2438s max 3365s | **exact** |
| drained first-job | med 4s max 731s | med 4s max 731s | **exact** |
| drained spread (needs-less jobs) | med 332s max 1708s | med **412s** max 1708s | max exact, median differs |
| all spread | med 218s max 1708s | med **292s** max 1708s | max exact, median differs |

Every MAXIMUM and the ENTIRE occupied cohort reproduce to the second; the population and two
medians do not. Tested and REJECTED the obvious mechanism — the plan's `sort -r` (no `-u`) across
paginated calls double-counting — there are zero duplicate run ids. Cause of the 6-run delta not
established. The shipped comment therefore states **cohort shape**, publishes the command with
`sort -ru`, commits the raw `jobs.tsv`, and tells the next reader not to cite a median without
re-running. **AC2 is amended accordingly** (it required the literal "20%/80%" split and "both cited
medians"); satisfying it verbatim would have meant writing figures I could not reproduce into the
one comment in this repo with a two-retraction history.

## E.9 determination — run BEFORE any job deletion, as the plan requires

- **B9 is NAME-KEYED and would go RED on a correct change.** `scripts/prod-version-drift-check.test.sh`
  computes `crit = max(release_ceiling, job_timeout("await-ci"))`, and `job_timeout` returns
  `DEFAULT_JOB_TIMEOUT_MIN = 360` when the job is ABSENT. Deleting `await-ci` therefore yields
  `max(60,360) + 30 + 15 + 90 = 495 > 207` and reds B9 on the very change that is correct. It is a
  lockstep edit, not a passenger.
- **B8e pins the topology as a LITERAL**: `"await-ci,migrate,release,verify-doppler-secrets,verify-migrations"`.
  Phase E drops `await-ci`, moves `release` out of the closure entirely (different run) and adds
  `resolve-target`, so this literal must be re-derived deliberately in the same commit.

## Phase E — BLOCKED on a structural fact the plan did not have

Decision 2 declares a stop condition: *"If any predicate cannot be reconstructed at equal strength,
#5806 does not ship in this shape."* Two measured facts make the prescribed mechanism unreachable:

1. **The REST jobs API does not expose job `outputs`.** Verified against a real run — the job object's
   key set is exactly `[check_run_url, completed_at, conclusion, created_at, head_branch, head_sha,
   html_url, id, labels, name, node_id, run_attempt, run_id, run_url, runner_group_id,
   runner_group_name, runner_id, runner_name, started_at, status, steps, url, workflow_name]`. There
   is no `outputs` key anywhere in the payload. So `needs.release.outputs.{version,tag,docker_pushed,
   mirror_verified}` — read at seven sites — cannot be reconstructed cross-run from the API.
   The job CONCLUSION *is* available, so predicate 1 alone is reachable.
2. **`release` is a reusable-workflow call, so its API job name is `release / release`.** A lookup
   keyed on the plan's literal `release` returns ZERO rows (measured). A resolver or guard built on
   that name would match nothing and fail OPEN — the empty-haystack class.

Routed to the `soleur:engineering:cto` agent as an architecture fork (artifact hop vs. release-object
read vs. honour the stop condition), per the work-skill rule that a blocked plan mechanism with
material trade-offs is the CTO's call and not the operator's.

## LEFTHOOK=0 commit 313e39e31 — every bypassed hook discharged explicitly

The hooked attempt was killed by the OOM reaper mid-`tsc --noEmit` (30 GB box at
2 GB available, load 23, six sibling worktree sessions). It left NO stale
`index.lock` and NO orphaned children, and the 17-path staged set was intact, so
the recovery was a plain re-commit rather than an index repair. Per the work-skill
rule, the bypassed hooks are discharged here rather than assumed:

| hook | how discharged | result |
|---|---|---|
| `gitleaks-staged` | `gitleaks git --log-opts=-1` over the commit | no leaks, 22.5 kB scanned |
| `markdown-lint` | the repo's **pinned single invoker** (`scripts/markdown-lint.sh`), NOT an ad-hoc runner | **5 files clean** |
| `generate-kb-index` | generator re-run | kb index unchanged by this diff |
| `lint-infra-no-human-steps` | ran on the prior commits covering the same workflow files | OK |
| `web-platform-typecheck` | see below | not applicable to this diff, PROVEN |

**The typecheck is discharged by proof, not by skipping it.** The commit's only
typecheck-relevant file is `apps/web-platform/test/helpers/install-vi-waitfor-floor.ts`,
and the change is comment-only. Verified mechanically rather than by eye — strip
`//` and `/* */`, normalise whitespace, compare: **472 == 472 bytes, byte-identical
executable code**. `tsc --noEmit` output is therefore unchanged by construction, so
running it would have re-confirmed a result the diff cannot move. It is also the run
the OOM killed, and re-running a 15-minute full typecheck at 5 GB available risks a
second kill for no information.

**Instrument note worth keeping.** A first pass used `npx markdownlint-cli2` and
reported 2 findings. Both were PRE-EXISTING on `origin/main` (identical count; only
the line numbers moved, by the addendum's 53 lines) — and more importantly `npx`
resolves the LATEST linter rather than the pinned one, which is exactly the
unpinned-resolver drift #7927 fixed and which `lefthook.yml`'s own comment warns
about. The repo's pinned invoker is the authority and reports clean. Reaching for
`npx` was the wrong instrument, and it produced a finding that was not a regression.
