---
name: questionnaire-generate
description: "This skill should be used when a decision needs an answer only an outside expert holds (accountant, lawyer, auditor, insurer, bank, regulator, landlord) and the founder must send them written questions with a deadline."
---

<!-- Inspired by mattpocock/skills/skills/productivity/to-questionnaire/SKILL.md (MIT, Copyright (c) 2026 Matt Pocock). -->

# Questionnaire Generate — ask the expert, not the founder

The founder is stuck on something an outside professional knows and they do not: an accountant, a
bookkeeper, a lawyer, a notary, an auditor, an insurer, a bank, a regulator, a landlord. The wrong move
is to put the question to the founder, who cannot answer it either. The right move is to write the
questions down, hand the founder one document, and let them send it.

This skill produces that document. It never sends it — the founder sends it from their own mail client,
so nothing here becomes an intermediary for anyone's correspondence.

`.claude/hooks/pre-ask-technical-fork-gate.sh` routes here. Its external-expert arm denies the
`AskUserQuestion` that would have gone to the founder and names this skill as rung 5 of its resolution
ladder. That deny is the main way this skill is reached, which is why every guardrail below is about
protecting a founder who did not ask for the document and will not audit it.

## What the document is

A list of questions from a founder. It is not a position, not an analysis, not advice, and not a
completed brief. The emitted document says so in its own opening lines, and that self-description is
load-bearing in two directions: it stops the recipient reading a guess as a claim, and it keeps
`docs/legal/disclaimer.md` §1.3 true, because nothing produced here is offered as professional advice.
It routes the founder **to** a professional rather than standing in for one.

The document also makes no promise about what the recipient does with it. Do not write, in the
founder's voice, any undertaking about confidentiality, retention or handling on the recipient's side.
The founder cannot warrant another party's behaviour.

## Step 1 — Interview the send, never the subject

Exactly three questions to the founder, and all three are about the send:

1. **Who receives this?** The role, and what they know that the founder does not.
2. **What has to come back?** The specific facts or decisions the founder cannot resolve alone.
3. **By when?** A date the founder names.

That is the whole interview. **If a question about the subject matter can usefully be put to the
founder, this skill had no reason to run** — the founder's not knowing the subject is the precondition
for being here. Aim every question at the distance between what this recipient already holds and what
the founder is missing — never at the founder.

Then write the questions. One idea per question, never compound, most consequential first, with a blank
quote line under each for the answer, and a single "why I am asking" line only where the question reads
two ways without it. Use the shape in
[questionnaire.template](./references/questionnaire.template).

## Step 2 — Assemble `## Context` from an allowlist

The Context paragraph carries **three things and nothing else**: the decision being made, the
recipient's role, and the deadline. All three came out of Step 1. Build the paragraph by putting those
three fields together.

**Do not read the knowledge base on the drafting path.** Not for colour, not for background, not to
"make the ask land better". No file read, no grep, no prior artifact, no summary of the project.

**Never draft a fuller paragraph and then remove what should not be in it.** That is the #7331 failure
shape: a draft-then-redact pipeline with every gate green and the thing that mattered still in the
document.

### Why an allowlist and not a scan

Because a scan cannot hold this line and a construction rule can. Every one of the following passes
`plugins/soleur/skills/incident/scripts/redact-sentinel.sh` completely clean, because that engine
matches **secrets**:

- the all-in monthly burn and the break-even user count from `knowledge-base/finance/cost-model.md`
- a `PIVOT` validation verdict
- the alpha-user count, and that user's name
- competitor names
- roadmap phases that have not shipped
- issue and PR numbers, file paths, agent and skill names
- anything under `knowledge-base/legal/`

None of it is a credential. All of it is reachable today by any skill that summarises the knowledge
base. And per `hr-third-party-content-grep-on-undertaking`, *a PII-scoped gate PASSES on filenames,
directory listings and repo internals — publication is a different predicate*. So the protection cannot
be "scan the draft and remove what looks sensitive". It is "the paragraph is assembled from three named
fields, so there is nothing to remove".

A future session will read this section and think the rule is over-strict. It is not: the allowlist is
the only part of this design that survives contact with a document written to be sent.

## Step 3 — Compute, preview, then take a typed confirmation

The shape is `plugins/soleur/skills/invoice/SKILL.md` S4 steps 4 and 5: compute the artifact, show the
founder what will actually go out, and take a literal typed `yes` before it becomes sendable.

1. Assemble the whole document in memory.
2. Show the founder the recipient role, the deadline, the question list, and the `## Context` paragraph
   **verbatim** — the real bytes, not a summary of them.
3. **Append nothing after the Context paragraph.** Whatever the preview ends with is what the recipient
   reads. A line added after the confirmation is a line the founder never approved.
