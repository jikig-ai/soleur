# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-07-19-fix-nic-wait-gate-tunnel-connector-plan.md
- Status: complete

### Errors
- Transient `ENOSPC` on the agent temp filesystem mid-session; retried successfully, no impact.
- Self-inflicted design defect caught before finalizing: the first draft put the timeout emit in a caller-side `|| soleur-boot-emit …` arm while also specifying the helper exits 0 on timeout, making `private_nic_timeout` unemittable. Fixed by moving all emission inside the helper.
- Two AC-authoring defects found by executing the ACs rather than reading them: `grep -c` exits 1 on a zero count (so `== 0` ACs abort under `set -e` on the passing case), and an unscoped `git diff` AC matched the plan's own prose about reboots. Both fixed and recorded as Sharp Edges.

### Decisions
- Defer-not-abort implemented as a runcmd wait placed **before** `cloudflared service install`, NOT an `ExecStartPre`. An `ExecStartPre` leaves the unit `activating`, consuming the pre-existing `cloudflared_ready` ~60s fail-closed budget and detonating its `|| exit 1` — reproducing the CF-5 catastrophe this work exists to prevent.
- A separate baked `soleur-wait-nic` rather than a `nic` verb on `soleur-wait-ready`: the shared helper is fail-closed by contract, and a soft verb would make that contract conditional on a boot path where the wrong branch bricks the host. Shared helper stays byte-identical.
- `ExecStartPre` rejected outright, not deferred. Reviewer dissent (engineering prefers the drop-in long-term) recorded with a revival condition.
- Severity framing split into common case (bounded, self-healing) vs pathological (~14 days, all signals green); `single-user incident` threshold justified by the latter.
- Budget re-derived live: 22,372 B against CI budget 22,450 → **78 B** headroom (prior figure reproduced). The binding constraint is the CI ratchet, not Hetzner's cap (10,396 B free). The `#6500` "Phase 0 measurement" pointer in the brief is a false lead — it carries a Doppler secret-name count, no byte figures.

### Findings surfaced beyond plan scope
1. **P0 the brief had described as safe.** `soleur-host-bootstrap.sh` feeds `host_scripts_content_hash`, verified at boot under `set -e`; `image_name` defaults to mutable `:latest`. A fresh `web-1` created between the apply and the matching bake aborts its entire runcmd. The existing coherence guard covers only the web-2-recreate job (verified: one call site), leaving the routine apply and fresh-create paths — this plan's target — uncovered. Now AC-gated.
2. **The archived CF-5 trade table is stale.** All three ingress services are now private-IP-relative, so a NIC-less connector serves nothing, not just `registry.`.

### Components Invoked
`soleur:plan` → `soleur:deepen-plan`; agents: learnings-researcher, Explore (x2), engineering:cto, architecture-strategist, spec-flow-analyzer, code-simplicity-reviewer, security-sentinel, best-practices-researcher; deepen-plan halt gates 4.5/4.55/4.6/4.7/4.8/4.9 (all pass) + Phase 4.4 precedent-diff.
