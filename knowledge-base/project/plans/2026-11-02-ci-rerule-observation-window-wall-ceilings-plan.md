---
title: "ci: re-rule the observation-window probe wall-time ceilings (240 s p95, 285 s max) and settle the s4-drain floor mismatch"
date: 2026-11-02
slug: ci-rerule-observation-window-wall-ceilings
branch: feat-one-shot-10865-ceiling-rerule
issue: 10865
type: ci
priority: p3-low
domain: engineering
brand_survival_threshold: none
requires_cpo_signoff: false
lane: cross-domain
---

# ci: re-rule the observation-window probe wall-time ceilings and settle the s4-drain floor mismatch

Ref #10865 (the soak tracker), Ref #10861 (S4 PR5), Ref #10448 (the S4 index-completion tracker). Every
reference in the commit, the PR title and the PR body is `Ref`; none is `Closes`/`Fixes`/`Resolves`.

## Overview

The CTO agent ruled on #10865 on 2026-11-02 that the observation-window probe
`scripts/followthroughs/ratchet-observation-window-10865.sh` takes `P95_MAX=240` and `MAX_MAX=285` now,
ahead of the 30-day trigger (2026-11-22). The same comment left one open problem that must be settled
before the change merges: both 2026-11-01 sweeper comments printed `floor=pr3a`, but the restart floor
should be `s4-drain` (PR5 #11226, merged 2026-10-26T21:59:35Z, label `s4-drain`). The sweeper closes
#10865 on a probe exit 0, so an unapplied floor would let a PASS count pre-PR5 units.

Two deliverables, one PR:

1. The ceiling re-rule: two constants in the probe, its header text, the replay-suite pins, titles and
   fixtures, the runbook mentions plus a dated observation-log row, and an append-only ADR-276 amendment.
2. The floor fix (ruled below): `pull-requests: read` on the sweeper workflow plus a fail-closed sentinel
   in the probe, so the floor can never again be silently dropped.

No flip, no `CI_PR_AFFECTED`, no activation-lock removal, no baseline edit, no live probe run, no post to
#10865, no PR D (#10414), no PR3b (#10859).

## Research Insights

### Premise Validation (Phase 0.6)

- `#10865`, `#10861`, `#10448` are all OPEN; the premise (tracker still soaking) holds. `#11771` (ratchet
  red on main) is CLOSED and its repair PR `#11781` merged 2026-11-01T11:45Z; the latest `merge_group`
  runs of `ci.yml` on main read `success` (run 41408788451, 41383859419, 41382075629) with one in progress
  at planning time. The ratchet must still be green or explained at merge time (see Acceptance Criteria).
- Collision pre-check: the only open change naming #10865 is PR #11847, which is THIS branch's own draft
  PR (`WIP: feat-one-shot-10865-ceiling-rerule`, no files yet). Not a duplicate.
- Cited paths confirmed on the branch: the probe (526 lines), the replay suite, the runbook (300 lines),
  ADR-276 (538 lines, last amendment `## Amendment 2026-10-22 (S4 index completion ratchet, #10448; Ref #9729)`).
- ADR-corpus check for the proposed mechanism: ADR-276 item 6 records the 210/270 ceilings as PROVISIONAL
  and says the CTO agent re-rules "the two constants at the close of the window or at the 30-day trigger,
  whichever is first". Re-ruling early is not a rejected alternative; it supersedes by subject, so the
  amendment is append-only (item 6 stays unedited).
- Brief claims that did not survive contact with the code (see Reconciliation below).

### Research Reconciliation: brief vs. code

| Brief claim | Reality | Plan response |
|---|---|---|
| "pinned rows (around lines 3204-3206)" carry the numbers | Only `row_ow_slow` (3204) and `row_ow_max` (3205) carry numbers; `row_ow_30day_ceiling` (3206) has none. A fourth consumer the brief omits: `row_ow_timeout` pins `wall max 300s is over 270` (content anchor `grep -q 'wall max 300s is over 270'`). | Update the two numeric rows AND `row_ow_timeout` to `over 285`. Find every site by content anchor, then re-grep for `270`/`210` afterwards. |
| "Do NOT blanket-replace 270" | Correct: `SOAK_BUDGET_S` default `270` (probe lines `BUDGET=` and the header "270 s, 30 s under the sweeper's 300 s"), the replay-suite pin `parallel=8 budget_s=270`, and `TIMEOUT_WALL=290` are all unrelated. | Edit by anchor: `^P95_MAX=210 ` and `^MAX_MAX=270 ` only; assert the three unrelated 270/290 sites are byte-identical in the diff. |
| "header text around lines 25-28" | Lines 24-28 hold the `(d)` criterion. `row_ow_static` pins the substring `ceilings are PROVISIONAL` in the probe; the PASS echo at the end of the probe also carries it. | Keep the phrase `ceilings are PROVISIONAL` in the header (reworded: first ruled 210/270, re-ruled 240/285 on 2026-11-02). Leave the PASS echo and the failure-message strings unchanged (brief: failure text unchanged; the `ceiling-owed-note-dropped` mutant anchors on it). |
| "ow_u_slow 220 becomes about 250; ow_u_bigmax 280 becomes 288" | `ow_u_slow` rewrites every unit to `220` via `${OW_UNITS[$i]% *} 220`; `ow_u_bigmax` appends 40 units at 150 plus one at `280`. With 250 every unit is over 240 and under 285, so only the p95 message fires; with 288 only the max message fires (one unit in ~49, p95 stays 150) and 288 < `TIMEOUT_WALL=290` so the unit is still a finished job. | Use exactly 250 and 288. Both are asserted by the row text (`wall p95 250s is over 240 s`, `wall max 288s is over 285 s`). |
| "find out why the live sweeper prints pr3a" | Root cause is the sweeper token, not the probe: the job log "GITHUB_TOKEN Permissions" block of run 41352096315 lists Actions/Checks/Contents/Issues/Metadata and NO Pull requests. See "Floor mismatch" below. | CTO-ruled fix (C), recorded in decision-challenges.md. |
| "the sweeper's env/inputs" | `.github/workflows/scheduled-followthrough-sweeper.yml` passes `GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}` to the sweeper, which hands it to a probe only when the directive says `secrets=GH_TOKEN`. The directive on #10865 does. The probe is not at fault: same file, same query, the operator's user token returns 4 PRs. | Fix at the token's scope plus a sentinel in the probe. |

### Floor mismatch: evidence and root cause

- Code path: probe lines after `floor_src="pr3a"` read
  `repos/$REPO/issues?labels=s4-drain&state=closed&sort=updated&direction=desc&per_page=100`, take
  `max(.pull_request.merged_at)`, and move `merged_at` to it only `if (( drain_epoch > merged_epoch ))`.
  The floor logic has been in the file since #11393 (2026-10-28); both 2026-11-01 sweeper runs
  (41338561300 at 18:55Z, 41352096315 at 21:31Z) executed a probe that has it, because they print `floor=`.
- Live read with the operator's token (a single read of the label list, not a probe run): 4 PRs
  (#11226 `2026-10-26T21:59:35Z`, #11131, #11109, #10945), each with `.pull_request.merged_at` set. Label
  `s4-drain` exists; PR #11226 carries it. So the probe, given that body, prints `floor=s4-drain` with
  `window opened=2026-10-26T21:59:35Z`.
- Sweeper token: `gh run view 41352096315 --log` shows `GITHUB_TOKEN Permissions: Actions: read, Checks:
  read, Contents: read, Issues: write, Metadata: read`. The workflow's explicit `permissions:` block makes
  every unlisted scope `none`; `pull-requests` is unlisted.
- GitHub's App-permissions documentation (https://developer.github.com/v3/apps/permissions/): "If your
  GitHub App has permissions on issues but not on pull requests, these endpoints will be limited to issues.
  Endpoints that return both issues and pull requests will be filtered." The label query is such an
  endpoint; it returns `[]` to this token, `drain_at` is empty, and the floor silently stays `pr3a`.
  The direct endpoints the probe reads (`pulls/N`, `pulls/N/files`, `commits/<sha>/pulls`,
  `issues/N/timeline`) work under the same token (the 2026-11-01 comments show `prs=14` / `prs=20` facts),
  which is why nothing else broke.
- Status of the claim: the permission block is measured; the filtering behaviour is documented, consistent
  with every observation, and NOT reproduced under a `GITHUB_TOKEN` (reproducing it means running the
  probe, which this PR does not do). The CTO ruling therefore pairs the permission fix with a sentinel that
  catches the symptom whatever its cause. Learning
  `2026-10-06-a-permission-table-is-not-the-endpoint-and-the-first-real-run-found-it.md` is the reason the
  PR body says "unproven empirically" rather than "confirmed".

### What the sweeper does on each probe exit code (for the PR body)

Source: `scripts/sweep-followthroughs.sh` (the `case "$rc"` after the probe returns).

| Probe exit | Sweeper verdict | Effect on #10865 |
|---|---|---|
| 0 | `PASS`: posts the PASS comment (`SWEEPER_PASS_HEADING`, last 4 KB of output) then runs `gh issue close` | **Closes the tracker.** Skipped only under `DRY_RUN=1`. |
| 2 | `NOT YET` (static rc-to-word map) | Posts a `Sweeper run: NOT YET (exit 2, ...)` comment; leaves the issue open. |
| 3 | `CANNOT ESTABLISH` | Same comment shape, `exit 3`; leaves the issue open. A probe killed by the 300 s `FT_PROBE_TIMEOUT` (rc 124/137) is mapped to 3 too. |
| 1 | `FAIL` (never used by this probe) | Comment, stays open. |
| other (78 xtrace refusal, 143, ...) | `TRANSIENT` | Comment, stays open. |

Only exit 0 mutates the tracker, which is why the floor must be provably applied before a PASS is possible.

### Institutional learnings applied

- `2026-10-28-a-probe-that-could-finally-pass-would-have-closed-its-tracker-on-pre-restart-evidence.md`:
  list what a verdict triggers before making it reachable; the floor is the criterion that was masked.
- `2026-08-13-a-lower-bound-cannot-tell-a-measurement-from-a-constant.md` and
  `2026-08-09-my-tests-pinned-a-constant-by-indexing-it-and-my-mutants-read-as-survivors.md`: pin the
  constants against an external referent (the probe file's own text), and add substitution mutants.
- `2026-10-22-a-probe-went-blind-when-its-suite-moved-...md`: a probe whose evidence channel can go blind
  must refuse a verdict (exit 3), not fall back to a weaker floor.
- Same 2026-10-28 learning, error 2: mutant `old` strings go stale when a probe line they anchor is
  edited; after any probe edit, grep every `^ow_mutate` old string against the probe before the full run.
- Replay-suite runtime: the full battery is a 10-45 minute run under load; use `--rows` ranges or the
  OW-only driver while iterating, one full run at the end.

### Property List and Cut List (Phase 0.6b)

Properties the ask buys:

- P1. The probe's wall-time criterion rejects a sweep whose whole-population p95 exceeds 240 s or whose
  maximum exceeds 285 s, and accepts one at or below both.
- P2. The suite pins those exact values and the observable behaviour at the new edges.
- P3. The ruling and its measured series are recorded where the rules live (runbook log, ADR-276).
- P4. A PASS can only count units created after the later of the PR3a merge and the latest `s4-drain` merge,
  under the token the sweeper really uses.
- P5. The reader of the PR can see what the sweeper does on exit 0, 2 and 3.

Mechanisms the brief names and what already covers them (Cut List): none cut. Considered and cut during
planning: (a) making `P95_MAX`/`MAX_MAX` env-overridable seams (the CTO ruling says "those two constants and
nothing else"; a seam is inert under the sweeper's `env -i` and would only add a pin); (b) reading the drain
list through `search/issues` (a new endpoint with a separate 30/min rate limit and the same unreproduced
permission semantics; the sentinel is cheaper and cause-independent); (c) editing the PASS echo to say the
ceilings are no longer provisional (the brief fixes the failure text; the `ceilings are PROVISIONAL` pin
stays satisfied; the wording decision belongs to the close-of-window ruling).

## Technical Rulings Applied

Persisted as rows of `| Item | Class | Ruling |` in
`knowledge-base/project/specs/feat-one-shot-10865-ceiling-rerule/decision-challenges.md`:

- D1 (technical): ceilings 240/285. Ruled by CTO agent, 2026-11-02 (recorded on #10865); not re-spawned.
- D2 (technical): floor mismatch fix = option (C): `pull-requests: read` on the sweeper workflow AND a
  fail-closed sentinel in the probe. Ruled by CTO agent, 2026-11-02 (this planning run).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "set P95_MAX=240 and MAX_MAX=285. Those two constants only." | Phase 1, Files to Edit: probe constants | mapped |
| 2 | "Keep the failure-message text unchanged. Update the header text around lines 25-28." | Phase 1 header edit; failure strings untouched | mapped |
| 3 | "update the pinned rows (around lines 3204-3206), the `^P95_MAX=210 ` / `^MAX_MAX=270 ` pin (around 3236), the titles (around 3649-3650) and the fixtures: ow_u_slow ... ow_u_bigmax" | Phase 2 | mapped |
| 4 | "update the ceiling mentions (around lines 171, 270, 276) and add a dated 2026-11-02 observation-log row carrying the measured series" | Phase 3 | mapped |
| 5 | "Add a dated, append-only amendment to ADR-276 (leave item 6 unedited)." | Phase 4 | mapped |
| 6 | "find out why the live sweeper prints pr3a, and either fix it in this PR or explain it in the PR body with evidence" | Phase 5 (fix, ruled D2) and the PR-body block | mapped |
| 7 | "In the PR body also state what the sweeper does on each probe exit code (0, 2, 3)." | PR-body block; table above | mapped |
| 8 | "Note in the PR body that the ratchet (affected-index-ratchet) state on main must be green or explained before merge." | PR-body block; Acceptance Criteria | mapped |
| 9 | "Ref #10865, Ref #10861, Ref #10448 — use \"Ref\" only, never Closes." | Phase 6 PR body | mapped |
| 10 | "Do NOT: touch scripts/ci-pr-affected-audit.baseline.tsv, run the probe live or re-run evidence, flip anything, post to #10865 ..." | Constraints / Acceptance Criteria (negative checks) | mapped |
| 11 | "The ceiling values (240/285) are already ruled ... record that as a `technical` row" | decision-challenges.md D1 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `row_ow_timeout` pin `over 270` to `over 285` | "update the pinned rows" (the same pin family; the ceiling it names changes) | asked |
| Sentinel tripwire in the probe + its replay rows and mutants | "either fix it in this PR" | asked (shape ruled D2) |
| `pull-requests: read` on the sweeper workflow + a pin in `scripts/sweep-followthroughs.test.sh` | "find out why the live sweeper prints pr3a ... either fix it in this PR" | asked (shape ruled D2) |
| Local `ci-pr-affected-replay.py ratchet` run before push | "the ratchet (affected-index-ratchet) state on main must be green or explained before merge" | asked (verifies this diff adds no new pair) |
| One runbook line on the sentinel and the post-merge `floor=s4-drain` check | "Read the probe's floor logic and the sweeper's env/inputs" | inferred — justification: the runbook is the rules home for the probe (its drain-claim paragraph states the floor), and the CTO ruling requires the follow-up check to be written down |

### Split Assessment

- Subsystems touched: 4 — `scripts/followthroughs/` (probe), `plugins/soleur/test/` (replay suite), `.github/workflows/` + `scripts/` (sweeper workflow and its test), `knowledge-base/` (runbook, ADR, specs)
- Planned files: 8 edited, 2 created (specs) | Estimated changed lines: ~230 (mostly test rows)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — the 4 roots reflect one concern (the probe and its rules); splitting the floor fix from the ceilings would leave a PASS-capable probe with the floor unapplied for the length of the gap, which is the exact hazard of item 5 ("must be resolved before this PR merges").

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing. The change is CI follow-through
  machinery (a probe, its test suite, a sweeper workflow permission, internal docs). The failure it
  guards against is internal: a tracker closing early on pre-restart evidence, which would let a later
  required-check decision (PR3b, held for the budget owner) lean on a window that did not hold.
- **If this leaks, the user's data / workflow / money is exposed via:** no user data is touched. The
  workflow change adds a READ scope (`pull-requests: read`) to a token already holding `issues: write`
  on a public repository; the token is handed only to probes whose directive declares `secrets=GH_TOKEN`.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** none, not aggregate pattern: no end user, customer data or
  billing path is reachable from these files; the worst outcome is a mistimed internal tracker close,
  which is reversible by reopening the issue.

threshold: none, reason: the touched `.github/workflows/` file is a read-scope addition on a token that
already has issue-write on a public repo, and the probe/test/doc edits reach no user-facing surface.

## Observability

```yaml
liveness_signal:
  what: the sweeper's per-tracker comment on #10865 (Sweeper run verdict) whose status line prints `floor=s4-drain` and `window opened=2026-10-26T21:59:35Z`
  cadence: daily at 18:00 UTC (scheduled-followthrough-sweeper.yml) plus any workflow_dispatch
  alert_target: the sweeper comment on tracker #10865 and a red run on the Scheduled Follow-Through Sweeper workflow
  configured_in: .github/workflows/scheduled-followthrough-sweeper.yml and scripts/sweep-followthroughs.sh
error_reporting:
  destination: GitHub issue comment on #10865 (the sweeper has no Sentry path; it is CI tooling)
  fail_loud: probe exit 3 with the first token `CANNOT ESTABLISH:` and a sentence naming the sentinel PR, rendered by the sweeper as `Sweeper run: CANNOT ESTABLISH (exit 3, ...)`
failure_modes:
  - mode: the sweeper token cannot see pull requests through the label listing (empty list while the sentinel PR is merged)
    detection: the probe sentinel compares the label-list maximum with `pulls/11226` merged_at and exits 3 instead of printing floor=pr3a
    alert_route: sweeper comment `CANNOT ESTABLISH` on #10865
  - mode: the `pull-requests: read` line is trimmed from the sweeper workflow later
    detection: the permission pin in scripts/sweep-followthroughs.test.sh goes red in the required test context, and the sentinel above catches it at run time
    alert_route: red required check on the PR that trims it; sweeper comment if it slips through
  - mode: the whole-population p95 drifts above 240 s (daily p95 was 237 s on 2026-11-02)
    detection: the probe prints `NOT YET: wall p95 <n>s is over 240 s` each sweep once it reads the population
    alert_route: sweeper NOT YET comment; the recheck trigger in the runbook row sends two consecutive reads above 240 s to the budget owner as a CI cost regression
logs:
  where: GitHub Actions run log of the sweeper job and the tracker comment (last 4 KB of probe output)
  retention: GitHub Actions default log retention; comments are permanent
discoverability_test:
  command: grep -c "pull-requests: read" .github/workflows/scheduled-followthrough-sweeper.yml
  expected_output: 1
```

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-276 (`knowledge-base/engineering/architecture/decisions/ADR-276-demand-first-hosted-runner-budget-merge-group-is-the-full-battery-authority.md`)
with a dated, append-only `## Amendment 2026-11-02 (observation-window wall ceilings re-ruled, Ref #10865; Ref #10448)`
placed after the last existing amendment. Decision: p95 ceiling 210 s becomes 240 s and maximum 270 s becomes
285 s; supersedes by subject the ceiling sentences of item 6 (which stays unedited, like every earlier
amendment) and the ceiling half of PR3b entry condition 9(e); records the measured series and the recheck
trigger; records that the probe's `s4-drain` floor now depends on the sweeper token's `pull-requests` scope
and is guarded by a sentinel. Status stays `adopting`. This is a task in Phase 4, not a follow-up issue.

### C4 views

No C4 impact. Checked against all three model files (`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`):
(a) external human actors: none added (the operator already models; the budget owner is a role, not an
element); (b) external systems: GitHub is the only system touched and is already modeled as `github` (the
sweeper is a workflow on it, not a separate element, and a grep of the model for
`followthrough|sweeper|ratchet` returns only unrelated edge prose at the plugin container and the
inngest/betterstack edges); (c) containers/data stores: none created or changed; (d) actor-to-surface access
relationships: unchanged (a read scope on an existing token on the existing `github` system adds no edge).
The derived-cardinality gate must stay green: run `bash plugins/soleur/test/c4-count-parity.test.sh` (no
workflow file is added, so the workflow count is unchanged).

### Sequencing

The amendment describes the state after this PR merges and is authored in this PR. The post-merge
`floor=s4-drain` observation is recorded in the amendment as the check that completes the floor fix, not as a
deferred ADR.

## Guard Contract

The deliverable adds three guards: the probe's floor sentinel, the sweeper-workflow permission pin, and the
exact-value pin of the two ceilings. Matrices are written from the design, before the code.

### Guard 1 — floor sentinel (probe)

**Property.** The probe never reports a floor older than the latest merged `s4-drain` PR it can independently
prove exists: when the sentinel PR (#11226, merged 2026-10-26T21:59:35Z) is merged and the label-list maximum
is empty or earlier than it, the probe exits 3 `CANNOT ESTABLISH` before it lists a single run.

**Assembly.** One chokepoint: the code between the label-list parse (`drain_at=`) and the `if [[ -n "$drain_at" ]]`
floor application in `scripts/followthroughs/ratchet-observation-window-10865.sh`; every later phase (run listing,
unit reads, facts, verdict) takes `merged_at` from that single assignment, so there is exactly one place the
floor is formed. Members: the sentinel read (`pulls/11226` via the shared `api` wrapper, so the budget, retry and
HTTP 403/429 flag apply), its timestamp validation, the epoch comparison, and the exit. The fail-closed arms
(sentinel read failure, non-object body, malformed `merged_at`) are three further members of the same chokepoint.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Replace the trip condition with `false` (tripwire disarmed) while the stub serves `[]` for the label list and a merged sentinel | RED: row `row_ow_sentinel_trips` expects exit 3 with the fixed `CANNOT ESTABLISH:` line, gets exit 2 |
| 2 | Delete the sentinel read entirely (dispatch: "0 checked") | RED: the same row asserts `pulls/11226` appears in the stub request log, and a second assertion that it appears BEFORE the first `actions/workflows/ci.yml/runs` request |
| 3 | Add a SECOND member after a compliant first: the label list holds an older drain (`2026-10-26T15:03:07Z`, #11131) but not the sentinel; mutate the test to `[[ -z "$drain_at" ]]` only | RED: row `row_ow_sentinel_older_list` expects exit 3 (a non-empty list that lacks the newest drain is the same defect) |
| 4 | REORDER: move the sentinel block after the run listing loop | RED: the request-order assertion in row 2 (observes INSIDE the window, not the final state) |
| 5 | Ignore a failed sentinel read (`|| true` instead of `|| fail_api`) | RED: row `row_ow_sentinel_errors` (HTTP 404, 403, 5xx each expect exit 3 with the one fixed line) |
| 6 | Leave the sentinel `merged_at` unvalidated (accept `junk`) | RED: `row_ow_sentinel_errors` malformed-timestamp case expects exit 3 |

**Harness rows.** (i) Run the new rows against the PRE-change probe (`git stash`-free: `git show HEAD:scripts/followthroughs/ratchet-observation-window-10865.sh`
into a temp path): `row_ow_sentinel_trips` must be RED there, proving the row can fail. (ii) Must-PASS inputs that
are NOT the canonical fixture and differ in a way the contract permits: sentinel `merged_at: null` (unmerged in
the fixture world) with an empty list passes through to the normal verdict; a list whose maximum EQUALS the
sentinel timestamp passes (equal is applied, not tripped); a list with a LATER drain than the sentinel passes
and prints `floor=s4-drain`. All existing rows get the sentinel stubbed as `merged_at: null` by `ow_case`, so a
vacuous trip cannot hide behind them, and `row_ow_read_only` (no `STUB-MISS`) stays the guard that every probe
read has a fixture.

**Anchor.** The sentinel compares a hard-coded PR number to a live API value. A one-diff weakening (edit the
constant to a PR that is not merged, or delete the block) is caught by mutation rows 1, 2 and the harness row
(i), not by the sentinel itself. What moves outside the commit: the ruling recorded in decision-challenges.md
and on the ADR-276 amendment (independently reviewed text), and the post-merge `floor=s4-drain` sweeper output.
The sentinel proves consistency with PR #11226, not integrity of a future PR; stated, not hidden.

### Guard 2 — sweeper workflow permission pin

**Property.** The effective token of the Scheduled Follow-Through Sweeper job includes `pull-requests: read`.

**Assembly.** The workflow's top-level `permissions:` block is the only source (the `sweep` job declares no
`permissions:` of its own); the pin reads the comment-stripped workflow and also asserts no job-level
`permissions:` override exists, so a later override cannot make the top-level line decorative.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the `pull-requests: read` line | RED |
| 2 | Comment it out (`# pull-requests: read`) | RED (the pin strips comment lines first; a bare `grep` would pass on the comment) |
| 3 | Set it to `pull-requests: none` | RED |
| 4 | Add a job-level `permissions:` block under `sweep:` that omits it | RED (the second assertion: no job-level `permissions:` key) |
| 5 | Delete the pin section so the suite checks nothing | RED: the suite's own assertion count (`TOTAL`) is compared with the expected number of PTO-style rows; a pin that registers 0 checks fails |

**Harness rows.** Run the pin against a copy of the workflow with the line removed (suite edit, temp path) and
require FAIL; run it against a copy where the line is present among other scopes in a different order and
require PASS (non-canonical must-PASS).

**Anchor.** A one-diff weakening can edit the pin and the workflow together. Outside the commit: the CTO
ruling (D2) and the sentinel in Guard 1, which fails at run time regardless of the pin.

### Guard 3 — exact-value pin of the two ceilings

**Property.** The probe's `P95_MAX` is exactly 240 and `MAX_MAX` exactly 285, and the behaviour at the edges
follows them.

**Assembly.** Constants: the two assignments at the top of the probe (`^P95_MAX=`, `^MAX_MAX=`). Consumers:
the two comparison lines in the verdict block, the failure messages built from `$P95_MAX`/`$MAX_MAX`, and the
suite pins (`row_ow_static`, `row_ow_slow`, `row_ow_max`, `row_ow_timeout`). Unrelated numbers that must not
move: `SOAK_BUDGET_S` default 270, `TIMEOUT_WALL=290`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | `P95_MAX=240` back to `210` | RED (`row_ow_static` pin, and `row_ow_slow` message `over 240 s`) |
| 2 | `P95_MAX=250` (equal to the fixture) | RED (`row_ow_slow` fixture at 250 is no longer over the ceiling, so no NOT YET) |
| 3 | `MAX_MAX=290` (equal to `TIMEOUT_WALL`) | RED (`row_ow_max`: the 288 s unit no longer trips) |
| 4 | `MAX_MAX=270` back | RED (`row_ow_static`, `row_ow_max`, `row_ow_timeout` message `over 285`) |
| 5 | Substitute the literal in the message (`over 240 s` hard-coded, `$P95_MAX` dropped) | survives behaviourally by design; caught by Guard 3 row 1/2 only through the constant. Recorded as an accepted residual: the message text and the constant are pinned independently |

**Harness rows.** Existing `ow_mutate` helper: add two mutants (`ceiling-p95-raised` `P95_MAX=240`→`250`,
`ceiling-max-raised` `MAX_MAX=285`→`290`); after the edit, grep every `^ow_mutate` old string against the
probe to confirm each lands once (learning 2026-10-28, error 2). Must-PASS: default fixtures (walls 150-155)
stay green at the new edges.

**Anchor.** The values are anchored outside the commit by the CTO ruling comment on #10865
(2026-11-02T08:31:45Z), the runbook observation-log row and the ADR amendment, which a one-diff weakening of
the constants does not move.

## Implementation Phases

Phase numbers follow the brief's items; ordering is chosen so the probe edits land before the suite edits that
pin them, and the suite is run once at the end.

### Phase 0 — Preflight (read-only)

- `bash plugins/soleur/scripts/collision-precheck.sh 10865` (PR #11847 is this branch; no foreign hit).
- Confirm CWD and branch. Capture the baseline of unrelated numbers to prove they do not move:
  `git grep -n -E 'SOAK_BUDGET_S:-270|TIMEOUT_WALL=290|budget_s=270' -- scripts plugins` (3 sites expected).
- Record the pre-edit line count of `scripts/ci-pr-affected-audit.baseline.tsv` (`wc -l`) and its `git hash-object`;
  Acceptance Criteria re-check both.

### Phase 1 — The probe: constants, header, sentinel (`scripts/followthroughs/ratchet-observation-window-10865.sh`)

1.1 Constants, edited by anchor: `P95_MAX=210   # PROVISIONAL (see (d))` becomes `P95_MAX=240 ...`;
    `MAX_MAX=270   # PROVISIONAL (see (d))` becomes `MAX_MAX=285 ...` (keep the trailing comment so
    `^P95_MAX=240 ` and `^MAX_MAX=285 ` match the trailing-space pin). Do not touch `BUDGET=`, `TIMEOUT_WALL=290`.
1.2 Header, criterion (d): `P95_MAX (240) s` / `MAX_MAX (285) s`; reword the PROVISIONAL sentence to keep the exact
    phrase `ceilings are PROVISIONAL` and add: first ruled 210/270, re-ruled 240/285 by the CTO agent on
    2026-11-02 from the whole post-PR5 population (372 jobs, p95 218 s, max 284 s) and recorded on the
    runbook's observation log. Do not alter the failure strings (`(PROVISIONAL ceiling; ceiling re-rule owed: ...)`)
    or the PASS echo.
1.3 Sentinel (Guard 1). Constant `DRAIN_SENTINEL=11226` near `PR3A=10851`, with a comment: PR5, carries label
    `s4-drain`, merged 2026-10-26T21:59:35Z; an independent lower bound for the floor; retired with the probe.
    After the existing `drain_at` validation line and before `if [[ -n "$drain_at" ]]`:
    - `s_json="$(api "repos/$REPO/pulls/$DRAIN_SENTINEL")" || fail_api "s4-drain sentinel $DRAIN_SENTINEL"`
    - `s_at="$(jq -r 'if type != "object" then error("not an object") else (.merged_at // "") end' <<<"$s_json" 2>/dev/null)" || fail_api "s4-drain sentinel (parse)"`
    - validate `s_at` against the same ISO-Z regex as `drain_at` (empty allowed = not merged), else `fail_api "s4-drain sentinel (parse)"`
    - if `s_at` non-empty: compute `s_epoch` (`date -u -d`, failure is `fail_api`), and if `drain_at` is empty OR
      `drain_epoch < s_epoch` print the single fixed line
      `CANNOT ESTABLISH: s4-drain floor not applied: the label list does not carry sentinel PR $DRAIN_SENTINEL (check the sweeper token's pull-requests scope)`
      and `exit 3`. The line is a literal built only from constants (no payload bytes reach the public comment).
    The `api` wrapper is used so the shared deadline, the single transient retry and the 403/429 flag apply;
    a deadline cut (rc 46) at this point (about 2 s in) would be unreachable in practice and is treated as a
    failed read via `fail_api` (stricter, per the ruling).
1.4 Header, RESTART FLOOR sentence: add one clause that the floor read is guarded by the sentinel and requires
    the token to see pull requests through the mixed issues endpoint.
1.5 Quota note: the sentinel is one extra request; `need` already carries a 100-request reserve, so the
    formula is unchanged. Say so in a comment on the line.

### Phase 2 — The replay suite (`plugins/soleur/test/ci-pr-affected-replay.test.sh`)

Find every line by content anchor, then re-grep:

2.1 `row_ow_slow`: `wall p95 220s is over 210 s` becomes `wall p95 250s is over 240 s`; fixture `ow_u_slow`:
    `... 220` becomes `... 250`.
2.2 `row_ow_max`: `wall max 280s is over 270 s` becomes `wall max 288s is over 285 s`; fixture `ow_u_bigmax`: the final
    unit's `280` becomes `288`.
2.3 `row_ow_timeout`: `wall max 300s is over 270` becomes `wall max 300s is over 285` (the omitted consumer).
2.4 `row_ow_static`: `^P95_MAX=210 ` becomes `^P95_MAX=240 `; `^MAX_MAX=270 ` becomes `^MAX_MAX=285 `.
2.5 Titles: `chk "window probe: a p95 over 210 s ..."` becomes `240 s`; `chk "... a maximum over 270 s fails by itself, though the p95 is under 210 s"` becomes `285 s` / `240 s`.
2.6 `row_ow_30day_ceiling` carries no number and needs no edit; verify it stays green (p95 250 is the only unmet criterion).
2.7 Sentinel support: `ow_case` default `OW_SENTINEL=""` and `ow_write`'s fixture block serves
    `repos/$R/pulls/11226` as `{"merged_at":null}` unless `OW_SENTINEL` holds a timestamp, `E404`, `E403`, `E502`,
    `junk` or `object` (mirror the `OW_RESOLVE` mode style). New rows (registered with `chk`, in the OW section):
    `row_ow_sentinel_trips` (empty list + merged sentinel: exit 3, the fixed line, `pulls/11226` requested before
    the first `ci.yml/runs` read), `row_ow_sentinel_older_list` (older drain only: exit 3), `row_ow_sentinel_applied`
    (list max equal to, and later than, the sentinel: exit 2 NOT YET path with `floor=s4-drain`, never 3),
    `row_ow_sentinel_unmerged` (null sentinel, empty list: unchanged verdict), `row_ow_sentinel_errors`
    (404/403/5xx/junk/object each exit 3 with one fixed line). Because the fixture world is 2031 and the
    sentinel's real timestamp is 2026, rows that need the sentinel merged set `OW_SENTINEL` to a 2031 stamp in
    the fixture and the probe reads the constant PR number only; the comparison is relative, so this is faithful.
2.8 Mutants via `ow_mutate`: `sentinel-disarmed`, `sentinel-read-removed`, `sentinel-after-listing` (reorder),
    `sentinel-error-ignored`, `sentinel-timestamp-unvalidated`, `ceiling-p95-raised`, `ceiling-max-raised`. Each
    `old` string must land exactly once; verify with a grep loop before the full run.
2.9 Do NOT add any text naming `.github/workflows/scheduled-followthrough-sweeper.yml` to this suite (it would
    create a new suite-to-path pair the baseline does not hold, turning the ratchet red); the workflow pin goes
    in `scripts/sweep-followthroughs.test.sh`, which already reads that file.

### Phase 3 — The runbook (`knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md`)

3.1 Ceilings line (`Ceilings: 210 s p95 wall, 270 s maximum, ...`): `240 s p95 wall, 285 s maximum`; keep `timeout-minutes: 5`;
    state they were re-ruled on 2026-11-02 (see the observation log).
3.2 The Criteria bullet: `p95 wall at most 210 s and maximum at most 270 s` becomes `240 s` / `285 s`.
3.3 The "Ceilings are PROVISIONAL" bullet: `210 s and 270 s are the ruled numbers` becomes a dated statement that
    210/270 were the first ruling and 240/285 the 2026-11-02 re-ruling; keep the sentence that the CTO re-rules
    at the close of the window or at the 30-day trigger (a later re-rule remains possible), and record the recheck
    trigger (whole-population p95 above 240 s on two consecutive reads is a CI cost regression for the budget
    owner, not another re-rule).
3.4 The drain-floor paragraph / forgery-bound area: add one sentence that the floor depends on the sweeper token
    seeing pull requests (`pull-requests: read`) and that the probe exits 3 when the sentinel PR #11226 is
    missing from the label list; and that the first post-merge sweeper output must print `floor=s4-drain`
    and `window opened=2026-10-26T21:59:35Z` before any PASS is trusted.
3.5 New observation-log row, dated 2026-11-02, appended as the last entry under "Observation log entries":
    whole post-PR5 population of 372 `affected-index-ratchet` jobs pulled from the jobs API (no probe re-run);
    p95 218 s overall and 225 s since 2026-10-31 (`merge_group` 212 s, `pull_request` 225 s); max 284 s;
    2 of 372 units over 270 s; daily p95 206, 207, 201, 206, 215, 222, 237 s for 2026-10-27 to 2026-11-02;
    versus the probe's oldest-260 sample p95 203-205 s (sweeper comments 2026-11-01); ruling: `P95_MAX=240`,
    `MAX_MAX=285` (240 s is the edge of the 4-billed-minute bucket the 210 s ceiling already sat in, so spend
    does not rise; 285 s stays 5 s under the 290 s timeout class); billed minutes average 3.52-3.63 per unit
    against 3.4 in the 4,400 min/week estimate (noted for the PR3b budget decision, nothing authorized now);
    the 237 s daily p95 on 2026-11-02 is 3 s under the new ceiling, so the recheck trigger is live.
    Also the floor finding as a second dated row (or the same row's last sentence): root cause, fix and the
    follow-up check.
3.6 Do not edit the historic first-run and canary rows. The closing instruction mentioning "ceilings provisional;
    the only prior figure is local mean 203 s" is a record instruction for PR3a and stays.

### Phase 4 — ADR-276 amendment

Append after the last amendment (do not edit item 6, nor any earlier sentence):
`## Amendment 2026-11-02 (observation-window wall ceilings re-ruled, Ref #10865; Ref #10448)` with: Status stays
`adopting`, non-activating (no flip, no `CI_PR_AFFECTED`, no lock removal, no baseline edit); Decision (240/285,
by subject supersedes the ceiling sentences of item 6 and the ceiling half of 9(e); the failing-`continue-on-error`
canary half of 9(e) is untouched); the measured series (as in 3.5); rationale (the oldest-260 sample understates
the tail; 240 s sits at the edge of the 4-billed-minute bucket; 285 s is 5 s under the 290 s timeout class); the
recheck trigger; the floor finding and its fix (sweeper token scope plus sentinel) and the post-merge check;
"Ruled by CTO agent, 2026-11-02". Cross-link the runbook row. Run `ls knowledge-base/engineering/architecture/decisions/ADR-276-*`
and the repo's ADR ordinal check (no new ordinal is created, so no collision is possible).

### Phase 5 — The sweeper workflow and its pin

5.1 `.github/workflows/scheduled-followthrough-sweeper.yml`: add `pull-requests: read` to the top-level
    `permissions:` block with a comment: (#10865) the observation-window probe reads the `s4-drain` label list
    through the mixed issues endpoint, which GitHub filters to issues when the token has no pull-requests scope;
    without it the restart floor silently stays at the PR3a merge. Read only; the token is forwarded only to probes
    declaring `secrets=GH_TOKEN`. Keep the explicit-block rule (#8450).
5.2 `scripts/sweep-followthroughs.test.sh`: next to `t_pto_7_default_is_300_and_job_ceiling_covers_it`, add a test
    function (registered wherever the `t_pto_*` functions are invoked) that reads the workflow comment-stripped and
    asserts `pull-requests: read` is present under the top-level `permissions:` and that no job-level
    `permissions:` key exists; plus the harness rows (a temp copy with the line removed must FAIL; a temp copy with
    the scopes reordered must PASS). Follow the grep-the-workflow pattern of
    `scripts/watch-shard-balance-11564.test.sh` (comment-stripped `wf`, `wf_missing` accumulator).
5.3 No change to `scripts/sweep-followthroughs.sh` (the exit-code contract is the documented fact, not a defect).

### Phase 6 — Verify, then ship through the normal flow

6.1 Local, read-only checks: `bash scripts/sweep-followthroughs.test.sh`; the replay suite OW section first
    (`--rows` range covering the OW rows, or the OW-only driver), then ONE full run at the end;
    `python3 -I scripts/ci-pr-affected-replay.py ratchet --report /tmp/...` (or the scratchpad) must report
    live == baseline with no new pair (the edit set above adds none); `bash plugins/soleur/test/c4-count-parity.test.sh`;
    `bash plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh --branch`; markdownlint on the touched docs.
6.2 PR title `ci: re-rule observation-window wall ceilings to 240/285 and guard the s4-drain floor (Ref #10865)`;
    body contains only `Ref #10865`, `Ref #10861`, `Ref #10448`. PR body carries: the floor-mismatch finding with
    the evidence and "unproven empirically under a GITHUB_TOKEN"; the exit-code table (0, 2, 3); the sentence that
    the replay test is an oracle input, so this PR is excluded from the window counts but does NOT restart it
    (not a drain PR, no `s4-drain` label); the sentence that the `affected-index-ratchet` state on main must be
    green or explained before merge (state at planning time: green); the post-merge check: the first scheduled or
    dispatched sweeper output must print `floor=s4-drain` and `window opened=2026-10-26T21:59:35Z`, and an exit 3
    naming the sentinel means the permission did not take effect; and the rendered `decision-challenges.md` rows.
6.3 Nothing is posted to #10865 by this PR or by the agent; posting needs a fresh explicit operator go.

## Files to Edit

- `scripts/followthroughs/ratchet-observation-window-10865.sh` — constants, header (d), RESTART FLOOR clause, sentinel.
- `plugins/soleur/test/ci-pr-affected-replay.test.sh` — rows, fixtures, titles, static pin, `row_ow_timeout`, sentinel stub + rows + mutants.
- `.github/workflows/scheduled-followthrough-sweeper.yml` — `pull-requests: read`.
- `scripts/sweep-followthroughs.test.sh` — permission pin (+ harness rows).
- `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md` — ceiling mentions, floor sentence, dated rows.
- `knowledge-base/engineering/architecture/decisions/ADR-276-demand-first-hosted-runner-budget-merge-group-is-the-full-battery-authority.md` — appended amendment.

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-10865-ceiling-rerule/decision-challenges.md` — D1, D2 rows.
- `knowledge-base/project/specs/feat-one-shot-10865-ceiling-rerule/tasks.md` — derived task list.

Not touched (verified list): `scripts/ci-pr-affected-audit.baseline.tsv`, `scripts/ci-pr-affected-audit.accept.tsv`,
`.github/workflows/ci.yml`, `scripts/test-all.sh`, `scripts/lib/test-affected-paths.sh`, `scripts/ci-pr-affected-replay.py`,
`scripts/sweep-followthroughs.sh`, `plugins/soleur/scripts/lint-ratchet.py`.

## Open Code-Review Overlap

Queried open `code-review` issues for every planned file path (`gh issue list --label code-review --state open --json number,title,body`, then `jq --arg path ... contains($path)` per file). Result recorded at work time; the planner expectation is None. If a match appears: fold in / acknowledge / defer with a one-line rationale in the PR body.

## Scope-Safe Negative Checks

- `git diff --stat origin/main -- scripts/ci-pr-affected-audit.baseline.tsv` is empty.
- `git diff origin/main -- scripts/followthroughs/ratchet-observation-window-10865.sh` shows `SOAK_BUDGET_S:-270`, `TIMEOUT_WALL=290` and the three failure/PASS strings unchanged.
- No `Closes`/`Fixes`/`Resolves` in any commit message or the PR body.

## Acceptance Criteria

<!-- founder-stated check: see plan-founder-check.md -->

### Pre-merge (PR)

- [ ] `grep -n -E '^P95_MAX=240 |^MAX_MAX=285 ' scripts/followthroughs/ratchet-observation-window-10865.sh` prints exactly 2 lines; `grep -c -E '^P95_MAX=210|^MAX_MAX=270' ...` prints 0.
- [ ] `git grep -n -E 'SOAK_BUDGET_S:-270|TIMEOUT_WALL=290|budget_s=270'` shows the same 3 sites as Phase 0; the failure-message and PASS-echo lines are byte-identical to `origin/main`.
- [ ] The header around criterion (d) states 240/285, keeps the phrase `ceilings are PROVISIONAL`, and cites the 2026-11-02 re-rule.
- [ ] Replay suite: the four rows (`row_ow_slow` 250/240, `row_ow_max` 288/285, `row_ow_timeout` 300/285, `row_ow_static` pins), both titles, both fixtures updated; `grep -n -E 'over 210|over 270|P95_MAX=210|MAX_MAX=270' plugins/soleur/test/ci-pr-affected-replay.test.sh` prints nothing.
- [ ] Sentinel: probe code, replay rows (trip, older list, applied, unmerged, errors) and 5 sentinel mutants plus 2 ceiling mutants, each landing exactly once, all green (the replay suite and `scripts/sweep-followthroughs.test.sh`).
- [ ] The new rows are RED against the pre-change probe (`git show origin/main:scripts/followthroughs/ratchet-observation-window-10865.sh`), recorded in the PR body.
- [ ] `.github/workflows/scheduled-followthrough-sweeper.yml` has `pull-requests: read` and its pin passes; removing the line turns the pin RED.
- [ ] Runbook: lines for the ceilings updated; dated 2026-11-02 row carries every figure in the brief (372 jobs; p95 218 s overall, 225 s since 2026-10-31; `merge_group` 212 s, `pull_request` 225 s; max 284 s; 2 of 372 over 270 s; daily p95 206, 207, 201, 206, 215, 222, 237 s; versus oldest-260 p95 203-205 s).
- [ ] ADR-276: new dated amendment appended; `git diff` shows item 6 and every earlier line unmodified (additions only).
- [ ] `decision-challenges.md` D1 and D2 rows pass `technical-ruling-gate.sh --branch`.
- [ ] `python3 -I scripts/ci-pr-affected-replay.py ratchet` reports live == baseline (no new pair); `scripts/ci-pr-affected-audit.baseline.tsv` byte-identical to `origin/main`.
- [ ] State of `affected-index-ratchet` on main re-read at merge time: green, or explained in the PR body (a red unit pauses the window and blocks a PASS; it does not block this merge).
- [ ] PR body: `Ref #10865`, `Ref #10861`, `Ref #10448` only; exit-code table (0 closes the tracker, 2 NOT YET comment, 3 CANNOT ESTABLISH comment); floor evidence flagged as unproven under a `GITHUB_TOKEN`; oracle-input note (excluded from counts, window not restarted); post-merge `floor=s4-drain` check.

### Post-merge (operator-visible, no new action required)

- [ ] The first sweeper output after merge (scheduled 18:00 UTC or any dispatch) prints `floor=s4-drain` with `window opened=2026-10-26T21:59:35Z`, or exit 3 naming the sentinel. Exit 2 with `floor=pr3a` after this PR is impossible by construction. Recorded by the daily sweeper comment; no one runs the probe by hand.

## Test Scenarios

- Given 250 s on every unit, when the probe runs, then exit 2 with `NOT YET: wall p95 250s is over 240 s (PROVISIONAL ceiling; ...)` and no max line (unit).
- Given 40 units at 150 s and one at 288 s, then exit 2 with `wall max 288s is over 285 s` and no `wall p95` line (unit).
- Given one unit killed at 300 s, then `wall max 300s is over 285` appears with `exit 2 never rerun on run(s) 5006` (unit).
- Given the label list is `[]` and `pulls/11226` is merged, then exit 3 with the fixed sentinel line and no `ci.yml/runs` request (unit, request-order observed inside the window).
- Given the label list holds only #11131 (older) and the sentinel is merged, then exit 3 (unit).
- Given the list maximum equals the sentinel's `merged_at`, then the floor applies (`floor=s4-drain`) and the verdict is the normal one (unit).
- Given the sentinel is unmerged (`merged_at` null) and the list empty, then the verdict is unchanged from today (unit).
- Given the sentinel read returns 404/403/502/junk/non-object, then exit 3, one fixed line (unit).
- Given the workflow with `pull-requests: read` removed, commented out, set to none, or overridden at job level, then the pin FAILS (unit).
- Regression: the full OW battery (`row_ow_*`, `ow_mutate` mutants) stays green; `row_ow_read_only` shows no `STUB-MISS`.

## Risks and Sharp Edges

- **Replay suite runtime.** A full run is 10-45 minutes under load. Iterate on the OW rows; run the full suite once; do not read a killed run as a pass. Run mutant batteries under `timeout`.
- **Mutant anchors go stale** the moment a probe line they anchor is edited. After Phase 1, grep every `^ow_mutate` old string against the probe before any full run.
- **No new suite-to-path pair.** Adding a workflow path to the replay suite would add a ratchet pair; keep that pin in `scripts/sweep-followthroughs.test.sh`, and run the local ratchet before pushing. If a pair appears anyway, fix by removing the mention, never by editing the baseline or adding an accept row in this non-drain PR.
- **The 237 s daily p95 on 2026-11-02 is within 3 s of the new 240 s p95 ceiling.** The ceiling is correct for the whole-population series (218 s) but a PASS-capable sweep that reads a drifted prefix could still print p95 over 240. That is the CTO's recheck trigger, written into the runbook row; it is not another re-rule.
- **The floor cause is documented, not reproduced.** Say so in the PR body. If the first post-merge sweep prints exit 3 naming the sentinel, the permission scope did not take effect, and the sentinel did its job.
- **The sentinel number is a hard-coded PR (#11226)** and is retired with the probe when #10865 closes (the probe's RETIREMENT header already says delete the file and its suite rows).
- **A plan whose `## User-Brand Impact` is empty or placeholder text fails `deepen-plan` Phase 4.6**; this plan fills it (threshold `none` with the scope-out line).
- **Do not use `git stash`** in this worktree; for the pre-change comparison use `git show origin/main:<path>` into the scratchpad.
