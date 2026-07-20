# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-07-20-feat-inngest-liveness-marker-discriminators-and-registry-probe-op-plan.md
- Status: complete

### Errors
- Plan write blocked once by the IaC-routing PreToolUse hook — an acceptance criterion quoted a
  forbidden literal (a Doppler secret-write command) in order to *prohibit* it. Reworded rather
  than adding the opt-out ack, since the plan introduces no manual provisioning. Recorded as a
  Sharp Edge in the plan.
- v1 of the plan carried four P0 design defects, all caught by the review panel and corrected in
  v2 (see the plan's Review Reconciliation table). No defective plan was committed — v1 was
  rewritten before the first commit.
- deepen-plan Phase 4.55 halted the plan (force-replace of a serving resource with no
  zero-downtime evaluation). Closed by adding the required section; telemetry emitted.

### Decisions
- Re-scoped from "build a marker" to "extend + deliver" after measuring that PR #6702's marker is
  on `main` and inert on the host, with a passing positive control proving the zero-row reading
  was real.
- Replaced `backend_sha8` with `backend_is_prod` sourced from `inngest-server-flip-guard.sh`,
  eliminating a guaranteed false-escalation defect (prod and dark would have hashed identically),
  a missing cross-host comparand, and a `/proc/environ` read contradicting the repo's secrets
  boundary.
- Decoupled the H4 double-scheduler answer from the host replace by adding `op=doublefire-probe`
  alongside the requested `op=registry-probe` — the replace becomes delivery, not diagnosis.
- Split into three ordered PRs so the #6295 credential-leak fix is not gated behind an OCI build,
  and so two contradictory close semantics do not share one PR body.
- `Ref #6617`, not `Closes` — the close-condition is a post-merge replace, with explicit branches
  that refuse to close on a degraded or positive reading.

### Components Invoked
- Skill: soleur:plan, soleur:plan-review, soleur:deepen-plan
- Agents: Explore x2, dhh-rails-reviewer, kieran-rails-reviewer, code-simplicity-reviewer,
  architecture-strategist, spec-flow-analyzer, cto, cpo
- scripts/betterstack-query.sh (hot + archive arms, with positive control)
- gh issue/pr view for premise validation; git log/grep for attribution checks
- .claude/hooks/lib/incidents.sh — emit_incident for the Phase 4.55 gate

## Scope Ruling (operator, 2026-07-20)

Operator was presented UC-1 (three-PR split) and UC-2 (priority reorder) and ruled:

**Ship PR A + PR B now. PR C is HELD pending a separate decision.**

- **PR A** (`_pf_scrub` libpq redaction, `Closes #6295`) — in scope.
- **PR B** (standalone `op=registry-probe` + `op=doublefire-probe`, `Ref #6617`) — in scope.
  Carries the H4 answer with **no host replace**.
- **PR C** (marker discriminators + `apply_target=inngest-host` delivery) — **HELD**. Not to be
  implemented, pushed, or merged in this run. The operator will decide after reading PR B's
  actual probe output (Phase B4.2).

Rationale: PR C's delivery path force-replaces the sole production Inngest scheduler days before
the cutover it instruments. PR B answers the double-scheduler question without that risk, so the
replace decision is better made with the probe reading in hand than ahead of it.

Live race noted: PR #6348 is draft and MERGEABLE. If it merges before PR C, PR C would be
stranded merged-but-undelivered. This does not affect A or B.
