# Decision Challenges — feat-one-shot-6500-6466-inngest-cutover-blockers

Recorded at plan time, headless arm (no operator pause). `ship` renders these
into the PR body and files them as an `action-required` issue.

Three items where plan-time evidence contradicts the operator's stated
direction. The operator's direction is the default — these are surfaced for a
decision, not silently applied beyond what the plan already encodes.

---

## UC-1 — The NIC-wait belongs to #6441, not #6466

**Operator's stated direction:** "#6466 (P1, labeled GA blocker) — NIC-wait
before `cloudflared service install`. Ship the ADR-114:161-163 gate."

**What the evidence shows:** #6466's body describes host-addressability
(fan-out `/hooks/deploy-status`, per-host infra-config targeting, host-scoped
SSH, a web-2 promotion runbook). It contains no NIC-wait item. ADR-114 §I1
states the gate verbatim and closes with: *"It is candidate (b) under I2 below,
tracked in #6441."* #6441 is OPEN and titled for exactly this residual.

**Why it matters:** filing against #6466 would close an issue whose real scope
is untouched, and leave #6441 — the issue the ADR points at — open with its
work silently done elsewhere.

**What the plan does:** ships the work (it is real and unshipped), attributes it
to #6441, and comments on #6466 to record the split. #6466 stays open.

**Decision needed:** confirm the re-attribution, or state why #6466 should carry it.

---

## UC-2 — Provisioning the heartbeat URL now would breach the cutover gate

**Operator's stated direction:** "Provision the heartbeat URL for the dedicated
host so `inngest-heartbeat` stops emitting `url_present=no` every 60s
(~1,414 rows/24h of wasted quota)."

**What the evidence shows:** the `url_present=no` line is the deliberate
**dark-arm**, rendered only when the host is on the dark Doppler project.
`INNGEST_HEARTBEAT_URL` is provisioned by **`op=arm` (G4)** in
`cutover-inngest.yml`; `op=rollback` removes it again. Per #6552 the reason is
explicit: so a dark host never becomes *"a SECOND pusher on the shared Better
Stack heartbeat monitor."*

**Why it matters:** provisioning it now bypasses the cutover FSM gate, creates
the exact dual-pusher state #6552 exists to prevent, and contradicts the same
brief's own constraint that nothing lands before `op=arm`.

**What the plan does:** keeps the goal (cut the quota waste), rejects the
mechanism. PR-A quiets the dark arm to once-per-boot + on-transition. No
heartbeat URL value is written by this work.

**Decision needed:** confirm the re-scope. If the URL genuinely should be
provisioned pre-arm, that is an ADR-100 amendment, not a plan-level change.

---

## UC-3 — The pattern being mirrored has never run in production

**Operator's stated direction:** "The web path already has the zot-aware `ZIREF`
equivalent at `cloud-init.yml:698,704` — mirror that pattern onto the inngest
host path."

**What the evidence shows:** that block is gated by `web_colocate_inngest`,
whose `default = false`. The reference implementation lives in a path that has
never executed. Separately, the inngest host has **zero** Sentry references and
appears **nowhere** in the zot registry's client configuration — so "mirror the
pattern" is closer to "port two subsystems" than to a copy.

**Why it matters:** treating the pattern as battle-tested would skip the tests
and the measurement it actually needs, on the one host with no rollback.

**What the plan does:** adopts the shape, treats it as new code with its own
tests, and gates PR-A behind a Phase A0 measurement of whether the inngest host
can reach and authenticate to zot at all.

**Decision needed:** none if A0 passes. If A0 shows the host is not an
authorized zot client, PR-A grows a registry-enrollment half — that expansion
should be an explicit call, not absorbed.
