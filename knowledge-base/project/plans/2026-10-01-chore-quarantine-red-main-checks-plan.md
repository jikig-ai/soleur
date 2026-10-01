---
title: "chore(ci): quarantine checks red on main and fix timing-flaky tests"
type: chore
date: 2026-10-01
slug: chore-quarantine-red-main-checks
branch: feat-one-shot-9402-quarantine-red-main
issue: 9402
closes: [9402]
priority: p2-medium
domain: engineering
lane: cross-domain
brand_survival_threshold: none
---

# chore(ci): quarantine checks red on main and fix timing-flaky tests

## Enhancement Summary

**Deepened on:** 2026-10-01
**Reviewed-Coverage: sequential-fallback** — deepen-plan ran inside a Task
subagent with no spawn capability, so the per-section research, learnings
filter, sharp-edges pass, and halt gates ran sequentially inline rather than
as a parallel agent fan-out. No independent review seat ran; treat sections
as single-author until a parallel review pass re-covers them.
**Sections enhanced:** Proposed Solution (A, B, C), Sharp Edges, References.

### Key Improvements

1. **`ship/SKILL.md` byte ceiling measured** (273,665/274,000 — 335 B
   headroom): the probe-disposition detail moved to a new
   `skills/ship/references/red-on-main-quarantine.md` with a ≤ 300-byte
   pointer, instead of a prose block that could not land.
2. **Probe join key verified live:** `deploy-script-tests (1/4)` carries the
   exact same name in `actions/runs/<id>/jobs` on main run 36905670146 (red)
   as in `gh pr checks`; skipped/absent jobs classified `no-evidence`, never
   quarantined.
3. **gh-stub fidelity rule applied** (learning
   `2026-09-25-gh-stub-must-mirror-real-cli-flags`): the new suite's stub
   whitelists only real `gh` flags — invented flags are a miss, not an
   answer.
4. **#8735 verified shipped**: `notify-main-failure` already reads the
   `deploy-script-tests-done` aggregator with `!= 'success'` (covers
   cancelled) — overlap disposition hardened from hedge to verified fact.

### New Considerations Discovered

