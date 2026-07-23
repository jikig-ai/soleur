# Learning: An acceptance criterion that IS a literal-string grep is a vacuous sweep for a semantic property

## Problem

Issue #6805 fixed a now-false rationale ("the Bash tool does NOT persist CWD
across calls") at two `SKILL.md` sites and shipped acceptance criterion AC5:

> After the change, `git grep -n "persist CWD" -- plugins/ .claude/` returns
> zero stale assertions.

That grep passed (zero rows) with the two named sites fixed — but a **third**
site asserting the *same* false mechanism survived it, because it was worded
differently: `work/SKILL.md:997` justified "relying on prior CWD" with the
parenthetical **"(shell state doesn't persist)"**. Same semantic claim (CWD
reliance is unsafe *because state does not persist*), different surface string,
so a grep pinned to the literal `persist CWD` could never see it. It was caught
only by a semantic review read, not by the AC.

## Root cause

The property the issue actually cared about is semantic — "no site justifies a
CWD instruction with a false persistence claim." AC5 encoded it as a search for
one *surface form* of that claim. A literal-string grep is a sound check for
"is this exact string gone" and a **vacuous** check for "is this idea gone":
the idea's synonyms pass it for free. This is the acceptance-criterion instance
of the already-documented `cq-assert-anchor-not-bare-token` /
"sweep the SEMANTIC quantity, not its formatted representation" class — here the
too-narrow anchor lived in the *issue's own AC*, which is exactly why it read as
rigor and shipped.

## Solution

- Fixed the surviving twin inline during review (`work/SKILL.md:997` reworded to
  the accurate CWD-*drift* rationale, matching the two primary sites).
- When an AC is a `grep` for a literal, ask "what OTHER wordings express the same
  claim?" and either widen the pattern to the concept's vocabulary
  (`grep -iE "persist(s|ence)?.{0,20}CWD|CWD.{0,20}persist|shell state.{0,20}persist"`)
  or pair the mechanical grep with a semantic-review pass whose job is the
  synonyms the grep cannot enumerate.

## Key Insight

A literal-string acceptance grep proves the *string* is gone, never the *claim*.
For a "remove every assertion of idea X" task, the greppable AC is necessary but
not sufficient — the differently-worded twin is the modal escape, and a
semantic-review pass (not a second grep) is what closes it. Treat any AC of the
form `grep "<phrase>" == 0` as a lower bound on the sweep, and name the concept's
other surface forms before trusting it.

## Session note (one-shot pipeline)

The plan+deepen subagent stalled (600s stream watchdog, no on-disk artifact) on
this trivial, fully-specified docs fix. one-shot's documented inline
plan-fallback path handled it correctly — recorded here only to confirm the
fallback is the right disposition for a stalled planning subagent on a
mechanical change, not a signal to retry the heavy subagent.

## Tags
category: best-practices
module: review, acceptance-criteria
related: cq-assert-anchor-not-bare-token, cq-cite-content-anchor-not-line-number
