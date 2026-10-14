# Decision Challenges — feat-one-shot-6617-inngest-liveness-marker-registry-probe

Persisted headless per ADR-084 / plan-review classifier routing. `ship` Phase 6 renders these
into the PR body and files an `action-required` issue. Mechanical findings were auto-applied to
the plan (see its **Review Reconciliation** table) and are not repeated here.

---

## UC-1 — Split into three PRs (User-Challenge: changes the operator's stated delivery shape)

**Raised by:** dhh-rails-reviewer (S1), code-simplicity-reviewer (#3), cpo (C6)

**The operator asked for** two deliverables in one piece of work, priority 2 over priority 1 if
sequencing were needed.

**The panel's position:** the work ships through three unrelated delivery channels, and the
single-PR shape forced two contradictory close semantics into one body (`Ref #6617` **and**
`Closes #6295`). A credential-leak fix (#6295, nine lines of `sed`) would have waited behind a
tag push, a digest resolution, an image content verification, and an ADR amendment.

**Applied:** split into PR A (scrub fix) → PR B (probe ops) → PR C (marker + delivery).

**Why this was treated as compatible with the operator's direction rather than a reversal:**
the operator explicitly sanctioned sequencing. The marginal-cost argument for doing the marker
fields now survives the split intact — it argues for doing them *now*, not for shipping them in
the same commit as a regex fix.

**Operator may override** by requesting a single PR; the plan's phases map 1:1 onto it.

---

## UC-2 — H4's answer moved off the replace path (User-Challenge: reorders the stated priorities)

**Raised by:** cto (P1/Q4)

**The operator framed** Priority 2 (the marker) as primary and Priority 1 (the registry-probe
op) as secondary, with the marker as the instrument that settles liveness.

**The panel's position:** `inngest-doublefire-probe.sh` already exists, is already installed on
the web hosts, already targets 10.0.1.40, and enumerates *actual cron runs*. It answers the
double-scheduler question with **no host replace at all** — and proves the harm itself rather
than a proxy for it. Coupling the diagnosis to a production replace of the sole scheduler was
the plan's largest unforced risk.

**Applied:** PR B now adds **two** standalone ops (`registry-probe` **and** `doublefire-probe`)
and carries the H4 answer. PR C still ships, because the marker makes the signal continuous and
the replace is independently owed — but it is now a *delivery* step, not a *diagnostic* one.

**Net effect on the operator's priority ordering:** Priority 1's surface grew by one op and now
lands first. The operator may prefer to keep `doublefire-probe` out of scope; the cost is that
H4 stays unanswered until the replace succeeds.

---

## T-1 — Threshold rationale, not the threshold itself (Taste)

**Raised by:** dhh-rails-reviewer (S6), contested by cpo

**DHH's position:** `requires_cpo_signoff: true` fired on the severity of the thing being
*observed*, not of the change. An observability change cannot cause a double-fire; it can only
reveal one. Gating every future probe and log field this way is how sign-offs become rubber
stamps.

**CPO's position (verified against the repo):** the tier is correct, but for a reason the plan
had not stated — the *mechanism* is systemic-shaped, and it lands at `single-user incident`
only because `Beta users: 0`. It becomes `aggregate pattern` once founders are recruited.

**Applied:** threshold kept; rationale rewritten to CPO's framing, with the expiry recorded.

**Unresolved and surfaced:** whether the threshold rubric should carve out read-only
instrumentation. That is a workflow question beyond this plan's scope.

---

## T-2 — Prose vs CI for the delivery invariant (Taste, partially applied)

**Raised by:** cto (P1/Q2), code-simplicity-reviewer (#5), architecture-strategist (P1-5)

**Position:** the plan identified that "nothing in CI ties the pin to the tree" and responded
with an ADR amendment. But the invariant is *already* documented three times (ADR-100 Amendment
6b, a learning file, a `cloud-init` comment) and #6539 happened anyway. A fourth prose copy is
not a mitigation.

**Applied:** the image-content check was upgraded from `grep -c` to a byte-`diff` and promoted
into `cloud-init-inngest-bootstrap.test.sh` as a permanent gate (C2.5). The ADR amendment is
kept for the *why*.

**Surfaced, not applied:** CTO recommended extending the same gate to `vector.toml` and the
redis/flip assets, which have identical exposure and no guard either — and doing it as a job in
`infra-validation.yml` covering the whole `COPY` set. That is the durable fix for the entire
#6539 class rather than this one field addition. Deliberately out of scope for a held-cutover
week; worth its own issue.

---

## T-3 — Root debt: the dedicated host has no in-place redelivery channel (Taste)

**Raised by:** architecture-strategist (P2-2)

**Position:** `ci-deploy.sh:2758-2891` implements in-place redelivery for the web host
(`docker pull` → `create` → `cp` → run, via the HMAC deploy webhook), and `cloud-init.yml:695`
documents it. The dedicated host was extracted from the web host **without carrying that
channel**, which is why every future observability change costs a replace of the sole
scheduler. An HMAC webhook violates neither of ADR-100's load-bearing constraints.

**Applied:** filed as C4.6, and recorded in the Alternatives table.

**Surfaced:** this is the root cause of the plan's central awkwardness. Fixing it would make
this class of change routine. Out of scope here.

---

## T-4 — Companion issue: cron send-path has no idempotency guard (Taste)

**Raised by:** cpo (roadmap follow-up)

**Position, verified:** `cron-email-ingress-probe.ts` → `notifyOfflineUser` →
`sendEmailNotification` → `sendEmailTriageEmailNotification` (`server/notifications.ts`
~275/~517/~565) issues a bare `resend.emails.send` with no idempotency key, no sent-marker row,
and no Inngest `idempotency`/`concurrency` config. The sibling `notifyInboxItem` path (`:709`,
ADR-035) *does* carry a `(workspace_id, dedup_key)` guard.

**Consequence:** a double-fire produces two identical statutory-deadline emails per user **per
tick, indefinitely**. This plan builds an instrument that *detects* double-fire; a dedupe guard
would make it *harmless* on the one path that reaches users.

**Not folded in** — it touches product notification code, not infra, and the dark window is the
constraint here. Cheap at 0 users, expensive at 10. Companion issue required.

---

## Operator Ruling — 2026-07-20

UC-1 and UC-2 were both put to the operator before implementation began.

**Ruling: ship PR A + PR B in this run. PR C is HELD.**

- **UC-1 (three-PR split): UPHELD.** The split stands.
- **UC-2 (priority reorder): UPHELD.** `doublefire-probe` stays in scope and PR B lands first,
  inverting the originally stated priority-2-first ordering. The operator accepted the panel's
  reasoning that coupling diagnosis to a production replace was the plan's largest unforced risk.
- **PR C: HELD, not cancelled.** Its force-replace of the sole production scheduler is deferred
  until the operator has read PR B's actual probe output (Phase B4.2). PR C must not be
  implemented, pushed, or merged in this run.

Standing risk carried forward: PR #6348 is draft and MERGEABLE. If it merges before PR C is
delivered, PR C would be stranded merged-but-undelivered. Unaffected by the A+B scope.

### Follow-on ruling — 2026-07-20: PR C is CANCELLED

The ruling above recorded **"PR C: HELD, not cancelled"**, conditioned on the operator first
reading PR B's actual probe output (Phase B4.2). **That condition has now been satisfied**, and on
reading the output the operator has ruled:

**PR C is CANCELLED.** The hold above is superseded. Phases C0–C6 are not to be implemented,
pushed, or merged — now or later. Their bodies are retained in `tasks.md` as the record of what was
designed, not as pending work.

**The condition that was satisfied.** `op=doublefire-probe` was dispatched on the post-merge host
state (run 29748606817, from `main` sha `898de92e4`, after #6748 merged) and returned **ZERO runs**
on the dedicated host. Combined with the registry probe (`function_count=0`, run 29729509511),
`backend_is_prod=false`, and the absent `INNGEST_CUTOVER_FLIP` start-block, the diagnostic question
PR C was built to answer is settled — on four independent measures, none of which required the host
replace. Phase C6.3's escalation branch fires on `backend_is_prod=yes` **OR** a non-empty doublefire
result; **neither limb is met.**

**Why cancel rather than continue to hold.** PR C's discriminators exist to distinguish states of a
**dark** host. After the cutover the dedicated host becomes the live scheduler and that question is
no longer asked. The instrument's useful life is therefore bounded by the pre-cutover window — and
it cannot be delivered inside that window at acceptable risk, because its delivery force-replaces
the sole production Inngest scheduler days before the cutover it was built to instrument. **An
instrument that cannot be delivered while it still matters is cancelled, not parked.**

**Standing risk dissolved.** The ruling above carried a standing risk that if #6348 merged before
PR C was delivered, PR C would be stranded merged-but-undelivered. **Cancelling PR C dissolves that
risk outright** — there is no longer an undelivered PR C to strand.

**What the operator is accepting.** After cancellation the dedicated Inngest host has no continuous
liveness discriminators; its observability posture is on-demand only, via the two standalone ops PR
B shipped. That is what makes #6780 (no in-place redelivery channel for the dedicated host) the
live root debt rather than a filed-and-forgotten follow-up.

**Carry-forwards** (already filed; referenced, not re-filed): #6780, #6781, #6608, #6348.

The tracking issue remains OPEN; its existing follow-through sweeper owns closure.
