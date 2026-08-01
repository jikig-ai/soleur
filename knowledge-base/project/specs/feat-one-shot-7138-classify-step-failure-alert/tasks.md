# Tasks — #7138 release-outcome: a failing classify step silences every alert channel

Plan: `knowledge-base/project/plans/2026-08-01-fix-release-outcome-classifier-failure-alert-plan.md`
Branch: `feat-one-shot-7138-classify-step-failure-alert`
Closes: #7138

Phase order is load-bearing: the shipped `if:` strings (Phase 1/2) must exist before the
harness copies them (Phase 3) and before the drift assertion compares them (Phase 4).

## Phase 0 — Preconditions

- [ ] T0.1 `command -v act` — record the result; do not use it either way (reimplemented evaluator)
- [ ] T0.2 `command -v actionlint` and `bash scripts/lint-workflows.sh` — record baseline clean
- [ ] T0.3 `python3 scripts/lint-workflow-step-env-refs.py` — record exit 0 / `0 findings` baseline
- [ ] T0.4 Read `.github/workflows/gdpr-gate-self-test.yml`; copy its `pull_request` + `paths` + permissions + timeout conventions
- [ ] T0.5 Confirm `test-scripts` → synthetic `test` aggregator is the required check; confirm the harness will NOT be added to any ruleset

## Phase 1 — Mirror step (the issue's stated scope)

- [ ] T1.1 `.github/workflows/web-platform-release.yml`: add `id: mirror` to the "Mirror non-delivery to Sentry and fail loudly" step
- [ ] T1.2 Replace its `if:` with the one-line shared-predicate form (plan §1.2)
- [ ] T1.3 Guard both `${FAILED}` expansions → `${FAILED:-}`
- [ ] T1.4 Branch `MSG` + the `classifier` tag on whether `FAILED` is empty; keep `op: release-alert-undelivered` unchanged
- [ ] T1.5 Branch the `$GITHUB_STEP_SUMMARY` and terminal `::error::` lines the same way; both keep `exit 1`
- [ ] T1.6 Add the "DO NOT add continue-on-error" comment to the `outcome` step

## Phase 2 — Email step (the push channel) — separable, cut-able as a unit

- [ ] T2.1 Replace the email step's `if:` with the shared predicate in `${{ … }}` form
- [ ] T2.2 Add `CLASSIFIER: ${{ steps.outcome.conclusion }}` to that step's **own** `env:`
- [ ] T2.3 Add the third headline branch ahead of the `R_DEPLOY` branch (plan §2.3)
- [ ] T2.4 Guard the "What stopped" list so an empty `FAILED_HTML` renders no empty `<ul></ul>`
- [ ] T2.5 New subject: `[RELEASE CHECK FAILED] …` — deliberately not `[RELEASE FAILED]`

## Phase 3 — Execution harness (AC2)

- [ ] T3.1 Create `.github/workflows/release-outcome-condition-harness.yml` with the self-bootstrapping `pull_request` `paths:` filter + `workflow_dispatch`
- [ ] T3.2 One `probe` matrix job, arms A–F, `fail-fast: false`, job-level `continue-on-error: true`, explicit `name: probe ${{ matrix.arm }}`
- [ ] T3.3 Copy the shipped `email` and `mirror` `if:` strings **verbatim** into the harness (each appears exactly once)
- [ ] T3.4 `verdict` job (`needs: [probe]`, `if: always()`, `actions: read`) asserting the six-arm truth table via the jobs API
- [ ] T3.5 Verdict also asserts six arms were observed (an empty sweep must not read as green)
- [ ] T3.6 Record the three runtime facts from plan §3.6 in `verification-evidence.md`; adapt if observed behaviour differs
- [ ] T3.7 `bash scripts/lint-workflows.sh` + `python3 scripts/lint-workflow-step-env-refs.py` clean with the new workflow present

## Phase 4 — Static assertions (AC3)

- [ ] T4.1 Refactor B1b's extractor into one helper keyed on step `id`
- [ ] T4.2 B1c — mirror `if:` contains `steps.outcome.conclusion == 'failure'` (whole phrase, not a bare token)
- [ ] T4.3 B1d — email `if:` contains both `!cancelled()` and the classifier predicate *(Phase 2 only)*
- [ ] T4.4 B1e — the `outcome` step declares no `continue-on-error`
- [ ] T4.5 B1f — harness↔shipped `if:` normalized byte-equality for `email` and `mirror`
- [ ] T4.6 B1g — the harness workflow exists and declares `on: pull_request`

## Phase 5 — Local execution of the shipped mirror body + C4

- [ ] T5.1 Part B: extract the `mirror` body by id; arms M1 (`FAILED=""`), M2 (populated), M3 (mutation proof — unguarded form must die with `unbound variable`)
- [ ] T5.2 Part B: email arm for the new third branch *(Phase 2 only)*
- [ ] T5.3 `model.c4`: add the `github -> resend` edge (plan §5.3)
- [ ] T5.4 `model.c4`: amend the `github -> sentry` description to name the release-outcome mirror and its unrouted status

## Phase 6 — Verify

