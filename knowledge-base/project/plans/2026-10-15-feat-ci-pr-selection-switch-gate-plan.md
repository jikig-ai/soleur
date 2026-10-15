---
title: "ci: stop paying for the dark pr-selection selector (S4 Q1 follow-up)"
date: 2026-10-15
slug: ci-pr-selection-switch-gate
branch: feat-one-shot-ci-pr-selection-switch-gate
issue: 9729
lane: cross-domain
type: feat
requires_cpo_signoff: true
brand_survival_threshold: single-user incident
---

# ci: stop paying for the dark pr-selection selector (S4 Q1 follow-up)

Ref #9729 (never Closes). Follow-up to PR #10285 (S4 PR B, merged as 2f651e16438142578f6bdcc4e0ab1a0fda080886).
Ruling source: the CTO advisory, Q1, at https://github.com/jikig-ai/soleur/issues/9729#issuecomment-6186322031 (not re-consulted, per the brief).
Spec lane: no spec.md exists for this branch, so `lane:` defaulted to `cross-domain` (fail-closed).

## Enhancement Summary

**Deepened on:** 2026-10-15 (headless; skills/agents used: soleur:plan-review panel, user-impact-reviewer, test-design-reviewer, learnings-researcher; Actions documentation fetched live)
**Gates run:** 4.6 user-brand (present, concrete), 4.7 observability (all five fields; the discoverability command executed in 0.01 s and prints `SOLEUR_PR_SELECTION`), 4.8 PAT (none), 4.9 UI (no UI surface), 4.10 encryption (no store or connection), 4.11 guard contract (`lint-guard-contract.py` green, 3 entries), 4.12 scope check (1 live section, no BLOCKED marker).

### Key improvements
1. The Actions semantics worry is resolved against the documentation: `vars` is available in `jobs.<job_id>.if`, an undefined variable is an empty string, string comparison ignores case (so the exact `on` compare stays in the driver).
2. Guard 3 was reframed honestly after test-design review: G1-8c is a must-PASS characterization; the mutants need NEW probe rows in `mutate_tol`'s own p-set, one new `tolmut.py` operator and one compound mutant.
3. Guard 1 gained the missing mutants (`!= invalid`, gate before the `paths_too_long` cap) and lost two non-gate rows; Guard 2 states that rows 1 to 4 share one detector and what `darkequiv` must do to `ev()` (wrap the bare `if:`, translate `vars`, model the need result, fail on None).
4. Four more floors that this diff silently loosens are named for re-derivation; AC9a/AC9c are demoted from gates to observations; the wrong-green harm statement now names `merge_group` as the backstop.

### New considerations
- The dark `would_skip` stream stops; the PR C replay (escape rate under 2%) is restated as the blocking pre-activation check.
- A notice with `switch=invalid` and `reason=switch_off` means a mistyped value; stated in the ADR amendment.
- Rollback for a post-merge failure of the job `if:` is a one-line revert.

## Overview

While the repository variable `CI_PR_AFFECTED` is unset, every `pull_request` run still pays for the `pr-selection` job: a runner, a
full-history checkout, and, on a doc-only diff, a stage-2 selector pass that can never take effect (the activation lock forces
`active=false`) and that a cold hosted runner cuts off at its own 90 s budget (`sel_censored=1`), so it does not even measure what it costs.
This change removes that cost in two independent layers, and changes nothing about which jobs run while the switch is unset:

1. **Driver gate (`scripts/ci-pr-selection.sh`).** Stage 2 (`test-all.sh --print-selection` and the three `--enumerate-commands`
   calls) runs only when the switch value is exactly the string `on`. Stage 1 (the pure-bash allowlist) still runs for any value, and the
   notice still reports, with a new reason `switch_off` on a doc-only diff and zero selector calls. The activation lock is untouched.
2. **Job gate (`.github/workflows/ci.yml`).** The `pr-selection` job gets the job-level condition
   `github.event_name == 'pull_request' && vars.CI_PR_AFFECTED != ''`, so it takes no runner while the variable is unset or empty.
   The verification the brief asked for is done and the answer is **yes, it is tolerated** (see Research Reconciliation row 1): the gated
   jobs and the `test` aggregator already treat a skipped `pr-selection` as full CI, because that is exactly the state on every `push`,
   `merge_group` and `workflow_dispatch` run today. This plan makes that proof executed for the `pull_request` event as well.

Everything else the brief lists (ADR-276 S4 amendment, the job comment in `ci.yml`, the pin suites, re-running every `ci.yml` reader) follows
from those two edits.

## Premise Validation (Phase 0.6)

Checked: #9729 is OPEN (`ci: S4 PR affected-only suite set ...`), PR #10285 is MERGED at 2026-10-14T23:24:32Z, `scripts/required-checks.txt`,
the canonical ruleset JSON and `infra/github/ruleset-ci-required.tf` contain no `pr-selection` (0 matches each), so the job is not a required
context. Mechanism vs the ADR corpus: ADR-276's S4 amendment records the dark cost and defers a derive-cache restore to PR C; the CTO comment
explicitly rejects sampling, skip-on-draft-push and a derive-cache restore for the dark pass, and this plan proposes none of them. Stale
premise found and corrected: the brief says to take the cold/warm measurement "via workflow_dispatch"; a `workflow_dispatch` run cannot reach the
selector (see Research Reconciliation row 2).

## Property List and Cut List (Phase 0.6b)

Properties (each one observable):

- P1. While the switch is not exactly `on`, neither `--print-selection` nor any `--enumerate-commands` call is made (stub call count 0).
- P2. Stage 1 still classifies and the notice still reports; a doc-only diff with the switch off reports `stage=1 reason=switch_off`.
- P3. While `CI_PR_AFFECTED` is unset or empty, no `pr-selection` runner is billed on a pull_request run.
- P4. Nothing changes which jobs run while the switch is unset: a skipped `pr-selection` is full CI, for the three gated jobs and for `test`.
- P5. The activation lock still forces `active=false` and an empty `skip_legs`.
- P6. The ADR, the job comment and the pins tell the truth; assertion floors are derived from a measured green run.

Cut List (mechanism, property it would buy, what already covers it):

- A new `workflow_dispatch` measurement workflow: buys the one-off cold/warm figure; the PR C replay is named by the CTO as the alternative and a new
  workflow adds a surface (fan-out ledger, c4 counts, workflow lints) for a single number. Recorded as a pending decision, not built.
- A new aggregator arm or a new `pr-selection` output ("skipped because dark"): buys P4; the aggregator already reads empty outputs as full CI
  (G1-8 executes it for three events), and any edit inside the aggregator step moves `AGG_DIGEST` for no gain.
- Reading `needs.pr-selection.result` in the gated jobs: buys nothing the empty outputs do not, and the census pin
  (`prcensus`, 16 references) would have to move.
- Comparing the switch with an Actions `==` for the stage-2 gate: Actions `==` ignores case (ADR-276 S4 amendment, kill-switch bullet), so `ON`
  would pass. The exact compare stays in the driver's bash; the job-level condition only tests "non-empty".
- Sampling, skip-on-draft-push, derive-cache restore for the dark pass: rejected by the CTO ruling.

## Research Reconciliation: Spec vs. Codebase

