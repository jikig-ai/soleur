---
title: "ADR-200 — Art. 33(5) breach documentation is a distinct register, discharged by an index rather than by transcription"
status: accepted
date: 2026-09-03
tags: [gdpr, legal, registers, accountability, breach-documentation]
related_adrs: [ADR-197]
related_runbooks:
  - knowledge-base/engineering/operations/runbooks/breach-access-log-investigation.md
---

# ADR-200 — Art. 33(5) breach documentation is a distinct register, discharged by an index

## Status

Accepted 2026-09-03 (#7717). Supersedes no ADR. The register it governs is
`knowledge-base/legal/breach-register.md`, which carries
`status: draft-requires-counsel-review` — this ADR fixes the *instrument*, and counsel review of
its content remains open as item 12 of the Art. 30 register's counsel-review list.

## The decision, in two parts

**1. Art. 33(5) documentation lives in its own register, not as a limb of the Art. 30 register.**

Art. 30(1) enumerates a closed list of limbs (a)–(g). Breach documentation is not among them.
Art. 33(5) is a separate obligation with a separate verification purpose — it exists so a
supervisory authority can verify compliance with Art. 33 — and CNIL practice keeps a *registre
des violations* distinct from the *registre des traitements*.

Co-locating the two invites the reading that Jikigai treats Art. 33(5) documentation as an
Art. 30 limb. That is a cheap error to avoid and an expensive one to explain in an Art. 58(1)(a)
exchange, where the register is the artifact actually produced.

The corpus already carried the precedent: `knowledge-base/legal/article-30-2-register.md` exists
as a distinct file for Art. 30(2) processor-capacity records. This decision applies the same
principle a second time rather than inventing one.

**Corollary — the identity field names the capacity the register is kept in.** The Art. 30(2)
register carries `processor:`; the breach register carries `controller:`. Art. 33(1) and 33(5)
both bind "the controller" on their face, and a processor's duty is the Art. 33(2) duty to notify
the controller, which carries no register of its own. Deriving the frontmatter by diffing the two
existing registers' field lists yields the wrong answer here; deriving it from the principle
yields the right one.

**2. The obligation is discharged by an index with stable canonical pointers, not by
transcription.**

Art. 33(5) requires documentation of the facts, effects and remedial action. That documentation
already exists, per incident, in the determination records themselves. Copying it into a register
mints a second artifact that drifts from the first — and this repository's gates measure
*agreement*, not *truth*, so two byte-identical copies of a stale sentence pass everything.

Two further grounds specific to signed instruments. A determination's integrity comes in part
from being unamended, and transcribing it reproduces its signature block without a signature. And
a register entry is a **live representation to a supervisory authority**, not an archival copy:
reproducing a determination's evidentiary sentence under any heading represents that the
controller currently believes it. Where a later annotation has narrowed that sentence, the copy
would be a misrepresentation the original is not.

Rows are therefore summaries. They must nonetheless be self-sufficient on notifiability, so the
column set is fixed: date, event, PA(s) touched, **awareness anchor** (the Art. 33(1) 72-hour
clock origin), determination, **Art. 33 engaged?**, **Art. 34 engaged?**, evidentiary limbs
inconclusive?, canonical source.

Art. 33 (supervisory authority) and Art. 34 (data subject) get **separate columns**. They are
different tests, and neither may be inferred from the other. Where a source makes a finding on
one and is silent on the other, the register records the silence as silence — writing "No" would
mint a finding nobody made.

## The inclusion predicate, and why it must be stated

"Index every determination" is unfalsifiable, and a gate built on it is unbuildable. The
predicate is conjunctive: an event is indexed when a **breach-shaped fact pattern** arose **and**
it was assessed against Art. 4(12) with a determination recorded.

Two exclusions follow, and both are load-bearing.

**Screening outputs are not determinations.** Post-incident reviews generated from
`plugins/soleur/skills/incident/templates/pir.md` carry `art_33_triggered:` frontmatter. Measured
2026-09-03 on `main`: **102** post-mortems under
`knowledge-base/engineering/operations/post-mortems/` carry that field, unchanged at this PR's
HEAD. A repo-wide total is not quoted — it counts plans, specs, this ADR and the guard's source,
so any PR that merely discusses the field moves it (this one took it 115 → 119). A `false` on an
availability-only or credential-only incident is a screening output. Indexing them would bury
four determinations under a hundred routine negatives, destroying the register's verification
value in the name of completeness.

**Prospective clearances are not breach documentation.** A review concluding that a *planned
change* engages no Art. 33 or Art. 34 duty describes no fact pattern. If every Art. 30 amendment
review reciting "this change engages nothing" earned a row, the register would become a log of
change approvals and an authority could no longer distinguish incidents from housekeeping.

**Exclusions are committed, never silent.** A file that is determination-shaped under the CI
guard's pinned pattern but falls outside the predicate carries a `NOT_TRANSCRIBED` waiver with a
reason and a citing issue. That is the structural answer to the obvious objection — that a
semantic predicate lets a real determination be quietly dropped. It can be argued with; it cannot
be applied invisibly.

## The maintaining surface — this ADR names a writer

A register with no writer is prose. Three surfaces maintain this one:

- **The `clo` agent** is the custodian, and maintains the register at ship time. A PR that lands
  a new determination adds its row in the same PR.
- **`/soleur:incident`** routes to this register for the `art_33_triggered: true` case, so a live
  incident that produces a determination has a defined destination rather than a convention.
- **`plugins/soleur/skills/ship/references/register-update-pr-pattern.md`** names this register
  alongside the Art. 30 register, so a register-update PR is not routed to the wrong file by a
  document that only knew about one register.

## The gate, and why it is advisory first

`scripts/lint-legal-registers.sh` asserts three properties: no standalone unresolved marker in
the register files; every canonical-source pointer resolves on disk; and declared-set integrity —
every determination-shaped `audits/**` file is either indexed or waived with a reason.

**The coverage assertion is inverted deliberately.** Asserting coverage of a *discovered* set is
not implementable: any keyword producer either captures the 102 screening outputs or misses the
six prose determinations, because the discriminator is semantic and no regex makes a legal
judgement. So the gate asserts integrity of the *declared* set instead. It cannot tell you that a
determination was missed; it can tell you that nothing was dropped without a recorded reason,
which is the property a register's maintenance actually needs.

**It lands advisory for one merge cycle.** It is the first lint over the legal **register
files** — narrower than "the first lint over `knowledge-base/legal/**`", which this ADR
claimed until self-review falsified it: `scripts/lint-infra-no-human-steps.py` already scans
`knowledge-base/legal/runbooks` through its `SCAN_DIRS`. What was true, and is the load-bearing
point, is that **no lint covered the registers themselves.** Its scope was designed rather than
measured. A first-of-its-kind gate does not go straight onto the one required
context that cannot be un-required. Promotion is deleting a flag at the call site once a cycle
has measured the scope, and is tracked with its checklist at **#7787**. The advisory path deliberately does **not** downgrade a fail-closed
refusal: a finding becomes a warning, an "I cannot decide" stays a hard failure.

**The token scan is scoped to the register files, not the corpus.** `audits/` is a
working-document tree whose counsel reviews legitimately carry unresolved markers for open
counsel questions; one of them cannot be made token-free without falsifying its own sentence.
Scanning the whole tree would red the required context on every future counsel review, and would
contradict the gate's own other half, which scopes its producer to `audits/**`. One script taking
opposite scoping decisions in its two halves was the defect the narrowing resolves.

## Consequences

- Determinations are enumerable on request. Accountability under Art. 5(2) means being able to
  *demonstrate*, and documentation that cannot be enumerated cannot be demonstrated.
- The register's value now depends on its pointers resolving, which is why that is the one
  property asserted per row rather than a row-count floor.
- A new determination is two edits, not one: the canonical record, and a row here. The gate makes
  the second non-optional for anything under `audits/**`.
- The predicate is a judgement, and judgements can be wrong. The waiver list is where that
  argument happens, in a diff a reviewer sees.
- **No new Processing Activity.** PA-36 stays free; this creates a register, not a processing
  activity.

## Alternatives considered

**A section inside the Art. 30 register.** The drafted design. Rejected: it asserts by placement
that Art. 33(5) is an Art. 30 limb, and Art. 30(1)'s list is closed.

**Transcribe each determination into the register.** Rejected on the three grounds above —
drift that the repository's gates cannot detect, reproduction of a signature block without a
signature, and the misrepresentation risk of restating a sentence a later annotation narrowed.

**A discovered-set coverage assertion.** Rejected as unimplementable: no regex separates 102
screening outputs from six prose determinations, and a producer that reaches the post-mortem tree
reds on all 102.

**A runtime `security_events` table (#3686).** Not an alternative — a complement. That is a
*runtime event* surface; this is an index of *determinations*. The register's scope paragraph
disclaims the collision expressly, because the corpus must not grow two things both called "the
Art. 33(5) register".

## Related

- `knowledge-base/legal/breach-register.md` — the register this ADR governs.
- `knowledge-base/legal/article-30-2-register.md` — the separate-instrument precedent.
- `knowledge-base/legal/article-30-register.md` — §Register Maintenance pointer; counsel-review
  item 12; PA-8 §(g) Art. 33 evidentiary-chain limitation.
- `knowledge-base/legal/statutory-response-catalog.md` — the accountability-pack step, which is
  what an operator opens the day a regulator letter arrives.
- ADR-197 — a zero from a log surface is not evidence of absence. The reason PA-8 §(g) records a
  limitation on the Art. 33 evidentiary chain rather than a retention measure.
- `scripts/lint-legal-registers.sh` — the gate.