- [ ] T6.1 `bash scripts/lint-workflow-step-env-refs.test.sh` → `All tests passed`
- [ ] T6.2 `python3 scripts/lint-workflow-step-env-refs.py` → exit 0
- [ ] T6.3 `bash scripts/lint-workflows.sh` → clean
- [ ] T6.4 `bash scripts/test-all.sh scripts` → green (the gate's own invocation)
- [ ] T6.5 `cd apps/web-platform && ./node_modules/.bin/vitest run test/c4-code-syntax.test.ts test/c4-render.test.ts`
- [ ] T6.6 Mutation-prove B1c/B1d/B1e/B1f/B1g individually RED; record each output
- [ ] T6.7 Push; capture the harness run URL + `gh run view --json jobs` into `verification-evidence.md`
- [ ] T6.8 Harness mutation proof on a scratch branch: `always()` → arms C and D flip to `success`, verdict reds; delete the branch
- [ ] T6.9 `git grep -n "steps.outcome.outputs.failed" .github/workflows/web-platform-release.yml`

## Phase 7 — Tracked scope-out + close-out

- [ ] T7.1 File the `op:release-alert-undelivered` routing-gap issue (labels `type/bug`, `deferred-scope-out`, `domain/engineering`, `priority/p2-medium`)
- [ ] T7.2 `decision-challenges.md` records the Phase-2 scope deviation for `/ship`
- [ ] T7.3 PR body contains `Closes #7138`; #7136 / #7137 / #7095 referenced as context only
- [ ] T7.4 `/compound` — learning under `knowledge-base/project/learnings/workflow-patterns/` (directory + topic only; date chosen at write time)

---

## Plan Review Revisions (R1–R42) — SUPERSEDE the phases above where they conflict

Read `## Plan Review Revisions` in the plan before starting. 7-reviewer panel; the shape of
the work changed materially. Highest-severity, in execution order:

- [ ] T-R34 **Before writing Phase 2**: re-verify "the mirror pages nobody" against the LIVE
      Sentry rules API. 4 of 29 rules are `ignore_changes` placeholders unreadable from the
      `.tf`, and the repo documents a non-IaC paging path (built-in high-priority rule →
      personal notification rule) that `level:"error"` feeds. The premise may be false.
- [ ] T-R35 Rewrite the Overview / Scope decision / C4 label on the **job-scope** argument
      (three other push channels exist; `release-outcome` is the only one that fires
      regardless of which job fails). Delete "the only push channel".
- [ ] T-R25 Remove the fabricated quotation (done in the plan body; verify none remain).
- [ ] T-R1 Guard `${FAILED}` at `web-platform-release.yml:1357` and `:1360` — Phase 2 makes
      them reachable; 1357 sits between the curl and the `delivered=1` write.
- [ ] T-R4 Branch the unconditional closing paragraph (`:1342`); assert the classifier-death
      body does NOT contain `nothing reaches production`.
- [ ] T-R5/R6 One discriminator in both steps; do not preempt a genuine `R_DEPLOY` failure.
- [ ] T-R7 Every `B1x` selector fails on zero matches (an `id` rename must not read as PASS).
- [ ] T-R26/R27 Fix the `curl` stub (`-d|--data|--data-raw`) and `run_step`'s `env -i` list
      (`GITHUB_STEP_SUMMARY`, `NEXT_PUBLIC_SENTRY_DSN`, `RUN_URL`, `GITHUB_SHA`) BEFORE any
      mirror arm — otherwise M1 false-REDs and M3 passes vacuously.
- [ ] T-R10/R11/R12 Harness: 3 arms (A/B/C), disposable (run → capture → delete before merge),
      cut Phase 6.8 + AC2b. R36: the verdict job's red spawns a production agent via the
      `workflow_run` → `engineering.ci_failed` webhook — enumerate in User-Brand Impact.
- [ ] T-R38 Fix the three vacuous ACs (lint-workflows exits 0 on findings; `infra/github/` is
      repo-root; the c4 vitest files never read `model.c4` — use `regenerate-c4-model.sh` +
      `c4-model-freshness.test.sh`).
- [ ] T-R8/R9/R13/R14/R15 Full-string B1c/B1d; verdict `env:` credentials; cut M2/M3, 6.2, 6.9;
      ACs 12 → 5.
- [ ] T-R40 C4: fix the `:528` `paths:` falsehood and the `:529` stale rule count (21/22 → 29);
      add `model.likec4.json` to Files to Edit.
- [ ] T-R17/R18/R19/R39 Phase 7: drop the circular trigger, state the Phase 2 coupling, name
      the Resend-single-point residual and the classify-hang/timeout/cancellation residual.
- [ ] T-R41 Cite ADR-117; re-argue the deferral on change-class blast radius.
- [ ] T-R42 Workflow edits must go through Bash (`security_reminder_hook.py WORKFLOW_GLOBS`);
      the "eight consecutive runs" figure is retracted to 15 by the 2026-07-29 post-mortem.
- [ ] T-R16 **Operator decision** (`decision-challenges.md` DC-2): generalize the defect class
      as a linter rule now, or file a tracking issue for the 3 other live instances.
