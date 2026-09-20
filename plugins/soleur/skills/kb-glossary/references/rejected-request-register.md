---
title: The no-list — write discipline
applies_to: knowledge-base/project/rejected/
---

<!-- Inspired by mattpocock/skills/skills/engineering/triage/OUT-OF-SCOPE.md (MIT, Copyright (c) 2026 Matt Pocock). -->

# The no-list — write discipline

`knowledge-base/project/rejected/` holds the **rejected-concepts record**, called **the no-list** in
conversation. It exists so that a refusal survives the issue it was written on: the issue closes, the
thread scrolls away, and the reasoning would otherwise have to be rebuilt from memory the next time
the same ask arrives.

The founder-facing convention — the full field table, the naming rule, the write procedure — is
`knowledge-base/project/rejected/README.md`. This file is the discipline an agent applies when
writing to it. Read the README before the first write; read this before every write.

## One file per concept

The unit is a **concept**, not an issue and not a request. Three people asking for the same thing
produce one file with three entries in `prior_requests`, not three files. Two people asking for
adjacent things produce two files only if the refusals are genuinely different — and if they are,
each `scope` has to say where the line between them falls, because a later lookup will land on
whichever it matches first.

The corollary is the one that gets forgotten: a **mechanism** that lost a design comparison is not a
concept. "We chose SQS over a custom queue" is an architecture decision and belongs in the ADR that
made it. Filing it here converts "we picked the other tool" into "we don't do queues", which is a
far wider refusal than anybody agreed to.

## Match on the concept, never on the words

Requests arrive in the founder's vocabulary, and the vocabulary moves. *Night theme*, *dark theme*,
*low-light mode* and *stop burning my eyes* are one concept. The `aliases` field is what carries
that: it is required, and an entry whose alias list holds only a restatement of its own title is a
matching failure waiting to happen.

Write aliases in the words people actually use, including the imprecise ones. An alias is not a
synonym dictionary; it is a record of how the ask has already been phrased.

## The reason has to be durable

Before writing, test the reason against time. A refusal that turns on a circumstance is not a
refusal:

- "The architecture puts this outside the product's boundary" — durable. Write it.
- "Counsel identified liability we cannot carry in this shape" — durable. Write it.
- "This costs more than the segment it serves is worth" — durable if the arithmetic is in the entry.
- "Nobody has time this quarter" — **not durable.** That is a deferral, and the roadmap owns it.
- "The current library cannot do it" — **not durable** unless the library choice is itself the
  boundary. Otherwise it expires the day the library does.

Every durable refusal has an `instead`. If nothing goes in that field, stop: either the concept is a
rare category-level never — which is worth saying out loud, in `why` — or what is really being
refused is a mechanism, and this is the wrong record for it.

The `why`/`public_note` split exists so that the blunt version stays internal. Write `why` for the
team, at whatever length the reasoning needs. Write `public_note` as one sentence that could be
pasted into a reply without editing. An agent quotes `public_note` and never `why`.

## Never write a built feature into the no-list

This is the prohibition that protects every future lookup. When a request is declined **because the
capability already exists**, nothing goes in this directory. The record of that decision is the
closing comment naming where the implementation lives — which is exactly what the redundancy
pre-check already produced, so there is nothing new to write.

The failure is not cosmetic. An entry claiming a shipped capability is absent seeds the duplicate
check with a refusal that never happened, and every later match against that entry inherits the
error and compounds it. The guard cannot catch it either:
`scripts/lint-rejected-register.sh` proves an entry is internally consistent, not that it is true.
`redundancy_check: not-implemented` is the only compliant value precisely so that the claim is
explicit and a reviewer can re-run the `searched` lines against it.

`knowledge-base/project/rejected/2026-09-20-server-side-browser-automation.md` is the worked example,
and it is a near miss on purpose: browser automation ships, the server-side variant was refused, and
the entry's `scope` names the implemented paths so that a lookup for the broad concept reads the yes
as readily as the no.

## The redundancy pre-check is specified elsewhere

How to search for an existing implementation is **not restated here.** It is
`plugins/soleur/skills/brainstorm/SKILL.md` `#### 1.1 Research (Context Gathering)`, which already
mandates the functional-noun re-sweep and the report-where-you-looked discipline in sharper terms
than a summary would. A second copy drifts from the first, and the drifted copy is the one somebody
follows.

## An entry advises; it never acts

A match is a finding to hand a human, with the entry named and the doubt stated. It is never grounds
on its own to close, label or dispose of anything, and `deferred-scope-out` must never be applied
because a lookup matched. The README carries the two automated hops that make this the strictest
rule in the record.

Where a match is uncertain, **fail open**: surface it, say why it is uncertain, and let the human
decide. A near-match reported is cheap. A near-match acted on is a closed door nobody chose.

## Order of gates

The machine gate runs before the human gate, always:

1. Both pre-checks — is it built, has it been refused before.
2. Draft the file.
3. `bash scripts/lint-rejected-register.sh <path>`.
4. Confirmation from the founder, given by **typing the concept** rather than `y`. A single keystroke
   is a reflex; spelling out the concept is a decision.
5. Write.

Nothing about a person goes in the file at any step. A role where a role is needed, never a name:
this repository is public, and git history does not forget.
