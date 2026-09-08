---
branch: feat-one-shot-7500-zot-last-err-redact
issue: 7500
phase: plan + deepen-plan
---

# Decision Challenges — #7500

Recorded rather than surfaced interactively (headless pipeline). `ship` renders these into the PR body
and files them as an `action-required` issue.

## 1. The plan answers more than #7500 literally asked — deliberately

**Operator's stated direction.** #7500 asks one question: should `zot_last_err` route through
`redact()`? It offers three options and says the answer is "not a foregone conclusion".

**What the plan does instead.** It answers that question (yes — per line, degrading rather than
dropping), and **also** ships two things the issue does not mention: a **tier gate** and a
**sink-side scrub** on a public-egress path.

**Why the expansion, in one line each.**

- The **sink-side scrub** exists because the plan discovered, and then measured, an egress the issue never mentions: `scripts/zot-restart-loop-alarm.sh` publishes the raw `zot_last_err` tail into a **public** GitHub issue. Public issue #7272 carries 36 published `headers:{` objects. That surface is worse than the warehouse path #7500 was filed about, and it is closable with **zero infrastructure cost**, whereas the producer-side answer to #7500's literal question is inert until the next host replace.
- The **tier gate** exists because tier 4 produced ~100% of the measured header-bearing samples and named a cause zero times across a 21-hour crash loop — and the tier is already tagged for free. It removes the dominant exposure for **+40 B** measured.

**What the operator may want to overrule.** Splitting either addition into its own issue is defensible.
The cost of doing so: the public egress stays open for the duration, and the split PRs both touch the
same two files.

## 2. A measured precondition may make half the fix unnecessary

Phase B (the producer-side redactor, +64 B, and the only half that costs a host replace) rests on a
claim the plan explicitly marks **unevidenced**: that tiers 1-3 can carry a header object. The measured
corpus says tier 4 produced ~100% of them.

The plan therefore makes Phase B conditional on a probe (counted header-bearing samples on tiers 1-3
over the retention window). **If that probe returns 0, the redactor should be deferred** and #7500 is
answered by the tier gate plus the sink scrub alone. This is flagged because it is the one place the
plan could still be doing unnecessary work, and the deciding measurement is a single query.

## 3. Brand-survival threshold set to `single-user incident`

Ruled by the CPO on the ladder's own text (`none` requires "no credential surface", false here), not on
a probability estimate — the measured fact pattern found **no** credential exposure. The consequence is
real process cost: CPO sign-off, `user-impact-reviewer` at review, and a non-scoped-down GDPR gate. An
operator who reads the measured evidence as decisive may prefer `aggregate pattern`; note that this
would be a **gate downgrade** (no sign-off, and `user-impact-reviewer` exits immediately), not an
escalation.
