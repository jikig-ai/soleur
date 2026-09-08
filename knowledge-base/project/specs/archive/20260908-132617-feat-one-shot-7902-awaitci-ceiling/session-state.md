# Session State

## Plan Phase

- Plan file: knowledge-base/project/plans/archive/20260908-132617-2026-09-07-fix-release-await-ci-ceiling-vs-ci-duration-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors

- `gh run list --workflow=ci.yml --event=push` returned a stale index (August runs for a September
  query). Worked around with `gh api .../workflows/ci.yml/runs?...`; recorded in the plan so the
  figures are reproducible.
- First plan commit blocked by two MD038 markdownlint violations (leading spaces inside a code
  span); fixed and re-committed.
- `playwright` and `plugin:github:github` MCP servers failed to connect. Neither was needed — the
  `gh` CLI covered all GitHub work.

### Decisions

- Final decision: **bounded ceiling raise (3000s -> 3600s, drift threshold moved first) + shard
  `test-scripts` at K derived from measured timings.** The raise is the deterministic unblock; the
  shard stops it becoming the next incident.
- ADR-072 option 3 (`workflow_run`) was chosen provisionally, then overturned on measurement: a
  CTO ruling plus per-job timing showed `test-scripts` is 89.6% of CI wall clock at p50 and 99.8%
  of the critical path, and option 3 carries a fail-open — under `workflow_run`, `EXPECTED_SHA`
  and `BUILD_SHA` both resolve to the default-branch tip, so the #3409 gate would self-certify an
  un-CI'd tree. Option 3 stays deferred on open issue #5806, now carrying fourteen scoping findings.
- Review found the revised plan had excluded the ceiling raise on a bad cost estimate; it was
  bundled back in.
- The gated metric was corrected: the gate polls the `test` check-run, not the ci.yml run. They
  measure equal in 22/22 runs only because `test-scripts` is the tail — they diverge exactly when
  this plan succeeds. The originally claimed residual (`critical-css-gate` / `lockfile-sync`
  becoming the tail) was wrong; neither is in `test`'s closure.
- The partition was re-keyed onto the `run_suite` label with round-robin at that chokepoint:
  ~198 scripts-group suites are hand-registered and ~24 have no path, so "hash the suite path" had
  no domain. Totality and determinism became structural, deleting an entire guard.
- Scope cut on verification: `TC_RUNTIME_CEILING_S` needed no change (ADR-133 is already
  CI-exempt); Guard 1 extends the existing `lint-orphan-test-suites.sh` rather than rebuilding its
  discovery authority.

### Caveat carried into work

Raising `CEILING_S` costs ~12 minutes of production drift-alert sensitivity
(`DRIFT_SUSTAINED_THRESHOLD_MIN` 195->207). That is inside the drift probe's own measured 61-243
minute delivery interval, but it is a real, permanent trade recorded in DC-1.

### Components Invoked

- Skills: `soleur:plan`, `soleur:deepen-plan`
- Agents: `repo-research-analyst`, `learnings-researcher`, `general-purpose` (CI duration
  measurement), `soleur:engineering:cto`, `spec-flow-analyzer` (x2), Fable strong-model consult,
  `architecture-strategist`, `test-design-reviewer`, `code-simplicity-reviewer`
- Gates: plan 0.6/0.6b/0.7, 1.7.5, 2.5, 2.10 ADR/C4, 2.12 Guard Contract; deepen-plan
  4.6/4.7/4.8/4.11 — all pass. 4.5, 4.9, 4.10, 4.55 not applicable.
- Verifications: `lint-guard-contract.py`, `lint-infra-no-human-steps.py`, `c4-count-parity.test.sh`
  (10/10), `markdownlint-cli`, ADR-ordinal probe across all `origin/*` refs (207).

## Work Phase

- Status: starting
