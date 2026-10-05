# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-10-04-fix-playwright-mcp-browser-closing-on-its-own-plan.md
- Status: complete

### Errors
None blocking. The brief's heartbeat theory was refuted by the plan: stdio passes runHeartbeat=false. The measured cause is the plugin Stop hook browser-cleanup-hook.sh (SIGTERMs every --remote-debugging-pipe Chrome host-wide at the end of every turn).

### Decisions
- Delete the Stop hook with its four mirror edits (hooks.json, devin-dispositions.tsv, web parity test REGISTRY, retired-rule-ids breadcrumb); ADR-271, ADR-213 addendum, ADR-093 amendment, learning.
- PLAYWRIGHT_MCP_PING_TIMEOUT_MS=0 added to both registrations as an inert latent-hazard guard only; the PR must not claim it fixes the symptom.
- Replace the project .mcp.json per-profile pkill reaper with a flock slot lease; plugin registration gets an opt-in --chromium-fallback proxy flag.
- One PR (reviewer-recommended split recorded in decision-challenges.md).
- Live idle survival is NOT proven; confirmation needs a full Claude Code restart plus >60s idle across several turns.

### Components Invoked
soleur:plan, soleur:deepen-plan (learnings-researcher, code-simplicity-reviewer, cto, architecture-strategist, two general-purpose probes)
