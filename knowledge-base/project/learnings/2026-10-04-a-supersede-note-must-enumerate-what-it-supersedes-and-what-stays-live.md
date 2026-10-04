# Learning: a supersede note must enumerate what it supersedes and what stays live

## Problem

Appending a dated "Superseded" note above pre-apply text (cron-egress runbook, ADR-218) is
additions-only and reads as trivially safe. A four-seat review of PR #9487 still found four
medium defects in the note's own wording, all the same shape: the note changed what the section
is *about* and left its dependents pointing at the old subject.

- It called "the web-1 half of this section's removal trigger" fired. The trigger on the
  surviving line is a single event; the web-2 rebirth is a closing condition for the issue, not
  a half of the trigger. Result: the note and the line beneath it contradicted each other.
- "The paragraphs about X and Y still apply" named whole paragraphs when only conditional
  sentences inside them stay true; the same paragraphs also contain statements now false.
- "Paused again" was stated as a durable fact with no timestamp, in a section whose own rule is
  "read workflow state live".
- The ADR bullet said "exactly as the bullet above says"; the bullet directly above was a
  different bullet, and the intended one still claimed "the alert stays absent".

## Solution

Write the note as a list of what it supersedes (named sentences, with quotes) and what remains
true only conditionally, date every state reading with a time, and name sibling bullets by
label rather than "above". Also: two adjacent blockquotes separated by a blank line trip MD028,
so a note placed directly above an existing blockquote is a bold-led paragraph, not a blockquote.

## Key Insight

A correction's scope is a claim like any other: re-read each sentence of the note against the
section it sits in and against every line it leaves standing. Append-only protects the old
text; it does nothing for the new text's accuracy.

## Session Errors

1. **Invalid `--risk-tier` value passed to `emit-review-trailer.sh` (script rejected it).**
   Recovery: reran with `none`. Prevention: read the script's `--help`/error text for enum
   values before first use (one-off).
2. **`Grep` tool unavailable; `xxd` not installed.** Recovery: used Bash `grep`/`tail`.
   Prevention: none needed (one-off environment gap).
3. **Stop hook fired twice while waiting on background review agents.** Recovery: ended the
   turn with a `<stop>BLOCKED: ...</stop>` tag naming the pending seats. Prevention: when only
   notifications remain, state the block explicitly instead of a future-tense sentence.
4. **Wrote a planner-supplied fact ("hand-made, paused Output utilization high") into the ADR
   before measuring it.** Recovery: the history seat flagged it unverifiable; verified via the
   read-only Better Stack token (`paused=true`). Prevention: measure a fact before the first
   write, as `work` already says.
5. **Plan/tasks said "blockquote"; the landed note is a paragraph (MD028 avoidance).**
   Recovery: corrected the wording. Prevention: update the plan when an implementation choice
   deviates from its prescription.

## Tags
category: workflow-patterns
module: knowledge-base/runbooks
