---
title: "fix(infra): make the cron-egress self-heal suite independent of the inherited SIGPIPE disposition"
type: fix
date: 2026-10-04
slug: cron-egress-self-heal-suite-sigpipe-disposition
branch: feat-one-shot-infra-validation-leg-2-red
issue: 9473
closes: 9473
priority: p3-low
domain: engineering
brand_survival_threshold: none
requires_cpo_signoff: false
lane: cross-domain
---

# fix(infra): make the cron-egress self-heal suite independent of the inherited SIGPIPE disposition

## Enhancement Summary

**Deepened on:** 2026-10-04
**Research agents used:** learnings-researcher, DHH, Kieran, code-simplicity and CTO plan review, test-design-reviewer, observability-coverage-reviewer, a verify-the-negative and citation pass, plus a scratchpad prototype of the suite changes (never in the tree).

### Key Improvements

1. Scope cut by review: the forced-default python arm and its rows, the standalone learning file and the 20-run loop were removed, and the first draft's matrix was trimmed from 5 rows to 3 (two different, design-derived rows were added back at deepen, below); the design is one shim guard, one helper and five rows.
2. The forced-ignored rows are now provably routed: the shim records its own SigIgn, closing an equivalent-mutant hole on the fixed shim.
3. Every count in the acceptance criteria was produced by running the prototype: unfixed `119 passed, 2 failed` (default shell) and `117 passed, 4 failed` (CI-like ambient); fixed `121 passed, 0 failed` in both.

### New Considerations Discovered

- The 204800-byte flood size is not load-bearing; the issue's "write more bytes" direction cannot fix this.
- A repo lint for exact-141 assertions without a disposition marker is a plausible follow-up (Taste, in `decision-challenges.md`), not part of this PR.

Spec lacks valid lane: no `specs/feat-one-shot-infra-validation-leg-2-red/spec.md` exists (one-shot path, no brainstorm), so `lane:` defaulted to `cross-domain` (fail-closed). The Phase 2.5 sweep below still concluded no domain is relevant.

## Overview

Infra Validation is red on main: job `deploy-script-tests (2/4)` runs `apps/web-platform/infra/cron-egress-self-heal.test.sh` and the suite prints `self-heal suite: 114 passed, 2 failed`. The two failing rows are the SIGPIPE control (want `141`, got `0`) and the mutant row that re-introduces the early-exiting pipeline. Both went red on the #9451 merge (`2afe2e1746`, run 37190362475) and the #9448 merge (`7a58d1935b`, run 37192796400), deterministically, and both pass on a developer shell.

The cause is the **inherited SIGPIPE disposition**, not timing. The suite's `nft` shim (`sigpipe` branch) floods 200 KB after `cat out; sleep 0.3` and relies on the shim itself dying of SIGPIPE (rc 141) once `grep -q` has exited. That holds only when SIGPIPE has its default disposition. GitHub Actions starts jobs with SIGPIPE ignored, so the flood's writes fail with EPIPE, the shim carries on to `exit "$(cat $k.rc)"` (0), and the old-form pipeline reads 0. Reproduced locally: `bash -c "trap '' PIPE; bash apps/web-platform/infra/cron-egress-self-heal.test.sh"` gives exactly `114 passed, 2 failed`; without the wrapper it is `116 passed, 0 failed`.

The fix is test-only and one line in the shim: turn a failed flood write into the status SIGPIPE death would have given (`|| exit 141`). It lands test-first: five new rows force SIGPIPE-ignored on entry, so the suite is red on the unfixed shim on **any** machine, not only on the CI runner. The production resolver (`cron-egress-resolve.sh`, the capture form) is untouched.

This PR is CI-test-only. It changes no production behaviour, reads no secrets and writes nothing to production.

## Research Insights

### Premise Validation (Phase 0.6)

