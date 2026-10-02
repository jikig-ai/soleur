---
title: Pipeline tally — per-branch flat-key counters, script-invoked, fail-open
status: accepted
date: 2026-10-01
amends: none
supersedes: none
issue: 9403
related: [9339, 5086, 9413]
related_adrs: [ADR-056, ADR-108, ADR-127, ADR-254, ADR-261]
tags: [pipeline, cost-visibility, session-state, stop-hook]
brand_survival_threshold: single-user incident
---

# ADR-264: Pipeline tally — per-branch flat-key counters, script-invoked, fail-open

## Status

**Accepted — 2026-10-01 (#9403).**

## Context

Autonomous pipelines (one-shot, work, review, test-fix-loop, drain-*,
resolve-*, eval-harness) spend real work — review seats spawned, CI cycles,
fix rounds, agent rounds — but print no running tally, so a run's cost shape is
only ever discovered post-hoc. The inciting case, PR #9339, consumed an
11-seat review and ~8 CI cycles for a small fix; nobody saw that until the end.
Issue #9403 asked for a running tally plus a configurable budget pause.

Two constraints shaped the design: prose bookkeeping has ~zero measured
compliance, so counters must be script invocations; and hook-only enforcement
covers ~1.5 of 4 harnesses, so the primary mechanism must work from the skill
layer, with hooks at most a supplemental floor.

## Decision

`plugins/soleur/scripts/pipeline-tally.sh` is the measuring instrument: a
per-branch counter file under the session-state root
(`<git-common-dir>/soleur-session-state/counters/<sanitized-branch>`), flat
`key=value`, rewritten wholesale under `with_lock`. Subcommands: `init`
(merge-safe; persists `--max-<dim>` caps into the file so they survive
skill-to-skill handoff), `incr <dim>`, `show`, `gate <dim>` (OK / WARN at 80% /
STOP / UNKNOWN), `selfcheck` (writes nothing). Everything is fail-open — exit
0 always, `SOLEUR_TALLY_ERROR reason=<k>` on stderr — except that `UNKNOWN`
under a configured cap renders `cap-unenforced` downstream, never a clean pass.

Caps are per-dimension and opt-in. Crossing a hard cap is a **classified stop**
(`budget-capped` marker + resume prompt written to `session-state.md`), never
a blocking prompt — the #8611 shape; unattended runs must not wait on a
question. `capped=` is sticky until caps are raised (`init` with new `--max-*`
→ `capped-reset`, preserving the forensic counts) or `--reset` is explicit.
`hooks/stop-hook.sh` additionally declines to continue a ralph loop while the
ledger is capped — a Claude-only negative enforcement floor.

ship renders the ledger as a `## Pipeline Tally` section in both PR-body
templates (counts only — no prompts, paths, or identifiers), ending with the
machine line `Pipeline-Tally: seats=N; ci_cycles=N; fix_rounds=N;
agent_rounds=N`. That body line is the cross-PR aggregation surface **because
squash merge drops branch-commit trailers** — `gh pr merge --squash` derives
main's commit from the PR body, so git trailers never reach `git log` on main.

## Alternatives

| Approach | Verdict | Why |
|---|---|---|
| Per-branch counters on session-state (chosen) | accepted | Cross-harness, survives worktrees/resumes, executable not prose |
| Derive at report time (trailer/commits/`gh run list`) | rejected | No running tally; nothing to gate on mid-run |
| Workflow-native `budget` object only | rejected | Covers only the opt-in workflow path; prose is the default |
| emit-decision enum extension | rejected | Frozen two-event contract (ADR-254) |
| PreToolUse hook enforcement | deferred | ~1.5/4 harness coverage; v2 candidate tracked in #9413 |
| Blocking prompt pause | rejected | Strands unattended runs; classified stop chosen instead |
| Dollar budget / dollar tally | rejected | ADR-056 units doctrine; subscription runs have no marginal dollar cost; would imply a billing relationship |
| Git `Pipeline-Cost:` trailer | rejected | Squash merge drops branch-commit trailers; the PR-body line carries aggregation |
| Tee-derived mechanical seat counts | deferred | `agent-token-tee.sh` counts all spawns, cannot isolate review seats; JSONL coupling for one dimension; tracked in #9413 |

## Consequences

- The running `tally:` line appears at every phase boundary of instrumented
  skills; the operator sees the cost shape mid-run, not just post-hoc.
- A `budget-capped` halt is durable and resumable only via raised caps or an
  explicit `--reset` — a capped run cannot livelock or silently continue.
- Counters can drift under prose-path discipline gaps; the
  `SOLEUR_TALLY_ABSENT` / `SOLEUR_TALLY_CAP_IGNORED` PR-body sentinels and the
  components.test.ts call-out sentinel bound the risk rather than hide it.
- No comparative "typical range" verdict exists yet — the body prints counts +
  cap-fraction only; a baseline-claiming verdict is deferred until PR-history
  aggregation exists.
