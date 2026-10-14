# A comment that reproduced the call shape became phantom data

**Issue:** #7696 / #7665 · **PR:** #9736 · **Date:** 2026-10-07

## Problem

Cutting ~7k Better Stack rows/day across two emitters went cleanly on the code side —
the flip FSM's `noop-*` terminal heartbeat gained a 300s mtime-stamp throttle, and
`resolveOrigin`'s rejection warn gained per-origin once-per-process dedupe. The defect
worth recording was in the *comment*.

While documenting why the throttle lives inside `emit_state` rather than a LUKS-style
`emit_noop` wrapper, I wrote the extracted call form verbatim into the comment:
`emit_state <ec> <dbsize> "<reason>"`. The cross-file parity extraction in
`cutover-inngest-workflow.test.sh` greps `emit_state [^ ]+ [^ ]+ "[^"]*"` over the RAW
source — comments are not stripped for that scan — so the comment parsed as a call site
and injected the literal string `<reason>` into the emitter's reason set. Two parity
assertions reddened (`missing: <reason>`), correctly and with a confusing message.

The suite caught it exactly as designed: 1038/2 red → reworded the comment to drop the
quoted shape → 1040/0 green.

## Why it is a class, not an instance

This repo derives contract surfaces by shape over raw source in several places (the
emitter-reason extraction, the seam-set tripwire, the gate-position anchors). Every such
derivation treats prose that reproduces the shape as DATA. The symmetric lesson — already
learned — is "a comment can satisfy a presence grep, so strip comments before reading";
this PR demonstrates the complement on the producer side: **a comment can MANUFACTURE a
match in a raw-source derivation, so never write the anchored call form inside the file
the anchor greps.** When you must name the shape in prose, break one element the regex
requires (drop the quotes, drop the arg count) so the text explains without matching.

## Prevention

**Prevention:** When documenting WHY a call site is shaped as it is, quote the extracting
test's *name* and describe the shape in words, not the literal pattern. Before committing
a comment that contains a function name plus a quoted argument, check whether any sibling
test derives data from that file with a raw grep — `grep -rn 'oE.*"'` on the test dir for
the function name finds the extractor in seconds.

## Session Errors

1. `doppler-injection-bound.test.sh` carries a HAND-TRANSCRIBED copy of Guard 1's unset
   list (`GUARD1_UNSET` + cardinality pin); adding a seam to the argv gate reds it until
   the copy is updated. Not a defect — the file documents "this copy moves with it" —
   but it is a recurring two-edit ritual worth knowing before the first suite run.
   **Prevention:** when the flip FSM gains a `CUTOVER_*`/`INNGEST_CUTOVER_*` read, update
   `GUARD1_UNSET` in the same commit — the suite failure is the reminder, not a surprise.
2. A plan premise inherited from issue text (`FLIP_LIVENESS_SINCE` "env-overridable") was
   stale — the value is a deliberate literal pinned by test. Verified against the source
   before designing around it. **Prevention:** constraints quoted from issue bodies are
   dated claims; re-read the constant's own comment block before planning around it.
3. GitHub GraphQL could not resolve PR #7674 (it is an issue, not a PR) — a one-off
   lookup error, no action.
