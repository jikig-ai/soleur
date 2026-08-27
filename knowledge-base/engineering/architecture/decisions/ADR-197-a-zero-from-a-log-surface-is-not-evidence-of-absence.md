---
title: "ADR-197 — a zero from a log surface is not evidence of absence without a coverage and instrumentation assertion"
status: accepted
date: 2026-08-26
tags: [observability, evidence, log-surfaces, vendor-contracts, gdpr]
related_adrs: [ADR-192, ADR-193, ADR-096]
related_runbooks:
  - knowledge-base/engineering/operations/runbooks/supabase-log-query.md
  - knowledge-base/engineering/operations/runbooks/betterstack-log-query.md
  - knowledge-base/engineering/operations/runbooks/breach-access-log-investigation.md
---

# ADR-197 — a zero from a log surface is not evidence of absence

## Status

`accepted`. The invariant is true the moment this ADR merges. **One** implementation enforces
the full contract — `scripts/supabase-logs-query.sh`, under this change.

`scripts/lib/betterstack-absence.sh` (ADR-192) satisfies **D-2 only** — its verdict reaches
`$?`. It does **not** satisfy D-1: `bs_absence_classify` emits a bare token
(`TRANSPORT_FAIL` / `LIVE` / `INGEST_DARK`) with no row count, no requested-vs-covered window
and no per-source instrumentation status, so it is ADR-192's three-state classifier rather
than an atomic evidence block. An earlier revision of this line counted it as one of "the
first two enforcing implementations"; that was an assertion about a file nobody re-read, and
recording the gap is worth more than the tidier sentence — it is what a later change has to
close.

## The invariant

**A zero returned by any log surface is not evidence of absence unless it arrives with two
assertions: that the requested window was actually covered, and that the queried source
actually emits.**

Stated deliberately above the vendor. This ADR is not about Supabase, and it is not about
Better Stack. It is about the shape of the answer a log surface gives, which is the same shape
everywhere and has now been got wrong by two independent vendors in three independent ways.

## Context — why this is stated at that altitude

ADR-192 established, for one warehouse, that an empty read is three states and not two:
the read failed, the read answered and the source is dark, or the read answered and there is
genuinely nothing. That was written as a Better Stack decision. It is not one.

Three measured proofs, two vendors:

**1. The window silently shrinks (Better Stack).** The `remote()` hot window answers a wide
`--since` with a much shorter span and reports success. `--since 24h` returning roughly forty
minutes of rows is not an error and does not look like one — it kept #6288 open from
2026-07-10 while the operator reasoned about a quiet system that was in fact a truncated query.

**2. The window truncates non-monotonically (Supabase).** On the replacement analytics
endpoint, a *wider* window can return *fewer* rows, with HTTP 200 and a null error field
throughout. The empirical cap is undocumented, sits well beyond the documented one, and can
move. Measurements: `knowledge-base/project/specs/feat-one-shot-supabase-analytics-logs-endpoint-migration/phase-0-endpoint-evidence.md`
§Confirmed from the plan (finding C). Note what this defeats: comparing two window widths and
trusting the larger is a natural client-side check, and on a non-monotone curve it can be read
backwards.

**3. The vendor's own documented guard does not fire (Supabase) — and this is the sharpest of
the three.** The endpoint's OpenAPI description states that the timestamp range must be no
more than 24 hours and that a validation error *will be thrown* beyond it. It is not enforced:
ranges far past that limit return HTTP 200 with data and no validation error at any width. See
the evidence file, §The documented 24-hour cap is NOT enforced.

The same file records a second instance of the same disease: both endpoints document that
omitting the timestamp bounds queries the last minute of logs, and the replacement instead
fails — so the documented behaviour is wrong in one direction on one endpoint and wrong in the
other direction on the other (§NEW — finding G).

**4. The instrumentation dimension is separate from the coverage dimension.** A source can be
perfectly covered and still return zero because it has never emitted anything. `edge_logs`
produced zero rows across an entire 30-day live period on prd (evidence file, finding E), and
a 2026-06-29 breach investigation reached for exactly that source and had to reason its way to
`INCONCLUSIVE` by hand. Coverage alone would have said "fully covered, zero rows" — which is
the wrong answer for the right reason.

**Why proof 3 changes the claim.** With proofs 1 and 2 alone, this ADR would say only "two
vendors got their range handling wrong", which invites the reading that a third vendor with a
better-specified contract would be safe to trust. Proof 3 forecloses that. The failing artifact
there is not the implementation but the **published contract**: a vendor guard that is
documented, specific, and silently absent. A client that delegates its coverage assertion to a
vendor's stated behaviour is trusting a sentence, and a sentence has no failure mode that
reaches the caller. **The coverage assertion must therefore be computed client-side. It cannot
be delegated, and a vendor's documentation is not evidence that it was enforced.**

## Decision

**D-1. Count, coverage and instrumentation are one inseparable block.** Any tool that reports a
row count from a log surface reports, in the same block: the window requested, the window
actually covered, the resolved source identity, and each queried source's instrumentation
status. Not a count with a verdict printed nearby — the consumer is routinely an agent
transcribing a figure into a determination or an incident record, and a count that can be
lifted alone will be.

**D-2. The verdict binds to the exit code.** A verdict that exists only as printed text is
invisible to `if tool; then …`, to `set -e`, and to any caller reading `$?`. An inconclusive
result exiting 0 is a false all-clear entering through the one channel nothing else guards.

**D-3. The coverage assertion is client-side.** Derived from what the tool itself measured, not
from a documented vendor limit, a tier page, or a retention setting. Proof 3 is the reason.

