---
category: integration-issues
module: observability
problem_type: integration_issue
symptom: "A log query returns HTTP 200 with fewer rows than the window should hold — or zero — and the short answer is read as a quiet system"
issues: [6288, 5697]
date: 2026-08-26
---

# A short answer is the bug, on both of our log surfaces

## Problem

Two vendors, two integrations, same defect, discovered fourteen months apart in
calendar time and about six weeks apart in ours:

- **Better Stack.** `betterstack-query.sh --since 24h` answers with roughly forty minutes
  of rows. HTTP 200, no warning, no error. The `remote()` hot window is shorter than the
  span asked for, and the difference is delivered as data rather than as a fault. This kept
  #6288 open from 2026-07-10 while the operator reasoned about a system that looked quiet.
- **Supabase.** The analytics endpoint truncates wide windows non-monotonically — a wider
  window can return *fewer* rows — again HTTP 200, again with a null error field. And a
  source that has never emitted anything returns a clean zero indistinguishable from a
  source that was simply idle.

In both cases the caller asked a question about a time window, got a syntactically perfect
answer about a *different* time window, and had no way to tell.

## The measurement

The Supabase side is measured in
`knowledge-base/project/specs/feat-one-shot-supabase-analytics-logs-endpoint-migration/phase-0-endpoint-evidence.md`
— finding C (the non-monotonic cap), finding E (`edge_logs` uninstrumented across a full
30-day live period), finding G (mandatory timestamp bounds), and §The documented 24-hour cap
is NOT enforced. Cite that file; it is the single source for the figures.

The last of those is the one that generalises hardest. The vendor **documents** a 24-hour
range limit and states that a validation error will be thrown beyond it. It is not enforced
at any width. So the client cannot get coverage from the vendor's contract even when the
vendor has written one down — a documented guard that silently does not fire looks exactly
like a guard that works.

## Solution

Do not try to detect a short answer by looking at the answer. Two things that seemed
obvious and are both wrong:

- **"Compare a wide window against a narrow one and trust the larger."** Defeated by the
  non-monotone curve — two samples can land anywhere on it, in either order. Useful as a
  probe, useless as the assertion.
- **"The window predates retention, so both queries return zero and the check catches it."**
  Both return zero, `0 >= 0` holds, and the check does not fire at all. This is the case
  that motivated the whole exercise, and the monotonicity probe is precisely blind to it.

What works is to make the tool assert coverage itself and refuse to emit a count without
it. Both helpers now do:

- `scripts/betterstack-query.sh` + `scripts/lib/betterstack-absence.sh` (ADR-192 — an empty
  read is three states, not two).
- `scripts/supabase-logs-query.sh` (runbook
  `knowledge-base/engineering/operations/runbooks/supabase-log-query.md`), which emits count,
  covered window, resolved project and per-source instrumentation status as one block, and
  binds the verdict to the exit code — `0` COVERED, `1` transient, `2` auth/config, `3`
  INCONCLUSIVE.

The exit-code binding matters more than it looks. A verdict printed only as text is invisible
to `if tool; then …`, to `set -e`, and to any agent reading `$?`; an INCONCLUSIVE that exits 0
is a false all-clear arriving through the one channel nothing else guards.

## Key insight

**A short answer is the bug, not the finding.** When a log surface returns less than you
asked for, the interesting fact is never the row count — it is that the query and the
question were about different windows.

That splits into two assertions that must travel with every count, and they are genuinely
independent:

1. **Coverage** — was the requested window actually queried?
2. **Instrumentation** — does this source emit at all?

A fully-covered zero from a source that never emits is not evidence of anything, and coverage
alone will happily call it clean. That exact pair is what a 2026-06-29 breach investigation had
to reason its way through by hand to reach `INCONCLUSIVE`; the reasoning was right, and it
should not have had to be done by hand.

Generalised above both vendors in **ADR-197** — *a zero from a log surface is not evidence of
absence without a coverage and instrumentation assertion.* The reason to state it at that
altitude rather than inside either integration is that we have now paid for this lesson twice,
and a third surface would otherwise pay for it a third time.

## Session Errors

1. **A vendor's documented range guard was assumed enforced.** The endpoint's own OpenAPI
   description promises a validation error past 24 hours; it never fires. Recovery: measured it
   directly at several widths. **Prevention:** never treat vendor documentation as evidence
   that a limit is enforced — probe it, and put the coverage assertion client-side.

2. **A documented default was assumed honoured.** Both endpoints document that omitting the
   timestamp bounds queries the last minute of logs; the replacement errors instead, and the
   error reads as a dialect fault. Recovery: reproduced it minutes apart to separate it from
   the transient variant. **Prevention:** the helper always sends both bounds, and a fixture
   pins the behaviour so a refactor that drops one is caught rather than misread.

3. **A monotonicity probe was nearly described as closing the truncation class.** It cannot
   fire when the whole window predates retention, which is the motivating case. Recovery:
   documented the blind spot in the same place as the probe. **Prevention:** state a
   detector's false-pass modes next to the detector, never only in the plan that commissioned
   it.

4. **A retention improvement nearly reopened a settled GDPR determination.** A longer retained
   span looked like it recovered an uncovered window; per-source measurement showed the source
   in question emits nothing, so it recovered nothing. Recovery: annotated the three records
   append-only rather than editing them. **Prevention:** before treating recovered retention as
   new evidence, check whether the source was ever instrumented.

## Related

- ADR-197 — a zero from a log surface is not evidence of absence.
- ADR-192 — an empty warehouse read is three states, not one (the Better Stack instance).
- `knowledge-base/engineering/operations/runbooks/supabase-log-query.md`
- `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md`
- `knowledge-base/engineering/operations/runbooks/breach-access-log-investigation.md`
- #6288 (the Better Stack hot window), #5697 (Supabase retention / durable sink — still open;
  revocable vendor-side retrievability satisfies neither limb of it).
