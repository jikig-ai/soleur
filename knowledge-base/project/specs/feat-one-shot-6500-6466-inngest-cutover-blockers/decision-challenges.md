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

---

## UC-4 — The NIC-wait as briefed would have caused the outage it prevents

*Raised at deepen time, not plan time.*

**Operator's stated direction:** "on a fresh web host, wait for the private NIC
(10.0.1.10) to converge BEFORE `cloudflared service install` runs."

**What the evidence shows:** `cloud-init.yml` states `runcmd is ONE /bin/sh`. A
fail-closed wait (`|| exit 1`) before the cloudflared install terminates the
**entire remaining runcmd** — cloudflared, the webhook, the readiness gate, every
monitor, the egress firewall — and `runcmd` is once-per-instance, so a reboot
does not re-run it.

Today a NIC-down web-1 boots with a **working connector**; only the private-net
`registry.` route is broken. The briefed design would have replaced that
partial, in-band-fixable degradation with total permanent loss of `deploy.` and
`ssh.` on the sole web host.

**Why it matters:** the brief's stated goal ("a fresh web-1 that starts
cloudflared pre-convergence is unrecoverable in-band") is correct. The prescribed
*mechanism* would have produced that exact outcome more reliably than the race it
guards against.

**What the plan does:** keeps the goal, changes the mechanism to **defer, not
abort** — a systemd precondition so a late NIC delays registration while the rest
of the boot completes. Adds a regression AC forbidding `exit 1` in `runcmd`.

**Decision needed:** confirm the deferral design. The invariant (ADR-114 I1) is
unchanged; only the enforcement point moves.

---

## UC-5 — Adding the Vector tags as briefed is a no-op for three of four

*Raised at deepen time.*

**Operator's stated direction:** "Add `inngest-redis.service`,
`inngest-nftables.service`, and `inngest-boot-phone-home` to the Vector
allowlist — they emit at PRIORITY 5-6 and match no source."

**What the evidence shows:** Source 4 matches `SYSLOG_IDENTIFIER` by **exact
value**, and none of the three currently produce the assumed identifier:

- `inngest-redis.service` sets no `SyslogIdentifier`; its `ExecStart=/usr/bin/doppler …` means journald tags it **`doppler`**.
- The nftables unit sets no `SyslogIdentifier`; it is tagged **`inngest-nftables.sh`** (with the extension).
- `inngest-boot-phone-home.sh` **never calls `logger`** — it is a pure `curl` POST and emits **zero** journald lines under any tag.

**Why it matters:** the diagnosis (their zero-row state is uninformative) is
exactly right. But adding the tags alone changes nothing, and the resulting green
AC would have certified a fix that does not exist — the same false-confidence
shape #6617 is about.

**What the plan does:** sets `SyslogIdentifier=` on the two units so the tags can
match, and **drops `inngest-boot-phone-home`** from the allowlist (it already
ships to Better Stack directly, so a journald channel buys nothing).

**Decision needed:** confirm dropping the phone-home tag, or say whether a
`logger -t` mirror is wanted alongside its existing POST.