**D-4. `INCONCLUSIVE` is a first-class verdict, not a softer zero.** It has its own exit status
and its own operator action. A partial pull is never rendered as a clean result, and the reason
(uncovered window, or uninstrumented source) travels attached to the verdict rather than as a
second token to scan for.

**D-5. This binds every log surface, present and future.** The two implementations that exist
are instances. A third surface is expected to satisfy D-1 through D-4 before any absence claim
is drawn from it — which is the whole point of stating this above the vendor rather than
inside either integration.

## Non-vacuity of the deprecated-endpoint guard after `advisors/*` migrates

Recorded here so a future reader does not have to re-litigate it.

`scripts/lint-supabase-deprecated-endpoints.sh` has two arms:

1. a **denylist arm** over deprecated API paths, and
2. a **host-pin arm** whose assembly is tracked non-doc files matching
   `/v1/projects/`, `SUPABASE_ACCESS_TOKEN` or `SUPABASE_PAT`, where **membership is the
   assertion** — each member either carries the bare literal `https://api.supabase.com` or sits
   on a short, dated, inline-justified allowlist.

When `advisors/*` eventually migrates, the denylist arm loses its last remaining call sites and
**goes vacuous**. That is expected and is not a defect. The guard's non-vacuity from that point
rests entirely on the **host-pin arm**, which is keyed on the presence of a PAT variable or a
project path — a population that persists regardless of which vendor paths are deprecated — plus
the committed high-water ratchet, which fails when the enumeration count falls. The quantifier
in that arm is deliberately inverted for the same reason: an assembly keyed on the pinned
literal cannot see a caller whose host has been redirected away from it, because such a caller
no longer contains the literal and is never enumerated.

**The guard is ADVISORY.** It runs in the `lint-bot-statuses` job, which is absent from
`scripts/required-checks.txt` and from the branch ruleset, so **a PR can merge with it red**.
No document in this change claims otherwise. Promotion to blocking is deliberately deferred
rather than forgotten, and is real work: it requires reproducing the gate in the bot-PR
composite action's preflight (because `required-checks.txt` carries an auto-fabrication guard
that would otherwise post a fabricated green for a content-scoped gate name), adding the job to
`required-checks.txt` and to the ruleset, and re-deriving the ADR-139 path-intersection test.
Landing a gate that *claims* to block while not blocking is the failure mode this paragraph
exists to prevent.

## Consequences

- Every log-surface helper carries a verdict path, which is more code than a thin query wrapper
  and is the cost of the invariant. Accepted.
- Some genuinely-empty windows will be reported `INCONCLUSIVE` rather than clean, when coverage
  cannot be established. This is the correct direction to be wrong in: an over-cautious
  inconclusive costs a re-query, a false clean costs a determination.
- ADR-192's three-state classifier and this ADR's verdict contract are the same invariant at two
  altitudes. ADR-192 is not superseded; it becomes the Better Stack instance of D-1 through D-4.
- Consumers that previously read a row count from stdout must now read the exit code as well.
  `knowledge-base/engineering/operations/runbooks/supabase-log-query.md` states this at its
  entry point. **The Better Stack side does NOT, and this ADR does not claim otherwise:**
  `betterstack-log-query.md:36` records that its `NIC_ALARM_VERDICT` is carried as an
  independent verdict, "deliberately NOT in the exit code". So D-4 (bind the verdict to `$?`)
  is implemented on the Supabase surface and is an ASPIRATION on the Better Stack one. Stating
  that asymmetry is the point: an ADR that claimed both surfaces already complied would be the
  same over-claim it exists to forbid, and the gap is what a later change has to close.
- The GDPR determination that motivated the Supabase half is **reinforced, not reopened** — its
  `INCONCLUSIVE` access-log treatment turns out to have been correct for a stronger reason than
  the one recorded at the time. See the 2026-08-26 addenda on
  `knowledge-base/legal/audits/2026-06-29-inngest-prd-rls-reachability-gdpr-determination.md`
  and its two sibling records.

## Alternatives considered

| Alternative | Why not |
|---|---|
| Scope the decision to Supabase (an endpoint-migration ADR) | It would leave the Better Stack instance as an unrelated coincidence and guarantee a third surface relearns the class from scratch. The altitude is the deliverable. |
| Rely on the vendor's documented range validation | Measured not enforced (proof 3). Delegating the assertion to a sentence is the failure mode, not a mitigation of it. |
| Detect truncation by comparing two window widths and trusting the larger | Defeated by proof 2: the measured curve is non-monotone in both directions, so two samples can land anywhere on it. Useful as a probe, never as the coverage assertion. |
| Report the row count and let the caller decide about coverage | This is the status quo ante and is exactly what produced the 2026-06-29 hand-reasoned `INCONCLUSIVE` and the 8-day life of #6288 (created 2026-07-09, closed 2026-07-17 — measured, not estimated; an earlier revision of this line said 'two-month' and was wrong). The consumer is often an agent, and the separable count is the thing that travels. |
| Make the deprecated-endpoint guard merge-blocking in this change | Requires four other pieces of work (see above), one of which — the auto-fabrication guard on `required-checks.txt` — would otherwise cause a fabricated green. Filed rather than faked. |

## Related

- ADR-192 — an empty warehouse read is three states, not one (the Better Stack instance).
- ADR-193 — a suite's anti-vacuity floor reports directly (the guard-vacuity discipline the
  host-pin arm's ratchet follows).
- ADR-096 — the Better Stack log-content alarm pattern (the consumers this invariant binds).
- `knowledge-base/project/specs/feat-one-shot-supabase-analytics-logs-endpoint-migration/phase-0-endpoint-evidence.md`
  — every measurement cited above; cite it rather than restating its figures.
