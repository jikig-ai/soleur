# ADR-166 — A CI-emitted operator-facing message may only name a cause the job measured

- **Status:** accepted
- **Date:** 2026-08-03
- **Extends:**
  [ADR-126 — cron liveness must assert the consumed artifact](ADR-126-cron-liveness-must-assert-the-consumed-artifact.md)
  (a check must assert the thing it claims about, not a proxy for it — this generalizes that
  from liveness to *diagnosis*),
  [ADR-147 — boot-stage diagnostics live in baked host scripts](ADR-147-boot-stage-diagnostics-live-in-baked-host-scripts.md)
  (a diagnosis must be produced where the evidence exists),
  [ADR-154 — repair the credential channel, not the host](ADR-154-repair-the-credential-channel-not-the-host.md)
  (the prior decision on *this* failure shape: a credential misdiagnosis routed an operator
  to the wrong repair),
  [ADR-164 — project-scoped service account and declared coverage floor](ADR-164-project-scoped-service-account-and-declared-coverage-floor.md)
  (a scan must declare what it did and did not cover)
- **Related:**
  [ADR-096](ADR-096-migrate-container-registry-ghcr-to-self-hosted-zot.md) (the zot pull
  path this fires on),
  [ADR-115](ADR-115-dedicated-host-private-nic-boot-convergence.md) and
  [ADR-082](ADR-082-fresh-web2-boot-observability.md) (the private-NIC advisory whose undated
  reboot claim supplied two of this incident's refuted hypotheses)
- **Supersedes:** nothing
- **Issue:** #7242
- **Enforced by:** `scripts/lint-diagnosis-claims.sh` + `scripts/lint-diagnosis-claims.highwater`,
  registered in `scripts/test-all.sh` (the `scripts` shard feeds the aggregate `test` job,
  which is in the CI Required ruleset — so this is **blocking**, not advisory)

## Context

On 2026-08-03 every `Web Platform Release` from 17:11 UTC failed at the zot-mirror
bridge. Production stayed pinned three releases behind for four hours.

The failure message told the operator the cause was a stale
`REGISTRY_PUSH_ACCESS_TOKEN_*` and to run the drift check. A step in the **same job**, six
minutes earlier, had already printed *"Registry-push Access service token verified live."*
The message asserted a cause the job had, by then, disproved.

It was also wrong on the merits. The measured cause was `zot` crash-looping at ~4
restarts/minute: a `docker login` plus a three-tag `crane copy` takes tens of seconds, so it
straddles a restart, the tunnel's origin dial fails mid-push, and that surfaces as
`websocket: bad handshake` — which the message read as an edge refusal. The Cloudflare
Access policy was intact, the service token expires 2027-07-29, and the tunnel connector
had never dropped (there is no `cloudflared` on the registry host at all). Both hypotheses
the message steered toward were refuted; so was the "the host rebooted at 17:13" premise
that a sibling advisory had supplied, on a host with 18.2 days of uptime.

**This was the third iteration of one defect on one code path.** The workflow's own
comments record the previous two. From `reusable-release.yml`:

> *"It predicted a missing tunnel-connector route as the likely cause. REFUTED … Reading
> that prediction as a finding is what sent the 2026-07-29 investigation to the wrong
> network layer and consumed its entire diagnostic budget."*

Iterations one (2026-07-15) and two (2026-07-29) were each fixed by rewriting the offending
sentence. Both re-drifted. The 2026-07-29 fix even wrote a *new* standing claim — *"The
MEASURED cause class is a CF Access service-token rotation that never propagated"* — which
was true of that incident and false as a general fact, and which is what iteration three
inherited.

A cause measured **once** is not a cause measured **always**. That is the whole finding.

## Decision

**No operator-facing message emitted by CI may name a cause the job did not measure.**

Concretely:

1. **Messages branch on a measured verdict, or explicitly declare themselves unmeasured.**
   A failure path that wants to name a cause must first compute one. Where nothing was
   computed, the message says so and ranks nothing.

2. **A verdict must not collapse "could not check" into "bad."** The DEAD /
   UNVERIFIABLE / UNMEASURED distinction is load-bearing, because the three call for
   different — sometimes opposite — operator actions. `check-cloudflare-token-drift.sh`
   exits 1 for `dead > 0 **OR** unverifiable > 0`, so deriving a verdict from the exit code
   alone prints *"the token is STALE, rotate it"* about a token nothing graded. Verdicts are
   derived from measured counts, never from an exit code that aggregates distinct states.

3. **Where a cheap probe discriminates competing hypotheses, the failing step runs it and
   reports the value.** The deciding datum for "was the origin flapping while this push
   ran" existed only on an ephemeral runner and was destroyed when the job ended. Telling
   the operator to go read a dashboard is not a substitute — and on this project it is a
   standing rule violation (`hr-no-dashboard-eyeball-pull-data-yourself`). Capture it in-job,
   fail-soft: a failed query prints "could not query", never a claim.

4. **Enforcement is the lint, not the prose.** An ADR whose only mitigation is "the ADR
   states the invariant" is the same unenforceable-prose failure it is trying to describe.
   `scripts/lint-diagnosis-claims.sh` scans `.github/workflows/` **and** `.github/actions/`
   for causal-claim phrases lacking a measured basis, ratcheted by a `.highwater` baseline,
   and it blocks.

### Scope

Widened at review from "this code path" to **any diagnostic claim in any CI-emitted
operator-facing message**. The narrow version would have been iteration four's setup: the
defect is not specific to the zot bridge, and every other `::error::` in the repo was free
to commit it.

## Consequences

- A message that cannot name a cause is now expected to say so. That reads as *less*
  helpful, and it is *more* honest — an unranked list beats a confident wrong answer, which
  is what consumed two prior diagnostic budgets.
- `.github/actions/**` gains its first lint of any kind. It was unlinted by every other
  tool here, which is why two offending lines in `cf-tunnel-registry-bridge/action.yml`
  survived two rounds of fixes aimed at exactly this defect.
- The four-valued verdict has to be threaded from producer to consumer explicitly. That
  plumbing is pinned structurally, because a behavioural test that injects the verdict
  cannot see the mapping that feeds it.
- The `unmeasured` arm is a **supported steady state**, not a fault. Two of the three
  callers of `cf-tunnel-registry-bridge` run no token preflight, so they sit on it
  permanently; it therefore has to be actionable standalone rather than a degraded
  placeholder.

## What this does NOT claim

- It does not say a message may never be *wrong*. A measurement can be misleading. It says
  a message may not assert a cause **nothing measured**.
- It does not fix the crash-loop that caused this incident, and it does not diagnose it.
  That is tracked separately, and this ADR deliberately records the proximate crash reason
  as UNKNOWN rather than guessing — which is the invariant applied to itself.
- The lint is a phrase-list guard, and a phrase list goes stale. It is a floor, not a
  proof: its suite asserts both arms against fixtures, including the verbatim historical
  line, so the guard cannot silently stop catching the thing it was built for.
