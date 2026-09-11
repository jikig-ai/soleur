---
title: "ADR-217: The deploy fires on CI's completion event, and the verdict never crosses as a value"
status: Accepted
date: 2026-09-09
supersedes: []
amends:

  - ADR-072
  - ADR-212
tags: [ci, deploy, release, concurrency, observability]
---

# ADR-217: The deploy fires on CI's completion event, and the verdict never crosses as a value

## Status

Accepted — 2026-09-09. Closes #5806 and #7931 parts 1–2. Part 3 is deferred with
its own issue (see [Consequences](#consequences)).

## Context

Two changes land together because they interact, and the interaction is the part
neither issue anticipated.

### The deploy gate polled for a verdict it could have been told about

`web-platform-release.yml` carried an `await-ci` job that polled the REST API for
CI's verdict on the SHA being released, holding an idle GitHub-hosted runner for
up to 72 minutes and **failing closed** when CI outran its ceiling. That is the

#7902 symptom: a healthy build that could not deploy.

ADR-072 shipped an adaptive wait as the minimal robust fix and recorded the
structural alternative — option 3, fire on `workflow_run: completed` — as
deferred. The adaptive wait widens the cliff (≈15m → ≈50m); it does not remove
it. **A fixed ceiling on an unbounded, growing quantity is the actual defect**,
and no amount of ceiling-sizing addresses it.

### The gate measured a quantity that belonged to a different commit

`ci.yml` grouped concurrency on `${{ github.workflow }}-${{ github.ref }}`. On
`main`, `github.ref` is **constant**, so every push shared one group; with
`cancel-in-progress` false there, "let prior runs finish" is *serialize*.

The consequence is not primarily wall clock. A run's gated quantity —
time-to-`test`, measured from that run's own `created_at` — **contained the
previous run's entire time-to-`test`**. That is an unbounded term belonging to a
different commit. No declared ceiling has ever had a place for it, and no
ceiling-sizing can bound it, because it is not a property of the run being
measured.

### What the measurement actually says

ADR-212's `Named residual` called the concurrency queue "the dominant term". It
is not, across the population. Measured over 29 consecutive `main` push runs
(2026-09-07T09:02:01Z → 2026-09-09T07:50:05Z; raw `jobs.tsv` committed at
`knowledge-base/project/specs/feat-one-shot-7931-5806-ci-concurrency-and-workflow-run-deploy/measurement-jobs-2026-09-09.tsv`):

| cohort | n | first-job delay | queue term | start spread (needs-less jobs) |
|---|---|---|---|---|
| group **occupied** at creation | 7 (24%) | med 460s, max 1249s | med 393s, max 1245s | med 68s, max 913s |
| group **drained** at creation | 22 (76%) | med 4s, max 731s | 0 | med 412s, max 1708s |
| all | 29 | — | — | med 292s, max 1708s |

The model is **additive, not either/or**:
`time-to-test = queue (only when the group is occupied) + runner availability + execution`.
The queue is real, bounded and intermittent; runner availability is the larger
term overall. The window's worst time-to-`test` (4156s) came from a run whose
group was **empty**.

> **On reproducing this table.** An earlier reading over a population reported as
> 35 published med 332s / max 1708s for the drained spread and a 20%/80% split.
> Re-derived at 29 runs it is med 412s / max 1708s and 24%/76%. Every **maximum**
> and the **entire occupied cohort** reproduce to the second; the medians and the
> population do not. The 6-run delta has a **candidate explanation, not a
> confirmed one**: the two readings covered different windows. This table's
> window was originally labelled as ending `2026-09-09T14:22Z`, but the committed
> TSV's last run was created `2026-09-09T07:50:05Z` — the label was ~6.5h wider
> than the data. Six additional runs in that 6.5h tail is a plausible rate
> (~22/day against the window's ~14.5/day average) but is not established, and
> the tail's runs are not in the committed file, so it cannot be settled from
> what is here. Paginated double-counting was tested and excluded — zero
> duplicate run ids. To settle it, re-run the command in `ci.yml`'s dispatch note
> over the wider window and compare run-id sets. The
> conclusions below are invariant across both readings, which is why they are
> stated as cohort shape. **Do not cite a median from this ADR without re-running
> the command in `ci.yml`'s dispatch note.**

## Decision

### 1. The `main` concurrency key is per-SHA, justified on semantics

```yaml
group: ${{ github.workflow }}-${{ github.event_name == 'pull_request' && github.ref || github.sha }}
```

Each `main` push is a distinct SHA needing its own CI verdict for its own deploy
gate. Per-SHA grouping makes the gated quantity a property of the SHA being
gated. That is a correctness statement about what the number *means*, and it
holds on 100% of runs regardless of the queue's magnitude.

**It is not sold as a speed fix.** The median saving is zero — the median run has
no queue term to remove.

**Nothing is cancelled on `main` under either key.** `cancel-in-progress` stays
`pull_request`-only; prior runs still run to completion and the audit trail is
byte-identically intact. ADR-212's claim that this "would break" the audit trail
is superseded there; the two properties were never in tension.

**The real cost:** peak concurrent `main` CI runs rises from 1 to the burst
depth, on the pool the measurement identifies as the binding constraint for 76%
of runs. This can make the median worse. Measured post-merge, not assumed.

### 2. The deploy fires on `workflow_run: completed`, and the verdict never crosses as a value

`release` stays on `push`; only the deploy chain moves. Full serialisation was
rejected on measurement — `release` beat `await-ci` in 14/14 runs at a median
+29.2 min lead, so `max(release, CI)` is empirically already `CI`.

**The trust ladder is the decision.** The REST jobs API exposes a job's
`conclusion` but **not** its `outputs` — verified against a live run, the job
object carries no `outputs` key at all. So the two halves come from different
sources at different trust levels:

| what | from | why |
|---|---|---|
| **the verdict** (`release.result`) | the jobs API, always | the only thing between a mirror-gate-blocked release and a prod deploy of an unmirrored image |
| **the values** (`version`, `tag`, `docker_pushed`, `mirror_verified`) | an artifact `reusable-release.yml` uploads | read from the same step outputs the job's `outputs:` block reads, so identical to what `needs` delivers |

**The prohibition that carries the whole design:** `resolve-target` must never
substitute the artifact's `mirror_verified` for the API conclusion read.
`docker_pushed` is written **ten steps before** the zot mirror assertion (so it
reads `true` on a release the gate *blocked*), and `mirror_verified` is
documented at FR-A9 as *"DELIBERATELY NOT a blocking conjunct … legibility after
the fact"*. Gating on either restores the exact fail-open
`needs.release.result` was written to close. This is a **tested** invariant now
rather than a structural one — under `needs`, `release.result` was syntactically
unavoidable — so `workflow-run-deploy-invariants.test.sh` carries a mutation row
for the substitution. That row is the only thing preventing its return.

**Identity comes from the trusted event, never the artifact** (the discipline
`fix-constraints-stage-b.yml` already states). `head_sha`, `run_id` and `schema`
are all asserted before any value is consumed.

**The job name is pinned to the literal `release / release`.** `release` is a
reusable-workflow call, so a lookup on the bare name matches **zero** rows — the
empty-haystack class, which fails open. The selection asserts exactly one match.

### 3. Five states, and two of them must stay green

`workflow_run` inherits **neither** path gate — not this file's `on.push.paths`
denylist, nor `reusable-release.yml`'s independent `check_changed` pathspec — so
it fires on every `main` CI completion, including docs-only pushes.

| observed | meaning | action |
|---|---|---|
| no push-arm run for this SHA | `on.push.paths` declined | **clean skip, green** |
| run exists, published nothing | `check_changed` declined | **clean skip, green** |
| run exists, still running | the measured lead did not hold | bounded liveness poll |
| run exists, `release` failed | a real failure | **fail closed, loud** |
| run exists, published | the normal path | deploy |

Collapsing the clean skips into the fail-closed arm reddens routine commits until
the signal stops carrying information. Collapsing them the other way swallows a
genuinely failed release. Both are defects and both are mutation rows.

**A sixth state, and it is not a clean skip.** The trigger is `completed`, not
`success`, so the deploy arm also fires when CI **failed** on `main`. The deploy
correctly does not happen (`skip_reason=ci_not_green`) and the run stays green —
but *a release was due and did not deliver*: main advanced, production did not.
Review found `ci_not_green` sitting in `release-outcome`'s not-paging arm
alongside `no_release_run`, which disarmed the email channel — the one built as
the non-delivery guarantee — for precisely the state it exists to report. Slack
still fired, so the fast channel was fine and the guarantee channel was silent,
which is the harder failure to notice. It is now classified as a real
non-delivery, with the cause named as upstream of this pipeline rather than as a
deploy-chain job (AP-021 — name only what was measured).

**The liveness poll needs no ceiling** — for two reasons, and the second is the
operative one this decision originally omitted. (a) It is a blocklist bounded by
the upstream run's own `timeout-minutes`, enforced by GitHub. (b) **Both arms
share a concurrency group.** The workflow keys on `web-platform-release-<sha>`
with `cancel-in-progress: false`, and both arms resolve it to the same SHA, so
the `workflow_run`-arm run *queues behind* the push-arm run that contains
`release` and cannot start until it finishes. By the time `resolve-target` runs,
the release run is already `completed` and the loop exits on its first iteration.

The loop is therefore dead code on both paths today, and is kept deliberately:
(b) is a property of the **concurrency key**, not of this job, so an edit that
stops the arms sharing a group — one made to parallelise them, say — makes the
loop live again with no other warning. There is deliberately **no**
`RELEASE_WAIT_S` constant: a derived constant is one more thing that can drift.

### 4. The creep detector is relocated, not deleted

`await-ci`'s `::warning::` at `0.7 × CEILING_S` was the only creep detection on
this pipeline (ADR-212 Decision 4), and deleting the job deletes `CEILING_S`.
Declaring a fresh `CI_BUDGET_S` was rejected — an unowned number is what ADR-212
Decision 3 rejected arithmetic for.

The reference derives from a constant that is **already owned and already
CI-asserted**: `DRIFT_SUSTAINED_THRESHOLD_MIN`, which check B9 asserts stays ≥
the declared critical path. CI's allowed share is that budget minus the declared
ceilings downstream of it.

**Two quantities, previously conflated, now pinned to separate subjects:**

- `CI_BUDGET_MIN = 207 − (30 + 15 + 90) = 72` — what the budget *allows* CI. The
  soft ceiling derives from this.

- `CI_DECLARED_PATH` — what CI *declares* for itself. **Corrected at review; the
  first version of this decision got it wrong and the error is instructive.**

> **Correction (2026-09-10).** This decision originally read
> `CI_DECLARED_PATH = 60 + 10 = 70` (`test-scripts` + `test`) and called
> `70 ≤ 72` "the headroom statement that makes the budget hold". Both the
> workflow and check B9 shipped that arithmetic and were green on it.
>
> It is the wrong quantity. `await-ci` polled for the **`test` check**, so
> to-`test` was correct for *that* mechanism and was carried across the rewrite
> unchanged. `workflow_run: types: [completed]` fires when the **whole `ci.yml`
> run** concludes. Measured on this tree: to-`test` is 70m, the whole-run
> declared path is **720m** — 19 of 25 jobs declare no `timeout-minutes`, so
> GitHub's 360m default applies to each. B9 was green at `205 ≤ 207`, a
> two-minute margin on a phantom.
>
> **The design consequence, which this ADR previously did not state.**
> `await-ci` also *capped* the wait at its own ceiling however long CI took.
> #5806 removes that cap deliberately — it is the issue's own item (a), "no
> fixed ceiling". So nothing in this pipeline bounds the wait any more; the
> bound is entirely `ci.yml`'s, and `ci.yml` mostly does not declare one. The
> declared merge-to-deploy distance is ~855m against a 207m drift alert.
>
> The headroom statement therefore **cannot be asserted** while any job is
> unbounded, and a green derived from 19 invented 360s would be worse than no
> green. So: the invariant is computed **only** when every job declares a
> ceiling; while any does not, the step emits a `::warning::` naming them. B9
> asserts over the arm this pipeline *controls* (downstream of the event,
> 195 ≤ 207) and says at the site why the CI term is absent. B9b ratchets the
> count of unbounded jobs so it can only fall, and B9c stops B9b going vacuous —
> verified by probe: blinding the extractor makes B9b report `0 ≤ 19` and pass
> forever. Ceiling gap filed as **#8020**.

Every input is read from the tree, so the numbers move when a ceiling moves.

### 5. Ordering: a monotonic-version precondition, not a git-ancestry guard

Decision 1 **removes the property Decision 2 depended on**, and neither issue
anticipates it. What orders deploys today is `ci.yml`'s single `main` group:
runs are serial, so their completions are FIFO. Per-SHA groups delete exactly
that. `workflow_run` guarantees **correct-SHA**, not **latest-SHA**.

The guard is a monotonic-version precondition on `deploy` — refuse the swap when
the resolved version is `<=` the version live on prod, a value `deploy` already
fetches over the webhook. This is emphatically **not** the Phase C guard ADR-072
rejected: no `origin/main`, no git ancestry, no `actions/checkout`, no
step-level `exit 0`. ADR-072's prohibition is scoped to the **git-ancestry**
form.

## Consequences

1. **The prod deploy gains a hard dependency on the GitHub artifacts service.**
   It had none. An artifacts-API degradation now stops deploys. The direction is
   right (closed, not open), but this is a genuinely new coupling.

2. **A shared workflow is edited for one consumer's benefit.**
   `reusable-release.yml`'s blast radius includes the plugin release pipeline.
   The step is additive, unconditional and terminal, and the `plugin` caller
   needs no edit — but it is no longer true that its path is untouched.

3. **The mirror-gate fail-open is now closed by a tested rule rather than by
   structure.** Weaker in kind, equal in current strength. The mutation row is
   the compensating control.

4. **`resolve-target` is a state machine, not a lookup** — five states, nine
   `skip_reason` strings, and its own trust ladder. More surface than a poll, and
   the guard's matrix has to grow with it or it passes vacuously over new arms.

5. **Both clean-skip states depend on `if: always()` on the artifact upload.**
   Removing it as "dead code" converts the `check_changed` no-op from a green
   skip into a loud fail-closed on every docs-adjacent push.

6. **`release-outcome` had to move.** Its non-delivery guarantee was built on all
   nine jobs living in one run; left on the push arm it would see only
   `release: success` and report that the release reached production — an
   observability regression on the one surface that exists to say otherwise.

7. **Two runs per merge.** Every consumer selecting "the latest
   `web-platform-release` run" must disambiguate the arms or it reads the wrong
   half roughly half the time. This is a silent mis-selection in the repo's own
   verification tooling, and it fails by finding an empty log rather than by
   erroring. Guard 8 discovers those call sites by extraction.

8. **#7931 part 3 (matrix-leg balance) is deferred**, and not for the reason the
   issue expected. LPT does not deliver the property it was chosen for: it is a
   greedy **global** assignment, so adding one slow suite or refreshing one
   duration can move arbitrarily many other labels between legs — the re-roll it
   was meant to stop. And `_shard_selects` cannot compute it: it is called once
   per streaming registration and cannot see the live registration set. What
   ships is the `TEST_TIMING_LOG` binding, so the next attempt has CI-measured
   data instead of a simulation. The cheaper alternative it must weigh first is a
   one-line K change (`ci.yml` records K=3 → 20.73 min against K=5 → 10.77 min).

9. **#5806 item 4** (gating the "v0.X.Y released!" announcement on deploy
   success) is deferred on **mechanism** but filed at **P2 with a dated trigger**,
   not P3. After this change the announcement and the deploy live in different
   runs with *no edge at all* — strictly less coupled than the unwired `needs:`
   gap #5806 flagged — so the misleading-announcement scenario becomes *easier*
   to hit silently, with only the 207-minute drift check behind it.

## Alternatives Considered

**Read the GitHub Release object for the SHA instead of the job conclusion.**
Rejected. A Release object's existence is a *proxy* for a verdict; `conclusion`
**is** the verdict and is one API field away. Worse, it is weaker in the specific
direction that kills: the mirror gate fails the release job while a draft or
published Release can still exist for that SHA, so this would deploy an
unmirrored image.

**Fully serialise the workflow behind CI (keep everything in one run).**
Attractive because it needs zero cross-run reconstruction. Rejected on
measurement: `release` beat `await-ci` in 14/14 runs, so it buys nothing, adds
`release`'s median 7.11 min to every deploy, and pushes the declared critical
path from 207 to ~265 min, breaking B9. It also introduces a worse fail-open:
under `workflow_run`, `actions/checkout` defaults to the default-branch head, so
a release job on that arm would build a SHA newer than the one CI validated.

**Honour the stop condition and re-file #5806.** The plan declared: *"If any
predicate cannot be reconstructed at equal strength, #5806 does not ship in this
shape."* The antecedent is **false** — the load-bearing predicate
(`release.result`) is fully obtainable, and the fields that are not obtainable
(`docker_pushed`, `mirror_verified`) are documented as non-gating and were never
the gate. Invoking a stop condition whose trigger has not occurred is not
caution; it preserves a 72-minute polling job to avoid a pattern the repo already
runs in production one workflow file over.

**Superseded-SHA guard ("Phase C").** Already designed and rejected in ADR-072
review: it false-skips nearly every deploy because `origin/main` advances on
every merge, `deploy` has no `actions/checkout`, and a step-level `exit 0`
reddens the run. Not re-introduced. Decision 5's monotonic-version check shares
none of those three defects.

## References

- #5806, #7931, #7902, #5795, #2769
- ADR-072 (`## Alternatives Considered` option 3 — adopted here)
- ADR-212 (`Named residual` corrected; Decision 4 relocated)
- `.github/workflows/ci.yml` — the concurrency block and the dispatch note
- `.github/workflows/web-platform-release.yml` — `resolve-target`
- `plugins/soleur/test/workflow-run-deploy-invariants.test.sh` — Guards 3/4/5/7/8
- `plugins/soleur/test/ci-concurrency-key.test.sh` — Guard 1
- `plugins/soleur/test/ci-test-aggregator-diagnosis.test.sh` — Guard 6
