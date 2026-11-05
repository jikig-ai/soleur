---
title: "feat: Resolve the boundary-prefix swept-scope deferred item on #10448 before the CI_PR_AFFECTED flip"
type: feat
date: 2026-11-05
slug: feat-boundary-prefix-deferred-item
branch: feat-one-shot-10448-boundary-prefix-deferred
issue: 10448
lane: cross-domain
---

# Resolve the boundary-prefix swept-scope deferred item on #10448

The #10861 drain series ended at strict zero (PR5z merged `3b95267fac`), and its
PR5d slice left exactly one named deferred item, recorded on #10448 and gated to
resolve before the `CI_PR_AFFECTED` activation flip: swept-scope `glob:` coverage
for `plugins/soleur/test/boundary-prefix.test.sh`. This PR resolves it — by the
CTO-ruled arm — and performs two bounded evidence steps: re-run the #10865
observation-window probe and post the measurement, and verify the remaining
#10859 entry conditions. The required-context flip itself is out of scope;
#10859 stays held for the budget owner.

## Research Insights

### Premise Validation

Checked 2026-11-05 against live state:

- **#10448** OPEN; the deferred item is mirrored verbatim in the issue comment of
  2026-11-05T00:03Z (PR5d mirror) and re-stated in the PR5z mirror of
  2026-11-05T16:42Z ("the boundary-prefix deferred item above still gates
  `CI_PR_AFFECTED`"). Held.
- **#10859** OPEN, held for the budget owner ("merging this changes the merge
  gate for every PR"). **#10865** OPEN; window restarted at the #12116 merge
  (2026-11-05T01:27:24Z). **#12129** OPEN money decision (ratchet p95 breached
  240 s twice — accept spend or roll back; option 1 notes closing it satisfies a
  PR3b entry condition). **#12149** OPEN, same subsystem, disjoint edit surface
  (`affected-tests.sh`/`test-all.sh`). **#12155** OPEN PR3b-lite proposal —
  context only. **PR #12199** OPEN draft, this branch.
- Cited files all exist on this branch:
  `scripts/followthroughs/ratchet-observation-window-10865.sh`,
  `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md`
  (§7 drain rubric + observation log), the PR5d archive spec dir
  `knowledge-base/project/specs/archive/20261105-010239-feat-one-shot-10861-pr5d-sweeps/`
  (`decision-challenges.md` rows 9–11, `receipts/glob-rate/glob-rate.tsv`,
  `receipts/pairs-decisions.tsv`, `receipts/rows-post-edit.txt`).
- Collision precheck on #10448: only this branch's draft PR #12199 names the
  issue; foreign `proc.sh` hits are sibling worktrees' `test-all.sh` runs, not
  this work.
- **Stale premise found and corrected:** the deferred item is often quoted as
  needing only an amendment to the >25% bar. `glob_decide`
  (`scripts/ci-pr-affected-replay.py`) shows TWO disqualifiers, not one: the
  suite's duration row is `src=floor` (`scripts/suite-durations.tsv:175` —
  the 1222 ms value is the generated `default-weight` placeholder, not a
  measurement), and `src != "measured"` returns `baselined`/`duration-floor`
  before the rate is even compared. Any install arm must first obtain a
  `measured` duration row; IF the real duration lands ≤10 s, the measured
  ~48% rate makes the policy's own verdict `always_on`, not `glob` — a third
  mechanical arm the deferral text did not name (if >10 s and >25%, the
  verdict stays `baselined` and only the amendment or accepted-gap arms
  remain).

### Property List (mechanism-minimality restatement)

1. The #10448 deferred item has a recorded resolution: a ruling choosing
   install or accepted-gap, persisted where rulings live, before the
   `CI_PR_AFFECTED` flip.
2. If install is ruled: the suite's selector coverage reflects what it actually
   reads (the four dir globs), the installed form conforms to the
   `glob_decide` policy as (possibly amended), and the 7 named pairs'
   dispositions stay valid (deferred-item AC 6).
