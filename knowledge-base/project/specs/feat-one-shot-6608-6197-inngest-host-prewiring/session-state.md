# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-07-18-fix-inngest-host-nftables-allowlist-parity-plan.md
- Status: complete

### Errors
None. Deepen-plan HALT gates passed (4.6/4.7/4.8/4.9); 4.55 Downtime + 4.5 Network-outage fired and were handled with telemetry.

### Decisions
- #6197 is a stale premise — arm64 Vector shipper + BETTERSTACK_LOGS_TOKEN already delivered (PR #6209, hardened #6631, baked into OCI v1.1.23 #6651). VERIFIED in-tree: inngest-betterstack-token.tf, inngest-bootstrap.sh:731-737 arm64→aarch64, vector.tf vector_sha256_arm64, inngest-host.test.sh:101-110. Close #6197 as already-delivered; no code here.
- This PR is #6608 only: user_data-ForceNew literal fix web_host_private_ips ".10,.11" -> ".10" + a drift-parity guard.
- Sibling co-edit: inngest-host.test.sh:91 hardcodes the stale literal; parity guard (mirroring cutover-inngest-workflow.test.sh:184-199, derived from var.web_hosts) replaces it.
- Merge is inert (inngest-host.tf excluded from per-PR CI -target); apply folds into the HELD Phase-2 cutover host replace. Use `Ref #6608`, close at Phase-2.
- No new ADR / no C4 change.

### Components Invoked
- Skill soleur:plan, Skill soleur:deepen-plan
- Agent Explore, Agent soleur:engineering:research:learnings-researcher
- gh, git, incidents.sh telemetry
