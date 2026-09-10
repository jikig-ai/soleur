---
title: "ci: main-push concurrency key, test-aggregator diagnosis, matrix-leg balance, and the workflow_run deploy gate"
date: 2026-09-09
slug: chore-ci-concurrency-and-workflow-run-deploy
branch: feat-one-shot-7931-5806-ci-concurrency-and-workflow-run-deploy
issue: 7931
closes: [7931, 5806]
lane: single-domain
type: chore
priority: P2
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

## Overview

Two CI-pipeline changes shipped together because they touch the same two workflow files and the
same measured quantity — `time-to-test`, the quantity ADR-212 established the deploy gate
actually measures.

**#7931** has three parts. `ci.yml` keys its concurrency group on `github.ref`, which is constant
on `main`, so a push that lands while its predecessor is still running queues behind it and the
deploy gate's measured quantity absorbs the predecessor's whole duration. The `test` aggregator
reports a bare result string, so a leg that blew its own declared budget and a leg cancelled by a
newer push read identically. And matrix-leg composition is a pure function of registration order,
so it re-rolls whenever a suite is registered.

**#5806** moves the web-platform prod deploy off the polling `await-ci` job onto a
`workflow_run: completed` trigger on `ci.yml` — ADR-072's recorded-and-deferred option 3. The
event carries the authoritative head SHA, so there is no fixed ceiling, no idle runner held for
the duration of a wait, and no out-of-order deploy.

The two are sequenced in one PR because #7931 part 1 changes *what the gate measures* and #5806
changes *whether the gate exists*. Landing them in the wrong order leaves a ceiling sized over a
quantity that no longer has the term it was sized for, or deletes the ceiling before the term is
removed.

---

## Research Reconciliation — Spec vs. Codebase

Every row below was measured or grepped at plan time. Three of the issue's premises did not
survive contact with `origin/main`; the plan's shape changes accordingly.

