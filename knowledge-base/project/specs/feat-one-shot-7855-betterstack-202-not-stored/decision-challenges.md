# Decision Challenges — #7855

Recorded in headless mode per `plan` Step 4.5 / plan-review. `ship` renders these into the PR body
and files an `action-required` issue. **The operator's stated direction is the default**; each entry
below is a challenge to it, not a change already made unilaterally — except where the plan had no
choice because an existing ADR forbids the stated mechanism.

## 1. "Widen the capture's polling window" — the window was never the defect

**Operator's stated direction (issue #7855, remediation 1):** establish the real ingest→query
latency and make the capture's polling window a measured value rather than an assumption.

**What measurement showed:** the poll is already bounded by `deadline=$(( SECONDS + 16 * 60 ))` — a
16-minute wall clock, which is already the shape the learning corpus prescribes — against ADR-172's
measured 17 s POST→queryable latency. That is ~56x headroom. The table has also been absent for more
than 18 hours since the source was created, which no polling window reaches.

**What the plan does instead:** treats the latency figure as genuinely worth establishing (ADR-172
measured it against a different source, region and platform) but ships **no constant change**, and
sequences the measurement as a follow-through because it cannot be taken while the warehouse stores
nothing. The half of the remediation that was actionable — "recorded reasoning rather than an
assumption" — is delivered; the half framed as "widen" is declined.

**Reversible if the operator disagrees:** the follow-through records a measured figure in its tracker
issue, and changing the constant is then a separate human-authored PR.

## 2. "Strengthen `betterstack-ingest-probe.sh` so INGEST_ACCEPTING means stored and queryable"

**Operator's stated direction (issue #7855, remediation 3):** make that probe's green verdict mean
stored-and-queryable rather than merely accepted, since an empty batch cannot demonstrate storage.

**Why the plan does not do it in that script:** ADR-192 decides *"The probe writes nothing"*, and the
reason is load-bearing rather than tidy — the absence alarm's positive control is an unfiltered "is
there any row" read, so a probe that wrote its own marker would satisfy that control forever and
convert an outage into a permanent blind spot. The script header restates the prohibition verbatim:
*"Do not add a payload here."*

**What the plan does instead:** splits the remediation. The probe keeps its non-writing design, but
its 2xx token is **renamed** so it can no longer be read as storage (the current name appears
verbatim inside #7811, an issue titled "Better Stack is accepting no writes"), and a **separate**
round-trip follow-through establishes storage by writing a marker and reading it back. The plan also
narrows ADR-192's blanket rule to the one that generalises: a probe may write to a source only if its
marker cannot satisfy that source's positive control.

**What the operator should know:** this is the one place the plan declines the stated mechanism
outright, because an existing accepted decision forbids it. The property the operator asked for is
still delivered — just not in that file.

## 3. Remediation 4 was an explicit invitation to decide, and the decision is "no"

**Operator's stated direction:** decide (and implement, or record the reasoning) whether the emitter
should verify a row is retrievable at least once per boot.

**Decision: no on-host readback**, recorded in the ADR-198 amendment. The load-bearing fact is that
the ClickHouse query connection is **team-scoped** — it reads every source in team 520508 — so baking
it would put a whole-warehouse read credential on the git-data host and fail ADR-198's own
capability-ceiling leg. `runcmd` is also once-per-instance with reboot barred by ADR-115, and any
emitter edit is ForceNew.

A cheaper alternative is recorded rather than omitted: the emitter already mirrors its POST outcome
to Sentry as `stage:betterstack_ingest`, so correlating that against a CI readback is an H5 decider
at zero credential cost and with no write.

## 4. Scope: this PR does not fix #7811, and one earlier-drafted fix was withdrawn

The warehouse has stored no row from any producer since `2026-09-03 12:18:10Z`; the git-data source
was created ~9 hours after that. An earlier draft corrected the ingest probe's stale `eu-fsn-3`
default. That was **withdrawn**: `.github/workflows/scheduled-zot-restart-loop.yml` invokes the probe
bare, and that invocation is the pager that files and re-probes #7811 — moving its endpoint
mid-incident would make #7811's own 202 evidence non-comparable across the change. The discrepancy is
reported to #7811 instead, and AC13 asserts zero ingest-URL literals change.
