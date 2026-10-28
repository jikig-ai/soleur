---
title: "feat: P4d bounded wait, then CI is the gate, on a refused local battery (rc=4)"
date: 2026-10-28
slug: p4d-bounded-wait-on-battery-refusal
branch: feat-one-shot-9757-p4d-rc4-bounded-wait
issue: 10924
type: feat
priority: p3
domain: engineering
brand_survival_threshold: none
lane: single-domain
---

# feat: P4d bounded wait, then CI is the gate, on a refused local battery (rc=4)

## Enhancement Summary

**Deepened on:** 2026-10-28
**Method:** halt gates 4.6-4.13 run mechanically; citation, attribution and byte-budget claims re-verified live; no 40-agent fan-out (the plan already carries a CTO ruling set F1-F7, G1-G2, H1-H3, a 3-seat plan-review panel, a learnings sweep, a repo-research pass and a registry overlap check, and the change is one bash script plus prose).
**Halt gates:** 4.6 User-Brand Impact present, threshold `none` with a scope-out reason and no sensitive-path file in the lists (pass); 4.7 Observability present, five fields, `discoverability_test.command` starts with `bash`, no ssh, finishes well inside 15 s, `expected_output` is the literal `class=not-waitable` (pass); 4.8 no PAT-shaped variable (pass); 4.9 no UI surface (skip); 4.10 no persistent store or new connection (skip); 4.11 `lint-guard-contract.py` green, Assembly names the chokepoint rather than today's members, matrix derived from the design (pass); 4.12 one unfenced Scope Check, three sub-sections, no `unmapped`/`BLOCKED` (pass); 4.13 no new autonomous-task surface (skip).

### Key Improvements
1. SKILL.md byte plan is now measured, not asserted: the two contention paragraphs (`ship/SKILL.md` lines 467-472 and 474) are about 1.7 KB; the replacement pointer that keeps the queue-in-lock command is about 0.9 KB, so net is roughly -0.7 KB against a 65-byte headroom. No test pins either paragraph (grep of `plugins/soleur/test`, `plugins/soleur/skills/*/test`, `.claude/hooks` for `TC_RUNTIME_CEILING_S`, `measured_runs=0`, "Under contention, wait" finds none).
2. Citation corrections: ADR-292 (not ADR-262) owns the affected-tests rc contract; PR #8135 / #8354 are the shipping sessions ship `SKILL.md` records the observations from; the sanitize helper lives at `plugins/soleur/scripts/lib/context-sanitize.sh`.
3. Live verification of every number cited: #10924 OPEN, #9757 OPEN, #6480 OPEN, #8800 OPEN, draft PR #11390 is this branch, ADR-133/196/262/292 files exist, the sibling-refusal line exists once on `origin/main` in `scripts/test-all.sh` and is pinned by `fanout-suite-scope.test.sh`, `battery-owed.sh` currently returns OWED (rc 0) on this branch.

### New Considerations Discovered
- `battery-owed.sh` returning OWED on a pre-push branch means the first Phase 4 run always happens locally, so the contended-start path this PR bounds is the normal first-run path, not a rare re-run path.
- This session's own Phase 4 will probably hit the refusal (a foreign worktree's `test-all.sh` is live); the work phase should use the affected set directly and, if refused, the new script once it exists - and record the outcome honestly in the PR body.

Ref #9757. Ref #10924 (checklist item P4d). Never a closing keyword: both stay open; the P4d box is ticked after merge.

## Overview

`soleur:ship` Phase 4 runs a detached local battery (`affected-tests.sh`, which delegates `scripts/test-all.sh`).
When another worktree already runs a full-gate battery, the runner refuses with rc=4 ("REFUSED, nothing ran").
Today's recipe answers that with "go back to waiting" with no upper bound (ship `SKILL.md` records, from shipping PR #8135, two 3-hour Monitors that
still contended and, from PR #8354, a 110-minute zero-wait loop), then an hours-long queue-inside-the-lock escalation. P4d adds the missing
bounded exit: wait a fixed wall-clock budget for the sibling to drain, and if the budget ends first, print a
machine verdict that records "CI is the gate", add one honest line to the PR Test plan, and continue - except
when the diff touches the infra surface or the operator typed `--full`, where the local run is the sole blocking gate
(or was asked for by name) and the existing queue-in-lock path stays. The recipe becomes launch-first: a refusal
costs under a second, so the old up-front `measured_runs` loop (itself unbounded) goes away.

### Re-scope of the brief (read first)

The run brief says rc=4 is the per-PR monitor lock (`DUPLICATE MONITOR`). The read says otherwise, and the
CTO confirmed (Ruled by CTO agent, 2026-10-28; table in `decision-challenges.md`):

- #10924 defines P4d as "On a local battery refusal (rc=4)"; ship `SKILL.md` documents rc=4 as `test-all.sh`
  REFUSED (nothing ran) around the detached-battery recipe (not the monitor).
- The archived P4c plan names P4d "bounded wait on rc=4 battery refusal"; the P4c learning records the motivating
  incident (affected gate queued behind sibling runs, zero suites ran, recovery was recording CI as the gate).
- The monitor-lock rc=4 means "this PR is already watched": there is nothing to wait for and no gate to defer.
  P4c already documents that exit (`plugins/soleur/lib/harness.ts` "Exit 4 means the PR IS being watched",
  `drain-prs/SKILL.md` Phase 7 wait). This PR adds nothing there.