- Ambient-CI-variable learning (#9323): the ceiling fix uses a FILE-read bump
  specifically because env-value reads inherit into nested runners; the bump
  env var carries only a path.
- The monitor's own `soleur:main-health-monitor` sentinel cannot be reused
  for quarantine trackers — its closer retires only its own sentinel, so a
  new `soleur:red-on-main` sentinel keeps ownership disjoint (#7374 lesson).

## Overview

Reduce per-PR CI cost when a check is already failing on main: detect the
"red on main too" condition mechanically, report it as a tracked issue instead
of paying rerun cycles, fix the one-second-tick flake in
`scripts/test-all-runtime-ceiling.test.sh`, and make shard-manifest
regeneration additive against the committed base table (existing rows pinned,
only newly-registered suites assigned) instead of rebalancing unrelated suites.

## Problem Statement / Motivation

PR #9339 (disk-leak fix, merged 2026-10-01) paid an 11-seat review, several fix
rounds and ~8 CI cycles for a small change. Three of those cycles were reruns
of `Infra Validation / deploy-script-tests (1/4)`, which was red on main and on
unrelated branches (`apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh`
hitting its 600 s per-suite bound in `run-registered-suites.sh`'s
`_SUITE_BOUNDS` map with no output — a stuck docker run). Separately,
`scripts/test-all-runtime-ceiling.test.sh` breaks when a one-second
`EPOCHSECONDS` tick lands between `_RUN_START_EPOCH` capture and the first
suite entry, and regenerating `scripts/suite-shard-legs.tsv` rebalanced 10
unrelated suites in the same diff.

The deeper defect is the loop shape: nothing in the pipeline can say "this
check is red on main too — do not rerun, do not fix-attempt, file it." `ship`
Phase 7 (the required-check-failure exit block and the flaky/unrelated arm)
treats every red check as this PR's problem: headless aborts, interactive
asks, and the only sanctioned rerun is a third-party-fetch failure.
`wg-when-tests-fail-and-are-confirmed-pre` demands a tracking issue for
pre-existing failures, but "confirmed pre-existing" is today an agent judgment
call with no mechanical probe.

Measured cost (Phase 0.6c): 17 workflow runs on PR #9339's final head SHA
(`gh api repos/jikig-ai/soleur/actions/runs?head_sha=<sha> --jq .total_count`),
29 commits. Live evidence the trigger is real and windowed: main's
infra-validation runs 36905670146 (18:17) and 36885018496 (15:32) on
2026-10-01 both concluded `failure` with `deploy-script-tests (1/4)` red, and
run 36927933411 (21:19) is green again — a point-in-time probe, not a
committed registry, is therefore the right shape.

## Research Insights

### Premise Validation (plan Phase 0.6)

- Issue #9402 OPEN, not closed by any PR (verified via `gh issue view 9402`).
- PR #9339 MERGED 2026-10-01 (verified).
- Cited files exist on origin/main: `scripts/test-all-runtime-ceiling.test.sh`,
  `scripts/suite-shard-legs.tsv`, `scripts/suite-shard-legs-heavy.tsv`,
  `apps/web-platform/infra/suite-shard-legs.tsv`. The rehearsal suite lives at
  `apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh` (the issue
  omits the path); it is the *symptom*, not a workstream — main's infra runs
  are green again at time of writing.
- ADR corpus check (mechanism keywords, not issue refs): ADR-240 (sticky-LPT
  shard assignment — the mechanism workstream C amends), ADR-252 (infra suite
  registration is filesystem presence; deploy-script-tests is a matrix),
  ADR-032 (required checks are IaC), ADR-235 (generated-artifact conflict
  lessons — argues FOR minimal regen diffs). No ADR rejects a red-on-main
  probe; ADR-072 (adaptive CI wait) is the closest neighbor and concerns
  deploy gating, not rerun decisions.
- Proposed mechanism vs. existing authority
  (`hr-verify-repo-capability-claim-before-assert`):
  `plugins/soleur/scripts/admin-merge-ready.sh` already reads
  `commits/<sha>/check-runs` and matches by name+app — it answers merge
  readiness, never main-vs-PR attribution. `main-health-monitor.yml` detects
  suite-level red on main every 6 h and files `ci/main-broken` issues — it
  re-runs the suites itself, does not read workflow-level check verdicts, and
  its cadence is too coarse for a per-PR decision. `notify-main-failure` in
  `infra-validation.yml` emails ops on push-main failure — reporting only, no
  PR-side consumption. The gap is real.

### Property List (plan Phase 0.6b)

- P1 — A PR never pays a rerun or autonomous-fix cycle for a check whose same
  context is already red on the latest main-branch run of its workflow that
  exercised it; the condition is reported as a tracked issue instead.
- P2 — `test-all-runtime-ceiling.test.sh` produces the same verdict on every
  run regardless of where the one-second `EPOCHSECONDS` boundary lands
  ("passes under an injected tick").
- P3 — Routine shard regeneration (suite added/removed) produces a manifest
  diff confined to the added/removed rows; incumbent assignments are pinned
  verbatim unless a full rebalance is explicitly requested.

### Cut List (plan Phase 0.6b)

- Committed quarantine registry file (e.g. `ci-quarantine.tsv`) → serves P1 →
  CUT: live derivation from the latest exercising main run covers the
  property with no drift surface, no unquarantine bookkeeping, and no new
  committed artifact to conflict on merge (ADR-235; the 2026-09-19
  generated-artifact learning).
- Neutralizing the check conclusion in-workflow when quarantined → serves P1
  → CUT: a check reporting green while its main twin is red destroys the
  signal the check exists to provide; the rerun decision lives in
  ship/monitor, not in the workflow.
- New scheduled workflow to maintain quarantine state → serves P1 → CUT: the
  probe runs at decision time inside existing loops; no scheduling substrate
  is needed (`main-health-monitor` already covers 6-hourly suite-level
  detection).
- New generator script for incremental regen → serves P3 → CUT:
  `regenerate-shard-manifest.py` already owns assignment; a flag on it reuses
  `read_incumbent`, `registered_labels` and the ⊆ lint contract for free.

### Repo findings (local research — inline; Task fan-out unavailable in this subagent context)

- `plugins/soleur/scripts/admin-merge-ready.sh` — the canonical "read
  check-runs for a sha, match by name AND app.id, max-id wins" implementation;
  its suite `admin-merge-ready.test.sh` is the gh-PATH-stub convention the new
  probe's suite follows (canned JSON per endpoint, STUB-MISS on unexpected
  argv, rc-3 on missing tool).
- `plugins/soleur/scripts/monitor-pr-checks.sh` — the poll loop whose
  `bucket=="fail"` output is where agents see a red check; terminal-fail
  annotation is the cheapest place to put the verdict in front of the rerun
  decision.
- `plugins/soleur/skills/ship/SKILL.md` — Phase 7 red-check handling: the
  `gh run rerun --failed` network-fetch exception, the `fix_attempt_count`
  autonomous-fix arm, and the "flaky or unrelated check → abort (headless) /
  ask (interactive)" arm. The CI auto-fix logic sits OUTSIDE the
  `phase-7-poll-block` markers, so no mirror update in `merge-pr/SKILL.md`
  §5.2 is required — the mirrored poll block itself must not gain this logic
  inline.
- `scripts/test-all-runtime-ceiling.test.sh` — flake locus:
  `run_arm two|three none 1` uses ceiling=1 s with a `slow.sh` `sleep 2`
  fixture. If the second boundary ticks between `_RUN_START_EPOCH` capture in
  `scripts/test-all.sh` and the first `run_suite` entry, the FIRST suite is
  declined too: `declined_suites=2` becomes 3 and `=== 1/2 suites passed ===`
  becomes 0/2. The sandbox builder (`build_sandbox`, python `sub_once`
  splice) is the existing injection mechanism — the fix splices the
  `_elapsed_s` computation to add a file-read bump rather than adding a test
  seam to production `test-all.sh`.
- `scripts/regenerate-shard-manifest.py` — `assign()` is sticky-LPT
  (5 %-of-mean-leg epsilon): a label keeps its incumbent leg only while that
  leg is within epsilon of least-loaded, so a median-drift wave still moves
  rows — the 10-suite rebalance the issue reports. `read_incumbent()` already
  parses the committed manifest; `registered_labels()` derives the registered
  set via the runner's own `--enumerate`.
- Registration: `plugins/soleur/test/*.test.sh` and
  `apps/web-platform/infra/**/*.test.sh` register by filesystem presence
  (test-all.sh enumerate glob; ADR-252). A new probe suite needs no list
  edit; it lands on a shard leg via hash fallback until a regen.
- Required vs advisory: `deploy-script-tests` is advisory (absent from
  `infra/github/ruleset-ci-required.tf`); a red-on-main REQUIRED check cannot
  be merged past regardless — quarantine there means "report + escalate, do
  not rerun/fix-attempt," never "merge anyway."
- Live API verification (CLI-verification gate): the join key works —
  `gh api repos/jikig-ai/soleur/actions/workflows/infra-validation.yml/runs?branch=main&status=completed`
  then `actions/runs/<id>/jobs` returns job names carrying the matrix suffix
  (`deploy-script-tests (1/4)`, conclusion `failure` on run 36905670146),
  identical to the `gh pr checks` name field. Verified 2026-10-01.

### Community scan (Phase 1.5b substitute — discovery agent unavailable in subagent context)

Web research surfaces Trunk-style flake quarantine, `mycargus/quarantine`
(git-branch state + per-test JUnit classification), and label-gated quarantine
manifests. All target test-level quarantine inside a workflow run with a
committed or branch-held registry — heavier machinery than P1 needs, and none
integrates with this repo's ship/monitor decision points. Skipped: the
live-derivation probe covers the property with zero new state.

## Open Code-Review Overlap

- #8659 (test-helpers EXIT-trap leak across 33 suites): adjacent to
  `scripts/test-all.sh` — disposition **acknowledge**; different concern
  (trap composition vs. the `_elapsed_s` splice anchor). If that work drifts
  the anchor line, `sub_once` fails loudly by design.
- #7942 (two `*.mutation.sh` batteries run in no gate): disposition
  **acknowledge** — unrelated surface; no real file overlap.
- #8735 (notify-main-failure misses cancelled jobs, OPEN): disposition
  **acknowledge** — verified: the aggregator fix already landed in
  `infra-validation.yml`; `notify-main-failure` fires on
  `needs.deploy-script-tests-done.result != 'success'` under an inline
  comment that cites #8735 itself, covering the cancelled-leg case the issue
  describes. The issue's residual is a tracker-state question (open despite
  shipped fix), not a code gap this plan should absorb — the probe's
  `--report` path is independent of the ops-email channel either way.
