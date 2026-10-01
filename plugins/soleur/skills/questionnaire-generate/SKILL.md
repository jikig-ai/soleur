---
name: questionnaire-generate
description: "This skill should be used when a decision needs an answer only an outside expert holds (accountant, lawyer, auditor, insurer, bank, regulator, landlord) and the founder must send them written questions with a deadline."
---

<!-- grok-harness-invoke:start -->
**Grok Build (`plugins/soleur/lib/harness.ts` `invokeSkill()`):** Read this SKILL.md in this process and run it to completion. A one-segment `soleur:<name>` in this document names a SKILL — on Grok Build, Read `plugins/soleur/skills/<name>/SKILL.md` in this process; it is not a nested tool_use. A multi-segment id such as `soleur:<domain>:<name>` names an AGENT: spawn it, never Read it, and on Grok Build spawn_subagent takes the id with its colons replaced by hyphens (`agentIdToGrokSubagentType`). **Claude Code:** Skill tool for a skill (`soleur:<name>`), Task tool with `subagent_type` for an agent. Forbidden is executing a subset, not the Read.
<!-- grok-harness-invoke:end -->

<!-- Inspired by mattpocock/skills/skills/productivity/to-questionnaire/SKILL.md (MIT, Copyright (c) 2026 Matt Pocock). -->

# Questionnaire Generate — ask the expert, not the founder

The founder is stuck on something an outside professional knows and they do not: an accountant, a
bookkeeper, a lawyer, a notary, an auditor, an insurer, a bank, a regulator, a landlord. The wrong move
is to put the question to the founder, who cannot answer it either. The right move is to write the
questions down, hand the founder one document, and let them send it.

This skill produces that document. It never sends it — the founder sends it from their own mail client,
so nothing here becomes an intermediary for anyone's correspondence.

Two entry paths, and the reliable one is the route. `soleur:go` carries a `questionnaire` row that
dispatches here directly. Separately, `.claude/hooks/pre-ask-technical-fork-gate.sh` denies an
`AskUserQuestion` whose answer is held outside the company and names this skill in the deny reason.

That hook arm is a BACKSTOP, not the main entrance, and the distinction is measured rather than
assumed: its vocabulary is a fixed list of profession nouns, so a question can be squarely in scope and
still not match. This skill's own worked example is one — "should the prepaid hosting contract be
expensed now or spread across the term?" names no profession and is ALLOWED by the hook in both of its
phrasings (measured). An earlier revision of this paragraph called the deny "the main way this skill is
reached", which is false for the very example the skill ships. That
arm has no resolution ladder — it is a single unconditional deny evaluated ahead of the authority
short-circuit — so citing a "rung" of one would be the invented-precision this repository's own
glossary discipline exists to stop. That deny is the main way this skill is reached, which is why every guardrail below is about
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

1. **What decision is blocked?** One sentence, in the founder's own words. This is the third
   allowlisted Context field and the frontmatter's `blocked_decision`, and an earlier revision of this
   step did not collect it — leaving Step 2 to claim "all three came out of Step 1" when only two did,
   and the executor to recover the third from the triggering context or from a file, which the
   allowlist forbids. Ask it; never infer it.
2. **Who receives this?** The role, and what they know that the founder does not.
3. **What has to come back?** The specific facts or decisions the founder cannot resolve alone.
4. **By when?** A date the founder names. If the founder answers with a PERIOD rather than a date
   ("before the quarter closes"), ask once for the date — do not convert it. The record's README is
   explicit that nothing derives this field, nothing rounds it and no default replaces it, so a
   derived date would be the skill inventing the one fact the follow-through sweep alarms on.

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
`redact-sentinel.sh` completely clean, because that engine matches **secrets**:

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

## Step 3 — Assemble the whole document, then apply the glossary as an outbound stop-list

1. Assemble the whole document in memory: the `## Context` paragraph from Step 2, the questions, and
   the template's remaining sections.
2. Then apply the stop-list below.

THIS STEP RUNS BEFORE THE REDACTION FLOOR, AND THE ORDER IS THE WHOLE POINT. The floor must scan the
bytes that actually go out, so nothing may edit the document after it. An earlier revision put the
floor here and the stop-list after it, which meant the stop-list rewrote text the sentinel had already
cleared — reintroducing, legitimately, the un-scanned preview the floor exists to prevent.

`knowledge-base/project/glossary.md` is the list of internal words that must not leave the repository
inside a document attributed to the founder. Read it as a stop-list here, before the redaction floor runs: if a word in
the document has an entry there, it is an internal noun and the emitted document says the plain thing
instead. Skill names, agent names, phase names, lane names and workflow nouns do not appear in a
document a founder signs.

