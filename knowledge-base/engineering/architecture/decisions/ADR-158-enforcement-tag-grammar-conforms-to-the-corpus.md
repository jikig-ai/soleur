# ADR-158 — The enforcement-tag grammar conforms to the corpus, not the reverse

- **Status:** Accepted
- **Date:** 2026-08-03
- **PR:** #7194
- **Issue:** #7172 (the vacuous gate), #6751 (its orphaned failing suite), #4622 (an earlier report of the same drift)
- **Related:** [ADR-151](./ADR-151-agents-rule-corpus-is-unconditionally-loaded.md) (the corpus split that
  created the drift), [ADR-092](./ADR-092-additive-only-auto-edit-boundary-and-hard-rule-body-weakening-gate.md)
  (why a rule-body edit is expensive), [ADR-155](./ADR-155-cross-gate-exemption-markers-in-the-rule-corpus.md)
  (the marker whose legend this linter was mis-parsing), `scripts/lint-agents-enforcement-tags.py` (the gate)

> **Ordinal.** ADR-158 is the next free ordinal against a freshly fetched `origin/main` (highest
> existing is ADR-157), verified at `/work` time. Provisional until `/ship` re-checks at merge.

## Context

`scripts/lint-agents-enforcement-tags.py` resolves every `[hook-enforced: …]` and
`[skill-enforced: …]` tag in the rule corpus to a real enforcer. It is the only thing tying a rule
to the surface that enforces it.

It had validated **zero** tags since ADR-151 moved every rule body out of the pointer-only
`AGENTS.md` and into `AGENTS.rules.md`. Its argparse default named `AGENTS.md`; `lefthook.yml`
*did* pass both files explicitly, but the linter appeared in **no** CI workflow, so the only
invocation that saw the real corpus was a pre-commit hook a `--no-verify` could skip. `main` drifted
to 13 unresolved tags while every local run reported `OK: all 0 hook + 0 skill … resolve`.

The obvious reading — "12 tags drifted, align them to their headings" — was wrong, and measuring
before acting is the whole point of this ADR. Of the 13:

- **1** was the linter parsing its own documentation. The `> **Tag legend.**` blockquote, added by
  the PR that discovered this defect, literally contains `[hook-enforced: …]`; the linter tried to
  resolve `…` as a hook script.
- **2** were genuine wording drift, both on one line, and one of those was a single capital letter
  (`budget checkpoint` vs the actual bold label `**Budget checkpoint.**`).
- **9** were the parser being narrower than the vocabulary the corpus has always used.

Every enforcer named by all 13 tags **exists and actually enforces**: all seven skills, both hook
scripts, `plugins/soleur/lib/workflow-fidelity.ts`, `plugins/soleur/test/components.test.ts` (and
its `AUTONOMOUS_LOOP_SKILLS` symbol), and every phase anchor. Not one tag was factually wrong.

## Decision

**The rule corpus's enforcement-tag vocabulary is authoritative. The linter conforms to the corpus.**

When a tag and the linter disagree, the default remediation is to **extend the parser**. Rewriting a
rule body is reserved for tags that are *factually wrong* about their enforcer — a named skill that
does not exist, a hook that was deleted, a symbol that moved.

The rationale is asymmetric cost. A tag body is security-tagged, human-reviewed text whose every
edit costs an ADR-092 ack row and escalates to mandatory human review; the parser is ungated code
with a test suite. Optimising the cheap side is correct. Rewriting nine accurate rule bodies to fit
a parser limitation would have cost nine ack rows, destroyed information (a rule enforced across
five skills would have had to name one), and encoded the parser's limits into the corpus — making
the *documentation* worse to make the *tool* pass.

The supported vocabulary is now, explicitly:

