---
title: "Gate moratorium and a meta-work filing budget"
status: proposed
date: 2026-07-20
issue: 6769
supersedes: null
---

# ADR-131: Gate moratorium and a meta-work filing budget

> **Status is `proposed`, deliberately.** This ADR decides nothing. It contains
> two policy proposals that are the operator's call, not an agent's, plus the
> argument *against* each. An agent that adopted these unilaterally would be
> making a governance decision about how the operator's own system behaves.
> Both proposals are recorded here so they have a return path — the
> operator-digest surfaces `status: proposed` ADRs in its "decisions awaiting
> your call" line.

## Context

Measured over the 7 days to 2026-07-20 (re-measured at session close on the
same data source; two independent methods agreed on the PR count):

| Metric | Prior 23d | Last 7d | Change |
|---|---|---|---|
| Issues created/day | 18.9 | 38.4 | 2.03x |
| Merged PRs/day | 15.5 | 18.9 | 1.2x |
| Filed per PR | 1.22 | 2.04 | 1.67x |
| Closed per PR | 0.75 | 0.95 | — |
| Net per PR | +0.46 | +1.09 | 2.4x |
| Queue growth/day | +7.2 | +20.6 | 2.9x |

1,024 open issues at measurement; 63% older than 30 days. Duplicate titles
account for only 3.6%, and closure ratios are uniform (~43–46%) across
`p3-low`, `type/chore` and `deferred-scope-out` — so this is throughput, not
triage bias, and not a duplicate-detection problem.

An earlier framing of this same data circulated "36 merged PRs / 7.4 filed per
PR". That PR denominator was wrong by ~3.7x. The corrected ratio is 2.04. The
**mechanism** of the diagnosis was confirmed by the correction; only the
magnitude changed. This ADR is written against the corrected numbers, and the
correction is recorded because the original figure is quoted elsewhere.

**The structural claim.** The dominant *source* of issues is the self-checking
apparatus itself. Every gate, linter, probe, cron and skill is software whose
job is finding defects and which has defects of its own. Filing is free;
closing is expensive. The consequence is uncomfortable: shipping *better* does
not reduce the inflow, and shipping *more* increases it. The apparatus's own
maintenance has become a large and growing share of the workload.

Two mitigations already shipped alongside this ADR (they are not in question
here): the net-issue-flow gate now blocks at `NET > 0`, and the cost-of-filing
auto-flip threshold moved from ≤30 lines/≤2 files to ≤100/≤4 with
instrumentation. Both act on the *rate*. Neither acts on the *number of
defect-producing components*, which is what the first proposal below addresses.

---

## Proposal 1 — Gate moratorium

**Statement.** For a defined period (suggested: 90 days), add no new CI gates,
linters, probes, or scheduled checks. Existing ones may be fixed, tightened,
merged, or deleted. A new gate requires an explicit operator exception.

### The argument for

- Each gate is a **permanent** issue generator. It runs forever, and its own
  false positives, environment drift, and unfailable-gate defects become issues
  in the same queue it is meant to protect. The marginal gate has an unbounded
  tail cost and a one-time benefit.
