---
title: "fix: main-health-monitor red on test-scripts shards — TEST_GROUP env leaks into suite children"
date: 2026-11-03
slug: fix-main-health-monitor-test-group-env-leak
branch: feat-one-shot-11939-main-health-scripts-shards
issue: 11939
closes: 11939 # conditional — see "PR keyword" under Acceptance Criteria
type: fix
priority: p1
domain: engineering
brand_survival_threshold: none
lane: cross-domain # spec.md absent for this branch: defaulted fail-closed (TR2)
---

## Enhancement Summary

**Deepened on:** 2026-11-03 (proportionate pass: the full all-agents fan-out was not run for a one-line
runner change; the gates and verification below were).
**Sections enhanced:** Research Insights, Guard Contract, Acceptance Criteria.
**Agents/gates used:** CTO ruling (3 forks), repo-research audit of every child-runner spawn, learnings
search, plan-review panel (DHH, Kieran, code-simplicity), Phase 4.6 (User-Brand Impact present), 4.8 (no
PAT-shaped variable), 4.11 (`lint-guard-contract.py` green), 4.12 (one unfenced Scope Check); 4.7/4.9/4.10/4.13
skip (no code under `apps/*`, no UI, no store, no new autonomous task).

### Key improvements
1. Root cause promoted from inference to reproduction on this worktree (28/0 vs 23/5; C0 PASS vs FAIL) and
   confirmed on one SHA (merge_group green, monitor red).
2. Repo-wide exposed-spawn inventory, so the single demotion is shown to cover every affected child.
3. Guard Contract made implementable: splice anchor rule, serial mode pin, grandchild row recognised as
   not a mutation, committed vs driven-once split.

### New considerations discovered
- `ci.yml` push runs elide test legs, so the `0/50` metric is blind here (#11953).
- The derive-cache lib reads `TEST_GROUP` in-shell (sourced), so `export -n` does not affect it.
- Cited issues/PRs verified live: #11119, #11844, #11665 MERGED; #9457, #11662, #7902 CLOSED; #9323, #10233,
  #9217, #7942, #11939, #11952, #11953 OPEN. Only one rule id is cited (`cq-write-failing-tests-before`,
  active). Labels used (`deferred-scope-out`, `meta/machinery`) verified to exist.

## Overview

