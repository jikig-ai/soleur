---
last_reviewed: 2026-09-20
review_cadence: biannual
---

# Project Glossary

The words this repository's skills and agents hand to each other, and the file that settles each one.
An agent reads this before it commits a word that names a concept — in a brainstorm, a plan, a spec,
an ADR or a digest — so that two sessions a month apart mean the same thing by the same noun.

Every entry is a **pointer**. The body names the file that owns the meaning and gives its path; it
does not restate the definition, because a second copy of a definition is a second thing that can go
stale. Follow the pointer when the detail matters.

## What this file is not

- Not `plugins/soleur/docs/pages/glossary.njk`. That is the **public** marketing glossary: category
  terms, written for someone deciding whether to use Soleur, and a Nunjucks template rather than
  readable text. Its term list is pinned by a rendered-page guard, so internal nouns must never be
  added to it.
- Not `knowledge-base/marketing/brand-guide.md`. That owns the **founder-facing** lexicon — the words
  the founder reads, and the jargon those words replace.

This file is neither of those. It is machinery vocabulary for the agent that loads it at decision
time, and a word the founder should ever see belongs in the brand guide instead. The full contract —
entry shape, the pointer rule, and what to do when the word you need is missing — is
`plugins/soleur/skills/kb-glossary/references/glossary-format.md`.

## What earns an entry

All four, or it is a candidate rather than an entry:

1. The word appears in at least three skill or agent definitions an agent reads while deciding.
2. Some file already settles it, and that file is worth pointing at. If nothing does, write the
   definer first.
3. Two honest readings send an agent down different paths, and the difference reaches a committed
   file. Name that wrong commit, or the ambiguity is only aesthetic.
4. It is not founder-facing.

## Terms

**Register**:
Four senses here, and they do not share a file. Disambiguate before using the word bare.

- _Compliance artifact_ — a counsel-reviewed record with an inclusion predicate, one per obligation:
  the seven files matching `knowledge-base/legal/*-register.md`, plus
  `knowledge-base/engineering/architecture/nfr-register.md`. This is the dominant local sense and the
  reason the word is not available for anything new.
- _Domain-model record_ — the entity and business-rule tables in
  `knowledge-base/engineering/architecture/domain-model.md`, whose drift against the code is checked
  by `plugins/soleur/skills/preflight/SKILL.md` §Check 11: Domain-Model Register Drift.
- _Prose voice_ — how a message is pitched to its reader, defined once in
  `plugins/soleur/skills/operator-digest/SKILL.md` §Register (how to write) and reused by
  `plugins/soleur/skills/operator-rephrase/SKILL.md`.
- _The verb_ — to enter something into an existing register, or to declare a component to a manifest
  (a skill into the docs categories, a flag into the runtime map). Always say which one.

_Avoid_: "register" and "store" as names for the record of concepts that were considered and
declined — that artifact is **the no-list** in prose and the **rejected-concepts record** where a
formal noun is needed. Both banned synonyms collapse back into the compliance sense above, and the
shortened form of either is exactly the word this entry exists to protect.

**Lane**:
A pre-declared route through a fan-out, chosen from the request rather than negotiated: the domain
rows and their matching signals in
`plugins/soleur/skills/brainstorm/references/brainstorm-domain-config.md` §Lane Inference.
Inference picks the lane; it does not invent one.

**Shard**:
A registered slice of the test corpus that the runner can execute on its own — a `TEST_GROUP` whose
suite list is fixed, partitioned across CI legs by `SCRIPTS_SHARD=k/N`. Defined by the runner itself,
`scripts/test-all.sh` (§Shard partition), and consumed by
`plugins/soleur/skills/work/SKILL.md` §Touched-Shard Exit Gate, which is what makes "run your touched
shards" a bounded instruction.

_Avoid_: using it for a slice of implementation work handed to one agent. That reading turns "the
shards are green" into a claim about delegates finishing rather than suites passing, and the two are
independently false. Name the delegate and the files instead.

**Ratchet**:
A pinned number that may only move in the direction that reduces it, read from the merge base so a
diff cannot raise its own limit. `scripts/lint-skill-body-budget.py` carries the canonical statement
in its module docstring — the ceiling rows, why the base and not the working tree, and _one-sided by
design_. A guard that reds when a count falls is not a ratchet; it is a pin.

**WORM**:
Write-once-read-many, in two distinct local shapes:

- _Retention floor on object storage_ — bucket lock rules that forbid deletion for a stated minimum
  period, described in
  `knowledge-base/engineering/operations/runbooks/cla-signature-evidence-retrieval.md`.
- _Append-only rows in Postgres_ — tables whose update and delete paths are refused by triggers, with
  erasure handled by anonymising rather than deleting. See
  `knowledge-base/engineering/architecture/domain-model.md` §Business Rules; the flag and role skills
  mean this sense when they require an audit row appended **before** the mutation.

_Avoid_: calling an append-only markdown log WORM. Nothing enforces it there, and an instruction to
"write a WORM audit" is an instruction to call the audit path that refuses overwrites, not to add a
line to a file.

**Soak**:
An observation window after a deploy, during which a close criterion is not yet decidable — "still
zero after seven days" rather than "zero now". The gate that detects a declared soak and the
enrollment it requires are in `plugins/soleur/skills/ship/SKILL.md` §Soak-Gated Follow-Through
Enrollment Gate, over the convention in
`knowledge-base/engineering/operations/runbooks/followthrough-convention.md`. A soak that relies on
somebody remembering to look is not a soak.

**Rung**:
One ordered step of a named fallback ladder — and the entry is the instruction, not a definition:
**name the ladder**. The ladders differ, so a bare "rung 5" resolves to nothing:
`plugins/soleur/skills/reproduce-bug/SKILL.md` numbers ten ways to build a reproduction loop, from a
failing test to a scripted browser session; `plugins/soleur/skills/operator-bootstrap/SKILL.md` climbs credential sources
and ends at a prompt; `plugins/soleur/skills/compound/SKILL.md` steps a rule through trim, migrate
and retire. Write "rung 4 of the reproduction ladder", never "rung 4".