3. If accepted-gap is ruled: the unnamed-swept-file residual is written down
   as the audit's documented lower bound in the runbook (the audit's
   `DECLARED LIMITS` already covers directory/glob reads generically) and
   mirrored on #10448.
4. #10865 carries a current measurement of the restarted window (evidence
   hygiene; the p95 read feeds the #12129 money decision).
5. #10859's entry conditions 2–3 carry a verified status (rename-carry design,
   jobs-API canary) without touching the flip.

### Cut List

- No new scripts, guards, workflow surfaces, or probe changes — the existing
  probe, runbook, accept-file and mirror conventions cover every property.
- No `DECLARED LIMITS` text edit unless the ruling lands arm (b) and the CTO
  wants the suite named there — the generic "directory and glob reads are not
  modelled" line already binds.
- No re-run of `glob-rate` at plan time — the PR5d receipt
  (`receipts/glob-rate/glob-rate.tsv`) already measured it on a recorded
  `origin/main` SHA; the work phase re-measures only if install is ruled
  (policy: measurements at work time, never from an earlier PR).

### Relevant files

- `plugins/soleur/test/boundary-prefix.test.sh` — the suite; its scan loop
  (`for f in "$HOOKS_DIR"/*.sh "$HOOKS_DIR"/lib/*.sh "$SCRIPTS_DIR"/*.sh
  "$SCRIPTS_DIR"/lib/*.sh`, ~line 285) is the swept scope: 4 dir globs, ~164
  files.
- `scripts/lib/test-affected-paths.sh` — `AFFECTED_*_PATHS` edge declarations;
  the suite's current set is ~14 exact files + `^glob:.claude/hooks/*guardrails*.sh`
  (PR5d `receipts/rows-post-edit.txt` line 381).
- `scripts/ci-pr-affected-replay.py` — `glob_decide` encodes PR4b row 6
  (`GLOB_MAX_MS=60000`, `GLOB_ALWAYS_POLICY_MS=30000`,
  `GLOB_ALWAYS_MAX_MS=10000`); `DECLARED LIMITS` documents that directory and
  glob reads are not modelled.
- `scripts/suite-durations.tsv` — row 175: `plugins/soleur/test/boundary-prefix.test.sh
  1222 floor` (generated by `regenerate-shard-manifest.py`; a `measured` row
  requires real timing data).
- `scripts/ci-pr-affected-audit.accept.tsv` — 13 anchor-keyed accept rows
  covering the 7 named pairs (lines ~866–878).
- `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md`
  §7 — drain rubric (incl. the measured-verdict paragraph), observation log,
  PR3b entry-condition paragraph.
- `knowledge-base/project/specs/archive/20261105-010239-feat-one-shot-10861-pr5d-sweeps/decision-challenges.md`
  — the deferral ruling (row 10) and its six ACs.

### Related issues / PRs

#10448 (work target), #10859 (held PR3b), #10865 (soak tracker), #10861 (drain,
DONE), #12129 (money decision — p95 breach), #12149 (overlapping subsystem),
#12155 (PR3b-lite context), #12150/#12128 (in-flight ratchet repairs pausing
the window).

### Institutional learnings applied

- Measurements at work time on a recorded `origin/main` SHA, never from an
  earlier PR (runbook §7 whole-tree/glob reader rule).
- "A mention is not declared" / anchor-keyed accept rows (drain rubric).
- Deferred items get a named follow-up and resolve before the gate they block —
  this plan IS that follow-up.

## Research Reconciliation — Spec vs. Codebase