| Brief claim | Reality (verified) | Plan response |
|---|---|---|
| The `pr-selection` job can be skipped only if the gated jobs and the aggregator "already tolerate" it (unverified) | Tolerated today. `pr-selection` already carries `if: github.event_name == 'pull_request'`, so it is `skipped` on every push, merge_group and dispatch run. Real GitHub evidence: `merge_group` CI run 38693668087 shows `pr-selection` skipped while `test-bun`, `test-webplat (1/2, 2/2)`, `test-scripts-heavy (1/3..3/3)` and `test-scripts (1..8/8)` ran and concluded success. The three gated `if:` terms are `!cancelled() && ... && !(github.event_name == 'pull_request' && needs.pr-selection.outputs.active == 'true' && ...)`, so a skipped need with empty outputs makes the negated term true. The aggregator tolerance requires `ACTIVE == "true"`, `HEAD_SHA_OK == "true"` and a well-formed `SKIP_LEGS`, all false on empty inputs. | Do it. The only gap is that the existing executed rows (G1-8) cover merge_group, push and workflow_dispatch but NOT `pull_request` with empty inputs. Add that (AC7, AC8). |
| Take the cold/warm `sel_s` measurement "via workflow_dispatch" | Not reachable. `ci.yml` has `workflow_dispatch`, but `pr-selection` is skipped off pull_request and the driver exits at `reason=not_pr` (G2-NOT-PR) before any selector call. A faithful measurement needs a pull_request run on a doc-only diff AND a stage-2 budget above the pinned 90 s (a cold pass is 126 to 211 s on a loaded workstation, and the canary logged `selector_timeout sel_s=90`). | ADR amendment states this accurately and names the PR C replay as the measurement point (decision row D3, ruled by the CTO agent: the measurement is taken in the PR C replay). |
| Pin suites must be re-checked for the pinned VALUE of the job `if` | Measured by trial (scratch copy of the tree, one-line `if:` edit, suites run): `scripts/ci-push-dedupe.test.sh` goes red on 11 rows: `P-JOBIF` (the pinned value) plus nine mutants whose anchor text embeds the old `if:` line and the `y-budget-10` mutant (anchor count 0, "did NOT land"). `scripts/ci-draft-light.test.sh`, the likec4 pin and `pr-fanout-ledger` results are recorded in Research Insights. | Define the job `if` ONCE as a constant in the suite and derive the pin, every anchor and the new mutants from it (AC6). |
| `ci-pr-selection.test.sh` floors "re-derived from a measured green run" | Measured by trial (driver gate only, nothing else edited): 104 of 2980 rows go red, ALL because the harness default `SWITCH=` (empty) reached stage 2 in every doc-only fixture. Flipping that single default to `SWITCH=on` leaves exactly two red rows (the "dark: would-skip evidence" row and the raw-switch-value `LEAK ... reaches stage 2` row), and the control-row gate then voids the mutation battery until they are fixed. | The harness default becomes `SWITCH=on`; the two rows are rewritten; a new `row_switch_gate` carries the switch-off contract (AC1 to AC4). |
| ADR says the dark job costs about 1.3 billed minutes per PR run | Measured now (n=14 `pr-selection` jobs on PR runs since the merge): p50 20 s, mean 31 s, max 108 s; billed per job with a 1-minute floor: 13 x 1 + 1 x 2 = 15 minutes / 14 runs = 1.07. Annotations (n=11): 10 stopped in stage 1 (6 `non_doc`, 3 `empty_diff`, 1 `trigger`), 1 reached stage 2 and was censored (`selector_timeout sel_s=90`). | Yield note below; the amendment records the measured figure next to the estimate. |
| Fan-out ledger and likec4 pin "need no change unless a count or exact condition moves" | No job is added or removed (27 declared jobs stay 27) and neither the three gated `if:` strings nor the `test` job change, so neither moves. The ledger row's prose says the job is "skipped, hence free, on every other event", which becomes incomplete. | One-sentence append to the ledger row (count unchanged); both suites still re-run. |

## Measured Yield (Phase 0.6c)

Commands that produced the numbers (run 2026-10-15 against the last 40 `ci.yml` pull_request runs):
`gh run list --workflow ci.yml --event pull_request --limit 60 --json databaseId,createdAt,conclusion,headBranch`, then per run
`gh api repos/jikig-ai/soleur/actions/runs/<id>/jobs --jq '.jobs[]|select(.name=="pr-selection")|[.conclusion,.started_at,.completed_at]'` and
`gh api repos/jikig-ai/soleur/check-runs/<job_id>/annotations --jq '.[]|select(.message|test("SOLEUR_PR_SELECTION"))|.message'`.

- **Job gate (layer 2):** removes the whole job: about 1.07 billed minutes per pull_request run (measured, n=14; the ADR estimated 1.3). At the ADR's
  figure of about 124 PR runs per day that is about 133 billed job-minutes per day, about 1.1% of the 99.8 job-minutes per PR run baseline in the
  ADR. It also removes the `needs:` edge latency in front of the three gated jobs (ADR estimate 25 to 45 s on a code PR). The saving appears the day the
  PR merges and ends the day `CI_PR_AFFECTED` is set to a non-empty value.
- **Driver gate (layer 1) alone:** saves only the stage-2 minutes of a doc-only run: 1 of 11 annotated runs reached stage 2, so about 0.07 to 0.09
  billed minutes per run, about 9 to 11 job-minutes per day. It is the weaker lever, and it is still required: it is the only layer that holds when the
  variable is set to a non-empty value other than `on` (a typo such as `ON`, or the measurement window), and it is the contract that keeps stage 2 off
  when the job-level condition is later widened or removed.
- Not measurable at plan time and not claimed: dollars (the hosted-runner rate is an estimate) and the cold/warm `sel_s` (see D3).
- Honest limit: the stage-2 evidence stream (`would_skip`, per-group tokens) stops while dark. That is the ruled trade (the data was censored at 90 s
  and the replay in PR C is the evidence source).

## User-Brand Impact

**If this lands broken, the user experiences:** a pull request whose merge gate is wrong in one of two directions. Wrong-red: the gated
jobs or `test` skip or fail on a PR with the switch unset, so a contributor's (or the operator's own) PR cannot merge until someone finds a
CI-only cause, and a queued merge group can stall. Wrong-green: a leg that should have run is skipped and `test` reports success, so an untested
change proceeds toward `main` and the shipped product that every Soleur user runs on. `merge_group` runs the full battery on the candidate tree and is the
backstop (ADR-276), so on this change the realistic harm is an ejected or stalled queue entry; a regression reaching `main` additionally needs the queue to be
bypassed (the ADR's named admin-merge residual). The single-user-incident path is the one user who hits a defect the full battery would have caught.
**If this leaks, the user's [workflow] is exposed via:** no user data, secret or credential is read or written by this change (the job keeps
`contents: read`, no secrets, every input through `env:`); the only disclosure surface is the `::notice` annotation, which this change makes smaller
(it never echoes a path, ref, SHA, repository name or the raw switch value, and a skipped job emits no notice).
**Brand-survival threshold:** single-user incident

`requires_cpo_signoff: true` is set; the CPO review and `soleur:engineering:review:user-impact-reviewer` are recorded in Domain Review below and
run again at review time. The wrong-green path is closed by construction: the change can only turn work OFF for the `pr-selection` job itself, never for
a gated job, and the gated jobs' own conditions are not edited.

## Observability

