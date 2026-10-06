# Decision Challenges — feat-one-shot-9555-9559-safe-bash-kb-search

Headless pipeline context (one-shot plan subagent): Taste/User-Challenge
findings are persisted here rather than presented at an interactive gate,
per `plan` "Plan Review (Always Runs)" headless arm.

## 2026-10-06 — plan-time records

- **[Taste] `GIT_BRANCH_READ_FLAG` breadth.** Issue #9555 enumerates a
  minimal allow-set (`git branch` bare / `--list` / `-v*` /
  `--show-current`); the plan admits a closed set of ALL pure list-mode
  flags (`-a`, `-r`, `--all`, `--remotes`, `--verbose`, `--contains`,
  `--merged`, `--no-merged`, `--points-at`, `--sort=`, `--format=`,
  `--abbrev`, `--column`, `--color`, `--ignore-case`) plus non-dash
  pattern/commit args reachable only after a list flag. Rationale: each
  member is provably list-mode read-only and under-denying common reads
  (`git branch --merged main` appears in repo tooling prose) would push
  them to the review-gate. The alternative — admitting only the issue's
  four literal forms — is tighter and equally valid. Recorded for
  reviewer/ship visibility; the operator's stated direction (read-only
  forms only) is honored either way.
- **[Mechanical → applied] harness limitation.** No Task/Workflow spawn
  surface exists in this Devin subagent context, so the plan skill's
  research fan-out, domain-leader spawn (Engineering + Support assessed
  inline), spec-flow pass, Step 4.5 advisor consult, and the plan-review
  agent panel were executed as inline orchestrator analysis. The standing
  panel check (AC concurrency independence — `cq-ac-must-not-depend-on-
  concurrent-sessions`) was applied textually: all ACs are deterministic
  file/command assertions. Noted in the plan's Research Insights.