| Spec/brief claim | Reality on this branch | Plan response |
|---|---|---|
| "Amend the >25% bar, then install glob: edges" (arm a as briefed) | `glob_decide` rejects `floor` durations before the rate check; even measured, 48% fails 25%; the policy verdict at ~1.2 s would be `always_on` | Plan carries arm (a') alongside (a)/(b); CTO rules with this evidence |
| "the 7 named pairs take individual dispositions" | Done in PR5d — all 7 dispositioned `mention` with 13 anchor-keyed accept rows (`accept.tsv` ~866–878); the 3 flagged real-read candidates were ruled mentions on static evidence (PR5d decision-challenges row 11) | Reconciliation step verifies rows still live (`stale-accept` clean), does not re-disposition |
| "argv-bearer-sweep whole-tree census coverage is the same-class documented residual" | Its `glob-rate` verdict is `baselined`/`rate-over-and-duration-over-30s` (47 s, 94/151) — residual exists but is only implicitly documented (receipt + mirror line) | Accepted-gap arm documents both residuals in one runbook paragraph |

## User-Brand Impact

- **If this lands broken, the user experiences:** an incorrectly resolved
  selection-policy residual — either the suite runs on ~half of all PRs without
  a ruled basis, or an undocumented audit blind spot persists into activation.
  The artifact is CI correctness, not a user-facing surface.
- **If this leaks, the user's [data / workflow / money] is exposed via:**
  misdirected CI spend (an `always_on`/`glob:` edge that selects too hot adds
  suite-run minutes to every PR) — bounded at the suite's real duration per
  affected run (unmeasured; floor placeholder 1222 ms).
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** internal CI/test-index tooling and
  docs only; no sensitive-path diff (preflight Check 6 regex matches none of
  the planned files), no regulated-data surface, no user-visible artifact.

## Implementation Phases

### Phase 0 — CTO ruling on the resolution arm (blocking first step)

Spawn `soleur:engineering:cto` ("Rule on this technical question (BINDING). Do
NOT use AskUserQuestion.") with the evidence packet:

- PR5d deferral ruling + ACs (`specs/archive/20261105-010239-...-pr5d-sweeps/decision-challenges.md` row 10);
- measured data (`receipts/glob-rate/glob-rate.tsv`): `duration_ms=1222 src=floor`, `rate_conservative=97/200`, `rate_excluded=48/151`, verdict `baselined`/`duration-floor`;
- the code facts: `glob_decide` needs `src=measured` before ANY verdict;
  `always_on` needs `measured` ≤10 s effective and >25%; the suite's 1222 ms
  row is the generated `default-weight` floor placeholder (real runtime
  unmeasured — 4 dir-glob awk scans over ~164 files could exceed 10 s, which
  would rule arm a' out entirely); `ALWAYS_ON_SUITES` in `scripts/test-all.sh`
  is the policy's own >25% answer;
- arms: **(a)** amend PR4b row 6 (>25% bar and/or the `measured`-only rule)
  then install `glob:`/`dir/` edges for the 4 dir globs (~164 files);
  **(a')** obtain a `measured` duration row (time the suite, regenerate the
  durations table via `regenerate-shard-manifest.py`), re-run `glob-rate` per
  the runbook measured-verdict procedure, install the verdict the policy
  returns (expected `always_on` — itself a selection-policy call the CTO must
  bless); **(b)** explicit accepted-gap: document the unnamed-swept-file
  residual as the audit's lower bound in the runbook (+ optionally a suite-named
  line near `DECLARED LIMITS`), mirror on #10448.

Disqualifying facts per arm, for the brief (a binding ruling needs the case
against, not only the case for):

- **(a)** the measured ~48% selection rate is roughly double the ruled 25%
  bar — the amendment widens a CTO-ruled constant for a ~half-of-PRs edge;
  and a `floor` duration means the amendment alone still cannot yield a
  `glob` verdict without also relaxing the `measured`-only rule.
- **(a')** an `ALWAYS_ON_SUITES` entry runs the suite on every `pull_request`
  and `merge_group` (~1.2 s per run, real cost on docs-only PRs); the
  runbook reserves `always_on` from drain PRs and PR5z is the only measured-
  verdict precedent; the measured duration could exceed the 10 s fast-tier
  cap and invalidate the whole arm.
- **(b)** leaves the audit's literal-name reach blind to every path named
  inside ~164 swept files — a new `.sh` under `.claude/hooks/` or
  `plugins/soleur/scripts/` that names a tracked path produces a pair the
  audit never sees (no `new-pair` red) and a change to such a file does not
  select the suite (no run); the residual persists into activation.

Record the ruling verbatim in `specs/feat-one-shot-10448-boundary-prefix-deferred/decision-challenges.md`
(replacing the `pending - assumed` row) and proceed on the ruled arm.

### Phase 1a — Accepted-gap arm (only if ruled)

1. Edit runbook §7 (drain rubric / residual paragraph): name the residual —
   `boundary-prefix.test.sh`'s four dir globs (~164 files under `.claude/hooks/`
   and `plugins/soleur/scripts/`) and the argv-bearer-sweep whole-tree census —
   as the audit's documented lower bound, with the measured rates/durations and
   the one-line reason (selection policy / duration class), pointing at
   `DECLARED LIMITS` for the mechanism.
2. Post the resolution comment on #10448 naming the ruling, the residual, and
   that the deferred item is resolved (arm b).
3. Verify: `python3 -I scripts/ci-pr-affected-replay.py ratchet` still
   `exit=0 reason=pass live=0` locally; no edge/accept change.

### Phase 1b — Install arm (only if ruled)

1. Obtain a `measured` duration row for the suite (timed runs →
   `regenerate-shard-manifest.py` → `scripts/suite-durations.tsv` src
   `measured`); if arm (a) amends the bar, land the `glob_decide` constant
   change + runbook amendment text in the same commit with the ruling quoted.
2. Re-measure at work time per the runbook: record `origin/main` SHA, save
   `rows.txt`, run `glob-rate --candidates <4 dir-glob entries> --pairs
   <7-pair file> --commits 200 --base <sha> --spot-check 3`.
3. Install per the measured verdict: `glob:`/`dir/` entries or an
   `ALWAYS_ON_SUITES` entry in `scripts/lib/test-affected-paths.sh` /
   `scripts/test-all.sh` as the ruling directs; reconcile the 7 pairs'
   dispositions (accept rows stay unless the installed edge changes the
   pairs' staleness; re-run the audit for `stale-accept`).
4. Verify: ratchet `exit=0`, `scripts/test-affected-kb-consumers.test.sh`,
   `scripts/test-all-fast-tier-budget.test.sh` (if `always_on`), local selector
   spot check on a `.claude/hooks/` diff selecting the suite. Editing
   `scripts/lib/test-affected-paths.sh` is a runner change: the local
   `--affected` gate degrades to the full battery and queues behind sibling
   worktree runs — let the full gate run detached (runbook §7 drain-rubric
   note).
5. Post the resolution comment on #10448 (arm a/a', with the measured numbers).

### Phase 2 — Observation-window probe + post to #10865

Re-run the probe read-only at work time and post the current measurement
(status line + `NOT YET` lines verbatim) as a comment on #10865. Probe only —
no flip work. Session-measured baseline (2026-11-05): `units=115
wall_p95_s=269 wall_max_s=279`, paused on red merge_group run 42084778935
(`exit=1 new-pair`), no bot PR yet, p95 over the 240 s ruled ceiling — a
further whole-population breach data point that also belongs on #12129's
evidence trail (posting there is optional, one line).

### Phase 3 — #10859 entry-condition verification (status only)

Verify and post a dated status comment on #10859:

- (1) window: OPEN, restarted 2026-11-05T01:27:24Z — from the Phase-2 probe.
- (2) ruled rename-carry design: **unmet and stale** — no ruled design exists
  (repo grep, 2026-11-05); its ruled precondition ("a pair already in the base
  baseline") is empty-set under strict zero since PR5z deleted the baseline;
  flag for re-rule or dissolution (CTO call, recorded in decision-challenges).
- (3) failing-`continue-on-error` jobs-API canary: **met** — 2026-10-23 canary
  (PR #10899, run 39937846319, job concluded `failure`, annotations
  `exit=1 reason=new-pair`), recorded in the runbook observation log.
- ADR-276 item-9 remainder for the owner's awareness: oracle control (a),
  accept-row growth design (b), cumulative baseline check at merge time (c —
  trivially satisfiable post-strict-zero; a re-added baseline is
  `baseline-reintroduced`), re-ruled ceilings (e — DONE 240/285), budget-owner
  go-ahead (f).

## Files to Edit

- `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md` — §7 residual/amendment record + observation-log note (always)
- `knowledge-base/project/specs/feat-one-shot-10448-boundary-prefix-deferred/decision-challenges.md` — record the CTO ruling (always)
- `scripts/lib/test-affected-paths.sh` — install arm only: swept-scope edges
- `scripts/test-all.sh` — install arm only, if the ruling lands `always_on`
- `scripts/suite-durations.tsv` — install arm only: regenerate for `measured` row
- `scripts/ci-pr-affected-replay.py` — install arm (a) only: `glob_decide` constant amendment as ruled
- `scripts/ci-pr-affected-audit.accept.tsv` — install arm only, only if re-audit surfaces `stale-accept`

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-10448-boundary-prefix-deferred/tasks.md` — task breakdown (this pipeline)

External writes (not files): comments on #10448 (resolution mirror), #10865
(probe measurement), #10859 (entry-condition status).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Also resolve the boundary-prefix deferred item on #10448 BEFORE the CI_PR_AFFECTED flip." | Phase 0 + Phase 1a/1b | mapped |
| 2 | "a step to re-run the observation-window probe and post the current measurement to #10865 (probe only — the required-context flip itself is OUT OF SCOPE this PR: merge stays held for the budget owner and the window has not reached its trigger)" | Phase 2 | mapped |
| 3 | "what remains of #10859 entry conditions 2-3 (rename-carry design, jobs-API canary) — verify status, do not implement the flip" | Phase 3 | mapped |
| 4 | "Resolution means ONE of: (a) install-under-amendment ... OR (b) an explicit accepted-gap ruling" | Phase 0 ruling arms; arm (a') surfaced by premise validation as a policy-native third option for the CTO | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Phase 0 CTO ruling | "the install-under-amendment vs accepted-gap choice IS a technical ruling ... spawn the CTO to rule it during planning if you can spawn subagents ... If you cannot spawn, record `pending - assumed`" | asked |
| Arm (a') measured-verdict path | — | inferred — justification: premise validation found `glob_decide` rejects `floor` durations before the rate check, so arm (a)'s glob: install is unreachable without a measured row, at which point the policy's own verdict is `always_on`; suppressing it would hand the CTO an incomplete option set |
| Phase 2 probe + #10865 comment | "a step to re-run the observation-window probe and post the current measurement to #10865" | asked |
| Phase 3 #10859 status comment | "verify status, do not implement the flip" | asked |
| #12129 one-line evidence note (optional) | — | inferred — justification: the Phase-2 probe produces the whole-population p95 the #12129 money decision explicitly waits on; one line costs nothing and the issue asks for exactly this data |

### Split Assessment

- Subsystems touched: 3 — `scripts/`, `knowledge-base/`, `plugins/soleur/` (arm-dependent; arm (b) touches only `knowledge-base/` + one `scripts/` none)
- Planned files: 7 (2 always, 5 conditional on install arm) | Estimated changed lines: ~80 (accepted-gap) to ~250 (install)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] The `pending - assumed` technical row in `decision-challenges.md` is replaced by a verbatim CTO ruling choosing an arm (a, a', or b), dated, with rationale
- [ ] Exactly one arm is implemented; the deferred item is resolved by that arm's definition (installed coverage conforming to `glob_decide` as ruled, or a written accepted-gap residual in runbook §7)
- [ ] A resolution comment on #10448 names the ruling and closes out the deferred item's AC (5) ("deferred decision resolves before the CI_PR_AFFECTED flip")
- [ ] `python3 -I scripts/ci-pr-affected-replay.py ratchet` on the branch reports `exit=0 reason=pass live=0` (strict zero preserved; no baseline line, no stale accept)
- [ ] If install arm: the measured `glob-rate` receipt is committed under `knowledge-base/project/specs/feat-one-shot-10448-boundary-prefix-deferred/receipts/` and the 7 named pairs' accept rows remain valid or are reconciled in the same commit
- [ ] A comment on #10865 posts the work-time probe output (status line + `NOT YET` lines verbatim); no flip change accompanies it
- [ ] A dated status comment on #10859 records: window open/paused; rename-carry design unmet and stale under strict zero (flagged for re-rule or dissolution); canary met per the 2026-10-23 observation-log entry
- [ ] `continue-on-error: true` on `affected-index-ratchet`, `scripts/required-checks.txt`, `CI_PR_AFFECTED`, and the activation lock are all untouched
- [ ] The 7 named pairs' individual dispositions and the `^glob:.claude/hooks/*guardrails*.sh` edge remain installed (deferred-item AC 6)

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — CI/test-index tooling and
documentation change on an internal selection-policy residual. No UI-surface
file in Files to Edit/Create (mechanical override did not fire); Product/UX
tier NONE. No regulated-data surface, no infrastructure provisioning, no
artifact distribution surface (GitHub issue comments on an existing tracker,
not a new distribution channel) — GDPR gate skipped per Phase 2.7.

## Open Code-Review Overlap

- `#7942` (*Two mutation batteries in plugins/soleur/test/ are named *.mutation.sh and run in no gate*) mentions `scripts/test-all.sh`, which the install arm may touch for an `ALWAYS_ON_SUITES` entry. **Disposition: acknowledge** — unrelated concern (mutation-battery gate wiring); a one-line `always_on` entry does not interact with it.
- Open PR **#12149** (`feat-one-shot-12013-affected-gate-lock-chain`) touches `affected-tests.sh`/`test-all.sh` — same subsystem, disjoint hunks vs. this plan's conditional `ALWAYS_ON_SUITES` addition; noted for merge-order awareness.

## Test Scenarios

- Given the accepted-gap arm, when `python3 -I scripts/ci-pr-affected-replay.py ratchet` runs on the branch, then `SOLEUR_PR_AFFECTED_RATCHET exit=0 reason=pass live=0` (integration)
- Given the install arm, when `git diff` names a file under `.claude/hooks/` not previously covered, then `bash scripts/test-all.sh --print-selection --paths=<file>` prints the suite's `AFFECTED_SELECTED` row with selected `1` (integration)
- Given the install arm, when `glob-rate` re-runs on a recorded `origin/main` SHA with the 4 dir-glob candidates, then the `verdict` column for the suite is `glob` or `always_on` per the ruled arm, and the receipt lands under `specs/<branch>/receipts/` (integration)
- Given either arm, when `python3 -I scripts/ci-pr-affected-replay.py audit` runs, then `stale=0` for the 13 boundary-prefix accept rows (integration)
- Given the Phase-2 probe run, when the comment lands on #10865, then it contains the literal status line `window opened=... units=... wall_p95_s=...` and every `NOT YET:` line the probe printed (manual/integration)

## Alternative Approaches Considered

| Approach | Why not chosen as default |
|---|---|
| Install the swept-scope edges without a ruling (arm a/a' unilaterally) | The deferral ruling reserves the selection-policy call to the CTO; a ~48%-selecting edge or an `always_on` entry doubles the ruled 25% bar or adds an always-on suite — both need the ruling |
| Amend `DECLARED LIMITS` instead of the runbook | `DECLARED LIMITS` already states directory/glob reads are not modelled; the residual is suite-specific, and the runbook is the operated surface that points at it |
| Wait for the window to advance before posting | Posting now keeps #10865 evidence current and feeds #12129; the probe is read-only and cheap (~110 s, 187 quota units measured) |
| Defer the rename-carry status to the PR3b PR | The condition's ruled precondition is empty-set post-strict-zero; surfacing staleness now lets the owner re-rule before the window passes, not after |

## Non-Goals

- The `CI_PR_AFFECTED` activation flip and every PR3b file change (required-checks.txt, canonical JSON, `infra/github`, count pin, fixtures, ledger) — #10859 stays held for the budget owner.
- Implementing or ruling the rename-carry design, accept-row growth design, or oracle control — status recording only.
- Any edit to `plugins/soleur/test/boundary-prefix.test.sh` itself, the accept file, or the edge set under arm (b).
- Merging anything that changes the merge gate.