| Shape | Meaning | Example |
|---|---|---|
| `,` | independent `<enforcer> <anchor>` pairs | `plan §1.8, brainstorm Phase 2 Budget checkpoint` |
| `/` | a **skill list** sharing one anchor | `plan/work/ship gates` |
| ` + ` | **enforcer segments**, each resolved on its own | `plan Phase 2.8 + iac-plan-write-guard.sh` |
| `<name>.<ext>` | a **file** enforcer, with an optional symbol | `components.test.ts AUTONOMOUS_LOOP_SKILLS` |
| `hook <script>` | an explicit hook segment | `… + hook ship-runbook-ssh-gate.sh` |
| `review-agent <name>` | an agent segment | `… + review-agent silent-failure-hunter` |

A `/`-joined anchor need resolve in only **one** member: a cross-skill gate documents its contract
in whichever skill owns it, not redundantly in all of them. Skill existence is still checked for
**every** member.

Two properties are preserved deliberately:

- **Tags are read only from real body lines** (`- ` at column 0), mirroring `lint-rule-bodies.py`.
  Prose *about* the tag syntax is documentation, not a claim to resolve.
- **Path traversal stays refused.** The `/` loosening applies to the skill-list token only; `..` is
  rejected unconditionally and anchors still reject `/`.

**A vacuity floor is added.** Scanning zero tags is now an ERROR, not a pass. "Everything resolved"
and "there was nothing to resolve" shared an exit code, and the second reads as safety — which is
exactly how this gate certified nothing for months. The floor is asserted over the sum across files,
so pointing the linter at the pointer-only `AGENTS.md` alone now fails loudly. Precedent: the
`MIN_ASSERTIONS` floor in `plugins/soleur/test/net-issue-flow.test.sh`.

## Alternatives considered

**(a) Normalise every tag to the one-skill-one-anchor grammar.** Rejected. Nine ADR-092 ack rows,
each escalating to mandatory human review; information loss on multi-skill and multi-enforcer rules;
and it inverts the dependency — the corpus would document what the parser can express rather than
what actually enforces the rule. This was the remedy #7172 prescribed, and measuring the failure set
is what refuted it.

**(b) Retire the two rules whose tags "named nonexistent skills."** Rejected on the facts: neither
named a skill. `SKILL_TAG_RE` captured the leading `[a-z][a-z0-9-]*` of `workflow-fidelity.ts` and
`components.test.ts` and mistook the prefix for a skill slug. Both tags already pointed at the
surface that enforces the rule.

**(c) Delete the anchor-parity check.** Rejected. It is the only mechanism tying a rule to a live
enforcer; the failure mode here was that it ran on nothing, not that it checked the wrong thing.

**(d) Make anchor matching case-insensitive** to absorb the `budget checkpoint` drift. Rejected as a
gate loosening bought for one character. The tag was corrected to cite the real bold label verbatim
instead, which is also better documentation.

## Consequences

- The gate now resolves 10 hook + 30 skill tags across 38 anchor-parity checks, and is registered in
  `scripts/test-all.sh` as a `-live` / `-unit` pair alongside `lint-rule-ids`, so it runs in CI
  rather than only at pre-commit.
- `scripts/lint-agents-enforcement-tags.test.sh` goes from 7/9 to 21/21 and is removed from the
  `lint-orphan-test-suites.sh` exclusion list, which is now empty — the goal state.
- **The grammar is more permissive, which is the risk this ADR accepts.** It is bounded by keeping a
  negative test per variant, asserting exact expected tag counts rather than `> 0`, and the vacuity
  floor. A future widening must add its own negative case.
- Adding a new tag shape is now a deliberate act: extend the parser, add a positive **and** a
  negative test, and record the shape in the table above.

## Recorded limitation

This ADR does not claim the corpus's vocabulary is *good* — `/`, ` + `, and bare file names are an
accreted notation, not a designed one. It claims only that the notation is **accurate about
reality**, and that accuracy is the property worth preserving when the two disagree. A deliberate
redesign of the tag syntax remains open, and would be a corpus-wide migration with its own ack
budget, not a side effect of repairing a gate.
