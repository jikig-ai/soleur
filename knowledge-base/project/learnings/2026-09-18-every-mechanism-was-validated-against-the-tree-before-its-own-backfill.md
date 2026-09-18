---
title: Every mechanism was validated against the tree before its own backfill
date: 2026-09-18
category: workflow-patterns
module: plugins/soleur/skills/plan
issue: 8299
tags: [guard-design, vacuity, mutation-testing, plan-review, gates]
---

# Every mechanism was validated against the tree before its own backfill

## Problem

A 454-line plan for #8299 proposed a born-blocking census: enumerate all 98 skills, require each
invocation-bearing one to carry a `grok-harness-invoke` marker block, and hold the result with four
numeric floors. Its measurements were unusually good — a reviewer independently reproduced 13 of 13
counts. It passed `lint-guard-contract.py`, `lint-infra-no-human-steps.py`, `gdpr-gate.sh` and
`c4-count-parity.test.sh`.

A six-agent panel then found, six independent ways, that **the gate would report green over the
exact defect it was commissioned to catch** — and that most of its mechanisms were sound against
today's tree and dead against the tree its own Phase 5 backfill would produce.

## Root cause

Two distinct errors, and the second is the generalizable one.

**1. The carrier was inbound; the property was outbound.** `grok-harness-invoke` is a
*self-invocation preamble* — it tells an agent already reading the file how it should have arrived.
The property was about what the file tells an agent to invoke *next*. Measured consequence:

| Doc | Carries the block? | Still dispatches | Census verdict |
| --- | --- | --- | --- |
| `ship/SKILL.md:504` | yes | `skill: soleur:preflight` via the Skill tool | **QUALIFIED** |
| `gdpr-gate/SKILL.md:270` | after backfill | `/soleur:trigger-cron` — the form that opened #8299 | **QUALIFIED** |
| `incident:39`, `product-roadmap:36` | after backfill | same form | **QUALIFIED** |
| `commands/go.md:122` | n/a | names Claude + Grok only | **outside the population** |

A presence check cannot detect a content defect. Every one of the plan's 13 mutation rows tested
**enumeration** — is the block there, is the population derived, does the floor fire. Not one
tested **implication** — does the block's presence mean anything. Adding that single row fails the
plan against its own matrix, which is how this should have been caught before 454 lines.

**2. Every mechanism was measured on the pre-state of the transformation it governed.** The plan's
backfill adds the block to 34 skills. The block's own text contains `Skill tool` and `invokeSkill` —
two of the classifier's twelve trigger alternatives. So:

```console
# leave-one-out on the trigger pattern: how many alternatives can be deleted
# without changing the trigger count?
today (12 skills carry the block) : 6 of 12 alternatives already unreachable
after the backfill (46 carry it)  : 12 of 12 unreachable
```

Reduce the pattern to the single alternative `invokeSkill` and the post-backfill census reports
trigger 46, qualified 46, unclassified 0, auto-exempt 52 — **all four floors green, the gate fully
vacuous, certifying perfect compliance.** The classifier's input had become a function of its own
output.

The same shape hit three more mechanisms:

- **The Cut List** cut marker-block stripping as "a measured no-op, 46 → 46." True today, because
  only 12 skills carried the block and all 12 triggered independently for other reasons. False the
  instant the backfill ran. The cut's reasoning also aimed at the wrong risk — it argued stripping
  "can never produce a false RED," when the reason to strip is to prevent a false **GREEN**.
- **The auto-exempt ceiling**, credited as the RED-by-default mechanism, is a *net-count identity*.
  Add one non-triggering skill and delete one auto-exempt skill: `pop 98≥98, trig 46≥46,
  auto 52≤52, unc 0` — green, new skill silently exempt. This is the partition defect ADR-193's own
  Consequences record having shipped and falsified: *"deriving `deferred` as 'everything not
  covered' makes the two sets a partition of one list, so the sum always equals the total and the
  arm can never fail."* Reproduced one level up, in the plan that cites that ADR.
