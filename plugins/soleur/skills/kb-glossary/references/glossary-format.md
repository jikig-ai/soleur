<!-- Inspired by mattpocock/skills/skills/engineering/domain-modeling/CONTEXT-FORMAT.md (MIT, Copyright (c) 2026 Matt Pocock). -->

# Glossary format

The contract for `knowledge-base/project/glossary.md`: what an entry looks like, what earns one, and
what a reader does when the word they need is not there. The artifact is written to this file, not
the other way round.

## Entry shape

```markdown
**Term**:
One or two lines saying which file settles this word, and the path to it.
_Avoid_: word, word
```

Three parts, in this order:

- **The term**, in bold, in the singular, spelled the way the repository already spells it.
- **The body**, which names the file that settles the meaning and gives its repo-relative path. An
  anchor (`path/to/file.md` §Heading) beats a bare path, because the reader lands on the sentence
  rather than on a 1,500-line document.
- **`_Avoid_`**, listing the words that are not to be used for this concept. Omit the line when
  there is nothing to steer away from; never leave it empty.

When a word carries more than one legitimate meaning here, the entry is one body per sense, each
with its own definer path, each sense labelled. A single-sense entry for a genuinely overloaded word
is worse than no entry: it looks settled and points a reader at the wrong file.

## An entry is a pointer, never a restatement

If any file in the repository already contains the sentence that settles a term, the entry's job is
to hand over the path and stop. A second wording of the same definition is a second thing to keep
true, and the copy that drifts is always the one nobody reads on the way to the code.

So: no entry paraphrases its own definer, no entry carries implementation detail, and a term with no
definer anywhere does not get one invented here — it gets a definer written in the file that owns
the behaviour, and then an entry pointing at it.

## What earns an entry

All four must hold. Three of four is a candidate, not an entry.

1. **Load-bearing breadth** — the word appears in at least three skill or agent definitions that an
   agent reads while deciding what to do. Below that, the one file it lives in defines it well
   enough.
2. **No existing definer, or a definer worth pointing at** — if an "an X is …" sentence exists, the
   entry is that path. If nothing anywhere settles the word, fix that first.
3. **A divergence you can name** — two honest readings send an agent down different paths, and the
   difference ends up in a file that gets committed. "It's a bit ambiguous" does not qualify: name
   the wrong commit the wrong reading produces.
4. **Not founder-facing** — if the founder should ever read the word, it belongs in the brand guide's
   `## Voice` section instead, which is where the founder-facing register and the audience voice
   profiles live. (There is no section literally called "lexicon" — an earlier revision of this line
   pointed at one, and a pointer whose target does not exist is precisely the defect this file exists
   to prevent.) This glossary is machinery vocabulary, written for the agent that loads it at
   decision time.

A term also has to be shared traffic: it belongs here only when two or more skills or agents hand it
to each other. A word one skill uses privately is that skill's business.

## The consumer pointer (defined once, here)

Five consumers carry a one-line read-pointer at `knowledge-base/project/glossary.md`: `brainstorm`,
`plan`, `spec-templates`, `architecture` and `operator-digest`. The instruction those lines cite is
this one, and it is stated only here so that five copies cannot drift apart:

> Before you commit a word that names a concept — in a brainstorm, a plan, a spec, an ADR or a
> digest — check it against `knowledge-base/project/glossary.md`. If the word has an entry, follow
> its pointer and use the sense that file settles; if the entry lists the word you were about to
> write under `_Avoid_`, use the entry's term instead. If the word is materially ambiguous and has
> no entry, take the miss path below.

`knowledge-base/project/constitution.md` carries the same pointer once, so a skill that reads the
constitution inherits it without a per-file edit.

**The founder-facing direction.** `operator-digest` and `operator-rephrase` read the same entries as
a **stop-list**: an entry's term is a word the founder must not be shown, and the plain clause that
opens the entry — or each of its senses — is what to say instead. The path in the body is for the
agent and never reaches the founder. This does not make the glossary a source of approved founder
words; plain words are chosen, not looked up.

## The miss path

A term that is materially ambiguous and absent from the glossary is a **candidate entry**, and the
absence is never a reason to guess quietly.

Do all three:

1. **Pick a reading and say which one.** Write the artifact in one sense, and state in the artifact
   which sense you took. A committed document that silently chose is the failure this whole
   mechanism exists to prevent.
2. **Name the ambiguity where the work lands**, in the committed artifact itself — not in the
   session, which nobody re-reads. One sentence: the word, the two readings, and which one this
   document uses.
3. **Propose the entry** if the four tests above pass, by invoking `soleur:kb-glossary` in the same
   session. If they do not all pass, the hedge in the artifact is the whole fix; do not grow the
   glossary to record a one-off.

A missing entry is cheap. A confident entry for a word nobody had settled is expensive, because
every later reader treats it as decided.

## Housekeeping

- The file's frontmatter carries `review_cadence` and `last_reviewed`. A review that changes nothing
  still moves `last_reviewed`, so an old date means unreviewed rather than unchanged.
- Entries are written inline as soon as a session settles a word. Batching them to the end of the
  work is how they get dropped.
- The glossary is a glossary. It is not a spec, not a design note, not a place to park anything that
  did not fit elsewhere. A rejected *concept* is not a term and does not belong in it; that record
  lives in the no-list, whose write contract is [rejected-request-register.md](./rejected-request-register.md).
