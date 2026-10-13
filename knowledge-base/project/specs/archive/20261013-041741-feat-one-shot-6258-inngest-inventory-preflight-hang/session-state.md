# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-07-09-fix-inngest-cutover-preflight-scan-hang-plan.md
- Status: complete

### Errors
None. All premise checks held (#6258/#6178/#6230 all OPEN, unchanged). All mandatory deepen-plan halt-gates passed (User-Brand Impact, Observability 5-field with ssh-free discoverability, no PAT-shaped vars, no UI surface, no downtime trigger). Only unresolved citation is the to-be-created ADR-106 (a Files-to-Create target, expected).

### Decisions
- Root cause is the HANG, not the pool cap. ADR-105 (PR #6265) bounded the connection footprint; the reproduced HTTP 000 is an unbounded pagination scan (`while :;` over a 365-day corpus) behind a webhook daemon with NO command-timeout — a timed-out client abandons a scan that keeps issuing queries and ratchets the next run to EMAXCONNSESSION. The residual 500 is the two-writer topology, deferred to #6178/#6230 (out of scope).
- Fix = bound scan duration (deadline + page ceiling) + abandon-safety + timeout-hierarchy + in-surface marker, riding the no-SSH infra-config auto-apply (apply-deploy-pipeline-fix.yml paths cover the 3 scripts). New ADR-106 amends ADR-105 (orthogonal: footprint vs duration).
- Deepen review corrections: (1) timeout is a sum-bound (deadline+per_page ≤ outer) via remaining-budget per-page clamp; (2) op=verify DoD re-scoped — registry_empty precondition can't go green pre-cutover, so DoD is op=inventory HTTP 200 + op=verify sub-probe transport proven by unit tests; (3) completeness by construction via dedicated eventNames:["reminder.scheduled"] query (never narrow FROM_TS) + differential test; (4) doublefire bounded by functionIDs+page-ceiling, not a narrowed window; (5) dropped /usr/bin/timeout hooks wrapper (can lose the marker) — in-script deadline suffices.
- Observability is journald-only (logger -t on the 3 already-allowlisted tags; stdout is the JSON body), START emitted as literal first line + curl-exit field to split pool-pressure-stall from slow-scan. Blast radius: inngest-inventory.sh also consumed by the 15-min health probe + op=execute/op=rollback.
- Threshold: single-user incident (dropped far-future armed reminder → false-clean cutover diff → silent reminder loss), requires_cpo_signoff: true; completeness invariant is the load-bearing guard.

### Components Invoked
- Skills: soleur:plan, soleur:deepen-plan
- Research agents: Explore x3, learnings-researcher
- Deepen agents: architecture-strategist, spec-flow-analyzer, data-integrity-guardian, observability-coverage-reviewer, Explore