- #8881 (K=6→7 rebalance review bucket): disposition **acknowledge** —
  evidence record, not a code surface.
- #6480 (promote `infra-validate-required` into the required set): not a
  code-review issue but the canonical alternative to workstream A — see
  Alternative Approaches.

## Proposed Solution

### A. Red-on-main probe + pipeline wiring (P1)

New `plugins/soleur/scripts/check-red-on-main.sh`:

```text
check-red-on-main.sh "<check-name>" --run-id <failing-run-id> [--report] [--repo owner/repo]
```

- Resolves the failing check's workflow via
  `gh api repos/{o}/{r}/actions/runs/<run-id>` → `.workflow_id` (the `link`
  field from `gh pr checks` already carries `actions/runs/<run-id>`).
- Lists up to 5 completed main-branch runs of that workflow
  (`actions/workflows/<workflow_id>/runs?branch=main&status=completed`),
  newest first.
- In each run, looks for the job named exactly `<check-name>` (matrix
  suffixes like `(1/4)` are part of the name — verified live above). Skipped
  and absent jobs are NOT evidence: a path-filtered main push that never ran
  the job says nothing, so the scan continues to older runs in the window.
- Verdict on the FIRST run where the job reached a real conclusion:
  - `red-on-main` — conclusion ∈ {failure, timed_out, cancelled}
  - `green-on-main` — conclusion ∈ {success, neutral}
  - `no-evidence` — no run in the window exercised that job → NOT quarantined
- Exit codes: 0 green, 1 red-on-main, 2 no-evidence, 3 gh/API error. Errors
  never quarantine — an unproven claim is worse than a rerun.
- Emits exactly one stdout marker:
  `SOLEUR_RED_ON_MAIN verdict=<v> check="<name>" main_run=<id> main_conclusion=<c>`
  plus a `--self-test` mode that exercises the pure classifier over fixture
  JSON with zero network (feeds the Observability discoverability probe).
- `--report`: on `red-on-main`, dedupe open `ci/main-broken` issues by a
  per-check sentinel `<!-- soleur:red-on-main check="<name>" -->` (oldest
  first, mirroring main-health-monitor's convention — a list failure warns
  and does NOT file, never a duplicate on a transient error), pre-create the
  label via `gh label create --force 2>/dev/null || true`, file with
  `--milestone "Post-MVP / Later"` + labels `ci/main-broken`,
  `meta/machinery`, `type/chore`. On `green-on-main`, comment-and-close only
  issues carrying OUR sentinel for that name — never a human-filed or
  monitor-sentinel tracker (the #7374 out-of-scope-green lesson is what the
  sentinel rule encodes).

Wiring (prose edits, no workflow changes):

- `plugins/soleur/skills/ship/SKILL.md`, Phase 7 red-check arm: before the
  fix-attempt ladder AND before the network-fetch rerun exception, run the
  probe per failing check. Disposition: advisory + red-on-main → report +
  continue (the check does not gate merge); required + red-on-main → report +
  escalate immediately ("main is broken, tracked as #N" — no rerun, no
  test-fix-loop, no merge attempt); green / no-evidence / error → unchanged
  behavior. This arm sits OUTSIDE the `phase-7-poll-block` markers;
  merge-pr's mirror needs no edit.
- **Byte-ceiling constraint (measured at plan time):** `ship/SKILL.md` is a
  lifecycle skill pinned at 274,000 bytes by
  `plugins/soleur/test/skill-body-budget.json` (enforced by
  `scripts/lint-skill-body-budget.py --base origin/main` — the ceiling reads
  from the merge base, so it cannot be raised in the same diff) and currently
  sits at 273,665 bytes — **335 B of headroom**. The disposition detail
  therefore goes in a new reference file
  `plugins/soleur/skills/ship/references/red-on-main-quarantine.md` (the
  budget binds SKILL.md bodies only) with a ≤ 300-byte pointer line in the
  Phase 7 arm. If the pointer itself overflows, compress adjacent prose — do
  NOT raise the ceiling.