The scheduled `main-health-monitor` has reported three scripts-group suites red on every run since the
2026-11-02 ceiling fix let it finish, while `ci.yml` is green on the **same commit**. The cause is not
the source tree and not the checkout: it is **how the group is delivered to the runner**. The monitor
sets `TEST_GROUP` as a step `env:`; `ci.yml` passes the group positionally. `scripts/test-all.sh`
resolves `TEST_GROUP="${TEST_GROUP:-${1:-all}}"` (env wins) and never un-exports it, so under the
monitor every suite the runner spawns inherits `TEST_GROUP=scripts` and any suite that itself spawns
`bash scripts/test-all.sh --enumerate-commands | --print-selection | --affected` gets a narrowed or
refused answer. The runner already follows a "consume the carrier at the point of coupling" rule for
`SCRIPTS_SHARD` (#7902); this plan applies the same rule to `TEST_GROUP`.

No assertion is weakened or skipped, no alert predicate is edited, `main-health-monitor.yml` is not
edited, nothing touches Hetzner or Doppler.

## Research Insights

### Root cause (reproduced, not inferred)

| Evidence | Finding |
|---|---|
| Same SHA `f05eaab78f` | `ci.yml` merge_group run 41576202102: all 8 `test-scripts` legs and 3 `test-scripts-heavy` legs **success**. Monitor run 41587171627 on the same SHA: legs 5/6/7 red. A source or checkout defect cannot split one SHA. |
| Channel difference | `main-health-monitor.yml` lines ~399/486 (`TEST_GROUP: scripts` / `scripts-heavy` as step env, `bash scripts/test-all.sh` with no positional). `ci.yml` test-scripts (`bash scripts/test-all.sh scripts`, positional; the comment above that job explains why the SHARD (not the group) is the env channel there). |
| Resolver | `scripts/test-all.sh` ~1177 `TEST_GROUP="${TEST_GROUP:-${1:-all}}"`; no `export -n`/unset of it anywhere; `unset SCRIPTS_SHARD SOLEUR_SHARD_MANIFEST …` at ~1446 already exists with a "consume at the point of coupling, not `env -u` at N call sites" comment. |
| C0 / M16 (`lint-orphan-test-suites-mutations-a/b`) | `scripts/lint-orphan-test-suites.test.sh` step (4b) builds its sandbox from a child `bash scripts/test-all.sh --enumerate-commands`. Inheriting `TEST_GROUP=scripts` returns only scripts-group registrations, so the bun-group registration `blog-link-validation` (the `blog-link-validation` `run_suite` line in `scripts/test-all.sh`, `want_bun`) has its target `scripts/validate-blog-links.sh` left out of the sandbox, and surface 7 (dead-registration census, #11662 G4 / #11665) reds C0 and M16. The file exists on main; the sandbox simply never received it. Local repro: `--rows 1-1` with `TEST_GROUP` unset → C0 PASS, rc 0; with `TEST_GROUP=scripts` → C0 FAIL "dead registration", rc 1. |
| B1/B2/B3 (`test-all-group-affected`) | The suite calls `bash scripts/test-all.sh --print-selection` under `env -u CI` only. `--print-selection` requires `TEST_GROUP=all` (runner ~1215) and env beats the positional `affected`, so rc=2 → empty selection → "edge suite not selected", "always-on suite fell off the floor", "positional alias diverged rc=2". |
| Why only now | The monitor has delivered the group as a step `env:` since #7371 (infra leg, 2026-08-10) and on every leg since #11119 (2026-10-26). Until #11844 (2026-11-02) its scripts legs ended at the 15-minute step ceiling (#9457, closed 2026-11-02 21:54Z), before the suites that leak reached their failing assertions. The surface-7 census (#11665, 2026-10-31) added the C0/M16 failure mode. |
| `Broken pipe` noise | Present in the **green** `ci.yml` legs too (25 and 34 occurrences in merge_group run 41576202102 shards 5/6). Not causal; left alone (the same SIGPIPE class as #9217). |
| 0/50 red rate | `ci.yml` **push** runs elide the test legs (`push-dedupe`; push run 41580111851 on the monitor's SHA shows `test-scripts` skipped), so the `0/50` figure cannot see this class. Recorded as a non-goal; alert predicates are not edited (see Deferrals). |

### Exposed-spawn inventory (repo-wide audit, read-only)

Nothing in the repo exports `TEST_GROUP` on purpose; the only parent export is the monitor's five step
`env:` keys (`main-health-monitor.yml` lines 217/300/399/486/602). Spawns of a child runner that do **not**
scrub or set the group and so change behaviour under an inherited `TEST_GROUP=scripts` (all are children
of the runner in the monitor, so all are covered by the single demotion):

| Spawn | Target | Effect when inherited |
|---|---|---|
| `scripts/lint-orphan-test-suites.test.sh:223` | `--enumerate-commands` (no group) | silent narrowing → C0/M16 (the observed failure) |
| `scripts/test-all-group-affected.test.sh` (`--print-selection`, positional `affected`) | runner | env beats positional; `--print-selection` needs `all` → rc 2 (B1/B2/B3). Reproduced locally on this worktree: `TEST_GROUP` unset → `28 passed, 0 failed` rc 0; `TEST_GROUP=scripts` → `23 passed, 5 failed` rc 1, the exact count in the CI log |
| `scripts/lib/test-suite-lanes.test.sh:30` | `--enumerate-commands all` | positional `all` overridden by env → narrowed enumeration (silent, currently green) |
| `scripts/lib/repo-write-boundary.test.sh:438,458` | sandboxed runner copies, no args | would run the scripts dispatch instead of `all` (unverified whether it reaches dispatch) |
| `tests/scripts/test-scratch-residue.sh:198` | `--enumerate-commands` | narrowing only; assertion unaffected |
| `scripts/ci-pr-selection.sh:366-372` | `--print-selection` | `ci.yml` job, not under the monitor; fail-safe fallback to the full battery |
| `scripts/hooks/pre-push:69` | `--affected` | developer hook; caller's own shell, out of scope |

Inert (query modes exit before group resolution, or already scrub/set the group) are not listed; the
full audit found them safe. Row 3 above and `test-suite-lanes.test.sh` are the two "silently narrowed but
currently green" members the dry run may newly surface (see Sharp Edges).

Reader check (plan-review P1): `scripts/lib/test-affected-derive-cache.sh:356` reads `${TEST_GROUP:-all}`,
but that library is `source`d by the runner (`test-all.sh` ~1136-1139), so it reads the shell variable,
which `export -n` preserves; it is not an exec'd child.

### Premise Validation (Phase 0.6)

Checked: #11939 is OPEN; #9323 and #10233 cited as related; PR #11952 is this branch's own draft
(collision pre-check hit = self, plus two foreign `test-all.sh` processes in unrelated worktrees,
reported and ignored). The brief's suspects were each tested and ruled out: `fetch-depth: 0` is set on
both workflows; the sandbox "subset of files" is by design, so the difference is in what the child
enumerator returns, not in the checkout; the monitor does **not** run a different group size than
`ci.yml` (same `SCRIPTS_SHARD` matrix, same manifest). The brief's claim that the file "exists on
origin/main" is true and is exactly why the "does not exist" message is about the **sandbox**, not the
repo. Cited paths verified in the worktree: `scripts/validate-blog-links.sh`, `scripts/test-all.sh`
registration line, `scripts/lint-orphan-test-suites.test.sh`, `scripts/test-all-group-affected.test.sh`.

### Property List and Cut List (Phase 0.6b)

Properties: (P1) a suite run by the runner sees the same environment whichever channel selected the
group; (P2) the monitor and `ci.yml` legs exercise identical suite behaviour on one SHA; (P3) no assertion
is weakened and no alert predicate changes; (P4) a future caller (developer who exports the variable,
a new workflow) cannot reintroduce the leak **into runner-spawned suites** (a suite run directly with an
exported `TEST_GROUP`, outside the runner, is unchanged; `lint-orphan-test-suites.sh` already scrubs per call
site at lines ~250/1073/1352).

Cut List: (a) patch each affected suite with `env -u TEST_GROUP` — buys P1 for two suites only, fails P4
(the two earlier learnings did exactly this and the class recurred); cut. (b) re-pin the monitor to the
positional channel — buys P2 but needs S2b (`main-health-monitor-workflow.test.sh:797`) rewritten and
would empty `scripts/followthroughs/jobs1-stopgap-7432.sh:140`, which slices the infra leg's log on the
`TEST_GROUP: infra` step-env echo; fails P4; cut (CTO ruling below). (c) a brand-new suite for the
regression guard — would need registration, a shard-manifest slot and an affected-class declaration for
one assertion group; cut in favour of new rows in the suite that already owns runner TEST_GROUP
behaviour.

### Institutional learnings applied

- `2026-08-14-every-defect-was-a-guard-that-could-not-fail-…`: a lint child inheriting `TEST_GROUP` from
  the shard recursed; rule: run each suite under the environment it ships into, a PASS-count delta across
  environments is a finding.
- `2026-10-31-anti-regrow-guards-totality-not-floors`: child `--enumerate` inherits
  `SCRIPTS_SHARD`/`TEST_GROUP` and emits a subset; field-exact matching for totality.
- `2026-09-08-…` (#7902): `SCRIPTS_SHARD` unset after the guard that reads it — the template for this fix.
- `2026-10-05-a-reader-that-exits-early-…`: SIGPIPE "Broken pipe" is early-exit-reader noise, not a verdict.

## Research Reconciliation — Spec vs. Codebase

| Brief claim | Reality | Plan response |
|---|---|---|
| "monitor's checkout/sandbox differs (fetch-depth, subset of files)" | Both use `fetch-depth: 0`; sandbox subset is by design and identical in both. | Not the cause; no checkout change. |
| "monitor runs the full group where ci.yml runs an affected subset" | Both run the full scripts group, same 8-way manifest. | Not the cause. |
| "validate-blog-links.sh does not exist" (sandbox log) | Exists on main; absent from the **sandbox** because the child enumerator was group-narrowed. | Fix the env leak, not the registration. |
| "Broken pipe SIGPIPE noise" | Appears in green legs too. | Out of scope. |

## Technical Decisions

Ruled by CTO agent, 2026-11-03: **Fork 1 — B only.** Demote `TEST_GROUP` to a non-exported shell variable
in `scripts/test-all.sh` immediately after the `unset SCRIPTS_SHARD …` line, plus a regression row.
Rationale: one edit at the point of coupling makes the runner independent of the caller (monitor,
`ci.yml`, a developer's exported variable); do **not** edit `main-health-monitor.yml` or S2b, because the
step-env channel has a live consumer (`jobs1-stopgap-7432.sh:140`). (The CTO first ruled D, A+B, then
revised to B-only on being shown that consumer; the revised ruling stands.) **Fork 2 —** `export -n` is
safe: it removes only the export attribute, all ~60 shell reads and the explicit positional hand-off to
the affected-walk child (`test-all.sh` ~4263, `"$TEST_GROUP"`) are unchanged; keep it after the
`--print-selection`/`--affected` parse and after the `affected→all` alias normalisation (~1211). **Fork 3 —**
`Closes #11939` only if a dry-run dispatch of the monitor on this branch is fully green, else `Ref`.
Recorded in `knowledge-base/project/specs/feat-one-shot-11939-main-health-scripts-shards/decision-challenges.md`.

Pre-merge checks already run for the ruling's two conditions: (1) no suite under `scripts/*.test.sh`,
`plugins/soleur/test/*.test.sh` or `apps/web-platform/infra/*.sh` branches on an inherited `TEST_GROUP`
(grep: only comments and one string-substitution fixture in `ship-battery-refusal-wait.test.sh:169`);
`ci.yml` already runs every suite with the variable unset, so no suite can depend on it being set.
(2) `git grep 'TEST_GROUP: '` consumers of the monitor's step-env echo: only
`scripts/followthroughs/jobs1-stopgap-7432.sh:140` and its test — untouched by a runner-only fix.

## Open Code-Review Overlap

#7942 (two `*.mutation.sh` batteries run in no gate) names `scripts/test-all.sh`. **Acknowledge:**
different concern (unwired batteries), needs its own cycle; remains open. No overlap on
`scripts/test-all-group-affected.test.sh` or `main-health-monitor.yml`.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly — this is CI tooling; a broken fix
  leaves the main-health tracker red (alert noise) or, worst case, a runner regression that reds PR CI.
- **If this leaks, the user's data / workflow / money is exposed via:** no exposure vector — an
  environment variable's export attribute is changed in a test runner; no secret, no user data, no network.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** `none`, not `aggregate pattern`: the failure mode is red CI on
  an internal gate, with no customer-facing artifact.

`threshold: none, reason: scripts/test-all.sh is a repo-internal test runner; the diff touches no
user-data, auth, billing or deploy path.`

## Proposed Solution

1. In `scripts/test-all.sh`, directly after `unset SCRIPTS_SHARD SOLEUR_SHARD_MANIFEST
   SOLEUR_SHARD_MANIFEST_HEAVY` (~1446), add `export -n TEST_GROUP` and extend that block's comment: the
   carrier is consumed here; env-vs-positional is a *selection* detail, not something descendants may
   observe; placement must stay after the group resolution/alias (~1177–1211) and after the
   `--print-selection`/`--affected` parse because those read `$TEST_GROUP` as a shell variable (still
   true after `export -n`). Update the stale SCOPE NOTE near ~1647 that says the monitor "runs
   `TEST_GROUP=all`" (it has run per-group legs since #11119).
2. In `scripts/test-all-group-affected.test.sh`, add **Part C — environment hygiene** using the existing
   fixture-sandbox builder (`run_sb`). It lives here because this is the suite that already owns runner
   `TEST_GROUP` semantics (env-vs-positional, the alias) and the only one whose sandbox splices
   registrations after the demotion point; a new suite would cost a registration, a shard-manifest slot
   and an affected-class declaration for one assertion group: register two probe suites in the spliced region; each prints
   `PROBE <name> TEST_GROUP=<set|absent>` from its own environment and a grandchild `bash -c`.
3. Verify the monitor shape end to end with a branch dry run (below), not by reasoning.

## Files to Edit

- `scripts/test-all.sh` — `export -n TEST_GROUP` after the `unset SCRIPTS_SHARD …` line; extend the
  comment block above it; correct the SCOPE NOTE near the `_shard_selects` helper.
- `scripts/test-all-group-affected.test.sh` — Part C rows (below); no existing row edited.

## Files to Create

- None in the repo besides the plan, `tasks.md` and `decision-challenges.md`. (A learning is captured at
  ship via `soleur:compound`.)

Glob/path check: every path above resolved with `git ls-files` in the worktree.

## Guard Contract

### Guard 1 — TEST_GROUP is never observable by a runner-spawned process

**Property.** No process started by `scripts/test-all.sh` for a suite (child or grandchild) has
`TEST_GROUP` in its environment, whichever channel (env or positional) selected the group, while the
runner's own group selection is unchanged.

**Assembly.** The property quantifies over every spawn the runner makes after group resolution: each
`run_suite` body, the infra arm (`run-registered-suites.sh`), `--enumerate*` children, the affected-walk
child (which receives the group **explicitly** as a positional, so it does not need the env), and any
suite that itself spawns a nested runner. Members drift (new spawn helpers appear); the assembly is
structural: the single chokepoint is the parent shell's export attribute on `TEST_GROUP`, set once after
the `unset SCRIPTS_SHARD` line and before the first registration (`tc_acquire`, ~5296). There is exactly
one demotion statement; a second spawn path cannot bypass it, but a re-export between registrations can,
which is what rows 2 and 4 drive.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the `export -n TEST_GROUP` line from the sandbox runner copy; run with `TEST_GROUP=scripts` exported | RED (probe A reports `set`) |
| 2 | REORDER: move the demotion to after the spliced registrations (into the window the first probe runs in), instead of deleting it | RED (probe A, registered first, observes `set`; a delete-only battery would not distinguish this) |
| 3 | The guard's own dispatch: make the probe suites print nothing (or register zero probes) | RED (the suite requires each probe's sentinel exactly once and a probe count floor of 2; "0 checked, exit 0" cannot pass) |
| 4 | Second member after a compliant first: inject `export TEST_GROUP` between probe A and probe B registrations | RED on probe B while probe A stays green (a check that stops at the first member is the defect) |
| 5 | Grandchild reading (not a mutation row: a grandchild's environment is a subset of its parent's, so it can only see the variable if the child re-exported it, which is a fixture edit, not a runner mutation) | folded into each probe as a free extra reading; no separate row |

**Committed vs driven-once (plan-review, DHH + simplicity: proportionality).** The matrix above is the
design contract the gate requires. To keep the committed suite proportionate to a one-line fix, only
row **1** (delete → probe A reads `set`, which doubles as the positive control), the grandchild reading
folded into each probe, and the H2 must-PASS rows are committed as suite assertions. Rows **2** (reorder), **3** (silent probes) and **4** (second member
after a compliant first) are each driven **once by hand** during the work phase against a scratch copy
of the sandbox runner and the RED output recorded in the PR body; they are not committed. H1 is dropped
(row 1's RED against the control already proves the probe can see a leak). The sandbox is known to
reach registration dispatch: `test-all-group-affected.test.sh` B4 already asserts `[ok] alpha-fixture`
from `run_sb`, so a spike is one extra `run_suite` line, not an unknown.

**Splice mechanics (Kieran review, verified against the worktree).** The sandbox keeps the runner's
line-~1446 demotion because the splice replaces only `tc_acquire`..`tc_epilogue`. Row 1 deletes that
line with a `re.M` match on `^export -n TEST_GROUP$` and asserts **exactly one** match, so the new
comment above it MUST NOT contain that literal (it would break the count-1 assertion; describe it as
"the export-attribute demotion"). Row 2 deletes the line and splices
`run_suite probeA; export -n TEST_GROUP; run_suite probeB` into the registration window; row 4 splices
`run_suite probeA; export TEST_GROUP; run_suite probeB`. `run_sb` for Part C must run serially
(`env -u SOLEUR_TEST_JOBS`): a caller's `SOLEUR_TEST_JOBS` engages `_pj_submit` (~1855), which defers
suite bodies and would make probe-A-green / probe-B-red ordering racy. Probe stdout reaches the captured
`OUT` on the serial path, so asserting on the `PROBE` lines is sound.

**Harness rows (as reduced above).** (H1, dropped: edit the suite) replace the probe's `${TEST_GROUP+set}` read with a constant
`absent`: the suite's built-in positive control — the same probe run against the row-1 mutant runner —
must read `set`, so a constant probe turns the control RED. (H2, must-PASS non-canonical inputs; it
reads `absent` even on the deleted-line mutant, so it guards against over-rejection only, never against a
missing demotion) the
positional channel (`runner.sh scripts`, `TEST_GROUP` unset in the caller) and an env value the contract
permits (`TEST_GROUP=scripts-heavy`) both read `absent` and must stay GREEN; RED rows alone cannot see a
guard that rejects everything. The counts are floors on the suite's own ledger (`>= N probes`, `>= 1`
control), asserted, not assumed.

**Anchor.** Not applicable: no stored value (hash, manifest row, count) is compared; the property is a
live read of a child's environment.

**Post-change survival check (the remediation's own tree).** After the fix lands, the three originally
failing suites run under the **monitor's** real shape (`TEST_GROUP=scripts SCRIPTS_SHARD=n/8 bash
scripts/test-all.sh`) and must go green; that is the mutation "restore the leak" in reverse, measured on
the post-fix tree rather than the one we found.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Root-cause what differs between the monitor run and ci.yml BEFORE changing anything" | Research Insights → Root cause (reproduced) | mapped |
| 2 | "do not weaken or skip any assertion" | Part C only adds rows; no existing assertion edited; S2b untouched | mapped |
| 3 | "do not edit alert predicates" | `main-health-monitor.yml` not edited; 0/50 blind spot recorded as a non-goal | mapped |
| 4 | "do not touch Hetzner/Doppler" | Files to Edit are two repo files; dry run is a GitHub workflow_dispatch only | mapped |
| 5 | "Use \"Closes #11939\" in the eventual PR only if the monitor will go green from the fix; otherwise \"Ref #11939\"" | AC "PR keyword" + dry-run gate | mapped |
| 6 | "plus 'Broken pipe' SIGPIPE noise" | Shown non-causal (present in green legs); out of scope | descoped — justification: appears in passing legs of the green comparator; #9217 owns the sweep |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `export -n TEST_GROUP` in the runner | "Root-cause what differs between the monitor run and ci.yml" | asked |
| Part C regression rows | "do not weaken or skip any assertion" (a fix without a guard re-opens the class) | inferred — justification: the learning corpus shows this exact class recurred after call-site patches (2026-08-14, 2026-10-31); `cq-write-failing-tests-before` |
| Stale SCOPE NOTE correction in `test-all.sh` | — | inferred — justification: the comment states the monitor runs `TEST_GROUP=all`, which is false since #11119 and would mislead the next editor of the same lines |
| Dry-run dispatch of the monitor | "only if the monitor will go green from the fix" | asked |

### Split Assessment

- Subsystems touched: 1 — `scripts/`
- Planned files: 2 | Estimated changed lines: ~90
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [x] **Failing test first (`cq-write-failing-tests-before`):** Part C rows are committed and observed RED
  against the unfixed runner before `export -n TEST_GROUP` is added.
- [x] `scripts/test-all.sh` contains `export -n TEST_GROUP` after the `unset SCRIPTS_SHARD` line and before
  `tc_acquire "test-all"`; the runner still reads `$TEST_GROUP` (no rename).
- [x] With `TEST_GROUP=scripts` exported, `bash scripts/lint-orphan-test-suites.test.sh --rows 1-18` and
  `--rows 19-35` exit 0 (C0 and M16 PASS), and `bash scripts/test-all-group-affected.test.sh` reports
  `0 failed` (B1/B2/B3 PASS), **both run as children of the runner**, i.e. via
  `TEST_GROUP=scripts SCRIPTS_SHARD=<k>/8 bash scripts/test-all.sh` on the shard that owns them
  (find it with `SCRIPTS_SHARD=k/8 bash scripts/test-all.sh --enumerate scripts`).
- [x] Part C: committed rows are the probe(s) incl. grandchild reading, the row-1 positive control and the
  positional-channel / `scripts-heavy` must-PASS; mutation rows 2, 3, 4 are each demonstrated RED once by
  hand (RED output recorded in the PR body, not committed); no existing assertion in
  `test-all-group-affected.test.sh` is edited, removed or loosened (`git diff` shows additions only to that
  file).
- [x] The inventory's scripts-group suites (`lib/test-suite-lanes`, `lib/repo-write-boundary`,
  `tests/scripts/test-scratch-residue`) are checked in the dry run's leg captures (no separate spot-run);
  any newly red one is root-caused, not skipped.
- [x] `plugins/soleur/test/main-health-monitor-workflow.test.sh` and
  `scripts/followthroughs/jobs1-stopgap-7432.test.sh` pass unchanged (they pin the step-env channel).
- [x] `lint-guard-contract.py` passes on this plan; `bash scripts/lint-orphan-test-suites.sh` exits 0.
- [ ] Measured gate before ship: `bash scripts/test-all.sh --affected` (the runner is the changed file, so
  expect the degraded-full fallback; allow the long run).
- [x] **Dry run on the branch (`gh workflow run main-health-monitor.yml --ref
  feat-one-shot-11939-main-health-scripts-shards -f dry_run=true`):** every leg including scripts 1-8 and
  scripts-heavy 1-3 reaches `success` and the three originally failing suites show `[ok]` in the leg
  captures. The dry run skips tracker/heartbeat by construction (`inputs.dry_run` guards), so it proves
  the legs, not the alert path.
- [ ] **PR keyword:** `Closes #11939` only if the dry run above is fully green; otherwise `Ref #11939`
  (the monitor auto-closes its own tracker on the next green scheduled run). Post-merge: confirm the next
  scheduled run is green; if red the monitor re-files, which is the correct behaviour.
- [x] Unmodified: alert predicates, `.github/workflows/main-health-monitor.yml`, anything under
  Hetzner/Doppler.

## Test Scenarios

- Given `TEST_GROUP=scripts` in the caller's environment, when the runner runs a registered probe suite,
  then the probe's environment has no `TEST_GROUP` (unit, sandbox runner).
- Given the group passed positionally (`runner.sh scripts`), when the probe runs, then it reads `absent`
  and the run is GREEN (must-PASS non-canonical, unit).
- Given the demotion line is deleted or reordered after the first registration, when the suite runs, then
  it is RED (mutation rows 1–2, unit).
- Given the monitor's exact shape (`TEST_GROUP=scripts SCRIPTS_SHARD=6/8 bash scripts/test-all.sh`), when
  the shard containing `lint-orphan-test-suites-mutations-a` runs, then C0 and M16 pass (integration,
  deterministic command above).
- Given a branch dry run of the monitor, when all legs finish, then the report job's inputs are all
  `success` (integration, `gh run view <id> --json conclusion`).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — CI/test-runner tooling change.

## Observability

Not applicable: no file under `apps/*/server`, `apps/*/src`, `apps/*/infra` or `plugins/*/scripts` is
edited and no infrastructure surface is introduced (plan Phase 2.9 skip). The change is verified by the
existing monitor leg annotations (`SOLEUR_MAIN_HEALTH <leg>=<outcome>`), which already carry each leg's
verdict, and by the tracker the monitor files on its own.

## Encryption Posture / Architecture Decision / Task Design

Skipped silently: no persistent store or connection is introduced; no architectural decision is made or
reversed (an existing consume-at-coupling convention is extended by one line, ADR-240's sharding is
unchanged); no new autonomous-task surface is created.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or placeholder fails `deepen-plan` Phase 4.6 — this
  one is filled.
- **Do not** "fix" this by adding `env -u TEST_GROUP` to the two failing suites: it greens the monitor and
  leaves every other child spawn (and every developer who exports the variable) exposed; the corpus shows
  the class recurring after exactly that patch.
- Keep the demotion where it is, beside the `unset SCRIPTS_SHARD` line, before the first suite spawn.
  It would also work earlier (the alias and the parse read `$TEST_GROUP` as a shell variable, which `export -n`
  preserves), but the convention keeps the two carrier-consuming lines together; a rename would break the readers.
- The branch dry run is ~40-50 min wall; dispatch it once the runner edit is pushed. It needs the branch
  on origin (the workflow file is read from the dispatched ref).
- After the fix, previously **silently narrowed** suites in the monitor's webplat/bun/infra legs now run
  under the same environment as `ci.yml`. A suite that was green only because its child enumerator was
  narrowed could newly red in the dry run; treat that as a finding, not a regression of this change.

## Deferrals

- The `0/50` main-push red-rate in the tracker body counts `ci.yml` push runs whose test legs are
  elided by `push-dedupe`, so it is blind to monitor-only failures. Alert predicates are out of scope by
  instruction; tracked as #11953 (label `deferred-scope-out`, milestone Post-MVP / Later) for a later,
  explicitly authorised change.

## References

- `.github/workflows/main-health-monitor.yml`, `.github/workflows/ci.yml` (test-scripts)
- `scripts/test-all.sh` (~1177, ~1446, ~4263), `scripts/lint-orphan-test-suites.test.sh` (build_pristine 4b),
  `scripts/lint-orphan-test-suites.sh` (surface 7), `scripts/test-all-group-affected.test.sh`
- Runs: monitor 41549682691, 41587171627; ci.yml merge_group 41576202102 (same SHA as the latter)
- Issues/PRs: #11939 (this), #11952 (draft PR), #9323 (cost of the mutation batteries), #10233 (fixture-dir ratchet failing when `$HOME` is a git repo; same suite family, not this defect), #11119, #11844, #11665, #7902, #9217
