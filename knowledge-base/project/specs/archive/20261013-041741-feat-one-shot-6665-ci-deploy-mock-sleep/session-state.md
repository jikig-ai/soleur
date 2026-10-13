# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-07-27-perf-ci-deploy-test-sleep-mock-default-plan.md
- Status: complete

### Errors
- Seven plan-drafting defects, all caught by the deepen-plan verify/self-audit passes and fixed before the phase finished:
  - The plan asserted "17 sleep sites" in `ci-deploy.sh` when there are **15** invocations — a bare `grep -c '\bsleep\b'` also counts a comment at `:1430` and the `_sleeps` array declaration at `:1437`. Corrected in plan + `tasks.md`, recorded as a Sharp Edge.
  - Plan↔`tasks.md` numbering collision: the plan cited "Phase 2.2", "Phase 3.2", "Phase 3.3", but `tasks.md` had independently decomposed those phases so the numbers pointed at *different* steps. Since `/work` executes against `tasks.md`, an implementer following a plan citation would have landed on the wrong step. Fixed by mirroring the plan's numbering exactly and lettering the finer actions.
  - Un-prefixed gate numbers (`Phase 1.4`, `2.9.1`, `2.9.2`, `4.45`) that read as this plan's own phases.
  - `DC-2` claimed "AC6 is cut" when AC numbers had been compacted and the current AC6 is unrelated.
  - `DC-4` argued from the baseline's 134s CPU while the rest of the plan uses the counterfactual's 117s as "the floor" — a 15% discrepancy in the one claim whose whole point is the floor.
  - A wrong rationale for the `$MOCK_SLEEP_LOG` rider, and stale v1-numbering cross-references after the review cuts.
- Instrumentation dead end (informative): a PATH-prepended logging `sleep` shim caught only 3 of the suite's sleeps, because `TEST_PATH_BASE` is a `readonly` *absolute* PATH that runner subshells substitute wholesale. That independently proved `$MOCK_DIR` is the only lever, and that the SIGTERM-trap test is out of the mock's reach by construction. Replaced with a zero-code-change counterfactual run.
- One reviewer claim refuted: spec-flow flagged "CRITICAL harness self-shadowing" as a blocker; direct reading — confirmed three times, including by the verify pass — shows all 11 PATH exports are subshell-scoped. Recorded in Research Reconciliation rather than inherited.

### Decisions
- **Invert the default rather than opt in per test** — `create_base_mocks` installs the no-op `sleep` unless `MOCK_SLEEP_REAL=1`. Opt-in means every future test silently re-pays the wall clock and the timeout-bump loop repeats.
- **Guard the hot-spin *class*, not the instance** — an invocation cap inside the mock (~500 → loud abort). This also supplies the replacement ceiling for a defense the flip removes: real `sleep` was an undeclared second brake on the canary `seq 1 10` loop.
- **Keep the recording rider on precedent grounds** — `workspaces-luks-harness.sh:301-315` already uses a recording no-op sleep and was written anticipating this issue by name.
- **Sequence the `timeout-minutes` change last, against real CI data** — the PR's own paths trigger the workflow, so numbers come from `gh api` on ≥2 runs, with a green run required at the new ceiling.
- **Cut ~60% of the first draft** (both simplification reviewers fired on the same scope), while adding the one failure mode nobody else named: a real `sleep` acting as an undeclared synchronization barrier, invisible to a single-run diff (AC2b: 5 identical name-sets, ≥1 under load).
- Four dissents preserved rather than silently applied, in `decision-challenges.md` (DC-1..DC-4) for `ship` to render.

### Components Invoked
- Skills: `soleur:plan`, `soleur:plan-review`, `soleur:deepen-plan`
- Agents: `learnings-researcher`, `Explore`, `spec-flow-analyzer`, `engineering:cto`, `dhh-rails-reviewer`, `kieran-rails-reviewer`, `code-simplicity-reviewer`, `architecture-strategist`, scoped strong-model consult, verify-the-negative pass, post-edit self-audit pass
- Gates: plan 1.4 / 1.7.5 / 2.5 / 2.6 / 2.7 / 2.8 / 2.9 / 2.10 / 2.11; deepen-plan 4.5 / 4.6 / 4.7 / 4.8 / 4.45 (4.9, 4.10, 4.55 skipped with reason); telemetry emitted for `hr-ssh-diagnosis-verify-firewall`
- Measurements: baseline suite run, PATH-shim instrumentation run, forced-gate counterfactual run, PASS-name-set diff
