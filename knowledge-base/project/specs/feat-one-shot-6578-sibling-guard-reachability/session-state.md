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

## Session Errors

### 1. Uncommitted verified work was silently reverted, twice, mid-session
`worktree-manager.sh` carries a "Syncing on-disk files from git HEAD" pass
(`:2133-2180`) and `.claude/hooks/guardrails.sh` can invoke it. It restores tracked
files to HEAD, discarding uncommitted working-tree edits with no warning to the
agent that asked for them.

Cost here: two full re-applications of verified work (the `cat-deploy-state.sh` live
fix, three probe corrections, and a complete note rewrite). The dangerous part was
not the loss — it was the SILENCE. `python .replace()` no-ops when its anchor is
absent, so the reconciliation scripts kept printing "ok"/"reconciled" against a
reverted file. The revert was only caught because a probe re-run printed the OLD
numbers, which contradicted a result verified minutes earlier.

**How to apply:** commit each verified unit IMMEDIATELY — never hold verified work in
the working tree across a long-running background job. Where an edit must be
followed by a commit, do both in ONE Bash invocation (`cat > file <<'EOF' … EOF;
git add …; git commit`) so no window exists. And treat any tool that silently
no-ops on a missing anchor (`str.replace`, `sed s///` without `q`) as unsafe for
reconciliation: assert the anchor (`assert old in s`) or the edit is unverified.

### 2. A measurement instrument that reports 0 when broken looks exactly like a finding
The probe's `count_sites` called a function that did not exist. Every payload file
scored zero, the corpus SHRANK, and the shrink read as a real result — the same
false-all-clear shape the probe exists to prevent, arriving through the back door.

**How to apply:** any measurement tool must fail LOUD on a broken pipeline rather
than return a plausible zero. `count_sites` now asserts its result is numeric and
exits non-zero otherwise. The general rule: a tool whose broken state is
indistinguishable from its clean state cannot be trusted for either.
