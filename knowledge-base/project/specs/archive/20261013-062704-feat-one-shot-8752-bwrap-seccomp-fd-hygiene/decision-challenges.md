# Decision Challenges — feat-one-shot-8752-bwrap-seccomp-fd-hygiene

Headless-run persistence channel (ADR-084): taste/user-challenge findings that
an operator-attached session would surface at the apply gate. `ship` Phase 6
renders these into the PR body / files `action-required` issues.

## 2026-10-06 — planning phase

1. **`requires_cpo_signoff: true` set without interactive CPO confirmation.**
   Threshold resolved to `single-user incident` (cross-tenant secret/fd leak is
   a single-tenant breach). The template marks the threshold decision as
   challengeable — the operator can downgrade to `aggregate pattern` and drop
   the sign-off requirement; the work phase must still surface CPO sign-off
   before implementation per Phase 2.6 lifecycle staging.

2. **Plan-review named panel (DHH/Kieran/Simplicity + domain leaders) could not
   be spawned in this harness** — the planning subagent environment exposes no
   Task/subagent tool, so all research agents, domain-leader assessments, the
   spec-flow pass, the GDPR gate, and the scoped advisor consult were executed
   inline by the orchestrator and are recorded as such in the plan (Domain
   Review `Status: reviewed (inline)`). A downstream review phase with real
   agent spawning should treat the domain fan-out as not yet independently
   reviewed (`Reviewed-Coverage: sequential-fallback` disclosure applies).

3. **Shim placement decision (taste-adjacent):** `/usr/local/bin/bwrap` baked
   via Dockerfile (zero env surgery, also covers canary replay) was chosen over
   a dedicated shim dir prepended to PATH inside `buildAgentEnv` (explicit but
   narrower — misses the canary replay and any non-agent-env bwrap caller).
   The boot self-check (`op=sandbox-hardening-selfprobe`) is the detection net
   for PATH-order drift; challengeable if an operator prefers the explicit-env
   form.

4. **`setns(2)` intentionally not denied** (recorded residual, Risk R7): out of
   issue scope and requires an fd to a foreign userns that the sandbox cannot
   obtain — flagged here so the choice is visible rather than silent.
