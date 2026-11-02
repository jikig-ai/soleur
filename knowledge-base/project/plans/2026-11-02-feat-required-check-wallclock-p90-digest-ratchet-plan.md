---
title: "feat(observability): required-check wall-clock p50/p90 per job in the weekly operator digest + regression ratchet"
date: 2026-11-02
slug: feat-required-check-wallclock-p90-digest-ratchet
branch: feat-one-shot-11774-p90-wallclock-ratchet
issue: 11774
---

## Overview

Epic #11556 needs a standing instrument for its 20-min/15-min required-check wall-clock goals: a weekly probe that computes per-required-check p50/p90, publishes the table where the weekly operator digest can read it, and fails loudly when a job's p90 drifts past its committed bound. Issue #11774 (Lever E, first item).

## Research Insights

**Premise validation** (Phase 0.6): #11556 OPEN (epic, Lever E item 1 = this issue verbatim); #11564 CLOSED (the drift-watch precedent shipped); #11648/#11647 CLOSED-merged as the dispatch brief states; #11729 (post-advisory follow-ups), #11810, #10448, #11776 all OPEN and correctly out of scope. Cited artifacts all exist on the branch: `scripts/watch-shard-balance-11564.sh`, `scripts/followthroughs/deploy-script-tests-legs-8736.sh`, `scripts/required-checks.txt` (24 non-comment rows), `plugins/soleur/skills/operator-digest/` + `assets/operator-digest.workflow.yml`, ADR-057. Collision precheck: only our own draft PR #11842 — no foreign work. ADR-mechanism check: a scheduled repo-scoped Actions watch + watch-owned tracker matches ADR-033 and three live siblings (shard-balance-watch, registration-narrowing-watch, code-quality-followups-watch); digest synthesis stays LLM-prose per ADR-057 (agent cannot post, scrub gate posts) — no mechanism sits in a rejected-alternatives table.

