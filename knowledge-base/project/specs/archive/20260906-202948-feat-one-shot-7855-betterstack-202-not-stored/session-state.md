# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-04-fix-betterstack-202-is-not-storage-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)
- Scope check: PASS — planning touched only plans/, specs/, and the hook-generated knowledge-base/INDEX.md
- Post-planning collision re-probe: plan frontmatter `issue: 7855` / `closes: 7855` — same ref cleared at Step 0a.5, no new target introduced

### Errors
- `plugin:github:github` MCP server failed to connect (400, malformed Authorization header); worked around with the `gh` CLI throughout — no impact on output.
- Self-caught in draft 1: AC6 prescribed `grep -c 'INGEST_ACCEPTING' scripts/` with no `-r`, so it exits 2 and prints `0` — passing because the command errored. Corrected.
- Caught by review in draft 2: the claim that source 2734275 is no absence alarm's positive control was FALSE — `ANCHOR_SQL` is exactly that. Guard now asserts the marker's `host_name` field, not the source id.
- Caught by review in draft 2: `bs_absence_classify` takes no arguments, so a "fourth state" would have required a shared-library arity change whose only consumer fails open. Redesigned as a composition in the single caller.
- Caught by review: a live credential-bypass in the probe's `https://*.betterstackdata.com/*` check — a glob crosses `/` and `?`, so `https://evil.com/?x=.betterstackdata.com/` matches.
- Caught by review: the poll bound is 16 minutes, not the "~50 min" quoted from a step comment (3x error).
- Caught by deepen agents: `betterstack-query.sh` site count is 141, not 71; the sweeper collapses all non-0/1 exits into one TRANSIENT arm.
- Caught by deepen gate 4.7: the `## Observability` block was missing its required `logs:` field — the gate halted the plan correctly.
- Not resolved (recorded as UNKNOWN, deliberately): why Better Stack accepts writes it does not store. Belongs to #7811.

### Decisions
- Reframed the issue against measurement rather than re-litigating it: the git-data table's absence is explained by a team-wide sink outage (#7811). Plan ships instruments and adopts no root cause for #7811, changing zero ingest-URL literals so that incident's evidence stays comparable.
- Compose, don't widen a shared contract: the three-way distinction is `(anchor_rc != 0) x bs_absence_classify()` in the one caller, leaving betterstack-query.sh, lib/betterstack-absence.sh and zot-restart-loop-alarm.sh untouched.
- Kept the ingest probe non-writing (ADR-192) and split the remediation: rename the token so it cannot be read as storage; a separate round-trip follow-through proves storage.
- Decided "no" on per-boot on-host readback: the ClickHouse query connection is team-scoped, so baking it in would put a whole-warehouse read credential on the git-data host.
- Refused to fabricate the latency constant: it cannot be measured while the warehouse is dark, so no constant changes in this PR.

### Verified independently by the parent before /work
- Warehouse hot+archive on the actively-used source: latest stored row `2026-09-03 12:18:10.458443`, earliest in window `2026-08-31 16:33:01`, n=441351 — i.e. ~27h dark as of 2026-09-04. Confirms the falsification; the issue's "known-good control" was itself dark.
- #7811 is OPEN and is the correct owner of the sink outage.

### Components Invoked
- Skills: soleur:plan, soleur:deepen-plan
- Agents: repo-research-analyst (x2), learnings-researcher, Explore, kieran-rails-reviewer, architecture-strategist, spec-flow-analyzer, code-simplicity-reviewer, framework-docs-researcher, general-purpose (advisor + verify-the-negative sweep)
- Tooling: gh CLI, doppler run -p soleur -c prd_terraform, scripts/betterstack-query.sh, Better Stack Telemetry API, scripts/lint-guard-contract.py, scripts/lint-infra-no-human-steps.py, markdownlint
- Commits: 53c512c85 (plan + tasks), b9ef48e5b (deepened), 70b8254e8 (decision challenges)
