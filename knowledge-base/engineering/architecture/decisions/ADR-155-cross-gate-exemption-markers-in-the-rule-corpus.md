# ADR-155 — Cross-gate exemption markers in the always-loaded rule corpus

- **Status:** Accepted
- **Date:** 2026-08-02
- **PR:** #7161
- **Issue:** none (surfaced while shipping the token-drift coverage PR, merged as `b5871b9f6`; the
  mandated filing that triggered the conflict is #7159)
- **Related:** [ADR-092](./ADR-092-additive-only-auto-edit-boundary-and-hard-rule-body-weakening-gate.md) (the ack gate that makes the
  marker human-controlled), [ADR-151](./ADR-151-agents-rule-corpus-is-unconditionally-loaded.md) (the corpus split
  that put rule bodies in `AGENTS.rules.md`), [ADR-131](./ADR-131-gate-moratorium-and-meta-work-budget.md)
  (the moratorium this must not be read as circumventing),
  [ADR-084](./ADR-084-decision-classification-taxonomy-for-autonomous-question-surfacing.md) (why two reviewer
  challenges were recorded rather than applied), `plugins/soleur/skills/ship/scripts/net-issue-flow.sh`
  (the reader), `scripts/lint-rule-bodies.py` (`SECURITY_TAG_MARKERS`)

> **Ordinal.** ADR-155 is the next free ordinal against a freshly fetched `origin/main` (highest
> existing is ADR-154), verified at `/work` time. Provisional until `/ship` re-checks at merge.

## Context

Two repo gates were in genuine, unresolvable-by-design conflict.

`wg-block-pr-ready-on-undeferred-operator-steps` **requires** a tracking issue for a bare operator
action before `gh pr ready`. `net-issue-flow.sh` **blocks** any PR whose `NET = FILED - CLOSING` is
`> 0`. On 2026-08-02, shipping the token-drift coverage PR, obeying the first forced a violation of
the second.

Neither documented exit applied:

- **"Fix inline"** is a **size** test (`<=100` lines AND `<=4` files). The blocker was **authority**:
  an operator-only production credential decision. No diff size makes an agent able to take it.
- **"Close something"** requires the filed issue to supersede an open one. A mandated tracker
  supersedes nothing — it exists precisely because the work is *not* done.

That left one exit: the blanket `<!-- gate-override: net-issue-flow -->` marker, whose own help text
described itself as a *"legitimate architectural-pivot deferral"*. This was not an architectural
pivot. Taking the documented exit required mis-describing the escape.

**That is the failure mode, and it is worse than a gap.** A gate whose only escape hatch demands a
false justification trains the reflex of reaching for the hatch without reading it. The override
stops being a decision on the record and becomes a keystroke. The net-issue-flow surface already
learned this once — it ran advisory for three months and was skipped, because advisory output is
free to ignore. An override that everyone reaches for reflexively is advisory with extra steps.

## Decision

Introduce `[mandates-filing]`, a marker in `AGENTS.rules.md` rule bodies. An issue whose body carries
`Mandated-By: <rule-id>` is subtracted from `NET` when **all four** conditions hold:

1. the ISSUE body carries `Mandated-By: <rule-id>` on a line of its own,
2. `<rule-id>` carries `[mandates-filing]` in the **merge-base** copy of `AGENTS.rules.md`,
3. the issue is **OPEN**, and
4. the PR body carries a `Tracks #<issue>` / `Refs #<issue>` companion.

Every condition fails **closed**. Initially tagged: `wg-block-pr-ready-on-undeferred-operator-steps`
and `wg-when-deferring-a-capability-create-a`.

### The class boundary (what is actually new here)

The corpus already carries `[compliance-tier]`, `[hook-enforced: …]`, `[skill-enforced: …]` and
`[scanner-enforced: …]`. Every one of those describes **how the rule it sits on is enforced**. They
are self-referential metadata: a reader of the rule learns where to find its teeth.

`[mandates-filing]` is the first marker that grants a rule **authority over a different gate**. It
does not describe how `wg-block-pr-ready-…` is enforced; it changes what `net-issue-flow.sh` will
let through. That is a new category, and it is the reason this needs an ADR rather than a comment.

The consequence to state plainly: the corpus is now an input to a gate that is not its own. Adding a
marker to a rule body is no longer a purely local edit.

### Why derive the set from the corpus rather than list it in the gate

A list in `net-issue-flow.sh` would be a second pin on the same fact, and the copy that drifts is
always the one that runs. The corpus is already the single always-loaded source of rule truth
(ADR-151), it is already human-gated for body changes (ADR-092), and it is already the thing an
agent reads when deciding what a rule requires.

Rejected alternatives:

- **A hardcoded id list in the gate.** The forbidden second pin.
- **A prose heuristic** ("does the rule body contain the word *file*"). Measured over-permissive: it
  matches `wg-when-a-test-runner-crashes-segfault-oom` (a three-way disjunction) and, worse,
  `wg-defer-only-after-inline-triage`, which *restricts* filing. A heuristic that exempts the rule
  telling you not to file is not a near-miss, it is an inversion.
- **A GitHub label** (`mandated-filing`). A bare label anyone can add reproduces the blanket override
  with extra steps and a false air of process.
- **A free-form `reason=` token on the existing override marker.** Cheaper (~20 lines) and delivers
  the same per-gate attribution — this was raised independently by two reviewers and is recorded as
  DC-2. It was not taken because it is self-serve: an agent invents the string. The corpus tag makes
  the set of valid claims a **closed, human-gated vocabulary**. That is a difference in kind, not
  degree, even though it is not tamper-evidence (below).

### Scope restricted to `^(hr|wg)-`

Extraction ignores any id outside those prefixes, so the derived set is **by construction** a subset
of the ADR-092 ack gate's coverage (`GATED_PREFIX_RE`). Without this, a `cq-*` rule could carry the
marker and grant exemption authority with no ack required — measured, **27 of 101** ids sit outside
that gate. `[mandates-filing]` is also added to `SECURITY_TAG_MARKERS` so both adding and (more
importantly) **dropping** it are loud; a silent drop would just stop the exemption matching, with no
symptom beyond a `Mandating rules:` count nobody is watching.

### Merge-base, never the worktree, never a bare `:path`

The corpus is read at `git merge-base origin/main HEAD`, behind an explicit SHA guard.

- The **worktree** is author-controlled: a PR could tag a rule and exempt itself in the same diff.
- A bare `git show ":AGENTS.rules.md"` reads the author's **staged index** — also author-controlled.
  This is the dangerous one: measured, it returns `rc=0` and a full 101-id list, so the read
  *succeeds* and no empty-set warning fires. A fail-open in the one shape nothing downstream can
  notice. (`.claude/hooks/brand-hex-commit-gate.sh` uses `git show ":$f"` **deliberately**, for the
  opposite reason — so an unstaged worktree edit cannot whitelist a colour. The two are not in
  tension; they want different things from the same primitive, which is exactly why the distinction
  needs writing down.)

## Consequences

### (a) It is NOT unforgeable, and must not be described as such

This gate runs as a local `PreToolUse` hook, in a process the claimant fully controls.
`SOLEUR_SKIP_NET_ISSUE_FLOW_GATE=1` is an unconditional bypass roughly seventy lines above where the
exemption logic sits. You cannot build tamper-evidence inside a process the claimant owns.

What the mechanism actually buys is (i) a **closed vocabulary** — an agent must name one of N
human-blessed rules rather than invent a reason — and (ii) **per-rule attribution** in telemetry.
Both are real. Neither is unforgeability. Any future document describing this as a security control
is wrong.

### (b) The attribution claim required building the readout it assumed

The justification in (a)(ii) was, when first written, **false**. `rule-metrics-aggregate.sh` builds
`rules[]` from `AGENTS.md` ids only and filters `net-issue-flow*` out of `orphan_rule_ids`, so those
counts reached `rule-metrics.json` **nowhere**; `operator-digest` never reads that file; and
`.claude/.rule-incidents*` is gitignored and worktree-scoped, so it dies with `clean_gone`.

Shipping the framing without the readout was the one outcome to avoid, so this PR adds
`summary.gate_exemptions` (per-rule bypass counts), `summary.gate_override_count`, and
`summary.gate_timeout_warn_count` to Stage C. The emitter was also corrected: the per-rule id rides
in the **structured `rule_id`** (`net-issue-flow-mandated-filing--<rule-id>`), not in
`rule_text_prefix`, which nothing parses. The signal worth watching is the **comparison**: exemptions
rising while overrides fall is the intended effect; both rising means the gate is being routed
around rather than satisfied.

### (c) Most filing sites can never use this, by construction

The corpus sweep covered *rules*. Most issues are filed from **SKILL.md phase mandates that carry no
rule id at all**: the CMO content-opportunity and website-framing gates (which file automatically,
headless), the ADR-084 decision-challenge issue, and the review-finding gate. There is nothing to
tag, so every one of those remains a **permanent blanket-override case**.

This is why the override is left working and unchanged, and why its help text was rewritten to
describe several legitimate uses rather than one. The exemption does **not** generalize, and reading
it as "the principled replacement for the override" would be a mistake.

### (d) A PR that adds a tag cannot use it

Because the corpus is read at the merge-base, the exemption does not work on the PR that introduces a
tag — including this one, which therefore carries the blanket override and says so. Branches open
when this merges will report `Mandating rules: 0` until rebased. Both are correct behaviour and
routine noise, not faults; the report distinguishes "read failed" from "read OK, zero tagged" and
gives each its own telemetry id so the two are never confused.

### (e) AP-017 deviation

AP-017 designates "add a new rule (new id)" as the always-safe additive lane. That lane now has an
exit into gate-exemption authority: a **new** rule id carrying `[mandates-filing]` is additive, so it
takes no ack. `SECURITY_TAG_MARKERS` makes it *annotate* loudly, and `^(hr|wg)-` keeps it inside the
ack gate's prefix scope, but the additive-new-rule path remains the widest door and should be treated
as such in review.

### (f) Cheaper unattributed bypasses still exist

The instrument measures only agents who take the honest path. Two cheaper routes are invisible to it:

- **File the issue BEFORE the PR exists.** The `createdAt` filter excludes it from `FILED` entirely —
  a free `NET 0` with no telemetry at all.
- **Write `Closes #N` without closing anything.** `CLOSING` is parsed from the PR body, not verified.

Both are cheaper than complying. So the exemption currently makes the *honest* path strictly harder
than the dishonest one, and the `gate_exemptions` numbers must be read as a floor on honest use, never
as a measure of total bypass. Closing those two is separate work and is not attempted here.

### (g) Relationship to the ADR-131 moratorium

ADR-131 (`status: proposed`) restricts *new* gates while permitting that existing ones "may be fixed,
tightened, merged, or deleted". This adds no new gate: it narrows an existing gate's escape hatch from
"blanket override, reflexively taken" to "blanket override, plus a narrow corpus-derived path for the
one case the repo's own rules force". Whether that counts as a *fix* is a judgement, and it is
recorded here rather than assumed.

## Recorded challenges (not applied)

Per ADR-084, two reviewer challenges contradict explicit operator direction and are recorded rather
than applied, with the operator's direction kept as the default. Both are in
`knowledge-base/project/specs/feat-one-shot-net-issue-flow-mandated-filing-exemption/decision-challenges.md`:

- **DC-2** — three reviewers argue the corpus mechanism is disproportionate versus a `reason=` token
  or an OPEN + `deferred-automation` label check. Addressed under "Rejected alternatives" above: both
  are self-serve, which the operator's constraint excluded explicitly.
- **DC-1** — three reviewers argue `wg-when-deferring-a-capability-create-a` should not be tagged,
  because its **default** is documenting in-place and its filing branch is conditional on a triple
  test the gate cannot observe. The counter is that the conditional branch is a genuine mandate, and
  the operator's direction said "at minimum" both rules. Untagging is a one-line corpus edit under
  the same ack gate. The decisive measurement — what fraction of recently filed issues would satisfy
  `Mandated-By` + `Refs` + OPEN — was never taken; the query is recorded in DC-1.