**Mechanism minimality** (Phase 0.6b). Property list: (P1) weekly per-required-check p50/p90 wall-clock visible to the operator; (P2) a bound breach fails loudly naming the offending check; (P3) aggregate-only data (ADR-057 — no per-PR/per-actor); (P4) missing data reports, never fails; (P5) a required check added later is measured without a code change (learnings 2026-10-04, 2026-08-04). Cut list: no new persistent store or committed report file (samples computed on the fly; the watch-owned tracker body carries the weekly table — gh reads/writes only); no sweeper followthrough (a standing weekly monitor needs per-verdict dedup — the sibling watch headers document why the sweeper is the wrong home); no leg-level bound rows (legs are not required contexts; `test`'s queue-to-green latency already captures leg cost through `needs:`).

**Measurement facts** (verified 2026-11-02): `GET /repos/{r}/commits/{sha}/check-runs` returns ~81 check runs for a PR head SHA covering EVERY required context across all workflows (ci.yml, secret-scan, pr-quality-guards, cla*, tenant-integration, vendor-pin, sentry-destroy) with `started_at`/`completed_at`/`conclusion` — one API call per sampled run head covers the whole required set; `queued_at` is null in practice. Post-#11648+#11647 reality: PR run 41404512976 `test` latency ≈ 38.8 min (created 07:09:57 → completed 07:48:46), merge_group run 41408788451 `test` ≈ 38.4 min — so bounds seeded at the epic target would fire immediately; seed from measured baseline instead. `required-checks.txt` non-comment rows are the authoritative required-set population (CODEOWNERS-gated; keep the ratchet population derived from it).

**Digest integration facts**: `operator-digest` runs in private repo `jikig-ai/operator-digest` (ADR-057), reads 5 sources under L1 path scope + an allowlisted tool set that already includes `Bash(gh issue list:*)` — a sixth source read via `gh issue list` needs no allowlist change; the installed workflow's prompt text ("five sources") does need editing + the provision script re-run post-merge. `digest-scrub.sh` aborts on email/UUID/IPv4/secret shapes — an aggregate CI table has none. The digest is operator-register prose: §6 renders consequence language, not a raw table.

**Institutional learnings applied**: 2026-10-04 (untracked members invisible — derive population from required-checks.txt); 2026-08-04 (name-keyed population, never counts); 2026-10-18 (pin scan population + own registrations); 2026-10-14 (budget-censored measurement reports lower bound); 2026-10-29 cohort model (time-to-green = queue + runner + execution; use run.created_at → check.completed_at); deploy-script-tests-legs convention (queue term lands before started_at); 2026-09-17 watcher lifecycle (watch owns its tracker: find-or-file by title+bot author, sentinel-hash dedupe of flagged-set identity). Suite registration contract: new `.test.sh` needs a `run_suite` line (test-all.sh), a `suite-durations.tsv` floor row, and a `suite-shard-legs.tsv` leg row.

**External research**: skipped — established in-repo precedent covers the entire shape; GitHub check-runs API verified live above.

## Problem Statement / Motivation

Epic #11556's goal — required-check wall-clock p90 ≤ 20 min on PR runs, ≤ 15 min in merge queue, held for 14 consecutive days — has no instrument: the only wall-clock data today is one-off jobs-API readings recorded in the sharding runbook, and the only standing CI watch (`watch-shard-balance-11564.sh`) deliberately ratchets per-suite time bounds, not wall-clock. Lever E item 1 (#11774) is the recurring measurement + regression ratchet. Post-#11648+#11647 the `test` context sits near ~38–39 min, so the operator currently learns drift only when someone re-runs a hand query.

## Proposed Solution

One new weekly watch, mirroring the shipped `shard-balance-watch` shape exactly:

1. **`scripts/watch-wallclock-p90-11774.sh`** — weekly probe.
   - Population: every non-comment line of `scripts/required-checks.txt` (derived, never enumerated).
   - Sample: last `SAMPLE` (default 30) *completed, conclusion=success* `ci.yml` runs per surface — `pull_request` and `merge_group`. Success-only keeps the p50/p90 an honest green-path figure (fast failures would skew it low).
   - Per run: `gh api repos/{r}/commits/{head_sha}/check-runs` once; keep check runs whose `name` ∈ the required set; per check record `duration_s = completed_at − started_at` and `latency_s = completed_at − run.created_at` (queue + runner wait + execution — the number the PR/queue entry experiences; the runbook's cohort model). Skipped/failed/missing-timestamp check runs are excluded and counted per context as `n`.
   - Aggregate: p50/p90 of `latency_s` per (check, surface); `duration_s` p90 carried as a secondary diagnostic column.
   - Bounds: committed `scripts/required-check-wallclock-bounds.tsv` — `check_name TAB pr_bound_s TAB mq_bound_s TAB margin_frac` seeded from the measured baseline taken during implementation (NOT the epic target — see decision-challenges: bound=baseline vs bound=epic-target). Breach = p90 > bound × (1 + margin); margin default 0.30 (LEG_DRIFT_RATIO precedent). A required context with no bound row is itself a finding — same class as drift — so adding a required check forces a bound row in the same change (the untracked-member class).
   - Report: watch-owned standing tracker issue `ci-wallclock-p90: required-check wall-clock report` (find-or-file by title + bot author, sibling convention). The body is rewritten in place each week with the full table (check × surface p50/p90, n, bound, epic-goal columns) — it is the standing report home, NOT closed on all-clear (differs from shard-balance-watch, whose tracker closes; document that divergence in the header).
   - Drift comments: only on flagged-set identity change — sentinel `<!-- wallclock-p90-watch:v1 drift=<sha1> -->` over (check, surface) pairs, sibling semantics.
   - Exit: `0` ok / missing-data (zero qualifying samples → report section says so, never a ratchet failure — issue requirement); `1` bound breach or unbound required context (workflow goes red; comment names offenders); `3` cannot-establish (gh API failure — distinct from *missing data*: the probe itself is broken, which must not read as green); `2` usage; `78` xtrace refusal.
   - `--dry-run` and `--print-report` modes + `WATCH_*` fixture seams, same as the sibling.

2. **`.github/workflows/wallclock-p90-watch.yml`** — clone of `shard-balance-watch.yml`: weekly cron staggered from existing watches, `workflow_dispatch` `dry_run`, default-branch-only guard, `actions: read` + `contents: read` + `issues: write`, `concurrency.group`, `timeout-minutes: 15`, self-disable comment block + retirement notes.

3. **`plugins/soleur/skills/operator-digest/SKILL.md`** — new source/section §6 "Your checks pipeline": read the standing tracker body via `gh issue list` (already in the `--allowedTools` list), render plain-language aggregate only (ADR-057/L3: "about normal / slower than usual; the slowest check is X at ~N min"), never per-PR/per-run rows or actor attribution. Update the L1 "five named sources" list, the "five sections" wording, and the fallback-line list (§6 → "No pipeline timing data this week.").

4. **`plugins/soleur/skills/operator-digest/assets/operator-digest.workflow.yml`** — prompt text "five sources"/"five plain-language sections" → six. Allowlist unchanged. Post-merge: re-run `provision-operator-digest-repo.sh` to reinstall the workflow into the private repo (script exists, idempotent).

5. **`scripts/watch-wallclock-p90-11774.test.sh`** — mock-`gh` + fixture check-runs/bounds seams (sibling test shape); registered `run_suite` + `suite-durations.tsv` floor row + `suite-shard-legs.tsv` leg row.

6. **Runbook** — `ci-test-scripts-sharding.md`: watcher section + measured-history note pointing at the standing tracker.

## Non-Goals

- #11729's shard-balance-watch promotion/ratchet changes (post-advisory follow-ups live there).
- #11810 `.gitignore` verdict-input edges — needs its own scope decision.
- K=8→10 shard-count decision — separate technical fork.
- The pr-selection/affected-index work (#10448/#11776) — the real fix for selector time.
- Leg-level bounds, per-PR drill-ins, and any required-set *definition* changes (`required-checks.txt` is input, never edited here).
- Closing the `ci-wallclock-p90` tracker on all-clear (it is the standing report; see header divergence note).

## Technical Considerations

- **`latency_s` vs `duration_s`:** the epic's "wall-clock" is what a PR/queue entry experiences — `completed_at − run.created_at` includes queue + runner spread (the runbook cohort: queue binds ~25% of runs). `duration_s` (started→completed) is kept as a diagnostic column because it isolates execution. Anchor caveat for non-ci contexts: `run.created_at` is the ci.yml run's creation; sibling workflows (cla, secret-scan) trigger on the same push within seconds, so the shared anchor is honest. Recorded as `pending - assumed` in decision-challenges.md (no subagent harness to spawn `soleur:engineering:cto`).
- **Re-runs / same-sha suites:** the check-runs API returns latest-attempt runs per check suite on a sha, and one sha can carry check suites from several runs (push + pull_request + retry). Resolve the check run belonging to the sampled run by `check_suite` proximity to the sampled run's `created_at`/`completed_at` window (fixture-covered); drop unresolvable samples rather than attributing another run's check to this run.
- **Advisor consult (inline — no subagent harness):** riskiest phase is the sampling/aggregation; self-review surfaced the same-sha resolution above and confirmed (a) success-only sampling to keep p50/p90 honest, (b) exit 3 reserved for probe-health failures distinct from missing data, (c) `n` per row in the report so a shrinking sample is visible.
- **Skipped-but-required:** a required check that is `skipped`/`timed_out` contributes no sample and is counted — the report shows `n` per (check, surface) so a shrinking n is visible.
- **Censoring:** if a sampled run's `test` was cancelled by `timeout-minutes`, its check run is excluded (non-success sample), never counted as duration=cap (the censored-measurement class, learning 2026-10-14).
- **Privacy (ADR-057 + GDPR check, advisory, applied inline):** report + digest carry aggregate p50/p90/n per check — no per-PR rows, no actor fields; data processed is check names + durations (no personal data, no Art. 6 basis needed; nothing for compliance-posture.md). The public tracker body holds aggregate rows only, same contents class as the sibling watch's comments.
- **Self-disable / dead-man:** same residual as siblings — a silently dropped scheduled run has no dead-man alarm; visible via `gh run list --workflow wallclock-p90-watch.yml --event schedule`.

## User-Brand Impact

- **If this lands broken, the user experiences:** a red scheduled workflow and/or a wrong "checks are slow/healthy" line in their weekly private digest — a comprehension bug, not a product bug.
- **If this leaks, the user's [data / workflow / money] is exposed via:** nothing new — every artifact is aggregate CI timing on a public repo or stays in the private digest (ADR-057 boundary unchanged).
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** internal engineering observability; the only operator-facing artifact is a plain-language line in an already-private digest.
- `threshold: none, reason: touches .github/workflows/ (sensitive path) — a repo-scoped scheduled read/write of Actions data + one tracker issue; no user-facing surface.`

## Observability

```yaml
liveness_signal:
  what: weekly GitHub Actions run of wallclock-p90-watch.yml — success/failure + the standing tracker body's refresh timestamp
  cadence: weekly (cron) + on-demand workflow_dispatch
  alert_target: GitHub Actions failure notification + watch-owned tracker comment on drift
  configured_in: .github/workflows/wallclock-p90-watch.yml
error_reporting:
  destination: workflow run log (::error::/::warning:: annotations) + tracker issue comments
  fail_loud: exit 1 on bound breach/unbound required context (red run + named offenders); exit 3 on gh API failure
failure_modes:
  - mode: gh API outage / token scope loss
    detection: probe exits 3, run log ::error
    alert_route: red scheduled run (visible in gh run list + Actions notifications)
  - mode: required check added without a bound row
    detection: unbound-context finding (exit 1, named in tracker comment)
    alert_route: red scheduled run + tracker comment
  - mode: scheduled run silently dropped
    detection: no new run in `gh run list --workflow wallclock-p90-watch.yml --event schedule` (documented residual, shared with siblings)
    alert_route: manual inspection (same as shard-balance-watch)
logs:
  where: GitHub Actions run log (private to repo members)
  retention: GitHub's Actions log retention (90 days)
discoverability_test:
  command: grep -c "cron:" .github/workflows/wallclock-p90-watch.yml
  expected_output: "1"
```

## Encryption Posture

Skipped: no persistent store and no new cross-component connection — the probe reads the same GitHub REST API the sibling watches read over the job's `GITHUB_TOKEN`, and the only write surface is a tracker issue on the same repo (existing edge).

## Task Design

```yaml
tasks:
  - task: wallclock-p90-watch
    trigger: weekly cron (staggered from the sibling watches) + workflow_dispatch (dry_run input)
    services: reads GitHub Actions runs + commits/{sha}/check-runs (actions:read); reads committed scripts/required-checks.txt + bounds TSV; writes ONE watch-owned tracker issue body/comments (issues:write)
    next: nothing downstream; the operator-digest weekly run READS the tracker body the watch maintains (read-only consumer)
    human_reentry: workflow_dispatch with dry_run=true prints the would-be table/comments; deleting the workflow file retires the task (self-disable); editing the tracker body is overwritten next run
    dedupe: sentinel hash `<!-- wallclock-p90-watch:v1 drift=<sha1-of-flagged-set> -->` — a comment posts only when flagged-set MEMBERSHIP changes; the body rewrite is idempotent (same inputs → same table)
    source_dedupe: not a ticket source — one standing tracker, find-or-file by exact title + bot author
```

## Guard Contract

### Guard 1 — wallclock-p90 bound ratchet

**Property.** Every required check's p90 latency that exceeds its committed bound by more than the drift margin fails the watch loudly, naming each offending (check, surface) — and a required context with no committed bound is a violation, not an omission.

**Assembly.** The quantified set is (non-comment rows of `scripts/required-checks.txt` × {pull_request, merge_group}); the chokepoint is the probe's population derivation in `scripts/watch-wallclock-p90-11774.sh` — rows flow through the committed `scripts/required-check-wallclock-bounds.tsv` bound lookup before any verdict; there is no second path to a verdict.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Fixture p90 for one (check, surface) above bound × (1+margin) | RED — exit 1, comment names it |
| 2 | Empty bounds TSV (zero bound rows) | RED — never exits 0 reporting "0 checked" |
| 3 | Two breaching (check, surface) pairs | RED — both named in one flagged set |
| 4 | Bound row removed for a required context | RED — unbound-context finding |
| 5 | Fixture p90 above bound but within the margin band | PASS — margin is load-bearing, not a strict > |
| 6 | Check run missing started/completed timestamps | excluded from sample, n drops, no breach and no green credit |
| 7 | Sentinel drift= equal to the previous flagged set | no repost (dedupe), but body still rewrites |
| 8 | Zero qualifying samples in the window | exit 0 with a no-data report section — never a ratchet fail (issue-required semantics) |

### Guard 2 — required-set population derivation

**Property.** The measured+bound population is exactly the non-comment rows of `scripts/required-checks.txt` — a rename or addition changes the ratchet's reach without a code edit.

**Assembly.** `scripts/required-checks.txt` is the single chokepoint both the rulesets (out of scope) and the probe read; the probe's derivation function is the only place names enter the sample.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Add a line to a fixture required-checks.txt with no bound row | RED — unbound-context finding names it |
| 2 | Rename a required-checks.txt row to a name no check run carries | RED — zero-sample/unmeasured context reported, not silently dropped |
| 3 | Comment out a row in fixture required-checks.txt | Population shrinks by exactly that name — assertion on the derived set, not a count |
| 4 | Derivation returns empty while the fixture file has rows | RED — empty population can never reach a verdict |
| 5 | Fixture check-runs carry a non-required name | PASS — excluded; only required names are measured |

## Architecture Decision (ADR/C4)

### ADR

None required — this is an instance of an already-recorded architecture: repo-scoped scheduled Actions watches with watch-owned trackers (ADR-033 + the sibling watches) and the ADR-057 digest boundary it feeds. No ownership/tenancy move, no new substrate, no ADR reversal.

### C4 views

No C4 impact. Checked against `model.c4`/`views.c4`/`spec.c4`: (a) external human actors — none added (probe is repo-internal; digest consumer already modeled via `founder`/github delivery edges); (b) external systems — `github` is already the external system element and a scheduled workflow reading its own repo's Actions API + writing its own issues is github-internal (LikeC4 rejects self-relations; the #8359/ADR-232 comment block in `views.c4` documents this precedent); (c) containers/data-stores — none created (no persistent store; the tracker issue is an existing GitHub surface); (d) relationships — none changed. Every other standing watch (shard-balance-watch et al.) is likewise unmodeled.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Add required-check wall-clock **p50/p90 per job** to the weekly operator digest" | FR-1 probe + FR-3 digest §6 | mapped |
| 2 | "with a regression ratchet: when a job's p90 exceeds its committed bound by more than the drift margin, the digest names it and the ratchet fails loudly" | FR-2 bounds TSV + breach exit/comment | mapped |
| 3 | "Source data: required-check job timings are already measurable from workflow run/job records" | check-runs-per-head-sha sampling | mapped |
| 4 | "the `deploy-script-tests-legs-8736.sh` followthrough pattern (weekly probe + NOT YET semantics) is the closest existing shape" | probe modes + exit-code semantics | mapped |
| 5 | "Privacy boundary (ADR-057): the digest may carry aggregate p50/p90 statistics only" | §6 aggregate-only render + P3 | mapped |
| 6 | "missing data → report, never fail" | exit-0 no-data arm | mapped |
| 7 | "a bound exceeded → fail with the offending job named" | exit 1 + named offenders | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `scripts/watch-wallclock-p90-11774.sh` | asks 1,2,3,4,6,7 | asked |
| `scripts/required-check-wallclock-bounds.tsv` | "committed bound by more than the drift margin" | asked |
| `.github/workflows/wallclock-p90-watch.yml` | "weekly" (in "the weekly operator digest" + "weekly probe") | asked |
| `plugins/soleur/skills/operator-digest/SKILL.md` §6 | "in the weekly operator digest" | asked |
| `assets/operator-digest.workflow.yml` | "in the weekly operator digest" | inferred — justification: the installed prompt says "five sources"; the new source cannot render without it |
| `scripts/watch-wallclock-p90-11774.test.sh` + registrations | — | inferred — justification: repo ratchets (lint-orphan-test-suites, fast-tier budget) fail on an unregistered/unpriced test file |
| `ci-test-scripts-sharding.md` runbook | — | inferred — justification: sibling-watch convention; retirement notes keep the watcher list accurate |

### Split Assessment

- Subsystems touched: 4 — `scripts/`, `.github/workflows/`, `plugins/soleur/skills/operator-digest/`, `knowledge-base/engineering/operations/runbooks/`
- Planned files: 10 (4 create + 6 edit) | Estimated changed lines: ~780
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — boundary is at exactly 4 roots but the digest/workflow/runbook edits are small and cohesive with the probe; splitting strands the ratchet without its digest delivery.

## Open Code-Review Overlap

1 open scope-out mentions a planned file: #7942 (`scripts/test-all.sh` — `.mutation.sh` vs `*-mutation.test.sh` naming). **Acknowledge** — unrelated concern (battery naming convention), does not interact with adding a `run_suite` registration line.

## Files to Create

- `scripts/watch-wallclock-p90-11774.sh` — weekly probe (population, sampling, p50/p90, threshold, tracker, report body, sentinel dedupe, exit semantics, `--dry-run`/`--print-report`, `WATCH_*` seams)
- `scripts/watch-wallclock-p90-11774.test.sh` — mock-gh fixture suite
- `scripts/required-check-wallclock-bounds.tsv` — committed bound table (check × pr_bound × mq_bound × margin), seeded from implementation-time measurement
- `.github/workflows/wallclock-p90-watch.yml` — weekly workflow (clone of `shard-balance-watch.yml` shape)

## Files to Edit

- `scripts/test-all.sh` — `run_suite "scripts/watch-wallclock-p90-11774" bash scripts/watch-wallclock-p90-11774.test.sh`
- `scripts/suite-durations.tsv` — floor row `scripts/watch-wallclock-p90-11774`
- `scripts/suite-shard-legs.tsv` — leg row for the new suite
- `plugins/soleur/skills/operator-digest/SKILL.md` — §6 source, L1 list, "five"→"six", fallback list
- `plugins/soleur/skills/operator-digest/assets/operator-digest.workflow.yml` — prompt "five sources"→"six sources" (no allowlist change)
- `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md` — watcher section + measured history

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `scripts/watch-wallclock-p90-11774.sh --dry-run` prints per-(check, surface) p50/p90 latency + duration rows over `scripts/required-checks.txt`-derived population and posts nothing
- [ ] Bound breach exits 1 and the composed comment names every offending (check, surface); zero qualifying samples exits 0 with a no-data report; gh API failure exits 3
- [ ] Bounds live in `scripts/required-check-wallclock-bounds.tsv`; a required context without a bound row is a finding
- [ ] `operator-digest` SKILL.md documents §6 with aggregate-only rendering and the L1 source list covers the tracker read; workflow asset prompt updated
- [ ] `bash scripts/watch-wallclock-p90-11774.test.sh` passes, registered in `scripts/test-all.sh`, with `suite-durations.tsv` + `suite-shard-legs.tsv` rows
- [ ] `.github/workflows/wallclock-p90-watch.yml` is default-branch-guarded, least-privilege, and supports `dry_run` dispatch
- [ ] Aggregate-only invariant: no per-PR or per-actor field anywhere in report/digest (ADR-057)
- [ ] Runbook documents the watch, its retirement set, and the bound-seeding method
- [ ] Malformed bounds TSV row (unparseable number / wrong column count) → cannot-establish, never a silent skip of that row
- [ ] Tracker find-or-file + sentinel dedupe proven in-suite: second identical flagged set → no repost, body still rewritten; duplicate same-title trackers → ::warning:: + lowest number wins; tracker never auto-closed

### Post-merge (operator)

- [ ] `gh workflow run wallclock-p90-watch.yml -f dry_run=true` prints the real measured table (workflow must exist on main first — pre-merge dispatch is impossible per GitHub)
- [ ] Re-run `plugins/soleur/skills/operator-digest/scripts/provision-operator-digest-repo.sh` on an operator-authenticated machine to reinstall `operator-digest.yml` with the six-source prompt. Automation: not feasible in-session — the script reads `ANTHROPIC_API_KEY` from Doppler soleur/prd and needs org-owner `gh` scope on the operator's machine
- [ ] First scheduled/dispatched real run files the standing tracker `ci-wallclock-p90: required-check wall-clock report` with the measured table as its body

## Domain Review

**Domains relevant:** Engineering, Product

### Engineering

**Status:** reviewed
**Assessment:** Repo-scoped observability watch matching the established ADR-033 pattern; all machinery (probe script, bounds, workflow, registrations) lives under `scripts/` + `.github/workflows/` — the engineering domain's own surface. CTO-rulable technical forks (wall-clock anchor, bound-seeding policy, report home) are recorded in `decision-challenges.md`.

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none
**Skipped specialists:** none — `soleur:product:design:ux-design-lead` N/A (no UI surface; register change only)
**Pencil available:** N/A (no UI surface)

#### Findings

The only operator-facing change is a new plain-language section in the private weekly digest (existing surface, no new interactive elements). The digest register contract already governs tone/aggregation, and ADR-057's L3 aggregate-only rule is the design constraint. No spec-flow/wireframe/copywriter need at advisory tier.

## Test Scenarios

- `unit`: fixture check-runs where p90 crosses bound×1.3 for `test`/PR → exit 1 + flagged set
- `unit`: fixture with empty bounds → RED on zero bound rows
- `unit`: fixture check run with null timestamps → excluded, n=0 reported, exit 0
- `unit`: sentinel dedupe — second identical flagged set → no comment, body rewritten
- `unit`: required-checks.txt fixture +1 row, no bound → unbound finding
- `unit`: non-required check name in fixtures → ignored
- `integration`: `gh workflow run wallclock-p90-watch.yml -f dry_run=true` on the merged branch prints the real table (operator verify, one dispatch)

## Context

Watch sibling to mirror: `scripts/watch-shard-balance-11564.sh` + `.github/workflows/shard-balance-watch.yml` (sentinel/dedupe/tracker/find-or-file). Probe-exit convention: `scripts/followthroughs/deploy-script-tests-legs-8736.sh` (0/1/2/3/78 — note this watch drops exit 2 entirely: missing data is a report, not NOT YET). Digest boundary: ADR-057 + `plugins/soleur/skills/operator-digest/SKILL.md` (L1-L3). Cohort model: `ci-test-scripts-sharding.md` "Runner-availability data".

Post-merge bootstrap: re-run `plugins/soleur/skills/operator-digest/scripts/provision-operator-digest-repo.sh` on an operator-authenticated machine to reinstall `operator-digest.yml` (carries the six-source prompt). The standalone watch works without it; only the digest section waits on that step.

## References

- Issue: #11774; epic: #11556 (Lever E item 1); precedent: #11564 / #11729
- `scripts/watch-shard-balance-11564.sh`, `.github/workflows/shard-balance-watch.yml`
- `scripts/followthroughs/deploy-script-tests-legs-8736.sh`
- `scripts/required-checks.txt`, `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md`
- ADR-057 (digest two-repo privacy boundary), ADR-033 (repo-scoped Actions)
- Learnings: 2026-10-04, 2026-08-04, 2026-10-18, 2026-10-14, 2026-10-29 (see Research Insights)

## Enhancement Summary

Deepen-pass (run inline; sequential-fallback — no subagent harness, Reviewed-Coverage: sequential-fallback).

- **Scheduled-work precedent check (Phase 4.4):** Inngest cron functions exist, but GH Actions is correct here under ADR-033's repo-scoped exception — the probe holds only `github.token` (`actions:read`, `contents:read`, `issues:write`), reads GitHub APIs, and writes a same-repo tracker; no app context, secrets, or Sentry, and no `step.run` memoization to gain. Matches all three sibling watches; the digest's own cron lives in the private repo per ADR-057.
- **Verify-the-negative pass:** every negative claim greps clean — "no per-PR/per-actor" (report rows are aggregates by construction), "never auto-closed" (explicit non-close arm unlike sibling), "agent cannot post" (allowlist unchanged — `gh issue list` only), "no committed report file" (tracker body is the artifact). No contradictions found.
- **Halt gates verified:** `## User-Brand Impact` present with `threshold: none` + sensitive-path scope-out (4.6); `## Observability` complete, probe verb allowlisted, literal expected output, 15 s-capable (4.7); no PAT-shaped vars (4.8); no UI surface (4.9 N/A); `## Encryption Posture` validly skipped — no new store or connection (4.10); `lint-guard-contract.py` PASSES — 2 guard entries (4.11); `## Scope Check` — all 7 asks mapped, no BLOCKED (4.12); `## Task Design` emitted for the new workflow (4.13); `technical-ruling-gate.sh --branch` PASS — 5 ruled rows. Network-outage (4.5) and Downtime (4.55) gates don't trigger; GDPR applied inline (no personal data).
- **Post-edit self-audit:** no dropped symbols; all file/symbol references verified against the tree during planning (check-runs API verified live; `grep -c "cron:"` = 1 on sibling).
