---
date: 2026-07-27
type: perf
issue: 6665
branch: feat-one-shot-6665-ci-deploy-mock-sleep
lane: cross-domain
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
revision: v2 (post 5-agent plan-review + scoped strong-model consult)
---

# perf(infra): make the no-op `sleep` mock the DEFAULT in `ci-deploy.test.sh`

> Spec lacks a valid `lane:` — defaulted to `cross-domain` (TR2 fail-closed). No
> `spec.md` exists for this branch; this plan is its first artifact.

## Enhancement Summary

**Deepened on:** 2026-07-27
**Passes:** 5-agent plan-review (DHH, Kieran, code-simplicity,
architecture-strategist, CTO) + scoped strong-model consult + deepen-plan gates
4.5 / 4.6 / 4.7 / 4.8 (4.9, 4.10, 4.55 skipped — no UI surface, no store, no
serving-surface downtime) + deepen-plan Phase 4.45's verify-the-negative and
post-edit self-audit passes.

### Key improvements over the first draft

1. **The premise stopped being a projection.** Forcing the existing gate on for
   the whole suite — zero code changes — was run at plan time: **538 s → 264 s,
   184/184, with an empty PASS-name-set diff.** The plan is now built on a
   measurement, and AC2's non-vacuity gate has already passed once.
2. **The 120 s target was tested against arithmetic and found to be at the
   floor.** Counterfactual `user + sys` ≈ 117 s of process-spawn cost that no
   sleep mock removes. AC1 is floor-relative and requires an *evidenced* miss
   rather than a silent one; DC-4 surfaces the target itself to the operator.
3. **A wrong rationale was caught and corrected.** The draft claimed the
   recording rider prevented T-6525-8 going vacuous. T-6525-8 already runs with
   the mock and already pays 0 s — the schedule-value hole is **pre-existing**,
   so the rider is net-new coverage. Stated honestly rather than defended.
4. **The tier argument was rebuilt.** "Two independent defects" does not survive
   P(later regression) ≈ 1 — the suite exists *because* deploy regressions
   recur. The honest ground for `aggregate pattern` is that the check is
   **advisory**, with #6480 named as the dependency that would expire it.
5. **A failure mode nobody else named was added.** A real `sleep` can be an
   undeclared **synchronization barrier**; under a no-op it becomes a race that
   is green locally and intermittent on a loaded runner — structurally invisible
   to a single-run name-set diff. AC2b (5 identical name-sets, ≥1 under load) is
   the detector, and the speedup is what makes it affordable.
6. **The hot-spin guard was generalised from instance to class.** A per-call-site
   countdown cap became an invocation cap **inside the mock** (~500 → loud
   abort) — one guard covering every time-gated loop, present and future.
7. **Two false-green ACs were killed.** `grep '~12s of slack'` can never match
   (the phrase is split across `:607`/`:608`), and `git grep -c` cannot express
   "returns 0" (it prints nothing and exits 1). Both verified at the keyboard.
8. **~60 % of the draft was cut.** Both simplification reviewers fired on the
   same scope, so the response was delete, not patch: the attribution histogram,
   the ~60-row delta table, the separate mutation battery, two of three
   structural guards, and four ACs are gone.

### New considerations discovered

