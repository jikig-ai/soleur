# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-07-15-fix-web2-private-net-attach-and-tunnel-connector-homogeneity-plan.md
- Status: complete
- Scope verified: diff vs merge-base a9016a997 touched only knowledge-base/project/{plans,specs}/ — subagent stayed in plan-only mandate.

### Errors
- Five v1 claims falsified by plan-review, all corrected before deepen completed:
  1. P2b fix would have broken CI's only path to prod (repointing `connection.host` defeats the bridge's `iptables -d "$SERVER_IP"` NAT match).
  2. P3 fix would not have worked (step outputs are namespaced by step id → Slack warning stays inert).
  3. Named one root-cause puller when there are two; the decisive one (`cloudflare_record.app`) is unremovable.
  4. Counts asserted without running them — AC6 returned 7 not 2; "T10 retro-proof" measured 0; 12 connection blocks not 11.
  5. Claimed ADR-068 omitted the invariant when it states it verbatim.
- Missed the Phase 0.6 ADR-corpus grep: ADR-068:378-384 had already REJECTED per-host tunnels; P2b re-proposed an explicitly-rejected alternative.
- Self-audit pass caught three further defects (stale ADR-107 after renumbering, AC8/AC9 mislabel, unthreaded self-instruction). All swept; fixes in 18c212fe6.

### Decisions
- ADR-113 (next-free verified): KEEP ONE TUNNEL. The operator's premise ("a tunnel for each backend") is inverted — one tunnel is already the design and is correct. Records `localhost:`-as-category-error, invariant I1 (restated as a runtime precondition after review proved the construction-time form falsified), and I2.
- Amend ADR-008 (`superseded-in-part`) and ADR-068 (extend + fix stale count). ADR-096 is vindicated, not amended.
- Restore web-2 via the existing `warm-standby` dispatch — it already targets the missing resource. No new Terraform.
- `host_creates` HALT: fail-closed, no ack bypass. Guard rather than break the dependency (pull is resource-level `-target` semantics).
- Cut P2b; ship a ~10-LoC `hostname` tripwire — the only runtime evidence, and it unblocks the deferred audit.
- Un-mask CI without reversing ADR-096 — loudness, not blocking.

### Components Invoked
soleur:plan, soleur:plan-review, soleur:deepen-plan; agents: cto, terraform-architect, learnings-researcher, Explore, dhh-rails-reviewer, kieran-rails-reviewer, code-simplicity-reviewer, architecture-strategist, spec-flow-analyzer, scoped fable advisor consult, 2x realism passes; gh, git, jq, fixture measurement.
