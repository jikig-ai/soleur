# Learning: a producer check was true of the system and false of the population the hook registered in

## Problem

PR #12435 (Ref #11076) added a flag-gated, annotate-only `PostToolUse(Bash)` hook that frames read-style `gh` output as untrusted text. The plan
did the check the 2026-10-25 learning prescribes for a framing guard ("name the producer, or it ships inert"): it cited `safe-bash.ts` auto-admitting
`gh issue|pr view`, `GH_TOKEN` minted into the sandbox env, and the image installing `gh`. Every clause was true of the hosted system. The hook, as the
operator specified it, registers only under `webEgress && classify-flag`, and in a web-egress session the sandbox env deny census removes `GH_TOKEN`
and the session prompt tells the model that in-sandbox `gh` fails at auth. So the producer exists, and it does not exist in the population the hook
is registered for. A CTO ruling made the same day (row 8, "out of this slice: a session with a gh token but no web egress") rested on the same
unexamined overlap. One review seat (agent-native) found it; three more confirmed it independently.

Second, separate defect class: the tokenizer and its bounded fallback scan used different grammars (the fallback split tokens on whitespace only), so
the fallback, whose whole job is to fail toward annotating, failed toward silence for a `gh` glued to `;`, `(`, `$(` or a backtick. The review fix then
conditioned the fallback trigger on a derived flag (`!parsed.ghSeen`) and re-opened the same hole for any script that ran another `gh` first; four of
five fix-round seats found that regression of the fix.

## Solution

- Kept the operator-stated predicate (an acceptance criterion), corrected the plan's producer sentence, and rewrote the ADR addendum to state the
  reach first ("near zero until registration is widened; a low count cannot tell working from inert") and to tie the enablement capture precondition
  to the widening decision, which is recorded as an open `operator (scope)` row rather than decided by the agent.
- Fallback scan splits on the tokenizer's own separators and skips backslash-newline; the trigger no longer depends on any earlier-`gh` flag and fires
  on any quote character or backslash-newline in a multi-line command. Every guard added in review was mutation-checked in the same session.

## Key Insight

A producer check must be evaluated over the **population the guard registers in**, not over the system: list the registration predicate's conjuncts,
and for each downstream fact the check cites ("the token is minted", "the tool is installed") ask whether it still holds once the predicate is true.
A predicate that gates on capability A (web egress) can switch off capability B (credentials) that the cited producer needs; the two facts live in
different files and nothing compares them. Separately: when a fallback exists to fail toward the safe direction, it needs the SAME grammar as the
primary path and its trigger must not condition on state the primary path derived from the same input.

## Session Errors

1. **Plan's producer check true of the system, false of the registered population; CTO ruling 8 built on the same premise** — Recovery: review seats
   found it; ADR/plan corrected, scope question routed as an operator row. **Prevention:** in plan Phase 2 for any flag/egress-gated registration,
   write the producer check as a table of (cited fact, file, still true when the predicate holds?) and run the grep for each row.
2. **Fallback scan used a narrower grammar than the tokenizer** — Recovery: split on the same separators; rows per separator. **Prevention:** when a
   design has a "decide / else bounded fallback" pair, derive the fallback's token boundaries from the primary's separator set in one shared constant.
3. **My review fix conditioned the fallback on `!parsed.ghSeen` and re-opened the hole for scripts with an earlier gh** — Recovery: dropped the
   conjunct; added the earlier-gh row; mutation-checked. **Prevention:** for every conjunct added to a fail-safe trigger, fixture the state where only
   that conjunct flips.
4. **Mutation-battery restore used `ls -d /var/tmp/mut2.* | tail -1`, which matched a stray file, so the SUT stayed mutated after one run** —
   Recovery: restored from the echoed backup path; `diff -q` caught it. **Prevention:** reuse the `BAK=` path echoed in the same session; never
   re-glob a scratch directory name in a later call.
5. **Running `eslint-config.test.ts` in one vitest invocation with `agent-outer-wrap.test.ts` failed once** (ESLint walked the app tree while that suite
   created and removed `.aow-bundle-*`); passes alone, 15/15. Different subsystem, no tracker filed (brief forbids filing). **Prevention:** run the
   eslint ratchet suite alone.
6. **Hand-counted table-row floors were wrong three times (63/60/87)** — Recovery: the registered-counter test printed the real count. **Prevention:**
   take the floor from a green run, never from arithmetic.
7. **A background task notification reported exit 0 for a multi-suite vitest run that had a failure** — Recovery: read the log summary, not the
   notification. **Prevention:** already covered by the existing "read the rc / log, not the notification" rule.

## Tags
category: logic-errors
module: apps/web-platform/server/untrusted-content