| Issue / brief claim | Reality on `origin/main` (2026-09-09) | Plan response |
|---|---|---|
| "#7902 wrote the dispatch-delay misattribution into **ADR-208**" | ADR-208 is *"A delegation refusal returns its reason, because a RAISE discards the audit row it was meant to write"* — a BYOK Postgres RPC decision with no CI, runner, dispatch or timing content anywhere in the file. The figures live in **ADR-212** (`ADR-212-deploy-gate-measures-its-own-gated-quantity.md`), the ADR #7902 actually produced. | **Do not touch ADR-208.** The correction target is ADR-212 and `ci.yml`. Recorded here so the mis-citation is not propagated a third time. |
| "Correct the misattributed dispatch-delay rationale in the ADR" | **Already done.** ADR-212 Decision 2 self-corrects verbatim: *"An earlier revision of this ADR recorded these figures as 'runner dispatch delay … tracked separately as runner-pool contention.' That was wrong, and it is corrected here rather than quietly dropped."* | The ADR correction is **not** work this plan performs. What this plan adds to ADR-212 is the *population* statistic its Consequences section lacks (next row). |
| "Real dispatch latency is ~1s; the rest is queue" (#7931 §1) | `ci.yml`'s own K-rationale comment (the block headed `NOTE ON DISPATCH — RETRACTED TWICE`) **already retracts this**, with measured counter-evidence: needs-less jobs — which a group release starts at the same instant — stagger across 15 minutes *inside one run*, on a run whose group had been empty for 12h10m. It closes by naming the falsifying experiment: *"do not replace this note with a third confident mechanism without measuring the start SPREAD within a single run."* | **The plan runs that experiment** (§Measurement) rather than asserting a third mechanism. Both prior notes turn out to be right about different runs. |
| "The queue is the dominant term" (implied by #7931 §1's consequence paragraph, and by ADR-212's `Named residual`) | Measured over 35 consecutive `main` push runs: the group is occupied at creation on **7/35 runs (20%)**, costing a median 393s / max 1245s. On the other 28 the first job starts a median of **4s** after creation, and the largest `time-to-test` in the whole window (4156s) came from a run whose group was **empty**. | #7931 part 1 is justified on **semantics**, not wall clock — see Decision 1. The wall-clock claim is downgraded to a measured, bounded, intermittent term, and a post-merge re-measurement is an AC. |
| "It raises peak runner concurrency — a resource ADR-072 Consequence #3 already treats as contended" | Confirmed and *strengthened*: the same measurement shows the runner pool is the binding constraint on 80% of runs (within-run start spread median 332s, max 1708s). | Treated as the primary risk of part 1, with a declared rollback trigger and a symmetric post-merge measurement. |
| ADR-212: the per-SHA key "would break the deliberate 'let prior runs finish so the audit trail stays intact' property" | Overstated. `cancel-in-progress` is already `false` for `push`; per-SHA grouping gives every run its *own* group, so nothing is cancelled under either key. What changes is that prior runs now finish **concurrently** rather than **serially**. The audit trail is preserved identically. | Stated explicitly in the new ADR and in the amended `ci.yml` comment, so the next reader does not inherit the overstatement. |
| "The `test` aggregator's loop is byte-unchanged (#7902 AC5)" (`ci.yml` comment above `timeout-minutes: 10`) | True today, and that comment documents a proof **this PR retires**. | The comment is rewritten in the same commit as the aggregator edit, not left asserting a preserved-byte property the diff falsifies. |
| "LPT needs a checked-in `label -> measured seconds` table … which will itself go stale" | The repo **already emits exactly that data**. `scripts/test-all.sh` `run_suite` writes `printf '%s\t%d%s\n' "$label" "$elapsed_ms"` to `$TEST_TIMING_LOG` on every `[ok]` suite, with two regression suites covering its field shape. `TEST_TIMING_LOG` is bound in **no** workflow — CI discards per-suite timings it already knows how to produce. | The table's producer is an existing mechanism, not a new one. See Cut List. This is what makes the drift story affordable (Decision 3). |
| "`max(build, CI)` parallelism is lost unless build/deploy are restructured" (#5806) | Measured: `release` completes before `await-ci` in **14/14** runs, median lead **+29.2 min**, minimum **+11.5 min**. `max(release, CI)` is empirically already just `CI`. | Decision 2 keeps `release` on `push` and moves only the deploy chain to `workflow_run`, so the parallelism is preserved by construction rather than restructured. |
| "`prod-version-drift-check.sh`'s critical path is `max(release 60, await-ci 72) + 30 + 15 + 90 = 207`" | Confirmed at `scripts/prod-version-drift-check.sh` (`DRIFT_SUSTAINED_THRESHOLD_MIN=207`), asserted by check **B9** in `scripts/prod-version-drift-check.test.sh` (*"B9 threshold >= release declared critical path"*). | Lockstep edit in Phase E. The 72 term is replaced by CI's declared to-`test` path; the *value* is expected to stay 207 — but B9's own extraction is re-run rather than reasoned about. |
| "`workflow_run` uses the event's authoritative `head_sha`" | Necessary but not sufficient. `web-platform-release.yml` has **9 `github.sha` consumers**, including `EXPECTED_SHA` (the wrong-image gate) and `live-verify`'s `if: github.event_name == 'push'` — the demonstrated fail-open ADR-072's amendment names. Under `workflow_run`, `github.sha` resolves to the **default-branch tip**. | Guard 3 (§Guard Contract) makes "no `workflow_run`-reachable path reads bare `github.sha`" a mechanically-driven-red property, not a review promise. |

---

## Research Insights

### Premise Validation (Phase 0.6)

Both target issues are **OPEN** with empty `closedByPullRequestsReferences` (`gh issue view 7931
--json state,closedByPullRequestsReferences`, same for 5806). Both carry `domain/engineering` +
`type/chore`; #7931 is `priority/p2-medium`, #5806 is `priority/p3-low`. The code both describe is
still live: `ci.yml`'s `concurrency.group` is `${{ github.workflow }}-${{ github.ref }}`, the
aggregator's `echo "$shard: $result" >&2` is intact, and `web-platform-release.yml` still defines
the `await-ci` job with `CEILING_S: "3600"`.

Three cited premises were **stale** and are corrected in the reconciliation table above: the
ADR-208 mis-citation, the already-performed ADR correction, and the "~1s dispatch / rest is queue"
mechanism that `ci.yml` itself has since retracted with counter-measurement.

**Mechanism-vs-ADR-corpus check.** `workflow_run`-triggered deploy is not an unconsidered idea and
not a rejected one — it is ADR-072's `## Alternatives Considered` **option 3**, explicitly
*deferred* to a tracking issue (#5806), and re-armed by ADR-212's `Relates to` line. The per-SHA
concurrency key is named verbatim in ADR-212's `Consequences` as the tracked follow-up. Both
mechanisms are therefore *owed*, not *re-proposed*. The one mechanism the corpus **rejects** is the
superseded-SHA "Phase C" guard, and this plan does not reintroduce it (§Non-Goals).

### Measurement (Phase 0.6c — value proposition, quantified)

Command that produced every figure below, reproducible verbatim:

```bash
# 1. enumerate main-push CI runs in the window
for p in 1 2 3 4; do
  gh api "/repos/{owner}/{repo}/actions/runs?event=push&branch=main&per_page=100&page=$p" \
    --jq '.workflow_runs[] | select(.name=="CI") | [.created_at,.id,.conclusion] | @tsv'
done | sort -r | awk -F'\t' '$1>="2026-09-07T00:00:00Z"' > ci-win.tsv

# 2. per-job start/complete for each (two-stage jq: `gh --jq` does NOT forward `--arg`)
while IFS=$'\t' read -r created rid concl; do
  gh api "/repos/{owner}/{repo}/actions/runs/$rid/jobs?per_page=100" > j.json
  jq -r --arg rid "$rid" --arg created "$created" \
    '.jobs[] | [$rid,$created,.name,(.started_at//""),(.completed_at//""),
                (.conclusion//""),(.runner_id|tostring),(.steps|length|tostring)] | @tsv' j.json
done < ci-win.tsv > jobs.tsv
```

Population: **35 consecutive `main` push CI runs**, 2026-09-07T09:02Z → 2026-09-09T14:22Z.
"Group occupied at creation" = the predecessor run's `test` job had not yet completed when this
run was created. Jobs with `runner_id: null` or zero steps are excluded (they never acquired a
runner and say nothing about availability) — the same exclusion `ci.yml`'s corrected dispatch note
applies.

| Cohort | n | first-job delay | within-run start spread | queue term | time-to-`test` |
|---|---|---|---|---|---|
| Group **occupied** at creation | 7 (20%) | med 460s, max 1249s | — | med **393s**, max **1245s** | med 2438s, max 3365s |
| Group **already drained** | 28 (80%) | med **4s**, max 731s | med **332s**, max **1708s** | 0 | med 2174s, **max 4156s** |
| All | 35 | — | med 218s, max 1708s | — | med 2196s, max 4156s |

Four findings, all load-bearing:

1. **#7931's evidence reproduces exactly.** The five queue-bound rows it cites (runs 34141448851,
   34143928519, 34147070945, 34149741403, 34152496134) are in this window with queue terms 405s,
   1245s, 740s, 68s, 0s, and each starts its first job within 1–4s of the predecessor's `test`
   completing. On 2026-09-07 15:16–17:58 five consecutive runs were queue-bound. The queue is real.

2. **It is not the dominant term across the population.** It binds on 20% of runs. On the other
   80% the first job starts in ~4s, and those runs produced the window's **worst** `time-to-test`.

3. **`ci.yml`'s current dispatch note is also right.** Median within-run start spread of 332s
   (max 1708s ≈ 28.5 min) across jobs a group release starts simultaneously cannot be a queue.
   Runner availability is the larger term overall.

4. **Therefore the honest model is additive, not either/or:**
   `time-to-test = queue (when the group is occupied) + runner availability + execution`,
   where the queue term is workload-dependent — large on a merge-burst day, zero on a normal one.

**Value proposition, stated honestly:** part 1 removes a measured term worth a median 393s on 20%
of runs, and removes it *unconditionally* rather than probabilistically. Its wall-clock saving in
the median case is **zero**. Its real value is semantic (Decision 1). It carries a measurable risk
of increasing contention on the pool that findings 2–3 identify as the binding constraint, and that
risk is measured post-merge with the same command (AC-P1..AC-P3).

Release-pipeline timings, same method over the 14 most recent `Web Platform Release` push runs:

| job | n | min | median | max |
|---|---|---|---|---|
| `release / release` | 14 | 5.78m | **7.11m** | 11.67m |
| `await-ci` | 12 | 18.32m | **35.07m** | 48.08m |
| `migrate` | 12 | 1.73m | 1.83m | 2.78m |
| `verify-migrations` | 12 | 0.93m | 0.99m | 1.32m |
| `deploy` | 12 | 1.03m | 1.10m | 1.23m |
| `live-verify` | 12 | 0.22m | 0.26m | 1.58m |

`release` finished before `await-ci` in **14/14** runs; median lead **+29.2m**, minimum **+11.5m**.

### Property List (Phase 0.6b)

What the ask is actually for, restated as observable outcomes:

- **P1** — A `main` push's CI run, and therefore its deploy gate, measures only its own SHA's CI.
- **P2** — When the required `test` check fails, its own output names the measured cause, so a
  reader can tell "CI is too slow" from "someone pushed again" without reconstructing it from the API.

- **P3** — Which matrix leg a suite lands on is a fact someone owns, not a consequence of where a
  file sorts; adding a suite does not re-roll the partition.

- **P4** — Every registered scripts-group suite runs on exactly one leg. *(Already held; must not
  regress.)*

- **P5** — The prod deploy fires on CI's real completion, however long CI took, with no fixed
  ceiling and no idle runner held.

- **P6** — The deploy deploys the SHA CI actually verified, in order.
- **P7** — The `workflow_dispatch` escape hatch still deploys.
- **P8** — CI creeping toward the pipeline's declared budget is visible on every release without SSH.
  *(ADR-212 Decision 4 installed this; #5806 must not silently delete it.)*

### Cut List (Phase 0.6b) — mechanisms removed before research

| Proposed mechanism | Property it would buy | Already covered by |
|---|---|---|
| A new per-suite duration measurement (parse `--- <label> ---` marks out of a job log, the method `ci.yml`'s K comment documents) | P3's data source | `scripts/test-all.sh` `run_suite` already writes `label \t elapsed_ms` to `$TEST_TIMING_LOG` (the `[ok]` branch), with two regression suites covering its field shape. It is set in **no** workflow — the mechanism exists and is simply unbound. Cut: bind `TEST_TIMING_LOG` on the leg and upload the artifact. |
| A scheduled workflow that regenerates the duration table on a cron and opens a PR | P3's refresh owner | The same run that consumes the table also produces the fresh timings. A same-run freshness comparison needs no scheduler. Cut. |
| A new "CI is getting slower" detector to replace `await-ci`'s soft ceiling | P8 | ADR-212 Decision 4's warning is *relocated*, not replaced — the same 0.7× derivation over a reference that stays owned (Decision 4). Cut the new detector. |
| A superseded-SHA guard on the deploy job ("Phase C") | P6 | The `workflow_run` event's `head_sha` gives P6 structurally. ADR-072 already designed and **rejected** Phase C. Cut, permanently — see Non-Goals. |
| A `workflow_call` input on `reusable-release.yml` to gate the release announcement on deploy-success | (#5806 item 4) | Under the new topology the announcement and the deploy live in different workflow runs, so this stops being a `needs:` edge. Cut from this PR and deferred with a filed issue (§Deferrals). |

### Files and anchors the plan depends on

- `.github/workflows/ci.yml` — `concurrency:` block; `test-scripts` job (`strategy.matrix.shard: ["1/3","2/3","3/3"]`, `timeout-minutes: 60`); the ~130-line K-rationale comment including `NOTE ON DISPATCH — RETRACTED TWICE`; the `test` aggregator (`needs: [test-webplat, test-bun, test-scripts]`, `if: always()`, `timeout-minutes: 10`, step `Aggregate shard results`, **no `actions/checkout`**).
- `scripts/test-all.sh` — `_shard_selects()` (the chokepoint; `run_suite`/`skip_suite` both call it first), `_shard_ordinal`, `SUITE_GLOBS` array, `--print-suite-globs`, `--enumerate`, `_suite_budget_ms()`, and the `[ok]` branch's `TEST_TIMING_LOG` append.
- `plugins/soleur/test/scripts-shard-totality.test.sh` — the totality guard; derives its reference set **independently of the partition** (static extraction + `--print-suite-globs`), which is why it stays valid under a different assignment function.
- `plugins/soleur/test/scripts-shard-totality-mutations.sh` — the mutation battery (Control, Rows 1–5, 7–10, a META row asserting the reference is not derived from the partition, a harness row, a must-pass non-canonical input, and an assertion floor). Deliberately **not** `*.test.sh` so glob discovery cannot run it inside its own mutated parent; invoked by the dedicated `shard-totality-mutations` CI job, which is **not** a required check.
- `plugins/soleur/test/await-ci-ceiling-invariants.test.sh` — I1 `timeout-minutes*60 >= 1.2*CEILING_S`; I2 `MAX_ATTEMPTS*INTERVAL_S >= CEILING_S`; I3 soft ceiling is *derived* not restated; I3b `0 < soft < CEILING_S`; I4 `soft_breach` has a consumer. `MIN_ROWS=14`.
- `.github/workflows/web-platform-release.yml` — `await-ci` job; `migrate` (`needs: [release, await-ci]`) and its result-gate `if:` with the `workflow_dispatch && needs.await-ci.result == 'skipped'` arm; `deploy` (`needs: [release, migrate, verify-migrations, verify-doppler-secrets, await-ci]`); `live-verify` (`if: always() && needs.deploy.result == 'success' && github.event_name == 'push'`); `notify-slow-ci`, `notify-gated`, `release-outcome`; the `allow_unmirrored_reason` dispatch-bypass note; 9 `github.sha` consumers.
- `.github/workflows/reusable-release.yml` — the `max(release, await-ci) + (migrate + verify-migrations + deploy)` critical-path comment; the `Post to Slack (release)` step. Two consumers: `web-platform-release.yml` and `version-bump-and-release.yml` (component `plugin`, **no deploy at all**).
- `scripts/prod-version-drift-check.sh` — `DRIFT_SUSTAINED_THRESHOLD_MIN=207` and the critical-path comment; asserted by B9 in `scripts/prod-version-drift-check.test.sh`.
- `scripts/required-checks.txt` — `test` is required; `shard-totality-mutations` is not.
- `workflow_run` precedent in-repo: `.github/workflows/post-merge-monitor.yml` (`workflows: ["CI"]`, `types: [completed]`, `branches: [main]`) is the closest, matching `ci.yml`'s `name: CI`. Also `deploy-docs.yml`, `fix-constraints-stage-b.yml`.

### Institutional learnings applied

- `2026-07-01-two-stage-privileged-workflow-split-and-its-review-traps.md` (ADR-074) — `workflow_run` always runs the **default-branch** file; routing identity must come from `github.event.workflow_run.head_sha`, validated `^[0-9a-f]{40}$`; `workflows: [X]` matches the upstream workflow's **`name:` field, not its filename**, so a rename desyncs the trigger silently → **add a parity test** (Guard 4).
- `2026-05-31-tag-driven-dispatch-invariant-and-checkout-refspec-tag-locality.md` — control-plane logic for a dispatch/`workflow_run` trigger must live **inline in the workflow `run:` block**, never in a checked-out script; pre-merge-verify by reimplementing the logic in a test fixture, never by live-triggering.
- `integration-issues/2026-04-21-workflow-dispatch-requires-default-branch.md` — a new trigger cannot be exercised from the feature branch. Shapes the whole verification strategy (§Verification).
- `2026-03-05-autonomous-bugfix-pipeline-gh-cli-pitfalls.md` — `workflow_dispatch` does not populate `github.event.workflow_run.*`; a dual-trigger workflow must resolve identity per event with an explicit fallback.
- `2026-05-12-ci-test-job-speedup-replan-and-validation-mechanics.md` — the synthetic `test` aggregator's `if: always()` is **load-bearing**; without it a skipped shard can produce an aggregator some branch-protection configs read as success.
- `2026-06-09-no-test-asserts-X-must-grep-workflow-step-names-in-ci-test-sh.md` — "no test asserts X" for a `.yml` is a false negative unless `*.test.sh` is grepped for `awk`/`grep` assertions on literal step/field names. Phase 0 does this before touching either workflow.
- `2026-05-29-canonical-constant-flip-must-grep-consumers-that-assert-old-value.md` — flipping a constant requires grepping *asserting consumers*, not just producers; a gate asserting the old value passes on `main` and fails only after merge.
- `2026-06-16-infra-test-orphan-suites-and-node-options-env-file-clobber.md` — enumerated (vs globbed) CI discovery is a standing orphan generator. Directly the risk a checked-in duration table carries, and why Guard 2 asserts the fallback arm rather than the table's completeness.
- `best-practices/2026-06-30-adaptive-ci-poll-gate-wall-clock-ceiling-not-attempt-count.md` — companion to ADR-072; the check-run does not exist until shards terminate.
- `2026-04-15-gh-jq-does-not-forward-arg-to-jq.md` — every `gh api` + `jq --arg` in this plan is two-stage. Applied in §Measurement.
- `2026-07-05-ghcr-installation-token-minter-dependency-gate-and-adr-ordinal-drift.md` — an ADR ordinal chosen at plan time is a claim, not a reservation.

### ADR ordinal (provisional)

`main`'s highest is ADR-212. A probe across **all 82 `origin/*` refs**
(`git ls-tree -r --name-only <ref> knowledge-base/engineering/architecture/decisions/`) shows
**ADR-213 already claimed on a pushed branch**. Next free is therefore **ADR-214 — provisional**.
Re-run the all-refs probe immediately before merge and after every rebase; on a renumber, sweep
`knowledge-base/project/{plans,specs}/` for the old ordinal in the same edit.

### CLAUDE.md / AGENTS conventions in force

`hr-when-a-plan-specifies-relative-paths-e-g` (every glob verified against the tree),
`hr-never-run-commands-with-unbounded-output`, `hr-verify-repo-capability-claim-before-assert`,
`hr-no-dashboard-eyeball-pull-data-yourself` (every figure above came from an API query),
`hr-observability-as-plan-quality-gate`, `hr-no-ssh-fallback-in-runbooks`,
`cq-cite-content-anchor-not-line-number`, `cq-assert-anchor-not-bare-token`,
`cq-write-failing-tests-before`, `wg-use-closes-n-in-pr-body-not-title-to`.

---

## Open Code-Review Overlap

Scanned all 64 open `code-review` issues against this plan's `## Files to Edit` /
`## Files to Create` (`gh issue list --label code-review --state open --json number,title,body
--limit 200`, then standalone `jq --arg path`).

- **#7942** — *"Two mutation batteries in `plugins/soleur/test/` are named `*.mutation.sh` and run
  in no gate"*. Names `scripts/test-all.sh`'s `SUITE_GLOBS` (the `plugins/soleur/test/*.test.sh`
  entry) as the reason `git-fixture-env.mutation.sh` and `hook-git-env-coverage.mutation.sh` are
  invisible to every gate.
  **Disposition: acknowledge.** Different concern — #7942 is about suite *registration*, this plan
  changes leg *assignment* at a chokepoint downstream of registration. #7942 also explicitly warns
  that the one-line rename is the wrong move on its own (its `git-fixture-env.mutation.sh` carries
  an unanchored two-stage parse whose half-fix reproduces #7466's defect), so folding it in would
  drag a decoy-class parse repair into a CI-topology PR.
  **Reciprocal note to add to #7942 when this merges:** once LPT lands, registering those two
  suites no longer re-rolls leg composition, which removes one of the costs of fixing #7942.

No other open code-review issue names any file in this plan's edit set.

---

## User-Brand Impact

**If this lands broken, the user experiences:** a merged production fix that never reaches
`soleur.ai` — the `workflow_run` trigger does not fire (wrong `name:` match, wrong filter, or the
default-branch file lacking the trigger) and the deploy chain silently never runs, so the operator
sees a green PR, a published GitHub Release, a "v0.X.Y released!" Slack message, and a production
site still serving the old build. This is #7902's symptom class, relocated and made *quieter*: the
current failure mode reddens a release run, the new one can produce **no run at all**.

**If this leaks, the user's workflow is exposed via:** the wrong-SHA deploy path. Under
`workflow_run`, `github.sha` resolves to the default-branch tip rather than the verified SHA. Any
of the 9 existing `github.sha` consumers left unconverted — in particular `EXPECTED_SHA`, the gate
that catches "right semver, wrong source tree" — would deploy an image built from a **different
commit than the one CI verified**, while the wrong-image gate compares it against the wrong
expectation and passes. That is unreviewed code reaching production under a reviewed version
number.

**Brand-survival threshold: single-user incident.** #5806's own body classifies the topology change
this way. One wrong-SHA prod deploy, or one silently-never-deployed fix, is a full incident for the
single operator this product serves.

`requires_cpo_signoff: true` is set in frontmatter. `user-impact-reviewer` is invoked at review
time per `plugins/soleur/skills/review/SKILL.md`'s conditional-agent block.

---

## Decisions

The brief names four decision gates. All four are decided here, with the evidence.

### Decision 1 — The concurrency key changes, justified on semantics, not wall clock

**Change:** `group: ${{ github.workflow }}-${{ github.event_name == 'pull_request' && github.ref || github.sha }}`.

**Why not the wall-clock argument.** §Measurement shows the queue binds on 20% of runs and the
median run saves nothing. Shipping this as a speed fix would restate the mis-framing ADR-212
Decision 1 exists to correct, one layer further out.

**The argument that survives.** Each `main` push is a distinct SHA that needs its own CI verdict
for its own deploy gate. Under the current key, a run's gated quantity contains an unbounded term
belonging to a *different commit* — a term no declared ceiling has ever had a place for, and which
no amount of ceiling-sizing can bound, because it is not a property of the run being measured.
Per-SHA grouping makes the gated quantity a property of the SHA being gated. That is a correctness
statement about what the number means, and it holds on 100% of runs regardless of the queue's
magnitude.

**What is preserved.** `cancel-in-progress` stays `${{ github.event_name == 'pull_request' }}`.
Nothing is cancelled on `main` under either key; per-SHA grouping gives each run its own group, so
prior runs still run to completion and the post-merge-monitor / release-gate audit trail is
byte-identically intact. ADR-212's "would break the … audit trail" phrasing is corrected in the new
ADR.

**What is risked, and how it is bounded.** Peak concurrent `main` CI runs rises from 1 to the
burst depth. On the measured window the maximum concurrent depth would have been 2 (no run was
created while two predecessors were still in `test`). The pool is the binding constraint on 80% of
runs, so this could make the median *worse*. Rollback trigger is declared in §Risks.

### Decision 2 — `release` stays on `push`; only the deploy chain moves to `workflow_run`

**Rejected: fully serialise the workflow behind CI.** `release` completed before `await-ci` in
14/14 runs, median lead +29.2 min. `max(release, CI)` is empirically already `CI`. Serialising
would add `release`'s median 7.11 min to every deploy for zero benefit and would push the declared
critical path from 207 to ~265 min, breaking B9.

**Chosen: split by trigger inside the one file.** `web-platform-release.yml` keeps `on: push` and
gains `on: workflow_run` (`workflows: ["CI"]`, `types: [completed]`). Jobs partition by event:

| Job | fires on |
|---|---|
| `release` | `push`, `workflow_dispatch` |
| `verify-doppler-secrets` | **`workflow_run`**, `workflow_dispatch` — it has no `needs:` and no push-context dependence, so moving it keeps `deploy.if`'s conjunct satisfiable in-run |
| `migrate` → `verify-migrations` → `deploy` → `live-verify` | `workflow_run` (main + success), `workflow_dispatch` |
| `await-ci`, `notify-slow-ci` | **removed** |
| `notify-gated` | rehomed onto the `workflow_run` arm (fires when the deploy chain is gated) |
| `release-outcome` | fires on both arms, with `await-ci` dropped from `needs:` |

`max(release, CI)` is preserved by construction: both still start from the same push.

**The `needs.release.*` predicates must be reconstructed at EQUAL STRENGTH, per predicate.** This
is the defect that would have shipped a deploy chain that cannot fire, caught at plan review. On a
`workflow_run` event the `release` and `verify-doppler-secrets` jobs are **skipped**, and both
`migrate.if` and `deploy.if` are built on non-tolerant conjuncts over them:

```yaml
# migrate.if                          # deploy.if (in addition)
needs.release.result == 'success'     needs.release.outputs.docker_pushed == 'true'
needs.release.outputs.version != ''   needs.verify-doppler-secrets.result == 'success'
```

Left as-is, every one is false or empty on the new arm and the deploy silently never runs — R2, the
quietest failure in this plan, on the very first post-merge run.

**Equal strength is the operative requirement, not mere substitution.** "A GitHub Release exists for
this SHA" is *weaker* than `needs.release.result == 'success'`, and `deploy.if`'s own FR-A5 comment
says exactly why: `docker_pushed` is written by a step that runs **ten steps before** the zot mirror
assertion, so a release blocked by the mirror gate still shows `docker_pushed == 'true'`. The
`release.result` conjunct is the only thing between a mirror-gate-blocked release and a prod deploy
of an unmirrored image. `migrate.if`'s comment records the same lesson from the other side: *"the
tell was already inside this expression — `await-ci` and `verify-doppler-secrets` were gated on
`.result`, while `release` alone was gated only on an output."* Reconstructing from an output would
re-open the exact fail-open that conjunct was written to close.

| Predicate today | Reconstructed on the `workflow_run` arm as |
|---|---|
| `needs.release.result == 'success'` | the `Web Platform Release` run for `head_sha` has a **`release` job whose conclusion is `success`** — the job's verdict, never the existence of a release object |
| `needs.release.outputs.version != ''` | that run's `release` job output `version`, read via the jobs/outputs API, asserted non-empty |
| `needs.release.outputs.docker_pushed == 'true'` | same source; **and** the mirror-gate verdict is re-checked independently, because `docker_pushed` alone is known-insufficient |
| `needs.release.outputs.mirror_verified` (read at 2 sites) | same source. This is the **zot-mirror gate** that `allow_unmirrored_reason` exists to override; severing it silently deletes the override's only reach into the deploy |
| `needs.release.outputs.tag` | same source |
| `needs.verify-doppler-secrets.result == 'success'` | `verify-doppler-secrets` **moves to the `workflow_run` arm** — it has no `needs:` and no dependence on the push context, so moving the job is cheaper and safer than proxying its result. Losing it would re-open #2769 (the drift that shipped `NEXT_PUBLIC_APP_URL=undefined`) |
| `needs.await-ci.result == 'success'` | retired: the arm only exists because CI concluded `success` |

`resolve-target`'s output set is therefore **`head_sha`, `version`, `tag`, `docker_pushed`,
`mirror_verified`, `released`, `should_deploy`, `skip_reason`** — not the three an earlier revision
listed. `needs.release.outputs.version` alone is read at seven sites.

If any predicate cannot be reconstructed at equal strength, **#5806 does not ship in this shape** —
that is a stop condition, not a risk to accept. Guard 3's assembly widens from "reads bare
`github.sha`" to "**reads any `needs.release.*` on a `workflow_run`-reachable path**".

**The lookup must exclude its own run.** Under the new topology `web-platform-release.yml` produces
runs for the same `head_sha` on **both** arms, and the `workflow_run`-arm run has `release`
*skipped*. An unfiltered "runs for this SHA" query can therefore resolve state 2 — *"published
nothing → clean skip"* — for a SHA that **did** publish, so the deploy silently never happens and
the run stays green. That is the `## User-Brand Impact` worst case reached through the mechanism
built to prevent it. Pin the query to `?event=push&head_sha=<sha>` **and** exclude
`github.run_id`. Guard 7 gains the row.

**`resolve-target` runs on the `workflow_dispatch` arm too.** An earlier revision said every
downstream job consumes `needs.resolve-target.outputs.head_sha` while also placing `resolve-target`
only on the `workflow_run` arm — on a dispatch it would be skipped and every consumer would receive
the empty string, targeting `""`. It runs on both arms; on dispatch it emits `github.sha` and reads
the in-run `release` job.

**The two path gates the `workflow_run` arm does not inherit.** This is the sharpest gap in the
whole topology change and it is not in #5806's body. Today `web-platform-release.yml` runs at all
only when a push matches its `on.push.paths` denylist (`apps/web-platform/**`, `plugins/soleur/**`
minus `docs/` and `test/`), and `reusable-release.yml` applies a *second*, independent
`check_changed` gate in git-pathspec dialect. **A `workflow_run` trigger carries neither.** It
fires on **every** `ci.yml` completion on `main`, including a docs-only or `plugins/soleur/test/`
push for which no release was ever published.

A naive implementation therefore turns every irrelevant main push into a deploy arm that finds no
release for its SHA and fails closed — a red release run on routine docs commits, and worse, a
"release missing" signal that fires so often it can no longer distinguish the genuine failure it
exists to catch.

**Resolution: `resolve-target` is a five-state machine, not a lookup.** For
`github.event.workflow_run.head_sha` it queries the `Web Platform Release` workflow's runs for that
SHA and branches on the `release` job's real state:

| Observed state | Meaning | Action |
|---|---|---|
| No `Web Platform Release` run exists for this SHA | the push did not match `on.push.paths` — nothing to deploy | **clean skip**, run stays green |
| Run exists, `release` succeeded, but published no release (`check_changed` said no-op) | the inner pathspec gate declined | **clean skip**, run stays green |
| Run exists, `release` still in progress | the measured +11.5 min lead did not hold | **bounded reconcile** (below) |
| Run exists, `release` **failed** | a real failure | **fail closed**, loudly, with the release run linked |
| Run exists, release published | the normal path | **deploy** |

The first two arms are what keep the failure signal meaningful. Collapsing them into "no release →
fail" is the defect; collapsing them into "no release → skip" is the *other* defect, because it
silently swallows arm 4. Both are driven red by Guard 7.

**The race, and why arm 3 needs no ceiling at all.** An earlier revision of this plan gave arm 3 a
`RELEASE_WAIT_S` ceiling derived from `reusable-release.yml`'s `timeout-minutes: 60`. Plan review
cut it: the repo already solves this exact class better, in the very job being removed.
`await-ci` waits on a **liveness blocklist** — keep waiting while the upstream run's
`status != completed`; fail closed the moment it concludes without producing the thing you need.
Applied to the *release run for this SHA*, that needs **no ceiling**, and therefore no derived
constant, no fourth input to Guard 5, and no fifth thing that can drift.

This is also the honest reading of #5806: what it objects to is a **fixed ceiling on an unbounded,
growing quantity** (CI duration). A liveness poll on a run that is already running, bounded by that
run's own `timeout-minutes` enforced by GitHub rather than by us, is not that. The held-runner cost
is bounded by the release job's own duration — measured median 7.11 min — not by CI's.

### Decision 3 — LPT is DEFERRED; the drift story survives but the mechanism does not

**Revised at plan review.** The brief's gate is: *"If the drift story cannot be made defensible, say
so and ship parts 1+2 with part 3 explicitly deferred via a filed issue rather than shipping an
unowned table."* This plan initially answered "it can" and shipped LPT. Two independent reviewers
(DHH, code-simplicity) converged on the same scope, and the second found a defect that is **not**
about staleness at all:

**LPT does not deliver the property it was chosen for.** P3 is *"adding a suite does not re-roll the
partition."* LPT is a greedy **global** assignment: adding one slow suite, or refreshing one
duration, can move arbitrarily many *other* labels between legs. It reduces the amplitude of the
re-roll; it does not remove it. Decision 3(a) below concedes this in different words — "a wrong
duration produces a worse partition" — while claiming the property anyway.

**And the chokepoint cannot compute it.** `_shard_selects` is called **once per streaming
registration** (`scripts/test-all.sh`, the `run_suite`/`skip_suite` chokepoint); at first call it
does not know the live registration set. LPT would therefore be computed over the *table's* labels
rather than the registered ones — a phantom entry consumes leg weight, and untabled labels
round-robin against an ordinal that now interleaves with the LPT assignment. `scripts/test-all.sh`
separately records that ordinal order is locale-dependent and diverges from index 185, which LPT
inherits for exactly the labels the table does not name.

That is a mechanism defect, not a drift story. Per the brief's own instruction, **part 3 is deferred
with a filed issue.** Parts 1 + 2 ship.

**What ships from Phase C anyway (3 lines, keeps its own value):** the `TEST_TIMING_LOG` binding on
each `test-scripts` leg plus the artifact upload. The runner already writes `label \t elapsed_ms`
and no workflow binds it; binding it costs three lines and gives the deferred decision real data to
be made against. No table, no generator, no freshness warning ship.

**The cheaper alternative the deferral must consider first.** `ci.yml`'s own re-simulation already
records, on the shipping 376-suite order, **K=3 → 20.73 min, K=4 → 18.02, K=5 → 10.77**. Changing
`shard: ["1/3","2/3","3/3"]` to five legs is a **one-line** edit that beats LPT's entire (unmeasured)
balance gain. It does not give P3 — leg composition still moves with registration order — but it is
the larger win, and `ci.yml` instructs `RE-SIMULATE before treating any K as chosen`. The deferral
issue covers both, with the timing artifacts this plan starts collecting.

**For the record, the drift story itself did hold** — it is the mechanism that failed, and the
analysis below is retained because the next attempt will need it:

**(a) What happens when an entry is 3x wrong?** It costs **balance**, never **totality**. Totality
is structural at the chokepoint — `run_suite` and `skip_suite` each call `_shard_selects` exactly
once per registration, and that property is a function of the chokepoint, not of the assignment
rule. A wrong duration produces a worse partition; it cannot produce a missing or duplicated suite.
And a worse partition is *the same kind of failure the status quo already has*, with a smaller
amplitude: round-robin's composition is a positional accident measured swinging 15.09 → 20.70 →
15.09 min from adding two files and removing one, and `ci.yml`'s own comment now records that on
the shipping 376-suite order K=3 lands 20.73 min while K=5 lands 10.77. **A stale table cannot be
worse in kind than an unowned accident, and it has an owner.**

**(b) Who refreshes it?** The same run that consumes it produces the fresh data. `TEST_TIMING_LOG`
is bound on each `test-scripts` leg and uploaded as an artifact; `scripts/derive-suite-durations.sh`
merges the legs' TSVs into the table's format. The refresh is one command over an artifact the run
already produced — no scheduler, no log-scraping, nothing left to memory. A **same-run freshness
warning** (never a failure: `_suite_budget_ms`'s own comment records load alone moving a suite
1.9x, so a hard gate would red CI on noise) emits a `::warning::` naming any table entry that
drifted beyond a declared factor, so the staleness is legible on the run where it appears.

**(c) Does the totality guard still bind?** Yes, unchanged. `scripts-shard-totality.test.sh`
derives its reference set **independently of the partition** — static extraction of `run_suite` /
`skip_suite` registrations plus `--print-suite-globs` expansion — and its mutation battery already
carries a META row asserting exactly that the reference must not be derived from the partition.
The guard is agnostic to *how* legs are chosen. LPT changes only the assignment function behind
`_shard_selects`, so every existing row keeps its meaning.

**The one new failure mode LPT introduces** is a label the table does not name. The battery gains
the row the issue specifies — *a label absent from the table is still assigned to exactly one leg*
— plus three more the design implies (Guard 2).

### Decision 5 — Phase D removes the ordering guarantee Phase E's P6 depends on

**Surfaced at plan review; neither issue anticipates it, and it is the sharpest interaction between
the two.**

P6 claims the deploy "deploys the SHA CI actually verified, **in order**", and #5806's body claims
`workflow_run` fixes out-of-order deploys. `workflow_run` guarantees **correct-SHA**, not
**latest-SHA**. What actually orders deploys *today* is `ci.yml`'s
`group: CI-refs/heads/main` with `cancel-in-progress: false` — main CI runs serially, so their
completions are FIFO and the deploys inherit that order.

**Phase D deletes exactly that property.** Merge A (large diff), then B (a one-liner) ninety seconds
later; under per-SHA groups both CI runs proceed concurrently, B's finishes first, B deploys — then
A's completes and deploys, and production regresses to the older commit. Neither phase creates this
alone: D removes the ordering, E makes the deploy fire on completion rather than on a serialized
gate. Shipping them together is what makes it reachable, which is precisely why the sequencing
question the brief asked had to be answered with more than "D before E".

Compounding it: `deploy`'s `web-1-swap` group is `cancel-in-progress: false` and **cross-pipeline**.
GitHub keeps one running plus one pending per group and **cancels an older pending run** when a third
arrives — a behaviour `main-health-monitor.yml`'s own concurrency comment already records. Three
close merges can therefore drop a deploy entirely.

**Chosen: a monotonic-version precondition on `deploy`.** Refuse the swap when the resolved release
version is `<=` the version currently live on prod — a value `deploy` **already fetches** over the
webhook. This is emphatically **not** the rejected Phase C guard: no `origin/main`, no git ancestry,
no `actions/checkout`, and no step-level `exit 0` — it carries none of the three defects ADR-072
named. §Non-Goals is amended to scope the Phase C prohibition to the **git-ancestry** form, so the
next reader does not read the ban as covering this.

Guard 3 gains a row (remove the monotonicity check → RED), and **AC-P9** asserts the live version is
monotonically non-decreasing across the first 15 post-merge deploys.

### Decision 4 — ADR-212's creep detector is relocated, not deleted

`await-ci`'s `::warning::` at `0.7 * CEILING_S` is the only creep detector on this pipeline
(ADR-212 Decision 4). `workflow_run` deletes `CEILING_S`. Deleting the warning with it would
regress P8 and undo the fix #7902 shipped two days ago.

**Rejected: declare a fresh `CI_BUDGET_S` and warn at 0.7× it.** That is an unowned number, which
is precisely what ADR-212 Decision 3 rejected arithmetic for.

**Chosen: derive the reference from a constant that is already owned and already CI-asserted.**
`DRIFT_SUSTAINED_THRESHOLD_MIN` (`scripts/prod-version-drift-check.sh`) is the repo's declared
end-to-end pipeline budget, and check **B9** already asserts it stays ≥ the declared critical path.
CI's **allowed** share of it is that budget minus the declared ceilings of the jobs downstream of CI:

```
CI_BUDGET_MIN  = DRIFT_SUSTAINED_THRESHOLD_MIN - (migrate 30 + verify-migrations 15 + deploy 90)
               = 207 - 135 = 72          # what the pipeline BUDGET allows CI
soft_ceiling_s = CI_BUDGET_MIN * 60 * 7 / 10      # 0.7x, the same factor ADR-212 chose
```

**Two different quantities, previously conflated — corrected at plan review.** An earlier revision
used `72` here and `70` in Phase E.9's critical-path arithmetic as if they were the same number.
They are not:

- **`CI_BUDGET_MIN = 72`** — what the declared pipeline budget *allows* CI. The soft ceiling derives
  from this.

- **`CI_DECLARED_PATH`** — CI's own *declared* path. **This plan got the quantity wrong; corrected
  at review, see the note below.**

> **Superseded 2026-09-10 (#7990).** This section read `CI_DECLARED_PATH = 70` — CI's declared
> to-`test` path (`test-scripts` 60 → `test` 10) — and called `70 ≤ 72` the headroom statement that
> makes `max(release 60, 70) + 135 = 205 ≤ 207` hold. Both the workflow and B9 shipped that
> arithmetic and were green on it.
>
> It is the wrong quantity. `await-ci` polled for the **`test` check**, so to-`test` was correct for
> *that* mechanism and was carried across the rewrite unchanged. `workflow_run: types: [completed]`
> fires when the **whole `ci.yml` run** concludes — measured at **720m**, because 19 of 25 jobs
> declare no `timeout-minutes` and carry GitHub's 360m default. The `205 ≤ 207` green was a
> two-minute margin on a phantom.
>
> `await-ci` also *capped* the wait; #5806 removes that cap deliberately (item (a)), so the bound is
> now entirely `ci.yml`'s. The headroom statement cannot be asserted while any job is unbounded, so
> it is computed only when every job declares a ceiling and otherwise warns with the list. B9
> asserts the arm this pipeline controls (195 ≤ 207); B9b ratchets the unbounded count; B9c stops
> B9b going vacuous. Filed as **#8020**. Full reasoning in ADR-215 Decision 4.

Guard 5 pins each quantity to its own subject so they cannot be swapped.

**Where the derivation runs — NOT on `deploy`.** `web-platform-release.yml`'s `deploy` job carries an
explicit in-file prohibition on adding `actions/checkout`: it *"drives the deploy entirely over the
webhook"*, and a checkout *"would pull ~1.5k files onto the runner that holds the `web-1-swap`
lock."* `notify-gated` inlines its Slack curl for the same stated reason. An earlier revision of this
plan required the deploy arm to parse four values "from the checked-out tree" and never reconciled
that with the prohibition. Resolved: **all file reading and derivation lives on `resolve-target`**,
a new job that holds no lock and drives no deploy, and which already reads the release run's state.
`deploy` stays checkout-free and consumes `resolve-target`'s outputs.

Every term is still **read**, never restated, exactly as ADR-212's I3 required of the old soft
ceiling — so the rewritten invariants suite keeps asserting a *derivation* rather than a literal, and
the number moves automatically when any ceiling moves.

---

## Implementation Phases

Ordered so the gate is never left measuring a quantity that no longer exists. Phases D and E are
the sequencing constraint the brief names: **D changes what the gate measures while the gate still
exists; E replaces the gate and its invariants suite in one commit.**

### Phase 0 — Preconditions (no behavior change)

0.1 Grep every `*.test.sh` for assertions on the literals about to change, per
`2026-06-09-no-test-asserts-X…`:
`git grep -nE "github\.workflow.*github\.ref|Aggregate shard results|await-ci|CEILING_S|shard: \[" -- '*.test.sh' '*.test.ts' 'scripts/' 'plugins/'`.
Every hit becomes a `Files to Edit` entry before any workflow byte moves.
0.2 Verify each glob this plan prescribes matches ≥1 real file:
`git ls-files | grep -E '^plugins/soleur/test/.*\.test\.sh$'`, same for the `SUITE_GLOBS` entries.
0.3 Re-run the all-refs ADR-ordinal probe; confirm ADR-214 (or the then-next-free) is unclaimed.
0.4 Confirm `bash scripts/test-all.sh --enumerate scripts` runs and record the live suite count.
0.5 Confirm `TEST_TIMING_LOG` is bound in **no** workflow (`git grep -n TEST_TIMING_LOG -- .github/`)
— this is the Cut List's load-bearing premise.

### Phase A — Premise correction (documentation only, no behavior change)

A.1 Rewrite `ci.yml`'s `NOTE ON DISPATCH — RETRACTED TWICE` block into a **third revision that is
the measurement, not a mechanism**: the additive model, the 20%/80% cohort split, the queue's
median 393s / max 1245s, the 4s free-run dispatch, the 332s/1708s within-run spread, and the
reproduction command. It must state that revisions 1 and 2 were each right about a different
cohort, so the next reader does not retract it a third time.
A.2 Amend **ADR-212**'s `Consequences` → `Named residual`: replace "the concurrency queue is the
dominant term" with the population statistic, and correct the "would break the … audit trail"
clause (per-SHA grouping cancels nothing; prior runs still finish).
A.3 **Do not edit ADR-208.** Record the mis-citation in the PR body so it is not propagated.

### Phase B — #7931 part 2: the aggregator names the measured cause

**Simplified at plan review.** An earlier revision added `actions/checkout` to the `test` job, a
`gh api` call, and a new `scripts/ci-classify-leg-outcome.sh`, in order to compare each leg's
elapsed time against a `timeout-minutes` parsed from the tree. Three reviewers converged against it,
and the objection is decisive: `test` is the job that reports the repo's **most load-bearing
required status**, and its verdict today depends on exactly two things — three GitHub-provided
`needs.*.result` strings and the workflow file. Adding a checkout, a network call and a checked-out
script widens the input surface of that check to obtain a *diagnostic string*.

**The discriminator is already in the three strings.** A concurrency cancellation cancels the
**whole run**, so every in-flight leg reads `cancelled`. A `timeout-minutes` kill stops **one** leg
while its siblings conclude normally. That is a shape comparison over data the job already has in
`env:`, and — importantly — it is correct **whether GitHub reports a timed-out job as `cancelled` or
as `failure`**, which the elapsed-vs-budget approach had to assume without citation.

B.1 **RED first** (`cq-write-failing-tests-before`): add
`plugins/soleur/test/ci-test-aggregator-diagnosis.test.sh` driving the extracted loop body over
synthetic `needs.*.result` triples, before the branch exists. The suite extracts and executes the
inlined `run:` body — the pattern `scripts/prod-version-drift-check.test.sh` already uses on this
repo — so the logic stays inline in the workflow (per `2026-05-31-tag-driven-dispatch-invariant…`,
and it *is* control-plane: its output decides `exit 1`) while remaining unit-testable.
B.2 Replace the bare `echo "$shard: $result" >&2` with a branch over the result triple:

| this leg | siblings | emitted line |
|---|---|---|
| `failure` | any | `FAILED — assertions failed; see the <leg> job log` |
| `cancelled` | **at least one sibling also `cancelled`** | `SUPERSEDED — the run was cancelled (a newer commit landed)` |
| `cancelled` | **all siblings concluded** (`success`/`failure`) | `STOPPED ALONE — this leg was stopped while its siblings finished; the usual cause is its own declared timeout-minutes` |
| `cancelled` | anything else | `CANCELLED — cause not determined from the result shape` |
| `skipped` | any | `SKIPPED — the leg did not run` |

The fourth row is deliberate. An honest UNKNOWN arm is required; a confident third mechanism is
exactly what this repo has already retracted twice on the adjacent question. No elapsed time, no
`0.98` magic constant (an unowned number in a plan whose Guard 5 exists to ban them), no API call.
B.3 Never swallow a failure: the branch is additive and every non-success leg still sets `fail=1`
and `exit 1`. This is 2 lines and is the part of the original B.5 with independent value.
B.4 Rewrite the stale `#7902 AC5` byte-unchanged comment above `timeout-minutes: 10` — it documents
a proof this commit retires.

**Scope note, stated honestly.** After Phase D every `main` SHA has its own concurrency group and
`cancel-in-progress` stays `false` on push, so **`SUPERSEDED` becomes structurally unreachable on
`main`**. The ambiguity #7931 part 2 exists to resolve survives only on `pull_request` runs. That is
still worth fixing — it is where the ambiguity is actually read — but the required check's
`main`-side output is improved by Phase D, not by Phase B.

### Phase C — #7931 part 3: timing collection only (LPT deferred)

**Reduced to its data-collection half — LPT is deferred (Decision 3).** What ships is three lines
plus an upload; what is deferred is the assignment change, the table, the generator, the freshness
warning, and the four Guard 2 rows that existed only to police a table.

C.1 Bind `TEST_TIMING_LOG` on each `test-scripts` leg and upload it with
`actions/upload-artifact`, one artifact per shard. `scripts/test-all.sh`'s `run_suite` already
writes `label <TAB> elapsed_ms` on every `[ok]` suite; no workflow binds it, so CI currently discards
per-suite timings it already knows how to produce. This is the only behavioural change in Phase C.

C.2 Record in the deferral issue (§Deferrals) what the collected artifacts are *for*: choosing
between (a) a K change — `ci.yml` already records K=3 -> 20.73 min vs K=5 -> 10.77 min on the
shipping order, a **one-line** edit that beats LPT's entire projected balance gain — and (b) an
insertion-stable assignment. Three constraints the next attempt must carry, all found at this plan's
review and none of them visible from the issue body:

- **`_shard_selects` takes no arguments.** Both call sites are bare `_shard_selects || return 0`.
  Any label-keyed partition must either pass the label explicitly at both sites, or read the
  caller's `local label` by dynamic scoping — an invisible coupling that a rename in `skip_suite`
  breaks silently while every existing guard row stays green.

- **`skip_suite`'s docstring promise becomes load-bearing.** It says `$1 = label (must match the
  label the suite would have run under)`. That is unenforced today; under a label-keyed partition a
  mismatch lands the registration on a different leg than the suite would have. It needs its own
  mutation row.

- **The table cannot be bootstrapped locally.** `scripts/test-all.sh` states that leg membership is
  not portable between machines and that balance tuning must be derived from CI's `C` collation,
  never a developer's. So the bootstrap is two pushes: land C.1, let CI upload, then derive.

C.3 K is **not** re-simulated in this PR. This plan adds three glob-discovered
`plugins/soleur/test/*.test.sh` suites, each of which shifts every subsequent ordinal — so a
re-simulation performed before they register measures a partition that will not ship.

### Phase D — #7931 part 1: the concurrency key

D.1 Change `concurrency.group` to the per-SHA expression. `cancel-in-progress` unchanged.
D.2 Rewrite the block comment: what the key now means, that nothing is cancelled under either key,
that the audit trail is preserved, and that the change is semantic (Decision 1).
D.3 Add `plugins/soleur/test/ci-concurrency-key.test.sh` (Guard 1).
D.4 **No ceiling is re-derived here, and that is a finding, not an omission.** `CEILING_S=3600` was
sized over a `time-to-test` that *included* the queue; removing the queue only adds headroom.
`test-scripts`' `timeout-minutes: 60` is derived from the advisory suite budget
(`rest-of-leg 6.95 + 41.67 = 48.62, ×1.2 → 60`), a quantity with no queue term. `await-ci`'s
`timeout-minutes: 72 = 1.2 × 3600/60` is unaffected. Harvesting the new headroom by lowering
`CEILING_S` would re-create #7902 and is explicitly not done.

### Phase E — #5806: the `workflow_run` deploy gate

E.1 Add `on: workflow_run: {workflows: ["CI"], types: [completed], branches: [main]}` to
`web-platform-release.yml`. **The `branches:` filter is not optional** — an earlier revision omitted
it while citing `post-merge-monitor.yml` as the precedent, and that file *has* it. Without it a full
`Web Platform Release` run is **created** for every PR CI completion and every `merge_group`
completion (35 main runs in the measured 53h window, plus PR volume), each with every job skipping
and `release-outcome`'s `if: always()` executing. It is defence-in-depth and does **not** replace
`resolve-target`'s runtime `head_branch`/`event` checks: `branches:` matches `head_branch`, which a
fork PR from a branch named `main` also satisfies.
E.2 Add a single `resolve-target` job on the `workflow_run` arm that emits `head_sha`, `version`,
`should_deploy` and `skip_reason`. It applies the event filters
(`head_branch == 'main'`, `conclusion == 'success'`, `event == 'push'`, `head_sha` matching
`^[0-9a-f]{40}$`) **and then** the five-state release resolution from Decision 2 — the two path
gates the `workflow_run` trigger does not inherit are re-established here, or every docs-only main
push reddens the release run. Every downstream job consumes
`needs.resolve-target.outputs.head_sha` — never `github.sha`.
E.3 Convert every broken context consumer to a per-event resolution
(`workflow_run` → event `head_sha`; `workflow_dispatch`/`push` → `github.sha`). The set is **ten**,
not nine — the plan's original count missed one, and the tenth is a different failure shape:

- the 9 `${{ github.sha }}` sites, including `EXPECTED_SHA` (the wrong-image gate) and the
  `live-verify` `if:`, which must no longer test `github.event_name == 'push'` or it skips forever;

- **`live-verify`'s changed-file trigger gate, which reads `BEFORE_SHA: ${{ github.event.before }}`.**
  `github.event.before` **does not exist on a `workflow_run` event**; it resolves to the empty
  string, and a compare-API diff gate with an empty base is the empty-haystack direction — it does
  not error, it silently matches nothing. Resolve the base by an explicit parent lookup from
  `github.event.workflow_run.head_sha`, never from `event.before`.

**Do not filter the new arm on `github.ref`.** Under `workflow_run`, `github.ref` is *always* the
default branch, so `github.ref == 'refs/heads/main'` is **vacuous** — it reads like a branch filter
and gates nothing. `deploy-docs.yml` carries the repo's own record of hitting this: an
`environment:` block with a `main` deployment-branch-policy was deleted because it did not work
under `workflow_run` and was replaced by exactly that vacuous conjunct. Filter on
`github.event.workflow_run.head_branch`, or at the trigger level.

**Precedent to follow for the arm's own concurrency:** `fix-constraints-stage-b.yml` already
SHA-keys a `workflow_run` arm — `group: fix-constraints-b-${{ github.event.workflow_run.head_sha }}`
— which is the shape the new deploy arm should use at workflow level.
E.4 Rehome `migrate`/`verify-migrations`/`deploy`/`live-verify` onto the new arm; delete `await-ci`
and `notify-slow-ci`; rehome `notify-gated`.

E.4a **Specify `notify-gated`'s new `if:` verbatim — "fires when the deploy chain is gated" is not
implementable.** Today it fires on `needs.await-ci.result == 'failure'`. With `await-ci` deleted,
"gated" is undefined, and `release-outcome`'s own classifier treats `skipped` as **not a fault** —
so **a red CI on `main` would produce a green release run and zero notifications**, where today it
reddens and Slacks. That is a silent drop on the operator's only channel. The predicate:

```yaml
if: >-
  github.event_name == 'workflow_run' &&
  github.event.workflow_run.head_branch == 'main' &&
  github.event.workflow_run.event == 'push' &&
  (github.event.workflow_run.conclusion != 'success' ||
   needs.resolve-target.outputs.skip_reason == 'release_failed' ||
   needs.resolve-target.outputs.skip_reason == 'upstream_concluded_unpublished')
```

`conclusion != 'success'` is deliberate rather than `== 'failure'`: it also covers `cancelled` and
`timed_out`. The two **clean-skip** states must NOT fire it, or every docs-only push pages the
operator. Guard 7 gains both rows (narrow to `failure` only → RED; clean-skip fires → RED).

E.4b **Redesign the run-outcome notification — it is the operator non-delivery guarantee and it is
single-run.** This is the largest thing #5806's body does not mention and the plan must not defer
alongside item 4. `release-outcome` today declares
`needs: [release, await-ci, migrate, verify-migrations, verify-doppler-secrets, deploy, live-verify,
notify-gated, notify-slow-ci]` with `if: always()`, and its steps are
*"Email the operator (release did NOT reach production)"* and *"Mirror non-delivery to Sentry and
fail loudly"*. That entire guarantee is built on all nine jobs living in **one run**. Split naively,
the `push` arm would see only `release: success` and report that the release reached production —
an observability regression on the single operator-facing surface that exists to say otherwise,
which `hr-observability-as-plan-quality-gate` makes a plan-quality gate.

`release-outcome` therefore moves to the **`workflow_run` arm**, where the whole deploy chain now
lives, and recovers the `release` job's verdict cross-run from the *same* API lookup
`resolve-target` already performs (Decision 2's five-state resolution) — no new mechanism. Its
`await-ci` and `notify-slow-ci` `needs:` entries retire with those jobs; every remaining classify
arm keeps its current wording. The two clean-skip states must classify as **delivered-nothing-to-
deliver**, never as non-delivery, or the operator is emailed on every docs-only push.

E.4c **`web-1-swap` — correct name, wider blast radius, and a parity test that counts it.** #5806's
body calls the deploy lock `deploy-web-platform`; that group was **renamed to `web-1-swap` in

#6060** and `apps/web-platform/infra/web-1-swap-concurrency-parity.test.sh` actively greps to stop

the old name returning. The real group is a **cross-pipeline mutex** taken at **9** sites across four
workflows — 8 job-level (1 in `web-platform-release.yml`, 6 in `apply-web-platform-infra.yml`,
1 in `apply-deploy-pipeline-fix.yml`) plus one **workflow-level** group in
`workspaces-luks-cutover.yml`. The parity guard counts the 8 JOB-LEVEL sites across the three
job-level workflows and does not read the cutover file at all; "8 across four workflows" (this
plan's original wording, corrected 2026-09-10 at review) conflated the two scopes — `web-platform-release.yml` (`deploy`), `apply-deploy-pipeline-fix.yml`,
`apply-web-platform-infra.yml` (six sites), and `workspaces-luks-cutover.yml` — and the parity
guard asserts the **total count `== 8`**, each with `cancel-in-progress: false`, plus release-job
membership. Rehoming `deploy` changes that count or that membership either way, so the parity test
is a **lockstep edit**, not a passenger. Verify with
`bash apps/web-platform/infra/web-1-swap-concurrency-parity.test.sh` (wired at
`infra-validation.yml`, the "cross-pipeline web-1-swap concurrency parity drift-guard" step).
E.5 Preserve the `workflow_dispatch` escape hatch as its own arm: the result-gate expression's
`needs.await-ci.result == 'skipped'` clause is replaced with a dispatch clause that no longer
references a job that does not exist. Update the `allow_unmirrored_reason` note, which currently
says the override "bypasses await-ci (a push-only job)".
E.6 Implement the bounded release reconcile (Decision 2) with `RELEASE_WAIT_S` **derived** from
`reusable-release.yml`'s declared `release` `timeout-minutes`.
E.7 Implement the relocated soft-ceiling warning (Decision 4), deriving `CI_SHARE_MIN` from
`DRIFT_SUSTAINED_THRESHOLD_MIN` minus the three downstream ceilings, all parsed from the tree.
E.8 **Rewrite `plugins/soleur/test/await-ci-ceiling-invariants.test.sh` in the same commit** —
never delete it. New name reflects the new subject. I1/I2 (poll-loop attempt arithmetic) retire
with the loop; I3 (derived, not restated), I3b (fires below its reference) and I4 (the emitted
signal has a consumer) survive with the new derivation as their subject, joined by the
release-reconcile derivation. The `MIN_ROWS` floor is preserved or raised, never lowered.
E.9 Reconcile the declared critical path across **three** files, and run B9 rather than reason
about it. This is the sharpest edge in Phase E:

- `web-platform-release.yml`'s `deploy` job carries a `COUPLED (#7091, #7160)` comment stating
  `max(release 60, await-ci 60) + migrate 30 + verify-migrations 15 + deploy 90 = 195`. That
  comment is **already stale** — `await-ci` is 72 and the threshold is 207 — so it is edited here
  regardless of #5806.

- The same comment records the hazard that makes naive deletion unsafe: *"DELETING one now fails it
  as well (**an absent ceiling reads as the GitHub 360 default, not as zero**)"*. If B9's extraction
  looks up a *named* job and substitutes 360 when the ceiling is missing, removing `await-ci` would
  compute `max(60, 360) + 135 = 495 > 207` and drive B9 **red on a correct change**. Determine
  which shape B9 uses (`scripts/prod-version-drift-check.test.sh`, the B9 block) **before** deleting
  the job, and adjust the extraction in the same commit if it is name-keyed rather than
  job-enumerating.

- `release`'s ceiling is declared on the **callee** (`reusable-release.yml`), because the GitHub
  schema forbids `timeout-minutes` on a `uses:` job. Any extraction change must keep following that
  indirection.

- Expected outcome once reconciled: `max(release 60, CI-to-test 70) + 30 + 15 + 90 = 205 ≤ 207`, so
  `DRIFT_SUSTAINED_THRESHOLD_MIN` stays **207**. Confirmed only by a green B9, never by this
  arithmetic.

E.10 Add Guards 3, 4, 5.

### Phase F — ADR, C4, and deferrals

F.1 Write **ADR-214** (provisional ordinal) — see §Architecture Decision.
F.2 Amend ADR-072 (`## Alternatives Considered` option 3: adopted, with the fail-open closed) and
ADR-212 (Decision 4 relocated; `Named residual` corrected).
F.3 Re-run `bash plugins/soleur/test/c4-count-parity.test.sh` after the workflow edits and correct
any moved count in the same commit (§Architecture Decision → C4 views).
F.4 File the deferral issues (§Deferrals) and post the reciprocal note on #7942.

---

## Files to Edit

| Path | Change |
|---|---|
| `.github/workflows/ci.yml` | concurrency key + comment (D); `test` aggregator step, checkout, and the stale AC5 comment (B); `TEST_TIMING_LOG` + artifact upload on `test-scripts` (C); K-table re-simulation and the dispatch-note third revision (A, C) |
| `.github/workflows/web-platform-release.yml` | `workflow_run` trigger; `resolve-target`; 9 `github.sha` consumers; job rehoming; `await-ci`/`notify-slow-ci` removal; dispatch arm; release reconcile; relocated soft ceiling (E) |
| `.github/workflows/reusable-release.yml` | critical-path comment only — the `max(release, await-ci)` term no longer exists. **No behavioral change**, so the `plugin` consumer is untouched (E) |
| `scripts/test-all.sh` | **NOT EDITED — corrected 2026-09-09 at implementation.** This row survived from the revision that shipped LPT; Decision 3 defers LPT, so `_shard_selects` is unchanged and the chokepoint comment block is untouched. The sibling `scripts-shard-totality*` row was updated when the deferral landed and this one was missed. Phase C is the `TEST_TIMING_LOG` binding in `ci.yml` only. |
| `scripts/prod-version-drift-check.sh` | critical-path comment; `DRIFT_SUSTAINED_THRESHOLD_MIN` re-verified via B9 (E) |
| `scripts/prod-version-drift-check.test.sh` | **two certain reds, not one conditional.** **B9**'s critical-path extraction is confirmed name-keyed (`max(release_ceiling, job_timeout("await-ci"))`, `DEFAULT_JOB_TIMEOUT_MIN=360`) → deleting the job computes `max(60,360)+135 = 495 > 207`. **B8e** separately pins `DEPLOY_NEEDS_CLOSURE` as the literal `"await-ci,migrate,release,verify-doppler-secrets,verify-migrations"`; Phase E drops `await-ci`, moves `release` out of the closure entirely (different run) and adds `resolve-target`. Both must be re-derived deliberately (E.9) |
| `plugins/soleur/skills/postmerge/SKILL.md` | its `gh run list --limit 1` selection now hits the wrong arm ~50% of the time and its `reason=canary_*` grep resolves against an empty log — Guard 8 (E) |
| `plugins/soleur/skills/ship/SKILL.md` | documents *"the post-merge `web-platform-release` run goes RED with `deploy: skipped`"* on an admin-merge and tells the operator not to fix it. Under `workflow_run` the squash commit's CI **does** run and the trigger **does** fire, so an admin-merge now **deploys** — the documented escape hatch inverts (E) |
| `knowledge-base/project/learnings/best-practices/2026-06-29-admin-merge-skips-deploy-via-await-ci-gate.md` | same inversion; the learning's premise is retired by this change (E) |
| `scripts/watch-live-verify-pass.sh` | `--limit 25` lookback is halved by run-doubling — Guard 8 (E) |
| `apps/web-platform/Dockerfile` | the comment *"Asserted post-deploy by web-platform-release.yml against `${{ github.sha }}`"* becomes wrong once E.3 changes what `EXPECTED_SHA` reads (E) |
| `plugins/soleur/test/await-ci-ceiling-invariants.test.sh` | rewritten in lockstep with E; renamed to match the new subject; `MIN_ROWS` preserved or raised (E) |
| `plugins/soleur/test/scripts-shard-totality*.{test.sh,sh}` | **not edited** — Guard 2 withdrawn with the LPT deferral; AC8 asserts they stay green unchanged |
| `apps/web-platform/infra/web-1-swap-concurrency-parity.test.sh` | **NOT EDITED — prediction corrected 2026-09-10 at review.** It asserts the job-level `group: web-1-swap` count `== 8` across **three** workflows (not four — it never reads `workspaces-luks-cutover.yml`, whose group is workflow-level) plus release-job membership. Rehoming `deploy` changed neither: the job kept its own `concurrency:` block, only its `needs:`/`if:`/env moved. Verified green 23/23 unchanged. |
| `knowledge-base/engineering/architecture/decisions/ADR-072-adaptive-ci-signal-wait-for-deploy-gate.md` | option 3 adopted; the named fail-open closed (F) |
| `knowledge-base/engineering/architecture/decisions/ADR-212-deploy-gate-measures-its-own-gated-quantity.md` | `Named residual` corrected; Decision 4 relocated (A, F) |

Any file surfaced by Phase 0.1's grep is added to this table before implementation begins.

## Files to Create

| Path | Purpose |
|---|---|
| `plugins/soleur/test/ci-test-aggregator-diagnosis.test.sh` | Guard 6 — the classifier's battery (B) |
| `plugins/soleur/test/ci-concurrency-key.test.sh` | Guard 1 (D) |
| `plugins/soleur/test/workflow-run-deploy-invariants.test.sh` | Guards 3, 4, 5, 7 (E) |
| `scripts/followthroughs/ci-concurrency-cohort-7931.sh` | soak probe for AC-P1..AC-P3 (§Observability) |
| `knowledge-base/engineering/architecture/decisions/ADR-214-*.md` | provisional ordinal (F) |

Every new `plugins/soleur/test/*.test.sh` is glob-discovered by `SUITE_GLOBS`, so it registers
automatically — and each one shifts the ordinal set, which under LPT no longer re-rolls leg
composition for known labels. `scripts/*.test.sh` is **not** globbed; anything placed there needs
an explicit `run_suite` registration.

---

## Verification (the `workflow_run` constraint, handled explicitly)

`workflow_run` runs the **default-branch** version of the workflow, so this change is not testable
from the feature branch the way an ordinary workflow edit is
(`integration-issues/2026-04-21-workflow-dispatch-requires-default-branch.md`). Four layers, in
order of when they bind:

1. **Static, pre-merge (primary gate).** `workflow-run-deploy-invariants.test.sh` parses the new
   `web-platform-release.yml` and drives red on: a `workflow_run`-reachable path reading bare
   `github.sha`; a missing `head_branch`/`conclusion`/`event` filter; `workflows:` not matching
   `ci.yml`'s `name:`; a `live-verify` `if:` that cannot be true on the new arm. Runs on the
   feature branch, on every PR.

2. **Fixture, pre-merge.** Per `2026-05-31-tag-driven-dispatch-invariant…`, reimplement the
   `resolve-target` resolution inline in the suite and drive it with synthetic `workflow_run`
   payloads: main+success (deploy), main+failure (no deploy), non-main branch (no deploy),
   `event != push` (no deploy), malformed `head_sha` (no deploy), `workflow_dispatch` (deploy, SHA
   from `github.sha`), and one fixture per Decision-2 release state — **no release run for the SHA**
   (docs-only push → clean skip, green), **`check_changed` no-op** (clean skip, green),
   **`release` in progress** (bounded reconcile), **`release` failed** (fail closed). This is the
   only pre-merge exercise of the decision logic itself.

3. **First post-merge run (the real trigger).** The merge commit's own CI run completes *after* the
   merge, by which time the default branch carries the new trigger — so the merge commit is itself
   covered. AC-P4..AC-P7 assert on that run.

4. **Rollback trigger.** If no deploy run appears within `CI p100 time-to-test + 15 min` of the
   first post-merge CI completion, revert Phase E. Declared, not implied.

**Double-deploy window.** For a push already in flight when the merge lands, the old `push`-arm
deploy chain and the new `workflow_run` arm could both target the same SHA. The existing
cross-pipeline **`web-1-swap`** mutex serialises them (not `deploy-web-platform` — renamed in

#6060), and the second is idempotent (same image, same version). Because that group is

`cancel-in-progress: false` and shared with four pipelines, GitHub keeps one running plus one
pending and cancels an older pending run when a third arrives — so AC-P8 asserts both that no
double-deploy occurred **and** that no deploy concluded `cancelled` while pending.

---

## Acceptance Criteria

### Pre-merge (PR)

- **AC1** `.github/workflows/ci.yml`'s `concurrency.group` is the per-SHA expression and
  `cancel-in-progress` is byte-unchanged.
  Verify: `bash plugins/soleur/test/ci-concurrency-key.test.sh` (Guard 1) exits 0. **The gate is the
  guard suite, not an `awk` print** — a printing command asserts nothing, and any `/x/,/y/` range
  form risks self-match (see Sharp Edges).

- **AC2** `ci.yml`'s dispatch note carries the 20%/80% cohort split, both cited medians, and the
  reproduction command; it does not assert a single mechanism.

- **AC3** ADR-212's `Named residual` no longer says the queue is "the dominant term" and no longer
  claims the per-SHA key breaks the audit trail. ADR-208 is untouched.
  Verify: `test -z "$(git diff origin/main...HEAD --name-only -- 'knowledge-base/engineering/architecture/decisions/ADR-208-*')"`
  — a bare `git diff` is vacuous on a committed branch.

- **AC4** The `test` job emits a distinct line for each of the five outcome classes, discriminated
  from the `needs.*.result` triple alone.
  Verify: `bash plugins/soleur/test/ci-test-aggregator-diagnosis.test.sh` exits 0 and reports
  ≥ its declared assertion floor.

- **AC5** The aggregator makes **no network call and requires no checkout**: the `test` job has no
  `actions/checkout` step and its `run:` block contains no `gh api`.
  Verify: the guard suite's own extraction of the job body. *(This AC replaces an earlier one that
  required parsing `timeout-minutes` from the tree — the simplified discriminator removed the need,
  and the old `grep -cE '\b(60|3600)\b'` form was unsound anyway: `* 60` is the required
  seconds-per-minute conversion, and `grep -c` exits 1 on zero matches, aborting the AC under
  `set -euo pipefail` on the passing case.)*

- **AC6** Every non-success leg still sets `fail=1` and the job still exits 1 — the diagnosis is
  additive and can never swallow a failure.
  Verify: a battery row asserting exit 1 for each non-success triple.

- **AC7** Each `test-scripts` leg uploads a non-empty `TEST_TIMING_LOG` artifact whose every row is
  `<label>\t<elapsed_ms>` and whose labels all resolve to live registrations
  (`bash scripts/test-all.sh --enumerate scripts`).

- **AC8** `bash plugins/soleur/test/scripts-shard-totality.test.sh` exits 0 **unchanged** —
  totality holds under LPT with no edit to the guard.

- **AC9** `bash plugins/soleur/test/scripts-shard-totality-mutations.sh` exits 0 **unchanged** —
  the battery is not edited by this PR (Guard 2 withdrawn with the LPT deferral).

- **AC10** The rewritten ceiling-invariants suite exits 0 and its `MIN_ROWS` is ≥ 14.
- **AC11** `bash plugins/soleur/test/workflow-run-deploy-invariants.test.sh` exits 0.
- **AC12** No `workflow_run`-reachable job in `web-platform-release.yml` reads bare `github.sha`.
  Verify: the suite's own extraction (not a hand-enumerated path list) — per
  `2026-07-28-my-ac-verified-four-paths-while-ci-verified-five`, the AC runs the gate's own
  invocation, not a reconstruction of its inputs.

- **AC13** The `await-ci` **job** no longer exists and nothing reads its results.
  Verify: `! grep -qE '^  await-ci:' .github/workflows/web-platform-release.yml` and
  `! git grep -qn 'needs\.await-ci' -- .github/workflows/`.
  **Prose references are permitted and expected** — E.5 rewrites the `allow_unmirrored_reason` note
  and E.9 rewrites the `COUPLED (#7091, #7160)` block, both of which name the removed job on
  purpose. There are 37 `await-ci` occurrences in that file today and most are comments; an
  absence-grep over all of them would forbid exactly the documentation this plan requires. *(Also:
  `grep -c PAT f1 f2 …` prints `path:count` per file and exits 0, so "is 0" is meaningless for the
  multi-file form.)*

- **AC14** `bash scripts/prod-version-drift-check.test.sh` exits 0, with **both B8e and B9** green
  against the new cross-run topology — B8e's `DEPLOY_NEEDS_CLOSURE` pin re-derived, B9's
  critical-path extraction rewritten. Both are **certain** reds before the rewrite, not conditional.

- **AC15** `workflow_dispatch` remains a reachable deploy path **and `skip_deploy` still stops it**:
  the dispatch fixture resolves a non-empty `head_sha` matching `^[0-9a-f]{40}$` and evaluates the
  deploy gate true; a second fixture with `skip_deploy: true` evaluates it **false**. An AC that
  only asserts dispatch deploys cannot see a broken escape hatch.

- **AC16** `git grep -n 'TEST_TIMING_LOG' -- .github/workflows/ci.yml` returns ≥ 1 hit on the
  `test-scripts` job.

- **AC17** ADR-214 (or the then-next-free ordinal, re-probed across all `origin/*` refs) exists,
  and no other file in the diff references a different ordinal for this decision.

- **AC17b** `resolve-target` reaches all five Decision-2 states across the fixture set, and the two
  clean-skip states leave the run **green**.
  Verify: `bash plugins/soleur/test/workflow-run-deploy-invariants.test.sh` reports one row per
  state and its docs-only-push must-PASS fixture is green.

- **AC18** `bash plugins/soleur/test/c4-count-parity.test.sh` exits 0 after the workflow edits.
- **AC19** The full battery is green at `/ship` Phase 4 (ADR-183 — the full-suite checkpoint is at
  ship, so an orphan suite outside the touched shards is caught there, not at implementation exit).

### Post-merge (automated, no operator step)

- **AC-P1** Re-run §Measurement's command over the first 15 `main` push runs after merge and assert
  the falsifiable property: **no run's first job start is gated on its predecessor's `test`
  completion** — i.e. for every run, `first_job_start - predecessor.test.completed_at` is not in the
  +0..+5s band that characterises a group release. *(An earlier form asserted the "group occupied at
  creation" cohort is 0/15, which is definitionally true under a per-SHA key — it restated the
  change instead of testing it, and read the shared `main` stream in the shape
  `cq-ac-must-not-depend-on-concurrent-sessions` warns about.)*

- **AC-P2** Report `time-to-test` median and max for those runs against the pre-change
  `med 2196s / max 4156s`. A median regression > 20% is the rollback trigger for Phase D.

- **AC-P3** Report within-run start spread median/max against `med 218s / max 1708s`, to size
  whether per-SHA concurrency worsened pool contention.

- **AC-P4** The first post-merge `main` push produces a deploy run triggered by `workflow_run`,
  not by `push`.

- **AC-P5** That deploy's resolved SHA equals the merge commit SHA.
- **AC-P6** `live-verify` **ran** (conclusion `success`), not `skipped`.
- **AC-P7** The relocated soft-ceiling step emitted its measurement line, and its computed
  reference equals `0.7 × (DRIFT_SUSTAINED_THRESHOLD_MIN − 135) × 60` seconds.

- **AC-P8** No double-deploy observed across the transition: at most one `deploy` job per SHA,
  **and** no `deploy` concluded `cancelled` while pending — the `web-1-swap` group keeps one running
  plus one pending and cancels an older pending run when a third arrives.

- **AC-P9** Across the first 15 post-merge deploys the live production version is **monotonically
  non-decreasing** (Decision 5). This is the detector for the out-of-order hazard Phase D creates
  and Phase E exposes.

- **AC-P10** A synthetic non-success CI conclusion on `main` produces **exactly one**
  `notify-gated` post, and a docs-only push produces **zero** (E.4a).

Each post-merge AC is a `gh api` query executed by the pipeline, not a dashboard reading
(`hr-no-dashboard-eyeball-pull-data-yourself`).

---

## Guard Contract

> **Format note (2026-09-10).** These matrices shipped as numbered lists and are now
> tables, which is the shape `scripts/lint-guard-contract.py` counts. The `Shipped as`
> column records what the implemented suite actually does, so this plan doubles as the
> record: rows that changed during implementation say so rather than being quietly
> restated.

### Guard 1 — the concurrency key is per-SHA on non-PR events

**Property.** No two `main` pushes share a CI concurrency group.

**Assembly.** The single `concurrency:` block at the top of `.github/workflows/ci.yml`. This is a
workflow-level key, but job-level `concurrency` coexists with it
(`2026-07-05-cross-pipeline-serialization-via-shared-job-level-concurrency-group`), so the
assembly is **every `concurrency:` mapping in the file**, discovered by structural extraction
(`awk` over `^concurrency:` and `^    concurrency:`), never by a fixed list.

**Mutation matrix.**

| # | Edit | Expected | Shipped as |
|---|---|---|---|
| 1 | Revert `group` to `${{ github.workflow }}-${{ github.ref }}` | RED | mutant 1 |
| 2 | Change the ternary so `push` takes the `github.ref` arm | RED | mutant 2 |
| 3 | Flip `cancel-in-progress` to unconditional `true` (would cancel `main` runs) | RED | mutant 3 |
| 4 | Add a **second**, job-level `concurrency:` keyed on `github.ref` | RED | mutant 4 |
| 5 | Delete the `concurrency:` block entirely | RED, not "0 checked, exit 0" | mutant 5 |
| 6 | **Added at review:** invert `cancel-in-progress` to `!= 'pull_request'` | RED | mutant 6 — this SURVIVED the original battery; P4 used substring containment, which the inversion satisfies |
| 7 | **Added at review:** a job-level **constant** group | RED | mutant 7 — survived; P5 keyed on the literal `github.ref`, so the worse defect passed |
| 8 | **Added at review:** a constant group via the `concurrency: <string>` shorthand | RED | mutant 8 — survived; no fixture instantiated that code path |

**Harness rows.** (a) Delete the guard's own comparison → the suite must RED. (b) A must-PASS
non-canonical input: the same key with different whitespace and a reordered but semantically
identical ternary must PASS.

### Withdrawn — the LPT totality guard (was Guard 2)

> Not a guard entry: LPT is deferred to #8006, so there is no property to state and
> no assembly to enumerate. `plugins/soleur/test/scripts-shard-totality.test.sh` is
> unchanged and still binds — it derives its reference set independently of the
> partition, so it is agnostic to how legs are chosen.

Guard 2's four proposed mutation rows (absent label, phantom label, empty table, second unknown
label) existed **only** to police `scripts/suite-durations.tsv`. Decision 3 defers LPT, so there is
no table, and rows guarding a mechanism that does not ship are ceremony.

`plugins/soleur/test/scripts-shard-totality.test.sh` and
`plugins/soleur/test/scripts-shard-totality-mutations.sh` are therefore **unchanged by this PR** —
P4 (every registration on exactly one leg) is already held structurally at the chokepoint and
neither file needs an edit. AC8 asserts the guard still exits 0 unchanged, which is the whole claim.

The four rows are carried into the deferral issue verbatim, plus the two the review added
(`_shard_selects` argument passing; `skip_suite` label parity), so the next attempt starts from the
finished battery rather than re-deriving it.

### Guard 3 — no `workflow_run`-reachable path reads bare `github.sha`

**Property.** On the `workflow_run` arm, every SHA-valued expression resolves to the event's
`head_sha`, never to the default-branch tip.

**Assembly.** Every `${{ github.sha }}` occurrence in `.github/workflows/web-platform-release.yml`,
discovered by extraction over the file, intersected with the set of jobs reachable on the
`workflow_run` arm (computed from each job's `if:` and the `needs:` closure) — **not** a checked-in
list of the 9 current sites, which would go stale on the next added job.

**Mutation matrix.**

| # | Edit | Expected | Shipped as |
|---|---|---|---|
| 10 | Reintroduce `EXPECTED_SHA: ${{ github.sha }}` | RED | G3-10 |
| 11 | Add a **new** job on the `workflow_run` arm using `${{ github.sha }}` (second-member row) | RED | G3-11 |
| 12 | Restore `live-verify`'s `if: github.event_name == 'push'` (would skip forever) | RED | G3-12 |
| 13 | Delete the job-reachability computation so it checks zero jobs | RED | analyser self-test |
| 13b | Reconstruct `needs.release.result` from "a release object exists" rather than the `release` job's conclusion | RED — the equal-strength row | G3-13b, re-anchored at review on the call form against a comment-stripped haystack: the token form was satisfied by the comment explaining it |

**Harness rows.** (a) Replace the extraction with a hardcoded 9-path list → the suite must RED on
mutation 11, proving the list form is insufficient. (b) Must-PASS: `github.sha` used inside a job
gated `if: github.event_name == 'workflow_dispatch'` is permitted and must PASS.

### Guard 4 — the trigger matches `ci.yml`'s `name:`, not its filename

**Property.** `web-platform-release.yml`'s `workflow_run.workflows` names the exact string
`ci.yml` declares as `name:`.

**Assembly.** `ci.yml`'s `name:` field and every `workflows:` list in the repo that intends to match
it — discovered by grepping `workflow_run:` across `.github/workflows/`, not by naming two files.
`post-merge-monitor.yml` already depends on the same string and must be covered.

**Mutation matrix.**

| # | Edit | Expected | Shipped as |
|---|---|---|---|
| 14 | Change `ci.yml`'s `name:` (both consumers desync) | RED | G4 desync row |
| 15 | Change `web-platform-release.yml`'s `workflows:` entry | RED | G4-15 — this was a SURVIVING mutant until review: the battery's predicate never re-applied the `CI_NAME` comparison, and the row scored KILLED on an unrelated baseline term |
| 16 | Change `post-merge-monitor.yml`'s `workflows:` entry (second-consumer row) | RED | G4 desync row, per consumer |
| 17 | Remove every `workflow_run:` block so the guard has nothing to check | RED, not vacuous pass | G4-17 |

**Harness rows.** (a) Delete the guard's `name:` read → RED. (b) Must-PASS: quoting variation
(`["CI"]` vs `[ CI ]`) is permitted.

### Guard 5 — every ceiling on the new path is derived, never restated

**Property.** `RELEASE_WAIT_S` and the relocated soft ceiling are computed from values read out of
the tree; neither appears as a literal.

**Assembly.** `resolve-target`'s derivation steps (never `deploy`'s — that job may not check out),
plus their **five** inputs: `DRIFT_SUSTAINED_THRESHOLD_MIN`, the `migrate`/`verify-migrations`/
`deploy` `timeout-minutes`, and **CI's own declared to-`test` path** (`test-scripts` +
`test` `timeout-minutes`). This is the successor to `await-ci-ceiling-invariants.test.sh`'s
I3/I3b/I4.

**Why the fifth input is required, and it was missing.** With only the first four, lowering
`test-scripts`' ceiling from 60 to 45 drops `CI_DECLARED_PATH` from 70 to 55 while the soft ceiling
stays pinned at `0.7 x CI_BUDGET_MIN` — the creep detector silently stops tracking the thing it
detects, and row 21 cannot see it because `test-scripts` is not among its inputs. Adding it was meant to turn
the headroom from a coincidence into an asserted invariant. **It could not** — see the superseded
note above: the quantity was to-`test` while the trigger waits for the whole run, so the invariant
was asserted over the wrong term. What ships instead is a refusal to assert it at all while any
`ci.yml` job is unbounded, plus a ratchet on that count (#8020).

**Mutation matrix.**

| # | Edit | Expected | Shipped as |
|---|---|---|---|
| 18 | Replace either derivation with a literal | RED | G5-18 |
| 19 | Change the `0.7` factor so the warning fires at or above its reference | RED | G5-19 |
| 20 | Remove the warning's downstream consumer | RED | G5-20 |
| 21 | Change any one input ceiling and assert the derived value **moves** | RED if it does not | G5-21, re-anchored at review on the **call form**: `grep -qF test` matched inside `test-scripts`, and all names also appear in the step's own error prose |
| 21b | **Added at review:** the extraction crosses a job boundary | RED | extractor-scope self-test — the budget step is its job's LAST step, so the old `awk` ran into `migrate` and captured 251 lines across two jobs |

**Harness rows.** (a) Delete the derivation comparison → RED. (b) Must-PASS: an editorial change to
a comment adjacent to a ceiling must not flip the guard (the existing comment-only negative control,
carried forward from the suite this replaces).

### Guard 7 — the deploy arm distinguishes "correctly no release" from "release is missing"

**Property.** For every `main` CI completion, `resolve-target` reaches exactly one of the five
states in Decision 2, and the two clean-skip states are never conflated with the fail-closed one.

**Assembly.** `resolve-target`'s state resolution and its four inputs: the existence of a
`Web Platform Release` run for the SHA, that run's `release` job conclusion, whether a release was
published, and the elapsed reconcile time. Discovered from the job body, not from a list of
expected states.

**Mutation matrix.**

| # | Edit | Expected | Shipped as |
|---|---|---|---|
| 26 | Collapse "no run exists" into the fail-closed arm (a docs-only push would redden) | RED | G7 clean-skip row |
| 27 | Collapse "`release` failed" into a clean skip (swallows the failure) | RED | G7 fail-closed row, re-anchored at review: the two conjuncts were unrelated greps satisfied anywhere in the block |
| 28 | Remove the "published no release" arm so it falls through to fail-closed (second clean-skip state) | RED | G7 state-coverage row |
| 29 | Make the reconcile unbounded | RED | superseded — the liveness poll is bounded by the release run's own timeout AND unreachable under the shared concurrency group; recorded in the workflow rather than guarded |
| 30 | Make the state resolution return a fixed value so it examines none of its inputs | RED, not vacuous pass | G7 input rows |
| 30b | **Added at review:** a `skip_reason` emitted by the producer and handled by no consumer | RED | Guard 9 set-parity — found `release_outputs_incomplete` named by two consumer arms with no producer |

**Harness rows.** (a) Delete the battery's state-coverage assertion → RED. (b) Must-PASS: a
docs-only-push fixture (CI green on `main`, no `Web Platform Release` run for the SHA) resolves to
a clean skip and the run stays **green**.

### Guard 8 — every consumer selecting a `web-platform-release` run disambiguates the two arms

**Property.** After the split, **every merge produces two runs of `web-platform-release.yml`** — a
push-arm run (release only) and a `workflow_run`-arm run (the deploy). Every in-repo consumer that
selects "the latest `web-platform-release` run" must disambiguate by `event` or by job presence,
or it reads the wrong half roughly half the time.

This is the blast-radius class the plan's original enumeration missed entirely: not a broken
`needs:` edge, but a **silent 50% mis-selection** in the repo's own verification tooling.

**Assembly.** Every `gh run list --workflow=web-platform-release` (and `gh run view` on its result)
call site across `plugins/`, `scripts/`, and `.github/`, discovered by extraction — **not** a
checked-in list, which would miss the next consumer added. Known members at plan time:
`plugins/soleur/skills/postmerge/SKILL.md` (`--limit 1`, then greps for `reason=canary_*` strings
that only the `deploy` job emits — lands on the push-arm run and its Phase 3.7
`GATE-VALIDATED`/`GATE-SUSPECT` classification resolves against an empty log),
`scripts/watch-live-verify-pass.sh` (`--limit 25` scanning for `live-verify`; half the window is now
push-arm runs with no such job, halving the #5463 dark-launch lookback), and
`scheduled-prod-version-drift.yml`'s remediation text.

**Mutation matrix.**

| # | Edit | Expected | Shipped as |
|---|---|---|---|
| 31 | Remove the `--event` (or job-presence) filter from any known consumer | RED | G8 disambiguation row |
| 32 | Add a **new** consumer with an undisambiguated `--limit 1` (second-member row) | RED | G8 discovery row |
| 33 | Delete the call-site extraction so it checks zero consumers | RED, not vacuous pass | G8 non-vacuity floor (>= 5 consumers) |
| 33b | **Added at review:** a consumer written in a spelling the discovery grep does not match | RED | the original discovery found 2 of ~10 sites — it grepped one literal and missed the space form, the variable form, the `gh api .../workflows/<f>/runs` form, and everything under `knowledge-base/` |
| 33c | **Added at review:** a consumer whose arm is named on an adjacent line | must PASS | the predicate now evaluates the enclosing command window, not one grep line |

**Harness rows.** (a) Replace the extraction with a hardcoded three-path list → the suite must RED
on mutation 32. (b) Must-PASS: a consumer that disambiguates by job presence rather than by `event`
is permitted and must PASS.

### Guard 6 — the aggregator's classifier is exhaustive and never swallows a failure

**Property.** Every non-success leg outcome produces a named line, and the job exits non-zero.

**Assembly.** The `Aggregate shard results` step's `run:` body in `ci.yml` — extracted and executed
by the battery, the pattern `scripts/prod-version-drift-check.test.sh` already uses on this repo —
together with the three `needs.*.result` values in its `env:`. No separate script, no `gh api`, no
checkout: the discriminator is a shape comparison over data the job already holds.

**Mutation matrix.**

| # | Edit | Expected | Shipped as |
|---|---|---|---|
| 22 | Remove the `TIMED OUT` branch | RED | mutant 22 |
| 23 | Remove the UNKNOWN fallback so an unclassified `cancelled` produces no line | RED | mutant 23 |
| 24 | Make any non-success leg stop setting `fail=1`, so the job exits 0 | RED — swallowing is the failure mode | mutant 24 |
| 24b | Emit `SUPERSEDED` on a **`push`-event** fixture | RED — after part 1 nothing on `main` is cancelled by supersession | mutant 24b, extended at review to `merge_group` and `workflow_dispatch` (rows E1): `ci.yml` declares four events and only two were fixtured |
| 25 | Make the loop `break` after the first failing leg (second-member row) | RED | mutant 25 |
| 25b | **Added at review:** point the step's `env:` at the wrong shard, or drop a shard from the `test` job's `needs:` | RED | rows W1/W2 — every other row is handed the three values by the harness, so the workflow's own wiring was unasserted |

**Harness rows.** (a) Delete the battery's exit-code assertion → RED. (b) Must-PASS: an all-success
run emits `All three shards green.` and exits 0.

---

## Observability

```yaml
liveness_signal:
  what: "the `test` required check-run on every main-push CI run, and the deploy run's
         time-to-test measurement line on every release"
  cadence: "every main push (12 runs in 9h at peak; 35 in the measured 53h window)"
  alert_target: "GitHub required-check status on the PR / merge queue; the deploy run's
                 ::warning:: annotation surfaces in the release run log and in
                 main-health-monitor.yml"
  configured_in: ".github/workflows/ci.yml (test job), .github/workflows/web-platform-release.yml
                  (deploy arm soft-ceiling step)"
error_reporting:
  destination: "GitHub Actions annotations (::error:: / ::warning::) on the run that produced them,
                plus the notify-gated Slack push for a gated deploy. Observability layer 6 (CI/CD)
                per hr-observability-layer-citation — CI failures are not Sentry-routed; the
                required check and the run annotation ARE the reachable surface, and both are
                readable via `gh run view` with no SSH."
  fail_loud: true
failure_modes:
  - mode: "a test leg exceeds its declared timeout-minutes (CI is too slow)"
    detection: "the aggregator's TIMED OUT line, naming elapsed and the parsed timeout-minutes"
    alert_route: "the `test` required check's own output — visible on the PR without opening a job log"
  - mode: "a test leg is cancelled by a superseding push"
    detection: "the aggregator's SUPERSEDED line"
    alert_route: "same required check output; distinguishable from the row above, which is the
                  whole point of #7931 part 2"
  - mode: "a leg's cause cannot be determined"
    detection: "the UNKNOWN line, carrying elapsed and the declared budget so a reader can judge"
    alert_route: "same; an honest UNKNOWN rather than a third confident mechanism"
  - mode: "the aggregator's own gh api fetch fails"
    detection: "::warning:: naming the fetch failure, plus the pre-change bare `shard: result` line"
    alert_route: "the job still exits 1; the diagnosis is additive and can never swallow a failure"
  - mode: "the workflow_run trigger does not fire (name desync, filter too tight, default-branch
           file lacking the trigger) — NO run is produced, the quietest failure in this plan"
    detection: "prod-version-drift-check.sh's sustained-drift check: a merged qualifying commit
                undeployed past DRIFT_SUSTAINED_THRESHOLD_MIN. This is the existing detector and it
                is the only one that can see absence-of-a-run, which no in-run signal can."
    alert_route: "the drift check's existing alert path"
  - mode: "CI creeps toward the pipeline's declared budget"
    detection: "the relocated soft-ceiling ::warning:: at 0.7x CI's derived share, measured on
                every release (ADR-212 Decision 4, preserved)"
    alert_route: "release run annotation; consumed by a downstream job so it cannot be silent"
  - mode: "the suite-duration table goes stale"
    detection: "the same-run freshness ::warning:: naming each drifted entry"
    alert_route: "the test-scripts job log; warning only, never a failure (load alone moves a
                  suite 1.9x, so a hard gate would red CI on noise)"
logs:
  where: "GitHub Actions run logs; per-suite timings additionally retained as the TEST_TIMING_LOG
          artifact per shard"
  retention: "GitHub Actions default (90 days for logs; artifact retention as configured)"
discoverability_test:
  command: "bash plugins/soleur/test/workflow-run-deploy-invariants.test.sh && bash plugins/soleur/test/ci-test-aggregator-diagnosis.test.sh"
  expected_output: "both suites exit 0 and each reports a row count at or above its declared
                    assertion floor"
```

The `workflow_run trigger does not fire` row is the one that matters most and the one an in-run
probe structurally cannot cover — a run that never starts emits nothing. It is deliberately routed
to the pre-existing drift check rather than to a new detector, which is also why Phase E must not
weaken `DRIFT_SUSTAINED_THRESHOLD_MIN`.

### Soak follow-through enrollment

AC-P1..AC-P3 are measured over the first 15 post-merge `main` pushes, which is a soak, not an
instant. `scripts/followthroughs/ci-concurrency-cohort-7931.sh` re-runs §Measurement's command,
exits 0 when the "group occupied at creation" cohort is 0 and the `time-to-test` median has not
regressed >20%, and is enrolled on the tracker with
`<!-- soleur:followthrough script=scripts/followthroughs/ci-concurrency-cohort-7931.sh earliest=<merge+3d> -->`
plus the `follow-through` label, so closure is automated rather than remembered.

---

## Architecture Decision (ADR/C4)

Detection fires: this changes a **dispatch / trust boundary** (what triggers a production deploy,
and where the deploying identity's SHA comes from) and **reverses a deferral recorded in an existing
ADR**. The ADR and the C4 assessment are deliverables of this plan, not follow-ups
(`wg-architecture-decision-is-a-plan-deliverable`).

### ADR

**Create ADR-214 (provisional)** — *"The deploy is triggered by CI's completion event, and the SHA
it deploys comes from that event."* Decision, in four parts:

1. The prod deploy chain fires on `workflow_run: completed` for `ci.yml`, filtered
   `head_branch == 'main' && conclusion == 'success' && event == 'push'` with a `^[0-9a-f]{40}$`
   `head_sha`. ADR-072 option 3 is **adopted**.

2. `release` stays on `push` — the measured `max(release, CI) == CI` (14/14 runs, min lead
   +11.5 min) means serialising it buys nothing and costs ~7 min per deploy.

3. Under `workflow_run`, `github.sha` is the default-branch tip and is therefore **banned** on
   every reachable path; identity comes from the event. This closes the fail-open ADR-072's
   amendment named. Enforced by Guard 3, not by review.

4. ADR-212 Decision 4's creep detector is **relocated**, not deleted, with its reference derived
   from `DRIFT_SUSTAINED_THRESHOLD_MIN` rather than from a fresh unowned number.

Also recorded: the per-SHA concurrency key is a **semantic** correction (the gated quantity becomes
a property of the SHA being gated), the measured 20%/80% cohort split, and the correction of
ADR-212's "would break the audit trail" clause.

**Amend ADR-072** — option 3 moves from `Alternatives Considered (deferred)` to adopted, with the
fail-open closed and Phase C still rejected. **Amend ADR-212** — `Named residual` gets the
population statistic; Decision 4 gets its relocation note.

**Ordinal is provisional.** ADR-213 is already claimed on a pushed branch. Re-probe across all
`origin/*` refs before merge and after every rebase; on renumber, sweep
`knowledge-base/project/{plans,specs}/` for the old ordinal in the same edit.

### C4 views

**Verdict: no `.c4` element, relationship, or view line changes.** All three of
`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}` were read in full —
not grepped for the feature's own noun — and the completeness enumeration this conclusion cites is:

- **External human actors.** Four are modeled (`founder`, `emailSender`, `betaContact`,
  `contributor`). Only `contributor` touches CI, and it is scoped to ADR-074 fix-constraints
  generating an import-boundary gate into a *customer's* product codebase
  (`constraintscaffold -> webapp "Generates L1 import-boundary gate (CI)"`), not into Soleur's own
  `ci.yml`. **No new actor, none falsified.**

- **External systems / vendors on the release-deploy path.** `github`, `ghcr`, `zotRegistry`,
  `sigstore`, `sentry`, `resend`, `betterstack`, `cloudflare`, `doppler` are all modeled. Each
  describes release *behavior* (image push/pull, signing, alerting, drift probing) at C4 altitude.
  Changing which *event* starts the deploy adds no vendor and falsifies no description.

- **Containers / data stores.** `webapp`, `hetzner`, `tunnel`, `zotRegistry`, `ghcr`. **No new
  store, no changed store.**

- **Actor↔surface / system↔system access relationships.** Seven edges mention CI/release/deploy/
  workflow/gate; each was checked individually. `github -> webapp` (the drift probe) describes a
  detector that is independent of whether the gate polls or is event-triggered — and the `deploy`
  job it refers to still exists and can still be skipped. `github -> tunnel` describes the
  *transport* for the push/deploy, not the trigger. `github -> sentry` names `live-verify` and
  `release-outcome`, both of which survive Phase E under the same names. **No access relationship
  changes** — the deploying identity is unchanged; only the trigger and the SHA source move.
  Direct grep confirms **zero** occurrences of `await`, `test-all.sh`, or `test-shard` anywhere in
  the three files, and the only `concurrency` hits are the Hook Engine's session-state lock, an
  unrelated sense of the word.

- **Derived cardinalities** (the class the actor/system rubric does *not* reach, and which
  `c4-count-parity` gates as required context). Two edges embed counts: `github -> sentry`
  (11 workflows / 6 scheduled / 5 dispatch-only / 56 monitors / 12 here / 44 webapp) and
  `github -> resend` (thirteen emitters). Neither `ci.yml` nor `web-platform-release.yml` nor
  `reusable-release.yml` uses the `actions/sentry-heartbeat` composite, so the Sentry counts are
  untouched; the two release workflows *do* match the Resend-emitter derivation, but Phase E adds,
  removes and renames no `api.resend.com` / `notify-ops-email` call site.
  **`bash plugins/soleur/test/c4-count-parity.test.sh` run at plan time: exit 0, 10 passed,
  0 failed (C1–C7 all green).** F.3 re-runs it after the workflow edits rather than relying on this
  reasoning, and any count it moves is edited in the same commit.

- Note: `plugins/soleur/test/await-ci-ceiling-invariants.test.sh` *does* assert on `await-ci`
  sizing, but grep confirms it carries no `.c4` reference — it is a CI-config invariant suite, not
  a C4-parity test, and is handled on its own merits in Phase E.8.

### Sequencing

The decision is true the moment Phase E merges, so ADR-214 is authored `status: accepted`, not
`adopting` — there is no interval during which it is only partly true. The post-merge ACs verify
the decision held; they do not decide whether it is adopted.

---

## Domain Review

**Domains relevant:** engineering

### Engineering

**Status:** reviewed
**Assessment:** The `soleur:engineering:cto` domain leader was consulted on the four forks this
plan decides (the release/deploy split, the per-SHA key's non-contention hazards, the derived
soft-ceiling reference, and first-merge reachability of the new trigger). Its findings are folded
into §Decisions, §Risks and the Guard Contract above; where it disagreed with a draft position, the
plan carries the corrected position and the reason. The independent C4 completeness pass (all three
`.c4` files read in full, `c4-count-parity` exit 0) is recorded under §Architecture Decision.

**Brainstorm-recommended specialists:** none — no brainstorm preceded this plan (one-shot entry).

### Product/UX Gate

Not applicable. The mechanical UI-surface override was evaluated against every path in
`## Files to Edit` and `## Files to Create`: all are `.github/workflows/*.yml`, `scripts/*`,
`plugins/soleur/test/*`, `knowledge-base/**`. No path matches `components/**/*.tsx`,
`app/**/page.tsx`, `app/**/layout.tsx`, or any term in the shared UI-surface list. Product tier:
**NONE**.

### Compliance gates

- **GDPR (Phase 2.7):** skipped. No regulated-data surface is touched — the edit set contains no
  schema, no migration, no auth flow, no API route, and no `.sql` file. None of the four expansion
  triggers fire: no LLM or external-API processing of session-derived data, no new scheduled job
  reading `learnings/` or `specs/`, and no new artifact distribution surface. The
  `single-user incident` threshold fires on the *brand* axis, which is discharged by
  `## User-Brand Impact` plus `user-impact-reviewer` at review — not by a data-protection finding.

- **Infrastructure-as-Code routing (Phase 2.8):** skipped. This plan provisions nothing: no host,
  no service unit, no scheduled job, no vendor account, no DNS record, no TLS certificate, no new
  credential, no firewall rule, and no monitoring webhook. Every change is to files already tracked
  in the repository and already applied by existing pipelines. The detection scan over this plan's
  own prose returns no shell-into-a-host verb, no credential-write verb, no vendor-console step,
  and no state-import step.

- **Encryption posture (Phase 2.11):** skipped. No persistent store and no new cross-component
  connection. No path in the edit set matches `\.tf$`, `supabase/migrations/.*\.sql$`,
  `cloud-init.*\.ya?ml$`, or `docker-compose.*\.ya?ml$`.

---

## Risks & Mitigations

| # | Risk | Mitigation |
|---|---|---|
| R1 | **Per-SHA concurrency worsens the median.** The pool is the binding constraint on 80% of runs; more concurrent runs draw on it harder. | AC-P2/AC-P3 measure the same statistics post-merge with the same command. **Rollback trigger: a `time-to-test` median regression > 20% reverts Phase D alone** — it is a one-line change in a separate commit, revertible without touching E. |
| R2 | **The `workflow_run` trigger silently never fires.** The quietest failure in the plan: no run, no annotation, nothing to grep. | Guard 4 (name parity, covering both consumers) pre-merge; the pre-existing drift check post-merge, which is the only detector that can see an absent run; declared rollback window (§Verification layer 4). |
| R3 | **A `github.sha` consumer is missed**, deploying an image built from the default-branch tip while `EXPECTED_SHA` compares it against the same wrong value and passes. | Guard 3, whose assembly is *computed* (reachable-job closure ∩ extracted occurrences), with an explicit harness row proving a hardcoded 9-path list would miss a newly added job. |
| R4 | **CI completes before `release` publishes.** Measured minimum lead +11.5 min, but empirical, not a bound. | Bounded reconcile with `RELEASE_WAIT_S` derived from `release`'s own declared `timeout-minutes` (Decision 2, Guard 5). Fail-closed with a named error, never a silent skip. |
| R5 | **The invariants suite is deleted rather than rewritten**, taking I3/I3b/I4's protection with it. | E.8 makes the rewrite a same-commit requirement; AC10 asserts `MIN_ROWS >= 14`; Guard 5 carries I3/I3b/I4 forward onto the new subject. |
| R6 | **The duration table goes stale and nobody notices.** | Same-run freshness warning (C.5); the refresh is one command over an artifact the run already produced; and the failure mode is bounded — worse balance, never lost totality (Decision 3a). |
| R7 | **`DRIFT_SUSTAINED_THRESHOLD_MIN` silently becomes wrong**, so the only absent-run detector mis-sizes. | E.9 runs B9's own extraction rather than reasoning about the arithmetic; AC14. |
| R7b | **Deleting `await-ci` drives B9 red on a correct change.** The `deploy` job's own coupling comment records that *an absent ceiling reads as the GitHub 360 default, not as zero* — so a name-keyed extraction would compute `max(60, 360) + 135 = 495 > 207`. | E.9 determines B9's extraction shape (name-keyed vs job-enumerating) **before** the job is removed and adjusts it in the same commit. AC14 is the gate. |
| R7c | **Three files disagree about the critical path today.** `web-platform-release.yml`'s `deploy` comment still says `max(release 60, await-ci 60) … = 195` while `prod-version-drift-check.sh` says 207. | E.9 reconciles all three (workflow comment, drift script, B9) in one commit — the stale comment is fixed regardless of #5806. |
| R7d | **The `workflow_run` arm inherits neither path gate.** `on.push.paths` (GitHub glob dialect) and `reusable-release.yml`'s inner `check_changed` (git-pathspec dialect) both cease to gate the deploy chain. Naive handling reddens the release run on every docs-only main push and destroys the "release missing" signal. | Decision 2's five-state resolution re-establishes both gates inside `resolve-target`; Guard 7 drives red on either collapse; AC17b and T21–T25. |
| R8 | **Double deploy across the transition.** | The existing **`web-1-swap`** cross-pipeline mutex serialises (note: *not* `deploy-web-platform` — renamed in #6060, and the parity guard greps to stop the old name returning); deploys are idempotent per SHA+version; AC-P8. |
| R8b | **`web-1-swap` gains contenders on a lock that already arbitrates infra applies and LUKS cutovers.** It is taken at 9 sites across four workflows (8 job-level, 1 workflow-level), and GitHub's single-pending-slot rule can silently cancel a *pending* infra apply. Per-SHA CI plus a `workflow_run` deploy arm puts more traffic on it. | Not a reason to abandon the design, but it widens Phase D's rollback rationale beyond runner contention. E.4c makes the parity guard a lockstep edit; AC-P9 measures `web-1-swap` queueing post-merge. |
| R8c | **`release-outcome` — the operator's only non-delivery signal — is single-run and would report success on the push arm.** | E.4b rehomes it to the `workflow_run` arm and recovers the `release` verdict from `resolve-target`'s existing lookup; Guard 8; AC20. Explicitly **not** deferred alongside item 4. |
| R9 | **PR size.** Five phases across three workflow files, four scripts, four test suites, three ADRs. | Phases are independently revertible in commit order (A doc-only, B aggregator, C shard, D one line, E topology). If review judges E too large to land with A–D, E splits into its own PR **after** D — never before, or the gate loses its queue-free measurement baseline. |
| R11 | **Phase E widens the announcement/deploy gap it does not close.** Today `release` and `await-ci` at least sit in one run; afterwards they are separate runs with no edge, so a silent no-deploy is announced as a success and the only detector is the ~3.5 h drift check. | Deferral filed at **P2 with a dated trigger** (§Deferrals) rather than "when observed"; `notify-gated` is rehomed onto the new arm so the *gated* case still pushes; the residual is the never-fired case, which R2's guards and the drift check cover. Named here rather than left implicit. |
| R10 | **The K table is re-simulated on a suite set this PR itself changes** (it adds three `plugins/soleur/test/*.test.sh` files, all glob-discovered). | C.6 re-simulates *after* the new suites are registered, and under LPT the known-label assignment no longer depends on ordinal position — which is the whole point of part 3. |

---

## Non-Goals

- **The superseded-SHA "Phase C" guard, in its GIT-ANCESTRY form.** Designed and rejected in
  ADR-072 review: keying on `git rev-parse origin/main` false-skips nearly every deploy because
  `origin/main` advances on every merge, the `deploy` job performs no `actions/checkout` so any
  git-ancestry logic is a permanent silent no-op, and a step-level `exit 0` leaves later verify
  steps polling for the wrong version. **Not reintroduced under any name.**
  **Scope note (amended at plan review):** the prohibition covers the git-ancestry mechanism and its
  three named defects — it is *not* a ban on ordering guarantees as such. Decision 5's
  monotonic-version precondition compares the resolved release version against the version already
  live, a value `deploy` already fetches over the webhook: no `origin/main`, no ancestry, no
  checkout, no step-level `exit 0`. Reading the ban as covering it would leave P6's "in order" claim
  unbacked, which is how the hazard Decision 5 names would ship.

- **Lowering `CEILING_S`** to harvest the headroom Phase D creates (Phase D.4).
- **Choosing a new K.** `ci.yml` records that K=3 is no longer known-optimal on the shipping order.
  LPT changes the balance function; re-deriving K is a separate decision over the post-LPT
  distribution and is deferred (§Deferrals).

- **Editing ADR-208**, which has nothing to do with CI.
- **Gating the release announcement on deploy-success** (§Deferrals).

## Deferrals (each gets a filed issue in the same PR)

| Deferred | Why | Re-evaluation criterion |
|---|---|---|
| #5806 item 4 — gate the "v0.X.Y released!" Slack/email on deploy-success — **FILED: #8007 (P2)** | Under the new topology the announcement and the deploy live in **different workflow runs**, so it stops being a `needs:` edge and becomes a cross-run notification — a different design than #5806 sketched. `reusable-release.yml`'s second consumer (`version-bump-and-release.yml`, component `plugin`) has **no deploy at all**, so any gate needs a `workflow_call` input to stay safe for it. **The deferral is on the mechanism, not on the risk** — see the priority note below. | **Fixed date, not an observed incident:** re-evaluate when this plan's own AC-P1..AC-P3 soak closes (merge + 3 days). File at **P2**, not P3. |

**Why item 4's deferral is filed at P2 with a dated trigger** (CPO plan-review finding, folded in).
After Phase E the announcement and the deploy live in different workflow runs with **no edge
between them at all** — strictly *less* coupled than today's unwired `needs:` gap that #5806 flagged.
So the exact scenario this plan's own `## User-Brand Impact` names — green PR, published Release,
"v0.X.Y released!" in Slack, site still on the old build — becomes **easier** to hit silently after
this ships, and its only remaining detector is the drift check at
`DRIFT_SUSTAINED_THRESHOLD_MIN = 207 min` (~3.5 h). A re-evaluation criterion of *"the first time a
misleading message is observed"* would mean waiting for the incident the `single-user incident`
threshold exists to prevent. The mechanism is genuinely a separate design and stays deferred; the
**risk is not deferred** — it is filed at P2 with a date, and named in R11 below.
| **LPT matrix-leg assignment (#7931 part 3)** — **FILED: #8006 (P3)** | Decision 3: LPT does not deliver P3 (a duration refresh re-rolls other labels) and `_shard_selects` cannot compute it — it is called once per streaming registration and cannot see the live set at first call. The brief's own gate authorises deferral in exactly this case. Phase C still lands the `TEST_TIMING_LOG` binding so the next attempt has CI-measured data. | After AC-P1..AC-P3 close, using the artifacts Phase C starts collecting. The issue carries the six mutation rows already designed and the three constraints in C.2, plus the K=5 alternative (`ci.yml`: K=3 -> 20.73 min, K=5 -> 10.77 min). |
| #7942 (`*.mutation.sh` orphan batteries) — **reciprocal note posted** | Acknowledged, not folded — see §Open Code-Review Overlap. | Already tracked in #7942; add the reciprocal note when this merges. |

---

## Test Scenarios

Every scenario below is `mutation → guard reddens`, not `command → terminal output` — the shape
ADR-180 requires of a change whose deliverable includes guards.

| # | Mutation | Expected |
|---|---|---|
| T1 | `concurrency.group` reverted to `github.ref` | `ci-concurrency-key.test.sh` RED |
| T2 | A job-level `concurrency:` keyed on `github.ref` added to `test-scripts` | Guard 1 RED (second-member) |
| T3 | The `concurrency:` block deleted entirely | Guard 1 RED, not vacuous pass |
| T4 | `TEST_TIMING_LOG` binding removed from a `test-scripts` leg | AC7 RED — the artifact is empty or absent |
| T5 | `scripts-shard-totality.test.sh` run against the post-Phase-C tree | PASS unchanged — Phase C changes no assignment |
| T6 | A new glob-discovered suite added | totality holds (structural at the chokepoint); leg composition moves, which is the deferred problem, not a regression |
| T7 | `EXPECTED_SHA: ${{ github.sha }}` reintroduced | `workflow-run-deploy-invariants.test.sh` RED |
| T8 | A **new** `workflow_run`-arm job added using `${{ github.sha }}` | Guard 3 RED; a hardcoded 9-path variant must fail to catch it (harness row) |
| T9 | `live-verify`'s `if:` restored to `github.event_name == 'push'` | Guard 3 RED |
| T10 | `ci.yml`'s `name:` changed | Guard 4 RED for **both** `web-platform-release.yml` and `post-merge-monitor.yml` |
| T11 | The soft-ceiling derivation replaced with a literal | Guard 5 RED (I3 successor) |
| T12 | The `0.7` factor raised to `1.1` | Guard 5 RED (I3b successor) |
| T13 | The soft-ceiling output's consumer removed | Guard 5 RED (I4 successor) |
| T14 | `migrate`'s `timeout-minutes` changed | Guard 5's derived value must move; RED if it does not |
| T15 | The aggregator's `TIMED OUT` branch removed | `ci-test-aggregator-diagnosis.test.sh` RED |
| T16 | The aggregator's `gh api` failure path changed to `exit 0` | Guard 6 RED |
| T17 | The aggregator loop `break`s after the first failing leg | Guard 6 RED (two legs fail, one named) |
| T18 | Comment-only edit adjacent to any guarded constant | every guard PASSES (must-pass negative control) |
| T19 | `DRIFT_SUSTAINED_THRESHOLD_MIN` lowered below the new critical path | B9 RED |
| T20 | A new `test-scripts` leg added (`shard: ["1/4"…]`) without updating the totality guard's N | existing battery row 5 RED |
| T21 | Docs-only main push fixture (CI green, no `Web Platform Release` run for the SHA) | Guard 7 must-PASS: clean skip, run **green** |
| T22 | "no run exists" collapsed into the fail-closed arm | Guard 7 RED |
| T23 | "`release` failed" collapsed into a clean skip | Guard 7 RED (swallowed failure) |
| T24 | The `check_changed` no-op arm removed so it falls through to fail-closed | Guard 7 RED (second clean-skip state) |
| T25 | `RELEASE_WAIT_S` removed so the reconcile is unbounded | Guard 7 RED (reintroduces the held runner #5806 removes) |

---

## Plan Review Revisions

A six-reviewer panel ran against v1 (DHH, Kieran, code-simplicity, architecture-strategist,
spec-flow-analyzer, CPO, plus the engineering CTO domain leader). Two of its findings would have
shipped a deploy chain that could not fire. Recorded here so the next reader sees what moved and
why, rather than inheriting v1's shape from a stale citation.

**Corrections that changed behaviour (mechanical, applied):**

| # | Finding | Where it landed |
|---|---|---|
| 1 | **The deploy could never fire.** `migrate.if`/`deploy.if` are built on non-tolerant conjuncts over `needs.release.*` and `needs.verify-doppler-secrets.result`, all of which resolve `skipped`/`''` on the `workflow_run` arm. | Decision 2 gained the per-predicate **equal-strength** reconstruction table; `resolve-target`'s output set grew from 3 to 8; `verify-doppler-secrets` moved arms; Guard 3 widened from "bare `github.sha`" to "any `needs.release.*` on a reachable path" |
| 2 | **The release lookup can find its own run.** Both arms produce runs for the same `head_sha`; the `workflow_run` one has `release` skipped, so an unfiltered query resolves "published nothing → clean skip" for a SHA that did publish. | Decision 2: query pinned to `?event=push&head_sha=`, `github.run_id` excluded; Guard 7 row |
| 3 | **Phase D deletes the ordering Phase E's P6 relies on.** Serial main CI is what made deploy completions FIFO; per-SHA groups remove it, and `workflow_run` gives correct-SHA, not latest-SHA. | New **Decision 5** (monotonic-version precondition); §Non-Goals scoped to the git-ancestry form of Phase C; AC-P9 |
| 4 | **CI red on `main` would have been silent.** `notify-gated` fires on `needs.await-ci.result`; with that job deleted, "gated" was undefined and `release-outcome` treats `skipped` as not-a-fault. | E.4a specifies the predicate verbatim on `conclusion != 'success'`; AC-P10; Guard 7 rows |
| 5 | **`release-outcome` — the operator's only non-delivery signal — is single-run.** | E.4b rehomes it and recovers the `release` verdict from `resolve-target`'s existing lookup |
| 6 | **Run-doubling breaks every "latest release run" consumer** (`postmerge/SKILL.md` `--limit 1`, `watch-live-verify-pass.sh` `--limit 25`, `ship/SKILL.md`'s admin-merge guidance, which *inverts*). | New **Guard 8**; six files added to `## Files to Edit` |
| 7 | **B8e as well as B9.** `DEPLOY_NEEDS_CLOSURE` pins the closure as a literal string naming `await-ci` and `release`. | E.9 and AC14 cover both as **certain** reds |
| 8 | **`deploy` may not check out** (in-file prohibition: ~1.5k files onto the `web-1-swap` lock holder). v1 required it to parse four values from the tree. | All derivation moved to `resolve-target`; `RELEASE_WAIT_S` replaced by the liveness-poll pattern `await-ci` already uses, removing the ceiling entirely |
| 9 | **72 and 70 were used interchangeably.** | Decision 4 separates `CI_BUDGET_MIN` (72) from `CI_DECLARED_PATH` (70) and Guard 5 gained a fifth input so a `test-scripts` ceiling change moves the detector |
| 10 | **`branches: [main]` was omitted** while citing the precedent that has it. | E.1 |
| 11 | **AC defects:** AC1 printed rather than asserted; AC3's `git diff` was vacuous on a committed branch; AC5's `grep -cE '\b(60\|3600)\b'` forbade the arithmetic B.4 mandated and aborts under `set -e`; AC13 forbade comments Phase E requires; AC-P1 was a tautology. | All five rewritten |

**Scope reductions (two panels fired on the same scope — the skill's rule is prefer delete):**

- **LPT deferred** (Decision 3). Not on the drift story, which held, but because LPT does not deliver
  P3 and `_shard_selects` cannot compute it. Removes 2 scripts, 1 data file, the freshness warning
  and 4 mutation rows.

- **Phase B's checkout, `gh api` and new script cut.** The discriminator is a shape comparison over
  the three `needs.*.result` strings the job already holds — and it is correct whether GitHub reports
  a timed-out job as `cancelled` or `failure`, which the elapsed-vs-budget form had to assume.

- **Guard rows trimmed** where three rows said "delete the thing entirely → RED", which is what an
  assertion floor is for.

**Surfaced, not applied** — see `knowledge-base/project/specs/<branch>/decision-challenges.md`:
the four-PR split (three reviewers), #5806 item 4's priority, and #5806's milestone.

---

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6. This one is filled.

- **The ADR ordinal in this plan is provisional.** ADR-213 is already claimed on a pushed branch,
  and `main` moves under a long session. Re-probe across all `origin/*` refs immediately before
  merge; on renumber, sweep this plan and `specs/<branch>/` in the same edit.

- **`gh api --jq` does not forward `--arg`.** Every query in this plan is two-stage
  (`gh api ... > f.json; jq --arg ... f.json`). A single-stage form fails at runtime with
  `unknown arguments`, silently returning nothing — which in §Measurement's shape looks like
  "no data" rather than "broken command".

- **`bash -n` cannot validate a workflow file.** Use `actionlint` for the YAML and
  `bash -c '<extracted run: snippet>'` for embedded shell. `actionlint` must **not** be pointed at
  a composite action definition — it emits spurious schema errors against that shape.

- **A leg killed by `timeout-minutes` produces no annotation.** That silence is the reason #7931
  part 2 exists, and it is also why the aggregator must parse the declared value rather than infer
  the cause from GitHub's own reporting.

- **This plan's own prose trips the IaC write guard if it quotes detection tokens.** The Phase 2.8
  rationale above deliberately describes what is absent without reproducing the literal shell-verb
  and credential-write strings the guard scans for. Keep it that way on any edit.
