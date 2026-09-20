---
name: kb-glossary
description: "This skill should be used when a session settles, sharpens, or disputes the meaning of an internal term: write it into knowledge-base/project/glossary.md as a pointer to its definer."
---

<!-- Inspired by mattpocock/skills/skills/engineering/domain-modeling/SKILL.md (MIT, Copyright (c) 2026 Matt Pocock). -->

# KB Glossary — the write side of the vocabulary

Reading `knowledge-base/project/glossary.md` is a one-line habit that several skills already carry.
This skill is the other half: the discipline that **changes** the glossary at the moment a session
works out what a word means, so the next session inherits the answer instead of re-deriving it.

The format contract is [glossary-format.md](./references/glossary-format.md) — entry shape, the four
admission tests, the pointer-not-restatement rule, and the miss path. Read it before writing an
entry; do not re-derive the rules from the entries already in the file.

## When to self-invoke

Invoke this skill in the same turn, without being asked by name, when any of these happens:

- A term the session is using **conflicts with an existing entry**. Say so immediately, quote both
  readings, and ask which one holds.
- A term is **fuzzy or overloaded** and the work is about to commit it to a file. Propose one precise
  term and name what the others would have meant.
- The code and the conversation **disagree** about a word. Surface the contradiction rather than
  picking the reading that makes the sentence work.
- A session **settles** a word — in a brainstorm, a plan review, a compound pass, an ADR argument.
  That is the moment the entry gets written.
- An artifact had to **hedge** on an ambiguous term because the glossary had no entry (the miss path).
  The hedge stays in the artifact; the candidate entry comes here.

Do **not** invoke it to look a word up, to restate a definition that already exists elsewhere, or to
record a word that only one skill uses. Reading is the consumers' pointer, not this skill.

## The write discipline

1. **Write inline, not later.** Update the glossary in the turn the word is settled. A batched entry
   is an entry that never lands, and the reasoning that justified it is gone by then.
2. **Point, never paraphrase.** Find the file that owns the meaning and give its path with an anchor.
   If nothing owns it, the fix is a definer in the file that owns the behaviour — then an entry
   pointing at it.
3. **Apply all four admission tests** from the format contract. Three of four is a candidate; record
   the hedge in the artifact and leave the glossary alone.
4. **Disambiguate rather than choose** when a word genuinely carries several senses here. One body per
   sense, each with its own path. A single-sense entry for an overloaded word reads as settled and
   sends the next reader to the wrong file.
5. **Steer with `_Avoid_`.** When two words compete for one concept, pick one and list the loser. A
   name that shortens in speech back into the banned word has not solved anything.
6. **Move `last_reviewed`** whenever the review happens, even when it changed nothing — otherwise an
   old date cannot be told apart from an unread file.

## Scope — it is a glossary and nothing else

The artifact holds terms and the paths that settle them. It is not a spec, not a design note, not an
implementation record, and not scratch space for anything that fitted nowhere else. Every one of
those grows the file an agent loads at decision time and none of them makes a word mean more.

Two neighbours it is explicitly not, and the glossary itself says so by path: the public marketing
glossary page, and the founder-facing brand lexicon. Never add an internal machinery noun to either.

## Siblings

- A **rejected concept** is not a term. Its record is the no-list, and the write contract for that is
  [rejected-request-register.md](./references/rejected-request-register.md).
- `soleur:operator-rephrase` reads the same entries in the opposite direction — as the stop-list of
  internal words that must be translated before the founder sees them.
