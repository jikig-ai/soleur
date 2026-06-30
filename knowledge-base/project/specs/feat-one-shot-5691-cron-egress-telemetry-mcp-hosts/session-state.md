# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-06-29-chore-cron-egress-mcp-telemetry-silence-at-source-plan.md
- Status: complete

### Errors
None. (Two background Monitor waits timed out benignly — the review agents signal completion via task-notifications, not `.exit` files; all three completed and were folded in.)

### Decisions
- Root cause (AC1/AC3): sporadic egress drops to mcp.cloudflare/vercel/stripe.com come from the claude-eval cron substrate spawning `claude --print --plugin-dir plugins/soleur`, which auto-connects plugin.json's four bundled remote HTTP MCP servers at startup. The containment hook denies every `mcp__*` tool (only ux-audit gets Playwright), so these connections are non-essential by construction. The 34.149.66.137 Datadog-vhost dialer is unprovable statically (default GCP-LB cert) — most likely Claude Code telemetry or the context7 backend.
- Decision (AC2): keep-blocked for all five hosts; no allowlist widening. Silence at source via two levers: prepend `--strict-mcp-config` to cron spawns (drops plugin MCP servers) + `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` env (kills CC telemetry). cron-egress-allowlist.txt and cron-egress-firewall.test.sh are untouched.
- Single-chokepoint design: inject both levers in `spawnClaudeEval` (covers 15 spawn sites); 2 inline-spawn crons get explicit edits; ux-audit re-supplies its Playwright .mcp.json overlay via `--mcp-config` under strict mode.
- Load-bearing gate: the `--strict-mcp-config` suppression of plugin-bundled MCP servers is undocumented → Phase 0 Spike A (deterministic `--debug` zero-connect trace) is the PRIMARY acceptance proof; the post-merge Sentry absence sweep was demoted to corroboration. Documentation-only fallback if the spike fails.
- Review-driven corrections folded in: ux-audit losing Playwright would be a silent exit-0 green degradation (liveness-only monitor) → guard is pre-merge; the 2 inline crons make no MCP dial (no `--plugin-dir`) so telemetry env is their only load-bearing fix; replaced a weak grep parity test with a `resolveClaudeBin()` structural drift invariant + filed a follow-up to migrate the inline crons onto the chokepoint.

### Components Invoked
- Skill soleur:plan (#5691) → created plan + tasks.md
- Skill soleur:deepen-plan → enhancement pass
- Agent claude-code-guide (CLI flag/telemetry-env verification)
- Agents architecture-strategist, code-simplicity-reviewer, observability-coverage-reviewer (parallel plan review, code-verified)
- Tools: Bash, Read, Edit, Write, Monitor, ToolSearch