`harness.ts` and `drain-prs/SKILL.md` were checked as the brief asked: they document the monitor rc=4 only, so
they are unchanged (no battery text lives in them).

## Research Reconciliation - Spec vs. Codebase

| Spec / brief claim | Reality | Plan response |
|---|---|---|
| rc=4 is the per-PR monitor lock | rc=4 in the P4d definition is the battery refusal (`test-all.sh` rc 4 -> `affected-tests.sh` rc 4 `runner-refused`); monitor rc 4 is "already watched" | Scope = battery refusal; monitor files untouched (F1) |
| "wait a bounded time, then record CI is the gate and continue" for any rc=4 | rc=4 has six producers (`scripts/test-all.sh` header); only the sibling-run refusal clears with time; selection refusals mean a gutted index; SOLEUR_SUBAGENT is a declared env var | Only the sibling-run text is waitable; everything else stays stop-and-fix (F4, G1) |
| "CI is the gate" is always safe | ship `SKILL.md`: the local run is the sole BLOCKING gate for `apps/web-platform/infra/` (no required check runs that shard, #6480 open) | Infra diff never gets the deferral; after the budget it yields `QUEUE_IN_LOCK` (F5, G2) |
| Infra trigger is one prefix | The runner's predicate has two triggers: `apps/web-platform/infra/` and `.github/workflows/apply-web-platform-infra.yml`, and fails safe (assumes infra) on detection failure | The script mirrors both, fails closed, and a parity test pins the literals (G2) |
| Change the rc contract so the deferral is a runner code | `test-all.sh`/`affected-tests.sh` rc contracts have many consumers (lefthook, 3 ci.yml shards, grok-pre-push-gate, main-health-monitor); affected-tests rc 6 already means "budget expired, CI authoritative" | Neither script is edited (F2); the verdict lives in a new ship-side script |
| The sibling refusal fires on a default Phase 4 run | It fires only on an explicit `--full` or on an `--affected` run that DEGRADED to full (`AFFECTED_FALLBACK reason=...` in the log, `scripts/test-all.sh` ~4640 conjunct `_AFFECTED == 0 \|\| -n $_aff_fallback`); a plain affected run is exempt (SKILL.md ~488) | `AFFECTED_FALLBACK` is a companion line, not an exclusion; `--full` never defers (H1) |
| Reuse the runner's infra predicate instead of copying it | It is computed inline at the runner's top level (`_diff_names` assembly, ~2547-2590) and is not sourced or queryable; exposing it means editing `test-all.sh`, which F2 rules out | Mirror it (never narrower: same four `git diff` forms and untracked list, substring match) and pin the literals with a parity row |
| Use `affected-tests.sh` rc 6 as the signal | rc 6 means budget expired with a detected CI workflow, on a run that STARTED; a refusal ran nothing, and mapping it to 6 changes a contract with many consumers (F2) | New ship-side verdict script |
| New prose can go in `ship/SKILL.md` | Body ceiling 273955 vs current 273890 = 65 bytes of headroom (merge-base ratchet); review `SKILL.md` has 27 | Detail goes in a new `references/` file and a script; `SKILL.md` edit is net-negative |

## Research Insights

**Premise Validation.** #10924 OPEN with P4d unchecked, P4a (#11124), P4b (#11164), P4c (#11286) merged. #9757 OPEN.
Draft PR #11390 is this branch's own WIP. Collision pre-check reported only foreign `test-all.sh` processes of
another worktree (feat-one-shot-8628-inngest-4-upgrade), no PR or issue duplicate; the live foreign battery is
exactly the contention this item addresses. ADR corpus: ADR-196 (a full-gate refusal binds to a measured condition,
`rc=4` is the REFUSED class, point 6: "wait for the sibling, or re-run with the hatch" at the pipeline call site) and
ADR-133 (advisory lock) are consistent with a bounded wait; neither lists a bounded wait or CI deferral as a
rejected alternative. ADR-292 (plugin-generic affected test gate) owns the affected-tests rc contract including rc 6; ADR-262 (PR path gates for the mutation batteries) is unrelated to this change; no conflict.

**Property List.**
1. A contention-refused local battery never makes the pipeline wait without an upper bound.
2. After the bound, "CI is the gate" is recorded visibly (transcript verdict line plus one PR Test plan line) and
   Phase 4 continues; the record never claims a local pass.
3. Only a refusal that time can clear (sibling full-gate run in flight) is waitable; every other refusal, and any
   unrecognised log, keeps stop-and-fix.
4. A diff on the infra surface never receives the CI deferral (the local run is its only blocking gate).
5. The classifier and the infra predicate cannot drift silently from `scripts/test-all.sh`.

**Cut List.**
- New exit code / mapping in `scripts/test-all.sh` or `affected-tests.sh` -> property 1,2 -> already covered by the
  ship-side script; rc contracts have too many consumers (F2).
- A hook or gate that consumes the record -> property 2 -> CI `test` is already the required merge gate; the
  transcript line plus PR line suffice (F7).
- Any monitor-lock handling -> n/a -> P4c shipped it (F1).
- A file artifact for the record -> property 2 -> the verdict line and PR line are the record (F6).
- Env-var command seams (an injectable capacity command) -> test seam only -> an env-injected command is an
  authority grant; tests use PATH stubs and a scratch repo instead.
- Changing the queue-inside-lock escalation -> n/a -> kept as the infra path.

**Institutional learnings applied.**
- `2026-10-27-the-per-pr-monitor-lock-...` (P4c): the motivating incident; a stub's expected argv must be derived by
  running the SUT once; helpers called through `$(...)` must be stateless; a mutant counts as killed only when the
  targeted check returns the guard-failed code.
- `2026-08-19-the-budget-was-shorter-than-the-thing-it-was-waiting-for`: size the wait against the real hold time;
  a lapsed wait must not release a stampede -> the verdict is CI-is-the-gate, never "run unserialized".
- `2026-10-07-a-sync-that-defers-to-a-queue-needs-a-bounded-wait-...`: every wait branch needs an upper bound that
  falls back to the old behaviour; every unreadable answer falls toward the old path -> unreadable capacity keeps
  waiting until the budget, unreadable diff goes to `QUEUE_IN_LOCK`.
- `2026-09-11-the-shard-i-substituted-for-a-refused-gate-was-the-one-that-was-red`: when substituting for a refused
  gate pick suites from the diff's new vocabulary - noted in the reference file as the manual complement.
- `2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous...` / `2026-07-27-a-check-that-cannot-report-...`: the
  matrix below is written before the script and includes a dispatch row and a must-PASS row that is not the canonical.
- `2026-05-18-test-all-tail-masking...`: redirect the run to a log and capture rc; never pipe through `tail`.
- `2026-04-10-foreground-sleep-blocks-polling...`: waits run under the Monitor tool; no chained sleep.

**Community overlap.** Functional-discovery found nothing relevant in three registries; build in-repo.

## Open Code-Review Overlap

#8800 (test fixture: census sandbox shares inodes/symlinks with live repo) names `scripts/lib/test-affected-paths.sh`.
Acknowledge: this PR only appends one declaration array there; the fixture hazard is a different concern with its
own cycle. The issue stays open. No other open `code-review` issue names a planned file.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "when the local detached-battery run is refused with rc=4 ... wait a bounded time, then record \"CI is the gate\" and continue instead of stopping" | Phases 1-3: `battery-refusal-wait.sh`, reference, SKILL.md wiring | mapped |
| 2 | "Start from plugins/soleur/skills/ship/SKILL.md" | Phase 3 edits the rc=4 / contention paragraphs there | mapped |
| 3 | "Also check plugins/soleur/lib/harness.ts and plugins/soleur/skills/drain-prs/SKILL.md" | Re-scope section: checked, monitor-only text, unchanged | mapped |
| 4 | "start with a read and re-scope if needed" | Re-scope section + decision-challenges.md F1-F7, G1-G2 | mapped |
| 5 | "PR body uses `Ref #9757` and `Ref #10924` only" | Phase 5 (ship-time) AC | mapped |
| 6 | "plugins/soleur/skills/review/SKILL.md has only 27 bytes of body-budget headroom: put new prose elsewhere" | No review/SKILL.md edit; new prose in script header and references | mapped |
| 7 | "Keep apps/** and scripts/registry-restore-from-ghcr.sh unchanged" / "If the PR would edit .github/workflows/apply-web-platform-infra.yml, stop" | Files lists contain neither; AC asserts the diff stays clear | mapped |
| 8 | "Done means: PR merged, postmerge verified ..., the P4d box ticked in #10924, and a resume prompt emitted" | Phase 5 (ship, postmerge) and session close | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `battery-refusal-wait.sh` verdict script | "wait a bounded time, then record \"CI is the gate\"" | asked |
| Infra carve-out (`QUEUE_IN_LOCK`) | inferred: "CI is the gate" is unsafe where CI does not block (ship SKILL.md, #6480) | inferred - without it the deferral would delete the only blocking gate for infra diffs; CTO F5/G2 |
| PR Test plan record line | "record \"CI is the gate\"" | asked |
| Drift-guard parity test (classifier text, infra literals) | inferred: ADR-196 requires the refusal to bind to measured text; a copied literal needs a pin | inferred - cheap, prevents a silent never-matching classifier; CTO F4 |
| `affected-gate-contract.md` rc 4 clause | inferred: its rc 4 row says "never retry blindly", which would contradict the new bounded wait | inferred - one clause, avoids two docs disagreeing |
| `test-affected-paths.sh` / `.accept.tsv` edits | inferred: the census linter reds an unclassified new suite | inferred - lint-forced, conditional |
| ADR-196 addendum | inferred: ADR-196 point 6 states the pipeline call-site behaviour this changes | inferred - recorded architecture must not lag the change (plan Phase 2.10) |

### Split Assessment

- Subsystems touched: 2 - `plugins/soleur/skills/ship/**`, `plugins/soleur/test/**` (+ `scripts/lib` declaration, KB docs)
- Planned files: ~9 | Estimated changed lines: ~900 (mostly the test suite)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines - only the line estimate is borderline and is test code
- Recommendation: single PR (one item, as the brief requires)

## User-Brand Impact

**If this lands broken, the user experiences:** a ship run that either waits forever behind a sibling battery (the status quo) or, worse, skips its local battery on a diff where CI would not have caught the regression and then merges it.
**If this leaks, the user's workflow is exposed via:** no data path - the script reads a log file, a state file, `git diff --name-only` and the capacity line; it handles no credentials and writes only its own state file.
**Brand-survival threshold:** none

threshold: none, reason: the diff touches `plugins/soleur/skills/ship/**` and a test, not a credential, auth, migration or user-data path; the one safety-relevant failure (skipping the sole blocking gate on infra diffs) is closed by the fail-closed infra carve-out and pinned by mutation rows.

## Architecture Decision (ADR/C4)

### ADR
Add an addendum (2026-10-28) to ADR-196 (`knowledge-base/engineering/architecture/decisions/ADR-196-full-gate-refusal-binds-to-a-measured-condition.md`):
its Decision 6 says a refusal at the pipeline call site is "actionable: wait for the sibling, or re-run with the hatch".
The addendum records the bounded form (budget, waitable class, infra carve-out, CI-is-the-gate record). Amendment via
`soleur:architecture`; no new ordinal.

### C4 views
No C4 change. Read `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`: the only matching
element is the coarse `ship` skill component and the existing `plugin -> github` edge. The change adds no external
human actor (the operator and the agent are already modeled), no external system or vendor (CI is the existing GitHub
edge), no container or data store (one temp state file), and no actor-to-surface access relationship. No derived
cardinality in `model.c4` prose moves; confirmed by running `bash plugins/soleur/test/c4-count-parity.test.sh` in Phase 4.

### Sequencing
True the moment the code merges; no soak window.

## Guard Contract

### Guard 1 - battery-refusal-wait verdict

**Property.** The script prints the CI-is-the-gate verdict (exit 42) only when the log shows the sibling full-gate refusal shape with no non-contention evidence, `--full` was not passed, a valid capacity reading was seen, the wall-clock budget since episode start is exhausted, and the changed-path set is positively resolved and contains no infra trigger.

**Assembly.** The verdict has one chokepoint: the final `case` on the (class, full, budget, capacity-seen, infra) tuple in `plugins/soleur/skills/ship/scripts/battery-refusal-wait.sh`; every path to exit 42 flows through it and the suite asserts there is no other way to produce 42 by mutation, not by grep. Inputs that feed it: (a) the classifier over the whole log, CR stripped (one shape, `refusing a full-gate run .* [0-9]+ sibling full-gate run(s) already in flight`; exclusions scanned over the full file: `[FAIL]`, `[KILLED]`, `AFFECTED_UNRESOLVED`, `AFFECTED_GATE_REFUSED reason=` other than `runner-refused`, `SOLEUR_SUBAGENT=1 is set`; `AFFECTED_FALLBACK` is a companion line and allowed); (b) the budget clock (`date +%s` via PATH, episode epoch in the `--state` file created by the recipe with `mktemp`, empty = episode start, written atomically; non-integer or future epoch exits 2); (c) the capacity reading (`CAPACITY_OK` + `measured_runs=0` is the only idle signal; the call is wrapped in `timeout`, stderr captured with its rc); (d) the infra predicate mirroring the runner's `_diff_names` assembly (scripts/test-all.sh ~2547-2590): `git diff --name-only HEAD`, `git diff --name-only origin/main...HEAD`, `git diff --name-status -M HEAD`, `git diff --name-status -M origin/main...HEAD`, and `git ls-files --others --exclude-standard`, unanchored substring match for `apps/web-platform/infra/` and `.github/workflows/apply-web-platform-infra.yml`, failing closed when the `origin/main...HEAD` form fails; (e) the call sites that consume the verdict: the ship `SKILL.md` recipe and the reference file's PR Test plan line. Members drift; the suite derives the classifier shape and the infra literals from `scripts/test-all.sh` rather than restating them.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Classifier shape edited so the real sibling text no longer matches (log of a real sibling refusal) | RED: "sibling refusal waits then defers" fails (verdict becomes NOT_WAITABLE) |
| 2 | Chokepoint `case` returns 42 regardless of the infra flag, or regardless of `--full` | RED: infra rows (prefix, workflow file, untracked, rename source, git failure) and the `--full` row fail |
| 3 | Add a second, non-contention line AFTER a compliant first (`AFFECTED_UNRESOLVED` beneath the sibling text; `[FAIL]` after it) | RED: mixed-evidence rows must stay NOT_WAITABLE; a check that stops at the first match turns them 42 |
| 4 | Budget comparison `>=` flipped, or the state epoch ignored (budget measured per call) | RED: boundary rows (elapsed = budget -1 / = budget) and the two-invocation shared-budget row fail |
| 5 | Dispatch: script body replaced by `exit 42`, or by "classify nothing, exit 10" | RED: the NOT_WAITABLE rows (selection refusal, empty log, missing log) expect 11 and the garbage-state row expects 2; the stray-status row (1, 127, 130 from a wrapper stub) must not continue |
| 6 | Capacity parse loosened to key on `measured_runs=0` alone (`CAPACITY_CONTENDED reason=low_tmp ... measured_runs=0`, or `measured_runs=?`, read as idle), or "never readable" folded into deferral | RED: the low_tmp row and the unreadable row keep waiting; the never-readable row expects 11 `capacity-unreadable` |
| 7 | REORDER: move the state-file epoch write from before the first poll to after the loop | RED: a row that kills the script mid-wait and re-invokes must see the original epoch (a delete-only mutant would not be caught) |
| 8 | Infra literal drift: edit one trigger literal in the script, or drop the `-M` rename form | RED: the parity row diffs both literals against `scripts/test-all.sh`; the rename-source row fails |
| 9 | Add `SOLEUR_SUBAGENT=1 is set` to the contention shape (the declared-env refusal becomes waitable) | RED: the SUBAGENT-only row must stay exit 11 and must not wait |

Harness rows: (H1) delete the 42-row `assert_rc` from a copy of the suite and the run must report fewer passes than the asserted PASS floor and exit non-zero (a suite whose success is `fail == 0` exits 0 on `0 passed, 0 failed`); (H2) must-PASS inputs that are NOT the canonical fixture: a log with CRLF endings, a sibling refusal preceded by 5000 lines of suite output, a `2 sibling full-gate run(s)` wording, and a degraded-affected log (`AFFECTED_FALLBACK reason=...` plus the sibling refusal) all classify as contention.

**Anchor.** The classifier shape and infra literals are copied text, so what outside this diff must move for a weakening to pass: the suite greps the live `scripts/test-all.sh` (a different file the diff would have to edit in step) for the sibling-refusal line and for both infra literals; loosening only the script reds the parity row, and editing only `test-all.sh` reds it from the other side. The refusal line is additionally pinned by `fanout-suite-scope.test.sh`. The budget default (1800) is pinned by the suite's default-budget row and the reference file's recipe.

## Observability

```yaml
liveness_signal:
  what: one transcript line per poll (battery-refusal-wait: WAITING elapsed_s=<n> budget_s=<n> capacity=<ok|contended|unknown|unreadable>) and one terminal BATTERY_REFUSAL_WAIT verdict line
  cadence: every --interval-s (default 60 s) while waiting, so the Monitor tool never sees silence
  alert_target: the shipping session itself (Monitor events); the PR Test plan line for the human reader
  configured_in: plugins/soleur/skills/ship/scripts/battery-refusal-wait.sh
error_reporting:
  destination: stderr of the script and a nonzero exit; the caller branches on the exit code only (42 is the sole continue value)
  fail_loud: every unrecognised input (bad flag, non-integer budget, bad state file, git failure, capacity never readable) exits 2, 11 or 12 with a named reason
failure_modes:
  - mode: capacity line unreadable for the whole budget
    detection: WAITING lines show capacity=unreadable; terminal verdict NOT_WAITABLE reason=capacity-unreadable (exit 11)
    alert_route: transcript verdict line, caller stops
  - mode: git cannot resolve the origin/main...HEAD diff
    detection: verdict QUEUE_IN_LOCK reason=diff-unresolved
    alert_route: transcript verdict line
  - mode: classifier text drifts from test-all.sh
    detection: ship-battery-refusal-wait.test.sh parity rows (CI required test shard)
    alert_route: red CI test check on the PR that edits either file
logs:
  where: the detached run's log (mktemp under TMPDIR per the existing recipe) and the session transcript
  retention: session lifetime; the PR body line persists the outcome
discoverability_test:
  command: bash plugins/soleur/skills/ship/scripts/battery-refusal-wait.sh --classify-only /dev/null
  expected_output: class=not-waitable
```

## Domain Review

**Domains relevant:** none

No cross-domain implications detected - internal engineering tooling inside the ship skill; no UI surface, no legal, finance, marketing or operations surface. Named-panel note: the devex lens would be the CTO, who already ruled every design fork of this plan (F1-F7, G1-G2, H1-H3), so no second CTO pass was spawned.

## Plan Review Outcome (2026-10-28)

Panel: DHH, Kieran, code-simplicity (3 reviewers; threshold none). Mechanical findings applied above: rename-aware infra predicate (4 diff forms + untracked, substring match, fail closed); episode-scoped state file (recipe `mktemp`, empty = start, atomic write, future epoch invalid); `date +%s` clock seam with `timeout` on the capacity call; distinct exit codes (RETRY 10, NOT_WAITABLE 11, QUEUE_IN_LOCK 12, usage 2, CI_IS_THE_GATE 42); `--full` never defers (H1); `AFFECTED_FALLBACK` allowed as companion; launch-first recipe removing the unbounded up-front loop; capacity-never-readable stops instead of deferring; flags only (no env vars, H2); classifier requires the full shape, scans the whole log, strips CR; variable named `wait_rc` in the recipe so it cannot be confused with the battery `rc`; suite trimmed (dropped the property loop, the grep-based single-`exit 42` AC and a duplicate meta-mutation); ADR-196 addendum and reference file shortened; real-log check promoted to an AC. Declined with reason: sourcing the runner's predicate (not queryable without editing `test-all.sh`, F2); dropping `--classify-only` (it is the discoverability command and the real-log check driver, ~5 lines); dropping the ADR-196 addendum (plan Phase 2.10: Decision 6 states the call-site behaviour this changes). Budget basis, stated honestly: no measured sibling hold time exists for 30 minutes to be sized against - a full gate runs ~35-45 minutes, so on a typical contended start the budget lapses to CI; that is the intended behaviour (a lapsed wait costs nothing because CI is the required gate for non-infra diffs, and the infra and `--full` paths keep waiting in the lock).

## Implementation Phases

Write the matrix (Guard Contract) first; the suite's rows come from it before the script body exists.

### Phase 1 - failing tests first (RED)
- Create `plugins/soleur/test/ship-battery-refusal-wait.test.sh` modelled on `ship-battery-owed.test.sh` and
  `ship-prepush-secret-scan.test.sh`: scratch git repo per arm (`lib/git-fixture-env.sh`), argv-strict PATH stubs for
  `sleep` (advances a fake clock file) and `date +%s` (reads it) - derive the expected argv by running the SUT once, a
  stub `scripts/test-all.sh --capacity` in the scratch repo, mutation harness copying the script and editing one literal per row.
- Rows: classifier (sibling shape -> contention incl. 1/2 siblings, CRLF, long preamble, degraded-affected log;
  SOLEUR_SUBAGENT-only, `[FAIL]`, `[KILLED]`, `AFFECTED_UNRESOLVED`, mixed evidence, empty and missing log, random text
  -> exit 11); wait loop (`CAPACITY_OK measured_runs=0` -> 10; never drains -> 42 at budget; boundary; shared state
  across two invocations; CONTENDED-with-zero and `?` keep waiting; never readable -> 11; hung capacity call bounded by
  `timeout`); state (empty = fresh, garbage and future epoch -> 2); infra (prefix, workflow file, committed,
  working-tree, untracked, rename source, git failure -> 12, never 42); `--full` + contended -> 12, never 42; stray
  statuses 1/127/130 from a wrapper never continue; arg validation (non-integer, negative, unknown flag -> 2; defaults
  1800/60); parity (sibling-refusal line and both infra literals live in `scripts/test-all.sh`); wiring (SKILL.md names the
  script and links the reference; the rc=4 REFUSED-nothing-ran sentence is intact).
- Floors: PASS count asserted (not `fail == 0`).

### Phase 2 - the script
- Create `plugins/soleur/skills/ship/scripts/battery-refusal-wait.sh`. Contract in the header comment (prose lives
  here, not in SKILL.md): flags `--log`, `--state`, `--budget-s` (default 1800), `--interval-s` (default 60), `--full`,
  `--classify-only`; verdict line `BATTERY_REFUSAL_WAIT verdict=<RETRY|CI_IS_THE_GATE|QUEUE_IN_LOCK|NOT_WAITABLE> waited_s=<n> reason=<r>`;
  exits RETRY 10, NOT_WAITABLE 11, QUEUE_IN_LOCK 12, usage/error 2, CI_IS_THE_GATE 42 (the odd number is the point,
  as `battery-owed.sh` SKIPPABLE: only 42 skips local evidence; every status bash emits by accident stops).
- Behaviour: classify -> not waitable => 11 now. Contention => write the episode epoch atomically if the state file is
  empty (before the first poll) => loop capacity every interval: `CAPACITY_OK` + `measured_runs=0` => 10; else keep
  waiting and note whether any valid CONTENDED/OK reading was seen; deadline reached => never-readable => 11
  `capacity-unreadable`; `--full` or infra/diff-unresolved => 12; else 42. Sanitize printed tokens
  (`soleur_ctx_sanitize`, `plugins/soleur/scripts/lib/context-sanitize.sh` with a same-name fallback as `battery-owed.sh`); `set -uo pipefail`; no `eval`; no env-injected commands.

### Phase 3 - wiring and docs
- `plugins/soleur/skills/ship/references/battery-refusal-wait.md` (new, short): the launch-first recipe as one Monitor
  script (`persistent: true`; launch detached with `setsid nohup ... ; echo $? > "$RCF"`, `wait_rc` variable, state file
  from `mktemp`, branch 10 relaunch / 42 record+continue / 12 queue-in-lock recipe / else stop), the fixed PR Test plan
  line (never "passed"/"verified"): `Local battery refused (sibling contention); waited <n>s; CI "test" is the authoritative gate; local run NOT executed.`, and links (not restatements) to the contract and the substituted-shard learning. Linked from `SKILL.md` by markdown link.
- `plugins/soleur/skills/ship/SKILL.md`: replace the two contention paragraphs (the "wait, launch and retry in ONE
  Monitor script" one and the "`measured_runs=0` is unbounded" one) with one short pointer paragraph that keeps the
  `SOLEUR_ALLOW_FULL_GATE=1 TC_LOCK_TIMEOUT=14400 TC_RUNTIME_CEILING_S=39600 ... --full` queue-in-lock command (the
  target of exit 12) and links the reference. Measured: the two paragraphs are ~1.7 KB, the pointer ~0.9 KB (net about -0.7 KB). Net bytes must be negative; verify with `python3 scripts/lint-skill-body-budget.py --base origin/main`.
  Do NOT touch `review/SKILL.md`. Keep the "dispatch is pinned" text, the dispatch fenced block, and the rc=4 REFUSED sentence intact.
  Constraint checks: `fullsuite-merge-gate.test.ts` (fenced test-all/affected lines in `## Phase 4: Run Tests` must be unsharded and carry `--affected`/`--full`, QUERY_FLAGs such as `--capacity` exempt) and `ship-battery-owed.test.sh` T16 (dispatch block up to the first column-0 `fi`, `rc -eq 42`).
- `plugins/soleur/skills/ship/references/affected-gate-contract.md`: rc 4 row gains one clause linking the reference
  for `reason=runner-refused` caused by a sibling run. No other row changes.
- `scripts/lib/test-affected-paths.sh`: declare `AFFECTED_PLUGINS_SOLEUR_TEST_SHIP_BATTERY_REFUSAL_WAIT_TEST_SH_PATHS`
  if `scripts/lint-orphan-test-suites.sh` reports the suite unclassified; add `scripts/ci-pr-affected-audit.accept.tsv` rows only if the audit lint names them.
  Do not hand-edit `scripts/suite-shard-legs.tsv` / `scripts/suite-durations.tsv` (generated; missing rows degrade rather than fail). `plugins/soleur/test/*.test.sh` is auto-globbed by `SUITE_GLOBS`.
- ADR-196 addendum, about five lines (budget, waitable class, `--full` and infra carve-out, record), via `soleur:architecture`.
- Doc drift noted, not fixed: `work/SKILL.md` and `ship/SKILL.md` print `CAPACITY_OK` without the `[contention]` prefix the real line carries; the script matches the substring.

### Phase 4 - verify (GREEN and gates)
- `bash plugins/soleur/test/ship-battery-refusal-wait.test.sh` (every mutation row RED against its mutant).
- Neighbours: `bash plugins/soleur/test/ship-battery-owed.test.sh`, `bun test plugins/soleur/test/fullsuite-merge-gate.test.ts`,
  `bun test plugins/soleur/test/components.test.ts` (reachability + budgets), `bash plugins/soleur/test/c4-count-parity.test.sh`,
  `bash scripts/lint-orphan-test-suites.sh`, `python3 scripts/lint-skill-body-budget.py --base origin/main`,
  `python3 scripts/lint-guard-contract.py <this plan>`, `bash plugins/soleur/test/fanout-suite-scope.test.sh`, markdown lint on new/edited .md.
- Real-log check (an AC): capture a real sibling refusal from `scripts/test-all.sh --full` against a real sibling holder
  (as `fanout-suite-scope.test.sh` does) and a degraded-affected one, and confirm `--classify-only` prints `class=contention`.

### Phase 5 - ship (handled by the pipeline, listed so the ACs are complete)
- PR body: `Ref #9757`, `Ref #10924`, no closing keyword (omit the template's `Closes #ISSUE_NUMBER` line); name the
  narrowing (sibling contention only, not every rc=4); `## Changelog`; label `semver:patch`.
- Merge via `gh pr merge <N> --squash --auto` (one merge string per Bash command); postmerge: `deploy-arm.sh find --wait`,
  served -> CONTAINS; skip Sentry monitors, live-verify, sole-copy. After merge tick the P4d checkbox in #10924 (body edit of that line only) and comment; never close it.
- Resume prompt covering #10932 (read its residual-gaps comment first).

## Files to Create
- `plugins/soleur/skills/ship/scripts/battery-refusal-wait.sh`
- `plugins/soleur/skills/ship/references/battery-refusal-wait.md`
- `plugins/soleur/test/ship-battery-refusal-wait.test.sh`
- `knowledge-base/project/specs/feat-one-shot-9757-p4d-rc4-bounded-wait/{tasks.md,decision-challenges.md,session-state.md}`
- a learning file under `knowledge-base/project/learnings/` (compound at ship)

## Files to Edit
- `plugins/soleur/skills/ship/SKILL.md` (net-negative bytes)
- `plugins/soleur/skills/ship/references/affected-gate-contract.md` (rc 4 row, one clause)
- `scripts/lib/test-affected-paths.sh` (one declaration array, if the census requires)
- `scripts/ci-pr-affected-audit.accept.tsv` (only if the audit names rows)
- `knowledge-base/engineering/architecture/decisions/ADR-196-full-gate-refusal-binds-to-a-measured-condition.md` (addendum)

Not touched (asserted in ACs): `apps/**`, `scripts/registry-restore-from-ghcr.sh`, `.github/workflows/apply-web-platform-infra.yml`,
`scripts/test-all.sh`, `plugins/soleur/scripts/affected-tests.sh`, `plugins/soleur/skills/review/SKILL.md`,
`plugins/soleur/lib/harness.ts`, `plugins/soleur/skills/drain-prs/SKILL.md`, `plugins/soleur/scripts/monitor-pr-checks.sh`.

## Acceptance Criteria

<!-- founder-stated check: see plan-founder-check.md -->

- [x] AC1 With a sibling-refusal log, a capacity stub that never reports `CAPACITY_OK measured_runs=0` but does report a valid CONTENDED line, a non-infra diff, no `--full` and an elapsed budget, `battery-refusal-wait.sh` prints `BATTERY_REFUSAL_WAIT verdict=CI_IS_THE_GATE` and exits 42 (final `case` in `plugins/soleur/skills/ship/scripts/battery-refusal-wait.sh`).
- [x] AC2 Every non-contention log (SOLEUR_SUBAGENT text, selection refusal, `[FAIL]`/`[KILLED]`, mixed, empty, missing) exits 11 `NOT_WAITABLE` without waiting; a degraded-affected log (`AFFECTED_FALLBACK` plus the sibling refusal) is contention.
- [x] AC3 A diff touching `apps/web-platform/infra/` or `.github/workflows/apply-web-platform-infra.yml` (committed, working-tree, untracked, or as a rename SOURCE), a failed `origin/main...HEAD` diff, or `--full`, never exits 42; after the budget it exits 12 `QUEUE_IN_LOCK`.
- [x] AC4 A `[contention] CAPACITY_OK ... measured_runs=0` line exits 10 `RETRY`; `CAPACITY_CONTENDED` (even with `measured_runs=0`), `CAPACITY_UNKNOWN`, `measured_runs=?` and a failed or hung call keep waiting; a budget that ends with no valid reading exits 11 `capacity-unreadable`; two invocations share one budget through `--state`; an empty state file starts a fresh episode; a non-integer or future epoch exits 2.
- [x] AC5 Defaults are 1800 s budget and 60 s interval via flags only (no env vars read); invalid values exit 2.
- [x] AC6 No exit status other than 42 continues: a stray 1, 127 or 130 from the script (wrapper stub) is treated as stop by the recipe's branch, and the suite asserts it.
- [x] AC7 `ship/SKILL.md` links `references/battery-refusal-wait.md`, no longer prescribes an unbounded "go back to waiting" or the unbounded up-front capacity loop, keeps the queue-in-lock command, the rc=4 "REFUSED - nothing ran" sentence and the pinned-dispatch text; net bytes < 0 and `lint-skill-body-budget.py --base origin/main` is OK. `review/SKILL.md` is byte-identical to base.
- [x] AC8 The reference file carries the exact PR Test plan line, which never contains the words "passed" or "verified", and uses `wait_rc` (not `rc`) for the script's status.
- [x] AC9 The suite's parity rows pass against the live `scripts/test-all.sh`; each mutation row (1-9) and H1 is demonstrated RED against its mutant; H2 inputs pass; the PASS floor is asserted.
- [x] AC10 `git diff --stat origin/main...HEAD` shows no change under `apps/`, none to `scripts/registry-restore-from-ghcr.sh`, `scripts/test-all.sh`, `affected-tests.sh`, `harness.ts`, `drain-prs/SKILL.md`, `monitor-pr-checks.sh`, `review/SKILL.md`, and none to `.github/workflows/apply-web-platform-infra.yml`.
- [x] AC11 Neighbour suites in Phase 4 are green; `lint-orphan-test-suites.sh` reports the new suite classified.
- [x] AC12 Real-log check: `--classify-only` prints `class=contention` for a log captured from a real sibling refusal and for a real degraded-affected refusal (fixtures built by the suite from a real `flock` holder, not hand-typed text only).
- [x] AC13 ADR-196 carries the 2026-10-28 addendum.
- [ ] AC14 PR body has `Ref #9757` and `Ref #10924`, no closing keyword, names the narrowing; after merge the P4d checkbox in #10924 is ticked and #10924 / #9757 remain open.

## Test Scenarios

(All are `unit`/`integration` shell suites; no e2e. Every scenario runs on a synthetic fixture; none depends on other sessions' processes.)
- Given a sibling-refusal log and a capacity stub that reports `CONTENDED` forever, when the budget (small, via flag) elapses on a non-infra diff without `--full`, then exit 42 and the verdict line [integration].
- Given the same log and `CAPACITY_OK measured_runs=0` on the third poll, then exit 10 after two WAITING lines [integration].
- Given the same log and a diff touching `.github/workflows/apply-web-platform-infra.yml`, or one that renames a file OUT of `apps/web-platform/infra/`, then exit 12 and never 42 [integration].
- Given the same log with `--full`, then exit 12 [integration].
- Given a log with the sibling text plus `AFFECTED_UNRESOLVED reason=below-floor` (or a trailing `[FAIL]`), then exit 11 [unit].
- Given `SOLEUR_SUBAGENT=1 is set` text only, then exit 11 and no waiting [unit].
- Given a first invocation killed mid-wait and a second invocation on the same state file, then the second sees the original epoch [integration].
- Given a capacity stub that never prints a valid line, then exit 11 `capacity-unreadable` at the budget [integration].
- Given a state file holding a future epoch, then exit 2 [unit].

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold fails `deepen-plan` Phase 4.6; it is filled above.
- The ship PR template contains `Closes #ISSUE_NUMBER`; this PR must omit it (Ref only). A closing keyword would close #10924 and #9757 on merge.
- Only `exit 42` continues without local evidence; a `set -u` abort exits 1 and must stop.
- Do not edit `scripts/test-all.sh` to "help" the classifier: its refusal text is pinned by `fanout-suite-scope.test.sh`; the parity row reads it, it does not own it.
- A foreign `test-all.sh` from another worktree is running right now and can refuse this PR's own Phase 4 battery: use the new script's flow (or the affected set directly), never kill the sibling's process.
- The recipe's Monitor must be armed with `persistent: true` (the Monitor tool default timeout is 5 minutes; the script's budget is 30).

## Post-review amendments (2026-10-28)

The 8-seat review and the CTO rulings R1-R5 (decision-challenges.md) amended the plan as follows; the ACs above were verified against the amended behavior (suite: 215 assertions, 57 mutant rows):

- AC2/AC3: `AFFECTED_FALLBACK` is classified by reason (index-missing and enumerate-unavailable stop; force-all behaves like `--full`; an unparseable or unknown reason stops).
- AC4: the state epoch must be exactly 10 digits, not future and not older than 6 h; the state path must be an absolute regular file; `--probe-timeout-s` is a flag.
- AC7: SKILL.md is 273877 bytes against 273890 on the base; the recipe launches the pinned dispatch (`affected-tests.sh`).

