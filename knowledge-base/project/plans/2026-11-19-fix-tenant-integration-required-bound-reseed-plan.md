---
title: "fix(ci): re-seed tenant-integration-required wallclock-p90 bound"
type: fix
date: 2026-11-19
slug: tenant-integration-required-bound-reseed
branch: feat-one-shot-tenant-p90-bound
issue: 12755
priority: medium
domain: engineering
brand_survival_threshold: none
requires_cpo_signoff: false
---

# Plan: fix(ci): re-seed tenant-integration-required wallclock-p90 bound

## Enhancement Summary

**Deepened on:** 2026-11-19 (headless; no Agent/Task spawn available, so the
per-section research fan-out ran as inline verification passes — see
`## Deepen Pass` for gate verdicts and live re-verification).

**Key improvements:**

1. `## Observability` rewritten to the mandatory 5-field YAML schema
   (liveness_signal / error_reporting / failure_modes / logs /
   discoverability_test) — `scripts/*.tsv` does not match the pure-docs
   skip set, so §4.7 applies.
2. Watch-script line citations corrected against the live file: bounds
   parser §(0b) :125-159, association-guard rule at :15-16 + :197-198,
   aggregation :247-268, breach flag :292-294, epic-goal constants
   `GOAL_PR_S=1200`/`GOAL_MQ_S=900` at :96-97.
3. Unverified "#12329 skip-aware redesign" attribution removed — #12329 is
   a MERGED PR (`feat(ci): S4 PR3b — required affected-index-ratchet +
   oracle-review-required context`); the plan now states only what was
   verified.
