# Decision Challenges — feat-one-shot-6178 Inngest cutover execute

Accepted risks and challenged decisions surfaced during multi-agent review of PR #6218.
Each entry is an operator-facing residual that **ship Phase 6 must surface as action-required**
(not silently accept).

---

## DC-1 — web-2 quiesce/capture residual is NOT auto-verified (DI-C3, data-integrity P1)

**Status:** ACCEPTED RISK (operator-facing, action-required at ship). Default direction
UNCHANGED — authoring-only PR; the real per-host fan-out infra stays DEFERRED (tracked #6227).

**The residual.** `op=execute` reaches inngest on the web hosts only through a load-balanced
web-host webhook (`/hooks/inngest-inventory`, `/hooks/inngest-rearm-reminders`), which resolves
to `127.0.0.1:8288` on **whichever host the LB routed to**. There is no host-targeting mechanism
today, so:
- **2.1 capture** captures only the LB-reachable host's local Redis.
- **2.2 quiesce hard gate** positively confirms only the LB-reachable host.
- The **weight-0 warm-standby web-2 (10.0.1.11)** — which self-arms oneshot reminders into its
  **own** Redis independent of LB weight — is **neither captured nor quiesce-verified** by CI.
- **`op=verify` cannot backstop this:** the doublefire-probe reads only the dedicated host's
  (`10.0.1.40`) run history, so a surviving web-2 scheduler's PRE-repoint double-fires (fired via
  web-2's own loopback backend against prod Postgres) never appear and read clean.

**The risk (state it plainly).** If web-2 is not manually quiesced before the flip:
1. A reminder web-2 self-armed into its **local Redis is silently dropped** at cutover (never
   captured → never re-armed → the reminder simply never fires). This is silent data loss.
2. A surviving web-2 scheduler **double-fires** every cron tick against prod Postgres, which
   `op=verify` cannot detect.

**The mitigation (in this PR).**
- The `op=execute` gate + SEAM and the runbook were made **honest**: the gate scopes its claim to
  the LB-reachable host, prints NO "zero inngest across all hosts" notice, and the SEAM/runbook add
  a **MANDATORY (non-skippable)** operator step to quiesce web-2 via the plan's **web-2
  freeze/recreate lifecycle** (§Downtime): take web-2 out of the warm-standby rotation and recreate
  it onto the post-cutover config so no surviving web-2 scheduler self-arms into its local Redis.
  No `ssh`/host-shell step (AC-NOSSH).
- `op=verify` carries a loud caveat that it is NOT a web-2 double-fire detector; the operator's
  web-2 quiesce is the control.
- The real per-host web→web fan-out infra (firewall rule for web→web:8288 + host-targeting
  inventory/capture hook + parameterized scripts) is **deferred and tracked in #6227**
  (deferred-scope-out, cross-cutting-refactor — CONCUR from
  `soleur:engineering:review:code-simplicity-reviewer`, conditioned on the operator web-2 quiesce
  being a mandatory runbook/SEAM gate, which this PR implements).

**Ship Phase 6 action-required.** Surface to the operator, before the cutover window, that
**web-2 quiesce is a manual, mandatory pre-flip step that CI does not verify** — the cutover is
data-safe only if the operator freezes/recreates web-2 per the runbook step 1a. Re-evaluate #6227
(and drop this manual step) once the web→web:8288 firewall rule + host-targeting inventory hook
land.
