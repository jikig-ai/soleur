---
title: A fix round closes the instance the reviewer named and leaves its sibling arms
date: 2026-11-09
category: workflow-patterns
module: ship Phase 7 required-set read (PR #12476, issue #11544, Ref #9927)
tags: [review, fix-round, mutation-testing, guard-vacuity, sanitiser, body-budget]
---

# Learning: a fix round closes the instance the reviewer named and leaves its sibling arms

## Problem

PR #12476 added an inline required-set read to the `soleur:ship` Phase 7 poll (and the
`soleur:merge-pr` 5.2 mirror), dispatched to a new `required-set-report.sh`. The 8-seat panel
returned 30 deduplicated findings, none a design fork. Two targeted fix rounds and three
verification seats followed. Every round after the first found the SAME shape again:

1. The panel said "RECOVERY lines are allowlisted by prefix only". The fix closed the one arm
   the seat named (`basis=workflow`). The next round found the three `pointer` arms still prefix-only,
   and three mutants that loosened them stayed green. The round after that found the `pending=`
   arm and the array pattern unpinned, and two `==` comparisons that a prefix match could replace.
2. The panel said "the shared sanitiser is single-pass". The fix routed the stderr tail through
   it. The next round showed a nested NEL/LS/PS sequence re-forms after one `sed` pass, on stdout
   `wf=` and on stderr, so the guard was still only true for single-level input.
3. A test fixture built a mock with a `<<` here-document opener INSIDE a double-quoted string.
   `scripts/guard-vacuity-floor.test.sh` scans lines for heredoc spans, never saw the terminator,
   and blanked the rest of the file, including the suite's own anti-vacuity floor line. The suite
   stayed green with its floor disarmed; only the repo-global guard noticed.
4. `plugins/soleur/skills/ship/SKILL.md` had 18 bytes of headroom under its body-budget ceiling.
   Any added sentence failed `lint-skill-body-budget.py`. Prose moved to `references/` kept
   positional words ("above", "below", "the Trigger line") whose referents no longer existed.

## Solution

- For a predicate with several arms, write the ARM x LOOSENING table first (one row per arm,
  one loosened mutant per row) and add a negative row per cell. S15b in
  `required-set-report.test.sh` is one count assertion, so it cannot name the failing row; the
  count changing is the pin. Tie a hand-copied grammar to its source with a drift row that
  strips comments, counts emitters, and instantiates each one.
- Sanitise to a fixpoint (bounded passes, then drop the lead bytes) instead of one pass, and
  run the loop under `LC_ALL=C`: in a UTF-8 locale a 240 KB pathological input took 32.5 s
  against 2.4 s.
- Build mock bodies with `printf %q` (a single-line knob), never a here-document inside a
  quoted string.
- When moving prose to a reference, rewrite every positional word to a named section and say in
  the header what was edited; "verbatim" is only true after a word-diff.

## Key Insight

A reviewer names an INSTANCE; the defect is a CLASS. A fix that is verified only against the
named instance leaves siblings, and each verification round re-finds the next sibling. Before
sending a fix agent, list every sibling arm of the predicate, every other consumer of the same
input, and every surface the guarantee is stated for, and brief the agent to cover the whole
table. A passing suite after a fix is evidence about the rows that exist, not about the arms
that do not.

## Session Errors

1. **Scope-out issue refused by the filing gate** (the monitor-dedupe follow-up was inside the
   inline threshold). Recovery: CTO re-ruled to document the deferral in the plan's Deferred
   section and file no issue; noted in the PR body. **Prevention:** run the cost-of-filing check
   before drafting a scope-out issue; a follow-up under the inline threshold belongs in the plan.
2. **Plan counted plain BLOCKED ticks as the read trigger**, which could print a false `absent`
   while checks were still running. Found by plan review; CTO re-ruled to a green dwell (10
   consecutive gate-holding ticks). **Prevention:** a trigger that reads an absence needs a
   positive-state precondition named in the plan; plan-review must ask "what makes this
   absence true for the wrong reason".
3. **`ci-head-verdict.test.sh` stopped with no summary line under load** (load average 34-57);
   the rerun was green. Later `monitor-pr-checks.test.sh` and the fixture suite hit a 280 s
   timeout (rc=124) under load. **Prevention:** a missing summary line or rc=124 is UNRESOLVED,
   never a pass or a fail; rerun with a longer `timeout` before drawing any conclusion.
4. **`lint-skill-body-budget.py` failed: `ship/SKILL.md` had 18 bytes of headroom.** Recovery:
   moved the ADR paragraph and Monitor-hygiene prose to references. **Prevention:** measure the
   byte headroom of every SKILL.md the plan edits at plan time and budget the offset in the plan.
5. **`plugin-root-anchoring.test.ts` flagged a new cwd-relative script anchor** in the moved
   prose. Recovery: name the script by file, not by a literal `bash scripts/...` anchor.
   **Prevention:** run the two repo-global guards (`context-sanitize`, `plugin-root-anchoring`)
   directly before the first push; the file-selected affected gate cannot see them.
6. **`guard-vacuity-floor.test.sh` failed on the PR** because of a heredoc opener inside a
   double-quoted string in the fixture (see Problem 3). Found in the fix round, not before the
   first push. **Prevention:** run `scripts/guard-vacuity-floor.test.sh` whenever a suite gains
   mock builders or a floor, and build mock bodies with `printf %q`.
7. **Moved prose kept dangling positional referents and a "verbatim" header** (D2, reported by
   five seats). **Prevention:** after moving prose, grep the destination for above/below/"the
   Trigger line" and word-diff against the source before claiming "verbatim".
8. **Fix-round tally double-incremented `fix_rounds`** (the ledger had already counted the
   round). Cosmetic; **Prevention:** `show` the tally before an `incr`.
9. **A verification seat ran the real resolver once** because it omitted the stub seam on one
   command (a read-only `gh` lookup of a non-existent PR). **Prevention:** brief seats to set
   `CI_HEAD_VERDICT_BIN` on every invocation of the script under test.
10. **The unkept-promise stop hook fired twice** on closing lines that named a next action.
    Recovery: end each legitimate wait with a `Paused:` sentence naming the one pending event.
    **Prevention:** none needed beyond the hook's own instruction.

## Tags

category: workflow-patterns
module: ship-phase-7-required-set