4. One new consideration surfaced: the bound-seeding method is
   mode-blind — p90 over a bimodal population reads whichever mode has ≥4
   members in the 30-sample window, so any future "the suite got faster
   (#12905)" re-seed must re-run the same per-sample census, not just
   next-minute(p90). Recorded in Sharp Edges.

## Overview

Re-seed the `tenant-integration-required` pull-request wallclock bound in
`scripts/required-check-wallclock-bounds.tsv` (300s → 960s, measured p90 → next
minute per the TSV's own seeding contract) and record the re-measurement
provenance in the runbook's `## Measured history` — same one-row edit merged as
PR #12877 for `oracle-review-required`, now applied to the second check in the
required population with a structurally bimodal latency profile.

## Problem Statement

- `scripts/watch-wallclock-p90-11774.sh --print-report` (dry-run 2026-11-19,
  60 sampled successful `ci.yml` runs, 30 per surface — last 30
  `pull_request` + last 30 `merge_group`, 755 qualifying samples, 0 failed
  check-run reads, sentinel `46676c5b`) produced:

  ```text
  tenant-integration-required | pull_request | n=26 | p50=50s | p90=915s | duration_p90=21s | bound=300s
  tenant-integration-required | merge_group  | n=30 | p50=50s | p90=70s  | duration_p90=21s | bound=180s
  ::error::wallclock p90 breach: 'tenant-integration-required' (pull_request) p90=915s > bound 300s x (1+0.30)
  ```

- The check's own execution is ~21s at p90. The PR-surface bound of 300s was
  seeded at #11774 before the window contained a path-gated heavy suite run;
  the brief's alternative hypothesis (queue-side wait vs execution-side
  regression, per #12905) is tested and refuted below — the tail is the
  check's own heavy predecessor, not runner queueing.
- The scheduled Friday 09:07 UTC `wallclock-p90-watch` run posts drift
  comments to standing tracker #12755; the 2026-11-13 report already flagged
  this same breach (~900s). Left unresolved it re-fires on the next scheduled
  run and keeps emitting a false-positive finding against a bound that cannot
  cover a legal latency class this check emits.

## Evidence — per-sample timeline analysis (required by the brief)

The brief asks whether the ~900s tail is *concentrated in bursts* or the *new
normal*, with a per-sample timeline over the rolling window. The answer, from
per-run API measurement of the same 30 sampled PR runs the watch consumed, is
**neither**: the population is **bimodal** — a fast mode at ~11-76s and a slow
mode at ~915-970s that appears exactly when the heavy `tenant-integration`
suite runs. Full timeline (26 qualifying + 4 `NOSAMPLE` = n=26, matching the
dry-run):

| Run `created_at` (UTC) | latency_s | duration_s | class |
|---|---|---|---|
| 2026-11-16T18:41:23Z | 46 | 18 | fast |
| 2026-11-16T18:43:06Z | 49 | 17 | fast |
| 2026-11-16T19:00:31Z | 43 | 16 | fast |
| 2026-11-16T19:06:50Z | 42 | 15 | fast |
| 2026-11-16T20:31:07Z | 42 | 11 | fast |
| 2026-11-16T20:56:21Z | 76 | 19 | fast |
| 2026-11-16T21:07:20Z | 62 | 21 | fast |
| 2026-11-16T22:35:12Z | 48 | 16 | fast |
| 2026-11-17T08:03:08Z | 54 | 16 | fast |
| 2026-11-17T12:58:38Z | NOSAMPLE | — | censored (earlier-batch check predates run `created_at`) |
| 2026-11-17T13:04:55Z | 11 | 18 | fast |
| 2026-11-17T14:01:29Z | 52 | 17 | fast |
| 2026-11-17T14:46:44Z | 55 | 24 | fast |
| 2026-11-17T16:06:01Z | NOSAMPLE | — | censored (earlier-batch check predates run `created_at`) |
| 2026-11-17T16:37:14Z | 46 | 12 | fast |
| 2026-11-17T17:19:16Z | 23 | 17 | fast |
| 2026-11-18T08:02:46Z | 46 | 19 | fast |
| 2026-11-18T10:05:35Z | 54 | 21 | fast |
| 2026-11-18T11:45:41Z | NOSAMPLE | — | censored (suite `cancelled` → gate failed closed) |
| 2026-11-18T11:58:57Z | NOSAMPLE | — | censored (earlier-batch check predates run `created_at`) |
| 2026-11-18T12:24:23Z | 50 | 17 | fast |
| 2026-11-18T13:37:58Z | 49 | 17 | fast |
| 2026-11-18T14:50:44Z | 67 | 30 | fast |
| 2026-11-18T14:52:44Z | **970** | 18 | **slow** |
| 2026-11-18T14:56:23Z | **915** | 17 | **slow** |
| 2026-11-18T17:02:52Z | 53 | 20 | fast |
| 2026-11-18T17:45:20Z | 16 | 20 | fast |
| 2026-11-18T23:08:43Z | **958** | 19 | **slow** |
| 2026-11-19T08:03:08Z | 51 | 20 | fast |
| 2026-11-19T10:07:31Z | 60 | 18 | fast |

Nearest-rank p90 over the 26 qualifying samples = index ceil(0.9×26)=24
(sorted), which lands in the 3-member slow cluster → p90=915s. The math is
mechanical: the moment ≥3 slow-mode samples are in-window, p90 reads the slow
mode while p50 (index 13) keeps reading the fast one (50s).

**The discriminator — sibling checks on the same slow runs.** On the three
tail runs, every other required check's latency (same `created_at` baseline,
same queue) was ≤478s: `guards-ruleset` ~112s, `e2e` ~355s, `quality-guards`
~478s, advisory/oracle/cla/secret/sentry/vendor legs ≤220s. Only
`tenant-integration` (the heavy job, `timeout-minutes: 19`,
`.github/workflows/tenant-integration.yml:236-243`) sat at ~835-910s, and the
aggregator's own completion follows it by ~19s in every case:

| tail run | tenant suite duration | check completed vs suite `completed_at` |
|---|---|---|
| 14:52Z | ~910s | +19s after |
| 14:56Z | ~835s | +20s after |
| 23:08Z | ~892s | +20s after |

So the check's wallclock ≈ suite runtime + ~60s of its own pipeline. A
queue-congestion burst would inflate *every* check on those runs; instead the
tail is specific to this check's own `needs` chain. The `detect-changes` job
is cheap, so fast-mode runs skip the heavy suite entirely (aggregator posts a
skipped-required success in ~50s); the slow mode is exactly the suite's legal
duration when the isolation surface is touched. `#12905` — which narrows the
test set *inside* the suite — could shorten the slow mode but does not remove
it, and is unrelated to queue wait.

**What the 4 `NOSAMPLE`s are.** Three are `earlier-batch`: a check run from a
prior same-sha push batch completed before the sampled run's `created_at`, so
the watch's association guard (:197-198) correctly declines it — they are
exclusions, not dropouts. The fourth (11:45Z, 11-18) is genuinely interesting
but in a different class: the heavy suite was `cancelled` at ~15.6 min —
consistent with the workflow's documented third-arrival eviction arm
(`.github/workflows/tenant-integration.yml:295-305` — "the eviction ARM stays:
it resolves the mutex by cancelling the predecessor run's suite job …
accepted, NOT greened") — and the aggregator fail-closed to `failure`
conclusion, which the watch's status filter excludes. One eviction event in
the 30-run window; the runbook bullet names it as observed history.

## Adjudication (the three-way decision the brief requires)

- **(a) bound mis-seed — ADOPTED.** The check emits two legal latency classes
  and a single bound must cover both, or the ratchet flags its own design.
  Re-seed PR bound to next-minute(p90) = 960s — the TSV header's own method,
  identical to merged PR #12877. Under the re-seeded bound the breach flag
  clears because the bound now covers the slow mode; margin 0.30 absorbs the
  observed max (970s ≪ 960×1.3=1248s).
- **(b) transient tail — REJECTED.** The slow mode is not congestion decaying
  on its own: it is the suite's legal duration, will recur on every
  isolation-surface PR, and re-enters any 30-sample window that catches ~3
  such runs. The 11-13 breach (~900s) is the same mode measured twice, one
  week apart — "self-resolved" only because slow samples rolled out of the
  window, not because the cause resolved.
- **(c) systemic regression — REJECTED.** duration p90=21s ≈ oracle's own
  ~10s class: the aggregator is healthy. The suite runtime (~15 min) sits
  inside its own `timeout-minutes: 19` budget and is the designed behavior of
  the path-gate, already tracked for *narrowing* by #12905 — a latency-cost
  matter for Epic #11556, not a regression finding. The only systemic defect
  is the bound's seed, which this slice fixes.

(Required-context provenance: `tenant-integration-required` came required via
the #5585-class aggregator gate work; the oracle sibling's context was added
by MERGED PR #12329 — verified live 2026-11-19.)

## Proposed Solution

- `scripts/required-check-wallclock-bounds.tsv` (data layer): one-row edit,
  tabs preserved —
  `tenant-integration-required␉960␉180␉0.30`. Seed provenance lands as a
  `# ROW SEED` comment (same comment-block slot and field shape as the
  2026-11-17 oracle seed: measured p90 → next minute per surface, sampled
  dates, n, sentinel commit of the measurement script).
- `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md`
  (`## Measured history`): one bullet recording the 2026-11-19 measurement
  that moved the bound — including the bimodal finding, the
  sibling-check discriminator, and the eviction note — since that section's
  contract is that every bound-moving measurement is recorded there.
- The `merge_group` bound stays 180s: measured p90=70s, fast mode only —
  merge groups post a skipped-required context rather than rerunning the
  dev-Supabase suite, so no slow mode exists on that surface.
- Out of scope — deliberately: no bound-semantics change (the metric's
  single-bound-per-surface design stands; the check is healthy — only its
  seed is stale), no workflow/script behavior change, no tightening of the
  mq bound, no new issue filed for the eviction event (it is the mutex's
  documented accepted residual).

## Technical Considerations

- **File shape (TSV):** tab-separated 4-column data rows; `#` comment lines
  and blanks ignored by the reader (`awk -F'\t'` NF check at
  `scripts/watch-wallclock-p90-11774.sh:134`, bounds-table section (0b)
  :125-159). The edit must keep literal tabs in the row — the suite's AC
  asserts the row with `awk -F'\t'`, not a whitespace-insensitive grep.
- **Seed contract (file header, `required-check-wallclock-bounds.tsv:3-6`):**
  bound = `ceil(p90/60)*60` with margin `0.30` ⇒ breach threshold bound×1.3
  (flag at :292-294); a bound may loosen only with the measurement recorded
  in the runbook.
- **Epic goals at source:** `GOAL_PR_S=1200`/`GOAL_MQ_S=900`
  (`watch-wallclock-p90-11774.sh:96-97`) — the seeded bounds sit inside
  both; the epic's 20-minute PR goal is a p90 goal, and today the slow
  mode alone (915s) fits inside it.
- **Association guard (why 3 of the NOSAMPLEs are excluded):** the watch
  never associates a check run that completed BEFORE the sampled run's
  `created_at` — that check belongs to an earlier trigger batch
  (header comment :15-16, resolvable-candidate impl :197-198).
- **Check-name shape:** the TSV check name must match the REQUIRED-check job
  name as it appears in the check-runs API — `tenant-integration-required`
  matches `scripts/required-checks.txt` and the workflow's aggregator job
  name; no rename involved.
- **Measurement protocol (unchanged):** `GH_TOKEN` in env ⇒
  `bash scripts/watch-wallclock-p90-11774.sh --print-report`; the report
  table is the artifact the runbook bullet cites; no state is written by a
  `--dry-run`/`--print-report` invocation.
- **Precedent:** merged PR #12877 —
  `knowledge-base/project/plans/2026-11-17-fix-oracle-review-required-bound-seed-plan.md`
  is the sibling plan; its `decision-challenges.md` carries the binding CTO
  ruling on `Ref`-vs-`Closes` for tracker #12755, reused verbatim here.
- **Merge effect:** the TSV is read at every watch invocation
  (`--bounds-file` default); after merge the next scheduled run measures
  against the new bound. No `on.push.paths` workflow applies these files —
  nothing auto-fires on merge; the only consumer is the Friday cron +
  `workflow_dispatch` watch itself.
- **Pre-merge check-run association is per-sha** (`/check-runs` on the PR
  head sha, nearest `check_suite.id` then `started_at`), so a same-repo PR
  re-verification is the prescribed proof rather than a workflow_dispatch.

## Research Insights

<details><summary>Click to expand research insights</summary>

### Premise Validation (Phase 0.6)

Every user-invented claim verified authoritative (fresh `gh` reads
2026-11-19):

- `tenant-integration-required` row present in TSV with `300␉180␉0.30` —
  confirmed; no other bound row or consumer pins its value (grep of
  `tests/`, `plugins/soleur/test/`, `scripts/*.test.sh` finds only fixture
  references and the SUT's own suite which seeds via `WATCH_BOUNDS` seams).
- Watch population: 13 required-check names from `required-checks.txt` ⇄ 13
  bound rows ⇄ 13 emitted rows — all three censuses equal (population check
  in the dry-run stderr).
- #12755 OPEN standing tracker, `ci-health` label, `wallclock-p90-watch:v1`
  sentinel present; `comments=5`; the 2026-11-13 body carried this same
  tenant breach alongside the `test` breach and oracle unbound.
- #12877 `state: MERGED`, `mergedAt: 2026-11-17` — file shapes verified from
  its merged diff (TSV row `oracle-review-required␉180␉120␉0.30` + `# ROW
  SEED` comment; runbook bullet under `## Measured history`).
- #12905 OPEN — narrows the tenant test set inside the suite; confirmed it
  does not touch queue wait and does not change the bound's slow-mode
  coverage requirement.
- #11556 OPEN epic — this slice serves its 20-minute PR required-check goal
  by keeping the ratchet honest.
- No open PR touches `scripts/required-check-wallclock-bounds.tsv`
  (`gh pr list --search` on the path — empty).

### Property List (Phase 0.6b)

1. The breach is adjudicated with per-sample evidence (the timeline above).
2. The chosen disposition lands: TSV row + `# ROW SEED` comment + runbook
   `## Measured history` bullet.
3. The commit-time re-verification holds (each bound ≥ re-measured p90 of
   its own surface at edit time).
4. The Friday 09:07 UTC scheduled watch does not flag
   `tenant-integration-required` again for the same seed class.
5. No file outside the two prescribed paths changes.

### Cut List (Phase 0.6b)

| Mechanism | What the ask proposes | Cheaper existing alternative | CUT? |
|---|---|---|---|
| Re-seed via TSV row + comment + runbook bullet | One bound-row update with provenance | None — the TSV header's documented seeding method IS this mechanism; the watch has no per-mode bound feature (splitting surfaces/modes is an architecture change nobody asked for) | NO |
| Bound-semantics change (per-mode bounds, suite-duration subtraction) | Not proposed — surfaced during analysis | Would mask the slow mode rather than measure it; the latency IS the suite wait by design of the metric | CUT — mechanism invention beyond the ask |

### Learnings applied (grep over `knowledge-base/project/learnings/`)

- **Seed vs flag (11774-class):** a stale seed emits a false-positive breach
  forever; the fix is re-measurement, not suppression — oracle slice
  (merged #12877).
- **`pending - assumed` rows (no-nested-subagent harness):**
  `knowledge-base/project/learnings/workflow-patterns/2026-11-01-devin-subagents-cannot-spawn-nested-subagents.md`
  + the 2026-10-30 technical-rulings learning — this planning subagent has
  no spawn tool; technical rows are written `pending - assumed:` for the
  parent's one batched `soleur:engineering:cto` consult; the closing-keyword
  row is already ruled (binding input, not re-ruled).
- **Bound semantics:** a bound governs the population it measures — the
  measured population here includes the heavy-suite mode by design, so the
  bound must cover it (#12016/PR #12419 mutant-side-vs-pristine learning:
  derive caps from the measured distribution, not from the mode you wish
  you had).

</details>

## Research Reconciliation

Research is fully consistent: the dry-run aggregate (p90=915s), the
per-sample timeline (3/26 slow at 915-970s), the sibling-check
discriminator (no shared congestion), and the workflow's own
`timeout-minutes: 19` all point the same direction — bimodal seed
insufficiency, disposition (a).

## User-Brand Impact

- **If this lands broken, the user experiences:** the weekly
  wallclock-p90 digest keeps reporting a false-positive tenant breach on
  #12755 — a noisy standing finding that can mask the next real breach.
- **If this leaks, the user's [data / workflow / money] is exposed via:**
  nothing user-facing — the diff is a CI-observability data row plus
  knowledge-base artifacts; no user data, credentials, or product surface
  is touched.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** internal CI-observability repair
  on a config data file; a wrong bound produces a red or a quiet weekly
  watch run, not a user-visible incident — `none`, not `single-user
  incident`.
- `threshold: none, reason: the touched paths are a CI-observability TSV
  and knowledge-base docs — no user-facing surface or regulated data`

## Observability

The watch IS the observability layer; this slice corrects one of its
calibration inputs. Metric: `latency_s = completed_at - run.created_at`
nearest-rank p50/p90 per (check, surface) — definition at
`watch-wallclock-p90-11774.sh:18-30`, aggregation at :247-268.

```yaml
liveness_signal:
  what: weekly wallclock-p90-watch verdict + standing tracker #12755 body
  cadence: weekly (Fri 09:07 UTC) + workflow_dispatch
  alert_target: operator digest §6 (reads tracker by ci/wallclock-p90 label)
  configured_in: .github/workflows/wallclock-p90-watch.yml
error_reporting:
  destination: standing tracker body + drift comments (issue #12755)
  fail_loud: "flagged findings list names offenders; exit 1 turns the workflow red"
failure_modes:
  - mode: "bound row malformed (wrong columns/non-numeric)"
    detection: "probe exit 3 cannot-establish; ::error:: names the row"
    alert_route: "weekly workflow goes red; tracker reports cannot-establish"
  - mode: "seeded bound drifts below real p90 (slow-mode recurrence)"
    detection: "breach finding when p90 > bound x 1.30"
    alert_route: "weekly workflow red + drift comment on flagged-set change"
logs:
  where: "GitHub Actions log of wallclock-p90-watch.yml; tracker issue body history"
  retention: "Actions retention window; tracker body rewritten each run"
discoverability_test:
  command: "grep -c '^tenant-integration-required' scripts/required-check-wallclock-bounds.tsv"
  expected_output: "1"
```

- **Verification hook (pre-merge):** `gh api
  'repos/{owner}/{repo}/commits/<pr-head-sha>/check-runs?per_page=100'` —
  `tenant-integration-required` `started_at`/`completed_at` ≈ ~50s on the
  PR's own head (fast mode; the PR touches no isolation surface).
- **Verification hook (post-merge):** dry-run against `main` head shows the
  check's row and no `::error::` line for it; next scheduled drift comment
  on #12755 omits the tenant breach.

## Open Code-Review Overlap

Searched `gh pr list --state open` + `gh pr list --search
'required-check-wallclock-bounds in:file'` — no open PR touches the TSV or
the runbook section; the only worktree-sibling process observed
(`test-all.sh` in another worktree) is unrelated.

## Functional Overlap

No community artifact is implicated: the change is a one-row data edit to a
repo-local bounds file plus a runbook bullet — the discovery fan-out has no
applicable registry surface (same call the oracle slice made).

## Implementation Phases

### FR-1 — Re-seed the bound row (TSV)

Edit `scripts/required-check-wallclock-bounds.tsv`: change the
`tenant-integration-required` row's pull-request column `300` → `960`
(literal tabs preserved; `merge_group` `180` and margin `0.30` unchanged).
Add a `# ROW SEED` comment block in the header notes area (after the oracle
seed block), matching the 2026-11-17 shape:

```text
# ROW SEED (tenant-integration-required): re-measured 2026-11-19T<HH:MM>Z
#   pull_request: n=<n> p90=<p90>s duration_p90=<d>s -> bound 960
#   merge_group:  n=<n> p90=<p90>s duration_p90=<d>s -> bound 180 (unchanged)
#   sentinel: <commit sha of the measurement script at measure time>
#   note: bimodal latency — slow mode = tenant-integration suite wait
#   (needs-chain), not queue congestion; see runbook Measured history.
```

Fields filled from the commit-time re-measurement (FR-3).

### FR-2 — Record the measurement (runbook)

Append one bullet under `## Measured history` in
`knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md`
(after the 2026-11-17 oracle bullet), shape per that bullet:

```markdown
- **2026-11-19 `tenant-integration-required` bound-row re-seed**
  (issue #12755, breach measured 2026-11-19; Epic #11556): measured PR p90
  915s (n=26), merge-group p90 70s (n=30) → bounds 960/180, margin 0.30.
  Finding: bimodal latency — 23/26 samples at 11-76s vs 3 at 915-970s
  (2026-11-18T14:52/14:56/23:08Z); the tail tracks the heavy
  `tenant-integration` suite duration (~835-910s, `timeout-minutes: 19`) on
  isolation-surface PRs, with sibling checks on the same runs ≤478s — suite
  `needs`-chain wait, not queue congestion; check's own duration_p90=21s.
  4 NOSAMPLE: 3 earlier-batch exclusions + 1 suite-cancelled
  (mutex-eviction arm) gate fail-closed. Prior 2026-11-13 breach (~900s)
  was the same mode. #12905 may shorten the suite; the bound must cover it
  meanwhile.
```

### FR-3 — Commit-time re-verification

Before committing the TSV edit, re-run the measurement:

```bash
GH_TOKEN="$(gh auth token)" bash scripts/watch-wallclock-p90-11774.sh \
  --print-report --dry-run
```

Assert in the report: `tenant-integration-required` row present on both
surfaces; `pull_request` p90 ≤ 960; `merge_group` p90 ≤ 180; no
`::error::` line for this check. If the re-measured PR p90 exceeds 960
(slow-mode drift beyond today's 915-970 band), re-seed to
`next-minute(re-measured p90)` and update the ROW SEED comment + runbook
bullet numbers accordingly — same method, new measurement.

### FR-4 — PR hygiene

PR body carries `## Changelog` (version-bump workflow requirement),
references `Ref #12755` (NOT `Closes` — standing tracker; binding CTO
ruling from the oracle slice), names #12905 as the complementary
suite-narrowing track under Epic #11556.

## Files to Edit

| File | Change |
|---|---|
| `scripts/required-check-wallclock-bounds.tsv` | `tenant-integration-required` PR bound 300→960 + `# ROW SEED` provenance comment |
| `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md` | one `## Measured history` bullet |

## Files to Create

None — planning artifacts only (this plan + `specs/feat-one-shot-tenant-p90-bound/{tasks.md,decision-challenges.md}`), which are pipeline output, not product diff.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "adjudicate the `tenant-integration-required` required-check wallclock bound breach" | Evidence section + Adjudication section / FR-1 | mapped |
| 2 | "The plan must pick between: (a) bound mis-seed → re-seed ... ; (b) transient tail → leave the bound and document why; (c) genuine systemic regression → file a regression finding issue" | Adjudication section — (a) adopted, (b)/(c) rejected with reasons | mapped |
| 3 | "a per-sample timeline analysis of this check's wallclock across the rolling window — is the ~900s concentrated in bursts or the new normal? — produced by re-running the dry-run measurement and/or reading the watch script's data sources" | Evidence section — 30-row timeline + sibling-check discriminator; answer: neither, bimodal | mapped |
| 4 | "this slice should adjudicate before then" (before Friday 09:07 UTC watch run) | Overview + AC-5 (post-merge dry-run before next scheduled run) | mapped |
| 5 | "Reference merged PR #12877 for the seeding method and the exact file shapes (TSV columns, ROW SEED comment, runbook section)" | Technical Considerations + FR-1/FR-2 shapes | mapped |
| 6 | "Also read `scripts/watch-wallclock-p90-11774.sh` to understand how p90 and n are computed before prescribing the analysis" | Technical Considerations + Evidence (nearest-rank p90 math, NOSAMPLE classes) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|---|---|---|
| TSV bound-row re-seed (FR-1) | "(a) bound mis-seed → re-seed using the measured-p90→next-minute method used for `oracle-review-required` in merged PR #12877" | asked |
| `# ROW SEED` comment (FR-1) | "including the TSV row, the `# ROW SEED` provenance comment" | asked |
| Runbook `## Measured history` bullet (FR-2) | "and the runbook `Measured history` bullet" | asked |
| Commit-time re-verification (FR-3) | "produced by re-running the dry-run measurement" | asked |
| PR-body `## Changelog` + `Ref #12755` (FR-4) | — | inferred — justification: `## Changelog` is the version-bump workflow's hard requirement and `Ref`-vs-`Closes` on the standing tracker is a binding prior CTO ruling (oracle slice), not optional style |

### Split Assessment

- Subsystems touched: 2 — `scripts/`, `knowledge-base/`
- Planned files: 2 | Estimated changed lines: ~20
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] **AC-1 (diff scope).** `git diff --name-only origin/main...HEAD` lists
  exactly: `scripts/required-check-wallclock-bounds.tsv`,
  `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md`,
  and the planning artifacts under `knowledge-base/project/plans/` +
  `knowledge-base/project/specs/feat-one-shot-tenant-p90-bound/`.
- [ ] **AC-2 (bound row).**
  `awk -F'\t' '$1=="tenant-integration-required"{print $2,$3,$4}' scripts/required-check-wallclock-bounds.tsv`
  prints `960 180 0.30` (literal tabs in the file; re-run this exact command
  — verified pre-plan it prints `300 180 0.30` today).
- [ ] **AC-3 (provenance).** `grep -c 'ROW SEED (tenant-integration-required)' scripts/required-check-wallclock-bounds.tsv` ≥ 1 and the comment records the commit-time measurement fields (n, p90, duration_p90, sentinel sha).
- [ ] **AC-4 (runbook).**
  `grep -c 'tenant-integration-required.*bound-row re-seed' knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md`
  ≥ 1 under `## Measured history`, and the bullet names the bimodal finding +
  the sibling-check discriminator.
- [ ] **AC-5 (invariant, not proxy).** Post-edit dry-run on the merge head:
  `GH_TOKEN="$(gh auth token)" bash scripts/watch-wallclock-p90-11774.sh --print-report --dry-run`
  emits the `tenant-integration-required` row on both surfaces with PR p90 ≤
  960 and produces **no** `::error::wallclock p90 breach` line for it
  (verified by grepping stderr — pre-change this command emits exactly one
  such line).
- [ ] **AC-6 (PR-body contract).** PR body contains `## Changelog`, `Ref
  #12755` (no `Closes`/`Fixes`/`Resolves` against #12755 —
  `grep -ciE 'closes #12755|fixes #12755|resolves #12755'` on the body = 0),
  and names #12905.

## Test Scenarios

- **Red-driving check:** AC-2/AC-5 fail on the current tree today
  (verified at plan time: the awk prints `300 180 0.30`; the dry-run emits
  the `::error::` line) — they are genuine red→green gates, not tautologies.
- **Vacuity check on AC-5:** the "no `::error::` line" assertion is
  meaningful only because the same command emits the line today — the
  trigger is demonstrably reachable in both directions.
- **NOSAMPLE regression guard:** the 4 censored samples must remain
  censored post-change (the watch's association + status filters are
  untouched); if a future n rises above 26 without a matching run census,
  that's a population anomaly worth a fresh look, not something this slice
  green-lights.

## Domain Review

| Domain | Relevant? | Leader run | Rationale |
|---|---|---|---|
| engineering (CI/observability) | Yes — inline | n/a (no leader spawn needed; sub-agent harness) | bounds TSV + runbook; adjudication done inline from measured data |
| product/design | No | — | no user-facing surface |
| infra | No | — | no IaC surface touched |
| legal/finance/marketing/sales/support/operations | No | — | n/a |

## Skipped Gates

- **GDPR gate:** skipped — no regulated-data surface (CI check-run
  timestamps and a TSV bound are not personal data).
- **IaC gate:** skipped — no infrastructure introduced or modified.
- **Architecture ADR/C4:** skipped — data-file + docs edit; the metric's
  architecture (single bound per surface) is unchanged by design.
- **Community discovery:** skipped per Functional Overlap — no applicable
  registry surface.
- **Domain-leader fan-out:** no spawn tool on this harness; engineering
  adjudication performed inline with measured evidence (recorded in
  `decision-challenges.md`).

## Context

- Epic #11556: "cut PR required-check time from ~1h to 20 min or less" —
  this slice serves the epic's observability honesty: an honestly-seeded
  bound is what makes the ratchet's *true* findings actionable.
- Tracker #12755 (OPEN, standing): receives the Friday drift comments;
  this slice removes a recurring false-positive line from them.
- #12905 (OPEN): narrows the tenant test set — complementary execution-side
  work; if it lands and shortens the suite, a later re-seed DOWN is the
  same one-row mechanism (bound may loosen with recorded measurement).
- **Observation for the record:** one suite-`cancelled` eviction event in
  the window (11-18T11:45Z) produced a gate fail-closed — the mutex's
  documented accepted residual, per the workflow comment at
  `tenant-integration.yml:295-305`. Not a finding; noted so the runbook
  history records the full picture.
- Prior breach 2026-11-13 (~900s, n=30): same slow mode, earlier window —
  it did not "self-resolve"; the samples rolled off.

## Sharp Edges

- **Literal tabs** in the TSV row — a space-substituted row silently
  corrupts every downstream `awk -F'\t'` field read. (sharp-edge: tabs are
  the literal delimiter; assert with `awk`, not `\s+`.)
- **`origin/main...HEAD` merge-base form** for the diff-scope AC — two-dot
  diffs lie after `origin/main` moves.
- **`pending - assumed`, not operator items:** the technical rows in
  `decision-challenges.md` carry `pending - assumed:` for the parent's one
  batched `soleur:engineering:cto` spawn (no nested-subagent tool on this
  harness — learning 2026-11-01); the row already ruled on #12877
  (`Ref`-vs-`Closes`) is binding, not re-ruled.
- **No `Closes #12755`:** closing the standing tracker would blind the
  Friday drift machinery — precedent + binding ruling from the oracle slice.
- **Bound covers the measured population:** 960 is p90-derived, not
  max-derived; the 0.30 margin is the designed absorber for the 970s max
  (1248 > 970). Do not "round to the max" — that would double-count margin.
- **Commit-time drift:** if the re-measured p90 lands above 960 before
  commit, the FR-3 conditional arm re-seeds to next-minute(p90) — the
  contract is bound ≥ commit-time p90, not "the number written in this
  plan".

## Deepen Pass

Recorded 2026-11-19. No nested-subagent capability in this harness (per
`2026-11-01-devin-subagents-cannot-spawn-nested-subagents`), so the skill's
fan-out ran as inline verification passes; the parent pipeline may still run
`soleur:plan-review` and the batched CTO consult downstream.

### Gate verdicts

| Gate | Verdict |
|---|---|
| 4.4 Precedent-diff | PASS — see below; sibling data rows uniform `<name>\t<int>\t<int>\t0.30`, dated `#`-header seed notes are the canonical provenance form (oracle `# ROW SEED`, merged #12877) |
| 4.45 verify-the-negative / self-audit | see below |
| 4.5 Network-outage | not triggered — `timeout`/`SSH`/`5xx` patterns absent from Overview, Problem Statement, and hypotheses (`timeout-minutes` appears only in the Evidence table's job-constant citation) |
| 4.55 Downtime & Cutover | not triggered — TSV data row + docs only |
| 4.6 User-Brand Impact | PASS — section present, threshold `none`, touched paths miss the sensitive-path regex, scope-out reason present |
| 4.7 Observability | PASS — all 5 fields non-placeholder; probe verb `grep` is Check-10 allowlisted; `expected_output` literal `1`; no SSH, no banned metacharacters, sub-15 s; command executed once: prints `1` today (row exists — the probe discovers the row, not the bound value) |
| 4.8 PAT-shaped variable | PASS — zero hits on the 4-pattern sweep (`GH_TOKEN=` env read is the watch's existing mechanism, not a `var.*`/`TF_VAR_*` infra-write credential) |
| 4.9 UI wireframe | not triggered — no UI-surface files |
| 4.10 Encryption posture | not triggered — no store/connection introduced; the word "queue" in prose is the runner-queue symptom noun, not a provisioned store |
| 4.11 Guard contract | not triggered — deliverable is a data row; prose references the watch's EXISTING association guard, unchanged |
| 4.12 Scope check | PASS — exactly 1 unfenced `## Scope Check`; 6 mapped asks; the one `inferred` row justified; `Recommendation: single PR` present; no `status: BLOCKED` |
| 4.13 Task design | not triggered — no autonomous-task surface |

### Claims re-verified live (2026-11-19)

- #12755 OPEN standing tracker; `wallclock-p90-watch:v1` sentinel present;
  2026-11-13 body carried this same tenant breach (`gh issue view`).
- #12877 `state: MERGED` — file shapes mirrored from its merged artifacts.
- #12905 OPEN — narrows the tenant test set inside the suite.
- #11556 OPEN epic; goals read at source `GOAL_PR_S=1200`/`GOAL_MQ_S=900`
  (`watch-wallclock-p90-11774.sh:96-97`).
- #12329 MERGED PR, title `feat(ci): S4 PR3b — required
  affected-index-ratchet + oracle-review-required context` — the plan now
  cites it only as the oracle context's requiring PR; an earlier draft's
  "skip-aware redesign" attribution was dropped as unverified.
- Watch-script citations re-read at line level: bounds parser `awk -F'\t'`
  NF check :134 (section (0b) :125-159); association-guard rule :15-16 +
  impl :197-198; aggregation `sorted(vals)` :257 within :247-268; breach
  flag :292-294; `unbound` finding :281.
- Workflow citations: `tenant-integration:` job :236,
  `timeout-minutes: 19` :243 with the #12905 sizing comment; eviction-arm
  comment :295-305 ("accepted, NOT greened"); Friday cron `7 9 * * 5`
  confirmed in `wallclock-p90-watch.yml` (:66).
- TSV header seed contract re-read at
  `required-check-wallclock-bounds.tsv:3-6`; AC-2's awk ran pre-edit and
  prints `300 180 0.30` as the AC expects; AC-5's dry-run emitted exactly
  one `::error::` line for this check.
- No open PR touches `scripts/required-check-wallclock-bounds.tsv`
  (`gh pr list --search`).
- Rule-id citations in the plan body: none — nothing to check against the
  active/retired registries.
- Labels prescribed: none — no `gh issue create` in this plan.

### Verify-the-negative + self-audit

- "No queue congestion" — supported positively, not just by absence:
  sibling checks measured on the SAME three slow runs stayed ≤478s while
  `tenant-integration` sat at ~835-910s and the aggregator completed ~19s
  after it each time. A shared-queue burst inflates all checks; the tail
  is specific to this needs-chain.
- "Not execution regression" — duration_p90=21s ≈ fast-mode durations
  (11-30s) across all 26 qualifying samples; no duration outlier exists.
- "4 NOSAMPLE = exclusions, not dropouts" — 3 match the earlier-batch
  predicate (check `completed_at` < run `created_at`, guard :197-198);
  1 is a suite-`cancelled` gate fail-closed excluded by the success-only
  filter. Post-edit census must still read n=26±window-drift, never a
  silent jump.
- Post-edit self-audit: no symbols, files, or fixtures dropped or
  renamed — trivially clean.

### Precedent-diff (§4.4)

Sibling data rows are uniform `<name>\t<int>\t<int>\t0.30` and dated
`#`-header seed notes are the provenance precedent (UMBRELLA RE-SEED plus
the 2026-11-17 `# ROW SEED` block merged in #12877). This edit changes one
field of an existing row and adds a same-shape comment block — no
precedent divergence.

## References

- Standing tracker: #12755 · Epic: #11556 · Ratchet issue: #11774 ·
  Precedent: merged PR #12877 + its archived sibling plan
  (`knowledge-base/project/plans/archive/20261117-181758-2026-11-17-fix-oracle-review-required-bound-row-plan.md`)
- `scripts/required-check-wallclock-bounds.tsv` header (columns + seeding
  method) · `scripts/watch-wallclock-p90-11774.sh` (metric :18-30,
  population, association guard :197-198, aggregation :247-268,
  breach flag :292-294)
- `.github/workflows/tenant-integration.yml` (path-gated suite :236-243,
  eviction arm :295-305) · `.github/workflows/wallclock-p90-watch.yml`
  (cron `7 9 * * 5`)
- Runbook:
  `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md`
  §The wall-clock ratchet · §Measured history
- Complementary: #12905 (tenant test-set narrowing, execution side)