- **All four floors were aggregates** while the property they defended (*"a newly added skill is not
  silently exempt"*) is **per-member**. No aggregate can express a per-member property.

## Solution

Invert the gate to **negative space**. Rather than asserting a marker is present, assert a
harness-specific invocation token is *absent*, and that skills name the canonical form the adapter
resolves:

```
population  = git ls-files plugins/soleur/{skills/*/SKILL.md,commands/*.md}   # 101 docs
strip       = sanctioned marker blocks + fenced code
assert      = zero harness-specific skill-invocation tokens in the remainder
canonical   = bare `soleur:<name>`, resolved per harness by lib/harness.ts
```

The predicate becomes **provable complete**, because its token set is not guessed — it is read off
the `formatSkillInvocation` / `formatAgentSpawn` functions that *define* the forms. Measured: 45 docs
/ 175 occurrences in violation; 56 compliant. It catches `go.md` (25), `gdpr-gate` (17), `ship` (14)
and `plan-review` (9) — every instance the presence census missed.

Four floors collapse to one exact snapshot, which catches removal, addition, over-matching **and**
under-matching in a single line — none of which the floors did.

## Key Insight

**A gate's mechanisms must be validated against the tree its own remediation produces, not the tree
it finds.** The plan's trigger floor, auto-exempt ceiling, two mutation rows and one Cut List entry
were each *correct when measured* and dead after the backfill. Nothing in the authoring loop asks
"re-run this measurement against the post-change state," because the post-change state does not
exist yet — so the check has to be an act of imagination, deliberately scheduled.

The cheapest form of that discipline: **for every mechanism, name the mutation that would defeat it
after the change lands.** For a classifier whose remediation writes text, the first candidate is
always *"does the remediation's own text match the classifier?"*

Corollary, and the sharper half: **a check that tests enumeration is not testing the property.**
Presence, counts, derivation and floors are all statements about the *shape* of the population. A
property of the form "X implies Y" needs a row where X holds and Y fails. If no such row exists, the
guard is measuring its own bookkeeping.

## Prevention

- In a Guard Contract, require at least one mutation row where the guard's own **precondition is
  satisfied and the property still fails**. Enumeration rows cannot substitute.
- Before cutting a mechanism as a "measured no-op," state which state the measurement was taken in,
  and re-take it against the post-remediation state.
- Treat an aggregate floor as unable to express a per-member property. If the property is
  per-member, the artifact is an inventory, not a count.
- After renaming any heading a gate keys on, re-run that gate and assert the **entry count** moved —
  not merely that it exits 0 (Session Error 2).
- Run every acceptance criterion that prescribes shell, against the current tree, before freezing it
  (Session Errors 6–7).

## Session Errors

1. **A presence census cannot detect a content defect.** 454-line plan superseded pre-implementation.
   **Recovery:** six-agent panel; operator chose the negative-space inversion; v2 written.
   **Prevention:** the implication-row requirement above.

2. **I renamed a heading and my own gate stopped validating the section that mattered.** Plan v2 was
   appended under `## v2 Guard Contract`; `scripts/lint-guard-contract.py`'s matcher is
   `^##\s+Guard\s+Contract\b`, which does not match it. The lint reported *"1 with a Guard Contract,
   1 guard entry"* — it had validated only v1's **superseded** contract while the plan of record was
   unchecked. **Recovery:** noticed the entry count was 1 while the file visibly had two `### Guard`
   headings; renamed to `## Guard Contract — v2 (plan of record)`; the lint then reported 2 entries.
   **Prevention:** a gate keyed on a heading is keyed on a string the author is free to change, and
   a superseded section can satisfy it — after any such rename, assert the count changed.

3. **My own ERE escaping produced a false zero.** `git grep -lE '/soleur:[a-z-]\+'` returned 0 files
   and I nearly reported that the alternative matched nothing; in ERE `\+` is a literal plus. Real
   answer: 32 files. **Recovery:** the 0 contradicted an earlier python scan.
   **Prevention:** when two tools disagree on a count of the same thing, escaping is the first
   suspect — and cross-tool disagreement is the cheap tell that caught it.

4. **I scoped ADR-193 out for Decision 1 and in for Decision 5 with the same argument.** If
   out-of-population defeats one decision it defeats its siblings identically — and Decision 5 was
   the sole cited authority for deleting the `UNION` array. **Recovery:** v2 argues the
   generalization on its merits and drops the deletion entirely.
   **Prevention:** if an argument disqualifies one decision in an ADR, state why it does not
   disqualify the others.

5. **Miscited `cq-test-fixtures-synthesized-only`** to justify ledger placement. It is a
   *secret-scan* rule over three specific globs, none of which is `plugins/soleur/test/fixtures/`.
   I borrowed a rule id for its name rather than its text. **Recovery:** v2 cites the real
   `fixture-*-assert.baseline.txt` precedent. **Prevention:** grep the rule body before citing it.

6. **Called `harness-model-map.test.ts:76` a 4-harness literal** two lines after my own Research
   Insights recorded that `TIER_MAPS` is claude/grok-only. It is `["claude","grok"]`, deliberately.
   Repointing it would have made a live assertion pass vacuously through the unmapped `"inherit"`
   fallback. **Recovery:** v2 repoints only `workflow-fidelity.test.ts:373`.
   **Prevention:** shares its root with 7 — see below.

7. **Three of four shell-prescribing ACs were broken.** AC11 (`git diff | grep -c 'PLUGIN_ROOT:-'`)
   returns 9, not 0, because the plan and spec discuss the banned form — and two of the nine are
   AC11's own lines. AC7 emits `path:count` per file with no total and no comparison operator. AC6
   was a bare-token absence check a tombstone comment would fail.
   **Prevention (shared with 6):** the root of both is **prescriptions I did not execute.** Every
   measurement in this plan was run; every prescription was written. The measured half reproduced
   13 of 13; the prescribed half broke 3 of 4. Run the command you are about to prescribe.

## Related

- `knowledge-base/project/plans/2026-09-18-feat-harness-parity-census-plan.md` — v1 retained as the
  review record with all 30 findings; v2 is the plan of record
- `knowledge-base/project/learnings/2026-09-18-a-census-cell-naming-two-markers-reports-the-union-as-each-member.md`
  — the brainstorm-phase sibling
- `knowledge-base/engineering/architecture/decisions/ADR-193-anti-vacuity-floor-contract.md` —
  Decision 5 and the partition defect its Consequences record
- Issues: #8299, #8306, #8307, #8308, #7453