- This repo has repeatedly shipped gates that **could not fail** — the
  secret-scan structurally-unfailable-gates fix, plus two still-open instances
  ("infra-validation cannot fail on main"; "preflight Check 10 cannot verify
  run-triggered emitters"). A gate that cannot fail is worse than no gate: it
  consumes maintenance and confers false confidence. The class recurs, which is
  evidence that gate-authoring is not a reliably-executed skill here.
- The queue is at 1,024 with 63% older than 30 days. Anything that adds inflow
  during a backlog crisis is compounding rather than mitigating.
- A moratorium is cheap and fully reversible. Nothing is deleted; the option to
  add gates returns automatically at expiry.

### The argument against

- **The apparatus is load-bearing, and this repo is agent-operated.** Gates are
  a primary substitute for human review. A moratorium during a period of high
  agent throughput removes the mechanism that catches agent error, at exactly
  the moment throughput is highest. The failure it invites is silent and
  expensive: a defect reaching production costs more than a queue entry.
- **It optimizes a proxy.** The goal is a healthy system, not a small queue. A
  smaller queue achieved by detecting fewer defects is strictly worse and looks
  strictly better. This is the classic measurement-substitution failure.
- **Attribution is unproven.** The claim "gates are the dominant source" is
  inferred from the inflow mix (85% `domain/engineering`), not from a
  per-component attribution of which issues each gate actually generated. The
  right first move might be to *measure* per-gate issue attribution and delete
  the worst offenders, rather than freeze the whole class. A blanket
  moratorium treats a well-behaved new gate identically to a noisy old one.
- **The rate mitigations may be sufficient.** The `NET > 0` gate and the raised
  auto-flip threshold shipped in the same change and have not been observed for
  even one cycle. Adding a second, blunter intervention before the first is
  measured makes it impossible to attribute any improvement to either.

### Synthesis (not a decision)

The strongest version of the argument for is narrower than a blanket
moratorium: *no new gates until per-gate issue attribution exists*. That
converts the freeze from a fixed 90-day window into a condition with a clear
exit, keeps the ability to add a genuinely load-bearing gate under exception,
and directly answers the "attribution is unproven" objection. It also sequences
correctly behind the two rate mitigations, so their effect stays measurable.

**Options for the operator:** (a) 90-day blanket moratorium; (b) moratorium
until per-gate attribution exists; (c) no moratorium — let the `NET > 0` gate
and the raised threshold run one measurement cycle first; (d) no moratorium at
all.

---

## Proposal 2 — Meta-work filing budget

**Statement.** A tooling/meta issue may be filed only with a **named drain
window** — a specific period in which it will actually be worked. Without one,
accept the defect knowingly and do not file.

### The argument for

- An unfiled known defect and a filed-and-ignored one are equivalent in effect.
  The second is strictly worse in cost: it consumes triage attention on every
  sweep and creates false confidence that the problem is tracked.
- The `action-required` label is the worked example. 29 open, oldest 130 days,
  ~0% resolution rate on the oldest items. One item sat 57 days while the
  outage it reported grew from one cron to eight. Those issues were filed
  instead of fixed, and filing did not cause them to be fixed.
- Naming a drain window forces the real question — "when will this actually be
  done?" — at the moment of filing, when the answer is cheapest to obtain and
  the context is loaded.

### The argument against

- **It trades a visible backlog for an invisible one.** Known defects that are
  never written down cannot be searched, counted, or picked up by someone else
  later. The queue is at least an honest record of what is broken; a policy of
  not-filing makes the same debt real but unmeasurable.
- **Drain windows will be fabricated.** Under a rule that requires one, the
  path of least resistance is to write a plausible date nobody enforces. The
  policy then adds ceremony without changing behavior — and produces issues
  that look *more* committed than they are.
- **It biases against the honest reporter.** The agent or person who notices a
  defect while doing unrelated work is the one asked to either commit calendar
  time or stay silent. Silence is the cheaper option, so the rule
  systematically suppresses reports from exactly the incidental discoveries
  that are most valuable.

### Synthesis (not a decision)

A weaker form avoids most of the counter-argument: keep filing, but make
**age itself a signal** rather than requiring a commitment at filing time —
an SLA band, an auto-nag, or an explicit "accepted, not scheduled" state that
is honest about the fact that nobody is working it. That preserves the searchable
record while removing the false confidence, which is the actual harm identified.

**Options for the operator:** (a) drain-window-required as stated; (b) the
weaker age-as-signal form; (c) apply to `type/chore` + tooling only, not all
meta; (d) no change.

---

## Recorded dissents (from plan review, surfaced not applied)

Both argued against the operator's explicitly stated direction, so they were
recorded rather than acted on:

1. **"Cut this ADR entirely."** The reviewer argued a gate moratorium is
   premature given that the `NET > 0` gate had not been observed for one cycle,
   and that an unadopted ADR is itself meta-work of the kind Proposal 2
   discourages. Not applied: the operator scoped this deliverable explicitly as
   draft-and-decide-later, and the counter-argument is captured above rather
   than discarded.
2. **"Swap the filed-per-PR metric."** The reviewer argued filed-per-PR is
   gameable — it improves when PR count rises without any change in filing
   behavior. Resolved by *addition* rather than substitution: the soak criterion
   checks both filed-per-PR ≤ 0.95 **and** total open issue count at merge+14d
   ≤ count at merge. The second is not gameable by splitting PRs.

## Consequences if adopted

- **Proposal 1** would need a recorded expiry or exit condition and an
  exception path, or it silently becomes permanent.
- **Proposal 2** would need a home in `AGENTS.md` under Workflow Gates, and
  would interact with the `NET > 0` gate: a PR that cannot file is pushed
  toward fixing inline, which is the intent, but raises per-PR scope.
- Neither is mechanically enforced by this change. Both are prose proposals
  awaiting a decision.
