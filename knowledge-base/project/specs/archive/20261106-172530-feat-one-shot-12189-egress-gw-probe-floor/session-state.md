# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-11-06-fix-egress-gw-probe-apply-floor-and-informational-resolver-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
- A first CTO ruling used the production alert's `updated_at` as the soak origin. Two read-only reads 10 minutes apart showed `updated_at` changing about every 5 minutes on every alert with no apply running, so the ruling was withdrawn and replaced by a pinned literal floor (the canary alert's `created_at`).

### Decisions
- Floor is a pinned literal `APPLY_FLOOR_EPOCH=1793967363` (2026-11-06T12:16:03Z) with 300 s slack on the recurrence comparison only; the live canary `created_at` is a cross-check; a missing or unparseable value is exit 3.
- Soak clock is `max(floor, latest production resolved_at)` plus 4 h; an open pre-floor production incident blocks a pass.
- The anchor's resolve actor is informational; rows on both roster hosts decide the pass and an unreadable warehouse read is exit 3; the verdict line appends `quiet_age_s` and `pre_floor_open_prod_incident`; exit 1 stays unused.
- ADR-218 gets a dated amendment and the runbook is edited in place: `resolved_by` null on incident 1048111600 OBSERVED (that it means an auto-resolve is inferred).

### Components Invoked
soleur:plan, soleur:deepen-plan, soleur:engineering:cto (x2), learnings-researcher, adversarial reviewer, code-simplicity-reviewer

cto_spawns=2