**This is the one sanctioned knowledge-base read on the drafting path, and it is not an exception to
Step 2.** Step 2 forbids SOURCING a fact from the knowledge base into the document. This read does the
opposite: it supplies a list of words to TAKE OUT. Nothing read here can enter the document, so the
allowlist is intact. Stated explicitly because the two rules otherwise read as a contradiction — one
says "no file read on the drafting path" and this step is a file read on the drafting path.

## Step 4 — The redaction floor

Before the file is written, run the document through the redaction sentinel — the same boundary
`soleur:legal-generate` applies before it presents a draft. Run this as ONE fence: each fenced block is
a separate Bash call and shell state does not persist, so a preflight in one fence protects nothing in
the next.

```bash
# ALLOCATE THE DRAFT FIRST. Everything below operates on "$DRAFT", and an earlier revision of this
# fence referenced it four times without ever defining it — so `[ -s "$DRAFT" ]` was false on every
# run and the floor halted with `reason=draft-empty` unconditionally. A gate that always refuses is
# not a strict gate, it is an unrunnable skill, and it is worse than the unanchored path it replaced.
DRAFT="$(mktemp)" || { echo "SOLEUR_QUESTIONNAIRE_HALT reason=draft-alloc-failed"
                       echo "questionnaire-generate: cannot allocate a draft file — stopping before any draft text exists." >&2
                       exit 2; }
trap 'rm -f "$DRAFT"' EXIT INT TERM HUP

# Write the assembled document into "$DRAFT" HERE, in THIS fence, before the gate below — each fenced
# block is a separate Bash call and shell state does not persist, so a draft written in another fence
# is not visible to this one and the emptiness check below would refuse.
#
# Use a QUOTED heredoc delimiter (`<<'DOC_EOF'`). The founder's three Step 1 answers are free text and
# can contain `$(…)`, backticks or `$VAR`; an unquoted delimiter would EXECUTE those substitutions on
# the founder's machine and expand `$VAR` to empty — mutating the very text the sentinel is about to
# scan, so a secret's shape can be destroyed by the shell rather than caught by the redactor.
#   cat > "$DRAFT" <<'DOC_EOF'
#   <the assembled questionnaire, verbatim — the Step 2 Context paragraph plus the questions>
#   DOC_EOF

# PLUGIN IDENTITY (ADR-179 decision 2). `[[ -r "$SENTINEL" ]]` alone is a SHAPE check, and
# ADR-179 §(a) measured that shape as bypassable: with an ambient CLAUDE_PLUGIN_ROOT pointing at an
# attacker-chosen directory a `test -d` preflight PASSED and the hostile payload executed. Verify the
# plugin's IDENTITY, and halt in THIS arm — a sibling halt further down the fence does not make this
# check fail-closed.
[ -f "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json" ] \
  && grep -q '"name"[[:space:]]*:[[:space:]]*"soleur"' "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json" \
  || { echo "SOLEUR_QUESTIONNAIRE_HALT reason=plugin-root-unverified root=[${CLAUDE_PLUGIN_ROOT}]"
       echo "questionnaire-generate: cannot verify the Soleur plugin installation — stopping before any document is written." >&2
       echo "  Resolved plugin root: [${CLAUDE_PLUGIN_ROOT}]" >&2
       echo "  If that is EMPTY: no Soleur plugin is loaded in this session. Install it and start a NEW session — re-running here resolves the same empty root." >&2
       echo "  If it names a path: that path is not a Soleur install (a repo checkout is not an install). Run 'claude plugin update soleur@soleur-marketplace' (or the id 'claude plugin list' prints, if you added the repository directly), then RESTART Claude Code — plugin changes apply only on restart." >&2
       echo "  Do NOT hand-write and send this document instead — the allowlist in Step 2 is what makes it safe to send, and this gate is the floor under it." >&2
       exit 2; }

SENTINEL="${CLAUDE_PLUGIN_ROOT}/skills/incident/scripts/redact-sentinel.sh"
[[ -r "$SENTINEL" ]] || { echo "SOLEUR_QUESTIONNAIRE_HALT reason=sentinel-unreadable sentinel=[$SENTINEL]"
       echo "questionnaire-generate: the redaction sentinel is missing from an otherwise valid Soleur install — stopping." >&2
       echo "  Expected at: [$SENTINEL]" >&2
       echo "  The install is partial or out of date. Run 'claude plugin update soleur@soleur-marketplace', then RESTART Claude Code." >&2
       exit 2; }

# EMPTINESS IS A FAILURE, NOT A CLEAN SCAN. The sentinel exits 0 on zero bytes, so an unwritten draft
# passes this gate vacuously and the preview then presents un-scanned text. Same shape as
# legal-generate's `[ -s "$DRAFT" ]`.
[ -s "$DRAFT" ] || { echo "SOLEUR_QUESTIONNAIRE_HALT reason=draft-empty draft=[$DRAFT]"
       echo "questionnaire-generate: the draft is empty — nothing was scanned, so nothing is safe to send." >&2
       echo "  Write the document into \"\$DRAFT\" in the SAME fence as this gate, then re-run." >&2
       exit 2; }

bash "$SENTINEL" "$DRAFT"
sentinel_rc=$?

# DISPATCH HERE, INSIDE THE FENCE, AND EMIT THE VERDICT. Assigning `sentinel_rc` and dispatching in
# prose below does not work and was measured not working: an assignment is the fence's terminal
# statement so the fence exits 0 whatever the sentinel said, shell state does not persist to the next
# fence (see the note above), and — the part that matters — rc=0 and rc=2 produce BYTE-IDENTICAL
# stdout, zero bytes each, because the sentinel writes its cannot-evaluate diagnostic to stderr.
# Measured: clean rc=0/0 bytes, matches rc=1/53 bytes, unreadable rc=2/0 bytes. So a document that was
# never scanned was indistinguishable from one that scanned clean, and the "cannot evaluate -> halt"
# arm below was unreachable. That is fail-OPEN, in the one gate whose whole purpose is to fail closed.
case "$sentinel_rc" in
  0) echo "SOLEUR_QUESTIONNAIRE_SENTINEL verdict=clean" ;;
  1) echo "SOLEUR_QUESTIONNAIRE_HALT reason=sentinel-matches"
     echo "questionnaire-generate: the sentinel matched. Do NOT write and do NOT present." >&2
     echo "  The allowlist was violated upstream — fix the CONSTRUCTION in Step 2, not the output." >&2
     exit 1 ;;
  *) echo "SOLEUR_QUESTIONNAIRE_HALT reason=sentinel-cannot-evaluate rc=[$sentinel_rc]"
     echo "questionnaire-generate: the sentinel could not evaluate the draft — stopping." >&2
     echo "  An un-scanned document is not a clean one. Do not present it and do not send it." >&2
     exit 2 ;;
esac
```

