# Session State

## Plan Phase
- Plan file: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-6288-zot-restart-loop-oom-telemetry/knowledge-base/project/plans/2026-07-09-fix-zot-restart-loop-oom-telemetry-plan.md
- Status: complete

### Errors
- Plan/tasks files were touched mid-authoring by a concurrent editor/linter; each reconciled into a consistent final state, no data lost.
- Live betterstack-query.sh telemetry initially returned oversized output (journald noise); resolved by filtering to the `SOLEUR_ZOT_DISK pcent=` marker.

### Decisions
- Two-slice, single-redeploy (telemetry + memory fix together): live telemetry shows zot_restarts climbing past the ~17:53 gc window (221→261, pcent 58→63), meeting the issue's "escalate the memory fix" re-eval criterion. P1, GHCR-covered.
- Confirmation signal corrected from page-cache-confounded host mem_used to the zot container's cgroup anonymous RSS (zot_anon_mb).
- storage.dedupe=false deferred (undedupe rewrite risks re-inflating disk). Fix is cx32 (4→8 GB, +~€2.1/mo) + ADR-062 --memory/--memory-swap cap.
- OOM detection hardened: keys on zot_restarts delta + exit_code=137 + journald oom_kills_5m window backstop + bounded zot_last_err for the non-OOM branch — not OOMKilled alone.
- mem_used_mb/mem_total_mb retained per operator's explicit #6288 request despite three reviewers recommending a cut — recorded as User-Challenge in decision-challenges.md for /ship to surface. Zero downtime for serving surface via GHCR atomic fallback.

### Components Invoked
- Skills: soleur:plan, soleur:deepen-plan
- Agents: repo-research-analyst, learnings-researcher, spec-flow-analyzer, coo, Task(fable) advisor, dhh-rails-reviewer, kieran-rails-reviewer, code-simplicity-reviewer
- Tools: betterstack-query.sh (live telemetry, no-SSH), gh, git (2 commits pushed)
