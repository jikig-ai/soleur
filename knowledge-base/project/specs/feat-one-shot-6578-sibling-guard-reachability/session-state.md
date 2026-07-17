# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-07-17-fix-sibling-guard-pipefail-reachability-measurement-plan.md
- Status: complete

### Errors
None blocking. Two self-corrections during planning, both caught and fixed before commit:
- First corpus grep used pathspec `apps/web-platform/infra/**/*.sh`, which silently undercounted (5 files vs 44). Recorded as a Sharp Edge in the plan.
- v1 of the plan asserted "202 `|| true` lines make this class material" — a syntax count with zero overlap with the corpus under test, i.e. the same unmeasured-figure defect the task exists to correct, committed inside the plan condemning it. Caught by dhh, verified, cut.

### Decisions
- Cut v1's classifier + 284-row provenance ledger + 11-rung attestation. Both review panels fired on the same scope; per plan-review's rule that means delete, not fix. The reachability predicate collapses (R1 eliminates <=16/284, R2 ~0 once `set -e` is admitted), so R3 (window-existence) decides everything and is undecidable for var-fed sites without the byte model the prior PR retracted.
- Reframed the deliverable from "how many sites are reachable" to "can this class be triaged at all", with the disposition rule stated over the measured production denominator (46 sites / 11 files), not 284.
- Pinned the grep implementation as a hard precondition — the probe aborts on a non-GNU grep rather than warning. Session `grep` is a shell function shadowing GNU grep with `ugrep`, whose `-q` does not early-exit; first probes read 0/200 and 0/50 and would have produced a false all-clear.
- Corrected the brief's FR4 premise twice: capture-once alone does NOT close the empty-read-back hole (the merged file annotates its own FATAL line as "NOT a fail-open guard"; the paired non-vacuity rung closes it), and the hole is orthogonal to the pipe conversion — measured identical under both forms. FR4's pinning test moves into `scan-workflow-mutation.test.sh`, which already owns the sandbox.
- Corrected the blast-radius call: the repo is PUBLIC, so a per-site index of live-vacuous security rungs is a targeting artifact. The deliverable ships counts + commands only; site detail goes to the tracking issue.
- Recorded three decision-challenges rather than silently applying any — notably UC-3, where dhh and cto converge on "skip the measurement, convert the class blind". That reverses operator-stated direction the operator has now declined twice, so it is surfaced with the data, not auto-applied.

### Components Invoked
- `Skill: soleur:plan`
- `Skill: soleur:plan-review`
- `Skill: soleur:deepen-plan`
- Agents: `learnings-researcher`, `dhh-rails-reviewer`, `kieran-rails-reviewer`, `code-simplicity-reviewer`, `architecture-strategist`, `spec-flow-analyzer`, `soleur:engineering:cto` (devex lens), scoped advisor consult (`general-purpose`, model `fable`)