```yaml
liveness_signal:
  what: the SOLEUR_PR_SELECTION notice (switch, locked, attempt, files, stage, reason, would_skip, sel_s, sel_censored, budget, active, groups) emitted once per pr-selection run that is not skipped; for a SKIPPED job the signal is the job conclusion `skipped` in the jobs API (the dark state)
  cadence: every pull_request run (one notice when the variable is non-empty, a skipped job when it is unset or empty)
  alert_target: none while dark (a cost lever, never a gate); the PR C first-active-run canary and soak probe read the same two signals
  configured_in: scripts/ci-pr-selection.sh (emit_notice) and .github/workflows/ci.yml (job pr-selection)
error_reporting:
  destination: the notice reason token (lever_error, signalled, switch_off, selector_timeout ...) plus the job-level continue-on-error, which keeps a failed lever from reddening the run
  fail_loud: false by design (cost lever, fail-open to the full battery); the loud failure is the pin suites, which red the PR that breaks the contract
failure_modes:
  - mode: the job-level condition skips the job even when the variable is `on` (typo, context unavailable)
    detection: the executed truth table over the real `if:` string (AC7) and, post-activation, the PR C canary (no notice on the first active run)
    alert_route: PR red in scripts/ci-push-dedupe.test.sh before merge; fail-safe direction (the full battery runs)
  - mode: the job runs although the variable is unset (the condition lost its `vars` term)
    detection: P-JOBIF pin plus the dark-equivalence table
    alert_route: PR red; cost regression only, no correctness effect
  - mode: stage 2 runs while the switch is not exactly `on`
    detection: stub selector call count above 0 in row_switch_gate; in CI, a notice with stage=2 and switch != on
    alert_route: PR red; cost regression only
  - mode: a gated job or the aggregator mis-handles a skipped pr-selection on a pull_request run
    detection: the dark-equivalence table (AC7) and the aggregator rows G1-8c (AC8) through the extracted real bodies; live, this PR's own CI run (AC9)
    alert_route: PR red; `test` red is itself the loud failure
logs:
  where: GitHub Actions job annotations and the step summary of the pr-selection job (public repo, readable without credentials)
  retention: GitHub's run-log retention (90 days)
discoverability_test:
  command: bash -c 'EVENT_NAME=push GITHUB_OUTPUT=/dev/null bash scripts/ci-pr-selection.sh'
  expected_output: SOLEUR_PR_SELECTION
```

## Architecture Decision (ADR/C4)

Detection: this extends an existing ADR (ADR-276 S4) by changing the dark-state cost model and the job's skip condition, so the amendment is a deliverable
of this plan, not a follow-up.

### ADR

Amend `knowledge-base/engineering/architecture/decisions/ADR-276-demand-first-hosted-runner-budget-merge-group-is-the-full-battery-authority.md`:
append `## Amendment 2026-10-15 (S4 Q1 follow-up, #9729)` AFTER the 2026-10-14 PR B amendment (the existing sentences stay unedited, per the ADR's own
supersession convention) and add one line to the dated amendment index near the top of the file. Content: (1) the two gates and their exact
predicates; (2) **Supersession**: the PR B bullets "Honest dark-state cost" and "Measured cost of PR B while dark" describe a job that runs on every PR run;
now it does not while the variable is unset or empty, and `sel_s` is no longer measured per run (stage 2 runs only on `on`); (3) the measured figures from
Measured Yield above, next to the estimate they correct; (4) the accurate measurement procedure (a `workflow_dispatch` run of `ci.yml` cannot take it;
the PR C replay does, on a fresh hosted runner, `time bash scripts/test-all.sh --print-selection --paths=README.md` run twice, first cold then warm,
with the stage-2 budget raised above the cold pass) and that setting the variable is a separate authorized act (a menu acknowledgement is not
authorization); (5) PR C checklist items: the `switch_off` branch of the driver is unreachable in CI while the variable is unset or empty (it is reachable with a non-empty, non-`on` value, which is also the one cheap real-Actions check of the `!= ''` true branch before activation, as a separately authorized step); the dark `would_skip`/`sel_s` stream stops, so the first-active-run canary's notice stream begins at activation; the driver has no `ACTION` input, so a `ready_for_review` run is not distinguished from `opened` (draft-light excludes it, the driver does not); (6) a notice reading `switch=invalid` together with `reason=switch_off` means a mistyped value, not an off switch; (7) rollback prose: for a post-merge failure of AC9c the rollback is a revert of the `pr-selection` `if:` line (one line), and with the variable deleted, "Re-run all jobs" no longer re-executes `pr-selection` at attempt 2, the job is skipped and the run is full. The PR C activation prerequisite that already requires the replay (escape rate under 2% over the last 300 first-parent commits, prerequisite 2) is restated as the blocking pre-activation check that replaces the stopped dark `would_skip` stream. Wording rule: do not put `gh run rerun` and the release
workflow file name on one line (the `workflow-run-deploy-invariants` G8 scan reads ADR prose).

### C4 views

No C4 impact. Checked against all three model files (`model.c4` 962 lines, `views.c4`, `spec.c4`): CI is modeled as the single external system `github`
(edges to sentry, resend, anthropic, zotRegistry, hetzner, betterstack; none names `ci.yml`, a job, `pr-selection` or `CI_PR_AFFECTED`); external human
actors: the operator/founder only, unchanged; external systems/vendors: none added; containers/data stores: none touched; actor-to-surface access
relationships: none changed. No derived cardinality in `model.c4` moves (no workflow or monitor is added; the declared `ci.yml` job count stays 27).
`plugins/soleur/test/c4-count-parity.test.sh` and `c4-model-freshness.test.sh` are in the re-run list to back this with a green run.

### Sequencing

The amendment describes the target state and lands in this PR. Status stays `adopting`.

## Open Code-Review Overlap

None. Queried `gh issue list --label code-review --state open --json number,title,body --limit 200` and searched the bodies for every path in
`## Files to Edit` (the driver, its suite, `ci.yml`, `ci-push-dedupe.test.sh`, `ci-test-aggregator-diagnosis.test.sh`, the fan-out ledger, ADR-276): 0 matches each.

## Domain Review

**Domains relevant:** Engineering (CI/cost lever). No marketing, legal, finance, sales or support surface; no UI surface (no file under a UI path).

### Engineering

**Status:** reviewed
**Assessment:** The CTO ruled Q1 in the #9729 comment (run stage 2 only on `on`; skip the job only if verified tolerated). Not re-spawned, per the brief. The
tolerance is verified in Research Reconciliation row 1. Remaining CTO-class forks are recorded in `specs/feat-one-shot-ci-pr-selection-switch-gate/decision-challenges.md`.

### CPO sign-off (requires_cpo_signoff)

**Status:** APPROVED-WITH-CONDITIONS by the CPO agent, 2026-10-15 (conditions folded in; see Plan Review Log). `soleur:engineering:review:user-impact-reviewer` runs at review time.

## Research Insights