- An in-repo precedent already anticipated this issue by name:
  `apps/web-platform/infra/workspaces-luks-harness.sh:301-315` (#6807) uses a
  **recording** no-op sleep, states the exact safety rule this plan derived
  independently (*"safe ONLY because the retry loops are bounded by ATTEMPTS,
  never by wall clock"*), and says that if #6665 broadens the gate, "the thing to
  share is the opt-in convention". Its prose is falsified by this PR and is now
  in `## Files to Edit`.
- Real `sleep` was an **undeclared second brake** on the canary `seq 1 10` loop.
  Removing it makes `create_mock_seq` the sole brake — a defense relaxation that
  must name its replacement ceiling, which the invocation cap now does.
- `TEST_PATH_BASE` is a `readonly` **absolute** PATH, so `$MOCK_DIR` is the only
  lever. Discovered empirically: a PATH-prepended shim caught only the 3 sleeps
  *outside* the runner subshells.
- **ADR-139** (earned-green for reachable-surface content gates) governs the
  shape of the residual: the Phase 2.2 comment is written as its tripwire.
  (`tasks.md` mirrors this numbering exactly, lettering finer actions as `2.2a`,
  `2.2b`, … so a plan citation always resolves to the matching `tasks.md` step.)

## Overview

`apps/web-platform/infra/ci-deploy.test.sh` (4983 lines, 184 assertions) spends
most of its wall clock doing nothing. The suite runs the real `ci-deploy.sh`
under a PATH-shadowing mock directory; `sleep` is the one binary the harness
deliberately does **not** shadow, so every retry/backoff/poll site in the
production script pays real seconds against the CI budget.

The fix is one line of intent: **`create_base_mocks` should install the no-op
`sleep` by default, not on opt-in.** Today it installs one only when
`MOCK_SLEEP_NOOP=1` (`ci-deploy.test.sh:699`), and exactly one test in the file
sets it (T-6525-8, `:3951`).

**This was measured at plan time, not projected.** Forcing the existing gate on
for the whole suite (`MOCK_SLEEP_NOOP=1 bash …`, zero code changes) yields:

| Run | Wall | user | sys | Result | PASS-name-set diff vs baseline |
| --- | --- | --- | --- | --- | --- |
| Baseline | **8m58.232s** | 0m41.805s | 1m32.496s | 184/184 | — |
| Gate forced on | **4m23.728s** | 0m36.572s | 1m20.362s | 184/184 | **empty** |

Two things follow, and they set the shape of the whole plan:

1. **The approach works and is behaviour-preserving.** 538 s → 264 s with an
   empty PASS-name-set diff — and that is a *partial* application, because
   T-6525-8's `unset` at `:3966` switches the gate back off for the last ~1000
   lines. The full inversion saves more.
2. **The issue's 120 s target sits at or below the local CPU floor.** The
   counterfactual's `user + sys` is ~117 s of pure process-spawn cost
   (thousands of subshells and mock binaries) that no sleep mock removes. §R2
   and AC1 are written around that measured fact rather than around the issue's
   round number.

Inverting the default — rather than adding `MOCK_SLEEP_NOOP=1` to N individual
tests, as the issue's literal wording suggests — is what makes this a
*root-cause* fix. Opt-in means **every future test silently re-pays the wall
clock**, and the `timeout-minutes` bump loop (#6649 → #6650 → #6665) runs again.

Two riders, both load-bearing, both scoped small:

1. **An invocation cap inside the mock.** The inversion creates a new latent
   **class**: any loop whose exit is *time-gated* rather than *data-gated* hot-spins
   under a no-op `sleep`. It also removes a **second brake** that nobody
   declared — real `sleep` was an independent bound on `ci-deploy.sh:2452`'s
   `for i in $(seq 1 10)` canary loop (five `sleep 3` sites), leaving
   `create_mock_seq` as the *sole* brake and changing runaway from
   slow-and-visible to hot spin. Per the defense-relaxation discipline, the
   removed ceiling must be replaced by a named one: the mock counts its own
   invocations and **aborts loudly past ~500** (real code never sleeps that many
   times; a hot loop reaches it in milliseconds). One guard, whole class,
   present and future — strictly better than hard-capping the one call site
   whose symptom we happen to know about.
2. **A recording mock** (append `$1` to `$MOCK_SLEEP_LOG` when set). Stated
   honestly, because the first draft of this plan got the rationale wrong: this
   is **net-new coverage for a pre-existing gap, not regression protection.**
   T-6525-8 already runs with the no-op mock and already pays 0 s, so the
   inversion removes no coverage — but the production default backoff schedule
   `"2 4"` (`ci-deploy.sh:1437`) can be mutated to `"9 9"` and the suite stays
   green today, because the only assertion is a pull *count*. Recording the
   argument closes that hole for ~6 lines. It is also the **established house
   pattern**, not an invention: `apps/web-platform/infra/workspaces-luks-harness.sh:301-315`
   (#6807, modelled on `nic-wait-gate.test.sh`) already uses a RECORDING no-op
   sleep for exactly this reason, with `rec()` at `:163`.

The budget change (`timeout-minutes: 12 → 8`) is sequenced **last and against
real CI numbers** — see §Sequencing.

## Premise Validation

| Cited artifact | Check run | Result |
| --- | --- | --- |
| Issue #6665 | `gh issue view 6665 --json state,closedByPullRequestsReferences` | `OPEN`, no closing PR. Premise holds. |
| `MOCK_SLEEP_NOOP=1` / `create_mock_sleep` gate "around the mock-sleep helper block" | Read `ci-deploy.test.sh:673-700` | Holds: helper body `:676-682`, gate `:699`. |
| "`timeout-minutes` returned from 12 to 8" | Read `.github/workflows/infra-validation.yml:307` | Holds: `timeout-minutes: 12`, #6649 rationale at `:296-306`. |
| "~407 s on the CI runner" | Not re-measured at plan time | Carried as a **claim**, not a fact. Phase 3 re-derives the CI number from this PR's own run. |
| Proposed mechanism vs. ADR corpus | Grepped `knowledge-base/engineering/architecture/decisions/` | No ADR governs test-harness mock defaults — not an explicitly-rejected alternative. **ADR-139** (`earned-green-required-for-reachable-surface-content-gates`, accepted 2026-07-23, #6882) *is* relevant: it is the repo's decision on when a green assertion may be non-earned, and requires the residual be paired with a **tripwire comment** naming the condition under which it goes live. Phase 2.2's comment is written in that shape. |

## Hypotheses

The **plan-skill** Phase 1.4 network-outage gate fired on the literal token
**`timeout`** (its deepen-plan enforcement counterpart is Phase 4.5, below);
telemetry emitted (`hr-ssh-diagnosis-verify-firewall`, `applied`). The L3→L7
checklist does not apply: the subject is `actions/runner` cancelling a job that
exceeded `timeout-minutes` — a scheduler decision made on the runner with no
host, no egress IP, no firewall, and no sshd in the causal chain.

| # | Hypothesis | Status | Discriminator |
| --- | --- | --- | --- |
| H1 | The dominant cost is real `sleep` inside `ci-deploy.sh`, reached through the harness's mock PATH | **CONFIRMED by measurement** | The Overview table: forcing the existing gate on cuts 538 s → 264 s with an identical PASS name-set. Not reasoned — run. |

### Network-Outage Deep-Dive (deepen-plan Phase 4.5)

The gate fired and is answered per layer rather than waved off, because "obvious"
is not a verification. The finding is that **every layer is structurally
inapplicable — not merely unverified** — and each row says why:

| Layer | Status | Reason |
| --- | --- | --- |
| **L3 — firewall allow-list** | **N/A, structurally** | There is no affected host. The failing actor is a GitHub-hosted `ubuntu-24.04` runner cancelling its own job; no `hcloud firewall describe` target exists and no operator egress IP participates. |
| **L3 — DNS / routing** | **N/A, structurally** | The suite resolves nothing over the network: `create_base_mocks` PATH-shadows `docker`, `curl`, `doppler`, `systemctl`, `flock`, `df`, and `logger`. No name resolution occurs on the measured path. |
| **L7 — TLS / proxy** | **N/A, structurally** | No HTTPS is transacted. The `curl` mock (`ci-deploy.test.sh:532`) answers from local files. |
| **L7 — application** | **VERIFIED — and it is the cause** | The measurement in the Overview is the artifact: `user + sys` is ~117 s against a 538 s wall clock, i.e. ~78 % of the run is a process voluntarily sleeping. Forcing the sleep mock on removes 274 s with an identical PASS name-set. The cost is in-process `sleep(2)` calls, not I/O wait on a socket. |

The positive evidence that this is budget exhaustion rather than a hung network
call: the cancelled runs cited in #6665 advanced *through several steps* before
being cancelled at ~8:02. A hung network call stalls on one step; a wall-clock
ceiling cuts wherever the job happens to be.

## Research Reconciliation — Spec vs. Codebase

Every row verified by reading the file. Line cites were re-verified by an
independent review pass and corrected where they had drifted.

| Claim | Reality | Plan response |
| --- | --- | --- |
| Issue + the `:675` comment: "lease/lock/drain timing" tests keep the real `sleep` | The four drain tests **already** set `CRON_DRAIN_POLL=0` (`:3307`, `:3326`, `:3351`, `:3371`); `run_quiesce_pessimism` already sets `QUIESCE_PROBE_INTERVAL=0` (`:2756`). They pay no meaningful sleep today. | The `:673-675` comment is **stale**; rewritten in Phase 2.2. "Drain timing" is not an exclusion — it is already opted out via a different seam. |
| spec-flow advisory: "CRITICAL — harness self-shadowing: the harness's own pacing sleeps resolve to the mock" | **REFUTED by direct reading, twice.** All `export PATH="$MOCK_DIR:$TEST_PATH_BASE"` occurrences (10, plus `$effective_path` at `:1361` = 11 total) sit inside `( … )` runner subshells. `TEST_PATH_BASE` (`:17`) is a `readonly` absolute constant — so `$MOCK_DIR` is the **only** lever, confirmed empirically when a PATH-prepended shim caught only the 3 sleeps *outside* the runners. `assert_trap_writes_timeout_state_in_isolation` (`:2466-2567`, own `mktemp -d` at `:2472`) calls **no** `create_base_mocks` and exports **no** `PATH`. | No exclusion needed for the trap test — out of reach by construction. |
| Implied: the exclusion list will be long ("check each candidate individually") | **Empty.** The only runtime duration assertion is T3's `T3_WAIT -le 2` (`:3335`) — an *upper* bound on a path (`while cron_in_flight`, no cron in flight) that never enters the loop body, reading 0 s before and after. Confirmed empirically: the counterfactual's PASS-name-set diff is **empty**. | No `MOCK_SLEEP_REAL=1` exclusions at merge. |
| Assumed: `deploy-script-tests` is merge-blocking | **Advisory** — absent from `infra-validate-required`'s `needs: [detect-changes, validate]` (`:273-292`) and from all 20 `required_check` contexts in `infra/github/ruleset-ci-required.tf`. | This is the **tier rationale** (§User-Brand Impact) and the rollback story (§R3). #6480 (cited at `infra-validation.yml:368-374`) would make it required — when that lands, the rationale changes. |
| Draft v1: "without the recording rider T-6525-8 degrades to a vacuous timing test" | **Wrong, and corrected.** T-6525-8 already sets `MOCK_SLEEP_NOOP=1` (`:3951`) and already pays 0 s; the inversion removes no coverage. The schedule-value hole is **pre-existing**. | Rider re-labelled as net-new coverage (Overview rider 2). Recorded as DC-3. |
| `create_mock_seq` (`:91`) prints only `"1"` | Confirmed; all four `seq` uses are `for i in $(seq …)`. | Residual cost is one sleep per loop plus the straight-line `sleep 5` at `ci-deploy.sh:2678`. **And**: real `sleep` was a second, undeclared brake on those loops — see Overview rider 1. |
| Draft v1 cited `attempt < max` at `ci-deploy.sh:1439` | `:1439` is `while :; do`; the guard is at **`:1470`**. | Corrected. |
| Draft v1 cited workflow paths at `:12-56` | `:13-53` (`:12` is `pull_request:`). | Corrected. |
| Draft v1 AC7 grepped `'~12s of slack'` | **False-green.** That string is line-split across `:607`/`:608`; the only single-line match is at `:303`, inside the block Phase 3.3 replaces anyway. The AC would pass with the stale note untouched. | Pattern changed to `'of slack under timeout-minutes'` (spans no line break). |
| Draft v1 used `git grep -c … returns 0` | `git grep -c` prints **nothing** and exits 1 on zero matches; only `grep -c` prints `0`. | All absence-ACs use `grep -c`. |
| Draft v1 Phase 0.1 re-verified the ruleset via `apps/web-platform/infra/*.tf` | Structurally incapable of falsifying the claim — the ruleset is at `infra/github/ruleset-ci-required.tf`. | Corrected. |
| Not previously noticed | `apps/web-platform/infra/workspaces-luks-harness.sh:308-314` names the `MOCK_SLEEP_NOOP` idiom and calls it "an opt-in gate" — prose this PR falsifies. | Added to `## Files to Edit`; the absence-grep is repo-wide, not scoped to one file. |

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly — no production
code path changes. The indirect artifact is a `ci-deploy.test.sh` that runs fast
and green while no longer guarding `ci-deploy.sh`, the deploy script for
soleur.ai. A later deploy-script regression then ships, and the user sees a
failed or partial deploy of their own platform.

**If this leaks, the user's data / workflow / money is exposed via:** no new
exposure vector. No data flow, no logging of user content, no network call.
`$MOCK_SLEEP_LOG` records only sleep durations emitted by `ci-deploy.sh`, into a
per-test `mktemp -d`.

**Brand-survival threshold:** `aggregate pattern`.

**Rationale — and the argument v1 got wrong.** The first draft justified the tier
by claiming an incident needs *two independent* defects (vacuity here, plus a
later deploy regression). That reasoning does not survive review: this suite has
184 assertions precisely *because* deploy-script regressions recur (#3007,
#3033, #5875, #6454), so P(later regression) ≈ 1 and P(incident) ≈ P(vacuity) —
not a product.

The tier still holds, on a property this plan verified rather than assumed:
**`deploy-script-tests` is advisory.** A *working* guard does not block the
regression either — it reds a log that merge does not gate on. The marginal loss
from vacuity is therefore the loss of a *signal*, not of a *gate*. **This
rationale expires when #6480 lands** and makes the check required; that
dependency is named here so the next reader can re-derive the tier instead of
inheriting it.

## Architecture Decision (ADR/C4)

**No new ADR.** The change alters the default of a test-harness mock factory. No
ownership/tenancy boundary moves, no substrate or integration pattern is
introduced, no resolver/dispatch/trust boundary changes.

**ADR-139 applies and is cited, not extended.** It is the repo's accepted
decision on when a green assertion may be non-earned, requiring the residual be
paired with a **tripwire comment** naming the condition under which it goes live.
Phase 2.2's rewritten comment and Phase 1.1's invocation cap are written in that shape:
each states the property it depends on (`create_mock_seq` is now the sole loop
brake; the mock shadows only a *bare* `sleep`) and what would make the residual
live.

### C4 views — no impact, with the enumeration cited

All three model files read in full, not grepped for the feature's own noun:
`model.c4` (558 lines), `views.c4` (62 lines; views `context`,
`containers of platform`, `components of platform.plugin`), `spec.c4` (54 lines).

| Dimension | This change introduces | Already modeled? |
| --- | --- | --- |
| External human actor | none | existing `founder`, `emailSender`, `betaContact`, `contributor` untouched |
| External system / vendor | none | `anthropic`, `github` untouched; the change runs *inside* the existing GitHub Actions surface without altering the relationship |
| Container / data store | none (a bash test file and a workflow scalar) | `infra` system's containers/databases untouched |
| Actor↔surface access relationship | none | — |

No `.c4` edit and no `view … include` line is in scope.

## Observability

```yaml
liveness_signal:
  what: the `deploy-script-tests` job's `Run ci-deploy.sh tests` step duration
        and conclusion on every PR touching `apps/*/infra/**`
  cadence: per pull_request event on the paths at infra-validation.yml:13-53
  alert_target: GitHub Actions check status on the PR (advisory, not required);
                a regression appears as a red or cancelled `deploy-script-tests`
  configured_in: .github/workflows/infra-validation.yml (job `deploy-script-tests`)

error_reporting:
  destination: GitHub Actions job log + check conclusion. The suite prints
               `=== Results: N/M passed, F failed ===` and exits non-zero on any
               FAIL, so a broken assertion is a job-level red, never a warning.
  fail_loud: true — runs under `set -euo pipefail`; the final gate exits non-zero.

failure_modes:
  - mode: a previously-passing assertion silently stops passing
    detection: PASS **name-set diff** (sorted PASS line texts, before vs after)
               must be empty. Deterministic; a count match is not sufficient.
               Already run at plan time on the counterfactual — empty.
    alert_route: /work Phase 2 gate — a non-empty diff blocks the phase.
  - mode: a real `sleep` was acting as an undeclared SYNCHRONIZATION BARRIER —
          letting a background write land before a later read. Under a no-op it
          becomes a race that passes locally and fails on a loaded runner.
          INTERMITTENT, so a single-run name-set diff cannot see it.
    detection: 5 consecutive runs must produce identical PASS name-sets, at
               least one under artificial CPU load. The speedup is what makes
               this affordable (5 x ~3 min, not 5 x ~9 min).
    alert_route: /work Phase 2 gate (AC2b).
  - mode: a test becomes VACUOUS — green, but no longer able to fail
    detection: the schedule mutation in Phase 1.3 (`"2 4"` -> `"9 9"` must RED),
               plus a grep confirming the runtime-duration-assertion set is
               still exactly {T3}.
    alert_route: /work Phase 1 gate.
  - mode: the no-op sleep turns a time-gated loop into a hot spin
    detection: the mock's own invocation cap (~500) aborts loudly with a named
               cause, converting a would-be 1-hour CI hang into a fast, countable
               failure. Backed by the Phase 0.3 loop-exit classification.
    alert_route: /work Phase 0 gate + the cap itself at runtime.
  - mode: `timeout-minutes` proves too tight on a slow runner
    detection: `deploy-script-tests` cancels; visible red on the PR check.
    alert_route: advisory check — recovery is a one-line bump. Phase 3.3 sets the
                 ceiling at ~2x observed max and requires a GREEN run at the new
                 ceiling before ship.

logs:
  where: GitHub Actions job logs for `infra-validation.yml / deploy-script-tests`
  retention: GitHub default workflow-log retention (90 days)

discoverability_test:
  command: |
    gh run list --workflow=infra-validation.yml \
      --branch=feat-one-shot-6665-ci-deploy-mock-sleep \
      --json databaseId,conclusion --limit 5
    gh api repos/jikig-ai/soleur/actions/runs/<id>/jobs \
      --jq '.jobs[] | select(.name=="deploy-script-tests")
            | {conclusion,
               job_secs: ((.completed_at|fromdate) - (.started_at|fromdate)),
               steps: [.steps[] | {name, secs: ((.completed_at|fromdate) - (.started_at|fromdate))}]
                      | sort_by(-.secs) | .[0:5]}'
  expected_output: |
    a JSON object naming conclusion, job_secs, and the five slowest steps, with
    `Run ci-deploy.sh tests` no longer at the top. NO `ssh` in the path — the
    numbers come from the GitHub API.
```

No soak-gated close criterion is declared (**plan-skill** Phase 2.9.1 — N/A). No
blind execution surface is touched (**plan-skill** Phase 2.9.2 — N/A). Both refer
to the plan skill's own gate numbering, not to this document's Phase 2.

## Open Code-Review Overlap

**None.** `gh issue list --label code-review --state open --json number,title,body --limit 200`
piped through a standalone `jq --arg path` for `ci-deploy.test.sh`,
`ci-deploy.sh`, and `infra-validation.yml`. Zero matches on all three.

## Files to Edit

| File | Change |
| --- | --- |
| `apps/web-platform/infra/ci-deploy.test.sh` | `create_mock_sleep` (`:676-682`) records `$1` to `$MOCK_SLEEP_LOG` when set, and enforces an ~500-invocation cap; `create_base_mocks` (`:699`) installs it **unless** `MOCK_SLEEP_REAL=1`; comment `:673-675` rewritten as an ADR-139-shaped tripwire; T-6525-8 (`:3943-3969`) drops `export MOCK_SLEEP_NOOP=1`, gains a schedule assertion, truncates `$MOCK_SLEEP_LOG` per arm, and adds it to the `unset` at `:3966`. |
| `apps/web-platform/infra/workspaces-luks-harness.sh` | `:308-314` describes the `MOCK_SLEEP_NOOP` idiom as "an opt-in gate" — prose this PR falsifies. Update the cross-reference (do **not** unify the mechanisms; that comment is right that they are different). |
| `.github/workflows/infra-validation.yml` | `timeout-minutes: 12 → 8` (`:307`); the #6649 rationale (`:296-306`) replaced by a measured-slack comment naming run IDs; the stale line-split "…`~12s` / `of slack under timeout-minutes: 8`" note (`:604-608`) **deleted**, not restored. |

## Files to Create

None.

## Sequencing (load-bearing)

The issue's AC1 measures **one step** locally. `timeout-minutes` budgets the
**whole job** — which also runs `fetch-depth: 0` checkout, `setup-terraform`,
`apt-get install cloud-init`, an alpine+bubblewrap docker build, a real
losetup/LUKS loopback suite, and ~55 further suites. **A local step measurement
cannot justify a job ceiling.**

Resolvable without splitting the PR: `infra-validation.yml`'s
`on.pull_request.paths` includes `apps/*/infra/**` (`:14`) **and**
`.github/workflows/infra-validation.yml` (`:16`) — verified — so **this PR's own
CI runs `deploy-script-tests`**. Therefore: land Phases 0-2 with
`timeout-minutes` unchanged at 12 and push; read real job/step seconds off this
PR's runs via `gh api`; then commit the ceiling to the **same** PR.

A dissent is on file (DC-1, `decision-challenges.md`): the strong-model consult
argued for cutting the ceiling change from this PR entirely, on the grounds that
`n=1` is not a ceiling policy and that lowering a ceiling saves nothing. The
plan keeps the operator's stated scope and raises the evidence bar instead
(≥2 runs, mandatory `gh run rerun`, fallback to `10`).

## Implementation Phases

### Phase 0 — Preconditions (no edits)

- **0.1** Re-confirm `deploy-script-tests` is advisory — against the **right**
  file: `grep -n 'deploy-script-tests' infra/github/ruleset-ci-required.tf` and
  the `infra-validate-required` `needs:` list. (Plan-time result: absent from
  both. Re-verify; `main` may have moved.)
- **0.2** Repo-wide absence sweep for the seam being renamed — a comment is not
  inert, grep-based guards read comments:
  `grep -rn 'MOCK_SLEEP_NOOP' . --exclude-dir=.git`. Plan-time result: 6 hits in
  `ci-deploy.test.sh`, 1 in `infra-validation.yml:305` (inside the block being
  replaced), 2 in `workspaces-luks-harness.sh:308,314`, plus learnings/plans
  (historical record — do not rewrite).
- **0.3** **Loop-exit classification** — the documented precondition for this
  technique in this codebase (`workspaces-luks-harness.sh:305-306`: *"a no-op is
  safe ONLY because the retry loops are bounded by ATTEMPTS, never by wall
  clock"*). For every `sleep` site in `ci-deploy.sh`, classify the enclosing
  loop. Enumerate **all 15** invocation sites, including the five `sleep 3`
  canary sites. (15, not 17: `ci-deploy.sh:1430` is a comment and `:1437` is the
  `_sleeps` **array declaration** — neither is a call. A case-insensitive
  `grep -c '\bsleep\b'` counts both and reads 17; the enumeration below is the
  authority.)
  - *bounded-iteration* — `for i in $(seq 1 N)`: `:1842`, `:1907`, `:1954`, and `:2452` (which contains `sleep 3` at `:2471`, `:2477`, `:2483`, `:2491`, `:2526`). 1-shot via `create_mock_seq`.
  - *counter-bounded* — `until … [[ "$n" -ge 3 ]] && break`: `:1200`, `:1201`, `:1275`, `:1278`; and `attempt < max` at `:1470` inside `while :; do` (`:1439`), sleep at `:1472`.
  - *straight-line* — `sleep 5` at `:2678`.
  - *wall-clock exit* — `while cron_in_flight` at `:2603` (sleep `:2610`). **The only one**; data-bounded in tests by the docker-mock countdown (`ci-deploy.test.sh:213-225`, default `exit 1` = zero iterations), and the timeout test pins `CRON_DRAIN_TIMEOUT=0` (`:3351`).
  Deliverable: this table re-derived, with a zero-reachable-hot-spin conclusion.
- **0.4** Clean **solo** baseline for the record (nothing else running):
  `time bash apps/web-platform/infra/ci-deploy.test.sh`, saved — it is the
  `before` side of every name-set diff. Plan-time reading: `real 8m58.232s /
  user 0m41.805s / sys 1m32.496s`, `184/184 passed`.

### Phase 1 — RED: make the schedule assertable

- **1.1** `create_mock_sleep`: append `$1` to `$MOCK_SLEEP_LOG` when non-empty
  (mirroring `rec()` at `workspaces-luks-harness.sh:163`); add the ~500-invocation
  cap that writes a named diagnostic to stderr and `exit 1`. Still opt-in here —
  this commit changes no timing.
- **1.2** T-6525-8 (`:3943-3969`): assert the recorded schedule is exactly `2`
  then `4`, alongside the existing 3-pulls assertion. Truncate `$MOCK_SLEEP_LOG`
  before the arm and add it to the `unset` at `:3966` (append-leakage).
- **1.3** **Mutation-prove it** — this *is* the mutation battery; no separate one
  is warranted, because T-6525-8 is the only test whose semantics change. Mutate
  `ci-deploy.sh:1437` `${PULL_TRANSIENT_RETRY_SLEEPS-2 4}` → `-9 9` **in place**,
  run T-6525-8, require **FAIL**, restore from backup **in a separate Bash call**
  (a 2-file sandbox copy aborts — this file resolves siblings relative to its own
  dir).

### Phase 2 — GREEN: invert the default

- **2.1** `create_base_mocks:699` → install unless `MOCK_SLEEP_REAL=1`. Keep the
  `if [[ … ]]; then … fi` form; **never** a bare `[[ … ]] && cmd` statement
  (under `set -euo pipefail` a false condition aborts the whole suite). Confirm
  no runner subshell's `unset` list clears `MOCK_SLEEP_REAL`.
- **2.2** Rewrite `:673-675` as an **ADR-139-shaped tripwire**: state the
  inverted contract, the opt-out, and the two properties the safety now rests on
  — that `create_mock_seq` is the sole loop brake, and that the mock shadows only
  a *bare* `sleep`. Do not reproduce any sibling regex literal near a count
  guard. Drop `MOCK_SLEEP_NOOP` from `:3946`/`:3951`/`:3966`; update
  `workspaces-luks-harness.sh:308-314`.
- **2.3** **Behavioural-equivalence gate.** `diff <(grep -o 'PASS: .*' before | sort) <(grep -o 'PASS: .*' after | sort)`
  must be empty and `=== Results: ===` must read `184/184`. Then **repeat 5×**,
  at least one run under artificial CPU load, requiring all five PASS name-sets
  identical — this is the only detector for the synchronization-barrier failure
  mode, which is intermittent and invisible to a single run.

### Phase 3 — Return the budget against real CI numbers

- **3.1** Push Phases 0-2 with `timeout-minutes` still `12`. Let CI run, then
  `gh run rerun` for a **mandatory** second observation.
- **3.2** Read the truth from the API (never a dashboard): the
  `discoverability_test` command above, for ≥2 runs on this PR. Take the max.
- **3.3** Set `timeout-minutes: 8` **only if** max job seconds ≤ ~240 s (ceiling
  ≈ 2× observed). If max lands 240-360 s, set `10` and say so. Replace `:296-306`
  with a comment recording measured step seconds, measured job seconds, and the
  run IDs; **delete** the stale note at `:604-608`. Push, and require a **green
  `deploy-script-tests` run at the new ceiling** before ship — a YAML grep alone
  cannot show the ceiling holds.

### Phase 4 — Ship

`/soleur:ship`. `Closes #6665` in the body. Body carries the before/after table,
the loop-exit classification, the mutation output, and the 5-run stability
result. `decision-challenges.md` is rendered by ship Phase 6.

## Acceptance Criteria

### Pre-merge (PR)

- **AC1** The suite's wall clock is reported before and after on clean solo local
  runs (baseline measured: `8m58.232s`; gate-forced-on counterfactual:
  `4m23.728s`), together with the **measured CPU floor** (`user + sys`;
  counterfactual: ~117 s). The PR states the seconds eliminated and whether
  120 s was reached. **An evidenced miss of 120 s is acceptable; a silent one is
  not** — the floor is a property of process-spawn cost, not of sleeps (§R2).
  Additionally: no single test block exceeds 60 s.
- **AC2** `=== Results: 184/184 passed, 0 failed ===`, **and** the sorted
  PASS-name-set diff before vs after is empty. A count match alone does not
  satisfy this.
- **AC2b** Five consecutive runs produce **identical** PASS name-sets, at least
  one under artificial CPU load. (Catches the synchronization-barrier race that
  AC2 structurally cannot.)
- **AC3** T-6525-8 asserts the production default backoff **values** (`2` then
  `4`) from `$MOCK_SLEEP_LOG`; mutating `ci-deploy.sh:1437` to `9 9` turns it
  RED, with the mutation output pasted.
- **AC4** The Phase 0.3 loop-exit classification table is in the PR body,
  enumerating **all 15** `sleep` **invocation** sites
  (`ci-deploy.sh:1200 1201 1275 1278 1472 1851 1915 1961 2471 2477 2483 2491 2526 2610 2678`),
  and concludes zero reachable hot-spin loops. The mock's invocation cap is
  present. Verify the count with
  `grep -nE '\bsleep ' apps/web-platform/infra/ci-deploy.sh | grep -vE ':\s*#' | wc -l`
  → `15`; a bare `grep -c '\bsleep\b'` reads 17 because it also counts the
  `:1430` comment and the `:1437` array declaration.
- **AC5** No stale seam prose survives repo-wide:
  `grep -rc 'MOCK_SLEEP_NOOP' apps/web-platform/infra/ | grep -v ':0'` returns
  nothing (learnings and `knowledge-base/project/{plans,specs}` are historical
  record and excluded).
  Note: `grep -c`, never `git grep -c` — the latter prints nothing and exits 1 on
  zero matches, so an absence assertion built on it cannot read `0`.
- **AC6** `grep -c 'of slack under timeout-minutes' .github/workflows/infra-validation.yml`
  returns `0`. (The v1 pattern `'~12s of slack'` was a **false-green**: that
  string is split across `:607`/`:608` and can never match a line-oriented grep,
  while its only single-line occurrence sits inside the block Phase 3.3 replaces
  regardless.)
- **AC7** `timeout-minutes` for `deploy-script-tests` is the value Phase 3.3's
  rule selects, verified with
  `awk '/^  deploy-script-tests:/{f=1} f&&/timeout-minutes:/{print; exit}' .github/workflows/infra-validation.yml`;
  the adjacent comment names measured step seconds, measured job seconds, and
  ≥1 run ID (`grep -cE 'runs/[0-9]{6,}' .github/workflows/infra-validation.yml`
  ≥ 1); **and** a `deploy-script-tests` run at that ceiling has concluded
  `success` with `job_secs ≤ 0.5 × ceiling`.

### Post-merge (operator)

None. Every step is automated: the suite runs in-session, CI numbers come from
`gh api`, and `deploy-script-tests` re-runs on merge through the same path
filter. No operator action is deferred.

## Risks & Mitigations

| # | Risk | Mitigation |
| --- | --- | --- |
| **R1** | The inversion opens a hot-spin **class** (any time-gated loop) **and** removes an undeclared second brake: real `sleep` independently bounded the `seq 1 10` canary loop, leaving `create_mock_seq` sole brake — runaway changes from slow-and-visible to hot spin. | The removed ceiling is replaced by a named one: an **invocation cap inside the mock** (~500 → loud abort). Guards the class, not the instance. Phase 0.3 proves zero currently-reachable instances. |
| **R2** | **The 120 s target is at or below the local CPU floor.** Counterfactual `user + sys ≈ 117 s` of process-spawn cost that no sleep mock removes; a 2-vCPU CI runner is likely higher. | AC1 is floor-relative and requires an *evidenced* miss rather than a silent one. Going below the floor needs a different architecture (sharding, or fewer subshell/mock spawns) — out of scope. Surfaced to the operator as DC-4. |
| **R3** | A real `sleep` may have been an undeclared **synchronization barrier**; a no-op turns it into a race that is green locally and intermittent on a loaded runner — invisible to a single-run name-set diff. | AC2b: 5 consecutive identical PASS name-sets, ≥1 under load. This is the failure mode the speedup itself makes affordable to test for. |
| **R4** | `timeout-minutes` too tight on a slow runner. | Advisory check (verified) — reds a log, not a merge; recovery is a one-line bump. Because that also means a regression can go *unnoticed*, the ceiling is ≈2× observed max over ≥2 runs, and AC7 requires a green run at the new ceiling. |
| **R5** | The PATH mock shadows only a **bare** `sleep`; `/bin/sleep` or `command sleep` would slip through silently. | Named in the Phase 2.2 tripwire comment as a property the design rests on. A dedicated assertion was proposed and **cut** as a change-detector (DHH); the invocation cap plus the wall-clock ACs are the real detector. |
| **R6** | Rewriting `:673-675` could trip a grep-based SSOT/count guard elsewhere. | Phase 0.2's repo-wide sweep runs first; Phase 2.2 forbids reproducing sibling regex literals in the new prose. |

## Alternative Approaches Considered

| Approach | Why not |
| --- | --- |
| Add `export MOCK_SLEEP_NOOP=1` to N individual tests (the issue's literal wording) | Omission-by-default: every test written afterwards silently re-pays the wall clock, and the #6649→#6650→#6665 loop repeats. Also a ~60-site diff with 60 chances to miss one. |
| Delete the gate entirely (unconditional mock, no `MOCK_SLEEP_REAL`) | Genuinely simpler and the exclusion set *is* empty — but it removes Test Scenario T2, the only probe that attributes the speedup to the mock rather than to an accidental skip. Kept the opt-out; recorded the dissent as DC-2. |
| A `CI_DEPLOY_SLEEP_SCALE=0` seam in `ci-deploy.sh` | Adds a test-only seam to **production** code for a problem entirely solvable in the harness, at a wider blast radius. |
| Shard `deploy-script-tests` across a matrix | Solves the budget, not the cost; the `apt-get` + `setup-terraform` setup would be paid per shard. Disproportionate for a default flip — though it is the honest lever if the CPU floor (§R2) ever has to come down. |
| Split the ceiling change into a second PR | This PR's own paths trigger the workflow, so the post-speedup CI number is observable before merge. Recorded as DC-1. |
| Delete the slow tests | They assert real regressions (canary rollback, drain ordering, GHCR retry). Not on the table. |

## Domain Review

**Domains relevant:** Engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Approves the default inversion over per-test opt-ins, naming
*omission-by-default* as the opt-in failure mode and *silent semantic change* as
the inversion's, and prescribing the PASS-name-set diff as the deterministic
mitigation (AC2). Rules the recording rider **in scope**, capped at one log and
one assertion, explicitly not generalising call-recording to other mocks.
Independently verified that `ci-deploy.sh:2603` is the only wall-clock-exit loop
and that it is data-bounded in tests. Surfaced the countdown hot-spin (now R1,
generalised into the mock-level cap) and two further risks now carried as R5 and
Phase 2.1's `unset`-list check. Recommends `8` and not lower ("a ceiling, not a
budget"), sourced from the PR's own CI run, and deleting rather than restoring
the stale slack comment. Confirms **no ADR** for the mock flip.

### Product/UX Gate

Not applicable. The mechanical UI-surface override was run against
`## Files to Edit` / `## Files to Create`: all three paths are infra shell or
workflow YAML. No match against any UI-surface term or glob
(`components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`). Product **NONE**.

**Brainstorm-recommended specialists:** none (no brainstorm preceded this plan).

## Plan Review Outcome

5-agent panel (DHH, Kieran, code-simplicity, architecture-strategist, CTO) plus a
scoped strong-model consult. Both simplification reviewers fired on the same
scope, so — per the panel protocol — the response was **cut, not patch**:

**Cut (mechanical, applied):** the per-site sleep-attribution histogram (v1's
Phase 0.3 — v2's 0.3 is the loop-exit classification, which was **kept**, since
it is the documented precondition for the technique, not a nice-to-have); the
~60-row per-test delta table and its AC; the separate 3-test mutation
battery (Phase 1.3 *is* the battery — only T-6525-8's semantics change); two of
three structural guards ("every sleep site is bare", "`create_base_mocks` honours
the flag" — change-detectors asserting the line above them); four ACs; the
15-line network-outage dismissal, cut to two sentences.

**Corrected (mechanical, applied):** the false rationale for the recording rider
(T-6525-8 already pays 0 s — it is net-new coverage, not regression protection);
the User-Brand tier *argument* (P(regression) ≈ 1, so the honest ground is that
the check is advisory, with #6480 named as its expiry); AC7's false-green grep;
`git grep -c` vs `grep -c` for absence assertions; Phase 0.1's structurally
incapable ruleset path; five line-cite drifts; the missing
`workspaces-luks-harness.sh` cross-reference; `$MOCK_SLEEP_LOG` append leakage.

**Added (mechanical, applied):** the synchronization-barrier failure mode and
AC2b (5 identical name-sets under load) — the one class no other reviewer named
and that AC2 structurally cannot see; the seq↔sleep second-brake removal (R1);
the mock-level invocation cap replacing a per-call-site hard-cap; the ADR-139
tripwire framing; the mandatory second CI observation and the green-run-at-the-new-ceiling
requirement in AC7.

**Surfaced, not applied (taste / user-challenge):** four entries in
[`decision-challenges.md`](../specs/feat-one-shot-6665-ci-deploy-mock-sleep/decision-challenges.md)
— DC-1 (cut the ceiling change from this PR), DC-2 (drop the `MOCK_SLEEP_REAL`
opt-out), DC-3 (drop the recording rider), DC-4 (the 120 s target may be
arithmetically unreachable). Headless run: persisted for `ship` Phase 6 to render
and file as `action-required`, per ADR-084.

## Test Scenarios

| # | Scenario | Expected |
| --- | --- | --- |
| T1 | Full suite, default (no env) | `184/184 passed`; wall clock ≪ baseline; PASS name-set identical to baseline |
| T2 | Full suite with `MOCK_SLEEP_REAL=1` | Still `184/184`; wall clock ≈ baseline — proves the opt-out is wired **and** that the speedup came from the mock, not an accidental skip |
| T3 | T-6525-8 with `ci-deploy.sh:1437` default mutated to `9 9` | **FAIL** on the schedule assertion |
| T4 | T-6525-9 (`PULL_TRANSIENT_RETRY_SLEEPS=""`, `max=0`) | PASS with exactly 1 pull — the `-` vs `:-` empty-means-empty contract untouched |
| T5 | Trap-isolation test (`:2466-2567`) under the inverted default | PASS — structurally outside the mock PATH; `sleep 30 &` still real |
| T6 | 5 consecutive full runs, ≥1 under CPU load | Five identical PASS name-sets (AC2b) |
| T7 | A deliberate hot-spin (arm a large `MOCK_CRON_INFLIGHT_FILE` countdown, default `CRON_DRAIN_TIMEOUT`) | The mock's invocation cap aborts with a named cause in seconds — not a 1-hour hang |
| T8 | Drain trio T1/T2/T3 (`:3298`-`:3362`) | Unchanged verdicts; `cron_drain_wait_secs` still `0` |

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or placeholder fails
  `deepen-plan` Phase 4.6. Fill it before `/work`.
- **Never** write a bare `[[ … ]] && cmd` as a standalone statement in this file
  — under `set -euo pipefail` a false condition aborts the whole suite, which
  presents as a mysterious mid-run crash rather than a test FAIL.
- To mutation-prove anything in `ci-deploy.sh`, mutate **in place** with a backup
  and restore **in a separate Bash call**. A 2-file sandbox copy aborts: the test
  resolves `DEPLOY_SCRIPT` and its canary/lib siblings relative to its own dir.
- This suite exceeds the foreground Bash limit. Always `run_in_background: true`;
  do not wrap it in a 300 s `Monitor`.
- A comment is **not inert** — grep-based SSOT/count guards read comments. Do not
  paste a sibling regex's pipe sequence into the rewritten `:673-675` prose.
- **`git grep -c` cannot express "returns 0"** — it prints nothing and exits 1 on
  zero matches. Absence assertions must use `grep -c`.
- **A grep for a phrase that spans a line break is a permanent false-green.**
  `~12s of slack under timeout-minutes: 8` is split across `:607`/`:608`. Pick a
  phrase that spans no line break (and no punctuation boundary).
- **A word-boundary grep counts declarations and comments, not call sites.**
  `grep -ci '\bsleep\b' ci-deploy.sh` reads **17**; there are **15** actual
  invocations. The two extras are a comment (`:1430`) and the `_sleeps` array
  declaration (`:1437`). An AC that says "enumerate all N" must derive N from the
  same instrument the enumeration uses — this plan shipped `17` in two places
  before the verify-the-negative pass caught it.
- `TEST_PATH_BASE` (`:17`) is a `readonly` **absolute** PATH, so `$MOCK_DIR` is
  the only lever — a PATH-prepended shim outside the runners catches nothing.
  Verified empirically while measuring this plan.
- The local machine's CPU profile is not the CI runner's. Never set
  `timeout-minutes` from a local number.