- Issue **#9473** (open, `type/chore`, `priority/p3-low`) is the tracker for exactly this red; this PR closes it. Its body says "the cause is not established here; a producer that finishes before the reader closes the pipe is the likely one" and suggests "make the producer write more than one pipe buffer". Both are **superseded by the verified diagnosis**: the shim already writes 200 KB (3x a 64 KiB pipe buffer), the failure reproduces deterministically under an ignored SIGPIPE and does not reproduce under a default one. More bytes would not help; the writes already fail.
- `apps/web-platform/infra/cron-egress-self-heal.test.sh` exists on `origin/main` (579 lines); the `sigpipe` shim branch, the control row and the `mut_probe` mutant row exist at the cited places. The suite is in the guard-vacuity-floor `PROMOTED_FILES` list.
- Run `37192796400` is `failure` with `deploy-script-tests (2/4)` and `deploy-script-tests-done` red (verified with `gh run view`).
- ADR corpus: no ADR covers SIGPIPE-disposition handling for infra test shims, and the mechanism (a test double normalising a write failure to the status the signal would give) is in no rejected-alternatives table. Nothing to reconcile.
- Cited by the brief but explicitly out of scope: the earlier red at `b77bee370` (a different job, `deploy-script-tests-fixed`, "Rung-2 evidence freshness") and `c6ae165d0e` (leg 4/4). Neither is this defect; they are tracked separately and not touched here. The Inngest backlog (#9462, #9387, #9343, #9312) is not part of this PR.

### Property List and Cut List (Phase 0.6b)

Properties the work must buy (the ask proposes a shim edit and a regression arrangement; these are the outcomes underneath):

1. The self-heal suite is green on a runner that starts jobs with SIGPIPE ignored (the red on main goes away).
2. The SIGPIPE control and the early-exit-pipeline mutant row give the **same verdict on a developer shell (default disposition) and on a CI runner (ignored)**, so the pair of rows means the same thing on both hosts.
3. A future regression of (1) is red locally on the unfixed shim without needing the CI runner or an external `trap '' PIPE` wrapper.
4. The forced disposition in (3) is itself proven (a row fails if the "ignored" arrangement did not take effect), so the new rows cannot go vacuously green.
5. The production resolver is unchanged.

Cut List:

| Mechanism | Property it would buy | What already covers it / why cut |
|---|---|---|
| `trap - PIPE` in the suite to re-enable SIGPIPE | 1 | Impossible: bash cannot re-enable a signal that was ignored on entry (POSIX). Not researched further. |
| A python `subprocess` arm that forces SIGPIPE **default** on entry, plus its canary and the default-mode copies of every new row (in the first draft of this plan) | 2 | Cut at plan review (DHH P1, code-simplicity): the default disposition is the ambient of every developer shell, and the existing ambient rows already assert it there; CI's ambient plus the forced rows assert the ignored side. Each host covers one half in every run, both halves are asserted in a normal dev-then-CI cycle, and the python dependency, the `restore_signals` quirk and the 128+n exit-status mapping disappear. The trade-off is that no single run asserts both; recorded in the Guard Contract Assembly. |
| Self-re-exec of the whole suite under an ignored SIGPIPE (a second full 6-7 s run) | 2, 3 | The forced rows buy the same property for the only rows that depend on it. The full-suite check is an acceptance criterion (run under both ambients once). |
| `echo \|\| exit 141` on the trailing newline write (in the brief's proposed fix) | 1 | Unreachable after the flood guard: if the flood's write failed the shim has already exited 141, and if it succeeded the reader is still reading. An equivalent mutant (no edit to it can turn a row red). Only the flood pipeline carries the guard. |
| Runner-wide SIGPIPE normalisation in `run-registered-suites.sh` (restore default for all ~140 suites) | 1 | Rejected: it would hide, not fix, suites whose subject is behaviour under the runner's real environment (`main-health-monitor` runs the same suites on the same kind of runner), and changes the blast radius of every leg. CTO devex review (advisory) concurred. |
| Raising the flood size or removing `sleep 0.3` (the issue's suggested direction) | 1 | Does not address the cause (see Premise Validation). |
| A new standalone learning file | - | Cut at plan review (DHH, code-simplicity): this is a recurrence of the 2026-08-20 learning's Instance 3b. The new content is appended to that file as Instance 3c. |

### Fleet sweep: does any other registered infra suite depend on a default SIGPIPE disposition?

Requested by the brief; the fix is not widened unless a deterministic failure is found. Method: (a) static grep of `apps/web-platform/infra/**.test.sh` for `SIGPIPE`, `141` and flood producers (`/dev/zero`, `yes |`, `flood`, `seq 1 <5+ digits>`); (b) run each of the 30 flood-producing suites twice, once on a default shell and once under `bash -c "trap '' PIPE; exec bash <suite>"`, 150 s cap, comparing exit codes.

- Static: 40 suites mention SIGPIPE, almost all in comments explaining why they avoid `producer | grep -q`. Only five observe the signal status: `cron-egress-ghcr-probe.test.sh` (accepts `141` OR `1`, with a comment naming GitHub Actions: already correct), `cron-egress-firewall.test.sh` (tolerates `28|141` for a race), `scripts/sigpipe-triage-feasibility.test.sh` (`run_probe_sigpipe_default`, restores the default via python `subprocess`), `workspaces-luks-wipe.test.sh` (`W_DD_RC=141` is a stubbed value, not an observed signal), and this suite.
- Empirical: 23 suites exited 0 in both modes; 3 exited 2 in both modes (the privileged loopback suites need root and run in a privileged CI job: **unverified here, not cleared**); 4 hit the 150 s cap in both modes (`ci-deploy`, `cloud-init-inngest-provision-unit`, `git-data-cutover-access`, `run-registered-suites`; inconclusive, but none of them observes a signal status). **No suite changed its exit code between the two dispositions.**
- Conclusion: this suite is the only one whose control row asserts an exact `141` from an uncooperative shim. No second deterministic failure, so the fix stays in this one file.

### Institutional learnings applied

- `knowledge-base/project/learnings/2026-08-20-the-check-failed-because-the-thing-it-checked-for-was-there.md` (Instance 3b): documents the two dispositions (default = signal 13 = 141; ignored = `write()` EPIPE = exit 1), says "verify a host-sensitive assertion under both dispositions before pushing" and names `( trap '' PIPE; <suite> )` as the local reproduction. The #9451 author did not apply it; this plan turns it into standing rows. That learning chose "assert non-zero, not 141"; here the **shim owns the contract** (it emulates SIGPIPE death, so it normalises to 141) and the assertion stays exact, which keeps the row title ("returns 141") true on every host.
- `knowledge-base/project/learnings/test-failures/2026-09-23-my-sigpipe-regression-guard-pinned-the-file-size-not-the-cause.md`: pin the causal quantity, not a proxy. The causal quantity is the disposition, so the rows pin the disposition (proven by a `/proc` canary), not a byte count or a timing. Prototype confirmed the 200 KB size is not load-bearing (see Risks).
- `knowledge-base/project/learnings/2026-10-04-a-new-suite-is-invisible-to-repo-ratchets-until-tracked-and-my-fix-moved-the-event-behind-a-hang.md`: mutation rows must mutate (non-empty, differing from pristine); ratchets read `git ls-files` (the suite is already tracked, so `guard-vacuity-floor` sees the edit).
- `scripts/guard-vacuity-floor.test.sh` (line ~779): this suite is `PROMOTED_FILES`; its floors are `-lt` over its own verdict count with the bound as a **literal on the `if` line**, reported by `printf` + `exit 1`. Keep that form.

### Prototype (scratchpad only, not in the tree)

The design was prototyped on a copy of the suite outside the repo (`hr-verify-repo-capability-claim-before-assert`):

| Arrangement | Default ambient | Ignored ambient (`trap '' PIPE` wrapper) |
|---|---|---|
| Unfixed shim + the 5 new rows | `119 passed, 2 failed (121 cases)`: the two "SIGPIPE ignored" rows | `117 passed, 4 failed (121 cases)`: those two plus the two existing ambient rows |
| Fixed shim (`{ head ... \| tr ...; } 2>/dev/null \|\| exit 141`) + the 5 new rows | `121 passed, 0 failed` | `121 passed, 0 failed`, no "Broken pipe" text |

Counts above are for the final design (five new rows, including the routing proof added at deepen-plan). Mutation spot-checks on the fixed prototype: neutering the `trap '' PIPE` in the helper turns only the canary red (`119 passed, 1 failed` in the four-row draft); a wrong status (`|| exit 1`) turns the control rows red; making the guard unconditional (`; exit 141`) turns the two capture-form rows red (they read `unreadable`); dropping the `probe_out` prefix turns the routing row and the ignored mutant row red; deleting the guard reproduces the unfixed counts.

## Research Reconciliation: Brief and Issue vs. Codebase

| Claim | Reality | Plan response |
|---|---|---|
| Issue #9473: "likely a producer that finishes before the reader closes the pipe; write more than one pipe buffer" | The shim already writes 200 KB; failure is deterministic and tracks the inherited disposition (reproduced both ways) | Fix the disposition dependence, not the byte count. Correct the issue when the PR closes it. |
| Brief: "`head -c ... \| tr ... \|\| exit 141` **and** `echo \|\| exit 141`" | The `echo` guard is unreachable once the flood guard exists (equivalent mutant) | Only the flood pipeline gets `\|\| exit 141`; a `2>/dev/null` group keeps "Broken pipe" lines out of the CI log. |
| Brief: "the `TABLE_ROWS -lt 25` floor ... literal on the line directly above its `if`" | In this file the literal is **inline on the `if` line**, the form `scripts/guard-vacuity-floor.test.sh` documents and pins for this file. The "line above" form is for floors that read a variable. | Keep every floor in its existing inline-literal form; no variable thresholds, no comment between a floor and its `if`. If a variable threshold is ever introduced, its literal goes on the line directly above the `if`. Verified by running `guard-vacuity-floor.test.sh` (AC). |

## Problem Statement

`deploy-script-tests` is advisory (not in `ruleset-ci-required.tf`) but every infra change to main reads a red shard, which trains everyone to ignore the shard and masks the next real failure. The cause is a test double whose behaviour (die of SIGPIPE) depends on a process attribute the suite never sets or checks (the inherited signal disposition). A host that differs from a developer shell makes the control row measure nothing, and the mutant row anchored on it stops telling a regression from a respelling.

## Proposed Solution

1. **Shim contract.** In the `sigpipe` branch of the `nft` shim, guard the flood with `|| exit 141`, so "the reader hung up" yields rc 141 under a default disposition (the producer dies of SIGPIPE; same status) and under an ignored one (the EPIPE write failure exits 141). A `{ ...; } 2>/dev/null` group keeps stderr clean. A short contract comment points at the 2026-08-20 learning and must not quote the guarded literal (the discoverability probe counts it).
2. **Forcing helper.** `with_sigpipe_ignored cmd...` is `( trap '' PIPE; exec "$@" )` (an ignored signal survives `exec`). It wraps **external commands only** (`env -i ...`, `bash -c ...`): `exec` cannot run a shell function.
3. **Prove the forcing.** `SIGPIPE_PROBE` reads `SigIgn` from `/proc/$$/status` (signal 13 is mask `0x1000`) and prints `ignored` / `default` / `unknown`. One canary row asserts `with_sigpipe_ignored bash -c "$SIGPIPE_PROBE"` prints `ignored`; `unknown` (no `/proc`) fails loud.
4. **Five new rows** (a block headed "SIGPIPE ignored on entry (forced, not ambient)", with the local reproduction one-liner in a comment): the canary; the OLD `nft | grep -q` form returns 141 with SIGPIPE ignored; the capture form on the reproducer shim still reads `present|present|present|0|0|false|false|false` with SIGPIPE ignored (this row passes on the unfixed and the fixed shim by design: it pins the other half of the contract, that the guard must not fire when the reader does not hang up, and it covers the production capture form under an ignored disposition); a **routing proof** (the shim itself records its own SigIgn into `$SC/shim.sigign` on the `sigpipe` branch, before the flood, and the row asserts it read `ignored` when `probe_out` ran with the knob set); and the early-exit-pipeline mutant changes the SIGPIPE row with SIGPIPE ignored. `probe_out` gains a `${PROBE_SIGPIPE_IGNORED:+with_sigpipe_ignored}` prefix on its `env -i` call and `mut_probe` passes a `MUT_SIGPIPE_IGNORED` knob through to it; when the knob is set, `mut_probe` also requires `shim.sigign` to read `ignored`, so a dropped knob cannot leave the mutant row green. The existing ambient control and mutant rows stay. The shim's recording is two lines inside its existing `sigpipe` branch and reads `/proc/$$/status` with the `read` builtin (`$$` is the shim's own bash; the mask test is `(( 0x$sv & 0x1000 ))`).
5. **Floors.** Verdict count 116 to 121 (the floor literal and its printf message); mutation rows: the floor literal 23 to 24 (one new mutant row; the slack over the actual count is unchanged). `TABLE_ROWS` is unchanged (the new capture-form row is a `check`, not a `row`), so its `-lt 25` stays.
6. **Learning.** Append "Instance 3c" to the 2026-08-20 learning (Phase 4).

## Files to Edit

- `apps/web-platform/infra/cron-egress-self-heal.test.sh`: add `with_sigpipe_ignored` + `SIGPIPE_PROBE` near `okc()`; prefix `probe_out`'s `env -i`; add the five-row block after the existing control; add the `MUT_SIGPIPE_IGNORED` knob (with its `shim.sigign` check) and one mutant row; record `shim.sigign` and fix the flood in the `sigpipe` shim branch; bump the `116` and `23` floor literals in place (inline, on their `if` lines); add a one-line local-reproduction comment to the header.
- `knowledge-base/project/learnings/2026-08-20-the-check-failed-because-the-thing-it-checked-for-was-there.md`: append Instance 3c (Phase 4).

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-infra-validation-leg-2-red/tasks.md` (planning artifact).
- `knowledge-base/project/specs/feat-one-shot-infra-validation-leg-2-red/decision-challenges.md` (one Taste item from plan review, below).

Not touched, by decision: `apps/web-platform/infra/cron-egress-resolve.sh` (production capture form), `scripts/guard-vacuity-floor.test.sh` (its `PROMOTED_FILES` already lists this suite), `.github/workflows/infra-validation.yml`, `apps/web-platform/infra/run-registered-suites.sh`, `plugins/soleur/skills/review/SKILL.md` (about 45 bytes under its byte ceiling: no prose goes there).

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` (200 issues) was searched for `apps/web-platform/infra/cron-egress-self-heal.test.sh` and `apps/web-platform/infra/cron-egress-resolve.sh`; no body names either path. Related but separate (acknowledged, not folded in): #9460 (an operator-ack-guard assertion that false-reds via `awk | grep -q` SIGPIPE under pipefail: a default-disposition race in a different suite) and #9325 (printf SIGPIPE flakes in the luks-monitor and cutover-inngest-workflow suites). Different suites, different mechanism, own cycles.

## Implementation Phases

### Phase 1: RED first (cq-write-failing-tests-before)

Do not add the `|| exit 141` guard in this phase. The only shim edit allowed here is the two-line `shim.sigign` recording at the top of the `sigpipe` branch (it observes, it does not change the exit status).

1. Add the helper, the canary, the `probe_out` prefix, the `shim.sigign` recording, the five-row block and the `MUT_SIGPIPE_IGNORED` knob with its mutant row, as in Proposed Solution items 2 to 4. Do not bump the floors yet.
2. Run the suite on a default shell. Expected and to be captured: **exactly two `FAIL:` lines** (`control, SIGPIPE ignored: ...` want `141` got `0`; `mutant caught: SIGPIPE ignored: ...`) and `self-heal suite: 119 passed, 2 failed (121 cases)`, rc 1. That is the red, reproducible on a laptop.
3. Run it under the ambient CI disposition: `bash -c "trap '' PIPE; bash apps/web-platform/infra/cron-egress-self-heal.test.sh"`. Expected: four `FAIL:` lines (the two existing ambient rows plus the two forced discriminating rows), `117 passed, 4 failed (121 cases)`.
4. Keep the red state in a local commit or capture the output for the PR description; do not push a red-only commit.

### Phase 2: GREEN

1. Fix the shim branch:

   ```bash
   if [[ -f "$SC/$k.sigpipe" ]]; then
     cat "$SC/$k.out"; /usr/bin/sleep 0.3
     { head -c 204800 /dev/zero | tr '\0' 'x'; } 2>/dev/null || exit 141
     echo
     exit "$(cat "$SC/$k.rc" 2>/dev/null || echo 0)"
   fi
   ```

   Add a short comment above it: a reader that hung up yields rc 141 under either inherited disposition (SIGPIPE death under a default one, the EPIPE write failure under an ignored one); see the 2026-08-20 learning, Instance 3b.
2. Bump the floors in place: `-lt 116` to `-lt 121` with the printf's `expected >= 116` to `121`, and `-lt 23` to `-lt 24` with its message. Each literal stays on its `if` line.
3. Re-run both ambients (expected output in Acceptance Criteria).

### Phase 3: ratchets and lint

1. `bash scripts/guard-vacuity-floor.test.sh` on the edited tree.
2. `python3 scripts/lint-guard-contract.py` (it walks `knowledge-base/project/plans/**`).
3. markdown lint on the plan, tasks and the edited learning (no doubled blank lines), and `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main`.
4. `shellcheck` on the suite if available (the header already disables SC2016, SC2329, SC2319; the new code must not need new disables).

### Phase 4: learning

Append Instance 3c to the 2026-08-20 learning: the recurrence (that learning already had the table and the `( trap '' PIPE; <suite> )` tip; #9451 shipped without applying it), the wrong first diagnosis in #9473 (timing; the shim already wrote 200 KB and the size is not load-bearing), the reusable arrangement (`with_sigpipe_ignored` plus a `/proc` `SigIgn` canary so a forced disposition is proven), and the rule of thumb: a test double that emulates a signal death owns the normalisation to the signal's status. Name this suite's helper by path as the pattern to copy, and say to extract it into a shared sourced lib only when a third suite needs it. No AGENTS.md rule (`cq-agents-md-tier-gate`: the violation can only occur while authoring a bash test double, which the learning covers).

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing. The worst case is that the advisory `deploy-script-tests (2/4)` shard stays red or turns falsely green, which affects maintainers reading CI, not any product user.
- **If this leaks, the user's data / workflow / money is exposed via:** no vector. The change edits a bash test double and test rows; it reads no credential, calls no network endpoint and writes nothing outside a `mktemp -d` fixture directory.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** `none`, because the change is confined to a CI test file for a shim, with no production code path, secret or user-visible artifact; the next tier up would need a path from this diff to a user, and there is none.

`threshold: none, reason: the diff touches apps/web-platform/infra/ only as a bash test suite (a *.test.sh with an nft shim in a mktemp fixture), not the host-provisioning, firewall or loader code the suite exercises, and it reaches no user data or production resource.`

## Observability

This is a CI-test-only change; there is no new runtime surface to instrument. The signal that matters is the existing CI one: the `deploy-script-tests (2/4)` shard result, aggregated by `deploy-script-tests-done` and independently re-run by `main-health-monitor`, which files a P1 `ci/main-broken` issue when the infra suites are red on main.

```yaml
liveness_signal:
  what: "GitHub Actions job 'deploy-script-tests (2/4)' conclusion on main, aggregated by 'deploy-script-tests-done'; the suite's own final ledger line 'self-heal suite: N passed, 0 failed'"
  cadence: "per push to main and per infra PR; main-health-monitor re-runs the infra suites every 6 hours"
  alert_target: "red Infra Validation check on the PR/main commit; main-health-monitor files a P1 ci/main-broken GitHub issue"
  configured_in: ".github/workflows/infra-validation.yml (deploy-script-tests, deploy-script-tests-done) and .github/workflows/main-health-monitor.yml"

error_reporting:
  destination: "GitHub Actions job log and annotations from apps/web-platform/infra/run-registered-suites.sh (per-suite PASS/RED plus ::error); no Sentry (a CI test has no DSN)"
  fail_loud: "the suite exits 1 and prints 'FAIL: <row label> (want=... got=...)' plus the accounting line"

failure_modes:
  - mode: "the shim stops yielding 141 under an ignored SIGPIPE (the guard is removed or weakened)"
    detection: "rows 'control, SIGPIPE ignored' and 'mutant caught: SIGPIPE ignored' go RED on any machine, not only in CI; surfaced in the workflow run log as an '::error::' annotation from run-registered-suites.sh"
    alert_route: "red check on the PR; main-health-monitor P1 issue if it reaches main"
  - mode: "the forcing helper silently stops forcing (a vacuously green pair of rows)"
    detection: "the 'harness canary' row and the 'routing' row read SigIgn from /proc and go RED; surfaced in the workflow run log as an '::error::' annotation from run-registered-suites.sh"
    alert_route: "red check on the PR"
  - mode: "a row is deleted to make the suite pass"
    detection: "the anti-vacuity floor (verdicts >= 121) and the PASS+FAIL==CASES identity exit 1, surfaced in the workflow run log as an '::error::' annotation from run-registered-suites.sh; scripts/guard-vacuity-floor.test.sh measures that the floor still fires under neutering"
    alert_route: "red check on the PR"

logs:
  where: "the GitHub Actions job log for the leg; per-suite logs retained as the infra-suite-logs-N artifact on failure"
  retention: "14 days (upload-artifact retention-days in infra-validation.yml)"

discoverability_test:
  command: "grep -c -F '2>/dev/null || exit 141' apps/web-platform/infra/cron-egress-self-heal.test.sh"
  expected_output: "1"
```

The discoverability probe is a static anchor on the one line that carries the fix, because preflight Check 10 executes the command in a 15 s sandbox and a whole suite is the wrong shape for it. Comments in the suite must not quote that literal, or the count changes. Check 10 runs only at ship time, after Phase 2 has landed the fix; the count is 0 on the pre-fix tree and that is expected. The behavioural evidence is the red-to-green suite run in Acceptance Criteria.

## Guard Contract

### Guard 1 — SIGPIPE-ignored-on-entry rows for the reproducer shim

**Property.** The control row and the early-exit-pipeline mutant row return the same verdict whether SIGPIPE is default (a developer shell) or ignored (a CI runner) on entry, and a loss of that property turns the suite red on any machine.

**Assembly.** The property quantifies over: (a) the two dispositions, where "ignored" is forced through the single chokepoint `with_sigpipe_ignored` (proven twice: by the `/proc` `SigIgn` canary on the helper, and by the shim recording its own `SigIgn` through the real `probe_out` and `mut_probe` call paths) and "default" is the ambient of a developer shell, asserted by the pre-existing ambient control and mutant rows; on a CI runner the ambient is itself ignored, so there the forced rows duplicate the ambient ones and the default half is not asserted in that run (accepted, see the Cut List); (b) every call site that runs a probe or the old-form pipeline: `probe_out` (used by `row`, the SIGPIPE table row and `mut_probe`, prefixed via `PROBE_SIGPIPE_IGNORED`) and the control; (c) the single shim branch (`$SC/$k.sigpipe`) that both chain reads (`k=jump`, `k=chain`) share, so one guarded flood covers both; (d) the floors that keep the new rows counted (`-lt 121` verdicts, `-lt 24` mutation rows). The members that can drift are the call sites in (b); the chokepoint is `with_sigpipe_ignored`.

**Mutation matrix:**

| # | Mutation (applied to a scratch copy of the suite, literal replace asserted to land) | Expected |
|---|---|---|
| 1 | Revert the fix: delete `\|\| exit 141` from the shim's flood line | RED: `control, SIGPIPE ignored` and `mutant caught: SIGPIPE ignored` fail; the ambient rows stay green on a default shell (proves the forced rows are what discriminate) |
| 2 | Own dispatch: neuter the helper (`( trap '' PIPE; exec "$@" )` becomes `( exec "$@" )`) | RED: `harness canary: with_sigpipe_ignored really runs with SIGPIPE ignored` fails (a vacuous forced-ignored set cannot stay green). Valid only when run from a default-ambient shell: on a CI runner the ambient is already ignored, so a neutered helper still reads `ignored`; run and record it locally |
| 3 | Wrong status: replace `\|\| exit 141` with `\|\| exit 1` (the "assert non-zero" trap from the 2026-08-20 learning, inverted) | RED: the old-form control rows (ambient and forced) read 1 |
| 4 | Unconditional guard: replace `\|\| exit 141` with `; exit 141` | RED: the capture-form rows (ambient table row and forced row) read `unreadable`, because the shim now exits 141 even when the reader never hung up |
| 5 | Routing: drop the `${PROBE_SIGPIPE_IGNORED:+with_sigpipe_ignored}` prefix in `probe_out` | RED: the routing row reads `default` and the ignored mutant row fails its `shim.sigign` requirement (otherwise an equivalent mutant on the fixed shim) |

**Harness rows.** Mutations 2 and 5 are edits to the suite itself, not the system under test. The must-PASS input that is not the canonical run: the whole suite started under an ignored ambient (`bash -c "trap '' PIPE; bash <suite>"`) must read `121 passed, 0 failed`, as must the default ambient; a harness that only worked under one ambient would fail one of the two.

**Anchor.** The floors are stored counts in the same file as the rows, so one diff can lower both and pass. What sits outside the commit: `scripts/guard-vacuity-floor.test.sh` measures that each floor in this file is constructible and fires under neutering (it does not pin the number), and the reviewer reads the floor literals in the PR diff. No independent registry exists and none is added: `deploy-script-tests` is advisory, and the new rows are named in this plan so a deletion shows up as a missing name, not just a smaller number.

## Review Amendment (2026-10-04)

Appended after the 7-seat review; the sections above are the pre-implementation record. Where they differ, this section and the code win.

- The default half is now forced too, not left to the ambient: `with_sigpipe_default` (python restores the default, which bash cannot). The "Cut List" row that dropped the python arm is superseded for the helper only; the rationale was the cost of a second helper, and the review (structural-enumeration and test-design seats) showed that on a CI runner the ambient is itself ignored, so the default half was asserted by no run there.
- Six rows were added on top of the original five (final count: 127 verdicts). The mutation-row floor moves 24 to 25 only because the actual count was already 25 (the harmless-respelling row counts); no mutation row was added, it removes a pre-existing slack of one. The six: a canary for `with_sigpipe_default`, a canary negative control (ignoring only SIGINT does not read as SIGPIPE ignored), a routing proof for the direct forced-ignored control, a forced-default old-form control with its own routing proof, and a recorder negative control (the shim records `default` under a default disposition). The shim records `unknown` without `/proc`, and the `/proc/<pid>/status` read is a one-shot snapshot (the line-by-line read returned no `SigIgn:` line in about 1 of 600 runs under load, measured by the fix-round test-design seat).
- Guard Contract assembly, corrected: `probe_out` is forced by `PROBE_SIGPIPE_IGNORED` only for the capture-form row and the forced mutant row (the `row()` table row stays ambient, with the forced twin beside it). The forced-ignored control is a direct call and carries its own routing proof. The shared sigpipe shim branch is reachable only through the jump flag (no chain-side flood is wired). Known and accepted: a new sigpipe-sensitive row added by following the pattern without a forced twin passes; asserting that every row is disposition-independent would need the whole-suite re-exec the Cut List rejected.
- Not changed, with reasons: the `2>/dev/null` on the flood group stays (it keeps `tr`'s EPIPE text out of the CI log; no row asserts stderr, and the discoverability probe pins the literal); an unknown `scenario()` flag being silently ignored is a pre-existing suite-wide property, not SIGPIPE-specific.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Fix the red Infra Validation workflow on main: job `deploy-script-tests (2/4)`, suite apps/web-platform/infra/cron-egress-self-heal.test.sh." | Phase 2 shim fix; Files to Edit entry | mapped |
| 2 | "make the sigpipe shim branch disposition-independent by turning a failed write into the same status SIGPIPE death gives" | Phase 2 step 1 (refined: only the flood pipeline is guarded; see Cut List) | mapped |
| 3 | "Keep the production resolver (the capture form) untouched." | "Not touched, by decision"; AC (no diff on `cron-egress-resolve.sh`) | mapped |
| 4 | "Test-first (rule cq-write-failing-tests-before): add a regression row/arrangement BEFORE the fix" | Phase 1 | mapped |
| 5 | "State the red→green evidence the work phase must capture." | Phase 1 steps 2-3, Acceptance Criteria evidence block | mapped |
| 6 | "Also consider whether the whole suite should self-assert it behaves the same under an ignored SIGPIPE." | Cut List (self-re-exec rejected; replaced by the four forced rows plus the both-ambients acceptance run) | mapped |
| 7 | "Also check (cheaply, report in the plan): whether any other registered infra suite under apps/web-platform/infra/*.test.sh relies on a default SIGPIPE disposition" | Research Insights, fleet sweep | mapped |
| 8 | "Do not widen the fix beyond this suite unless the grep finds another deterministic failure." | Fleet sweep conclusion; Files to Edit lists one code file | mapped |
| 9 | "mention them in the plan as out of scope / separately tracked, do not fix them here." | Premise Validation (b77bee370, c6ae165d0e) and Out of Scope | mapped |
| 10 | "This PR is ONLY the SIGPIPE-disposition fix (plus its regression test and a learning if the plan calls for one)." | Phase 4 learning (appended, not a new file); Out of Scope | mapped |
| 11 | "Guards that have bitten before: markdown-lint (no doubled blank lines); guard-vacuity-floor ...; do not add prose to plugins/soleur/skills/review/SKILL.md" | Phase 3, AC, "Not touched" list | mapped |
| 12 | "The plan must include the standard sections the plan skill requires (Acceptance Criteria etc.), and the observability/User-Brand-Impact gates apply as the skill defines" | User-Brand Impact, Observability, Acceptance Criteria | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Edit `cron-egress-self-heal.test.sh` (shim guard, helper, four rows, floors) | "Fix the red Infra Validation workflow on main: job `deploy-script-tests (2/4)`, suite apps/web-platform/infra/cron-egress-self-heal.test.sh." | asked |
| Forced-ignored control, capture-form and mutant rows | "add a regression row/arrangement BEFORE the fix that runs the control (and ideally the sigpipe table row + the mutant) with SIGPIPE ignored on entry" | asked |
| `/proc` `SigIgn` canary row | "so the suite itself is red under the ambient CI disposition on the unfixed shim and green after" | inferred - justification: a forced-ignored arrangement is only evidence if it is proven to be ignored, otherwise the new rows can go vacuously green (the vacuity class the repo's guard rules exist for) |
| Floor bumps (116 to 121, 23 to 24) | "guard-vacuity-floor (a floor's threshold literal must sit on the line directly above its `if` ...)" | inferred - justification: the anti-vacuity floor must track the verdict count or deleting the new rows would pass; the quoted ask constrains floor placement, not whether to bump |
| Append Instance 3c to the 2026-08-20 learning | "plus its regression test and a learning if the plan calls for one" | asked |
| Shim `SigIgn` recording and the routing row | "add a regression row/arrangement BEFORE the fix that runs the control (and ideally the sigpipe table row + the mutant) with SIGPIPE ignored on entry" | inferred - justification: the canary proves the helper, not that `probe_out` and `mut_probe` apply it; without the routing proof a dropped prefix leaves the ignored rows green on the fixed shim (test-design review, P1) |
| `tasks.md` and `decision-challenges.md` | "The plan must include the standard sections the plan skill requires" | inferred - justification: plan skill Save Tasks derives tasks.md; the headless plan-review route persists Taste items to decision-challenges.md for `ship` |

### Split Assessment

- Subsystems touched: 1 - `apps/web-platform/infra/` (test suite) plus knowledge-base artifacts
- Planned files: 4 (2 edited, 2 created) | Estimated changed lines: about 35 added, 5 changed
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

### Pre-merge (PR)

Evidence the work phase must capture (paste the literal lines into the PR description under a "Red to green" heading):

- [x] **RED, default ambient, before the shim fix:** `bash apps/web-platform/infra/cron-egress-self-heal.test.sh` prints exactly two `FAIL:` lines, `control, SIGPIPE ignored: ... (want='141' got='0')` and `mutant caught: SIGPIPE ignored: ...`, and `self-heal suite: 119 passed, 2 failed (121 cases)`, rc 1.
- [x] **RED, ambient CI disposition, before the shim fix:** `bash -c "trap '' PIPE; bash apps/web-platform/infra/cron-egress-self-heal.test.sh"` prints four `FAIL:` lines (the existing ambient `control: the OLD 'nft | grep -q' form ...` and `mutant caught: the capture is re-introduced as an early-exiting pipeline ...`, plus the two forced rows), `117 passed, 4 failed (121 cases)`.
- [x] **GREEN, default ambient, after the fix:** `self-heal suite: 121 passed, 0 failed (121 cases)`, rc 0.
- [x] **GREEN, ignored ambient, after the fix:** the same line from `bash -c "trap '' PIPE; bash apps/web-platform/infra/cron-egress-self-heal.test.sh"`, rc 0, with no `Broken pipe` text in the output.
- [x] The harness canary row and the routing row PASS in both ambients.
- [x] Run the suite 5 times under each ambient, 0 failures (about 70 s total; each run piped through `tail -1`, and issued as a background or split command because the single-call tool timeout is 120 s).
- [x] Mutation spot-checks 1 to 5 from the Guard Contract were run against a scratch copy and went RED as stated (paste the failing row names; run #2 from a default-ambient shell); the working tree is not left mutated.
- [x] `git diff origin/main -- apps/web-platform/infra/cron-egress-resolve.sh` is empty (production resolver untouched), and `git diff --stat origin/main` lists only the suite, the 2026-08-20 learning and the planning artifacts (plan, tasks.md, decision-challenges.md).
- [x] `bash scripts/guard-vacuity-floor.test.sh` exits 0 on the edited tree; every floor in the suite is still a literal on its `if` line (`grep -nE '(-lt|-ge) [0-9]+' apps/web-platform/infra/cron-egress-self-heal.test.sh` shows only inline literals) and no comment sits between a floor and its `if`.
- [x] `grep -c -F '2>/dev/null || exit 141' apps/web-platform/infra/cron-egress-self-heal.test.sh` prints `1` (the discoverability probe).
- [x] `python3 scripts/lint-guard-contract.py` passes with this plan's contract counted (1 entry, 5 matrix rows).
- [x] markdown lint is clean on the plan, tasks.md and the edited learning (no doubled blank lines, fenced blocks carry a language), and `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` (CI's own invocation, not a hand-listed path set) reports no violation once the artifacts are committed.
- [x] `plugins/soleur/skills/review/SKILL.md` is not in the diff.
- [ ] The PR body contains `Closes #9473` and a one-line correction that the issue's "producer finishes before the reader" hypothesis was not the cause.

### After merge (verified by command)

- [ ] The Infra Validation run on the merge commit shows `deploy-script-tests (2/4)` green, read with `gh run list --branch main --workflow infra-validation.yml --limit 1` then `gh run view <id> --json jobs`; no dashboard eyeballing. If it is red for a different suite, that is a separate defect (see Out of Scope).

## Test Scenarios

- Given the suite is started with SIGPIPE at its default disposition, when the OLD `nft | grep -q` form runs on the reproducer shim under pipefail, then it returns 141.
- Given SIGPIPE is ignored on entry (the CI runner, or forced), when the same form runs, then it still returns 141 (the shim converts the EPIPE write failure).
- Given `with_sigpipe_ignored`, when the `/proc/<pid>/status` `SigIgn` mask is read, then signal 13 (`0x1000`) is set.
- Given the capture-form probe and the reproducer shim with SIGPIPE ignored, when run, then it reads all three rules `present` with rc 0/0 and `read_failed=false`.
- Given a mutant that re-introduces `| grep -m1` into the probe, when run with SIGPIPE ignored, then the SIGPIPE row changes from pristine.
- Given the shim's `|| exit 141` is removed, when the suite runs on a laptop with no wrapper, then it is red.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected: this is a CI test-double fix inside an infra test suite. No legal, finance, marketing, sales, support or product surface is touched. The Product/UX gate does not fire (no UI-surface file in the Files lists).

## Infrastructure and Architecture Gates

- IaC routing (Phase 2.8): not triggered. No server, unit, secret, vendor account, DNS record or firewall rule is introduced.
- Architecture decision (Phase 2.10): not triggered. No ownership boundary, substrate, trust boundary or ADR is changed or reversed.
- Encryption posture (Phase 2.11): not triggered. No persistent store and no new connection.
- GDPR (Phase 2.7): not triggered. No regulated-data surface, no LLM or external-API processing, no new distribution surface.
- Skill description budget (Phase 1.8): not triggered. No `SKILL.md` description is a candidate.

## Plan Review Disposition

Panel: DHH, Kieran, code-simplicity (eng baseline, threshold `none`) and CTO (devex lens, advisory). Applied (Mechanical, the DHH and code-simplicity panels converged, so delete over fix): the python default-restore arm, the forced-default rows, the second and third Guard Contract rows, the standalone learning file and the 20-run loop were cut; the plan shrank from 8 new rows to 4 and from 5 matrix rows to 3. Applied from Kieran (Mechanical): `exec` cannot run a shell function so the helper wraps external commands only; the mutation-floor wording now says the floor moves 23 to 24 with unchanged slack; the mask is stated as signal 13 / `0x1000`; comments must not quote the probed literal; the loop is sized to the tool timeout. Applied from CTO (Mechanical): a header reproduction one-liner and a shim comment pointing at the learning; the learning names the helper as the pattern to copy. Not applied: DHH's "drop tasks.md and the ask mapping" (skill-mandated artifacts). Persisted to `decision-challenges.md` (Taste, argues for widening the brief's scope): CTO's suggestion of a cheap repo lint for exact-`141` assertions that lack a disposition marker.

## Deepen-Plan Disposition

Mechanical halts all pass: User-Brand Impact present with the sensitive-path scope-out line; Observability present with all five fields and an allowlisted-verb, sub-second, literal-output probe; no PAT-shaped token; no UI surface; no Terraform, migration or cloud-init file so Encryption Posture does not fire; `scripts/lint-guard-contract.py` green; Scope Check present once, unfenced, all three subsections, no `unmapped`. Citation sweep (verify-the-negative agent): issues 9473, 9460, 9325, 9392, 9462, 9387, 9343, 9312 and PRs 9478, 9451, 9448 exist in the states the plan claims; commits `2afe2e1746` and `7a58d1935b` and both runs resolve; the negative claims (no ADR on test-shim disposition, `ruleset-ci-required.tf` has no `deploy-script-tests` context, `main-health-monitor` runs the infra suites via `TEST_GROUP=infra bash scripts/test-all.sh`, the scheduling cron lives in Inngest) all hold. Test-design review found the one real gap: the canary proved the helper but not that `probe_out` and `mut_probe` applied it, so the shim now records its own SigIgn and a routing row plus a `mut_probe` requirement assert it, with two new matrix rows (unconditional guard, dropped prefix) and a caveat that matrix row 2 is valid only from a default-ambient shell. Observability review: failure-mode detections now cite the workflow run log annotation, and the probe note states that the count is 0 pre-fix by design. The simplification pressure from plan review was kept: no python arm, no forced-default rows.

## Risks and Sharp Edges

- The helper is `( trap '' PIPE; exec "$@" )`. Keep the `trap` and the `exec` adjacent: a command between them would run with SIGPIPE ignored and could fail in a way the `exec`ed command never sees. `exec` cannot run a shell function, so never pass one.
- The 204800-byte flood size is **not** what makes the reproducer work under either disposition: any write after the reader has closed fails (EPIPE or SIGPIPE) regardless of size, and the `sleep 0.3` orders the reader's exit before the flood. Prototype: shrinking the flood to 1024 bytes leaves the suite green, so a size mutation is an equivalent mutant and is deliberately not in the matrix. Do not retune the size as a "fix" (that was #9473's suggestion).
- The `PROBE_SIGPIPE_IGNORED` routing in `probe_out` is invisible to the exit codes on the fixed shim (both dispositions normalise to 141), which is why the shim records its own `SigIgn` and the routing row plus `mut_probe` assert it. Keep that recording; without it, dropping the prefix is an equivalent mutant.
- `/proc/<pid>/status` is Linux-only. The suite already depends on Linux userland (the nft shim, `tr`, `head`), and `unknown` fails loud; do not add a skip branch (a skipped canary is the vacuous-green failure this guards against).
- `PROBE_SIGPIPE_IGNORED=1 probe_out ...` (an env prefix on a shell function) is scoped to the call in bash non-POSIX mode; the suite already uses this idiom (`NFT_RETRY_SLEEP=3 probe_out ...`, `MUT_SLEEP=abc ... mut_probe`). Do not run the suite under `sh` or `set -o posix`. `env -i` strips the variable inside the probe, which is intended: the knob is read by the function, not by the probe.
- A mutation row must mutate: assert that the literal replace landed and that the mutant output is non-empty and differs from pristine (`mut_copy` already does the first two; the new mutant row reuses it).
- The three privileged loopback suites that exited 2 in the fleet sweep need root and run in a privileged job; they are unverified here, not cleared. The sweep proves no *runnable* suite changes verdict with the disposition.
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan fills it (`none`, with the sensitive-path scope-out line).

## Out of Scope

- `b77bee370` red: `deploy-script-tests-fixed`, "Rung-2 evidence freshness": a different job and cause; tracked separately.
- `c6ae165d0e` red: leg 4/4: a different suite and cause; tracked separately.
- The Inngest backlog (#9462, #9387, #9343, #9312).
- #9460 and #9325 (other suites' default-disposition SIGPIPE races).
- Normalising SIGPIPE for the whole runner (`run-registered-suites.sh`): considered and rejected (Cut List); not deferred to an issue because no gap remains once suites are individually correct.

## References

- Issue #9473; PR #9478 (draft, this branch); merged causes #9451 (suite added, Ref #9392) and #9448; runs 37190362475 and 37192796400
- `apps/web-platform/infra/cron-egress-self-heal.test.sh` (shim `sigpipe` branch, `row`, `mut_probe`, control)
- `apps/web-platform/infra/scripts/sigpipe-triage-feasibility.test.sh` (`run_probe_sigpipe_default`, a python restore precedent for the default disposition)
- `apps/web-platform/infra/cron-egress-ghcr-probe.test.sh` (accepts 141 or 1; the sibling fix)
- `knowledge-base/project/learnings/2026-08-20-the-check-failed-because-the-thing-it-checked-for-was-there.md` (Instance 3b)
- `scripts/guard-vacuity-floor.test.sh`, `scripts/lint-guard-contract.py`
