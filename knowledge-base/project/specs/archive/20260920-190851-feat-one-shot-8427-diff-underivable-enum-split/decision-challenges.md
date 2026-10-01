# Decision challenges — feat-one-shot-8427-diff-underivable-enum-split

Findings from `soleur:plan-review` classified as **Taste** or **User-Challenge** per
ADR-084. This session is headless, so they are persisted here rather than surfaced at
an apply gate. `soleur:ship` Phase 6 renders this file into the PR body and files it
as an `action-required` issue.

Everything classified **Mechanical** was auto-applied to the plan and is not listed
here.

---

## UC-1 — Shrink the diff-shape field set (User-Challenge)

**Panel:** `dhh-rails-reviewer` (F1), `code-simplicity-reviewer` (rec. 2),
`soleur:engineering:cto` (finding 2) — three reviewers, independently.

**The operator's stated direction** (work target, change 3): record "its length, plus
cheap booleans for a leading code fence, presence of a `--- `/`+++ ` header pair, and
presence of an `@@` hunk" — four fields, named explicitly.

**The challenge.** Two mutually exclusive proposals, both arguing the four fields are
over-provisioned once the `empty` predicate lands:

- *Cut two, keep two.* `len` and `hunk` (or `len` and `headerPair`, the reviewers
  differ) discriminate nothing at the apply arm, because the `empty` predicate
  intercepts the empty and whitespace-only inputs before `git apply` runs. Keep
  `fenced` + one other.
- *Collapse to an enum.* Replace all four with
  `{ len: number; kind: "empty" | "whitespace-only" | "fenced" | "header-no-hunk" | "other" }`.
  Four independent booleans give sixteen representable states to answer a
  three-way question, and the runbook then has to teach the truth table; one tag
  makes it a lookup, shrinks the PA-8 register cell to one field, and makes the
  acceptance criterion a trivial equality.

**Why it is not auto-applied.** Both drop or restructure scope the operator named
explicitly. Per ADR-084 and the `plan-review` routing rule, a `simplify-cut` of
operator-requested scope is never Mechanical.

**What the plan does meanwhile.** Implements the four fields as specified, and
removes the *false claim* attached to them — the draft said all four resolved a
four-way ambiguity at the apply arm, which the `empty` predicate had already made
untrue. That correction was Mechanical and is applied.

**If the operator agrees with the challenge**, the cheapest version is the enum: it
is a strictly smaller marker payload into a processor with no executed Art. 28(3)
instrument, which is the plan's own Art. 5(1)(c) argument applied to itself.

---

## UC-2 — Cut the path-narrowing in `detail` entirely (Taste) — PARTLY SUPERSEDED

**Status after the deepen pass:** the mechanism this challenge attacked no longer
exists in the form challenged. The security review established that the risk at the
`path-refused` and `structural-op` arms is not incidental disclosure but a
**200-character controlled write channel** into a third-party processor (the path in
`detail` is model-authored, not git-authored). D4.3 therefore now *classifies* the
path against a fixed prefix set and emits `<matched-prefix>/[elided]` or
`[unclassified-path]`, rather than eliding one directory's slugs. That change also
removes the incoherence the two reviewers correctly identified — the old rule fired
only on its own stated exception.

The residual question for the operator is narrower and is left open: is collapsing
the channel to a few bits worth the loss of the exact path in the Better Stack row,
given the full path still reaches Sentry? The reviewers' "cut it entirely" position
would answer no.

### Original challenge (retained for the record)

## UC-2a — Cut the learnings-slug elision entirely (Taste)

**Panel:** `dhh-rails-reviewer` (F2), `code-simplicity-reviewer` (rec. 6).

**The challenge.** D4 rule 3 reduces a `knowledge-base/project/learnings/` path in
`detail` to `[slug-elided]`. Both reviewers argue it should be deleted outright:

- Its original justification was self-defeating — it exempted `path-refused`, which
  is the only arm where a learnings path can actually surface, so the rule fired
  solely on its own stated exception. *(This part was a real defect and has been
  fixed in the plan: the exemption is gone and the justification rewritten.)*
- The residual objection stands: the same learnings corpus is already shipped in
  full to Anthropic by this very cron, so scrubbing a filename on its way to Better
  Stack is disproportionate.

**Why it is not auto-applied.** The rule derives from a condition the CLO attached to
its ADVISORY verdict, not from engineering taste. Dropping a legal-advisory control
is not a decision a review panel's simplicity lens gets to make silently — and
neither is keeping it without recording that two reviewers dissented.

**Counter-argument recorded for the operator:** "we already disclose it to a
different processor" is not a minimisation argument. Anthropic and Better Stack have
different postures, different retention, and — for Better Stack — no executed Art.
28(3) instrument (escalations #7529, #7825). The elision costs one line and one test
row.

---

## T-1 — The plan's gate sections are ceremony (Taste, declined)

**Panel:** `dhh-rails-reviewer` (F8).

**The challenge.** Roughly eighty lines conclude that a gate does not apply —
`Files to Create: None`, the C4 enumeration, `Encryption Posture`, `Open Code-Review
Overlap`, the six irrelevant domains. Collapse each to one line.

**Declined, with the reason recorded.** Phase 2.10's reject condition is explicit
that "an unsupported 'None' is a reject condition" for the C4 conclusion, and the
same shape applies to the other gates: the enumeration *is* the deliverable, because
a bare "not applicable" is indistinguishable from a gate nobody ran. The reviewer
framed this as a gripe about the template rather than about the plan, and it is
recorded here so the template critique reaches the operator rather than being
absorbed silently.
