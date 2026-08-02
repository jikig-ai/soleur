# Decision Challenges — feat-one-shot-net-issue-flow-mandated-filing-exemption

Persisted at plan time on the headless path (ADR-084 / ADR-083). `/ship` renders this into the
PR body and files it as an `action-required` issue. **Not silently applied** — the operator's
stated direction remains the default in the plan.

Two challenges. Both come from reviewers who agreed with each other independently, and both
contradict explicit operator direction, so neither is auto-applied.

---

## DC-2 — Is the corpus-tag mechanism proportionate, or does a `reason=` token deliver the same benefit?

**Class:** User-Challenge (argues the operator's specified design should change)
**Raised by:** `dhh-rails-reviewer` and `code-simplicity-reviewer`, independently, converging on
the same scope. `cto` and `architecture-strategist` independently found the fact that makes their
case stronger (see "What changed since v1").
**Status:** recorded; operator direction followed in the plan (full mechanism retained)

### The operator's stated direction

> "Consider requiring the issue body to name the mandating rule id (e.g. `Mandated-By: <rule-id>`)
> and validating that id exists in AGENTS.rules.md… **derive the qualifying set from the rules
> corpus** rather than restating a list."

### The challenge

Both reviewers propose deleting the corpus mechanism and instead adding a **`reason=` token to the
override marker that already exists**:

```
<!-- gate-override: net-issue-flow reason=mandated-filing rule=wg-block-pr-ready-on-undeferred-operator-steps -->
```

Parse the trailing tokens, require the reason non-empty, print it on the report line, interpolate
it into the existing `_emit bypass` detail. Roughly 15–20 lines and three test cases, versus the
plan's 11 FRs, 8 TRs, 18 ACs, ~16 fixtures, a new ADR, a new corpus marker vocabulary, two WORM
ack rows, and a change to `lint-rule-bodies.py`.

Their argument in one line: **the plan pays the entire cost of unforgeability and then concedes it
does not achieve unforgeability.** The plan's own D3 says so — *"On pure rigor it is the blanket
override with extra steps, and a reviewer claiming so is correct."* Both reviewers claim exactly
that. What survives, they argue, is per-gate attribution — and a `reason=` token delivers 100% of
that.

Supporting points:

- **The gate runs as a local PreToolUse hook, in a process the claimant fully controls.**
  `SOLEUR_SKIP_NET_ISSUE_FLOW_GATE=1` is an unconditional bypass ~70 lines above where the
  exemption logic would land. You cannot build tamper-evidence inside a process the claimant owns.
- A third alternative from `code-simplicity-reviewer`: key the exemption off facts that already
  exist — the issue being **OPEN** and labelled **`deferred-automation`**, which is the mandating
  rule's own literal success predicate (*"`Tracks/Refs #NNNN` companions to OPEN deferred-automation
  issues"*). **Verified: issue #7159 already carries both.** ~6 lines, no corpus edit, no ADR, and
  it dissolves DC-1 entirely.

### What changed since v1 — this materially strengthens the challenge

The plan's counter-argument was that the corpus mechanism buys **attribution**, which a free-form
reason string does not. Two reviewers then measured the telemetry plane and found **there is no
readout at all**:

- `rule-metrics-aggregate.sh` builds `rules[]` from `AGENTS.md` ids only, and its line-319 filter
  removes `net-issue-flow*` from `orphan_rule_ids` — so those counts appear in `rule-metrics.json`
  **nowhere**.
- `operator-digest` never reads that file.
- `.claude/.rule-incidents*` is gitignored and worktree-scoped — it dies with `clean_gone`.
- The rule id would land in `rule_text_prefix`, a free-text field nothing parses.

So the attribution advantage the mechanism was justified by **does not exist as designed**. The
plan now requires FR6 to build the readout (~15 lines in the aggregator). Note that FR6 would
deliver attribution for a `reason=` token too — which is the reviewers' point: the readout is the
valuable part, and it is separable from the corpus mechanism.

### The counter-argument (why the plan still keeps the mechanism)

- The corpus tag makes the set of valid claims a **closed, human-gated vocabulary** rather than a
  free-form string. An agent must name one of N blessed rules, not invent a reason. That is a real
  difference in kind, even if it is not unforgeability.
- The operator specified this design explicitly and in detail. Per ADR-084, operator direction is
  the default; two reviewers agreeing is grounds to **surface**, not to override.
- The mechanism is reversible — untagging is a one-line corpus edit.

### The operator's call

- **(a) Keep the full mechanism** (plan default).
- **(b) Ship the `reason=` token instead** — ~20 lines, 3 tests, no ADR, no corpus change. Keep FR6
  (the readout) and FR0 (the timeout fix), which are valuable independently.
- **(c) Ship the label+OPEN variant** — ~6 lines, keys off the mandating rule's own predicate.
- **(d) Keep the mechanism but ship FR0 + FR6 first** as a separate PR, so the timeout fix and the
  attribution readout land regardless of how (a)/(b)/(c) resolves.

**Note:** FR0 (the gate currently times out and fails open — measured, live) is **not** part of
this challenge. It should ship regardless of the outcome.

---

## DC-1 — Should `wg-when-deferring-a-capability-create-a` carry `[mandates-filing]`?

**Class:** User-Challenge (contradicts explicit operator direction)
**Raised by:** the plan-time engineering consult, then independently by `dhh-rails-reviewer` and
`spec-flow-analyzer`. Three reviewers, three different arguments, same conclusion.
**Status:** recorded; operator direction followed in the plan (both rules tagged)

### The operator's stated direction

> "**At minimum** `wg-block-pr-ready-on-undeferred-operator-steps` and
> `wg-when-deferring-a-capability-create-a`."

### The challenge

The rule body, verbatim:

> When deferring a capability, default to **documenting it in-place** (plan, register entry, ADR,
> or code comment). File a GitHub issue **ONLY** when the `wg-defer-only-after-inline-triage` triple
> test passes. The plan's "Non-Goals" list IS the documentation; converting every Non-Goal to an
> issue creates phantom backlog.

1. **It fails the plan's own stated criterion.** D4's test is *"a compliant outcome requires a
   GitHub issue to exist — no inline-only path satisfies it."* This rule's **default** is the
   inline path. D4 excludes `wg-defer-only-after-inline-triage` as *"restricts, never mandates"* —
   and then tags its mirror image.
2. **The plan self-demonstrates the contradiction.** Its own Non-Goals section reads *"Documented
   in-place per `wg-when-deferring-a-capability-create-a` … none becomes a GitHub issue."* The plan
   invokes the rule as its reason **not** to file, in the same document that tags it as
   filing-mandating.
3. **It is mechanically unfalsifiable.** The mandate is conditional on the triple test, which has
   no observable precondition the gate can check.
4. **It covers the largest filing category**, so one tag risks making the gate advisory for the
   bulk of real filings.
5. **It is a reader with no writer** (`spec-flow-analyzer`). FR10 supplies a `Mandated-By:` writer
   only for `wg-block-pr-ready-…`. Capability-deferral issues are filed from `work/SKILL.md`,
   `review/SKILL.md` CONCUR, `drain-labeled-backlog`, and Non-Goals conversion — **none** emits the
   claim. So for the larger half of the tagged set, the claim is exactly what FR10's rationale says
   must not happen: hand-authored by an agent that wants an exemption.

### The counter-argument (why the plan still tags it)

- The rule **does** mandate a filing in the branch where the triple test passes — a genuine, merely
  conditional, mandate. The conflict the operator hit is real for this rule too.
- The direction is explicit and says "at minimum". Per ADR-084 the operator's direction is the
  default.
- Untagging later is a one-line corpus edit under the same ack gate.

### The decisive number was never measured

`architecture-strategist` names the question that should settle this, and notes nobody answered it:

> Of issues filed against merged PRs in the last 30 days, what fraction would satisfy
> `Mandated-By` + `Refs` + OPEN after FR10 ships?

If that fraction is **>50%**, the gate is advisory on merge. This is answerable with `gh` in one
session. **ADR-084 says operator direction is the default — it does not say the operator should
decide blind.** Running this query before Phase 1 is recommended regardless of the outcome.

### The operator's call

- **(a) Keep both** (plan default) — accept the wider surface, watch per-rule telemetry (which
  requires FR6 to exist).
- **(b) Ship with `wg-block-pr-ready-on-undeferred-operator-steps` only** — narrower, fully
  falsifiable, and it has a writer. The blanket override still covers deferral conflicts. Note this
  leaves a one-element derived set, which weakens D1's argument against a hardcoded list.
- **(c) Keep both and add a writer** — **now defined as FR10b** in the plan (`work/SKILL.md`). Note
  this option got substantially cheaper after the deepen pass: FR10b is now required *regardless* of
  how DC-1 resolves, because `work/SKILL.md` was found to be a live writer for the
  `wg-block-pr-ready-…` path too, carrying the same double-quoted-`\n` defect. Choosing (c) means
  additionally gating that writer on the triple test having actually passed.
- **(d) Measure first**, then decide.
