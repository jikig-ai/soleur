---
name: operator-rephrase
description: "This skill should be used when the last message did not land: say it again in short plain sentences, with no jargon, file paths or issue numbers."
---

<!-- Inspired by mattpocock/skills/skills/productivity/wait-what/SKILL.md (MIT, Copyright (c) 2026 Matt Pocock). -->

# Operator Rephrase

The previous message did not land. Say the **same thing** again, in a register the operator can act
on. This is a restatement, not an escalation: no new facts, no extra detail, no lecture. If the
content was wrong, fix the content — that is a different job than this one.

## Register

As defined in [operator-digest](../operator-digest/SKILL.md) §Register. Read it there; it is not
restated here, because a second copy drifts from the first.

### Delta from `operator-digest`

Three differences, and only these:

- **One message, not a document.** The output is the immediately preceding message said again — not
  a section, not a report, not a digest.
- **Synchronous.** Emit the rephrasing in the current turn. The digest is a scheduled headless
  artifact; this is a reply.
- **The business-consequence rule does not apply.** The digest cuts every line that does not state a
  business consequence or an owner action. That rule would mangle an in-the-moment restatement of a
  technical fact the operator asked about. Keep the fact; change only how it reads.

## How to write the restatement

The discipline is **influenced by ASD-STE100 Simplified Technical English**. This skill does not
claim conformance to that standard — there is no controlled vocabulary in this repository to bind it
to, and no gate that could check the claim. What is adopted is the checkable part:

1. Write short sentences. One idea per sentence.
2. Give one instruction per sentence. Do not chain two actions with "and then".
3. Use each word in one sense. Pick the everyday sense and keep it for the whole message.
4. Write in the active voice. Name who does the thing.
5. Remove jargon, file paths, issue numbers, PR numbers, and command names. Name the effect instead
   of the artifact that produces it. **Exception: keep any literal the operator must type, click or
   paste** — a command to run, a button label, a value to enter. Put it alone on its own line,
   unchanged; the sentences around it say what it does. A restatement that deletes the one string
   the operator needs has removed the action along with the jargon.
6. Open with the outcome. Put the reason after it, if the reason is still needed.

## Vocabulary

**v1 ships with no vocabulary source, and that is the durable state.** There is no repository
glossary to draw approved terms from, so rule 3 above is satisfied by choosing plain everyday words,
not by looking a term up. A repository glossary is a separate piece of work tracked in **#8289**; if
one lands later, this skill can cite it then. Do not invent one here, and do not point at
`plugins/soleur/docs/pages/glossary.njk` — that is marketing surface, its entries are category terms
rather than operational ones, and it is a Nunjucks template rather than readable plain text.

## When to self-invoke

Invoke this skill in the same turn, without being asked by name, when the operator's reply is one
of these shapes — each is "that did not land", not a new question:

- "what?", "huh?", "sorry?"
- "in plain English", "in normal words", "without the jargon"
- "I don't follow", "I don't understand", "lost me"
- "say that again", "come again", "one more time"
- "what does that mean for me?", "so what do I do?"

Do **not** invoke it when the operator asks for *more* detail, disputes a fact, or asks a follow-up
question — those are new answers, not restatements.

## Stop conditions

- Stop after one restatement. If that one also does not land, ask which part did not land rather
  than rephrasing a third time.
- Do not apologise at length. One short acknowledgement at most, then the restatement.
- Do not change the decision, the recommendation, or the facts while rephrasing them. A restatement
  that says something different is a new answer wearing a rephrasing's clothes.

## Siblings

`soleur:operator-digest` is the scheduled weekly counterpart: same register, batched, written to a
file rather than said in a turn.