The fence above emits exactly one `SOLEUR_QUESTIONNAIRE_*` marker and halts on anything but a clean
scan. For reference, the arms it implements:

- **0** — clean. Proceed.
- **1** — matches found. Do not write and do not present. The allowlist was violated upstream; fix the
  construction, not the output.
- **2** — cannot evaluate. **Halt.** An un-scanned document is not a clean one.

This sentinel is a **floor and never a ceiling**. Exit 0 means no secret was found. It does not mean
the document is safe to send — Step 2 is what makes it safe to send.

## Step 5 — Compute, preview, then take a typed confirmation

The shape is `plugins/soleur/skills/invoice/SKILL.md` S4 steps 4 and 5: compute the artifact, show the
founder what will actually go out, and take a literal typed `yes` before it becomes sendable.

1. Show the founder the recipient role, the deadline, the question list, and the `## Context` paragraph
   **verbatim** — the real bytes, not a summary of them.
2. **Append nothing after the Context paragraph.** Whatever the preview ends with is what the recipient
   reads. A line added after the confirmation is a line the founder never approved.
3. Require a single literal `yes`. Any other token — `y`, `Yes`, `yes go ahead` — re-shows the Context
   paragraph once, then aborts. There is no force flag.
4. Only then write the file.

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
(the date from Step 1 question 4), `blocked_decision` (Step 1 question 1), and **`status: draft`**.

**`draft`, not `sent`, and this is a correctness matter rather than a nicety.** This skill writes a
document; it never sends anything — the founder sends it later, by hand, from their own mail client.
So at emit time nothing is known about whether it was sent, and an earlier revision emitted
`status: sent`. [questionnaire-unanswered-8289.sh](../../../../scripts/followthroughs/questionnaire-unanswered-8289.sh)
starts its overdue clock at
`sent`, so an unsent draft became an ACTION REQUIRED on its own `needed_by` — reporting an overdue
answer to a question nobody had asked, in an unattended sweep that writes to a public issue comment.
Tell the founder, in the hand-off line, to change `draft` to `sent` when they actually send it.

`<topic>` in the filename is a two-or-three-word slug of `blocked_decision`, lower-case and
hyphenated — derived from a field Step 1 collected, never invented from the subject matter.

`## Blocked on` takes the artifact that caused the ask: a repo-relative path, or an issue reference.
If Step 1 produced no such artifact, write the plan or decision record the founder named when they
described the block; if there is genuinely none, say so in one line rather than leaving the section
empty, because the section is what lets the next session pick the thread up. The remaining conventions
for this directory, including the `## Answers` discipline, are in
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