- **Premise Validation, Property List, Cut List:** carried in full in the sections above (`## Premise Validation`, `## Property List and Cut List`); not restated.
- **Trial runs (scratch copy of the tree, nothing in the repository edited):** (1) `ci.yml` with the one-line job `if:` edit: `scripts/ci-push-dedupe.test.sh` 179 passed, 11 failed (`P-JOBIF`, nine `y-prsel-*` mutant anchors, `y-budget-10`); `scripts/ci-draft-light.test.sh` 209 passed, 0 failed; `plugins/soleur/test/ci-test-aggregator-diagnosis.test.sh` 165/165; `ci-e2e-skip-anchors` 51/51; `ci-concurrency-key` 14/14; `pr-fanout-ledger` ALL TESTS PASSED; and green on the same trial tree: `ci-head-verdict` (75, 35/35 mutants), `ci-shard-totality-skip`, `scripts-shard-runtime-coverage`, `deploy-arm` (79), `c4-model-freshness`, `ship-battery-owed`, `ci-classify-step-exec`, `regenerate-shard-manifest`, `workflow-run-deploy-invariants` (80/80), `required-checks-canonical-parity`, `required-checks-merge-group-coverage` (73), `test-cancel-superseded-pr-runs` (178), `probe-merge-group-coverage` (`merge-group-coverage=OK contexts=25 producers=24`). The vitest files were not run in the trial (no node_modules in the scratch copy); the likec4 pin was read instead (it pins only the gated jobs' `if:` strings). (2) Driver gate only: `scripts/ci-pr-selection.test.sh` 104 of 2980 rows red, all from the harness default `SWITCH=`; after flipping the default to `on`, 2 rows red and the control-row gate voids the mutation battery.
- **Institutional learnings applied:** `2026-10-14-a-dark-lever-measures-itself-through-its-own-budget-and-my-fix-round-tripped-ratchets-no-file-query-selects.md` (censored `sel_s`; the eight repo-global ratchets to run after any test or ADR edit); `2026-10-09-a-cost-lever-must-not-be-able-to-redden-the-run-it-saves.md` (job-level `continue-on-error`, empty output means run everything); `test-failures/2026-07-18-pipefail-grep-q-early-match-sigpipe-flakes-drift-guards.md` (here-strings); `test-failures/2026-09-19-every-guard-i-shipped-pinned-spelling-not-the-executed-program.md` (execute, do not grep); `test-failures/2026-10-11-a-pin-that-reports-through-the-gate-it-pins-is-silenced-by-disarming-the-gate.md` (pins report directly). Gap found: no learning covers `needs.X.outputs` of a skipped job or `vars.*` in a job-level `if:`; the compound step at ship time should record the measured trial results above.
- **Consumers of a skipped `pr-selection` on a PR run** (checked): `scripts/ci-demand-census.sh` excludes skipped jobs from counted minutes by design; `plugins/soleur/scripts/admin-merge-ready.sh` reads required contexts only (`pr-selection` is not one); the draft-light and push-dedupe soak probes key on named gated jobs. No consumer treats a skipped `pr-selection` as an anomaly.
- **Docs facts (verified at deepen time, 2026-10-15):** `jobs.<job_id>.if` exposes `github, needs, vars, inputs`; an undefined variable reads as an empty string; string comparison in expressions ignores case. The earlier draft's null-versus-empty coercion worry therefore does not arise. The live run (AC9b) remains the check of the evaluator model's other rows.

## Files to Edit

- `scripts/ci-pr-selection.sh`: the stage-2 gate (`reason=switch_off`, `GUARD:G2-16-SWITCH-GATE`, placed after the stage-1 allowlist and before `stage=2`), header comment (stage 2 only on `on`; `sel_s` is 0 when stage 2 did not run). The arm line and the lock are NOT touched.
- `scripts/ci-pr-selection.test.sh`: harness default `SWITCH=` becomes `SWITCH=on`; rewrite the rows "G2-13 dark: would-skip evidence", "LEAK the run still reaches stage 2" and the unset/empty rows; add `row_switch_gate` and its mutants; re-derive `BASE_ROWS`/`MIN_MUTANTS` from a measured green run; update the header comment. Any new redirect or `rm -rf` spelled inside a quoted sed script is spliced through a variable (`RD='>>'`), never baselined.
- `.github/workflows/ci.yml`: the `pr-selection` job `if:` and its comment block (the comment above the job, which today says the job "only annotates `would_skip`" with the variable unset). No edit inside the `test` aggregator step, so `AGG_DIGEST` does not move.
- `scripts/ci-push-dedupe.test.sh`: one `PRSEL_IF` constant exported to `chk.py`; `P-JOBIF` compares against it; the nine `y-prsel-*` anchors and `y-budget-10` derive from it; new mutants; the dark-equivalence mode (AC7). `AGG_DIGEST` stays as is.
- `plugins/soleur/test/ci-test-aggregator-diagnosis.test.sh`: rows G1-8c (pull_request with the empty inputs a skipped `pr-selection` produces) and their mutants; the W5/W7 pins are re-read, not expected to move.
- `scripts/pr-fanout-ledger.txt`: one sentence appended to the `ci.yml` row's consequence (the job is also skipped while the variable is unset or empty); the count 27 does not move.
- `knowledge-base/engineering/architecture/decisions/ADR-276-demand-first-hosted-runner-budget-merge-group-is-the-full-battery-authority.md`: the new dated amendment and its index line (see Architecture Decision).
- Only if a ratchet moves when run: `scripts/test-affected-kb-consumers.baseline.txt`, `plugins/soleur/test/fixture-relative-assert.baseline.txt` (move DOWN or hold; never raise to make red go green without a named cause).
- Not edited, and why: `scripts/ci-draft-light.test.sh` (trial: 209 passed, 0 failed with the new `if:`; re-run in the list), `apps/web-platform/test/c4-likec4-version-pin.test.ts` (pins only the gated jobs' `if:` strings, which do not change), `scripts/required-checks.txt`, the ruleset JSON and `infra/github/ruleset-ci-required.tf` (context names unchanged), the archived S4 plan and spec (stay at their archive paths; not touched, so no in-place edit).

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-ci-pr-selection-switch-gate/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-ci-pr-selection-switch-gate/decision-challenges.md`

## Implementation Phases

Order follows `cq-write-failing-tests-before`: each phase writes the executed test first, watches it go red against the unmodified tree, then makes the edit.

### Phase 1: driver gate (RED then GREEN)

1. In `scripts/ci-pr-selection.test.sh` add `row_switch_gate` and run it against the unmodified driver: it must go red (stage 2 ran, `STUB_CALLS` 4).
2. Edit the driver: before `stage=2`, `reason=switch_off`, then `[ "$sw" = on ] || return 0  # GUARD:G2-16-SWITCH-GATE`. It reads the `sw` token (set by the one exact compare, `GUARD:G2-5-SWITCH-EXACT`), not the raw variable, so there is exactly one place that decides what "on" means.
3. Flip the harness default `SWITCH=` to `SWITCH=on`, fix the two rows named in Research Reconciliation, run to green (control rows first: the battery is void while a control row is red).
4. Add the mutants (Guard 1 matrix), confirm each LANDED and each is KILLED, then re-derive the floors (Phase 5).

### Phase 2: job gate

1. Write the failing pins first (Phase 3) against the unedited `ci.yml`.
2. Edit the job: `if: github.event_name == 'pull_request' && vars.CI_PR_AFFECTED != ''`. Docs check DONE at deepen time (https://docs.github.com/en/actions/reference/workflows-and-actions/contexts, retrieved 2026-10-15): the `vars` context is available in `jobs.<job_id>.if` (row: `github, needs, vars, inputs`), and a reference to a variable that is not defined "will be an empty string". So the unset case is a plain string-to-string comparison `'' != ''` (false), no null coercion is involved, and the comment may state exactly that. The expressions page adds that string comparison ignores case (https://docs.github.com/en/actions/reference/workflows-and-actions/expressions), which is why the exact `on` compare stays in the driver. A set variable is a string, so `ON`, `off`, `on ` all run the job (the driver's bash compare then reports `invalid`). Anything unexpected fails toward the job being SKIPPED (full CI) or RUN (cost only), never toward a lost leg.
3. Rewrite the comment block above the job, including the clauses that become false: "with the repository variable CI_PR_AFFECTED unset the job only annotates `would_skip`", "It runs a stage-2 selector pass on doc-only diffs even while dark", and "Off a pull_request the job is skipped before it takes a runner" (extend to: or while the variable is unset or empty). The driver header's "STAGE 2 runs only for a doc-only diff, in dark mode too" line is rewritten the same way. (The comment block is outside the parsed job block, so `P-JOB-TEXT`'s `timeout-minutes: 3` line count is unaffected; do not add a second line reading exactly `timeout-minutes: 3`).

### Phase 3: pin suites

1. `scripts/ci-push-dedupe.test.sh`: `PRSEL_IF` constant; `P-JOBIF` equality against it; anchors rebuilt from it; mutants (Guard 2 matrix); `darkequiv` mode in `chk.py` evaluating the REAL parsed `if:` strings of the job and of the three gated jobs plus `test`.
2. `plugins/soleur/test/ci-test-aggregator-diagnosis.test.sh`: G1-8c rows through the extracted aggregator body (Guard 3).
3. Re-run `scripts/ci-draft-light.test.sh` unchanged to confirm its A-NEEDS-SET and truth table still hold.

### Phase 4: ADR and comments

ADR-276 amendment, `ci.yml` job comment, driver header, ledger sentence, as specified above. Prose rules: no `gh run rerun` beside the release workflow file name on one line; no new `knowledge-base/` path literals in the driver or its suite (kb-consumer census); the archived S4 plan and spec are cited by path, never moved or edited.

### Phase 5: re-derive floors and run everything

1. `bash scripts/ci-pr-selection.test.sh | tail -3`: set `BASE_ROWS = total - 19 * sourced_count` (19 rows per sourced file, re-measured at review; 18 was the pre-change figure) and `MIN_MUTANTS` (91 at plan time) to the measured mutant count (the unmutated baseline is 2980 rows at the harness-default flip with the battery void; the green-run figure comes only from a full run). Re-derive the other three floors this diff loosens silently (slack, not red) from green runs too: `ci-test-aggregator-diagnosis.test.sh` `MIN_ROWS` (165, an itemized zero-slack derivation) and `MIN_MUTANTS` (33); `ci-push-dedupe.test.sh` `_FLOOR` (190) and the `MUT_RUN` minimum (94).
2. Run the full re-run list below, then the repo-global ratchets, then push.

### Phase 6: live proof on the PR's own run (after push)

Preconditions, each checked and recorded: `gh api repos/jikig-ai/soleur/actions/variables/CI_PR_AFFECTED` returns 404 (observed 404 at plan time; the organization endpoint needs admin rights (HTTP 403 for the planning account), and an organization variable is visible through `vars`, so the run's own `pr-selection` conclusion is the decisive observation); the observed run is a non-draft run or a `ready_for_review` run, so `draft-light` did not skip `test-webplat`/`test-scripts-heavy` for its own reason (read the run's `draft-light` job: it must not have emitted `light=true`). Then record in the PR body: this PR's `CI` run shows `pr-selection` concluded `skipped`; `test-webplat`, `test-bun`, `test-scripts-heavy`, all `test-scripts` legs and `test` concluded `success` (`gh api repos/jikig-ai/soleur/actions/runs/<id>/jobs`). Discriminating power: the PR's own run proves the skipped-need semantics on a `pull_request` event; the first doc-only PR after merge (AC9c) proves it for an ordinary PR. The trigger list is not the reason the run is full: with the job skipped the driver never runs.

## Re-run List (every suite that reads ci.yml, plus the ratchets file-referencing selection missed in PR #10285)

Brief's list, verbatim: `scripts/ci-push-dedupe.test.sh`, `scripts/ci-draft-light.test.sh`,
`plugins/soleur/test/{ci-test-aggregator-diagnosis,ci-e2e-skip-anchors,ci-concurrency-key,pr-fanout-ledger,ci-head-verdict,ci-shard-totality-skip,scripts-shard-runtime-coverage,deploy-arm,c4-model-freshness,ship-battery-owed,ci-classify-step-exec,regenerate-shard-manifest,workflow-run-deploy-invariants,required-checks-canonical-parity,required-checks-merge-group-coverage}.test.sh`,
`.github/scripts/test/test-cancel-superseded-pr-runs.sh`, `scripts/probe-merge-group-coverage.sh`, and the vitest files
`apps/web-platform/test/{c4-likec4-version-pin,eslint-config,session-sync-path-allowlist}.test.ts`, `apps/web-platform/server/webhooks/github-route.test.ts`,
`apps/web-platform/server/inngest/rule-body-gate-recursion-invariant.test.ts` (run vitest from `apps/web-platform`).

Added by this plan (the PR B learning's ratchet list, plus the suites this change's own files feed): `scripts/ci-pr-selection.test.sh`,
`plugins/soleur/test/{fixture-relative-assert,fixture-dir-operand-assert,fixture-cd-containment,fixture-env-adoption,guard-vacuity-floor,c4-count-parity}.test.sh`,
`scripts/test-affected-kb-consumers.test.sh`, `plugins/soleur/test/lint-orphan-test-suites.test.sh`, `scripts/test-all-affected.test.sh`, and
`python3 scripts/lint-guard-contract.py` over this plan. Run the bash suites under the CI shell version (bash 5.2.x) where the workstation differs.

## Acceptance Criteria

Every criterion below is an executed test or an executed command with a literal expected result; none is a text pin.

- [ ] AC1 (stage 2 never runs off-switch): `bash scripts/ci-pr-selection.test.sh` `row_switch_gate`, for SWITCH in unset (empty), `ON`, ` on`, `on `, newline-wrapped `on`, `1`, `off` and a raw token carrying the leak marker (the `sw` classification itself is already pinned by the G2-5 rows; these prove the gate reads it), on the doc-only fixture `k1`: stub selector call count `STUB_CALLS` is exactly 0 (covers `--print-selection` and all three `--enumerate-commands`), the notice reads `stage=1 reason=switch_off would_skip=none sel_s=0 sel_censored=0 groups=- active=false`, `files` is 1, exit 0, one notice, an 8-line output file ending `active=false skip_legs=`, empty stderr.
- [ ] AC2 (stage 2 still runs on exactly `on`, must-PASS non-canonical): the same rows with `SWITCH=on` on `k1`, `k2` (root markdown too), `kad` (add and delete) and `krn` (rename) give `STUB_CALLS` 4 and `stage=2`; on the locked driver `reason=affected would_skip=test-webplat,test-bun,test-scripts-heavy active=false skip_legs=` .
- [ ] AC3 (stage 1 unchanged while off): with the switch unset, a non-doc diff (`code`, `legal`, `mk`, `docmod`), a trigger diff (`ci.yml`), an empty diff, a fork head, `RUN_ATTEMPT=2`, and an over-500-file diff report the same `reason` and `files` as with `SWITCH=on`, with `STUB_CALLS` 0; a doc-only diff is the ONLY shape that reports `switch_off` (unless its joined paths exceed the 100000-byte cap, which reports `paths_too_long` first).
- [ ] AC4 (lock unchanged, both ways): locked driver + `SWITCH=on` on a doc-only diff: `active=false`, `skip_legs=` empty, notice `switch=on locked=true`. Lock-neutralized copy + `SWITCH=on`: `active=true`, `skip_legs=test-webplat,test-bun,test-scripts-heavy`. Lock-neutralized copy + any other switch value: `active=false`, `STUB_CALLS` 0.
- [ ] AC5 (mutants): each Guard 1 mutant is confirmed LANDED (differs from the pristine bytes) and KILLED; the control rows are green; the floors are the figures measured from the full green run (`bash scripts/ci-pr-selection.test.sh | tail -3`), with `ROWS_PER_SOURCED_FILE` re-verified, not guessed.
- [ ] AC6 (job `if`): `bash scripts/ci-push-dedupe.test.sh` is green with 0 "did NOT land" mutants; `P-JOBIF` compares against the single `PRSEL_IF` constant; the Guard 2 mutants are caught by the named tag.
- [ ] AC7 (dark equivalence, executed over the real `if:` strings parsed from `ci.yml`): `chk.py darkequiv` evaluates, for event in {push, pull_request, merge_group, workflow_dispatch}, variable in {unset, empty, `on`, `ON`, `0`}: the `pr-selection` `if:` is true exactly when event is `pull_request` and the variable is neither unset nor empty. The model rows that diverge from a naive Python `!=` are pinned explicitly and labelled "model, not verified live": unset gives job-false (translate `vars.CI_PR_AFFECTED` as the empty string when unset, per the documented behavior; a model that mapped unset to Python `None` would invert this row) and `0` gives job-true (string-to-string compare). For every (event, elide, light, cancelled) combination, each of `test-webplat`, `test-bun`, `test-scripts-heavy` and `test` evaluates IDENTICALLY when `pr-selection` is skipped (outputs forced to empty) and when it ran with `active=false`, `skip_legs=''`, any `head_sha`. Zero differing rows.
- [ ] AC8 (aggregator, executed through the extracted real body): rows G1-8c (the existing G1-8 event loop gains `pull_request`, plus the explicit `HEAD_SHA_OK` variants below) run the `test` step's `run:` body with `EVENT_NAME=pull_request`, `ATTEMPT=1`, `SKIP_LEGS=''`, `ACTIVE=''`, `HEAD_SHA_OK` in {`''`, `false`}: all six legs `success` gives rc 0 and the line `All six legs green (four shards + web-platform-build + encryption-posture).` with no `PR-AFFECTED-SKIP`; each of `test-webplat`, `test-bun`, `test-scripts-heavy` as `skipped` gives rc 1 with `<leg>: SKIPPED`; a `failure` leg gives rc 1. `AGG_DIGEST` is unchanged (`ci-push-dedupe` mode `agg` empty).
- [ ] AC9 (real GitHub semantics; (a) and (c) are observations, not review-time gates, because one ages out and the other happens after merge; (b) is the gate): (a) background only, not evidence for this change: CI run 38693668087 (`merge_group`) already had `pr-selection` `skipped` with the gated legs `success` (it ages out with the 90-day log retention); (b) the evidence: this PR's own `pull_request` CI run, per Phase 6, valid only when its preconditions hold (variable absent at repository AND organization level, or simply the observed `pr-selection` conclusion; run is not a light draft); (c) after merge, the first doc-only PR shows the same, which is the observation that separates the new behavior from the old for a PR that does not touch `ci.yml`.
- [ ] AC10 (no scope leak): after `git fetch origin main`, `git diff $(git merge-base HEAD origin/main) -- scripts/required-checks.txt scripts/ci-required-ruleset-canonical-required-status-checks.json infra/github/ruleset-ci-required.tf` is empty; `yaml.safe_load(ci.yml)['jobs']` still has 27 entries; the three gated jobs' and `test`'s `if:` strings are byte-identical to the merge-base.
- [ ] AC11 (environment-dependent: vitest needs the app's node_modules, the bash suites should run under the CI bash 5.2.x, `scripts/probe-merge-group-coverage.sh` may need network): every suite in the Re-run List exits 0 on the final tree; `python3 scripts/lint-guard-contract.py knowledge-base/project/plans/2026-10-15-feat-ci-pr-selection-switch-gate-plan.md` exits 0.
- [ ] AC12: the PR body says `Ref #9729` and contains no `Closes`/`Fixes`/`Resolves` for it.
- [ ] AC13: the ADR amendment exists, states the superseded sentences, the measured figures with their source commands, the accurate measurement procedure, and `workflow-run-deploy-invariants` stays green.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "in scripts/ci-pr-selection.sh, run stage 2 ... ONLY when the switch value is exactly `on`" [brief] | Phase 1; Files to Edit entry 1; AC1, AC2 | mapped |
| 2 | "while it is unset, empty or anything else, stage 1 still runs and the notice still reports, with a new reason such as `switch_off` and no selector call at all" [brief] | Phase 1 step 2; AC1, AC3 | mapped |
| 3 | "The activation lock still forces active=false and an empty skip_legs" [brief] | AC4 | mapped |
| 4 | "Verify, by reading ci.yml and the aggregator, whether the pr-selection JOB can be skipped entirely while CI_PR_AFFECTED is unset or empty" [brief] | Research Reconciliation row 1; Phase 2; AC7, AC8, AC9 | mapped |
| 5 | "Only do this if every pin and the aggregator tolerate it with executed proofs; otherwise keep the job and say why" [brief] | Phase 3; AC6 to AC8 | mapped |
| 6 | "Nothing may change which jobs run while the switch is unset" [brief] | AC7, AC10 | mapped |
| 7 | "Update ADR-276's S4 amendment (dark cost, sel_s no longer measured per run, how to take the one cold/warm measurement via workflow_dispatch)" [brief] | Architecture Decision (ADR); Phase 4; AC13; decision row D3 | mapped |
| 8 | "the pr-selection job comment in ci.yml" [brief] | Phase 2 step 3 | mapped |
| 9 | "the pin suites (ci-push-dedupe, ci-test-aggregator-diagnosis, scripts/ci-pr-selection.test.sh floors re-derived from a measured green run, mutants for each new guard)" [brief] | Phase 3, Phase 5; Guard Contract; AC5, AC6, AC8 | mapped |
| 10 | "re-run EVERY suite that reads ci.yml" [brief] | Re-run List; AC11 | mapped |
| 11 | "Keep scripts/required-checks.txt and ruleset context names unchanged" [brief] | AC10 | mapped |
| 12 | "Ref #9729 only, never Closes" [brief] | AC12 | mapped |
| 13 | "Threshold: single-user incident; run user-impact-reviewer" [brief] | User-Brand Impact; Plan Review Log | mapped |
| 14 | "Do not archive anything under knowledge-base/project/plans or specs that is still being read" [brief] | Files to Edit "Not edited" bullet | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `scripts/ci-pr-selection.sh` gate | "run stage 2 ... ONLY when the switch value is exactly `on`" | asked |
| `scripts/ci-pr-selection.test.sh` rows, mutants, floors | "floors re-derived from a measured green run, mutants for each new guard" | asked |
| `ci.yml` job `if:` and comment | "job-level if: on the repository variable, vars.CI_PR_AFFECTED" | asked |
| `ci-push-dedupe.test.sh` constant, mutants, `darkequiv` | "the pin suites (ci-push-dedupe, ..." and "executed proofs" | asked |
| `ci-test-aggregator-diagnosis.test.sh` G1-8c | "synthetic needs-result triples through the real aggregator body" (brief, planning contract) | asked |
| ADR-276 amendment | "Update ADR-276's S4 amendment" | asked |
| `scripts/pr-fanout-ledger.txt` sentence | "the fan-out ledger row ... need no change unless a count or exact condition moves" | inferred: the row's prose "skipped, hence free, on every other event" becomes incomplete, and the ledger header requires a row to name its consequence accurately |
| Added ratchet suites in the Re-run List | "since CI caught pr-fanout-ledger and c4-likec4-version-pin last time after file-referencing selection missed them" | inferred: the PR B learning lists eight repo-global ratchets that file-referencing selection missed in the previous fix round |
| Phase 6 live proof | "executed proofs" | inferred: the truth table re-implements Actions' expression semantics in Python, so one real GitHub run is the only check of the semantics themselves |
| decision-challenges.md, tasks.md | the technical-rulings clause of the brief | asked |

### Split Assessment

- Subsystems touched: 3 (`scripts`, `.github`, `plugins/soleur`) plus `knowledge-base` docs
- Planned files: 9 (+2 created) | Estimated changed lines: about 450 (the driver gate is 3 lines; the suites carry the volume)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Guard Contract

### Guard 1 — stage-2 switch gate (G2-16)

**Property.** No selector call (`--print-selection` or `--enumerate-commands`) is made unless the switch value is exactly the string `on`, while stage 1 and the notice still run for every value.

**Assembly.** One chokepoint: the single statement between the end of the stage-1 loop and `stage=2` in `run()` of `scripts/ci-pr-selection.sh`, reading the `sw` token set by the one exact compare. The selector call sites it must dominate are exactly four: the `--print-selection` call and the three `--enumerate-commands` calls in the `for g in webplat bun scripts-heavy` loop (all four sit after the gate, so a gate that precedes the first call dominates all of them; the suite counts calls through the `PR_SELECTION_TEST_ALL` stub, which is the structural measure). The values the compare must classify: every string; the suite drives the 8 listed in AC1 (the G2-5 rows cover the wider spellings of `sw`).

**Mutation matrix.**

| # | Mutation of the driver | Must go RED via |
|---|---|---|
| 1 | delete the gate statement | AC1 `STUB_CALLS` 0 rows (stage 2 runs off-switch); each 0-row is paired with a 4-row on the same fixture (AC2), which proves the instrument counts |
| 2 | gate on `[ -n "${SWITCH:-}" ]` (any non-empty value runs stage 2) | the `ON`, `off`, `1`, ` on` value rows |
| 3 | gate on `[ "$sw" != invalid ]` (an unset or empty switch would run stage 2) | the unset row |
| 4 | gate placed AFTER the `--print-selection` call and before the enumerates (a REORDER, pays one call); the sed is line-addressed on the `GUARD:G2-9-CI-UNSET` anchor and lands after `rc=$?`/`sel_s=` so it cannot clobber `rc` | `STUB_CALLS` must be exactly 0, not "fewer" |
| 5 | gate moved BEFORE stage 1 (REORDER: code PRs would report `switch_off` and `files=0`) | AC3 rows (`non_doc`, `trigger`, `empty_diff` reasons and `files` unchanged while off) |
| 6 | gate moved BEFORE the `paths_too_long` cap (REORDER within stage 1's tail: an over-cap doc diff would report `switch_off`) | new fixtures: an over-cap doc-only diff (reason `paths_too_long`, switch off) and `bigok` just under the cap (reason `switch_off`) |
| 7 | gate inverted (`&& return 0`) | AC2 must-PASS rows |

(A gate reading the raw `$SWITCH` instead of `$sw` is equivalent while `sw` is derived from it by the one exact compare, so it is not a mutant. The trailing-newline spelling of `on` belongs to the existing G2-5 trim mutants.)

The lock's own arm line is exercised by the unchanged G2-13 rows and AC4 (the lock is not a new guard).

**Harness rows.** (a) A must-PASS input that is not the canonical `k1`: `krn` (rename inside the allowlist) and `k2` (root markdown) with `SWITCH=on` reach stage 2 (`STUB_CALLS` 4). (b) A floor on the new rows' own dispatch: `BASE_ROWS` is derived from a measured run, so deleting `row_switch_gate`'s loop reds the assertion floor. (Reverting the harness default to `SWITCH=` is a one-off trial recorded in Research Insights (104 rows red), not a committed check.)

**Anchor.** The suite and the driver live in one diff, so the suite proves consistency, not integrity. The outside anchor is `merge_group` (the full battery on the candidate tree is the authority, ADR-276), the trigger list (an edit to the driver is itself a full-battery run), and the measured row floor, which a weakening PR cannot lower without editing the floor in the same diff; the reviewer reads the floor diff.

### Guard 2 — job-level condition and dark equivalence

**Property.** While `CI_PR_AFFECTED` is unset or empty, the `pr-selection` job takes no runner and the set of jobs that run is identical to the set that runs when `pr-selection` ran with `active=false`.

**Assembly.** Every place the property quantifies over: the job's own `if:`; the `if:` of each job whose `needs:` names `pr-selection` (`test-webplat`, `test-bun`, `test-scripts-heavy`, `test`), found by the suite from the parsed workflow rather than listed (`G-PRNEEDS` and `G-PRNEEDS-EXTRA` already close the set in both directions); the four events; the variable values. The suite parses the REAL `ci.yml` strings, so a fifth consumer added later is in scope the moment it names `pr-selection`.

**Mutation matrix.** Rows 1 to 4 are all caught by the single `P-JOBIF` string equality, so they count as ONE structural detector; the independent evidence is `darkequiv` (its unset, `ON` and `0` rows; the `0` row kills `== 'on'` without relying on Actions' case-insensitivity). `darkequiv` must wrap the bare `if:` string in `${{ }}` before `ev()` (which returns None for an unwrapped expression), translate `vars.CI_PR_AFFECTED` (unset as the empty string), model `needs.pr-selection.result` as `skipped` versus `success` for row 5, and FAIL on a None result (a vacuous table). The gated-job half largely already exists in `truth` mode (pull_request x skipped x empty outputs over the consumers); `darkequiv` adds the job-`if:` evaluation and the composition.

| # | Mutation of `ci.yml` | Must go RED via |
|---|---|---|
| 1 | the `vars.CI_PR_AFFECTED != ''` term removed (job runs while dark) | `P-JOBIF` and `darkequiv` row for unset |
| 2 | the event term removed (job would run on push when the variable is set) | `P-JOBIF` and the event rows |
| 3 | `== 'on'` instead of `!= ''` (narrower than the ruling; also case-insensitive in Actions) | `P-JOBIF` and the `ON` row |
| 4 | inverted `== ''` | `P-JOBIF` and `darkequiv` |
| 5 | a gated job's `if:` gains `needs.pr-selection.result == 'success'` (a skipped need now skips the gated job: lost coverage) | `darkequiv` (own dispatch: the table must see a gated job that stops running when `pr-selection` is skipped) and `G-COND` |
| 6 | the same edit applied to a SECOND gated job after a compliant first | `darkequiv` loops over all four consumers |

(`test`'s `needs:` losing `pr-selection` and a deleted `if:` line are already covered by `G-PRNEEDS:test` and `P-JOBKEYS`; not re-tested.)

**Harness rows.** (a) Mutant row 6 doubles as the harness check: a `darkequiv` that evaluates only the first consumer cannot red it. (b) Must-PASS non-canonical: the variable value `on ` (trailing space) must RUN the job (string-to-string compare), proving the evaluator is not "starts with on". (c) The evaluator itself is cross-checked by one live observation (AC9), because it re-implements Actions' loose comparison.

**Anchor.** The literal `PRSEL_IF` constant lives in the suite and the workflow in the same diff, so a weakening PR can edit both. The outside anchors are AC9 (a real GitHub run of this PR) and the fact that the three gated jobs' and `test`'s `if:` strings are pinned byte-for-byte by three other suites (`ci-push-dedupe`, `ci-draft-light`, the likec4 vitest pin), which a "make the job skip the gated legs" weakening would have to edit as well.

### Guard 3 — aggregator reads a skipped pr-selection as full CI on pull_request

**Property.** On a `pull_request` run whose `pr-selection` was skipped (all three consumed outputs empty), the `test` aggregator tolerates no skipped leg and passes only when every leg is `success`; and the head-bound input is read exactly (`HEAD_SHA_OK` must be exactly `true`, so its empty spelling never reads as bound).

**Assembly.** The aggregator step body extracted from `ci.yml` and executed (not its text); its inputs `SKIP_LEGS`, `ACTIVE`, `HEAD_SHA_OK` (read from the pr-selection outputs, W7 pins exactly that), `ATTEMPT`, `EVENT_NAME`; the six legs; the events G1-8 already covers plus `pull_request`. Two instruments, which are NOT the same thing: the main-line `tol` rows (G1-8, G1-8c) are executed characterizations of the real body; the `mutate_tol` probe set (rows p0..p22 in `ci-test-aggregator-diagnosis.test.sh`) is what drives mutants, and it never runs the main-line rows. So any new mutant needs its own probe row in that set.

G1-8c is a must-PASS characterization (the empty-inputs state is full CI), not a guard by itself. With `SKIP_LEGS=''` the tolerance regex fails on its own, so single-operator mutants of the tolerance cannot change this state; only a compound mutant can.

**Mutation matrix.**

| # | Mutation of the extracted body | Must go RED via |
|---|---|---|
| 1 | a NEW `tolmut.py` operator loosening `HEAD_SHA_OK` to `!= "false"` (empty reads as bound) | a NEW probe row in the p-set: a non-empty listed skip with `ACTIVE=true` and `HEAD_SHA_OK=''` (today the p-set has `HEAD_SHA_OK` only as `false`) |
| 2 | COMPOUND: the outer tolerance condition removed (the existing `no-active`/`no-regex` operators) AND any skipped leg tolerated (the existing `tolerate-anything-skipped` operator), applied together | G1-8c skipped-leg rows (rc must be 1) over all three gateable legs, run through a NEW probe row with empty inputs on `pull_request` |
| 3 | the final line prints the tolerated banner when `tolerated` is `","` | G1-8c all-green row asserts the exact six-leg line and forbids `PR-AFFECTED-SKIP` |

**Harness rows.** (a) The mutant rows 1 and 2 each require a probe row that did not exist before; the suite's `mutate_tol` landing check (the mutant differs from the pristine body) stays on. (b) Must-PASS non-canonical: `HEAD_SHA_OK` = the real GitHub spelling `false` (a computed boolean string) beside the empty spelling.

**Anchor.** `AGG_DIGEST` in `scripts/ci-push-dedupe.test.sh` pins the aggregator step's parsed content by sha256 and this PR leaves it unchanged; any edit to the step moves the digest and must be re-measured in the same PR by the author of that edit, which the reviewer sees in the diff.

## Test Scenarios

| Scenario | Switch | Diff | Expected |
|---|---|---|---|
| Dark steady state | unset | any PR | job skipped, gated jobs and `test` run as before |
| Variable set to a typo | `ON` | doc-only | job runs, `switch=invalid`, `stage=1 reason=switch_off`, 0 selector calls |
| Variable set to a typo | `ON` | code | job runs, `reason=non_doc`, 0 selector calls |
| Measurement window | `on` | doc-only | job runs, `stage=2`, `locked=true active=false`, selector called 4 times |
| Activation (PR C) | `on`, lock removed | doc-only | unchanged by this PR: arms by the existing line |
| Non-PR events | any | any | job skipped (as today); aggregator unchanged |
| Re-run all jobs (attempt 2) while dark | unset | any | job still skipped (no `if:` reads `run_attempt`); full CI |

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or carries placeholder text fails `deepen-plan` Phase 4.6; this one carries the threshold and a concrete artifact and vector.
- Do not edit inside the `test` aggregator step's `run:` body or `env:`: a `run:` comment is part of the parsed string and moves `AGG_DIGEST`. Comments between `env:` keys are not parsed but are not needed here either.
- The comment block above the `pr-selection` job is outside the job block that `P-TIMEOUT-LINE` counts, but a second line reading exactly `    timeout-minutes: 3` inside the block reds `P-TIMEOUT-LINE`.
- Use here-strings (`grep -q ... <<< "$var"`), never `printf | grep -q`, in any new assertion under `pipefail` (early-match SIGPIPE false negatives).
- `vars` compares: both an unset variable (documented: an empty string) and a set one are strings, so `!= ''` is a plain string comparison, which Actions performs case-insensitively (which is why the exact `on` compare stays in bash). State this in the comment so the next reader does not "simplify" to `== 'on'`.
- The evaluator in `chk.py` re-implements Actions' expression semantics; it is a model. AC9 is the check of the model against the real thing, and the first time the `on` branch of the job `if:` is evaluated by real Actions is the PR C canary (listed as a PR C checklist item in the ADR amendment).
- Floors: derive from a full green run of the final tree. The trial figures in this plan (2980 rows) are a VOID run (the control-row gate stopped the battery), not a floor.
- The ADR-276 text is read by `workflow-run-deploy-invariants` G8: keep `gh run rerun` and the release workflow file name off one line.
- PR body: `Ref #9729`, and the `## Changelog` section the plugin AGENTS.md requires for a PR (no semver bump label needed for a CI-only change; follow `soleur:ship`).

## Plan Review Log

Panel (2026-10-15, headless): DHH-style overengineering lens, code-simplicity (per mechanism), architecture-strategist, spec-flow-analyzer (the last two because the threshold is single-user incident), and the CPO sign-off read. `soleur:engineering:review:kieran-rails-reviewer` was not run: its Rails-convention lens has no object in a bash and workflow-YAML change. CTO not re-spawned (brief).

- **CPO: APPROVED-WITH-CONDITIONS.** Conditions applied: AC9b recorded in the PR body before merge (Phase 6 and AC9); `darkequiv` and G1-8c stay executed tests of the real parsed `if:` strings and the real aggregator body; the amendment states the `sel_s`/`would_skip` stream stops while dark and that setting the variable is a separate authorized act; the CPO status above is completed by the user-impact-reviewer run at review time; AC10 and `Ref #9729` only. Status: signed off at plan time under those conditions.
- **Mechanical, applied:** AC9b preconditions (variable absent; run not a light draft) and the corrected Phase 6 rationale; AC9a relabelled background; AC9c added; model rows pinned and labelled (unset gives job-false, `0` gives job-true) with the docs check as a Phase 2 exit gate and only verified claims in the comment; AC10 uses the merge-base after a fetch; ADR item (5) reworded (the `switch_off` branch is reachable with a non-empty non-`on` value), rollback prose and the `ready_for_review`/`ACTION` PR C item added; the three stale comment clauses in `ci.yml` and the driver header listed; AC3 notes the `paths_too_long` precedence; G1-8c folded into the existing G1-8 loop; duplicated mutants removed (Guard 1 from 8 to 5, Guard 2 from 8 to 6, Guard 3 from 5 to 3); AC1 values cut from 14 to 8; ADR item (6) dropped (AC10 proves it).
- **Taste, kept as written (operator-requested scope is never auto-cut):** the `darkequiv` executed proof and per-guard mutants are verbatim asks ("synthetic needs-result triples through the real aggregator body and the real gated-job `if:` expressions", "mutants for each new guard"); the enumerated re-run list is the brief's own list; the `PRSEL_IF` constant is kept because it is what makes the 11 red rows one edit. Suggested but not taken: replacing the list with a full `scripts/test-all.sh` run (CI performs it anyway; the enumerated run gives the pre-push signal the brief asked for).
- **D3 (ruled by the CTO agent, 2026-10-15):** the brief's "take the measurement via workflow_dispatch" is infeasible (the job is skipped and the driver exits `not_pr` off pull_request); the CTO's earlier wording allowed "a workflow_dispatch run or the PR C replay", so the measurement is taken in the PR C replay and the ADR amendment documents the procedure (fresh hosted runner, `time bash scripts/test-all.sh --print-selection --paths=README.md` run cold then warm, budget raised above the cold pass). This is a ruled technical row, not an open User-Challenge.