4. Require a single literal `yes`. Any other token — `y`, `Yes`, `yes go ahead` — re-shows the Context
   paragraph once, then aborts. There is no force flag.
5. Only then write the file.

## Step 4 — The redaction floor

Before the file is written, run the document through
`plugins/soleur/skills/incident/scripts/redact-sentinel.sh`, the same boundary
`plugins/soleur/skills/legal-generate/SKILL.md` applies before it presents a draft. Dispatch on the
exit code, fail-closed:

- **0** — clean. Proceed.
- **1** — matches found. Do not write and do not present. The allowlist was violated upstream; fix the
  construction, not the output.
- **2** — cannot evaluate. **Halt.** An un-scanned document is not a clean one.

This sentinel is a **floor and never a ceiling**. Exit 0 means no secret was found. It does not mean
the document is safe to send — Step 2 is what makes it safe to send.

## Step 5 — The glossary as the outbound stop-list

`knowledge-base/project/glossary.md` is the list of internal words that must not leave the repository
inside a document attributed to the founder. Read it as a stop-list before the preview: if a word in
the document has an entry there, it is an internal noun and the emitted document says the plain thing
instead. Skill names, agent names, phase names, lane names and workflow nouns do not appear in a
document a founder signs.

## Step 6 — Emit

Write to:

```text
knowledge-base/project/questionnaires/YYYY-MM-DD-<recipient-role>-<topic>.md
```

**Strip the first line of the template.** Line 1 of
[questionnaire.template](./references/questionnaire.template) is a provenance comment for this
repository, and the emitted document is a founder's correspondence rather than a Soleur artifact — so
the emitter drops line 1 and the document starts at the frontmatter fence. The emitted file carries no
vendor mark of any kind.

Frontmatter, all four fields required: `recipient_role` (a role, never a person's name), `needed_by`
(the date from Step 1 question 3), `blocked_decision`, and `status: sent`. The conventions for this
directory, including the `## Answers` section and the `## Blocked on` back-pointer, are in
`knowledge-base/project/questionnaires/README.md`.

## Voice

Brand-guide **General register** (`knowledge-base/marketing/brand-guide.md` → Audience Voice Profiles).
Over the emitted document:

- First-person singular. "I need", "my accountant". Never `we` or `our` for the sender — a solo founder
  writing as a committee reads as a form letter and invites a form answer.
- **Jikigai** wherever a legal entity is named. The word **Soleur** never appears. The founder is
  writing to their accountant, not introducing their tooling vendor.
- No emoji.
- No hedges. `might`, `could`, `potentially` and `perhaps` are absent. A hedged question invites a
  hedged answer, and the founder gets one async round-trip.
- Plain language, no jargon without an immediate definition in the same sentence.

## Must refuse

Each of these ends the step and routes to a founder-fix, exactly as
`plugins/soleur/skills/invoice/SKILL.md` S6 refuses to invent an invoice fact:

- **Any fact about the founder's business the founder did not say out loud in this session.** No
  knowledge-base enrichment, no inferred figures, no "based on your roadmap", no rounded estimate.
- **Claimed knowledge the founder does not have.** No "as we discussed", no invented prior
  correspondence, no implied earlier call. The founder has to be able to answer any follow-up the
  recipient asks about their own document, and every sentence in it is a sentence they may be asked
  about.
- **Forged attribution.** No signature block, job title, letterhead, address or credential the founder
  did not supply.
- **A question whose answer the founder is obliged to already hold.** A registration number, a fiscal
  year end, a filing date: asking an outsider for those is the founder's own record-keeping gap
  wearing a questionnaire's clothes. Route it to the founder as a fix.

## The return leg

The document is half the mechanism. The other half is that nobody has to remember it.
`status: sent` plus the founder's own `needed_by` is what
[questionnaire-unanswered-8289.sh](../../../../scripts/followthroughs/questionnaire-unanswered-8289.sh)
reads on the follow-through sweep: still `sent` and past its date means the founder is waiting on an
answer. `## Blocked on` points back at the artifact that caused the ask, so the next session finds the
open question instead of re-deriving it.

That probe runs on the sweeper and **never inside this skill**. A skill that reports on its own output
is reporting on itself (#6737, ADR-126).

## Sharp edges

- **Three interview questions, not four.** Adding a subject question is the most tempting change here
  and it defeats the skill: the founder does not have that answer, which is why the document exists.
- **The preview is the document, byte for byte.** A preview that paraphrases the Context paragraph
  confirms something the founder never saw.
- **`redact-sentinel.sh` going green is not approval.** It is the floor. Step 2 is the design.
- **This skill sends nothing.** Emitting to a mail API, an issue comment or any outbound channel would
  make the Plugin an intermediary for third-party correspondence, which
  `docs/legal/data-protection-disclosure.md` §2.1(d) says it is not. The founder sends the file.