- `plugins/soleur/scripts/monitor-pr-checks.sh`: on the terminal-fail exit
  path only (never per-tick — the gh budget is per-failing-check), annotate
  up to 10 failing check names with their verdict so the reading agent sees
  the red-on-main attribution inline instead of reaching for `gh run rerun`.
- `plugins/soleur/test/check-red-on-main.test.sh`: new suite (auto-registers
  via the `plugins/soleur/test/*.test.sh` enumerate glob), gh PATH-stubbed in
  the `admin-merge-ready.test.sh` shape — canned JSON per endpoint,
  STUB-MISS on unexpected argv, rows for: red-on-main, green-on-main, job
  skipped in newest run but failed in an older one (windowed evidence),
  no-evidence, gh-error → rc 3 + no quarantine, cancelled-classified-as-red,
  `--report` dedupe (existing sentinel → comment not create), `--report`
  closes its own sentinel on green, `--report` never touches a non-sentinel
  issue.
- **Stub fidelity constraint** (learning
  `2026-09-25-gh-stub-must-mirror-real-cli-flags`, PR #8919): the `gh` stub
  must WHITELIST only flags the real CLI accepts on each subcommand
  (`gh api`: `--jq`, `--paginate`, `-X`, `-f`, `-F`; `gh issue list`/`create`:
  `--label`, `--state`, `--milestone`, `--json`, `--jq`, `-L`) and exit 64 on
  anything else — an invented flag (e.g. `gh api --arg`, which the real CLI
  rejects per cli/cli#10263) must be a stub miss, not an answer. The probe
  itself must never prescribe `gh api --arg`; two-stage `gh api URL | jq
  --arg` is the canonical form.

### B. Deterministic ceiling trip (P2)

`scripts/test-all-runtime-ceiling.test.sh` only — no production
`test-all.sh` edit. `build_sandbox` gains a splice rule rewriting the
sandbox copy's
`_elapsed_s=$(( "${EPOCHSECONDS:-0}" - _RUN_START_EPOCH ))`
line (anchor asserted exactly-once by `sub_once`) to add a file-read bump:

```bash
_elapsed_s=$(( "${EPOCHSECONDS:-0}" - _RUN_START_EPOCH + $(cat "${SOLEUR_TC_BUMP_FILE:-/dev/null}" 2>/dev/null || echo 0) ))
```

A new fixture `bump.sh` (replacing `sleep`-driven `slow.sh` in the trip arms)
writes `120` to `${SOLEUR_TC_BUMP_FILE}` when invoked as a suite — a
deterministic injected tick between suite entries, propagated to the suite
child through the run's env. Trip arms move to ceiling=60: entry-1 elapsed is
a few seconds at most (startup jitter cannot reach 60), entry-2 elapsed ≥
120 → declined, rc 3, marker present. `declined_suites=2` and `=== 1/2 ===`
become exact again; no arm depends on where the second boundary lands.
Control arms (99999, `abc`, `07200`, CI-exempt) are untouched. The mutation
battery's M2 anchor (`(( _elapsed_s >= _CEILING_S ))`) still lands on the
spliced line.

Nested-runner caveat (learning
`2026-10-01-an-ambient-ci-variable-…-needs-a-scrub`, #9323): `run_arm`
already runs `env -u CI` so the nested runner cannot take the CI-exempt arm
by inheritance — the bump file is a *file* read (not an ambient variable
*value*), which is the shape that sidesteps that whole class; the env var
carries only a path. If `build_sandbox` copies `test-all.sh` for the new
fixture layout it must carry every lib the runner sources
(`repo-write-boundary.test.sh` is the existing detector for that miss).

### C. Incremental shard regeneration (P3)

`scripts/regenerate-shard-manifest.py` gains `--incremental`:

- Reads the incumbent manifest via existing `read_incumbent()` + the
  registered set via `registered_labels()`. No `gh` timing fetch — new labels
  get the floor weight (median of the committed `suite-durations*.tsv`
  measured rows, else `DEFAULT_SUITE_MS`), because there is no measurement
  yet for a suite that has never run.
- Output rows = {incumbent rows whose label is still registered, leg pinned
  verbatim} ∪ {registered labels absent from incumbent → least-loaded leg by
  incumbent leg loads}. Unregistered incumbent rows drop out — that IS the
  row the diff should show.
- Interactions: refuses `--incremental` combined with
  `--run/--runs/--timings-dir` (contradictory inputs); the `--legs` K≠N
  committed-write refusal still applies; empty incumbent → falls back to
  normal assignment with a WARN (first-ever manifest). The durations table is
  NOT rewritten in incremental mode (no new measurements exist); new labels
  land there on the next full `--write`.
- Full sticky-LPT rebalance stays as today's default (`--runs 5 --write`),
  deliberately opt-in churn; the runbook
  `ci-test-scripts-sharding.md` gains "incremental for add/remove; full
  regen when leg balance drifts."
- Test: `plugins/soleur/test/regenerate-shard-manifest.test.sh` gains arms —
  incumbent-pinned delta (add 1 suite → diff is exactly +1 row), drop
  unregistered row, new label lands on least-loaded leg, empty-incumbent
  fallback, contradictory-flag refusal.

## Technical Considerations

- Naming authority: the probe joins on the check-run/job NAME — GitHub's own
  join key between `gh pr checks` output and a run's `jobs[]`. A renamed job
  degrades old evidence to `no-evidence`, which fails toward normal handling
  (the safe direction).
- Windowing: 5 completed main runs bounds API cost and handles path-filtered
  workflows whose latest main run skipped the job. `cancelled` counts as red
  (matches `notify-main-failure`'s `!= 'success'` convention); supersession
  cancels on main are rare — cancel-in-progress is pull_request-only in these
  workflows.
- Masking risk (accepted): a check red on main could ALSO be freshly broken
  by the PR's diff. Quarantine suppresses only the rerun/fix loop — the
  tracking issue records it and the merge gate is unchanged (a required red
  check still blocks; an advisory one never did). A future refinement could
  diff failure signatures; out of scope.
- `gh` rate limiting: probe calls happen only at fail-decision time, and
  `--report`'s issue list is fail-open-with-warning, never file-on-error.
- `gh api` GET calls embed the query in the URL (never `-f`, which flips the
  request to POST and 404s the actions `.../runs` list endpoints — measured
  2026-09-29, PR #9233).
- IaC gate note: no new infrastructure, secrets, services, or scheduled jobs
  are introduced; the sole scheduler reference in this plan (the existing
  Inngest-driven `main-health-monitor` cadence) is read-only context.
- Sensitive-path note for preflight Check 6: if implementation regenerates
  `apps/web-platform/infra/suite-shard-legs.tsv` (`apps/*/infra/` matches the
  canonical regex) or touches `infra-validation.yml`, the User-Brand Impact
  scope-out bullet below already covers it.

## Implementation Phases

### Phase 1 — probe script + suite (P1)

- Write `plugins/soleur/test/check-red-on-main.test.sh` FIRST
  (`cq-write-failing-tests-before`) with the stubbed-`gh` battery enumerated
  above.
- Write `plugins/soleur/scripts/check-red-on-main.sh`: arg validation,
  workflow resolution, windowed job scan, verdict + marker, `--report`
  file/dedupe/close, `--self-test`.

### Phase 2 — ship/monitor wiring (P1 consumers)

- `plugins/soleur/skills/ship/SKILL.md` Phase 7 failure arm: probe consult +
  disposition table (outside the `phase-7-poll-block` markers).
- `plugins/soleur/scripts/monitor-pr-checks.sh`: terminal-fail annotation
  (≤10 checks, once per watch, warn-and-continue on probe error).

### Phase 3 — ceiling test determinism (P2)

- `build_sandbox` bump-file splice + `bump.sh` fixture; convert trip arms to
  ceiling=60; keep control/mutation arms; run the suite 5× locally to prove
  determinism where previously any 1 s boundary in startup could red it.

### Phase 4 — incremental regen + ADR amendment (P3)

- `--incremental` mode in `scripts/regenerate-shard-manifest.py`; test arms
  in `regenerate-shard-manifest.test.sh`; runbook update; ADR-240 amendment
  (below).

## Files to Edit

- `plugins/soleur/scripts/monitor-pr-checks.sh` — terminal-fail annotation.
- `plugins/soleur/skills/ship/SKILL.md` — Phase 7 red-check arm: consult the
  probe before rerun/fix/abort decisions.
- `plugins/soleur/test/regenerate-shard-manifest.test.sh` — incremental-mode arms.
- `scripts/regenerate-shard-manifest.py` — `--incremental` mode.
- `scripts/test-all-runtime-ceiling.test.sh` — bump-file splice + fixtures.
- `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md` —
  prescribe `--incremental` for add/remove regens.
- `knowledge-base/engineering/architecture/decisions/ADR-240-shard-assignment-is-checked-in-derived-data.md` —
  amend `## Decision` + `## Alternatives Considered` (see ADR section).

## Files to Create

- `plugins/soleur/scripts/check-red-on-main.sh`
- `plugins/soleur/test/check-red-on-main.test.sh`
- `plugins/soleur/skills/ship/references/red-on-main-quarantine.md` —
  the probe-disposition detail SKILL.md cannot carry (335 B headroom).

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing — the
  blast radius is the Soleur repo's own CI/pipeline. A misclassified
  `green-on-main` verdict wastes one rerun cycle; a misclassified
  `red-on-main` verdict suppresses a rerun of a check that is advisory
  anyway, or escalates a required check whose merge was already blocked.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no
  exposure — the probe reads public-repo check-run/job data with the ambient
  `gh` token and writes only GitHub issues on the repo itself; the `--report`
  body carries check names and run ids only, never log content.
- **Brand-survival threshold:** `none`
- `threshold: none, reason: CI-machinery change only — any sensitive-path hit
  (workflow YAML, apps/*/infra/ generated tables) carries no user data,
  credentials, or product runtime behavior.`

## Observability

```yaml
liveness_signal:
  what: "SOLEUR_RED_ON_MAIN verdict=… marker on every probe invocation; suite plugins/soleur/test/check-red-on-main runs in the test-scripts legs"
  cadence: "on-demand at ship/monitor fail-decision points; suite on every scripts CI leg"
  alert_target: "ship transcript; filed ci/main-broken issue when verdict=red-on-main under --report"
  configured_in: "plugins/soleur/scripts/check-red-on-main.sh; plugins/soleur/test/check-red-on-main.test.sh"
error_reporting:
  destination: "stderr + exit 3 (error) / exit 2 (no-evidence); never quarantines on unproven state"
  fail_loud: "SOLEUR_RED_ON_MAIN verdict=error reason=<api|name|parse> line"
failure_modes:
  - mode: "gh API unreachable or rate-limited at decision time"
    detection: "verdict=error marker + exit 3; ship treats as not-quarantined (existing behavior)"
    alert_route: "ship transcript + monitor-pr-checks terminal line"
  - mode: "quarantined check goes green on main but tracker stays open"
    detection: "--report closes sentinel-owned issues on a green verdict"
    alert_route: "issue comment + close"
  - mode: "job renamed so evidence goes absent"
    detection: "verdict=no-evidence exits 2 — visible in transcript, never silent-quarantined"
    alert_route: "ship transcript"
logs:
  where: "ship session transcript + monitor-pr-checks output; suite output under the test-scripts leg"
  retention: "GitHub run-log retention; transcript ephemeral"
discoverability_test:
  command: bash plugins/soleur/scripts/check-red-on-main.sh --self-test
  expected_output: SOLEUR_RED_ON_MAIN_SELFTEST ok
```

## Architecture Decision (ADR/C4)

- **ADR**
  - Amend `ADR-240-shard-assignment-is-checked-in-derived-data.md`: add
    `--incremental` as the routine regen mode (incumbent rows pinned, new
    labels to least-loaded leg, durations table untouched) alongside the
    existing full sticky-LPT rebalance, which remains the balance-correction
    path. Record "always full-rebalance on every add/remove" in
    `## Alternatives Considered` with the cost evidence from #9402 (10
    unrelated suites rebalanced; generated-artifact conflict surface per
    ADR-235).
  - No new ADR for the probe: it is a read-only classifier wired into
    existing skill prose, not a trust-boundary or substrate decision.
- **C4 views**
  - No C4 impact. Enumerated per the completeness mandate against all three
    model files (`model.c4`, `spec.c4`, `views.c4`): (a) external human
    actors — none added (the check is read by the same pipeline agents
    already modeled); (b) external systems — GitHub is already the `github`
    system ("Source control, CI/CD, issue tracking, and releases") and the
    probe's `gh api` reads are covered by the existing `engine -> github
    "Git operations and CI"` edge; (c) containers/data stores — none added
    (no persistent store; issues filed are the existing tracker surface);
    (d) actor↔surface relationships — unchanged.
- **Sequencing**
  - The ADR-240 amendment lands in the same PR as `--incremental`; it
    describes shipped behavior, not a target state.

## Guard Contract

### Guard 1 — red-on-main verdict classifier

**Property.** A failing PR check is declared `red-on-main` iff the newest
completed main-branch run of the same workflow that exercised a job of the
exact same name concluded it non-green; every other shape (green, skipped,
absent, API failure) must NOT quarantine.

**Assembly.** `plugins/soleur/scripts/check-red-on-main.sh` verdict
derivation — the single chokepoint all verdicts flow through (workflow
resolution → windowed run list → job-name match → conclusion read →
marker/exit code), plus `--report`'s sentinel-keyed issue file/close, the
only write path.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Classifier treats `skipped` job as evidence (quarantine on a path-filtered skip) | RED |
| 2 | Classifier returns red-on-main when the job is absent from the whole window | RED |
| 3 | Scan stops at the newest completed run without checking job presence (verdict from a run that never ran the job) | RED |
| 4 | `--report` files when `gh issue list` fails (duplicate-on-transient) | RED |
| 5 | `--report` closes an open tracker lacking the `soleur:red-on-main` sentinel for that check name | RED |
| 6 | Harness row: stub `gh` to return malformed JSON mid-window | RED (rc 3, no quarantine) |
| 7 | Harness row: must-PASS non-canonical input — cancelled (not failure) main conclusion | PASS (still quarantines; cancelled is red by convention) |

### Guard 2 — incremental regen row pinning

**Property.** `--incremental` output contains every still-registered
incumbent row byte-identical in leg, exactly the registered-but-untabled
labels as new rows, and zero rows for unregistered labels.

**Assembly.** `regenerate-shard-manifest.py`'s incremental branch — the
chokepoint is the row-set construction ({incumbent ∩ registered} ∪
{registered − incumbent → least-loaded}), exercised through
`regenerate-shard-manifest.test.sh` fixture manifests and registered-sets.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Incremental mode re-runs sticky-LPT on incumbents (rows move) | RED |
| 2 | Unregistered incumbent row is silently retained | RED |
| 3 | Two new labels both land on leg 1 regardless of load (second member after a compliant first) | RED |
| 4 | `--incremental --run <id>` accepted (contradictory inputs) | RED |
| 5 | Harness row: empty incumbent file → WARN + full-assignment fallback (guard's own degenerate input) | PASS |
| 6 | Harness row: incumbent carries a leg > n (out-of-range pin) | RED |

## Domain Review

**Domains relevant:** engineering

### Engineering

**Status:** reviewed (inline — Task fan-out unavailable in this planning
subagent; semantic assessment against `brainstorm-domain-config.md`)
**Assessment:** Pure CI/pipeline machinery. Architectural notes worth one
leader-equivalent pass, captured inline: the probe is a new cross-cutting
reader (check-name → main verdict) with fail-closed semantics (errors and
no-evidence never quarantine); the `--incremental` mode amends ADR-240's
balancing contract; the ceiling fix keeps the mutation battery's anchors
intact. No infrastructure provisioning, no secret handling, no new external
dependency (`gh` + `jq` only). Lane: `cross-domain` by fail-closed default —
no spec.md exists yet to carry a lane, and the description's "Infra" token
matches the cross-domain trigger scan anyway; the semantic set is
engineering-only.

Product/UX gate: NONE — no UI-surface file in `## Files to Create` or
`## Files to Edit` (the mechanical override does not fire).

## Acceptance Criteria

- [x] `plugins/soleur/scripts/check-red-on-main.sh` exists with the verdict
  contract above: exact-name job match over a 5-run completed-main window;
  exit 1 only on `red-on-main`; `skipped`/`absent`/API-error never
  quarantines; one `SOLEUR_RED_ON_MAIN` marker line per invocation;
  `--self-test` runs the classifier on fixtures with zero network.
- [x] A PR does not need a rerun for a check already red on main: ship
  Phase 7's red-check arm consults the probe before any `gh run rerun` or
  `test-fix-loop` dispatch; advisory + red-on-main → tracker filed
  (sentinel-deduped) + pipeline continues; required + red-on-main → tracker
  filed + escalation with no rerun and no autonomous fix attempt.
- [x] `monitor-pr-checks.sh` annotates failing check names with the probe
  verdict on its terminal-fail exit path (once per watch, warn-and-continue
  on probe failure).
- [x] `--report` on a `green-on-main` verdict closes only issues carrying the
  `soleur:red-on-main` sentinel for that exact check name; a list/lookup
  failure files nothing and closes nothing.
- [x] The ceiling test passes under an injected tick:
  `test-all-runtime-ceiling.test.sh` trip arms derive the ceiling crossing
  from `SOLEUR_TC_BUMP_FILE` writes, contain no wall-clock-dependent trip
  arm, and the suite passes 5 consecutive local runs.
- [x] `regenerate-shard-manifest.py --incremental --write` on a manifest
  whose registered set gained one suite produces a diff of exactly one added
  row; removing a suite produces exactly one removed row; incumbent legs
  never change.
- [x] `--incremental` refuses `--run/--runs/--timings-dir` combinations and
  the committed-write `--legs` K≠N refusal still applies.
- [x] ADR-240 carries the `--incremental` amendment in `## Decision` +
  `## Alternatives Considered`.
- [x] Runbook `ci-test-scripts-sharding.md` prescribes `--incremental` for
  add/remove regens and full `--runs 5 --write` for balance corrections.
- [x] New + edited suites register and run green
  (`plugins/soleur/test/*.test.sh` glob covers the probe suite;
  `regenerate-shard-manifest.test.sh` and
  `test-all-runtime-ceiling.test.sh` stay in their existing legs).
- [x] `git grep` confirms the Phase-7 probe logic is outside the
  `phase-7-poll-block` markers (so `merge-pr/SKILL.md` §5.2 needs no mirror
  edit), or the mirror is updated in the same PR.

## Test Scenarios

- Given a PR check `deploy-script-tests (1/4)` failing on the PR while the
  same-named job failed on the newest completed main run exercising it, when
  the probe runs, then it prints `SOLEUR_RED_ON_MAIN verdict=red-on-main` and
  exits 1.
- Given the same check but the newest exercising main run was green, when the
  probe runs, then verdict `green-on-main`, exit 0, and ship's existing
  rerun/fix ladder applies unchanged.
- Given the job skipped on the 2 newest main runs but failed on the 3rd
  (path-filtered skips are not evidence), when the probe runs, then verdict
  `red-on-main` from the run that measured it.
- Given the job never appears in the 5-run window (renamed or never run on
  main), when the probe runs, then `no-evidence`, exit 2, no quarantine.
- Given `gh` exits non-zero on any call, when the probe runs, then
  `verdict=error`, exit 3, no issue filed.
- Given an open tracker already carrying this check's sentinel, when
  `--report` runs on a red verdict, then it comments instead of creating a
  duplicate; on a green verdict it comments and closes that issue and no
  other.
- Given `SOLEUR_TC_BUMP_FILE` is written with `120` by the first fixture
  suite and `TC_RUNTIME_CEILING_S=60`, when the trip arm runs, then the first
  suite runs and every later suite is declined — deterministically, on every
  invocation, with `declined_suites=2` and `=== 1/2 suites passed ===`.
- Given a registered suite added since the manifest's last regen, when
  `--incremental --write` runs, then the manifest diff is exactly that one
  new row and `suite-durations.tsv` is untouched.
- Integration verify (local, deterministic):
  - `bash plugins/soleur/test/check-red-on-main.test.sh` — all stubbed-gh
    arms green.
  - `for i in 1 2 3 4 5; do bash scripts/test-all-runtime-ceiling.test.sh || break; done`
    — five consecutive greens.
  - `python3 scripts/regenerate-shard-manifest.py --incremental` (dry-run) —
    prints incumbent-pinned diff only.

## Sharp Edges

- `gh run rerun` operates on completed runs only; the probe is invoked at
  terminal-fail time, after completion — do not move it into the per-tick
  poll path.
- The `phase-7-poll-block` markers in `ship/SKILL.md` mirror
  `merge-pr/SKILL.md` §5.2 — the probe consult must live OUTSIDE those
  markers or be mirrored in both files in the same PR.
- Check-run/job NAME is the join key — exact match including the `(n/m)`
  matrix suffix; never prefix-match a matrix leg against its parent name.
- `skipped`/`absent`/`cancelled`-absence on main is not "green": only a real
  conclusion counts as evidence, and `cancelled` counts as red by the same
  `!= 'success'` convention `notify-main-failure` uses.
- A plan whose `## User-Brand Impact` section is empty, contains only
  TBD/placeholder text, or omits the threshold fails `deepen-plan` Phase 4.6
  — it is filled above.
- `EPOCHSECONDS` is a dynamic bash variable and cannot be assigned to fake
  time; the injected tick is a file-read bump spliced into the SANDBOX copy —
  production `test-all.sh` gains no test seam.
- `--incremental` must not rewrite `suite-durations*.tsv`: there are no new
  measurements in incremental mode, and rewriting would stamp stale medians
  over live ones.
- Semver label: the diff touches `plugins/soleur/` (scripts + SKILL.md +
  test) → PR carries `semver:patch`.
- PR body reminder: `Closes #9402`.

## Success Metrics

- A check red on main costs zero reruns on unrelated PRs (vs. three on
  #9339): the probe verdict appears in the ship transcript and the tracker
  issue exists.
- `test-all-runtime-ceiling.test.sh` flake rate → 0 (no boundary-dependent
  arms remain).
- Suite-addition regens produce single-row manifest diffs (vs. the 10-suite
  rebalance observed).

## Dependencies & Risks

- `gh` auth availability at ship/monitor time — the probe degrades to
  `verdict=error` (never quarantines), which is the same handling as today.
- The job-name join depends on GitHub keeping check-run names equal to job
  names for matrix legs — verified live today; a future GitHub change shows
  up as `no-evidence`, not a wrong quarantine.
- #8659's in-flight `test-all.sh` trap work could drift the `_elapsed_s`
  splice anchor — `sub_once` asserts exactly-one-match, so a drift is a loud
  suite red, not a silent escape.
- Adding `--incremental` without updating the manifest header's `regen:` hint
  would leave operators on the full-rebalance path — the render strings and
  runbook are in the same file list for that reason.

## Rollback Plan

All three workstreams are independently revertible; none mutates production:

- **Probe + wiring:** revert removes the script, the SKILL.md pointer, the
  reference file, and the monitor annotation — ship's Phase 7 returns
  verbatim to today's rerun/abort behavior. Any `soleur:red-on-main` tracker
  issues already filed stay open until manually closed (a revert does not
  erase their audit value); no state accumulates anywhere else — there is no
  committed quarantine registry by design.
- **Ceiling test:** the bump-file splice lives entirely inside
  `test-all-runtime-ceiling.test.sh`'s sandbox builder; reverting restores
  the timing-flaky-but-functional suite. Production `test-all.sh` is never
  touched, so there is nothing to roll back there.
- **Incremental regen:** `--incremental` is opt-in; reverting the flag leaves
  the existing full sticky-LPT `--runs 5 --write` path untouched. A manifest
  written incrementally is still a valid manifest — rolling back the
  generator does not strand generated data.

## Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| Committed quarantine registry file + scheduled maintainer | Rejected — drift surface and merge-conflict artifact (ADR-235); live derivation covers P1 at decision time. |
| In-workflow `continue-on-error`/neutral flip when quarantined | Rejected — greens the PR signal while main is red; suppresses evidence instead of reruns. |
| Promote `infra-validate-required` into the required set (#6480) | Rejected for this issue — orthogonal severity decision; quarantine helps advisory AND required reds differently (report+proceed vs report+escalate), and #6480 remains the right fix for merge blocking. |
| New standalone regen script for incremental mode | Rejected — flag on `regenerate-shard-manifest.py` reuses `read_incumbent`/`registered_labels`/lint contract. |
| Add a test-only env seam to production `test-all.sh` | Rejected — the sandbox splice is the existing injection mechanism; production code stays untouched. |
| Reuse `ci/main-broken` sentinel `soleur:main-health-monitor` for quarantine issues | Rejected — the monitor's closer retires only its own sentinel; piggybacking would let the monitor close issues about check-contexts it never measured. New sentinel `soleur:red-on-main` keeps ownership disjoint. |

## Non-Goals

- Fixing the `git-data-runcmd-rehearsal.test.sh` stuck-docker root cause —
  the symptom that motivated this; tracked by the `ci/main-broken` machinery
  it already feeds. Quarantine is the cost fix; the suite's flake is a
  separate fix.
- Promoting advisory checks into the required ruleset (#6480).
- Comparing failure signatures/log content between PR and main runs (the
  verdict is name+conclusion only).
- Quarantining individual suites within a check (check-level granularity
  only).

## References & Research

- Issue: #9402 (this work), #9339 (cost evidence), #6480 (required-set
  promotion), #8735 (cancelled-leg notify fix — landed), #7374 (sentinel
  ownership lesson), #7307 (monitor contract precedent).
- ADRs: ADR-240 (amended here), ADR-252 (presence registration), ADR-235
  (generated-artifact conflicts), ADR-032 (required-check IaC), ADR-072
  (adaptive CI wait — neighbor, not overlap).
- Code: `plugins/soleur/scripts/admin-merge-ready.sh` (check-runs read +
  name/app match precedent), `plugins/soleur/scripts/monitor-pr-checks.sh`,
  `plugins/soleur/skills/ship/SKILL.md` (Phase 7), `main-health-monitor.yml`
  (issue-filing + sentinel conventions), `infra-validation.yml`
  `notify-main-failure` (ops-email reporting precedent),
  `scripts/regenerate-shard-manifest.py` (`assign`, `read_incumbent`,
  `registered_labels`), `scripts/test-all-runtime-ceiling.test.sh`
  (`build_sandbox` splice idiom), `run-registered-suites.sh` (`_SUITE_BOUNDS`
  600 s override).
- Learnings (paths verified): `knowledge-base/project/learnings/2026-09-19-a-generated-artifact-in-my-diff-made-every-landing-on-main-a-conflict.md`
  (regen diffs and merge conflicts),
  `knowledge-base/project/learnings/2026-05-12-ci-test-job-speedup-replan-and-validation-mechanics.md`
  (CI mechanics validation),
  `knowledge-base/project/learnings/2026-09-11-a-filer-with-no-honest-exit-takes-the-free-one-at-any-price.md`
  (sentinel/dedupe care),
  `knowledge-base/project/learnings/2026-04-23-hostname-prefix-guard-and-strict-mode-pipefail.md`
  (exact-match identity guards).
